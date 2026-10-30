#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
# Compile the shipping client with protocol/model stubs and an isolated defaults suite.
python3 - "$root/NearByDrop/UsageAnalytics.swift" "$workspace/main.swift" <<'PY'
import sys
s=open(sys.argv[1]).read().replace('import NearbyShare','')
s=s.replace('UserDefaults.standard','testDefaults')
s=s.replace('Bundle.main.object(forInfoDictionaryKey: endpointKey)', '("https://diagnostics.invalid/ingest.php" as Any?)')
pre=r'''import Foundation
let suite = "NearbyDrop.DiagnosticsTest." + UUID().uuidString
let testDefaults = UserDefaults(suiteName: suite)!
struct RemoteDeviceInfo {
    enum DeviceType { case phone, tablet, computer, unknown }
    let name: String
    let type: DeviceType
}
enum NearbyConnectionManager { static let currentDeviceName = "Test Mac" }
final class StubProtocol: URLProtocol {
    static let lock = NSLock()
    static var status = 503
    static var received: [[String: Any]] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let status = Self.status
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var collected = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; collected.append(buffer, count: count)
            }
            body = collected
        }
        if let body, let value=try? JSONSerialization.jsonObject(with:body) as? [String:Any] { Self.received.append(value) }
        Self.lock.unlock()
        let response=HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data("{\"ok\":true}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
func waitFor(line: Int = #line, _ predicate: () -> Bool) {
    let end=Date().addingTimeInterval(5)
    while !predicate() && Date()<end { Thread.sleep(forTimeInterval:0.02) }
    precondition(predicate(), "Timed out waiting for diagnostics state at line \(line)")
}
'''
post='''
URLProtocol.registerClass(StubProtocol.self)
defer { testDefaults.removePersistentDomain(forName:suite) }
UsageAnalytics.start()
Thread.sleep(forTimeInterval:0.1)
precondition(testDefaults.array(forKey:"diagnosticsPendingEvents") == nil)
testDefaults.set(true,forKey:"hasCompletedOnboarding")
UsageAnalytics.start()
Thread.sleep(forTimeInterval:0.1)
precondition(testDefaults.array(forKey:"diagnosticsPendingEvents") == nil, "Upgrade disclosure must precede reporting")
testDefaults.set(true,forKey:"diagnosticsDisclosureSeen")
testDefaults.set(Date().addingTimeInterval(-8 * 86400),forKey:"diagnosticsFirstLaunchDate")
testDefaults.set("expired-first-event",forKey:"diagnosticsFirstLaunchEventID")
UsageAnalytics.start()
waitFor { (testDefaults.array(forKey:"diagnosticsPendingEvents")?.count ?? 0) == 2 }
precondition(!testDefaults.bool(forKey:"diagnosticsFirstLaunchSent"))
precondition(testDefaults.string(forKey:"diagnosticsFirstLaunchEventID") != "expired-first-event", "Expired unsent first launch must get a reportable timestamp")
let original=testDefaults.array(forKey:"diagnosticsPendingEvents") as! [Data]
let payload=try! JSONSerialization.jsonObject(with:original[0]) as! [String:Any]
precondition(payload["mac_model"] as? String != "unknown")
precondition(payload["mac_name"] as? String == "Test Mac")
precondition(payload["event"] as? String == "first_launch")
precondition(payload["file_name"] == nil && payload["peer_id"] == nil)
StubProtocol.lock.lock(); StubProtocol.status=202; StubProtocol.lock.unlock()
Thread.sleep(forTimeInterval:0.2)
UsageAnalytics.start()
waitFor { testDefaults.bool(forKey:"diagnosticsFirstLaunchSent") && (testDefaults.array(forKey:"diagnosticsPendingEvents")?.isEmpty ?? false) }
UsageAnalytics.completedTransfer(direction:"incoming",peer:RemoteDeviceInfo(name:"Test Phone",type:.phone))
waitFor { StubProtocol.lock.lock(); defer { StubProtocol.lock.unlock() }; return StubProtocol.received.contains { $0["peer_name"] as? String == "Test Phone" } }
StubProtocol.lock.lock(); StubProtocol.status=503; StubProtocol.lock.unlock()
Thread.sleep(forTimeInterval:0.2)
UsageAnalytics.start()
waitFor { !(testDefaults.array(forKey:"diagnosticsPendingEvents")?.isEmpty ?? true) }
UsageAnalytics.setEnabled(false)
waitFor { testDefaults.array(forKey:"diagnosticsPendingEvents") == nil }
UsageAnalytics.completedTransfer(direction:"outgoing",peer:RemoteDeviceInfo(name:"Must Not Send",type:.phone))
Thread.sleep(forTimeInterval:0.1)
precondition(testDefaults.array(forKey:"diagnosticsPendingEvents") == nil)
print("Client checks passed: disclosure gate, fields, durable failure queue, retry acknowledgement, transfer report, and opt-out purge.")
'''
open(sys.argv[2],'w').write(pre+s+post)
PY
swiftc -swift-version 5 "$workspace/main.swift" -o "$workspace/client-test"
"$workspace/client-test"
