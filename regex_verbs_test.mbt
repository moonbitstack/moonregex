// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The completion pass: control verbs (COMMIT/PRUNE/SKIP/THEN/MARK/LIMIT/
/// VERSION/FENCE), the newline and whitespace escapes, braced backreferences,
/// branch reset, `(?(DEFINE)…)` and recursion conditions.

///|
test "line-break and whitespace escapes match their Unicode sets" {
  // \R and \v match any of the line separators.
  assert_eq(whole("a\\Rb", "a\r\nb"), "") // CR alone is matched by \R, then \n breaks it
  assert_true(@moonregex.fullmatch("\\R", "\u{2028}") is Some(_)) // line separator
  assert_true(@moonregex.fullmatch("\\R", "\n") is Some(_))
  // \h matches tab and space but not a newline; \H is its complement.
  assert_true(@moonregex.fullmatch("\\h+", " \t\u{00A0}") is Some(_))
  assert_true(@moonregex.fullmatch("\\H", "a") is Some(_))
  // A newline is not horizontal whitespace, so \H matches it.
  assert_true(@moonregex.fullmatch("\\H", "\n") is Some(_))
  // \N matches anything but a newline.
  assert_true(@moonregex.fullmatch("\\N", "x") is Some(_))
  assert_true(@moonregex.fullmatch("\\N", "\n") is None)
}

///|
test "escape char and braced backreferences" {
  assert_true(@moonregex.fullmatch("\\e", "\u{001B}") is Some(_))
  // Perl \g{name} / \g{n} next to the \g<…> spelling.
  let pat = @moonregex.compile("(?P<w>\\w+) \\g{w}")
  assert_true(pat.fullmatch("go go") is Some(_))
  let pat2 = @moonregex.compile("(\\w+) \\g{1}")
  assert_true(pat2.fullmatch("go go") is Some(_))
}

///|
test "(*COMMIT) fails the whole match and stops the search" {
  // Without COMMIT, the engine would backtrack and find a later start.
  assert_true(@moonregex.search("a(*COMMIT)b", "ab") is None)
  assert_true(@moonregex.search("a(*COMMIT)b", "aab") is None)
  // A committed failure is not rescued by a later alternative.
  assert_true(@moonregex.search("(a(*COMMIT)b)|b", "ab") is None)
}

///|
test "(*PRUNE) and (*THEN) fail the current branch" {
  assert_true(@moonregex.search("a(*PRUNE)b|b", "b") is Some(_))
  assert_true(@moonregex.search("a(*THEN)b|b", "b") is Some(_))
}

///|
test "(*MARK) and (*SKIP) skip past the marked position" {
  // A mark set at the start of the attempt: `(*SKIP:M)` aborts the first
  // branch and resumes the search just past the mark, where `b` then matches.
  let m = @moonregex.search("(*MARK:M)a(*SKIP:M)(*F)|b", "ab").unwrap()
  assert_eq(m.group().unwrap(), "b")
  assert_eq(m.start(), 1)
}

///|
test "(*MARK) names are reported on the match" {
  let m = @moonregex.search("a(*MARK:one)(*MARK:two)", "a").unwrap()
  assert_eq(m.marks(), ["one", "two"])
}

///|
test "(*LIMIT_MATCH:n) and (*LIMIT_RECURSION:n) are accepted" {
  assert_true(@moonregex.fullmatch("(*LIMIT_MATCH:1000)a", "a") is Some(_))
  assert_true(@moonregex.fullmatch("(*LIMIT_RECURSION:10)a", "a") is Some(_))
}

///|
test "(*VERSION) and (*FENCE) parse and run" {
  assert_true(@moonregex.fullmatch("a(*VERSION)", "a") is Some(_))
  // FENCE is a barrier, not a failure: the match still succeeds.
  assert_true(@moonregex.fullmatch("a(*FENCE)b", "ab") is Some(_))
}

///|
test "branch reset (?|…) renumbers groups per alternative" {
  let m = @moonregex.search("(?|(a)|(b)(c))", "bc").unwrap()
  // Both alternatives capture to group 1; the second also opens group 2.
  assert_eq(m.group(group=@moonregex.Num(n=1)).unwrap(), "b")
  assert_eq(m.group(group=@moonregex.Num(n=2)).unwrap(), "c")
  assert_true(@moonregex.fullmatch("(?|(a)|(b))", "a") is Some(_))
  assert_true(@moonregex.fullmatch("(?|(a)|(b))", "b") is Some(_))
}

///|
test "(?(DEFINE)…) declares subroutines and matches empty" {
  // A grammar rule defined once, then called via recursion.
  let pat = @moonregex.compile("(?(DEFINE)(?P<num>\\d+))(?P>num)")
  assert_true(pat.fullmatch("12345") is Some(_))
}

///|
test "recursion conditions (?(R)…) select branches" {
  // (?R) is true only inside a recursion, so a balanced-paren pattern works.
  let pat = @moonregex.compile("\\((?:[^()]|(?R))*\\)")
  assert_true(pat.fullmatch("(a(b)c)") is Some(_))
  assert_true(pat.fullmatch("(a(b)c") is None)
}

///|
test "(*PRUNE) aborts the current position without backtracking" {
  // With FAIL, the `ac` alternative would rescue the match; PRUNE does not.
  assert_true(@moonregex.search("a(*FAIL)b|ac", "ac") is Some(_))
  assert_true(@moonregex.search("a(*PRUNE)b|ac", "ac") is None)
}

///|
test "relative backreference \\g{-1} names the last group" {
  assert_true(@moonregex.fullmatch("(a)\\g{-1}", "aa") is Some(_))
  assert_true(@moonregex.fullmatch("(a)(b)\\g{-1}", "abb") is Some(_))
  assert_true(@moonregex.fullmatch("(a)(b)\\g{-1}", "aba") is None)
  assert_true(@moonregex.fullmatch("(a)(b)\\g{-2}", "aba") is Some(_))
}

///|
test "\\N{name} matches a named Unicode character" {
  assert_true(@moonregex.fullmatch("\\N{EM DASH}", "\u{2014}") is Some(_))
  assert_true(@moonregex.fullmatch("\\N{SNOWMAN}", "\u{2603}") is Some(_))
  assert_true(@moonregex.fullmatch("\\N{LATIN SMALL LETTER A}", "a") is Some(_))
  // Control aliases and algorithmic CJK names.
  assert_true(@moonregex.fullmatch("\\N{TAB}", "\t") is Some(_))
  assert_true(
    @moonregex.fullmatch("\\N{CJK UNIFIED IDEOGRAPH-4E00}", "\u{4E00}")
    is Some(_),
  )
}
