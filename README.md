<div align="center">

# moonregex

**Regular expressions for MoonBit** — Python's `re` interface, the `regex` superset
behind it, and the ECMA-262 grammar that JSON Schema and OpenAPI mean.

[Homepage](https://moonbitstack.github.io/moonregex/) ·
[Guide](https://moonbitstack.github.io/moonregex/guide.html) ·
[Showcase](https://moonbitstack.github.io/moonregex/showcase.html) ·
[API](https://moonbitstack.github.io/moonregex/api.html) ·
[Mooncakes](https://mooncakes.io/docs/moonbitstack/moonregex)

</div>

The [showcase](https://moonbitstack.github.io/moonregex/showcase.html) runs this
library in the browser: `src/examples/browser` compiles to `docs/assets/moonregex_web.js`
with `python scripts/build_web.py`, and the page feeds your pattern, flags and
text through it. Nothing there is re-implemented in JavaScript.

```moonbit
let year = @moonregex.search("\\d{4}", "copyright 2026").unwrap()
assert_eq(year.content(), "2026")
assert_eq(year.start(0), 10)
assert_eq(@moonregex.sub("\\s+", " ", "a   b  c"), "a b c")
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

```moonbit
let word = @moonregex.compile("[a-z]+")
assert_true(word.search("  hello ") is Some(_))
assert_true(word.prefix("  hello ") is None)
assert_true(word.full("hello") is Some(_))
assert_eq(word.search("  hello ").unwrap().start(0), 2)
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
`span`, `captures`, `starts`, `ends`, `spans`, `capturesdict`,
`allcaptures`, `allspans`, `expand`, `expandf`, `pos`, `endpos`, `lastindex`,
`lastgroup`, `re`, `string`, `content`, `before`, `after`, `fuzzy_counts`,
`fuzzy_changes`, `marks` and `partial`.

A group is addressed by number or by name — `trait GroupKey` is implemented by
`Int` and by `String`, so `m.group(1)` and `m.group("year")` both work. There is
no default: `m.start(0)` says "the whole match" the way `m.group(0)` does.

The singular forms answer the last capture a group made, the plural forms answer
all of them — in one list, because this engine keeps one span per group:
`captures` gives the text, `spans` the offsets, `starts` and `ends` the ends of
those offsets.

### Groups, and the one place a list cannot answer

`findall` collects the whole match when the pattern has no groups, the single
group when it has one — and refuses when it has two or more, because Python
answers a tuple there and a statically typed list cannot. Pass `group` to say
which one, or walk `finditer` for matches that carry them all.

```moonbit
let ambiguous = try {
  let _ = @moonregex.findall("(\\w+)=(\\d+)", "a=1")
  0
} catch {
  @moonregex.Refused::Ambiguous(groups~) => groups
  e => raise e
}
assert_eq(ambiguous, 2)
assert_eq(@moonregex.findall("(\\w+)=(\\d+)", "a=1", group=Num(n=1)), [Some("a")])
```

### Flags

`Flags` is a record, not a bitmask: `Flags::new(ignorecase=true)` sets one
switch and leaves the rest, and `@moonregex.flags` is all of them off.

`ignorecase`, `multiline`, `dotall`, `verbose`, `ascii`, `unicode`,
`unicode_sets`, `fullcase`, `bestmatch`, `enhancematch`, `posix`, `reverse`,
`word`, and `version` (`V0` / `V1`). `fullcase` is on under `V1`, which is the
behaviour set that defines it; `(?-f:…)` is how a pattern gives it up.

The common ones also have their inline spelling — `(?i)`, `(?m)`, `(?s)`,
`(?x)`, `(?a)` and the scoped `(?i:…)` — which needs no flag argument at all.

### Case, and where it comes from

`(?i:…)` scopes a flag to one group, `(?-i:…)` takes it away again, so a
pattern can be case-insensitive in one place and exact in another. A group is
read under the flags around the group; a backreference is compared under the
flags around the reference — the place it is written. The two may disagree, and
the reference decides.

```moonbit
// The group is exact and the reference is not.
let outer = @moonregex.compile("(?i)(?-i:(a))\\1")
assert_eq(outer.search("aA").unwrap().content(), "aA")

// The group is caseless and the reference is exact: `aA` is no match.
let inner = @moonregex.compile("(?i:(a))\\1")
assert_true(inner.full("AA") is Some(_))
assert_true(inner.full("aA") is None)
```

The comparison runs one code point at a time and folds it, over every script
rather than ASCII alone: `é` and `É` are one letter here, and so are `k` and the
Kelvin sign `K`. A reference to a group that captured nothing is no match.

### Folding across lengths

`f` — `fullcase` — is the rest of the fold: a few characters have a folded form
longer than themselves, and then "the same text" is a comparison of folded
strings rather than of characters. `ß` folds to `ss`, `ﬁ` to `fi`, `ﬅ` to `st`.

```moonbit
let sharp = @moonregex.compile("(?fi)ß")
assert_eq(sharp.full("SS").unwrap().span(0), (0, 2))
assert_eq(sharp.full("ẞ").unwrap().span(0), (0, 1))

// The other direction too: a run of letters matches the one character.
assert_eq(@moonregex.compile("(?fi)ss").full("ß").unwrap().span(0), (0, 1))

// A class, a reference and a quantifier all fold the same way.
assert_eq(@moonregex.compile("(?fi)[ß]").full("ss").unwrap().span(0), (0, 2))
assert_eq(@moonregex.compile("(?fi)(ß)\\1").full("ssSS").unwrap().span(0), (
  0, 4,
))
```

`V1` turns it on, as the behaviour set it belongs to; `(?fi)` asks for it in the
default one. Without `i` it does nothing, and with `a` it does nothing either,
because ASCII has no characters that fold to two.

Only the characters written one at a time grow a longer reading: `[ß]` matches
`ss`, while `[a-ß]` — a range — matches one code point at a time, and so does a
negated class.

One code point is folded differently from what the references do — `İ`, which
Unicode folds to `i` and a combining dot and they fold to a lone `i`. The
difference table below says what that changes and why it is the reading here.

### Escape

`escape` follows the grammar it is told to follow, because the three do not
agree on what is special:

| Dialect | `escape("a.b")` | rule |
|:--|:--|:--|
| `Python` | `a\.b` | `re.escape`: the characters that can mean something take a backslash |
| `Ecma262` | `\x61\.b` | `RegExp.escape`: punctuation is spelled in hex, and a leading alphanumeric too |
| `Lexmatch` | `a\.b` | the `@string.Regex` metacharacters, with `\u{…}` for the invisible ones |

```moonbit
assert_eq(@moonregex.escape("a.b"), "a\\.b")
assert_eq(@moonregex.escape("a.b", dialect=@moonregex.ecma262), "\\x61\\.b")
assert_eq(@moonregex.escape("a.b", dialect=@moonregex.lexmatch_dialect), "a\\.b")
```

## The three grammars

```moonbit
// Python: named group, `\A`, backreference — the default.
assert_eq(@moonregex.findall("(?P<w>\\w+)\\s+\\1", "go go no"), [Some("go")])

// ECMA-262: what a JSON Schema `pattern` means.
let schema = @moonregex.compile("^[a-z]+$", dialect=@moonregex.ecma262)
assert_true(schema.full("abc") is Some(_))
assert_true(schema.full("ABC") is None)

// lexmatch: a pattern already written for the core library.
let posix = @moonregex.compile("[[:digit:]]+", dialect=@moonregex.lexmatch_dialect)
assert_eq(posix.findall("a12b3"), [Some("12"), Some("3")])

// It reads the shorthand classes and named captures too.
let tag = @moonregex.compile("(?<k>\\w+)=(?<v>\\d+)", dialect=@moonregex.lexmatch_dialect)
assert_eq(tag.search("size=42").unwrap().group("v"), Some("42"))
```

Choose by where the pattern comes from. A pattern a person wrote for text
processing is `Python`; a pattern from a schema, a form, or a JavaScript
codebase is `Ecma262`; a pattern from a MoonBit lexer is `Lexmatch`.

`Lexmatch` is the core grammar plus the two things a lexer usually wants and
that grammar leaves out: `\d`, `\w`, `\s` and their negations are read the way
Python reads them, and `(?<name>…)` captures under a name. A pattern therefore
keeps its meaning when it moves between `Python` and `Lexmatch`, and one that
uses them still lowers onto the core engine — the classes are written out as
the ranges they stand for.

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

```moonbit
let date = @moonregex.compile("\\d{4}").capture("year") +
  @moonregex.compile("-") +
  @moonregex.compile("\\d{2}").capture("month")
let stamp = date.prefix("2026-10").unwrap()
assert_eq(stamp.group("month"), Some("10"))
assert_true(date.lower() is Some(_))

// `lower` hands the pattern to the core engine when it fits.
assert_true(@moonregex.compile("(a)\\1").lower() is None)
```

## Step limits

A backtracking engine can be talked into taking a very long time. Every call
carries a step ceiling — ten million by default, the number PCRE2 uses — and
raises `Exceeded(limit~, got~)` rather than hanging. `limit~` raises or lowers it
per call.

```moonbit
let runaway = try {
  let _ = @moonregex.full("(a+)+b", "aaaaaaaaaaaaaaaaaaaa", limit=100)
  "no error"
} catch {
  @moonregex.Refused::Exceeded(limit~, got~) => "stopped at \{limit} of \{got} steps"
  e => raise e
}
assert_eq(runaway, "stopped at 100 of 101 steps")
```

## Partial matching

With `partial=true`, a pattern that has matched everything it can but could go
on matching if the text continued answers a match with `Match::partial` set —
what a streaming parser needs to know that it should wait for more input. The
span is the text that arrived, so nothing is invented: `\d{4}-\d{2}` against
`2026-` answers `2026-`, flagged.

```moonbit
let stream = @moonregex.compile("\\d{4}-\\d{2}", partial=true)
let cut = stream.prefix("2026-").unwrap()
assert_eq(cut.content(), "2026-")
assert_true(cut.partial())
assert_true(stream.prefix("2026-10").unwrap().partial() is false)
```

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
| Caseless comparison | Unicode simple case folding, backreferences and literals alike | `re` lowercases, so `(?i)(σ)\1` does not match `σς` there; the `regex` package folds |
| U+0130's fold | `i` and a combining dot: `(?fi)İ` matches `i̇`, and `(?i)İ` matches `İ` alone | `re` and the `regex` package fold it to a plain `i`, which is a different text: there `(?i)İ` matches `i`, and `(?fi)İ` answers only the `i` of `i̇` |
| `\d`, `\w`, `\s` under `Lexmatch` | read as Python reads them | the core grammar has the POSIX classes only |
| `v`-mode nested classes | `[[a-z]--[aeiou]]` is not read as a class expression | ECMA-262 reads them |
| Repeated captures | one span per group: `captures` and `spans` answer the last turn | `regex` lists every turn |

## Licence

Apache-2.0. See [LICENSE](LICENSE).
