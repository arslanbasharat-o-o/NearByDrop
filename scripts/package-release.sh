#!/bin/bash
# Package a verified universal build without requiring Developer ID credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
derived="${1:-build}"
output="${2:-dist}"
mode="${3:---ci-unsigned}"
if [ "$#" -gt 3 ]; then
    echo "Usage: $0 [derived-data-path] [output-dir] [--ci-unsigned|--release|--release-keychain]" >&2
    exit 2
fi

case "$mode" in
    --ci-unsigned)
        if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
            echo "CI unsigned mode refuses SPARKLE_PRIVATE_KEY." >&2
            exit 2
        fi
        artifact_suffix="-ci-unsigned"
        ;;
    --release)
        if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
            echo "Release mode requires SPARKLE_PRIVATE_KEY; keychain fallback is disabled." >&2
            exit 2
        fi
        artifact_suffix=""
        ;;
    --release-keychain)
        if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
            echo "Keychain release mode refuses SPARKLE_PRIVATE_KEY; choose --release instead." >&2
            exit 2
        fi
        artifact_suffix=""
        ;;
    *)
        echo "Unknown package mode: $mode" >&2
        echo "Usage: $0 [derived-data-path] [output-dir] [--ci-unsigned|--release|--release-keychain]" >&2
        exit 2
        ;;
esac

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
archive="$output/Nearby-Drop-$version$artifact_suffix-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"

# Build installer DMG with Applications shortcut
dmg_staging="$(mktemp -d "${TMPDIR:-/tmp}/nearby-drop-dmg.XXXXXX")"
ditto "$app" "$dmg_staging/Nearby Drop.app"
ln -s /Applications "$dmg_staging/Applications"
dmg="$output/Nearby-Drop-$version$artifact_suffix.dmg"
rm -f "$dmg"
hdiutil create -volname "Nearby Drop" -srcfolder "$dmg_staging" -ov -format UDZO "$dmg"
rm -rf "$dmg_staging"

(cd "$output" && shasum -a 256 "$(basename "$dmg")" "$(basename "$archive")" > SHA256SUMS.txt)
if [ "$mode" = "--ci-unsigned" ]; then
    cat > "$output/NONPUBLIC-CI-ARTIFACTS.txt" <<EOF
Engineering validation artifacts only.
Not for installation or distribution.
Ad hoc code signatures; no production Sparkle signature or appcast.
EOF
    rm -f "$output/appcast.xml"
    printf 'Created nonpublic CI artifacts: %s and %s (macOS %s+, arm64 + x86_64)\n' "$dmg" "$archive" "$minimum"
else
    sparkle_bin="${SPARKLE_BIN_DIR:-$derived/SourcePackages/artifacts/sparkle/Sparkle/bin}"
    feed_staging="$(mktemp -d "${TMPDIR:-/tmp}/nearby-drop-feed.XXXXXX")"
    trap 'rm -rf "$staging" "$feed_staging"' EXIT
    cp "$archive" "$feed_staging/"
    if [ "$mode" = "--release" ]; then
        printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sparkle_bin/generate_appcast" --ed-key-file - --maximum-deltas 0 --download-url-prefix "https://github.com/arslanbasharat-o-o/NearByDrop/releases/download/v$version/" "$feed_staging"
    else
        "$sparkle_bin/generate_appcast" --maximum-deltas 0 --download-url-prefix "https://github.com/arslanbasharat-o-o/NearByDrop/releases/download/v$version/" "$feed_staging"
    fi
    cp "$feed_staging/appcast.xml" "$output/appcast.xml"
    rm -rf "$feed_staging"
    printf 'Packaged signed-release inputs: %s and %s (macOS %s+, arm64 + x86_64)\n' "$dmg" "$archive" "$minimum"
fi
