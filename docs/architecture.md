# moonregex — Architecture & Interface Contract

This document is the up-front design for moonregex. It is the contract the
implementation is held to, not a description written after the fact. It states:

1. the **layered architecture** and how the packages link;
2. the **public interface surface** (module functions, `Pattern`, `Match`,
   `Scanner`, flags, errors) mapped onto the Python `regex` (mrab-regex)
   library;
3. the **internal pipeline** (`parse → ast → compile → exec`) and the data
   that flows between stages;
4. a **feature-completeness matrix** for the `regex` superset syntax.

The governing rule is *one coherent surface, not bolted-on extras*: every
capability is exposed through the same `Pattern`/`Match`/`Scanner` objects a
Python caller already knows, and the dialects (`re`, ECMA-262, lexmatch) are a
single parameter, not separate code paths.

---

## 1. Layered architecture

```
            ┌─────────────────────────────────────────────┐
            │  moonregex  (root package — public API)       │
            │  module fns · Pattern · Match · Scanner ·     │
            │  Flags · Dialect · Refused · escape · purge   │
            └───────┬───────────────┬───────────────┬──────┘
                    │               │               │
          ┌─────────▼──┐   ┌────────▼────────┐  ┌───▼───────┐
          │   parse    │   │     exec        │  │   glob     │
          │ grammar,   │   │ compiler + VM   │  │ fnmatch,   │
          │ AST, flags,│   │ (backtracking)  │  │ Glob,      │
          │ dialects   │   │                 │  │ translate  │
          └─────┬──────┘   └────────┬────────┘  └────────────┘
                │                   │
                │           ┌───────▼───────┐
                └──────────►│     prop      │
                            │ Unicode       │
                            │ properties,   │
                            │ \p{…}, \w…    │
                            └───────────────┘

  bin/        command-line driver (reads a pattern + text, prints matches)
  examples/   worked examples, referenced by the docs
  scripts/    build / doc-generation helpers
  docs/       homepage (index.html) + this contract
```

**Linkage rules (who may call whom):**

- `moonregex` (root) is the only package a caller imports. It depends on
  `parse` and `exec`. It never reaches into `prop` directly; `parse` does.
- `parse` depends on `prop` for character-class and Unicode-property
  semantics (`\p{…}`, `\w`, `\d`, `\s`, `\b`, full-case folding). It is
  grammar-only: it produces an `Ast`, it never runs anything.
- `exec` is a pure function of an `Ast`: `compile(ast) → Program`, and
  `Program.search/match_at/fullmatch` drive a backtracking VM. It depends on
  `parse` for the node and error types, not for parsing.
- `prop` has no upward dependency; it is a leaf (Unicode data + queries).
- `glob` is an independent facade over the same engine, expressing
  `fnmatch`/`Glob` path semantics through the regex compiler with a small
  `translate` layer. It does not leak glob syntax into `parse`.

This is a strict DAG: no cycles, no back-edges. That is what keeps the
engine from becoming a "shit mountain" — each layer has one job and one
consumer contract.

---

## 2. Public interface surface

### 2.1 Module functions (Python `regex` / `re`)

Every module function compiles (memoised in the caller's `Pattern` when
reused) and runs. They are the thin, stateless front door; `Pattern` is the
stateful object behind them.

| `regex`                         | moonregex                          | notes |
|---------------------------------|------------------------------------|-------|
| `compile(pat, flags=0)`         | `compile(pat, flags~, dialect~, lists~, partial~)` | also takes dialect, named lists, partial |
| `search(pat, s, …)`             | `search(pat, s, …)`                | `pos~`, `endpos~`, `limit~` added |
| `match(pat, s, …)`              | `match_at(pat, s, …)`              | named `match_at` to avoid MoonBit keyword |
| `fullmatch(pat, s, …)`          | `fullmatch(pat, s, …)`             | |
| `findall(pat, s, …)`            | `findall(pat, s, group~, …)`       | `group~` resolves the 2+-group ambiguity at the call site |
| `finditer(pat, s, …)`           | `finditer(pat, s, …)`              | |
| `split(pat, s, maxsplit=0, …)`  | `split(pat, s, maxsplit~, …)`      | |
| `sub(pat, repl, s, count=0, …)` | `sub(pat, repl, s, count~, …)`     | `repl` may be a `String` template |
| `subn(pat, repl, s, …)`         | `subn(pat, repl, s, …)`            | returns `(String, Int32)` |
| `sub(pat, f, s)` (callable)     | `sub_by(pat, f, s, …)`             | `f : Match -> String` |
| `subn(pat, f, s)` (callable)    | `subn_by(pat, f, s, …)`            | |
| `subf(pat, tmpl, s, …)`         | `subf(pat, tmpl, s, …)`            | `str.format`-shaped template, `{}`/`{0}`/`{name}`/`{0[0]}` |
| `subfn(pat, tmpl, s, …)`        | `subfn(pat, tmpl, s, …)`           | returns `(String, Int32)` |
| `escape(s, special_only, literal_spaces)` | `escape(s, special_only~, literal_spaces~)` | |
| `purge()`                       | `purge()`                           | clears the compile cache |
| `error`                         | `RegexError` (= `Refused`)          | the exception type (upper-case in MoonBit) |
| `RegexFlag` / `re.RegexFlag`    | `RegexFlag` (= `Flags`)             | the flags type |
| `DEFAULT_VERSION`               | `default_version`                   | `V0` |
| `__version__`                   | `version`                           | `"0.1.0"` |
| `__version_info__`              | `version_info`                      | `(0, 1, 0)` |

`findall` with a callable replacement does not exist in `re`; moonregex
exposes `sub_by`/`subn_by` instead of overloading `sub`'s type. The named
flags (`I`/`IGNORECASE`, `M`, `S`, …) are lower-case `let` bindings — `i`,
`ignorecase`, `m`, `multiline`, … — because MoonBit requires upper-case
constants to be primitive.

### 2.2 `Pattern`

`Pattern` is a compiled, reusable object: the tree (`Ast`), the flat program
(`Program`), the source, the flags, the dialect, and whether it was built for
partial matching.

| `regex.Pattern`            | moonregex                      |
|----------------------------|--------------------------------|
| `p.pattern`                | `p.pattern()`                  |
| `p.flags`                  | `p.flags()`                    |
| `p.groups`                 | `p.groups()`                   |
| `p.groupindex`             | `p.groupindex()`               |
| `p.scanner(s)`             | `p.scanner(s)` → `Scanner`     |
| `p.match / fullmatch / search / findall / finditer / split / sub / subn` | same, with `pos~/endpos~/limit~` |
| `p.subf(s, tmpl)` / `p.subfn` | `p.subf(s, tmpl)` / `p.subfn(s, tmpl)` | format substitution (§4) |

### 2.3 `Match`

`Match` carries the matched `Pattern`, the subject `String`, and a
`MatchResult` (one span per group, plus fuzzy counts when applicable).

| `regex.Match`            | moonregex                         |
|--------------------------|-----------------------------------|
| `m.group([g])`           | `m.group(group~)` (`GroupKey`)    |
| `m.groups(default=None)` | `m.groups(default~)`              |
| `m.groupdict(default)`   | `m.groupdict(default~)`           |
| `m.start([g])` / `m.end([g])` | `m.start(group~)` / `m.end(group~)` |
| `m.span([g])`            | `m.span(group~)`                  |
| `m.expand(tmpl)`         | `m.expand(tmpl)`                  |
| `m.captures(g)`          | `m.captures(group~)`              |
| `m.capturesdict()`       | `m.capturesdict()`               |
| `m.slices([g])`          | `m.slices(group~)`                |
| `m.pos` / `m.endpos`     | `m.pos()` / `m.endpos()`          |
| `m.lastindex` / `m.lastgroup` | `m.lastindex()` / `m.lastgroup()` |
| `m.string`               | `m.string()`                      |
| `m.re`                   | `m.re()` (= `m.pattern()`)        |
| `m.partial`              | `m.partial()`                      |
| `m.fuzzy_counts`         | `m.fuzzy_counts()` → `(sub,ins,del)` |
| `m.fuzzy_changes`        | `m.fuzzy_changes()` → `(subs,ins,dels)` |

`GroupKey` unifies Python's three ways of naming a group — `Whole`, `Num(n)`,
`Name(n)` — so one `group~` argument serves `m.group()`, `m.start()`, etc.

### 2.4 `Scanner`

A `Scanner` binds a `Pattern` to a subject `String` once; its methods take no
text argument and resume where the previous call left off. This is the
`mrab` streaming idiom, and it reuses the same `search`/`finditer` machinery
internally.

| `regex.Scanner`     | moonregex                    |
|---------------------|------------------------------|
| `s.match()`         | `s.match()`                  |
| `s.fullmatch()`     | `s.fullmatch()`              |
| `s.search()`        | `s.search()`                 |
| `s.findall()`       | `s.findall(group~)`          |
| `s.finditer()`      | `s.finditer()`               |
| `s.split()`         | `s.split(maxsplit~)`         |
| `s.sub(repl)`       | `s.sub(repl)`                |
| `s.subn(repl)`      | `s.subn(repl)`               |

### 2.5 Flags, dialects, versions

`Flags` is a **record**, deliberately not a bitmask: `(?a)` inside a scoped
group changes `\w` for that group alone, and a record can be asked about and
resolved per-node, whereas a bitmask cannot. Flags are baked into the `Ast`
at parse time (e.g. `(?s:.)`), so the VM never re-consults them. Named
constants (`I`, `IGNORECASE`, `M`, `S`, `X`, `A`, `U`, `F`, `W`, `T`,
`BESTMATCH`, `ENHANCEMATCH`, `REVERSE`, `POSIX`, `V0`, `V1`, …) are pure
`Flags` literals, so `regex.I | regex.M` is `Flags::{ ignorecase: true,
multiline: true, ..flags }`.

`Dialect` selects the grammar (`Python`, `Ecma262`, `Lexmatch`); `Version`
(`V0`, `V1`) selects the `regex` behaviour set under the Python dialect
(`V1` opens set algebra `--`, `&&`, `~~` and nested sets).

### 2.6 Errors

`Refused` is the single error type, with four variants:
`Pattern(msg, at, line, column)` (the grammar could not read the pattern),
`Exceeded(limit, got)` (the step ceiling was hit), `Ambiguous(groups)`
(`findall` with several unnamed groups), and `Accept(start, end)` (the
`(*ACCEPT)` verb — an internal control flow, surfaced only through `search`).
`error` is an alias of `Refused` for drop-in `regex` callers.

---

## 3. Internal pipeline

```
pattern: StringView
   │  parse::parse(pattern, flags, dialect, lists)   → Ast        (grammar, dialects, scopes)
   ▼
Ast  (Node tree: Group, Repeat, Char, Class, Backref, Lookaround, Cond,
      Recurse, Verb, FuzzyLit, …)  + groupindex + groups count
   │  exec::compile(ast)                              → Program   (flatten to Inst[])
   ▼
Program { code: Inst[], ngroups, group_codes, extra }  (backtracking VM instructions)
   │  Program::search / match_at / fullmatch (pos, endpos, limit)
   ▼
MatchResult { start, end, spans[ngroups+1], fuzzy?, pos, endpos }
   │  wrapped by Pattern into Match(text, result)
   ▼
Match (group/start/end/span/groups/groupdict/expand/captures/…)
```

Key invariants that keep the layers honest:

- **Code-point offsets everywhere.** MoonBit `String` is UTF-16; the engine
  reports positions in *code points* and `Match` slices back by code points.
  `start`/`end`/`span` read exactly as Python's do, for astral characters too.
- **Span = `(Int32, Int32)`.** `(-1, -1)` means "group did not participate".
  `Match.groups(default)` and `groupdict` fill those with `None`/`default`.
- **The VM is the only runner.** `search`, `match_at`, `fullmatch` differ
  only by their entry/accept conditions; `finditer`/`findall`/`split`/`sub`
  are loops over `search`. One engine, many surfaces.
- **Recursion and verbs are instructions, not special cases.** `(?R)`,
  `(?P>name)` and `(*ACCEPT)`/`(*FAIL)` compile to `RecurseWhole` /
  `RecurseGroup` / `Accept` / `Fail`; the VM handles them uniformly, which is
  why the `(*VERB)` and `(?P>name)` parsing bugs could be fixed in the
  grammar alone.

---

## 4. Feature-completeness matrix (regex superset syntax)

| Feature (mrab)                         | Status | Where |
|----------------------------------------|--------|-------|
| Literals, `.`, `^`, `$`, `[…]`         | ✅ | parse + exec |
| `*` `+` `?` `{m,n}`, lazy `*?`         | ✅ | parse + exec |
| Capturing `(…)`, `(?:…)`, named `(?P<name>…)` | ✅ | parse + exec |
| Backreferences `\1`, `\g<name>`        | ✅ | parse + exec |
| Lookaround `(?=…)` `(?!…)` `(?<=…)` `(?<!…)` | ✅ | parse + exec |
| Conditionals `(?(id)…\|…)`             | ✅ | parse + exec |
| Atomic groups `(?>…)`, possessive `*+` | ✅ | parse + exec |
| Unicode properties `\p{…}`, `\P{…}`    | ✅ | prop + parse |
| Inline flags `(?i)`, scoped `(?i:…)`   | ✅ | parse |
| `VERBOSE` `x`, `DOTALL` `s`, `MULTILINE` `m`, `ASCII` `a`, `IGNORECASE` `i` | ✅ | flags |
| `FULLCASE` `f`, `WORD` `w` (`\m \M`)   | ✅ | flags + parse |
| `POSIX` `p`, `REVERSE` `r`, `BESTMATCH` `b`, `ENHANCEMATCH` `e` | ✅ | flags + exec |
| Control verbs `(*ACCEPT)` `(*FAIL)` `(*COMMIT)` `(*MARK)` `(*PRUNE)` `(*SKIP)` `(*THEN)` `(*LIMIT_MATCH)` `(*LIMIT_RECURSION)` `(*VERSION)` `(*FENCE)` | ✅ | parse + exec |
| Recursion `(?R)`, `(?1)`, `(?P>name)`, `(?&name)` | ✅ | parse + exec |
| Recursion conditions `(?(R))`, `(?(R1))`, `(?(R&name))` | ✅ | parse + exec |
| `(?\|…)` branch reset, `(?(DEFINE)…)`    | ✅ | parse + exec |
| `\Q…\E` literal quoting                | ✅ | parse |
| `\R` `\h` `\H` `\v` `\V` `\N` `\e`     | ✅ | parse + exec |
| `\N{name}` named character             | ✅ (full table + algorithmic CJK/Tangut/Hangul) | prop + parse |
| Backreferences `\g{name}` `\g{n}` `\g{-1}` | ✅ | parse + exec |
| Fuzzy `{e}`/`{i}`/`{d}`/`{s}` + counts/changes | ✅ counts · ✅ changes | exec |
| Set algebra `--` `&&` `~~` (V1)        | ✅ | parse |
| `subf`/`subfn` format substitution     | ✅ (`{}` `{0}` `{name}` `{0[0]}` + `:spec` align/width/precision; types `s d x X o b`) | subf.mbt |
| `Match.marks()` — `(*MARK:name)` names | ✅ | match.mbt |

The completion pass closed every gap in `docs/gaps.md`; unknown control verbs
are still refused with a position rather than ignored, but nothing is deferred
any more.

---

## 5. Design principles (the "no shit mountain" rules)

1. **One surface.** Every capability is reached through `Pattern`/`Match`/
   `Scanner`. There is no second, parallel API to keep in sync.
2. **Dialects are a parameter, not a fork.** `re`, ECMA-262 and lexmatch share
   the same node types and VM; only the grammar front-end differs.
3. **Flags resolve at parse time.** By the time the VM runs, behaviour is in
   the tree, so the executor stays small and predictable.
4. **Code-point correctness is non-negotiable.** Offsets and slices are in
   code points, so astral and combining characters behave as Python's `re`
   does.
5. **Refuse loudly, never silently.** An unknown verb, an unbalanced group, or
   an over-budget fuzzy match is an error with a position, not a silent
   `None` or a dropped feature.
6. **A strict DAG, no cycles.** `root → {parse, exec}`, `parse → prop`,
   `glob → exec`. Dependencies point one way, so each layer has one job.
