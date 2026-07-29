/// A source whose value can be sampled on demand, so an external trigger (the
/// media-key tap) marks a change as key-originated instead of waiting for the
/// next poll. Sampling respects the source's own rules — de-dup, and the
/// brightness sources' origin gating — so it emits immediately when the value
/// is already applied, may defer to the armed poll when it is not, and stays
/// silent on a redundant poke.
protocol ManuallySampledSource: Sendable {
    func sample()

    /// Another authority just reported this channel's level, so whatever window a
    /// key opened here is spent: the change is already accounted for and this
    /// source must not emit its own reading of it. Without this, a key the tap
    /// merely OBSERVED (suppression off, so the key travels on to whoever applies
    /// it) arms this source, and both it and the reporting source draw for one
    /// press — the neighbour's value first, then this one's, which is the wrong
    /// one whenever the two measure different things (docs/DECISIONS.md:
    /// betterdisplay-osd-source). Default no-op: a source with no origin gate has
    /// no window to spend.
    func standDown()
}

extension ManuallySampledSource {
    func standDown() {}
}
