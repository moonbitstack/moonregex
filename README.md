# moonre

The regular expressions JavaScript means, which is what JSON Schema and OpenAPI
mean too.

> **Status: planned.** The repository is set up; nothing is
> implemented yet.

MoonBit's own `@string.Regex` is a different language, and deliberately so —
core states that it is not ECMA-262 compliant by design and will not carry
Unicode tables. Anything that has to agree with a JavaScript engine therefore
needs this, and the answer is the same whichever library asked: JSON Schema's
`pattern`, OpenAPI's `pattern`, a route matcher, a config field.

## Three targets, three routes to the same answer

| Target | How |
|:--|:--|
| `js` | The host's own `RegExp`. It is ECMA-262 by definition and faster than anything written here |
| `wasm`, `wasm-gc`, `native` | Parse the pattern, lower what can be lowered onto `@string.Regex`, and run the rest here |

The same pattern must give the same answer on all four. That is the point of the
library and the thing its tests exist to hold.

| Package | What it covers |
|:--|:--|
| `parse` | ECMA-262 §22.2's grammar, into a syntax tree |
| `lower` | What `@string.Regex` can be made to do, expressed in its spelling |
| `exec` | What it cannot: backreferences, lookaround, and the rest |
| `prop` | `\p{…}`: the Unicode property tables, generated, with the version recorded |

## Install

```bash
moon add moonbitstack/moonre
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
