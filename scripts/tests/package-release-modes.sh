#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/nearby-drop-package-mode-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

if env -u SPARKLE_PRIVATE_KEY "$root/scripts/package-release.sh" "$tmp/missing-derived" "$tmp/release-out" --release >"$tmp/release.log" 2>&1; then
    echo "Release packaging succeeded without the required signing secret." >&2
    exit 1
fi
if ! grep -Fq "Release mode requires SPARKLE_PRIVATE_KEY; keychain fallback is disabled." "$tmp/release.log"; then
    echo "Missing release credentials did not fail with the explicit signing guard." >&2
    cat "$tmp/release.log" >&2
    exit 1
fi

if env -u SPARKLE_PRIVATE_KEY "$root/scripts/package-release.sh" "$tmp/missing-derived" "$tmp/ci-out" --ci-unsigned >"$tmp/ci.log" 2>&1; then
    echo "Unsigned packaging unexpectedly succeeded without a built app." >&2
    exit 1
fi
if [ -e "$tmp/ci-out/appcast.xml" ]; then
    echo "Unsigned CI mode created an appcast." >&2
    exit 1
fi

echo "Package mode guards passed."
