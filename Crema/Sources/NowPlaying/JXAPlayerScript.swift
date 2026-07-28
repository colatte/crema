/// The one home for which players the JXA fallback talks to, and in what
/// precedence: read (JXANowPlayingSource) and command (JXACommandChannel)
/// interpolate this same preamble, so both sides always agree on which player
/// is "the active one". A third player, or a precedence change, lands here
/// once and reaches both scripts — split per-script lists would let the UI
/// show one player while the buttons drive another, silently, on the
/// low-observability fallback path.
enum JXAPlayerScript {
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
