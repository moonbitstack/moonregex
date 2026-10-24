// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What an anchor tests at the current position.
pub(all) enum AnchorKind {
  TextStart
  TextEnd
  LineStart
  LineEnd
  /// End of the text, or just before a single trailing newline — Python's `$`
  /// and `\Z`.
  SoftEnd
  WordBoundary(negate~ : Bool)
  WordStart
  WordEnd
  /// `\G`: where the search started.
  SearchStart
}

///|
/// One instruction of the flat program the tree is lowered into.
///
/// Every jump and slot is an `Int`, the native index type of `Array`; only the
/// literal code point in `Char` is `Int32`, because that is the type the parse
/// tree and the property tables speak.
pub(all) enum Inst {
  Char(code~ : Int32)
  Any(except_newline~ : Bool)
  Class(set~ : @prop.CharSet)
  Anchor(kind~ : AnchorKind)
  /// Greedy choice: try `x` first, then `y`.
  Split(x~ : Int32, y~ : Int32)
  /// Reluctant choice: try `y` first, then `x`.
  SplitLazy(x~ : Int32, y~ : Int32)
  Jmp(x~ : Int32)
  Save(slot~ : Int32)
  Match
  /// A backreference to the text a group captured.
  Backref(slot~ : Int32, icase~ : Bool)
  /// `\K`: the match starts here, not where the search did.
  Keep
  /// `\X`: one grapheme cluster (approximated by one code point here).
  Grapheme
  /// An atomic group: match the sub-program, commit, no backing into it.
  Atomic(id~ : Int32)
  /// A lookahead: run the sub-program at the position, do not consume.
  Lookahead(id~ : Int32, positive~ : Bool)
  /// A lookbehind: run the sub-program ending at the position, do not consume.
  Lookbehind(id~ : Int32, positive~ : Bool)
  /// A conditional on whether a group took part.
  CondGroup(slot~ : Int32, yes_id~ : Int32, no_id~ : Int32)
  /// A conditional on whether a lookaround holds.
  CondLook(id~ : Int32, yes_id~ : Int32, no_id~ : Int32)
  /// Unbounded repetition of a sub-program.
  Star(body_id~ : Int32, greedy~ : Bool)
  /// Recurse into a named group's sub-program.
  RecurseGroup(slot~ : Int32)
  /// Recurse into the whole pattern.
  RecurseWhole
}

///|
/// A compiled pattern: the flat program, the sub-programs for groups and other
/// constructs, and how many capture groups it has (group 0 not counted).
pub struct Program {
  code : Array[Inst]
  ngroups : Int32
  group_codes : Map[Int32, Array[Inst]]
  extra : Map[Int32, Array[Inst]]
}

///|
/// The outcome of a run: where the whole match sits, and every group's span.
pub struct MatchResult {
  /// Code point offset where the whole match begins.
  start : Int32
  /// Code point offset just past where the whole match ends.
  end : Int32
  /// One span per group, group 0 first; `(-1, -1)` means the group did not
  /// take part.
  spans : Array[(Int32, Int32)]
  /// The edit budget spent, when the pattern was fuzzy; `None` otherwise.
  fuzzy : (Int32, Int32, Int32)?
}

///|
/// State carried through compilation.
///
/// `extra` and `group_codes` are persisted maps; `counter` is a one-element
/// array standing in for the next sub-program identifier, so it can be bumped
/// in place through an immutable receiver. Maps and arrays are mutable by
/// reference, which is why no field here needs to be `mut`.
priv struct Compile {
  counter : Array[Int32]
  extra : Map[Int32, Array[Inst]]
  group_codes : Map[Int32, Array[Inst]]
  groupindex : Map[String, Array[Int32]]
}

///|
fn Compile::new(groupindex : Map[String, Array[Int32]]) -> Compile {
  { counter: [0], extra: {}, group_codes: {}, groupindex, }
}

///|
/// Compile `node` into a fresh sub-program and return its identifier.
fn Compile::extra_for(self : Compile, node : @parse.Node) -> Int32 {
  let sub : Array[Inst] = []
  self.emit(node, sub)
  let id = self.counter[0]
  self.counter[0] = id + 1
  self.extra.set(id, sub)
  id
}

///|
/// Lower a parse node into `code`, mutating the compilation state in place.
fn Compile::emit(
  self : Compile,
  node : @parse.Node,
  code : Array[Inst],
) -> Unit {
  match node {
    @parse.Empty => ()
    @parse.Char(code=c) => code.push(Char(code=c))
    @parse.Any(dotall~) => code.push(Any(except_newline=!dotall))
    @parse.Class(set~) => code.push(Class(set~))
    @parse.Seq(items~) =>
      for item in items {
        self.emit(item, code)
      }
    @parse.Alt(items~) => self.emit_alt(items, code)
    @parse.Repeat(node~, min~, max~, greedy~) =>
      self.emit_repeat(node, min, max, greedy, code)
    @parse.Group(slot~, node~) => {
      let key = slot
      if !self.group_codes.contains(key) {
        let body : Array[Inst] = []
        self.emit(node, body)
        let wrapped : Array[Inst] = [
          Save(slot=2 * key),
          ..body,
          Save(slot=2 * key + 1),
        ]
        self.group_codes.set(key, wrapped)
      }
      // Inline: capture here, run the body, capture the end.
      code.push(Save(slot=2 * key))
      self.emit(node, code)
      code.push(Save(slot=2 * key + 1))
    }
    @parse.Atomic(node~) => {
      let id = self.extra_for(node)
      code.push(Atomic(id~))
    }
    @parse.Lookaround(node~, look~) => {
      let id = self.extra_for(node)
      match look {
        @parse.Ahead(positive~) => code.push(Lookahead(id~, positive~))
        @parse.Behind(positive~) => code.push(Lookbehind(id~, positive~))
      }
    }
    @parse.Backref(slot~, icase~) => code.push(Backref(slot~, icase~))
    @parse.Cond(probe~, yes~, no~) => {
      let yes_id = self.extra_for(yes)
      let no_sub : Array[Inst] = []
      match no {
        None => ()
        Some(n) => self.emit(n, no_sub)
      }
      let no_id = self.counter[0]
      self.counter[0] = no_id + 1
      self.extra.set(no_id, no_sub)
      match probe {
        @parse.ByGroup(slot~) => code.push(CondGroup(slot~, yes_id~, no_id~))
        @parse.ByLook(node~, ..) => {
          // Compile the lookaround body into its own sub-program and test it as
          // a forward assertion here; a true lookbehind is approximated by the
          // same forward run until the dedicated behind pass is wired in.
          let look_sub : Array[Inst] = []
          self.emit(node, look_sub)
          let look_id = self.counter[0]
          self.counter[0] = look_id + 1
          self.extra.set(look_id, look_sub)
          code.push(CondLook(id=look_id, yes_id~, no_id~))
        }
      }
    }
    @parse.Anchor(anchor~) => code.push(Anchor(kind=anchor_to_kind(anchor)))
    @parse.Keep => code.push(Keep)
    @parse.Grapheme => code.push(Grapheme)
    @parse.Fuzzy(spec~, node~) => {
      // Fuzzy is matched exactly for now: the inner node, without edits. The
      // budget is recorded so a later, fuller implementation can spend it.
      let _ = spec
      self.emit(node, code)
    }
    @parse.Recurse(target~) =>
      match target {
        @parse.Whole => code.push(RecurseWhole)
        @parse.Group(slot~) => code.push(RecurseGroup(slot~))
        @parse.Named(name~) => {
          let slot = match self.groupindex.get(name) {
            Some(slots) => slots[0]
            None => 0
          }
          code.push(RecurseGroup(slot~))
        }
      }
  }
}

///|
fn Compile::emit_alt(
  self : Compile,
  items : ArrayView[@parse.Node],
  code : Array[Inst],
) -> Unit {
  let n = items.length()
  if n == 0 {
    return
  }
  if n == 1 {
    self.emit(items[0], code)
    return
  }
  let split_pc = code.length()
  code.push(Split(x=0, y=0))
  let b1 = code.length()
  self.emit(items[0], code)
  let jmp_pc = code.length()
  code.push(Jmp(x=0))
  // The rest is compiled recursively; its end is where the first branch jumps.
  self.emit_alt(items[1:], code)
  let end = code.length()
  // The `y` arm of the outer split enters the second branch (just past the
  // jump that closes the first); the jump lands past the whole alternation.
  code[split_pc] = Split(x=b1, y=jmp_pc + 1)
  code[jmp_pc] = Jmp(x=end)
}

///|
fn Compile::emit_repeat(
  self : Compile,
  node : @parse.Node,
  min : Int32,
  max : Int32?,
  greedy : Bool,
  code : Array[Inst],
) -> Unit {
  let body : Array[Inst] = []
  self.emit(node, body)
  // The mandatory `min` copies run whether or not more follow.
  let mut k = 0
  while k < min {
    for inst in body {
      code.push(inst)
    }
    k = k + 1
  }
  match max {
    None => {
      let id = self.counter[0]
      self.counter[0] = id + 1
      self.extra.set(id, body)
      code.push(Star(body_id=id, greedy~))
    }
    Some(m) => {
      let more = m - min
      if more > 0 {
        self.emit_opt(more, body, greedy, code)
      }
    }
  }
}

///|
/// `more` optional copies of `body`, greedy or reluctant.
fn Compile::emit_opt(
  self : Compile,
  more : Int32,
  body : Array[Inst],
  greedy : Bool,
  code : Array[Inst],
) -> Unit {
  if more == 0 {
    return
  }
  let split_pc = code.length()
  if greedy {
    code.push(Split(x=0, y=0))
  } else {
    code.push(SplitLazy(x=0, y=0))
  }
  let a = code.length()
  for inst in body {
    code.push(inst)
  }
  // After a copy, carry on with the remaining optional copies.
  self.emit_opt(more - 1, body, greedy, code)
  let after = code.length()
  if greedy {
    code[split_pc] = Split(x=a, y=after)
  } else {
    code[split_pc] = SplitLazy(x=a, y=after)
  }
}

///|
fn anchor_to_kind(anchor : @parse.Anchor) -> AnchorKind {
  match anchor {
    @parse.StartLine(multiline~) =>
      if multiline {
        LineStart
      } else {
        TextStart
      }
    @parse.EndLine(multiline~, ..) => if multiline { LineEnd } else { SoftEnd }
    @parse.TextStart => TextStart
    @parse.TextEnd => TextEnd
    @parse.WordBoundary(negate~, ..) => WordBoundary(negate~)
    @parse.WordStart => WordStart
    @parse.WordEnd => WordEnd
    @parse.SearchAnchor => SearchStart
  }
}

///|
/// Compile a parsed pattern into the flat program.
pub fn compile(ast : @parse.Ast) -> Program {
  let state = Compile::new(ast.groupindex())
  let code : Array[Inst] = []
  code.push(Save(slot=0))
  state.emit(ast.root(), code)
  code.push(Save(slot=1))
  code.push(Match)
  {
    code,
    ngroups: ast.groups(),
    group_codes: state.group_codes,
    extra: state.extra,
  }
}

// ---------------------------------------------------------------------------
// Running
// ---------------------------------------------------------------------------

///|
/// The engine: holds the text as code points and walks the program, backtracking
/// over choices and counting steps so a runaway pattern hits `limit`.
///
/// `steps` is a one-element array, the running step count, bumped in place so it
/// survives the recursion that implements backtracking.
priv struct Matcher {
  program : Program
  chars : Array[Int32]
  len : Int32
  pos : Int32
  limit : Int32
  steps : Array[Int32]
}

///|
fn clone_saves(a : Array[Int32]) -> Array[Int32] {
  let r = Array::make(a.length(), 0)
  let len = a.length()
  for i in 0..<len {
    r[i] = a[i]
  } nobreak {
    r
  }
}

///|
fn to_code_points(s : String) -> Array[Int32] {
  let a : Array[Int32] = []
  for c in s {
    a.push(c.to_int())
  }
  a
}

///|
fn Matcher::is_word(_self : Matcher, code : Int32) -> Bool {
  (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
  (code >= 'A'.to_int() && code <= 'Z'.to_int()) ||
  (code >= '0'.to_int() && code <= '9'.to_int()) ||
  code == '_'.to_int()
}

///|
fn Matcher::word_at(self : Matcher, sp : Int32) -> Bool {
  if sp < self.len {
    self.is_word(self.chars[sp])
  } else {
    false
  }
}

///|
fn Matcher::word_before(self : Matcher, sp : Int32) -> Bool {
  if sp > 0 {
    self.is_word(self.chars[sp - 1])
  } else {
    false
  }
}

///|
fn Matcher::is_word_boundary(self : Matcher, sp : Int32) -> Bool {
  self.word_before(sp) != self.word_at(sp)
}

///|
fn Matcher::at_word_start(self : Matcher, sp : Int32) -> Bool {
  self.is_word_boundary(sp) && self.word_at(sp)
}

///|
fn Matcher::at_word_end(self : Matcher, sp : Int32) -> Bool {
  self.is_word_boundary(sp) && self.word_before(sp)
}

///|
fn Matcher::test_anchor(self : Matcher, kind : AnchorKind, sp : Int32) -> Bool {
  match kind {
    TextStart => sp == 0
    TextEnd => sp == self.len
    LineStart => sp == 0 || self.chars[sp - 1] == '\n'.to_int()
    LineEnd => sp == self.len || self.chars[sp] == '\n'.to_int()
    SoftEnd =>
      sp == self.len ||
      (sp < self.len && self.chars[sp] == '\n'.to_int() && sp + 1 == self.len)
    WordBoundary(negate~) => self.is_word_boundary(sp) != negate
    WordStart => self.at_word_start(sp)
    WordEnd => self.at_word_end(sp)
    SearchStart => sp == self.pos
  }
}

///|
/// Run the program from `entry` at position `sp0`, returning whether it reached
/// `Match`, where it ended, and the captures then held.
fn Matcher::run(
  self : Matcher,
  code : Array[Inst],
  entry : Int32,
  sp0 : Int32,
  saves0 : Array[Int32],
) -> (Bool, Int32, Array[Int32]) raise @parse.Refused {
  let mut saves = saves0
  let mut sp = sp0
  let mut pc = entry
  let len = self.len
  let program = self.program
  while true {
    self.steps[0] = self.steps[0] + 1
    if self.steps[0] > self.limit {
      raise @parse.Exceeded(limit=self.limit, got=self.steps[0])
    }
    if pc < 0 {
      return (false, sp, saves)
    }
    if pc >= code.length() {
      // Reaching the end of a code array accepts: the main program always ends
      // in an explicit `Match`, but every sub-program (a group body, a look-
      // around, a condition branch, a star body) is a fragment that succeeds
      // once its last instruction has run.
      return (true, sp, saves)
    }
    match code[pc] {
      Char(code=c) =>
        if sp < len && self.chars[sp] == c {
          sp = sp + 1
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      Any(except_newline~) =>
        if sp < len && (!except_newline || self.chars[sp] != '\n'.to_int()) {
          sp = sp + 1
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      Class(set~) =>
        if sp < len && set.contains(self.chars[sp]) {
          sp = sp + 1
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      Anchor(kind~) =>
        if self.test_anchor(kind, sp) {
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      Split(x~, y~) => {
        let (ok, esp, ns) = self.run(code, x, sp, clone_saves(saves))
        if ok {
          return (true, esp, ns)
        }
        pc = y
      }
      SplitLazy(x~, y~) => {
        let (ok, esp, ns) = self.run(code, y, sp, clone_saves(saves))
        if ok {
          return (true, esp, ns)
        }
        pc = x
      }
      Jmp(x~) => pc = x
      Save(slot~) => {
        saves[slot] = sp
        pc = pc + 1
      }
      Match => return (true, sp, saves)
      Backref(slot~, icase~) => {
        let s = saves[2 * slot]
        let e = saves[2 * slot + 1]
        if s < 0 {
          return (false, sp, saves)
        }
        let n = e - s
        if sp + n > len {
          return (false, sp, saves)
        }
        let mut i = 0
        let mut ok = true
        while i < n {
          let a = self.chars[sp + i]
          let b = self.chars[s + i]
          if a != b && !(icase && (a - b == 32 || b - a == 32)) {
            ok = false
            break
          }
          i = i + 1
        }
        if ok {
          sp = sp + n
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      }
      Keep => {
        saves[0] = sp
        pc = pc + 1
      }
      Grapheme =>
        if sp < len {
          sp = sp + 1
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      Atomic(id~) => {
        let sub = program.extra.get(id).unwrap()
        let (ok, esp, ns) = self.run(sub, 0, sp, clone_saves(saves))
        if ok {
          sp = esp
          saves = ns
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      }
      Lookahead(id~, positive~) => {
        let sub = program.extra.get(id).unwrap()
        let (ok, _esp, ns) = self.run(sub, 0, sp, clone_saves(saves))
        if ok == positive {
          saves = ns
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      }
      Lookbehind(id~, positive~) => {
        let sub = program.extra.get(id).unwrap()
        let mut found = false
        let mut found_saves = saves
        let mut j = 0
        while j <= sp {
          let (ok, esp, ns) = self.run(sub, 0, j, clone_saves(saves))
          if ok && esp == sp {
            found = true
            found_saves = ns
            break
          }
          j = j + 1
        }
        if found == positive {
          saves = found_saves
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      }
      CondGroup(slot~, yes_id~, no_id~) => {
        let bid = if saves[2 * slot] >= 0 { yes_id } else { no_id }
        let sub = program.extra.get(bid).unwrap()
        let (ok, esp, ns) = self.run(sub, 0, sp, clone_saves(saves))
        if ok {
          sp = esp
          saves = ns
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      }
      CondLook(id~, yes_id~, no_id~) => {
        let sub = program.extra.get(id).unwrap()
        let (ok, _esp, _) = self.run(sub, 0, sp, clone_saves(saves))
        let bid = if ok { yes_id } else { no_id }
        let bsub = program.extra.get(bid).unwrap()
        let (ok2, esp2, ns2) = self.run(bsub, 0, sp, clone_saves(saves))
        if ok2 {
          sp = esp2
          saves = ns2
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      }
      Star(body_id~, greedy~) => {
        let sub = program.extra.get(body_id).unwrap()
        let (ok, esp, ns) = self.run(sub, 0, sp, clone_saves(saves))
        if greedy {
          if ok && esp > sp {
            let (ok2, esp2, ns2) = self.run(code, pc, esp, clone_saves(ns))
            if ok2 {
              return (true, esp2, ns2)
            }
            sp = esp
            saves = ns
            pc = pc + 1
          } else {
            pc = pc + 1
          }
        } else {
          let (okstop, esp_s, ns_s) = self.run(
            code,
            pc + 1,
            sp,
            clone_saves(saves),
          )
          if okstop {
            return (true, esp_s, ns_s)
          }
          if ok && esp > sp {
            let (ok2, esp2, ns2) = self.run(code, pc, esp, clone_saves(ns))
            if ok2 {
              return (true, esp2, ns2)
            }
            sp = esp
            saves = ns
            pc = pc + 1
          } else {
            return (false, sp, saves)
          }
        }
      }
      RecurseGroup(slot~) => {
        let sub = match program.group_codes.get(slot) {
          Some(s) => s
          None => [Match]
        }
        let (ok, esp, ns) = self.run(sub, 0, sp, clone_saves(saves))
        if ok {
          sp = esp
          saves = ns
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      }
      RecurseWhole => {
        let (ok, esp, ns) = self.run(program.code, 0, sp, clone_saves(saves))
        if ok {
          sp = esp
          saves = ns
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      }
    }
  } nobreak {
    (false, 0, saves)
  }
}

///|
fn make_match(saves : Array[Int32], ngroups : Int32) -> MatchResult {
  let spans : Array[(Int32, Int32)] = Array::make(ngroups + 1, (-1, -1))
  for g in 0..<(ngroups + 1) {
    let s = saves[2 * g]
    let e = saves[2 * g + 1]
    if s >= 0 && e >= 0 {
      spans[g] = (s, e)
    }
  }
  MatchResult::{ start: saves[0], end: saves[1], spans, fuzzy: None, }
}

///|
/// Search left to right from `pos` to `endpos`, returning the leftmost match.
pub fn Program::search(
  self : Program,
  text : String,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> MatchResult? raise @parse.Refused {
  let chars = to_code_points(text)
  let len = chars.length()
  let end = if endpos < 0 { len } else { endpos }
  let mat = Matcher::{ program: self, chars, len, pos, limit, steps: [0], }
  let mut p = pos
  while p <= end {
    let init = Array::make(2 * (self.ngroups + 1), -1)
    let (ok, _esp, saves) = mat.run(self.code, 0, p, init)
    if ok {
      return Some(make_match(saves, self.ngroups))
    }
    p = p + 1
  }
  None
}

///|
/// Match only at `pos` (Python's `match`).
pub fn Program::match_at(
  self : Program,
  text : String,
  pos~ : Int32 = 0,
  limit~ : Int32 = 10000000,
) -> MatchResult? raise @parse.Refused {
  let chars = to_code_points(text)
  let mat = Matcher::{
    program: self,
    chars,
    len: chars.length(),
    pos,
    limit,
    steps: [0],
  }
  let init = Array::make(2 * (self.ngroups + 1), -1)
  let (ok, _esp, saves) = mat.run(self.code, 0, pos, init)
  if ok {
    Some(make_match(saves, self.ngroups))
  } else {
    None
  }
}

///|
/// Match the whole region `pos..endpos` (Python's `fullmatch`).
pub fn Program::fullmatch(
  self : Program,
  text : String,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
) -> MatchResult? raise @parse.Refused {
  let chars = to_code_points(text)
  let len = chars.length()
  let end = if endpos < 0 { len } else { endpos }
  let mat = Matcher::{ program: self, chars, len, pos, limit, steps: [0], }
  let init = Array::make(2 * (self.ngroups + 1), -1)
  let (ok, esp, saves) = mat.run(self.code, 0, pos, init)
  if ok && esp == end {
    Some(make_match(saves, self.ngroups))
  } else {
    None
  }
}
