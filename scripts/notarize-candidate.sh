#!/usr/bin/env bash
# Run only after an authorized Developer ID build and notarization approval.
set -euo pipefail
if [[ $# != 3 ]]; then
    echo 'Usage: notarize-candidate.sh /absolute/path/App.app keychain-profile output-directory' >&2
    exit 2
fi
app="$1"; profile="$2"; output="$3"
if [[ ! -d "$app" || -L "$app" ]]; then echo 'Choose an existing app bundle.' >&2; exit 2; fi
metadata="$(codesign -dv --verbose=4 "$app" 2>&1)"
if ! printf '%s\n' "$metadata" | grep -q '^Authority=Developer ID Application:'; then
    echo 'An authorized Developer ID Application signature is required; ad hoc candidates cannot be notarized.' >&2
    exit 2
fi
if ! printf '%s\n' "$metadata" | grep -Eq 'flags=.*runtime'; then
    echo 'The Developer ID build must enable Hardened Runtime.' >&2
    exit 2
fi
codesign --verify --deep --strict "$app"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app" "$workspace/submission.zip"
xcrun notarytool submit "$workspace/submission.zip" --keychain-profile "$profile" --wait --output-format json > "$output/notarization-result.json"
python3 - "$output/notarization-result.json" <<'PY'
import json,sys
if json.load(open(sys.argv[1])).get('status')!='Accepted':
    raise SystemExit('Notarization was not accepted. Inspect the submission result before distribution.')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/Nearby-Drop-notarized.zip"
echo 'Notarized, stapled application ZIP prepared. Nothing was published.'
