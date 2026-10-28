// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The whole surface in one run, so a reader can see what this is for before
/// reading any of it.
///
///     moon run examples/tour
#coverage.skip
fn show(a : Array[String?]) -> String {
  let buf = StringBuilder::StringBuilder()
  buf.write_char('[')
  let mut i = 0
  for x in a {
    if i > 0 {
      buf.write_string(", ")
    }
    match x {
      None => buf.write_string("None")
      Some(s) => buf.write_string(s)
    }
    i += 1
  }
  buf.write_char(']')
  buf.to_string()
}

///|
/// The whole surface in one run, so a reader can see what this is for before
/// reading any of it.
///
///     moon run examples/tour
#coverage.skip
fn main raise {
  // A plain search and a forced match-at-start.
  println(@moonregex.search("\\d+", "order 42").unwrap().group(0).unwrap())
  println(
    "prefix at the start: " +
    (@moonregex.prefix("\\d+", "order 42") is None).to_string(),
  )

  // findall collects one capture per match.
  println("findall: " + show(@moonregex.findall("(\\w+)=(\\d+)", "a=1 b=2")))

  // split keeps the captured separators.
  println("split: " + show(@moonregex.split("(\\s+)", "a  b\tc")))

  // sub with a callable replacement.
  let numbered = @moonregex.sub_with(
    "(\\w+)",
    fn(m) -> String raise @moonregex.Refused {
      match m.group(0) {
        Some(s) => s.to_upper()
        None => ""
      }
    },
    "hello world",
  )
  println("sub_with: " + numbered)

  // case-insensitive and multiline flags.
  let rx = @moonregex.compile(
    "^line",
    flags=@moonregex.Flags::new(ignorecase=true, multiline=true),
  )
  println(
    "anchored, case-insensitive: " +
    (rx.search("LINE\nline") is Some(_)).to_string(),
  )

  // a named group.
  match @moonregex.search("(?P<word>\\w+)", "see spot") {
    None => ()
    Some(m) => println("named group: " + m.group("word").unwrap())
  }

  // a named Unicode character and a line break.
  println(
    "named char: " +
    (@moonregex.full("\\N{EM DASH}", "\u{2014}") is Some(_)).to_string(),
  )
  println(
    "line break: " + (@moonregex.full("\\R", "\u{2028}") is Some(_)).to_string(),
  )

  // a control verb: (*COMMIT) aborts the whole match.
  println(
    "commit: " + (@moonregex.search("a(*COMMIT)b", "ab") is None).to_string(),
  )

  // branch reset: (?|(a)|(b)) captures to group 1 either way.
  println(
    "branch reset: " +
    (@moonregex.full("(?|(a)|(b))", "b") is Some(_)).to_string(),
  )

  // (?(DEFINE)…) declares a subroutine, then recursion calls it.
  let grammar = @moonregex.compile("(?(DEFINE)(?P<num>\\d+))(?P>num)")
  println("define+recursion: " + (grammar.full("12345") is Some(_)).to_string())
}
