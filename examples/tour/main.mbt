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
  println(@moonregex.search("\\d+", "order 42").unwrap().group().unwrap())
  println(
    "match_at at the start: " +
    (@moonregex.match_at("\\d+", "order 42") is None).to_string(),
  )

  // findall collects one capture per match.
  println("findall: " + show(@moonregex.findall("(\\w+)=(\\d+)", "a=1 b=2")))

  // split keeps the captured separators.
  println("split: " + show(@moonregex.split("(\\s+)", "a  b\tc")))

  // sub with a callable replacement.
  let numbered = @moonregex.sub_by(
    "(\\w+)",
    fn(m) -> String raise @moonregex.Refused {
      match m.group() {
        Some(s) => s.to_upper()
        None => ""
      }
    },
    "hello world",
  )
  println("sub_by: " + numbered)

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
    Some(m) =>
      println(
        "named group: " + m.group(group=@moonregex.Name(n="word")).unwrap(),
      )
  }
}
