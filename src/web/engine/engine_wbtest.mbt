// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The page depends on this exact shape, so one case pins it whole.
test "a full match is one span, spelled exactly so" {
  assert_eq(
    run("a+", "", "aaa", "full"),
    "{\"ok\":true,\"count\":1,\"groups\":0,\"matches\":[{\"start\":0,\"end\":3,\"text\":\"aaa\",\"groups\":[{\"slot\":0,\"name\":\"\",\"start\":0,\"end\":3,\"text\":\"aaa\"}]}]}",
  )
}

///|
test "a named group carries its name, its span and its text" {
  let json = run("(?P<year>\\d{4})", "", "in 2026", "search")
  assert_true(json.contains("\"name\":\"year\""))
  assert_true(json.contains("\"start\":3,\"end\":7,\"text\":\"2026\""))
}

///|
test "the four functions answer as their names say" {
  assert_true(run("\\d", "", "1 2 3", "findall").contains("\"count\":3"))
  assert_true(run("\\d", "", "1 2 3", "search").contains("\"count\":1"))
  assert_true(run("\\d", "", "1 2 3", "prefix").contains("\"count\":1"))
  assert_true(run("\\d", "", "x 1", "prefix").contains("\"count\":0"))
  assert_true(run("\\d+", "", "x 1", "full").contains("\"count\":0"))
}

///|
test "a refusal says where reading stopped" {
  let json = run("(", "", "x", "search")
  assert_true(json.contains("\"ok\":false"))
  assert_true(json.contains("\"column\":1"))
}

///|
test "a bad flag has no column, because the pattern is not at fault" {
  assert_true(run("a", "q", "a", "search").contains("\"column\":0"))
}

///|
test "text lands in the JSON escaped, not raw" {
  let json = run("\\n", "", "a\nb", "search")
  assert_true(json.contains("\\n"))
  assert_true(!json.contains("\n"))
}

///|
test "offsets count code points, which is what the page converts" {
  // The emoji is one code point but two UTF-16 units.
  assert_true(run("x", "", "😀x", "search").contains("\"start\":1,\"end\":2"))
}
