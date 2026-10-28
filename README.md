<div align="center">

# moonregex

**Regular expressions for MoonBit** — Python's `re` interface, the `regex` superset
behind it, and the ECMA-262 grammar that JSON Schema and OpenAPI mean.

[Homepage](https://moonbitstack.github.io/moonregex/) ·
[Guide](https://moonbitstack.github.io/moonregex/guide.html) ·
[API](https://moonbitstack.github.io/moonregex/api.html) ·
[Mooncakes](https://mooncakes.io/docs/moonbitstack/moonregex)

</div>

<!-- nocheck -->
```moonbit
let year = @moonregex.search("\\d{4}", "copyright 2026").unwrap()
year.content()            // "2026"
year.start()              // 10
@moonregex.sub("\\s+", " ", "a   b  c")   // "a b c"
```

A pattern is read by one of three grammars, lowered into a single syntax tree,
and run by one engine, so the same pattern behaves the same way on every
backend.

| | |
|:--|:--|
| `Python` (the default) | `re` as Python 3.15 documents it, plus everything the `regex` package adds |
| `Ecma262` | ECMA-262 §22.2, the grammar JSON Schema and OpenAPI patterns are written in |
| `Lexmatch` | the grammar the core library's `@string.Regex` and the lexer speak |

## Install

```bash
moon add moonbitstack/moonregex
```

## The names it uses

The module functions are the `re` ones, with three renames — one concept, one
name, and the name says where the match has to fall:

| Python | moonregex | where the match must be |
|:--|:--|:--|
| `re.search` | `search` | anywhere, leftmost first |
| `re.match` | `prefix` | at the position the scan starts |
| `re.fullmatch` | `full` | the whole region |
| `re.sub` with a function | `sub_with` | — |
| `re.subn` with a function | `subn_with` | — |

`match` is not used because in most languages it means what Python calls
`search`, and Python itself has soft-deprecated it in favour of `prefixmatch`.
Reading an ECMA-262 pattern next to a Python one, a name that means two things
is worse than a name nobody has seen before. `Pattern::search`, `Pattern::prefix`
and `Pattern::full` are the same three.

<!-- nocheck -->
```moonbit
let p = @moonregex.compile("[a-z]+")
p.search("  hello ")   // Some(_) — at 2
p.prefix("  hello ")   // None    — the scan starts at 0
p.full("hello")        // Some(_)
```

## The interface

Module functions compile on every call. `compile` once, then use the `Pattern`
methods, when a pattern is used more than once.

| Function | Returns |
|:--|:--|
| `compile(pattern, flags~, dialect~, lists?, partial~)` | `Pattern` |
| `search` / `prefix` / `full` | `Match?` |
| `findall` | `Array[String?]` |
| `finditer` | `Array[Match]` |
| `split` | `Array[String?]` |
| `sub` / `subn` / `subf` / `subfn` | `String` or `(String, Int)` |
| `sub_with` / `subn_with` | `String` or `(String, Int)` |
| `escape(string, dialect~, special_only~, literal_spaces~)` | `String` |

`Pattern` answers `pattern`, `flags`, `dialect`, `groups`, `groupindex`,
`named_lists`, `partial`, `dump`, and the same matching methods without the
compile options. `Match` answers `group`, `groups`, `groupdict`, `start`, `end`,
`span`, `captures`, `starts`, `ends`, `spans`, `capturesdict`, `allcaptures`,
`allspans`, `expand`, `expandf`, `pos`, `endpos`, `lastindex`, `lastgroup`, `re`,
`string`, `content`, `before`, `after`, `fuzzy_counts`, `fuzzy_changes`, `marks`
and `partial`.

A group is addressed by number or by name — `trait GroupKey` is implemented by
`Int` and by `String`, so `m.group(1)` and `m.group("year")` both work.

### Groups, and the one place a list cannot answer

`findall` collects the whole match when the pattern has no groups, the single
group when it has one — and refuses when it has two or more, because Python
answers a tuple there and a statically typed list cannot. Pass `group` to say
which one, or walk `finditer` for matches that carry them all.

<!-- nocheck -->
```moonbit
@moonregex.findall("(\\w+)=(\\d+)", "a=1")            // raises Ambiguous
@moonregex.findall("(\\w+)=(\\d+)", "a=1", group=1)   // ["a"]
```

### Flags

`Flags` is a record, not a bitmask: `Flags::new(ignorecase=true)` sets one
switch and leaves the rest, and `@moonregex.flags` is all of them off.

`ignorecase`, `multiline`, `dotall`, `verbose`, `ascii`, `unicode`,
`unicode_sets`, `fullcase`, `bestmatch`, `enhancematch`, `posix`, `reverse`,
`word`, and `version` (`V0` / `V1`).

The common ones also have their inline spelling — `(?i)`, `(?m)`, `(?s)`,
`(?x)`, `(?a)` and the scoped `(?i:…)` — which needs no flag argument at all.

### Escape

`escape` follows the grammar it is told to follow, because the three do not
agree on what is special:

| Dialect | `escape("a.b")` | rule |
|:--|:--|:--|
| `Python` | `a\.b` | `re.escape`: the characters that can mean something take a backslash |
| `Ecma262` | `\x61\.b` | `RegExp.escape`: punctuation is spelled in hex, and a leading alphanumeric too |
| `Lexmatch` | `a\.b` | the `@string.Regex` metacharacters, with `\u{…}` for the invisible ones |

## The three grammars

<!-- nocheck -->
```moonbit
// Python: named group, `\A`, backreference — the default.
@moonregex.findall("(?P<w>\\w+)\\s+\\1", "go go no")

// ECMA-262: what a JSON Schema `pattern` means.
@moonregex.compile("^[a-z]+$", dialect=@moonregex.ecma262)

// lexmatch: a pattern already written for the core library.
@moonregex.compile("[[:digit:]]+", dialect=@moonregex.lexmatch_dialect)
```

Choose by where the pattern comes from. A pattern a person wrote for text
processing is `Python`; a pattern from a schema, a form, or a JavaScript
codebase is `Ecma262`; a pattern from a MoonBit lexer is `Lexmatch`.

The dialects differ where the standards differ: `\A` and `\Z` exist only in
Python, `$` sits before a trailing newline only in Python, `\w` is ASCII in
ECMA-262, and `[[:alpha:]]` is a class escape only in the superset. Each of
those is settled while reading the pattern, not while matching it.

## Standing next to the core engine

The core library ships a regular-expression engine of its own, reached through
`@string.Regex` and the `lexmatch` grammar. This library uses it where it can
and runs the rest itself.

- **A pattern that says nothing the core engine cannot say lowers onto it.**
  `Pattern::lower` answers the `@string.Regex` for it, or `None`. Backreferences,
  lookaround, conditionals, recursion, atomic groups, fuzzy matching, `\X`,
  Unicode word boundaries and Python's `$` answer `None` — those run here.
- **The combinators are the same five**, with the same meaning: `Pattern::string`,
  `+`, `|`, `repeat`, `capture`. A pattern assembled in code and a pattern
  written as text are the same kind of value.
- **A match carries both views**: `content`, `before` and `after` as core spells
  them, next to `group`, `span` and the rest.

<!-- nocheck -->
```moonbit
let year = @moonregex.Pattern::string("\\d{4}").capture("year")
let dash = @moonregex.Pattern::string("-")
let month = @moonregex.Pattern::string("\\d{2}").capture("month")
let date = year + dash + month

let m = date.prefix("2026-10").unwrap()
m.group(group=@moonregex.Name(n="month"))   // Some("10")

// `lower` hands the pattern to the core engine when it fits.
match date.lower() {
  Some(core) => core.execute("2026-10") is Some(_)   // true
  None => false
}
```

## Step limits

A backtracking engine can be talked into taking a very long time. Every call
carries a step ceiling — ten million by default, the number PCRE2 uses — and
raises `Exceeded(limit~, got~)` rather than hanging. `limit~` raises or lowers it
per call.

## Partial matching

With `partial=true`, a pattern that has matched everything it can but could go
on matching if the text continued answers a match with `Match::partial` set —
what a streaming parser needs to know that it should wait for more input.

## What it does not do

| Not implemented | Why |
|:--|:--|
| `re.LOCALE` | MoonBit has no locale; `re` itself only offers it for bytes and advises against it |
| `re.DEBUG` | the library does not print; `Pattern::dump` returns the tree as text instead |
| `re.purge` | there is no global pattern cache to clear |
| ECMA's `g`, `y`, `d` | they are ways of calling, not properties of a pattern: `g` is `findall`/`finditer`/`count=0`, `y` is `prefix(pos=)`, `d` is what `span` has always answered |
| `Match.detach_string`, `Match.regs` | strings are immutable here, and `spans` covers `regs` |

## Where it differs from the references

Everything else follows the reference implementations case by case, checked
against generated vectors. These are the places where a decision was taken
instead:

| Case | Here | The reference |
|:--|:--|:--|
| `match` | not offered; `prefix` is the same thing | `re.match`, soft-deprecated in 3.15 |
| Runaway patterns | `Exceeded` after ten million steps | no limit |
| `\N` without a name | any character but a newline | `re` refuses it; `regex` reads a literal `N` under V0 |
| `\v`, `\V` | the vertical tab under V0, the vertical-space class under V1 | `re` always means the tab |
| `\e`, `\Q…\E`, `\K` | accepted | `re` refuses them |
| `(?<name>…)` | accepted in the Python dialect too | `re` wants `(?P<name>…)` |
| `[[:alpha:]]` | a class escape in every dialect | `re` reads it as a set of characters |
| Refusal offsets | where reading stopped | Python's convention differs per error |
| A group repeated over an empty tail | keeps the captures of the empty turn (`(a*)*` leaves group 1 at the end) | ECMA-262 clears them |
| Astral characters | offsets count code points | ECMA-262 counts UTF-16 code units |
| Property names | Unicode loose matching in every dialect | ECMA-262 is case- and space-sensitive |
| A name used twice | allowed in the ECMA dialect anywhere | `re` refuses it; ECMA-262 only across alternatives |
| `v`-mode nested classes | `[[a-z]--[aeiou]]` is not read as a class expression | ECMA-262 reads them |

## Licence

Apache-2.0. See [LICENSE](LICENSE).
