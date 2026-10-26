#!/usr/bin/env bash
set -euo pipefail

prefix="${1:?Expected the Flatpak files directory}"
app_id=de.magynhard.DiskView

# Flatpak bundles embed PNG icons, even when newer AppStream defaults to JPEG XL.
image_format=()
if [[ "$(appstreamcli compose --help)" == *"--image-format"* ]]; then
    image_format=(--image-format=png)
fi
appstreamcli compose --no-net --prefix=/ --origin="$app_id" \
    --result-root="$prefix" \
    --data-dir="$prefix/share/app-info/xmls" \
    --icons-dir="$prefix/share/app-info/icons/flatpak" \
    --components="$app_id" "${image_format[@]}" "$prefix"

test -s "$prefix/share/app-info/xmls/$app_id.xml.gz"
for size in 64 128; do
    test -s "$prefix/share/app-info/icons/flatpak/${size}x${size}/$app_id.png"
done
