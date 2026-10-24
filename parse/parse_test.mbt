// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Parse `pattern` and, when it is refused, hand back the refusal; otherwise
/// report that nothing was wrong.
fn refused(pattern : String) -> @parse.Refused? {
  try {
    ignore(@parse.parse(pattern, flags=@parse.flags))
    None
  } catch {
    r => Some(r)
  }
}

///|
test "the tree prints back as a pattern" {
  // Plain atoms, sequences, alternation and groups.
  assert_eq(@parse.parse("a", flags=@parse.flags).dump(), "a")
  assert_eq(@parse.parse("ab", flags=@parse.flags).dump(), "ab")
  assert_eq(@parse.parse("a|b", flags=@parse.flags).dump(), "a|b")
  assert_eq(@parse.parse("(a)", flags=@parse.flags).dump(), "(a)")
  // Quantifiers round-trip in their canonical spelling.
  assert_eq(@parse.parse("a*", flags=@parse.flags).dump(), "a*")
  assert_eq(@parse.parse("a+", flags=@parse.flags).dump(), "a+")
  assert_eq(@parse.parse("a?", flags=@parse.flags).dump(), "a?")
  assert_eq(@parse.parse("a{2}", flags=@parse.flags).dump(), "a{2}")
  assert_eq(@parse.parse("a{2,3}", flags=@parse.flags).dump(), "a{2,3}")
  assert_eq(@parse.parse("a{0,1}", flags=@parse.flags).dump(), "a?")
  // A character class and its range.
  assert_eq(@parse.parse("[a-z]", flags=@parse.flags).dump(), "[a-z]")
  // A backreference keeps its slot.
  assert_eq(@parse.parse("(a)\\1", flags=@parse.flags).dump(), "(a)\\1")
  // A named group drops its name on the way to the tree.
  assert_eq(@parse.parse("(?P<name>a)", flags=@parse.flags).dump(), "(a)")
  // A lookahead.
  assert_eq(@parse.parse("(?=a)", flags=@parse.flags).dump(), "(?=a)")
}

///|
test "anchors take the grammar's meaning at parse time" {
  // Python's `^` without `m` is the text start, so it prints `\A`.
  assert_eq(@parse.parse("^a", flags=@parse.flags).dump(), "\\Aa")
  // And `$` is printed as `$` (it also sits before a trailing newline).
  assert_eq(@parse.parse("a$", flags=@parse.flags).dump(), "a$")
  // With `m`, `^` is the line start and prints as `^`.
  assert_eq(
    @parse.parse("^a", flags=@parse.Flags::new(multiline=true)).dump(),
    "^a",
  )
}

///|
/// The code-point offset, line and column a `Pattern` refusal stopped at.
///
/// The run-time refusals (`Exceeded`, `Ambiguous`) never arise from these
/// purely-parse tests, so only the `Pattern` variant is read here.
fn where_stopped(r : @parse.Refused) -> (Int32, Int32, Int32) {
  match r {
    @parse.Pattern(msg=_msg, at~, line~, column~) => (at, line, column)
    _ => (0, 0, 0)
  }
}

///|
test "refusals carry where reading stopped" {
  let (at, line, column) = where_stopped(refused("(").unwrap())
  assert_eq(at, 0)
  assert_eq(line, 1)
  assert_eq(column, 1)
  // A stray close parenthesis is reported at its position.
  let (at2, _, column2) = where_stopped(refused("a)").unwrap())
  assert_eq(at2, 1)
  assert_eq(column2, 2)
  // A quantifier with nothing before it.
  let (at3, _, _) = where_stopped(refused("*").unwrap())
  assert_eq(at3, 0)
  // A repeated anchor is refused: an assertion matches a position.
  let (at4, _, _) = where_stopped(refused("^*").unwrap())
  assert_eq(at4, 1)
}

///|
test "a class keeps its ranges and negation" {
  let az = @parse.parse("[a-z]", flags=@parse.flags).root()
  match az {
    Class(set~) => {
      // `a` through `z` is one contiguous range.
      assert_eq(set.ranges().length(), 1)
      assert_true(set.contains('m'.to_int()))
      assert_false(set.contains('5'.to_int()))
    }
    _ => assert_true(false)
  }
}

///|
test "flags fold into the nodes they touch" {
  // `(?i)a` folds the case set, so `A` must be in the tree for `a`.
  let node = @parse.parse("(?i)a", flags=@parse.flags).root()
  match node {
    Class(set~) => {
      assert_true(set.contains('a'.to_int()))
      assert_true(set.contains('A'.to_int()))
    }
    _ => assert_true(false)
  }
}

///|
test "group counts and names are learned" {
  // Python's `re.groups` counts the parenthesised groups only; group 0, the
  // whole match, is implicit and not tallied here.
  let ast = @parse.parse("(a)(?P<b>b)", flags=@parse.flags)
  assert_eq(ast.groups(), 2)
  // Group 2 is the one named `b`.
  let index = ast.groupindex()
  let slots = index.get("b").unwrap()
  assert_eq(slots[0], 2)
}
