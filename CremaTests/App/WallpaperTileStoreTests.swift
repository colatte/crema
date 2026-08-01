import AppKit
import Testing
@testable import Crema

/// What the tile backdrop costs, and what it remembers.
///
/// Every claim here is about how often a FILE IS READ, which nothing about the
/// drawn picture can show: a store that re-decoded a 6K desktop on every body
/// would look identical on screen. So the decoder is a recorder, the URLs it was
/// handed are the evidence, and object identity separates a remembered image
/// from a freshly decoded one.
@MainActor
struct WallpaperTileStoreTests {
    private static let deskA = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sonoma.heic")
    private static let deskB = URL(fileURLWithPath: "/Users/someone/Pictures/desk.jpg")

    @Test func theSamePictureIsDecodedOnceHoweverOftenTheTilesAsk() throws {
        let source = MockDesktopPictureSource(url: Self.deskA)
        let loader = RecordingLoader()
        let store = WallpaperTileStore(source: source, loadImage: loader.load)

        let first = try #require(store.backdrop())
        let second = try #require(store.backdrop())
        let third = try #require(store.backdrop())

        #expect(loader.loaded == [Self.deskA])
        // The same object, not merely an equal one: a store that re-decoded and
        // handed back a fresh image each time satisfies every assertion about
        // what is drawn while paying the full price of the file every body.
        #expect(first === second)
        #expect(second === third)
        // The border is asked every single time. Only the answer is cached —
        // caching the question would freeze the tiles on the wallpaper that was
        // set the first time anything asked.
        #expect(source.callCount == 3)
    }

    @Test func aDifferentPictureIsReadAgainAndBecomesTheRememberedOne() throws {
        let source = MockDesktopPictureSource(url: Self.deskA)
        let loader = RecordingLoader()
        let store = WallpaperTileStore(source: source, loadImage: loader.load)
        let onA = try #require(store.backdrop())

        source.url = Self.deskB
        let onB = try #require(store.backdrop())

        #expect(loader.loaded == [Self.deskA, Self.deskB])
        #expect(onA !== onB)
        // The cache MOVED rather than grew: the new desk is the one a further
        // ask gets back, and getting it back costs no third read.
        let again = try #require(store.backdrop())
        #expect(again === onB)
        #expect(loader.loaded == [Self.deskA, Self.deskB])
    }

    @Test func aBorderWithNoAnswerDrawsNothingRatherThanTheLastDesk() throws {
        let source = MockDesktopPictureSource(url: Self.deskA)
        let loader = RecordingLoader()
        let store = WallpaperTileStore(source: source, loadImage: loader.load)
        _ = try #require(store.backdrop())

        source.url = nil

        // A picture of a desk the app can no longer confirm is a picture of
        // nothing; the tile draws its own desk instead (TileBackdrop.fallback).
        #expect(store.backdrop() == nil)
        // And "nothing" costs no read: the fallback is a decision, not a failed
        // decode.
        #expect(loader.loaded == [Self.deskA])
    }

    @Test func aPictureThatFailedToDecodeIsRememberedUntilItChanges() throws {
        let source = MockDesktopPictureSource(url: Self.deskA)
        let loader = RecordingLoader()
        loader.unreadable = [Self.deskA]
        let store = WallpaperTileStore(source: source, loadImage: loader.load)

        #expect(store.backdrop() == nil)
        #expect(store.backdrop() == nil)
        #expect(store.backdrop() == nil)

        // One attempt, not one per body: a dynamic or aerial desktop is a file
        // ImageIO opens for nobody, and a store that only remembered SUCCESS
        // would re-open it every time SwiftUI feels like rebuilding the tiles.
        #expect(loader.loaded == [Self.deskA])

        source.url = Self.deskB
        _ = try #require(store.backdrop())

        // The remembered failure belongs to the file, not to the store: a new
        // picture is read on its own merits.
        #expect(loader.loaded == [Self.deskA, Self.deskB])
    }
}

/// The decoder the store is handed, standing in for ImageIO: it records every
/// URL it was asked to open and answers with a DISTINCT object per call, so a
/// remembered image and a re-decoded one are told apart by identity.
@MainActor
private final class RecordingLoader {
    private(set) var loaded: [URL] = []

    /// Files the decode is scripted to fail on — an aerial desktop, a picture
    /// that moved, anything ImageIO will not open.
    var unreadable: Set<URL> = []

    func load(_ url: URL) -> NSImage? {
        loaded.append(url)
        guard !unreadable.contains(url) else { return nil }
        return NSImage(size: NSSize(width: 1, height: 1))
    }
}
