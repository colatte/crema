/// What the menu bar should say about who is receiving the media keys.
///
/// The three cases are one story told at three stages: another app is ahead and
/// Crema simply loses those keys; the app ahead is one Crema knows how to
/// cooperate with, so the line carries the fix; or the cooperation is running and
/// the line becomes a confirmation instead of a warning.
enum MediaKeyChainNotice: Equatable {
    /// Crema is first in the chain, or nothing that could take a key is ahead.
    case quiet
    /// BetterDisplay is publishing its OSD events and Crema is drawing the screen
    /// brightness HUD from them — the arrangement working, worth saying so.
    case drawingFromBetterDisplay
    /// BetterDisplay is ahead of us in the chain and has never reported: it is
    /// taking the brightness keys with its OSD integration switched off, which is
    /// the one contention the user can resolve into cooperation.
    case betterDisplayAheadAndSilent
    /// Some other app is ahead. Naming it is all Crema can honestly do — the
    /// choice of which app should own the key is the user's.
    case anotherAppAhead(String)
}
