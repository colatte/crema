#!/usr/bin/env bash
#
# release.sh — build a production Crema.app, package it as Crema.dmg, and regenerate
# the Sparkle appcast. Usage: ./scripts/release.sh <version>   (e.g. ./scripts/release.sh 1.0.0)
#
# Signing modes, by CREMA_SIGN_IDENTITY: empty = ad-hoc (local/testing). A
# "Developer ID Application: …" cert = Developer ID (sign + notarize + staple) via the
# CREMA_NOTARY_PROFILE keychain profile (default "CremaNotary"). Any other non-empty
# identity = self-signed: signs with a stable code identity so the Accessibility grant
# persists across releases, but is not notarized (Apple only notarizes Developer ID).
#
# Identity builds (self-signed or Developer ID) also re-sign the nested Sparkle code with
# our identity and regenerate docs/appcast.xml; ad-hoc is a throwaway test build and does
# neither. The script never commits — publishing the appcast (a push to main, which
# GitHub Pages serves from /docs) is a printed next step, not an action here.
#
# Dependencies: full Xcode; create-dmg optional (hdiutil fallback); the Developer ID
# path needs the cert + notary profile; the appcast needs the Sparkle EdDSA private key in
# the Keychain (generate_appcast reads it on its own). See docs/internal/RELEASE-GUIDE.md.

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

# Build number (CFBundleVersion), derived from the semver: BUILD = MAJOR*10000 + MINOR*100 + PATCH
# (1.1.1 -> 10101, 1.2.0 -> 10200). Sparkle compares sparkle:version, which comes from
# CFBundleVersion; the project ships a static CURRENT_PROJECT_VERSION = 1, so without a stamp every
# build reports version 1 and no update ever fires. This scheme is deterministic (auditable
# straight from the tag — nothing to remember to bump), monotonic while the semver climbs, and
# always > 1 (above every build shipped so far). Corollary: re-releasing the SAME marketing version
# reuses the same build number, so Sparkle sees no update — a re-release needs a patch bump.
# Invariant: each component must stay < 100, or the packing collides (1.0.100 and 1.1.0 both -> 10100),
# handing a legit bump the same CFBundleVersion as an earlier release and blinding Sparkle to the update
# — the same failure as re-releasing, but triggered by a valid climb. Guarded below; widen the field
# multipliers here if a component ever legitimately needs to reach 100.
IFS='.' read -r VMAJOR VMINOR VPATCH <<<"$VERSION"
(( 10#$VMINOR < 100 && 10#$VPATCH < 100 )) \
    || fail "Version $VERSION has a minor or patch >= 100; the build-number scheme (MAJOR*10000 + MINOR*100 + PATCH) collides there (e.g. 1.0.100 and 1.1.0 both map to 10100). Widen the field multipliers in release.sh before shipping this version."
BUILD_NUMBER=$(( 10#$VMAJOR * 10000 + 10#$VMINOR * 100 + 10#$VPATCH ))   # 10# forces base-10 (guards a leading zero)

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
DMG_VERSIONED="$REPO_ROOT/Crema-$VERSION.dmg"   # byte-identical copy of Crema.dmg; the appcast enclosure asset
STAGING_DIR="$REPO_ROOT/build/appcast-staging"  # holds ONLY the new dmg so generate_appcast emits a one-item feed
APPCAST="$REPO_ROOT/docs/appcast.xml"           # versioned; regenerated here, published by a push to main (Pages serves /docs)

# Signing mode: empty = ad-hoc; "Developer ID Application …" = Developer ID + notarize; any other non-empty = self-signed (sign only).
# NOTARY_PROFILE is a notarytool keychain profile created once out of band; no secret lives here.
SIGN_IDENTITY="${CREMA_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${CREMA_NOTARY_PROFILE:-CremaNotary}"
ENTITLEMENTS="$REPO_ROOT/Crema.entitlements"

# Start clean so a stale archive, half-built .dmg, or a prior version's enclosure can't leak in.
step "Preparing a clean build ($TAG)"
rm -rf "$BUILD_DIR" "$STAGING_DIR"
rm -f "$DMG_OUT"
rm -f "$REPO_ROOT"/Crema-*.dmg   # stale version-named enclosures from earlier runs (Crema.dmg has no hyphen, kept)
mkdir -p "$BUILD_DIR"
info "Intermediates: $BUILD_DIR"

# 1. Archive (Release)

step "Archiving Crema in Release (this can take a few minutes)"
# MARKETING_VERSION stamps CFBundleShortVersionString; CURRENT_PROJECT_VERSION stamps
# CFBundleVersion (the number Sparkle compares) per build, off the semver above — the pbxproj
# keeps a static 1, so the stamp is what makes updates fire. Archive is unsigned; the app is
# signed after extraction, since a real code identity is what lets the grant stick.
if ! xcodebuild archive \
        -project "$PROJECT" \
        -scheme Crema \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
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

# Build-number sanity-check: the stamp must land in CFBundleVersion, or Sparkle would compare the
# static 1 and never see an update. A mismatch means CURRENT_PROJECT_VERSION stopped feeding it.
BUILT_BUILD="$(defaults read "$APP_SRC/Contents/Info" CFBundleVersion 2>/dev/null || echo '?')"
if [[ "$BUILT_BUILD" != "$BUILD_NUMBER" ]]; then
    info "${RED}Warning:${RESET} built app reports build $BUILT_BUILD, expected $BUILD_NUMBER — reconcile before publishing."
else
    info "Built $APP_NAME reports build $BUILT_BUILD (from $VERSION)."
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
    # Identity string picks the shape: "Developer ID Application …" = Developer ID (notarizable); any other non-empty = self-signed (sign only).
    [[ -f "$ENTITLEMENTS" ]] || fail "Entitlements file not found: $ENTITLEMENTS"
    security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY" \
        || fail "Signing identity not in the keychain: '$SIGN_IDENTITY'. List them with: security find-identity -v -p codesigning"
    if [[ "$SIGN_IDENTITY" == "Developer ID Application"* ]]; then
        TIMESTAMP_FLAG=--timestamp   # Apple recommends a timestamp for Developer ID/notarization
        RUNTIME_FLAG="--options runtime"   # notarization requires hardened runtime; the real Team ID satisfies library validation
        info "Developer ID: $SIGN_IDENTITY"
    else
        TIMESTAMP_FLAG=--timestamp=none   # self-signed: a timestamp adds a network dependency with no Gatekeeper/notarization benefit
        # NO hardened runtime for self-signed: the runtime flag turns on dyld
        # library validation, which demands a REAL matching Team ID between the
        # process and every non-platform library it maps — a self-signed cert
        # has no Team ID, so the app CRASHES AT LAUNCH loading
        # Sparkle.framework ("mapping process and mapped file (non-platform)
        # have different Team IDs"), even with every component signed by the
        # same identity. codesign --verify never checks this (it is load
        # policy, not integrity) — the launch smoke below is what pins it
        # (docs/DECISIONS.md: signed-without-hardened-runtime).
        # Hardened runtime buys nothing here anyway: no notarization, and
        # Gatekeeper treats self-signed as unidentified either way. The TCC
        # identity stability (the reason this mode exists) comes from the
        # cert, not the runtime flag.
        RUNTIME_FLAG=""
        info "Self-signed: $SIGN_IDENTITY"
        info "Signing with a self-signed identity (stable code identity, Accessibility grant persists across releases)."
        info "Skipping notarization (Apple only notarizes Developer ID; Gatekeeper first-launch flow still applies)."
    fi
    # Sign inside-out; NEVER --deep with entitlements (mis-applies the app's options to nested code).

    # Sparkle (SPM, Release-only) embeds Sparkle.framework, and inside it ships an XPC pair, an
    # Autoupdate helper and Updater.app that the Sparkle project pre-signs ad-hoc under its own
    # identifier (no Team). They must carry OUR identity + hardened runtime, signed inside-out
    # BEFORE the framework bundle re-seals over them — otherwise Developer ID notarization rejects
    # the foreign/ad-hoc nested code and even --verify --strict trusts a stale seal. Paths below
    # pin Sparkle 2.9.4's layout (Versions/Current -> B); if Sparkle is upgraded, re-list them
    # from the built framework. Via Versions/Current so a version-letter bump doesn't matter.
    SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
    if [[ -d "$SPARKLE_FW" ]]; then
        SPARKLE_CUR="$SPARKLE_FW/Versions/Current"
        SPARKLE_NESTED=(
            "$SPARKLE_CUR/XPCServices/Downloader.xpc"
            "$SPARKLE_CUR/XPCServices/Installer.xpc"
            "$SPARKLE_CUR/Autoupdate"
            "$SPARKLE_CUR/Updater.app"
        )
        for item in "${SPARKLE_NESTED[@]}"; do
            [[ -e "$item" ]] || fail "Expected Sparkle nested code missing: $item (did Sparkle's layout change?)"
            codesign --force $RUNTIME_FLAG $TIMESTAMP_FLAG --sign "$SIGN_IDENTITY" "$item" \
                || fail "codesign failed on Sparkle nested code: $item"
        done
    fi

    # Embedded frameworks/dylibs (Sparkle.framework today) — signed last of the nested code so its
    # seal covers the re-signed helpers above.
    if [[ -d "$APP/Contents/Frameworks" ]]; then
        while IFS= read -r -d '' item; do
            codesign --force $RUNTIME_FLAG $TIMESTAMP_FLAG --sign "$SIGN_IDENTITY" "$item" \
                || fail "codesign failed on: $item"
        done < <(find "$APP/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
    fi
    # The two vendored Mach-O in Contents/Resources, which a top-level codesign never reaches.
    for item in "${NESTED_MACHO[@]}"; do
        [[ -e "$item" ]] || fail "Expected nested binary missing: $item"
        codesign --force $RUNTIME_FLAG $TIMESTAMP_FLAG --sign "$SIGN_IDENTITY" "$item" \
            || fail "codesign failed on: $item"
    done
    codesign --force $RUNTIME_FLAG $TIMESTAMP_FLAG \
        --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP" \
        || fail "codesign failed on $APP_NAME"
    codesign --verify --deep --strict --verbose=2 "$APP" \
        || fail "signature did not verify on $APP_NAME"

    # Signing CONSISTENCY across every Mach-O the process maps: dyld's
    # load-time policy (same authority/Team as the app, for non-platform code)
    # is NOT covered by --verify, which checks integrity of each signature in
    # isolation — a foreign or stale identity on one nested binary verifies
    # green and still refuses to load. Compare the leaf Authority + Team of
    # each component against the app's and fail loudly on any mismatch.
    step "Verifying signing consistency (the load-time check --verify does not make)"
    # awk consumes the whole stream on purpose: an early `exit` would SIGPIPE
    # codesign under `set -o pipefail` and abort the script with 141.
    sig_leaf() { codesign -dvv "$1" 2>&1 | awk -F= '/^Authority=/ && !done { print $2; done = 1 }'; }
    sig_team() { codesign -dvv "$1" 2>&1 | awk -F= '/^TeamIdentifier=/ && !done { print $2; done = 1 }'; }
    APP_LEAF="$(sig_leaf "$APP")"
    APP_TEAM="$(sig_team "$APP")"
    [[ -n "$APP_LEAF" ]] || fail "could not read the app's signing authority"
    CONSISTENCY_ITEMS=("${NESTED_MACHO[@]}")
    if [[ -d "$SPARKLE_FW" ]]; then
        # Through the REAL versioned path (readlink), never the Current
        # symlink: dyld maps Versions/B/Sparkle, so that exact binary is the
        # one whose identity matters.
        SPARKLE_REAL="$(readlink "$SPARKLE_FW/Versions/Current" || true)"
        [[ -n "$SPARKLE_REAL" ]] || fail "Sparkle.framework/Versions/Current is not a symlink — the framework layout was materialized by a broken copy; aborting."
        CONSISTENCY_ITEMS+=(
            "$SPARKLE_FW/Versions/$SPARKLE_REAL/Sparkle"
            "$SPARKLE_FW/Versions/$SPARKLE_REAL/XPCServices/Downloader.xpc"
            "$SPARKLE_FW/Versions/$SPARKLE_REAL/XPCServices/Installer.xpc"
            "$SPARKLE_FW/Versions/$SPARKLE_REAL/Autoupdate"
            "$SPARKLE_FW/Versions/$SPARKLE_REAL/Updater.app"
        )
    fi
    for item in "${CONSISTENCY_ITEMS[@]}"; do
        ITEM_LEAF="$(sig_leaf "$item")"
        ITEM_TEAM="$(sig_team "$item")"
        [[ "$ITEM_LEAF" == "$APP_LEAF" && "$ITEM_TEAM" == "$APP_TEAM" ]] \
            || fail "signing inconsistency: ${item#"$APP"/} carries '$ITEM_LEAF' (team '$ITEM_TEAM') but the app carries '$APP_LEAF' (team '$APP_TEAM') — dyld refuses this at LOAD even though --verify passes. Re-run; if it persists, the artifact layout changed."
    done
    info "All ${#CONSISTENCY_ITEMS[@]} nested binaries match the app: $APP_LEAF (team ${APP_TEAM:-none})"

    if [[ "$SIGN_IDENTITY" == "Developer ID Application"* ]]; then
        info "Signed with Developer ID (hardened runtime + entitlements + timestamp)."
    else
        info "Signed self-signed (entitlements, no hardened runtime, no timestamp)."
    fi
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

if [[ "$SIGN_IDENTITY" == "Developer ID Application"* ]]; then
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

# 4.5 Launch smoke — the guard no static check can replace

# Install the app FROM THE FINAL DMG into a temp dir, run it, and require the
# process to survive ~5 s. This is the only stage that exercises dyld's
# LOAD-time policy (library validation, Team consistency): a bundle can pass
# codesign --verify --deep --strict on every component and still be
# unlaunchable — the self-signed + hardened-runtime combination shipped
# exactly that once (dyld: "mapping process and mapped file (non-platform)
# have different Team IDs"). Runs in EVERY mode, after the dmg is final
# (post-staple on Developer ID, since stapling rewrites the file).
step "Launch smoke (install from $DMG_NAME, must survive 5 s)"
SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/crema-launch-smoke.XXXXXX")"
SMOKE_MOUNT="$SMOKE_DIR/mnt"
mkdir -p "$SMOKE_MOUNT"
hdiutil attach "$DMG_OUT" -nobrowse -readonly -noautoopen -mountpoint "$SMOKE_MOUNT" >/dev/null \
    || fail "launch smoke: could not mount $DMG_NAME"
cp -R "$SMOKE_MOUNT/$APP_NAME" "$SMOKE_DIR/$APP_NAME"
hdiutil detach "$SMOKE_MOUNT" >/dev/null 2>&1 || hdiutil detach "$SMOKE_MOUNT" -force >/dev/null 2>&1 || true
# The raw executable, not `open`: same dyld load path, and the pid is ours to
# watch and kill without LaunchServices in the middle.
# Side effects on the release machine for these ~5 s: a second live Crema
# (same bundle id and identity — duplicated media-key tap, and duplicated
# suppression if the pref is on), reading the real UserDefaults; on a machine
# without the Accessibility grant it persists the has-seen-onboarding flag.
# Nothing reaches the artifact — the dmg is final and was mounted read-only.
"$SMOKE_DIR/$APP_NAME/Contents/MacOS/Crema" > "$SMOKE_DIR/launch.log" 2>&1 &
SMOKE_PID=$!
sleep 5
if kill -0 "$SMOKE_PID" 2>/dev/null; then
    kill "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
    rm -rf "$SMOKE_DIR"
    info "Launch smoke passed: the installed app survived 5 s."
else
    SMOKE_STATUS=0; wait "$SMOKE_PID" 2>/dev/null || SMOKE_STATUS=$?
    printf '%s\n' "----- launch.log (tail) -----" >&2
    tail -n 12 "$SMOKE_DIR/launch.log" >&2 || true
    fail "launch smoke FAILED: the app from $DMG_NAME died within 5 s (exit $SMOKE_STATUS).
    A dyld 'Library not loaded / different Team IDs' tail means a signing/load-policy
    problem the consistency check above should explain; do NOT publish this dmg.
    (Artifacts kept at $SMOKE_DIR for inspection.)"
fi

# 5. Regenerate the Sparkle appcast (identity builds only)

# Ad-hoc is a throwaway local build, so no appcast. A real release (self-signed or Developer ID)
# produces the enclosure and rewrites docs/appcast.xml. Runs AFTER notarize+staple: stapling
# rewrites the .dmg, so the EdDSA signature must be computed over the final bytes.
if [[ -n "$SIGN_IDENTITY" ]]; then
    # The enclosure carries the version in its name so its per-tag URL is unambiguous. It is a
    # byte-for-byte copy of Crema.dmg, which keeps the fixed name the README's latest-download
    # link needs — both get uploaded to the release, same bytes under two names.
    step "Preparing the appcast enclosure"
    cp "$DMG_OUT" "$DMG_VERSIONED"

    # generate_appcast / sign_update ship inside Sparkle's SPM artifact, which Xcode resolves under
    # DerivedData (the archive above triggered the resolve). That folder name carries a per-project
    # hash, so find the tools by glob (newest wins) rather than hardcoding the hash.
    find_sparkle_tool() {
        local tool="$1" newest=''
        while IFS= read -r p; do
            [[ -z "$newest" || "$p" -nt "$newest" ]] && newest="$p"
        done < <(find "$HOME/Library/Developer/Xcode/DerivedData" \
            -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool" -type f 2>/dev/null)
        [[ -n "$newest" ]] && printf '%s' "$newest"
    }
    GENERATE_APPCAST="$(find_sparkle_tool generate_appcast)"
    [[ -n "$GENERATE_APPCAST" ]] || fail "generate_appcast not found under any DerivedData/…/SourcePackages/artifacts/sparkle/Sparkle/bin.
    Build Crema once (Xcode or 'xcodebuild build') so SPM resolves Sparkle, then re-run."

    # Staging holds ONLY the new dmg and no prior appcast, and the feed is written to a FRESH path
    # inside it — never straight to the committed docs/appcast.xml. generate_appcast reads its own
    # output file as a base and MERGES new items into it, so aiming -o at the published feed would
    # accumulate every past release's item after the first release (docs/appcast.xml pre-exists on
    # every run). Regenerating into a fresh target gives a genuine single-item feed — the whole
    # appcast rebuilt each release. History lives in GitHub Releases, not the feed; a single item
    # also sidesteps the one-download-prefix concern when each release's URL is per-tag. The private
    # EdDSA key is read from the Keychain by generate_appcast itself.
    step "Generating docs/appcast.xml"
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"
    cp "$DMG_OUT" "$STAGING_DIR/Crema-$VERSION.dmg"
    STAGED_APPCAST="$STAGING_DIR/appcast.xml"   # fresh each run; the committed feed is never the merge base
    "$GENERATE_APPCAST" \
        --download-url-prefix "https://github.com/colatte/crema/releases/download/$TAG/" \
        -o "$STAGED_APPCAST" \
        "$STAGING_DIR" \
        || fail "generate_appcast failed. Is your Sparkle EdDSA private key in the Keychain?"
    [[ -f "$STAGED_APPCAST" ]] || fail "generate_appcast finished but $STAGED_APPCAST is missing."

    # A missing enclosure signature is a dead feed: SUPublicEDKey is set, so every client rejects an
    # unsigned update at runtime. generate_appcast omits the signature — printing only a "SUPublicEDKey
    # … does not match" warning while still exiting 0 — when the signing key's public half differs from
    # the one baked into the app. Fail before publishing so that mismatch can't ship as a green build.
    ENCLOSURE_SIG="$(grep -o 'sparkle:edSignature="[^"]*"' "$STAGED_APPCAST" | head -1 | sed 's/^[^"]*"//; s/"$//')"
    [[ -n "$ENCLOSURE_SIG" ]] || fail "generate_appcast produced a feed with no sparkle:edSignature — the Sparkle signing key does not match the app's SUPublicEDKey (see the warning above). The feed would be rejected at runtime; fix the signing key (generate_keys) and re-run."

    # The CFBundleVersion stamp is the linchpin that makes any update fire: generate_appcast reads
    # sparkle:version straight from the built app's CFBundleVersion, and Sparkle compares that. If the
    # stamp silently fails to flow (a fixed CFBundleVersion in Info.plist, GENERATE_INFOPLIST_FILE
    # changing), the feed would carry sparkle:version="1" while this run believes it shipped
    # $BUILD_NUMBER — a dead feed no client ever updates from. The archive-time check (built app reports
    # build N) is only advisory; hard-fail here, on the published feed, where the value actually matters.
    # Sparkle 2.x emits sparkle:version as a child element (<sparkle:version>10101</sparkle:version>),
    # older layouts as an enclosure attribute (sparkle:version="10101"); match either and take the
    # numeric build. (sparkle:shortVersion, sparkle:shortVersionString hold the marketing string, not
    # this number.) CFBundleVersion is purely numeric, so the digit extraction is unambiguous.
    FEED_VERSION="$(grep -oE '<sparkle:version>[^<]*</sparkle:version>|sparkle:version="[^"]*"' "$STAGED_APPCAST" | head -1 | grep -oE '[0-9]+' | head -1)"
    [[ "$FEED_VERSION" == "$BUILD_NUMBER" ]] \
        || fail "generate_appcast wrote sparkle:version=\"$FEED_VERSION\", but this build is $BUILD_NUMBER — the CFBundleVersion stamp did not reach the feed. A feed carrying the wrong (or stale 1) version means no client sees the update; fix the stamp and re-run."

    cp "$STAGED_APPCAST" "$APPCAST"
    [[ -f "$APPCAST" ]] || fail "generate_appcast finished but $APPCAST is missing."
    info "Wrote docs/appcast.xml — enclosure Crema-$VERSION.dmg, sparkle:version $FEED_VERSION (read back from the feed)."

    # Optional sanity check: verify the enclosure against the signature the appcast just embedded.
    # This proves the signature is internally consistent with the local signing key; it does NOT
    # prove that key's public half matches the SUPublicEDKey baked into the app — the definitive
    # match is the runtime EdDSA check exercised by the E2E in RELEASE-GUIDE.md.
    SIGN_UPDATE="$(find_sparkle_tool sign_update)"
    if [[ -n "$SIGN_UPDATE" ]]; then
        if "$SIGN_UPDATE" --verify "$DMG_VERSIONED" "$ENCLOSURE_SIG" >/dev/null 2>&1; then
            info "EdDSA enclosure signature verifies against the local signing key."
        else
            info "${RED}Warning:${RESET} the enclosure EdDSA signature did not verify — check your Sparkle signing key before publishing."
        fi
    fi
fi

# 6. Cleanup + summary

step "Cleaning intermediates"
rm -rf "$BUILD_DIR" "$STAGING_DIR"

DMG_SIZE="$(du -h "$DMG_OUT" | cut -f1 | tr -d ' ')"
printf '\n%s✓ %s ready%s\n' "$GREEN$BOLD" "$DMG_NAME" "$RESET"
info "File:    $DMG_OUT ($DMG_SIZE)"
info "Version: $VERSION (build $BUILD_NUMBER)   ·   Tag to publish: $TAG"

if [[ -n "$SIGN_IDENTITY" ]]; then
    info "Enclosure: $DMG_VERSIONED   ·   Appcast: docs/appcast.xml (regenerated, uncommitted)"
    printf '\n%sNext%s — test it, then publish (see docs/internal/RELEASE-GUIDE.md):\n' "$BOLD" "$RESET"
    info "1. open \"$DMG_OUT\"   → drag Crema into Applications, confirm it launches."
    info "2. Create the release with BOTH dmgs (same bytes, two names):"
    info "   gh release create $TAG \"$DMG_OUT\" \"$DMG_VERSIONED\" --target main --title \"Crema $VERSION\" --notes \"…\" --latest"
    info "     · Crema.dmg          → the README's releases/latest/download/Crema.dmg link"
    info "     · Crema-$VERSION.dmg → the appcast enclosure (its URL in docs/appcast.xml)"
    info "3. Publish the appcast (a push to main; Pages serves /docs) — this script did NOT commit:"
    info "   git add docs/appcast.xml && git commit -m \"chore(release): appcast $VERSION\" && git push"
    info "4. Confirm it is live and points at this release:"
    info "   curl -fsS https://colatte.github.io/crema/appcast.xml | grep -E 'sparkle:version|Crema-$VERSION\\.dmg'"
else
    printf '\n%sNote%s — ad-hoc test build: no appcast, no enclosure (set CREMA_SIGN_IDENTITY for a real release).\n' "$BOLD" "$RESET"
    info "open \"$DMG_OUT\"   → drag Crema into Applications, confirm it launches."
fi
