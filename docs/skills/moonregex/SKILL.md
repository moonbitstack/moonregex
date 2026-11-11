---
name: moonregex
description: "Match, extract and replace text in MoonBit with moonbitstack/moonregex: Python's re interface plus the regex superset, the ECMA-262 grammar that JSON Schema and OpenAPI patterns are written in, and the core library's lexmatch grammar, with Unicode properties. Use when a pattern has to be compiled and run, when a schema or JavaScript pattern has to be read as ECMA-262, or when a lexer's pattern has to be read as MoonBit spells it."
---

# moonregex

```bash
moon add moonbitstack/moonregex
```

```moonbit
// moon.pkg
import {
  "moonbitstack/moonregex",      // Pattern, Match, the module functions
  "moonbitstack/moonregex/glob", // fnmatch, Glob, GlobSet
}
```

The module functions compile the pattern on every call; `compile` once and use
the `Pattern` methods in a loop or a hot path.

## Anchor the match where you mean it

`search` takes the leftmost match anywhere, `prefix` only at the position the
scan starts, `full` only when the match covers the whole region. There is no
`match` — it is `prefix`.

```moonbit
fn anchors(text : String) -> Unit raise {
  let word = @moonregex.compile("[a-z]+")
  let anywhere = word.search(text).unwrap() // leftmost, wherever it starts
  let only_at_start = word.prefix(text)     // None when text starts otherwise
  let whole = word.full(text)               // None unless the match is all of it
  println("\{anywhere.start(0)} \{only_at_start is Some(_)} \{whole is Some(_)}")
}
```

## Take the group you want

`findall` answers the whole match when the pattern has no groups and the single
group when it has one. With two or more it refuses — Python answers a tuple
there — so pass `group` or walk `finditer`. A group is addressed by number or by
name, and the key is never optional.

```moonbit
fn pairs(text : String) -> Array[String?] raise {
  let p = @moonregex.compile("(?<key>\\w+)=(?<value>\\d+)")
  // `findall` would raise Ambiguous(groups=2) here; name the group instead.
  let keys = p.findall(text, group=Num(n=1))
  for m in p.finditer(text) {
    let value = m.group("value") // Some("1"); `default` fills one that took none
    println("\{m.span("key")} \{value}")
  }
  keys
}
```

## Read someone else's pattern in its own grammar

The dialect is a parameter, not a fork: Python (the default), `Ecma262` for a
JSON Schema or OpenAPI `pattern`, and `Lexmatch` for a pattern written for the
core library's `@string.Regex` or the lexer. The same pattern in the wrong
grammar compiles and answers differently, which is why the choice is explicit.
`Lexmatch` also reads `\d`, `\w`, `\s` and `(?<name>…)` the way Python does, so
a pattern moves between the two grammars unchanged.

```moonbit
fn schema_pattern(pattern : String, value : String) -> Bool raise {
  let p = @moonregex.compile(pattern, dialect=@moonregex.ecma262)
  p.full(value) is Some(_)
}

fn lexer_values(pattern : String, text : String) -> Array[String?] raise {
  // The core grammar leaves `\d` out; here it means what Python means by it.
  let p = @moonregex.compile(pattern, dialect=@moonregex.lexmatch_dialect)
  p.findall(text, group=Name(n="value"))
}
```

## Things that catch people out

- Offsets count code points, not UTF-16 units: `span`, `start` and `end` differ
  from ECMA-262's `index` past the BMP.
- `findall` returns `Array[String?]`, not `Array[String]`: a group that took no
  part is `None`.
- Every call carries a step ceiling of ten million (`limit`), and past it raises
  `Exceeded(limit~, got~)` instead of hanging. Lower it when a pattern is known
  to be cheap and the input is not trusted.
- `Pattern::string` is literal — `Pattern::string("\\d")` matches a backslash and
  a `d`. Compile the pattern when it is meant as syntax.
- `partial=true` answers a match the text cut short, with `Match::partial` set;
  without it the same text is no match at all.
- `\w` and `\d` are ASCII under `Ecma262` and Unicode under `Python`; `\A`, `\Z`
  and `$`-before-a-final-newline exist only in `Python`. Under `Lexmatch` they
  are the Python ones.
- A backreference takes its case from where it is written, not from the group it
  names: `(?i)(?-i:(a))\1` compares caselessly, `(?i:(a))\1` does not. The
  comparison folds over every script, so `(?i)(é)\1` matches `éÉ`.
- `i` folds one code point against one. `f` — `fullcase`, on under `V1` and asked
  for with `(?fi)` — folds across lengths: `(?fi)ß` matches `SS` and `ss`, and
  `(?fi)ss` matches `ß`. A class written character by character folds the same
  way; a range and a negated class stay one code point at a time.
- A pattern is cached nowhere: `findall(pattern, text)` recompiles each call.
