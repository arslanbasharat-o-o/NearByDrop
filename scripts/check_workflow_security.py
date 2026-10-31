#!/usr/bin/env python3
"""Guard the repository's PR/release workflow boundary."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = ROOT / ".github" / "workflows"
BUILD = WORKFLOW_DIR / "build.yml"
RELEASE = WORKFLOW_DIR / "signed-release.yml"
PACKAGE = ROOT / "scripts" / "package-release.sh"


def main() -> int:
    errors: list[str] = []
    workflows = sorted((*WORKFLOW_DIR.glob("*.yml"), *WORKFLOW_DIR.glob("*.yaml")))
    if not workflows:
        errors.append("No GitHub Actions workflow files were found.")

    for path in workflows:
        text = path.read_text(encoding="utf-8")
        if re.search(r"(?m)^\s*pull_request_target\s*:", text):
            errors.append(f"{path.name} must not use pull_request_target.")
        if path != RELEASE and re.search(r"\bsecrets\b", text, re.IGNORECASE):
            errors.append(f"{path.name} references secrets outside the isolated release workflow.")
        if re.search(r"(?m)^\s*pull_request\s*:", text):
            if re.search(r"(?m)^\s*environment\s*:", text):
                errors.append(f"{path.name} must not reference a deployment environment.")
            if re.search(r"(?m)^\s+\w+:\s*write\s*$", text):
                errors.append(f"{path.name} grants a write permission to a pull-request workflow.")

        for action in re.finditer(r"(?m)^\s*uses:\s*[^@\s]+@([^\s#]+)", text):
            if not re.fullmatch(r"[0-9a-f]{40}", action.group(1)):
                errors.append(f"{path.name} uses an action that is not pinned to a full commit SHA.")
                break

    if not BUILD.is_file():
        errors.append("build.yml is missing.")
    else:
        build_text = BUILD.read_text(encoding="utf-8")
        if "scripts/package-release.sh build dist --ci-unsigned" not in build_text:
            errors.append("The CI package job must use --ci-unsigned mode.")
        if "nearby-drop-ci-nonpublic" not in build_text:
            errors.append("The CI artifact name must identify it as nonpublic.")
        if "action-gh-release" in build_text or "generate_appcast" in build_text:
            errors.append("The build workflow must not sign or publish a release.")

    if not RELEASE.is_file():
        errors.append("signed-release.yml is missing.")
    else:
        release_text = RELEASE.read_text(encoding="utf-8")
        for forbidden in ("pull_request:", "pull_request_target:", "workflow_run:", "workflow_dispatch:"):
            if forbidden in release_text:
                errors.append(f"signed-release.yml must not use {forbidden[:-1]}.")
        required_fragments = (
            'tags: ["v*"]',
            "vars.RELEASE_SIGNING_ENABLED == 'true'",
            "startsWith(github.ref, 'refs/tags/v')",
            "name: release-signing",
            "secrets.SPARKLE_PRIVATE_KEY",
            "scripts/package-release.sh build dist --release",
            "contents: write",
        )
        for fragment in required_fragments:
            if fragment not in release_text:
                errors.append(f"signed-release.yml is missing required release gate text: {fragment}")
        if "actions/download-artifact" in release_text or "download-artifact@" in release_text:
            errors.append("The signing workflow must build from its trusted tag checkout, not a transferred artifact.")

    if not PACKAGE.is_file():
        errors.append("scripts/package-release.sh is missing.")
    else:
        package_text = PACKAGE.read_text(encoding="utf-8")
        if "--ci-unsigned" not in package_text or "NONPUBLIC-CI-ARTIFACTS.txt" not in package_text:
            errors.append("The package script must mark unsigned CI output as nonpublic.")
        if "keychain fallback is disabled" not in package_text:
            errors.append("Missing release credentials must fail instead of falling back implicitly.")
        if re.search(r'if \[ -n "\$\{SPARKLE_PRIVATE_KEY:-\}" \]; then\s*\n\s*.*generate_appcast', package_text):
            errors.append("The package script must not sign by implicitly detecting a key.")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Workflow security policy passed for {len(workflows)} workflow files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
