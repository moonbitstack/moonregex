// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A compiled pattern: the tree it came from, the flat program it became, and
/// the source, so it can answer what Python's `re` answers of a `Pattern` —
/// its string, its flags, how many groups, and what they are named.
pub(all) struct Pattern {
  priv pat : String
  priv flags : @parse.Flags
  priv dialect : @parse.Dialect
  priv ast : @parse.Ast
  priv program : @exec.Program
  priv partial : Bool
}

///|
/// The pattern's source text.
pub fn Pattern::pattern(self : Pattern) -> String {
  self.pat
}

///|
/// The effective flags.
pub fn Pattern::flags(self : Pattern) -> @parse.Flags {
  self.flags
}

///|
/// The dialect the pattern was read under.
pub fn Pattern::dialect(self : Pattern) -> @parse.Dialect {
  self.dialect
}

///|
/// How many capturing groups the pattern has, group 0 not counted — Python's
/// `Pattern.groups`.
pub fn Pattern::groups(self : Pattern) -> Int32 {
  self.ast.groups()
}

///|
/// Group name to slot, as Python's `Pattern.groupindex`.
pub fn Pattern::groupindex(self : Pattern) -> Map[String, Array[Int32]] {
  self.ast.groupindex()
}

///|
/// The syntax tree re-printed, as Python's `Pattern.dump` would.
pub fn Pattern::dump(self : Pattern) -> String {
  self.ast.dump()
}

///|
/// Whether the pattern was compiled for partial matching.
pub fn Pattern::partial(self : Pattern) -> Bool {
  self.partial
}

///|
/// Scan `text` for the leftmost match.
pub fn Pattern::search(
  self : Pattern,
  text : String,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> Match? raise @parse.Refused {
  self.search_from(text, pos, endpos, false, limit)
}

///|
/// A search that may be told it has to consume something, which is how the
/// scan steps past an empty match without losing a non-empty one at the same
/// place.
fn Pattern::search_from(
  self : Pattern,
  text : String,
  pos : Int32,
  endpos : Int32,
  must_advance : Bool,
  limit : Int32,
) -> Match? raise @parse.Refused {
  match self.program.search(text, pos~, endpos~, limit~, must_advance~) {
    None => None
    Some(r) => {
      let e = if endpos < 0 { cp_length(text) } else { endpos }
      Some(Match::{ pattern: self, text, result: r, pos, endpos: e, })
    }
  }
}

///|
/// Match only at `pos`.
pub fn Pattern::prefix(
  self : Pattern,
  text : String,
  pos~ : Int32 = 0,
  limit~ : Int32 = 10000000,
) -> Match? raise @parse.Refused {
  match self.program.prefix(text, pos~, limit~) {
    None => None
    Some(r) =>
      Some(Match::{
        pattern: self,
        text,
        result: r,
        pos,
        endpos: cp_length(text),
      })
  }
}

///|
/// Match the whole region `pos..endpos`.
pub fn Pattern::full(
  self : Pattern,
  text : String,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> Match? raise @parse.Refused {
  match self.program.full(text, pos~, endpos~, limit~) {
    None => None
    Some(r) => {
      let e = if endpos < 0 { cp_length(text) } else { endpos }
      Some(Match::{ pattern: self, text, result: r, pos, endpos: e, })
    }
  }
}

///|
/// All non-overlapping matches, as `findall` at the module level.
pub fn Pattern::findall(
  self : Pattern,
  text : String,
  group~ : Group = Whole,
  overlapped~ : Bool = false,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> Array[String?] raise @parse.Refused {
  let ng = self.groups()
  // Python answers a tuple once there are two or more groups, which a
  // statically typed list cannot say, so the caller has to pick one.
  if group is Whole && ng >= 2 {
    raise @parse.Ambiguous(groups=ng)
  }
  let use_group = if group is Whole {
    if ng == 0 {
      Whole
    } else {
      Num(n=1)
    }
  } else {
    group
  }
  let out : Array[String?] = []
  for m in self.walk(text, pos~, endpos~, overlapped~, limit~) {
    // A group that took no part answers the empty string, which is what
    // Python's `findall` collects — `split` and `group` keep the difference.
    out.push(
      match m.group(use_group) {
        None => Some("")
        Some(g) => Some(g)
      },
    )
  }
  out
}

///|
/// All matches as `Match` objects, as `finditer` at the module level.
pub fn Pattern::finditer(
  self : Pattern,
  text : String,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  overlapped~ : Bool = false,
  limit~ : Int32 = 10000000,
) -> Array[Match] raise @parse.Refused {
  self.walk(text, pos~, endpos~, overlapped~, limit~)
}

///|
/// Every match in the region, the way the two Python engines walk it.
///
/// After an empty match the next attempt at the same position has to consume
/// something — that is what makes `|a` on `a` answer an empty match at 0, then
/// `a`, then an empty match at 1, and what keeps `x*` from looping.
fn Pattern::walk(
  self : Pattern,
  text : String,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  overlapped~ : Bool = false,
  limit~ : Int32 = 10000000,
) -> Array[Match] raise @parse.Refused {
  let out : Array[Match] = []
  let end = if endpos < 0 { cp_length(text) } else { endpos }
  let mut p = pos
  let mut must_advance = false
  while p <= end {
    match self.search_from(text, p, end, must_advance, limit) {
      None =>
        if must_advance {
          must_advance = false
          p = p + 1
        } else {
          break
        }
      Some(m) => {
        out.push(m)
        if overlapped {
          p = m.start(0) + 1
          must_advance = false
        } else if m.end(0) == m.start(0) {
          // After an empty match Python retries the same position for a
          // non-empty one; ECMA-262's `lastIndex` just moves on by one.
          if self.dialect is @parse.Ecma262 {
            p = m.end(0) + 1
            must_advance = false
          } else {
            p = m.end(0)
            must_advance = true
          }
        } else {
          p = m.end(0)
          must_advance = false
        }
      }
    }
  }
  out
}

///|
/// Split `text` on the pattern, as `split` at the module level.
pub fn Pattern::split(
  self : Pattern,
  text : String,
  maxsplit~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> Array[String?] raise @parse.Refused {
  let ng = self.groups()
  let end = if endpos < 0 { cp_length(text) } else { endpos }
  let out : Array[String?] = []
  let mut last = pos
  let mut count = 0
  for m in self.walk(text, pos~, endpos~, overlapped=false, limit~) {
    if maxsplit != 0 && count >= maxsplit {
      break
    }
    out.push(Some(slice_cp(text, last, m.start(0))))
    let mut g = 1
    while g <= ng {
      out.push(m.group(Num(n=g)))
      g += 1
    }
    last = m.end(0)
    count += 1
  }
  out.push(Some(slice_cp(text, last, end)))
  out
}

///|
/// Replace matches with `repl`, as `sub` at the module level.
pub fn Pattern::sub(
  self : Pattern,
  text : String,
  repl : String,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> String raise @parse.Refused {
  self.subn(text, repl, count~, pos~, endpos~, limit~).0
}

///|
/// Replace matches with `repl`, returning the new text and the count, as `subn`
/// at the module level.
pub fn Pattern::subn(
  self : Pattern,
  text : String,
  repl : String,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> (String, Int32) raise @parse.Refused {
  self.replace(text, m => expand(repl, m), count~, pos~, endpos~, limit~)
}

///|
/// Replace matches with `f(match)`, as `subn_with` at the module level.
pub fn Pattern::subn_with(
  self : Pattern,
  text : String,
  f : (Match) -> String raise @parse.Refused,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> (String, Int32) raise @parse.Refused {
  self.replace(text, f, count~, pos~, endpos~, limit~)
}

///|
/// Replace matches with `f(match)`, as `sub_with` at the module level.
pub fn Pattern::sub_with(
  self : Pattern,
  text : String,
  f : (Match) -> String raise @parse.Refused,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> String raise @parse.Refused {
  self.replace(text, f, count~, pos~, endpos~, limit~).0
}

///|
/// Replace matches with `repl`, as `regex.subf` — `repl` is a format template
/// whose fields name groups (`{}`, `{0}`, `{name}`, `{0[0]}`), with an optional
/// `:spec`.
pub fn Pattern::subf(
  self : Pattern,
  text : String,
  repl : String,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> String raise @parse.Refused {
  self.replace(text, m => expandf(repl, m), count~, pos~, endpos~, limit~).0
}

///|
/// Replace matches with `repl`, returning the new text and the count, as
/// `regex.subfn`.
pub fn Pattern::subfn(
  self : Pattern,
  text : String,
  repl : String,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> (String, Int32) raise @parse.Refused {
  self.replace(text, m => expandf(repl, m), count~, pos~, endpos~, limit~)
}

///|
/// The one substitution loop: walk the matches, keep the text between them,
/// and put whatever the replacement answers in their place.
fn Pattern::replace(
  self : Pattern,
  text : String,
  f : (Match) -> String raise @parse.Refused,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> (String, Int32) raise @parse.Refused {
  let end = if endpos < 0 { cp_length(text) } else { endpos }
  let buf = StringBuilder::StringBuilder()
  let mut last = pos
  let mut n = 0
  for m in self.walk(text, pos~, endpos~, overlapped=false, limit~) {
    if count != 0 && n >= count {
      break
    }
    buf.write_string(slice_cp(text, last, m.start(0)))
    buf.write_string(f(m))
    last = m.end(0)
    n += 1
  }
  buf.write_string(slice_cp(text, last, end))
  (buf.to_string(), n)
}
