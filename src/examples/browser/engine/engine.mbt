// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
let hex_digits : Array[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
/// `\uXXXX`, the four-digit form JSON wants (never `\u{…}`).
fn hex4(code : Int32) -> String {
  let buf = StringBuilder::StringBuilder()
  buf.write_string("\\u")
  let mut shift = 12
  while shift >= 0 {
    buf.write_char(hex_digits[(code >> shift) & 0xF])
    shift -= 4
  }
  buf.to_string()
}

///|
/// A JSON string literal, escaped: quotes, the backslash, the five short
/// escapes, and every other control character as `\u00XX`.
fn quote(text : String) -> String {
  let buf = StringBuilder::StringBuilder()
  buf.write_char('"')
  for c in text {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{08}' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      _ =>
        if c.to_int() < 0x20 {
          buf.write_string(hex4(c.to_int()))
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// The flags a caller may spell, in the letters Python uses.
fn flags_of(text : String) -> @parse.Flags raise @parse.Refused {
  let mut ignorecase = false
  let mut multiline = false
  let mut dotall = false
  let mut verbose = false
  let mut ascii = false
  for c in text {
    match c {
      'i' => ignorecase = true
      'm' => multiline = true
      's' => dotall = true
      'x' => verbose = true
      'a' => ascii = true
      'u' | ' ' | ',' => ()
      _ =>
        // `column: 0` says the fault is in the flags, not in the pattern, so
        // the page does not draw a caret over a pattern that is fine.
        raise @parse.Pattern(msg="unknown flag '\{c}'", at=0, line=1, column=0)
    }
  }
  @parse.Flags::new(ignorecase~, multiline~, dotall~, verbose~, ascii~)
}

///|
/// A refusal, as the page reads it: a message and where reading stopped.
fn error_json(error : @parse.Refused) -> String {
  match error {
    Pattern(msg~, at~, line~, column~) =>
      "{\"ok\":false,\"kind\":\"syntax\",\"message\":" +
      quote(msg) +
      ",\"at\":" +
      at.to_string() +
      ",\"line\":" +
      line.to_string() +
      ",\"column\":" +
      column.to_string() +
      "}"
    Exceeded(limit~, got~) =>
      "{\"ok\":false,\"kind\":\"limit\",\"message\":" +
      quote("stopped after \{got} of \{limit} steps") +
      "}"
    Ambiguous(groups~) =>
      "{\"ok\":false,\"kind\":\"ambiguous\",\"message\":" +
      quote("the pattern has \{groups} groups; pick one") +
      "}"
    _ =>
      "{\"ok\":false,\"kind\":\"refused\",\"message\":" +
      quote(error.to_string()) +
      "}"
  }
}

///|
/// The slot → name map, from the pattern's own table.
fn names_of(pattern : @moonregex.Pattern) -> Map[Int32, String] {
  let out : Map[Int32, String] = Map([])
  for name, slots in pattern.groupindex() {
    for slot in slots {
      out[slot] = name
    }
  }
  out
}

///|
/// One match as `{start, end, text, groups:[…]}`, with offsets in code
/// points — the page turns them into UTF-16 indices itself.
fn match_json(
  m : @moonregex.Match,
  names : Map[Int32, String],
) -> String raise @parse.Refused {
  let buf = StringBuilder::StringBuilder()
  let start = m.start(@moonregex.Whole)
  let end = m.end(@moonregex.Whole)
  buf.write_string("{\"start\":")
  buf.write_string(start.to_string())
  buf.write_string(",\"end\":")
  buf.write_string(end.to_string())
  buf.write_string(",\"text\":")
  buf.write_string(quote(m.content().to_owned()))
  buf.write_string(",\"groups\":[")
  let total = m.pattern().groups()
  let mut slot = 0
  while slot <= total {
    if slot > 0 {
      buf.write_char(',')
    }
    let s = m.start(@moonregex.Num(n=slot))
    let e = m.end(@moonregex.Num(n=slot))
    buf.write_string("{\"slot\":")
    buf.write_string(slot.to_string())
    buf.write_string(",\"name\":")
    buf.write_string(
      quote(
        match names.get(slot) {
          Some(name) => name
          None => ""
        },
      ),
    )
    buf.write_string(",\"start\":")
    buf.write_string(s.to_string())
    buf.write_string(",\"end\":")
    buf.write_string(e.to_string())
    buf.write_string(",\"text\":")
    match m.group(@moonregex.Num(n=slot)) {
      Some(text) => buf.write_string(quote(text))
      None => buf.write_string("null")
    }
    buf.write_char('}')
    slot = slot + 1
  }
  buf.write_string("]}")
  buf.to_string()
}

///|
/// The one entry point the page uses.
///
/// `mode` picks the function, with the names the guide uses: `search` for the
/// leftmost match anywhere, `prefix` for one at the start, `full` for one that
/// covers the text, `all` for every match.
pub fn run(
  pattern : String,
  flags : String,
  text : String,
  mode : String,
) -> String {
  let out = try {
    let compiled = @moonregex.compile(pattern, flags=flags_of(flags))
    let matches : Array[@moonregex.Match] = match mode {
      "search" =>
        match compiled.search(text) {
          Some(m) => [m]
          None => []
        }
      "prefix" =>
        match compiled.prefix(text) {
          Some(m) => [m]
          None => []
        }
      "full" =>
        match compiled.full(text) {
          Some(m) => [m]
          None => []
        }
      "findall" | "all" => compiled.finditer(text)
      _ =>
        raise @parse.Pattern(
          msg="unknown function '\{mode}'",
          at=0,
          line=1,
          column=1,
        )
    }
    let names = names_of(compiled)
    let buf = StringBuilder::StringBuilder()
    let total = matches.length()
    buf.write_string("{\"ok\":true,\"count\":")
    buf.write_string(total.to_string())
    buf.write_string(",\"groups\":")
    buf.write_string(compiled.groups().to_string())
    buf.write_string(",\"matches\":[")
    let mut i = 0
    while i < total {
      if i > 0 {
        buf.write_char(',')
      }
      buf.write_string(match_json(matches[i], names))
      i = i + 1
    }
    buf.write_string("]}")
    Some(buf.to_string())
  } catch {
    error => Some(error_json(error))
  }
  out.unwrap()
}
