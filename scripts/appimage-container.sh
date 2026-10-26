#!/usr/bin/env bash
set -euo pipefail
cd /src
version="$(python3 scripts/packaging.py version)"
export DESTDIR=/work/AppDir
bash scripts/offline-build.sh /usr
desktop="$DESTDIR/usr/share/applications/de.magynhard.DiskView.desktop"
icon="$DESTDIR/usr/share/icons/hicolor/scalable/apps/de.magynhard.DiskView.svg"
desktop-file-validate "$desktop"
appstreamcli validate --no-net "$DESTDIR/usr/share/metainfo/de.magynhard.DiskView.metainfo.xml"
export APPIMAGE_EXTRACT_AND_RUN=1 DEPLOY_GTK_VERSION=4
linuxdeploy.AppImage --appdir "$DESTDIR" --desktop-file "$desktop" --icon-file "$icon" --plugin gtk

# The upstream GTK plugin forces X11 and a fixed theme. Its resource bundling
# is useful, but replace that hook so Adwaita can follow the real system style.
install -m755 packaging/appimage/gtk-runtime.sh "$DESTDIR/apprun-hooks/linuxdeploy-plugin-gtk.sh"
mkdir -p "$DESTDIR/usr/lib/gio/modules" "$DESTDIR/usr/share/icons" "/output"
install -m755 /usr/lib/x86_64-linux-gnu/gio/modules/libdconfsettings.so "$DESTDIR/usr/lib/gio/modules/"
gio-querymodules "$DESTDIR/usr/lib/gio/modules"
cp -a /usr/share/icons/Adwaita "$DESTDIR/usr/share/icons/"
for language in $(<po/LINGUAS); do
    for domain in gtk40 libadwaita glib20; do
        catalog="/usr/share/locale/$language/LC_MESSAGES/$domain.mo"
        if [[ -f "$catalog" ]]; then
            install -Dm644 "$catalog" "$DESTDIR/usr/share/locale/$language/LC_MESSAGES/$domain.mo"
        fi
    done
done
for directory in /usr/share/doc/*; do
    if [[ -f "$directory/copyright" ]]; then
        install -Dm644 "$directory/copyright" "$DESTDIR/usr/share/licenses/de.magynhard.DiskView/system/$(basename "$directory").copyright"
    fi
done
dpkg-query -W > "$DESTDIR/usr/share/licenses/de.magynhard.DiskView/build-packages.txt"
cp packaging/sources.json "$DESTDIR/usr/share/licenses/de.magynhard.DiskView/sources.json"
export LDAI_OUTPUT="/output/Disk_View-${version}-x86_64.AppImage"
export LDAI_RUNTIME_FILE=/opt/tools/runtime-x86_64
linuxdeploy.AppImage --appdir "$DESTDIR" --library "$DESTDIR/usr/lib/gio/modules/libdconfsettings.so" --output appimage
cd /output
sha256sum "Disk_View-${version}-x86_64.AppImage" > "Disk_View-${version}-x86_64.AppImage.sha256"
chown -R "${OUTPUT_UID:-0}:${OUTPUT_GID:-0}" /output
