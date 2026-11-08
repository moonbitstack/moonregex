#!/usr/bin/env python3
# Copyright 2026 Leo Cheng
# SPDX-License-Identifier: Apache-2.0
"""Fill the code the site shows from the tests that run it.

Every block on the site is a region of `src/examples/docs/<page>.mbt`, between
`// docs:begin <id>` and `// docs:end`. The lines outside those markers are the
setup and the asserts the page leaves out, so the block on the page is a fragment
that still runs, in `moon test`, without anyone pasting anything.

This writes the marked lines into `docs/<page>.html`, highlighting them the way
the pages already are (`c-kw`, `c-str`, `c-num`, `c-com`):

  * a code block marked `<code data-snippet="<page>/<id>">` takes the snippet as
    HTML, one line per line;
  * lines between `// docs:snippet <page>/<id>` and `// docs:end` take it as a
    JavaScript string, for the panels that keep their code in a script.

    python scripts/gen_docs_snippets.py           # rewrite the pages
    python scripts/gen_docs_snippets.py --check   # exit 1 if a page is stale
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SNIPPETS = ROOT / "src" / "examples" / "docs"
DOCS = ROOT / "docs"

BEGIN = re.compile(r"^\s*//\s*docs:begin\s+(\S+)\s*$")
END = re.compile(r"^\s*//\s*docs:end\s*$")

# Words the pages set in the keyword face. `Some` and `None` are constructors and
# stay in the code face, as they were before this script existed.
KEYWORDS = {
    "as",
    "async",
    "catch",
    "else",
    "fn",
    "for",
    "guard",
    "if",
    "in",
    "is",
    "let",
    "match",
    "mut",
    "pub",
    "raise",
    "return",
    "true",
    "false",
    "try",
    "while",
    "test",
    "type",
    "enum",
    "struct",
    "impl",
    "derive",
}

WORD = re.compile(r"[A-Za-z_@][A-Za-z0-9_]*")
NUMBER = re.compile(r"\d+")


def regions(path: Path) -> dict[str, list[str]]:
    """`id -> lines` between the markers, with the common indent taken off."""
    out: dict[str, list[str]] = {}
    current: str | None = None
    buffer: list[str] = []
    for line in path.read_text(encoding="utf-8").split("\n"):
        begin = BEGIN.match(line)
        if begin:
            current, buffer = begin.group(1), []
            continue
        if END.match(line) and current is not None:
            body = [ln.rstrip() for ln in buffer]
            while body and not body[0].strip():
                body.pop(0)
            while body and not body[-1].strip():
                body.pop()
            indent = min((len(ln) - len(ln.lstrip()) for ln in body if ln.strip()), default=0)
            out[current] = [ln[indent:] if ln.strip() else "" for ln in body]
            current, buffer = None, []
            continue
        if current is not None:
            buffer.append(line)
    return out


def segments(line: str) -> list[tuple[str, str]]:
    """Split one line into `(class, text)` runs, class `""` for plain text."""
    out: list[tuple[str, str]] = []
    plain: list[str] = []
    i, n = 0, len(line)

    def flush() -> None:
        if plain:
            out.append(("", "".join(plain)))
            plain.clear()

    while i < n:
        ch = line[i]
        if line.startswith("//", i):
            flush()
            out.append(("c-com", line[i:]))
            return out
        if ch == '"':
            flush()
            j = i + 1
            while j < n:
                if line[j] == "\\":
                    j += 2
                    continue
                if line[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(("c-str", line[i:j]))
            i = j
            continue
        word = WORD.match(line, i)
        if word:
            text = word.group(0)
            if text in KEYWORDS:
                flush()
                out.append(("c-kw", text))
            else:
                plain.append(text)
            i = word.end()
            continue
        number = NUMBER.match(line, i)
        if number and (i == 0 or not (line[i - 1].isalnum() or line[i - 1] == "_")):
            flush()
            out.append(("c-num", number.group(0)))
            i = number.end()
            continue
        plain.append(ch)
        i += 1
    flush()
    return out


def as_html(lines: list[str]) -> str:
    out = []
    for line in lines:
        parts = []
        for cls, text in segments(line):
            escaped = html.escape(text, quote=False)
            parts.append(f'<span class="{cls}">{escaped}</span>' if cls else escaped)
        out.append("".join(parts))
    return "\n".join(out)


def as_js(lines: list[str]) -> str:
    quoted = []
    for line in lines:
        body = as_html([line])
        body = body.replace("\\", "\\\\").replace("'", "\\'")
        quoted.append(f"'{body}\\n'")
    if not quoted:
        return ""
    # The last line carries the object literal's comma; a page panel is always a
    # member of a map, so it needs one.
    return " +\n".join(quoted) + ","


BLOCK = re.compile(r'(<code data-snippet="([^"]+)">)(.*?)(</code>)', re.S)
MARK = re.compile(r"(\n[ \t]*//[ \t]*docs:snippet[ \t]+(\S+)[ \t]*\n)(.*?)([ \t]*//[ \t]*docs:end[ \t]*\n)", re.S)


def fill(page: Path, snippets: dict[str, list[str]]) -> tuple[str, list[str]]:
    """The page with its snippets written in, and the ids it asked for."""
    text = page.read_text(encoding="utf-8")
    wanted: list[str] = []

    def block(m: re.Match) -> str:
        wanted.append(m.group(2))
        body = snippets.get(m.group(2))
        if body is None:
            raise SystemExit(f"{page.name}: no snippet for {m.group(2)}")
        return f"{m.group(1)}{as_html(body)}{m.group(4)}"

    text = BLOCK.sub(block, text)

    def marked(m: re.Match) -> str:
        wanted.append(m.group(2))
        body = snippets.get(m.group(2))
        if body is None:
            raise SystemExit(f"{page.name}: no snippet for {m.group(2)}")
        return f"{m.group(1)}{as_js(body)}\n{m.group(4)}"

    text = MARK.sub(marked, text)
    return text, wanted


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="report stale pages, write nothing")
    args = ap.parse_args()

    pages = sorted(DOCS.glob("*.html"))
    stale, total = [], 0
    for source in sorted(SNIPPETS.glob("*.mbt")):
        snippets = {f"{source.stem}/{key}": body for key, body in regions(source).items()}
        page = DOCS / f"{source.stem}.html"
        if not page.exists():
            raise SystemExit(f"{source.name}: no page {page.name}")
        filled, wanted = fill(page, snippets)
        total += len(wanted)
        if filled != page.read_text(encoding="utf-8"):
            stale.append(page.name)
            if not args.check:
                page.write_text(filled, encoding="utf-8", newline="\n")
    for page in stale:
        print(f"{page}: out of date")
    if args.check:
        return 1 if stale else 0
    print(f"{total} blocks on {len(pages)} pages written from {len(list(SNIPPETS.glob('*.mbt')))} snippet files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
