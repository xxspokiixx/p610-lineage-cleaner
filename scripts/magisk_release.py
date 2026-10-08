#!/usr/bin/env python3
"""Pick the official stable Magisk APK from a GitHub release JSON document."""

import json
import sys

PREFIX = "https://github.com/topjohnwu/Magisk/releases/download/"


def main() -> None:
    try:
        release = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Magisk release JSON is not valid: {exc}") from exc
    if not isinstance(release, dict):
        raise SystemExit("Magisk release JSON is not an object")
    if release.get("prerelease") is True:
        raise SystemExit("Refusing a Magisk prerelease")
    if release.get("draft") is True:
        raise SystemExit("Refusing a Magisk draft")
    tag = release.get("tag_name")
    if not isinstance(tag, str) or len(tag) < 2 or not tag.startswith("v"):
        raise SystemExit("Unexpected Magisk tag")
    if "/" in tag or ".." in tag or "\\" in tag:
        raise SystemExit("Unexpected Magisk tag")
    assets = release.get("assets")
    if not isinstance(assets, list):
        raise SystemExit("Magisk release has no assets")
    name = f"Magisk-{tag}.apk"
    chosen = None
    for asset in assets:
        if isinstance(asset, dict) and asset.get("name") == name:
            chosen = asset
            break
    if chosen is None:
        raise SystemExit(f"Release has no {name}")
    url = chosen.get("browser_download_url")
    size = chosen.get("size")
    if not isinstance(url, str) or not isinstance(size, int) or size < 1000000:
        raise SystemExit("Bad Magisk asset")
    if url != f"{PREFIX}{tag}/{name}":
        raise SystemExit("Refusing a Magisk URL that is not the official GitHub release")
    sys.stdout.write(f"{url}\n{size}\n{tag}\n")


if __name__ == "__main__":
    main()
