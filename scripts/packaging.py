#!/usr/bin/env python3
"""Pinned packaging inputs and a LOCAL, AI-assisted Flatpak development build.

The generated manifest is not a Flathub submission manifest. See doc/packaging.md.
Requires Python 3.12+, PyYAML and git; networking is confined to source downloads.
"""

import argparse
import hashlib
import json
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_ID = "de.magynhard.DiskView"
PINS = json.loads((ROOT / "packaging/sources.json").read_text())


def verify(root=ROOT):
    import yaml

    lock = yaml.safe_load((root / "shard.lock").read_text())["shards"]
    if set(lock) != set(PINS["shards"]):
        raise ValueError("Packaging shard set differs from shard.lock; update packaging/sources.json")
    for name, source in PINS["shards"].items():
        if str(lock[name]["version"]) != source["version"] or lock[name]["git"].lower() != source["url"].lower():
            raise ValueError(f"Packaging pin for {name} differs from shard.lock")
        if not re.fullmatch(r"[a-f0-9]{40}", source["commit"]):
            raise ValueError(f"Invalid immutable commit for {name}")
    version = str(yaml.safe_load((root / "shard.yml").read_text())["version"])
    metadata = root / f"data/{APP_ID}.metainfo.xml"
    if metadata.exists():
        component = ET.parse(metadata).getroot()
        if component.findtext("id") != APP_ID or component.find("releases/release").get("version") != version:
            raise ValueError("AppStream ID/release version differs from the application")
    return version


def download(source, cache):
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / source["sha256"]
    if not path.exists():
        temporary = path.with_suffix(".part")
        subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--silent", "--show-error", source["url"], "-o", str(temporary)], check=True)
        temporary.replace(path)
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != source["sha256"]:
        raise ValueError(f"SHA-256 mismatch: {source['url']}")
    return path


def fetch_tools(destination):
    architecture = platform.machine()
    if architecture != "x86_64":
        raise ValueError("The AppImage builder currently targets native x86_64 only")
    destination.mkdir(parents=True, exist_ok=True)
    cache = destination / ".downloads"
    source = PINS["crystal"][architecture]
    compiler = destination / "crystal"
    marker = compiler / ".source-sha256"
    if compiler.exists():
        if not marker.exists() or marker.read_text().strip() != source["sha256"]:
            raise ValueError(f"Remove the outdated generated tool directory: {compiler}")
    else:
        archive = download(source, cache)
        with tempfile.TemporaryDirectory(dir=destination) as temporary:
            with tarfile.open(archive) as tar:
                tar.extractall(temporary, filter="data")
            roots = list(Path(temporary).iterdir())
            if len(roots) != 1 or not roots[0].is_dir():
                raise ValueError("Unexpected Crystal archive layout")
            shutil.move(str(roots[0]), compiler)
        marker.write_text(source["sha256"] + "\n")
    for key, filename in (("linuxdeploy", "linuxdeploy.AppImage"), ("gtk_plugin", "linuxdeploy-plugin-gtk.sh"), ("appimage_runtime", "runtime-x86_64")):
        target = destination / filename
        shutil.copyfile(download(PINS[key], cache), target)
        target.chmod(0o755)


def fetch_shards(destination):
    verify()
    destination.mkdir(parents=True, exist_ok=True)
    for name, source in PINS["shards"].items():
        target = destination / name
        if target.exists():
            revision = subprocess.check_output(["git", "-C", str(target), "rev-parse", "HEAD"], text=True).strip()
            if revision != source["commit"]:
                raise ValueError(f"Unexpected revision in {target}; use an empty generated directory")
            continue
        target.mkdir()
        subprocess.run(["git", "init", "--quiet", str(target)], check=True)
        subprocess.run(["git", "-C", str(target), "fetch", "--quiet", "--depth=1", source["url"], source["commit"]], check=True)
        subprocess.run(["git", "-C", str(target), "checkout", "--quiet", "--detach", "FETCH_HEAD"], check=True)


def flatpak_manifest(destination):
    verify()
    destination.mkdir(parents=True, exist_ok=True)
    snapshot = destination / "source"
    if snapshot.exists():
        shutil.rmtree(snapshot)
    shutil.copytree(ROOT, snapshot, ignore=shutil.ignore_patterns(".git", ".idea", "lib", "bin", "build", "dist", ".flatpak-builder", "*.mo", "*.gresource", "__pycache__"))
    sources = [{"type": "dir", "path": str(snapshot)}]
    for architecture in ("x86_64", "aarch64"):
        sources.append({"type": "archive", **PINS["crystal"][architecture], "dest": "crystal", "strip-components": 2, "only-arches": [architecture]})
    for name, source in PINS["shards"].items():
        sources.append({"type": "git", "url": source["url"], "commit": source["commit"], "dest": f"lib/{name}"})
    manifest = {
        "app-id": APP_ID,
        "runtime": "org.gnome.Platform",
        "runtime-version": "51",
        "sdk": "org.gnome.Sdk",
        "separate-locales": False,
        "appstream-compose": False,
        "command": "disk-view",
        "x-local-development-only": "AI-assisted local packaging; NOT a Flathub submission manifest. See doc/packaging.md.",
        "finish-args": ["--require-version=1.17.0", "--socket=wayland", "--socket=fallback-x11", "--share=ipc", "--device=dri", "--filesystem=host-root:ro", "--filesystem=/run/udev:ro", "--system-talk-name=org.freedesktop.UDisks2"],
        "cleanup": ["/include", "/lib/pkgconfig", "/lib/*.la", "/share/man", "/share/doc"],
        "modules": [
            {"name": "bdw-gc", "buildsystem": "autotools", "config-opts": ["--disable-static"], "post-install": [f"install -Dm644 README.QUICK /app/share/licenses/{APP_ID}/bdw-gc/README.QUICK"], "sources": [{"type": "archive", **PINS["gc"]}]},
            {"name": "disk-view", "buildsystem": "simple", "build-options": {"prepend-path": "/run/build/disk-view/crystal/bin"}, "build-commands": ["bash scripts/offline-build.sh /app"], "sources": sources},
        ],
    }
    path = destination / f"{APP_ID}.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(path)


def licenses(prefix):
    destination = prefix / "share/licenses" / APP_ID
    for name in PINS["shards"]:
        for pattern in ("LICENSE*", "COPYING*"):
            for path in (ROOT / "lib" / name).glob(pattern):
                if path.is_file():
                    target = destination / "shards" / name / path.name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(path, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["verify", "version", "fetch-tools", "fetch-shards", "flatpak-manifest", "licenses"])
    parser.add_argument("destination", nargs="?", type=Path)
    args = parser.parse_args()
    if args.command in ("verify", "version"):
        print(verify())
    else:
        if args.destination is None:
            parser.error("destination is required")
        {"fetch-tools": fetch_tools, "fetch-shards": fetch_shards, "flatpak-manifest": flatpak_manifest, "licenses": licenses}[args.command](args.destination.resolve())


if __name__ == "__main__":
    main()
