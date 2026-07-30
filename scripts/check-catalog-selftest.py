#!/usr/bin/env python3
"""Proves scripts/check-catalog.py, by making it fail.

A checker nobody checks is worse than none: this one's first version reported nine
problems against a clean catalog, all its own fault, and a "clean" from a broken
checker reads exactly like a "clean" from a working one. So every rule gets a
catalog built to violate it, and two cases that must stay SILENT — the ones a
careless normalization gets wrong in the expensive direction.

Run: python3 scripts/check-catalog-selftest.py
Exit: 0 all cases hold, 1 a case failed.
"""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
CHECKER = HERE / "check-catalog.py"


def entry(en, pt, state="manual"):
    return {
        "extractionState": state,
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}},
            "pt-BR": {"stringUnit": {"state": "translated", "value": pt}},
        },
    }


def sandbox(catalog, swift):
    root = pathlib.Path(tempfile.mkdtemp())
    (root / "Crema").mkdir()
    (root / "Crema/Localizable.xcstrings").write_text(json.dumps(catalog))
    (root / "Crema/Src.swift").write_text(swift)
    return root


# (name, expected marker or None for "must report nothing", catalog, swift)
CASES = [
    ("a key used in code but absent from the catalog", "MISSING",
     {"strings": {}},
     'String(localized: "a.b", defaultValue: "Hi")'),

    ("the catalog's en drifted from the code", "DRIFT",
     {"strings": {"a.b": entry("Hello", "Ola")}},
     'String(localized: "a.b", defaultValue: "Hi")'),

    ("extractionState is not manual, so Xcode may rewrite it", "EXTRACTION",
     {"strings": {"a.b": entry("Hi", "Oi", state="automated")}},
     'String(localized: "a.b", defaultValue: "Hi")'),

    ("no pt-BR unit at all", "NO-PT-BR",
     {"strings": {"a.b": {"extractionState": "manual", "localizations": {
         "en": {"stringUnit": {"state": "translated", "value": "Hi"}}}}}},
     'String(localized: "a.b", defaultValue: "Hi")'),

    ("a key translated but used nowhere", "ORPHAN",
     {"strings": {"a.b": entry("Hi", "Oi"), "dead.key": entry("X", "X")}},
     'String(localized: "a.b", defaultValue: "Hi")'),

    ("the translation dropped one of the holes", "SPECIFIERS",
     {"strings": {"a.b": entry("%1$@ of %2$@", "%1$@")}},
     r'String(localized: "a.b", defaultValue: "\(x) of \(y)")'),

    # The sentinel case. With a SPACE standing in for a hole, "Crema 1.0" and
    # "Crema%@1.0" normalize to the same text and real drift is reported clean —
    # a false negative, the direction that ships the bug.
    ("a hole where the code has a plain space", "DRIFT",
     {"strings": {"a.b": entry("Crema%@1.0", "Crema%@1.0")}},
     'String(localized: "a.b", defaultValue: "Crema 1.0")'),

    # A literal percent is written `%%` in the catalog and `%` in Swift. Normalize
    # only one side and this identical pair reports drift forever.
    ("a literal percent beside a hole, identical on both sides", None,
     {"strings": {"a.b": entry("Battery 50%%%@dead", "Bateria 50%%%@morta")}},
     r'String(localized: "a.b", defaultValue: "Battery 50%\(x)dead")'),

    # Reordering is what positional specifiers are FOR; flagging it would punish a
    # correct translation.
    ("a translation that reorders its positional holes", None,
     {"strings": {"a.b": entry("%1$@ of %2$@", "%2$@ de %1$@")}},
     r'String(localized: "a.b", defaultValue: "\(x) of \(y)")'),
]


def main():
    failures = 0
    for name, expected, catalog, swift in CASES:
        root = sandbox(catalog, swift)
        try:
            result = subprocess.run(
                [sys.executable, str(CHECKER), str(root)], capture_output=True, text=True
            )
            if expected is None:
                held = result.returncode == 0
            else:
                held = result.returncode == 1 and expected in result.stdout
            print(f"{'ok  ' if held else 'FAIL'}  {name}")
            if not held:
                failures += 1
                print(f"        expected {expected or 'no report'}, exit {result.returncode}")
                print("        " + result.stdout.replace("\n", "\n        ").strip())
        finally:
            shutil.rmtree(root)

    print(f"\n{len(CASES) - failures}/{len(CASES)} cases hold")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
