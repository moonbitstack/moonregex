#!/usr/bin/env python3
"""Generate prop/unicode_data.mbt — the Unicode property tables — from the
Unicode Character Database.

The tables are data, not code: they are regenerated whenever Unicode ships a
new version, and the version they came from is recorded in the generated file
(and surfaced as `@prop.version()`), so a pattern that relies on a property
behaves the same everywhere and the reader can tell which Unicode it answers
to.

Reproducible: every run with the same `--version` writes byte-identical output.
The UCD files are fetched once into `scripts/.ucd/<version>/` and reused after
that, so the script works offline once the cache is warm.

    python3 scripts/gen_unicode.py                 # Unicode 17.0.0
    python3 scripts/gen_unicode.py --version 16.0.0

DO NOT EDIT the generated file by hand.
"""

import argparse
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "prop" / "unicode_data.mbt"
CACHE = ROOT / "scripts" / ".ucd"
BASE = "https://www.unicode.org/Public/{v}/ucd"

FILES = [
    "UnicodeData.txt",
    "Scripts.txt",
    "Blocks.txt",
    "PropList.txt",
    "DerivedCoreProperties.txt",
    "CaseFolding.txt",
    "emoji/emoji-data.txt",
    "PropertyValueAliases.txt",
]

# Binary properties worth a table. The rest of PropList / DerivedCoreProperties
# is of no use to a regex engine that matches text.
BINARY_PROPERTIES = [
    "ASCII_Hex_Digit",
    "Alphabetic",
    "Bidi_Control",
    "Cased",
    "Case_Ignorable",
    "Changes_When_Casefolded",
    "Changes_When_Lowercased",
    "Changes_When_Uppercased",
    "Default_Ignorable_Code_Point",
    "Deprecated",
    "Diacritic",
    "Emoji",
    "Emoji_Component",
    "Emoji_Modifier",
    "Emoji_Modifier_Base",
    "Emoji_Presentation",
    "Extended_Pictographic",
    "Extender",
    "Hex_Digit",
    "Hyphen",
    "ID_Continue",
    "ID_Start",
    "Ideographic",
    "Join_Control",
    "Logical_Order_Exception",
    "Lowercase",
    "Math",
    "Noncharacter_Code_Point",
    "Pattern_Syntax",
    "Pattern_White_Space",
    "Quotation_Mark",
    "Radical",
    "Regional_Indicator",
    "Sentence_Terminal",
    "Soft_Dotted",
    "Terminal_Punctuation",
    "Uppercase",
    "Variation_Selector",
    "White_Space",
    "XID_Continue",
    "XID_Start",
]

# Spellings the mrab-regex superset accepts beyond the canonical Unicode name.
BINARY_ALIASES = {
    "alpha": "Alphabetic",
    "upper": "Uppercase",
    "lower": "Lowercase",
    "whitespace": "White_Space",
    "space": "White_Space",
    "iscased": "Cased",
    "caseignorable": "Case_Ignorable",
}

def fetch(version: str, name: str) -> str:
    cached = CACHE / version / name
    if not cached.exists():
        cached.parent.mkdir(parents=True, exist_ok=True)
        url = f"{BASE.format(v=version)}/{name}"
        print(f"fetching {url}", file=sys.stderr)
        with urllib.request.urlopen(url, timeout=60) as r:
            cached.write_bytes(r.read())
    return cached.read_text(encoding="utf-8")


def parse_ranges_field(line_field: str):
    """'0041..005A' or '0041' -> (0x41, 0x5A) / (0x41, 0x41)."""
    if ".." in line_field:
        lo, hi = line_field.split("..")
        return int(lo, 16), int(hi, 16)
    c = int(line_field, 16)
    return c, c


def normalise(ranges):
    """Sort and merge into the disjoint form CharSet keeps."""
    out = []
    for lo, hi in sorted(ranges):
        if out and lo <= out[-1][1] + 1:
            out[-1] = (out[-1][0], max(out[-1][1], hi))
        else:
            out.append((lo, hi))
    return out


def read_value_aliases(version):
    """Every spelling of a general category, script or block value.

    PropertyValueAliases.txt is the authority on which spellings name the same
    value: `Lu`, `Uppercase_Letter`, `Grek`, `Greek`, `ASCII`, `Basic_Latin`.
    Returns {kind: {normalised_key: canonical_name}} where the canonical name
    is the one the data file (UnicodeData, Scripts, Blocks) spells it with —
    the short name for categories, the long one for scripts and blocks.
    """
    aliases = {"gc": {}, "sc": {}, "blk": {}}
    # Which field of the line names the value the way its data file does.
    canonical_field = {"gc": 0, "sc": 1, "blk": 1}
    for line in fetch(version, "PropertyValueAliases.txt").splitlines():
        line = line.split("#")[0].strip()
        if not line or ";" not in line:
            continue
        kind = line.split(";")[0].strip()
        if kind not in aliases:
            continue
        fields = [p.strip() for p in line.split(";")[1:]]
        canonical = fields[canonical_field[kind]]
        for spelling in [f for f in fields if f]:
            aliases[kind][norm(spelling)] = canonical
    return aliases


def norm(name: str) -> str:
    """Loose matching, the way Unicode specifies it for property values."""
    return re.sub(r"[ _\-]", "", name).lower()


def spellings(aliases, kind):
    """{data-file name: [every normalised spelling]} for one kind of value."""
    out = {}
    for key, canonical in aliases[kind].items():
        out.setdefault(norm(canonical), []).append(key)
    return out


def read_unicodedata(version):
    """General categories: {'Lu': [...], 'L': [...]} (one-letter groups unioned).

    UnicodeData.txt spells a run of same-category code points as a
    `<Name, First>` / `<Name, Last>` pair; the code point of the second line
    closes the range the first opened.
    """
    cats = {}
    first_cp = None
    first_gc = None
    for line in fetch(version, "UnicodeData.txt").splitlines():
        f = line.split(";")
        if len(f) < 3:
            continue
        cp = int(f[0], 16)
        name, gc = f[1], f[2]
        if name.endswith(", First>"):
            first_cp, first_gc = cp, gc
            continue
        if name.endswith(", Last>"):
            if first_cp is None or first_gc != gc:
                raise SystemExit(f"unbalanced First/Last pair at {cp:04X}")
            cats.setdefault(gc, []).append((first_cp, cp))
            first_cp = first_gc = None
            continue
        cats.setdefault(gc, []).append((cp, cp))
    if first_cp is not None:
        raise SystemExit("dangling First range at end of UnicodeData.txt")
    # One-letter groups are the union of their members, as Unicode defines them;
    # LC (Cased_Letter) is the one group that is not a prefix union.
    for group in "LMNPSCZ":
        cats[group] = normalise(
            [r for g in cats if g.startswith(group) for r in cats[g]])
    cats["LC"] = normalise(cats.get("Ll", []) + cats.get("Lt", []) + cats.get("Lu", []))
    return {k: normalise(v) for k, v in cats.items()}


def read_scripts(version):
    scripts = {}
    for line in fetch(version, "Scripts.txt").splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        rng, _, name = (p.strip() for p in line.partition(";"))
        lo, hi = parse_ranges_field(rng)
        scripts.setdefault(name, []).append((lo, hi))
    return {k: normalise(v) for k, v in scripts.items()}


def read_blocks(version):
    blocks = {}
    for line in fetch(version, "Blocks.txt").splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        rng, _, name = (p.strip() for p in line.partition(";"))
        lo, hi = parse_ranges_field(rng)
        blocks.setdefault(name, []).append((lo, hi))
    return {k: normalise(v) for k, v in blocks.items()}


def read_props(version, files, wanted):
    """Binary properties across PropList / DerivedCoreProperties / emoji-data."""
    props = {name: [] for name in wanted}
    for fname in files:
        for line in fetch(version, fname).splitlines():
            line = line.split("#")[0].strip()
            if not line:
                continue
            rng, _, name = (p.strip() for p in line.partition(";"))
            if name in props:
                lo, hi = parse_ranges_field(rng)
                props[name].append((lo, hi))
    missing = [n for n, v in props.items() if not v]
    if missing:
        raise SystemExit(f"properties with no data: {missing}")
    return {k: normalise(v) for k, v in props.items()}


def read_casefold(version):
    """Simple, single-code-point case folding: the C and S mappings only.

    Sorted by source code point — these are pairs, not ranges, so they are
    never merged: merging (0x41, 0x61) with (0x42, 0x62) would invent the
    folding A -> z.
    """
    pairs = []
    for line in fetch(version, "CaseFolding.txt").splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        fields = [p.strip() for p in line.split(";")]
        cp, status, mapping = fields[0], fields[1], fields[2]
        if status not in ("C", "S"):
            continue
        if " " in mapping:  # full mappings expand to several code points
            continue
        pairs.append((int(cp, 16), int(mapping, 16)))
    return sorted(pairs)


def ident(name: str) -> str:
    return re.sub(r"[^0-9a-zA-Z]", "_", name).lower()


def emit_set(name: str, ranges, out, comment=None):
    if comment:
        out.append(f"// {comment}")
    body = ", ".join(f"(0x{lo:X}, 0x{hi:X})" for lo, hi in ranges)
    # Top-level items are private unless marked `pub`, so no modifier is needed
    # here — and a package never qualifies its own names with `@pkg.`.
    out.append(f"let {name} : CharSet = CharSet::of([{body}])")
    out.append("")


def emit_match(fn: str, arms, out, default="None"):
    """arms: [(moonbit-pattern, table-ident)]"""
    out.append(f"fn {fn}(name : StringView) -> CharSet? {{")
    out.append("  match name {")
    for pat, table in arms:
        out.append(f'    "{pat}" => Some({table})')
    out.append(f"    _ => {default}")
    out.append("  }")
    out.append("}")
    out.append("")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="17.0.0")
    args = ap.parse_args()
    v = args.version

    aliases = read_value_aliases(v)
    cats = read_unicodedata(v)
    scripts = read_scripts(v)
    blocks = read_blocks(v)
    props = read_props(v, ["PropList.txt", "DerivedCoreProperties.txt", "emoji/emoji-data.txt"], BINARY_PROPERTIES)
    fold = read_casefold(v)

    out = []
    w = out.append
    w(f"// Generated by scripts/gen_unicode.py from the Unicode {v} Character")
    w("// Database. DO NOT EDIT — regenerate with `python3 scripts/gen_unicode.py`.")
    w("//")
    w("// The tables below are data. The version they came from is recorded here")
    w(f"// and surfaced as @prop.version(), so a pattern that leans on \\p{{...}} can")
    w("// say which Unicode it answers to.")
    w("")
    w(f'let unicode_version : String = "{v}"')
    w("")

    # --- general categories -------------------------------------------------
    # Every spelling PropertyValueAliases.txt accepts — Lu, Uppercase_Letter,
    # uppercaseletter — reaches the one table the category has.
    w("// General categories, one-letter groups included (L, M, N, P, S, Z, C).")
    gc_keys = spellings(aliases, "gc")
    cat_arms = []
    for name in sorted(cats):
        emit_set(f"gc_{ident(name)}", cats[name], out)
        for key in sorted(gc_keys.get(norm(name), [name.lower()])):
            cat_arms.append((key, f"gc_{ident(name)}"))
    emit_match("gc_of", cat_arms, out)

    # --- scripts ------------------------------------------------------------
    w("// Scripts, long and short names (Scripts.txt, PropertyValueAliases.txt).")
    sc_keys = spellings(aliases, "sc")
    sc_arms = []
    for name in sorted(scripts):
        emit_set(f"sc_{ident(name)}", scripts[name], out)
        for key in sorted(sc_keys.get(norm(name), [norm(name)])):
            sc_arms.append((key, f"sc_{ident(name)}"))
    emit_match("script_of", sc_arms, out)

    # --- blocks -------------------------------------------------------------
    w("// Blocks (Blocks.txt, PropertyValueAliases.txt).")
    blk_keys = spellings(aliases, "blk")
    blk_arms = []
    for name in sorted(blocks):
        emit_set(f"blk_{ident(name)}", blocks[name], out)
        for key in sorted(blk_keys.get(norm(name), [norm(name)])):
            blk_arms.append((key, f"blk_{ident(name)}"))
    emit_match("block_of", blk_arms, out)

    # --- binary properties ---------------------------------------------------
    w("// Binary properties, with the short spellings the superset accepts.")
    bin_arms = []
    for name in sorted(props):
        emit_set(f"bin_{ident(name)}", props[name], out)
        bin_arms.append((name.lower().replace("_", ""), f"bin_{ident(name)}"))
    for alias, target in BINARY_ALIASES.items():
        # An alias that normalises to a canonical key would be a second match
        # arm for the same pattern, which MoonBit rejects as unreachable.
        canonical = {pat for pat, _ in bin_arms}
        if alias not in canonical:
            bin_arms.append((alias, f"bin_{ident(target)}"))
    emit_match("binary_of", bin_arms, out)

    # --- case folding --------------------------------------------------------
    w("// Simple case folding: status C and S, single code point results only.")
    w("// Full (multi-code-point) mappings are left out on purpose — case-")
    w("// insensitive matching here folds one code point at a time.")
    body = ", ".join(f"(0x{lo:X}, 0x{hi:X})" for lo, hi in fold)
    w(f"let casefold_pairs : Array[(Int, Int)] = [{body}]")
    w("")

    text = "\n".join(out).rstrip() + "\n"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8")

    n_ranges = sum(len(x) for x in list(cats.values()) + list(scripts.values()) + list(blocks.values()) + list(props.values())) + len(fold)
    print(f"wrote {OUT} ({len(text.splitlines())} lines, {n_ranges} ranges, Unicode {v})")


if __name__ == "__main__":
    main()
