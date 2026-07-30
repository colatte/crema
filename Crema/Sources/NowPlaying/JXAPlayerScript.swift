/// The one home for which players the JXA fallback talks to, and in what
/// precedence: read (JXANowPlayingSource) and command (JXACommandChannel)
/// interpolate this same preamble, so both sides always agree on which player
/// is "the active one". A third player, or a precedence change, lands here
/// once and reaches both scripts — split per-script lists would let the UI
/// show one player while the buttons drive another, silently, on the
/// low-observability fallback path.
///
/// Everything OUTSIDE the script that has to talk about these players reads
/// `players` from here, for the same reason: the Automation permission check asks
/// macOS per bundle ID and Settings names them to the user, so a second list
/// would let the app check consent for a player the script never asks — or
/// promise one it does not script. The two representations cannot be generated
/// from each other (the preamble also carries the per-player isSpotify flag its
/// callers branch on), so a test pins that they name the same set.
enum JXAPlayerScript {
    /// One scriptable player, named the two ways the app needs it: the bundle ID
    /// macOS answers Automation consent for, and the name shown to the user.
    struct Player: Sendable {
        let bundleID: String
        let name: String
    }

    /// The players, in the preamble's own precedence order.
    static let players = [
        Player(bundleID: "com.spotify.client", name: "Spotify"),
        Player(bundleID: "com.apple.Music", name: "Music"),
    ]

    /// JS helper `withActivePlayer(fn)`: calls `fn(app, state, isSpotify)` on
    /// the first player in precedence order that is running and not stopped,
    /// returning fn's (truthy) result; null when none qualifies or scripting
    /// throws (app not installed / not scriptable / no Automation permission).
    static let preamble = """
      function withActivePlayer(fn) {
        function attempt(name, isSpotify) {
          try {
            const app = Application(name);
            if (!app.running()) return null;
            const state = app.playerState();
            if (state === 'stopped') return null;
            return fn(app, state, isSpotify);
          } catch (e) {
            return null;   // app not installed / not scriptable
          }
        }
        return attempt('Spotify', true) || attempt('Music', false);
      }
    """
}
