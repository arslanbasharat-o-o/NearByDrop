//
//  ShareViewController.swift
//  ShareExtension
//
//

import Foundation
import Cocoa
import UniformTypeIdentifiers
import os
import NearbyShare
import QRCode

class ShareViewController: NSViewController, ShareExtensionDelegate{
	private let logger = Logger(subsystem: "com.arslanbasharat.NearByDrop", category: "ShareExtension")
	
	private var urls:[URL]=[]
	private var foundDevices:[RemoteDeviceInfo]=[]
	private var chosenDevice:RemoteDeviceInfo?
	private var lastError:Error?
	private var sheetWindow:NSWindow?
	private var completionGeneration = 0
	
	@IBOutlet var filesIcon:NSImageView?
	@IBOutlet var filesLabel:NSTextField?
	@IBOutlet var loadingOverlay:NSStackView?
	@IBOutlet var largeProgress:NSProgressIndicator?
	@IBOutlet var listView:NSCollectionView?
	@IBOutlet var listViewWrapper:NSView?
	@IBOutlet var contentWrap:NSView?
	@IBOutlet var progressView:NSView?
	@IBOutlet var progressDeviceIcon:NSImageView?
	@IBOutlet var progressDeviceName:NSTextField?
	@IBOutlet var progressProgressBar:NSProgressIndicator?
	@IBOutlet var progressState:NSTextField?
	@IBOutlet var progressDeviceIconWrap:NSView?
	@IBOutlet var progressDeviceSecondaryIcon:NSImageView?
	@IBOutlet var qrCodeButton:NSButton?
	
	@IBOutlet var qrCodeSheetView:NSView?
	@IBOutlet var qrCodeView:NSImageView?
	@IBOutlet var qrCodeWrapView:NSView?
	
	override var nibName: NSNib.Name? {
		return NSNib.Name("ShareViewController")
	}

	override func loadView() {
		super.loadView()
	
		guard let item=self.extensionContext?.inputItems.first as? NSExtensionItem else {
			let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
			extensionContext?.cancelRequest(withError: cancelError)
			return
		}
		guard let contentWrap,
		      let listViewWrapper,
		      let loadingOverlay,
		      let progressView,
		      let largeProgress,
		      let listView,
		      let progressDeviceIconWrap,
		      let qrCodeWrapView else {
			let loadError = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: [NSLocalizedDescriptionKey: "The share extension interface could not be loaded."])
			extensionContext?.cancelRequest(withError: loadError)
			return
		}
		if let attachments = item.attachments, !attachments.isEmpty {
			var completedCount=0
			var loadError:Error?
			for attachment in attachments {
				let provider=attachment
				provider.loadItem(forTypeIdentifier: UTType.url.identifier) { data, err in
					DispatchQueue.main.async {
						completedCount+=1
						if let err=err {
							loadError=err
						}else if let urlData=data as? Data, let url=URL(dataRepresentation: urlData, relativeTo: nil, isAbsolute: false) {
							self.urls.append(url)
						}else if let url=data as? NSURL {
							self.urls.append(url as URL)
						}else if loadError==nil {
							loadError=NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [NSLocalizedDescriptionKey: "Unable to read the shared item"])
						}
						guard completedCount==attachments.count else { return }
						if let loadError=loadError {
							self.extensionContext?.cancelRequest(withError: loadError)
						}else{
							self.urlsReady()
						}
					}
				}
			}
		} else {
			let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
			self.extensionContext?.cancelRequest(withError: cancelError)
			return
		}
		
		contentWrap.addSubview(listViewWrapper)
		contentWrap.addSubview(loadingOverlay)
		contentWrap.addSubview(progressView)
		progressView.isHidden=true
		
		listViewWrapper.translatesAutoresizingMaskIntoConstraints=false
		loadingOverlay.translatesAutoresizingMaskIntoConstraints=false
		progressView.translatesAutoresizingMaskIntoConstraints=false
		NSLayoutConstraint.activate([
			NSLayoutConstraint(item: listViewWrapper, attribute: .width, relatedBy: .equal, toItem: contentWrap, attribute: .width, multiplier: 1, constant: 0),
			NSLayoutConstraint(item: listViewWrapper, attribute: .height, relatedBy: .equal, toItem: contentWrap, attribute: .height, multiplier: 1, constant: 0),
			
			NSLayoutConstraint(item: loadingOverlay, attribute: .width, relatedBy: .equal, toItem: contentWrap, attribute: .width, multiplier: 1, constant: 0),
			NSLayoutConstraint(item: loadingOverlay, attribute: .centerY, relatedBy: .equal, toItem: contentWrap, attribute: .centerY, multiplier: 1, constant: 0),
			
			NSLayoutConstraint(item: progressView, attribute: .width, relatedBy: .equal, toItem: contentWrap, attribute: .width, multiplier: 1, constant: 0),
			NSLayoutConstraint(item: progressView, attribute: .centerY, relatedBy: .equal, toItem: contentWrap, attribute: .centerY, multiplier: 1, constant: 0)
		])
		
		largeProgress.startAnimation(nil)
		let flowLayout=NSCollectionViewFlowLayout()
		flowLayout.itemSize=NSSize(width: 75, height: 90)
		flowLayout.sectionInset=NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
		flowLayout.minimumInteritemSpacing=10
		flowLayout.minimumLineSpacing=10
		listView.collectionViewLayout=flowLayout
		listView.dataSource=self
		listView.delegate=self
		listView.isSelectable=true
		
		progressDeviceIconWrap.wantsLayer=true
		progressDeviceIconWrap.layer?.masksToBounds=false
		
		qrCodeWrapView.wantsLayer=true
		qrCodeWrapView.layer?.masksToBounds=false
		qrCodeWrapView.layer?.shadowColor = .black
		qrCodeWrapView.layer?.shadowOpacity=0.3
		qrCodeWrapView.layer?.shadowRadius=12
		qrCodeWrapView.layer?.shadowOffset=CGSizeMake(0, -5)
	}
	
	override func viewDidLoad(){
		super.viewDidLoad()
		NearbyConnectionManager.shared.startDeviceDiscovery()
		NearbyConnectionManager.shared.addShareExtensionDelegate(self)
	}
	
	override func viewWillDisappear() {
		completionGeneration += 1
		if chosenDevice == nil {
			closeQrCodeSheet(clearKey: true)
		}
		if chosenDevice==nil{
			NearbyConnectionManager.shared.stopDeviceDiscovery()
		}
		NearbyConnectionManager.shared.removeShareExtensionDelegate(self)
	}

	@IBAction func cancel(_ sender: AnyObject?) {
		completionGeneration += 1
		closeQrCodeSheet(clearKey: true)
		if let device=chosenDevice, let id=device.id{
			NearbyConnectionManager.shared.cancelOutgoingTransfer(id: id)
		}
		let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
		extensionContext?.cancelRequest(withError: cancelError)
	}
	
	@IBAction func useQrCode(_ sender: AnyObject?) {
		guard let window=contentWrap?.window,
		      let qrCodeSheetView,
		      let qrCodeView else { return }
		closeQrCodeSheet(clearKey: true)
		let sheetWindow=NSWindow()
		sheetWindow.contentView=qrCodeSheetView
		let size=NSSize(width: 380, height: 400)
		sheetWindow.contentMaxSize=size
		sheetWindow.contentMinSize=size
		sheetWindow.setContentSize(size)
		
		let qrKey=NearbyConnectionManager.shared.generateQrCodeKey()
		do {
			let qrCodeImage=try QRCode.build
				.text("https://quickshare.google/qrcode#key=\(qrKey)")
				.backgroundColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0))
				.quietZonePixelCount(3)
				.onPixels.shape(.circle())
				.eye.shape(.roundedPointing())
				.errorCorrection(.low)
				.generate.image(dimension: max(1, Int(qrCodeView.frame.width) * 2))
			qrCodeView.image=NSImage(cgImage: qrCodeImage, size: qrCodeImage.size)
		} catch {
			NearbyConnectionManager.shared.clearQrCodeKey()
			let alert=NSAlert(error: error)
			if let window=view.window {
				alert.beginSheetModal(for: window)
			} else {
				alert.runModal()
			}
			return
		}
		
		self.sheetWindow=sheetWindow
		window.beginSheet(sheetWindow) { [weak self, weak sheetWindow] _ in
			guard let self, self.sheetWindow === sheetWindow else { return }
			self.sheetWindow=nil
			NearbyConnectionManager.shared.clearQrCodeKey()
		}
	}
	
	@IBAction func dismissQrCodeSheet(_ sender: AnyObject?){
		closeQrCodeSheet(clearKey: true)
	}

	private func closeQrCodeSheet(clearKey: Bool) {
		if let sheetWindow {
			if let parent=contentWrap?.window, parent.attachedSheet === sheetWindow {
				parent.endSheet(sheetWindow)
			}
			self.sheetWindow=nil
		}
		if clearKey {
			NearbyConnectionManager.shared.clearQrCodeKey()
		}
	}
	
	private func urlsReady(){
		for url in urls{
			if url.isFileURL{
				var isDirectory: ObjCBool = false
				if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue{
					logger.notice("Canceling share request because a directory was selected")
					let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
					extensionContext?.cancelRequest(withError: cancelError)
					return
				}
			}
		}
		if urls.count==1{
			if urls[0].isFileURL{
				filesLabel?.stringValue=urls[0].lastPathComponent
				filesIcon?.image=NSWorkspace.shared.icon(forFile: urls[0].path)
			}else if urls[0].scheme=="http" || urls[0].scheme=="https"{
				filesLabel?.stringValue=urls[0].absoluteString
				filesIcon?.image=NSImage(named: NSImage.networkName)
			}
		}else{
			filesLabel?.stringValue=String.localizedStringWithFormat(NSLocalizedString("NFiles", value: "%d files", comment: ""), urls.count)
			filesIcon?.image=NSImage(named: NSImage.multipleDocumentsName)
		}
	}
	
	func addDevice(device: RemoteDeviceInfo) {
		let key=device.id ?? "name:\(device.name)"
		if let index=foundDevices.firstIndex(where: { ($0.id ?? "name:\($0.name)") == key }) {
			foundDevices[index]=device
			listView?.reloadData()
			return
		}
		if foundDevices.isEmpty{
			loadingOverlay?.animator().isHidden=true
		}
		foundDevices.append(device)
		listView?.animator().insertItems(at: [[0, foundDevices.count-1]])
	}
	
	func removeDevice(id: String){
		if chosenDevice != nil{
			return
		}
		for i in foundDevices.indices{
			if foundDevices[i].id==id{
				foundDevices.remove(at: i)
				listView?.animator().deleteItems(at: [[0, i]])
				break
			}
		}
		if foundDevices.isEmpty{
			loadingOverlay?.animator().isHidden=false
		}
	}
	
	func startTransferWithQrCode(device: RemoteDeviceInfo){
		closeQrCodeSheet(clearKey: false)
		selectDevice(device: device)
	}
	
	func connectionWasEstablished(pinCode: String) {
		progressState?.stringValue=String(format:NSLocalizedString("PinCode", value: "PIN: %@", comment: ""), arguments: [pinCode])
		progressProgressBar?.isIndeterminate=false
		progressProgressBar?.maxValue=1000
		progressProgressBar?.doubleValue=0
	}
	
	func connectionFailed(with error: Error) {
		progressProgressBar?.isIndeterminate=false
		progressProgressBar?.maxValue=1000
		progressProgressBar?.doubleValue=0
		lastError=error
		if let ne=(error as? NearbyError), case let .canceled(reason)=ne{
			switch reason{
			case .userRejected:
				progressState?.stringValue=NSLocalizedString("TransferDeclined", value: "Declined", comment: "")
			case .userCanceled:
				progressState?.stringValue=NSLocalizedString("TransferCanceled", value: "Canceled", comment: "")
			case .notEnoughSpace:
				progressState?.stringValue=NSLocalizedString("NotEnoughSpace", value: "Not enough disk space", comment: "")
			case .unsupportedType:
				progressState?.stringValue=NSLocalizedString("UnsupportedType", value: "Attachment type not supported", comment: "")
			case .timedOut:
				progressState?.stringValue=NSLocalizedString("TransferTimedOut", value: "Timed out", comment: "")
			}
			progressDeviceSecondaryIcon?.isHidden=false
			dismissDelayed()
		}else{
			let alert=NSAlert(error: error)
			if let window=view.window {
				alert.beginSheetModal(for: window) { [weak self] _ in
					self?.extensionContext?.cancelRequest(withError: error)
				}
			} else {
				extensionContext?.cancelRequest(withError: error)
			}
		}
	}
	
	func transferAccepted() {
		progressState?.stringValue=NSLocalizedString("Sending", value: "Sending...", comment: "")
	}
	
	func transferProgress(progress: Double) {
		if let progressProgressBar {
			progressProgressBar.doubleValue=progress*progressProgressBar.maxValue
		}
	}
	
	func transferFinished() {
		lastError=nil
		progressState?.stringValue=NSLocalizedString("TransferFinished", value: "Transfer finished", comment: "")
		dismissDelayed()
	}
	
	func selectDevice(device:RemoteDeviceInfo){
		guard chosenDevice == nil, let deviceID=device.id else { return }
		NearbyConnectionManager.shared.stopDeviceDiscovery()
		listViewWrapper?.animator().isHidden=true
		progressView?.animator().isHidden=false
		qrCodeButton?.animator().isHidden=true
		progressDeviceName?.stringValue=device.name
		progressDeviceIcon?.image=imageForDeviceType(type: device.type)
		progressProgressBar?.startAnimation(nil)
		progressState?.stringValue=NSLocalizedString("Connecting", value: "Connecting...", comment: "")
		lastError=nil
		chosenDevice=device
		NearbyConnectionManager.shared.startOutgoingTransfer(deviceID: deviceID, delegate: self, urls: urls)
		NearbyConnectionManager.shared.clearQrCodeKey()
	}
	
	private func dismissDelayed(){
		completionGeneration += 1
		let generation=completionGeneration
		DispatchQueue.main.asyncAfter(deadline: .now()+2.0){ [weak self] in
			guard let self, self.completionGeneration == generation else { return }
			if let error=self.lastError{
				self.extensionContext?.cancelRequest(withError: error)
			}else{
				self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
			}
		}
	}
}

fileprivate func imageForDeviceType(type:RemoteDeviceInfo.DeviceType)->NSImage{
	let imageName:String
	switch type{
	case .tablet:
		imageName="com.apple.ipad"
	case .computer:
		imageName="com.apple.macbookpro-13-unibody"
	default: // also .phone
		imageName="com.apple.iphone"
	}
	return NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/\(imageName).icns") ?? NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 32, height: 32))
}

extension ShareViewController:NSCollectionViewDataSource{
	func numberOfSections(in collectionView: NSCollectionView) -> Int {
		return 1
	}
	
	func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
		return foundDevices.count
	}
	
	func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
		let item=collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DeviceListCell"), for: indexPath)
		let device=foundDevices[indexPath[1]]
		item.textField?.stringValue=device.name
		item.imageView?.image=imageForDeviceType(type: device.type)
		return item
	}
}

extension ShareViewController:NSCollectionViewDelegate{
	func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
		guard chosenDevice==nil, let indexPath=indexPaths.first else {
			return
		}
		selectDevice(device: foundDevices[indexPath.item])
	}
}
