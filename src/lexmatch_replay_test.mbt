// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The lexmatch frontend, against Python's answers for the same pattern.
///
/// `src/lexmatch_vectors_test.mbt` holds what CPython's `re` answered for
/// patterns both grammars accept and mean the same thing by: the shorthand
/// classes and named captures that the core grammar leaves out and this
/// library reads the Python way. Replaying them through `Lexmatch` is what
/// makes "the same meaning" a measurement rather than a claim.

///|
test "CPython's re, read as lexmatch" {
  for line in lexmatch_vectors {
    replay(line, "lexmatch", dialect=@moonregex.lexmatch_dialect) catch {
      e => fail("vector \{line}\n  \{e}")
    }
  }
}
