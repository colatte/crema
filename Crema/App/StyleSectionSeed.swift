import AppKit

/// One reading of everything the all-displays section seeds into `@State`.
///
/// Two windows carry that section — the welcome tour and the General tab — and
/// both seed from here, because two copies of one seed rule diverge on the next
/// adjustment (a read added to one window and not the other is a section that
/// behaves differently depending on where it was opened).
/// Capturing at view construction is part of the contract: these are the
/// seeded-once mirrors both views document, not live bindings.
@MainActor
struct StyleSectionSeed {
    let style: Style
    /// The displays drawing Card. The General tab names them under the Card
    /// indicator; the tour only asks whether there are any.
    let cardDisplays: Set<DisplayUUID>
    var rendersCard: Bool { !cardDisplays.isEmpty }
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
        cardDisplays = core.displaysRendering(.card)
        rendersNotch = core.rendersAnywhere(.notch)
        wallpaper = core.tileWallpaper()
        launchesAtLogin = core.loginItem.isEnabled || core.loginItem.requiresApproval
        loginNeedsApproval = core.loginItem.requiresApproval
    }
}
