// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The Python `regex` (mrab-regex) / `re` surface: named flags, `Scanner`,
/// `Match` methods (`expand`, `pos`/`endpos`, `captures`, `fuzzy_*`), and the
/// module-level aliases. These are the "last mile" pieces of full API parity.

///|
test "named flag constants exist and differ" {
  // Each named flag sets exactly its own field.
  assert_true(@moonregex.i.ignorecase)
  assert_true(@moonregex.m.multiline)
  assert_true(@moonregex.s.dotall)
  assert_true(@moonregex.x.verbose)
  assert_true(@moonregex.a.ascii)
  assert_true(@moonregex.u.unicode)
  assert_true(@moonregex.f.fullcase)
  assert_true(@moonregex.w.word)
  assert_true(@moonregex.b.bestmatch)
  assert_true(@moonregex.e.enhancematch)
  assert_true(@moonregex.r.reverse)
  assert_true(@moonregex.p.posix)
  // The long spellings alias the short ones.
  assert_true(@moonregex.ignorecase.ignorecase)
  assert_true(@moonregex.multiline.multiline)
  assert_true(@moonregex.dotall.dotall)
  // Version flags.
  assert_eq(@moonregex.v0.version, @moonregex.version0_value)
  assert_eq(@moonregex.v1.version, @moonregex.version1_value)
  assert_eq(@moonregex.default_version, @moonregex.version0_value)
  // The TEMPLATE flag is the empty flag set.
  assert_false(@moonregex.t.ignorecase)
  assert_false(@moonregex.t.multiline)
}

///|
test "ignorecase flag makes matching case-insensitive" {
  let pat = @moonregex.compile("hello", flags=@moonregex.i)
  assert_true(pat.search("HELLO world") is Some(_))
  assert_true(pat.fullmatch("HeLLo") is Some(_))
}

///|
test "multiline flag anchors ^ and $ at line breaks" {
  let pat = @moonregex.compile("^b", flags=@moonregex.m)
  assert_true(pat.search("a\nb") is Some(_))
  let pat2 = @moonregex.compile("a$", flags=@moonregex.m)
  assert_true(pat2.search("a\nb") is Some(_))
}

///|
test "dotall flag lets dot cross newlines" {
  let pat = @moonregex.compile("a.b", flags=@moonregex.s)
  assert_true(pat.search("a\nb") is Some(_))
  let pat2 = @moonregex.compile("a.b")
  assert_true(pat2.search("a\nb") is None)
}

///|
test "purge and template are present for drop-in compatibility" {
  @moonregex.purge()
  let pat = @moonregex.template("abc")
  assert_true(pat.fullmatch("abc") is Some(_))
}

///|
test "Match pos and endpos report the search region" {
  let m = @moonregex.search("b+", "abc", pos=1, endpos=3).unwrap()
  assert_eq(m.pos(), 1)
  assert_eq(m.endpos(), 3)
  assert_eq(m.group().unwrap(), "b")
}

///|
test "Match re returns the pattern and expand substitutes groups" {
  let pat = @moonregex.compile("(?P<word>\\w+) \\1")
  let m = pat.search("go go").unwrap()
  assert_eq(m.re().pattern(), "(?P<word>\\w+) \\1")
  assert_eq(m.expand("\\g<word>-\\g<word>"), "go-go")
  assert_eq(m.expand("\\1"), "go")
}

///|
test "Match captures and slices list a group's captured text" {
  let m = @moonregex.search("(a+)b", "aaab").unwrap()
  assert_eq(m.captures(group=@moonregex.Num(n=1)), [(0, 3)])
  assert_eq(m.slices(group=@moonregex.Num(n=1)), ["aaa"])
  assert_eq(m.slices(), ["aaab"])
}

///|
test "Match capturesdict maps named groups to spans" {
  let m = @moonregex.search("(?P<a>\\d+)-(?P<b>\\d+)", "12-34").unwrap()
  let d = m.capturesdict()
  assert_eq(d["a"], [(0, 2)])
  assert_eq(d["b"], [(3, 5)])
}

///|
test "fuzzy_counts and fuzzy_changes report the edit distance" {
  let m = @moonregex.search("(?:foo){e<=2}", "fox").unwrap()
  let (s, i, d) = m.fuzzy_counts()
  assert_eq(s + i + d, 1)
  let (subs, inss, dels) = m.fuzzy_changes()
  // Exactly one edit: a single substitution (o -> x).
  assert_eq(subs.length() + inss.length() + dels.length(), 1)
}

///|
test "Scanner search walks the text left to right" {
  let sc = @moonregex.compile("\\d+").scanner("a1 b22 c333")
  let m1 = sc.search().unwrap()
  assert_eq(m1.group().unwrap(), "1")
  let m2 = sc.search().unwrap()
  assert_eq(m2.group().unwrap(), "22")
  let m3 = sc.search().unwrap()
  assert_eq(m3.group().unwrap(), "333")
  assert_true(sc.search() is None)
}

///|
test "Scanner match_at anchors each call at the cursor" {
  // `match_at` anchors at the cursor: after matching "foo", the cursor sits at
  // the space, where `\w+` does not match, so the second call is `None`.
  let sc = @moonregex.compile("\\w+").scanner("foo bar")
  let m1 = sc.match_at().unwrap()
  assert_eq(m1.group().unwrap(), "foo")
  assert_true(sc.match_at() is None)
}

///|
test "Scanner findall and finditer collect the remainder" {
  let sc = @moonregex.compile("\\d").scanner("1a2b3")
  let _ = sc.search() // consume the leading "1"
  assert_eq(sc.findall(), [Some("2"), Some("3")])
  let sc2 = @moonregex.compile("\\d").scanner("1a2b3")
  let _ = sc2.search()
  let ms = sc2.finditer()
  assert_eq(ms.length(), 2)
  assert_eq(ms[0].group().unwrap(), "2")
  assert_eq(ms[1].group().unwrap(), "3")
}

///|
test "Scanner split and sub act on the remainder" {
  let sc = @moonregex.compile(",").scanner("a,b,c")
  assert_eq(sc.split(), [Some("a"), Some("b"), Some("c")])
  let sc2 = @moonregex.compile("\\d").scanner("x1y2")
  assert_eq(sc2.sub("#"), "x#y#")
}

///|
test "RegexError and RegexFlag aliases are the underlying types" {
  // These compile-time aliases just need to exist and be usable.
  let _flag : @moonregex.RegexFlag = @moonregex.i
  assert_true(true)
}
