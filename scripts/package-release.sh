#!/bin/bash
# Package a verified universal build without requiring Developer ID credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
derived="${1:-build}"
output="${2:-dist}"
product="$derived/Build/Products/Release/Nearby Drop.app"
test -d "$product"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
staging="$(mktemp -d "${TMPDIR:-/tmp}/nearbydrop-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Nearby Drop.app"
ditto "$product" "$app"
notices="$app/Contents/Resources/ThirdPartyLicenses"
mkdir -p "$notices"
cp UNLICENSE "$notices/NearbyDrop-UNLICENSE.txt"
cp Vendor/USB/licenses/*.txt "$notices/"
cp Vendor/USB/README.md "$notices/USB.md"
cp README.md "$notices/NearbyDrop-README.md"
for dependency in ASN1 BigInt SwiftECC swift-qrcode-generator QRCode swift-protobuf SwiftImageReadWrite; do
    checkout="$derived/SourcePackages/checkouts/$dependency"
    if [ ! -d "$checkout" ] && [ "$dependency" = QRCode ]; then
        checkout="$derived/SourcePackages/checkouts/qrcode"
    fi
    if [ -f "$checkout/LICENSE" ]; then
        cp "$checkout/LICENSE" "$notices/$dependency-LICENSE.txt"
    else
        cp "$checkout/LICENSE.txt" "$notices/$dependency-LICENSE.txt"
    fi
done
while IFS= read -r -d '' binary; do
    if file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
        lipo "$binary" -verify_arch arm64
        lipo "$binary" -verify_arch x86_64
        case "$binary" in
            *.dylib) codesign --force --sign - --timestamp=none "$binary" ;;
        esac
    fi
done < <(find "$app/Contents" -type f -print0)
codesign --force --sign - --timestamp=none --entitlements ShareExtension/ShareExtension.entitlements \
    "$app/Contents/PlugIns/ShareExtension.appex"
codesign --force --sign - --timestamp=none --options runtime --entitlements NearByDrop/NearByDrop.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
minimum=$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$app/Contents/Info.plist")
test "$minimum" = 14.0
archive="$output/NearbyDrop-$version-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd "$output" && shasum -a 256 "$(basename "$archive")" > SHA256SUMS.txt)
printf 'Packaged %s (macOS %s+, arm64 + x86_64, ad hoc signed)\n' "$archive" "$minimum"
