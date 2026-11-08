// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The plural forms of `start`, `end` and `span` answer every capture of a
/// group, and `allcaptures`/`allspans` answer every group at once.

///|
test "starts, ends and spans agree with captures" {
  let m = @moonregex.compile("(?<year>\\d{4})-(?<month>\\d{2})")
    .search("on 2026-10-28")
    .unwrap()
  assert_eq(m.captures(1), ["2026"])
  assert_eq(m.spans(1), [(3, 7)])
  assert_eq(m.starts(1), [3])
  assert_eq(m.ends(1), [7])
  assert_eq(m.starts("month"), [8])
  assert_eq(m.ends("month"), [10])
  assert_eq(m.spans("month"), [(8, 10)])
}

///|
test "a group that took no part answers empty lists" {
  let m = @moonregex.compile("(a)|(b)").search("b").unwrap()
  assert_eq(m.captures(1), [])
  assert_eq(m.starts(1), [])
  assert_eq(m.ends(1), [])
  assert_eq(m.spans(1), [])
}

///|
test "allcaptures lists every group, group 0 first" {
  let m = @moonregex.compile("(a)|(b)").search("b").unwrap()
  assert_eq(m.allcaptures(), [["b"], [], ["b"]])
  assert_eq(m.allspans(), [[(0, 1)], [], [(0, 1)]])
}

///|
test "allspans covers a named group at its span" {
  let m = @moonregex.compile("(?<y>\\d{4})").search("in 2026").unwrap()
  assert_eq(m.allspans(), [[(3, 7)], [(3, 7)]])
}
