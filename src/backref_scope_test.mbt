// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What the leftmost match of `pattern` in `text` covers, or `None` when there
/// is none. The whole match, not a group: these tests are about a pattern
/// accepting or refusing a text.
fn covers(pattern : String, text : String) -> String? raise {
  @moonregex.search(pattern, text).map(m => m.content().to_owned())
}

///|
/// The case a backreference is compared under.
///
/// A group is read under the flags around it and a reference is compared under
/// the flags around the reference; the two need not be the same, and when they
/// differ the reference wins. Python's `re` answers this way, so the patterns
/// below are also in `src/vectors_test.mbt`, where its answers are replayed.

///|
test "a reference is read under the flags around it" {
  let bs = "\\"
  // `(?-i:…)` makes the group case-sensitive while `(?i)` is still in force at
  // the reference, so the reference is the caseless half of the pair.
  let outer = "(?i)(?-i:(a))" + bs + "1"
  assert_eq(covers(outer, "aA"), Some("aA"))
  assert_eq(covers(outer, "aa"), Some("aa"))
  // The group is case-sensitive, so `AA` does not even start to match.
  assert_eq(covers(outer, "AA"), None)
  assert_eq(covers(outer, "Aa"), None)
  // The other way round: `(?i:…)` makes the group caseless and the reference
  // sits outside it, so the reference is case-sensitive.
  let inner = "(?i:(a))(?-i:" + bs + "1)"
  assert_eq(covers(inner, "aa"), Some("aa"))
  assert_eq(covers(inner, "AA"), Some("AA"))
  assert_eq(covers(inner, "Aa"), None)
  assert_eq(covers(inner, "aA"), None)
}

///|
test "a reference inside a caseless group is caseless" {
  let bs = "\\"
  assert_eq(covers("(?i:(a)" + bs + "1)", "aA"), Some("aA"))
  assert_eq(covers("(?i:(a)" + bs + "1)", "AA"), Some("AA"))
  // And a reference under a global `(?i)` is caseless too.
  assert_eq(covers("(?i)(a)" + bs + "1", "Aa"), Some("Aa"))
}

///|
/// The comparison is per code point over every script, not over ASCII alone.
test "a caseless reference folds the alphabet it names" {
  let bs = "\\"
  assert_eq(covers("(?i)(é)" + bs + "1", "éÉ"), Some("éÉ"))
  assert_eq(covers("(?i)(σ)" + bs + "1", "σΣ"), Some("σΣ"))
  // The Kelvin sign is a case of `k`, though no lowercasing table says so
  // without folding.
  assert_eq(covers("(?i)(k)" + bs + "1", "k\u{212A}"), Some("k\u{212A}"))
  // A case-sensitive reference stays exact, whatever the characters are.
  assert_eq(covers("(é)" + bs + "1", "éÉ"), None)
  assert_eq(covers("(é)" + bs + "1", "éé"), Some("éé"))
}

///|
/// One place where the case relation is wider than Python's: `re` compares the
/// lowercased code points of the two sides, and a handful of characters — the
/// final sigma, the long s, the micro sign, the Cherokee lower case — fold to a
/// different letter than they lowercase to. A backreference here compares by
/// that fold, as the `regex` package does, so a literal and a reference in the
/// same pattern never disagree about case.
test "a reference folds where the reference only lowercases" {
  let bs = "\\"
  // `(?i)σ` matches `ς` on its own, so the reference to it must match too.
  assert_true(@moonregex.search("(?i)σ", "ς") is Some(_))
  assert_eq(covers("(?i)(σ)" + bs + "1", "σς"), Some("σς"))
  assert_eq(covers("(?i)(s)" + bs + "1", "sſ"), Some("sſ"))
}

///|
/// A reference to a group that took no part is no match, and the same holds
/// when the reference is caseless: nothing was captured, so nothing compares.
test "a reference to an empty group cannot match" {
  let bs = "\\"
  assert_eq(covers("(?i)(a)?" + bs + "1", "A"), None)
  assert_eq(covers("(?i)(a*)b" + bs + "1", "aabAA"), Some("aabAA"))
}
