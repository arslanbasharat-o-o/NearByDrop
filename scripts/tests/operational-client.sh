#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
python3 - "$root" "$workspace/main.swift" <<'PY'
import sys,re
from pathlib import Path
root=Path(sys.argv[1])
fixture=(root/'scripts/tests/diagnostics-client.sh').read_text()
pre=re.search("pre=r'''(.*?)'''",fixture,re.S)[1]
pre=pre.replace('static var received: [[String: Any]] = []', 'static var received: [[String: Any]] = []; static var destinations: [String] = []')
pre=pre.replace('Self.received.append(value)', 'Self.received.append(value); Self.destinations.append(request.url?.lastPathComponent ?? "")')
pre+='\nvar operationalTestRollout = false\n'
source=(root/'NearByDrop/OperationalDiagnostics.swift').read_text()+'\n'+(root/'NearByDrop/UsageAnalytics.swift').read_text().replace('import NearbyShare','')
source=source.replace('UserDefaults.standard','testDefaults')
source=source.replace('Bundle.main.object(forInfoDictionaryKey: endpointKey)', '("https://diagnostics.invalid/ingest.php" as Any?)')
source=source.replace('Bundle.main.object(forInfoDictionaryKey: "ExpandedDiagnosticsEnabled")', '(operationalTestRollout as Any?)')
post=r'''
URLProtocol.registerClass(StubProtocol.self)
defer { testDefaults.removePersistentDomain(forName: suite) }
testDefaults.set(true, forKey: "hasCompletedOnboarding")
testDefaults.set(true, forKey: "diagnosticsDisclosureSeen")
UsageAnalytics.recordOperational(.clientHealth)
Thread.sleep(forTimeInterval:0.1)
precondition(testDefaults.array(forKey:"diagnosticsPendingEvents") == nil)
UsageAnalytics.setOperationalEnabled(true)
precondition(!UsageAnalytics.operationalEnabled, "Build gate must override consent")
operationalTestRollout = true
UsageAnalytics.recordOperational(.clientHealth)
Thread.sleep(forTimeInterval:0.1)
precondition(testDefaults.array(forKey:"diagnosticsPendingEvents") == nil, "Separate consent is required")
UsageAnalytics.setOperationalEnabled(true)
precondition(UsageAnalytics.operationalEnabled)
var operation = OperationContext(method:.wifi,direction:.outgoing,fileCount:2,bytes:1024)
UsageAnalytics.recordOperational(.transferStarted,context:operation)
precondition(operation.finish(.failed))
UsageAnalytics.recordOperational(.transferFailed,context:operation,error:.connection)
precondition(operation.retry())
UsageAnalytics.recordOperational(.transferStarted,context:operation)
precondition(operation.finish(.completed))
UsageAnalytics.recordOperational(.transferCompleted,context:operation)
waitFor { (testDefaults.array(forKey:"diagnosticsPendingEvents")?.count ?? 0) == 4 }
let pending = testDefaults.array(forKey:"diagnosticsPendingEvents") as! [Data]
let objects = pending.map { try! JSONSerialization.jsonObject(with:$0) as! [String:Any] }
precondition(Set(objects.map { $0["job_id"] as! String }).count == 1)
precondition(Set(objects.map { $0["attempt_id"] as! String }).count == 2)
precondition(Set(objects.map { $0["event_id"] as! String }).count == 4)
for object in objects {
    precondition(object["schema_version"] as? Int == 2)
    for key in ["mac_name","peer_name","file_name","path","clipboard","content","mac_model"] { precondition(object[key] == nil) }
}
UsageAnalytics.setOperationalEnabled(false)
waitFor { (testDefaults.array(forKey:"diagnosticsPendingEvents")?.count ?? 0) == 0 }
precondition(UsageAnalytics.isEnabled, "Operational opt-out must preserve legacy reporting choice")
StubProtocol.lock.lock(); StubProtocol.status=202; StubProtocol.lock.unlock()
UsageAnalytics.setOperationalEnabled(true)
UsageAnalytics.recordOperational(.onboardingCompleted)
waitFor {
    StubProtocol.lock.lock(); defer { StubProtocol.lock.unlock() }
    return StubProtocol.received.contains { $0["event"] as? String == "onboarding_completed" }
}
waitFor { (testDefaults.array(forKey:"diagnosticsPendingEvents")?.count ?? 0) == 0 }
StubProtocol.lock.lock(); let destinations = StubProtocol.destinations; StubProtocol.lock.unlock()
precondition(!destinations.isEmpty && destinations.allSatisfy { $0 == "operational.php" })
UsageAnalytics.setEnabled(false)
waitFor { testDefaults.array(forKey:"diagnosticsPendingEvents") == nil }
precondition(!UsageAnalytics.operationalEnabled)
precondition(testDefaults.integer(forKey: "operationalDiagnosticsConsentVersion") == 0)
UsageAnalytics.setEnabled(true)
precondition(!UsageAnalytics.operationalEnabled, "Legacy re-enable must not restore expanded consent")
print("Operational client passed: rollout + consent gates, job/attempt correlation, UUIDs, privacy allowlist, delivery and opt-out purge.")
'''
Path(sys.argv[2]).write_text(pre+source+post)
PY
swiftc "$workspace/main.swift" -o "$workspace/client"
"$workspace/client"
