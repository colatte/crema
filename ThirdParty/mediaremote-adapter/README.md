# mediaremote-adapter (vendored)

Now-playing bridge used by `Crema/Sources/NowPlaying/`. macOS blocks
`MRMediaRemoteGetNowPlayingInfo` without an entitlement since 15.4; this adapter
loads the private MediaRemote framework out-of-process (a Perl script `dlopen`s
a small Objective-C framework) and streams now-playing state as JSON lines.

## Vendored version

- Upstream: https://github.com/ungive/mediaremote-adapter
- Release tag: **v0.7.6** (published 2026-05-11). Do not vendor < 0.7 — earlier
  versions leak memory in the Perl process.
- License: **BSD-3-Clause** (`LICENSE` in this directory; Copyright (c) 2025
  Jonas van den Berg and contributors).

## Contents

- `bin/mediaremote-adapter.pl` — entry point (verbatim from upstream).
- `MediaRemoteAdapter.framework` — the Objective-C framework the script loads.
- `MediaRemoteAdapterTestClient` — helper used only by the `test` command.

The framework and test client are not shipped as release binaries, so they were
built from the v0.7.6 source (universal x86_64 + arm64) with the Xcode clang
toolchain, mirroring the upstream CMake build:

```
clang -arch x86_64 -arch arm64 -dynamiclib -fobjc-arc -fvisibility=default \
  -mmacosx-version-min=14.0 -Iinclude -Isrc \
  src/adapter/*.m src/private/MediaRemote.m src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o MediaRemoteAdapter        # then assembled into the .framework bundle

clang -arch x86_64 -arch arm64 -fobjc-arc -mmacosx-version-min=14.0 -Isrc/test \
  src/test/main.m src/test/NowPlayingTest.m \
  -framework Foundation -framework MediaPlayer -o MediaRemoteAdapterTestClient
```

Both are ad-hoc signed (`codesign --sign -`), matching the upstream CMake
post-build step.

## Usage (see Sources/NowPlaying)

```
# stream (long-running; JSON line per update on stdout)
/usr/bin/perl bin/mediaremote-adapter.pl MediaRemoteAdapter.framework stream

# availability probe — creates a temporary FAKE track; exit 0 = functional.
# Use ONLY for isAvailable(), never in the normal flow.
/usr/bin/perl bin/mediaremote-adapter.pl MediaRemoteAdapter.framework \
  MediaRemoteAdapterTestClient test
```

## Updating

Bump the release tag above, rebuild both binaries from that tag's source with
the commands above, replace the files here, and re-run the app's adapter
observation to confirm the stream still parses.
