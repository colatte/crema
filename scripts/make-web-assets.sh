#!/usr/bin/env bash
#
# Derives the landing page's images from the full-size screenshots in
# docs/assets/.
#
# Why a separate set instead of pointing the page at the PNGs: those PNGs are
# the README's media and have to stay full-size and lossless there, but the
# page was shipping 9.1 MB of them into boxes between 1.6x and 3.7x smaller.
# The same six screenshots come out of here at 186 KB total.
#
# The three HUD specimens are also CROPPED, not just resized. Full frame they
# are ~90% empty wallpaper with the indicator in one corner; in a three-column
# grid at ~340 px the subject is a speck and the tile reads as a grey
# rectangle. The crop keeps enough desk around the indicator to say "this sits
# on your screen" and still shows the thing the caption names.
#
# Requires cwebp (brew install webp). Safe to re-run; output is overwritten.

set -euo pipefail

cd "$(dirname "$0")/.."
src="docs/assets"
out="docs/assets/web"
mkdir -p "$out"

# Source screenshots are 1240x776. Each indicator sits at a different height,
# so the crop box travels while the width stays fixed: one aspect ratio across
# the three keeps the grid even.
#            name          crop w  h    x    y
crop_tile () {
  cwebp -quiet -q 80 -m 6 \
    -crop "$3" "$4" "$1" "$2" \
    "$src/$5.png" -o "$out/$5.webp"
}
crop_tile 760 507 240 0   hud-notch
crop_tile 760 507 240 0   hud-card
crop_tile 760 507 240 132 hud-classic

# The style shots keep their whole frame and are only capped at 2x the widest
# box they land in.
for f in notch-expanded card-expanded classic-expanded; do
  cwebp -quiet -q 80 -m 6 -resize 1180 0 "$src/$f.png" -o "$out/$f.webp"
done

# The icon is used at 22 px and 84 px; 256 covers both at 2x and replaces a
# 188 KB master that was being scaled down by up to 23x.
cwebp -quiet -q 90 -m 6 -resize 256 0 "$src/icon.png" -o "$out/icon.webp"

# The favicon stays PNG (broadest <link rel="icon"> support) but never the
# 188 KB master: 128 covers every browser-tab size at 2x. sips is macOS-native,
# so this step adds no dependency beyond the cwebp the rest already needs.
sips -s format png -Z 128 "$src/icon.png" --out "$out/favicon.png" >/dev/null

printf '%s\n' "--- docs/assets/web ---"
du -sh "$out"
ls -l "$out" | awk 'NR>1 {printf "  %6d KB  %s\n", $5/1024, $9}'
