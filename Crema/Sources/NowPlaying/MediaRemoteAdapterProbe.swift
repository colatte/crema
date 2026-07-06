import Foundation

/// Availability probe for the adapter, via its `test` command (exit 0 = the
/// adapter can use MediaRemote).
///
/// The `test` command creates a temporary fake now-playing track to probe the
/// entitlement, so it must be used only here, for availability — never in the
/// normal stream flow, where it would inject a bogus track.
struct MediaRemoteAdapterProbe {
    let paths: MediaRemoteAdapterPaths

    func isAvailable() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // Test-client path is the second argument (the script routes any arg
        // containing a slash to MEDIAREMOTEADAPTER_TEST_CLIENT_PATH).
        process.arguments = [paths.script, paths.framework, paths.testClient, "test"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
