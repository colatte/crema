#!/usr/bin/env bash
#
# Captures the landing page's images and videos from the real app, so the site
# shows Crema as it is and is refreshed by running this again, never by hand.
#
# It builds a separate Debug copy (its own bundle id, so its preferences never
# touch the installed app's), runs it on the demo sources with made-up tracks,
# covers every screen with backdrop.swift and drives each state through
# DemoRemote (post.swift). The surfaces drawn are the real ones.
#
# It TAKES OVER THE SCREEN for a few minutes and quits the installed Crema while
# it runs (relaunching it after): run it when nobody is using the Mac. The notch
# shots need a built-in display with a notch. Requires full Xcode and cwebp
# (brew install webp); avconvert ships with macOS.

set -euo pipefail

cd "$(dirname "$0")/../.."
root="$(pwd)"
out="docs/assets/site"
work="$(mktemp -d)"
mkdir -p "$out" "$work/raw"

echo "--- building the capture copy"
xcodebuild -project Crema.xcodeproj -scheme Crema -configuration Debug \
  -derivedDataPath "$work/dd" PRODUCT_BUNDLE_IDENTIFIER=com.colatte.crema.capture build >"$work/build.log" 2>&1 \
  || { echo "build failed: $work/build.log"; exit 1; }
app="$work/dd/Build/Products/Debug/Crema.app"
swiftc -O scripts/site-capture/backdrop.swift -o "$work/backdrop"
swiftc -O scripts/site-capture/post.swift -o "$work/post"
swiftc -O scripts/site-capture/windowid.swift -o "$work/windowid"
swiftc -O scripts/site-capture/screensize.swift -o "$work/screensize"

installed_was_running=0
if pgrep -f "/Applications/Crema.app/Contents/MacOS/Crema" >/dev/null; then
  installed_was_running=1
  osascript -e 'tell application id "com.colatte.crema" to quit' || true
  sleep 2
fi

cleanup() {
  "$work/post" quit 2>/dev/null || true
  [ -n "${stage_pid:-}" ] && kill "$stage_pid" 2>/dev/null || true
  sleep 1
  pkill -f "$work/dd/Build" 2>/dev/null || true
  [ "$installed_was_running" = 1 ] && open -a /Applications/Crema.app || true
}
trap cleanup EXIT

"$work/backdrop" "$root/design/icon/crema-mark.svg" &
stage_pid=$!
sleep 1.5
"$app/Contents/MacOS/Crema" -CremaUseDemoSources YES -hasSeenWelcomeTour YES -AppleLanguages "(en)" >"$work/app.log" 2>&1 &
app_pid=$!
sleep 3

say() { "$work/post" "$@"; }
# Regions in points, top-left origin of the main display; captured at 2x. Taken
# from the display's own size, so any MacBook frames the same picture: the
# notch's neighbourhood, the menu bar's right corner, the bottom block.
read -r screen_w screen_h < <("$work/screensize")
w=560
mid=$(( (screen_w - w) / 2 ))
top="$mid,0,$w,200"
corner="$(( screen_w - w )),0,$w,200"
bottom="$mid,$(( screen_h - 430 )),$w,420"
# The three styles share one frame on the page, so one size: the top's region
# taken as tall as the bottom's.
tall="$mid,0,$w,420"
shot() { screencapture -x -R"$2" "$work/raw/$1.png"; }
window_shot() { screencapture -x -o -l"$("$work/windowid" "$app_pid")" "$work/raw/$1.png"; }

echo "--- notch"
say style notch; sleep 1.5
screencapture -x -v -V 10 -R"$top" "$work/raw/hero.mov" &
rec=$!
sleep 0.8; say next; say play
sleep 3.4; say invoke
sleep 3.2; say route airPods; say hud volume 0.5
sleep 0.3; say hud volume 0.56
sleep 0.3; say hud volume 0.62
wait "$rec"
sleep 4
say next; sleep 0.9; shot notch-compact "$top"
sleep 3.2; say invoke; sleep 1.2; shot notch-expanded "$top"; shot style-notch "$tall"
say hud volume 0.62; sleep 0.5; shot notch-hud "$top"
sleep 5

echo "--- card"
say style card; sleep 2
say invoke; sleep 1.2; shot card-expanded "$top"; shot style-card "$tall"
sleep 5.5
say hud screenBrightness 0.7; sleep 0.5; shot card-hud "$top"
sleep 2
say indicator filled; say route builtInSpeakers; say hud volume 0.62; sleep 0.5; shot card-filled "$top"
sleep 2
say indicator slider; say place topRight; sleep 1; say hud volume 0.62; sleep 0.5; shot card-place "$corner"
say place topCenter; say indicator slider; sleep 2

echo "--- classic"
say style classic; sleep 2
say invoke; sleep 1.2; shot style-classic "$bottom"
sleep 5.5

echo "--- tour"
say style notch; say appearance dark; sleep 1.5
for step in welcome accessibility; do
  say tour "$step"; sleep 1
  osascript -e 'tell application id "com.colatte.crema.capture" to activate' || true
  sleep 1; window_shot "tour-$step"
  say tour close; sleep 0.8
done

echo "--- encoding"
# The folder holds this run's output and nothing else, so a capture this run
# no longer takes cannot linger from an earlier one.
rm -rf "$out" && mkdir -p "$out"
for f in "$work"/raw/*.png; do
  cwebp -quiet -q 84 -m 6 "$f" -o "$out/$(basename "${f%.png}").webp"
done
avconvert -s "$work/raw/hero.mov" -p Preset1920x1080 -o "$out/hero.mp4" --replace >/dev/null
du -sh "$out"
ls -l "$out" | awk 'NR>1 {printf "  %6d KB  %s\n", $5/1024, $9}'
echo "raw captures kept in $work/raw"
