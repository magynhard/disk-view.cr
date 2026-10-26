#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
version="$(python3 scripts/packaging.py version)"
python3 scripts/packaging.py flatpak-manifest "$root/build/flatpak"
mkdir -p dist
repo="${FLATPAK_REPO_DIR:-$root/build/flatpak/repo}"
if [[ ! -f "$repo/config" ]]; then
    mkdir -p "$repo"
    ostree --repo="$repo" init --mode=archive
fi
# OSTree's default 3% reserve can reject a tiny package on a large, mostly full
# disk. Keep a fixed reserve in this generated local repo, not in user remotes.
ostree --repo="$repo" config set core.min-free-space-percent 0
ostree --repo="$repo" config set core.min-free-space-size 512MB
flatpak-builder --user --force-clean --disable-rofiles-fuse \
    "$root/build/flatpak/app" "$root/build/flatpak/de.magynhard.DiskView.json"
bash scripts/flatpak-compose.sh "$root/build/flatpak/app/files"
flatpak build-export "$repo" "$root/build/flatpak/app"
flatpak build-bundle --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo "$repo" \
    "$root/dist/Disk_View-${version}-$(uname -m).flatpak" de.magynhard.DiskView
cd dist
sha256sum "Disk_View-${version}-$(uname -m).flatpak" > "Disk_View-${version}-$(uname -m).flatpak.sha256"
