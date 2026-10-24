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
  match self.program.search(text, pos~, endpos~, limit~) {
    None => None
    Some(r) => Some(Match::{ pattern: self, text, result: r, })
  }
}

///|
/// Match only at `pos`.
pub fn Pattern::match_at(
  self : Pattern,
  text : String,
  pos~ : Int32 = 0,
  limit~ : Int32 = 10000000,
) -> Match? raise @parse.Refused {
  match self.program.match_at(text, pos~, limit~) {
    None => None
    Some(r) => Some(Match::{ pattern: self, text, result: r, })
  }
}

///|
/// Match the whole region `pos..endpos`.
pub fn Pattern::fullmatch(
  self : Pattern,
  text : String,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> Match? raise @parse.Refused {
  match self.program.fullmatch(text, pos~, endpos~, limit~) {
    None => None
    Some(r) => Some(Match::{ pattern: self, text, result: r, })
  }
}

///|
/// All non-overlapping matches, as `findall` at the module level.
pub fn Pattern::findall(
  self : Pattern,
  text : String,
  group~ : GroupKey = Whole,
  overlapped~ : Bool = false,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> Array[String?] raise @parse.Refused {
  let ng = self.groups()
  let use_group = if group is Whole {
    if ng == 0 {
      Whole
    } else {
      Num(n=1)
    }
  } else {
    group
  }
  if use_group is Whole && ng >= 2 {
    raise @parse.Ambiguous(groups=ng)
  }
  let out : Array[String?] = []
  let mut p = pos
  let end = if endpos < 0 { cp_length(text) } else { endpos }
  while p <= end {
    match self.search(text, pos=p, endpos=end, limit~) {
      None => break
      Some(m) => {
        out.push(m.group(group=use_group))
        let e = m.end()
        let next = if e > p { e } else { p + 1 }
        p = if overlapped { m.start() + 1 } else { next }
      }
    }
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
  let out : Array[Match] = []
  let mut p = pos
  let end = if endpos < 0 { cp_length(text) } else { endpos }
  while p <= end {
    match self.search(text, pos=p, endpos=end, limit~) {
      None => break
      Some(m) => {
        out.push(m)
        let e = m.end()
        let next = if e > p { e } else { p + 1 }
        p = if overlapped { m.start() + 1 } else { next }
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
  let out : Array[String?] = []
  let mut p = pos
  let end = if endpos < 0 { cp_length(text) } else { endpos }
  let mut last = pos
  let mut count = 0
  while p <= end {
    if maxsplit != 0 && count >= maxsplit {
      break
    }
    match self.search(text, pos=p, endpos=end, limit~) {
      None => break
      Some(m) => {
        let s = m.start()
        let e = m.end()
        out.push(Some(slice_cp(text, last, s)))
        let mut g = 1
        while g <= ng {
          out.push(m.group(group=Num(n=g)))
          g += 1
        }
        last = e
        count += 1
        p = if e > s { e } else { s + 1 }
      }
    }
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
  let end = if endpos < 0 { cp_length(text) } else { endpos }
  let buf = StringBuilder::StringBuilder()
  let mut p = pos
  let mut last = pos
  let mut n = 0
  while p <= end {
    if count != 0 && n >= count {
      break
    }
    match self.search(text, pos=p, endpos=end, limit~) {
      None => break
      Some(m) => {
        let s = m.start()
        let e = m.end()
        buf.write_string(slice_cp(text, last, s))
        buf.write_string(expand(repl, m))
        last = e
        n += 1
        p = if e > s { e } else { s + 1 }
      }
    }
  }
  buf.write_string(slice_cp(text, last, end))
  (buf.to_string(), n)
}

///|
/// Replace matches with `f(match)`, as `subn_by` at the module level.
pub fn Pattern::subn_by(
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
  let mut p = pos
  let mut last = pos
  let mut n = 0
  while p <= end {
    if count != 0 && n >= count {
      break
    }
    match self.search(text, pos=p, endpos=end, limit~) {
      None => break
      Some(m) => {
        let s = m.start()
        let e = m.end()
        buf.write_string(slice_cp(text, last, s))
        buf.write_string(f(m))
        last = e
        n += 1
        p = if e > s { e } else { s + 1 }
      }
    }
  }
  buf.write_string(slice_cp(text, last, end))
  (buf.to_string(), n)
}

///|
/// Replace matches with `f(match)`, as `sub_by` at the module level.
pub fn Pattern::sub_by(
  self : Pattern,
  text : String,
  f : (Match) -> String raise @parse.Refused,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> String raise @parse.Refused {
  self.subn_by(text, f, count~, pos~, endpos~, limit~).0
}
