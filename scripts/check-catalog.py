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

Two reports sit outside those six, and both say the same thing: this call site was
NOT checked. A rule that quietly applies to nothing reads exactly like a rule that
passes, so a shape these patterns cannot read is named instead of skipped.

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
# A multiline literal is the one shape the pattern above reads as an EMPTY default,
# which then reports as drift against every real catalog value — a true failure with
# a misleading name. Detected on its own so the message says what actually happened.
MULTILINE_DEFAULT = re.compile(
    r'String\(' + SKIP_BETWEEN + r'localized:' + SKIP_BETWEEN + r'"([^"]+)"' + SKIP_BETWEEN
    + r',' + SKIP_BETWEEN + r'defaultValue:' + SKIP_BETWEEN + r'"""'
)
TEXT_WITH_COMMENT = re.compile(r'Text\(\s*"([a-z][a-zA-Z0-9.]*\.[a-zA-Z0-9.]+)"\s*,\s*comment:')
# Every localized call, whatever its arguments look like. The two patterns above
# read one shape each; a call matching neither — a key held in a variable, an
# argument order these regexes miss — used to vanish, taking its key out of rule 1
# with it: a string missing from the catalog would then ship the English default
# and this checker would call the run clean. Matched by start offset against the
# patterns above, so anything unread gets named at its call site.
LOCALIZED_CALL = re.compile(r"String\(" + SKIP_BETWEEN + r"localized:")

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


def unit_values(localization):
    """Every string a localization carries, as {label: value}.

    A localization is USUALLY one `stringUnit`, but the String Catalog's own
    format — and what Xcode writes the moment a key is given a plural — is a
    `variations` tree keyed by `plural` and/or `device`, with a `stringUnit`
    at each leaf and NONE at the top. Reading only the top level reported such a
    key as having no translation at all, so the gate refused a shape the Apple
    tooling produces: adding a single plural to this app would have failed CI
    with `NO-EN`, and the honest fix would have looked like deleting the plural.

    Every leaf is returned because every leaf ships. A plural whose "other" form
    quietly lost its `%lld` is served to exactly the users who have two of
    something, which is the same bug this file exists to catch, one level down.
    """
    unit = localization.get("stringUnit")
    if unit is not None:
        return {"": unit.get("value")}

    found = {}

    def walk(node, path):
        for axis in ("plural", "device"):
            for category, child in (node.get(axis) or {}).items():
                label = f"{path}{axis}.{category}"
                leaf = child.get("stringUnit")
                if leaf is not None:
                    found[label] = leaf.get("value")
                else:
                    walk(child, f"{label}/")

    walk(localization.get("variations") or {}, "")
    return found


def unit_states(localization):
    """The `state` of every leaf, same traversal as `unit_values`."""
    unit = localization.get("stringUnit")
    if unit is not None:
        return {"": unit.get("state")}

    found = {}

    def walk(node, path):
        for axis in ("plural", "device"):
            for category, child in (node.get(axis) or {}).items():
                label = f"{path}{axis}.{category}"
                leaf = child.get("stringUnit")
                if leaf is not None:
                    found[label] = leaf.get("state")
                else:
                    walk(child, f"{label}/")

    walk(localization.get("variations") or {}, "")
    return found


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
    unparsed = []
    unread = []
    for path in sorted(root.rglob("*.swift")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        text = path.read_text(errors="replace")
        site = path.relative_to(root)
        for key, default in LOCALIZED.findall(text):
            used.setdefault(key, []).append((site, default))
        for key in TEXT_WITH_COMMENT.findall(text):
            # No defaultValue to compare: None means "key exists, value unverifiable".
            used.setdefault(key, []).append((site, None))
        for key in MULTILINE_DEFAULT.findall(text):
            unparsed.append((key, site))
        read = {m.start() for m in LOCALIZED.finditer(text)} | {m.start() for m in MULTILINE_DEFAULT.finditer(text)}
        for call in LOCALIZED_CALL.finditer(text):
            if call.start() not in read:
                excerpt = " ".join(text[call.start():call.start() + 60].split())
                unread.append((site, text.count("\n", 0, call.start()) + 1, excerpt))

    problems = []
    for key, site in sorted(unparsed):
        problems.append(
            f"UNPARSED   {key}  ({site}) uses a multiline string literal for defaultValue; "
            f"this checker only reads a single-line one, so its value cannot be compared"
        )

    for site, line, excerpt in sorted(unread):
        problems.append(
            f"CALL-SHAPE {site}:{line}  {excerpt}…  is a localized call this checker "
            f"cannot read, so NO rule was applied to it — give it a literal key and "
            f"defaultValue, or teach the patterns this shape"
        )

    for key, sites in sorted(used.items()):
        entry = strings.get(key)
        if entry is None:
            problems.append(f"MISSING    {key}  (used in {sites[0][0]})")
            continue

        if entry.get("extractionState") != "manual":
            problems.append(f"EXTRACTION {key}  is {entry.get('extractionState')!r}, expected 'manual'")

        locs = entry.get("localizations", {})
        # A dict per side, because a plural is several strings under one key and
        # every one of them ships (see `unit_values`).
        en_values = {k: v for k, v in unit_values(locs.get("en", {})).items() if v}
        if not en_values:
            problems.append(f"NO-EN      {key}")
        else:
            # The code's defaultValue must match SOME en form — not every one.
            # For a plain key there is exactly one form and this is the old
            # byte-for-byte rule unchanged. For a plural the source text is one
            # string and the catalog holds several, so the default names one
            # category (in practice "other") and the singular legitimately reads
            # differently: requiring all of them to match would forbid the very
            # thing a plural is for.
            for site, default in sites:
                if default is None:
                    continue
                wanted = shape_of_code(unescape(default))
                if any(wanted == shape_of_catalog(value) for value in en_values.values()):
                    continue
                shown = ", ".join(
                    f"{label or 'value'}={value!r}" for label, value in sorted(en_values.items())
                )
                problems.append(
                    f"DRIFT      {key}\n"
                    f"             code ({site}): {unescape(default)!r}\n"
                    f"             catalog en:      {shown}"
                )
                break

        pt_values = {k: v for k, v in unit_values(locs.get("pt-BR", {})).items() if v}
        if not pt_values:
            problems.append(f"NO-PT-BR   {key}")
            continue
        for label, state in sorted(unit_states(locs.get("pt-BR", {})).items()):
            if state not in {"translated", None}:
                where = f" [{label}]" if label else ""
                problems.append(f"PT-STATE   {key}{where}  state={state!r}")
        # Guarded on `en`: without this the parity check raises on exactly the
        # NO-EN entry it was asked to report, and the run dies instead of listing.
        #
        # Compared as SETS across the forms rather than category by category:
        # en and pt-BR need not have the same plural categories (a language may
        # have more, or fewer), so pairing them by name would invent a mismatch.
        # What must hold is that no form on either side carries holes the other
        # side never produces.
        en_specs = {tuple(specifiers_of(v)) for v in en_values.values()}
        pt_specs = {tuple(specifiers_of(v)) for v in pt_values.values()}
        if en_values and en_specs != pt_specs:
            problems.append(
                f"SPECIFIERS {key}  en {sorted(en_specs)} vs pt-BR {sorted(pt_specs)}"
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
