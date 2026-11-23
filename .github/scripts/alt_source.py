"""Stamp unsigned CI builds and publish metadata read from the released IPA."""

import hashlib
import json
import plistlib
import re
import sys
import zipfile
from datetime import datetime
from pathlib import Path
from urllib.parse import quote


def version_tuple(value):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
        raise ValueError(f"Invalid version: {value}")
    parts = [int(part) for part in value.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def stamp(path, run_number):
    if not 0 < run_number < 99_990_000:
        raise ValueError("Run number outside CFBundleVersion limits")
    plist = plistlib.loads(path.read_bytes())
    major, minor, patch = version_tuple(plist["CFBundleShortVersionString"])
    # Increment the visible version as well for SideStore clients that compare it.
    plist["CFBundleShortVersionString"] = f"{major}.{minor}.{patch + run_number}"
    plist["CFBundleVersion"] = f"{1 + run_number // 10000}.{run_number // 100 % 100}.{run_number % 100}"
    path.write_bytes(plistlib.dumps(plist, fmt=plistlib.FMT_BINARY))


def update(path, ipa_path, release_path, repo):
    source = json.loads(path.read_text(encoding="utf-8"))
    release = json.loads(release_path.read_text(encoding="utf-8"))
    if release["draft"] or release["prerelease"]:
        raise ValueError("Expected a published stable release")
    datetime.fromisoformat(release["published_at"])
    asset, = [asset for asset in release["assets"] if asset["name"] == "JARVIS-AI.ipa"]
    url = f"https://github.com/{repo}/releases/download/{quote(release['tag_name'], safe='')}/JARVIS-AI.ipa"
    if asset["browser_download_url"] != url or asset["state"] != "uploaded":
        raise ValueError("Expected the uploaded IPA at the specific release URL")
    if not 0 < asset["size"] == ipa_path.stat().st_size:
        raise ValueError("The IPA size does not match the release")
    with ipa_path.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    if asset.get("digest") and asset["digest"] != f"sha256:{digest}":
        raise ValueError("The IPA digest does not match the release")

    with zipfile.ZipFile(ipa_path) as ipa:
        plist = plistlib.loads(ipa.read("Payload/JarvisAI.app/Info.plist"))
    bundle_id = plist["CFBundleIdentifier"]
    if source["identifier"] != f"{bundle_id}.source":
        raise ValueError("The IPA bundle identifier does not match the source")
    app, = source["apps"]
    if app["bundleIdentifier"] != bundle_id:
        raise ValueError("Refusing to change the app bundle identifier")
    entry = {
        "version": plist["CFBundleShortVersionString"],
        "buildVersion": plist["CFBundleVersion"],
        "date": release["published_at"],
        "downloadURL": url,
        "size": asset["size"],
        "minOSVersion": plist["MinimumOSVersion"],
    }
    history = app["versions"]
    for existing in history:
        if version_tuple(existing["buildVersion"]) == version_tuple(entry["buildVersion"]):
            if existing != entry:
                raise ValueError("Build version already belongs to another release")
            return
    history.append(entry)
    history.sort(key=lambda item: version_tuple(item["buildVersion"]), reverse=True)
    for newer, older in zip(history, history[1:]):
        if version_tuple(newer["version"]) <= version_tuple(older["version"]):
            raise ValueError("App versions must increase with build versions")
    path.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    command, *args = sys.argv[1:]
    if command == "stamp":
        plist, run = args
        stamp(Path(plist), int(run))
    elif command == "update":
        source, ipa, release, repo = args
        update(Path(source), Path(ipa), Path(release), repo)
    else:
        sys.exit(f"Unknown command: {command}")
