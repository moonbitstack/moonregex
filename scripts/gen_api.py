#!/usr/bin/env python3
# Copyright 2026 Leo Cheng
# SPDX-License-Identifier: Apache-2.0
"""Generate `docs/api.html` from the packages' interfaces and doc comments.

The list of public items comes from each package's `pkg.generated.mbti`, which
`moon info` writes and the compiler keeps honest; the words next to them come
from the `///` comments in the sources. Nothing here is written by hand, so
the page cannot drift from the code: the workflow regenerates it and fails if
the result differs from what is committed.

    python scripts/gen_api.py
"""

from __future__ import annotations

import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "docs" / "api.html"

PACKAGE_TITLES = {
    "moonregex": "The library",
    "moonregex/parse": "parse",
    "moonregex/exec": "exec",
    "moonregex/prop": "prop",
    "moonregex/glob": "glob",
}

PACKAGE_BLURB = {
    "moonregex": "Patterns, matches and the functions that drive them — the surface a caller meets.",
    "moonregex/parse": "One syntax tree for three grammars: Python, ECMA-262 and lexmatch.",
    "moonregex/exec": "The compiled program and the backtracking engine that runs it.",
    "moonregex/prop": "Code-point sets, the Unicode property lookups behind `\\\\p{…}`, and case folding.",
    "moonregex/glob": "Shell globbing — `fnmatch`, `Glob` and `GlobSet`.",
}

# Methods every type gets from a derive; they are the language's, not this
# library's, and a reference full of them is harder to read.
GENERATED = {"equal", "not_equal", "output", "to_string", "to_repr", "hash", "compare"}

PACKAGE_ORDER = ["moonregex", "moonregex/parse", "moonregex/exec", "moonregex/prop", "moonregex/glob"]


# ---------------------------------------------------------------------------
# Reading the sources
# ---------------------------------------------------------------------------

DOC_LINE = re.compile(r"^///\s?(.*)$")
DOC_START = re.compile(r"^///\|")
DECL = re.compile(
    r"^(?:pub(?:\([a-z]+\))?\s+)(?:fn|struct|enum|type|let|extend|const|impl|trait|typealias)\b"
)


def doc_map(files: list[Path]) -> dict[str, str]:
    """`name -> doc text`, from the `///` blocks in front of each declaration."""
    out: dict[str, str] = {}
    for path in files:
        lines = path.read_text(encoding="utf-8").splitlines()
        buffer: list[str] = []
        collecting = False
        for line in lines:
            if DOC_START.match(line):
                buffer = []
                collecting = True
                continue
            match = DOC_LINE.match(line)
            if collecting and match:
                buffer.append(match.group(1))
                continue
            if collecting and line.strip() == "":
                continue
            if collecting:
                collecting = False
                text = "\n".join(buffer).strip()
                name = decl_name(line)
                if name and text and name not in out:
                    out[name] = text
    return out


def decl_name(line: str) -> str | None:
    if not DECL.match(line):
        return None
    # pub fn Type::name(  |  pub struct Name {  |  pub let name :
    match = re.search(r"\bfn\s+(?:[A-Za-z0-9_]+\s*::\s*)?([A-Za-z_][A-Za-z0-9_]*)", line)
    if match:
        return method_key(line, match.group(1))
    match = re.search(r"\b(?:struct|enum|trait)\s+([A-Za-z_][A-Za-z0-9_]*)", line)
    if match:
        return match.group(1)
    match = re.search(r"\blet\s+([A-Za-z_][A-Za-z0-9_]*)", line)
    if match:
        return match.group(1)
    return None


def method_key(line: str, name: str) -> str:
    owner = re.search(r"\bfn\s+([A-Za-z0-9_]+)\s*::", line)
    return f"{owner.group(1)}::{name}" if owner else name


# ---------------------------------------------------------------------------
# Reading the generated interfaces
# ---------------------------------------------------------------------------

ITEM = re.compile(
    r"^(?P<kind>pub(?:\.[a-z]+)?)\s+(?P<body>.+)$"
)


def read_mbti(path: Path) -> list[tuple[str, str]]:
    """The public items of one package, as `(kind, signature)` pairs."""
    items: list[tuple[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.rstrip()
        if not line.startswith("pub"):
            continue
        if line.startswith("pub impl") or line.startswith("pub impl "):
            continue
        match = ITEM.match(line)
        if not match:
            continue
        body = match.group("body")
        if body.startswith("fn "):
            items.append(("fn", body[3:]))
        elif body.startswith(("struct ", "enum ", "type ", "trait ", "let ", "const ")):
            items.append(("type", body))
        elif body.startswith("extend "):
            continue
    return items


def split_name(signature: str) -> tuple[str | None, str]:
    """`Pattern::search(...)` -> `("Pattern", "search(...)")`."""
    match = re.match(r"([A-Za-z0-9_]+)::([A-Za-z0-9_]+)(.*)$", signature, re.S)
    if match:
        return match.group(1), match.group(2) + match.group(3)
    match = re.match(r"(?:fn\s+)?([A-Za-z_][A-Za-z0-9_]*?)(\s*[(<:]|\s*$)", signature)
    if match:
        return None, signature
    return None, signature


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def inline(text: str) -> str:
    """Doc text to HTML: paragraphs, `code`, and the odd arrow."""
    out = []
    for block in text.split("\n\n"):
        block = block.strip()
        if not block:
            continue
        escaped = html.escape(block)
        escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
        escaped = escaped.replace("\n", " ")
        out.append(f"<p>{escaped}</p>")
    return "\n".join(out)


def short(signature: str, limit: int = 96) -> str:
    signature = re.sub(r"\s+", " ", signature).strip()
    if len(signature) <= limit:
        return signature
    return signature[: limit - 1].rstrip() + "…"


def render_package(slug: str, docs: dict[str, str]) -> str:
    path = SRC / Path(slug.replace("moonregex", "")).relative_to("/") / "pkg.generated.mbti" if slug != "moonregex" else SRC / "pkg.generated.mbti"
    if not path.exists():
        return ""
    items = read_mbti(path)
    free: list[str] = []
    types: dict[str, list[tuple[str, str]]] = {}
    values: list[str] = []

    for kind, signature in items:
        owner, rest = split_name(signature)
        if owner is None:
            if signature.startswith(("let ", "const ")):
                values.append(signature)
            else:
                free.append(signature)
        else:
            method = rest.split("(", 1)[0].strip()
            if method not in GENERATED:
                types.setdefault(owner, []).append((f"{owner}::{method}", rest))

    blocks = []
    title = PACKAGE_TITLES.get(slug, slug)
    blurb = PACKAGE_BLURB.get(slug, "")
    blocks.append(f'<section class="pkg" id="{slug.replace("/", "-")}">')
    blocks.append(f"<h2>{title}</h2>")
    if blurb:
        blocks.append(f'<p class="blurb">{blurb}</p>')
    blocks.append(f'<p class="slug"><code>{slug}</code></p>')

    if types:
        blocks.append("<h3>Types</h3>")
        for owner in sorted(types):
            doc = docs.get(owner, "")
            rows = []
            for key, rest in sorted(types[owner]):
                text = docs.get(key, "")
                rows.append(
                    "<li>"
                    f'<code class="sig">{html.escape(short(rest, 120))}</code>'
                    + (f'<div class="desc">{inline(text)}</div>' if text else "")
                    + "</li>"
                )
            blocks.append(
                f'<div class="type" id="{slug.replace("/", "-")}-{owner}">'
                f'<h4><code>{html.escape(owner)}</code></h4>'
                + (f'<div class="desc">{inline(doc)}</div>' if doc else "")
                + f'<ul class="members">{"".join(rows)}</ul></div>'
            )

    if free:
        blocks.append("<h3>Functions</h3>")
        blocks.append('<ul class="members">')
        for signature in sorted(free):
            name = re.match(r"([A-Za-z0-9_]+)", signature)
            doc = docs.get(name.group(1), "") if name else ""
            blocks.append(
                "<li>"
                f'<code class="sig">{html.escape(short(signature, 140))}</code>'
                + (f'<div class="desc">{inline(doc)}</div>' if doc else "")
                + "</li>"
            )
        blocks.append("</ul>")

    if values:
        blocks.append("<h3>Values</h3>")
        blocks.append('<ul class="members">')
        for signature in sorted(values):
            name = re.match(r"(?:let|const)\s+([A-Za-z0-9_]+)", signature)
            doc = docs.get(name.group(1), "") if name else ""
            blocks.append(
                "<li>"
                f'<code class="sig">{html.escape(short(signature))}</code>'
                + (f'<div class="desc">{inline(doc)}</div>' if doc else "")
                + "</li>"
            )
        blocks.append("</ul>")

    blocks.append("</section>")
    return "\n".join(blocks)


def package_sources(slug: str) -> list[Path]:
    directory = SRC if slug == "moonregex" else SRC / slug.split("/", 1)[1]
    return sorted(p for p in directory.glob("*.mbt") if not p.name.endswith("_test.mbt"))


def main() -> int:
    sections = []
    nav = []
    for slug in PACKAGE_ORDER:
        directory = SRC if slug == "moonregex" else SRC / slug.split("/", 1)[1]
        if not (directory / "pkg.generated.mbti").exists():
            continue
        docs = doc_map(package_sources(slug))
        rendered = render_package(slug, docs)
        if rendered:
            sections.append(rendered)
            nav.append(
                f'<li><a href="#{slug.replace("/", "-")}">{PACKAGE_TITLES.get(slug, slug)}</a></li>'
            )

    page = TEMPLATE.replace("{{NAV}}", "\n".join(nav)).replace(
        "{{BODY}}", "\n".join(sections)
    )
    OUT.write_text(page, encoding="utf-8", newline="\n")
    print(f"{OUT.relative_to(ROOT)}: {len(sections)} packages")
    return 0


TEMPLATE = """<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>moonregex — API reference</title>
<meta name="description" content="Every public type, function and value moonregex exports, generated from the packages' interfaces and their documentation." />
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Ccircle cx='16' cy='16' r='13' fill='%238ea2ff'/%3E%3Ccircle cx='21' cy='12' r='11' fill='%23080a13'/%3E%3C/svg%3E" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;700&family=Inter:wght@400;500;600&display=swap" rel="stylesheet" />
<link rel="stylesheet" href="./assets/site.css" />
<script type="module" src="assets/scrollbar.js"></script>
<script>
  (function () {
    try {
      var saved = localStorage.getItem("moonregex-theme");
      var light = window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches;
      document.documentElement.setAttribute("data-theme", saved || (light ? "light" : "dark"));
    } catch (e) {}
  })();
</script>
</head>
<body>

<div class="sky"></div>
<div class="stars"></div>
<div class="grid-lines"></div>

<header class="nav">
  <div class="wrap nav-inner">
    <a class="brand" href="./index.html"><span class="dot"></span>moon<span class="acc">regex</span></a>
    <div class="nav-tools">
      <nav class="nav-links" id="nav-panel" aria-label="site">
        <a href="./index.html">Home</a>
        <a href="./showcase.html">Showcase</a>
        <a href="./guide.html">Guide</a>
        <a class="on" href="./api.html" aria-current="page">API</a>
      </nav>
      <button class="theme-toggle" type="button" aria-label="Switch theme">
        <svg class="moon-icon" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z"/></svg>
        <svg class="sun" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><circle cx="12" cy="12" r="4.2"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5 5l1.4 1.4M17.6 17.6 19 19M19 5l-1.4 1.4M6.4 17.6 5 19"/></svg>
      </button>
      <a class="cta" href="https://github.com/moonbitstack/moonregex" aria-label="Repository on GitHub">
        <svg width="15" height="15" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>
        <span class="lbl">GitHub</span>
      </a>
      <button class="nav-burger" type="button" aria-expanded="false" aria-controls="nav-panel" aria-label="Open the menu">
        <svg class="bar-open" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>
        <svg class="bar-close" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>
      </button>
    </div>
  </div>
</header>

<div class="wrap layout">
  <aside class="side">
    <h4>Packages</h4>
    <ul>
{{NAV}}
    </ul>
  </aside>
  <main>
    <h1 class="docs-title">Every <span class="reg">public</span> name.</h1>
    <p class="docs-lede">Generated from the packages' interfaces and their
      documentation. Types first, then functions and values, each in alphabetical
      order.</p>
{{BODY}}
  </main>
</div>

<footer>
  <div class="wrap foot-grid">
    <div>
      <a class="brand" href="./index.html"><span class="dot"></span>moon<span class="acc">regex</span></a>
      <div class="foot-note">© 2026 Leo Cheng · Apache-2.0</div>
    </div>
    <div class="foot-links">
      <a href="./index.html">Home</a>
      <a href="./showcase.html">Showcase</a>
      <a href="./guide.html">Guide</a>
      <a href="./api.html">API</a>
      <a href="https://mooncakes.io/docs/moonbitstack/moonregex">Mooncakes</a>
      <a href="https://github.com/moonbitstack/moonregex">GitHub</a>
      <a href="https://github.com/moonbitstack/moonregex/blob/master/README.md">README</a>
    </div>
  </div>
</footer>

<script src="./assets/site.js"></script>
</body>
</html>
"""


if __name__ == "__main__":
    raise SystemExit(main())
