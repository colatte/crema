import SwiftUI

/// The welcome tour: five steps that CONFIGURE the app instead of describing it.
///
/// Every control here is the same control the Settings window carries — the same
/// persisted key, applied live through the same AppCore call — so the tour is a
/// place the app gets set up, not a slideshow pointing at a window the person
/// then has to find (docs/DECISIONS.md: the-tour-configures-instead-of-pointing).
/// It follows that nothing here needs undoing: what was picked in the tour is
/// what Settings shows afterwards.
///
/// The window is one fixed size for every step. The steps hold different amounts,
/// and a window that resized between them would jump under the pointer at the
/// exact moment a button is being clicked; the frame is pinned here on the root
/// so no step can grow the window by growing its content.
@MainActor
struct WelcomeTourView: View {
    let core: AppCore
    let dismiss: () -> Void

    @State private var step: WelcomeTourStep = .welcome
    /// The suppression opt-in, bound to the key the feature itself reads — the
    /// same one the Indicators tab binds, so this toggle and that one are a single
    /// switch. The live effect is the AppCore call in `onChange`, which every
    /// control that writes a preference owes.
    @AppStorage(Preferences.suppressesNativeOSDKey) private var suppressesNativeOSD = false
    /// Seeded-once mirrors, the shape the all-displays section uses: the declared style,
    /// which of the styles any panel actually renders, and the real login-item
    /// status, re-read from every attempt rather than wished at. Nothing else can
    /// write them while this window is up — it is modal in practice, being the
    /// only thing on screen at first launch.
    @State private var style: Style
    @State private var rendersCard: Bool
    @State private var rendersNotch: Bool
    @State private var launchesAtLogin: Bool
    @State private var loginNeedsApproval: Bool
    /// The desk the style tiles stand on, read once with the mirrors above and for
    /// the same reason — the store behind it (`AppCore.tileWallpaper`) is what
    /// remembers the decode, so nothing here re-opens the file per body.
    @State private var wallpaper: NSImage?

    init(core: AppCore, dismiss: @escaping () -> Void) {
        self.core = core
        self.dismiss = dismiss
        // One seed rule for both windows that carry this section — the reads and
        // their why live in StyleSectionSeed, never respelled here.
        let seed = StyleSectionSeed(core: core)
        _style = State(initialValue: seed.style)
        _rendersCard = State(initialValue: seed.rendersCard)
        _rendersNotch = State(initialValue: seed.rendersNotch)
        _wallpaper = State(initialValue: seed.wallpaper)
        _launchesAtLogin = State(initialValue: seed.launchesAtLogin)
        _loginNeedsApproval = State(initialValue: seed.loginNeedsApproval)
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Divider()
            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, Layout.margin)
                .padding(.vertical, 18)
            Divider()
            footer
        }
        .frame(width: Layout.width, height: Layout.height)
    }

    // MARK: - Chrome

    private var progressHeader: some View {
        let progress = WelcomeTourFlow.progress(step)
        return VStack(spacing: 6) {
            ProgressView(value: Double(progress.index), total: Double(progress.count))
            Text(String(
                localized: "tour.progress",
                defaultValue: "Step \(progress.index) of \(progress.count)"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Layout.margin)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            // Leaving is offered until the last step, where the primary button
            // already says the tour is over and a second way out beside it would
            // only ask the person to choose between two identical exits.
            if WelcomeTourFlow.next(after: step) != nil {
                // Esc leaves, the way it does out of every macOS sheet: this is the
                // first thing a new install shows and nothing in it is required, so
                // the platform's own way out has to reach the button that takes it.
                Button(String(localized: "tour.skip", defaultValue: "Skip")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if let previous = WelcomeTourFlow.previous(before: step) {
                Button(String(localized: "tour.back", defaultValue: "Back")) { step = previous }
            }
            primaryButtons
        }
        .padding(.horizontal, Layout.margin)
        .padding(.vertical, 14)
    }

    /// The prominent button, and — on the permission step — the way forward beside
    /// it. Two buttons there rather than one that does both: granting is a system
    /// prompt whose answer arrives later (the monitor picks it up live), so the
    /// button that asks cannot also be the button that advances without pretending
    /// the answer was yes.
    @ViewBuilder private var primaryButtons: some View {
        switch WelcomeTourFlow.primaryAction(for: step, accessibilityGranted: core.permissionMonitor.isGranted) {
        case .continue:
            continueButton
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .grantAccess:
            continueButton
            Button(String(
                localized: "settings.permissions.grant",
                defaultValue: "Grant Accessibility Access…"
            )) {
                core.requestAccessibilityAccess()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        case .done:
            Button(String(localized: "onboarding.done", defaultValue: "Done")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var continueButton: some View {
        Button(String(localized: "tour.continue", defaultValue: "Continue")) { advance() }
    }

    /// Forward, or out. The last step's button is Done rather than Continue, so
    /// the second branch is what keeps this total — never a second exit.
    private func advance() {
        guard let next = WelcomeTourFlow.next(after: step) else { dismiss(); return }
        step = next
    }

    // MARK: - The steps

    @ViewBuilder private var stepBody: some View {
        switch step {
        case .welcome: welcomeStep
        case .accessibility: accessibilityStep
        case .style: styleStep
        case .indicators: indicatorsStep
        case .finish: finishStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 14) {
            // The menu bar icon at the size it appears up there. The app has no
            // Dock tile and no window of its own, so "where is it" is the first
            // question the tour owes an answer to, and the answer is a picture of
            // the thing to look for rather than a sentence describing it. Hidden
            // from VoiceOver, which would otherwise read the asset's name aloud:
            // the sentences below carry the whole meaning either way.
            Image("MenuBarIcon")
                .accessibilityHidden(true)
                .foregroundStyle(.primary)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            // Its own key, deliberately not the window's title: every step carries a
            // heading and this is the first one, but the two strings answer to
            // different constraints — a title bar is sized by the window and this
            // line by the step — and sharing one made a change to either silently
            // rewrite the other.
            Text(String(localized: "tour.welcome.title", defaultValue: "Welcome to Crema"))
                .font(.title2.bold())
            Text(String(
                localized: "tour.welcome.body",
                // swiftlint:disable:next line_length
                defaultValue: "Crema shows what’s playing near the top of your screen and can replace the system’s volume and brightness indicators with its own."
            ))
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    /// Reuses the onboarding window's own sentences: it is the same permission,
    /// asked for in the same words, and a second wording for one concept is how
    /// two screens come to describe different things.
    private var accessibilityStep: some View {
        VStack(spacing: 12) {
            Image(systemName: core.permissionMonitor.isGranted ? "checkmark.circle.fill" : "accessibility")
                .font(.system(size: 40))
                .foregroundStyle(core.permissionMonitor.isGranted ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
            Text(String(
                localized: "tour.step.accessibility.title",
                defaultValue: "Let Crema see the media keys"
            ))
            .font(.title3.bold())
            Text(String(
                localized: "onboarding.body",
                // swiftlint:disable:next line_length
                defaultValue: "Crema uses the Accessibility permission to capture the volume and brightness keys so it can show its own indicators. Without it the app keeps working — it just can’t react to those keys."
            ))
            .foregroundStyle(.secondary)
            // The grant lands while this window is open — the monitor polls, so the
            // step answers the person who just flipped the switch in System
            // Settings instead of waiting for a relaunch nobody would perform.
            if core.permissionMonitor.isGranted {
                Text(String(
                    localized: "tour.step.accessibility.granted",
                    defaultValue: "Accessibility access is on."
                ))
                .foregroundStyle(.green)
            } else {
                Text(String(
                    localized: "onboarding.grantDetection",
                    defaultValue: "Granting is picked up automatically — no relaunch needed. If capture still doesn’t start, relaunch Crema."
                ))
                .font(.footnote)
                .foregroundStyle(.tertiary)
            }
        }
        .multilineTextAlignment(.center)
    }

    /// Picking here is the real declaration, applied at once to every display —
    /// not a preview of one. The tile is the figure a person reads; whatever the
    /// panels behind this window happen to be showing at that moment (a HUD, a
    /// track) changes with it, but nothing here depends on something being up.
    ///
    /// It carries the all-displays section's footer because it is the same
    /// declaration, and a price named in one place and not the other is a price paid
    /// by whoever met the control here first. Only the sweep sentence is worded for
    /// this window, because that one points at a list Settings has and this step
    /// does not.
    private var styleStep: some View {
        VStack(spacing: 16) {
            Text(String(localized: "tour.step.style.title", defaultValue: "Pick a style"))
                .font(.title3.bold())
            // The rendered-style mirrors are re-read from the panels right after
            // they are re-resolved, never inferred from `new`: which displays have
            // a slit is a fact about the hardware, not about the pick.
            StylePicker(selection: $style, wallpaper: wallpaper)
                .onChange(of: style) { _, new in
                    core.setStyleEverywhere(new)
                    rendersCard = core.rendersAnywhere(.card)
                    rendersNotch = core.rendersAnywhere(.notch)
                }
            VStack(spacing: 6) {
                Text(fallbackIsInEffect
                    ? String(
                        localized: "settings.general.style.footer.fallingBack",
                        defaultValue: "Applies to every display. No connected display has a notch, so every one is drawing Card."
                    )
                    : String(
                        localized: "settings.general.style.footer",
                        defaultValue: "Applies to every display. On a display without a notch, the Notch style falls back to Card."
                    ))
                // Picking a tile calls the same `setStyleEverywhere` the Settings
                // declaration does, which SWEEPS the per-display styles — on an
                // upgrading install that silently discards configuration, so this
                // window owes the same warning that section owes. Said only when
                // there is something to replace.
                //
                // Its own key, and not the Settings one: that sentence points DOWN
                // at the list under it, and there is no list here. A shared string
                // would have to lose the pointer to be true in both places, which
                // costs the pane the only wording that says WHERE.
                if hasPerDisplayStyles {
                    Text(String(
                        localized: "tour.step.style.replacesPerDisplay",
                        defaultValue: "This also replaces the per-display styles in Settings."
                    ))
                }
                Text(String(
                    localized: "tour.step.style.body",
                    defaultValue: "You can give a single display its own style later, in Settings → General."
                ))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    /// Notch is what was picked and nothing on screen is honouring it — the
    /// all-displays section's gate, copied whole. Deliberately not `!rendersNotch`
    /// alone: with Card or Classic picked there is no fallback to report and the
    /// generic sentence is the true one.
    private var fallbackIsInEffect: Bool {
        style == .notch && !rendersNotch && rendersCard
    }

    /// Whether any connected display carries a style of its own. Read where it is
    /// used rather than mirrored into state, as in Settings: the pick right above
    /// sweeps those overrides, and a seeded copy would go on promising a
    /// replacement that has already happened.
    private var hasPerDisplayStyles: Bool {
        PerDisplayStyleOverride.exists(among: core.displayRoster.displays)
    }

    /// The app's headline feature, offered where the Indicators tab offers it and
    /// with the same scope caveat: the sentence about the built-in display and the
    /// pointer is the one that keeps the switch from promising what it cannot do
    /// on a second display (docs/DECISIONS.md: brightness-key-follows-the-pointer).
    private var indicatorsStep: some View {
        VStack(spacing: 14) {
            // Names what the person gets, never what the switch below already
            // says: a heading repeating its own control's label verbatim reads as
            // the label having been printed twice.
            Text(String(
                localized: "tour.step.indicators.title",
                defaultValue: "Volume and brightness, drawn by Crema"
            ))
            .font(.title3.bold())

            Toggle(isOn: $suppressesNativeOSD) {
                Text(String(localized: "settings.hud.suppress", defaultValue: "Replace the system indicators"))
            }
            .toggleStyle(.switch)
            .disabled(!canSuppress)
            .onChange(of: suppressesNativeOSD) { _, new in core.setNativeOSDSuppression(new) }

            // The house rule, the same one the Indicators tab follows: the fix sits
            // BESIDE the control it unblocks, never in its place. Without it this
            // step showed a dead switch and a sentence naming a permission, to a
            // person whose only way to grant it was to walk back a step.
            if !core.permissionMonitor.isGranted {
                Button(String(
                    localized: "settings.permissions.grant",
                    defaultValue: "Grant Accessibility Access…"
                )) {
                    core.requestAccessibilityAccess()
                }
            }

            VStack(spacing: 6) {
                Text(String(
                    localized: "settings.hud.suppress.footer",
                    defaultValue: "Hides the system volume and brightness indicators and shows Crema’s instead."
                ))
                Text(String(
                    localized: "settings.hud.suppress.footer.brightnessScope",
                    // swiftlint:disable:next line_length
                    defaultValue: "Screen brightness is replaced only on the built-in display, while the pointer is on it — a key aimed at any other display is left to the system."
                ))
                // Split for the reason the Indicators tab states it: the joint gate
                // told someone who HAD granted Accessibility that the grant was
                // missing, which is an accusation rather than a diagnosis. The
                // second branch is the honest sentence for a Mac with nothing to
                // engage.
                if !core.permissionMonitor.isGranted {
                    Text(String(
                        localized: "settings.hud.suppress.needsPermission",
                        defaultValue: "Needs Accessibility access — until then the system’s own indicators stay."
                    ))
                    .foregroundStyle(.orange)
                } else if core.osdSuppressor == nil {
                    Text(String(
                        localized: "settings.hud.suppress.unavailable",
                        defaultValue: "System indicator replacement isn’t available on this Mac."
                    ))
                    .foregroundStyle(.orange)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    /// The same rule the Indicators tab reads: the opt-in can be persisted with
    /// nothing to engage, so the switch is offered only where it would take
    /// effect.
    private var canSuppress: Bool {
        core.permissionMonitor.isGranted && core.osdSuppressor != nil
    }

    /// Last, where a person has seen what they would be keeping. The toggle is a
    /// view onto the real registration — a custom binding, copied from the General
    /// tab, that reflects the status the attempt returns: a failed one snaps back
    /// and a pending approval stays on with the note beneath it.
    private var finishStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text(String(localized: "tour.step.finish.title", defaultValue: "You’re set"))
                .font(.title3.bold())

            Toggle(isOn: Binding(
                get: { launchesAtLogin },
                set: { wanted in
                    (launchesAtLogin, loginNeedsApproval) = core.setLaunchesAtLogin(wanted)
                }
            )) {
                Text(String(localized: "settings.general.launchAtLogin", defaultValue: "Open Crema at login"))
            }
            .toggleStyle(.switch)

            if loginNeedsApproval {
                // No written path, and a button instead — the tour's own rule
                // (the-tour-configures-instead-of-pointing) applied to the one
                // step that was still pointing. The path it used to spell,
                // "System Settings › General › Login Items", macOS 15 renamed to
                // "Login Items & Extensions"; the app supports 14+, so any
                // written path is wrong on one of them.
                Text(String(
                    localized: "settings.general.launchAtLogin.needsApproval",
                    defaultValue: "Approve Crema in System Settings to finish enabling this."
                ))
                .font(.footnote)
                .foregroundStyle(.orange)
                Button(String(
                    localized: "settings.general.launchAtLogin.openSettings",
                    defaultValue: "Open Login Items Settings…"
                )) {
                    core.openLoginItemsSettings()
                }
                .buttonStyle(.link)
                .font(.footnote)
            }

            // Where everything in this window lives afterwards, said in words rather
            // than offered as a button: nothing outside the Settings scene can open
            // that window — an accessory app has no supported call for it, so a
            // button here would be one that does nothing
            // (docs/DECISIONS.md: the-tour-configures-instead-of-pointing).
            //
            // The menu bar is the whole answer, and Command-Comma is deliberately no
            // longer part of it: a key equivalent belongs to the active app, and this
            // one has no Dock tile and no window to become active by — so the
            // shortcut fires only while the menu it was offered as an alternative to
            // is already open.
            Text(String(
                localized: "tour.step.finish.body",
                defaultValue: "Crema lives in the menu bar — its icon opens the menu, and Settings is there too."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    /// One size for the window, and the margin its content breathes in. Fixed
    /// rather than derived: the steps differ in height and the tallest (the style
    /// picker's three tiles) sets the floor, so a size that followed the content
    /// would resize the window on every step change.
    private enum Layout {
        static let width: CGFloat = 460
        static let height: CGFloat = 420
        static let margin: CGFloat = 28
    }
}
