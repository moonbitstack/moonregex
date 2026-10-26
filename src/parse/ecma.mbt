// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Parse `pattern` as an ECMA-262 `RegExp` — the grammar JSON Schema and
/// OpenAPI mean by a "string" pattern, and what a browser hands `new RegExp`.
///
/// The tree is the same one Python's `re` reads into; only the dialect differs,
/// so the executor never asks which grammar a node came from.
pub fn ecma_parse(pattern : StringView) -> Ast raise Refused {
  parse(pattern, dialect=Ecma262)
}

///|
/// Parse an ECMA-262 `RegExp` with the flags already chosen by the caller.
pub fn ecma_parse_with(
  pattern : StringView,
  flags : Flags,
) -> Ast raise Refused {
  parse(pattern, flags~, dialect=Ecma262)
}
