/// Stable per-display key. The raw value is the display's UUID string
/// (obtained via CGDisplayCreateUUIDFromDisplayID at the source border) —
/// never the numeric display ID, which changes across sessions/reconnections.
struct DisplayUUID: Hashable, Sendable {
    var rawValue: String
}
