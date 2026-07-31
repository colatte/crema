# Crema release guide

> How a Crema release is published, and how the **Sparkle auto-update cycle** is
> fed. The process is always the same; only the version number changes. Written
> for whoever holds the signing identity — today the author — and kept in the
> repository because the parts that matter are facts about the tooling, not
> about one machine.

Crema is distributed as a `Crema.dmg` — a direct download from the
[Releases](https://github.com/colatte/crema/releases) page, outside the Mac App
Store. Since Sparkle was integrated, every release also **regenerates the
appcast** (`docs/appcast.xml`), served by GitHub Pages, so that anyone who
already has the app installed is updated in place. `scripts/release.sh` builds,
stamps the version, signs (including the nested Sparkle), notarizes when the
identity is Developer ID, packages the `.dmg`, produces the versioned enclosure
and rewrites the appcast — but it **commits nothing and publishes nothing**. You
test locally, create the GitHub Release with the assets, and **push the appcast**
yourself.

> **Signing — the current path is self-signed.** `release.sh` signs with the
> certificate named in `CREMA_SIGN_IDENTITY`. Today that is a **self-signed**
> certificate the author creates in Keychain Access (free): it gives a **stable
> code identity** across versions, so the **Accessibility grant persists** from
> one release to the next — and Sparkle can **replace the installed app**,
> because the signer is the same. It does **not** satisfy Gatekeeper (the "open
> anyway" of the first launch stays) and **cannot** be notarized (Apple only
> notarizes Developer ID). With no identity at all, the script falls back to
> **ad-hoc** — good only for a quick local packaging test; it generates **no**
> appcast and does **not** persist Accessibility. **Developer ID + notarization**
> wait for the day the author has an Apple Developer account (roadmap, no date).
> Both paths are described below.

---

## 1. Prerequisites (once per machine)

- **Full Xcode** (not just the Command Line Tools) — `archive` needs it. If
  `xcode-select -p` points at `.../CommandLineTools`, the script finds
  `/Applications/Xcode.app` on its own; to make it permanent:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app
  ```
- **create-dmg** (recommended) — gives the standard "drag to Applications"
  layout:
  ```bash
  brew install create-dmg
  ```
  Without it the script falls back to `hdiutil` automatically (same content,
  plainer window). Not mandatory.
- **GitHub CLI** (`gh`) — to create the Release from the command line, already
  authenticated: `gh auth status`. Alternative: publish from the web UI (no `gh`
  needed).
- **Sparkle EdDSA key in the Keychain** — generated **once** with the
  `generate_keys` pair; the **private** half lives in the author's login
  keychain, the **public** half is already written into `Info.plist` as
  `SUPublicEDKey`. `generate_appcast` reads the private half by itself when it
  signs the enclosure — **you never type or paste that key**. To confirm it is
  reachable on this machine (this prints **only the public half**):
  ```bash
  SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData \
    -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | head -1)"
  "$SPARKLE_BIN/generate_keys" -p
  # must print exactly:  AWufPX9SoMRSSmTVmoLNaoXyHJuRHOKx+BxrSfazfmQ=
  ```
  That string has to match the `SUPublicEDKey` in `Crema/Info.plist`
  **byte for byte**. If `generate_keys -p` prints nothing, the private key is not
  in this keychain (new machine, replaced keychain) — restore it from the backup
  below before attempting a release.
  > `$SPARKLE_BIN` comes from Sparkle's SPM checkout inside DerivedData; the path
  > carries a per-project hash, so we locate it by glob. If `find` comes up
  > empty, build Crema once (Xcode or `xcodebuild build`) so SPM resolves
  > Sparkle.

### Back the private key up — once, and off this machine

A normal release never touches the private key, which is exactly why it is easy
to forget that the login keychain is its **only** copy. Export it once:

```bash
"$SPARKLE_BIN/generate_keys" -x sparkle-eddsa-private-key.txt
```

Store that file **outside the release machine** — a password manager entry, or
offline media — and delete the exported copy from disk afterwards. Restoring on
a new machine (or a new keychain) is `generate_keys -f <that file>`, which is
the step §1 above sends you to when `generate_keys -p` prints nothing.

> **Losing that key ends the update channel, permanently.** Sparkle's documented
> key-rotation route assumes an installed base that can authenticate an update
> some other way — a Developer ID anchor Crema does not have, because it ships
> self-signed. The EdDSA key is therefore the only authentication every copy of
> Crema in the field will accept. Lose it and every future appcast is rejected by
> every installation, with no path back except asking each user to download and
> re-install by hand. Treat the key as unrecoverable and the backup as the thing
> that makes that untrue.

---

## 2. Self-signed signing (the current path)

Today's release path. A **self-signed** certificate gives a code identity that is
stable across versions — Accessibility persists, and Sparkle accepts replacing
the installed app because the signer is the same. It does not satisfy Gatekeeper
(the "open anyway" of the first launch stays) and cannot be notarized; that is
Developer ID (section 3).

### Create the certificate (once)

- **Keychain Access** → menu _Certificate Assistant → Create a Certificate…_
- **Name:** `Crema Code Signing` — this exact string becomes the value of
  `CREMA_SIGN_IDENTITY`. **Identity type:** _Self-Signed Root_.
  **Certificate type:** _Code Signing_.
- Tick **"Let me override defaults"** and set the validity to **3650 days**: the
  365-day default means a new certificate (a new identity!) every year — and a
  new certificate means users **re-grant** Accessibility **and** Sparkle refuses
  the swap (different signer). One certificate, reused for every release.
- On the first `codesign`, macOS asks for access to the private key — click
  **Always Allow**.
- Confirm it shows up:
  ```bash
  security find-identity -v -p codesigning | grep "Crema Code Signing"
  ```
  If it is listed as _invalid_, open the certificate in Keychain Access → **Trust**
  tab → **Code Signing: Always Trust**.

### Run it

```bash
export CREMA_SIGN_IDENTITY="Crema Code Signing"
./scripts/release.sh 1.1.1
```

The script signs with that certificate (including the **nested Sparkle**, see
§4), **skips notarization** (only `Developer ID Application:` is notarized) and
**regenerates the appcast**. Out comes a `Crema.dmg` signed with a stable
identity, a `Crema-1.1.1.dmg` (the enclosure) and a fresh `docs/appcast.xml`.

> **Self-signed NEVER carries the hardened runtime** (release-guard round, the
> fix for the 1.1.9 crash): the runtime turns on dyld's _library validation_,
> which demands a **real and matching Team ID** between the process and every
> non-platform library — a self-signed certificate **has no Team**, so the app
> **crashes at launch** loading `Sparkle.framework` ("mapping process and mapped
> file (non-platform) have different Team IDs"), even with every component signed
> by the same identity and `codesign --verify --deep --strict` green (verify
> checks integrity, not load policy). `release.sh` only adds `--options runtime`
> on the Developer ID branch; on top of that it validates the **identity
> consistency** of every nested Mach-O and runs a **launch smoke** (installs from
> the dmg and requires the process to stay alive for 5 s) in every mode — an
> unlaunchable dmg never goes green again (docs/DECISIONS.md:
> signed-without-hardened-runtime).

What does **not** change for the user: Gatekeeper still asks for **"open
anyway"** on the first launch (the **First launch** section of the README stays
as it is). What **improves**: Accessibility **persists** across releases, and
**auto-update** works.

---

## 3. Developer ID signing + notarization (future)

The real distribution path, for **if and when the author has an Apple Developer
account** (roadmap). `release.sh` is already ready: signing is a matter of
setting `CREMA_SIGN_IDENTITY` to any identity, and **notarization** only fires
when that identity is a `Developer ID Application:`. The checklist below is
waiting for that day.

### Why (and the hardened-runtime crux)

Notarization **requires the hardened runtime**. Crema `dlopen`s two private
brightness frameworks — but both are **system frameworks, signed by Apple**
(`/System/Library/PrivateFrameworks/DisplayServices.framework` and
`.../CoreBrightness.framework`). The hardened runtime's _library validation_
**permits** loading Apple-signed code, so those `dlopen` calls **do not break**
and **do not need** `disable-library-validation`. As a result
`Crema.entitlements` is **deliberately empty** — no security-weakening
entitlement is needed (the file itself documents why each candidate was
discarded). That gives the cleanest notarization possible.

> **Sparkle and notarization.** `Sparkle.framework` embeds **nested executable
> code** that Apple requires to be signed with the **same** identity and hardened
> runtime: the two XPC services (`Downloader.xpc`, `Installer.xpc`), the
> `Autoupdate` helper and `Updater.app`. Sparkle ships them **pre-signed ad-hoc**
> under the `org.sparkle-project` identifier (no Team) — notarization would
> **reject** that. `release.sh` re-signs them with **our** identity, inside out,
> **before** sealing the framework (see §4). Without that, notarization fails on
> nested code.

### Checklist — for the day the Apple Developer account exists (once)

- [ ] **"Developer ID Application" certificate.** In Xcode: _Settings → Accounts
      → (your account) → Manage Certificates → + → Developer ID Application_ (or
      through developer.apple.com → Certificates). Confirm it appears:
      ```bash
      security find-identity -v -p codesigning
      # must list: "Developer ID Application: Your Name (TEAMID)"
      ```
- [ ] **Notarization credential** — one of the two:
      - **App-specific password**: appleid.apple.com → Sign-In & Security →
        App-Specific Passwords → generate one for notarytool. Keep the Team ID
        handy (10 characters, at developer.apple.com → Membership).
      - **API key** (App Store Connect → Users and Access → Integrations → Keys):
        downloads a `.p8` key file plus a Key ID and an Issuer ID. The `.p8` is a
        secret and never belongs in the repository — the `.gitignore` already
        covers that shape.
- [ ] **notarytool keychain profile** (stores the credential in the keychain,
      out of the script). With an app-specific password:
      ```bash
      xcrun notarytool store-credentials "CremaNotary" \
        --apple-id "your-apple-id@example.com" \
        --team-id "TEAMID" \
        --password "the-app-specific-password"
      ```
      Or with an API key:
      ```bash
      xcrun notarytool store-credentials "CremaNotary" \
        --key "/path/to/your-api-key.p8" --key-id "KEYID" --issuer "ISSUER-UUID"
      ```
      `CremaNotary` is the name the script expects (`CREMA_NOTARY_PROFILE`).

### Running in Developer ID mode

```bash
export CREMA_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# CREMA_NOTARY_PROFILE=CremaNotary is already the default
./scripts/release.sh 1.1.1
```

The script then: builds Release (stamping the version) → signs inside out
(nested Sparkle → the adapter's two vendored Mach-Os → the app) with **hardened
runtime + `Crema.entitlements` + timestamp** and your Developer ID → packages
`Crema.dmg` → **notarizes** the dmg (`notarytool submit --wait`) → **staples** it
→ regenerates the appcast **over the already-stapled dmg** (the EdDSA signature
has to cover the final bytes). Out comes a notarized `Crema.dmg` that opens
**without** the Gatekeeper prompt.

A quick check of what came out:

```bash
codesign -dvv --verbose=4 /Volumes/Crema/Crema.app   # Authority: Developer ID Application...; flags runtime
spctl --assess --type open --verbose /path/to/Crema.dmg   # "accepted"
xcrun stapler validate /path/to/Crema.dmg
```

### Ad-hoc fallback (no identity at all)

Without `CREMA_SIGN_IDENTITY` the script signs **ad-hoc**, does **not** re-sign
the nested Sparkle and does **not** generate an appcast. It is only good for a
quick local packaging test: Accessibility works for that specific build, but it
does not persist across versions and Gatekeeper still asks for "open anyway".
For a release, use self-signed (§2).

---

## 4. What `release.sh` does for Sparkle (the three beams)

Context for the ritual in §5, and for diagnosing problems.

1. **Build stamp (`CFBundleVersion`).** Sparkle decides "is there an update?" by
   comparing `sparkle:version`, which **comes from `CFBundleVersion`**. The
   `pbxproj` pins `CURRENT_PROJECT_VERSION = 1`, so **every build ever published
   reports version 1** — without a stamp, no update ever fires. `release.sh`
   derives the number from the semver itself and passes it to
   `xcodebuild archive`:
   ```
   BUILD = MAJOR*10000 + MINOR*100 + PATCH      (1.1.1 → 10101 · 1.2.0 → 10200)
   ```
   It is **deterministic** (auditable straight from the tag, nothing to remember
   to bump), **monotonic** while the semver climbs — **as long as each component
   stays < 100** — and always **> 1** (above everything ever shipped). If a
   `minor` or `patch` ever reached 100 the scheme **collides** (`1.0.100` and
   `1.1.0` both land on `10100`), which would give a legitimate bump the same
   `CFBundleVersion` as an earlier release and blind Sparkle to the update; the
   script therefore **aborts** in that case (widen the multipliers in
   `release.sh` if it is ever needed). The script also checks that the built app
   reports that `CFBundleVersion` (an **advisory** — the script calls it that
   itself; you read it in the output, §5.1) **and** re-reads `sparkle:version`
   from the generated feed — that one does **abort** on a mismatch.
   > **Corollary:** re-releasing the **same** marketing version reuses the
   > **same** build number → Sparkle sees **no** update. A re-release requires a
   > patch bump (1.1.1 → 1.1.2). There is no "fix it and republish 1.1.1".

2. **Sparkle's nested signature.** Before sealing `Sparkle.framework`, the script
   re-signs with **our** identity, inside out: `XPCServices/Downloader.xpc`,
   `XPCServices/Installer.xpc`, the `Autoupdate` helper and `Updater.app` — which
   Sparkle ships pre-signed ad-hoc under `org.sparkle-project`. Only then is the
   framework sealed (the seal covers the nested code already carrying our
   signature), and finally the app. The gate is the
   `codesign --verify --deep --strict` that already existed. **Only on the branch
   with an identity** (ad-hoc does not touch Sparkle). The paths in the script
   pin the layout of **Sparkle 2.9.4** (`Versions/Current` → `B`); if Sparkle is
   updated, re-derive them from the built framework.

3. **Appcast.** After packaging (and notarizing, on Developer ID), the script
   copies `Crema.dmg` into a staging folder containing **only it**, named
   `Crema-<version>.dmg`, and runs `generate_appcast` with
   `--download-url-prefix https://github.com/colatte/crema/releases/download/v<version>/`,
   writing `docs/appcast.xml`. Because the staging folder holds a **single** dmg,
   the feed comes out with a **single** item — the appcast is **regenerated
   whole** on every release. History lives in GitHub **Releases**, not in the
   feed; this is what keeps a single URL prefix from serving URLs that are
   actually per-tag. The script does **not** commit — publishing the appcast is a
   `git push` to `main` (Pages serves `/docs`), which it prints as the next step.
   > Since the app ships `SURequireSignedFeed`, `generate_appcast` also **signs
   > the feed itself**, with the same keychain EdDSA key, appending a
   > `<!-- sparkle-signatures: … -->` block. No extra release step — but it does
   > mean `docs/appcast.xml` is self-authenticating, and a hand edit after
   > generation is not untidiness, it is an outage for every client carrying the
   > key (docs/DECISIONS.md: the-feed-signs-itself).

---

## 5. A normal release — the ritual, in exact order

From nothing to published. Run it in a **normal macOS session** (not over SSH) —
create-dmg uses the Finder to position the icons. Example with `1.1.1`.

### 5.1 Build, sign and package

```bash
export CREMA_SIGN_IDENTITY="Crema Code Signing"   # self-signed (§2); or Developer ID (§3)
./scripts/release.sh 1.1.1
```

At the end the script prints a summary and the next steps. Check the output for:

- `Built Crema.app reports version 1.1.1.` and `… reports build 10101 (from 1.1.1).`
- `Wrote docs/appcast.xml — enclosure Crema-1.1.1.dmg, sparkle:version 10101 (read back from the feed).`
- `EdDSA enclosure signature verifies against the local signing key.`

Two distinct EdDSA signature cases:

- **A key that does not match the app's `SUPublicEDKey` → the script ABORTS** (not
  a mere warning). `generate_appcast` emits a `SUPublicEDKey … does not match`
  warning and omits the signature; `release.sh` detects the feed with no
  `sparkle:edSignature` and stops with
  `generate_appcast produced a feed with no sparkle:edSignature — the Sparkle signing key does not match the app's SUPublicEDKey`.
  Run `generate_keys -p` and compare byte for byte with `SUPublicEDKey` in
  `Crema/Info.plist` (§1).
- **A residual warning** `the enclosure EdDSA signature did not verify` — a
  separate and rare case (`sign_update --verify`): the signature is present but
  does not verify against the local key. If it appears, **stop** and review the
  signing key before publishing.

And, because the app ships `SURequireSignedFeed`, confirm the generated feed
carries the block that authenticates it:

```bash
grep -c '<!-- sparkle-signatures:' docs/appcast.xml   # must print 1
```

An unsigned feed here means the app no longer carries `SURequireSignedFeed`, or
the signing key is not reachable — either way, every already-updated client would
reject this appcast.

What is left in the repo root (both gitignored by `*.dmg`):

- **`Crema.dmg`** — the fixed name feeding the README's
  `releases/latest/download/Crema.dmg` link.
- **`Crema-1.1.1.dmg`** — a byte-for-byte copy; it is the **enclosure** whose URL
  is in `docs/appcast.xml`.

And `docs/appcast.xml` was **rewritten** (still **not** committed).

### 5.2 Test the `.dmg` locally — BEFORE publishing

You are the first to validate exactly the flow the user will go through.

1. **Mount and install.** `open Crema.dmg` → drag **Crema** to Applications.
2. **First open → the warning is expected.** The app is signed (self-signed) but
   Gatekeeper does not recognize the certificate, so it warns about an
   "unidentified developer".
3. **"Open anyway"**, as the README instructs — the Terminal path (the most
   reliable one):
   ```bash
   xattr -dr com.apple.quarantine /Applications/Crema.app
   ```
   (Or via System Settings → Privacy & Security → "Open Anyway".)
4. **Confirm it works.** Icon in the **menu bar** (not the Dock); play something
   → **now playing** near the notch; a **volume** key → the **volume HUD** (works
   without Accessibility — Core Audio); grant **Accessibility** and confirm the
   media keys; only then a **brightness** key → the **brightness HUD** (it depends
   on the event tap, which needs the permission).

If any step of "open anyway" does not match the README, fix the README **now**.

> To test the "first launch" from scratch again: `rm -rf /Applications/Crema.app`
> and reinstall from the dmg.

### 5.3 Create the GitHub Release — with BOTH assets

Check first: the Release points at **`main`** (that is what users download **and**
what Pages serves), the `.dmg` has been tested, and the version the app reports
matches the tag.

Tag **`v1.1.1`** · Title **`Crema 1.1.1`** · Assets **`Crema.dmg`** and
**`Crema-1.1.1.dmg`**.

#### Option A — `gh` (command line)

```bash
gh release create v1.1.1 Crema.dmg Crema-1.1.1.dmg \
  --target main \
  --title "Crema 1.1.1" \
  --notes-file docs/internal/release-notes-1.1.1.md \
  --latest
```

- **`Crema.dmg`** → makes the README's `releases/latest/download/Crema.dmg` link
  resolve.
- **`Crema-1.1.1.dmg`** → the **enclosure** `docs/appcast.xml` references at
  `releases/download/v1.1.1/Crema-1.1.1.dmg`. Without it, auto-update 404s.
- `--notes-file` points at a file in `docs/internal/` (gitignored working notes;
  the template is in §8). Or use `--notes "..."`, or omit it to open the editor.

Check with `gh release view v1.1.1`.

#### Option B — web UI

Repo → **Releases** → **Draft a new release** → tag `v1.1.1` (Create new tag on
publish, target `main`) → title `Crema 1.1.1` → paste the notes → **Attach
binaries**: drag **both** (`Crema.dmg` and `Crema-1.1.1.dmg`, exact names) → **Set
as the latest release** → **Publish**.

### 5.4 Publish the appcast — `git push` to `main`

`release.sh` rewrote `docs/appcast.xml` but did **not** commit it. Pages serves
`/docs` from `main`, so publishing is a commit and a push **to `main`**:

```bash
git add docs/appcast.xml
git commit -m "chore(release): appcast 1.1.1"
git push
```

> If you work on a branch (`dev`), remember: Pages serves **`main`**. The appcast
> only goes live once that commit reaches `main` (merge/PR or direct push,
> whichever your flow is). The enclosure has to be published in the Release
> **first** — otherwise the app finds the item and 404s on the download.

### 5.5 Post-publication verification

> **Wait for GitHub Pages to republish.** After the push, Pages takes tens of
> seconds to a few minutes to rebuild and serve the new `/docs`. During that
> window the `curl` below still returns the **old** feed (the previous release, or
> the empty placeholder) — the `grep` comes back empty, and that is **not** a
> broken release. Wait and repeat, or let the retry loop below run.

```bash
# 1. Is the appcast live and pointing at this release? (waits for Pages to
#    republish; ceiling ~5 min — a wrong URL must fail loudly, never wait forever)
for i in $(seq 1 20); do
  curl -fsS https://colatte.github.io/crema/appcast.xml | grep -q 'Crema-1.1.1\.dmg' && break
  [ "$i" = 20 ] && { echo "appcast did NOT go up in ~5 min — check the URL/Pages"; exit 1; }
  echo "appcast has not republished yet (Pages rebuild); waiting…"; sleep 15
done
curl -fsS https://colatte.github.io/crema/appcast.xml | grep -E 'sparkle:version|Crema-1.1.1\.dmg'
#    expect to see  sparkle:version="10101"  and the enclosure url .../v1.1.1/Crema-1.1.1.dmg

# 2. Does the enclosure actually download (following GitHub's redirect)?
curl -fsSIL https://github.com/colatte/crema/releases/download/v1.1.1/Crema-1.1.1.dmg | head -1

# 3. Does the README's fixed link resolve to the new asset?
curl -fsSIL https://github.com/colatte/crema/releases/latest/download/Crema.dmg | head -1
```

**Mandatory before the first release with an identity** (self-signed or Developer
ID): run the **E2E script** (§6) once, to watch Sparkle find, download, validate
and install end to end. The branch with an identity — Sparkle's nested re-signing
(§4.2) and the `codesign --verify --deep --strict` over the result — is **not**
covered by any unit test and is only exercised in a genuinely signed build; the
E2E is the runtime proof that the signing order and the Sparkle 2.9.4 layout are
right. On later releases it becomes recommended.

---

## 6. E2E script — proving the update cycle (on the author's machine)

Exercises Sparkle **for real**: an "old" installed app discovers a "new" build,
downloads the dmg, validates the EdDSA signature, installs and relaunches. It
runs **100% locally** (feed over `http://localhost`), touching neither GitHub nor
the published appcast.

> Why local `http` works: `localhost` is exempt from App Transport Security, and
> Sparkle accepts a feed without HTTPS **when the enclosure is EdDSA-signed**
> (ours is). The update's authentication comes from the signature, not from the
> transport.

### 6.1 Build the "old" build and install it

Two options:

- **(recommended) Build an earlier patch** from the current code, so that the old
  app **already has Sparkle** (the "Check for Updates…" menu item):
  ```bash
  export CREMA_SIGN_IDENTITY="Crema Code Signing"
  ./scripts/release.sh 1.1.0            # CFBundleVersion 10100
  open Crema.dmg                        # install into /Applications, "open anyway"
  ```
- The real installed `v1.1.0` **does not work**: that build did not embed Sparkle
  (the integration landed after the tag) and has no `SUFeedURL` — the only path
  for the E2E is building the "old" one with `release.sh`, as above. The
  corollary that matters for re-addressing: **no already-shipped binary carries
  `SUFeedURL`** — v1.2.0 is the first build in history to bake a feed URL in, so
  there is no orphaned installed base pointing at the old Pages site.

What matters: the **old** one has a **lower** `CFBundleVersion` than the new one,
and **both** are signed with the **same** `CREMA_SIGN_IDENTITY` (Sparkle refuses
to swap for a different signer).

### 6.2 Build the "new" build and generate a STAGING appcast (localhost)

```bash
export CREMA_SIGN_IDENTITY="Crema Code Signing"
./scripts/release.sh 1.1.1            # CFBundleVersion 10101 > 10100
```

That left `Crema-1.1.1.dmg` in the repo root. Now a **test** appcast pointing at
the local server (do NOT use the production `docs/appcast.xml` here):

```bash
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData \
  -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | head -1)"

E2E=/tmp/crema-e2e
rm -rf "$E2E"; mkdir -p "$E2E"
cp Crema-1.1.1.dmg "$E2E/"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "http://localhost:8000/" \
  -o "$E2E/appcast.xml" \
  "$E2E"

# Serve the staging folder (leave this running in this terminal):
cd "$E2E" && python3 -m http.server 8000
```

In another terminal, check:
`curl -fsS http://localhost:8000/appcast.xml | grep -E 'sparkle:version|enclosure'`.

### 6.3 Point the installed app at the staging feed

Sparkle honours a `SUFeedURL` override in `UserDefaults` (built for testing):

```bash
defaults write com.colatte.crema SUFeedURL "http://localhost:8000/appcast.xml"
```

### 6.4 Trigger the update

```bash
open /Applications/Crema.app        # the OLD build
```

In Crema's menu bar → **Check for Updates…**. Sparkle should: find `1.1.1`, offer
the update, download `Crema-1.1.1.dmg` from `localhost:8000`, **validate the
EdDSA**, install and **relaunch** the app.

### 6.5 Success criteria (observable)

- Sparkle's prompt appears announcing **1.1.1** (not "you're up to date").
- The download completes and there is **no** "update is improperly signed" /
  invalid-signature alert.
- After installing and relaunching, the app reports the new version:
  ```bash
  defaults read /Applications/Crema.app/Contents/Info CFBundleShortVersionString   # 1.1.1
  defaults read /Applications/Crema.app/Contents/Info CFBundleVersion              # 10101
  ```
- **The staging feed carries its signature block** and the update still installs
  from it:
  ```bash
  grep -c '<!-- sparkle-signatures:' "$E2E/appcast.xml"   # must print 1
  ```
  This is the runtime proof of the `SURequireSignedFeed` +
  `SUVerifyUpdateBeforeExtraction` pair: if the pair were wrong, Sparkle would
  refuse to **start** the updater at all rather than degrade (docs/DECISIONS.md:
  the-feed-signs-itself).
- **The gentle reminder is exercised.** With a newer version in the feed, let the
  **scheduled** check run with Crema in the background (do not use "Check for
  Updates…", which is user-initiated and deliberately does not light the line):
  the menu bar must show "An update to Crema is available." with the "Show the
  Update…" button right below it, and the line must disappear once the alert has
  received attention or the session ends (docs/DECISIONS.md:
  the-update-alert-nobody-sees).

### 6.6 Failure points and diagnosis

- **"You're up to date" (nothing offered).** The old build's `CFBundleVersion` is
  **not** lower than the new one's. Confirm `10100 < 10101` (or `1 < 10101`).
  Review the stamp (§4.1).
- **"The update is improperly signed" / invalid EdDSA.** The key that signed the
  enclosure does not match the app's `SUPublicEDKey`. Confirm
  `generate_keys -p` == `SUPublicEDKey` (§1). In a real release this mismatch
  never gets this far: `release.sh` **aborts** before publishing (a feed with no
  `sparkle:edSignature` / `does not match the app's SUPublicEDKey`, see §5.1).
- **Update downloads but does not install / "the installer could not be
  validated".** Different signers between old and new. Rebuild **both** with the
  same `CREMA_SIGN_IDENTITY`. Also check that the **nested Sparkle** was re-signed
  (§4.2) — an XPC service or Autoupdate still carrying `org.sparkle-project`'s
  ad-hoc signature makes the installer fail.
- **404 on download.** The staging `--download-url-prefix` does not match what
  `python3 -m http.server` serves. The dmg's name in the folder has to be exactly
  the enclosure's (`Crema-1.1.1.dmg`), and the prefix `http://localhost:8000/`.
- **`.dmg` enclosure refused by Sparkle.** See the caveat below (Plan B: zip).

### 6.7 Cleanup (always, when finished)

```bash
defaults delete com.colatte.crema SUFeedURL      # back to the Info.plist SUFeedURL
# Ctrl-C in the python3 -m http.server terminal
rm -rf /tmp/crema-e2e
```

> Do not forget the `defaults delete`: while the override exists, the installed
> app keeps checking `localhost` (which will be down) instead of the production
> feed.

---

## 7. Caveat — the `.dmg` enclosure (Plan B: zip)

Today the enclosure is the **`.dmg` itself** (it is also what the user downloads
manually — a single artifact). Sparkle installs updates from a `.dmg` normally.
**If** the E2E (§6) ever fails **specifically at installing from the dmg**
(Sparkle refusing or erroring while mounting the dmg as an update), **Plan B** is
to distribute the update as a **zip**, keeping the `.dmg` for the manual download
only:

```bash
# build the zip of the signed app (Plan B — NOT in release.sh)
ditto -c -k --keepParent /path/to/Crema.app Crema-1.1.1.zip
# then: generate_appcast over a staging folder containing the .zip, same --download-url-prefix
```

`ditto -c -k --keepParent` is the packaging Sparkle expects (it preserves the
bundle's metadata and symlinks). This is **documented as plan B, not implemented
in the script** — it only comes into play if the dmg-as-enclosure proves
problematic on hardware. In that case the Release would carry **three** assets
(`Crema.dmg` for manual download + `Crema-<v>.zip` as the enclosure) and
`release.sh` would be adjusted.

---

## 8. Release notes — template

Public, in English (consistent with the README). Sober tone. Save as
`docs/internal/release-notes-<version>.md` (gitignored working notes, which is
where `release.sh` looks for them) and pass it to `--notes-file`; or paste
straight into the description (option B). On the **first** release use the full
overview; afterwards, summarize **what changed** (new things, fixes).

```markdown
**Crema 1.0.0 — first release**

A quiet companion for your Mac's notch. Native and out of the way.

Crema shows what's playing near the notch — album art, a touch of its color, and
the controls you reach for — and gives volume, screen brightness, and keyboard
backlight their own HUDs that can optionally replace the system's.

**Highlights**

- Now playing at the notch: artwork, an accent color drawn from it, and play/pause,
  previous, next, and a draggable scrubber.
- Its own volume, screen-brightness, and keyboard-backlight HUDs — optionally
  replacing the native ones.
- Three styles — notch, card, and classic — one per display.
- Lives in the menu bar with no Dock icon; surfaces briefly when the track changes,
  then tucks away.
- A Settings window for styles, HUD behavior, permissions, and launch at login.

**Requirements:** macOS 14 (Sonoma) or later · Apple Silicon or Intel.

**Install:** download `Crema.dmg` below, open it, and drag Crema into Applications.
Crema isn't notarized by Apple, so the first launch needs one extra step —
see **First launch** in the README:
https://github.com/colatte/crema#first-launch

Free and open source under GPL-3.0.
```

---

## 9. The ritual, summarized

```bash
export CREMA_SIGN_IDENTITY="Crema Code Signing"
./scripts/release.sh X.Y.Z                       # build, stamp, sign (Sparkle incl.), package, regenerate appcast
open Crema.dmg                                    # local test (§5.2)
gh release create vX.Y.Z Crema.dmg Crema-X.Y.Z.dmg \
  --target main --title "Crema X.Y.Z" --notes "…" --latest     # BOTH assets
git add docs/appcast.xml && git commit -m "chore(release): appcast X.Y.Z"
# publishing = that appcast commit reaching MAIN (Pages serves /docs from main). On main,
# `git push` is enough; on a branch (dev), merge/PR — or push directly: git push origin HEAD:main
git push                                                                                   # (on main) publishes the feed
# Pages takes ~1–3 min to republish; ceiling ~5 min (a wrong URL fails loudly, §5.5)
for i in $(seq 1 20); do
  curl -fsS https://colatte.github.io/crema/appcast.xml | grep -q sparkle:version && break
  [ "$i" = 20 ] && { echo "appcast did NOT go up in ~5 min — check the URL/Pages"; exit 1; }
  sleep 15
done
```

If the app is ever signed with Developer ID and notarized, review §3, the signing
part of `scripts/release.sh` **and** the README's "First launch" section together.

> **On the Developer ID day — EVERY user's login item will be invalidated.** The
> bundle's identity changes, and macOS revokes the Background Task Management
> registration of every installation (measured on hardware on this machine: the
> signature swap took Accessibility, Media and the login item down with it). The
> app covers that by warning in the menu bar with one click to re-enable
> (docs/DECISIONS.md: login-item-intent) — but it is worth saying in the release
> notes, and worth checking on your own Mac after installing: Crema has to come up
> in the same batch as Dock/Finder on the next boot
> (`ps -o comm,lstart -p $(pgrep -x Crema)`).
