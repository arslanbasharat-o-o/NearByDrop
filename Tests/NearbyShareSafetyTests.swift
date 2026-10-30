import XCTest
@testable import NearbyShare
import Darwin

final class NearbyShareSafetyTests: XCTestCase {
    func testWindowsBinaryEndpointNameIsPreserved() throws {
        // Field 2 is length-delimited even though Google labels it as a string.
        let wire=Data([0x12, 0x03, 0x06, 0xFF, 0x80])
        let request=try Location_Nearby_Connections_ConnectionRequestFrame(serializedData: wire)
        XCTAssertEqual(request.endpointName, Data([0x06, 0xFF, 0x80]))
        XCTAssertEqual(try request.serializedData(), wire)
    }

    func testFrameLengthRejectsMalformedHeaders() {
        XCTAssertNil(NearbyConnection.frameLength(from: Data()))
        XCTAssertNil(NearbyConnection.frameLength(from: Data([0, 0, 0])))
        XCTAssertNil(NearbyConnection.frameLength(from: Data([0, 0, 0, 0])))
        XCTAssertNil(NearbyConnection.frameLength(from: Data([0x00, 0x50, 0x00, 0x01])))
        XCTAssertEqual(NearbyConnection.frameLength(from: Data([0, 0, 0, 1])), 1)
    }

    func testPayloadRangeRejectsNegativeAndOverflowingChunks() {
        XCTAssertTrue(NearbyConnection.isValidPayloadRange(totalSize: 10, offset: 0, bodyCount: 10))
        XCTAssertTrue(NearbyConnection.isValidPayloadRange(totalSize: 10, offset: 10, bodyCount: 0))
        XCTAssertFalse(NearbyConnection.isValidPayloadRange(totalSize: -1, offset: 0, bodyCount: 0))
        XCTAssertFalse(NearbyConnection.isValidPayloadRange(totalSize: 10, offset: -1, bodyCount: 0))
        XCTAssertFalse(NearbyConnection.isValidPayloadRange(totalSize: 10, offset: 9, bodyCount: 2))
    }

    func testURLSafeBase64RejectsGarbage() {
        XCTAssertNil(Data.dataFromUrlSafeBase64("not valid base64!"))
        XCTAssertEqual(Data([0x01, 0xFE, 0xFF]).urlSafeBase64EncodedString(), "Af7_")
    }
}

import Network
import CryptoKit

final class TransferLoopbackTests: XCTestCase, InboundNearbyConnectionDelegate, OutboundNearbyConnectionDelegate {
    private var received: XCTestExpectation!
    private var sent: XCTestExpectation!
    private var inbound: InboundNearbyConnection?
    private var outbound: OutboundNearbyConnection?
    private var destinations: [URL] = []
    private var lastReceivedBytes: Int64 = 0
    private var cancelAfterAcceptance = false
    private var rejectQR = false
    private var rejectIncoming = false
    private var duplicateIntroduction = false
    private var prematureURLPayload = false
    private var earlyResponse = false
    private var safeDisconnectOnly = false
    private var legacyCloseOnly = false
    private var dataTransferStarted: Date?
    private var dataTransferFinished: Date?
    private var consentRequestCount = 0
    private var expectedPeerName: String?
    private var expectedPeerID: String?
    private var replaceFirstSourceWithSymlinkAfterApproval = false
    private var firstOutboundFile: URL?
    private var replacementTargetURL: URL?

    func testExplicitApprovalCompletesEncryptedFilesAndEmptyFileRoundTrip() throws {
        try runRoundTrip()
        XCTAssertEqual(consentRequestCount, 1)
    }
    func testUntrustedSenderReachesManualConsentFlow() throws {
        try runRoundTrip(payloadSize: 64 * 1024)
        XCTAssertEqual(consentRequestCount, 1)
    }
    func testLegacyTrustedNameDoesNotBypassConsent() throws {
        let (name, _) = senderIdentity()
        try runRoundTrip(payloadSize: 64 * 1024, trustedEntries: [name], expectedName: name)
        XCTAssertEqual(consentRequestCount, 1)
    }
    func testLegacyTrustWithChangedEndpointIDDoesNotBypassConsent() throws {
        let (name, endpointID) = senderIdentity()
        let staleEndpointID = "stale-\(endpointID)"
        XCTAssertNotEqual(endpointID, staleEndpointID)
        try runRoundTrip(
            payloadSize: 64 * 1024,
            trustedEntries: ["\(name)#\(staleEndpointID)"],
            expectedName: name,
            expectedID: endpointID
        )
        XCTAssertEqual(consentRequestCount, 1)
    }
    func testMatchingCompositeTrustDoesNotAuthorizeUnverifiedSender() throws {
        let (name, endpointID) = senderIdentity()
        try runRoundTrip(
            payloadSize: 64 * 1024,
            trustedEntries: ["\(name)#\(endpointID)"],
            expectedName: name,
            expectedID: endpointID
        )
        XCTAssertEqual(consentRequestCount, 1)
    }
    func testDeclinedTransferWritesNoFilesAndClearsConsentState() throws {
        rejectIncoming = true
        try runRoundTrip(payloadSize: 64 * 1024)
        XCTAssertEqual(consentRequestCount, 1)
    }
    func testDuplicateIntroductionCannotReplaceConsentMetadata() throws {
        duplicateIntroduction = true
        try runRoundTrip(payloadSize: 64 * 1024)
        XCTAssertEqual(consentRequestCount, 1)
    }
    func testURLPayloadBeforeApprovalIsNotOpened() throws {
        prematureURLPayload = true
        try runRoundTrip(prematureURLPayload: true)
    }
    func testLargeEncryptedTransferThroughput() throws { try runRoundTrip(payloadSize: 64 * 1024 * 1024) }
    func testReceiverCanCompleteWithCleanSocketClose() throws {
        legacyCloseOnly = true
        try runRoundTrip()
    }
    func testReceiverCanConfirmThroughSafeDisconnect() throws {
        safeDisconnectOnly = true
        try runRoundTrip()
    }
    func testEarlyQRConnectionResponseRoundTrip() throws {
        earlyResponse = true
        try runRoundTrip(qr: true)
    }
    func testQRAuthenticationStillRequiresAndCompletesManualApproval() throws {
        try runRoundTrip(qr: true)
        XCTAssertEqual(consentRequestCount, 1)
    }
    func testQRRejectsADifferentSenderKey() throws {
        rejectQR = true
        try runRoundTrip(qr: true)
        XCTAssertEqual(consentRequestCount, 0)
    }
    func testCancellationRemovesPartialFiles() throws {
        cancelAfterAcceptance = true
        try runRoundTrip()
    }
    func testOutboundPathRejectsFileReplacedWithSymlinkBeforeOpening() throws {
        replaceFirstSourceWithSymlinkAfterApproval = true
        try runRoundTrip(payloadSize: 64 * 1024)
    }

    private func senderIdentity() -> (name: String, endpointID: String) {
        let manager = NearbyConnectionManager.shared
        let endpointID = String(bytes: manager.endpointID, encoding: .ascii) ?? "ABCD"
        return (NearbyConnectionManager.currentDeviceName, endpointID)
    }

    private func runRoundTrip(
        qr: Bool = false,
        payloadSize: Int = 8 * 1024 * 1024,
        trustedEntries: [String] = [],
        expectedName: String? = nil,
        expectedID: String? = nil,
        prematureURLPayload: Bool = false
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloads = root.appendingPathComponent("received")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let oldPath = UserDefaults.standard.object(forKey: "downloadDirectoryURL")
        let oldBookmark = UserDefaults.standard.object(forKey: "downloadDirectoryBookmark")
        let oldTrustedEntries = UserDefaults.standard.object(forKey: "trustedDevices")
        UserDefaults.standard.set(trustedEntries, forKey: "trustedDevices")
        expectedPeerName = expectedName
        expectedPeerID = expectedID
        consentRequestCount = 0
        destinations = []
        defer {
            UserDefaults.standard.set(oldPath, forKey: "downloadDirectoryURL")
            UserDefaults.standard.set(oldBookmark, forKey: "downloadDirectoryBookmark")
            if let oldTrustedEntries {
                UserDefaults.standard.set(oldTrustedEntries, forKey: "trustedDevices")
            } else {
                UserDefaults.standard.removeObject(forKey: "trustedDevices")
            }
            try? FileManager.default.removeItem(at: root)
        }
        NearbyConnectionManager.downloadDirectory = downloads
        let payload = Data((0..<payloadSize).map { UInt8(truncatingIfNeeded: $0) })
        let file = root.appendingPathComponent("payload.bin")
        firstOutboundFile = file
        let replacementTarget = root.appendingPathComponent("outside-target.bin")
        replacementTargetURL = replacementTarget
        try Data("outside target".utf8).write(to: replacementTarget)
        let empty = root.appendingPathComponent("empty.txt")
        try payload.write(to: file)
        try Data().write(to: empty)
        received = expectation(description: "Receiver completed")
        sent = expectation(description: "Sender completed")
        let qrKey = qr ? P256.Signing.PrivateKey() : nil
        let listener = try NWListener(using: .tcp, on: .any)
        defer { listener.cancel(); inbound = nil; outbound = nil }
        listener.newConnectionHandler = { connection in
            let inbound = IndexedInboundConnection(connection: connection, id: "test-incoming")
            inbound.reorderHandshake = self.earlyResponse
            inbound.safeDisconnectOnly = self.safeDisconnectOnly
            inbound.legacyCloseOnly = self.legacyCloseOnly
            inbound.qrSenderPublicKey = self.rejectQR ? P256.Signing.PrivateKey().publicKey : qrKey?.publicKey
            if let qrKey {
                let keyData=Data([0, 0])+qrKey.publicKey.compressedRepresentation
                inbound.qrReceiverCode=try! QuickShareCode("https://quickshare.google/qrcode#key=\(keyData.urlSafeBase64EncodedString())")
            }
            inbound.delegate = self
            self.inbound = inbound
            inbound.start()
        }
        listener.stateUpdateHandler = { state in
            guard state == .ready, let port = listener.port else { return }
            let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            let urlsToSend = prematureURLPayload ? [URL(string: "https://example.invalid")!] : [file, empty]
            let outbound = OutboundNearbyConnection(connection: connection, id: "test-outgoing", urlsToSend: urlsToSend)
            outbound.qrCodePrivateKey = qrKey
            outbound.delegate = self
            self.outbound = outbound
            outbound.start()
        }
        let start = Date()
        listener.start(queue: .main)
        wait(for: [received, sent], timeout: 30)
        if cancelAfterAcceptance || rejectQR || rejectIncoming || duplicateIntroduction || prematureURLPayload || replaceFirstSourceWithSymlinkAfterApproval {
            if rejectQR { XCTAssertTrue(destinations.isEmpty) }
            if rejectIncoming {
                XCTAssertEqual(consentRequestCount, 1)
                XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: downloads.path).isEmpty)
            }
            if duplicateIntroduction { XCTAssertEqual(consentRequestCount, 1) }
            if prematureURLPayload {
                XCTAssertEqual(consentRequestCount, 1)
                XCTAssertEqual((inbound as? IndexedInboundConnection)?.openedURLCount, 0)
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: downloads.path).isEmpty)
            return
        }
        XCTAssertEqual(lastReceivedBytes, Int64(payload.count))
        XCTAssertEqual(destinations.count, 2)
        XCTAssertEqual(try Data(contentsOf: downloads.appendingPathComponent("payload.bin")), payload)
        XCTAssertEqual(try Data(contentsOf: downloads.appendingPathComponent("empty.txt")), Data())
        print("Encrypted loopback: \(payload.count) bytes plus empty file in \(Date().timeIntervalSince(start)) seconds")
        if let started = dataTransferStarted, let finished = dataTransferFinished {
            print("Encrypted data throughput: \(Double(payload.count) / finished.timeIntervalSince(started) / 1_000_000) MB/s")
        }
    }

    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo, connection: InboundNearbyConnection) {
        consentRequestCount += 1
        if let expectedPeerName { XCTAssertEqual(device.name, expectedPeerName) }
        if let expectedPeerID { XCTAssertEqual(device.id, expectedPeerID) }
        destinations = transfer.files.compactMap(\.destinationURL)
        for destination in destinations {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "Files must not be created before explicit consent")
        }
        if duplicateIntroduction {
            if consentRequestCount == 1 {
                var duplicate = Sharing_Nearby_Frame()
                duplicate.version = .v1
                duplicate.v1.type = .introduction
                duplicate.v1.introduction.startTransfer = true
                duplicate.v1.introduction.useCase = .nearbyShare
                var file = Sharing_Nearby_FileMetadata()
                file.id = 999
                file.name = "unapproved.bin"
                file.size = 1
                file.mimeType = "application/octet-stream"
                file.payloadID = Int64.random(in: Int64.min...Int64.max)
                duplicate.v1.introduction.fileMetadata = [file]
                do { try outbound?.sendTransferSetupFrame(duplicate) }
                catch { XCTFail("Could not send duplicate introduction: \(error)") }
            } else {
                connection.submitUserConsent(accepted: false)
            }
            return
        }
        if prematureURLPayload {
            guard let payloadID = (connection as? IndexedInboundConnection)?.latestTextPayloadID,
                  let outbound else {
                XCTFail("The URL introduction must expose a test payload ID")
                return
            }
            do { try outbound.sendBytesPayload(data: Data("https://example.invalid".utf8), id: payloadID) }
            catch { XCTFail("Could not send premature URL payload: \(error)") }
            return
        }
        if rejectIncoming {
            connection.submitUserConsent(accepted: false)
            return
        }
        NearbyConnection.connectionQueue.async {
            var acknowledgement = Location_Nearby_Connections_OfflineFrame()
            acknowledgement.version = .v1
            acknowledgement.v1.type = .payloadTransfer
            acknowledgement.v1.payloadTransfer.packetType = .payloadAck
            acknowledgement.v1.payloadTransfer.payloadHeader.id = 0
            do { try connection.encryptAndSendOfflineFrame(acknowledgement) }
            catch { XCTFail(error.localizedDescription) }
            connection.submitUserConsent(accepted: true)
        }
    }
    func inboundTransferProgress(connection: InboundNearbyConnection, id: String, bytesTransferred: Int64, totalBytes: Int64) {
        XCTAssertLessThanOrEqual(bytesTransferred, totalBytes)
        XCTAssertGreaterThanOrEqual(bytesTransferred, lastReceivedBytes)
        lastReceivedBytes = bytesTransferred
    }
    func connectionWasTerminated(connection: InboundNearbyConnection, error: Error?) {
        dataTransferFinished = Date()
        if rejectQR {
            XCTAssertTrue(String(describing: error).contains("does not match the scanned QR code"))
        } else if rejectIncoming {
            XCTAssertNotNil(error)
        } else if duplicateIntroduction || prematureURLPayload || replaceFirstSourceWithSymlinkAfterApproval {
            XCTAssertNotNil(error)
        } else if cancelAfterAcceptance { XCTAssertNotNil(error) }
        else { XCTAssertNil(error) }
        received.fulfill()
    }
    func outboundConnectionWasEstablished(connection: OutboundNearbyConnection) {}
    func outboundConnection(connection: OutboundNearbyConnection, transferProgress: Double) {}
    func outboundConnectionTransferAccepted(connection: OutboundNearbyConnection) {
        dataTransferStarted = Date()
        if cancelAfterAcceptance { connection.cancel() }
        if replaceFirstSourceWithSymlinkAfterApproval,
           let firstOutboundFile, let replacementTargetURL {
            do {
                try FileManager.default.removeItem(at: firstOutboundFile)
                try FileManager.default.createSymbolicLink(at: firstOutboundFile, withDestinationURL: replacementTargetURL)
            } catch {
                XCTFail("Could not replace the source fixture: \(error)")
            }
        }
    }
    func outboundConnection(connection: OutboundNearbyConnection, failedWithError: Error) {
        if !cancelAfterAcceptance && !rejectQR && !rejectIncoming && !duplicateIntroduction && !prematureURLPayload && !replaceFirstSourceWithSymlinkAfterApproval {
            XCTFail(failedWithError.localizedDescription)
        }
        sent.fulfill()
    }
    func outboundConnectionTransferFinished(connection: OutboundNearbyConnection) { sent.fulfill() }
}

final class TransferFileSafetyTests: XCTestCase {
    func testEmptyFoldersAndUnreadableFilesAreExplained() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let emptyFolder = root.appendingPathComponent("empty", isDirectory: true)
        let unreadableFile = root.appendingPathComponent("unreadable.txt")
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: unreadableFile)
        defer {
            _ = unreadableFile.path.withCString { Darwin.chmod($0, mode_t(0o600)) }
            try? FileManager.default.removeItem(at: root)
        }

        XCTAssertEqual(unreadableFile.path.withCString { Darwin.chmod($0, mode_t(0)) }, 0)
        let probe = unreadableFile.path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
        if probe >= 0 {
            Darwin.close(probe)
            throw XCTSkip("The test runner can read files despite cleared POSIX permissions.")
        }

        let selection = TransferFileSafety.expandSelection([emptyFolder, unreadableFile])
        XCTAssertTrue(selection.urls.isEmpty)
        XCTAssertEqual(selection.skipped.unreadable, 1)
        XCTAssertTrue(selection.emptyMessage.contains("No transferable files remain"))
        XCTAssertTrue(selection.emptyMessage.contains("1 unreadable item was skipped"))
    }

    func testFolderExpansionSkipsEverySymlinkWithoutFollowingIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("選択", isDirectory: true)
        let nested = folder.appendingPathComponent("子", isDirectory: true)
        let outside = root.appendingPathComponent("outside.txt")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("valid".utf8).write(to: nested.appendingPathComponent("naïve-🛰️.txt"))
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("external-file"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("internal-file"), withDestinationURL: nested.appendingPathComponent("naïve-🛰️.txt"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("external-dir"), withDestinationURL: root)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("dangling"), withDestinationURL: root.appendingPathComponent("missing"))
        let cycle = folder.appendingPathComponent("cycle")
        try FileManager.default.createSymbolicLink(at: cycle, withDestinationURL: cycle)

        let selection = TransferFileSafety.expandSelection([folder])
        XCTAssertEqual(selection.urls, [nested.appendingPathComponent("naïve-🛰️.txt")])
        XCTAssertEqual(selection.displayNames, ["選択/子/naïve-🛰️.txt"])
        XCTAssertEqual(selection.skipped.symbolicLinks, 5)
        XCTAssertEqual(selection.identities.count, 1)
        XCTAssertTrue(selection.skipped.message?.contains("5 symbolic links were skipped for safety.") == true)
    }

    func testExplicitSymlinkRootsAreExcluded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("file.txt")
        try Data("file".utf8).write(to: file)
        let fileLink = root.appendingPathComponent("file-link")
        let directoryLink = root.appendingPathComponent("directory-link")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: file)
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: folder)
        defer { try? FileManager.default.removeItem(at: root) }

        let selection = TransferFileSafety.expandSelection([fileLink, directoryLink])
        XCTAssertTrue(selection.urls.isEmpty)
        XCTAssertEqual(selection.skipped.symbolicLinks, 2)
        XCTAssertTrue(selection.emptyMessage.contains("No transferable files remain"))
    }

    func testSourceReplacementAfterSelectionIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.bin")
        let target = root.appendingPathComponent("target.bin")
        try Data("source".utf8).write(to: source)
        try Data("target".utf8).write(to: target)
        defer { try? FileManager.default.removeItem(at: root) }

        let identity = try TransferFileSafety.readableIdentity(at: source)
        try FileManager.default.removeItem(at: source)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: target)
        XCTAssertThrowsError(try TransferFileSafety.openReadOnlyFile(at: source, expected: identity))
    }

    func testInPlaceSourceEditAfterSelectionIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.bin")
        try Data("original".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        let identity = try TransferFileSafety.readableIdentity(at: source)
        Thread.sleep(forTimeInterval: 0.002)
        let writer = try FileHandle(forWritingTo: source)
        try writer.write(contentsOf: Data("modified".utf8))
        try writer.close()
        let changedIdentity = try TransferFileSafety.readableIdentity(at: source)
        XCTAssertEqual(changedIdentity.device, identity.device)
        XCTAssertEqual(changedIdentity.inode, identity.inode)
        XCTAssertEqual(changedIdentity.size, identity.size)
        XCTAssertNotEqual(changedIdentity, identity)
        XCTAssertThrowsError(try TransferFileSafety.openReadOnlyFile(at: source, expected: identity))
    }

    func testFileSelectionCountBoundariesAndLargeFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(TransferFileSafety.expandSelection([]).urls.count, 0)
        for count in [1, 128, 129, 1_000] {
            let batch = root.appendingPathComponent("batch-\(count)", isDirectory: true)
            try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
            for index in 0..<count {
                try Data().write(to: batch.appendingPathComponent("\(index).bin"))
            }
            let selection = TransferFileSafety.expandSelection([batch])
            XCTAssertEqual(selection.urls.count, count)
            XCTAssertEqual(selection.identities.count, count)
        }
        XCTAssertEqual(TransferFileSafety.maximumFileCount, 128)
    }
}

final class OutgoingTransferPreflightTests: XCTestCase {
    func test129FilesFailManagerPreflightBeforeDeviceLookup() {
        let delegate = PreflightShareExtensionDelegate()
        let urls = (0..<129).map { URL(fileURLWithPath: "/nonexistent/\($0).bin") }
        NearbyConnectionManager.shared.startOutgoingTransfer(
            deviceID: "unavailable-device",
            delegate: delegate,
            urls: urls
        )
        wait(for: [delegate.failed], timeout: 5)
        XCTAssertTrue(delegate.error?.localizedDescription.contains("up to 128 files") == true)
    }

    func test128FilesReachDeviceLookupWithoutBeingTruncated() {
        let delegate = PreflightShareExtensionDelegate()
        let urls = (0..<128).map { URL(fileURLWithPath: "/nonexistent/\($0).bin") }
        NearbyConnectionManager.shared.startOutgoingTransfer(
            deviceID: "unavailable-device",
            delegate: delegate,
            urls: urls
        )
        wait(for: [delegate.failed], timeout: 5)
        XCTAssertTrue(delegate.error?.localizedDescription.contains("no longer reachable") == true)
    }
}

private final class PreflightShareExtensionDelegate: ShareExtensionDelegate {
    let failed = XCTestExpectation(description: "Preflight failure delivered")
    private(set) var error: Error?

    func addDevice(device: RemoteDeviceInfo) {}
    func removeDevice(id: String) {}
    func startTransferWithQrCode(device: RemoteDeviceInfo) {}
    func connectionWasEstablished(pinCode: String) {}
    func connectionFailed(with error: Error) { self.error = error; failed.fulfill() }
    func transferAccepted() {}
    func transferProgress(progress: Double) {}
    func transferFinished() {}
}

final class AppSupportTests: XCTestCase {
    func testReceiveProgressIsScopedToEachTransfer() {
        let start = Date(timeIntervalSince1970: 0)
        let first = ReceiveProgress(bytes: 1024, total: 2048, started: start, updated: start.addingTimeInterval(1))
        let second = ReceiveProgress(bytes: 0, total: 4096, started: start, updated: start)
        XCTAssertEqual(first.fraction, 0.5)
        XCTAssertEqual(first.bytesPerSecond, 1024)
        XCTAssertEqual(second.fraction, 0)
        XCTAssertEqual(second.bytesPerSecond, 0)
        XCTAssertNil(ReceiveProgress().fraction)
    }


    func testPhoneFoldersCannotEscapeOrMerge() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try ReceivedFolder.create(in: root, name: "Photos")
        let second = try ReceivedFolder.create(in: root, name: "Photos")
        XCTAssertNotEqual(first, second)
        let escaped = try ReceivedFolder.create(in: root, name: "../../outside")
        XCTAssertEqual(escaped.deletingLastPathComponent().standardizedFileURL, root.standardizedFileURL)
        let dot = try ReceivedFolder.create(in: root, name: "..")
        XCTAssertEqual(dot.lastPathComponent, "Received folder")
        let link = root.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        XCTAssertNotEqual(try ReceivedFolder.create(in: root, name: "Link"), link)
    }
}

final class TrustedDevicePreferenceMigrationTests: XCTestCase {
    func testLegacyTrustEntriesAreInvalidatedOnRepeatedLaunches() throws {
        let suiteName = "TrustedDevicePreferenceMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(["Known Phone", "Known Phone#old-endpoint", "Known Phone#new-endpoint"], forKey: "trustedDevices")
        NearbyConnectionManager.invalidateLegacyTrustedDevices(in: defaults)
        XCTAssertNil(defaults.object(forKey: "trustedDevices"))

        // A repeated launch, including a value restored by a downgraded build,
        // invalidates the same unsafe preference again.
        defaults.set(["Known Phone"], forKey: "trustedDevices")
        NearbyConnectionManager.invalidateLegacyTrustedDevices(in: defaults)
        XCTAssertNil(defaults.object(forKey: "trustedDevices"))
    }
}

final class IncomingConsentPresentationStateTests: XCTestCase {
    func testDeclineRemovesPendingRequestAndApprovalState() {
        var incoming = ["transfer-1": "metadata"]
        var progress = ["transfer-1": "pending"]
        var accepted: Set<String> = []

        IncomingConsentPresentationState.applyDecision(
            transferID: "transfer-1",
            accepted: false,
            incoming: &incoming,
            progress: &progress,
            acceptedIDs: &accepted
        )

        XCTAssertTrue(incoming.isEmpty)
        XCTAssertTrue(progress.isEmpty)
        XCTAssertTrue(accepted.isEmpty)
    }

    func testApprovedTransferStaysVisibleUntilCompletionThenResets() {
        var incoming = ["transfer-1": "metadata"]
        var progress = ["transfer-1": "receiving"]
        var accepted: Set<String> = []

        IncomingConsentPresentationState.applyDecision(
            transferID: "transfer-1",
            accepted: true,
            incoming: &incoming,
            progress: &progress,
            acceptedIDs: &accepted
        )
        XCTAssertNotNil(incoming["transfer-1"])
        XCTAssertNotNil(progress["transfer-1"])
        XCTAssertTrue(accepted.contains("transfer-1"))

        IncomingConsentPresentationState.finish(
            transferID: "transfer-1",
            incoming: &incoming,
            progress: &progress,
            acceptedIDs: &accepted
        )
        XCTAssertTrue(incoming.isEmpty)
        XCTAssertTrue(progress.isEmpty)
        XCTAssertTrue(accepted.isEmpty)
    }
}

final class QRScannerLifetimeTests: XCTestCase {
    func testScannerCanStopAndDeallocateRepeatedly() {
        let released = expectation(description: "Scanner released after queued shutdown")
        weak var lastScanner: QRScanner?
        for _ in 0..<25 {
            autoreleasepool {
                let scanner = QRScanner()
                lastScanner = scanner
                scanner.stop()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertNil(lastScanner)
            released.fulfill()
        }
        wait(for: [released], timeout: 3)
    }
}

final class HandshakeKeyEncodingTests: XCTestCase {
    private final class Sender: OutboundNearbyConnection {
        var frames: [Data] = []
        override func sendFrameAsync(_ frame: Data, completion: (() -> Void)? = nil, failure: ((Error) -> Void)? = nil) {
            frames.append(frame)
        }
    }

    private final class Receiver: InboundNearbyConnection {
        var frames: [Data] = []
        override func sendFrameAsync(_ frame: Data, completion: (() -> Void)? = nil, failure: ((Error) -> Void)? = nil) {
            frames.append(frame)
        }
    }

    func testBothHandshakePublicKeysUsePositiveSignedCoordinates() throws {
        try NearbyConnection.connectionQueue.sync {
            for _ in 0..<32 {
                let sender = Sender(connection: NWConnection(host: "127.0.0.1", port: 9, using: .tcp), id: "key-sender", urlsToSend: [])
                let receiver = Receiver(connection: NWConnection(host: "127.0.0.1", port: 9, using: .tcp), id: "key-receiver")
                defer { sender.handleConnectionClosure(); receiver.handleConnectionClosure() }
                sender.connectionReady()
                XCTAssertEqual(sender.frames.count, 2)
                for frame in sender.frames { receiver.processReceivedFrame(frameData: frame) }
                XCTAssertNil(receiver.lastError)
                let serverFrame = try XCTUnwrap(receiver.frames.first)
                let serverMessage = try Securegcm_Ukey2Message(serializedData: serverFrame)
                let serverInit = try Securegcm_Ukey2ServerInit(serializedData: serverMessage.messageData)
                try checkCoordinates(serverInit.publicKey, connection: receiver)

                sender.processReceivedFrame(frameData: serverFrame)
                XCTAssertNil(sender.lastError)
                let finishMessage = try Securegcm_Ukey2Message(serializedData: sender.frames[2])
                let finish = try Securegcm_Ukey2ClientFinished(serializedData: finishMessage.messageData)
                try checkCoordinates(finish.publicKey, connection: sender)
                receiver.processReceivedFrame(frameData: sender.frames[2])
                XCTAssertNil(receiver.lastError)
                XCTAssertEqual(sender.pinCode, receiver.pinCode)
            }
        }
    }

    private func checkCoordinates(_ encodedKey: Data, connection: NearbyConnection) throws {
        let key = try Securemessage_GenericPublicKey(serializedData: encodedKey)
        let localKey = try XCTUnwrap(connection.publicKey)
        for (encoded, magnitude) in [(key.ecP256PublicKey.x, localKey.w.x.asMagnitudeBytes()),
                                     (key.ecP256PublicKey.y, localKey.w.y.asMagnitudeBytes())] {
            XCTAssertFalse(encoded.isEmpty)
            XCTAssertLessThan(try XCTUnwrap(encoded.first), 0x80, "Android interprets a high sign bit as a negative coordinate")
            XCTAssertEqual(Array(encoded.drop(while: { $0 == 0 })), Array(magnitude.drop(while: { $0 == 0 })))
        }
    }
}

import CoreImage.CIFilterBuiltins
import Vision

final class QuickShareCodeTests: XCTestCase {
    private let key = "AAADaxfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpY"

    func testQRScanRefreshesDiscoveryIdentity() throws {
        let manager=NearbyConnectionManager.shared
        let previous=manager.endpointID
        defer { manager.stopReceivingQRCode() }
        try manager.receiveQRCode("https://quickshare.google/qrcode#key=\(key)")
        XCTAssertNotEqual(manager.endpointID, previous)
    }
    func testQRAdvertisementUsesVersionOneAndPreservesToken() throws {
        let token=try QuickShareCode("https://quickshare.google/qrcode#key=\(key)").advertisingToken
        let data=EndpointInfo(name: "Mac", deviceType: .computer, qrCodeData: token).serialize()
        XCTAssertEqual(data[0] >> 5, 1)
        XCTAssertEqual(EndpointInfo(data: data)?.qrCodeData, token)
    }
    func testReceiverQRProofMatchesAndroidFormat() throws {
        let code=try QuickShareCode("https://quickshare.google/qrcode#key=\(key)")
        let proof=code.receiverHandshakeData(authToken: Data(0..<32))
        XCTAssertEqual(proof.hexEncodedString(), "1a875b60edd48c0342b475727d56f238")
        XCTAssertNotEqual(proof, code.receiverHandshakeData(authToken: Data(1...32)))
    }

    func testKnownCodeAndAdvertisingToken() throws {
        let code = try QuickShareCode("https://quickshare.google/qrcode#key=\(key)")
        XCTAssertEqual(code.advertisingToken.hexEncodedString(), "b81f9de8c5eca923f12b153bcaf4a068")
        XCTAssertEqual(try QuickShareCode("https://quickshare.google/qrcode?key=\(key)").advertisingToken, code.advertisingToken)
        XCTAssertEqual(try QuickShareCode("https://quickshare.google/qrcode#source=camera&key=\(key)").advertisingToken, code.advertisingToken)
    }

    func testInvalidAndAmbiguousCodesAreRejected() {
        for value in [
            "https://quickshare.google/qrcode#monkey=\(key)",
            "https://quickshare.google/qrcode#key=\(key)&key=\(key)",
            "https://quickshare.google/qrcode?key=\(key)#key=\(key)",
            "https://quickshare.google.example.com/qrcode#key=\(key)",
            "http://quickshare.google/qrcode#key=\(key)",
            "https://quickshare.google/qrcode#key=invalid"
        ] { XCTAssertThrowsError(try QuickShareCode(value), value) }
    }

    func testGeneratedQRCodeImageCanBeDecoded() throws {
        let manager = NearbyConnectionManager.shared
        let value = "https://quickshare.google/qrcode#key=\(manager.generateQrCodeKey())"
        defer { manager.clearQrCodeKey() }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        let output = try XCTUnwrap(filter.outputImage).transformed(by: .init(scaleX: 8, y: 8))
        let image = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let decoded = try XCTUnwrap(request.results?.first?.payloadStringValue)
        XCTAssertEqual(decoded, value)
        XCTAssertNoThrow(try QuickShareCode(decoded))
    }

    func testScannerAllowsRetryingTheSameRejectedCode() {
        let scanner = QRScanner()
        var attempts = 0
        scanner.onCode = { _ in
            attempts += 1
            return "Try again"
        }
        scanner.handleCode("same-code")
        scanner.handleCode("same-code")
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(scanner.message, "Try again")
    }
}

final class PayloadControlTests: XCTestCase {
    func testAcknowledgementsDoNotRequireDataChunks() throws {
        var frame = Location_Nearby_Connections_PayloadTransferFrame()
        frame.packetType = .payloadAck
        XCTAssertTrue(try NearbyConnection.isPayloadControl(frame))
        frame.packetType = .control
        frame.controlMessage.event = .payloadReceivedAck
        XCTAssertTrue(try NearbyConnection.isPayloadControl(frame))
        frame.controlMessage.event = .payloadError
        XCTAssertThrowsError(try NearbyConnection.isPayloadControl(frame))
        frame.controlMessage.event = .payloadCanceled
        XCTAssertThrowsError(try NearbyConnection.isPayloadControl(frame))
        frame.packetType = .data
        XCTAssertFalse(try NearbyConnection.isPayloadControl(frame))
    }
}

private final class IndexedInboundConnection: InboundNearbyConnection {
    var reorderHandshake = false
    private var heldClientFinish: Data?
    private(set) var latestTextPayloadID: Int64?
    private(set) var openedURLCount = 0
    override func processReceivedFrame(frameData: Data) {
        if reorderHandshake,
           let frame=try? Securegcm_Ukey2Message(serializedData: frameData),
           frame.hasMessageType, frame.messageType == .clientFinish {
            heldClientFinish=frameData
            return
        }
        super.processReceivedFrame(frameData: frameData)
        if let held=heldClientFinish {
            heldClientFinish=nil
            reorderHandshake=false
            super.processReceivedFrame(frameData: held)
        }
    }

    var safeDisconnectOnly = false
    var legacyCloseOnly = false
    override func sendTransferSetupFrame(_ frame: Sharing_Nearby_Frame, completion: (() -> Void)? = nil, failure: ((Error) -> Void)? = nil) throws {
        if frame.v1.type == .pairedKeyEncryption, let code=qrReceiverCode {
            XCTAssertEqual(frame.v1.pairedKeyEncryption.qrCodeHandshakeData, code.receiverHandshakeData(authToken: try XCTUnwrap(authKey).data()))
        }
        try super.sendTransferSetupFrame(frame, completion: completion, failure: failure)
    }

    override func processTransferSetupFrame(_ frame: Sharing_Nearby_Frame) throws {
        if frame.v1.type == .introduction {
            XCTAssertTrue(frame.v1.introduction.startTransfer)
            XCTAssertEqual(frame.v1.introduction.useCase, .nearbyShare)
            let ids = frame.v1.introduction.fileMetadata.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count)
            XCTAssertFalse(ids.contains(0))
            latestTextPayloadID = frame.v1.introduction.textMetadata.first?.payloadID
        }
        try super.processTransferSetupFrame(frame)
    }
    override func openReceivedURL(_ url: URL) {
        openedURLCount += 1
    }
    override func acknowledgePayload(_ header: Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader) throws {
        if !safeDisconnectOnly && !legacyCloseOnly { try super.acknowledgePayload(header) }
    }
    override func sendDisconnectionAndDisconnect(completion: (() -> Void)? = nil) throws {
        guard safeDisconnectOnly else { try super.sendDisconnectionAndDisconnect(completion: completion); return }
        var frame = Location_Nearby_Connections_OfflineFrame()
        frame.version = .v1
        frame.v1.type = .disconnection
        frame.v1.disconnection.requestSafeToDisconnect = true
        try encryptAndSendOfflineFrame(frame, completion: completion)
    }

    private var nextIndex: [Int64: Int32] = [:]
    override func processFileChunk(frame: Location_Nearby_Connections_PayloadTransferFrame) throws {
        let id = frame.payloadHeader.id
        XCTAssertTrue(frame.payloadHeader.hasFileName)
        XCTAssertFalse(frame.payloadHeader.fileName.isEmpty)
        XCTAssertTrue(frame.payloadChunk.hasIndex)
        XCTAssertEqual(frame.payloadChunk.index, nextIndex[id, default: 0])
        nextIndex[id, default: 0] += 1
        if frame.payloadChunk.flags == 1 {
            var update = Sharing_Nearby_Frame()
            update.version = .v1
            update.v1.type = .progressUpdate
            update.v1.progressUpdate.progress = 1
            try sendTransferSetupFrame(update)
        }
        try super.processFileChunk(frame: frame)
    }
}


final class AppUpdaterTests: XCTestCase {
    func testInstallationWaitsForTransferThenResumes() {
        let updater = AppUpdater()
        updater.canInstall = { false }
        var installations = 0
        updater.showReady(toInstallAndRelaunch: { _ in installations += 1 })
        XCTAssertEqual(installations, 0)
        XCTAssertFalse(updater.busy)
        updater.install()
        XCTAssertEqual(installations, 0)
        updater.canInstall = { true }
        updater.install()
        XCTAssertEqual(installations, 1)
        updater.install()
        XCTAssertEqual(installations, 1)
    }
    func testTerminationCanBeRetriedAfterTransferFinishes() {
        let updater = AppUpdater()
        updater.canInstall = { false }
        var retries = 0
        updater.showInstallingUpdate(withApplicationTerminated: false, retryTerminatingApplication: { retries += 1 })
        XCTAssertFalse(updater.busy)
        updater.install()
        XCTAssertEqual(retries, 0)
        updater.canInstall = { true }
        updater.install()
        XCTAssertEqual(retries, 1)
        XCTAssertTrue(updater.busy)
    }
    func testFailureClearsBusyStateAndAcknowledges() {
        let updater = AppUpdater()
        updater.showDownloadInitiated(cancellation: {})
        XCTAssertTrue(updater.busy)
        var acknowledged = false
        updater.showUpdaterError(NSError(domain: "test", code: 1), acknowledgement: { acknowledged = true })
        XCTAssertTrue(acknowledged)
        XCTAssertFalse(updater.busy)
        XCTAssertNil(updater.version)
        XCTAssertTrue(updater.message.hasPrefix("Update failed:"))
    }
}
