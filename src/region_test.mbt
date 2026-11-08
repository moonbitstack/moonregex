// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// `pos` and `endpos` name the region a call works on. The end is the end of
/// the subject as far as matching goes — a greedy repetition stops there and
/// `$` sits there — which is what Python means by `endpos`.

///|
test "endpos bounds the match, it does not just bound the scan" {
  let m = @moonregex.search("\\w+", "abcdef", endpos=3).unwrap()
  assert_eq(m.content(), "abc")
  assert_eq(m.span(0), (0, 3))
  assert_eq(m.endpos(), 3)
}

///|
test "endpos moves where a dollar sits" {
  let m = @moonregex.search("\\w{3}$", "abcdef", endpos=3).unwrap()
  assert_eq(m.content(), "abc")
  assert_true(@moonregex.search("\\w{6}$", "abcdef", endpos=3) is None)
}

///|
test "full matches the region, not the whole text" {
  let m = @moonregex.full("\\w+", "abcd efgh", pos=5, endpos=9).unwrap()
  assert_eq(m.content(), "efgh")
  assert_false(@moonregex.full("\\w+", "abcd efgh", endpos=4) is None)
}

///|
test "findall, split and sub stay inside endpos" {
  let p = @moonregex.compile("\\w+")
  let got = p.findall("abcd efgh", endpos=6)
  assert_eq(got, [Some("abcd"), Some("e")])
  let parts = p.split("abcd efgh", endpos=6)
  assert_eq(parts, [Some(""), Some(" "), Some("")])
  assert_eq(p.sub("abcd efgh", "X", endpos=6), "X X")
}

///|
test "finditer reports the region it was given" {
  let m = @moonregex.compile("\\w+").finditer("abcd efgh", pos=5, endpos=9)[0]
  assert_eq(m.content(), "efgh")
  assert_eq(m.pos(), 5)
  assert_eq(m.endpos(), 9)
}

///|
test "endpos past the end of the text is the end of the text" {
  let m = @moonregex.search("\\w+", "abcdef", endpos=99).unwrap()
  assert_eq(m.content(), "abcdef")
  assert_eq(m.endpos(), 6)
}

///|
test "pos past the end of the text matches only the empty pattern" {
  assert_true(@moonregex.search("\\w+", "abcdef", pos=99) is None)
  let m = @moonregex.search("", "abcdef", pos=99).unwrap()
  assert_eq(m.span(0), (6, 6))
}

///|
test "a region that ends before it starts holds no match" {
  assert_true(@moonregex.search("\\w+", "abcdef", pos=4, endpos=2) is None)
  assert_true(@moonregex.full("\\w+", "abcdef", pos=4, endpos=2) is None)
}

///|
test "a caret still means the start of the text, not of the region" {
  // The scan starts at 2 and `^` holds only at 0, so the pattern cannot match,
  // even though the text at the scan position begins with it.
  assert_true(@moonregex.search("^cde", "abcdef", pos=2) is None)
  let m = @moonregex.search("^abc", "abcdef").unwrap()
  assert_eq(m.content(), "abc")
}
