# moonregex

Regular expressions, with the interface Python's `re` gave everyone.

> **Status: planned.** The repository is set up; nothing is
> implemented yet.

```moonbit
@moonregex.search(pattern, text)
@moonregex.findall(pattern, text)
@moonregex.sub(pattern, replacement, text)
let rx = @moonregex.compile(pattern, flags=IgnoreCase | Multiline)
```

MoonBit's own `@string.Regex` is a different language, and deliberately so —
core states it is not ECMA-262 compliant by design and will not carry Unicode
tables. Anything that has to agree with a JavaScript engine, or with Python,
needs this instead.

## Two dialects, one interface

The API is Python's. The grammar is a parameter, because the two callers who
need this need different ones:

| `dialect` | Who asks for it |
|:--|:--|
| `Python` (the preset) | Anyone reaching for a regex library and expecting `(?P<name>…)`, `\A`, `\Z` to mean what they mean everywhere else |
| `Ecma262` | JSON Schema's `pattern`, OpenAPI's `pattern` — both defined as ECMA-262 §22.2, and neither forgiving about it |

## Three targets, one answer

| Target | How |
|:--|:--|
| `js` | The host's own `RegExp`, for the ECMA-262 dialect. It is that grammar by definition, and faster than anything written here |
| `wasm`, `wasm-gc`, `native` | Parse, lower what `@string.Regex` can carry, run the rest here |

**The same pattern gives the same answer on all four.** That is what the tests
are for, and why the case set is shared rather than split per target.

| Package | What it covers |
|:--|:--|
| `parse` | Both grammars, into one syntax tree |
| `lower` | What `@string.Regex` can be made to do, in its own spelling |
| `exec` | What it cannot: backreferences, lookaround, conditionals |
| `prop` | `\p{…}`: the Unicode property tables, generated, version recorded |
| `api` | `Pattern` and `Match`, shaped as Python's |

## Install

```bash
moon add moonbitstack/moonregex
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
