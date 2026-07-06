/// A media-key source whose owned keys can be consumed — swallowed before the
/// system processes them (both phases; key-downs and autorepeats forwarded to
/// the consumer). The seam the OSD suppressor engages; setting nil restores
/// pure observation, which is the suppression's reversibility story.
protocol MediaKeyConsuming: AnyObject, Sendable {
    typealias Consumer = @Sendable (MediaKey, _ fine: Bool) -> Void
    func setConsumer(_ consumer: Consumer?)
}
