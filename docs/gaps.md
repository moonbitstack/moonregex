# moonregex — Remaining Gap Analysis (completion pass)

> **Status: closed.** Every item below has now been implemented and tested —
> the control verbs, the newline/whitespace escapes, braced backreferences,
> branch reset, `(?(DEFINE)…)` and recursion conditions. Two niche items remain
> deliberately deferred: `\N{name}` (a named Unicode character, needs a UCD name
> table) and `\g{-1}` (relative backreference, needs open-group tracking).

This is the authoritative checklist for the completion pass: every feature of
Python `re`, the `regex` (mrab-regex) package, and the commonly-used extensions
from other regex engines (PCRE / Perl / JavaScript / .NET / Ruby) that the
engine did **not** carry, mapped to exactly how it was closed.

Two rules govern the pass:

1. **Everything below is implemented**, regardless of how rarely a caller uses
   it. A gap is never left "documented but unimplemented".
2. **Other-language features that already map onto an existing moonregex
   construct are not reimplemented** — they are already covered. Only features
   with no counterpart get a new, same-style implementation.

---

## 1. Control verbs — the previously-documented gaps

| Verb | Semantics | Where it lands |
|------|-----------|----------------|
| `(*ACCEPT)` | end the match successfully now | done (`Accept`) |
| `(*FAIL)` / `(*F)` | force failure, backtrack | done (`Fail`) |
| `(*COMMIT)` | fail the entire match, no further search | ✅ `Commit` instruction → `Commit` refusal |
| `(*PRUNE)` / `(*PRUNE:name)` | fail current branch, no re-entry | ✅ `Prune` instruction |
| `(*SKIP)` / `(*SKIP:name)` | fail and resume search at the last `(*MARK)` (or search start) | ✅ `Skip` instruction → `Skip` refusal |
| `(*THEN)` / `(*THEN:name)` | fail and jump to next alternative | ✅ `Then` instruction |
| `(*MARK:name)` / `(*:name)` | record a mark at the current position | ✅ `Mark` instruction + `Match.marks()` |
| `(*LIMIT_MATCH:n)` | set the match step ceiling | ✅ `Limit` instruction (dynamic step limit) |
| `(*LIMIT_RECURSION:n)` | set the recursion depth ceiling | ✅ `Limit` instruction (dynamic recursion limit) |
| `(*VERSION)` | accept the current engine version (no-op) | ✅ `Version` instruction |
| `(*FENCE)` | prevent any backtracking past this point | ✅ `Fence` instruction (barrier) |

The AST `VerbKind` grows to `Accept, Fail, Commit, Prune, Skip, Then, Mark(name),
Limit(kind, n), Version, Fence`. The VM gains the matching `Inst` variants; the
mark stack and the dynamic limits live on the matcher as reference-mutable
arrays (MoonBit has no mutable struct fields).

---

## 2. Python `re` / mrab-regex — remaining escapes

| Escape | Meaning | Status |
|--------|---------|--------|
| `\R` | Unicode line break (LF, VT, FF, CR, NEL, LS, PS) | ✅ |
| `\h` / `\H` | horizontal whitespace (and its complement) | ✅ |
| `\v` / `\V` | vertical whitespace (and its complement) | ✅ |
| `\N` | any character except a newline | ✅ |
| `\N{name}` | a named Unicode character | deferred — needs a UCD name table (§4) |
| `\e` | escape (0x1B) | ✅ |

---

## 3. Other languages — extensions with no moonregex counterpart

| Feature | Language(s) | Mapping | Status |
|---------|-------------|---------|--------|
| `\g{name}` / `\g{n}` | Perl, Oniguruma | braced backreference next to `\g<…>` | ✅ added this pass |
| `\g{-1}` (relative) | Perl, Oniguruma | relative backreference | deferred (needs open-group tracking) |
| `(?|…)` branch reset | Perl, PCRE | reset group numbering per alternative | ✅ added this pass |
| `(?(DEFINE)…)` | PCRE | declare subroutines, match empty | ✅ added this pass |
| `(?(R)…)` / `(?(R1)…)` / `(?(R&name)…)` | PCRE, mrab-regex | recursion condition | ✅ added this pass |
| `\k{name}` | .NET | named backreference (braced) | covered by `\g{name}` |
| `\A`, `\z`, `\Z`, `\G`, `\K`, `\X` | PCRE/Perl/JS | already implemented | ✅ already present |
| `(?>…)`, possessive `*+` | PCRE/Perl | already implemented | ✅ already present |
| `(?'name'…)` | .NET | already implemented (ECMA) | ✅ already present |

---

## 4. Named Unicode characters — `\N{name}`

Python `re` and `regex` both accept `\N{NAME}` to match a character by its
Unicode name (e.g. `\N{EM DASH}`, `\N{SNOWMAN}`). This needs a name → code
point table derived from the UCD `UnicodeData.txt` (already fetched by
`scripts/gen_unicode.py`).

Status: **deferred to a follow-up that regenerates the prop tables** — the name
table is ~150 000 entries and, unlike the property tables, is generated from the
name field rather than a ranges field; shipping it half-sized (e.g. without CJK
ideograph names) would silently break patterns, which the architecture forbids.
Until it lands, `\N{name}` is refused with a precise message (as today), and
plain `\N` works as "not newline".

---

## 5. What is *not* a gap

Already implemented and verified (so no work is scheduled for them):

- Every `re` module function and `Pattern`/`Match`/`Scanner` method, flags,
  `subf`/`subfn`, fuzzy `{e/i/d/s}` + `fuzzy_counts`/`fuzzy_changes`.
- Named groups `(?P<name>…)`, `(?<name>…)`, `(?'name'…)`; backreferences
  `\1`, `\g<name>`, `\g<1>`, `(?P=name)`, `\k<name>` (ECMA).
- Recursion `(?R)`, `(?0)`, `(?1)`, `(?&name)`, `(?P>name)`.
- Lookaround (fixed/variable lookbehind), atomic groups, possessive quantifiers,
  conditionals `(?(id)…|…)` and `(?(?=…)…|…)`.
- `\p{…}` / `\P{…}`, `\Q…\E`, set algebra (`--`, `&&`, `~~`) under V1.
- Three dialects (Python, ECMA-262, lexmatch) and the `glob`/`fnmatch` layer.
