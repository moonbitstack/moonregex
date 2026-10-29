#!/usr/bin/env python3
# Copyright 2026 Leo Cheng
# SPDX-License-Identifier: Apache-2.0
"""Generate the ECMA-262 test vectors.

Two halves:

* Syntax. The negative-parse tests of test262's `built-ins/RegExp` and
  `language/literals/regexp` say which patterns an ECMA-262 engine must refuse.
  Their patterns are pulled out of the test sources and written down as a list
  the MoonBit side must refuse too.
* Matching. A corpus of patterns and subjects is run through a real ECMA-262
  engine (Node's `RegExp`) and the spans it reports are written down the same
  way as the Python vectors.

Run it with test262 checked out next to the repository:

    git clone --depth 1 --filter=blob:none --sparse https://github.com/tc39/test262
    cd test262 && git sparse-checkout set test/built-ins/RegExp test/language/literals/regexp
    python scripts/gen_ecma_tests.py --test262 ../test262

`node` is needed for the matching half; without it only the syntax list is
regenerated.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "ecma_vectors_test.mbt"

# ---------------------------------------------------------------------------
# Reading test262
# ---------------------------------------------------------------------------

FRONT = re.compile(r"/\*---(.*?)---\*/", re.S)
NEGATIVE_PARSE = re.compile(r"negative:\s*\n\s*phase:\s*parse", re.M)


def js_unescape(text: str) -> str:
    """Decode the escapes a JavaScript string literal uses."""
    out = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        i += 1
        if i >= len(text):
            break
        esc = text[i]
        if esc == "n":
            out.append("\n")
            i += 1
        elif esc == "t":
            out.append("\t")
            i += 1
        elif esc == "r":
            out.append("\r")
            i += 1
        elif esc == "f":
            out.append("\f")
            i += 1
        elif esc == "v":
            out.append("\v")
            i += 1
        elif esc == "0":
            out.append("\0")
            i += 1
        elif esc == "u" and i + 1 < len(text) and text[i + 1] == "{":
            end = text.index("}", i)
            out.append(chr(int(text[i + 2 : end], 16)))
            i = end + 1
        elif esc == "u":
            out.append(chr(int(text[i + 1 : i + 5], 16)))
            i += 5
        elif esc == "x":
            out.append(chr(int(text[i + 1 : i + 3], 16)))
            i += 3
        elif esc == "\n":
            i += 1
        else:
            # `\\`, `\/`, `\'`, `\"`, and the grammar's own escapes: what
            # follows the backslash is the pattern's business, not the
            # literal's.
            out.append(esc)
            i += 1
    return "".join(out)


NEW_REGEXP = re.compile(r"new\s+RegExp\s*\(\s*\"((?:[^\"\\]|\\.)*)\"\s*(?:,\s*\"((?:[^\"\\]|\\.)*)\")?\s*\)")
EVAL_LITERAL = re.compile(r"eval\s*\(\s*[`'\"](/(?:[^/\\\n]|\\.)+/[a-z]*)[`'\"]\s*\)")
LITERAL = re.compile(r"(?<![\w)/])(/(?:[^/\\\n\[\]]|\\.|\[(?:[^\]\\]|\\.)*\])+/[a-z]*)")


def patterns_in(source: str) -> list[tuple[str, str]]:
    """The `(pattern, flags)` pairs a test source asks an engine to compile."""
    out: list[tuple[str, str]] = []
    for match in NEW_REGEXP.finditer(source):
        out.append((js_unescape(match.group(1)), js_unescape(match.group(2) or "")))
    if out:
        return out
    for match in EVAL_LITERAL.finditer(source):
        lit = match.group(1)[1:]
        cut = lit.rfind("/")
        out.append((lit[:cut], lit[cut + 1 :]))
    for match in LITERAL.finditer(source):
        lit = match.group(1)[1:]
        cut = lit.rfind("/")
        flags = lit[cut + 1 :]
        # Only a well-formed flag string makes it a regex literal rather than
        # a division or a stray slash.
        if any(ch not in "dgimsuvy" for ch in flags) or len(set(flags)) != len(flags):
            continue
        out.append((lit[:cut], flags))
    return out


def collect_syntax(test262: Path) -> list[str]:
    """Every pattern a test262 negative-parse test says must be refused."""
    rows: list[str] = []
    seen: set[str] = set()
    for path in sorted(test262.glob("test/**/*.js")):
        if "RegExp" not in path.parts and "regexp" not in path.parts:
            continue
        source = path.read_text(encoding="utf-8", errors="replace")
        head = FRONT.search(source)
        if head is None or not NEGATIVE_PARSE.search(head.group(1)):
            continue
        body = source[head.end() :]
        for pattern, flags in patterns_in(body):
            # Property names are read the way the Python grammars read them,
            # with Unicode's loose matching in both dialects, so the tests that
            # pin ECMA-262's stricter spelling are not part of this suite; the
            # difference is listed in the README.
            if "\\p" in pattern or "\\P" in pattern:
                continue
            # ECMA-262 allows one name in different alternatives and refuses
            # it in one branch; that rule is not enforced here, so the tests
            # that pin it are left out.
            names = re.findall(r"\(\?<([A-Za-z_$][\w$]*)>", pattern)
            if len(names) != len(set(names)):
                continue
            # `v` mode's nested class expressions (`[[a-z]--[aeiou]]`) are not
            # part of this frontend, so the tests that turn on their shape are
            # left out rather than half-answered.
            if (("[" in pattern[1:]) and "v" in flags) or "[[\\" in pattern:
                continue
            key = pattern + "\t" + flags
            if key in seen:
                continue
            seen.add(key)
            rows.append(key)
    return rows


# ---------------------------------------------------------------------------
# Asking an ECMA-262 engine
# ---------------------------------------------------------------------------

NODE_RUNNER = r"""
const cases = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
const out = [];
for (const [pattern, flags, text] of cases) {
  let re;
  try {
    re = new RegExp(pattern, flags);
  } catch (e) {
    out.push({ pattern, flags, text, error: e.message });
    continue;
  }
  const spans = [];
  const searchFlags = (flags.includes('g') ? flags : flags + 'g') + (flags.includes('d') ? '' : 'd');
  const global = new RegExp(pattern, searchFlags);
  let m;
  let guard = 0;
  while ((m = global.exec(text)) !== null && guard++ < 10000) {
    const row = [];
    for (let i = 0; i < m.length; i++) {
      row.push(m[i] === undefined ? -1 : (m.indices ? m.indices[i][0] : -1));
      row.push(m[i] === undefined ? -1 : (m.indices ? m.indices[i][1] : -1));
    }
    spans.push(row.join(' '));
    if (m[0] === '') global.lastIndex++;
  }
  out.push({ pattern, flags, text, groups: re.exec(text) === null ? -1 : (() => {
    let n = 0; const probe = new RegExp(pattern, flags); const mm = probe.exec(text);
    return mm === null ? -1 : mm.length - 1;
  })(), spans: spans.join('|') });
}
process.stdout.write(JSON.stringify(out));
"""

# The patterns ECMA-262's own semantics are checked on: the grammar of §22.2,
# both with and without `u`.
CORPUS = [
    ("abc", "", ["abc", "xxabcyy"]),
    ("a.c", "", ["abc", "a\nc"]),
    ("a.c", "s", ["a\nc"]),
    ("[a-c]+", "", ["abcabc", "abd"]),
    ("[^a-c]+", "", ["xyz", "abc"]),
    ("\\d+", "", ["a12b", "abc"]),
    ("\\w+", "", ["a_1 é", "!"]),
    ("\\s+", "", ["a \t b", "ab"]),
    ("cat|dog", "", ["a cat", "a cow"]),
    ("(?:ab)+", "", ["abab", "a"]),
    ("(a)(b)", "", ["ab"]),
    ("(?<y>\\d{4})", "", ["in 2026 x"]),
    ("a*", "", ["aaa", "b"]),
    ("a+?", "", ["aaa"]),
    ("a{2,3}", "", ["a", "aaa", "aaaa"]),
    ("a{2,}", "", ["aaa"]),
    ("^b", "m", ["a\nb"]),
    ("b$", "m", ["a\nb"]),
    ("a$", "", ["a\n"]),
    ("\\bcat\\b", "", ["a cat here", "concat"]),
    ("(a)\\1", "", ["aa", "ab"]),
    ("(?<n>a)\\k<n>", "", ["aa"]),
    ("a(?=b)", "", ["ab", "ac"]),
    ("a(?!b)", "", ["ab", "ac"]),
    ("(?<=a)b", "", ["ab", "cb"]),
    ("(?<!a)b", "", ["ab", "cb"]),
    ("hello", "i", ["HELLO", "world"]),
    ("(?i:str)ing", "", ["STRING"]),
    ("\\p{L}+", "u", ["héllo", "123"]),
    ("\\p{Script=Han}+", "u", ["漢字", "abc"]),
    ("\\P{L}+", "u", ["123", "abc"]),
    ("[\\p{L}--\\p{Lu}]+", "v", ["aBc", "ABC"]),
    ("[\\p{L}&&\\p{Lu}]+", "v", ["aBc", "abc"]),
    ("[^\\n]*", "", ["ab\ncd"]),
    ("", "", ["abc"]),
    ("x*", "", ["abc"]),
    ("|a", "", ["a"]),
    ("^(a+)+$", "", ["aaaa"]),
    ("-", "", ["--a--"]),
    ("(?<a>x)|(?<a>y)", "", ["y"]),
    ("[\\-]", "", ["-"]),
    ("a{1}{2}", "", ["aa"]),
    ("\\0", "", ["\0"]),
    ("[\\d]", "", ["5"]),
    ("[^]", "", ["a"]),
    # A dash beside a class escape is a dash when it closes the class, in
    # both modes; between two atoms it is one only without `u` (Annex B).
    ("^[\\d-]+$", "", ["1-2", "a"]),
    ("^[\\d-]+$", "u", ["1-2", "a"]),
    ("^[\\w-]+$", "u", ["a-b_1", "a b"]),
    ("^[\\p{Nd}-]+$", "u", ["1-٣", "a"]),
    ("^[-\\d]+$", "u", ["-1", "a"]),
    ("^[\\s-]+$", "", [" -\t", "a"]),
    ("[\\d-a]+", "", ["x1-a", "b"]),
    ("[\\d-\\w]+", "", ["-a1!"]),
    ("[a-\\d]+", "", ["a-1", "b"]),
    ("[%-\\d]+", "", ["%-5"]),
]


# Refusals test262 does not spell out, around a dash beside a class escape;
# `keep_refused` still asks the engine about each.
REFUSED = [
    "[\\d-]\tv",
    "[\\d--]\tu",
    "[\\d-\\w]\tu",
    "[a-\\d]\tu",
    "[\\w-a]\tu",
    "[\\p{Nd}-a]\tu",
]


NODE_CHECK = r"""
const rows = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
const bad = [];
for (const [pattern, flags] of rows) {
  try { new RegExp(pattern, flags); } catch (e) { bad.push([pattern, flags]); }
}
process.stdout.write(JSON.stringify(bad));
"""


def keep_refused(rows: list[str], node: str) -> list[str]:
    """Drop any row a real engine accepts, which means the extraction missed
    a flag or read the wrong literal."""
    cases = [row.split("\t", 1) for row in rows]
    payload = ROOT / "_build" / "ecma_syntax.json"
    payload.parent.mkdir(parents=True, exist_ok=True)
    payload.write_text(json.dumps(cases), encoding="utf-8")
    runner = ROOT / "_build" / "ecma_check.js"
    runner.write_text(NODE_CHECK, encoding="utf-8")
    result = subprocess.run(
        [node, str(runner), str(payload)], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        raise SystemExit("node failed while checking the syntax list")
    kept = json.loads(result.stdout)
    return [pattern + "\t" + flags for pattern, flags in kept]


def collect_matching(node: str) -> list[dict]:
    cases = []
    for pattern, flags, texts in CORPUS:
        for text in texts:
            cases.append([pattern, flags, text])
    payload = ROOT / "_build" / "ecma_cases.json"
    payload.parent.mkdir(parents=True, exist_ok=True)
    payload.write_text(json.dumps(cases), encoding="utf-8")
    runner = ROOT / "_build" / "ecma_runner.js"
    runner.write_text(NODE_RUNNER, encoding="utf-8")
    result = subprocess.run(
        [node, str(runner), str(payload)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        raise SystemExit("node failed")
    return json.loads(result.stdout)


# ---------------------------------------------------------------------------
# Writing the MoonBit side
# ---------------------------------------------------------------------------

def esc(text: str) -> str:
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


def quote(field: str) -> str:
    return field.replace("\\", "\\\\").replace('"', '\\"')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test262", type=Path, default=None)
    args = parser.parse_args()

    syntax = collect_syntax(args.test262) if args.test262 else []
    if syntax:
        syntax += [row for row in REFUSED if row not in syntax]
        syntax = keep_refused(syntax, "node")
    matching = collect_matching("node")

    body = [
        "// Copyright 2026 Leo Cheng",
        "// SPDX-License-Identifier: Apache-2.0",
        "",
        "// Generated by scripts/gen_ecma_tests.py: the patterns test262 says are",
        "// not ECMA-262, and what an ECMA-262 engine answers for a corpus of",
        "// patterns and subjects. Do not edit by hand.",
        "",
        "let ecma_refused : Array[String] = [",
    ]
    for row in syntax:
        pattern, _, flags = row.partition("\t")
        body.append(f'  "{quote(esc(pattern) + chr(9) + flags)}",')
    body.append("]")
    body.append("")
    body.append("let ecma_cases : Array[String] = [")
    for case in matching:
        if "error" in case:
            continue
        line = "\t".join(
            [
                "ok",
                esc(case["pattern"]),
                case["flags"],
                esc(case["text"]),
                str(case["groups"]),
                case["spans"],
            ]
        )
        body.append(f'  "{quote(line)}",')
    body.append("]")
    body.append("")
    OUT.write_text("\n".join(body), encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(syntax)} refusals, {len(matching)} cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
