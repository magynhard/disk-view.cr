#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[[ "$(uname -m)" == x86_64 ]] || { printf '%s\n' 'AppImage builds currently require an x86_64 host.' >&2; exit 1; }
python3 scripts/packaging.py verify
mkdir -p dist
image=disk-view-appimage-builder
docker build --platform linux/amd64 --file packaging/appimage/Dockerfile --tag "$image" .
docker run --rm --platform linux/amd64 \
    --env OUTPUT_UID="$(id -u)" --env OUTPUT_GID="$(id -g)" \
    --volume "$root/dist:/output" "$image"
