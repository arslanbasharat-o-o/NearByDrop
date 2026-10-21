//
//  InboundNearbyConnection.swift
//  NearByDrop Created by Arslan Basharat
//
//

import Foundation
import Network
import CryptoKit
import CommonCrypto
import System
import AppKit

import SwiftECC
import BigInt

class InboundNearbyConnection: NearbyConnection{
	
	var qrSenderPublicKey: P256.Signing.PublicKey?
	private var currentState:State = .initial
	public var delegate:InboundNearbyConnectionDelegate?
	private var cipherCommitment:Data?
	
	private var textPayloadID:Int64=0
	
	enum State{
		case initial, receivedConnectionRequest, sentUkeyServerInit, receivedUkeyClientFinish, sentConnectionResponse, sentPairedKeyResult, receivedPairedKeyResult, waitingForUserConsent, receivingFiles, disconnected
	}
	
	override init(connection: NWConnection, id:String) {
		super.init(connection: connection, id: id)
	}
	
	override func handleConnectionClosure() {
		if lastError==nil && currentState == .receivingFiles && transferredFiles.values.contains(where: {$0.created}){
			lastError=NearbyError.protocolError("Connection closed before file transfer completed")
		}
		super.handleConnectionClosure()
		NSLog("[NearByDrop] Inbound connection closed in state: %@, lastError: %@", String(describing: currentState), String(describing: lastError))
		currentState = .disconnected
		do{
			try deletePartiallyReceivedFiles()
		}catch{
			print("Error deleting partially received files: \(error)")
		}
		DispatchQueue.main.async {
			self.delegate?.connectionWasTerminated(connection: self, error: self.lastError)
		}
	}
	
	override internal func processReceivedFrame(frameData:Data){
		do{
			switch currentState {
			case .initial:
				let frame=try Location_Nearby_Connections_OfflineFrame(serializedData: frameData)
				try processConnectionRequestFrame(frame)
			case .receivedConnectionRequest:
				let msg=try Securegcm_Ukey2Message(serializedData: frameData)
				ukeyClientInitMsgData=frameData
				try processUkey2ClientInit(msg)
			case .sentUkeyServerInit:
				let msg=try Securegcm_Ukey2Message(serializedData: frameData)
				try processUkey2ClientFinish(msg, raw: frameData)
			case .receivedUkeyClientFinish:
				let frame=try Location_Nearby_Connections_OfflineFrame(serializedData: frameData)
				try processConnectionResponseFrame(frame)
			default:
				let smsg=try Securemessage_SecureMessage(serializedData: frameData)
				try decryptAndProcessReceivedSecureMessage(smsg)
			}
		}catch{
			lastError=error
			NSLog("[NearByDrop] Inbound deserialization/processing error: %@ in state %@", error.localizedDescription, String(describing: currentState))
			print("Deserialization error: \(error) in state \(currentState)")
			protocolError()
		}
	}
	
	override internal func processTransferSetupFrame(_ frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1 else { return }
		if frame.v1.hasType, case .cancel = frame.v1.type {
			print("Transfer canceled")
			currentState = .disconnected
			try sendDisconnectionAndDisconnect()
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
	
	override func processFileChunk(frame: Location_Nearby_Connections_PayloadTransferFrame) throws{
		let id=frame.payloadHeader.id
		guard let fileInfo=transferredFiles[id] else { throw NearbyError.protocolError("File payload ID \(id) is not known") }
		let currentOffset=fileInfo.bytesTransferred
		guard frame.payloadChunk.offset==currentOffset else { throw NearbyError.protocolError("Invalid offset into file \(frame.payloadChunk.offset), expected \(currentOffset)") }
		guard currentOffset+Int64(frame.payloadChunk.body.count)<=fileInfo.meta.size else { throw NearbyError.protocolError("Transferred file size exceeds previously specified value") }
		if frame.payloadChunk.body.count>0{
			guard let fileHandle=fileInfo.fileHandle else { throw NearbyError.inputOutput }
			try fileHandle.write(contentsOf: frame.payloadChunk.body)
			transferredFiles[id]!.bytesTransferred+=Int64(frame.payloadChunk.body.count)
			fileInfo.progress?.completedUnitCount=transferredFiles[id]!.bytesTransferred
		}
		if (frame.payloadChunk.flags & 1)==1{
			guard transferredFiles[id]!.bytesTransferred==fileInfo.meta.size else { throw NearbyError.protocolError("File ended before receiving the advertised byte count") }
			guard let fileHandle=transferredFiles[id]!.fileHandle else { throw NearbyError.inputOutput }
			try fileHandle.close()
			transferredFiles[id]!.fileHandle=nil
			fileInfo.progress?.unpublish()
			transferredFiles.removeValue(forKey: id)
			if transferredFiles.isEmpty{
				try sendDisconnectionAndDisconnect()
			}
		}
	}
	
	override func processBytesPayload(payload: Data, id: Int64) throws -> Bool {
		if id==textPayloadID{
			// Only open http(s). Any other scheme would make the Mac launch an
			// arbitrary URL handler after the user consented to a generic "link".
			if let urlStr=String(data: payload, encoding: .utf8), let url=URL(string: urlStr),
			   url.scheme=="http" || url.scheme=="https"{
				NSWorkspace.shared.open(url)
			}
			try sendDisconnectionAndDisconnect()
			return true
		}else if let fileInfo=transferredFiles[id]{
			guard fileInfo.bytesTransferred+Int64(payload.count)<=fileInfo.meta.size else { throw NearbyError.protocolError("Transferred file size exceeds previously specified value") }
			guard let fileHandle=fileInfo.fileHandle else { throw NearbyError.inputOutput }
			try fileHandle.write(contentsOf: payload)
			transferredFiles[id]!.bytesTransferred+=Int64(payload.count)
			fileInfo.progress?.completedUnitCount=transferredFiles[id]!.bytesTransferred
			guard transferredFiles[id]!.bytesTransferred==fileInfo.meta.size else { throw NearbyError.protocolError("File ended before receiving the advertised byte count") }
			try fileHandle.close()
			transferredFiles[id]!.fileHandle=nil
			fileInfo.progress?.unpublish()
			transferredFiles.removeValue(forKey: id)
			try sendDisconnectionAndDisconnect()
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
		NSLog("[NearByDrop] Inbound ConnectionRequest from device '%@' (type: %@)", name, String(describing: endpointInfo.deviceType))
		remoteDeviceInfo=RemoteDeviceInfo(name: name, type: endpointInfo.deviceType, id: frame.v1.connectionRequest.endpointID.isEmpty ? nil : frame.v1.connectionRequest.endpointID)
		currentState = .receivedConnectionRequest
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
		serverInit.random=Data.randomData(length: 32)
		serverInit.handshakeCipher = .p256Sha512
		
		var pkey=Securemessage_GenericPublicKey()
		pkey.type = .ecP256
		pkey.ecP256PublicKey=Securemessage_EcP256PublicKey()
		pkey.ecP256PublicKey.x=NearbyConnection.fixedCoordinate32Bytes(pubKey.w.x)
		pkey.ecP256PublicKey.y=NearbyConnection.fixedCoordinate32Bytes(pubKey.w.y)
		serverInit.publicKey=try pkey.serializedData()
		
		var serverInitMsg=Securegcm_Ukey2Message()
		serverInitMsg.messageType = .serverInit
		serverInitMsg.messageData=try serverInit.serializedData()
		let serverInitData=try serverInitMsg.serializedData()
		ukeyServerInitMsgData=serverInitData
		sendFrameAsync(serverInitData)
		currentState = .sentUkeyServerInit
	}
	
	private func processUkey2ClientFinish(_ msg:Securegcm_Ukey2Message, raw:Data) throws{
		guard msg.hasMessageType, msg.hasMessageData else { throw NearbyError.requiredFieldMissing("clientFinish ukey2message.type|data") }
		guard case .clientFinish = msg.messageType else { throw NearbyError.ukey2 }
		
		var sha=SHA512()
		sha.update(data: raw)
		guard cipherCommitment==Data(sha.finalize()) else { throw NearbyError.ukey2 }
		
		let clientFinish=try Securegcm_Ukey2ClientFinished(serializedData: msg.messageData)
		guard clientFinish.hasPublicKey else {throw NearbyError.requiredFieldMissing("ukey2clientFinish.publicKey") }
		let clientKey=try Securemessage_GenericPublicKey(serializedData: clientFinish.publicKey)
		
		try finalizeKeyExchange(peerKey: clientKey)
		
		currentState = .receivedUkeyClientFinish
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
			pairedEncryption.v1.pairedKeyEncryption.secretIDHash=Data.randomData(length: 6)
			pairedEncryption.v1.pairedKeyEncryption.signedData=Data.randomData(length: 72)
			try sendTransferSetupFrame(pairedEncryption)
			currentState = .sentConnectionResponse
		} else {
			print("Unhandled offline frame plaintext: \(frame)")
		}
	}
	
	private func processPairedKeyEncryptionFrame(_ frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasPairedKeyEncryption else { throw NearbyError.requiredFieldMissing("shareNearbyFrame.v1.pairedKeyEncryption") }
        if let key=qrSenderPublicKey, !frame.v1.pairedKeyEncryption.qrCodeHandshakeData.isEmpty {
            let proof=frame.v1.pairedKeyEncryption.qrCodeHandshakeData
            guard let authKey=authKey, let signature=try? P256.Signing.ECDSASignature(rawRepresentation: proof),
                  key.isValidSignature(signature, for: authKey.data()) else {
                throw NearbyError.protocolError("The sender does not match the scanned QR code.")
            }
        }
		var pairedResult=Sharing_Nearby_Frame()
		pairedResult.version = .v1
		pairedResult.v1=Sharing_Nearby_V1Frame()
		pairedResult.v1.type = .pairedKeyResult
		pairedResult.v1.pairedKeyResult=Sharing_Nearby_PairedKeyResultFrame()
		pairedResult.v1.pairedKeyResult.status = .unable
		try sendTransferSetupFrame(pairedResult)
		currentState = .sentPairedKeyResult
	}
	
	private func processPairedKeyResultFrame(_ frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasPairedKeyResult else { throw NearbyError.requiredFieldMissing("shareNearbyFrame.v1.pairedKeyResult") }
		currentState = .receivedPairedKeyResult
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
			if (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) == nil {
				directory=downloadsDirectory
				comps=[comps.last!]
			}
		}
		var dest=directory.appendingPathComponent(comps.last!, isDirectory: false)
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
		currentState = .waitingForUserConsent
		NSLog("[NearByDrop] Inbound Introduction received: %lu files, %lu text items", frame.v1.introduction.fileMetadata.count, frame.v1.introduction.textMetadata.count)
		if !frame.v1.introduction.fileMetadata.isEmpty {
			let downloadsDirectory=NearbyConnectionManager.downloadDirectory.resolvingSymlinksInPath()
			for file in frame.v1.introduction.fileMetadata{
				let dest=makeFileDestinationURL(file.name, in: downloadsDirectory)
				let info=InternalFileInfo(meta: FileMetadata(name: dest.lastPathComponent, size: file.size, mimeType: file.mimeType),
										  payloadID: file.payloadID,
										  destinationURL: dest)
				transferredFiles[file.payloadID]=info
			}
			let metadata=TransferMetadata(files: transferredFiles.map({$0.value.meta}), id: id, pinCode: pinCode)
			requestOrAutomaticConsent(metadata: metadata)
		}else if !frame.v1.introduction.textMetadata.isEmpty {
			let meta=frame.v1.introduction.textMetadata[0]
			if case .url=meta.type{
				let metadata=TransferMetadata(files: [], id: id, pinCode: pinCode, textDescription: meta.textTitle)
				textPayloadID=meta.payloadID
				requestOrAutomaticConsent(metadata: metadata)
			}else{
				let downloadsDirectory=NearbyConnectionManager.downloadDirectory.resolvingSymlinksInPath()
				let dateFormatter=DateFormatter()
				dateFormatter.dateFormat="yyyy-MM-dd HH.mm.ss"
				let dest=makeFileDestinationURL("\(dateFormatter.string(from: Date())).txt", in: downloadsDirectory)
				let info=InternalFileInfo(meta: FileMetadata(name: dest.lastPathComponent, size: meta.size, mimeType: "text/plain"),
										  payloadID: meta.payloadID,
										  destinationURL: dest)
				transferredFiles[meta.payloadID]=info
				requestOrAutomaticConsent(metadata: TransferMetadata(files: [info.meta], id: self.id, pinCode: self.pinCode))
			}
		}else{
			rejectTransfer(with: .unsupportedAttachmentType)
		}
	}

	// Trusted devices skip the prompt; every other sender sees the consent card.
	private func requestOrAutomaticConsent(metadata:TransferMetadata){
		guard let device=remoteDeviceInfo else { return }
		if NearbyConnectionManager.isTrusted(name: device.name, id: device.id){
			submitUserConsent(accepted: true)
		}else{
			DispatchQueue.main.async {
				self.delegate?.obtainUserConsent(for: metadata, from: device, connection: self)
			}
		}
	}
	
	func submitUserConsent(accepted:Bool){
		DispatchQueue.global(qos: .userInitiated).async {
			if accepted{
				self.acceptTransfer()
			}else{
				self.rejectTransfer()
			}
		}
	}
	
	private func acceptTransfer(){
		do{
			for (id, file) in transferredFiles{
				FileManager.default.createFile(atPath: file.destinationURL.path, contents: nil)
				let handle=try FileHandle(forWritingTo: file.destinationURL)
				transferredFiles[id]!.fileHandle=handle
				let progress=Progress()
				progress.fileURL=file.destinationURL
				progress.totalUnitCount=file.meta.size
				progress.kind = .file
				progress.isPausable=false
				progress.publish()
				transferredFiles[id]!.progress=progress
				transferredFiles[id]!.created=true
			}
			
			var frame=Sharing_Nearby_Frame()
			frame.version = .v1
			frame.v1.type = .response
			frame.v1.connectionResponse.status = .accept
			currentState = .receivingFiles
			try sendTransferSetupFrame(frame)
		}catch{
			lastError=error
			protocolError()
		}
	}
	
	private func rejectTransfer(with reason:Sharing_Nearby_ConnectionResponseFrame.Status = .reject){
		var frame=Sharing_Nearby_Frame()
		frame.version = .v1
		frame.v1.type = .response
		frame.v1.connectionResponse.status = reason
		do{
			try sendTransferSetupFrame(frame)
			try sendDisconnectionAndDisconnect()
		}catch{
			print("Error \(error)")
			protocolError()
		}
	}
	
	private func deletePartiallyReceivedFiles() throws{
		for (_, file) in transferredFiles{
			guard file.created else { continue }
			try FileManager.default.removeItem(at: file.destinationURL)
		}
	}
}

protocol InboundNearbyConnectionDelegate{
	func obtainUserConsent(for transfer:TransferMetadata, from device:RemoteDeviceInfo, connection:InboundNearbyConnection)
	func connectionWasTerminated(connection:InboundNearbyConnection, error:Error?)
}
