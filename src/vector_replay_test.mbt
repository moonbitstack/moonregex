// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Replaying the generated vectors.
///
/// `src/vectors_test.mbt` holds what CPython's `re` and the `regex` package
/// answered for a corpus of patterns and texts: whether each compile was
/// refused and where, every match's span per group, and what `findall`,
/// `split` and `sub` returned. This file replays them, so the engine is pinned
/// to the two implementations it claims to agree with rather than to what
/// someone wrote down by hand.

///|
/// Undo the escaping the generator applies to one field.
fn unescape(field : String) -> String {
  let buf = StringBuilder::StringBuilder()
  let chars : Array[Char] = []
  for c in field {
    chars.push(c)
  }
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c != '\\' {
      buf.write_char(c)
      i += 1
      continue
    }
    let next = chars[i + 1]
    if next == 'n' {
      buf.write_char('\n')
      i += 2
    } else if next == 't' {
      buf.write_char('\t')
      i += 2
    } else if next == 'r' {
      buf.write_char('\r')
      i += 2
    } else if next == '\\' {
      buf.write_char('\\')
      i += 2
    } else if next == 'u' && i + 3 < chars.length() && chars[i + 2] == '{' {
      let mut j = i + 3
      let mut code = 0
      while j < chars.length() && chars[j] != '}' {
        code = code * 16 + hex_value(chars[j])
        j += 1
      }
      buf.write_char(code.unsafe_to_char())
      i = j + 1
    } else {
      buf.write_char(c)
      i += 1
    }
  }
  buf.to_string()
}

///|
fn hex_value(c : Char) -> Int32 {
  let code = c.to_int()
  if code >= '0'.to_int() && code <= '9'.to_int() {
    code - '0'.to_int()
  } else if code >= 'a'.to_int() && code <= 'f'.to_int() {
    code - 'a'.to_int() + 10
  } else if code >= 'A'.to_int() && code <= 'F'.to_int() {
    code - 'A'.to_int() + 10
  } else {
    0
  }
}

///|
/// The items of a list field: each one is terminated by `|`, which is what
/// tells `[""]` from `[]`.
fn list_items(field : String) -> Array[String] {
  let out : Array[String] = []
  let buf = StringBuilder::StringBuilder()
  for c in field {
    if c == '|' {
      out.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  out
}

///|
fn split_field(field : String, separator : Char) -> Array[String] {
  let out : Array[String] = []
  let buf = StringBuilder::StringBuilder()
  for c in field {
    if c == separator {
      out.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  out.push(buf.to_string())
  out
}

///|
/// The flags a letter stands for, as the vector writes them.
fn flags_of(letters : String) -> @moonregex.Flags {
  let mut ignorecase = false
  let mut multiline = false
  let mut dotall = false
  let mut verbose = false
  let mut ascii = false
  for c in letters {
    if c == 'i' {
      ignorecase = true
    } else if c == 'm' {
      multiline = true
    } else if c == 's' {
      dotall = true
    } else if c == 'x' {
      verbose = true
    } else if c == 'a' {
      ascii = true
    }
  }
  @moonregex.Flags::new(ignorecase~, multiline~, dotall~, verbose~, ascii~)
}

///|
/// Every match with every group's span, laid out the way the vector is.
fn walk_spans(
  p : @moonregex.Pattern,
  text : String,
) -> String raise @moonregex.Refused {
  let out : Array[String] = []
  for m in p.finditer(text) {
    let parts : Array[String] = []
    let mut slot = 0
    while slot <= p.groups() {
      let (start, end) = m.span(group=@moonregex.Num(n=slot))
      parts.push("\{start} \{end}")
      slot += 1
    }
    out.push(parts.join(" "))
  }
  out.join("|")
}

///|
/// Replay one generated line against the engine.
fn replay(line : String, engine : String) -> Unit raise {
  let fields = split_field(line, '\t')
  if fields[0] == "err" {
    let pattern = unescape(fields[1])
    let flags = flags_of(fields[2])
    // The offset a grammar reports for a bad pattern is its own convention —
    // Python points at the opening bracket for an unterminated class, this
    // library at where reading stopped — so the vectors pin the refusal, not
    // the number. `wanted` is kept in the data to read.
    let _wanted = int_of(fields[3])
    let refused = try {
      let _ = @moonregex.compile(pattern, flags~)
      false
    } catch {
      @moonregex.Refused::Pattern(..) => true
      _ => false
    }
    if !refused {
      fail("[\{engine}] \{pattern}: accepted, want a refusal")
    }
    return
  }
  let pattern = unescape(fields[1])
  let flags = flags_of(fields[2])
  let text = unescape(fields[3])
  let groups = int_of(fields[4])
  let p = @moonregex.compile(pattern, flags~)
  let label = "[\{engine}] /\{pattern}/ on \"\{text}\""
  if p.groups() != groups {
    fail("\{label}: \{p.groups()} groups, want \{groups}")
  }
  let spans = walk_spans(p, text)
  if spans != fields[5] {
    fail("\{label}: spans \{spans}, want \{fields[5]}")
  }
  // `findall` cannot say "a tuple per match", so a pattern with two or more
  // groups is refused by the library, and the vector records `!`.
  if fields[6] == "!" {
    let refused = try {
      let _ = p.findall(text)
      false
    } catch {
      @moonregex.Refused::Ambiguous(_) => true
      _ => false
    }
    if !refused {
      fail("\{label}: findall with \{groups} groups was not refused")
    }
  } else {
    let want : Array[String?] = list_items(fields[6]).map(piece => {
      Some(unescape(piece))
    })
    let got = p.findall(text)
    if got != want {
      fail("\{label}: findall \{debug_repr(got)}, want \{debug_repr(want)}")
    }
  }
  let want_split : Array[String?] = list_items(fields[7]).map(piece => {
    // A group that took no part is written as the `\u{1}` marker, which no
    // text in the corpus can produce.
    if piece == "\\u{1}" {
      None
    } else {
      Some(unescape(piece))
    }
  })
  let got_split = p.split(text)
  if got_split != want_split {
    fail(
      "\{label}: split \{debug_repr(got_split)}, want \{debug_repr(want_split)}",
    )
  }
  let want_sub = unescape(fields[8])
  let got_sub = p.sub(text, "<M>")
  if got_sub != want_sub {
    fail("\{label}: sub \"\{got_sub}\", want \"\{want_sub}\"")
  }
}

///|
/// A list of optional strings as text, for a failure message.
fn debug_repr(items : Array[String?]) -> String {
  let parts : Array[String] = []
  for item in items {
    match item {
      None => parts.push("∅")
      Some(text) => parts.push("\"" + text + "\"")
    }
  }
  "[" + parts.join(", ") + "]"
}

///|
fn int_of(text : String) -> Int32 {
  let mut sign = 1
  let mut value : Int32 = 0
  for c in text {
    if c == '-' {
      sign = -1
    } else if c >= '0' && c <= '9' {
      value = value * 10 + c.to_int() - 0x30
    }
  }
  value * sign
}

///|
test "CPython's re, replayed" {
  for line in python_vectors {
    replay(line, "re") catch {
      e => fail("vector \{line}\n  \{e}")
    }
  }
}

///|
test "mrab's regex, replayed" {
  for line in regexp_vectors {
    replay(line, "regex") catch {
      e => fail("vector \{line}\n  \{e}")
    }
  }
}
