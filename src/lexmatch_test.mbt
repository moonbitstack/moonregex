// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The `lexmatch` grammar, with the two things it shares with Python: the
/// shorthand classes and named captures. A pattern moved from one grammar to
/// the other keeps its meaning, which is the point of reading both here.

///|
fn lexmatch_pattern(
  pattern : String,
) -> @moonregex.Pattern raise @moonregex.Refused {
  @moonregex.compile(pattern, dialect=@moonregex.lexmatch_dialect)
}

///|
/// Compile `pattern` as lexmatch and answer what the grammar said, so a
/// refusal can be read as text.
fn lexmatch_refusal(pattern : String) -> String {
  try {
    ignore(lexmatch_pattern(pattern))
    "accepted"
  } catch {
    @moonregex.Refused::Pattern(msg~, ..) => msg
    e => e.to_string()
  }
}

///|
test "the shorthand classes mean what Python means by them" {
  // `\d` is every decimal digit the UCD knows, not the ASCII ten.
  assert_eq(lexmatch_pattern("\\d+").findall("a12b٣٤"), [
    Some("12"),
    Some("٣٤"),
  ])
  assert_eq(lexmatch_pattern("\\w+").findall("héllo, 東京"), [
    Some("héllo"),
    Some("東京"),
  ])
  assert_eq(lexmatch_pattern("\\s+").findall("a \t b\u{00A0}c"), [
    Some(" \t "),
    Some("\u{00A0}"),
  ])
  // The negations are complements of the same sets.
  assert_eq(lexmatch_pattern("\\D+").findall("12ab"), [Some("ab")])
  assert_eq(lexmatch_pattern("\\W+").findall("ab, cd"), [Some(", ")])
  assert_eq(lexmatch_pattern("\\S+").findall(" ab cd "), [
    Some("ab"),
    Some("cd"),
  ])
}

///|
test "the shorthand classes work inside a class" {
  assert_eq(lexmatch_pattern("[\\d]+").findall("a12"), [Some("12")])
  assert_eq(lexmatch_pattern("[\\s\\d]+").findall("a 1\t2"), [Some(" 1\t2")])
  assert_eq(lexmatch_pattern("[^\\d]+").findall("12ab34"), [Some("ab")])
  // A range and a shorthand in the same class keep their own meanings.
  assert_eq(lexmatch_pattern("[a-f\\d]+").findall("abc123"), [Some("abc123")])
}

///|
test "a named capture is a named capture" {
  let p = lexmatch_pattern("(?<year>\\d{4})-(?<month>\\d{2})")
  assert_eq(p.groups(), 2)
  let m = p.search("on 2026-10-28").unwrap()
  assert_eq(m.group("year"), Some("2026"))
  assert_eq(m.group("month"), Some("10"))
  assert_eq(m.group(1), Some("2026"))
  assert_eq(m.span("month"), (8, 10))
}

///|
test "a lexmatch pattern still lowers onto the core engine" {
  // `\d` is written out as the ranges it stands for, so the core grammar can
  // read the pattern even though it has no shorthand class of its own.
  assert_true(lexmatch_pattern("(?<year>\\d{4})").lower() is Some(_))
  assert_true(lexmatch_pattern("\\w+\\s\\d+").lower() is Some(_))
  let core = lexmatch_pattern("(?<year>\\d{4})").lower().unwrap()
  assert_true(core.execute("2026") is Some(_))
  // The class is written out as ranges, so the core engine matches the same
  // text the parser's own set matches — `\w` is not the ASCII ten there.
  let word = lexmatch_pattern("\\w+").lower().unwrap()
  assert_true(word.execute("héllo") is Some(_))
  assert_true(word.execute("  ") is None)
}

///|
test "the grammar's own classes are untouched" {
  // The POSIX classes are what the core grammar offers instead of `\d`.
  assert_eq(lexmatch_pattern("[[:digit:]]+").findall("a12b"), [Some("12")])
  assert_eq(lexmatch_pattern("[[:alpha:]]+").findall("ab12"), [Some("ab")])
}

///|
test "what the grammar does not spell is refused where it is written" {
  // One modifier, spelled one way; the refusal says which.
  assert_eq(
    lexmatch_refusal("(?m:a)"),
    "lexmatch spells only the i modifier: (?i:…)",
  )
  assert_eq(
    lexmatch_refusal("(?s:a)"),
    "lexmatch spells only the i modifier: (?i:…)",
  )
  // One name, one group.
  assert_eq(
    lexmatch_refusal("(?<x>a)(?<x>b)"),
    "redefinition of group name 'x' as group 2",
  )
}

///|
test "the modifier the grammar has is still the modifier it had" {
  let p = lexmatch_pattern("(?i:ab)c")
  assert_eq(p.search("ABc").unwrap().content(), "ABc")
  assert_true(p.search("ABC") is None)
}
