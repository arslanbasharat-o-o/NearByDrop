#!/bin/bash
set -euo pipefail

REPO="arslanbasharat-o-o/NearByDrop"
DESTINATION="${INSTALL_DESTINATION:-/Applications}"
CURL_BIN="${CURL_BIN:-curl}"
HDITOOL_BIN="${HDITOOL_BIN:-hdiutil}"
DITTO_BIN="${DITTO_BIN:-ditto}"
CODESIGN_BIN="${CODESIGN_BIN:-codesign}"
SHASUM_BIN="${SHASUM_BIN:-shasum}"
STAT_BIN="${STAT_BIN:-stat}"
PLIST_BUDDY="${PLIST_BUDDY:-/usr/libexec/PlistBuddy}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nearby-drop-install.XXXXXX")"
MOUNT_DIR=""
STAGE_DIR=""
BACKUP_PATH=""
APP_PATH=""
INSTALLED_APP_IDENTITY=""
mounted=0
replacement_complete=0

cleanup() {
    local result=$?
    if [[ "$replacement_complete" -ne 1 && -n "$APP_PATH" && -n "$INSTALLED_APP_IDENTITY" ]]; then
        if [[ -d "$APP_PATH" && ! -L "$APP_PATH" ]]; then
            local current_identity
            current_identity="$("$STAT_BIN" -f '%d:%i' "$APP_PATH" 2>/dev/null || true)"
            if [[ "$current_identity" == "$INSTALLED_APP_IDENTITY" ]]; then
                rm -rf -- "$APP_PATH"
            else
                printf 'Installation failed; the destination changed during rollback, so it was preserved.\n' >&2
            fi
        fi
    fi
    if [[ "$replacement_complete" -ne 1 && -n "$BACKUP_PATH" && -e "$BACKUP_PATH" ]]; then
        if [[ ! -e "$APP_PATH" && ! -L "$APP_PATH" ]]; then
            if ! mv -- "$BACKUP_PATH" "$APP_PATH"; then
                printf 'Installation failed; the previous app remains at %s\n' "$BACKUP_PATH" >&2
            fi
        else
            printf 'Installation failed; preserved the previous app at %s because the destination changed.\n' "$BACKUP_PATH" >&2
        fi
    fi
    if [[ "$mounted" -eq 1 && -n "$MOUNT_DIR" ]]; then
        "$HDITOOL_BIN" detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || printf 'Could not detach temporary disk image at %s\n' "$MOUNT_DIR" >&2
    fi
    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf -- "$STAGE_DIR"
    fi
    rm -rf -- "$TMP_DIR"
    return "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

LATEST_RELEASE_URL="$("$CURL_BIN" -fL --silent --show-error --retry 2 -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")"
EXPECTED_RELEASE_PREFIX="https://github.com/$REPO/releases/tag/"
if [[ "$LATEST_RELEASE_URL" != "$EXPECTED_RELEASE_PREFIX"* ]]; then
    printf 'Could not resolve the latest Nearby Drop release on GitHub.\n' >&2
    exit 1
fi
RELEASE_TAG="${LATEST_RELEASE_URL##*/}"
if [[ ! "$RELEASE_TAG" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    printf 'GitHub returned an invalid Nearby Drop release tag.\n' >&2
    exit 1
fi
RELEASE_VERSION="${BASH_REMATCH[1]}"
DMG_NAME="Nearby-Drop-$RELEASE_VERSION.dmg"
RELEASE_BASE="https://github.com/$REPO/releases/download/$RELEASE_TAG"
DOWNLOAD_URL="$RELEASE_BASE/$DMG_NAME"
CHECKSUM_URL="$RELEASE_BASE/SHA256SUMS.txt"

DMG_PATH="$TMP_DIR/Nearby-Drop-$RELEASE_VERSION.dmg"
CHECKSUMS_PATH="$TMP_DIR/SHA256SUMS.txt"
MOUNT_DIR="$TMP_DIR/mounted"
mkdir "$MOUNT_DIR"
printf 'Downloading Nearby Drop %s…\n' "$RELEASE_VERSION"
"$CURL_BIN" -fL --silent --show-error --retry 2 -o "$CHECKSUMS_PATH" "$CHECKSUM_URL"
EXPECTED_SHA256="$(awk -v filename="$DMG_NAME" '$2 == filename || $2 == "*" filename { count++; digest = $1 } END { if (count != 1) exit 1; print tolower(digest) }' "$CHECKSUMS_PATH")" || {
    printf 'The release checksum file did not contain one checksum for %s.\n' "$DMG_NAME" >&2
    exit 1
}
if [[ ! "$EXPECTED_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    printf 'The release checksum for %s was malformed.\n' "$DMG_NAME" >&2
    exit 1
fi
"$CURL_BIN" -fL --silent --show-error --retry 2 -o "$DMG_PATH" "$DOWNLOAD_URL"

ACTUAL_SHA256="$("$SHASUM_BIN" -a 256 "$DMG_PATH" | awk '{print tolower($1)}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    printf 'The downloaded disk image checksum did not match the checksum published for this release asset.\n' >&2
    exit 1
fi
"$HDITOOL_BIN" verify "$DMG_PATH" >/dev/null
mounted=1
"$HDITOOL_BIN" attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -noautoopen -readonly -quiet

SOURCE_APP="$MOUNT_DIR/Nearby Drop.app"
if [[ ! -d "$SOURCE_APP" || -L "$SOURCE_APP" ]]; then
    printf 'The verified disk image does not contain the expected Nearby Drop app bundle.\n' >&2
    exit 1
fi
"$CODESIGN_BIN" --verify --deep --strict "$SOURCE_APP"
SOURCE_VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")"
if [[ "$SOURCE_VERSION" != "$RELEASE_VERSION" ]]; then
    printf 'App version %s did not match release version %s.\n' "$SOURCE_VERSION" "$RELEASE_VERSION" >&2
    exit 1
fi

if [[ ! -d "$DESTINATION" || -L "$DESTINATION" ]]; then
    printf 'Install destination must be an existing, non-symlinked directory: %s\n' "$DESTINATION" >&2
    exit 1
fi
DESTINATION="$(cd -- "$DESTINATION" && pwd -P)"
APP_PATH="$DESTINATION/Nearby Drop.app"
if [[ -L "$APP_PATH" || ( -e "$APP_PATH" && ! -d "$APP_PATH" ) ]]; then
    printf 'Refusing to replace a non-directory or symlink at %s\n' "$APP_PATH" >&2
    exit 1
fi

# Stage on the destination volume. A permissions or copy failure leaves the
# existing application untouched, and no administrator prompt is requested.
STAGE_DIR="$(mktemp -d "$DESTINATION/.nearby-drop-stage.XXXXXX")"
STAGED_APP="$STAGE_DIR/Nearby Drop.app"
"$DITTO_BIN" "$SOURCE_APP" "$STAGED_APP"
if [[ ! -d "$STAGED_APP" || -L "$STAGED_APP" ]]; then
    printf 'The staged app bundle is incomplete.\n' >&2
    exit 1
fi
"$CODESIGN_BIN" --verify --deep --strict "$STAGED_APP"
STAGED_VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$STAGED_APP/Contents/Info.plist")"
if [[ "$STAGED_VERSION" != "$RELEASE_VERSION" ]]; then
    printf 'The staged app version did not match the downloaded release.\n' >&2
    exit 1
fi

if [[ -e "$APP_PATH" ]]; then
    BACKUP_PATH="$DESTINATION/.Nearby Drop.app.backup.$$"
    if [[ -e "$BACKUP_PATH" || -L "$BACKUP_PATH" ]]; then
        printf 'Refusing to overwrite an existing installer backup at %s\n' "$BACKUP_PATH" >&2
        exit 1
    fi
    mv -- "$APP_PATH" "$BACKUP_PATH"
fi
mv -- "$STAGED_APP" "$APP_PATH"
INSTALLED_APP_IDENTITY="$("$STAT_BIN" -f '%d:%i' "$APP_PATH")"
"$CODESIGN_BIN" --verify --deep --strict "$APP_PATH"
INSTALLED_VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [[ "$INSTALLED_VERSION" != "$RELEASE_VERSION" ]]; then
    printf 'The installed app version did not match the downloaded release.\n' >&2
    exit 1
fi

replacement_complete=1
if [[ -n "$BACKUP_PATH" && -e "$BACKUP_PATH" ]]; then
    if rm -rf -- "$BACKUP_PATH"; then
        BACKUP_PATH=""
    else
        printf 'Installed Nearby Drop, but could not remove the previous app backup at %s\n' "$BACKUP_PATH" >&2
    fi
fi
printf 'Nearby Drop %s was installed at %s\n' "$RELEASE_VERSION" "$APP_PATH"
