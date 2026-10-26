// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Parse `pattern` as a MoonBit `lexmatch` literal — the grammar MoonBit's own
/// `@string.Regex` speaks, the lexer uses, and `lexmatch` documents.
pub fn lexmatch_parse(pattern : StringView) -> Ast raise Refused {
  parse(pattern, dialect=Lexmatch)
}

///|
/// Parse a `lexmatch` literal with the flags already chosen by the caller.
pub fn lexmatch_parse_with(
  pattern : StringView,
  flags : Flags,
) -> Ast raise Refused {
  parse(pattern, flags~, dialect=Lexmatch)
}
