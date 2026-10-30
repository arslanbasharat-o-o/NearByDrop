//
//  OutboundNearbyConnection.swift
//  NearbyShare
//
//

import Foundation
import os
import Network
import CryptoKit
import CommonCrypto
import System
import UniformTypeIdentifiers

import SwiftECC
import BigInt

class OutboundNearbyConnection:NearbyConnection{
	private static let logger = Logger(subsystem: "com.arslanbasharat.NearByDrop", category: "OutgoingTransfer")
    private var currentState:State = .initial {
        didSet { Self.logger.notice("Outgoing stage: \(String(describing: self.currentState), privacy: .public)") }
    }
	private let urlsToSend:[URL]
	// Names sent in the introduction; entries may contain "/" (relative paths when
	// the user selected directories). Falls back to the URL's last path component.
	private let displayNames:[String]?
	private var ukeyClientFinishMsgData:Data?
	private var queue:[OutgoingFileTransfer]=[]
	private var currentTransfer:OutgoingFileTransfer?
	public var delegate:OutboundNearbyConnectionDelegate?
	private var totalBytesToSend:Int64=0
	private var totalBytesSent:Int64=0
    private var lastProgressTime=DispatchTime.now()
	private var cancelled:Bool=false
	private var textPayloadID:Int64=0
	private var resultReported=false
	private var handlesClosed=false
    private var pendingAcknowledgements: Set<Int64> = []
    private var acknowledgementTimeout: DispatchWorkItem?
	
	public var qrCodePrivateKey:P256.Signing.PrivateKey?
	
	enum State{
		case initial, sentUkeyClientInit, sentUkeyClientFinish, sentPairedKeyEncryption, sentPairedKeyResult, sentIntroduction, sendingFiles, finishing, completed, failed, cancelled, disconnected
	}
	
	init(connection: NWConnection, id: String, urlsToSend:[URL], displayNames:[String]?=nil){
		self.urlsToSend=urlsToSend
		self.displayNames=displayNames
		super.init(connection: connection, id: id)
		if urlsToSend.count==1 && !urlsToSend[0].isFileURL{
			textPayloadID=Int64.random(in: Int64.min...Int64.max)
		}
	}
	
	deinit {
		closeAllTransferHandles()
	}
	
	public func cancel(){
		NearbyConnection.connectionQueue.async { [weak self] in
			guard let self=self, !self.resultReported else { return }
			self.cancelled=true
			self.currentState = .cancelled
			let error=NearbyError.canceled(reason: .userCanceled)
			self.lastError=error
			self.reportFailure(error)
			if self.encryptionDone{
				var cancel=Sharing_Nearby_Frame()
				cancel.version = .v1
				cancel.v1=Sharing_Nearby_V1Frame()
				cancel.v1.type = .cancel
				do {
					try self.sendTransferSetupFrame(cancel, completion: {
						do { try self.sendDisconnectionAndDisconnect() } catch {
							self.lastError=error
							self.disconnect()
						}
					}, failure: { error in
						self.lastError=error
						self.disconnect()
					})
				} catch {
					self.lastError=error
					self.disconnect()
				}
				return
			}
			do { try self.sendDisconnectionAndDisconnect() } catch {
				self.lastError=error
				self.disconnect()
			}
		}
	}
	
	override func connectionReady() {
		super.connectionReady()
		do{
			try sendConnectionRequest()
			try sendUkey2ClientInit()
		}catch{
			lastError=error
			protocolError()
		}
	}
	
	override func isServer() -> Bool {
		return false
	}
	
	override func processReceivedFrame(frameData: Data) {
		do{
			#if DEBUG
			print("received \(frameData), state is \(currentState)")
			#endif
			switch currentState {
			case .initial:
				protocolError()
			case .sentUkeyClientInit:
				try processUkey2ServerInit(frame: try Securegcm_Ukey2Message(serializedData: frameData), raw: frameData)
			case .sentUkeyClientFinish:
				try processConnectionResponse(frame: try Location_Nearby_Connections_OfflineFrame(serializedData: frameData))
			default:
				let smsg=try Securemessage_SecureMessage(serializedData: frameData)
				try decryptAndProcessReceivedSecureMessage(smsg)
			}
		}catch{
			if case NearbyError.ukey2=error{
			}else if currentState == .sentUkeyClientInit{
				sendUkey2Alert(type: .badMessage)
			}
			lastError=error
			protocolError()
		}
	}
	
	override func processTransferSetupFrame(_ frame: Sharing_Nearby_Frame) throws {
		if frame.hasV1 && frame.v1.hasType, case .cancel = frame.v1.type {
			print("Transfer canceled")
			currentState = .cancelled
			let error=NearbyError.canceled(reason: .userCanceled)
			lastError=error
			reportFailure(error)
			try sendDisconnectionAndDisconnect()
			return
		}
        Self.logger.notice("Received sharing frame: \(String(describing: frame.v1.type), privacy: .public), stage: \(String(describing: self.currentState), privacy: .public)")
        if (currentState == .sendingFiles || currentState == .finishing),
           frame.v1.type == .progressUpdate || frame.v1.type == .certificateInfo { return }
		switch currentState{
		case .sentPairedKeyEncryption:
			try processPairedKeyEncryption(frame: frame)
		case .sentPairedKeyResult:
			try processPairedKeyResult(frame: frame)
		case .sentIntroduction:
			try processConsent(frame: frame)
		case .sendingFiles:
			break
		default:
			throw NearbyError.protocolError("Unexpected \(frame.v1.type) frame while \(currentState)")
		}
	}
	
	override func handleConnectionClosure() {
		acknowledgementTimeout?.cancel()
		super.handleConnectionClosure()
		guard !resultReported || currentState == .finishing else { return }
		NSLog("[NearByDrop] Outbound connection closed in state: %@, lastError: %@", String(describing: currentState), String(describing: lastError))
		let filesWereAcknowledged = !urlsToSend.isEmpty && urlsToSend.allSatisfy(\.isFileURL) && pendingAcknowledgements.isEmpty
		// A peer reset after saving every file can race the final disconnect.
		if currentState == .finishing && (lastError == nil || filesWereAcknowledged) {
			currentState = .completed
			closeAllTransferHandles()
			guard !resultReported else { return }
			resultReported=true
			delegate?.outboundConnectionTransferFinished(connection: self)
			return
		}
		guard !resultReported else { return }
		let err = lastError ?? NearbyError.protocolError("Connection closed unexpectedly")
		lastError=err
		currentState = cancelled ? .cancelled : .failed
		closeAllTransferHandles()
		reportFailure(err)
	}

	override func protocolError() {
		NSLog("[NearByDrop] Outbound protocol error in state: %@, lastError: %@", String(describing: currentState), String(describing: lastError))
		let err = lastError ?? NearbyError.protocolError("Protocol error occurred")
		lastError=err
		currentState = cancelled ? .cancelled : .failed
		reportFailure(err)
		super.protocolError()
	}
	
	private func sendConnectionRequest() throws {
		let deviceName=NearbyConnectionManager.currentDeviceName
		var frame=Location_Nearby_Connections_OfflineFrame()
		frame.version = .v1
		frame.v1=Location_Nearby_Connections_V1Frame()
		frame.v1.type = .connectionRequest
		frame.v1.connectionRequest=Location_Nearby_Connections_ConnectionRequestFrame()
		frame.v1.connectionRequest.endpointID=String(bytes: NearbyConnectionManager.shared.endpointID, encoding: .ascii) ?? "ABCD"
		frame.v1.connectionRequest.endpointName=Data(deviceName.utf8)
		let endpointInfo=EndpointInfo(name: deviceName, deviceType: .computer)
		frame.v1.connectionRequest.endpointInfo=endpointInfo.serialize()
		frame.v1.connectionRequest.mediums=[.wifiLan]
		sendFrameAsync(try frame.serializedData())
	}
	
	private func sendUkey2ClientInit() throws {
		let domain=Domain.instance(curve: .EC256r1)
		let (pubKey, privKey)=domain.makeKeyPair()
		publicKey=pubKey
		privateKey=privKey
		
		var finishFrame=Securegcm_Ukey2Message()
		finishFrame.messageType = .clientFinish
		var finish=Securegcm_Ukey2ClientFinished()
		var pkey=Securemessage_GenericPublicKey()
		pkey.type = .ecP256
		pkey.ecP256PublicKey=Securemessage_EcP256PublicKey()
		// SecureMessage coordinates are signed integers; preserve the positive sign bit.
		pkey.ecP256PublicKey.x=Data(pubKey.w.x.asSignedBytes())
		pkey.ecP256PublicKey.y=Data(pubKey.w.y.asSignedBytes())
		finish.publicKey=try pkey.serializedData()
		finishFrame.messageData=try finish.serializedData()
		ukeyClientFinishMsgData=try finishFrame.serializedData()
		
		var frame=Securegcm_Ukey2Message()
		frame.messageType = .clientInit
		
		var clientInit=Securegcm_Ukey2ClientInit()
		clientInit.version=1
		clientInit.random=try Data.randomData(length: 32)
		clientInit.nextProtocol="AES_256_CBC-HMAC_SHA256"
		var sha=SHA512()
		sha.update(data: ukeyClientFinishMsgData!)
		var commitment=Securegcm_Ukey2ClientInit.CipherCommitment()
		commitment.commitment=Data(sha.finalize())
		commitment.handshakeCipher = .p256Sha512
		clientInit.cipherCommitments.append(commitment)
		frame.messageData=try clientInit.serializedData()
		
		ukeyClientInitMsgData=try frame.serializedData()
		sendFrameAsync(ukeyClientInitMsgData!)
		currentState = .sentUkeyClientInit
	}
	
	private func processUkey2ServerInit(frame:Securegcm_Ukey2Message, raw:Data) throws{
		ukeyServerInitMsgData=raw
		guard frame.messageType == .serverInit else{
			sendUkey2Alert(type: .badMessageType)
			throw NearbyError.ukey2
		}
		let serverInit=try Securegcm_Ukey2ServerInit(serializedData: frame.messageData)
		guard serverInit.version==1 else{
			sendUkey2Alert(type: .badVersion)
			throw NearbyError.ukey2
		}
		guard serverInit.random.count==32 else{
			sendUkey2Alert(type: .badRandom)
			throw NearbyError.ukey2
		}
		guard serverInit.handshakeCipher == .p256Sha512 else{
			sendUkey2Alert(type: .badHandshakeCipher)
			throw NearbyError.ukey2
		}
		
		let serverKey=try Securemessage_GenericPublicKey(serializedData: serverInit.publicKey)
		try finalizeKeyExchange(peerKey: serverKey)
		sendFrameAsync(ukeyClientFinishMsgData!)
		currentState = .sentUkeyClientFinish
		
		var resp=Location_Nearby_Connections_OfflineFrame()
		resp.version = .v1
		resp.v1=Location_Nearby_Connections_V1Frame()
		resp.v1.type = .connectionResponse
		resp.v1.connectionResponse=Location_Nearby_Connections_ConnectionResponseFrame()
		resp.v1.connectionResponse.response = .accept
		resp.v1.connectionResponse.status=0
            resp.v1.connectionResponse.safeToDisconnectVersion=6
		resp.v1.connectionResponse.osInfo=Location_Nearby_Connections_OsInfo()
		resp.v1.connectionResponse.osInfo.type = .apple
		sendFrameAsync(try resp.serializedData())
		
		encryptionDone=true
		startKeepAliveTimer()
		delegate?.outboundConnectionWasEstablished(connection: self)
	}
	
	private func processConnectionResponse(frame:Location_Nearby_Connections_OfflineFrame) throws{
		#if DEBUG
		print("connection response: \(frame)")
		#endif
		guard frame.version == .v1 else {throw NearbyError.protocolError("Unexpected offline frame version \(frame.version)")}
		guard frame.v1.type == .connectionResponse else {throw NearbyError.protocolError("Unexpected frame type \(frame.v1.type)")}
		guard frame.v1.connectionResponse.response == .accept else {throw NearbyError.protocolError("Connection was rejected by recipient")}
		
		var pairedEncryption=Sharing_Nearby_Frame()
		pairedEncryption.version = .v1
		pairedEncryption.v1=Sharing_Nearby_V1Frame()
		pairedEncryption.v1.type = .pairedKeyEncryption
		pairedEncryption.v1.pairedKeyEncryption=Sharing_Nearby_PairedKeyEncryptionFrame()
		pairedEncryption.v1.pairedKeyEncryption.secretIDHash=try Data.randomData(length: 6)
		pairedEncryption.v1.pairedKeyEncryption.signedData=try Data.randomData(length: 72)
		if let qrKey=qrCodePrivateKey{
			if let authKeyData=authKey?.data(), let signature = try? qrKey.signature(for: authKeyData) {
				pairedEncryption.v1.pairedKeyEncryption.qrCodeHandshakeData=signature.rawRepresentation
			}
		}
		try sendTransferSetupFrame(pairedEncryption)
		
		currentState = .sentPairedKeyEncryption
	}
	
	private func processPairedKeyEncryption(frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasPairedKeyEncryption else { throw NearbyError.requiredFieldMissing("sharingNearbyFrame.v1.pairedKeyEncryption") }
		var pairedResult=Sharing_Nearby_Frame()
		pairedResult.version = .v1
		pairedResult.v1=Sharing_Nearby_V1Frame()
		pairedResult.v1.type = .pairedKeyResult
		pairedResult.v1.pairedKeyResult=Sharing_Nearby_PairedKeyResultFrame()
		pairedResult.v1.pairedKeyResult.status = .unable
		try sendTransferSetupFrame(pairedResult)
		currentState = .sentPairedKeyResult
	}
	
	private func processPairedKeyResult(frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasPairedKeyResult else { throw NearbyError.requiredFieldMissing("sharingNearbyFrame.v1.pairedKeyResult") }
		
		var introduction=Sharing_Nearby_Frame()
		introduction.version = .v1
		introduction.v1.type = .introduction
        introduction.v1.introduction.startTransfer = true
        introduction.v1.introduction.useCase = .nearbyShare
		if urlsToSend.count==1 && !urlsToSend[0].isFileURL{
			var meta=Sharing_Nearby_TextMetadata()
			meta.type = .url
			meta.textTitle=urlsToSend[0].host ?? "URL"
			meta.size=Int64(urlsToSend[0].absoluteString.utf8.count)
			meta.payloadID=textPayloadID
			introduction.v1.introduction.textMetadata.append(meta)
		}else{
			for (index,url) in urlsToSend.enumerated(){
				guard url.isFileURL else {continue}
				var meta=Sharing_Nearby_FileMetadata()
                meta.id = Int64(index + 1)
				let displayName = displayNames != nil && displayNames!.count==urlsToSend.count ? displayNames![index] : url.lastPathComponent
				meta.name=OutboundNearbyConnection.sanitizeFileName(name: displayName)
				let attrs=try FileManager.default.attributesOfItem(atPath: url.path)
				guard let fileSize=attrs[FileAttributeKey.size] as? NSNumber else { throw NearbyError.inputOutput }
				meta.size=fileSize.int64Value
				let typeID=try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier
				meta.mimeType="application/octet-stream"
				if let typeID=typeID{
					if #available(macOS 11.0, *){
						let type=UTType(typeID)
						if let type=type, let mimeType=type.preferredMIMEType{
							meta.mimeType=mimeType
						}
					}else{
						if let mimeType=UTTypeCopyPreferredTagWithClass(typeID as CFString, kUTTagClassMIMEType){
							meta.mimeType=(mimeType.takeRetainedValue() as NSString) as String
						}
					}
				}
				if meta.mimeType.starts(with: "image/"){
					meta.type = .image
				}else if meta.mimeType.starts(with: "video/"){
					meta.type = .video
				}else if(meta.mimeType.starts(with: "audio/")){
					meta.type = .audio
				}else if(url.pathExtension.lowercased()=="apk"){
					meta.type = .androidApp
				}else{
					meta.type = .unknown
				}
				meta.payloadID=Int64.random(in: Int64.min...Int64.max)
                pendingAcknowledgements.insert(meta.payloadID)
				queue.append(OutgoingFileTransfer(url: url, payloadID: meta.payloadID, handle: try FileHandle(forReadingFrom: url), totalBytes: meta.size, currentOffset: 0))
				introduction.v1.introduction.fileMetadata.append(meta)
				totalBytesToSend+=meta.size
			}
		}
		#if DEBUG
		print("sent introduction: \(introduction)")
		#endif
		try sendTransferSetupFrame(introduction)
		
		currentState = .sentIntroduction
	}
	
	private func processConsent(frame:Sharing_Nearby_Frame) throws{
		guard frame.version == .v1, frame.v1.type == .response else {throw NearbyError.requiredFieldMissing("sharingNearbyFrame.v1.type==response")}
		switch frame.v1.connectionResponse.status{
		case .accept:
			currentState = .sendingFiles
			delegate?.outboundConnectionTransferAccepted(connection: self)
			if urlsToSend.count==1 && !urlsToSend[0].isFileURL{
				try sendURL()
			}else{
				try sendNextFileChunk()
			}
		case .reject, .unknown:
			let error=NearbyError.canceled(reason: .userRejected)
			lastError=error
			currentState = .failed
			reportFailure(error)
			try sendDisconnectionAndDisconnect()
		case .notEnoughSpace:
			let error=NearbyError.canceled(reason: .notEnoughSpace)
			lastError=error
			currentState = .failed
			reportFailure(error)
			try sendDisconnectionAndDisconnect()
		case .timedOut:
			let error=NearbyError.canceled(reason: .timedOut)
			lastError=error
			currentState = .failed
			reportFailure(error)
			try sendDisconnectionAndDisconnect()
		case .unsupportedAttachmentType:
			let error=NearbyError.canceled(reason: .unsupportedType)
			lastError=error
			currentState = .failed
			reportFailure(error)
			try sendDisconnectionAndDisconnect()
		}
	}
	
	private func sendURL() throws{
		try sendBytesPayload(data: Data(urlsToSend[0].absoluteString.utf8), id: textPayloadID, completion: { [weak self] in
			self?.beginFinishing()
		}, failure: { [weak self] error in
			self?.lastError=error
			self?.protocolError()
		})
	}
	
	private func sendNextFileChunk() throws{
		if cancelled || resultReported { return }
		if currentTransfer==nil || currentTransfer?.currentOffset==currentTransfer?.totalBytes{
			if var transfer=currentTransfer, transfer.handle != nil{
				try transfer.handle?.close()
				transfer.handle=nil
				currentTransfer=transfer
			}
			if queue.isEmpty{
				#if DEBUG
				print("Disconnecting because all files have been transferred")
				#endif
				beginFinishing()
				return
			}
			currentTransfer=queue.removeFirst()
		}
		if currentTransfer!.totalBytes==0{
			// Zero-byte file: read(upToCount:) returns nil at EOF, so there is no
			// data chunk — just the end-of-file marker.
			try sendEOFChunk(completion: { [weak self] in
				guard let self=self else { return }
				do { try self.sendNextFileChunk() } catch {
					self.lastError=error
					self.protocolError()
				}
			}, failure: { [weak self] error in
				self?.lastError=error
				self?.protocolError()
			})
			return
		}

		let fileBuffer:Data
		if #available(macOS 10.15.4, *) {
			guard let _fileBuffer=try currentTransfer!.handle!.read(upToCount: Int(min(512*1024, currentTransfer!.totalBytes-currentTransfer!.currentOffset))) else{
				throw NearbyError.inputOutput
			}
			guard !_fileBuffer.isEmpty else { throw NearbyError.inputOutput }
			fileBuffer=_fileBuffer
		} else {
			fileBuffer=currentTransfer!.handle!.readData(ofLength: 512*1024)
		}
		
		var transfer=Location_Nearby_Connections_PayloadTransferFrame()
		transfer.packetType = .data
		transfer.payloadChunk.offset=currentTransfer!.currentOffset
		transfer.payloadChunk.flags=0
        transfer.payloadChunk.index=currentTransfer!.nextChunkIndex
        currentTransfer!.nextChunkIndex += 1
		transfer.payloadChunk.body=fileBuffer
		transfer.payloadHeader.id=currentTransfer!.payloadID
		transfer.payloadHeader.type = .file
		transfer.payloadHeader.totalSize=Int64(currentTransfer!.totalBytes)
		transfer.payloadHeader.isSensitive=false
        transfer.payloadHeader.fileName=Self.sanitizeFileName(name: currentTransfer!.url.lastPathComponent)
		currentTransfer!.currentOffset+=Int64(fileBuffer.count)
		
		var wrapper=Location_Nearby_Connections_OfflineFrame()
		wrapper.version = .v1
		wrapper.v1=Location_Nearby_Connections_V1Frame()
		wrapper.v1.type = .payloadTransfer
		wrapper.v1.payloadTransfer=transfer
		let reachesEOF=currentTransfer!.currentOffset==currentTransfer!.totalBytes
		try encryptAndSendOfflineFrame(wrapper, completion: {
			if reachesEOF {
				do {
					try self.sendEOFChunk(completion: {
						do { try self.sendNextFileChunk() } catch {
							self.lastError=error
							self.protocolError()
						}
					}, failure: { error in
						self.lastError=error
						self.protocolError()
					})
				} catch {
					self.lastError=error
					self.protocolError()
				}
			} else {
				do{
					try self.sendNextFileChunk()
				}catch{
					self.lastError=error
					self.protocolError()
				}
			}
		}, failure: { error in
			self.lastError=error
			self.protocolError()
		})
		totalBytesSent+=Int64(fileBuffer.count)
        let now=DispatchTime.now()
        if totalBytesSent == totalBytesToSend || now > lastProgressTime + .milliseconds(100) {
            lastProgressTime=now
            delegate?.outboundConnection(connection: self, transferProgress: totalBytesToSend>0 ? Double(totalBytesSent)/Double(totalBytesToSend) : 1)
        }
		
	}
	
	private func sendEOFChunk(completion:(()->Void)?=nil, failure:((Error)->Void)?=nil) throws{
		guard let transfer=currentTransfer else { return }
		var frameTransfer=Location_Nearby_Connections_PayloadTransferFrame()
		frameTransfer.packetType = .data
		frameTransfer.payloadChunk.offset=transfer.currentOffset
		frameTransfer.payloadChunk.flags=1 // <- the end-of-file bit
        frameTransfer.payloadChunk.index=transfer.nextChunkIndex
		frameTransfer.payloadHeader.id=transfer.payloadID
		frameTransfer.payloadHeader.type = .file
		frameTransfer.payloadHeader.totalSize=transfer.totalBytes
		frameTransfer.payloadHeader.isSensitive=false
        frameTransfer.payloadHeader.fileName=Self.sanitizeFileName(name: transfer.url.lastPathComponent)
		
		var wrapper=Location_Nearby_Connections_OfflineFrame()
		wrapper.version = .v1
		wrapper.v1=Location_Nearby_Connections_V1Frame()
		wrapper.v1.type = .payloadTransfer
		wrapper.v1.payloadTransfer=frameTransfer
		try encryptAndSendOfflineFrame(wrapper, completion: completion, failure: failure)
		#if DEBUG
		print("sent EOF, current transfer: \(String(describing: transfer))")
		#endif
	}

    override func remoteSafeDisconnectionAcknowledged() {
        guard currentState == .finishing, !resultReported else { return }
        // Older Android builds confirm drained payloads through safe disconnect instead of PAYLOAD_ACK.
        pendingAcknowledgements.removeAll()
        Self.logger.notice("Receiver completed the safe-disconnect handshake")
    }

    override func processPayloadAcknowledgement(id: Int64) {
        guard pendingAcknowledgements.remove(id) != nil else { return }
        Self.logger.notice("Receiver acknowledged file; remaining: \(self.pendingAcknowledgements.count)")
        if currentState == .finishing && pendingAcknowledgements.isEmpty { finishAcknowledgedTransfer() }
    }

    private func beginFinishing() {
        guard !resultReported, currentState == .sendingFiles else { return }
        currentState = .finishing
        if pendingAcknowledgements.isEmpty { finishAcknowledgedTransfer(); return }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, !self.resultReported else { return }
            self.lastError = NearbyError.protocolError("The receiver did not confirm saving the files.")
            self.protocolError()
        }
        acknowledgementTimeout = timeout
        NearbyConnection.connectionQueue.asyncAfter(deadline: .now() + 30, execute: timeout)
    }

    private func finishAcknowledgedTransfer() {
        acknowledgementTimeout?.cancel()
        do { try sendDisconnectionAndDisconnect() }
        catch { lastError = error; protocolError() }
    }

	private func reportFailure(_ error:Error){
        Self.logger.error("Outgoing failure: \(error.localizedDescription, privacy: .public)")
		guard !resultReported else { return }
		resultReported=true
        acknowledgementTimeout?.cancel()
		closeAllTransferHandles()
		delegate?.outboundConnection(connection: self, failedWithError: error)
	}

	private func closeAllTransferHandles(){
		guard !handlesClosed else { return }
		handlesClosed=true
		if var transfer=currentTransfer, let handle=transfer.handle {
			try? handle.close()
			transfer.handle=nil
			currentTransfer=transfer
		}
		for index in queue.indices {
			if let handle=queue[index].handle {
				try? handle.close()
				queue[index].handle=nil
			}
		}
	}
	
	private static func sanitizeFileName(name:String)->String{
		// "/" is kept: senders may pass relative paths when sharing directories.
		return name.replacingOccurrences(of: "[\\\\?%*:\\|\"<>=]", with: "_", options: .regularExpression)
	}
}

fileprivate struct OutgoingFileTransfer{
	let url:URL
	let payloadID:Int64
	var handle:FileHandle?
	let totalBytes:Int64
	var currentOffset:Int64
    var nextChunkIndex:Int32 = 0
}

protocol OutboundNearbyConnectionDelegate{
	func outboundConnectionWasEstablished(connection:OutboundNearbyConnection)
	func outboundConnection(connection:OutboundNearbyConnection, transferProgress:Double)
	func outboundConnectionTransferAccepted(connection:OutboundNearbyConnection)
	func outboundConnection(connection:OutboundNearbyConnection, failedWithError:Error)
	func outboundConnectionTransferFinished(connection:OutboundNearbyConnection)
}
