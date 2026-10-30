#!/usr/bin/env python3
"""Build a minimal IndexNow payload from changed published HTML pages."""

import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
from urllib.parse import quote


SITE = "https://arslanbasharat-o-o.github.io/NearByDrop/"
KEY_FILE = Path("docs/5647534b0fe64589927ee2557c53be8c.txt")


def page_url(path):
    relative = PurePosixPath(path).relative_to("docs")
    if relative.as_posix() == "index.html":
        return SITE
    return SITE + quote(relative.as_posix(), safe="/:@-._~")


def changed_html_urls(base, head):
    paths = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", "-z", base, head, "--", "docs"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split("\0")
    return sorted({page_url(path) for path in paths if path.endswith(".html")})


def main():
    assert page_url("docs/index.html") == SITE
    assert page_url("docs/blog/a b.html") == SITE + "blog/a%20b.html"
    key = KEY_FILE.read_text(encoding="utf-8").strip()
    if KEY_FILE.stem != key or not (8 <= len(key) <= 128) or not all(
        (character.isascii() and character.isalnum()) or character in "-_" for character in key
    ):
        raise ValueError("IndexNow key file name and contents must match.")
    payload = {
        "host": "arslanbasharat-o-o.github.io",
        "key": key,
        "keyLocation": SITE + KEY_FILE.name,
        "urlList": changed_html_urls(sys.argv[1], sys.argv[2]),
    }
    print(json.dumps(payload))


if __name__ == "__main__":
    main()
