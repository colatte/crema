import SwiftUI

/// The welcome tour: five steps that show the app working on the real screen and
/// CONFIGURE it, instead of describing it.
///
/// Every control here is the same control the Settings window carries — the same
/// persisted key, applied live through the same AppCore call — so the tour is a
/// place the app gets set up, not a slideshow pointing at a window the person
/// then has to find (docs/DECISIONS.md: the-tour-configures-instead-of-pointing).
/// It follows that nothing here needs undoing: what was picked in the tour is
/// what Settings shows afterwards. What happens on the screen behind each step
/// (the player held up, the arrow at the menu bar) is AppCore's, per step.
///
/// The window is one fixed size for every step. The steps hold different amounts,
/// and a window that resized between them would jump under the pointer at the
/// exact moment a button is being clicked; the frame is pinned here on the root
/// so no step can grow the window by growing its content.
@MainActor
struct WelcomeTourView: View {
    let core: AppCore
    let dismiss: () -> Void

    @State private var step: WelcomeTourStep
    /// Whether a HUD has risen since the key test came on screen: the test's
    /// answer, and a one-way one — the bar reverting a moment later does not
    /// take back that the key arrived.
    @State private var heardAKey = false
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
    /// The display the player is offered on when no display shows it, seeded once
    /// like the mirrors above and kept for the whole window: the switch has to
    /// stay under the hand after it is flipped, not vanish because it worked.
    @State private var playerOffer: ScreenDescription?
    @State private var playerOfferOn = false

    init(core: AppCore, firstStep: WelcomeTourStep = .welcome, dismiss: @escaping () -> Void) {
        self.core = core
        self.dismiss = dismiss
        _step = State(initialValue: firstStep)
        // One seed rule for both windows that carry this section — the reads and
        // their why live in StyleSectionSeed, never respelled here.
        let seed = StyleSectionSeed(core: core)
        _style = State(initialValue: seed.style)
        _rendersCard = State(initialValue: seed.rendersCard)
        _rendersNotch = State(initialValue: seed.rendersNotch)
        _wallpaper = State(initialValue: seed.wallpaper)
        _launchesAtLogin = State(initialValue: seed.launchesAtLogin)
        _loginNeedsApproval = State(initialValue: seed.loginNeedsApproval)
        _playerOffer = State(initialValue: core.welcomeTourPlayerOffer())
    }

    var body: some View {
        VStack(spacing: 0) {
            // A cross-fade between steps and never a slide: a fade is what Reduce
            // Motion asks motion to become, so one transition serves both.
            stepBody
                .id(step)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Layout.margin)
                .padding(.top, Layout.top)
            footer
        }
        .frame(width: Layout.width, height: Layout.height)
        .onChange(of: step, initial: true) { _, entered in
            core.welcomeTourEntered(entered)
            if entered == .tryIt { heardAKey = false }
        }
        .onChange(of: core.permissionMonitor.isGranted) { _, granted in
            if granted, step == .accessibility { core.bringWelcomeTourForward() }
        }
        // The HUD's value, not whether one is up: a key pressed while a bar from
        // an earlier press is still on screen updates that bar, and must count.
        .onChange(of: core.coordinator.layers.hud) { _, hud in
            if hud != nil, step == .tryIt { heardAKey = true }
        }
    }

    // MARK: - Chrome

    private var footer: some View {
        HStack(spacing: 10) {
            TourStepDots(step: step)
            Spacer()
            // Leaving is offered until the last step, where the primary button
            // already says the tour is over and a second way out beside it would
            // only ask the person to choose between two identical exits.
            if WelcomeTourFlow.next(after: step) != nil {
                // Esc leaves, the way it does out of every macOS sheet: this is the
                // first thing a new install shows and nothing in it is required, so
                // the platform's own way out has to reach the button that takes it.
                Button(String(localized: "tour.skip", defaultValue: "Skip")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            if let previous = WelcomeTourFlow.previous(before: step) {
                Button(String(localized: "tour.back", defaultValue: "Back")) { go(to: previous) }
            }
            primaryButtons
        }
        .controlSize(.large)
        .padding(.horizontal, Layout.margin)
        .padding(.vertical, 18)
    }

    /// The way forward. On the permission step, before the grant, it is the plain
    /// way on and the grant itself is the step's own prominent button: two
    /// buttons rather than one that does both, because granting is a system
    /// prompt whose answer arrives later (the monitor picks it up live), so the
    /// button that asks cannot also be the button that advances without pretending
    /// the answer was yes. The way on names what declining costs, so going on
    /// without the grant is a choice the person can read.
    @ViewBuilder private var primaryButtons: some View {
        switch WelcomeTourFlow.primaryAction(for: step, accessibilityGranted: core.permissionMonitor.isGranted) {
        case .continue:
            Button(step == .welcome
                ? String(localized: "tour.start", defaultValue: "Get Started")
                : String(localized: "tour.continue", defaultValue: "Continue")) { advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
        case .grantAccess:
            Button(String(localized: "tour.step.accessibility.without", defaultValue: "Continue Without Access")) {
                advance()
            }
        case .done:
            Button(String(localized: "onboarding.done", defaultValue: "Done")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Forward, or out. The last step's button is Done rather than Continue, so
    /// the second branch is what keeps this total — never a second exit.
    private func advance() {
        guard let next = WelcomeTourFlow.next(after: step) else { dismiss(); return }
        go(to: next)
    }

    private func go(to target: WelcomeTourStep) {
        withAnimation(.easeInOut(duration: 0.25)) { step = target }
    }

    // MARK: - The steps

    @ViewBuilder private var stepBody: some View {
        switch step {
        case .welcome: welcomeStep
        case .accessibility: accessibilityStep
        case .style: styleStep
        case .tryIt: tryItStep
        case .finish: finishStep
        }
    }

    /// The app's icon, and the player itself on the real screen behind the
    /// window (AppCore holds it up for this step): what Crema is, answered by the
    /// thing rather than a paragraph about it.
    private var welcomeStep: some View {
        TourStepLayout(
            title: String(localized: "tour.welcome.title", defaultValue: "Welcome to Crema"),
            hero: {
                // The icon carries no meaning the title does not; hidden from
                // VoiceOver, which would otherwise read the image's name aloud.
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 128, height: 128)
                    .accessibilityHidden(true)
            },
            content: {
                Text(String(
                    localized: "tour.welcome.body",
                    defaultValue: "Crema shows what’s playing on your screen, and can show its own bar when you change the volume or brightness."
                ))
                .foregroundStyle(.secondary)
                // Said for what is actually up there: the sample is named as one,
                // so nobody goes looking for a song that is not playing, and a
                // player switched off everywhere is said to be off.
                if !playerIsShownSomewhere {
                    TourPlayerOffNote()
                } else {
                    Text(core.coordinator.showsSample
                        ? String(
                            localized: "tour.welcome.sample",
                            defaultValue: "Nothing is playing, so the player on your screen shows a sample. Play a song to see yours."
                        )
                        : String(
                            localized: "tour.welcome.playing",
                            defaultValue: "The player on your screen is Crema, showing what’s playing now."
                        ))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let playerOffer {
                    TourPlayerSwitch(core: core, display: playerOffer, isOn: $playerOfferOn)
                }
            }
        )
    }

    /// What the permission is for, in the things it lets the app do, and what it
    /// never sees — the list the standalone permission window shows too.
    private var accessibilityStep: some View {
        let granted = core.permissionMonitor.isGranted
        return TourStepLayout(
            title: String(localized: "tour.step.accessibility.title", defaultValue: "Let Crema notice the volume and brightness keys"),
            hero: {
                Image(systemName: granted ? "checkmark.circle.fill" : "accessibility")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(granted ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            },
            content: {
                AccessibilityPurposeList()
                    .fixedSize()
                // The grant lands while this window is open — the monitor polls, so
                // the step answers the person who just flipped the switch in System
                // Settings instead of waiting for a relaunch nobody would perform.
                if granted {
                    Text(String(localized: "tour.step.accessibility.granted", defaultValue: "Accessibility is on for Crema."))
                        .foregroundStyle(.green)
                } else {
                    // In the step and not the footer: the footer's row has no room
                    // for it beside the way on, in either language.
                    Button(String(
                        localized: "settings.permissions.grant",
                        defaultValue: "Grant Accessibility Access…"
                    )) {
                        core.requestAccessibilityAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    Text(String(
                        localized: "onboarding.grantDetection",
                        // swiftlint:disable:next line_length - one line, so check-catalog.py reads the defaultValue
                        defaultValue: "Crema notices the permission on its own, so there’s no need to restart. If the keys still don’t respond, quit and reopen Crema."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        )
    }

    /// Picking here is the real declaration, applied at once to every display —
    /// and the player AppCore holds up on the real screen redraws in it, so the
    /// tile is the label and the screen is the preview.
    ///
    /// It carries the all-displays section's footer because it is the same
    /// declaration, and a price named in one place and not the other is a price paid
    /// by whoever met the control here first. Only the sweep sentence is worded for
    /// this window, because that one points at a list Settings has and this step
    /// does not.
    private var styleStep: some View {
        TourStepLayout(
            title: String(localized: "tour.step.style.title", defaultValue: "Pick a style"),
            hero: {
                // The rendered-style mirrors are re-read from the panels right after
                // they are re-resolved, never inferred from `new`: which displays have
                // a slit is a fact about the hardware, not about the pick.
                StylePicker(selection: $style, wallpaper: wallpaper)
                    .onChange(of: style) { _, new in
                        core.setStyleEverywhere(new)
                        rendersCard = core.rendersAnywhere(.card)
                        rendersNotch = core.rendersAnywhere(.notch)
                    }
            },
            content: {
                if playerIsShownSomewhere {
                    Text(String(
                        localized: "tour.step.style.live",
                        defaultValue: "The player on your screen changes as you pick."
                    ))
                    .foregroundStyle(.secondary)
                } else {
                    TourPlayerOffNote()
                }
                if let playerOffer {
                    TourPlayerSwitch(core: core, display: playerOffer, isOn: $playerOfferOn)
                }
                VStack(spacing: 4) {
                    Text(fallbackIsInEffect
                        ? String(
                            localized: "settings.general.style.footer.fallingBack",
                            defaultValue: "Changes every display at once. None of your displays has a notch, so they all use Card."
                        )
                        : String(
                            localized: "settings.general.style.footer",
                            defaultValue: "Changes every display at once. On a display without a notch, Notch shows as Card."
                        ))
                    // Picking a tile calls the same `setStyleEverywhere` the Settings
                    // declaration does, which SWEEPS the per-display styles — on an
                    // upgrading install that silently discards configuration, so this
                    // window owes the same warning that section owes. Said only when
                    // there is something to replace.
                    //
                    // Its own key, and not the Settings one: that sentence points DOWN
                    // at the list under it, and there is no list here.
                    if hasPerDisplayStyles {
                        Text(String(
                            localized: "tour.step.style.replacesPerDisplay",
                            defaultValue: "This also clears the styles set for single displays in Settings."
                        ))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        )
    }

    private var playerIsShownSomewhere: Bool {
        playerOffer == nil || playerOfferOn
    }

    private var fallbackIsInEffect: Bool {
        Style.fallsBackToCard(declared: style, rendersNotch: rendersNotch, rendersCard: rendersCard)
    }

    /// Whether any connected display carries a style of its own. Read where it is
    /// used rather than mirrored into state, as in Settings: the pick right above
    /// sweeps those overrides, and a seeded copy would go on promising a
    /// replacement that has already happened.
    private var hasPerDisplayStyles: Bool {
        PerDisplayStyleOverride.exists(among: core.displayRoster.displays)
    }

    /// The person presses a key and the real HUD answers, in the style just
    /// picked: the one step that teaches by doing (HIG, Onboarding). A volume key
    /// works with or without the grant, Core Audio reporting the change either
    /// way, so the test never waits on the permission.
    ///
    /// Under it the app's headline switch, offered where the Indicators tab offers
    /// it and with the same scope caveat: the sentence about the built-in display
    /// and the pointer keeps the switch from promising what it cannot do on a
    /// second display (docs/DECISIONS.md: brightness-key-follows-the-pointer).
    private var tryItStep: some View {
        TourStepLayout(
            title: String(localized: "tour.step.try.title", defaultValue: "Press a volume key"),
            hero: {
                Image(systemName: heardAKey ? "checkmark.circle.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(heardAKey ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            },
            content: {
                Text(heardAKey
                    ? String(localized: "tour.step.try.heard", defaultValue: "That’s Crema’s indicator.")
                    : String(localized: "tour.step.try.waiting", defaultValue: "Crema’s indicator shows up on your screen."))
                    .foregroundStyle(heardAKey ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))

                VStack(spacing: 10) {
                    Toggle(isOn: $suppressesNativeOSD) {
                        Text(String(localized: "settings.hud.suppress", defaultValue: "Replace the system indicators"))
                    }
                    .toggleStyle(.switch)
                    .disabled(!core.suppressionAvailable)
                    .onChange(of: suppressesNativeOSD) { _, new in core.setNativeOSDSuppression(new) }

                    // The house rule, the same one the Indicators tab follows: the fix
                    // sits by the control it unblocks, never in its place — under it,
                    // since beside it the row outgrows the window in Portuguese.
                    if !core.permissionMonitor.isGranted {
                        Button(String(
                            localized: "settings.permissions.grant",
                            defaultValue: "Grant Accessibility Access…"
                        )) {
                            core.requestAccessibilityAccess()
                        }
                    }
                }

                SuppressionNotes(core: core, alignment: .center)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        )
    }

    /// Last, where a person has seen what they would be keeping. The toggle is
    /// the General tab's own (`LaunchAtLoginToggle`): a failed attempt snaps back
    /// and a pending approval stays on with the note beneath it. The arrow at the
    /// real icon is AppCore's, shown for this step.
    private var finishStep: some View {
        TourStepLayout(
            title: String(localized: "tour.step.finish.title", defaultValue: "You’re set"),
            hero: {
                // The menu bar, pointed at: the app has no Dock tile and no window
                // of its own, so "where is it" is the question this step owes an
                // answer to — and the arrow on the real screen gives it.
                Image(systemName: "menubar.arrow.up.rectangle")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            },
            content: {
                // The menu bar is the whole answer, with no Command-Comma beside it:
                // a key equivalent belongs to the active app, and this one has no
                // Dock tile and no window to become active by — so the shortcut
                // fires only while the menu is already open. And words rather than
                // a Settings button: nothing outside the Settings scene can open
                // that window (docs/DECISIONS.md: the-tour-configures-instead-of-pointing).
                Text(String(
                    localized: "tour.step.finish.body",
                    defaultValue: "Crema lives in the menu bar, with no Dock icon. Its menu has Settings, and this tour if you want to see it again."
                ))
                .foregroundStyle(.secondary)

                LaunchAtLoginToggle(core: core, isOn: $launchesAtLogin, needsApproval: $loginNeedsApproval)
                    .toggleStyle(.switch)

                if loginNeedsApproval {
                    // No written path, and a button instead — the tour's own rule
                    // (the-tour-configures-instead-of-pointing): macOS 15 renamed
                    // the pane to "Login Items & Extensions" and the app supports
                    // 14+, so any written path is wrong on one of them.
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
            }
        )
    }

    /// One size for the window, and the margins its content breathes in. Fixed
    /// rather than derived: the steps differ in height and the tallest (the key
    /// test's switch and its notes) sets the floor, so a size that followed the
    /// content would resize the window on every step change.
    private enum Layout {
        static let width: CGFloat = 560
        static let height: CGFloat = 520
        static let margin: CGFloat = 36
        /// Air under the title bar: SwiftUI already keeps the content clear of
        /// it (the window's safe area), so this is spacing and nothing more.
        static let top: CGFloat = 12
    }
}
