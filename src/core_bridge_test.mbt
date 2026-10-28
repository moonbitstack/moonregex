// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Every match, with its groups, as one comparable string.
fn walked(
  pattern : @moonregex.Pattern,
  text : String,
) -> String raise @moonregex.Refused {
  let buf = StringBuilder::StringBuilder()
  for m in pattern.finditer(text) {
    buf.write_string("\{m.start()}-\{m.end()}")
    let mut slot = 1
    while slot <= pattern.groups() {
      buf.write_string("/")
      match m.group(group=@moonregex.Num(n=slot)) {
        None => buf.write_string("-")
        Some(g) => buf.write_string(g)
      }
      slot += 1
    }
    buf.write_string(";")
  }
  buf.to_string()
}

///|
/// The same five constructs spelled three ways, as the interface promises: a
/// Python pattern, the `lexmatch` spelling of it, and one assembled from the
/// combinators, all matching alike.
test "three spellings of one pattern agree" {
  let cases : Array[(String, String, String)] = [
    // Python spelling, lexmatch spelling, the text to walk
    ("a(b+)c", "a(b+)c", "xabbc abc"),
    ("cat|dog", "cat|dog", "a cat and a dog"),
    ("(ab)+", "(ab)+", "ababab ab"),
    ("a{2,3}b", "a{2,3}b", "aab aaab aaaab"),
    ("[0-9]+x", "[0-9]+x", "12x 7x x 3x"),
    ("^ab$", "^ab$", "ab\nab"),
    ("(a)(b)(c)", "(a)(b)(c)", "abc"),
    ("a.c", "a.c", "a c abc"),
  ]
  for (python, core_spelling, text) in cases {
    let py = @moonregex.compile(python)
    let core = @moonregex.compile(
      core_spelling,
      dialect=@moonregex.lexmatch_dialect,
    )
    assert_eq(walked(py, text), walked(core, text))
  }
}

///|
test "combinators build the same pattern as text" {
  // `cat|dog`, written and assembled.
  let written = @moonregex.compile("cat|dog")
  let assembled = @moonregex.Pattern::string("cat") |
    @moonregex.Pattern::string("dog")
  let text = "a cat and a dog and a cow"
  assert_eq(walked(written, text), walked(assembled, text))

  // `(ab)+c`, written and assembled.
  let written2 = @moonregex.compile("(ab)+c")
  let assembled2 = @moonregex.Pattern::string("ab")
    .capture("pair")
    .repeat(min=1) +
    @moonregex.Pattern::string("c")
  let text2 = "ababc xabc"
  assert_eq(walked(written2, text2), walked(assembled2, text2))

  // `(a)(b){2,3}`, written and assembled, groups and all.
  let written3 = @moonregex.compile("(a)(b){2,3}")
  let assembled3 = @moonregex.Pattern::string("a").capture("first") +
    @moonregex.Pattern::string("b").capture("rest").repeat(min=2, max=3)
  assert_eq(written3.groups(), assembled3.groups())
  assert_eq(walked(written3, "abb abbb"), walked(assembled3, "abb abbb"))
}

///|
test "a composed pattern knows its own group names" {
  let p = @moonregex.compile("x").capture("letter") + @moonregex.compile("(y)z")
  assert_eq(p.groups(), 2)
  assert_eq(p.groupindex().get("letter").unwrap(), [1])
  let m = p.search("xyz").unwrap()
  assert_eq(m.group(group=@moonregex.Name(n="letter")), Some("x"))
  assert_eq(m.group(group=@moonregex.Num(n=2)), Some("y"))
}

///|
test "lower hands the subset to the core engine, and it agrees" {
  let cases : Array[String] = [
    "abc", "a(b+)c", "cat|dog", "(ab)+c", "a{2,3}b", "[0-9]+", "^ab", "a.c", "(?<year>[0-9]{4})-(?<month>[0-9]{2})",
  ]
  let texts : Array[String] = [
    "xx abc yy", "a bbb c", "a cat and a dog", "ababc", "aab aaab", "x 123 y", "ab",
    "a c abc", "ab ab", "on 2026-10-28 ok",
  ]
  for pattern in cases {
    let p = @moonregex.compile(pattern)
    let lowered = p.lower()
    assert_true(lowered is Some(_))
    let core = lowered.unwrap()
    for text in texts {
      let ours = p.search(text)
      let theirs = core.execute(text)
      assert_eq(
        ours is Some(_),
        theirs is Some(_),
        msg="search(\{pattern}, \{text}) disagrees",
      )
      match (ours, theirs) {
        (Some(m), Some(c)) => {
          assert_eq(m.content().to_owned(), c.content().to_owned())
          assert_eq(m.before().to_owned(), c.before().to_owned())
          assert_eq(m.after().to_owned(), c.after().to_owned())
        }
        _ => ()
      }
    }
  }
}

///|
test "lower refuses what the core engine cannot run" {
  let outside : Array[String] = [
    "(a)\\1", "a(?=b)", "(?<=a)b", "(?>ab)", "a*+", "\\X", "a$\\n", "(a)(?(1)b|c)",
    // Python's `$` also sits before a final newline; the core engine's does
    // not, so the two are not the same assertion.
     "^ab$",
    // Python's `\b` is a Unicode word boundary; the core engine's is ASCII.
     "\\bab\\b", "(?R)", "(?:ab){e<=1}",
  ]
  for pattern in outside {
    let p = @moonregex.compile(pattern)
    assert_true(p.lower() is None, msg="\{pattern} should not lower")
  }
}

///|
test "Match carries the core view alongside the Python one" {
  let m = @moonregex.search("b+", "aabbbcc").unwrap()
  assert_eq(m.before().to_owned(), "aa")
  assert_eq(m.content().to_owned(), "bbb")
  assert_eq(m.after().to_owned(), "cc")
  // And the Python spelling of the same three.
  assert_eq(m.group().unwrap(), "bbb")
  assert_eq(m.start(), 2)
  assert_eq(m.end(), 5)
}

///|
test "escape follows the grammar it is told" {
  // Python: the characters that can mean something take a backslash.
  assert_eq(@moonregex.escape("a.b*c"), "a\\.b\\*c")
  assert_eq(@moonregex.escape("a b"), "a\\ b")
  assert_eq(@moonregex.escape("a b", literal_spaces=true), "a b")
  assert_eq(@moonregex.escape("-"), "\\-")
  // ECMA-262: `RegExp.escape`, which spells punctuation out in hex and
  // protects a leading alphanumeric.
  assert_eq(@moonregex.escape("a.b", dialect=@moonregex.ecma262), "\\x61\\.b")
  assert_eq(@moonregex.escape("-", dialect=@moonregex.ecma262), "\\x2D")
  assert_eq(@moonregex.escape("$", dialect=@moonregex.ecma262), "\\$")
  assert_eq(@moonregex.escape(" ", dialect=@moonregex.ecma262), "\\x20")
  assert_eq(@moonregex.escape("/", dialect=@moonregex.ecma262), "\\/")
  // lexmatch: its own metacharacters, and no `\x..` at all.
  assert_eq(
    @moonregex.escape("a.b", dialect=@moonregex.lexmatch_dialect),
    "a\\.b",
  )
  assert_eq(
    @moonregex.escape("a\tb", dialect=@moonregex.lexmatch_dialect),
    "a\\tb",
  )
}

///|
test "escape produces a pattern that matches the text literally" {
  let sample = "a.b*c[d]e(f){g}|h^i$j\\k+l?m"
  for d in [@moonregex.python, @moonregex.ecma262, @moonregex.lexmatch_dialect] {
    let escaped = @moonregex.escape(sample, dialect=d)
    let p = @moonregex.compile(escaped, dialect=d)
    assert_true(p.full(sample) is Some(_), msg="escape under \{d}")
  }
}

///|
test "a word boundary follows the Unicode word set unless the grammar says ASCII" {
  // `é` is a word character in Unicode, so there is no boundary inside "aé".
  let uni = @moonregex.compile("\\ba\\b")
  assert_true(uni.search("aé") is None)
  // Under the ASCII reading it is a boundary, because `é` is not a word
  // character there.
  let ascii = @moonregex.compile("\\ba\\b", flags=@moonregex.a)
  assert_true(ascii.search("aé") is Some(_))
}

///|
test "a grapheme cluster is what the UCD says it is" {
  // `e` plus a combining acute is one cluster.
  let p = @moonregex.compile("\\X")
  let m = p.search("e\u{301}x").unwrap()
  assert_eq(m.content(), "e\u{301}")
  // A flag sequence and a family emoji are single clusters too.
  let flag = p.search("🇯🇵").unwrap()
  assert_eq(flag.content(), "🇯🇵")
  let family = p.search("👨‍👩‍👧").unwrap()
  assert_eq(family.content(), "👨‍👩‍👧")
}
