@testable import Crema

/// Test double for the cover-lookup border: it answers whatever the test told it
/// to, and records every question.
///
/// The recording is the point of half the assertions. "The resolver did not fetch"
/// is not observable from the bytes it draws — a disabled resolver and a resolver
/// whose answer was discarded show the same cover — so the only honest proof that
/// no network call happened is that nothing was asked.
///
/// `@unchecked Sendable` because the protocol is `Sendable` (the real one crosses
/// into a `URLSession` task) while the tests drive this one from the MainActor and
/// never concurrently.
final class MockArtworkLookup: ArtworkLookup, @unchecked Sendable {
    /// The bytes to hand back, or nil for "found nothing" — which is every kind
    /// of failure as far as the caller is concerned.
    private let answer: [UInt8]?

    private(set) nonisolated(unsafe) var asked: [(title: String, artist: String?, album: String?)] = []

    init(answer: [UInt8]? = nil) {
        self.answer = answer
    }

    func highResolutionArtwork(title: String, artist: String?, album: String?) async -> [UInt8]? {
        asked.append((title, artist, album))
        return answer
    }
}
