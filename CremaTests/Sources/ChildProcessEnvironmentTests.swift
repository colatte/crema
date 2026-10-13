import Testing
@testable import Crema

/// What a child process inherits: a fixed PATH and the user's own few keys,
/// never a launch environment someone else may have set.
struct ChildProcessEnvironmentTests {

    @Test func onlyTheUsersOwnKeysAndAFixedPathReachAChild() {
        let launched = [
            "HOME": "/Users/someone",
            "LANG": "pt_BR.UTF-8",
            "PATH": "/tmp/evil:/usr/bin",
            "PERL5OPT": "-Mevil",
            "PERL5LIB": "/tmp/evil",
            "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib",
        ]
        let child = ChildProcessEnvironment.sanitized(launched)
        #expect(child == [
            "HOME": "/Users/someone",
            "LANG": "pt_BR.UTF-8",
            "PATH": ChildProcessEnvironment.path,
        ])
    }
}
