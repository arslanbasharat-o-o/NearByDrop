//
//  InboundNearbyConnection.swift
//  Nearby Drop — Created by Arslan Basharat
//
//

import Foundation
import Network
import CryptoKit
import CommonCrypto
import System
import AppKit
import Darwin

import SwiftECC
import BigInt

class InboundNearbyConnection: NearbyConnection{
	
	var qrSenderPublicKey: P256.Signing.PublicKey?
	private var currentState:State = .initial
	public var delegate:InboundNearbyConnectionDelegate?
	private var cipherCommitment:Data?
	
	private var textPayloadID:Int64=0
	private var timeoutWorkItem:DispatchWorkItem?
	private var terminationReported=false
	private var createdDirectories:Set<URL>=[]
	private static let handshakeTimeout:TimeInterval=15
	private static let consentTimeout:TimeInterval=60
	
	enum State{
		case initial, receivedConnectionRequest, sentUkeyServerInit, receivedUkeyClientFinish, sentConnectionResponse, sentPairedKeyResult, receivedPairedKeyResult, waitingForUserConsent, receivingFiles, finishing, completed, failed, cancelled, disconnected
	}
	
	override init(connection: NWConnection, id:String) {
		super.init(connection: connection, id: id)
	}

	override func start(){
		NearbyConnection.connectionQueue.async { [weak self] in self?.setState(.initial) }
		super.start()
	}
	
	override func handleConnectionClosure() {
		guard !terminationReported else { return }
		timeoutWorkItem?.cancel()
		timeoutWorkItem=nil
		if currentState == .finishing && lastError == nil {
			currentState = .completed
		}else if currentState != .completed && currentState != .failed && currentState != .cancelled {
			lastError=lastError ?? NearbyError.protocolError("Connection closed before file transfer completed")
			currentState = .disconnected
		}
		super.handleConnectionClosure()
		NearbyLogger.log("[NearByDrop] Inbound connection closed in state: \(currentState), lastError: \(String(describing: lastError))")
		terminationReported=true
		if currentState != .completed {
			do{
				try deletePartiallyReceivedFiles()
			}catch{
				print("Error deleting partially received files: \(error)")
			}
		}else{
			createdDirectories.removeAll()
		}
		let terminationError=currentState == .completed ? nil : (lastError ?? NearbyError.protocolError("Connection terminated"))
		DispatchQueue.main.async {
			self.delegate?.connectionWasTerminated(connection: self, error: terminationError)
		}
	}

	private func setState(_ state:State){
		currentState=state
		timeoutWorkItem?.cancel()
		timeoutWorkItem=nil
		let timeout:TimeInterval
		switch state {
		case .waitingForUserConsent: timeout=Self.consentTimeout
		case .initial, .receivedConnectionRequest, .sentUkeyServerInit, .receivedUkeyClientFinish, .sentConnectionResponse, .sentPairedKeyResult, .receivedPairedKeyResult: timeout=Self.handshakeTimeout
		default: return
		}
		let expectedState=state
		let work=DispatchWorkItem { [weak self] in
			guard let self=self, self.currentState == expectedState, !self.terminationReported else { return }
			self.lastError=NearbyError.canceled(reason: .timedOut)
			if expectedState == .waitingForUserConsent {
				self.rejectTransfer(with: .timedOut)
			}else{
				self.setState(.failed)
				self.disconnect()
			}
		}
		timeoutWorkItem=work
		NearbyConnection.connectionQueue.asyncAfter(deadline: .now()+timeout, execute: work)
	}
	
	override internal func processReceivedFrame(frameData:Data){
		do{
			switch currentState {
			case .initial:
				if let offline = try? Location_Nearby_Connections_OfflineFrame(serializedData: frameData),
				   offline.hasV1 && offline.v1.hasType && offline.v1.type == .keepAlive {
					return
				}
				let frame=try Location_Nearby_Connections_OfflineFrame(serializedData: frameData)
				try processConnectionRequestFrame(frame)
			case .receivedConnectionRequest:
				if let offline = try? Location_Nearby_Connections_OfflineFrame(serializedData: frameData),
				   offline.hasV1 && offline.v1.hasType && offline.v1.type == .keepAlive {
					return
				}
				let msg=try Securegcm_Ukey2Message(serializedData: frameData)
				ukeyClientInitMsgData=frameData
				try processUkey2ClientInit(msg)
			case .sentUkeyServerInit:
				NearbyLogger.log("[NearByDrop] sentUkeyServerInit received \(frameData.count) bytes: \(frameData.prefix(64).hexEncodedString())")
				if let offline = try? Location_Nearby_Connections_OfflineFrame(serializedData: frameData) {
					NearbyLogger.log("[NearByDrop] sentUkeyServerInit matched OfflineFrame: hasV1=\(offline.hasV1), type=\(offline.v1.hasType ? String(describing: offline.v1.type) : "none")")
					if offline.hasV1 && offline.v1.hasType && offline.v1.type == .keepAlive {
						return
					}
					if offline.hasV1 && offline.v1.hasType && offline.v1.type == .connectionResponse {
						// Client sent connectionResponse before or interleaved with clientFinish
						NearbyLogger.log("[NearByDrop] sentUkeyServerInit received early connectionResponse")
						return
					}
				}
				if let ukey = try? Securegcm_Ukey2Message(serializedData: frameData) {
					NearbyLogger.log("[NearByDrop] sentUkeyServerInit matched Ukey2Message: hasType=\(ukey.hasMessageType), type=\(ukey.messageType), hasData=\(ukey.hasMessageData), dataLen=\(ukey.messageData.count)")
					if ukey.hasMessageType && ukey.messageType == .alert {
						if let alert = try? Securegcm_Ukey2Alert(serializedData: ukey.messageData) {
							NearbyLogger.log("[NearByDrop] Client sent Ukey2Alert: type=\(alert.type), error=\(alert.errorMessage)")
						}
					}
					try processUkey2ClientFinish(ukey, raw: frameData)
				} else {
					let msg=try Securegcm_Ukey2Message(serializedData: frameData)
					try processUkey2ClientFinish(msg, raw: frameData)
				}
			case .receivedUkeyClientFinish:
				if let offline = try? Location_Nearby_Connections_OfflineFrame(serializedData: frameData) {
					if offline.hasV1 && offline.v1.hasType && offline.v1.type == .keepAlive {
						return
					}
					try processConnectionResponseFrame(offline)
				} else if let smsg = try? Securemessage_SecureMessage(serializedData: frameData) {
					if !encryptionDone {
						encryptionDone = true
						startKeepAliveTimer()
					}
					try decryptAndProcessReceivedSecureMessage(smsg)
				} else {
					let frame=try Location_Nearby_Connections_OfflineFrame(serializedData: frameData)
					try processConnectionResponseFrame(frame)
				}
			default:
				let smsg=try Securemessage_SecureMessage(serializedData: frameData)
				try decryptAndProcessReceivedSecureMessage(smsg)
			}
		}catch{
			lastError=error
			NearbyLogger.log("[NearByDrop] Inbound error: \(error) in state: \(currentState)")
			print("Deserialization error: \(error) in state \(currentState)")
			protocolError()
		}
	}
	
	override internal func processTransferSetupFrame(_ frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasType else { throw NearbyError.requiredFieldMissing("shareNearbyFrame.v1.type") }
		if frame.v1.hasType, case .cancel = frame.v1.type {
			print("Transfer canceled")
			lastError=NearbyError.canceled(reason: .userCanceled)
			setState(.cancelled)
			do { try sendDisconnectionAndDisconnect() } catch { disconnect() }
			return
		}
		if frame.v1.hasPairedKeyEncryption {
			try processPairedKeyEncryptionFrame(frame)
			return
		}
		if frame.v1.hasPairedKeyResult {
			try processPairedKeyResultFrame(frame)
			return
		}
		if frame.v1.hasIntroduction {
			try processIntroductionFrame(frame)
			return
		}
		print("Unexpected or unhandled frame in processTransferSetupFrame: \(frame)")
	}
	
	override func isServer() -> Bool {
		return true
	}
	
	private var lastProgressTime: DispatchTime = .now()
	private var totalFilesBytes: Int64 = 0
    private var completedFilesBytes: Int64 = 0

	private func notifyProgressIfNeeded(force: Bool = false) {
		let now = DispatchTime.now()
		if force || now > lastProgressTime + .milliseconds(100) {
			lastProgressTime = now
			let transferred = completedFilesBytes + transferredFiles.values.reduce(0) { $0 + $1.bytesTransferred }
			let total = max(totalFilesBytes, transferredFiles.values.reduce(0) { $0 + $1.meta.size })
			let currentID = self.id
			DispatchQueue.main.async { [weak self] in
				guard let self = self else { return }
				self.delegate?.inboundTransferProgress(connection: self, id: currentID, bytesTransferred: transferred, totalBytes: total)
			}
		}
	}

	override func processFileChunk(frame: Location_Nearby_Connections_PayloadTransferFrame) throws{
		let id=frame.payloadHeader.id
		guard let fileInfo=transferredFiles[id] else { throw NearbyError.protocolError("File payload ID \(id) is not known") }
		guard frame.payloadHeader.totalSize == fileInfo.meta.size,
			  frame.payloadChunk.offset >= 0,
			  NearbyConnection.isValidPayloadRange(totalSize: fileInfo.meta.size,
				  offset: frame.payloadChunk.offset,
				  bodyCount: frame.payloadChunk.hasBody ? frame.payloadChunk.body.count : 0) else {
			throw NearbyError.protocolError("Invalid file payload range")
		}
		let currentOffset=fileInfo.bytesTransferred
		guard frame.payloadChunk.offset==currentOffset else { throw NearbyError.protocolError("Invalid offset into file \(frame.payloadChunk.offset), expected \(currentOffset)") }
		guard currentOffset <= fileInfo.meta.size - Int64(frame.payloadChunk.body.count) else { throw NearbyError.protocolError("Transferred file size exceeds previously specified value") }
		if frame.payloadChunk.body.count>0{
			guard fileInfo.fd >= 0 else { throw NearbyError.inputOutput }
			try frame.payloadChunk.body.withUnsafeBytes { rawPtr in
				guard let base = rawPtr.baseAddress else { return }
				var remaining = rawPtr.count
				var current = base
				while remaining > 0 {
					let written = write(fileInfo.fd, current, remaining)
					if written <= 0 { throw NearbyError.inputOutput }
					remaining -= written
					current = current.advanced(by: written)
				}
			}
			transferredFiles[id]!.bytesTransferred+=Int64(frame.payloadChunk.body.count)
			notifyProgressIfNeeded()
		}
		if (frame.payloadChunk.flags & 1)==1{
			guard transferredFiles[id]!.bytesTransferred==fileInfo.meta.size else { throw NearbyError.protocolError("File ended before receiving the advertised byte count") }
			if transferredFiles[id]!.fd >= 0 {
				close(transferredFiles[id]!.fd)
				transferredFiles[id]!.fd = -1
			}
			completedFilesBytes += fileInfo.meta.size
			transferredFiles.removeValue(forKey: id)
			notifyProgressIfNeeded(force: true)
			if transferredFiles.isEmpty{
				beginFinishing()
			}
		}
	}
	
	override func processBytesPayload(payload: Data, id: Int64) throws -> Bool {
		if id==textPayloadID{
			// Only open http(s). Any other scheme would make the Mac launch an
			// arbitrary URL handler after the user consented to a generic "link".
			guard let urlStr=String(data: payload, encoding: .utf8), let url=URL(string: urlStr),
				  url.scheme=="http" || url.scheme=="https" else {
				throw NearbyError.protocolError("Invalid URL payload")
			}
			NSWorkspace.shared.open(url)
			beginFinishing()
			return true
		}else if let fileInfo=transferredFiles[id]{
			guard fileInfo.bytesTransferred <= fileInfo.meta.size - Int64(payload.count) else { throw NearbyError.protocolError("Transferred file size exceeds previously specified value") }
			guard fileInfo.fd >= 0 else { throw NearbyError.inputOutput }
			try payload.withUnsafeBytes { rawPtr in
				guard let base = rawPtr.baseAddress else { return }
				var remaining = rawPtr.count
				var current = base
				while remaining > 0 {
					let written = write(fileInfo.fd, current, remaining)
					if written <= 0 { throw NearbyError.inputOutput }
					remaining -= written
					current = current.advanced(by: written)
				}
			}
			transferredFiles[id]!.bytesTransferred+=Int64(payload.count)
			guard transferredFiles[id]!.bytesTransferred==fileInfo.meta.size else { throw NearbyError.protocolError("File ended before receiving the advertised byte count") }
			if transferredFiles[id]!.fd >= 0 {
				close(transferredFiles[id]!.fd)
				transferredFiles[id]!.fd = -1
			}
			completedFilesBytes += fileInfo.meta.size
			transferredFiles.removeValue(forKey: id)
			notifyProgressIfNeeded(force: true)
			beginFinishing()
			return true
		}
		return false
	}
	
	private func processConnectionRequestFrame(_ frame:Location_Nearby_Connections_OfflineFrame) throws{
		guard frame.hasV1 && frame.v1.hasConnectionRequest && frame.v1.connectionRequest.hasEndpointInfo else { throw NearbyError.requiredFieldMissing("connectionRequest.endpointInfo") }
		guard case .connectionRequest = frame.v1.type else { throw NearbyError.protocolError("Unexpected frame type \(frame.v1.type)") }
		// The connection-request endpoint info has the same layout as the mDNS record;
		// the shared parser handles the "hidden" case where the name is absent.
		guard let endpointInfo=EndpointInfo(data: frame.v1.connectionRequest.endpointInfo) else { throw NearbyError.protocolError("Endpoint info could not be parsed") }
		let name=endpointInfo.name ?? "Unknown device"
		NearbyLogger.log("[NearByDrop] Inbound ConnectionRequest from device '\(name)' (type: \(endpointInfo.deviceType))")
		remoteDeviceInfo=RemoteDeviceInfo(name: name, type: endpointInfo.deviceType, id: frame.v1.connectionRequest.endpointID.isEmpty ? nil : frame.v1.connectionRequest.endpointID)
		setState(.receivedConnectionRequest)
	}
	
	private func processUkey2ClientInit(_ msg:Securegcm_Ukey2Message) throws{
		guard msg.hasMessageType, msg.hasMessageData else { throw NearbyError.requiredFieldMissing("clientInit ukey2message.type|data") }
		guard case .clientInit = msg.messageType else{
			sendUkey2Alert(type: .badMessageType)
			throw NearbyError.ukey2
		}
		let clientInit:Securegcm_Ukey2ClientInit
		do{
			clientInit=try Securegcm_Ukey2ClientInit(serializedData: msg.messageData)
		}catch{
			sendUkey2Alert(type: .badMessageData)
			throw NearbyError.ukey2
		}
		guard clientInit.version==1 else{
			sendUkey2Alert(type: .badVersion)
			throw NearbyError.ukey2
		}
		guard clientInit.random.count==32 else{
			sendUkey2Alert(type: .badRandom)
			throw NearbyError.ukey2
		}
		var found=false
		for commitment in clientInit.cipherCommitments{
			if case .p256Sha512 = commitment.handshakeCipher{
				found=true
				cipherCommitment=commitment.commitment
				break
			}
		}
		guard found else{
			sendUkey2Alert(type: .badHandshakeCipher)
			throw NearbyError.ukey2
		}
		guard clientInit.nextProtocol=="AES_256_CBC-HMAC_SHA256" else{
			sendUkey2Alert(type: .badNextProtocol)
			throw NearbyError.ukey2
		}
		
		let domain=Domain.instance(curve: .EC256r1)
		let (pubKey, privKey)=domain.makeKeyPair()
		publicKey=pubKey
		privateKey=privKey
		
		var serverInit=Securegcm_Ukey2ServerInit()
		serverInit.version=1
		serverInit.random=try Data.randomData(length: 32)
		serverInit.handshakeCipher = .p256Sha512
		
		var pkey=Securemessage_GenericPublicKey()
		pkey.type = .ecP256
		pkey.ecP256PublicKey=Securemessage_EcP256PublicKey()
		// SecureMessage coordinates are signed integers; preserve the positive sign bit.
		pkey.ecP256PublicKey.x=Data(pubKey.w.x.asSignedBytes())
		pkey.ecP256PublicKey.y=Data(pubKey.w.y.asSignedBytes())
		serverInit.publicKey=try pkey.serializedData()
		
		var serverInitMsg=Securegcm_Ukey2Message()
		serverInitMsg.messageType = .serverInit
		serverInitMsg.messageData=try serverInit.serializedData()
		let serverInitData=try serverInitMsg.serializedData()
		ukeyServerInitMsgData=serverInitData
		sendFrameAsync(serverInitData)
		setState(.sentUkeyServerInit)
	}
	
	private func processUkey2ClientFinish(_ msg:Securegcm_Ukey2Message, raw:Data) throws{
		guard msg.hasMessageType, msg.hasMessageData else { throw NearbyError.requiredFieldMissing("clientFinish ukey2message.type|data") }
		guard case .clientFinish = msg.messageType else { throw NearbyError.ukey2 }
		
		var sha=SHA512()
		sha.update(data: raw)
		let rawHash=Data(sha.finalize())
		sha=SHA512()
		sha.update(data: msg.messageData)
		let dataHash=Data(sha.finalize())
		guard cipherCommitment == rawHash || cipherCommitment == dataHash else {
			NearbyLogger.log("[NearByDrop] UKEY2 cipher commitment mismatch! rawHash: \(rawHash.hexEncodedString()), dataHash: \(dataHash.hexEncodedString()), expected: \(cipherCommitment?.hexEncodedString() ?? "nil")")
			throw NearbyError.ukey2
		}
		
		let clientFinish=try Securegcm_Ukey2ClientFinished(serializedData: msg.messageData)
		guard clientFinish.hasPublicKey else {throw NearbyError.requiredFieldMissing("ukey2clientFinish.publicKey") }
		let clientKey=try Securemessage_GenericPublicKey(serializedData: clientFinish.publicKey)
		
		try finalizeKeyExchange(peerKey: clientKey)
		
		setState(.receivedUkeyClientFinish)
	}
	
	private func processConnectionResponseFrame(_ frame:Location_Nearby_Connections_OfflineFrame) throws{
		guard frame.hasV1, frame.v1.hasType else { throw NearbyError.requiredFieldMissing("offlineFrame.v1.type") }
		if case .connectionResponse = frame.v1.type {
			var resp=Location_Nearby_Connections_OfflineFrame()
			resp.version = .v1
			resp.v1=Location_Nearby_Connections_V1Frame()
			resp.v1.type = .connectionResponse
			resp.v1.connectionResponse=Location_Nearby_Connections_ConnectionResponseFrame()
			resp.v1.connectionResponse.response = .accept
			resp.v1.connectionResponse.status=0
			resp.v1.connectionResponse.osInfo=Location_Nearby_Connections_OsInfo()
			resp.v1.connectionResponse.osInfo.type = .apple
			sendFrameAsync(try resp.serializedData())
			
			encryptionDone=true
			startKeepAliveTimer()
			
			var pairedEncryption=Sharing_Nearby_Frame()
			pairedEncryption.version = .v1
			pairedEncryption.v1=Sharing_Nearby_V1Frame()
			pairedEncryption.v1.type = .pairedKeyEncryption
			pairedEncryption.v1.pairedKeyEncryption=Sharing_Nearby_PairedKeyEncryptionFrame()
			// Presumably used for all the phone number stuff that no one needs anyway
			pairedEncryption.v1.pairedKeyEncryption.secretIDHash=try Data.randomData(length: 6)
			pairedEncryption.v1.pairedKeyEncryption.signedData=try Data.randomData(length: 72)
			try sendTransferSetupFrame(pairedEncryption)
			setState(.sentConnectionResponse)
		} else {
			print("Unhandled offline frame plaintext: \(frame)")
		}
	}
	
	private func processPairedKeyEncryptionFrame(_ frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasPairedKeyEncryption else { throw NearbyError.requiredFieldMissing("shareNearbyFrame.v1.pairedKeyEncryption") }
		if let key=qrSenderPublicKey {
			let proof=frame.v1.pairedKeyEncryption.qrCodeHandshakeData
			guard let authKey=authKey, let signature=try? P256.Signing.ECDSASignature(rawRepresentation: proof),
				  key.isValidSignature(signature, for: authKey.data()) else {
				throw NearbyError.protocolError("The sender does not match the scanned QR code.")
			}
			let identity=Data(SHA256.hash(data: key.rawRepresentation)).map { String(format: "%02x", $0) }.joined()
			remoteDeviceInfo?.id="qr:\(identity)"
		}
		var pairedResult=Sharing_Nearby_Frame()
		pairedResult.version = .v1
		pairedResult.v1=Sharing_Nearby_V1Frame()
		pairedResult.v1.type = .pairedKeyResult
		pairedResult.v1.pairedKeyResult=Sharing_Nearby_PairedKeyResultFrame()
		pairedResult.v1.pairedKeyResult.status = .unable
		try sendTransferSetupFrame(pairedResult)
		setState(.sentPairedKeyResult)
	}
	
	private func processPairedKeyResultFrame(_ frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasPairedKeyResult else { throw NearbyError.requiredFieldMissing("shareNearbyFrame.v1.pairedKeyResult") }
		setState(.receivedPairedKeyResult)
	}
	
	private func makeFileDestinationURL(_ name:String, in downloadsDirectory:URL) -> URL{
		// Senders put relative paths in the name when sharing directories; each path
		// component is sanitized separately and ".."/"." are dropped, so the result
		// can never escape downloadsDirectory.
		var comps=[String]()
		for raw in name.split(whereSeparator: {$0=="/" || $0=="\\"}){
			var comp=String(raw).replacingOccurrences(of: "\0", with: "_")
			comp=comp.replacingOccurrences(of: "[?%*:\\|\"<>=]", with: "_", options: .regularExpression)
			if comp.isEmpty || comp=="." || comp==".."{ continue }
			comps.append(comp)
		}
		if comps.isEmpty{ comps=["Unnamed file"] }
		var directory=downloadsDirectory
		if comps.count>1{
			for comp in comps.dropLast(){ directory=directory.appendingPathComponent(comp, isDirectory: true) }
		}
		guard let lastComponent=comps.last else {
			return downloadsDirectory.appendingPathComponent("Unnamed file", isDirectory: false)
		}
		var dest=directory.appendingPathComponent(lastComponent, isDirectory: false)
		var counter=1
		let ext=dest.pathExtension
		let baseUrl=dest.deletingPathExtension()
		while FileManager.default.fileExists(atPath: dest.path) || transferredFiles.values.contains(where: {$0.destinationURL.path==dest.path}){
			var path="\(baseUrl.path) (\(counter))"
			if !ext.isEmpty{
				path+=".\(ext)"
			}
			dest=URL(fileURLWithPath: path)
			counter+=1
		}
		return dest
	}
	
	private func processIntroductionFrame(_ frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasIntroduction else { throw NearbyError.requiredFieldMissing("shareNearbyFrame.v1.introduction") }
		let introduction=frame.v1.introduction
		guard introduction.fileMetadata.count <= 128,
			  !(introduction.fileMetadata.isEmpty && introduction.textMetadata.isEmpty) else {
			throw NearbyError.protocolError("Malformed introduction payload")
		}
		NearbyLogger.log("[NearByDrop] Inbound Introduction received: \(introduction.fileMetadata.count) files, \(introduction.textMetadata.count) text items")
		if !introduction.fileMetadata.isEmpty {
			var payloadIDs=Set<Int64>()
			let downloadsDirectory=NearbyConnectionManager.downloadDirectory.resolvingSymlinksInPath()
			for file in introduction.fileMetadata{
				guard file.size >= 0, file.name.utf8.count <= 4096, payloadIDs.insert(file.payloadID).inserted else {
					throw NearbyError.protocolError("Malformed file metadata")
				}
				let dest=makeFileDestinationURL(file.name, in: downloadsDirectory)
				let info=InternalFileInfo(meta: FileMetadata(name: dest.lastPathComponent, size: file.size, mimeType: file.mimeType, destinationURL: dest),
										  payloadID: file.payloadID,
										  destinationURL: dest)
				transferredFiles[file.payloadID]=info
			}
			setState(.waitingForUserConsent)
			let metadata=TransferMetadata(files: transferredFiles.map({$0.value.meta}), id: id, pinCode: pinCode)
			requestOrAutomaticConsent(metadata: metadata)
		}else if !introduction.textMetadata.isEmpty {
			let meta=introduction.textMetadata[0]
			guard meta.size >= 0, meta.size <= Int64(NearbyConnection.SANE_FRAME_LENGTH) else {
				throw NearbyError.protocolError("Byte payload is too large")
			}
			if case .url=meta.type{
				let metadata=TransferMetadata(files: [], id: id, pinCode: pinCode, textDescription: meta.textTitle)
				textPayloadID=meta.payloadID
				setState(.waitingForUserConsent)
				requestOrAutomaticConsent(metadata: metadata)
			}else{
				let downloadsDirectory=NearbyConnectionManager.downloadDirectory.resolvingSymlinksInPath()
				let dateFormatter=DateFormatter()
				dateFormatter.dateFormat="yyyy-MM-dd HH.mm.ss"
				let dest=makeFileDestinationURL("\(dateFormatter.string(from: Date())).txt", in: downloadsDirectory)
				let info=InternalFileInfo(meta: FileMetadata(name: dest.lastPathComponent, size: meta.size, mimeType: "text/plain", destinationURL: dest),
										  payloadID: meta.payloadID,
											  destinationURL: dest)
				transferredFiles[meta.payloadID]=info
				setState(.waitingForUserConsent)
				requestOrAutomaticConsent(metadata: TransferMetadata(files: [info.meta], id: self.id, pinCode: self.pinCode))
			}
		}else{
			rejectTransfer(with: .unsupportedAttachmentType)
		}
	}

	// Trusted devices skip the prompt; every other sender sees the consent card.
	private func requestOrAutomaticConsent(metadata:TransferMetadata){
		guard let device=remoteDeviceInfo else { return }
        DispatchQueue.main.async {
            self.delegate?.obtainUserConsent(for: metadata, from: device, connection: self)
        }
	}
	
	func submitUserConsent(accepted:Bool){
		NearbyConnection.connectionQueue.async { [weak self] in
			guard let self=self, self.currentState == .waitingForUserConsent, !self.terminationReported else { return }
			if accepted{
				self.acceptTransfer()
			}else{
				self.rejectTransfer()
			}
		}
	}
	
	private func acceptTransfer(){
		do{
			let downloadsRoot=NearbyConnectionManager.downloadDirectory.resolvingSymlinksInPath().standardizedFileURL
			for (id, file) in transferredFiles{
				let parent=file.destinationURL.deletingLastPathComponent()
				let resolvedParent=parent.resolvingSymlinksInPath().standardizedFileURL
				guard resolvedParent.path == downloadsRoot.path || resolvedParent.path.hasPrefix(downloadsRoot.path + "/") else {
					throw NearbyError.inputOutput
				}
				if !FileManager.default.fileExists(atPath: parent.path){
					try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
					createdDirectories.insert(parent)
				}
				let fd=open(file.destinationURL.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
				guard fd >= 0 else { throw NearbyError.inputOutput }
				transferredFiles[id]!.fd=fd
				transferredFiles[id]!.created=true
			}
			totalFilesBytes=transferredFiles.values.reduce(0) { $0 + $1.meta.size }
			notifyProgressIfNeeded(force: true)
			
			var frame=Sharing_Nearby_Frame()
			frame.version = .v1
			frame.v1.type = .response
			frame.v1.connectionResponse.status = .accept
			try sendTransferSetupFrame(frame)
			setState(.receivingFiles)
		}catch{
			lastError=error
			setState(.failed)
			disconnect()
		}
	}
	
	private func rejectTransfer(with reason:Sharing_Nearby_ConnectionResponseFrame.Status = .reject){
		let error:NearbyError
		switch reason {
		case .timedOut: error = .canceled(reason: .timedOut)
		case .notEnoughSpace: error = .canceled(reason: .notEnoughSpace)
		case .unsupportedAttachmentType: error = .canceled(reason: .unsupportedType)
		default: error = .canceled(reason: .userRejected)
		}
		lastError=error
		setState(.failed)
		var frame=Sharing_Nearby_Frame()
		frame.version = .v1
		frame.v1.type = .response
		frame.v1.connectionResponse.status = reason
		do{
			try sendTransferSetupFrame(frame)
			try sendDisconnectionAndDisconnect()
		}catch{
			lastError=error
			disconnect()
		}
	}

	private func beginFinishing(){
		guard currentState == .receivingFiles, !terminationReported else { return }
		setState(.finishing)
		do {
			try sendDisconnectionAndDisconnect()
		}catch{
			lastError=error
			setState(.failed)
			disconnect()
		}
	}
	
	private func deletePartiallyReceivedFiles() throws{
		for file in transferredFiles.values{
			guard file.created else { continue }
			if file.fd >= 0 {
				close(file.fd)
			}
			try FileManager.default.removeItem(at: file.destinationURL)
		}
		transferredFiles.removeAll()
		for directory in createdDirectories.sorted(by: { $0.path.count > $1.path.count }){
			guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path), contents.isEmpty else { continue }
			try? FileManager.default.removeItem(at: directory)
		}
		createdDirectories.removeAll()
	}
}

protocol InboundNearbyConnectionDelegate{
	func obtainUserConsent(for transfer:TransferMetadata, from device:RemoteDeviceInfo, connection:InboundNearbyConnection)
	func inboundTransferProgress(connection:InboundNearbyConnection, id:String, bytesTransferred:Int64, totalBytes:Int64)
	func connectionWasTerminated(connection:InboundNearbyConnection, error:Error?)
}
