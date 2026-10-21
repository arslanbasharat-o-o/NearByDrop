//
//  LocalFileShareServer.swift
//  NearByDrop
//
//  Created for rock-solid local Wi-Fi QR Code transfers from Mac to Android/iOS.
//

import Foundation
import Network
import Darwin
import NearbyShare

final class LocalFileShareServer: ObservableObject {
    static let shared = LocalFileShareServer()

    @Published var isRunning = false
    @Published var serverURL: URL?

    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var urls: [URL] = []
    private var displayNames: [String] = []
    private var tempZipURLs: [URL] = []

    private var speedSamples: [(time: Date, bytes: Int64)] = []
    private var onProgressCallback: ((Double, String, String) -> Void)?
    private var onCompletedCallback: ((String, Int64, URL?) -> Void)?
    private var onErrorCallback: ((String) -> Void)?

    private init() {}

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start(
        urls: [URL],
        displayNames: [String]? = nil,
        onProgress: @escaping (Double, String, String) -> Void,
        onCompleted: @escaping (String, Int64, URL?) -> Void,
        onError: @escaping (String) -> Void
    ) -> URL? {
        stop()

        guard !urls.isEmpty else {
            onError("No files selected to transfer.")
            return nil
        }

        guard let ip = getLocalIPv4Address() else {
            onError("No local network connection found. Please connect to Wi-Fi.")
            return nil
        }

        self.urls = urls
        self.displayNames = displayNames ?? []
        self.onProgressCallback = onProgress
        self.onCompletedCallback = onCompleted
        self.onErrorCallback = onError
        self.speedSamples.removeAll()

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2

        let params = NWParameters(tls: .none, tcp: tcpOptions)
        params.allowFastOpen = true
        params.preferNoProxies = true

        do {
            let listener = try NWListener(using: params, on: .any)
            self.listener = listener

            let sema = DispatchSemaphore(value: 0)
            var assignedPort: UInt16 = 0

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = self?.listener?.port?.rawValue {
                        assignedPort = port
                        sema.signal()
                    }
                case .failed(let err):
                    self?.onErrorCallback?("Local transfer server failed: \(err.localizedDescription)")
                    sema.signal()
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: .global(qos: .userInitiated))

            // Wait briefly for the listener to bind to a port
            _ = sema.wait(timeout: .now() + 1.5)

            guard assignedPort > 0, let url = URL(string: "http://\(ip):\(assignedPort)/") else {
                stop()
                onError("Failed to bind local server port.")
                return nil
            }

            DispatchQueue.main.async {
                self.serverURL = url
                self.isRunning = true
            }

            return url
        } catch {
            onError("Failed to start server: \(error.localizedDescription)")
            return nil
        }
    }

    func stop() {
        if let l = listener {
            l.stateUpdateHandler = nil
            l.newConnectionHandler = nil
            l.cancel()
            listener = nil
        }

        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()

        for zip in tempZipURLs {
            try? FileManager.default.removeItem(at: zip)
        }
        tempZipURLs.removeAll()

        urls.removeAll()
        displayNames.removeAll()
        speedSamples.removeAll()
        onProgressCallback = nil
        onCompletedCallback = nil
        onErrorCallback = nil

        DispatchQueue.main.async {
            self.isRunning = false
            self.serverURL = nil
        }
    }

    // MARK: - Local IP Discovery

    func getLocalIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidateInterfaces: [(name: String, ip: String)] = []

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ifName = String(cString: ptr.pointee.ifa_name)
                        let ip = String(cString: hostname)
                        candidateInterfaces.append((ifName, ip))
                    }
                }
            }
        }

        // Prefer standard macOS Wi-Fi interface (en0)
        if let wifi = candidateInterfaces.first(where: { $0.name == "en0" }) {
            return wifi.ip
        }
        // Then secondary Wi-Fi (en1)
        if let wifi2 = candidateInterfaces.first(where: { $0.name == "en1" }) {
            return wifi2.ip
        }
        // Otherwise any active non-loopback IPv4
        return candidateInterfaces.first?.ip
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let connection = connection else { return }
            if let error = error {
                connection.cancel()
                self.removeConnection(connection)
                return
            }
            guard let data = data, let req = String(data: data, encoding: .utf8) else {
                connection.cancel()
                self.removeConnection(connection)
                return
            }

            self.processHTTPRequest(req, on: connection)
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        activeConnections.removeAll { $0 === connection }
    }

    private func processHTTPRequest(_ request: String, on connection: NWConnection) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendHTTPResponse(status: 400, headers: ["Content-Type": "text/plain"], body: "Bad Request".data(using: .utf8)!, on: connection)
            return
        }

        let path = String(parts[1])

        if path == "/" || path == "/index.html" {
            let html = generateHTMLPage()
            sendHTTPResponse(
                status: 200,
                headers: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Cache-Control": "no-cache, no-store, must-revalidate"
                ],
                body: html.data(using: .utf8)!,
                on: connection
            )
        } else if path.hasPrefix("/download/") {
            let param = String(path.dropFirst("/download/".count))
            if param == "all" {
                handleDownloadAll(on: connection)
            } else if let index = Int(param), index >= 0, index < urls.count {
                handleDownloadSingle(index: index, on: connection)
            } else {
                sendHTTPResponse(status: 404, headers: ["Content-Type": "text/plain"], body: "File Not Found".data(using: .utf8)!, on: connection)
            }
        } else {
            sendHTTPResponse(status: 404, headers: ["Content-Type": "text/plain"], body: "Not Found".data(using: .utf8)!, on: connection)
        }
    }

    // MARK: - Downloads

    private func handleDownloadSingle(index: Int, on connection: NWConnection) {
        let url = urls[index]
        let displayName = (index < displayNames.count && !displayNames[index].isEmpty) ? displayNames[index] : url.lastPathComponent

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // Zip directory
            guard let zipURL = createZipArchive(for: [url], archiveName: "\(displayName).zip") else {
                sendHTTPResponse(status: 500, headers: ["Content-Type": "text/plain"], body: "Failed to package directory".data(using: .utf8)!, on: connection)
                return
            }
            streamFile(at: zipURL, downloadName: "\(displayName).zip", isTemporary: true, on: connection)
        } else {
            streamFile(at: url, downloadName: displayName, isTemporary: false, on: connection)
        }
    }

    private func handleDownloadAll(on connection: NWConnection) {
        if urls.count == 1 {
            handleDownloadSingle(index: 0, on: connection)
            return
        }

        let archiveName = "NearByDrop-\(urls.count)-files.zip"
        guard let zipURL = createZipArchive(for: urls, archiveName: archiveName) else {
            sendHTTPResponse(status: 500, headers: ["Content-Type": "text/plain"], body: "Failed to create ZIP".data(using: .utf8)!, on: connection)
            return
        }
        streamFile(at: zipURL, downloadName: archiveName, isTemporary: true, on: connection)
    }

    private func createZipArchive(for sources: [URL], archiveName: String) -> URL? {
        let tmp = FileManager.default.temporaryDirectory
        let staging = tmp.appendingPathComponent("staging_\(UUID().uuidString)")
        let zipURL = tmp.appendingPathComponent("pkg_\(UUID().uuidString)_\(archiveName)")

        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for (idx, src) in sources.enumerated() {
                let name = (idx < displayNames.count && !displayNames[idx].isEmpty) ? displayNames[idx] : src.lastPathComponent
                let dest = staging.appendingPathComponent(name)
                try? FileManager.default.linkItem(at: src, to: dest)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: src, to: dest)
                }
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", staging.path, zipURL.path]
            try process.run()
            process.waitUntilExit()

            try? FileManager.default.removeItem(at: staging)

            if FileManager.default.fileExists(atPath: zipURL.path) {
                tempZipURLs.append(zipURL)
                return zipURL
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
        }
        return nil
    }

    private func streamFile(at fileURL: URL, downloadName: String, isTemporary: Bool, on connection: NWConnection) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            sendHTTPResponse(status: 404, headers: ["Content-Type": "text/plain"], body: "File unreadable".data(using: .utf8)!, on: connection)
            return
        }

        let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let totalSize = (attr?[.size] as? Int64) ?? 0

        let mime = mimeType(for: fileURL)
        let percentName = downloadName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? downloadName
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nContent-Length: \(totalSize)\r\nContent-Disposition: attachment; filename=\"\(downloadName)\"; filename*=UTF-8''\(percentName)\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"

        speedSamples.removeAll()

        connection.send(content: header.data(using: .utf8), completion: .contentProcessed { [weak self, weak connection] err in
            guard let self = self, let connection = connection, err == nil else {
                try? handle.close()
                if isTemporary { try? FileManager.default.removeItem(at: fileURL) }
                return
            }

            self.streamNextChunk(
                handle: handle,
                totalSize: totalSize,
                sentBytes: 0,
                downloadName: downloadName,
                fileURL: fileURL,
                isTemporary: isTemporary,
                connection: connection
            )
        })
    }

    private func streamNextChunk(
        handle: FileHandle,
        totalSize: Int64,
        sentBytes: Int64,
        downloadName: String,
        fileURL: URL,
        isTemporary: Bool,
        connection: NWConnection
    ) {
        let chunkSize = 131072 // 128 KB
        let chunk = handle.readData(ofLength: chunkSize)

        if chunk.isEmpty {
            try? handle.close()
            connection.cancel()
            removeConnection(connection)
            if isTemporary { try? FileManager.default.removeItem(at: fileURL) }

            DispatchQueue.main.async { [weak self] in
                self?.onProgressCallback?(1.0, "Complete", "")
                self?.onCompletedCallback?(downloadName, totalSize, isTemporary ? nil : fileURL)
            }
            return
        }

        connection.send(content: chunk, completion: .contentProcessed { [weak self, weak connection] err in
            guard let self = self, let connection = connection, err == nil else {
                try? handle.close()
                connection?.cancel()
                if let conn = connection { self?.removeConnection(conn) }
                if isTemporary { try? FileManager.default.removeItem(at: fileURL) }
                return
            }

            let newSent = sentBytes + Int64(chunk.count)
            self.trackSpeed(sentBytes: newSent, totalSize: totalSize)

            self.streamNextChunk(
                handle: handle,
                totalSize: totalSize,
                sentBytes: newSent,
                downloadName: downloadName,
                fileURL: fileURL,
                isTemporary: isTemporary,
                connection: connection
            )
        })
    }

    private func trackSpeed(sentBytes: Int64, totalSize: Int64) {
        let now = Date()
        speedSamples.append((now, sentBytes))
        speedSamples.removeAll { now.timeIntervalSince($0.time) > 2.0 }

        guard speedSamples.count >= 2, let first = speedSamples.first, let last = speedSamples.last else { return }
        let duration = last.time.timeIntervalSince(first.time)
        guard duration > 0.1 else { return }

        let bytesPerSec = Double(last.bytes - first.bytes) / duration
        let speedStr: String
        if bytesPerSec >= 1_048_576 {
            speedStr = String(format: "%.1f MB/s", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1024 {
            speedStr = String(format: "%.0f KB/s", bytesPerSec / 1024)
        } else {
            speedStr = String(format: "%.0f B/s", bytesPerSec)
        }

        let remainingBytes = max(0, totalSize - sentBytes)
        let etaStr: String
        if bytesPerSec > 0 && remainingBytes > 0 {
            let seconds = Int(Double(remainingBytes) / bytesPerSec)
            etaStr = seconds < 60 ? "\(seconds)s left" : "\(seconds / 60)m \(seconds % 60)s left"
        } else {
            etaStr = "Finishing…"
        }

        let progress = totalSize > 0 ? Double(sentBytes) / Double(totalSize) : 0

        DispatchQueue.main.async { [weak self] in
            self?.onProgressCallback?(progress, speedStr, etaStr)
        }
    }

    private func sendHTTPResponse(status: Int, headers: [String: String], body: Data, on connection: NWConnection) {
        var headerStr = "HTTP/1.1 \(status) \(statusDescription(status))\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (k, v) in headers {
            headerStr += "\(k): \(v)\r\n"
        }
        headerStr += "\r\n"

        var fullData = headerStr.data(using: .utf8)!
        fullData.append(body)

        connection.send(content: fullData, completion: .contentProcessed { [weak self, weak connection] _ in
            connection?.cancel()
            if let conn = connection { self?.removeConnection(conn) }
        })
    }

    private func statusDescription(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Response"
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }

    // MARK: - HTML Generation

    private func generateHTMLPage() -> String {
        let senderName = NearbyConnectionManager.currentDeviceName
        var itemsHTML = ""
        var totalBytes: Int64 = 0

        for (idx, url) in urls.enumerated() {
            let name = (idx < displayNames.count && !displayNames[idx].isEmpty) ? displayNames[idx] : url.lastPathComponent
            let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attr?[.size] as? Int64) ?? 0
            totalBytes += size
            let formattedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

            itemsHTML += """
            <div class="file-item">
                <div class="file-info">
                    <div class="file-icon">📄</div>
                    <div>
                        <div class="file-name">\(name)</div>
                        <div class="file-size">\(formattedSize)</div>
                    </div>
                </div>
                <a class="btn-download" href="/download/\(idx)" onclick="markDownloading(this)">Download</a>
            </div>
            """
        }

        let totalFormatted = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let downloadAllButton = urls.count > 1 ? """
        <a class="btn-download-all" href="/download/all" onclick="markDownloading(this)">Download All (\(totalFormatted))</a>
        """ : ""

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
            <title>NearByDrop - Receive Files</title>
            <style>
                :root {
                    --bg: #0F172A;
                    --card: #1E293B;
                    --border: #334155;
                    --text: #F8FAFC;
                    --text-secondary: #94A3B8;
                    --primary: #22C55E;
                    --primary-hover: #16A34A;
                    --accent: #3B82F6;
                }
                @media (prefers-color-scheme: light) {
                    :root {
                        --bg: #F8FAFC;
                        --card: #FFFFFF;
                        --border: #E2E8F0;
                        --text: #0F172A;
                        --text-secondary: #64748B;
                        --primary: #16A34A;
                        --primary-hover: #15803D;
                        --accent: #2563EB;
                    }
                }
                * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
                body {
                    background-color: var(--bg);
                    color: var(--text);
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    padding: 20px;
                }
                .container {
                    width: 100%;
                    max-width: 440px;
                    background: var(--card);
                    border: 1px solid var(--border);
                    border-radius: 24px;
                    padding: 28px 24px;
                    box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.1), 0 8px 10px -6px rgba(0, 0, 0, 0.1);
                    text-align: center;
                }
                .header-icon {
                    width: 56px;
                    height: 56px;
                    background: rgba(34, 197, 94, 0.12);
                    color: var(--primary);
                    border-radius: 50%;
                    display: inline-flex;
                    align-items: center;
                    justify-content: center;
                    margin-bottom: 16px;
                    font-size: 26px;
                }
                h1 { font-size: 22px; font-weight: 700; margin-bottom: 6px; }
                p.sender { color: var(--text-secondary); font-size: 14px; margin-bottom: 24px; }
                .files-box {
                    border: 1px solid var(--border);
                    border-radius: 16px;
                    overflow: hidden;
                    margin-bottom: 20px;
                    text-align: left;
                }
                .file-item {
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    padding: 14px 16px;
                    border-bottom: 1px solid var(--border);
                }
                .file-item:last-child { border-bottom: none; }
                .file-info { display: flex; align-items: center; gap: 12px; overflow: hidden; }
                .file-icon { font-size: 22px; flex-shrink: 0; }
                .file-name {
                    font-size: 14px;
                    font-weight: 600;
                    white-space: nowrap;
                    overflow: hidden;
                    text-overflow: ellipsis;
                    max-width: 180px;
                }
                .file-size { font-size: 12px; color: var(--text-secondary); margin-top: 2px; }
                .btn-download {
                    background: rgba(59, 130, 246, 0.12);
                    color: var(--accent);
                    padding: 6px 14px;
                    border-radius: 12px;
                    font-size: 13px;
                    font-weight: 600;
                    text-decoration: none;
                    flex-shrink: 0;
                    transition: all 0.2s ease;
                }
                .btn-download:active { transform: scale(0.96); }
                .btn-download-all {
                    display: block;
                    background: var(--primary);
                    color: #FFFFFF;
                    padding: 14px;
                    border-radius: 14px;
                    font-size: 15px;
                    font-weight: 600;
                    text-decoration: none;
                    margin-bottom: 12px;
                    box-shadow: 0 4px 12px rgba(34, 197, 94, 0.25);
                    transition: all 0.2s ease;
                }
                .btn-download-all:active { transform: scale(0.98); background: var(--primary-hover); }
                .status-hint { font-size: 12px; color: var(--text-secondary); margin-top: 14px; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header-icon">↓</div>
                <h1>NearByDrop</h1>
                <p class="sender">Received from <strong>\(senderName)</strong></p>
                <div class="files-box">
                    \(itemsHTML)
                </div>
                \(downloadAllButton)
                <p class="status-hint">Files are transferred directly over your local Wi-Fi.</p>
            </div>
            <script>
                function markDownloading(el) {
                    el.innerText = "Downloading…";
                    el.style.opacity = "0.7";
                    el.style.pointerEvents = "none";
                    setTimeout(function() {
                        el.innerText = "Done";
                        el.style.opacity = "1";
                    }, 4000);
                }
            </script>
        </body>
        </html>
        """
    }
}
