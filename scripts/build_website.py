#!/usr/bin/env python3
"""Build the static product website with verified GitHub Release download links."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
API = "https://api.github.com/repos/tombang/rightkey/releases/latest"
DOWNLOAD_PREFIX = "https://github.com/tombang/rightkey/releases/download/"
# Keep local configuration and unrelated files out of the published site, even
# when they exist in website/. Add new public assets explicitly here.
PUBLIC_FILES = (
    "index.html",
    "404.html",
    "styles.css",
    "app.js",
    "CNAME",
    "robots.txt",
    "sitemap.xml",
    "assets/icon.svg",
    "assets/social.png",
)


def release_metadata(data):
    tag = data["tag_name"]
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Latest release must have a stable vMAJOR.MINOR.PATCH tag")
    version = tag[1:]
    assets = {asset["name"]: asset["browser_download_url"] for asset in data["assets"]}
    archive = f"RightKey-{version}.zip"
    download = assets[archive]
    checksum = assets[archive + ".sha256"]
    if not all(url.startswith(DOWNLOAD_PREFIX + tag + "/") for url in (download, checksum)):
        raise ValueError("Release assets must belong to the official RightKey repository")
    return {
        "version": version,
        "download": download,
        "checksum": checksum,
        "page": f"https://github.com/tombang/rightkey/releases/tag/{tag}",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-json", type=Path, help="Use a cached GitHub release response")
    args = parser.parse_args()
    if args.release_json:
        data = json.loads(args.release_json.read_text(encoding="utf-8"))
    else:
        headers = {"Accept": "application/vnd.github+json", "User-Agent": "RightKey-Website"}
        if token := os.environ.get("GH_TOKEN"):
            headers["Authorization"] = "Bearer " + token
        with urlopen(Request(API, headers=headers), timeout=30) as response:
            data = json.load(response)
    metadata = release_metadata(data)
    output = ROOT / ".build" / "website"
    if output.is_symlink() or output.parent.is_symlink():
        raise ValueError("Website build directory must not be a symlink")
    if output.exists():
        shutil.rmtree(output)
    source_root = (ROOT / "website").resolve()
    for relative_path in PUBLIC_FILES:
        source = source_root / relative_path
        if not source.resolve().is_relative_to(source_root):
            raise ValueError(f"Public website file points outside website/: {relative_path}")
        destination = output / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    (output / "release.js").write_text(
        "window.RIGHTKEY_RELEASE = " + json.dumps(metadata, ensure_ascii=False) + ";\n",
        encoding="utf-8",
    )
    (output / ".nojekyll").touch()
    print(f"Built RightKey website for v{metadata['version']} at {output}")


if __name__ == "__main__":
    main()
