import SwiftUI

/// One step's shape: a picture, a heading, then what the step says and offers,
/// the whole of it centred in the window so a short step does not sit on a
/// field of empty space.
struct TourStepLayout<Hero: View, Content: View>: View {
    let title: String
    @ViewBuilder let hero: () -> Hero
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 14) {
            hero()
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: 170)
            Text(title)
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Where the reader is, as dots: the count is what matters at a glance, and the
/// sentence is still there for VoiceOver.
struct TourStepDots: View {
    let step: WelcomeTourStep

    var body: some View {
        let progress = WelcomeTourFlow.progress(step)
        HStack(spacing: 6) {
            ForEach(1...progress.count, id: \.self) { index in
                Circle()
                    .fill(index == progress.index ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            localized: "tour.progress",
            defaultValue: "Step \(progress.index) of \(progress.count)"
        ))
    }
}

/// One thing the app can do, said in a line under its name.
private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }
}

/// The window's ground: near-black with a lift at the top, the tone the surfaces
/// themselves are drawn in, so the tour reads as the app and not as a system
/// dialog about it.
struct TourBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(white: 0.16), Color(white: 0.09)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// What the app can do beyond the defaults, one line each under its name.
struct TourFeatureList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(
                symbol: "square.grid.3x3",
                title: String(localized: "tour.step.more.position.title", defaultValue: "Where the indicator appears"),
                detail: String(
                    localized: "tour.step.more.position.detail",
                    defaultValue: "On Card, the volume and brightness indicator can sit in one of eight places."
                )
            )
            FeatureRow(
                symbol: "rectangle.lefthalf.filled",
                title: String(localized: "tour.step.more.filled.title", defaultValue: "A filled indicator"),
                detail: String(
                    localized: "tour.step.more.filled.detail",
                    defaultValue: "On Card, the whole indicator fills up as the level rises."
                )
            )
            FeatureRow(
                symbol: "display.2",
                title: String(localized: "tour.step.more.perDisplay.title", defaultValue: "A style for each display"),
                detail: String(
                    localized: "tour.step.more.perDisplay.detail",
                    defaultValue: "Notch on the built-in display, Card on an external one."
                )
            )
            FeatureRow(
                symbol: "headphones",
                title: String(localized: "tour.step.more.output.title", defaultValue: "Where the sound goes"),
                detail: String(
                    localized: "tour.step.more.output.detail",
                    defaultValue: "The volume indicator shows where the sound is going: AirPods, headphones, an AirPlay speaker."
                )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The notes under the tour's suppression switch, the Indicators tab's own:
/// what the switch does, where brightness stops, and why it cannot engage yet.
struct TourSuppressionNotes: View {
    let core: AppCore

    var body: some View {
        VStack(spacing: 4) {
            Text(String(
                localized: "settings.hud.suppress.footer",
                defaultValue: "Hides the system volume and brightness indicators and shows Crema’s instead."
            ))
            Text(String(
                localized: "settings.hud.suppress.footer.brightnessScope",
                // swiftlint:disable:next line_length - one line, so check-catalog.py reads the defaultValue
                defaultValue: "Brightness is only replaced on the built-in display, while the pointer is on it. With the pointer on another display, macOS shows its own."
            ))
            // Split for the reason the Indicators tab states it: someone who
            // HAS granted Accessibility must not be told the grant is
            // missing. The second branch is the honest sentence for a Mac
            // with nothing to engage.
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
}

/// Said where the tour would point at the player and no display shows it.
struct TourPlayerOffNote: View {
    var body: some View {
        Text(String(
            localized: "tour.player.off",
            defaultValue: "The player is off on your displays. Turn it on to see it."
        ))
        .foregroundStyle(.secondary)
    }
}

/// The per-display switch of Settings › General, for the one display the tour
/// offers: the same key, written through the same AppCore call, so the tour
/// turns on what Settings shows as on (docs/DECISIONS.md:
/// the-tour-configures-instead-of-pointing).
struct TourPlayerSwitch: View {
    let core: AppCore
    let display: ScreenDescription
    @Binding var isOn: Bool

    var body: some View {
        // The display's name under the label and never inside it: a name is a
        // title (macOS's own, or "Built-in display"), and set mid-sentence it
        // reads as a typo in both languages.
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "tour.player.show", defaultValue: "Show the player"))
                Text(verbatim: DisplayStyleRow.title(for: display))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .onChange(of: isOn) { _, new in core.setShowsNowPlaying(new, on: display.id) }
    }
}
