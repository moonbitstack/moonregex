// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One match: where it sits in the text, and every group's span.
///
/// A span is a code-point range, so `start` and `end` read the way Python's do
/// — characters, not UTF-16 units — and `group` slices the original text back
/// out by those offsets.
pub(all) struct Match {
  priv pattern : Pattern
  priv text : String
  priv result : @exec.MatchResult
}

///|
/// The `Pattern` that produced this match.
pub fn Match::pattern(self : Match) -> Pattern {
  self.pattern
}

///|
/// The subject text.
pub fn Match::string(self : Match) -> String {
  self.text
}

///|
/// Map a group key to its slot, refusing keys the pattern does not have.
fn Match::slot_of(self : Match, group : GroupKey) -> Int32 raise @parse.Refused {
  match group {
    Whole => 0
    Num(n~) => {
      if n < 0 || n > self.pattern.groups() {
        raise @parse.Pattern(msg="no such group \{n}", at=0, line=1, column=1)
      }
      n
    }
    Name(n=name) =>
      match self.pattern.groupindex().get(name) {
        None =>
          raise @parse.Pattern(
            msg="no such group '\{name}'",
            at=0,
            line=1,
            column=1,
          )
        Some(slots) => {
          let slot : Int32 = slots[0]
          slot
        }
      }
  }
}

///|
/// Code-point offset where the whole match begins.
pub fn Match::start(
  self : Match,
  group~ : GroupKey = Whole,
) -> Int32 raise @parse.Refused {
  let slot = self.slot_of(group)
  self.result.spans[slot].0
}

///|
/// Code-point offset just past where the whole match ends.
pub fn Match::end(
  self : Match,
  group~ : GroupKey = Whole,
) -> Int32 raise @parse.Refused {
  let slot = self.slot_of(group)
  self.result.spans[slot].1
}

///|
/// The `(start, end)` span of a group.
pub fn Match::span(
  self : Match,
  group~ : GroupKey = Whole,
) -> (Int32, Int32) raise @parse.Refused {
  (self.start(group~), self.end(group~))
}

///|
/// The substring the group captured, or `None` if it took no part.
pub fn Match::group(
  self : Match,
  group~ : GroupKey = Whole,
) -> String? raise @parse.Refused {
  let s = self.start(group~)
  let e = self.end(group~)
  if s < 0 || e < 0 {
    None
  } else {
    Some(slice_cp(self.text, s, e))
  }
}

///|
/// All capturing groups (1..n) as strings, `None` for those that did not take
/// part — Python's `Match.groups`.
pub fn Match::groups(self : Match, default~ : String? = None) -> Array[String?] {
  let ng = self.pattern.groups()
  let out : Array[String?] = []
  let mut g = 1
  while g <= ng {
    let span = self.result.spans[g]
    if span.0 < 0 {
      out.push(default)
    } else {
      out.push(Some(slice_cp(self.text, span.0, span.1)))
    }
    g += 1
  }
  out
}

///|
/// Named groups to their captured strings, `default` filling those that took no
/// part — Python's `Match.groupdict`.
pub fn Match::groupdict(
  self : Match,
  default~ : String? = None,
) -> Map[String, String] {
  let index = self.pattern.groupindex()
  let out : Map[String, String] = Map([])
  for k in index.keys() {
    let slots = index.get(k).unwrap()
    let slot : Int32 = slots[0]
    let span = self.result.spans[slot]
    if span.0 >= 0 {
      out[k] = slice_cp(self.text, span.0, span.1)
    } else if default is Some(d) {
      out[k] = d
    }
  }
  out
}

///|
/// The number of the highest group that took part, or `None` — Python's
/// `Match.lastindex`.
pub fn Match::lastindex(self : Match) -> Int32? {
  let spans = self.result.spans
  let mut i = spans.length() - 1
  while i >= 1 {
    let span = spans[i]
    if span.0 >= 0 {
      return Some(i)
    }
    i -= 1
  }
  None
}

///|
/// The name of the group `lastindex` points at, or `None` — Python's
/// `Match.lastgroup`.
pub fn Match::lastgroup(self : Match) -> String? {
  match self.lastindex() {
    None => None
    Some(idx) => {
      let index = self.pattern.groupindex()
      for k in index.keys() {
        let slots = index.get(k).unwrap()
        let slot : Int32 = slots[0]
        if slot == idx {
          return Some(k)
        }
      }
      None
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
fn cp_length(text : String) -> Int32 {
  let mut n = 0
  for c in text {
    ignore(c)
    n += 1
  }
  n
}

///|
/// Slice `text` by code-point offsets (MoonBit strings are UTF-16; the engine
/// reports positions in code points, so the two must not be conflated).
fn slice_cp(text : String, start : Int32, end : Int32) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut i = 0
  for c in text {
    if i >= start && i < end {
      buf.write_char(c)
    }
    i += 1
  }
  buf.to_string()
}

///|
/// Expand the Python replacement language in `repl` against `m`: `\1`..`\99`,
/// `\g<n>`, `\g<name>`, `\\`, and the control escapes.
fn expand(repl : String, m : Match) -> String raise @parse.Refused {
  let chars : Array[Char] = []
  for c in repl {
    chars.push(c)
  }
  let n = chars.length()
  let buf = StringBuilder::StringBuilder()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '\\' && i + 1 < n {
      let d = chars[i + 1]
      if d == 'g' && i + 2 < n && chars[i + 2] == '<' {
        let mut j = i + 3
        let mut name = ""
        while j < n && chars[j] != '>' {
          name = name + chars[j].to_string()
          j += 1
        }
        let key = parse_group_key(name)
        match m.group(group=key) {
          None => ()
          Some(s) => buf.write_string(s)
        }
        i = if j < n { j + 1 } else { n }
      } else if d >= '0' && d <= '9' {
        let mut j = i + 1
        let mut num = ""
        while j < n && chars[j] >= '0' && chars[j] <= '9' && num.length() < 2 {
          num = num + chars[j].to_string()
          j += 1
        }
        let key = Num(n=decimal_of(num))
        match m.group(group=key) {
          None => ()
          Some(s) => buf.write_string(s)
        }
        i = j
      } else {
        buf.write_string(escape_char(d))
        i += 2
      }
    } else {
      buf.write_char(c)
      i += 1
    }
  }
  buf.to_string()
}

///|
fn parse_group_key(name : String) -> GroupKey {
  let mut all_digits = name.length() > 0
  for c in name {
    if !(c >= '0' && c <= '9') {
      all_digits = false
    }
  }
  if all_digits {
    Num(n=decimal_of(name))
  } else {
    Name(n=name)
  }
}

///|
fn decimal_of(s : String) -> Int32 {
  let mut v : Int32 = 0
  for c in s {
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  v
}

///|
fn escape_char(d : Char) -> String {
  if d == 'n' {
    "\n"
  } else if d == 't' {
    "\t"
  } else if d == 'r' {
    "\r"
  } else if d == 'f' {
    "\f"
  } else if d == 'v' {
    '\u{0b}'.to_string()
  } else if d == '\\' {
    "\\"
  } else {
    d.to_string()
  }
}
