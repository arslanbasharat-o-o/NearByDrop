//
//  NearbyConnectionManager.swift
//  NearByDrop Created by Arslan Basharat
//
//

import Foundation
import Network
import System
import CryptoKit
import SwiftECC

public struct RemoteDeviceInfo{
	public let name:String
	public let type:DeviceType
	public let qrCodeData:Data?
	public var id:String?
	
	init(name: String, type: DeviceType, id: String? = nil) {
		self.name = name
		self.type = type
		self.id = id
		self.qrCodeData = nil
	}
	
	init(info:EndpointInfo, id: String? = nil){
		self.name=info.name ?? "Unknown device"
		self.type=info.deviceType
		self.qrCodeData=info.qrCodeData
		self.id=id
	}
	
	public enum DeviceType:Int32{
		case unknown=0
		case phone
		case tablet
		case computer
		
		public static func fromRawValue(value:Int) -> DeviceType{
			switch value {
			case 0:
				return .unknown
			case 1:
				return .phone
			case 2:
				return .tablet
			case 3:
				return .computer
			default:
				return .unknown
			}
		}
	}
}


public enum NearbyError:Error{
	case protocolError(_ message:String)
	case requiredFieldMissing(_ message:String)
	case ukey2
	case inputOutput
	case canceled(reason:CancellationReason)
	
	public enum CancellationReason{
		case userRejected, userCanceled, notEnoughSpace, unsupportedType, timedOut
	}
}

public struct TransferMetadata{
	public let files:[FileMetadata]
	public let id:String
	public let pinCode:String?
	public let textDescription:String?
	
	init(files: [FileMetadata], id: String, pinCode: String?, textDescription: String?=nil){
		self.files = files
		self.id = id
		self.pinCode = pinCode
		self.textDescription = textDescription
	}
}

public struct FileMetadata{
	public let name:String
	public let size:Int64
	public let mimeType:String
}

struct FoundServiceInfo{
	let service:NWBrowser.Result
	var device:RemoteDeviceInfo?
}

struct OutgoingTransferInfo{
	let service:NWBrowser.Result
	let device:RemoteDeviceInfo
	let connection:OutboundNearbyConnection
	let delegate:ShareExtensionDelegate
}

struct EndpointInfo{
	var name:String?
	let deviceType:RemoteDeviceInfo.DeviceType
	let qrCodeData:Data?
	
	init(name: String, deviceType: RemoteDeviceInfo.DeviceType, qrCodeData: Data? = nil){
		self.name = name
		self.deviceType = deviceType
		self.qrCodeData=qrCodeData
	}
	
	init?(data:Data){
		guard data.count>17 else {return nil}
		let hasName=(data[0] & 0x10)==0
		let deviceNameLength:Int
		let deviceName:String?
		if hasName{
			deviceNameLength=Int(data[17])
			guard data.count>=deviceNameLength+18 else {return nil}
			guard let _deviceName=String(data: data[18..<(18+deviceNameLength)], encoding: .utf8) else {return nil}
			deviceName=_deviceName
		}else{
			deviceNameLength=0
			deviceName=nil
		}
		let rawDeviceType:Int=Int(data[0] & 0x0E) >> 1
		self.name=deviceName
		self.deviceType=RemoteDeviceInfo.DeviceType.fromRawValue(value: rawDeviceType)
		var offset=1+16
		if hasName{
			offset=offset+1+deviceNameLength
		}
		var qrCodeData:Data?=nil
		while offset < data.count {
            guard data.count - offset >= 2 else { return nil }
            let type=data[offset], length=Int(data[offset+1])
            offset += 2
            guard length <= data.count-offset else { return nil }
            if type == 1 { qrCodeData=data.subdata(in: offset..<offset+length) }
            offset += length
        }
		self.qrCodeData=qrCodeData
	}
	
	func serialize()->Data{
		// 1 byte: Version(3 bits)|Visibility(1 bit)|Device Type(3 bits)|Reserved(1 bits)
		// Device types: unknown=0, phone=1, tablet=2, laptop=3
		var endpointInfo:[UInt8]=[UInt8(deviceType.rawValue << 1)]
		// 16 bytes: unknown random bytes
		for _ in 0...15{
			endpointInfo.append(UInt8.random(in: 0...255))
		}
		// Device name in UTF-8 prefixed with 1-byte length
		var nameChars=[UInt8](name!.utf8)
		if nameChars.count>255{
			nameChars=[UInt8](nameChars[0..<255])
		}
		endpointInfo.append(UInt8(nameChars.count))
		for ch in nameChars{
			endpointInfo.append(UInt8(ch))
		}
        if let qrCodeData=qrCodeData {
            endpointInfo.append(contentsOf: [1, UInt8(qrCodeData.count)])
            endpointInfo.append(contentsOf: qrCodeData)
        }
		return Data(endpointInfo)
	}
}

public protocol MainAppDelegate{
	func obtainUserConsent(for transfer:TransferMetadata, from device:RemoteDeviceInfo)
	func incomingTransfer(id:String, didFinishWith error:Error?)
	func advertisementStateDidChange(_ state:NearbyConnectionManager.AdvertisementState)
}

public protocol ShareExtensionDelegate:AnyObject{
	func addDevice(device:RemoteDeviceInfo)
	func removeDevice(id:String)
	func startTransferWithQrCode(device:RemoteDeviceInfo)
	func connectionWasEstablished(pinCode:String)
	func connectionFailed(with error:Error)
	func transferAccepted()
	func transferProgress(progress:Double)
	func transferFinished()
}

public class NearbyConnectionManager : NSObject, NetServiceDelegate, InboundNearbyConnectionDelegate, OutboundNearbyConnectionDelegate{
	public enum AdvertisementState:Equatable{
		case idle
		case starting
		case published
		case failed
	}
	
	private var tcpListener:NWListener;
	public let endpointID:[UInt8]=generateEndpointID()
	private var mdnsService:NetService?
	public private(set) var advertisementState:AdvertisementState = .idle
	private var activeConnections:[String:InboundNearbyConnection]=[:]
	private var foundServices:[String:FoundServiceInfo]=[:]
	private var shareExtensionDelegates:[ShareExtensionDelegate]=[]
	private var outgoingTransfers:[String:OutgoingTransferInfo]=[:]
	public var mainAppDelegate:(any MainAppDelegate)?
	private var discoveryRefCount=0
	
	private var browser:NWBrowser?
	
	private var qrCodePublicKey:ECPublicKey?
	private var qrCodePrivateKey:ECPrivateKey?
	private var qrCodeAdvertisingToken:Data?
	private var qrCodeNameEncryptionKey:SymmetricKey?
	private var qrCodeData:Data?
	
	public static let shared=NearbyConnectionManager()
	private static let downloadDirKey = "downloadDirectoryURL"
	private static let downloadBookmarkKey = "downloadDirectoryBookmark"

	public static var downloadDirectory: URL {
		get {
			if let data = UserDefaults.standard.data(forKey: downloadBookmarkKey) {
				var isStale = false
				if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
					_ = url.startAccessingSecurityScopedResource()
					return url
				}
			}
			if let path = UserDefaults.standard.string(forKey: downloadDirKey), !path.isEmpty {
				let url = path.hasPrefix("file://") ? (URL(string: path) ?? URL(fileURLWithPath: path)) : URL(fileURLWithPath: path)
				if FileManager.default.fileExists(atPath: url.path) {
					return url
				}
			}
			return (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
		}
		set {
			UserDefaults.standard.set(newValue.path, forKey: downloadDirKey)
			if let bookmark = try? newValue.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
				UserDefaults.standard.set(bookmark, forKey: downloadBookmarkKey)
			}
		}
	}

	private static let trustedKey="trustedDevices"

	public static func trustedDeviceKey(name:String, id:String?) -> String{
		return "\(id ?? "-")|\(name)"
	}

	public static func isTrusted(name:String, id:String?) -> Bool{
		guard let list = UserDefaults.standard.stringArray(forKey: trustedKey) else { return false }
		let key = trustedDeviceKey(name: name, id: id)
		return list.contains(key) || list.contains(name) || (id != nil && list.contains(id!))
	}

	public static func setTrusted(name:String, id:String?, trusted:Bool){
		var list = UserDefaults.standard.stringArray(forKey: trustedKey) ?? []
		let key = trustedDeviceKey(name: name, id: id)
		if trusted{
			if !list.contains(key){ list.append(key) }
			if !list.contains(name){ list.append(name) }
			if let id = id, !list.contains(id){ list.append(id) }
		}else{
			list.removeAll{ $0==key || $0==name || (id != nil && $0==id) }
		}
		UserDefaults.standard.set(list, forKey: trustedKey)
	}
	private let pathMonitor=NWPathMonitor()
    private var lastNetworkPath: String?
    private var receivingCode: QuickShareCode?
    private var receivingCodeExpiry: DispatchWorkItem?
	
	override init() {
		let tcpOptions=NWProtocolTCP.Options()
		tcpOptions.noDelay=true
		tcpOptions.enableKeepalive=true
		tcpOptions.keepaliveIdle=2
		let params=NWParameters(tls: .none, tcp: tcpOptions)
		params.serviceClass = .responsiveData
		params.allowFastOpen=true
		params.preferNoProxies=true
		tcpListener=try! NWListener(using: params)
		super.init()
		startPathMonitoring()
	}
	
    private func startPathMonitoring(){
        pathMonitor.pathUpdateHandler={ [weak self] path in
            let identity="\(path.status):" + path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            DispatchQueue.main.async {
                guard let self=self, self.lastNetworkPath != identity else { return }
                let hadPath=self.lastNetworkPath != nil
                self.lastNetworkPath=identity
                if path.status != .satisfied { self.updateAdvertisementState(.failed) }
                else if hadPath && self.mdnsService != nil { self.refreshMDNS() }
            }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }

    public func refreshMDNS(){
        guard tcpListener.state == .ready else { return }
        // An intentional restart is not a publication failure.
        let previous=mdnsService
        mdnsService=nil
        previous?.delegate=nil
        previous?.stop()
        initMDNS()
    }

    public func receiveQRCode(_ value:String) throws {
        let code=try QuickShareCode(value)
        receivingCodeExpiry?.cancel()
        receivingCode=code
        updateAdvertisementRecord()
        let expiry=DispatchWorkItem { [weak self] in self?.stopReceivingQRCode() }
        receivingCodeExpiry=expiry
        DispatchQueue.main.asyncAfter(deadline: .now()+120, execute: expiry)
    }

    public func stopReceivingQRCode(){
        receivingCodeExpiry?.cancel()
        receivingCodeExpiry=nil
        receivingCode=nil
        updateAdvertisementRecord()
    }

    private func advertisementRecord()->Data {
        let info=EndpointInfo(name: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
                              deviceType: .computer, qrCodeData: receivingCode?.advertisingToken)
        return NetService.data(fromTXTRecord: ["n": info.serialize().urlSafeBase64EncodedString().data(using: .utf8)!])
    }

    private func updateAdvertisementRecord(){ mdnsService?.setTXTRecord(advertisementRecord()) }

	public func becomeVisible(){
		updateAdvertisementState(.starting)
		startTCPListener()
	}

    private func updateAdvertisementState(_ state:AdvertisementState){
        let update={
            guard self.advertisementState != state else { return }
            self.advertisementState=state
            self.mainAppDelegate?.advertisementStateDidChange(state)
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

	private func startTCPListener(){
		tcpListener.stateUpdateHandler={(state:NWListener.State) in
			switch state{
			case .ready:
				self.updateAdvertisementState(.starting)
				DispatchQueue.main.async {
					self.initMDNS()
				}
			case let .failed(error):
#if DEBUG
				print("TCP listener failed: \(error)")
#endif
				self.updateAdvertisementState(.failed)
			default:
				break
			}
		}
		tcpListener.newConnectionHandler={(connection:NWConnection) in
			let id=UUID().uuidString
			let conn=InboundNearbyConnection(connection: connection, id: id)
            conn.qrSenderPublicKey=self.receivingCode?.publicKey
			self.activeConnections[id]=conn
			conn.delegate=self
			conn.start()
		}
		tcpListener.start(queue: .global(qos: .userInitiated))
	}
	
	private static func generateEndpointID()->[UInt8]{
		var id:[UInt8]=[]
		let alphabet="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".compactMap {UInt8($0.asciiValue!)}
		for _ in 0...3{
			id.append(alphabet[Int.random(in: 0..<alphabet.count)])
		}
		return id
	}
	
	private func initMDNS(){
        guard mdnsService == nil else { return }
		let nameBytes:[UInt8]=[
			0x23, // PCP
			endpointID[0], endpointID[1], endpointID[2], endpointID[3],
			0xFC, 0x9F, 0x5E, // Service ID hash
			0, 0
		]
		let name=Data(nameBytes).urlSafeBase64EncodedString()
		
		let port:Int32=Int32(tcpListener.port!.rawValue)
		let service=NetService(domain: "", type: "_FC9F5ED42C8A._tcp.", name: name, port: port)
		service.includesPeerToPeer=true
		service.delegate=self
		service.setTXTRecord(advertisementRecord())
		mdnsService=service
		service.publish()
	}

	public func netServiceDidPublish(_ sender: NetService){
        guard sender === mdnsService else { return }
		updateAdvertisementState(.published)
	}

	public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]){
        guard sender === mdnsService else { return }
#if DEBUG
		print("Bonjour advertisement failed: \(errorDict)")
#endif
		updateAdvertisementState(.failed)
	}

	public func netServiceDidStop(_ sender: NetService){
        guard sender === mdnsService else { return }
		updateAdvertisementState(.failed)
	}
	
	func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo, connection: InboundNearbyConnection) {
		guard let delegate=mainAppDelegate else {return}
		delegate.obtainUserConsent(for: transfer, from: device)
	}
	
	func connectionWasTerminated(connection:InboundNearbyConnection, error:Error?){
		guard let delegate=mainAppDelegate else {return}
		delegate.incomingTransfer(id: connection.id, didFinishWith: error)
		activeConnections.removeValue(forKey: connection.id)
	}
	
	public func submitUserConsent(transferID:String, accept:Bool){
		guard let conn=activeConnections[transferID] else {return}
		conn.submitUserConsent(accepted: accept)
	}
	
	public func startDeviceDiscovery(){
		if discoveryRefCount==0{
			foundServices.removeAll()
			if browser==nil{
				browser=NWBrowser(for: .bonjourWithTXTRecord(type: "_FC9F5ED42C8A._tcp.", domain: nil), using: .tcp)
				browser?.browseResultsChangedHandler={newResults, changes in
					for change in changes{
						switch change{
						case let .added(res):
							self.maybeAddFoundDevice(service: res)
						case let .removed(res):
							self.maybeRemoveFoundDevice(service: res)
                        case let .changed(old: _, new: res, flags: _):
                            self.maybeAddFoundDevice(service: res)
						default:
							break
						}
					}
				}
			}
			browser?.start(queue: .main)
		}
		discoveryRefCount+=1
	}
	
	public func stopDeviceDiscovery(){
		discoveryRefCount-=1
		assert(discoveryRefCount>=0)
		if discoveryRefCount==0{
			browser?.cancel()
			browser=nil
		}
	}
	
	public func addShareExtensionDelegate(_ delegate:ShareExtensionDelegate){
		shareExtensionDelegates.append(delegate)
		for service in foundServices.values{
			guard let device=service.device else {continue}
			delegate.addDevice(device: device)
		}
	}
	
	public func removeShareExtensionDelegate(_ delegate:ShareExtensionDelegate){
		shareExtensionDelegates.removeAll(where: {$0===delegate})
	}
	
	public func cancelOutgoingTransfer(id:String){
		guard let transfer=outgoingTransfers[id] else {return}
		transfer.connection.cancel()
	}
	
	private func endpointID(for service:NWBrowser.Result)->String?{
		guard case let NWEndpoint.service(name: serviceName, type: _, domain: _, interface: _)=service.endpoint else {return nil}
		guard let nameData=Data.dataFromUrlSafeBase64(serviceName) else {return nil}
		guard nameData.count>=10 else {return nil}
		let pcp=nameData[0]
		guard pcp==0x23 else {return nil}
		guard let endpointID=String(data: nameData.subdata(in: 1..<5), encoding: .ascii) else {return nil}
		let serviceIDHash=nameData.subdata(in: 5..<8)
		guard serviceIDHash==Data([0xFC, 0x9F, 0x5E]) else {return nil}
		return endpointID
	}
	
	private func maybeAddFoundDevice(service:NWBrowser.Result){
		#if DEBUG
		print("found service \(service)")
		#endif
		for interface in service.interfaces{
			if case .loopback=interface.type{
				#if DEBUG
				print("ignoring localhost service")
				#endif
				return
			}
		}
		guard let endpointID=endpointID(for: service), endpointID != String(bytes: self.endpointID, encoding: .ascii) else {return}
		#if DEBUG
		print("service name is valid, endpoint ID \(endpointID)")
		#endif
		var foundService=FoundServiceInfo(service: service)
		
		guard case let NWBrowser.Result.Metadata.bonjour(txtRecord)=service.metadata else {return}
		guard let endpointInfoEncoded=txtRecord.dictionary["n"] else {return}
		guard let endpointInfoSerialized=Data.dataFromUrlSafeBase64(endpointInfoEncoded) else {return}
		guard var endpointInfo=EndpointInfo(data: endpointInfoSerialized) else {return}
		
		var deviceInfo:RemoteDeviceInfo?
		if let _=endpointInfo.name{
			deviceInfo=addFoundDevice(foundService: &foundService, endpointInfo: endpointInfo, endpointID: endpointID)
		}
		
		if let qrData=endpointInfo.qrCodeData, let _=qrCodeAdvertisingToken{
#if DEBUG
			print("Device has QR data: \(qrData.base64EncodedString()), our advertising token is \(qrCodeAdvertisingToken!.base64EncodedString())")
#endif
			if qrData==qrCodeAdvertisingToken!{
				if let deviceInfo=deviceInfo{
					for delegate in shareExtensionDelegates{
						delegate.startTransferWithQrCode(device: deviceInfo)
					}
				}
			}else if qrData.count>28{
				do{
					let box=try AES.GCM.SealedBox(combined: qrData)
					let decryptedName=try AES.GCM.open(box, using: qrCodeNameEncryptionKey!, authenticating: qrCodeAdvertisingToken!)
					guard let name=String.init(data: decryptedName, encoding: .utf8) else {return}
					endpointInfo.name=name
					let deviceInfo=addFoundDevice(foundService: &foundService, endpointInfo: endpointInfo, endpointID: endpointID)
					for delegate in shareExtensionDelegates{
						delegate.startTransferWithQrCode(device: deviceInfo)
					}
				}catch{
#if DEBUG
					print("Error decrypting QR code data of an invisible device: \(error)")
#endif
				}
			}
		}
	}
	
	private func addFoundDevice(foundService:inout FoundServiceInfo, endpointInfo:EndpointInfo, endpointID:String) -> RemoteDeviceInfo{
		let deviceInfo=RemoteDeviceInfo(info: endpointInfo, id: endpointID)
		foundService.device=deviceInfo
		foundServices[endpointID]=foundService
		for delegate in shareExtensionDelegates{
			delegate.addDevice(device: deviceInfo)
		}
		return deviceInfo
	}
	
	private func maybeRemoveFoundDevice(service:NWBrowser.Result){
		guard let endpointID=endpointID(for: service) else {return}
		guard let _=foundServices.removeValue(forKey: endpointID) else {return}
		for delegate in shareExtensionDelegates {
			delegate.removeDevice(id: endpointID)
		}
	}
	
	public func generateQrCodeKey() -> String{
		let domain=Domain.instance(curve: .EC256r1)
		let (pubKey, privKey)=domain.makeKeyPair()
		qrCodePublicKey=pubKey
		qrCodePrivateKey=privKey
		var keyData=Data()
		keyData.append(contentsOf: [0, 0, 2 + (pubKey.w.y.asSignedBytes().last! & 1)])
		let keyBytes=Data(pubKey.w.x.asSignedBytes())
		// Sometimes, for some keys, there will be a leading zero byte. Strip that, Android really hates it (it breaks the endpoint info)
		let x=keyBytes.suffixOfAtMost(numBytes: 32)
        keyData.append(Data(repeating: 0, count: 32-x.count))
        keyData.append(x)
		
		let ikm=SymmetricKey(data: keyData)
		qrCodeAdvertisingToken=NearbyConnection.hkdf(inputKeyMaterial: ikm, salt: Data(), info: "advertisingContext".data(using: .utf8)!, outputByteCount: 16).data()
		qrCodeNameEncryptionKey=NearbyConnection.hkdf(inputKeyMaterial: ikm, salt: Data(), info: "encryptionKey".data(using: .utf8)!, outputByteCount: 16)
		qrCodeData=keyData
		
		return keyData.urlSafeBase64EncodedString()
	}
	
	public func clearQrCodeKey(){
		qrCodePublicKey=nil
		qrCodePrivateKey=nil
		qrCodeAdvertisingToken=nil
		qrCodeNameEncryptionKey=nil
		qrCodeData=nil
	}
	
	public func startOutgoingTransfer(deviceID:String, delegate:ShareExtensionDelegate, urls:[URL], displayNames:[String]?=nil){
		guard let info=foundServices[deviceID] else {return}
		let tcp=NWProtocolTCP.Options.init()
		tcp.noDelay=true
		let nwconn=NWConnection(to: info.service.endpoint, using: NWParameters(tls: .none, tcp: tcp))
		let conn=OutboundNearbyConnection(connection: nwconn, id: deviceID, urlsToSend: urls, displayNames: displayNames)
		conn.delegate=self
		conn.qrCodePrivateKey=qrCodePrivateKey
		let transfer=OutgoingTransferInfo(service: info.service, device: info.device!, connection: conn, delegate: delegate)
		outgoingTransfers[deviceID]=transfer
		conn.start()
	}
	
	func outboundConnectionWasEstablished(connection: OutboundNearbyConnection) {
		guard let transfer=outgoingTransfers[connection.id] else {return}
		DispatchQueue.main.async {
			transfer.delegate.connectionWasEstablished(pinCode: connection.pinCode!)
		}
	}
	
	func outboundConnectionTransferAccepted(connection: OutboundNearbyConnection) {
		guard let transfer=outgoingTransfers[connection.id] else {return}
		DispatchQueue.main.async {
			transfer.delegate.transferAccepted()
		}
	}
	
	func outboundConnection(connection: OutboundNearbyConnection, transferProgress: Double) {
		guard let transfer=outgoingTransfers[connection.id] else {return}
		DispatchQueue.main.async {
			transfer.delegate.transferProgress(progress: transferProgress)
		}
	}
	
	func outboundConnection(connection: OutboundNearbyConnection, failedWithError: Error) {
		guard let transfer=outgoingTransfers[connection.id] else {return}
		DispatchQueue.main.async {
			transfer.delegate.connectionFailed(with: failedWithError)
		}
		outgoingTransfers.removeValue(forKey: connection.id)
	}
	
	func outboundConnectionTransferFinished(connection: OutboundNearbyConnection) {
		guard let transfer=outgoingTransfers[connection.id] else {return}
		DispatchQueue.main.async {
			transfer.delegate.transferFinished()
		}
		outgoingTransfers.removeValue(forKey: connection.id)
	}
}

public struct QuickShareCode {
    let publicKey: P256.Signing.PublicKey
    let advertisingToken: Data

    public init(_ value:String) throws {
        guard value.utf8.count < 512,
              let url=URLComponents(string: value), url.scheme == "https",
              (url.host == "quickshare.google" || url.host == "www.quickshare.google"),
              (url.path == "/qrcode" || url.path == "/qrcode/") else {
            throw NearbyError.protocolError("This is not a Quick Share QR code.")
        }
        var keyString: String? = nil
        if let fragment = url.fragment {
            if fragment.hasPrefix("key=") {
                keyString = String(fragment.dropFirst(4))
            } else if let range = fragment.range(of: "key=") {
                keyString = String(fragment[range.upperBound...])
            }
            if let str = keyString, let amp = str.firstIndex(of: "&") {
                keyString = String(str[..<amp])
            }
        }
        if keyString == nil, let queryItems = url.queryItems {
            keyString = queryItems.first(where: { $0.name == "key" })?.value
        }
        guard let encoded = keyString, encoded.count == 47,
              encoded.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              let data=Data(base64Encoded: encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="),
              data.count == 35, data[0] == 0, data[1] == 0, data[2] == 2 || data[2] == 3 else {
            throw NearbyError.protocolError("This Quick Share code is invalid or unsupported.")
        }
        publicKey=try P256.Signing.PublicKey(compressedRepresentation: data.dropFirst(2))
        advertisingToken=HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: data), salt: Data(), info: Data("advertisingContext".utf8), outputByteCount: 16).withUnsafeBytes { Data($0) }
    }
}
