// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The command this repository installs: a quick taste of the surface.
///
///     moon run bin
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
/// The command this repository installs: a quick taste of the surface.
///
///     moon run bin
#coverage.skip
fn main raise {
  let text = "The quick brown fox jumps over 13 lazy dogs."
  match @moonregex.search("\\w+", text) {
    None => println("no match")
    Some(m) => println("first word: " + m.group().unwrap())
  }
  println("all words: " + show(@moonregex.findall("\\w+", text)))
  let count = @moonregex.subn("\\w+", "X", text).1
  println("how many words: \{count}")
  let swapped = @moonregex.sub("(\\w+) (\\w+)", "\\2 \\1", "folded cart")
  println("swapped: " + swapped)
}
