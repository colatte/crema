/// One step of the welcome tour, in the order they are walked. The order IS the
/// declaration order: the permission comes before the key test it makes work,
/// the style before the test that shows it, and the login-item switch comes
/// last, where a person has already seen what they would be keeping. The raw
/// values are the DEBUG step flag's vocabulary and nothing else's.
enum WelcomeTourStep: String, CaseIterable {
    case welcome
    case accessibility
    case style
    case tryIt
    case finish
}

/// Where the tour can go from a step, what its prominent button offers there,
/// and what the real screen does behind it.
///
/// Pure and stringless — the view maps a case to its sentence, the way the menu
/// maps a `MenuStatus` row — because these are the parts with a rule in them, and
/// a rule that lives in a view body is a rule nothing pins.
enum WelcomeTourFlow {
    /// What the prominent button does on a step.
    ///
    /// `grantAccess` is an OFFER standing BESIDE the way forward, never in place
    /// of it: the permission is optional to the app (without it Crema runs
    /// without key capture), so a step that could only be left by granting would
    /// trap someone who declines inside a window whose whole point is that it can
    /// be left.
    enum PrimaryAction: Equatable {
        case `continue`
        case grantAccess
        case done
    }

    static func next(after step: WelcomeTourStep) -> WelcomeTourStep? {
        self.step(offsetting: step, by: 1)
    }

    static func previous(before step: WelcomeTourStep) -> WelcomeTourStep? {
        self.step(offsetting: step, by: -1)
    }

    /// 1-based, because it is read out loud ("Step 2 of 6") and nobody counts
    /// their way through a window from zero.
    static func progress(_ step: WelcomeTourStep) -> (index: Int, count: Int) {
        let all = WelcomeTourStep.allCases
        // `allCases` contains every value by construction, so the fallback is
        // unreachable; it exists to keep the answer total rather than trapping.
        return ((all.firstIndex(of: step) ?? 0) + 1, all.count)
    }

    /// The permission decides the OFFER and nothing else — where the road goes is
    /// `next(after:)`, which never sees it.
    static func primaryAction(for step: WelcomeTourStep, accessibilityGranted: Bool) -> PrimaryAction {
        switch step {
        case .welcome, .style, .tryIt: .continue
        case .accessibility: accessibilityGranted ? .continue : .grantAccess
        case .finish: .done
        }
    }

    /// The steps that hold the real player up while they talk about it: the
    /// welcome shows what the app draws, and the style step redraws it in each
    /// pick. Every other step lets it go — the key test wants a clear screen for
    /// the HUD it asks for.
    static func holdsThePlayer(_ step: WelcomeTourStep) -> Bool {
        step == .welcome || step == .style
    }

    /// The step that points at the menu bar icon: the last one, where the person
    /// learns where the app lives once the window is gone.
    static func pointsAtTheMenuBar(_ step: WelcomeTourStep) -> Bool {
        step == .finish
    }

    /// The display the tour offers the player on, or nil when one already shows
    /// it. The player is born on only on the built-in panel
    /// (`Preferences.defaultShowsNowPlaying`), so a Mac without one, or with its
    /// lid closed, starts with it off everywhere — and a tour that shows the
    /// player has to be able to switch it on before it has anything to show. The
    /// one offered is the first in the roster, the primary display, which carries
    /// the menu bar.
    static func displayToOfferThePlayer(
        among displays: [ScreenDescription],
        showing shows: (ScreenDescription) -> Bool
    ) -> ScreenDescription? {
        displays.contains(where: shows) ? nil : displays.first
    }

    /// Both ends answer nil rather than wrapping: a tour that looped would have no
    /// last step, and the last step is the one that finishes.
    private static func step(offsetting step: WelcomeTourStep, by offset: Int) -> WelcomeTourStep? {
        let all = WelcomeTourStep.allCases
        guard let here = all.firstIndex(of: step) else { return nil }
        let there = all.index(here, offsetBy: offset)
        return all.indices.contains(there) ? all[there] : nil
    }
}
