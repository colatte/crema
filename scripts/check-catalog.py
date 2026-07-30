#!/usr/bin/env python3
"""Checks Crema/Localizable.xcstrings against the discipline CLAUDE.md states.

This exists because Xcode does not. Measured: with `extractionState: manual`,
`xcstringstool sync` walks past an entry whose `en` has drifted from the code —
intact, no warning — and never marks an orphan. So the catalog gets zero drift
detection and zero orphan detection from the toolchain, and every rule below has a
failure mode that ships silently to a pt-BR user.

  1. every localized key in code exists in the catalog   a missing key ships the
                                                         English defaultValue
  2. the code's defaultValue matches the catalog's `en`   drift makes the source of
                                                         truth ambiguous
  3. extractionState is manual                            Xcode may otherwise prune
                                                          or rewrite the entry
  4. every key has a translated pt-BR unit                the point of a second
                                                          language
  5. no orphan keys                                       dead strings still get
                                                          translated
  6. `en` and pt-BR carry the same specifiers             a translation that drops
                                                          or renames a hole is a
                                                          wrong format string
                                                          served only to Brazilians

Rule 2 compares FORM, not text: both sides are normalized so every hole becomes one
sentinel. It never tries to infer what a hole's TYPE would be — a regex cannot type
a Swift expression, and an early version that guessed reported nine problems that
were all its own fault.

Run: python3 scripts/check-catalog.py [repo-root]
Exit: 0 clean, 1 problems found, 2 could not run.
"""
import json
import pathlib
import re
import sys

# One sentinel per hole, on both sides. Deliberately NOT a space: with a space,
# "Crema 1.0" in the code and "Crema%@1.0" in the catalog normalize to the same
# text and the drift goes unreported — a false negative, which is the failure this
# whole script exists to prevent.
HOLE = "\x00"
# Stands in for an escaped percent while specifiers are being replaced, so `%%`
# (a literal %) is never mistaken for a conversion. Any character the sources
# cannot contain would do; this one cannot appear in a Swift string literal.
ESCAPED_PERCENT = "\x01"

# A printf conversion as the String Catalog writes them, positional form included.
SPECIFIER = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|j|t)?[@dDiuUxXoOfFeEgGaAcCsSp]")
# Swift interpolation, tolerating one level of nested parentheses inside the hole.
INTERPOLATION = re.compile(r"\\\(([^()]*(?:\([^()]*\))?[^()]*)\)")

# Two call shapes, and both needed a correction after a first pass reported nine
# problems that were all the checker's own fault:
#   - String(localized:defaultValue:) can carry a COMMENT between its arguments
#     (a `// swiftlint:disable:next line_length` sits right there in this repo),
#     so the gap between them is not only whitespace.
#   - Text("key", comment:) is the other shape, for VoiceOver labels. It carries no
#     defaultValue, so only the key is checkable.
SKIP_BETWEEN = r"(?:\s|//[^\n]*\n)*"
LOCALIZED = re.compile(
    r"String\(" + SKIP_BETWEEN + r"localized:" + SKIP_BETWEEN + r'"([^"]+)"' + SKIP_BETWEEN
    + r"," + SKIP_BETWEEN + r"defaultValue:" + SKIP_BETWEEN + r'"((?:[^"\\]|\\.)*)"'
)
TEXT_WITH_COMMENT = re.compile(r'Text\(\s*"([a-z][a-zA-Z0-9.]*\.[a-zA-Z0-9.]+)"\s*,\s*comment:')

SKIP_DIRS = {".git", "build", "DerivedData", ".build"}


def unescape(literal):
    """A Swift string literal's source text as the value it denotes."""
    return literal.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")


def shape_of_code(default):
    """The code side, holes collapsed. A literal % stays a literal %."""
    return INTERPOLATION.sub(HOLE, default)


def shape_of_catalog(value):
    """The catalog side, holes collapsed and `%%` restored to one literal %.

    Both halves matter and they must happen in this order: replacing specifiers
    first would eat the second character of `%%` as a conversion, and the two sides
    would then disagree about a string that is identical in both.
    """
    protected = value.replace("%%", ESCAPED_PERCENT)
    return SPECIFIER.sub(HOLE, protected).replace(ESCAPED_PERCENT, "%")


def specifiers_of(value):
    """The conversions a value carries, order-insensitive.

    A sorted multiset rather than a sequence, because reordering is exactly what
    positional specifiers are FOR: a translation is allowed to say "%2$@ de %1$@"
    where English says "%1$@ of %2$@". What it may not do is lose one or change
    what it consumes.
    """
    protected = value.replace("%%", ESCAPED_PERCENT)
    return sorted(SPECIFIER.findall(protected))


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    catalog_path = root / "Crema/Localizable.xcstrings"
    if not catalog_path.exists():
        print(f"no catalog at {catalog_path}", file=sys.stderr)
        return 2

    strings = json.loads(catalog_path.read_text()).get("strings", {})

    used = {}
    for path in sorted(root.rglob("*.swift")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        text = path.read_text(errors="replace")
        for key, default in LOCALIZED.findall(text):
            used.setdefault(key, []).append((path.relative_to(root), default))
        for key in TEXT_WITH_COMMENT.findall(text):
            # No defaultValue to compare: None means "key exists, value unverifiable".
            used.setdefault(key, []).append((path.relative_to(root), None))

    problems = []
    for key, sites in sorted(used.items()):
        entry = strings.get(key)
        if entry is None:
            problems.append(f"MISSING    {key}  (used in {sites[0][0]})")
            continue

        if entry.get("extractionState") != "manual":
            problems.append(f"EXTRACTION {key}  is {entry.get('extractionState')!r}, expected 'manual'")

        locs = entry.get("localizations", {})
        en = locs.get("en", {}).get("stringUnit", {}).get("value")
        if en is None:
            problems.append(f"NO-EN      {key}")
        else:
            for site, default in sites:
                if default is None:
                    continue
                if shape_of_code(unescape(default)) != shape_of_catalog(en):
                    problems.append(
                        f"DRIFT      {key}\n"
                        f"             code ({site}): {unescape(default)!r}\n"
                        f"             catalog en:      {en!r}"
                    )
                    break

        pt = locs.get("pt-BR", {}).get("stringUnit", {})
        if not pt.get("value"):
            problems.append(f"NO-PT-BR   {key}")
            continue
        if pt.get("state") not in {"translated", None}:
            problems.append(f"PT-STATE   {key}  state={pt.get('state')!r}")
        # Guarded on `en`: without this the parity check raises on exactly the
        # NO-EN entry it was asked to report, and the run dies instead of listing.
        if en is not None and specifiers_of(en) != specifiers_of(pt["value"]):
            problems.append(
                f"SPECIFIERS {key}  en {specifiers_of(en)} vs pt-BR {specifiers_of(pt['value'])}"
            )

    for key in sorted(set(strings) - set(used)):
        problems.append(f"ORPHAN     {key}  (in the catalog, used nowhere in code)")

    print(f"catalog: {len(strings)} keys | code: {len(used)} keys referenced")
    if not problems:
        print("clean: every rule holds")
        return 0
    print(f"\n{len(problems)} problem(s):\n")
    for problem in problems:
        print("  " + problem)
    return 1


if __name__ == "__main__":
    sys.exit(main())
