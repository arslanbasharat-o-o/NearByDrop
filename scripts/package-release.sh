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
staging="$(mktemp -d "${TMPDIR:-/tmp}/nearby-drop-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Nearby Drop.app"
ditto "$product" "$app"
notices="$app/Contents/Resources/ThirdPartyLicenses"
mkdir -p "$notices"
cp LICENSE "$notices/Nearby-Drop-LICENSE.txt"
cp Vendor/USB/licenses/*.txt "$notices/"
cp Vendor/USB/README.md "$notices/USB.md"
cp README.md "$notices/Nearby-Drop-README.md"
for dependency in ASN1 BigInt SwiftECC swift-qrcode-generator QRCode swift-protobuf SwiftImageReadWrite Sparkle; do
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
# Sparkle's nested installer tools must retain valid signatures after packaging.
if [ -d "$app/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --deep --sign - --timestamp=none "$app/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --sign - --timestamp=none --entitlements ShareExtension/ShareExtension.entitlements \
    "$app/Contents/PlugIns/ShareExtension.appex"
codesign --force --sign - --timestamp=none --options runtime --entitlements NearByDrop/NearByDrop.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
minimum=$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$app/Contents/Info.plist")
test "$minimum" = 14.0
archive="$output/Nearby-Drop-$version-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"

# Build installer DMG with Applications shortcut
dmg_staging="$(mktemp -d "${TMPDIR:-/tmp}/nearby-drop-dmg.XXXXXX")"
ditto "$app" "$dmg_staging/Nearby Drop.app"
ln -s /Applications "$dmg_staging/Applications"
dmg="$output/Nearby-Drop-$version.dmg"
rm -f "$dmg"
hdiutil create -volname "Nearby Drop" -srcfolder "$dmg_staging" -ov -format UDZO "$dmg"
rm -rf "$dmg_staging"

(cd "$output" && shasum -a 256 "$(basename "$dmg")" "$(basename "$archive")" > SHA256SUMS.txt)
printf 'Packaged %s and %s (macOS %s+, arm64 + x86_64, ad hoc signed)\n' "$dmg" "$archive" "$minimum"

# Sparkle signs the archive using the local Keychain or the CI signing secret.
sparkle_bin="${SPARKLE_BIN_DIR:-$derived/SourcePackages/artifacts/sparkle/Sparkle/bin}"
feed_staging="$(mktemp -d "${TMPDIR:-/tmp}/nearby-drop-feed.XXXXXX")"
cp "$archive" "$feed_staging/"
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sparkle_bin/generate_appcast" --ed-key-file - --maximum-deltas 0 --download-url-prefix "https://github.com/arslanbasharat-o-o/NearByDrop/releases/download/v$version/" "$feed_staging"
else
    "$sparkle_bin/generate_appcast" --maximum-deltas 0 --download-url-prefix "https://github.com/arslanbasharat-o-o/NearByDrop/releases/download/v$version/" "$feed_staging"
fi
cp "$feed_staging/appcast.xml" "$output/appcast.xml"
rm -rf "$feed_staging"
