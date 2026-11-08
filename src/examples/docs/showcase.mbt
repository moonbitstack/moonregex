// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The showcase's "three spellings" panel: `docs/showcase.html`. The panel prints
/// a one-line summary under each spelling, and these blocks are what makes that
/// line true.

///|
test "showcase/py" {
  // docs:begin py
  let p = @moonregex.compile("(?P<year>\\d{4})-(?P<month>\\d{2})")
  let m = p.search("on 2026-10-28").unwrap()
  // docs:end
  assert_eq(m.span(0), (3, 10))
  assert_eq(m.span("year"), (3, 7))
  assert_eq(m.span("month"), (8, 10))
}

///|
test "showcase/core" {
  // docs:begin core
  let p = @moonregex.compile(
    "([0-9]{4})-([0-9]{2})",
    dialect=@moonregex.lexmatch_dialect,
  )
  let m = p.search("on 2026-10-28").unwrap()
  // docs:end
  assert_eq(m.span(0), (3, 10))
  assert_eq(m.span(1), (3, 7))
  assert_eq(m.span(2), (8, 10))
}

///|
test "showcase/built" {
  // docs:begin built
  let year = @moonregex.compile("\\d{4}").capture("year")
  let dash = @moonregex.Pattern::string("-")
  let month = @moonregex.compile("\\d{2}").capture("month")
  let p = year + dash + month
  let m = p.search("on 2026-10-28").unwrap()
  // docs:end
  assert_eq(m.span(0), (3, 10))
  assert_eq(m.span("year"), (3, 7))
  assert_eq(m.span("month"), (8, 10))
}
