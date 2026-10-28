// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One pattern, three spellings, one answer.
///
/// `[A-Z](\d)-(\d+)` is written in Python's grammar, in the `lexmatch` grammar
/// the core library speaks, and assembled from the combinators. All three are
/// the same kind of value and match alike; the first is then lowered onto the
/// core engine, and it answers the same again.
fn main raise {
  let text = "see L1-42 and L2-7"
  let py = @moonregex.compile("[A-Z](\\d)-(\\d+)")
  // The `lexmatch` grammar has no `\d`; its classes are spelled the POSIX way.
  let core = @moonregex.compile(
    "[A-Z]([0-9])-([0-9]+)",
    dialect=@moonregex.lexmatch_dialect,
  )
  // `Pattern::string` is a literal, so the assembled one spells its letters
  // and digs and leaves the classes to the written forms.
  let built = @moonregex.Pattern::string("L").capture("key") +
    @moonregex.Pattern::string("1").capture("page") +
    @moonregex.Pattern::string("-") +
    @moonregex.Pattern::string("42").capture("line")

  println("python:      " + walk(py, text))
  println("lexmatch:    " + walk(core, text))
  println("combinators: " + walk(built, "L1-42"))
  println(
    "python and lexmatch agree: " +
    (walk(py, text) == walk(core, text)).to_string(),
  )

  match py.lower() {
    None => println("lower: outside the core engine")
    Some(regex) =>
      match regex.execute(text) {
        None => println("lower: no match")
        Some(m) => println("lower: " + m.content().to_owned())
      }
  }
  println(
    "a backreference lowers: " +
    (@moonregex.compile("(a)\\1").lower() is Some(_)).to_string(),
  )
}

///|
/// Every match with its groups, as one line.
fn walk(pattern : @moonregex.Pattern, text : String) -> String raise {
  let parts : Array[String] = []
  for m in pattern.finditer(text) {
    let groups : Array[String] = []
    let mut slot = 1
    while slot <= pattern.groups() {
      groups.push(m.group(slot).unwrap_or("?"))
      slot += 1
    }
    parts.push(groups.join("/"))
  }
  " [" + parts.join(" ") + "]"
}
