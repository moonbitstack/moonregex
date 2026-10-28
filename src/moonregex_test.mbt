// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Helper: the whole match text, or fail the test.
fn whole(pattern : String, text : String) -> String raise @moonregex.Refused {
  match @moonregex.search(pattern, text) {
    None => ""
    Some(m) => m.group().unwrap()
  }
}

///|
/// Helper: the whole full match text, or the empty string when it does not fit.
fn full(pattern : String, text : String) -> String raise @moonregex.Refused {
  match @moonregex.full(pattern, text) {
    None => ""
    Some(m) => m.group().unwrap()
  }
}

///|
test "search returns the leftmost match" {
  assert_eq(whole("\\d+", "order 42"), "42")
  assert_eq(whole("\\w+", "  abc def"), "abc")
}

///|
test "prefix anchors to the start only" {
  assert_true(@moonregex.prefix("\\d+", "42") is Some(_))
  assert_true(@moonregex.prefix("\\d+", "x42") is None)
}

///|
test "full requires the whole region" {
  assert_true(@moonregex.full("\\d+", "42") is Some(_))
  assert_true(@moonregex.full("\\d+", "42x") is None)
  assert_true(@moonregex.full("\\d+", "x42") is None)
}

///|
test "capturing groups come back in order" {
  let m = @moonregex.search("(\\w+) (\\w+)", "hello world").unwrap()
  assert_eq(m.group().unwrap(), "hello world")
  assert_eq(m.group(group=@moonregex.Num(n=1)).unwrap(), "hello")
  assert_eq(m.group(group=@moonregex.Num(n=2)).unwrap(), "world")
  assert_eq(m.groups(), [Some("hello"), Some("world")])
  assert_eq(m.lastindex().unwrap(), 2)
}

///|
test "named groups populate groupdict" {
  let m = @moonregex.search("(?P<first>\\w+) (?P<last>\\w+)", "hello world").unwrap()
  let gd = m.groupdict()
  assert_eq(gd["first"], "hello")
  assert_eq(gd["last"], "world")
  assert_eq(m.group(group=@moonregex.Name(n="first")).unwrap(), "hello")
  assert_eq(m.lastgroup().unwrap(), "last")
}

///|
test "ECMA-262 named groups, both spellings" {
  let a = @moonregex.search(
    "(?<word>\\w+)",
    "see spot",
    dialect=@moonregex.ecma262,
  ).unwrap()
  assert_eq(a.group(group=@moonregex.Name(n="word")).unwrap(), "see")
  let b = @moonregex.search(
    "(?'word'\\w+)",
    "see spot",
    dialect=@moonregex.ecma262,
  ).unwrap()
  assert_eq(b.group(group=@moonregex.Name(n="word")).unwrap(), "see")
  // Python keeps its own `(?P<name>` spelling, which must still work.
  let c = @moonregex.search("(?P<w>\\w+)", "x", dialect=@moonregex.python).unwrap()
  assert_eq(c.group(group=@moonregex.Name(n="w")).unwrap(), "x")
}

///|
test "findall collects whole matches when there are no groups" {
  assert_eq(@moonregex.findall("\\w+", "a b c"), [
    Some("a"),
    Some("b"),
    Some("c"),
  ])
}

///|
test "findall collects the single group when there is one" {
  assert_eq(@moonregex.findall("(\\d+)", "a1 b2 c3"), [
    Some("1"),
    Some("2"),
    Some("3"),
  ])
}

///|
test "split drops the separator when it is not captured" {
  assert_eq(@moonregex.split("\\s+", "a  b\tc"), [
    Some("a"),
    Some("b"),
    Some("c"),
  ])
}

///|
test "split keeps a captured separator" {
  assert_eq(@moonregex.split("(\\s+)", "a  b"), [
    Some("a"),
    Some("  "),
    Some("b"),
  ])
}

///|
test "sub swaps and counts" {
  assert_eq(
    @moonregex.sub("(\\w+) (\\w+)", "\\2 \\1", "folded cart"),
    "cart folded",
  )
  let r = @moonregex.subn("(\\w+) (\\w+)", "\\2 \\1", "folded cart")
  assert_eq(r.0, "cart folded")
  assert_eq(r.1, 1)
}

///|
test "sub_with rewrites with a callable" {
  assert_eq(
    @moonregex.sub_with(
      "\\w+",
      fn(m) -> String raise @moonregex.Refused {
        match m.group() {
          Some(s) => s.to_upper()
          None => ""
        }
      },
      "hello world",
    ),
    "HELLO WORLD",
  )
}

///|
test "escape quotes the metacharacters" {
  assert_eq(@moonregex.escape("a.b*c"), "a\\.b\\*c")
  assert_eq(@moonregex.escape("a.b*c", special_only=false), "a\\.b\\*c")
}

///|
test "anchors ^ and $ behave like Python" {
  assert_true(@moonregex.search("^a", "ba") is None)
  assert_true(@moonregex.search("^a", "ab") is Some(_))
  assert_true(@moonregex.search("c$", "abc") is Some(_))
  assert_true(@moonregex.search("c$", "cab") is None)
}

///|
test "alternation picks each branch" {
  assert_eq(@moonregex.findall("cat|dog", "cat and dog"), [
    Some("cat"),
    Some("dog"),
  ])
}

///|
test "a character class matches its members" {
  assert_eq(whole("[a-z]+", "123 abc 456"), "abc")
  assert_true(@moonregex.search("[0-9]", "abc 5") is Some(_))
}

///|
test "quantifiers are greedy by default, lazy with ?" {
  assert_eq(whole("a+", "aaa"), "aaa")
  assert_eq(whole("a+?", "aaa"), "a")
  assert_eq(whole("a*", "aaa"), "aaa")
}

///|
test "a backreference matches a repeated capture" {
  let m = @moonregex.search("(\\w+) \\1", "hello hello").unwrap()
  assert_eq(m.group(group=@moonregex.Num(n=1)).unwrap(), "hello")
  assert_true(@moonregex.search("(\\w+) \\1", "hello world") is None)
}

///|
test "ignorecase folds letters" {
  let flags = @moonregex.Flags::new(ignorecase=true)
  assert_true(@moonregex.search("ABC", "abc", flags~) is Some(_))
  assert_true(@moonregex.search("abc", "ABC", flags~) is Some(_))
}

///|
test "multiline lets ^ and $ see line edges" {
  let flags = @moonregex.Flags::new(multiline=true)
  assert_true(@moonregex.search("^b", "a\nb", flags~) is Some(_))
  assert_true(@moonregex.search("^b", "a\nb", flags=@moonregex.flags) is None)
}

///|
test "span and start/end are code points" {
  let m = @moonregex.search("世界", "hello 世界 end").unwrap()
  assert_eq(m.group().unwrap(), "世界")
  assert_eq(m.start(), 6)
  assert_eq(m.end(), 8)
  let s = m.span()
  assert_eq(s.0, 6)
  assert_eq(s.1, 8)
}

///|
test "finditer walks every match in order" {
  let ms = @moonregex.finditer("\\d+", "a1 b22 c333")
  assert_eq(ms.length(), 3)
  assert_eq(ms[0].group().unwrap(), "1")
  assert_eq(ms[1].group().unwrap(), "22")
  assert_eq(ms[2].group().unwrap(), "333")
}

///|
test "split stops after maxsplit" {
  assert_eq(@moonregex.split(":", "a:b:c:d", maxsplit=2), [
    Some("a"),
    Some("b"),
    Some("c:d"),
  ])
}

///|
test "escape leaves alphanumerics and escapes the rest" {
  assert_eq(@moonregex.escape("a1.b2"), "a1\\.b2")
  assert_eq(@moonregex.escape("a b", literal_spaces=true), "a b")
}

///|
/// Fuzzy matching over a literal run: a bounded Levenshtein budget of
/// insertions, deletions and substitutions, as mrab-regex spells
/// `{e<=n}`, `{i<=n}`, `{d<=n}`, `{s<=n}`.
test "fuzzy tolerates one error of any kind" {
  // exact still works, and beats a longer edited match
  assert_eq(whole("(?:abc){e<=1}", "abc"), "abc")
  // one substitution: c -> d
  assert_eq(whole("(?:abc){e<=1}", "abd"), "abd")
  // one deletion: drop the trailing c
  assert_eq(whole("(?:abc){e<=1}", "ab"), "ab")
  // one insertion: skip the stray X in the middle
  assert_eq(whole("(?:abc){e<=1}", "aXbc"), "aXbc")
  // two errors exceed the budget of one
  assert_true(@moonregex.search("(?:abc){e<=1}", "axy") is None)
}

///|
test "fuzzy budgets are scoped per operation" {
  // deletions only: an insertion is not allowed, so the whole string cannot be
  // spanned by an inserted character
  assert_eq(full("(?:abc){d<=1}", "ab"), "ab")
  assert_true(@moonregex.full("(?:abc){d<=1}", "abcd") is None)
  // insertions only: a deletion is not allowed
  assert_eq(full("(?:abc){i<=1}", "abcd"), "abcd")
  assert_true(@moonregex.full("(?:abc){i<=1}", "ab") is None)
  // substitutions only
  assert_eq(full("(?:abc){s<=1}", "abd"), "abd")
  assert_true(@moonregex.full("(?:abc){s<=1}", "ab") is None)
}

///|
test "fuzzy matches a class run" {
  assert_eq(whole("(?:[ab]c){e<=1}", "ac"), "ac")
  // substitution of the class char: x -> a is one error
  assert_eq(whole("(?:[ab]c){e<=1}", "xc"), "xc")
}

///|
test "fuzzy full measures the whole region" {
  let flags = @moonregex.flags
  assert_true(@moonregex.full("(?:hello){e<=1}", "hellp", flags~) is Some(_))
  // two errors exceed the budget, so the whole string cannot be matched
  assert_true(@moonregex.full("(?:hello){e<=1}", "helloxx", flags~) is None)
}
