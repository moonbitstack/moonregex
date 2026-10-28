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
}

///|
test "ignorecase flag makes matching case-insensitive" {
  let pat = @moonregex.compile("hello", flags=@moonregex.i)
  assert_true(pat.search("HELLO world") is Some(_))
  assert_true(pat.full("HeLLo") is Some(_))
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
test "Match pos and endpos report the search region" {
  let m = @moonregex.search("b+", "abc", pos=1, endpos=3).unwrap()
  assert_eq(m.pos(), 1)
  assert_eq(m.endpos(), 3)
  assert_eq(m.group(0).unwrap(), "b")
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
  assert_eq(m.captures(1), [(0, 3)])
  assert_eq(m.slices(1), ["aaa"])
  assert_eq(m.slices(0), ["aaab"])
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
  assert_eq(m1.group(0).unwrap(), "1")
  let m2 = sc.search().unwrap()
  assert_eq(m2.group(0).unwrap(), "22")
  let m3 = sc.search().unwrap()
  assert_eq(m3.group(0).unwrap(), "333")
  assert_true(sc.search() is None)
}

///|
test "Scanner prefix anchors each call at the cursor" {
  // `prefix` anchors at the cursor: after matching "foo", the cursor sits at
  // the space, where `\w+` does not match, so the second call is `None`.
  let sc = @moonregex.compile("\\w+").scanner("foo bar")
  let m1 = sc.prefix().unwrap()
  assert_eq(m1.group(0).unwrap(), "foo")
  assert_true(sc.prefix() is None)
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
  assert_eq(ms[0].group(0).unwrap(), "2")
  assert_eq(ms[1].group(0).unwrap(), "3")
}

///|
test "Scanner split and sub act on the remainder" {
  let sc = @moonregex.compile(",").scanner("a,b,c")
  assert_eq(sc.split(), [Some("a"), Some("b"), Some("c")])
  let sc2 = @moonregex.compile("\\d").scanner("x1y2")
  assert_eq(sc2.sub("#"), "x#y#")
}

///|
test "version constants mirror regex.__version__" {
  assert_eq(@moonregex.version, "0.1.0")
  assert_eq(@moonregex.version_info, (0, 1, 0))
}

///|
test "Match partial reflects the compile-time partial flag" {
  let m = @moonregex.search("a", "a").unwrap()
  assert_false(m.partial())
  let p = @moonregex.compile("a", partial=true)
  let m2 = p.search("a").unwrap()
  assert_true(m2.partial())
}

///|
test "subf formats the whole match and groups" {
  // {} is the whole match; substitution is in-place, keeping the rest.
  assert_eq(@moonregex.subf("\\d+", "({})", "order 42"), "order (42)")
  // {name} names a group; {n} reorders the captured parts.
  let pat = @moonregex.compile("(?P<w>\\w+)=(?P<n>\\d+)")
  assert_eq(pat.subf("a=1 b=22", "{n}:{w}"), "1:a 22:b")
}

///|
test "subf applies alignment, width and precision" {
  // Right-align in a field of 5.
  assert_eq(@moonregex.subf("\\d+", "[{0:>5}]", "7"), "[    7]")
  // Left-align with a fill character.
  assert_eq(@moonregex.subf("\\d+", "[{0:*<5}]", "7"), "[7****]")
  // Precision truncates a string.
  assert_eq(@moonregex.subf("\\w+", "{0:.2}", "abcdef"), "ab")
}

///|
test "subf formats integer groups in other bases" {
  assert_eq(@moonregex.subf("\\d+", "{0:x}", "255"), "ff")
  assert_eq(@moonregex.subf("\\d+", "{0:X}", "255"), "FF")
  assert_eq(@moonregex.subf("\\d+", "{0:o}", "8"), "10")
  assert_eq(@moonregex.subf("\\d+", "{0:b}", "5"), "101")
}

///|
test "subfn returns the replacement count" {
  let (s, n) = @moonregex.subfn("\\d", "#", "1a2b3")
  assert_eq(s, "#a#b#")
  assert_eq(n, 3)
  let (s2, n2) = @moonregex.subfn("\\d", "#", "1a2b3", count=2)
  assert_eq(s2, "#a#b3")
  assert_eq(n2, 2)
}
