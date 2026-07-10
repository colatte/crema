#!/usr/bin/env bash
#
# release.sh — build a production Crema.app and package it as Crema.dmg.
# Usage: ./scripts/release.sh <version>   (e.g. ./scripts/release.sh 1.0.0)
#
# Signing modes: ad-hoc by default; Developer ID when CREMA_SIGN_IDENTITY is set
# (a "Developer ID Application: …" cert), then notarized via the CREMA_NOTARY_PROFILE
# keychain profile (default "CremaNotary").
# Dependencies: full Xcode; create-dmg optional (hdiutil fallback); the Developer ID
# path needs the cert + notary profile. See docs/internal/RELEASE-GUIDE.md.

set -euo pipefail

# Output helpers

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
    BOLD=''; RED=''; GREEN=''; BLUE=''; RESET=''
fi

step() { printf '%s==>%s %s\n' "$BLUE$BOLD" "$RESET$BOLD" "$*$RESET"; }
info() { printf '    %s\n' "$*"; }
fail() { printf '%sError:%s %s\n' "$RED$BOLD" "$RESET" "$*" >&2; exit 1; }

# Locate the repo (works from any CWD)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/Crema.xcodeproj"
[[ -d "$PROJECT" ]] || fail "Crema.xcodeproj not found at $PROJECT — is this the Crema repo?"

# Argument: version

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf 'Usage: %s <version>\n  e.g. %s 1.0.0\n' "$0" "$0"
    exit 0
fi

VERSION="${1:-}"
[[ -n "$VERSION" ]] || fail "Missing version. Usage: ./scripts/release.sh <version>  (e.g. 1.0.0)"
VERSION="${VERSION#v}"   # tolerate a leading "v"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "Version must be MAJOR.MINOR.PATCH (e.g. 1.0.0), got: '$VERSION'"
TAG="v$VERSION"

# Toolchain

# `xcodebuild archive` needs full Xcode; the CLT alone cannot archive. If only the
# CLT is active, point DEVELOPER_DIR at Xcode.app for this process.
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

# Paths

APP_NAME="Crema.app"
DMG_NAME="Crema.dmg"                       # fixed name: matches releases/latest/download/Crema.dmg and the README
VOL_NAME="Crema"
BUILD_DIR="$REPO_ROOT/build/release"       # under gitignored build/
ARCHIVE="$BUILD_DIR/Crema.xcarchive"
DMG_SRC="$BUILD_DIR/dmg-src"               # holds only Crema.app for packaging
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
DMG_OUT="$REPO_ROOT/$DMG_NAME"

# Signing mode: SIGN_IDENTITY set = Developer ID + notarize; empty = ad-hoc fallback.
# NOTARY_PROFILE is a notarytool keychain profile created once out of band; no secret lives here.
SIGN_IDENTITY="${CREMA_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${CREMA_NOTARY_PROFILE:-CremaNotary}"
ENTITLEMENTS="$REPO_ROOT/Crema.entitlements"

# Start clean so a stale archive or half-built .dmg can't leak into the release.
step "Preparing a clean build ($TAG)"
rm -rf "$BUILD_DIR"
rm -f "$DMG_OUT"
mkdir -p "$BUILD_DIR"
info "Intermediates: $BUILD_DIR"

# 1. Archive (Release)

step "Archiving Crema in Release (this can take a few minutes)"
# MARKETING_VERSION stamps CFBundleShortVersionString. Archive is unsigned; the app
# is signed after extraction, since a real code identity is what lets the grant stick.
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

# Version sanity-check: a mismatch means the project stopped deriving from MARKETING_VERSION.
BUILT_VERSION="$(defaults read "$APP_SRC/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?')"
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
    info "${RED}Warning:${RESET} built app reports version $BUILT_VERSION, expected $VERSION — reconcile before publishing."
else
    info "Built $APP_NAME reports version $BUILT_VERSION."
fi

# 2. Sign the app

step "Signing $APP_NAME"
rm -rf "$DMG_SRC"
mkdir -p "$DMG_SRC"
cp -R "$APP_SRC" "$DMG_SRC/$APP_NAME"
APP="$DMG_SRC/$APP_NAME"

# A code signature is what lets TCC anchor the Accessibility grant: an unsigned bundle
# has no identity, so the grant never applies. The two vendored Mach-O live in
# Contents/Resources, which a top-level codesign never reaches — sign them explicitly.
ADAPTER_DIR="$APP/Contents/Resources/mediaremote-adapter"
NESTED_MACHO=(
    "$ADAPTER_DIR/MediaRemoteAdapter.framework"
    "$ADAPTER_DIR/MediaRemoteAdapterTestClient"
)

if [[ -n "$SIGN_IDENTITY" ]]; then
    info "Developer ID: $SIGN_IDENTITY"
    [[ -f "$ENTITLEMENTS" ]] || fail "Entitlements file not found: $ENTITLEMENTS"
    security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY" \
        || fail "Signing identity not in the keychain: '$SIGN_IDENTITY'. List them with: security find-identity -v -p codesigning"
    # Sign inside-out; NEVER --deep for Developer ID (mis-applies the app's options
    # to nested code).
    # Embedded frameworks/dylibs (usually none, but sign whatever the build produced).
    if [[ -d "$APP/Contents/Frameworks" ]]; then
        while IFS= read -r -d '' item; do
            codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item" \
                || fail "codesign (Developer ID) failed on: $item"
        done < <(find "$APP/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
    fi
    # The two vendored Mach-O in Contents/Resources, which a top-level codesign never reaches.
    for item in "${NESTED_MACHO[@]}"; do
        [[ -e "$item" ]] || fail "Expected nested binary missing: $item"
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item" \
            || fail "codesign (Developer ID) failed on: $item"
    done
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP" \
        || fail "codesign (Developer ID) failed on $APP_NAME"
    codesign --verify --deep --strict --verbose=2 "$APP" \
        || fail "Developer ID signature did not verify on $APP_NAME"
    info "Signed with Developer ID (hardened runtime + entitlements + timestamp)."
else
    info "Ad-hoc signing $APP_NAME (CREMA_SIGN_IDENTITY unset — local/testing build)."
    # --deep is fine for ad-hoc: no entitlements to mis-apply. The grant does not
    # survive rebuilds and Gatekeeper still prompts. Hardened runtime is off (notarization-only).
    codesign --force --deep --sign - "$APP" \
        || fail "codesign (ad-hoc) failed on $APP_NAME."
    codesign --verify --deep --strict "$APP" \
        || fail "the ad-hoc signature did not verify on $APP_NAME."
    info "$(codesign -dvv "$APP" 2>&1 | grep -E '^Signature=' || echo 'Signature=adhoc')"
fi

# 3. Package into Crema.dmg

step "Packaging $DMG_NAME"
if [[ "$USE_CREATE_DMG" == "1" ]]; then
    info "Using create-dmg (drag-to-Applications layout)."
    # create-dmg may exit non-zero after writing the .dmg, so success is judged by the
    # file existing, not the exit code. Needs a desktop session (over SSH the Finder step fails).
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
    # Stage the app next to an /Applications symlink, then image the folder (UDZO = compressed, read-only).
    ln -s /Applications "$DMG_SRC/Applications"
    hdiutil create \
        -volname "$VOL_NAME" \
        -srcfolder "$DMG_SRC" \
        -ov -format UDZO \
        "$DMG_OUT" >/dev/null || fail "hdiutil failed to create $DMG_NAME."
fi

[[ -f "$DMG_OUT" ]] || fail "Packaging finished but $DMG_OUT is missing."

# 4. Notarize + staple (Developer ID only)

if [[ -n "$SIGN_IDENTITY" ]]; then
    # Notarize then staple the .dmg. The app copied to /Applications is notarized but
    # not stapled, so its first launch uses the online Gatekeeper check.
    # notarytool submit --wait exits 0 even when Invalid, so success = grep "status: Accepted".
    step "Notarizing $DMG_NAME (notarytool submit --wait — can take minutes)"
    NOTARY_OUT="$(xcrun notarytool submit "$DMG_OUT" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
    printf '%s\n' "$NOTARY_OUT" | sed 's/^/    /'
    grep -q "status: Accepted" <<<"$NOTARY_OUT" || fail "Notarization was not Accepted. Inspect the log with:
    xcrun notarytool log <submission-id> --keychain-profile \"$NOTARY_PROFILE\""

    step "Stapling $DMG_NAME"
    xcrun stapler staple "$DMG_OUT" || fail "stapler staple failed on $DMG_NAME"
    xcrun stapler validate "$DMG_OUT" || fail "stapler validate failed on $DMG_NAME"
    # Final Gatekeeper check — should report "accepted" / "Notarized Developer ID".
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_OUT" 2>&1 | sed 's/^/    /' || true
    info "Notarized + stapled."
fi

# 5. Cleanup + summary

step "Cleaning intermediates"
rm -rf "$BUILD_DIR"

DMG_SIZE="$(du -h "$DMG_OUT" | cut -f1 | tr -d ' ')"
printf '\n%s✓ %s ready%s\n' "$GREEN$BOLD" "$DMG_NAME" "$RESET"
info "File:    $DMG_OUT ($DMG_SIZE)"
info "Version: $VERSION   ·   Tag to publish: $TAG"
printf '\n%sNext%s — test it, then publish (see docs/internal/RELEASE-GUIDE.md):\n' "$BOLD" "$RESET"
info "1. open \"$DMG_OUT\"   → drag Crema into Applications, confirm it launches."
info "2. gh release create $TAG \"$DMG_OUT\" --title \"Crema $VERSION\" --notes \"…\""
