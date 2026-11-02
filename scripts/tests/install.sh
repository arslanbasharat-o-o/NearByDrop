#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nearby-drop-installer-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
BIN="$TEST_ROOT/bin"
mkdir -p "$BIN"

cat > "$BIN/curl" <<'MOCK'
#!/bin/bash
set -euo pipefail
output=""
url=""
write_format=""
while (($#)); do
    if [[ "$1" == "-o" ]]; then
        output="$2"
        shift 2
    elif [[ "$1" == "-w" ]]; then
        write_format="$2"
        shift 2
    else
        url="$1"
        shift
    fi
done
if [[ "$url" == https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest ]]; then
    printf 'https://github.com/arslanbasharat-o-o/NearByDrop/releases/tag/%s' "$INSTALL_TEST_RELEASE_TAG"
elif [[ "$url" == */SHA256SUMS.txt ]]; then
    cp "$INSTALL_TEST_CHECKSUMS" "$output"
else
    cp "$INSTALL_TEST_DMG" "$output"
fi
MOCK

cat > "$BIN/hdiutil" <<'MOCK'
#!/bin/bash
set -euo pipefail
command="$1"
if [[ "$command" == "verify" ]]; then
    [[ "${INSTALL_TEST_FAILURE:-}" != "dmg-verify" ]]
    exit
fi
if [[ "$command" == "attach" ]]; then
    [[ "${INSTALL_TEST_FAILURE:-}" != "mount" ]] || exit 1
    mount=""
    while (($#)); do
        if [[ "$1" == "-mountpoint" ]]; then mount="$2"; shift 2; else shift; fi
    done
    mkdir -p "$mount/Nearby Drop.app/Contents"
    cat > "$mount/Nearby Drop.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>2.3.5</string></dict></plist>
PLIST
    printf 'verified mock release\n' > "$mount/Nearby Drop.app/release-marker"
    exit 0
fi
if [[ "$command" == "detach" ]]; then exit 0; fi
exit 1
MOCK

cat > "$BIN/ditto" <<'MOCK'
#!/bin/bash
set -euo pipefail
[[ "${INSTALL_TEST_FAILURE:-}" != "copy" ]] || exit 1
cp -R "$1" "$2"
MOCK

cat > "$BIN/codesign" <<'MOCK'
#!/bin/bash
set -euo pipefail
count=0
[[ ! -f "$INSTALL_TEST_CODESIGN_COUNT" ]] || count="$(cat "$INSTALL_TEST_CODESIGN_COUNT")"
count=$((count + 1))
printf '%s' "$count" > "$INSTALL_TEST_CODESIGN_COUNT"
if [[ "${INSTALL_TEST_FAILURE:-}" == "staged-signature" && "$count" -eq 2 ]]; then exit 1; fi
if [[ "${INSTALL_TEST_FAILURE:-}" == "installed-signature" && "$count" -eq 3 ]]; then exit 1; fi
exit 0
MOCK

chmod +x "$BIN"/*

make_checksum_file() {
    local digest="$1"
    local include_asset="${2:-yes}"
    if [[ "$include_asset" == yes ]]; then
        printf '%s  Nearby-Drop-2.3.5.dmg\n' "$digest" > "$CASE_ROOT/SHA256SUMS.txt"
    else
        printf '%s  Nearby-Drop-other.dmg\n' "$digest" > "$CASE_ROOT/SHA256SUMS.txt"
    fi
}

prepare_case() {
    local case_name="$1"
    CASE_ROOT="$TEST_ROOT/$case_name"
    DEST="$CASE_ROOT/Applications"
    mkdir -p "$DEST/Nearby Drop.app"
    printf 'previous working app\n' > "$DEST/Nearby Drop.app/old-marker"
    printf 'mock dmg bytes\n' > "$CASE_ROOT/release.dmg"
    DIGEST="$(shasum -a 256 "$CASE_ROOT/release.dmg" | awk '{print $1}')"
    make_checksum_file "$DIGEST"
    CODESIGN_COUNT="$CASE_ROOT/codesign-count"
}

run_installer() {
    INSTALL_DESTINATION="$DEST" \
    INSTALL_TEST_RELEASE_TAG="${INSTALL_TEST_RELEASE_TAG:-v2.3.5}" \
    INSTALL_TEST_CHECKSUMS="$CASE_ROOT/SHA256SUMS.txt" \
    INSTALL_TEST_DMG="$CASE_ROOT/release.dmg" \
    INSTALL_TEST_CODESIGN_COUNT="$CODESIGN_COUNT" \
    INSTALL_TEST_FAILURE="${INSTALL_TEST_FAILURE:-}" \
    CURL_BIN="$BIN/curl" \
    HDITOOL_BIN="$BIN/hdiutil" \
    DITTO_BIN="$BIN/ditto" \
    CODESIGN_BIN="$BIN/codesign" \
    "$ROOT/scripts/install.sh" > "$CASE_ROOT/install.log" 2>&1
}

prepare_case success
run_installer
[[ -f "$DEST/Nearby Drop.app/release-marker" ]]
[[ ! -f "$DEST/Nearby Drop.app/old-marker" ]]
[[ -z "$(find "$DEST" -maxdepth 1 -name '.Nearby Drop.app.backup.*' -print -quit)" ]]

prepare_case checksum-mismatch
make_checksum_file "$(printf '0%.0s' {1..64})"
if run_installer; then echo "installer accepted a mismatched checksum" >&2; exit 1; fi
[[ -f "$DEST/Nearby Drop.app/old-marker" ]]

prepare_case copy-failure
INSTALL_TEST_FAILURE=copy
if run_installer; then echo "installer ignored a copy failure" >&2; exit 1; fi
unset INSTALL_TEST_FAILURE
[[ -f "$DEST/Nearby Drop.app/old-marker" ]]

prepare_case mount-failure
INSTALL_TEST_FAILURE=mount
if run_installer; then echo "installer ignored a mount failure" >&2; exit 1; fi
unset INSTALL_TEST_FAILURE
[[ -f "$DEST/Nearby Drop.app/old-marker" ]]

prepare_case installed-signature-failure
INSTALL_TEST_FAILURE=installed-signature
if run_installer; then echo "installer ignored an installed bundle verification failure" >&2; exit 1; fi
unset INSTALL_TEST_FAILURE
[[ -f "$DEST/Nearby Drop.app/old-marker" ]]
[[ ! -f "$DEST/Nearby Drop.app/release-marker" ]]

prepare_case symlinked-destination
rm -rf -- "$DEST/Nearby Drop.app"
mkdir -p "$CASE_ROOT/external.app"
printf 'outside app remains untouched\n' > "$CASE_ROOT/external.app/marker"
ln -s "$CASE_ROOT/external.app" "$DEST/Nearby Drop.app"
if run_installer; then echo "installer trusted a symlinked app destination" >&2; exit 1; fi
[[ -L "$DEST/Nearby Drop.app" ]]
[[ -f "$CASE_ROOT/external.app/marker" ]]

prepare_case missing-asset
make_checksum_file "$DIGEST" no
if run_installer; then echo "installer accepted a release without the exact DMG asset" >&2; exit 1; fi
[[ -f "$DEST/Nearby Drop.app/old-marker" ]]

echo "Installer checks passed: checksum, asset selection, mount/copy failure, signature rollback, symlink refusal, and existing-app preservation."
