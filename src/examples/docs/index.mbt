// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The home page: `docs/index.html`.

///|
test "index/search" {
  // docs:begin search
  let m = @moonregex.search("\\d+", "order 42").unwrap()
  assert_eq(m.content(), "42")
  assert_true(@moonregex.prefix("\\d+", "order 42") is None)
  assert_true(@moonregex.full("\\d+", "42") is Some(_))

  let year = @moonregex.compile("\\d{4}")
  assert_eq(year.findall("1999 and 2026"), [Some("1999"), Some("2026")])
  // docs:end
}

///|
test "index/groups" {
  // docs:begin groups
  let p = @moonregex.compile("(?<year>\\d{4})-(?<month>\\d{2})")
  let m = p.search("on 2026-10-28").unwrap()
  assert_eq(m.group(1), Some("2026"))
  assert_eq(m.group("month"), Some("10"))
  assert_eq(m["year"], Some("2026"))

  let pairs = @moonregex.findall("(\\w+)=(\\d+)", "a=1", group=Num(n=1))
  assert_eq(pairs, [Some("a")])
  // docs:end
  // Two groups and no `group=`: refused, rather than answering a tuple.
  assert_true(
    try {
      let _ = @moonregex.findall("(\\w+)=(\\d+)", "a=1")
      false
    } catch {
      @moonregex.Refused::Ambiguous(_) => true
      e => raise e
    },
  )
}

///|
test "index/replace" {
  // docs:begin replace
  assert_eq(@moonregex.sub("\\s+", " ", "a   b  c"), "a b c")
  assert_eq(@moonregex.sub("(\\w+)@(\\w+)", "\\g<2>:\\g<1>", "u@h"), "h:u")
  assert_eq(@moonregex.subf("\\d+", "[{0}]", "n 42"), "n [42]")

  let wrapped = @moonregex.sub_with(
    "\\d+",
    m => "<" + m.content().to_owned() + ">",
    "a1b",
  )
  // docs:end
  assert_eq(wrapped, "a<1>b")
}

///|
test "index/unicode" {
  // docs:begin unicode
  let words = @moonregex.findall("\\p{Lu}\\p{Ll}+", "Paris and Αθήνα")
  assert_eq(words, [Some("Paris"), Some("Αθήνα")])

  let han = @moonregex.compile("\\p{Script=Han}+")
  assert_eq(han.findall("漢字 and kana"), [Some("漢字")])

  let x = @moonregex.compile("\\X")
  assert_eq(x.search("e\u{301}x").unwrap().content(), "e\u{301}")
  // docs:end
}

///|
test "index/bridge" {
  // docs:begin bridge
  let date = @moonregex.compile("\\d{4}").capture("year") +
    @moonregex.compile("-") +
    @moonregex.compile("\\d{2}").capture("month")

  let core = date.lower().unwrap()
  assert_true(core.execute("2026-10") is Some(_))
  // docs:end
}
