#!/usr/bin/env python3
"""Check the public release references against the authoritative release metadata."""

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    metadata = json.loads((ROOT / "scripts/release-version.json").read_text(encoding="utf-8"))
    version = metadata["version"]
    build = metadata["build"]
    tag = f"v{version}"
    dmg_name = f"Nearby-Drop-{version}.dmg"
    dmg_url = f"https://github.com/arslanbasharat-o-o/NearByDrop/releases/download/{tag}/{dmg_name}"
    errors: list[str] = []

    def require(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    project = (ROOT / "NearByDrop.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    site = (ROOT / "docs/index.html").read_text(encoding="utf-8")
    llms = (ROOT / "docs/llms.txt").read_text(encoding="utf-8")
    components = (ROOT / "scripts/site-components.tsx").read_text(encoding="utf-8")
    installer = (ROOT / "scripts/install.sh").read_text(encoding="utf-8")

    changelog_headings = [line for line in changelog.splitlines() if line.startswith("# ")]
    current_heading = f"# {version} ({build})"
    if changelog_headings and changelog_headings[0] == "# Unreleased":
        require(
            len(changelog_headings) >= 2 and changelog_headings[1] == current_heading,
            "CHANGELOG.md must place the current version immediately after Unreleased.",
        )
    else:
        require(
            bool(changelog_headings) and changelog_headings[0] == current_heading,
            "CHANGELOG.md must start with the current version and build, optionally after Unreleased.",
        )
    marketing_versions = re.findall(r"MARKETING_VERSION = ([^;]+);", project)
    require(bool(marketing_versions) and set(marketing_versions) == {version}, "Xcode MARKETING_VERSION values do not match release-version.json.")
    project_builds = re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", project)
    require(project_builds.count(build) >= 4, "App and Share Extension build numbers do not match release-version.json.")

    require(f'"softwareVersion": "{version}"' in site, "Website JSON-LD softwareVersion is stale.")
    require(dmg_url in site, "Website download links do not point to the current release DMG.")
    require(f"DOWNLOAD FOR MAC · {tag.upper()}" in site, "Website download label is stale.")
    require(f"current {tag} release" in site, "Website current-release copy is stale.")
    require(f"Current public release: Nearby Drop {tag} (checked " in llms, "docs/llms.txt has a stale current-release statement.")
    require(components.count(dmg_url) == 2, "Both generated site download buttons must use the current release DMG.")
    require(f"DOWNLOAD FOR MAC · {tag.upper()}" in components, "Site component download label is stale.")
    require("releases/latest" in installer and "xattr -cr" not in installer, "Installer must resolve latest release metadata and preserve Gatekeeper quarantine.")
    require("releases/download/v2.3.4/Nearby-Drop-2.3.4.dmg" not in site + components + llms + installer, "A stale current-release DMG reference remains.")

    generated = ROOT / "docs/assets/site-components.js"
    if generated.exists():
        bundle = generated.read_text(encoding="utf-8")
        require(bundle.count(dmg_url) == 2, "Committed site component bundle is stale; rebuild it from site-components.tsx.")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Release references agree on {tag} (build {build}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
