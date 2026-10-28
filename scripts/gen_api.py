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
    OUT.write_text(page, encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(sections)} packages")
    return 0


TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>moonregex — API reference</title>
<meta name="description" content="Every public type, function and value moonregex exports, generated from the packages' interfaces and their documentation." />
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Ccircle cx='16' cy='16' r='13' fill='%238ea2ff'/%3E%3Ccircle cx='21' cy='12' r='11' fill='%230a0b14'/%3E%3C/svg%3E" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;700&family=Inter:wght@400;500;600&display=swap" rel="stylesheet" />
<style>
  :root {
    --bg: #0a0b14; --bg-2: #0e1020; --surface: #12142a;
    --border: rgba(255,255,255,0.08); --text: #eceaf6; --muted: #9a98b5;
    --faint: #6b698a; --accent: #8ea2ff; --accent-2: #5be0c6; --mark: #ffc857;
    --display: "Space Grotesk", "Segoe UI", system-ui, sans-serif;
    --mono: "JetBrains Mono", "SF Mono", "Cascadia Code", Consolas, monospace;
    --body: "Inter", system-ui, -apple-system, "Segoe UI", sans-serif;
  }
  * { box-sizing: border-box; }
  html, body, button, input, textarea, select { font-variant-ligatures: no-contextual; }
  html { scroll-behavior: smooth; }
  body {
    margin: 0; color: var(--text); font-family: var(--body); line-height: 1.65; font-size: 16px;
    background: radial-gradient(1000px 600px at 88% -10%, rgba(142,162,255,0.13), transparent 60%),
                linear-gradient(180deg, var(--bg) 0%, var(--bg-2) 100%);
    background-attachment: fixed;
  }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  code { font-family: var(--mono); font-size: 0.88em; }
  .nav { position: sticky; top: 0; z-index: 10; backdrop-filter: blur(12px); background: rgba(10,11,20,0.82); border-bottom: 1px solid var(--border); }
  .wrap { width: min(1120px, calc(100% - 48px)); margin: 0 auto; }
  .nav-inner { display: flex; align-items: center; justify-content: space-between; height: 62px; }
  .brand { font-family: var(--display); font-weight: 600; font-size: 19px; color: var(--text); display: flex; align-items: center; gap: 8px; }
  .brand .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--accent); box-shadow: 0 0 12px var(--accent); }
  .brand .acc { color: var(--accent); }
  .nav-links { display: flex; align-items: center; gap: 4px; }
  .nav-links a { color: var(--muted); font-size: 14.5px; padding: 7px 11px; border-radius: 8px; }
  .nav-links a:hover { color: var(--text); background: rgba(255,255,255,0.05); text-decoration: none; }
  .nav-links a.cta { color: var(--text); border: 1px solid var(--border); }
  .layout { display: grid; grid-template-columns: minmax(0, 210px) minmax(0, 1fr); gap: 44px; padding: 36px 0 80px; }
  .side { position: sticky; top: 84px; align-self: start; font-size: 14.5px; }
  .side h4 { margin: 0 0 10px; font-family: var(--display); font-size: 12px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--faint); }
  .side ul { list-style: none; margin: 0; padding: 0; }
  .side li a { display: block; color: var(--muted); padding: 5px 10px; border-radius: 0 8px 8px 0; border-left: 2px solid transparent; }
  .side li a:hover { color: var(--text); background: rgba(255,255,255,0.04); text-decoration: none; }
  main { min-width: 0; }
  h1 { font-family: var(--display); font-size: 36px; letter-spacing: -0.02em; margin: 8px 0 6px; }
  h1 .reg { color: var(--mark); }
  .lede { color: var(--muted); margin: 0 0 8px; }
  .pkg { padding-top: 30px; }
  .pkg h2 { font-family: var(--display); font-size: 26px; margin: 30px 0 2px; scroll-margin-top: 84px; }
  .pkg .blurb { color: var(--muted); margin: 4px 0 2px; }
  .pkg .slug code { color: var(--faint); font-size: 13px; }
  .pkg h3 { font-family: var(--display); font-size: 13px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--faint); margin: 30px 0 8px; }
  .type { border: 1px solid var(--border); border-radius: 12px; padding: 14px 18px; margin: 12px 0; background: rgba(18,20,42,0.6); }
  .type h4 { margin: 0 0 4px; font-family: var(--display); font-size: 17px; }
  .type h4 code { color: var(--accent-2); font-size: 16px; }
  .members { list-style: none; margin: 8px 0 0; padding: 0; }
  .members li { padding: 8px 0; border-top: 1px solid var(--border); }
  .members li:first-child { border-top: none; }
  .sig { display: block; color: #cfd6ff; font-size: 13.5px; overflow-x: auto; white-space: nowrap; }
  .desc { color: var(--muted); font-size: 14.5px; margin-top: 4px; }
  .desc p { margin: 4px 0; }
  .desc code { color: var(--accent-2); background: rgba(91,224,198,0.08); padding: 0 4px; border-radius: 4px; }
  footer { border-top: 1px solid var(--border); padding: 28px 0 60px; color: var(--faint); font-size: 14px; }
  footer .foot-grid { display: flex; justify-content: space-between; gap: 20px; flex-wrap: wrap; }
  ::-webkit-scrollbar { width: 11px; height: 11px; }
  ::-webkit-scrollbar-track { background: #0b0d18; }
  ::-webkit-scrollbar-thumb { background: #262a45; border-radius: 6px; border: 2px solid #0b0d18; }
  ::-webkit-scrollbar-thumb:hover { background: #343a5e; }
  @supports not selector(::-webkit-scrollbar) {
    html { scrollbar-color: #343a5e #0b0d18; scrollbar-width: thin; }
  }
  @media (width <= 860px) {
    .layout { grid-template-columns: minmax(0, 1fr); gap: 8px; }
    .side { position: static; }
    .wrap { width: calc(100% - 32px); }
    h1 { font-size: 30px; }
  }
</style>
</head>
<body>
<header class="nav">
  <div class="wrap nav-inner">
    <a class="brand" href="./index.html"><span class="dot"></span>moon<span class="acc">regex</span></a>
    <nav class="nav-links">
      <a href="./index.html">Home</a>
      <a href="./guide.html">Guide</a>
      <a href="./api.html">API</a>
      <a class="cta" href="https://github.com/moonbitstack/moonregex">GitHub</a>
    </nav>
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
    <h1>Every <span class="reg">public</span> name.</h1>
    <p class="lede">Generated from the packages' interfaces and their documentation.
      Grouped by package; within a package, types first, then functions and values,
      each in alphabetical order.</p>
{{BODY}}
  </main>
</div>

<footer>
  <div class="wrap foot-grid">
    <div>moonregex — Apache-2.0.</div>
    <div>
      <a href="./index.html">Home</a> ·
      <a href="./guide.html">Guide</a> ·
      <a href="https://github.com/moonbitstack/moonregex">GitHub</a> ·
      <a href="https://mooncakes.io/docs/moonbitstack/moonregex">Mooncakes</a>
    </div>
  </div>
</footer>
</body>
</html>
"""


if __name__ == "__main__":
    raise SystemExit(main())
