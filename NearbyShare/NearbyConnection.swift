//
//  NearbyConnection.swift
//  Nearby Drop — Created by Arslan Basharat
//
//

import Foundation
import Network
import CommonCrypto
import CryptoKit
import System

import SwiftECC
import BigInt

class NearbyConnection{
	internal static let SANE_FRAME_LENGTH=5*1024*1024
	internal static let connectionQueue=DispatchQueue(label: "com.arslanbasharat.NearByDrop.queue", qos: .userInitiated) // High priority FIFO queue for high-throughput transfers
	
	internal let connection:NWConnection
	internal var remoteDeviceInfo:RemoteDeviceInfo?
	private var payloadBuffers:[Int64:NSMutableData]=[:]
	private var payloadSizes:[Int64:Int64]=[:]
	private var bufferedPayloadBytes:Int64=0
	internal var encryptionDone:Bool=false
	internal var transferredFiles:[Int64:InternalFileInfo]=[:]
	public let id:String
	internal var lastError:Error?
	private var connectionClosed:Bool=false
	private var closureHandled:Bool=false
	private var keepAliveTimer:DispatchSourceTimer?
	
	// UKEY2-related state
	internal var publicKey:ECPublicKey?
	internal var privateKey:ECPrivateKey?
	internal var ukeyClientInitMsgData:Data?
	internal var ukeyServerInitMsgData:Data?
	
	// SecureMessage encryption keys
	internal var decryptKey:[UInt8]?
	internal var encryptKey:[UInt8]?
	internal var recvHmacKey:SymmetricKey?
	internal var sendHmacKey:SymmetricKey?
	
	// SecureMessage sequence numbers
	private var serverSeq:Int32=0
	private var clientSeq:Int32=0
	
	private(set) var pinCode:String?
	private(set) var authKey:SymmetricKey?
	
	init(connection:NWConnection, id:String) {
		self.connection=connection
		self.id=id
	}
	
	func start(){
		connection.stateUpdateHandler={ [weak self] state in
            guard let self=self else { return }
			if case .ready = state {
				self.connectionReady()
				self.receiveStreamAsync()
			} else if case .failed(let err) = state {
				self.lastError=err
				print("Error opening socket: \(err)")
				self.handleConnectionClosure()
			} else if case .cancelled = state {
				self.handleConnectionClosure()
			}
		}
		connection.start(queue: NearbyConnection.connectionQueue)
	}
	
	func connectionReady(){}
	
	internal func handleConnectionClosure(){
		guard !closureHandled else { return }
		closureHandled=true
		connectionClosed=true
		payloadBuffers.removeAll()
		payloadSizes.removeAll()
		bufferedPayloadBytes=0
		streamBuffer.removeAll()
		stopKeepAliveTimer()
        connection.stateUpdateHandler=nil
        connection.cancel()
		print("Connection closed")
	}
	
	internal func protocolError(){
		disconnect()
	}
	
	internal func processReceivedFrame(frameData:Data){
		lastError=NearbyError.protocolError("Received frame on an unsupported connection")
		protocolError()
	}
	
	internal func processTransferSetupFrame(_ frame:Sharing_Nearby_Frame) throws{
		throw NearbyError.protocolError("Received transfer setup on an unsupported connection")
	}
	
	internal func isServer() -> Bool{
		return false
	}
	
	internal func processFileChunk(frame:Location_Nearby_Connections_PayloadTransferFrame) throws{
		protocolError()
	}
	
	internal func processBytesPayload(payload:Data, id:Int64)throws ->Bool{
		return false
	}

	internal static func frameLength(from header:Data) -> Int? {
		guard header.count == 4 else { return nil }
		let length=UInt32(header[0]) << 24 | UInt32(header[1]) << 16 | UInt32(header[2]) << 8 | UInt32(header[3])
		guard length > 0, length <= UInt32(SANE_FRAME_LENGTH) else { return nil }
		return Int(length)
	}

    internal static func isPayloadControl(_ frame: Location_Nearby_Connections_PayloadTransferFrame) throws -> Bool {
        switch frame.packetType {
        case .payloadAck: return true
        case .control:
            guard frame.hasControlMessage, frame.controlMessage.hasEvent else {
                throw NearbyError.requiredFieldMissing("payloadTransfer.controlMessage.event")
            }
            switch frame.controlMessage.event {
            case .payloadReceivedAck: return true
            case .payloadCanceled: throw NearbyError.canceled(reason: .userCanceled)
            case .payloadError: throw NearbyError.protocolError("The receiving device could not receive the payload.")
            default: throw NearbyError.protocolError("Unknown payload control event")
            }
        case .data: return false
        default: throw NearbyError.protocolError("Unknown payload packet type")
        }
    }

    internal func processPayloadAcknowledgement(id: Int64) {}
    internal func remoteSafeDisconnectionAcknowledged() {}

    internal func acknowledgePayload(_ header: Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader) throws {
        var frame = Location_Nearby_Connections_OfflineFrame()
        frame.version = .v1
        frame.v1.type = .payloadTransfer
        frame.v1.payloadTransfer.packetType = .payloadAck
        frame.v1.payloadTransfer.payloadHeader = header
        try encryptAndSendOfflineFrame(frame)
    }

	internal static func isValidPayloadRange(totalSize:Int64, offset:Int64, bodyCount:Int) -> Bool {
		guard totalSize >= 0, offset >= 0, bodyCount >= 0, offset <= totalSize else { return false }
		return Int64(bodyCount) <= totalSize - offset
	}

	private func discardBufferedPayload(_ id:Int64){
		if let buffer=payloadBuffers.removeValue(forKey: id) {
			bufferedPayloadBytes=max(0, bufferedPayloadBytes-Int64(buffer.count))
		}
		payloadSizes.removeValue(forKey: id)
	}

	private var streamBuffer = Data()

	private func receiveStreamAsync(){
		connection.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] content, _, isComplete, error in
			guard let self=self else { return }
			if self.connectionClosed{
				return
			}
			if let error=error{
				self.lastError=error
				self.protocolError()
				return
			}
			if let content=content, !content.isEmpty{
				self.streamBuffer.append(content)
				self.drainStreamBuffer()
			}
			if isComplete {
				self.handleConnectionClosure()
			} else {
				self.receiveStreamAsync()
			}
		}
	}

	private func drainStreamBuffer(){
		while !connectionClosed && streamBuffer.count >= 4 {
			guard let frameLength=NearbyConnection.frameLength(from: Data(streamBuffer.prefix(4))) else {
				lastError=NearbyError.protocolError("Unexpected packet length")
				protocolError()
				return
			}
			let totalNeeded=4+frameLength
			if streamBuffer.count < totalNeeded {
				break
			}
			let frameData=streamBuffer.subdata(in: 4..<totalNeeded)
			streamBuffer.removeSubrange(0..<totalNeeded)
			processReceivedFrame(frameData: frameData)
		}
	}
	
	internal func sendFrameAsync(_ frame:Data, completion:(()->Void)?=nil, failure:((Error)->Void)?=nil){
		if connectionClosed{
			failure?(NearbyError.protocolError("Connection is closed"))
			return
		}
		guard !frame.isEmpty, frame.count <= NearbyConnection.SANE_FRAME_LENGTH else {
			let error=NearbyError.protocolError("Unexpected packet length")
			lastError=error
			if let failure=failure { failure(error) } else { protocolError() }
			return
		}
		var lengthPrefixedData=Data(capacity: frame.count+4)
		let length:Int=frame.count
		lengthPrefixedData.append(contentsOf: [
			UInt8(truncatingIfNeeded: length >> 24),
			UInt8(truncatingIfNeeded: length >> 16),
			UInt8(truncatingIfNeeded: length >> 8),
			UInt8(truncatingIfNeeded: length)
		])
		lengthPrefixedData.append(frame)
		connection.send(content: lengthPrefixedData, completion: .contentProcessed({ [weak self] error in
			guard let self=self else { return }
			if let error=error{
				self.lastError=error
				if let failure=failure {
					failure(error)
				}else{
					self.protocolError()
				}
			}else if let completion=completion{
				completion()
			}
		}))
	}
	
	internal func encryptAndSendOfflineFrame(_ frame:Location_Nearby_Connections_OfflineFrame, completion:(()->Void)?=nil, failure:((Error)->Void)?=nil) throws{
		guard let encryptKey=encryptKey, let sendHmacKey=sendHmacKey else { throw NearbyError.protocolError("Encryption is not ready") }
		var d2dMsg=Securegcm_DeviceToDeviceMessage()
		serverSeq+=1
		d2dMsg.sequenceNumber=serverSeq
		d2dMsg.message=try frame.serializedData()
		
		let serializedMsg=try d2dMsg.serializedData()
		let iv=try Data.randomData(length: 16)
		var encryptedData=Data(count: serializedMsg.count+16)
		var encryptedLength:size_t=0
		var encryptionStatus=CCCryptorStatus(kCCSuccess)
		iv.withUnsafeBytes { ivBytes in
			serializedMsg.withUnsafeBytes { msgBytes in
				encryptedData.withUnsafeMutableBytes { outBytes in
						encryptionStatus=CCCrypt(
						CCOperation(kCCEncrypt),
						CCAlgorithm(kCCAlgorithmAES128),
						CCOptions(kCCOptionPKCS7Padding),
							encryptKey, kCCKeySizeAES256,
						ivBytes.baseAddress,
						msgBytes.baseAddress, serializedMsg.count,
						outBytes.baseAddress, outBytes.count,
						&encryptedLength
					)
				}
			}
		}
		guard encryptionStatus==CCCryptorStatus(kCCSuccess) else { throw NearbyError.protocolError("CCCrypt error: \(encryptionStatus)") }
		
		var hb=Securemessage_HeaderAndBody()
		hb.body=encryptedData.prefix(encryptedLength)
		hb.header=Securemessage_Header()
		hb.header.encryptionScheme = .aes256Cbc
		hb.header.signatureScheme = .hmacSha256
		hb.header.iv=iv
		var md=Securegcm_GcmMetadata()
		md.type = .deviceToDeviceMessage
		md.version=1
		hb.header.publicMetadata=try md.serializedData()
		
		var smsg=Securemessage_SecureMessage()
		smsg.headerAndBody=try hb.serializedData()
		smsg.signature=Data(HMAC<SHA256>.authenticationCode(for: smsg.headerAndBody, using: sendHmacKey))
		sendFrameAsync(try smsg.serializedData(), completion: completion, failure: failure)
	}
	
	internal func sendTransferSetupFrame(_ frame:Sharing_Nearby_Frame, completion:(()->Void)?=nil, failure:((Error)->Void)?=nil) throws{
		try sendBytesPayload(data: try frame.serializedData(), id: Int64.random(in: Int64.min...Int64.max), completion: completion, failure: failure)
	}
	
	internal func sendBytesPayload(data:Data, id:Int64, completion:(()->Void)?=nil, failure:((Error)->Void)?=nil) throws{
		guard data.count <= NearbyConnection.SANE_FRAME_LENGTH else { throw NearbyError.protocolError("Payload too large (\(data.count) bytes)") }
		var transfer=Location_Nearby_Connections_PayloadTransferFrame()
		transfer.packetType = .data
		transfer.payloadChunk.offset=0
		transfer.payloadChunk.flags=0
		transfer.payloadChunk.body=data
		transfer.payloadHeader.id=id
		transfer.payloadHeader.type = .bytes
		transfer.payloadHeader.totalSize=Int64(transfer.payloadChunk.body.count)
		transfer.payloadHeader.isSensitive=false
		
		var wrapper=Location_Nearby_Connections_OfflineFrame()
		wrapper.version = .v1
		wrapper.v1=Location_Nearby_Connections_V1Frame()
		wrapper.v1.type = .payloadTransfer
		wrapper.v1.payloadTransfer=transfer
		try encryptAndSendOfflineFrame(wrapper, completion: { [weak self] in
			guard let self=self else { return }
			var lastTransfer=transfer
			lastTransfer.payloadChunk.flags=1 // .lastChunk
			lastTransfer.payloadChunk.offset=Int64(lastTransfer.payloadChunk.body.count)
			lastTransfer.payloadChunk.clearBody()
			var lastWrapper=Location_Nearby_Connections_OfflineFrame()
			lastWrapper.version = .v1
			lastWrapper.v1=Location_Nearby_Connections_V1Frame()
			lastWrapper.v1.type = .payloadTransfer
			lastWrapper.v1.payloadTransfer=lastTransfer
			do {
				try self.encryptAndSendOfflineFrame(lastWrapper, completion: completion, failure: failure)
			}catch{
				self.lastError=error
				failure?(error)
			}
		}, failure: failure)
	}
	
	internal func decryptAndProcessReceivedSecureMessage(_ smsg:Securemessage_SecureMessage) throws{
		guard smsg.hasSignature, smsg.hasHeaderAndBody else { throw NearbyError.requiredFieldMissing("secureMessage.signature|headerAndBody") }
		guard let recvHmacKey=recvHmacKey, let decryptKey=decryptKey else { throw NearbyError.protocolError("Encryption is not ready") }
		let hmac=Data(HMAC<SHA256>.authenticationCode(for: smsg.headerAndBody, using: recvHmacKey))
		guard hmac==smsg.signature else { throw NearbyError.protocolError("hmac!=signature") }
		let headerAndBody=try Securemessage_HeaderAndBody(serializedData: smsg.headerAndBody)
		guard headerAndBody.hasHeader, headerAndBody.hasBody,
			  headerAndBody.header.hasEncryptionScheme, headerAndBody.header.encryptionScheme == .aes256Cbc,
			  headerAndBody.header.hasSignatureScheme, headerAndBody.header.signatureScheme == .hmacSha256,
			  headerAndBody.header.hasIv, headerAndBody.header.iv.count == kCCBlockSizeAES128,
			  !headerAndBody.body.isEmpty, headerAndBody.body.count % kCCBlockSizeAES128 == 0,
			  headerAndBody.body.count <= NearbyConnection.SANE_FRAME_LENGTH else {
			throw NearbyError.protocolError("Malformed encrypted payload")
		}
		var decryptedData=Data(count: headerAndBody.body.count)
		
		var decryptedLength:Int=0
		var decryptionStatus=CCCryptorStatus(kCCSuccess)
		let iv=headerAndBody.header.iv
		let body=headerAndBody.body
		iv.withUnsafeBytes { ivBytes in
			body.withUnsafeBytes { bodyBytes in
				decryptedData.withUnsafeMutableBytes { outBytes in
					decryptionStatus=CCCrypt(
						CCOperation(kCCDecrypt),
						CCAlgorithm(kCCAlgorithmAES128),
						CCOptions(kCCOptionPKCS7Padding),
						decryptKey, kCCKeySizeAES256,
						ivBytes.baseAddress,
						bodyBytes.baseAddress, body.count,
						outBytes.baseAddress, outBytes.count,
						&decryptedLength
					)
				}
			}
		}
		guard decryptionStatus==CCCryptorStatus(kCCSuccess) else { throw NearbyError.protocolError("CCCrypt error: \(decryptionStatus)") }
		decryptedData=decryptedData.prefix(decryptedLength)
		let d2dMsg=try Securegcm_DeviceToDeviceMessage(serializedData: decryptedData)
		guard d2dMsg.hasMessage, d2dMsg.hasSequenceNumber else { throw NearbyError.requiredFieldMissing("d2dMessage.message|sequenceNumber") }
		clientSeq+=1
		guard d2dMsg.sequenceNumber==clientSeq else { throw NearbyError.protocolError("Wrong sequence number. Expected \(clientSeq), got \(d2dMsg.sequenceNumber)") }
		let offlineFrame=try Location_Nearby_Connections_OfflineFrame(serializedData: d2dMsg.message)
		
		if offlineFrame.hasV1 && offlineFrame.v1.hasType, case .payloadTransfer = offlineFrame.v1.type {
			guard offlineFrame.v1.hasPayloadTransfer else { throw NearbyError.requiredFieldMissing("offlineFrame.v1.payloadTransfer") }
			let payloadTransfer=offlineFrame.v1.payloadTransfer
            if try Self.isPayloadControl(payloadTransfer) {
                guard payloadTransfer.payloadHeader.hasID else { throw NearbyError.requiredFieldMissing("payloadHeader.id") }
                processPayloadAcknowledgement(id: payloadTransfer.payloadHeader.id)
                return
            }
			let header=payloadTransfer.payloadHeader;
			let chunk=payloadTransfer.payloadChunk;
			guard header.hasType, header.hasID, header.hasTotalSize else { throw NearbyError.requiredFieldMissing("payloadHeader.type|id|totalSize") }
			guard payloadTransfer.hasPayloadChunk, chunk.hasOffset, chunk.hasFlags else { throw NearbyError.requiredFieldMissing("payloadTransfer.payloadChunk|offset|flags") }
			guard chunk.flags == 0 || chunk.flags == 1 else { throw NearbyError.protocolError("Unknown payload chunk flags") }
			guard header.totalSize >= 0, chunk.offset >= 0 else { throw NearbyError.protocolError("Negative payload size or offset") }
			if case .bytes = header.type{
				let payloadID=header.id
				guard header.totalSize <= Int64(NearbyConnection.SANE_FRAME_LENGTH) else {
					self.discardBufferedPayload(payloadID)
					throw NearbyError.protocolError("Payload too large (\(header.totalSize) bytes)")
				}
				guard NearbyConnection.isValidPayloadRange(totalSize: header.totalSize, offset: chunk.offset, bodyCount: chunk.hasBody ? chunk.body.count : 0) else {
					self.discardBufferedPayload(payloadID)
					throw NearbyError.protocolError("Invalid byte payload range")
				}
				if payloadBuffers[payloadID]==nil {
					guard payloadBuffers.count < 16,
						  bufferedPayloadBytes <= Int64(NearbyConnection.SANE_FRAME_LENGTH) - header.totalSize else {
						throw NearbyError.protocolError("Too many buffered payloads")
					}
					payloadSizes[payloadID]=header.totalSize
					payloadBuffers[payloadID]=NSMutableData(capacity: Int(header.totalSize))
				}
				guard payloadSizes[payloadID] == header.totalSize else {
					self.discardBufferedPayload(payloadID)
					throw NearbyError.protocolError("Payload size changed mid-transfer")
				}
				let buffer=payloadBuffers[payloadID]!
				guard chunk.offset==buffer.count else {
					self.discardBufferedPayload(payloadID)
					throw NearbyError.protocolError("Unexpected chunk offset \(chunk.offset), expected \(buffer.count)")
				}
				if chunk.hasBody {
					buffer.append(chunk.body)
					bufferedPayloadBytes+=Int64(chunk.body.count)
				}
				if (chunk.flags & 1)==1 {
					guard Int64(buffer.count) == header.totalSize else {
						self.discardBufferedPayload(payloadID)
						throw NearbyError.protocolError("Byte payload ended before the advertised byte count")
					}
					payloadBuffers.removeValue(forKey: payloadID)
					payloadSizes.removeValue(forKey: payloadID)
					bufferedPayloadBytes-=Int64(buffer.count)
					if !(try processBytesPayload(payload: Data(buffer), id: payloadID)){
						let innerFrame=try Sharing_Nearby_Frame(serializedData: buffer as Data)
						try processTransferSetupFrame(innerFrame)
					}
				}
			}else if case .file = header.type{
				guard chunk.hasBody || chunk.flags == 1 else { throw NearbyError.protocolError("Empty file payload chunk") }
				try processFileChunk(frame: payloadTransfer)
			}else{
				throw NearbyError.protocolError("Unsupported payload type")
			}
        }else if offlineFrame.hasV1 && offlineFrame.v1.type == .disconnection {
            if offlineFrame.v1.disconnection.requestSafeToDisconnect {
                var acknowledgement = Location_Nearby_Connections_OfflineFrame()
                acknowledgement.version = .v1
                acknowledgement.v1.type = .disconnection
                acknowledgement.v1.disconnection.ackSafeToDisconnect = true
                try encryptAndSendOfflineFrame(acknowledgement, completion: { [weak self] in
                    self?.remoteSafeDisconnectionAcknowledged()
                    self?.disconnect()
                })
            }
		}else if offlineFrame.hasV1 && offlineFrame.v1.hasType, case .keepAlive = offlineFrame.v1.type{
#if DEBUG
			print("Sent keep-alive")
#endif
			if !offlineFrame.v1.keepAlive.ack {
				sendKeepAlive(ack: true)
			}
		}else{
				print("Unhandled offline frame type: \(offlineFrame.v1.hasType ? String(describing: offlineFrame.v1.type) : "missing")")
		}
	}
	
	internal static func pinCodeFromAuthKey(_ key:SymmetricKey) -> String{
		var hash:Int=0
		var multiplier:Int=1
		let keyBytes:[UInt8]=key.withUnsafeBytes({
			return [UInt8]($0)
		})
		
		for _byte in keyBytes {
			let byte=Int(Int8(bitPattern: _byte))
			hash=(hash+byte*multiplier)%9973
			multiplier=(multiplier*31)%9973
		}
		
		return String(format: "%04d", abs(hash))
	}
	
	public static func fixedCoordinate32Bytes(_ bint: BInt) -> Data {
		let raw = Data(bint.asMagnitudeBytes())
		if raw.count == 32 { return raw }
		if raw.count > 32 { return raw.suffix(32) }
		return Data(repeating: 0, count: 32 - raw.count) + raw
	}
	
	internal static func hkdfExtract(salt:Data, ikm:Data) -> Data{
		return HMAC<SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: salt)).withUnsafeBytes({return Data(bytes: $0.baseAddress!, count: $0.count)})
	}
	
	internal static func hkdfExpand(prk:Data, info:Data, length:Int) -> Data{
		var okm=Data()
		var t=Data()
		var i=0
		while okm.count<length{
			i=i+1
			let toDigest=t+info+Data([UInt8(truncatingIfNeeded: i)])
			t=HMAC<SHA256>.authenticationCode(for: toDigest, using: SymmetricKey(data: prk)).withUnsafeBytes({return Data(bytes: $0.baseAddress!, count: $0.count)})
			okm=okm+t
		}
		return okm.subdata(in: 0..<length)
	}
	
	internal static func hkdf(inputKeyMaterial:SymmetricKey, salt:Data, info:Data, outputByteCount:Int) -> SymmetricKey{
		if #available(macOS 11.0, *){
			return HKDF<SHA256>.deriveKey(inputKeyMaterial: inputKeyMaterial, salt: salt, info: info, outputByteCount: outputByteCount)
		}else{
			return SymmetricKey(data: hkdfExpand(prk: hkdfExtract(salt: salt, ikm: inputKeyMaterial.data()), info: info, length: outputByteCount))
		}
	}
	
	internal func finalizeKeyExchange(peerKey:Securemessage_GenericPublicKey) throws{
		guard peerKey.hasEcP256PublicKey else { throw NearbyError.requiredFieldMissing("peerKey.ecP256PublicKey") }
		
		let domain=Domain.instance(curve: .EC256r1)
		var clientX=peerKey.ecP256PublicKey.x
		var clientY=peerKey.ecP256PublicKey.y
		if clientX.count>32{
			clientX=clientX.suffix(32)
		}
		if clientY.count>32{
			clientY=clientY.suffix(32)
		}
		let key=try ECPublicKey(domain: domain, w: Point(BInt(magnitude: [UInt8](clientX)), BInt(magnitude: [UInt8](clientY))))
		
		guard let privateKey=privateKey else { throw NearbyError.protocolError("Missing local key") }
		let dhs=NearbyConnection.fixedCoordinate32Bytes(try privateKey.domain.multiplyPoint(key.w, privateKey.s).x)
		var sha=SHA256()
		sha.update(data: dhs)
		let derivedSecretKey=Data(sha.finalize())
		
		var ukeyInfo=Data()
		guard let ukeyClientInitMsgData=ukeyClientInitMsgData, let ukeyServerInitMsgData=ukeyServerInitMsgData else {
			throw NearbyError.protocolError("Missing UKEY2 transcript")
		}
		ukeyInfo.append(ukeyClientInitMsgData)
		ukeyInfo.append(ukeyServerInitMsgData)
		let authString=NearbyConnection.hkdf(inputKeyMaterial: SymmetricKey(data: derivedSecretKey), salt: "UKEY2 v1 auth".data(using: .utf8)!, info: ukeyInfo, outputByteCount: 32)
		let nextSecret=NearbyConnection.hkdf(inputKeyMaterial: SymmetricKey(data: derivedSecretKey), salt: "UKEY2 v1 next".data(using: .utf8)!, info: ukeyInfo, outputByteCount: 32)
		
		authKey=authString
		pinCode=NearbyConnection.pinCodeFromAuthKey(authString)
		
		let salt:Data=Data([0x82, 0xAA, 0x55, 0xA0, 0xD3, 0x97, 0xF8, 0x83, 0x46, 0xCA, 0x1C,
							0xEE, 0x8D, 0x39, 0x09, 0xB9, 0x5F, 0x13, 0xFA, 0x7D, 0xEB, 0x1D,
							0x4A, 0xB3, 0x83, 0x76, 0xB8, 0x25, 0x6D, 0xA8, 0x55, 0x10])
		
		let d2dClientKey=NearbyConnection.hkdf(inputKeyMaterial: nextSecret, salt: salt, info: "client".data(using: .utf8)!, outputByteCount: 32)
		let d2dServerKey=NearbyConnection.hkdf(inputKeyMaterial: nextSecret, salt: salt, info: "server".data(using: .utf8)!, outputByteCount: 32)
		
		sha=SHA256()
		sha.update(data: "SecureMessage".data(using: .utf8)!)
		let smsgSalt=Data(sha.finalize())
		
		let clientKey=NearbyConnection.hkdf(inputKeyMaterial: d2dClientKey, salt: smsgSalt, info: "ENC:2".data(using: .utf8)!, outputByteCount: 32).withUnsafeBytes({return [UInt8]($0)})
		let clientHmacKey=NearbyConnection.hkdf(inputKeyMaterial: d2dClientKey, salt: smsgSalt, info: "SIG:1".data(using: .utf8)!, outputByteCount: 32)
		let serverKey=NearbyConnection.hkdf(inputKeyMaterial: d2dServerKey, salt: smsgSalt, info: "ENC:2".data(using: .utf8)!, outputByteCount: 32).withUnsafeBytes({return [UInt8]($0)})
		let serverHmacKey=NearbyConnection.hkdf(inputKeyMaterial: d2dServerKey, salt: smsgSalt, info: "SIG:1".data(using: .utf8)!, outputByteCount: 32)
		
		if isServer(){
			decryptKey=clientKey
			recvHmacKey=clientHmacKey
			encryptKey=serverKey
			sendHmacKey=serverHmacKey
		}else{
			decryptKey=serverKey
			recvHmacKey=serverHmacKey
			encryptKey=clientKey
			sendHmacKey=clientHmacKey
		}
	}
	
	internal func disconnect(){
		if connectionClosed{
			return
		}
		connectionClosed=true
		stopKeepAliveTimer()
        guard connection.state == .ready else {
            handleConnectionClosure()
            return
        }
		connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ [weak self] error in
			guard let self=self else { return }
			if let error=error { self.lastError=error }
			self.handleConnectionClosure()
		}))
	}
	
	internal func sendDisconnectionAndDisconnect(completion:(()->Void)?=nil) throws{
		var offlineFrame=Location_Nearby_Connections_OfflineFrame()
		offlineFrame.version = .v1
		offlineFrame.v1.type = .disconnection
		offlineFrame.v1.disconnection=Location_Nearby_Connections_DisconnectionFrame()
		
		let serialized=try offlineFrame.serializedData()
		let finish: () -> Void = { [weak self] in
			completion?()
			self?.disconnect()
		}
		let fail: (Error) -> Void = { [weak self] (error:Error) in
			self?.lastError=error
			self?.disconnect()
		}
		if encryptionDone{
			try encryptAndSendOfflineFrame(offlineFrame, completion: finish, failure: fail)
		}else{
			sendFrameAsync(serialized, completion: finish, failure: fail)
		}
	}

	internal func sendUkey2Alert(type:Securegcm_Ukey2Alert.AlertType){
		var alert=Securegcm_Ukey2Alert()
		alert.type=type
		var msg=Securegcm_Ukey2Message()
		msg.messageType = .alert
		do {
			msg.messageData = try alert.serializedData()
			sendFrameAsync(try msg.serializedData(), completion: { [weak self] in self?.disconnect() }, failure: { [weak self] error in
				self?.lastError=error
				self?.disconnect()
			})
		}catch{
			lastError=error
			disconnect()
		}
	}
	
	internal func sendKeepAlive(ack:Bool){
		var offlineFrame=Location_Nearby_Connections_OfflineFrame()
		offlineFrame.version = .v1
		offlineFrame.v1.type = .keepAlive
		offlineFrame.v1.keepAlive.ack=ack
		
		do{
			if encryptionDone{
				try encryptAndSendOfflineFrame(offlineFrame)
			}else{
				sendFrameAsync(try offlineFrame.serializedData())
			}
		}catch{
			print("Error sending KEEP_ALIVE: \(error)")
		}
	}

	internal func startKeepAliveTimer(){
		guard encryptionDone, !connectionClosed, keepAliveTimer==nil else { return }
		let timer=DispatchSource.makeTimerSource(queue: NearbyConnection.connectionQueue)
		timer.schedule(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(10), repeating: DispatchTimeInterval.seconds(10))
		timer.setEventHandler { [weak self] in
			guard let self=self, self.encryptionDone, !self.connectionClosed else { return }
			self.sendKeepAlive(ack: false)
		}
		keepAliveTimer=timer
		timer.resume()
	}

	private func stopKeepAliveTimer(){
		keepAliveTimer?.cancel()
		keepAliveTimer=nil
	}
}

struct InternalFileInfo{
	let meta:FileMetadata
	let payloadID:Int64
	let destinationURL:URL
	var bytesTransferred:Int64=0
	var fd:Int32 = -1
	var created:Bool=false
}
