#!/bin/bash
set -euo pipefail

echo "==> Installing Nearby Drop..."
REPO="arslanbasharat-o-o/NearByDrop"
LATEST_RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest")
DOWNLOAD_URL=$(echo "$LATEST_RELEASE_JSON" | grep -o "https://github.com/${REPO}/releases/download/[^\"']*\.dmg" | head -n 1 || true)

if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v2.3.4/Nearby-Drop-2.3.4.dmg"
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
TMP_DMG="$TMP_DIR/Nearby-Drop-2.3.4.dmg"

echo "==> Downloading $DOWNLOAD_URL..."
curl -fL -o "$TMP_DMG" "$DOWNLOAD_URL"

echo "==> Installing to /Applications..."
MOUNT_DIR=$(mktemp -d)
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
rm -rf "/Applications/Nearby Drop.app"
cp -R "$MOUNT_DIR/Nearby Drop.app" /Applications/
hdiutil detach "$MOUNT_DIR" -quiet

xattr -cr "/Applications/Nearby Drop.app" 2>/dev/null || true
echo "==> Nearby Drop successfully installed to /Applications/Nearby Drop.app"
