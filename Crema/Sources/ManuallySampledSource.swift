/// A source whose value can be sampled on demand, so an external trigger (the
/// media-key tap) marks a change as key-originated instead of waiting for the
/// next poll. Sampling respects the source's own rules — de-dup, and the
/// brightness sources' origin gating — so it emits immediately when the value
/// is already applied, may defer to the armed poll when it is not, and stays
/// silent on a redundant poke.
protocol ManuallySampledSource: Sendable {
    func sample()
}
