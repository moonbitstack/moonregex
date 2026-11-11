// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Full case folding: the `f` flag, on by default under `V1`.
///
/// Case-insensitive matching without it compares one code point with one, so
/// `ß` matches `ẞ` and nothing else. With it a literal stands for its folded
/// text, which is two characters for `ß` and `ﬁ`, and a run of `ss` collapses
/// onto the one — which is what the `regex` package does and what Unicode's
/// canonical caseless match says.

///|
test "a literal folds across lengths" {
  let p = @moonregex.compile("(?fi)ß")
  assert_eq(p.search("ss").unwrap().span(0), (0, 2))
  assert_eq(p.search("SS").unwrap().span(0), (0, 2))
  assert_eq(p.search("ß").unwrap().span(0), (0, 1))
  assert_eq(p.search("ẞ").unwrap().span(0), (0, 1))
  assert_eq(p.search("Ss").unwrap().span(0), (0, 2))
  // A run of two folds onto the one character that folds to it.
  let q = @moonregex.compile("(?fi)ss")
  assert_eq(q.search("ß").unwrap().span(0), (0, 1))
  // The first `ß` is the whole match: the pattern is two folded characters.
  assert_eq(q.search("ßß").unwrap().span(0), (0, 1))
  assert_true(@moonregex.compile("(?fi)sss").search("ß") is None)
  assert_eq(
    @moonregex.compile("(?fi)sss").search("ßs").unwrap().span(0),
    (0, 2),
  )
  // And a single `s` does not: a fold is never split.
  assert_true(@moonregex.compile("(?fi)s").search("ß") is None)
}

///|
test "a ligature folds onto its letters" {
  let p = @moonregex.compile("(?fi)ﬁ")
  assert_eq(p.search("fi").unwrap().span(0), (0, 2))
  assert_eq(p.search("FI").unwrap().span(0), (0, 2))
  assert_eq(
    @moonregex.compile("(?fi)fi").search("ﬁ").unwrap().span(0),
    (0, 1),
  )
}

///|
test "the flag is what turns folding on" {
  // `i` alone folds one code point at a time.
  assert_true(@moonregex.compile("(?i)ß").search("ss") is None)
  // `f` alone is nothing without `i`.
  assert_true(@moonregex.compile("(?f)ß").search("ss") is None)
  // `V1` carries `f`.
  assert_eq(
    @moonregex.compile("(?V1)(?i)ß").search("ss").unwrap().span(0),
    (0, 2),
  )
  // And a scope can give it up.
  assert_true(@moonregex.compile("(?fi)(?-f:ß)").search("ss") is None)
  assert_true(@moonregex.compile("(?fi)(?-i:ß)").search("ss") is None)
  // ASCII mode has no such pairs to fold over.
  assert_true(@moonregex.compile("(?fia)ß").search("ss") is None)
}

///|
test "a class folds across lengths through its written characters" {
  let p = @moonregex.compile("(?fi)[ß]")
  assert_eq(p.search("ss").unwrap().span(0), (0, 2))
  assert_eq(p.search("ẞ").unwrap().span(0), (0, 1))
  // One code point wins when both readings are open.
  assert_eq(
    @moonregex.compile("(?fi)[ßs]").search("ss").unwrap().span(0),
    (0, 1),
  )
  // Two classes in a row each take their own.
  assert_eq(
    @moonregex.compile("(?fi)[ß][ß]").search("ssss").unwrap().span(0),
    (0, 4),
  )
  // A range names characters, not folds: it does not grow a longer reading.
  assert_eq(
    @moonregex.compile("(?fi)[a-ß]").search("ss").unwrap().span(0),
    (0, 1),
  )
  // A negated class answers one code point at a time.
  assert_eq(
    @moonregex.compile("(?fi)[^ß]").search("ss").unwrap().span(0),
    (0, 1),
  )
  assert_true(@moonregex.compile("(?fi)[^ß]").search("ß") is None)
}

///|
test "a backreference folds across lengths" {
  let p = @moonregex.compile("(?fi)(ß)\\1")
  assert_eq(p.search("ssSS").unwrap().span(0), (0, 4))
  assert_eq(p.search("ssß").unwrap().span(0), (0, 3))
  let q = @moonregex.compile("(?fi)(ss)\\1")
  assert_eq(q.search("ßß").unwrap().span(0), (0, 2))
  // Off, the two sides are compared one code point at a time as before.
  assert_true(@moonregex.compile("(?i)(ß)\\1").search("ssSS") is None)
}

///|
test "folding leaves the patterns that do not ask for it alone" {
  let p = @moonregex.compile("ss")
  assert_true(p.search("ß") is None)
  assert_eq(
    @moonregex.compile("(?i)str").search("STR").unwrap().span(0),
    (0, 3),
  )
  // The simple fold still reaches beyond ASCII.
  assert_eq(@moonregex.compile("(?i)σ").search("ς").unwrap().span(0), (0, 1))
}

///|
test "every code point that folds to more than one character" {
  for line in fullcase_vectors {
    replay(line, "regex") catch {
      e => fail("vector \{line}\n  \{e}")
    }
  }
  // The table covers the whole `F` class of CaseFolding.txt, in both
  // directions: the character written in the pattern matches its folded text,
  // and the folded text written in the pattern matches the character.
  assert_eq(fullcase_pairs.length(), 104)
  for pair in fullcase_pairs {
    let (code, fold) = pair
    let one = unescape(code)
    let many = unescape(fold)
    assert_true(@moonregex.compile("(?fi)" + one).full(many) is Some(_))
    assert_true(@moonregex.compile("(?fi)" + many).full(one) is Some(_))
  }
  // `regex` ends a match inside the fold of U+0130, so `(?fi)İ` answers just
  // `i` of `i` + a combining dot. Canonical caseless matching — which is what
  // this library implements, and what the README's difference table says —
  // compares the two folds whole, so the pair is pinned here rather than by a
  // vector shared with the reference.
  assert_eq(fullcase_divergences.length(), 1)
  for pair in fullcase_divergences {
    let (code, fold) = pair
    let one = unescape(code)
    let many = unescape(fold)
    assert_true(@moonregex.compile("(?fi)" + one).full(many) is Some(_))
    assert_true(@moonregex.compile("(?fi)" + many).full(one) is Some(_))
  }
}

///|
test "a folded run the text cuts short" {
  // Partial matching treats the rest of the fold as text still to come, the
  // way it treats any other character the subject has not reached yet.
  let p = @moonregex.compile("(?fi)ß", partial=true)
  let whole = p.prefix("ss").unwrap()
  assert_true(whole.partial() is false)
  assert_eq(whole.span(0), (0, 2))
  assert_true(p.prefix("s").unwrap().partial())
  // A repeat of a folded run still ends: an attempt that consumed nothing
  // stops the repetition, as it does everywhere else.
  assert_true(
    @moonregex.compile("(?fi)ß*", partial=true).prefix("x") is Some(_),
  )
  // One word, folded whole: `ß` is two characters here and one there.
  let street = @moonregex.compile("(?fi)straße")
  assert_eq(street.full("STRASSE").unwrap().span(0), (0, 7))
  assert_eq(street.full("straße").unwrap().span(0), (0, 6))
}
