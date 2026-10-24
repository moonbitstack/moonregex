# moonregex

Regular expressions for MoonBit — the interface Python's `re` gave everyone, the
[mrab-regex](https://github.com/mrabarnett/mrab-regex) superset behind it, and the
ECMA-262 dialect that JSON Schema and OpenAPI actually mean.

MoonBit's own `@string.Regex` is a different language, and deliberately so — core
states it is not ECMA-262 compliant by design and will not carry the Unicode
tables. Anything that has to agree with a JavaScript engine, or with Python, needs
this instead.

> **Status: implemented.** The full surface — `Pattern`/`Match`, the `re`-shaped
> module functions, the Python and ECMA-262 dialects, the `regex` superset and a
> `glob`/`fnmatch` layer — is in place, with tests running green on every target.

> **Homepage:** <https://moonbitstack.github.io/moonregex/> — generated API docs live
> under `/api`.

```moonbit
// The Python `re` surface, on every backend.
@moonregex.search(pattern, text)
@moonregex.match_at(pattern, text)
@moonregex.fullmatch(pattern, text)
@moonregex.findall(pattern, text)
@moonregex.finditer(pattern, text)
@moonregex.split(pattern, text)
@moonregex.sub(pattern, replacement, text)
@moonregex.subn(pattern, replacement, text)
```

The quickest way to see it work is `moon run examples/tour` — it runs the whole
tour end to end.

## Why a second regex

`@string.Regex` is fast and well suited to lexing, but it is its own grammar and
stops short of ECMA-262. Three callers keep turning up with three different
grammars, and the library makes the grammar a parameter rather than a fork:

| `dialect` | Who asks for it |
|:--|:--|
| `Python` (the preset) | Anyone reaching for a regex library and expecting `(?P<name>…)`, `\A`, `\Z` to mean what they mean everywhere else |
| `Ecma262` | JSON Schema's `pattern`, OpenAPI's `pattern` — both defined as ECMA-262 §22.2, and neither forgiving about it |
| `Lexmatch` | MoonBit's own `@string.Regex` spelling, for callers who already wrote it |

## Configuration, and its precedence

Every module function accepts the same four knobs, and they resolve in a fixed
order so the result is never ambiguous:

| Argument | What it sets | Default |
|:--|:--|:--|
| `dialect~` | the grammar — `Python`, `Ecma262` or `Lexmatch` | `Python` |
| `flags~` | the flag set (`Flags`) | `@moonregex.flags` |
| `lists?` | named lists for `\L<name>` | none |
| `partial~` | partial matching | `false` |

**Precedence, highest first:**

1. An argument passed at the call site — `search(pattern, text, flags=…)`.
2. The package defaults — `@moonregex.flags`, `@moonregex.dialect`.
3. The compiled `Pattern`, once `compile` has run.

`compile` bakes `dialect`, `flags`, `lists` and `partial` into the `Pattern`.
The `Pattern::` methods (`search`, `findall`, `sub`, …) then use those baked-in
settings and **ignore** any `flags~`/`dialect~` you pass to them — you configure
once, at compile time, and the match is reproducible. The module functions are a
convenience that compile on every call, so their arguments win over the defaults
but are still overridden by an explicit `compile`.

`Flags` is a record, so you toggle one bit without naming the rest:

```moonbit
// keep every default flag, flip on ignorecase
let rx = @moonregex.compile(r"[A-Z]+", flags=@moonregex.Flags::new(ignorecase=true))
```

## The dialects

| Dialect | Named groups | Lookbehind | Notes |
|:--|:--|:--|:--|
| `Python` | `(?P<name>…)` and `(?<name>…)` | variable-length, via the superset | the default; closest to CPython `re` |
| `Ecma262` | `(?<name>…)` and `(?'name'…)` | supported by the engine | the grammar JSON Schema and OpenAPI rely on |
| `Lexmatch` | `@string.Regex` spelling | as the lexer expects | for MoonBit-native patterns |

The grammar is lowered into one syntax tree, flags and all, so the engine never
asks which dialect a node came from — and the same pattern gives the same answer
on every target.

## Four targets, one answer

| Target | How |
|:--|:--|
| `js` | runs through the host where that is the natural fit for the dialect |
| `wasm`, `wasm-gc`, `native` | parse, lower, and run here |

**The same pattern returns the same match on all four.** That is what the shared
test set is for, and why the cases are not split per target.

## Packages

| Package | What it covers |
|:--|:--|
| `moonregex` | `Pattern` and `Match`, shaped as Python's `re`, plus the module functions |
| `parse` | the three grammars into one syntax tree, flags and all |
| `exec` | the backtracking engine — backreferences, lookaround, conditionals, recursion, fuzzy matching |
| `prop` | `\p{…}`: the Unicode property tables, generated, version recorded |
| `glob` | `fnmatch`, `Glob` and `GlobSet` — shell globbing on top of the engine |

## Shell globbing

The `glob` package turns shell patterns into regexes and lets the engine match
them, so the dialects and Unicode handling come for free:

```moonbit
// fnmatch: * and ? cross a separator, [..] is a class, {a,b} an alternation
@glob.fnmatch("cat.txt", "*.txt")          // true
@glob.filter(["a.txt", "b.csv"], "*.txt")  // ["a.txt"]

// Glob: * stops at a separator, ** crosses them, both / and \ are separators
let g = @glob.Glob::compile("src/**/*.mbt")
g.matches("src/parse/lex.mbt")             // true
g.matches("src/lex.mbt")                   // true  (** spans zero dirs too)
```

## Fuzzy matching

For a run of literals or character classes, `moonregex` performs approximate
matching with a bounded edit distance, spelled the way mrab-regex spells it:

```moonbit
// a total error budget of one (insertion, deletion or substitution)
@moonregex.fullmatch("(?:hello){e<=1}", "hellp")  // Some(_) — p -> o

// budgets can be scoped to one operation
@moonregex.fullmatch("(?:abc){i<=1}", "abcd")    // Some(_) — one insertion
@moonregex.fullmatch("(?:abc){d<=1}", "ab")      // Some(_) — one deletion
@moonregex.fullmatch("(?:abc){s<=1}", "abd")     // Some(_) — one substitution
```

The matcher consumes as much text as the budget allows, so an exact prefix still
wins when no edit is needed. A weighted budget (`2i+1d+1s<=3`) and fuzzy groups
whose inner node is not a literal or class run are matched exactly for now, and
the syntax is still accepted.

The spent budget is reported on the match: `fuzzy_counts` gives `(sub, ins, del)`
and `fuzzy_changes` the individual edits, so a caller can see exactly how a near
miss was aligned.

```moonbit
let m = @moonregex.search("(?:foo){e<=2}", "fox").unwrap()
m.fuzzy_counts()   // (1, 0, 0) — one substitution
```

## The full `regex` surface

Beyond the `re` functions above, `moonregex` carries the whole Python `regex`
module API so a port is drop-in:

```moonbit
// Named flag constants (lower-case; Python spells them upper-case).
@moonregex.compile("hello", flags=@moonregex.i)      // IGNORECASE
@moonregex.compile("^b",  flags=@moonregex.m)        // MULTILINE
@moonregex.compile("a.b", flags=@moonregex.s)        // DOTALL

// `Pattern` methods, plus `scanner` for incremental scanning.
let sc = @moonregex.compile(r"\d+").scanner("a1 b22")
sc.search()   // Some("1")
sc.search()   // Some("22")

// `Match` carries what Python's does.
let m = @moonregex.search(r"(?P<w>\w+) \1", "go go").unwrap()
m.pos()            // 0
m.endpos()         // 5
m.expand(r"\g<w>") // "go"
m.captures()       // [(0, 5)]
```

Type aliases `RegexFlag` and `RegexError` mirror `regex.RegexFlag` and
`regex.error`; `template` and `purge` are kept for compatibility. See
`docs/architecture.md` for the full interface contract.

## Examples

`examples/tour` is the canonical demo — `moon run examples/tour` exercises search,
groups, substitution, flags, the ECMA-262 dialect and the glob layer in one run.

## Install

```bash
moon add moonbitstack/moonregex
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
