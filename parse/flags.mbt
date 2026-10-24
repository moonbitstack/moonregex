// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which grammar a pattern is written in.
///
/// The interface is the same whichever is chosen; the grammar is a parameter
/// because the callers need different ones. JSON Schema's `pattern` and
/// OpenAPI's `pattern` are defined as ECMA-262 §22.2 and are unforgiving
/// about it, while everyone else writes Python's.
pub(all) enum Dialect {
  /// Python's `re` and the `regex` superset behind it.
  Python
  /// ECMA-262's `RegExp`, as a JavaScript engine reads it.
  Ecma262
  /// The `lexmatch` literal MoonBit's own `@string.Regex` speaks.
  Lexmatch
} derive(Eq, Debug)

///|
pub extend Dialect with Eq::{equal, not_equal}

///|
pub extend Dialect with Debug::{to_repr}

///|
pub extend Dialect with Show::{output, to_string}

///|
pub impl Show for Dialect with fn output(self, logger) {
  logger.write_string(
    match self {
      Python => "Python"
      Ecma262 => "Ecma262"
      Lexmatch => "Lexmatch"
    },
  )
}

///|
/// Which `regex`-module behaviour set a Python pattern is read under.
///
/// `V0` is `re` as everyone writes it; `V1` opens the set algebra (`--`, `&&`,
/// `~~`, nested sets) and the rest of what `(?V1)` unlocks. Only the Python
/// dialect has versions — ECMA-262 gates the same algebra behind its `v` flag.
pub(all) enum Version {
  V0
  V1
} derive(Eq, Debug)

///|
pub extend Version with Eq::{equal, not_equal}

///|
pub extend Version with Debug::{to_repr}

///|
/// The switches a pattern can carry.
///
/// A record rather than a bitmask, because every one of these is a thing a
/// reader may want to look at, set, or refuse — `(?a)` inside a scoped group
/// changes what `\w` means for that group alone, and a bitmask cannot be
/// asked about politely.
///
/// Flags are resolved into the syntax tree at parse time: `(?s:.)` puts the
/// dotall behaviour inside the node, so the executor never consults them.
pub(all) struct Flags {
  /// `i` — case-insensitive matching.
  ignorecase : Bool
  /// `m` — `^` and `$` match at line boundaries.
  multiline : Bool
  /// `s` — `.` matches a newline.
  dotall : Bool
  /// `x` — whitespace and `#` comments in the pattern are not literals.
  verbose : Bool
  /// `a` — `\w`, `\d`, `\s` and `\b` are ASCII-only.
  ascii : Bool
  /// `u` — Unicode semantics. On by default under the Python dialect, where
  /// patterns are Unicode already; under ECMA-262 it switches from UTF-16
  /// code units to code points.
  unicode : Bool
  /// `v` — ECMA-262's Unicode sets: `--`, `&&` and string properties.
  unicode_sets : Bool
  /// `f` — full case folding, the default under `V1`.
  fullcase : Bool
  /// `b` — fuzzy matching takes the best match, not the first.
  bestmatch : Bool
  /// `e` — fuzzy matching improves a match once found.
  enhancematch : Bool
  /// `p` — leftmost-longest rather than leftmost-first.
  posix : Bool
  /// `r` — search from the end of the string backwards.
  reverse : Bool
  /// `w` — Unicode word boundaries and line endings (`\m`, `\M`).
  word : Bool
  /// Which `regex` behaviour set the Python grammar is read under.
  version : Version
} derive(Eq, Debug)

///|
pub extend Flags with Eq::{equal, not_equal}

///|
pub extend Flags with Debug::{to_repr}

///|
/// Everything off, `unicode` on, version `V0`.
///
/// This is the preset every default argument points at, so a pattern written
/// with no flags at all behaves the way Python's `re` does by default.
pub let flags : Flags = {
  ignorecase: false,
  multiline: false,
  dotall: false,
  verbose: false,
  ascii: false,
  unicode: true,
  unicode_sets: false,
  fullcase: false,
  bestmatch: false,
  enhancematch: false,
  posix: false,
  reverse: false,
  word: false,
  version: V0,
}

///|
/// The dialect a pattern is read under when the caller does not say.
pub let dialect : Dialect = Python

///|
/// Build flags, leaving unset switches at their preset.
///
/// A flag that is only meaningful in one dialect is accepted everywhere and
/// refused by the parser when the grammar cannot honour it — `verbose` under
/// ECMA-262, for instance — so that the mistake is named where it happens.
pub fn Flags::new(
  ignorecase~ : Bool = false,
  multiline~ : Bool = false,
  dotall~ : Bool = false,
  verbose~ : Bool = false,
  ascii~ : Bool = false,
  unicode~ : Bool = true,
  unicode_sets~ : Bool = false,
  fullcase~ : Bool = false,
  bestmatch~ : Bool = false,
  enhancematch~ : Bool = false,
  posix~ : Bool = false,
  reverse~ : Bool = false,
  word~ : Bool = false,
  version~ : Version = V0,
) -> Flags {
  {
    ignorecase,
    multiline,
    dotall,
    verbose,
    ascii,
    unicode,
    unicode_sets,
    fullcase,
    bestmatch,
    enhancematch,
    posix,
    reverse,
    word,
    version,
  }
}

///|
/// Why a pattern, or a run of one, was refused.
///
/// The word is deliberate: a pattern is input, and this library is fed
/// patterns it did not write. Refusals say what was wrong and where; the
/// step ceiling says how far the run got before giving up.
pub(all) suberror Refused {
  /// The pattern is not the grammar it claims: `at` is the code point offset
  /// reading stopped at, `line` and `column` are where that is in the text.
  Pattern(msg~ : String, at~ : Int32, line~ : Int32, column~ : Int32)
  /// The run passed `limit` steps and stopped; `got` is how far it got.
  Exceeded(limit~ : Int32, got~ : Int32)
  /// A call needed one group out of a pattern that has several, and none was
  /// named — `findall` with two groups or more, for instance.
  Ambiguous(groups~ : Int32)
  /// `(*ACCEPT)`: the pattern asked for the match to end here, successfully.
  /// Carries the match's start and end so the caller can build it.
  Accept(start~ : Int32, end~ : Int32)
} derive(Eq, Debug)

///|
pub extend Refused with Eq::{equal, not_equal}

///|
pub extend Refused with Debug::{to_repr}

///|
pub extend Refused with Show::{output, to_string}

///|
pub impl Show for Refused with fn output(self, logger) {
  logger.write_string(
    match self {
      Pattern(msg~, at~, line~, column~) =>
        "\{msg} at position \{at} (line \{line}, column \{column})"
      Exceeded(limit~, got~) => "match exceeded \{limit} steps (got \{got})"
      Ambiguous(groups~) =>
        "pattern has \{groups} groups; pass group= to say which one to take"
      Accept(start~, end~) => "match accepted at \{start}..\{end}"
    },
  )
}
