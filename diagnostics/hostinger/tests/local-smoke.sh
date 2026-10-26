#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tmp_dir="$(mktemp -d)"
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir/public" "$tmp_dir/sessions"
cp -R "$repo_root/diagnostics/hostinger/public/." "$tmp_dir/public/"
database="$tmp_dir/events.sqlite"
sqlite3 "$database" <<'SQL'
CREATE TABLE diagnostic_events (
  event_id TEXT PRIMARY KEY,
  installation_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  app_name TEXT NOT NULL,
  app_version TEXT NOT NULL,
  macos_version TEXT NOT NULL,
  mac_name TEXT NOT NULL,
  mac_model TEXT NOT NULL DEFAULT 'unknown',
  transfer_direction TEXT,
  peer_name TEXT,
  peer_type TEXT
);
SQL

cat > "$tmp_dir/config.php" <<PHP
<?php
return [
    'dsn' => 'sqlite:$database',
    'db_user' => '',
    'db_password' => '',
    'admin_username' => '',
    'admin_password_hash' => '',
];
PHP
chmod 600 "$tmp_dir/config.php"

token="$(openssl rand -hex 32)"
password="$(openssl rand -hex 24)"
token_hash="$(printf '%s' "$token" | shasum -a 256 | awk '{print $1}')"
expires_at="$(php -r 'echo time() + 172800;')"
printf '{"token_hash":"%s","expires_at":%s}\n' "$token_hash" "$expires_at" > "$tmp_dir/nearbydrop-dashboard-setup.token"
chmod 600 "$tmp_dir/nearbydrop-dashboard-setup.token"
port="$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0", $error, $message); echo substr(strrchr(stream_socket_get_name($socket, false), ":"), 1); fclose($socket);')"
NEARBYDROP_DIAGNOSTICS_CONFIG="$tmp_dir/config.php" php -d "session.save_path=$tmp_dir/sessions" -S "127.0.0.1:$port" -t "$tmp_dir/public" >"$tmp_dir/server.log" 2>&1 &
server_pid=$!
base_url="http://127.0.0.1:$port"

for _ in {1..40}; do
  if curl -fsS "$base_url/" -o "$tmp_dir/ready.html" 2>/dev/null; then break; fi
  sleep 0.1
done
grep -q 'Nearby Drop Diagnostics' "$tmp_dir/ready.html"

session_from() {
  sed -n 's/^Set-Cookie: PHPSESSID=\([^;]*\).*/\1/ip' "$1" | tail -1
}
csrf_from() {
  grep -oE 'name="csrf" value="[^"]+"' "$1" | head -1 | sed -E 's/.*value="([^"]+)"/\1/'
}
post_event() {
  local file="$1"
  python3 - "$file" <<'PYTIME'
import datetime,sys
p=sys.argv[1]
s=open(p).read().replace('TIMESTAMP',datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:00:00Z'))
open(p,'w').write(s)
PYTIME
  local status
  status="$(curl -sS -o "$tmp_dir/event-response.json" -w '%{http_code}' \
    -H 'Content-Type: application/json' --data-binary "@$file" "$base_url/ingest.php")"
  [[ "$status" == 202 && "$(cat "$tmp_dir/event-response.json")" == '{"ok":true}' ]]
}

status="$(curl -sS -D "$tmp_dir/token.headers" -o /dev/null -w '%{http_code}' "$base_url/setup.php?token=$token")"
[[ "$status" == 302 ]]
setup_session="$(session_from "$tmp_dir/token.headers")"
[[ -n "$setup_session" ]]
curl -sS -D "$tmp_dir/setup.headers" -H "Cookie: PHPSESSID=$setup_session" \
  "$base_url/setup.php" -o "$tmp_dir/setup.html"
grep -q 'name="password_confirmation"' "$tmp_dir/setup.html"
grep -q 'name="database_password"' "$tmp_dir/setup.html"
if grep -q 'setup link has expired' "$tmp_dir/setup.html"; then exit 1; fi
setup_csrf="$(csrf_from "$tmp_dir/setup.html")"

# Opening the one-time link in another session must not consume it.
status="$(curl -sS -o /dev/null -w '%{http_code}' "$base_url/setup.php?token=$token")"
[[ "$status" == 302 ]]

# A reissued link must replace stale authorization in the existing session.
old_token="$token"
token="$(openssl rand -hex 32)"
token_hash="$(printf '%s' "$token" | shasum -a 256 | awk '{print $1}')"
expires_at="$(php -r 'echo time() + 172800;')"
printf '{"token_hash":"%s","expires_at":%s}\n' "$token_hash" "$expires_at" > "$tmp_dir/nearbydrop-dashboard-setup.token"
status="$(curl -sS -D "$tmp_dir/renew.headers" -o /dev/null -w '%{http_code}' \
  -H "Cookie: PHPSESSID=$setup_session" "$base_url/setup.php?token=$token")"
[[ "$status" == 302 ]]
setup_session="$(session_from "$tmp_dir/renew.headers")"
[[ -n "$setup_session" ]]
curl -sS -D "$tmp_dir/setup.headers" -H "Cookie: PHPSESSID=$setup_session" \
  "$base_url/setup.php" -o "$tmp_dir/setup.html"
grep -q 'name="password_confirmation"' "$tmp_dir/setup.html"
if grep -q 'setup link has expired' "$tmp_dir/setup.html"; then exit 1; fi
setup_csrf="$(csrf_from "$tmp_dir/setup.html")"
status="$(curl -sS -o /dev/null -w '%{http_code}' "$base_url/setup.php?token=$old_token")"
[[ "$status" == 404 ]]

status="$(curl -sS -D "$tmp_dir/save.headers" -o "$tmp_dir/save.html" -w '%{http_code}' \
  -H "Cookie: PHPSESSID=$setup_session" \
  --data-urlencode "csrf=$setup_csrf" \
  --data-urlencode 'username=Arsalan Basharat' \
  --data-urlencode 'database_password=local-only-test' \
  --data-urlencode "password=$password" \
  --data-urlencode "password_confirmation=$password" \
  "$base_url/setup.php")"
[[ "$status" == 302 ]]
grep -qi '^Location: /' "$tmp_dir/save.headers"
saved_session="$(session_from "$tmp_dir/save.headers")"
[[ -n "$saved_session" ]]
EXPECTED_PASSWORD="$password" NEARBYDROP_DIAGNOSTICS_CONFIG="$tmp_dir/config.php" php -r '
  $config = require getenv("NEARBYDROP_DIAGNOSTICS_CONFIG");
  if ($config["admin_username"] !== "Arsalan Basharat"
      || $config["db_password"] !== "local-only-test"
      || !password_verify(getenv("EXPECTED_PASSWORD"), $config["admin_password_hash"])) exit(1);
'

status="$(curl -sS -o /dev/null -w '%{http_code}' "$base_url/setup.php?token=$token")"
[[ "$status" == 404 ]]

curl -fsS -H "Cookie: PHPSESSID=$saved_session" "$base_url/" -o "$tmp_dir/initial-dashboard.html"
grep -q 'Reported installs' "$tmp_dir/initial-dashboard.html"
curl -sS -o /dev/null -H "Cookie: PHPSESSID=$saved_session" "$base_url/?logout=1"

curl -sS -D "$tmp_dir/login.headers" "$base_url/" -o "$tmp_dir/login.html"
login_session="$(session_from "$tmp_dir/login.headers")"
login_csrf="$(csrf_from "$tmp_dir/login.html")"
status="$(curl -sS -D "$tmp_dir/auth.headers" -o "$tmp_dir/auth.html" -w '%{http_code}' \
  -H "Cookie: PHPSESSID=$login_session" \
  --data-urlencode "csrf=$login_csrf" \
  --data-urlencode 'username=Arsalan Basharat' \
  --data-urlencode "password=$password" \
  "$base_url/")"
[[ "$status" == 302 ]]
auth_session="$(session_from "$tmp_dir/auth.headers")"
[[ -n "$auth_session" ]]

cat > "$tmp_dir/first-launch.json" <<'JSON'
{"event_id":"00000000-0000-4000-8000-000000000001","installation_id":"10000000-0000-4000-8000-000000000001","event":"first_launch","occurred_at":"TIMESTAMP","app_name":"Nearby Drop","app_version":"2.3.4","macos_version":"15.0","mac_name":"Local Test Mac"}
JSON
post_event "$tmp_dir/first-launch.json"
post_event "$tmp_dir/first-launch.json"
cat > "$tmp_dir/app-opened.json" <<'JSON'
{"event_id":"00000000-0000-4000-8000-000000000002","installation_id":"10000000-0000-4000-8000-000000000001","event":"app_opened","occurred_at":"TIMESTAMP","app_name":"Nearby Drop","app_version":"2.3.4","macos_version":"15.0","mac_name":"Local Test Mac"}
JSON
post_event "$tmp_dir/app-opened.json"
cat > "$tmp_dir/transfer.json" <<'JSON'
{"event_id":"00000000-0000-4000-8000-000000000003","installation_id":"10000000-0000-4000-8000-000000000001","event":"transfer_completed","occurred_at":"TIMESTAMP","app_name":"Nearby Drop","app_version":"2.3.4","macos_version":"15.0","mac_name":"Local Test Mac","transfer_direction":"outgoing","peer_name":"Android Test Phone","peer_type":"phone"}
JSON
post_event "$tmp_dir/transfer.json"

curl -fsS -H "Cookie: PHPSESSID=$auth_session" "$base_url/" -o "$tmp_dir/dashboard.html"
grep -q 'Local Test Mac' "$tmp_dir/dashboard.html"
grep -q 'Android Test Phone' "$tmp_dir/dashboard.html"
grep -q 'Reported installs' "$tmp_dir/dashboard.html"
[[ "$(sqlite3 "$database" 'SELECT COUNT(*) FROM diagnostic_events;')" == 3 ]]
echo 'Local diagnostics smoke test passed: setup, sign-in, ingestion, deduplication, and dashboard.'

# Validation must reject stale/future timestamps without growing storage.
python3 - "$tmp_dir/first-launch.json" "$tmp_dir/future.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]));x['occurred_at']='2099-01-01T00:00:00Z'
json.dump(x,open(sys.argv[2],'w'))
PY
[[ "$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary "@$tmp_dir/future.json" "$base_url/ingest.php")" == 422 ]]
[[ "$(curl -sS -o /dev/null -w '%{http_code}' "$base_url/cleanup.php")" == 404 ]]

# Retention removes expired events but preserves current data.
sqlite3 "$database" "INSERT INTO diagnostic_events SELECT 'expired', installation_id, event_type, '2000-01-01 00:00:00', app_name, app_version, macos_version, mac_name, mac_model, transfer_direction, peer_name, peer_type FROM diagnostic_events LIMIT 1;"
NEARBYDROP_DIAGNOSTICS_CONFIG="$tmp_dir/config.php" php "$tmp_dir/public/cleanup.php" >/dev/null
[[ "$(sqlite3 "$database" 'SELECT COUNT(*) FROM diagnostic_events;')" == 3 ]]
# Duplicate events stay deduplicated; excessive calls receive Retry-After.
for _ in {1..125}; do
  status="$(curl -sS -D "$tmp_dir/limit.headers" -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary "@$tmp_dir/first-launch.json" "$base_url/ingest.php")"
  [[ "$status" == 429 ]] && break
done
[[ "$status" == 429 ]]
grep -qi '^Retry-After:' "$tmp_dir/limit.headers"
[[ "$(sqlite3 "$database" 'SELECT COUNT(*) FROM diagnostic_events;')" == 3 ]]
echo 'Safeguards passed: timestamps, CLI-only cleanup, 90-day retention, and rate limiting.'
