#!/usr/bin/env python3
# Copyright 2026 Leo Cheng
# SPDX-License-Identifier: Apache-2.0
"""Generate the differential test vectors moonregex is checked against.

The corpus below is run through CPython's `re`, and through the `regex`
package (mrab-regex), and what both answer is written out as MoonBit data that
`moon test` replays.  Nothing here runs at test time: the data is generated
once, committed, and read back by the tests, so CI needs neither Python nor a
network.

Run it with:

    python scripts/gen_vectors.py

`python -m pip install regex` is only needed for the `regex` half; the `re`
half runs on the standard library alone.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import regex as mrab
except ImportError:  # pragma: no cover - the re half still generates
    mrab = None

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "vectors_test.mbt"

# A replacement with no metacharacters, so both engines expand it identically.
REPL = "<M>"

# Flags, by the letter the generated MoonBit uses. Each engine spells the
# constants its own way, so the value is taken from the engine in hand.
FLAG_NAMES = {"i": "I", "m": "M", "s": "S", "x": "X", "a": "A"}

# ---------------------------------------------------------------------------
# The corpus
# ---------------------------------------------------------------------------
#
# (pattern, flags, texts).  Every feature the library claims has a run here;
# the cases marked "test_re" are the shapes CPython's own test_re.py uses, and
# the rest cover the same ground from the other side — the corners a port
# usually gets wrong (empty matches, anchors at the edges, folding, nesting).

# Entries are (pattern, flags, texts) or (pattern, flags, texts, engine), the
# last form for a construct only one of the two engines has.
CORPUS: list[tuple] = [
    # -- literals, dots, escapes -------------------------------------------
    ("abc", "", ["abc", "xxabcyy", "ab", "ABC"]),
    ("a.c", "", ["abc", "a c", "a\nc", "ac"]),
    ("a\\.c", "", ["a.c", "abc"]),
    ("a\\tb", "", ["a\tb", "a b"]),
    ("\\x41\\x42", "", ["AB", "ab"]),
    ("\\u00e9", "", ["é", "e"]),
    ("\\N{SNOWMAN}", "", ["☃", "*"]),
    ("[a-c]+", "", ["abcabc", "abd", "xyz"]),
    ("[^a-c]+", "", ["xyz", "abc", "abxyzcd"]),
    ("[]a]+", "", ["]]a", "b"]),
    ("[a\\-z]+", "", ["a-z", "b"]),
    ("[\\d]+", "", ["12", "ab"]),
    ("[[:alpha:]]+", "", ["abc", "123"], "regex"),
    # -- alternation and grouping ------------------------------------------
    ("cat|dog", "", ["a cat", "a dog", "a cow"]),
    ("(cat|dog)s?", "", ["cats", "dog", "cow"]),
    ("(?:ab)+", "", ["abab", "ab", "a"]),
    ("(a)(b)(c)", "", ["abc", "xabc"]),
    ("((a)(b))", "", ["ab"]),
    ("a|", "", ["b", "a"]),
    ("|a", "", ["b", "a"]),
    ("(|a)b", "", ["b", "ab"]),
    # -- quantifiers --------------------------------------------------------
    ("a*", "", ["aaa", "b", ""]),
    ("a+", "", ["aaa", "b"]),
    ("a?", "", ["a", "b"]),
    ("a{2}", "", ["aa", "a", "aaa"]),
    ("a{2,}", "", ["aa", "aaaa", "a"]),
    ("a{2,3}", "", ["a", "aa", "aaa", "aaaa"]),
    ("a*?", "", ["aaa"]),
    ("a+?", "", ["aaa"]),
    ("a??", "", ["a"]),
    ("a{2,3}?", "", ["aaaa"]),
    (".*", "", ["abc", "a\nb"]),
    (".*", "s", ["a\nb"]),
    ("<.*>", "", ["<a><b>"]),
    ("<.*?>", "", ["<a><b>"]),
    ("(ab)*", "", ["ababab", "x"]),
    ("(a*)*", "", ["aaa"]),
    ("(a|b)*c", "", ["ababc", "c"]),
    # -- anchors ------------------------------------------------------------
    ("^abc", "", ["abc", "xabc"]),
    ("abc$", "", ["abc", "abcx", "abc\n"]),
    ("^abc$", "", ["abc", "abc\n"]),
    ("^b", "m", ["a\nb\nc"]),
    ("b$", "m", ["a\nb\nc"]),
    ("\\Aabc", "", ["abc", "xabc"]),
    ("abc\\Z", "", ["abc", "abc\n"]),
    ("\\bcat\\b", "", ["a cat here", "concat", "cat"]),
    ("\\Bcat", "", ["concat", "cat"]),
    ("\\b", "", ["ab cd"]),
    ("a\\Kb", "", ["ab"], "regex"),
    # -- groups and backreferences -----------------------------------------
    ("(a)\\1", "", ["aa", "ab"]),
    ("(a)(b)\\2\\1", "", ["abba", "abab"]),
    ("(?P<x>a)(?P=x)", "", ["aa", "ab"]),
    ("(a+)\\1", "", ["aaaa", "aaa"]),
    ("(a)?b\\1", "", ["b", "aba"]),
    ("(?<year>\\d{4})-(?<month>\\d{2})", "", ["on 2026-10-28 ok"], "regex"),
    # -- lookaround ---------------------------------------------------------
    ("a(?=b)", "", ["ab", "ac"]),
    ("a(?!b)", "", ["ab", "ac"]),
    ("(?<=a)b", "", ["ab", "cb"]),
    ("(?<!a)b", "", ["ab", "cb"]),
    ("(?=(a+))a", "", ["aaa"]),
    ("(?<=a+)b", "", ["aaab"]),
    ("(?<=^\\w+)x", "", ["abcx"]),
    # -- atomic and possessive ---------------------------------------------
    ("(?>a+)ab", "", ["aaab", "ab"]),
    ("a++b", "", ["aaab"]),
    ("\\d++5", "", ["12345"]),
    # -- conditionals and recursion ----------------------------------------
    ("(a)?(?(1)b|c)", "", ["ab", "c", "b"]),
    ("\\((?<p>[^()]*)\\)", "", ["(abc)", "()"], "regex"),
    ("(?<p>\\((?:[^()]|(?&p))*\\))", "", ["(a(b)c)", "x"], "regex"),
    # -- flags --------------------------------------------------------------
    ("hello", "i", ["HELLO", "world"]),
    ("[a-z]+", "i", ["ABC", "abc"]),
    ("(?i)str", "", ["STR", "str"]),
    ("(?i:str)ing", "", ["STRING", "string"]),
    ("k", "i", ["K", "k", "K"]),
    ("s", "i", ["S", "s", "ſ"]),
    ("σ", "i", ["Σ", "ς", "σ"]),
    ("a b", "x", ["ab", "a b"]),
    ("a  # comment\n b", "x", ["ab"]),
    ("\\w+", "", ["héllo", "_x1"]),
    ("\\w+", "a", ["héllo", "_x1"]),
    ("\\d+", "", ["٣٤", "12"]),
    ("\\d+", "a", ["٣٤", "12"]),
    ("\\s+", "", [" \t\u00a0", "x"]),
    ("\\W", "", ["é", "e"]),
    # -- Unicode properties -------------------------------------------------
    ("\\p{L}+", "", ["héllo", "123"], "regex"),
    ("\\p{Lu}+", "", ["ABC", "abc"], "regex"),
    ("\\p{Greek}+", "", ["αβγ", "abc"], "regex"),
    ("\\P{L}+", "", ["123!", "abc"], "regex"),
    ("\\p{Nd}+", "", ["12", "ab"], "regex"),
    ("\\p{Alphabetic}+", "", ["abc", "12"], "regex"),
    ("\\p{Script=Han}+", "", ["漢字", "abc"], "regex"),
    ("\\p{Block=Basic Latin}+", "", ["abc", "é"], "regex"),
    ("(?V1)[\\p{L}--\\p{Lu}]+", "", ["aBc", "ABC"], "regex"),
    ("(?V1)[\\p{L}&&\\p{Lu}]+", "", ["aBc", "abc"], "regex"),
    # -- escapes and classes the superset adds ------------------------------
    ("\\R", "", ["\n", "\u2028", "x"], "regex"),
    ("\\h+", "", [" \t", "x"], "regex"),
    ("\\v+", "", ["\n", "x"], "regex"),
    ("\\X", "", ["e\u0301", "ab"], "regex"),
    # -- empty matches, splits and substitutions ---------------------------
    ("", "", ["abc"]),
    ("x*", "", ["abc"]),
    ("\\b", "", ["ab cd"]),
    (",", "", ["a,b,,c"]),
    ("(,)", "", ["a,b,c"]),
    ("\\s+", "", ["  a  b  "]),
    ("(\\w+)@(\\w+)", "", ["u@h x@y"]),
    ("-", "", ["--a--"]),
    # -- the awkward ones ---------------------------------------------------
    ("(?P<n>\\d+)-(?P=n)", "", ["12-12 34-35"]),
    ("(a)(?(1)b)", "", ["ab"]),
    ("\\bfoo\\b.*\\bbar\\b", "", ["foo x bar y bar"]),
    ("^(a+)+$", "", ["aaaa", "aaaa!"]),
    ("[^\\n]*", "", ["ab\ncd"]),
    ("(.*)", "", ["ab"]),
    ("\\A", "", ["ab"]),
    ("\\Z", "", ["ab"]),
    ("$", "", ["ab\n"]),
    # -- patterns the grammar refuses ---------------------------------------
    ("(", "", []),
    ("a)", "", []),
    ("[a", "", []),
    ("a**", "", []),
    ("*a", "", []),
    ("a{2,1}", "", []),
    ("(?P<n>a)(?P<n>b)", "", [], "re"),
    ("(?P<1>a)", "", []),
    ("\\", "", []),
    ("a\\", "", []),
    ("(?P=nope)", "", []),
    ("\\1", "", []),
    ("(?<=a*)b", "", []),
    ("[z-a]", "", []),
]


def flag_value(engine, letters: str) -> int:
    value = 0
    for letter in letters:
        value |= getattr(engine, FLAG_NAMES[letter])
    return value


def esc(text: str) -> str:
    """Escape a value for one TSV field."""
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 0x20:
            out.append("\\u{%X}" % ord(ch))
        else:
            out.append(ch)
    return "".join(out)


def list_field(items) -> str:
    """A list of strings, each followed by the separator.

    The trailing separator is what tells `[""]` from `[]`, which a plain join
    cannot; `None` is marked so it cannot be confused with the empty string.
    """
    return "".join(("\\u{1}" if item is None else esc(item)) + "|" for item in items)


def describe(engine, pattern: str, flags: int, letters: str, text: str) -> str | None:
    """One case, as the tab-separated line the MoonBit test replays."""
    try:
        compiled = engine.compile(pattern, flags)
    except Exception as error:  # noqa: BLE001 - both engines raise their own
        pos = getattr(error, "pos", None)
        if pos is None:
            return None
        return "\t".join(
            ["err", esc(pattern), letters, str(pos)]
        )

    try:
        spans = []
        groups = compiled.groups
        for match in compiled.finditer(text):
            row = []
            for i in range(groups + 1):
                span = match.span(i)
                row.append(str(span[0]))
                row.append(str(span[1]))
            spans.append(" ".join(row))
        fields = [
            "ok",
            esc(pattern),
            letters,
            esc(text),
            str(groups),
            "|".join(spans),
        ]
        # `findall` answers a tuple once there are two or more groups, which a
        # statically typed list cannot say; those cases are checked through
        # `finditer` instead, and the test asserts the refusal.
        if groups <= 1:
            found = compiled.findall(text)
            if any(not isinstance(v, str) for v in found):
                # The `regex` package answers a tuple here to expose the
                # captures of a repeated group; a list of strings cannot say
                # that, so the case is left to `finditer`.
                return None
            fields.append(list_field(found))
        else:
            fields.append("!")
        fields.append(list_field(list(compiled.split(text))))
        fields.append(esc(compiled.sub(REPL, text)))
        return "\t".join(fields)
    except Exception:  # noqa: BLE001 - a construction one engine refuses
        return None


def generate(engine, name: str) -> list[str]:
    lines: list[str] = []
    for entry in CORPUS:
        pattern, flags, texts = entry[0], entry[1], entry[2]
        only = entry[3] if len(entry) > 3 else None
        if only is not None and only != name:
            continue
        value = flag_value(engine, flags)
        cases = texts if texts else [""]
        for text in cases:
            line = describe(engine, pattern, value, flags, text)
            if line is None:
                print(f"  skipped: {name} {pattern!r} {flags!r}", file=sys.stderr)
                continue
            lines.append(line)
    return lines


def quote(field: str) -> str:
    """A field as a MoonBit string literal, with its own escapes intact."""
    return field.replace("\\", "\\\\").replace('"', '\\"')


def main() -> int:
    std = generate(re, "re")
    extra = generate(mrab, "regex") if mrab is not None else []
    body = []
    body.append("// Copyright 2026 Leo Cheng")
    body.append("// SPDX-License-Identifier: Apache-2.0")
    body.append("")
    body.append("// Generated by scripts/gen_vectors.py from CPython's `re` and the")
    body.append("// `regex` package. Do not edit by hand: run the script again.")
    body.append("")
    body.append('let python_vectors : Array[String] = [')
    for line in std:
        body.append(f'  "{quote(line)}",')
    body.append("]")
    body.append("")
    body.append('let regexp_vectors : Array[String] = [')
    for line in extra:
        body.append(f'  "{quote(line)}",')
    body.append("]")
    body.append("")
    OUT.write_text("\n".join(body), encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(std)} python, {len(extra)} regex cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
