#!/usr/bin/env bash
#
# Derives the landing page's icon and favicon from the icon's web export,
# docs/assets/icon.png (written by design/icon/makeicon.swift).
#
# The page draws the app in HTML instead of showing screenshots, so the icon is
# the only image it loads; it is used at 26 px and up to 120 px, and 256 covers
# both at 2x in place of the full-size master.
#
# Requires cwebp (brew install webp). Safe to re-run; output is overwritten.

set -euo pipefail

cd "$(dirname "$0")/.."
src="docs/assets"
out="docs/assets/web"
mkdir -p "$out"

cwebp -quiet -q 90 -m 6 -resize 256 0 "$src/icon.png" -o "$out/icon.webp"

# The favicon stays PNG (broadest <link rel="icon"> support) but never the
# full-size master: 128 covers every browser-tab size at 2x. sips is
# macOS-native, so this step adds no dependency beyond cwebp.
sips -s format png -Z 128 "$src/icon.png" --out "$out/favicon.png" >/dev/null

printf '%s\n' "--- docs/assets/web ---"
du -sh "$out"
ls -l "$out" | awk 'NR>1 {printf "  %6d KB  %s\n", $5/1024, $9}'
