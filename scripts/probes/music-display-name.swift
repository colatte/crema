// What does macOS call the Music app for a person who reads it in Portuguese?
//
// The Permissions tab names the apps the backup now-playing reader scripts, and
// writes them as the scripts know them ("Music"), not resolved from the
// installed bundle. That holds only while macOS itself shows "Music" under a
// pt-BR locale: Music.app's InfoPlist.loctable maps `pt` to "Música", but has no
// `pt-BR`. This prints the three readings a resolver could use, under whatever
// AppleLanguages the process runs with.
//
// Run:  swift scripts/probes/music-display-name.swift -AppleLanguages '(pt-BR)'
// (the argument domain sets the process's languages, as the app's own would be).

import AppKit
import Foundation

let path = "/System/Applications/Music.app"
let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []
print("AppleLanguages: \(languages)")
print("FileManager.displayName: \(FileManager.default.displayName(atPath: path))")

if let bundle = Bundle(url: URL(fileURLWithPath: path)) {
    print("bundle localizations: \(bundle.localizations.sorted())")
    print("preferred for these languages: \(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: languages))")
    let localized = bundle.localizedInfoDictionary ?? [:]
    print("localizedInfoDictionary CFBundleDisplayName: \(localized["CFBundleDisplayName"] ?? "nil")")
    print("localizedInfoDictionary CFBundleName: \(localized["CFBundleName"] ?? "nil")")
} else {
    print("no bundle at \(path)")
}
