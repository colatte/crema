#!/usr/bin/env bash
#
# release.sh — build a production Crema.app and package it as Crema.dmg for a
# GitHub release. Run on the author's Mac (macOS + full Xcode); the author then
# uploads the .dmg to a release (see docs/internal/RELEASE-GUIDE.md).
#
#   ./scripts/release.sh <version>        e.g. ./scripts/release.sh 1.0.0
#
# What it does:
#   1. Validate the version argument and the toolchain.
#   2. Archive the Crema scheme in Release — this compiles out the `#if DEBUG`
#      demos and optimizes — stamping <version> as the app's MARKETING_VERSION.
#   3. Extract Crema.app from the archive.
#   4. Package Crema.app + an /Applications shortcut into Crema.dmg.
#   5. Leave Crema.dmg in the repo root and remove the intermediate build/.
#
# Why unsigned: Crema is distributed without a Developer ID signature or
# notarization (documented in the README's "First launch"). So the build runs
# with signing disabled — the same flags the CI uses — and users clear the
# quarantine flag on first launch. Do NOT add signing here without also updating
# the README.
#
# Why the name is exactly Crema.dmg: GitHub exposes the newest release asset at
#   https://github.com/vctorgriggi/crema/releases/latest/download/Crema.dmg
# and the README points users at a file called Crema.dmg. A different filename
# would silently break that direct-download URL, so the name is fixed here.
#
# Requirements:
#   - Full Xcode (not just the Command Line Tools) — `archive` needs it. If the
#     active developer dir is only the CLT, the script points DEVELOPER_DIR at
#     /Applications/Xcode.app for this run.
#   - create-dmg (optional, recommended) for the standard drag-to-Applications
#     layout:  brew install create-dmg
#     Without it the script falls back to hdiutil — same contents (app +
#     /Applications symlink), plainer window. create-dmg is preferred because it
#     positions the icons and hides the .app extension; hdiutil is the
#     dependency-free safety net so the script never hard-blocks on a missing brew.

set -euo pipefail

# --- output helpers ----------------------------------------------------------

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
    BOLD=''; RED=''; GREEN=''; BLUE=''; RESET=''
fi

step() { printf '%s==>%s %s\n' "$BLUE$BOLD" "$RESET$BOLD" "$*$RESET"; }
info() { printf '    %s\n' "$*"; }
fail() { printf '%sError:%s %s\n' "$RED$BOLD" "$RESET" "$*" >&2; exit 1; }

# --- locate the repo (works from any CWD) ------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/Crema.xcodeproj"
[[ -d "$PROJECT" ]] || fail "Crema.xcodeproj not found at $PROJECT — is this the Crema repo?"

# --- argument: version -------------------------------------------------------

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf 'Usage: %s <version>\n  e.g. %s 1.0.0\n' "$0" "$0"
    exit 0
fi

VERSION="${1:-}"
[[ -n "$VERSION" ]] || fail "Missing version. Usage: ./scripts/release.sh <version>  (e.g. 1.0.0)"
VERSION="${VERSION#v}"   # tolerate a leading "v" (v1.0.0 -> 1.0.0)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "Version must be MAJOR.MINOR.PATCH (e.g. 1.0.0), got: '$VERSION'"
TAG="v$VERSION"

# --- toolchain ---------------------------------------------------------------

# `xcodebuild archive` needs a full Xcode. If the active developer dir is only
# the Command Line Tools, point DEVELOPER_DIR at Xcode.app for this process.
step "Checking toolchain"
CURRENT_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$CURRENT_DEV_DIR" == *"Xcode"*"/Developer"* ]]; then
    export DEVELOPER_DIR="$CURRENT_DEV_DIR"
elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    info "Command Line Tools are active; using /Applications/Xcode.app for this build."
else
    fail "Full Xcode is required (the Command Line Tools alone cannot archive).
    Install Xcode, then either run 'sudo xcode-select -s /Applications/Xcode.app'
    or place it at /Applications/Xcode.app."
fi
xcodebuild -version >/dev/null 2>&1 || fail "xcodebuild is not usable under DEVELOPER_DIR=$DEVELOPER_DIR"
info "Xcode: $(xcodebuild -version | head -1)  ·  DEVELOPER_DIR=$DEVELOPER_DIR"

USE_CREATE_DMG=1
command -v create-dmg >/dev/null 2>&1 || USE_CREATE_DMG=0

# --- paths -------------------------------------------------------------------

APP_NAME="Crema.app"
DMG_NAME="Crema.dmg"                       # fixed — see header
VOL_NAME="Crema"
BUILD_DIR="$REPO_ROOT/build/release"       # under gitignored build/
ARCHIVE="$BUILD_DIR/Crema.xcarchive"
DMG_SRC="$BUILD_DIR/dmg-src"               # holds only Crema.app for packaging
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
DMG_OUT="$REPO_ROOT/$DMG_NAME"

# Start clean so a stale archive or half-built .dmg can't leak into the release.
step "Preparing a clean build ($TAG)"
rm -rf "$BUILD_DIR"
rm -f "$DMG_OUT"
mkdir -p "$BUILD_DIR"
info "Intermediates: $BUILD_DIR"

# --- 1. archive (Release, unsigned) ------------------------------------------

step "Archiving Crema in Release (this can take a few minutes)"
# MARKETING_VERSION="$VERSION" stamps CFBundleShortVersionString so the built
# app reports the release version. Signing is disabled (matches CI). Output is
# tee'd to a log so a failure leaves something to read.
if ! xcodebuild archive \
        -project "$PROJECT" \
        -scheme Crema \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE" \
        MARKETING_VERSION="$VERSION" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
        2>&1 | tee "$BUILD_LOG"; then
    fail "xcodebuild archive failed. See the log above (also saved at $BUILD_LOG)."
fi

APP_SRC="$ARCHIVE/Products/Applications/$APP_NAME"
[[ -d "$APP_SRC" ]] || fail "Build succeeded but $APP_NAME was not found at $APP_SRC."

# Sanity: confirm the app reports the version we asked for. A mismatch usually
# means the project stopped deriving its version from MARKETING_VERSION.
BUILT_VERSION="$(defaults read "$APP_SRC/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?')"
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
    info "${RED}Warning:${RESET} built app reports version $BUILT_VERSION, expected $VERSION — reconcile before publishing."
else
    info "Built $APP_NAME reports version $BUILT_VERSION."
fi

# --- 2. package into Crema.dmg -----------------------------------------------

step "Packaging $DMG_NAME"
rm -rf "$DMG_SRC"
mkdir -p "$DMG_SRC"
cp -R "$APP_SRC" "$DMG_SRC/$APP_NAME"

if [[ "$USE_CREATE_DMG" == "1" ]]; then
    info "Using create-dmg (drag-to-Applications layout)."
    # create-dmg adds the /Applications shortcut itself via --app-drop-link, so
    # DMG_SRC contains only the app. It occasionally exits non-zero on a Finder/
    # AppleScript hiccup even after writing the .dmg, so success is judged by the
    # file existing, not solely by the exit code. (Run in a normal desktop
    # session — over SSH the Finder window step can't run and it falls short.)
    create-dmg \
        --volname "$VOL_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 128 \
        --icon "$APP_NAME" 150 190 \
        --hide-extension "$APP_NAME" \
        --app-drop-link 450 190 \
        --no-internet-enable \
        "$DMG_OUT" "$DMG_SRC" || true
    [[ -f "$DMG_OUT" ]] || fail "create-dmg did not produce $DMG_NAME. Re-run in a desktop session, or uninstall create-dmg to use the hdiutil fallback."
else
    info "create-dmg not found; using hdiutil fallback (plainer layout). For the nicer window: brew install create-dmg"
    # hdiutil path: stage the app next to an /Applications symlink, then image
    # the folder. UDZO = compressed, read-only — the standard distribution format.
    ln -s /Applications "$DMG_SRC/Applications"
    hdiutil create \
        -volname "$VOL_NAME" \
        -srcfolder "$DMG_SRC" \
        -ov -format UDZO \
        "$DMG_OUT" >/dev/null || fail "hdiutil failed to create $DMG_NAME."
fi

[[ -f "$DMG_OUT" ]] || fail "Packaging finished but $DMG_OUT is missing."

# --- 3. cleanup + summary ----------------------------------------------------

step "Cleaning intermediates"
rm -rf "$BUILD_DIR"

DMG_SIZE="$(du -h "$DMG_OUT" | cut -f1 | tr -d ' ')"
printf '\n%s✓ %s ready%s\n' "$GREEN$BOLD" "$DMG_NAME" "$RESET"
info "File:    $DMG_OUT ($DMG_SIZE)"
info "Version: $VERSION   ·   Tag to publish: $TAG"
printf '\n%sNext%s — test it, then publish (see docs/internal/RELEASE-GUIDE.md):\n' "$BOLD" "$RESET"
info "1. open \"$DMG_OUT\"   → drag Crema into Applications, confirm it launches."
info "2. gh release create $TAG \"$DMG_OUT\" --title \"Crema $VERSION\" --notes \"…\""
