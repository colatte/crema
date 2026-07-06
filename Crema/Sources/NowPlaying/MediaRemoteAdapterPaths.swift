import Foundation

/// Absolute paths to the vendored adapter inside the app bundle (copied into
/// Resources/mediaremote-adapter at build time by the "Embed mediaremote-adapter"
/// phase). nil when the resources are missing.
struct MediaRemoteAdapterPaths {
    /// The Perl entry point.
    let script: String
    /// The MediaRemoteAdapter.framework directory the script dlopens.
    let framework: String
    /// The test client, used only by the availability probe.
    let testClient: String

    static func inBundle(_ bundle: Bundle = .main) -> MediaRemoteAdapterPaths? {
        guard let root = bundle.resourceURL?.appendingPathComponent("mediaremote-adapter"),
              FileManager.default.fileExists(atPath: root.path) else {
            return nil
        }
        return MediaRemoteAdapterPaths(
            script: root.appendingPathComponent("bin/mediaremote-adapter.pl").path,
            framework: root.appendingPathComponent("MediaRemoteAdapter.framework").path,
            testClient: root.appendingPathComponent("MediaRemoteAdapterTestClient").path
        )
    }
}
