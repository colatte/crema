import Foundation

/// The environment every child process starts with: a fixed PATH and the few keys
/// a tool reads to find the user (home, temp dir, locale), never Crema's whole
/// environment. Whoever controls Crema's launch environment would otherwise reach
/// into its children as well: `PERL5OPT` or `PERL5LIB` run Perl of their choosing
/// inside the adapter, which runs as Crema's child.
enum ChildProcessEnvironment {
    static let path = "/usr/bin:/bin:/usr/sbin:/sbin"
    static let passedThrough: Set<String> = [
        "HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "__CF_USER_TEXT_ENCODING",
    ]

    static func sanitized(_ environment: [String: String]) -> [String: String] {
        var kept = environment.filter { passedThrough.contains($0.key) }
        kept["PATH"] = path
        return kept
    }

    static var current: [String: String] {
        sanitized(ProcessInfo.processInfo.environment)
    }
}
