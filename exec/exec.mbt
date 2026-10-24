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
  /// A fuzzy match over a literal/character-class sequence: the target is
  /// matched against the text with a bounded Levenshtein budget of insertions,
  /// deletions and substitutions. The general case (a fuzzy quantifier over an
  /// arbitrary sub-expression) still matches the inner node exactly; this
  /// covers the common, well-defined case of a fuzzy literal or class run.
  FuzzyLit(
    target~ : Array[@prop.CharSet],
    ins~ : Int32,
    del~ : Int32,
    sub~ : Int32,
    err~ : Int32
  )
  /// `(*ACCEPT)`: end the whole match here, successfully. The engine raises an
  /// `Accept` refusal that the top-level search/match/fullmatch catch and turn
  /// into the winning match.
  Accept
  /// `(*FAIL)` / `(*F)`: make this match attempt fail at this position.
  Fail
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
  /// The edit budget spent, when the pattern was fuzzy, as
  /// `(substitutions, insertions, deletions)`; `None` otherwise.
  fuzzy : (Int32, Int32, Int32)?
  /// The individual edits, when the pattern was fuzzy, as
  /// `(substitutions, insertions, deletions)` — each a list of
  /// `(string_offset, pattern_offset)`; `None` otherwise.
  fuzzy_changes : (
    Array[(Int32, Int32)],
    Array[(Int32, Int32)],
    Array[(Int32, Int32)],
  )?
}

///|
/// The edits a fuzzy match made, reconstructed from the alignment that won.
priv struct FuzzyOutcome {
  /// End code-point offset just past the fuzzy run.
  end : Int32
  /// Substitutions, insertions and deletions actually used.
  sub : Int32
  ins : Int32
  del : Int32
  /// Per-edit positions, as `(string_offset, pattern_offset)`.
  subs : Array[(Int32, Int32)]
  ins_ch : Array[(Int32, Int32)]
  del_ch : Array[(Int32, Int32)]
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
        // Emit the body into a program that already carries its leading
        // `Save`, so the `Split`/`Jmp` offsets the body computes are correct
        // relative to where the sub-program actually starts. Prepending the
        // `Save` afterwards would shift every offset by one and turn an
        // alternation into an infinite loop.
        let wrapped : Array[Inst] = [Save(slot=2 * key)]
        self.emit(node, wrapped)
        wrapped.push(Save(slot=2 * key + 1))
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
    @parse.Fuzzy(spec~, node~) =>
      // When the inner node is a literal or character-class run, lower it to a
      // `FuzzyLit` that the matcher solves with a bounded edit-distance search.
      // Otherwise the budget is ignored and the inner node is matched exactly,
      // as before — the syntax is still accepted.
      match (flatten_literal(node), fuzzy_caps(spec)) {
        (Some(target), Some((ins, del, sub, err))) =>
          code.push(FuzzyLit(target~, ins~, del~, sub~, err~))
        _ => self.emit(node, code)
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
    @parse.Verb(kind~) =>
      match kind {
        // `(*ACCEPT)` and `(*FAIL)` lower to dedicated instructions; the rest
        // carry no observable effect on a plain match, so they are dropped.
        @parse.Accept => code.push(Accept)
        @parse.Fail => code.push(Fail)
        _ => ()
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
/// Flatten a node into a sequence of character sets when it is nothing but
/// literals and character classes (possibly grouped). Anything else — an
/// alternation, a quantifier, an anchor, a backreference — returns `None`, and
/// the fuzzy quantifier falls back to matching the node exactly.
fn flatten_literal(node : @parse.Node) -> Array[@prop.CharSet]? {
  match node {
    @parse.Char(code=c) => Some([@prop.CharSet::single(c)])
    @parse.Class(set~) => Some([set])
    @parse.Group(node=inner, ..) => flatten_literal(inner)
    @parse.Seq(items~) => {
      let out : Array[@prop.CharSet] = []
      for it in items {
        match flatten_literal(it) {
          Some(set) =>
            for s in set {
              out.push(s)
            }
          None => return None
        }
      }
      Some(out)
    }
    _ => None
  }
}

///|
/// Turn a parsed budget into `(insertions, deletions, substitutions, errors)`
/// caps, or `None` when there is no budget to spend (or a weighted budget,
/// which the literal matcher does not approximate).
fn fuzzy_caps(spec : @parse.FuzzySpec) -> (Int32, Int32, Int32, Int32)? {
  if spec.cost is Some(_) {
    // A weighted budget (`2i+1d+1s<=3`): not approximated here, so the inner
    // node is matched exactly.
    return None
  }
  if spec.errors is None &&
    spec.insertions is None &&
    spec.deletions is None &&
    spec.substitutions is None {
    return None
  }
  match spec.errors {
    Some(e) => {
      // A total error budget also caps each operation at the same total, with
      // the combined spend bounded by `err`.
      let ins = spec.insertions.unwrap_or(e)
      let del = spec.deletions.unwrap_or(e)
      let sub = spec.substitutions.unwrap_or(e)
      Some((ins, del, sub, e))
    }
    None => {
      // Individual budgets only: an unmentioned operation is not permitted.
      let ins = spec.insertions.unwrap_or(0)
      let del = spec.deletions.unwrap_or(0)
      let sub = spec.substitutions.unwrap_or(0)
      Some((ins, del, sub, -1))
    }
  }
}

///|
/// Solve a fuzzy match of `target` against the text starting at `sp`, allowing
/// at most `ins` insertions, `del` deletions and `sub` substitutions, and at
/// most `err` errors of any kind (`err < 0` means no total cap). Returns the
/// alignment (`FuzzyOutcome`) whose end is the longest reach that finishes the
/// pattern within budget, or `None`.
///
/// The search is a bounded Levenshtein alignment: a state is `(ti, pi, ins,
/// del, sub)` and we ask whether `pi == target.length()` is reachable. Each
/// reachable cell keeps a single representative state (the one with the fewest
/// total errors), together with the operation and predecessor that reached it,
/// so the winning alignment can be walked back into its individual edits.
fn fuzzy_lit_end(
  chars : Array[Int32],
  sp : Int32,
  len : Int32,
  target : Array[@prop.CharSet],
  ins_cap : Int32,
  del_cap : Int32,
  sub_cap : Int32,
  err_cap : Int32,
) -> FuzzyOutcome? {
  let m = target.length()
  if m == 0 {
    return Some(FuzzyOutcome::{
      end: sp,
      sub: 0,
      ins: 0,
      del: 0,
      subs: [],
      ins_ch: [],
      del_ch: [],
    })
  }
  // Guard against pathological budgets: beyond these, the fuzzy run cannot
  // match, so the instruction fails the attempt.
  if m > 64 || ins_cap > 32 || del_cap > 32 || sub_cap > 32 {
    return None
  }
  let avail = len - sp
  if avail < 0 {
    return None
  }
  let max_ti = if avail < m + ins_cap { avail } else { m + ins_cap }
  let dl1 = del_cap + 1
  let sl1 = sub_cap + 1
  let pack = fn(ins : Int32, del : Int32, sub : Int32) -> Int32 {
    (ins * dl1 + del) * sl1 + sub
  }
  let unpack = fn(st : Int32) -> (Int32, Int32, Int32) {
    let sub0 = st % sl1
    let rem = st / sl1
    let del0 = rem % dl1
    let ins0 = rem / dl1
    (ins0, del0, sub0)
  }
  // `cells[ti][pi]` holds the packed representative state, `-1` meaning
  // unreachable. `back[ti][pi]` holds `(op, prev)` with `op` ∈ {1 start, 2
  // match, 3 sub, 4 ins, 5 del} and `prev` the predecessor cell index
  // `pti * (m + 1) + ppi`, or `-1` for the start.
  let cells : Array[Array[Int32]] = []
  let back : Array[Array[(Int32, Int32)]] = []
  let mut ti = 0
  while ti <= max_ti {
    let rc : Array[Int32] = []
    let rb : Array[(Int32, Int32)] = []
    let mut pi = 0
    while pi <= m {
      rc.push(-1)
      rb.push((-1, -1))
      pi = pi + 1
    }
    cells.push(rc)
    back.push(rb)
    ti = ti + 1
  }
  cells[0][0] = pack(0, 0, 0)
  back[0][0] = (1, -1)
  // A state `a` is better than `b` when it has fewer total errors; ties break
  // towards the smaller packed value (fewer insertions first).
  let better = fn(a : Int32, b : Int32) -> Bool {
    let (ai, ad, as_) = unpack(a)
    let (bi, bd, bs) = unpack(b)
    let ta = ai + ad + as_
    let tb = bi + bd + bs
    if ta != tb {
      ta < tb
    } else {
      a < b
    }
  }
  let stride = m + 1
  ti = 0
  while ti <= max_ti {
    let mut pi = 0
    while pi <= m {
      let st = cells[ti][pi]
      if st < 0 {
        pi = pi + 1
        continue
      }
      let (ins0, del0, sub0) = unpack(st)
      let prev = ti * stride + pi
      if pi < m {
        if ti < max_ti {
          let hit = target[pi].contains(chars[sp + ti])
          if hit {
            // Match: no error.
            let cand = cells[ti + 1][pi + 1]
            if cand < 0 || better(st, cand) {
              cells[ti + 1][pi + 1] = st
              back[ti + 1][pi + 1] = (2, prev)
            }
          } else if sub0 < sub_cap {
            // Substitute one character.
            let ns = pack(ins0, del0, sub0 + 1)
            let cand = cells[ti + 1][pi + 1]
            if cand < 0 || better(ns, cand) {
              cells[ti + 1][pi + 1] = ns
              back[ti + 1][pi + 1] = (3, prev)
            }
          }
          // Insert a text character (pattern stays put).
          if ins0 < ins_cap {
            let ns = pack(ins0 + 1, del0, sub0)
            let cand = cells[ti + 1][pi]
            if cand < 0 || better(ns, cand) {
              cells[ti + 1][pi] = ns
              back[ti + 1][pi] = (4, prev)
            }
          }
        }
        // Delete a pattern character (text stays put).
        if del0 < del_cap {
          let ns = pack(ins0, del0 + 1, sub0)
          let cand = cells[ti][pi + 1]
          if cand < 0 || better(ns, cand) {
            cells[ti][pi + 1] = ns
            back[ti][pi + 1] = (5, prev)
          }
        }
      } else if ti < max_ti && ins0 < ins_cap {
        // Pattern consumed: only trailing insertions remain.
        let ns = pack(ins0 + 1, del0, sub0)
        let cand = cells[ti + 1][pi]
        if cand < 0 || better(ns, cand) {
          cells[ti + 1][pi] = ns
          back[ti + 1][pi] = (4, prev)
        }
      }
      pi = pi + 1
    }
    ti = ti + 1
  }
  // Greedy fuzzy: the longest end that finishes the pattern (and respects any
  // total error cap) wins.
  let mut best = -1
  let mut t = max_ti
  while t >= 0 {
    let st = cells[t][m]
    if st >= 0 {
      if err_cap < 0 {
        best = t
        break
      }
      let (i, d, s) = unpack(st)
      if i + d + s <= err_cap {
        best = t
        break
      }
    }
    t = t - 1
  }
  if best < 0 {
    return None
  }
  // Walk the back pointers from `(best, m)` to recover the individual edits.
  let subs : Array[(Int32, Int32)] = []
  let ins_ch : Array[(Int32, Int32)] = []
  let del_ch : Array[(Int32, Int32)] = []
  let mut cti = best
  let mut cpi = m
  while cti > 0 || cpi > 0 {
    let (op, _prev) = back[cti][cpi]
    match op {
      2 => {
        // Exact match: no edit.
        cti = cti - 1
        cpi = cpi - 1
      }
      3 => {
        subs.push((sp + cti, cpi))
        cti = cti - 1
        cpi = cpi - 1
      }
      4 => {
        ins_ch.push((sp + cti, cpi))
        cti = cti - 1
      }
      5 => {
        del_ch.push((sp + cti, cpi))
        cpi = cpi - 1
      }
      _ => break
    }
  }
  Some(FuzzyOutcome::{
    end: sp + best,
    sub: subs.length(),
    ins: ins_ch.length(),
    del: del_ch.length(),
    subs,
    ins_ch,
    del_ch,
  })
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
  fz : Array[FuzzyOutcome?],
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
      // once its last instruction has been run.
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
        let (ok, esp, ns) = self.run(code, x, sp, clone_saves(saves), fz)
        if ok {
          return (true, esp, ns)
        }
        pc = y
      }
      SplitLazy(x~, y~) => {
        let (ok, esp, ns) = self.run(code, y, sp, clone_saves(saves), fz)
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
        let (ok, esp, ns) = self.run(sub, 0, sp, clone_saves(saves), fz)
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
        let (ok, _esp, ns) = self.run(sub, 0, sp, clone_saves(saves), fz)
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
          let (ok, esp, ns) = self.run(sub, 0, j, clone_saves(saves), fz)
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
        let (ok, esp, ns) = self.run(sub, 0, sp, clone_saves(saves), fz)
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
        let (ok, _esp, _) = self.run(sub, 0, sp, clone_saves(saves), fz)
        let bid = if ok { yes_id } else { no_id }
        let bsub = program.extra.get(bid).unwrap()
        let (ok2, esp2, ns2) = self.run(bsub, 0, sp, clone_saves(saves), fz)
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
        let (ok, esp, ns) = self.run(sub, 0, sp, clone_saves(saves), fz)
        if greedy {
          if ok && esp > sp {
            let (ok2, esp2, ns2) = self.run(code, pc, esp, clone_saves(ns), fz)
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
            fz,
          )
          if okstop {
            return (true, esp_s, ns_s)
          }
          if ok && esp > sp {
            let (ok2, esp2, ns2) = self.run(code, pc, esp, clone_saves(ns), fz)
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
        let (ok, esp, ns) = self.run(sub, 0, sp, clone_saves(saves), fz)
        if ok {
          sp = esp
          saves = ns
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      }
      RecurseWhole => {
        let (ok, esp, ns) = self.run(
          program.code,
          0,
          sp,
          clone_saves(saves),
          fz,
        )
        if ok {
          sp = esp
          saves = ns
          pc = pc + 1
        } else {
          return (false, sp, saves)
        }
      }
      FuzzyLit(target~, ins~, del~, sub~, err~) =>
        match
          fuzzy_lit_end(self.chars, sp, self.len, target, ins, del, sub, err) {
          None => return (false, sp, saves)
          Some(out) => {
            fz[0] = Some(out)
            sp = out.end
            pc = pc + 1
          }
        }
      Accept => raise @parse.Accept(start=saves[0], end=sp)
      Fail => return (false, sp, saves)
    }
  } nobreak {
    (false, 0, saves)
  }
}

///|
fn make_match(
  saves : Array[Int32],
  ngroups : Int32,
  fz : FuzzyOutcome?,
) -> MatchResult {
  let spans : Array[(Int32, Int32)] = Array::make(ngroups + 1, (-1, -1))
  for g in 0..<(ngroups + 1) {
    let s = saves[2 * g]
    let e = saves[2 * g + 1]
    if s >= 0 && e >= 0 {
      spans[g] = (s, e)
    }
  }
  let (fuzzy, fuzzy_changes) = match fz {
    None => (None, None)
    Some(o) => (Some((o.sub, o.ins, o.del)), Some((o.subs, o.ins_ch, o.del_ch)))
  }
  MatchResult::{ start: saves[0], end: saves[1], spans, fuzzy, fuzzy_changes, }
}

///|
/// Build the match `(*ACCEPT)` asked for: group 0 spans `start..end`, and no
/// other group is set, because the verb cut the pattern short before they ran.
fn accept_match(start : Int32, end : Int32, ngroups : Int32) -> MatchResult {
  let spans : Array[(Int32, Int32)] = Array::make(ngroups + 1, (-1, -1))
  spans[0] = (start, end)
  MatchResult::{ start, end, spans, fuzzy: None, fuzzy_changes: None, }
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
  let fz : Array[FuzzyOutcome?] = [None]
  let mat = Matcher::{ program: self, chars, len, pos, limit, steps: [0], }
  let mut p = pos
  try {
    while p <= end {
      let init = Array::make(2 * (self.ngroups + 1), -1)
      let (ok, _esp, saves) = mat.run(self.code, 0, p, init, fz)
      if ok {
        return Some(make_match(saves, self.ngroups, fz[0]))
      }
      p = p + 1
    }
    None
  } catch {
    @parse.Accept(start~, end~) => Some(accept_match(start, end, self.ngroups))
    e => raise e
  }
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
  let fz : Array[FuzzyOutcome?] = [None]
  let mat = Matcher::{
    program: self,
    chars,
    len: chars.length(),
    pos,
    limit,
    steps: [0],
  }
  let init = Array::make(2 * (self.ngroups + 1), -1)
  try {
    let (ok, _esp, saves) = mat.run(self.code, 0, pos, init, fz)
    if ok {
      Some(make_match(saves, self.ngroups, fz[0]))
    } else {
      None
    }
  } catch {
    @parse.Accept(start~, end~) => Some(accept_match(start, end, self.ngroups))
    e => raise e
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
  let fz : Array[FuzzyOutcome?] = [None]
  let mat = Matcher::{ program: self, chars, len, pos, limit, steps: [0], }
  let init = Array::make(2 * (self.ngroups + 1), -1)
  try {
    let (ok, esp, saves) = mat.run(self.code, 0, pos, init, fz)
    if ok && esp == end {
      Some(make_match(saves, self.ngroups, fz[0]))
    } else {
      None
    }
  } catch {
    @parse.Accept(start~, end~) => Some(accept_match(start, end, self.ngroups))
    e => raise e
  }
}
