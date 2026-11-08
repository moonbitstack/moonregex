// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A pattern with `partial=true` answers a match when the text stops in the
/// middle of one: the span is the text that arrived, and `Match::partial` says
/// there would be more. A complete match is never partial.

///|
test "a partial match stops at the end of the text" {
  let p = @moonregex.compile("\\d{4}-\\d{2}", partial=true)
  let m = p.prefix("2026-").unwrap()
  assert_eq(m.content(), "2026-")
  assert_eq(m.span(0), (0, 5))
  assert_true(m.partial())
  let one = p.prefix("2026-1").unwrap()
  assert_eq(one.content(), "2026-1")
  assert_true(one.partial())
}

///|
test "a match the text completed is not partial" {
  let p = @moonregex.compile("\\d{4}-\\d{2}", partial=true)
  let m = p.prefix("2026-10").unwrap()
  assert_eq(m.content(), "2026-10")
  assert_false(m.partial())
}

///|
test "without partial the same text is no match" {
  assert_true(@moonregex.prefix("\\d{4}-\\d{2}", "2026-") is None)
  let p = @moonregex.compile("\\d{4}-\\d{2}")
  assert_true(p.prefix("2026-") is None)
  assert_true(p.full("2026-") is None)
}

///|
test "full answers a partial match when the whole region is a prefix" {
  let p = @moonregex.compile("\\d{4}", partial=true)
  let m = p.full("20").unwrap()
  assert_eq(m.content(), "20")
  assert_true(m.partial())
}

///|
test "an empty text is a partial match of any pattern that needs a character" {
  let p = @moonregex.compile("abc", partial=true)
  let m = p.prefix("").unwrap()
  assert_eq(m.span(0), (0, 0))
  assert_true(m.partial())
}

///|
test "search reports the partial match at the end of the text" {
  let p = @moonregex.compile("\\d{4}", partial=true)
  let m = p.search("tel 20").unwrap()
  assert_eq(m.span(0), (4, 6))
  assert_true(m.partial())
  // Nothing to match in the middle: the partial match sits where the text ends.
  let tail = p.search("abc").unwrap()
  assert_eq(tail.span(0), (3, 3))
  assert_true(tail.partial())
}

///|
test "a greedy repetition reads past the end without looping" {
  let p = @moonregex.compile("a*b", partial=true)
  let m = p.prefix("aaa").unwrap()
  assert_eq(m.content(), "aaa")
  assert_true(m.partial())
  let star = @moonregex.compile("(a*)*b", partial=true)
  assert_eq(star.prefix("aaa").unwrap().content(), "aaa")
}

///|
test "a backreference whose text has not all arrived is partial" {
  let p = @moonregex.compile("(ab)\\1", partial=true)
  let m = p.prefix("aba").unwrap()
  assert_eq(m.content(), "aba")
  assert_true(m.partial())
}

///|
test "a lookahead that needs the next character makes the match partial" {
  let p = @moonregex.compile("a(?=b)", partial=true)
  let m = p.prefix("a").unwrap()
  assert_eq(m.content(), "a")
  assert_true(m.partial())
}

///|
test "a lookbehind does not read text still to come" {
  // The body must end where the assertion sits, so no continuation can help it.
  let p = @moonregex.compile("(?<=ab)c", partial=true)
  // The assertion is satisfied by text that did arrive; only `c` is missing.
  let cut = p.search("ab").unwrap()
  assert_eq(cut.span(0), (2, 2))
  assert_true(cut.partial())
  let m = p.search("abc").unwrap()
  assert_eq(m.content(), "c")
  assert_false(m.partial())
}

///|
test "findall keeps the partial match as its last item" {
  let p = @moonregex.compile("\\d{2}", partial=true)
  let got = p.findall("11 22 3")
  assert_eq(got.length(), 3)
  assert_eq(got[0], Some("11"))
  assert_eq(got[2], Some("3"))
  assert_true(p.finditer("11 3")[1].partial())
}

///|
test "partial and a step limit can be asked for together" {
  let got = @moonregex.compile("\\d{2}", partial=true).full("1", limit=100)
  assert_true(got.unwrap().partial())
}
