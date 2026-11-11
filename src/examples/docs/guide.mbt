// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The guide: `docs/guide.html`.

///|
test "guide/first-match" {
  // docs:begin first-match
  let m = @moonregex.search("\\d{4}", "copyright 2026").unwrap()
  // docs:end
  assert_eq(m.content(), "2026")
  assert_eq(m.start(0), 10)
  assert_eq(m.end(0), 14)
}

///|
test "guide/reuse" {
  // docs:begin reuse
  let year = @moonregex.compile("\\d{4}")
  assert_eq(year.findall("1999 and 2026"), [Some("1999"), Some("2026")])
  // docs:end
}

///|
test "guide/refusal" {
  // docs:begin refusal
  let (message, at) = try {
    let _ = @moonregex.compile("(a")
    ("", 0)
  } catch {
    @moonregex.Refused::Pattern(msg~, at~, ..) => (msg, at)
    e => raise e
  }
  // docs:end
  assert_eq(message, "missing ), unterminated group")
  assert_eq(at, 2)
}

///|
test "guide/anchors" {
  // docs:begin anchors
  let word = @moonregex.compile("[a-z]+")
  assert_true(word.search("  hello ") is Some(_))
  assert_true(word.prefix("  hello ") is None)
  assert_true(word.full("hello") is Some(_))
  // docs:end
  assert_eq(word.search("  hello ").unwrap().start(0), 2)
}

///|
test "guide/groups" {
  // docs:begin groups
  let p = @moonregex.compile("(?<year>\\d{4})-(?<month>\\d{2})")
  let m = p.search("on 2026-10-28").unwrap()
  assert_eq(m.group(1), Some("2026"))
  assert_eq(m.group("month"), Some("10"))
  assert_eq(m.span("month"), (8, 10))
  assert_eq(m.groups(), [Some("2026"), Some("10")])
  assert_eq(m.groupdict(), { "year": "2026", "month": "10" })
  // docs:end
  assert_eq(m.captures("month"), ["10"])
}

///|
test "guide/no-participation" {
  // docs:begin no-participation
  let m = @moonregex.compile("(a)|(b)").search("b").unwrap()
  assert_eq(m.group(1), None)
  assert_eq(m.group(2), Some("b"))
  // docs:end
}

///|
test "guide/findall-groups" {
  let p = @moonregex.compile("(\\w+)=(\\d+)")
  // docs:begin findall-groups
  assert_eq(p.findall("a=1", group=Num(n=1)), [Some("a")])
  assert_eq(p.finditer("a=1").length(), 1)
  // docs:end
  // Answering no group when there are two of them is the refusal the page names.
  assert_true(
    try {
      let _ = p.findall("a=1")
      false
    } catch {
      @moonregex.Refused::Ambiguous(groups~) => groups == 2
      e => raise e
    },
  )
}

///|
test "guide/replace" {
  // docs:begin replace
  assert_eq(@moonregex.sub("\\s+", " ", "a   b  c"), "a b c")
  assert_eq(@moonregex.subn("\\d", "#", "a1b2"), ("a#b#", 2))

  let parts = @moonregex.split("\\s*,\\s*", "a , b,c")
  assert_eq(parts, [Some("a"), Some("b"), Some("c")])
  // docs:end
}

///|
test "guide/replace-function" {
  // docs:begin replace-function
  assert_eq(@moonregex.sub("(\\w+)@(\\w+)", "\\g<2>:\\g<1>", "u@h"), "h:u")

  let shouted = @moonregex.sub_with(
    "\\d+",
    m => "<" + m.content().to_owned() + ">",
    "a1b",
  )
  // docs:end
  assert_eq(shouted, "a<1>b")
}

///|
test "guide/flags" {
  // docs:begin flags
  let icase = @moonregex.Flags::new(ignorecase=true)
  let p = @moonregex.compile("hello", flags=icase)
  assert_true(p.full("HeLLo") is Some(_))
  // docs:end
}

///|
test "guide/inline-flags" {
  // docs:begin inline-flags
  let p = @moonregex.compile("(?i)hello")
  assert_true(p.full("HELLO") is Some(_))

  let q = @moonregex.compile("(?i:hello) world")
  assert_true(q.full("HELLO world") is Some(_))
  assert_true(q.full("HELLO WORLD") is None)
  // docs:end
}

///|
test "guide/case" {
  // docs:begin case
  // A group is read under the flags around it; a reference is compared under
  // the flags around the reference. When the two differ, the reference wins.
  let caseless = @moonregex.compile("(?i)(?-i:(a))\\1")
  assert_eq(caseless.search("aA").unwrap().content(), "aA")

  // The same pattern the other way round: the group is caseless, so it can
  // take either letter, and the reference insists on the one it captured.
  let exact = @moonregex.compile("(?i:(a))\\1")
  assert_true(exact.search("AA") is Some(_))
  assert_true(exact.search("aA") is None)
  // docs:end
}

///|
test "guide/case-alphabet" {
  // docs:begin case-alphabet
  // The comparison is per code point over every script, not ASCII alone.
  assert_true(@moonregex.compile("(?i)(é)\\1").full("éÉ") is Some(_))
  assert_true(@moonregex.compile("(?i)(k)\\1").full("k\u{212A}") is Some(_))
  // docs:end
}

///|
test "guide/case-folding" {
  // docs:begin case-folding
  // `f` folds over more than one character: `ß` is `ss`, and `ss` is `ß`.
  let sharp = @moonregex.compile("(?fi)ß")
  assert_eq(sharp.full("SS").unwrap().span(0), (0, 2))
  assert_eq(@moonregex.compile("(?fi)ss").full("ß").unwrap().span(0), (0, 1))

  // A class and a reference fold the same way.
  assert_eq(@moonregex.compile("(?fi)[ß]").full("ss").unwrap().span(0), (0, 2))
  assert_eq(
    @moonregex.compile("(?fi)(ß)\\1").full("ssSS").unwrap().span(0),
    (0, 4),
  )
  // docs:end
}

///|
test "guide/ecma" {
  // docs:begin ecma
  let p = @moonregex.compile("^[a-z]+$", dialect=@moonregex.ecma262)
  assert_true(p.full("abc") is Some(_))
  assert_true(p.full("ABC") is None)
  // docs:end
}

///|
test "guide/lexmatch" {
  // docs:begin lexmatch
  let tag = @moonregex.compile(
    "(?<name>\\w+)=(?<value>\\d+)",
    dialect=@moonregex.lexmatch_dialect,
  )
  assert_eq(tag.search("size=42").unwrap().group("value"), Some("42"))
  // `\d` is every decimal digit the UCD knows, not the ASCII ten.
  assert_eq(tag.findall("a=1 b=٢", group=Name(n="value")), [
    Some("1"),
    Some("٢"),
  ])
  // docs:end
  assert_true(tag.lower() is Some(_))
}

///|
test "guide/unicode" {
  // docs:begin unicode
  let words = @moonregex.findall("\\p{Lu}\\p{Ll}+", "Paris and Αθήνα")
  assert_eq(words, [Some("Paris"), Some("Αθήνα")])

  let han = @moonregex.compile("\\p{Script=Han}+")
  assert_eq(han.findall("漢字 and kana"), [Some("漢字")])

  let latin = @moonregex.compile("\\p{Block=Basic Latin}+")
  assert_eq(latin.findall("abcé"), [Some("abc")])
  // docs:end
}

///|
test "guide/grapheme" {
  // docs:begin grapheme
  let p = @moonregex.compile("\\X")
  let cluster = p.search("e\u{301}x").unwrap().content()
  // docs:end
  // Two code points, one cluster.
  assert_eq(cluster, "e\u{301}")
  assert_eq(cluster.length(), 2)
}

///|
test "guide/compose" {
  // docs:begin compose
  let date = @moonregex.compile("\\d{4}").capture("year") +
    @moonregex.compile("-") +
    @moonregex.compile("\\d{2}").capture("month")
  let m = date.prefix("2026-10").unwrap()
  assert_eq(m.group("month"), Some("10"))
  assert_eq(m.before(), "")
  assert_eq(m.after(), "")
  // docs:end
}

///|
test "guide/lower" {
  // The pattern the previous block built, written again because a page block has
  // to stand on its own.
  let date = @moonregex.compile("\\d{4}").capture("year") +
    @moonregex.compile("-") +
    @moonregex.compile("\\d{2}").capture("month")
  // docs:begin lower
  let core = date.lower().unwrap()
  assert_true(core.execute("2026-10") is Some(_))
  // docs:end
  // A pattern with a backreference stays on this engine, and answers None.
  assert_true(@moonregex.compile("(a)\\1").lower() is None)
}

///|
test "guide/limit" {
  // docs:begin limit
  let stopped = try {
    let _ = @moonregex.full("(a+)+b", "aaaaaaaaaaaaaaaaaaaa", limit=100)
    None
  } catch {
    @moonregex.Refused::Exceeded(limit~, got~) => Some((limit, got))
    e => raise e
  }
  // docs:end
  assert_eq(stopped, Some((100, 101)))
}

///|
test "guide/partial" {
  // docs:begin partial
  let p = @moonregex.compile("\\d{4}-\\d{2}", partial=true)
  let m = p.prefix("2026-").unwrap()
  assert_eq(m.content(), "2026-")
  assert_true(m.partial())
  // docs:end
  assert_false(p.prefix("2026-10").unwrap().partial())
}

///|
test "guide/globs" {
  // docs:begin globs
  assert_true(@glob.fnmatch("cat.txt", "*.txt"))
  assert_eq(@glob.filter(["a.txt", "b.csv"], "*.txt"), ["a.txt"])

  let g = @glob.Glob::compile("src/**/*.mbt")
  assert_true(g.matches("src/parse/lex.mbt"))
  assert_true(g.matches("src/lex.mbt"))
  // docs:end
}
