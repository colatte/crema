import AppKit

/// One reading of everything the all-displays section seeds into `@State`.
///
/// Two windows carry that section — the welcome tour and the General tab — and
/// each used to spell the same six reads in its own `init`. Two copies of one
/// seed rule diverge on the next adjustment (a future read added to one window
/// and not the other is a section that behaves differently depending on where it
/// was opened), so the reads live here once and both views seed from the result.
/// Capturing at view construction is part of the contract: these are the
/// seeded-once mirrors both views document, not live bindings.
@MainActor
struct StyleSectionSeed {
    let style: Style
    let rendersCard: Bool
    let rendersNotch: Bool
    let wallpaper: NSImage?
    /// "On" includes pending approval: a registration BTM is still holding is an
    /// intent the user expressed, and a toggle that read it as off would invite a
    /// second click that re-registers over the pending one. Same shape as the
    /// post-write re-read (`AppCore.applyLaunchesAtLogin`), so the seeded value
    /// and the value every attempt refreshes cannot disagree.
    let launchesAtLogin: Bool
    let loginNeedsApproval: Bool

    init(core: AppCore) {
        style = core.declaredStyle()
        rendersCard = core.rendersAnywhere(.card)
        rendersNotch = core.rendersAnywhere(.notch)
        wallpaper = core.tileWallpaper()
        launchesAtLogin = core.loginItem.isEnabled || core.loginItem.requiresApproval
        loginNeedsApproval = core.loginItem.requiresApproval
    }
}
