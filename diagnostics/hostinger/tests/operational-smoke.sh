#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
workspace="$(mktemp -d)"; server=""
cleanup() { if [[ -n "$server" ]]; then kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi; rm -rf "$workspace"; }
trap cleanup EXIT
port="$(python3 - <<'PY'
import socket
s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()
PY
)"
cat > "$workspace/config.php" <<PHP
<?php return ['dsn'=>'sqlite:$workspace/events.sqlite','db_user'=>'','db_password'=>'','operational_enabled'=>true,'admin_username'=>'test','admin_password_hash'=>password_hash('local-test-password',PASSWORD_DEFAULT)];
PHP
chmod 600 "$workspace/config.php"
php "$root/diagnostics/hostinger/migrations/apply-004.php" "$workspace/config.php"
php "$root/diagnostics/hostinger/migrations/apply-004.php" "$workspace/config.php"
php "$root/diagnostics/hostinger/tests/operational-accounting.php"
sqlite3 "$workspace/events.sqlite" 'CREATE TABLE diagnostic_events(event_id TEXT PRIMARY KEY, installation_id TEXT, event_type TEXT, occurred_at TEXT, app_version TEXT, mac_name TEXT, mac_model TEXT, macos_version TEXT, peer_name TEXT, peer_type TEXT, transfer_direction TEXT);'
NEARBYDROP_DIAGNOSTICS_CONFIG="$workspace/config.php" php -S "127.0.0.1:$port" -t "$root/diagnostics/hostinger/public" > "$workspace/server.log" 2>&1 &
server=$!
for attempt in {1..40}; do if curl -s "http://127.0.0.1:$port/" >/dev/null; then break; fi; sleep 0.1; done
base="http://127.0.0.1:$port"
[[ "$(curl -s -o /dev/null -w '%{http_code}' "$base/operations.php")" == 401 ]]
python3 - "$workspace/event.json" <<'PY'
import json,sys,datetime
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')
e={'schema_version':2,'event_id':'00000000-0000-4000-8000-000000000001','installation_id':'10000000-0000-4000-8000-000000000001','event':'transfer_started','occurred_at':stamp,'app_version':'2.5.0','macos_version':'26.0','device_category':'computer','job_id':'20000000-0000-4000-8000-000000000001','attempt_id':'30000000-0000-4000-8000-000000000001','attempt_number':1,'job_started_at':stamp,'method':'wifi','direction':'outgoing','outcome':'pending','size_bucket':'unknown','count_bucket':'one','duration_bucket':'lt1s','error_category':'none','queue_bucket':'zero','stage':'connecting','connection_duration_bucket':'lt1s','approval_duration_bucket':'unknown'}
json.dump(e,open(sys.argv[1],'w'))
PY
for attempt in 1 2; do
 [[ "$(curl -s -o "$workspace/response.json" -w '%{http_code}' -H 'Content-Type: application/json' --data-binary @"$workspace/event.json" "$base/operational.php")" == 202 ]]
done
[[ "$(sqlite3 "$workspace/events.sqlite" 'SELECT COUNT(*) FROM operational_events;')" == 1 ]]
[[ "$(sqlite3 "$workspace/events.sqlite" "SELECT value FROM operational_collector_health WHERE metric='duplicates';")" == 1 ]]
[[ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data '{"schema_version":2,"file_name":"private"}' "$base/operational.php")" == 422 ]]
# Establish a local authenticated session through the real login form.
curl -s -c "$workspace/cookies" "$base/" > "$workspace/login.html"
csrf="$(python3 - "$workspace/login.html" <<'PY'
import re,sys
print(re.search(r'name="csrf" value="([^"]+)"',open(sys.argv[1]).read())[1])
PY
)"
curl -s -b "$workspace/cookies" -c "$workspace/cookies" --data-urlencode "csrf=$csrf" --data-urlencode 'username=test' --data-urlencode 'password=local-test-password' "$base/" -o /dev/null
curl -fsS -b "$workspace/cookies" "$base/operations.php?method=wifi&version=2.5.0" > "$workspace/dashboard.html"
grep -q 'Started jobs' "$workspace/dashboard.html"
grep -q 'Unknown jobs' "$workspace/dashboard.html"
grep -q 'Collector health' "$workspace/dashboard.html"
curl -fsS -b "$workspace/cookies" "$base/operations.php?method=usb" > "$workspace/empty.html"
grep -q 'No detailed reports for this selection.' "$workspace/empty.html"
[[ "$(curl -s -b "$workspace/cookies" -o /dev/null -w '%{http_code}' "$base/operations.php?from=2026-02-31")" == 400 ]]
echo 'Operational HTTP checks passed: auth, migration replay, validation, UUID deduplication, filters and rendered metrics.'
