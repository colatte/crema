import SwiftUI

struct SystemHUDSettingsView: View {
    let core: AppCore
    @AppStorage(Preferences.suppressesNativeOSDKey) private var suppress = false
    @AppStorage(Preferences.hudIndicatorStyleKey) private var indicatorStyle = HUDIndicatorStyle.slider.rawValue
    /// Whether any connected display RENDERS Card — the gate for the Card-scoped
    /// picker below. A mirror of what is drawn, not of the declaration: the two
    /// disagree on notchless hardware, where the default declaration is Notch and
    /// every display draws Card.
    ///
    /// Seeded once, and nothing in this tab can change the answer: the writer that
    /// can is the style declaration, which lives in the Displays tab. So a style
    /// declared with this window open leaves the gate on the previous answer until
    /// it reopens — the pinned-latent deal this mirror has always taken
    /// (docs/internal/archive/CONTRACTS-AUDIT.md: S4).
    @State private var rendersCard: Bool

    init(core: AppCore) {
        self.core = core
        _rendersCard = State(initialValue: core.rendersAnywhere(.card))
    }

    private var canSuppress: Bool {
        core.permissionMonitor.isGranted && core.osdSuppressor != nil
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $suppress) {
                    Text(String(localized: "settings.hud.suppress", defaultValue: "Replace the system indicators"))
                }
                .disabled(!canSuppress)
                .onChange(of: suppress) { _, new in core.setNativeOSDSuppression(new) }

                if !core.permissionMonitor.isGranted {
                    // The fix belongs under the line that explains the problem —
                    // the house rule for the menu, applied here. Without it the
                    // person for whom this whole tab is inert reads the longest
                    // sentence in the window and is sent to another tab to find a
                    // button that already exists. Same button, same key.
                    Button(String(
                        localized: "settings.permissions.grant",
                        defaultValue: "Grant Accessibility Access…"
                    )) {
                        core.requestAccessibilityAccess()
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        localized: "settings.hud.suppress.footer",
                        defaultValue: "Hides the system volume and brightness indicators and shows Crema's instead."
                    ))
                    // Unconditional, and deliberately not routed through
                    // `brightnessKeyTargetNotice`: that answer needs a
                    // MediaKeyChainNotice, whose every read resets the latency
                    // counters of every tap on the machine — a Form body is rebuilt
                    // whenever SwiftUI likes, so binding it here would turn a
                    // settings pane into a periodic system-wide probe. The sentence
                    // above was flatly false in two whole arrangements until this
                    // one existed: with the pointer on any other display, and on a
                    // Mac with no built-in panel at all
                    // (docs/DECISIONS.md: brightness-key-follows-the-pointer).
                    Text(String(
                        localized: "settings.hud.suppress.footer.brightnessScope",
                        // swiftlint:disable:next line_length
                        defaultValue: "Screen brightness is replaced only on the built-in display, while the pointer is on it — a key aimed at any other display is left to the system."
                    ))
                    if !canSuppress {
                        Text(String(
                            localized: "settings.hud.suppress.needsPermission",
                            defaultValue: "Needs Accessibility access — until then the system's own indicators stay."
                        ))
                        .foregroundStyle(.orange)
                    }
                }
                .settingsFootnote()
            }

            // The indicator's own appearance, in the tab that is about indicators.
            // It sat beside the Style picker in General, where a greyed row explained
            // itself by adjacency; that neighbour is gone, so the footer names the
            // style it governs and where that style is chosen.
            Section {
                // Named for what it governs, which is also why it can be greyed out
                // without a sentence excusing it: a row called "Card indicator" says
                // what it is about, where "Indicator style" only looked broken.
                //
                // Kept visible but disabled when nothing on screen renders Card (the
                // macOS dependent-setting pattern). The gate is the RENDERED style,
                // not the declared one: on hardware without a notch the default
                // declaration is Notch while every display draws Card, so gating on
                // the declaration greyed out the only control over that HUD's
                // appearance in the state the app ships in
                // (docs/DECISIONS.md: rendered-style-gates-settings).
                Picker(selection: $indicatorStyle) {
                    ForEach(HUDIndicatorStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                } label: {
                    Text(String(localized: "settings.hud.indicator", defaultValue: "Card indicator"))
                }
                .disabled(!rendersCard)
                .onChange(of: indicatorStyle) { _, new in
                    core.setHUDIndicatorStyle(HUDIndicatorStyle(rawValue: new) ?? .slider)
                }
            } footer: {
                Text(String(
                    localized: "settings.hud.indicator.footer",
                    defaultValue: "Applies to the Card style, which is chosen in the Displays tab."
                ))
                .settingsFootnote()
            }

            // Explaining the integration is always worth doing — that is what a
            // settings pane is for, and someone seeing two bars or none has nowhere
            // else to look. What is NOT always said is that it is WORKING: that
            // sentence appears only once a payload has actually arrived, because a
            // neighbour being installed, or even running, proves nothing about
            // whether its OSD integration is switched on
            // (docs/DECISIONS.md: betterdisplay-osd-source). The claim is
            // observable, so it flips with this window open: the person reading
            // this line is usually the one switching that setting on in the other
            // app, and an answer that only arrives on the next open reads as no.
            // The negative names the channel and not a fault — the common case is a
            // Mac with no BetterDisplay on it, where nothing is wrong and nothing on
            // this side turns anything on.
            Section {
                LabeledContent {
                    Text(core.betterDisplayIsReporting
                        ? String(
                            localized: "settings.hud.betterDisplay.receiving",
                            defaultValue: "Receiving"
                        )
                        : String(
                            localized: "settings.hud.betterDisplay.notReceiving",
                            defaultValue: "No signal"
                        ))
                        .foregroundStyle(core.betterDisplayIsReporting ? .primary : .secondary)
                } label: {
                    Text(String(
                        localized: "settings.hud.betterDisplay",
                        defaultValue: "BetterDisplay integration"
                    ))
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        localized: "settings.hud.betterDisplay.footer",
                        // swiftlint:disable:next line_length
                        defaultValue: "With BetterDisplay 4.2.1 or newer, Crema can show the brightness indicator for an external display. Nothing to enable here."
                    ))
                    // Named as the two switches they are, in the neighbour's own
                    // words, because this is the one place a user can act on it —
                    // and the second is what stops two bars from appearing at once.
                    Text(String(
                        localized: "settings.hud.betterDisplay.howTo",
                        // swiftlint:disable:next line_length
                        defaultValue: "In BetterDisplay, turn on Settings → Application → Integration → OSD notification, and turn its own OSD off in that same panel."
                    ))
                }
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}
