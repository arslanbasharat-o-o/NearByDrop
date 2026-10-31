//
//  NearbyConnectionManager.swift
//  Nearby Drop — Created by Arslan Basharat
//
//

import Foundation
import Network
import System
import CryptoKit
import SwiftECC
import CoreBluetooth

public struct RemoteDeviceInfo: Sendable {
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
	
	public enum DeviceType:Int32, Sendable{
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


public enum NearbyError: LocalizedError, Sendable {
	case protocolError(_ message:String)
	case requiredFieldMissing(_ message:String)
	case ukey2
	case inputOutput
	case canceled(reason:CancellationReason)
	case receivingPaused
	
	public enum CancellationReason: Sendable {
		case userRejected, userCanceled, notEnoughSpace, unsupportedType, timedOut
	}

	public var errorDescription: String? {
		switch self {
		case .protocolError(let message):
			if message.contains("Connection closed before file transfer completed") {
				return "Connection was interrupted by the remote device. Keep both devices unlocked and near each other."
			}
			return message
		case .requiredFieldMissing:
			return "The transfer was interrupted due to an invalid data packet."
		case .ukey2:
			return "Security handshake failed. Ensure both devices are nearby and try again."
		case .inputOutput:
			return "Could not write received file to disk. Check permissions and disk space."
		case .canceled(let reason):
			switch reason {
			case .userRejected:
				return "The transfer was declined."
			case .userCanceled:
				return "The transfer was canceled by the remote device."
			case .notEnoughSpace:
				return "Not enough free disk space to receive this file."
			case .unsupportedType:
				return "Unsupported file type."
			case .timedOut:
				return "The transfer timed out."
			}
		case .receivingPaused:
			return "Receiving is paused. Resume receiving to accept new transfers."
		}
	}
}

public struct TransferMetadata: Sendable {
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

public struct FileMetadata: Sendable {
	public let name:String
	public let size:Int64
	public let mimeType:String
	public let destinationURL:URL?

	init(name:String, size:Int64, mimeType:String, destinationURL:URL?=nil){
		self.name=name
		self.size=size
		self.mimeType=mimeType
		self.destinationURL=destinationURL
	}
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
	var cancelled=false
}

struct EndpointInfo: Sendable {
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
		while offset + 2 <= data.count {
            let type=data[offset], length=Int(data[offset+1])
            offset += 2
            guard length <= data.count-offset else { break }
            if type == 1 { qrCodeData=data.subdata(in: offset..<offset+length) }
            offset += length
        }
		self.qrCodeData=qrCodeData
	}
	
	func serialize()->Data{
		// 1 byte: Version(3 bits)|Visibility(1 bit)|Device Type(3 bits)|Reserved(1 bits)
		// Device types: unknown=0, phone=1, tablet=2, laptop=3
		var endpointInfo:[UInt8]=[UInt8(deviceType.rawValue << 1) | (qrCodeData == nil ? 0 : 0x20)]
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
	func incomingTransferProgress(id:String, bytesTransferred:Int64, totalBytes:Int64)
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

enum ReceivingPausePolicy {
	static let preferenceKey = "receivingPaused"

	static func restored(defaults: UserDefaults = .standard) -> Bool {
		defaults.bool(forKey: preferenceKey)
	}

	static func mayAcceptNewSession(isPaused: Bool) -> Bool { !isPaused }

	static func mayHonorConsent(accepted: Bool, isPaused: Bool) -> Bool {
		!accepted || !isPaused
	}

	static func sessionsToCancel(activeIDs: Set<String>, approvedIDs: Set<String>, isPaused: Bool) -> Set<String> {
		guard isPaused else { return [] }
		return activeIDs.subtracting(approvedIDs)
	}
}

public class NearbyConnectionManager : NSObject, NetServiceDelegate, InboundNearbyConnectionDelegate, OutboundNearbyConnectionDelegate, CBCentralManagerDelegate{
	public enum AdvertisementState:Equatable, Sendable{
		case idle
		case starting
		case published
		case failed
		case paused
	}
	
	private var tcpListener:NWListener?
	private var tcpListenerUsesFixedPort = false
	private var tcpListenerHasStarted = false
	private var listenerCancellationID:UUID?
	private var cancellingListener:NWListener?
	private let stateQueue=DispatchQueue(label: "com.arslanbasharat.NearByDrop.manager-state", qos: .userInitiated)
	private static let maxActiveConnections=8
	public private(set) var endpointID:[UInt8]=generateEndpointID()
	private var mdnsService:NetService?
	public private(set) var advertisementState:AdvertisementState = .idle
	private var activeConnections:[String:InboundNearbyConnection]=[:]
	private var approvedInboundTransferIDs:Set<String>=[]
	private var foundServices:[String:FoundServiceInfo]=[:]
	private var shareExtensionDelegates:[ShareExtensionDelegate]=[]
	private var outgoingTransfers:[String:OutgoingTransferInfo]=[:]
	private var _mainAppDelegate:(any MainAppDelegate)?
	public var mainAppDelegate:(any MainAppDelegate)? {
		get { stateQueue.sync { _mainAppDelegate } }
		set { stateQueue.sync { _mainAppDelegate=newValue } }
	}
	private var discoveryRefCount=0
	private var receivingPaused = ReceivingPausePolicy.restored()

	var receivingPausedForTesting: Bool { stateQueue.sync { receivingPaused } }
	var inboundListenerExistsForTesting: Bool { stateQueue.sync { tcpListener != nil } }
	var inboundListenerReadyForTesting: Bool { stateQueue.sync { !receivingPaused && tcpListener?.state == .ready } }
	var inboundAdvertisementExistsForTesting: Bool { stateQueue.sync { mdnsService != nil } }
	var discoveryReferenceCountForTesting: Int { stateQueue.sync { discoveryRefCount } }
	
	private var browser:NWBrowser?
	private var centralManager:CBCentralManager?
	private static let quickShareServiceUUID=CBUUID(string: "FE2C")
	private var lastBLEDiscoveryTime:Date?
	private var qrCodePrivateKey:P256.Signing.PrivateKey?
	private var qrCodeAdvertisingToken:Data?
	private var qrCodeNameEncryptionKey:SymmetricKey?
	private var qrCodeData:Data?
	
	public static let shared=NearbyConnectionManager()
	private static let downloadDirKey = "downloadDirectoryURL"
	private static let downloadBookmarkKey = "downloadDirectoryBookmark"
	private static let downloadScopeLock=NSLock()
	private static var scopedDownloadDirectory:URL?
	private static var scopedDownloadDirectoryAccessed=false

	public static var downloadDirectory: URL {
		get {
			let resolved:URL
			if let data = UserDefaults.standard.data(forKey: downloadBookmarkKey) {
				var isStale = false
				if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
					let homeDownloads = (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false))?.path ?? (NSHomeDirectory() + "/Downloads")
					if url.path == homeDownloads {
						resolved=defaultDownloadDirectory
					} else {
						resolved=url
					}
					return activateDownloadScope(for: resolved)
				}
			}
			if let path = UserDefaults.standard.string(forKey: downloadDirKey), !path.isEmpty {
				let url = path.hasPrefix("file://") ? (URL(string: path) ?? URL(fileURLWithPath: path)) : URL(fileURLWithPath: path)
				let homeDownloads = (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false))?.path ?? (NSHomeDirectory() + "/Downloads")
				if url.path != homeDownloads && FileManager.default.fileExists(atPath: url.path) {
					return activateDownloadScope(for: url)
				}
			}
			return activateDownloadScope(for: defaultDownloadDirectory)
		}
		set {
			UserDefaults.standard.set(newValue.path, forKey: downloadDirKey)
			if let bookmark = try? newValue.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
				UserDefaults.standard.set(bookmark, forKey: downloadBookmarkKey)
			}
			_ = activateDownloadScope(for: newValue)
		}
	}

	private static func activateDownloadScope(for url:URL)->URL {
		downloadScopeLock.lock()
		defer { downloadScopeLock.unlock() }
		if scopedDownloadDirectory?.path != url.path {
			if scopedDownloadDirectoryAccessed { scopedDownloadDirectory?.stopAccessingSecurityScopedResource() }
			scopedDownloadDirectory=url
			scopedDownloadDirectoryAccessed=url.startAccessingSecurityScopedResource()
		}
		return url
	}

	public static var defaultDownloadDirectory: URL {
		let base = (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
		let legacyFolder = base.appendingPathComponent("NearByDrop", isDirectory: true)
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: legacyFolder.path, isDirectory: &isDirectory), isDirectory.boolValue {
			// Keep existing installs on their old folder so a branding rename cannot hide received files.
			return legacyFolder
		}
		let folder = base.appendingPathComponent("Nearby Drop", isDirectory: true)
		if !FileManager.default.fileExists(atPath: folder.path) {
			try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		}
		return folder
	}

	public static var customDeviceName: String? {
		get { UserDefaults.standard.string(forKey: "customDeviceName") }
		set {
			if let val = newValue, !val.isEmpty {
				UserDefaults.standard.set(val, forKey: "customDeviceName")
			} else {
				UserDefaults.standard.removeObject(forKey: "customDeviceName")
			}
			shared.refreshMDNS()
		}
	}

	public static var currentDeviceName: String {
		customDeviceName ?? Host.current().localizedName ?? ProcessInfo.processInfo.hostName
	}

	/// Older releases stored display names and connection IDs as trusted identities.
	/// Neither value is a persistent authenticated peer identity, so discard them
	/// whenever the app starts. Repeating this is safe and also clears values
	/// written by a downgraded older release.
	public static func invalidateLegacyTrustedDevices(in defaults: UserDefaults = .standard) {
		defaults.removeObject(forKey: "trustedDevices")
	}
	private let pathMonitor=NWPathMonitor()
    private var hasNetworkPath=false
    private var receivingCode: QuickShareCode?
    private var receivingCodeExpiry: DispatchWorkItem?
	
    private static func makeListener(preferFixedPort: Bool = true) -> (listener: NWListener, usesFixedPort: Bool)? {
        let tcpOptions=NWProtocolTCP.Options()
        tcpOptions.noDelay=true
        tcpOptions.enableKeepalive=true
        tcpOptions.keepaliveIdle=2
        let params=NWParameters(tls: .none, tcp: tcpOptions)
        params.preferNoProxies=true
        params.allowLocalEndpointReuse=true
        if preferFixedPort, let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: 52843)!) {
            return (listener, true)
        }
        guard let listener = try? NWListener(using: params) else { return nil }
        return (listener, false)
    }

    private func createInboundListener(preferFixedPort: Bool = true) {
        let binding = Self.makeListener(preferFixedPort: preferFixedPort)
        tcpListener = binding?.listener
        tcpListenerUsesFixedPort = binding?.usesFixedPort ?? false
        tcpListenerHasStarted = false
    }

    override init() {
		if !ReceivingPausePolicy.restored() {
			let binding = Self.makeListener()
			tcpListener = binding?.listener
			tcpListenerUsesFixedPort = binding?.usesFixedPort ?? false
		}
        super.init()
        startPathMonitoring()
    }

    private func startPathMonitoring(){
        pathMonitor.pathUpdateHandler={ [weak self] path in
            self?.stateQueue.async {
                guard let self=self else { return }
                if !ReceivingPausePolicy.mayAcceptNewSession(isPaused: self.receivingPaused) {
                    self.updateAdvertisementState(.paused)
                    return
                }
                let hadPath=self.hasNetworkPath
                self.hasNetworkPath=true
                if path.status != .satisfied { self.updateAdvertisementState(.failed) }
                else if hadPath && self._mainAppDelegate != nil {
                    // Switching Wi-Fi networks can keep the same interface name and path status.
					NearbyLogger.log("[NearByDrop] Network changed; refreshing Bonjour")
                    self.refreshMDNSOnStateQueue()
                }
            }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }

    public func refreshMDNS(){
        stateQueue.async { [weak self] in self?.refreshMDNSOnStateQueue() }
    }

    private func refreshMDNSOnStateQueue(){
			guard ReceivingPausePolicy.mayAcceptNewSession(isPaused: receivingPaused) else {
			updateAdvertisementState(.paused)
			return
		}
		guard listenerCancellationID == nil else {
			updateAdvertisementState(.starting)
			return
		}
        if tcpListener == nil || tcpListener?.state == .cancelled {
            createInboundListener()
            startTCPListener()
            return
        }
        if case .failed = tcpListener?.state {
            let retryWithEphemeralPort = tcpListenerUsesFixedPort
            tcpListener?.stateUpdateHandler=nil
            tcpListener?.cancel()
            createInboundListener(preferFixedPort: !retryWithEphemeralPort)
            let previous=mdnsService
            mdnsService=nil
            previous?.delegate=nil
            previous?.stop()
            startTCPListener()
            return
        }
        guard let listener=tcpListener, listener.state == .ready else { return }
        // An intentional restart is not a publication failure.
        let previous=mdnsService
        mdnsService=nil
        previous?.delegate=nil
        previous?.remove(from: .main, forMode: .default)
        previous?.stop()
        initMDNS()
    }

    public func receiveQRCode(_ value:String) throws {
        let code=try QuickShareCode(value)
		try stateQueue.sync {
			guard !receivingPaused else { throw NearbyError.receivingPaused }
            receivingCodeExpiry?.cancel()
            // Android caches endpoint metadata by ID; a QR session needs fresh discovery.
            endpointID=Self.generateEndpointID()
            receivingCode=code
            refreshMDNSOnStateQueue()
            let expiry=DispatchWorkItem { [weak self] in self?.stopReceivingQRCodeOnStateQueue() }
            receivingCodeExpiry=expiry
            stateQueue.asyncAfter(deadline: .now()+120, execute: expiry)
        }
    }

    public func stopReceivingQRCode(){
        stateQueue.async { [weak self] in self?.stopReceivingQRCodeOnStateQueue() }
    }

    private func stopReceivingQRCodeOnStateQueue(){
        receivingCodeExpiry?.cancel()
        receivingCodeExpiry=nil
        receivingCode=nil
        updateAdvertisementRecord()
    }

    public static func currentLocalIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferredIP: String?
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let address = interface.ifa_addr else { continue }
            let addrFamily = address.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("lo") && !name.hasPrefix("utun") && !name.hasPrefix("awdl") && !name.hasPrefix("llw") else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: hostname)
                if name.hasPrefix("en") {
                    return ip
                }
                if preferredIP == nil {
                    preferredIP = ip
                }
            }
        }
        return preferredIP
    }

    private func advertisementRecord()->Data {
        let info=EndpointInfo(name: NearbyConnectionManager.currentDeviceName,
                              deviceType: .computer, qrCodeData: receivingCode?.advertisingToken)
        var dict: [String: Data] = [
            "n": Data(info.serialize().urlSafeBase64EncodedString().utf8)
        ]
        if let ip = NearbyConnectionManager.currentLocalIPv4Address() {
            dict["IPv4"] = Data(ip.utf8)
        }
        return NetService.data(fromTXTRecord: dict)
    }

    private func updateAdvertisementRecord(){ mdnsService?.setTXTRecord(advertisementRecord()) }

	public func becomeVisible(){
		stateQueue.async {
			guard !self.receivingPaused else {
				self.updateAdvertisementState(.paused)
				return
			}
			self.updateAdvertisementState(.starting)
			self.startTCPListener()
		}
	}

	public func setReceivingPaused(_ paused: Bool) {
		stateQueue.async {
			guard self.receivingPaused != paused else {
				if paused { self.updateAdvertisementState(.paused) }
				return
			}
			self.receivingPaused = paused
			UserDefaults.standard.set(paused, forKey: ReceivingPausePolicy.preferenceKey)
			if paused {
				self.receivingCodeExpiry?.cancel()
				self.receivingCodeExpiry = nil
				self.receivingCode = nil

				let pendingIDs = ReceivingPausePolicy.sessionsToCancel(
					activeIDs: Set(self.activeConnections.keys),
					approvedIDs: self.approvedInboundTransferIDs,
					isPaused: true
				)
				for id in pendingIDs {
					guard let connection = self.activeConnections[id] else { continue }
					NearbyConnection.connectionQueue.async {
						connection.lastError = NearbyError.receivingPaused
						connection.disconnect()
					}
					self.approvedInboundTransferIDs.remove(id)
				}

				let previousService = self.mdnsService
				self.mdnsService = nil
				previousService?.delegate = nil
				previousService?.remove(from: .main, forMode: .default)
				previousService?.stop()

				if let listener = self.tcpListener {
					let listenerWasStarted = self.tcpListenerHasStarted
					self.tcpListener = nil
					self.tcpListenerUsesFixedPort = false
					let waitForCancellation: Bool
					switch listener.state {
					case .waiting, .ready:
						waitForCancellation = true
					case .setup:
						waitForCancellation = true
					case .failed, .cancelled:
						waitForCancellation = false
					@unknown default:
						waitForCancellation = true
					}
					self.tcpListenerHasStarted = false
					if !waitForCancellation {
						listener.stateUpdateHandler = nil
						listener.newConnectionHandler = nil
						listener.cancel()
						self.listenerCancellationID = nil
						self.cancellingListener = nil
					} else {
						let cancellationID = UUID()
						self.listenerCancellationID = cancellationID
						self.cancellingListener = listener
						// Listener events are delivered on stateQueue, so this callback can update manager state directly.
						listener.stateUpdateHandler = { [self] state in
							switch state {
							case .cancelled, .failed:
								guard self.listenerCancellationID == cancellationID else { return }
								self.cancellingListener?.stateUpdateHandler = nil
								self.listenerCancellationID = nil
								self.cancellingListener = nil
								if self.receivingPaused {
									self.updateAdvertisementState(.paused)
								} else {
									self.startReceivingListenerOnStateQueue()
								}
							default:
								break
							}
						}
						listener.newConnectionHandler = nil
						if listener.state == .setup && !listenerWasStarted {
							listener.start(queue: self.stateQueue)
						}
						listener.cancel()
					}
				}
				self.updateAdvertisementState(.paused)
			} else {
				self.updateAdvertisementState(.starting)
				self.startReceivingListenerOnStateQueue()
			}
		}
	}

	private func startReceivingListenerOnStateQueue() {
		guard !receivingPaused else {
			updateAdvertisementState(.paused)
			return
		}
		guard listenerCancellationID == nil else {
			updateAdvertisementState(.starting)
			return
		}
		if tcpListener == nil || tcpListener?.state == .cancelled {
			createInboundListener()
		}
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
        stateQueue.async { [weak self] in
            guard let self=self else { return }
            guard ReceivingPausePolicy.mayAcceptNewSession(isPaused: self.receivingPaused) else {
                self.updateAdvertisementState(.paused)
                return
            }
			guard self.listenerCancellationID == nil else { return }
            guard let listener=self.tcpListener else { self.updateAdvertisementState(.failed); return }
            if listener.state == .ready {
                if self.mdnsService == nil { self.initMDNS() }
                return
            }
            guard listener.state == .setup else {
                self.updateAdvertisementState(.failed)
                return
            }
			listener.stateUpdateHandler={(state:NWListener.State) in
				self.stateQueue.async {
                    guard self.tcpListener === listener else { return }
					switch state{
					case .ready:
						NearbyLogger.log("[NearByDrop] TCP listener ready on port \(String(describing: self.tcpListener?.port?.rawValue))")
						self.initMDNS()

					case let .failed(error):
						NearbyLogger.log("[NearByDrop] TCP listener failed: \(error)")
						if self.tcpListener === listener,
						   self.tcpListenerUsesFixedPort,
						   case NWError.posix(.EADDRINUSE) = error {
							listener.stateUpdateHandler = nil
							listener.newConnectionHandler = nil
							self.tcpListener = nil
							self.tcpListenerUsesFixedPort = false
							listener.cancel()
							self.createInboundListener(preferFixedPort: false)
							self.startTCPListener()
						} else {
							self.updateAdvertisementState(.failed)
						}
					default:
						break
					}
				}
			}
			listener.newConnectionHandler={(connection:NWConnection) in
				self.stateQueue.async {
					guard ReceivingPausePolicy.mayAcceptNewSession(isPaused: self.receivingPaused) else {
						NearbyLogger.log("[NearByDrop] Rejected inbound connection while receiving is paused")
						connection.cancel()
						return
					}
					guard self.activeConnections.count < Self.maxActiveConnections else {
						NearbyLogger.log("[NearByDrop] Rejected inbound connection: max connections reached")
						connection.cancel()
						return
					}
					let id=UUID().uuidString
					NearbyLogger.log("[NearByDrop] Inbound TCP connection accepted")
					let conn=InboundNearbyConnection(connection: connection, id: id)
					conn.qrSenderPublicKey=self.receivingCode?.publicKey
                    conn.qrReceiverCode=self.receivingCode
					self.activeConnections[id]=conn
					conn.delegate=self
					conn.start()
				}
			}
			listener.start(queue: self.stateQueue)
			self.tcpListenerHasStarted = true
        }
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
        guard !receivingPaused, mdnsService == nil else { return }
		let nameBytes:[UInt8]=[
			0x23, // PCP
			endpointID[0], endpointID[1], endpointID[2], endpointID[3],
			0xFC, 0x9F, 0x5E, // Service ID hash
			0, 0
		]
		let name=Data(nameBytes).urlSafeBase64EncodedString()
		
		guard let listener=tcpListener, let port=listener.port else { return }
		let service=NetService(domain: "", type: "_FC9F5ED42C8A._tcp.", name: name, port: Int32(port.rawValue))
		service.delegate=self
		service.setTXTRecord(advertisementRecord())
		service.schedule(in: .main, forMode: .default)
		mdnsService=service
		service.publish()
	}

	public func netServiceDidPublish(_ sender: NetService){
		stateQueue.async {
			guard sender === self.mdnsService else { return }
			NearbyLogger.log("[NearByDrop] Bonjour advertisement published")
			self.updateAdvertisementState(.published)
		}
	}

	public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]){
        stateQueue.async {
        guard sender === self.mdnsService else { return }
#if DEBUG
		NearbyLogger.log("[NearByDrop] Bonjour advertisement failed")
#endif
		self.updateAdvertisementState(.failed)
        }
	}

	public func netServiceDidStop(_ sender: NetService){
		stateQueue.async {
			guard sender === self.mdnsService else { return }
			self.updateAdvertisementState(.failed)
		}
	}
	
	func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo, connection: InboundNearbyConnection) {
		stateQueue.async {
			guard let delegate=self._mainAppDelegate else { return }
			DispatchQueue.main.async { delegate.obtainUserConsent(for: transfer, from: device) }
		}
	}
	
	func inboundTransferProgress(connection: InboundNearbyConnection, id: String, bytesTransferred: Int64, totalBytes: Int64) {
		stateQueue.async {
			guard let delegate=self._mainAppDelegate else { return }
			DispatchQueue.main.async { delegate.incomingTransferProgress(id: id, bytesTransferred: bytesTransferred, totalBytes: totalBytes) }
		}
	}

	func connectionWasTerminated(connection:InboundNearbyConnection, error:Error?){
		stateQueue.async {
			self.activeConnections.removeValue(forKey: connection.id)
			self.approvedInboundTransferIDs.remove(connection.id)
			guard let delegate=self._mainAppDelegate else { return }
			DispatchQueue.main.async { delegate.incomingTransfer(id: connection.id, didFinishWith: error) }
		}
	}
	
	public func submitUserConsent(transferID:String, accept:Bool){
		stateQueue.async {
			guard let connection = self.activeConnections[transferID] else { return }
			if !ReceivingPausePolicy.mayHonorConsent(accepted: accept, isPaused: self.receivingPaused) {
				connection.submitUserConsent(accepted: false)
				return
			}
			if accept {
				self.approvedInboundTransferIDs.insert(transferID)
			} else {
				self.approvedInboundTransferIDs.remove(transferID)
			}
			connection.submitUserConsent(accepted: accept)
		}
	}

	public func cancelIncomingTransfer(id: String) {
		stateQueue.async {
			self.approvedInboundTransferIDs.remove(id)
			if let connection=self.activeConnections[id] {
                NearbyConnection.connectionQueue.async {
						connection.lastError=NearbyError.canceled(reason: .userCanceled)
                    connection.disconnect()
                }
            }
		}
	}

	public func startDeviceDiscovery(){
		stateQueue.async { [weak self] in
			guard let self=self else { return }
			if self.discoveryRefCount==0{
				self.foundServices.removeAll()
				if self.browser==nil{
					self.browser=NWBrowser(for: .bonjourWithTXTRecord(type: "_FC9F5ED42C8A._tcp.", domain: nil), using: .tcp)
					self.browser?.browseResultsChangedHandler={ [weak self] _, changes in
						guard let self=self else { return }
						self.stateQueue.async {
							for change in changes{
								switch change{
								case let .added(res), let .changed(old: _, new: res, flags: _):
									self.maybeAddFoundDevice(service: res)
								case let .removed(res):
									self.maybeRemoveFoundDevice(service: res)
								default:
									break
								}
							}
						}
					}
				}
				self.browser?.start(queue: self.stateQueue)
			}
			self.discoveryRefCount+=1
		}
	}
	
	public func stopDeviceDiscovery(){
		stateQueue.async {
			guard self.discoveryRefCount > 0 else { return }
			self.discoveryRefCount-=1
			if self.discoveryRefCount==0{
				self.browser?.cancel()
				self.browser=nil
			}
		}
	}
	
	public func addShareExtensionDelegate(_ delegate:ShareExtensionDelegate){
		stateQueue.async {
			self.shareExtensionDelegates.append(delegate)
			let devices=self.foundServices.values.compactMap(\.device)
			DispatchQueue.main.async { devices.forEach { delegate.addDevice(device: $0) } }
		}
	}
	
	public func removeShareExtensionDelegate(_ delegate:ShareExtensionDelegate){
		stateQueue.async { self.shareExtensionDelegates.removeAll(where: {$0===delegate}) }
	}
	
	public func cancelOutgoingTransfer(id:String){
		stateQueue.async {
			guard var transfer = self.outgoingTransfers.removeValue(forKey: id) else { return }
            transfer.cancelled=true
            transfer.connection.cancel()
        }
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
			NearbyLogger.log("[NearByDrop] Found a nearby service")
		#endif
		for interface in service.interfaces{
			if case .loopback=interface.type{
				#if DEBUG
				NearbyLogger.log("[NearByDrop] Ignored a local service")
				#endif
				return
			}
		}
		guard let endpointID=endpointID(for: service), endpointID != String(bytes: self.endpointID, encoding: .ascii) else {return}
		#if DEBUG
			NearbyLogger.log("[NearByDrop] Nearby service metadata parsed")
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
		
		if let qrData=endpointInfo.qrCodeData, let qrCodeAdvertisingToken=qrCodeAdvertisingToken{
#if DEBUG
			NearbyLogger.log("[NearByDrop] Nearby service has QR pairing metadata")
#endif
			if qrData==qrCodeAdvertisingToken{
				let targetDevice = deviceInfo ?? addFoundDevice(foundService: &foundService, endpointInfo: endpointInfo, endpointID: endpointID)
				for delegate in shareExtensionDelegates{
					DispatchQueue.main.async { delegate.startTransferWithQrCode(device: targetDevice) }
				}
			}else if qrData.count>28{
				do{
					let box=try AES.GCM.SealedBox(combined: qrData)
					guard let qrCodeNameEncryptionKey=qrCodeNameEncryptionKey else { return }
					let decryptedName=try AES.GCM.open(box, using: qrCodeNameEncryptionKey, authenticating: qrCodeAdvertisingToken)
					guard let name=String.init(data: decryptedName, encoding: .utf8) else {return}
					endpointInfo.name=name
					let deviceInfo=addFoundDevice(foundService: &foundService, endpointInfo: endpointInfo, endpointID: endpointID)
					for delegate in shareExtensionDelegates{
						DispatchQueue.main.async { delegate.startTransferWithQrCode(device: deviceInfo) }
					}
				}catch{
#if DEBUG
					NearbyLogger.log("[NearByDrop] Could not decrypt nearby QR metadata")
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
			DispatchQueue.main.async { delegate.addDevice(device: deviceInfo) }
		}
		return deviceInfo
	}
	
	private func maybeRemoveFoundDevice(service:NWBrowser.Result){
		guard let endpointID=endpointID(for: service) else {return}
		guard let _=foundServices.removeValue(forKey: endpointID) else {return}
		for delegate in shareExtensionDelegates {
			DispatchQueue.main.async { delegate.removeDevice(id: endpointID) }
		}
	}
	
	public func generateQrCodeKey() -> String{
		stateQueue.sync {
			let privKey=P256.Signing.PrivateKey()
			qrCodePrivateKey=privKey
			var keyData=Data([0, 0])
			keyData.append(privKey.publicKey.compressedRepresentation)
			let ikm=SymmetricKey(data: keyData)
			qrCodeAdvertisingToken=NearbyConnection.hkdf(inputKeyMaterial: ikm, salt: Data(), info: "advertisingContext".data(using: .utf8)!, outputByteCount: 16).data()
			qrCodeNameEncryptionKey=NearbyConnection.hkdf(inputKeyMaterial: ikm, salt: Data(), info: "encryptionKey".data(using: .utf8)!, outputByteCount: 16)
			qrCodeData=keyData
			return keyData.urlSafeBase64EncodedString()
		}
	}
	
	public func clearQrCodeKey(){
		stateQueue.sync {
			qrCodePrivateKey=nil
			qrCodeAdvertisingToken=nil
			qrCodeNameEncryptionKey=nil
			qrCodeData=nil
		}
	}
	
	public func startOutgoingTransfer(deviceID:String, delegate:ShareExtensionDelegate, urls:[URL], displayNames:[String]?=nil, fileIdentities:[TransferFileIdentity]?=nil){
		stateQueue.async {
			guard urls.filter(\.isFileURL).count <= TransferFileSafety.maximumFileCount else {
				DispatchQueue.main.async {
					delegate.connectionFailed(with: NearbyError.protocolError("Quick Share supports up to \(TransferFileSafety.maximumFileCount) files per transfer. Select fewer files and try again."))
				}
				return
			}
			guard let info=self.foundServices[deviceID] else {
				DispatchQueue.main.async { delegate.connectionFailed(with: NearbyError.protocolError("Device is no longer reachable")) }
				return
			}
			guard self.outgoingTransfers[deviceID] == nil else {
				DispatchQueue.main.async { delegate.connectionFailed(with: NearbyError.protocolError("A transfer to this device is already active")) }
				return
			}
			guard self.outgoingTransfers.count < Self.maxActiveConnections else {
				DispatchQueue.main.async { delegate.connectionFailed(with: NearbyError.protocolError("Too many active transfers")) }
				return
			}
			let tcp=NWProtocolTCP.Options()
			tcp.noDelay=true
			tcp.enableKeepalive=true
			tcp.keepaliveIdle=2
			let params=NWParameters(tls: .none, tcp: tcp)
			params.serviceClass = .responsiveData
			params.preferNoProxies=true
			let nwconn=NWConnection(to: info.service.endpoint, using: params)
			let conn=OutboundNearbyConnection(connection: nwconn, id: deviceID, urlsToSend: urls, displayNames: displayNames, fileIdentities: fileIdentities)
			conn.delegate=self
			conn.qrCodePrivateKey=self.qrCodePrivateKey
			let targetDevice = info.device ?? RemoteDeviceInfo(name: "Android Phone", type: .phone, id: deviceID)
			let transfer=OutgoingTransferInfo(service: info.service, device: targetDevice, connection: conn, delegate: delegate)
			self.outgoingTransfers[deviceID]=transfer
			conn.start()
		}
	}
	
	func outboundConnectionWasEstablished(connection: OutboundNearbyConnection) {
		stateQueue.async {
			guard let transfer=self.outgoingTransfers[connection.id], transfer.connection === connection, !transfer.cancelled else { return }
			guard let pinCode=connection.pinCode else {
				self.outgoingTransfers.removeValue(forKey: connection.id)
				DispatchQueue.main.async { transfer.delegate.connectionFailed(with: NearbyError.protocolError("Missing connection authentication")) }
				connection.cancel()
				return
			}
			DispatchQueue.main.async { transfer.delegate.connectionWasEstablished(pinCode: pinCode) }
		}
	}

	func outboundConnectionTransferAccepted(connection: OutboundNearbyConnection) {
		stateQueue.async {
			guard let transfer=self.outgoingTransfers[connection.id], transfer.connection === connection, !transfer.cancelled else { return }
			DispatchQueue.main.async { transfer.delegate.transferAccepted() }
		}
	}

	func outboundConnection(connection: OutboundNearbyConnection, transferProgress: Double) {
		stateQueue.async {
			guard let transfer=self.outgoingTransfers[connection.id], transfer.connection === connection, !transfer.cancelled else { return }
			DispatchQueue.main.async { transfer.delegate.transferProgress(progress: transferProgress) }
		}
	}

	func outboundConnection(connection: OutboundNearbyConnection, failedWithError: Error) {
		stateQueue.async {
			guard let transfer=self.outgoingTransfers[connection.id], transfer.connection === connection else { return }
			self.outgoingTransfers.removeValue(forKey: connection.id)
            guard !transfer.cancelled else { return }
			DispatchQueue.main.async { transfer.delegate.connectionFailed(with: failedWithError) }
		}
	}

	func outboundConnectionTransferFinished(connection: OutboundNearbyConnection) {
		stateQueue.async {
			guard let transfer=self.outgoingTransfers[connection.id], transfer.connection === connection else { return }
			self.outgoingTransfers.removeValue(forKey: connection.id)
            guard !transfer.cancelled else { return }
			DispatchQueue.main.async { transfer.delegate.transferFinished() }
		}
	}

	// MARK: - BLE Discovery Scanner (0xFE2C)

	public func startBLEScanning(){
		stateQueue.async {
			if self.centralManager == nil {
				self.centralManager = CBCentralManager(delegate: self, queue: self.stateQueue)
			} else if self.centralManager?.state == .poweredOn && !(self.centralManager?.isScanning ?? false) {
				self.centralManager?.scanForPeripherals(withServices: [NearbyConnectionManager.quickShareServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
			}
		}
	}

	public func stopBLEScanning(){
		stateQueue.async {
			if self.centralManager?.isScanning == true { self.centralManager?.stopScan() }
		}
	}

	public func centralManagerDidUpdateState(_ central: CBCentralManager){
		stateQueue.async {
			if central.state == .poweredOn {
				central.scanForPeripherals(withServices: [NearbyConnectionManager.quickShareServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
			}
		}
	}

	public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber){
		stateQueue.async {
			let now = Date()
			if let last = self.lastBLEDiscoveryTime, now.timeIntervalSince(last) < 2.0 { return }
			self.lastBLEDiscoveryTime = now
			#if DEBUG
			NearbyLogger.log("[NearByDrop] Discovered a Quick Share BLE beacon")
			#endif
			if self.mdnsService == nil { self.initMDNS() }
		}
	}
}

public struct QuickShareCode {
    let publicKey: P256.Signing.PublicKey
    let advertisingToken: Data
    private let authenticationKey: SymmetricKey

    func receiverHandshakeData(authToken: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: authToken, using: authenticationKey).prefix(16))
    }

    public init(_ value:String) throws {
        guard value.utf8.count < 512,
              let url=URLComponents(string: value), url.scheme == "https",
              (url.host == "quickshare.google" || url.host == "www.quickshare.google"),
              (url.path == "/qrcode" || url.path == "/qrcode/") else {
            throw NearbyError.protocolError("This is not a Quick Share QR code.")
        }
        let fragmentItems = URLComponents(string: "?" + (url.percentEncodedFragment ?? ""))?.queryItems ?? []
        let keys = (fragmentItems + (url.queryItems ?? [])).filter { $0.name == "key" }
        guard keys.count == 1, let encoded = keys[0].value, encoded.count == 47,
              encoded.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              let data=Data(base64Encoded: encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="),
              data.count == 35, data[0] == 0, data[1] == 0, data[2] == 2 || data[2] == 3 else {
            throw NearbyError.protocolError("This Quick Share code is invalid or unsupported.")
        }
        authenticationKey=HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: data), salt: Data(), info: Data("authKey".utf8), outputByteCount: 16)
        publicKey=try P256.Signing.PublicKey(compressedRepresentation: data.dropFirst(2))
        advertisingToken=HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: data), salt: Data(), info: Data("advertisingContext".utf8), outputByteCount: 16).withUnsafeBytes { Data($0) }
    }
}
