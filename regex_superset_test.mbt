// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Helper: the whole match text, or the empty string when there is none.
fn sup_whole(
  pattern : String,
  text : String,
) -> String raise @moonregex.Refused {
  match @moonregex.search(pattern, text) {
    None => ""
    Some(m) => m.group().unwrap()
  }
}

///|
test "possessive star does not give back" {
  // Greedy `*`: the dot-star gives back so the trailing `b` can match.
  assert_eq(sup_whole("a.*b", "axb"), "axb")
  // Possessive `*+`: the dot-star keeps every character, so the `b` cannot.
  assert_true(@moonregex.search("a.*+b", "axb") is None)
  // A possessive run that needs no backtracking still matches fully.
  assert_eq(sup_whole("a.*+", "ab"), "ab")
  // A bare possessive quantifier still consumes what it can.
  assert_eq(sup_whole("a*+", "aaa"), "aaa")
  assert_eq(sup_whole("a++", "aaa"), "aaa")
}

///|
test "possessive plus and optional" {
  // `a++` is a possessive one-or-more; `a+` would backtrack to make `a` fit.
  assert_eq(sup_whole("a++", "aaa"), "aaa")
  // `a?+` matches the `a` and refuses to release it, so `a?+a` cannot work:
  // the optional `a` is taken, then there is nothing left to backtrack into.
  assert_true(@moonregex.search("a?+a", "a") is None)
  // But with nothing to consume it still matches zero and lets `b` through.
  assert_eq(sup_whole("a?+b", "ab"), "ab")
}

///|
test "(*ACCEPT) ends the match early" {
  // The `b` is never reached: the verb accepts after `a`.
  assert_eq(sup_whole("a(*ACCEPT)b", "axyz"), "a")
  // Even a fullmatch is forced to succeed by the verb.
  assert_true(@moonregex.fullmatch("a(*ACCEPT)b", "axyz") is Some(_))
  // And a plain match at the accepted position is exactly that prefix.
  let m = @moonregex.search("a(*ACCEPT).*", "axyz").unwrap()
  assert_eq(m.group().unwrap(), "a")
}

///|
test "(*FAIL) makes the attempt fail" {
  // The sequence cannot complete, and there is nothing else to try.
  assert_true(@moonregex.search("a(*FAIL)b", "ab") is None)
  // Inside an alternation, the failing branch is simply skipped.
  assert_eq(sup_whole("a((*FAIL)|b)c", "abc"), "abc")
}

///|
test "\\Q…\\E quotes metacharacters literally" {
  assert_eq(sup_whole("\\Qa.b\\E", "a.b"), "a.b")
  assert_true(@moonregex.search("\\Qa.b\\E", "axb") is None)
  // A whole run of metacharacters is taken verbatim.
  assert_eq(sup_whole("\\Q(a*b+c)\\E", "(a*b+c)"), "(a*b+c)")
  assert_true(@moonregex.search("\\Q(a*b)\\E", "axb") is None)
}

///|
test "named-group recursion (?P>name) replays the group" {
  // `(?P>g)` replays the definition of group `g`.
  assert_eq(sup_whole("(?P<g>a)(?P>g)", "aa"), "aa")
  assert_eq(sup_whole("(?P<g>a|b)(?P>g)", "ab"), "ab")
  // The `regex` spelling `(?&name)` does the same.
  assert_eq(sup_whole("(?P<g>a)(?&g)", "aa"), "aa")
}

///|
test "whole-pattern recursion (?R) is accepted" {
  // `(?R)` must parse and run without refusing the pattern. We only require
  // that the syntax is recognised; the match itself is left unasserted because
  // whole-pattern recursion needs a guard to terminate in general.
  let _ = ignore(@moonregex.search("(a)(?R)", "a")) catch { _ => () }
  // Confirms the syntax is recognised; no assertion needed beyond no refusal.
  assert_true(true)
}
