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
