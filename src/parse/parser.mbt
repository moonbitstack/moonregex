// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The parser: three grammars, one syntax tree.
//
// One recursive descent walks all three, branching where the grammars part
// company. That is a deliberate choice over three parsers: the shared
// skeleton is most of the code, and the places the dialects differ —
// escapes, group syntax, what a `-` means in a class — are few enough to
// name inline. Where a dialect refuses a construct, it refuses it here, with
// the position, so the caller is told which grammar was being read.

///|
/// What one item in a character class contributed: a code point, or a set.
priv enum ClassPart {
  One(code~ : Int32)
  Many(set~ : @prop.CharSet)
}

///|
/// A parsed quantifier: `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}`, or a fuzzy
/// budget — with whether the `+` that followed it made it possessive.
priv struct Quant {
  min : Int32
  max : Int32?
  possessive : Bool
  fuzzy : FuzzySpec?
}

///|
/// Where the parser is, and what it has learned so far.
priv struct Parser {
  /// The whole pattern, for reporting where reading stopped.
  src : StringView
  /// What is left to read.
  rest : StringView
  dialect : Dialect
  /// The behaviour set in force; `(?V1)` changes it mid-pattern.
  mut version : Version
  /// The flags in force here; a scoped `(?i:…)` swaps them for its body.
  mut flags : Flags
  /// How many capture groups have opened so far.
  mut groups : Int32
  /// Group name to the slots carrying it.
  groupindex : Map[String, Array[Int32]]
  /// The `\L<name>` lists the pattern used.
  named_lists : Map[String, Array[String]]
  /// The `\L<name>` lists the caller passed in.
  lists : Map[String, Array[String]]
  /// Capture groups currently open, innermost last: a backreference cannot
  /// name one of them, as its match is not decided yet.
  open : Array[Int32]
  /// How deep in groups the parser is, to refuse a pattern that would
  /// overflow the stack before it does.
  mut depth : Int32
}

///|
/// How deep groups may nest before the parser refuses.
const MAX_DEPTH = 64

///|
/// Read a pattern into the syntax tree.
///
/// `flags` are the compile-time flags; the pattern's own global inline flags
/// are merged into them as they are met, and the merged result is what
/// `Ast::flags` answers.
pub fn parse(
  pattern : StringView,
  flags~ : Flags = flags,
  dialect~ : Dialect = dialect,
  lists? : Map[String, Array[String]],
) -> Ast raise Refused {
  if dialect is Ecma262 && flags.unicode && flags.unicode_sets {
    // ECMA-262: the two Unicode modes are alternatives, never a pair.
    raise Pattern(
      msg="invalid regular expression flags",
      at=0,
      line=1,
      column=1,
    )
  }
  let parser : Parser = {
    src: pattern,
    rest: pattern,
    dialect,
    version: flags.version,
    flags,
    groups: 0,
    groupindex: {},
    named_lists: {},
    lists: lists.unwrap_or({}),
    open: [],
    depth: 0,
  }
  parser.read()
}

///|
/// Read the whole pattern: global inline flags, one alternation, nothing left.
fn Parser::read(self : Parser) -> Ast raise Refused {
  let rest = if self.dialect is Python {
    self.global_flags(self.rest)
  } else {
    self.rest
  }
  let (rest, root) = self.alternation(rest)
  if rest.length() > 0 {
    let c = rest.at(0).to_int()
    let msg = if c == ')' {
      "unbalanced parenthesis"
    } else if c == ']' {
      "unbalanced bracket"
    } else {
      "unexpected character"
    }
    raise self.refuse(rest, msg)
  }
  {
    root,
    groups: self.groups,
    groupindex: self.groupindex,
    named_lists: self.named_lists,
    flags: self.flags,
  }
}

// ---------------------------------------------------------------------------
// The recursive descent
// ---------------------------------------------------------------------------

///|
/// `sequence ('|' sequence)*`
fn Parser::alternation(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  let branches : Array[Node] = []
  let mut view = rest
  let (next, first) = self.sequence(view)
  view = next
  branches.push(first)
  while view.length() > 0 && view.at(0).to_int() == '|' {
    let (nxt, branch) = self.sequence(view.view(start_offset=1))
    branches.push(branch)
    view = nxt
  }
  (view, if branches.length() == 1 { branches[0] } else { Alt(items=branches) })
}

///|
/// `term*`, up to the end of the pattern, a `|`, or the `)` closing a group.
fn Parser::sequence(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  let items : Array[Node] = []
  let mut view = self.skip_space(rest)
  while view.length() > 0 {
    let c = view.at(0).to_int()
    if c == '|' || c == ')' {
      break
    }
    let (next, item) = self.term(view)
    items.push(item)
    view = self.skip_space(next)
  }
  (
    view,
    if items.length() == 0 {
      Empty
    } else if items.length() == 1 {
      items[0]
    } else {
      Seq(items~)
    },
  )
}

///|
/// Whitespace and `#` comments, which the `x` flag makes insignificant
/// everywhere but inside a class.
fn Parser::skip_space(self : Parser, rest : StringView) -> StringView {
  if !self.flags.verbose {
    return rest
  }
  let mut view = rest
  let mut going = true
  while going && view.length() > 0 {
    match view.at(0).to_int() {
      ' ' | '\t' | '\n' | '\r' | '\u{0c}' | '\u{0b}' =>
        view = view.view(start_offset=1)
      '#' => {
        // A comment runs to the end of the line, newline included.
        let mut i = 0
        while i < view.length() && view.at(i).to_int() != '\n' {
          i += 1
        }
        view = view.view(start_offset=i)
      }
      _ => going = false
    }
  }
  view
}

///|
/// An atom and the quantifier that may follow it.
fn Parser::term(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  let (after_atom, atom, assertion) = self.atom(rest)
  let (rest, node) = self.quantify(atom, after_atom)
  if node is Repeat(node=Lookaround(..), ..) && !(self.dialect is Python) {
    raise self.refuse(after_atom, "nothing to repeat")
  }
  if node is Repeat(..) && assertion {
    // `^*` and `\b{2}` are refusals in every grammar here: an assertion
    // matches a position, and a position cannot be repeated. Lookarounds are
    // quantifiable under Python, which reads `(?=a)*` as a repeated test.
    // The offending quantifier is the one just past the atom, so the refusal
    // points at it rather than past it.
    raise self.refuse(after_atom, "nothing to repeat")
  }
  (rest, node)
}

///|
/// The quantifier after an atom, if there is one.
fn Parser::quantify(
  self : Parser,
  atom : Node,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  let (rest, quant) = self.quantifier(rest)
  match quant {
    None => (rest, atom)
    Some(q) => {
      // `?` after a quantifier is the lazy marker, `+` the possessive one;
      // either way a quantifier may not follow it.
      let (rest, reluctant, possessive_mod) = if rest.length() > 0 &&
        rest.at(0).to_int() == '?' {
        (rest.view(start_offset=1), true, false)
      } else if rest.length() > 0 && rest.at(0).to_int() == '+' {
        (rest.view(start_offset=1), false, true)
      } else {
        (rest, false, false)
      }
      let (_, again) = self.quantifier(rest)
      if again is Some(_) {
        raise self.refuse(rest, "multiple repeat")
      }
      let node = match q.fuzzy {
        Some(spec) => Fuzzy(spec~, node=atom)
        None => {
          // A possessive quantifier is an atomic repeat: no backtracking into
          // the repetitions once they are taken. The possessive marker may be
          // the `+` just past the quantifier, or the `+` after a counted one.
          let possessive = q.possessive || possessive_mod
          let repeated = Repeat(
            node=atom,
            min=q.min,
            max=q.max,
            greedy=!reluctant,
          )
          if possessive {
            Atomic(node=repeated)
          } else {
            repeated
          }
        }
      }
      (rest, node)
    }
  }
}

///|
/// Read a quantifier, or nothing.
///
/// A `{` that does not open a well-formed counted quantifier is a literal in
/// Python and in ECMA-262's Annex B grammar, and a refusal everywhere else —
/// which is why the strictness is asked of the dialect rather than assumed.
fn Parser::quantifier(
  self : Parser,
  rest : StringView,
) -> (StringView, Quant?) raise Refused {
  if rest.length() == 0 {
    return (rest, None)
  }
  let c = rest.at(0).to_int()
  if c == '*' {
    return (
      rest.view(start_offset=1),
      Some({ min: 0, max: None, possessive: false, fuzzy: None, }),
    )
  }
  if c == '+' {
    return (
      rest.view(start_offset=1),
      Some({ min: 1, max: None, possessive: false, fuzzy: None, }),
    )
  }
  if c == '?' {
    return (
      rest.view(start_offset=1),
      Some({ min: 0, max: Some(1), possessive: false, fuzzy: None, }),
    )
  }
  if c != '{' {
    return (rest, None)
  }
  // `{` opens a counted quantifier, a fuzzy budget, or nothing at all.
  match self.read_until_close(rest.view(start_offset=1), '}') {
    None => {
      if self.strict_braces() {
        raise self.refuse(rest, "unterminated quantifier")
      }
      (rest, None)
    }
    Some((inner, after)) =>
      match self.counted(inner) {
        Some((min, max)) => {
          let (after, possessive) = if after.length() > 0 &&
            after.at(0).to_int() == '+' {
            (after.view(start_offset=1), true)
          } else {
            (after, false)
          }
          (after, Some({ min, max, possessive, fuzzy: None, }))
        }
        None =>
          match self.fuzzy_spec(inner) {
            Some(spec) =>
              (
                after,
                Some({
                  min: 0,
                  max: None,
                  possessive: false,
                  fuzzy: Some(spec),
                }),
              )
            None => {
              if self.strict_braces() {
                raise self.refuse(rest, "invalid quantifier")
              }
              (rest, None)
            }
          }
      }
  }
}

///|
/// The punctuators ECMA-262 reserves as a pair inside a class expression.
fn is_double_reserved(c : Int32) -> Bool {
  match c {
    0x26
    | 0x21
    | 0x23
    | 0x24
    | 0x25
    | 0x2A
    | 0x2B
    | 0x2C
    | 0x2E
    | 0x3A
    | 0x3B
    | 0x3C
    | 0x3D
    | 0x3E
    | 0x3F
    | 0x40
    | 0x5E
    | 0x60
    | 0x7E => true
    _ => false
  }
}

///|
/// The punctuation ECMA-262's `v` mode reserves inside a class expression, so
/// that a bare one cannot be mistaken for syntax.
fn is_reserved_in_class(c : Int32) -> Bool {
  match c {
    0x28
    | 0x29
    | 0x7B
    | 0x7D
    | 0x2F
    | 0x7C
    | 0x21
    | 0x23
    | 0x25
    | 0x2C
    | 0x3A
    | 0x3B
    | 0x3C
    | 0x3D
    | 0x3E
    | 0x40
    | 0x60
    | 0x7E
    | 0x26
    | 0x2D => true
    _ => false
  }
}

///|
/// Whether a stray `{` is a refusal or a literal.
fn Parser::strict_braces(self : Parser) -> Bool {
  match self.dialect {
    // ECMA-262 with `u` refuses lone quantifier brackets; without it, Annex B
    // lets them stand for themselves.
    Ecma262 => self.flags.unicode || self.flags.unicode_sets
    // lexmatch's grammar has no use for a `{` that is not a quantifier.
    Lexmatch => true
    Python => false
  }
}

///|
/// Read `{n}`, `{n,}`, `{n,m}` out of a quantifier body.
fn Parser::counted(
  self : Parser,
  body : StringView,
) -> (Int32, Int32?)? raise Refused {
  let mut i = 0
  let min = match self.digits(body, 0) {
    None => return None
    Some((n, next)) => {
      i = next
      n
    }
  }
  if i == body.length() {
    return Some((min, Some(min)))
  }
  if body.at(i).to_int() != ',' {
    return None
  }
  if i + 1 == body.length() {
    // `{n,}`: at least `n`, with no ceiling.
    return Some((min, None))
  }
  let (max, next) = match self.digits(body, i + 1) {
    None => return None
    Some(pair) => pair
  }
  if next != body.length() {
    return None
  }
  if min > max {
    raise self.refuse(body, "min repeat greater than max repeat")
  }
  Some((min, Some(max)))
}

///|
/// Read decimal digits starting at `from`, and where reading stopped.
fn Parser::digits(
  _self : Parser,
  text : StringView,
  from : Int32,
) -> (Int32, Int32)? {
  let mut i = from
  let mut value : Int32? = None
  while i < text.length() {
    let c = text.at(i).to_int()
    if c < '0'.to_int() || c > '9'.to_int() {
      break
    }
    value = Some(value.unwrap_or(0) * 10 + (c - '0'.to_int()))
    i += 1
  }
  match value {
    None => None
    Some(v) => Some((v, i))
  }
}

///|
/// Read a fuzzy budget out of a quantifier body: `{e<=1}`, `{i<=2,d<=1}`,
/// `{2i+1d+1s<=3}`.
fn Parser::fuzzy_spec(_self : Parser, body : StringView) -> FuzzySpec? {
  let weighted = body.contains("i+") ||
    body.contains("d+") ||
    body.contains("s+")
  let mut spec : FuzzySpec = {
    insertions: None,
    deletions: None,
    substitutions: None,
    errors: None,
    cost: None,
  }
  let mut seen = false
  for part in body.to_owned().split(",") {
    let (lhs, rhs) = match part[:].split_once("<=") {
      None => return None
      Some(pair) => pair
    }
    let budget = match parse_int(rhs) {
      None => return None
      Some(n) => n
    }
    let name = lhs.trim()
    if weighted {
      // `<n>i+<n>d+<n>s<=<n>`: weights and a budget over them.
      let mut insertions = 0
      let mut deletions = 0
      let mut substitutions = 0
      for term in name.to_owned().split("+") {
        let t = term.trim()
        if t.length() == 0 {
          return None
        }
        let letter = t.view(start_offset=t.length() - 1)
        let count = if t.length() == 1 {
          1
        } else {
          match parse_int(t.view(end_offset=t.length() - 1)) {
            None => return None
            Some(n) => n
          }
        }
        match letter.to_owned() {
          "i" => insertions = count
          "d" => deletions = count
          "s" => substitutions = count
          _ => return None
        }
      }
      spec = {
        ..spec,
        insertions: Some(insertions),
        deletions: Some(deletions),
        substitutions: Some(substitutions),
        cost: Some((budget, budget, budget)),
      }
    } else {
      match name.to_owned() {
        "e" => spec = { ..spec, errors: Some(budget), }
        "i" => spec = { ..spec, insertions: Some(budget), }
        "d" => spec = { ..spec, deletions: Some(budget), }
        "s" => spec = { ..spec, substitutions: Some(budget), }
        _ => return None
      }
    }
    seen = true
  }
  if seen {
    Some(spec)
  } else {
    None
  }
}

///|
/// Decimal digits as a number.
fn parse_int(text : StringView) -> Int32? {
  let mut value = 0
  let mut seen = false
  for c in text {
    if c < '0' || c > '9' {
      return None
    }
    value = value * 10 + (c.to_int() - '0'.to_int())
    seen = true
  }
  if seen {
    Some(value)
  } else {
    None
  }
}

///|
/// Read up to the first `close`, returning what was between and what follows
/// it. `None` when there is no closing character at all.
fn Parser::read_until_close(
  _self : Parser,
  rest : StringView,
  close : Int32,
) -> (StringView, StringView)? {
  let mut i = 0
  while i < rest.length() {
    if rest.at(i).to_int() == close {
      return Some((rest.view(end_offset=i), rest.view(start_offset=i + 1)))
    }
    i += 1
  }
  None
}

// ---------------------------------------------------------------------------
// Atoms
// ---------------------------------------------------------------------------

///|
/// One atom: a literal, a class, a group, an escape, an assertion.
///
/// The third part of the answer says whether the atom is an assertion — a
/// thing that matches a position rather than consuming text — because that
/// decides whether a quantifier may follow it.
fn Parser::atom(
  self : Parser,
  rest : StringView,
) -> (StringView, Node, Bool) raise Refused {
  if rest.length() == 0 {
    raise self.refuse(rest, "unexpected end of pattern")
  }
  let c = rest.at(0).to_int()
  if c == '(' {
    let (view, node) = self.group(rest)
    return (view, node, false)
  }
  if c == '[' {
    let (view, node) = self.klass(rest)
    return (view, node, false)
  }
  if c == '\\' {
    return self.escape(rest)
  }
  if c == '.' {
    // `.` stands for any character but a newline, unless dotall — and under
    // lexmatch it stands for every character, newline included.
    let node = if self.dialect is Lexmatch {
      Any(dotall=true)
    } else {
      Any(dotall=self.flags.dotall)
    }
    return (rest.view(start_offset=1), node, false)
  }
  if c == '^' {
    return (
      rest.view(start_offset=1),
      Anchor(anchor=StartLine(multiline=self.flags.multiline)),
      true,
    )
  }
  if c == '$' {
    return (
      rest.view(start_offset=1),
      Anchor(
        anchor=EndLine(
          multiline=self.flags.multiline,
          // Python's `$` also sits before a newline at the very end of the
          // text; ECMA-262's does not.
          before_final_newline=self.dialect is Python,
        ),
      ),
      true,
    )
  }
  if c == '?' || c == '*' || c == '+' {
    raise self.refuse(rest, "nothing to repeat")
  }
  if c == '{' {
    // A `{…}` that reads as a counted quantifier has nothing to repeat here,
    // which is an error even where a stray brace is a literal. A brace that
    // is not a quantifier is a literal in Annex B and a refusal under `u`.
    match self.read_until_close(rest.view(start_offset=1), '}') {
      Some((inner, _)) =>
        match self.counted(inner) {
          Some(_) => raise self.refuse(rest, "nothing to repeat")
          None =>
            if self.strict_braces() {
              raise self.refuse(rest, "lone quantifier brackets")
            }
        }
      None =>
        if self.strict_braces() {
          raise self.refuse(rest, "lone quantifier brackets")
        }
    }
  }
  if c == '}' && self.strict_braces() {
    raise self.refuse(rest, "lone quantifier brackets")
  }
  // A literal code point.
  let (ch, view) = next_char(rest)
  let code = ch.to_int()
  let node = if self.flags.ignorecase {
    Class(set=@prop.CharSet::single(code).fold())
  } else {
    Char(code~)
  }
  (view, node, false)
}

///|
/// The first code point of a view, and the view past it.
fn next_char(rest : StringView) -> (Char, StringView) {
  let mut width = 1
  if rest.length() > 1 {
    let c = rest.at(0).to_int()
    if c >= 0xD800 && c <= 0xDBFF {
      let c2 = rest.at(1).to_int()
      if c2 >= 0xDC00 && c2 <= 0xDFFF {
        width = 2
      }
    }
  }
  let code = if width == 2 {
    0x10000 +
    ((rest.at(0).to_int() - 0xD800) << 10) +
    (rest.at(1).to_int() - 0xDC00)
  } else {
    rest.at(0).to_int()
  }
  (code.unsafe_to_char(), rest.view(start_offset=width))
}

///|
/// Read a `\Q…\E` quoted run into a sequence of literal nodes.
///
/// `rest` points just past the `\Q`. Everything is taken literally until a `\E`
/// closes it; if no `\E` appears, the rest of the pattern is quoted. Each code
/// point is folded under `ignorecase` the way a plain literal would be.
fn Parser::quote(self : Parser, rest : StringView) -> (StringView, Array[Node]) {
  let items : Array[Node] = []
  let mut view = rest
  while view.length() > 0 {
    if view.at(0).to_int() == '\\' &&
      view.length() > 1 &&
      view.at(1).to_int() == 'E'.to_int() {
      view = view.view(start_offset=2)
      break
    }
    let (ch, next) = next_char(view)
    let code = ch.to_int()
    items.push(
      if self.flags.ignorecase {
        Class(set=@prop.CharSet::single(code).fold())
      } else {
        Char(code~)
      },
    )
    view = next
  }
  (view, items)
}

///|
/// A group: `(…)`, with everything the `?` after the parenthesis can mean.
fn Parser::group(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  // The opening parenthesis is consumed by the caller's atom.
  let after = rest.view(start_offset=1)
  if self.depth >= MAX_DEPTH {
    raise self.refuse(rest, "pattern nests too deeply")
  }
  if after.length() == 0 {
    raise self.refuse(rest, "missing ), unterminated group")
  }
  if after.at(0).to_int() == '*' {
    // A control verb `(*ACCEPT)`, `(*FAIL)`, `(*MARK:name)`, … — no question
    // mark, so it is caught before the `(?` extension branch below.
    return self.verb(after)
  }
  if after.at(0).to_int() != '?' {
    // A plain capture group.
    return self.capture(after, None)
  }
  // `(?` — the extension decides what kind of group this is.
  if after.length() == 1 {
    raise self.refuse(rest, "unexpected end of pattern")
  }
  let ext = after.at(1).to_int()
  if ext == '|' {
    // `(?|…)`: a branch-reset group, so each alternative renumbers its groups
    // from the same slot.
    return self.branch_reset(after)
  }
  if ext == ':' {
    let (view, body) = self.scoped(after.view(start_offset=2))
    return (view, body)
  }
  if ext == '>' {
    // An atomic group: no backtracking into it once through.
    let (view, body) = self.scoped(after.view(start_offset=2))
    return (view, Atomic(node=body))
  }
  if ext == '=' || ext == '!' {
    let positive = ext == '='
    let (view, body) = self.scoped(after.view(start_offset=2))
    return (view, Lookaround(node=body, look=Ahead(positive~)))
  }
  if ext == '<' &&
    after.length() > 2 &&
    (after.at(2).to_int() == '=' || after.at(2).to_int() == '!') {
    let positive = after.at(2).to_int() == '='
    let (view, body) = self.scoped(after.view(start_offset=3))
    return (view, Lookaround(node=body, look=Behind(positive~)))
  }
  if ext == 'P' {
    return self.python_group(after)
  }
  if ext == '(' {
    return self.conditional(after)
  }
  if ext == '#' {
    // A comment: read to the closing parenthesis and drop it.
    return match self.read_until_close(after.view(start_offset=2), ')') {
      None => raise self.refuse(rest, "missing ), unterminated comment")
      Some((_, view)) =>
        // The comment stood where an atom was expected, so an empty node
        // keeps the tree well-formed and reading carries on after it.
        (view, Empty)
    }
  }
  if ext == 'R' || (ext >= '1' && ext <= '9') || ext == '&' {
    return self.recursion(after)
  }
  if ext == 'i' ||
    ext == 'm' ||
    ext == 's' ||
    ext == 'a' ||
    ext == 'u' ||
    ext == 'x' ||
    ext == 'f' ||
    ext == 'b' ||
    ext == 'e' ||
    ext == 'p' ||
    ext == 'r' ||
    ext == 'w' ||
    ext == 'v' ||
    ext == '-' {
    if self.dialect is Ecma262 {
      // ECMA-262's modifier letters are `i`, `m` and `s` only.
      let ok = ext == 'i' || ext == 'm' || ext == 's' || ext == '-'
      if !ok {
        raise self.refuse(rest, "invalid group")
      }
    }
    if self.dialect is Lexmatch && ext != 'i' {
      raise self.refuse(rest, "invalid group")
    }
    return self.scoped_flags(after)
  }
  if (self.dialect is Python || self.dialect is Ecma262) && ext == '<' {
    // `(?<name>…)`: ECMA-262's spelling of a named group and the regex
    // superset's; Python's own `re` refuses it, so it is read here rather than
    // under `?P`.
    let (view, body) = self.named(after.view(start_offset=2))
    return (view, body)
  }
  if ext == '\'' {
    // ECMA-262's `(?'name'…)`: the single-quoted spelling of a named group.
    if self.dialect is Ecma262 {
      let (view, body) = self.named_sq(after.view(start_offset=2))
      return (view, body)
    }
    raise self.refuse(rest, "unknown extension ?'")
  }
  raise self.refuse(rest, "unknown extension ?\{ext.unsafe_to_char()}")
}

///|
/// `(?|…)`: a branch-reset group. Each alternative renumbers its capture
/// groups from the same starting slot, so `(?|(a)|(b))` captures to group 1
/// whichever branch is taken. After the group, the counter resumes at the
/// highest slot any branch reached.
fn Parser::branch_reset(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  // rest points at `?|…`.
  let base = self.groups
  let branches : Array[Node] = []
  self.depth += 1
  self.groups = base
  let (next, first) = self.sequence(rest.view(start_offset=2))
  let mut view = next
  branches.push(first)
  let mut max_slot = self.groups
  while view.length() > 0 && view.at(0).to_int() == '|' {
    self.groups = base
    let (nxt, branch) = self.sequence(view.view(start_offset=1))
    branches.push(branch)
    if self.groups > max_slot {
      max_slot = self.groups
    }
    view = nxt
  }
  self.groups = max_slot
  self.depth -= 1
  let view = self.close(view)
  (view, if branches.length() == 1 { branches[0] } else { Alt(items=branches) })
}

///|
/// `(?:…)`: read a body and close the group, leaving flags alone.
fn Parser::scoped(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  self.depth += 1
  let (view, body) = self.alternation(rest)
  self.depth -= 1
  let view = self.close(view)
  (view, body)
}

///|
/// Read `)` and return the view past it, or refuse where it is missing.
fn Parser::close(self : Parser, rest : StringView) -> StringView raise Refused {
  if rest.length() == 0 {
    raise self.refuse(rest, "missing ), unterminated group")
  }
  if rest.at(0).to_int() != ')' {
    raise self.refuse(rest, "unexpected character in group")
  }
  rest.view(start_offset=1)
}

///|
/// A capture group: `(…)`, `(?P<name>…)` or `(?<name>…)`.
fn Parser::capture(
  self : Parser,
  rest : StringView,
  name : String?,
) -> (StringView, Node) raise Refused {
  self.groups += 1
  let slot = self.groups
  match name {
    None => ()
    Some(name) =>
      // ECMA-262 since 2025 allows the same name in different branches;
      // Python's `re` refuses a name used twice anywhere.
      match self.groupindex.get(name) {
        None => self.groupindex[name] = [slot]
        Some(slots) => {
          if self.dialect is Python {
            raise self.refuse(
              rest,
              "redefinition of group name '\{name}' as group \{slot}",
            )
          }
          self.groupindex[name] = slots + [slot]
        }
      }
  }
  self.open.push(slot)
  self.depth += 1
  let (view, body) = self.alternation(rest)
  self.depth -= 1
  ignore(self.open.pop())
  let view = self.close(view)
  (view, Group(slot~, node=body))
}

///|
/// A named group: read `name>` and open a capture group under it.
fn Parser::named(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  let (rest, name) = self.name(rest)
  self.capture(rest, Some(name))
}

///|
/// ECMA-262's `(?'name'…)`: read `'name'` and open a capture group under it.
fn Parser::named_sq(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  let mut i = 0
  while i < rest.length() && is_name_char(rest.at(i).to_int()) {
    i += 1
  }
  if i == 0 || i >= rest.length() || rest.at(i).to_int() != '\'' {
    raise self.refuse(rest, "missing ', unterminated name")
  }
  let name = rest.view(end_offset=i).to_owned()
  let rest2 = rest.view(start_offset=i + 1)
  self.capture(rest2, Some(name))
}

///|
/// Python's `(?P<name>…)` and `(?P=name)`.
fn Parser::python_group(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  // rest points at `(?P…`
  if rest.length() < 3 {
    raise self.refuse(rest, "unknown extension ?P")
  }
  let c = rest.at(2).to_int()
  if c == '<' {
    let (rest, name) = self.name(rest.view(start_offset=3))
    return self.capture(rest, Some(name))
  }
  if c == '=' {
    // `(?P=name)` closes with `)`, not `>`.
    let (rest, name) = self.name_close(rest.view(start_offset=3))
    let slot = match self.groupindex.get(name) {
      None => raise self.refuse(rest, "unknown group name '\{name}'")
      Some(slots) => slots[0]
    }
    return (rest, Backref(slot~, icase=self.flags.ignorecase))
  }
  if c == '>' {
    // `(?P>name)`: the `regex` superset's spelling of a named-group recursion.
    // The name is closed by `)`, not `>`, so a `)`-delimited reader is used.
    let (view, name) = self.name_close(rest.view(start_offset=3))
    match self.groupindex.get(name) {
      None => raise self.refuse(rest, "unknown group name '\{name}'")
      Some(_) => ()
    }
    return (view, Recurse(target=Named(name~)))
  }
  raise self.refuse(rest, "unknown extension ?P\{c.unsafe_to_char()}")
}

///|
/// Read `name>` and return the view past it and the name.
fn Parser::name(
  self : Parser,
  rest : StringView,
) -> (StringView, String) raise Refused {
  let mut i = 0
  while i < rest.length() && is_name_char(rest.at(i).to_int()) {
    i += 1
  }
  if i == 0 || i >= rest.length() || rest.at(i).to_int() != '>' {
    raise self.refuse(rest, "missing >, unterminated name")
  }
  if rest.at(0).to_int() >= '0'.to_int() && rest.at(0).to_int() <= '9'.to_int() {
    // A name is an identifier: it may not start with a digit.
    raise self.refuse(rest, "bad character in group name")
  }
  (rest.view(start_offset=i + 1), rest.view(end_offset=i).to_owned())
}

///|
/// Like `name`, but the name is closed by `)` — used by `(?P>name)` and
/// `(?&name)`, where the group parenthesis, not a `>`, follows the name.
fn Parser::name_close(
  self : Parser,
  rest : StringView,
) -> (StringView, String) raise Refused {
  let mut i = 0
  while i < rest.length() && is_name_char(rest.at(i).to_int()) {
    i += 1
  }
  if i == 0 || i >= rest.length() || rest.at(i).to_int() != ')' {
    raise self.refuse(rest, "missing ), unterminated name")
  }
  (rest.view(start_offset=i + 1), rest.view(end_offset=i).to_owned())
}

///|
/// Read a group reference up to `close` (`>` or `}`): a name, a number, or a
/// relative `-n`. Unlike `name`, a leading `-` is accepted.
fn Parser::gref(
  self : Parser,
  rest : StringView,
  close : Int32,
) -> (StringView, String) raise Refused {
  let mut i = 0
  while i < rest.length() {
    let c = rest.at(i).to_int()
    if c == close {
      break
    }
    if !(is_name_char(c) || c == '-') {
      raise self.refuse(rest, "bad character in group reference")
    }
    i += 1
  }
  if i == 0 || i >= rest.length() || rest.at(i).to_int() != close {
    raise self.refuse(rest, "unterminated group reference")
  }
  (rest.view(start_offset=i + 1), rest.view(end_offset=i).to_owned())
}

///|
fn is_name_char(c : Int32) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// `(?(1)yes|no)`, `(?(name)yes|no)`, `(?(?=…)yes|no)`.
fn Parser::conditional(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  // rest points at `?(`. The condition is read up to the `)` that closes it,
  // then the two branches, then the group's own `)`.
  let head = rest.view(start_offset=2)
  let (cond, view) = if head.length() > 0 && head.at(0).to_int() == '?' {
    let ((body, look), view) = self.look_cond(head)
    (Cond::ByLook(node=body, look~), view)
  } else if head.length() > 0 && head.at(0).to_int() == 'R' {
    // `(?(R)…)`, `(?(R1)…)`, `(?(R&name)…)`: a recursion condition.
    self.recurse_cond(rest, head)
  } else if head.length() > 6 && head.view(end_offset=6).to_owned() == "DEFINE" {
    // `(?(DEFINE)…)`: declare subroutines, match empty. The inner groups are
    // registered, but the group itself produces nothing.
    let view = self.close(head.view(start_offset=6))
    self.depth += 1
    let (view, body) = self.alternation(view)
    self.depth -= 1
    let view = self.close(view)
    return (view, Define(node=body))
  } else {
    let mut i = 0
    while i < head.length() && is_name_char(head.at(i).to_int()) {
      i += 1
    }
    if i == 0 || i >= head.length() || head.at(i).to_int() != ')' {
      raise self.refuse(rest, "bad character in group name")
    }
    let text = head.view(end_offset=i).to_owned()
    let view = head.view(start_offset=i + 1)
    if text.at(0).to_int() >= '0' && text.at(0).to_int() <= '9' {
      let slot = match parse_int(text[:]) {
        None => raise self.refuse(rest, "invalid group reference")
        Some(n) => n
      }
      // A numbered condition may name a group that opens later; a named one
      // must already exist, as in Python.
      if slot > self.groups {
        raise self.refuse(rest, "invalid group reference \{slot}")
      }
      (Cond::ByGroup(slot~), view)
    } else {
      match self.groupindex.get(text) {
        None => raise self.refuse(rest, "unknown group name '\{text}'")
        Some(slots) => (Cond::ByGroup(slot=slots[0]), view)
      }
    }
  }
  let (view, yes) = self.sequence(view)
  let (no, view) = if view.length() > 0 && view.at(0).to_int() == '|' {
    let (view, no) = self.sequence(view.view(start_offset=1))
    if view.length() > 0 && view.at(0).to_int() == '|' {
      raise self.refuse(view, "conditional backref with more than two branches")
    }
    (Some(no), view)
  } else {
    (None, view)
  }
  let view = self.close(view)
  (view, Cond(probe=cond, yes~, no~))
}

///|
/// `(?(R)…)`, `(?(R1)…)`, `(?(R&name)…)`: read a recursion condition.
fn Parser::recurse_cond(
  self : Parser,
  rest : StringView,
  head : StringView,
) -> (Cond, StringView) raise Refused {
  // head points at `R…`.
  let after = head.view(start_offset=1)
  if after.length() == 0 {
    raise self.refuse(rest, "bad condition (?(R)")
  }
  let c = after.at(0).to_int()
  if c == ')' {
    return (Cond::ByRecurse(target=AnyRecursion), after.view(start_offset=1))
  }
  if c == '&' {
    let (view, name) = self.name_close(after.view(start_offset=1))
    match self.groupindex.get(name) {
      None => raise self.refuse(rest, "unknown group name '\{name}'")
      Some(_) => ()
    }
    return (Cond::ByRecurse(target=NamedRecursion(name~)), view)
  }
  // `(?(R1))` … `(?(R99))`.
  let (slot, after2) = match self.digits(after, 0) {
    None => raise self.refuse(rest, "bad condition (?(R")
    Some(pair) => pair
  }
  if slot > self.groups {
    raise self.refuse(rest, "invalid group reference \{slot}")
  }
  let view = self.close(after.view(start_offset=after2))
  (Cond::ByRecurse(target=GroupRecursion(slot~)), view)
}

///|
/// Read the lookaround in a conditional's condition slot.
fn Parser::look_cond(
  self : Parser,
  rest : StringView,
) -> ((Node, Look), StringView) raise Refused {
  // rest points at `?=`, `?!`, `?<=` or `?<!`.
  let mut width = 1
  if rest.length() > 1 && rest.at(1).to_int() == '<' {
    width = 2
    if rest.length() > 2 &&
      (rest.at(2).to_int() == '=' || rest.at(2).to_int() == '!') {
      width = 3
    }
  }
  if rest.length() < width + 1 {
    raise self.refuse(rest, "unknown extension ?<")
  }
  let positive = rest.at(width - 1).to_int() == '='
  let behind = width >= 2 && rest.at(1).to_int() == '<'
  self.depth += 1
  let (view, body) = self.alternation(rest.view(start_offset=width))
  self.depth -= 1
  let view = self.close(view)
  let look = if behind { Behind(positive~) } else { Ahead(positive~) }
  ((body, look), view)
}

///|
/// `(?R)`, `(?1)`, `(?&name)`.
fn Parser::recursion(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  // rest points at `?R`, `?1` or `?&` — the `(` was consumed by the caller.
  if rest.length() < 2 {
    raise self.refuse(rest, "unknown extension ?")
  }
  let c = rest.at(1).to_int()
  if c == 'R' {
    let view = self.close(rest.view(start_offset=2))
    return (view, Recurse(target=Whole))
  }
  if c == '&' {
    let (view, name) = self.name_close(rest.view(start_offset=2))
    match self.groupindex.get(name) {
      None => raise self.refuse(rest, "unknown group name '\{name}'")
      Some(_) => ()
    }
    return (view, Recurse(target=Named(name~)))
  }
  // A number: `(?1)` … `(?99)`.
  let (slot, after) = match self.digits(rest, 1) {
    None => raise self.refuse(rest, "invalid group reference")
    Some(pair) => pair
  }
  if slot > self.groups {
    raise self.refuse(rest, "invalid group reference \{slot}")
  }
  let view = self.close(rest.view(start_offset=after))
  (view, Recurse(target=Group(slot~)))
}

///|
/// `(*VERB)`, `(*VERB:arg)`: a control verb from the `regex` superset.
///
/// `rest` points at `(?*…`, so `at(2)` is the first letter of the verb. The
/// whole `(…)` is read to its close, the verb name and optional argument split
/// at `:`, and the name mapped to a `VerbKind`. Unknown verbs are refused so a
/// pattern counting on behaviour we do not carry is flagged rather than silent.
fn Parser::verb(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  // rest points at `*VERB)…` (the `(` was consumed by the caller's atom).
  // Read to the closing parenthesis of the group.
  match self.read_until_close(rest.view(start_offset=1), ')') {
    None => raise self.refuse(rest, "unterminated verb")
    Some((inner, view)) => {
      // Split the verb at its first `:`, into the name and an optional argument.
      let mut colon = -1
      let mut k = 0
      while k < inner.length() {
        if inner.at(k).to_int() == ':' {
          colon = k
          break
        }
        k = k + 1
      }
      let (name, arg) = if colon < 0 {
        (inner, None)
      } else {
        (inner.view(end_offset=colon), Some(inner.view(start_offset=colon + 1)))
      }
      let kind = match name.to_owned() {
        "ACCEPT" => VerbKind::Accept
        "FAIL" | "F" => VerbKind::Fail
        "COMMIT" => VerbKind::Commit
        "PRUNE" => VerbKind::Prune(name=arg.map(to_str))
        "SKIP" => VerbKind::Skip(name=arg.map(to_str))
        "THEN" => VerbKind::Then(name=arg.map(to_str))
        "MARK" =>
          match arg {
            None => raise self.refuse(rest, "(*MARK) needs a name")
            Some(a) => VerbKind::Mark(name=a.to_owned())
          }
        ":" =>
          match arg {
            None => raise self.refuse(rest, "(*:MARK) needs a name")
            Some(a) => VerbKind::Mark(name=a.to_owned())
          }
        "LIMIT_MATCH" =>
          match arg {
            None => raise self.refuse(rest, "(*LIMIT_MATCH) needs a number")
            Some(a) => VerbKind::LimitMatch(n=self.verb_number(rest, a))
          }
        "LIMIT_RECURSION" =>
          match arg {
            None => raise self.refuse(rest, "(*LIMIT_RECURSION) needs a number")
            Some(a) => VerbKind::LimitRecursion(n=self.verb_number(rest, a))
          }
        "VERSION" => VerbKind::Version
        "FENCE" => VerbKind::Fence
        other => raise self.refuse(rest, "unknown verb (*\{other})")
      }
      (view, Verb(kind~))
    }
  }
}

///|
/// Turn a verb's `:name` argument into a `String`.
fn to_str(view : StringView) -> String {
  view.to_owned()
}

///|
/// Read a non-negative number out of a verb argument, refusing otherwise.
fn Parser::verb_number(
  self : Parser,
  rest : StringView,
  arg : StringView,
) -> Int32 raise Refused {
  if arg.length() == 0 {
    raise self.refuse(rest, "verb needs a number")
  }
  match parse_int(arg) {
    None =>
      raise self.refuse(rest, "verb needs a number, got '\{arg.to_owned()}'")
    Some(n) =>
      if n < 0 {
        raise self.refuse(rest, "verb number must not be negative")
      } else {
        n
      }
  }
}

///|
/// `(?flags:…)` and `(?flags-flags:…)`: a group with its own flags.
fn Parser::scoped_flags(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  // rest points at `?` — the flag letters start right after it.
  let mut i = 1
  let on : Array[String] = []
  let off : Array[String] = []
  let mut target = on
  let mut colon = false
  while i < rest.length() {
    let c = rest.at(i).to_int()
    if c == ':' {
      colon = true
      i += 1
      break
    }
    if c == '-' {
      target = off
      i += 1
      continue
    }
    if !(c >= 'a' && c <= 'z') {
      break
    }
    target.push(c.unsafe_to_char().to_string())
    i += 1
  }
  if !colon {
    raise self.refuse(rest, "missing :")
  }
  let body = rest.view(start_offset=i)
  let before = self.flags
  self.flags = self.apply_inline(body, before, on, off)
  self.depth += 1
  let (view, node) = self.alternation(body)
  self.depth -= 1
  self.flags = before
  let view = self.close(view)
  (view, node)
}

///|
/// Global inline flags, read only at the very start of a pattern: `(?i)`,
/// `(?ims)`.
fn Parser::global_flags(
  self : Parser,
  rest : StringView,
) -> StringView raise Refused {
  if rest.length() < 3 ||
    rest.at(0).to_int() != '(' ||
    rest.at(1).to_int() != '?' {
    return rest
  }
  let mut i = 2
  let letters : Array[String] = []
  while i < rest.length() {
    let c = rest.at(i).to_int()
    if c == 'V' && i + 1 < rest.length() {
      // `(?V0)` / `(?V1)`: which behaviour set the Python grammar is read
      // under, spelled the way the superset spells it.
      let digit = rest.at(i + 1).to_int()
      if digit == '0' || digit == '1' {
        letters.push("V" + digit.unsafe_to_char().to_string())
        i += 2
        continue
      }
    }
    if c == ')' {
      // The whole group was flag letters.
      if letters.length() == 0 {
        return rest
      }
      self.flags = self.apply_inline(rest, self.flags, letters, [])
      self.version = self.flags.version
      return rest.view(start_offset=i + 1)
    }
    if c == ':' || c == '-' || !(c >= 'a' && c <= 'z') {
      // Not a global flag group after all — a scoped one, or something else.
      return rest
    }
    letters.push(c.unsafe_to_char().to_string())
    i += 1
  }
  rest
}

///|
/// Turn inline flag letters into flags, refusing the ones this grammar has no
/// use for. `cursor` is only for saying where the refusal happened.
fn Parser::apply_inline(
  self : Parser,
  cursor : StringView,
  base : Flags,
  on : Array[String],
  off : Array[String],
) -> Flags raise Refused {
  let mut flags = base
  if self.dialect is Ecma262 {
    for letter in on {
      if letter != "i" && letter != "m" && letter != "s" {
        raise self.refuse(cursor, "invalid modifiers")
      }
    }
    for letter in off {
      if letter != "i" && letter != "m" && letter != "s" {
        raise self.refuse(cursor, "invalid modifiers")
      }
    }
    // ECMA-262 has no empty modifier group and refuses a flag added and
    // removed in the same one.
    if on.length() == 0 && off.length() == 0 {
      raise self.refuse(cursor, "invalid modifiers")
    }
    for letter in on {
      for other in off {
        if letter == other {
          raise self.refuse(cursor, "invalid modifiers")
        }
      }
    }
    let mut i = 0
    while i < on.length() {
      let mut j = i + 1
      while j < on.length() {
        if on[i] == on[j] {
          raise self.refuse(cursor, "invalid modifiers")
        }
        j += 1
      }
      i += 1
    }
    let mut i = 0
    while i < off.length() {
      let mut j = i + 1
      while j < off.length() {
        if off[i] == off[j] {
          raise self.refuse(cursor, "invalid modifiers")
        }
        j += 1
      }
      i += 1
    }
  }
  for letter in on {
    flags = self.set_inline(cursor, flags, letter, true)
  }
  for letter in off {
    flags = self.set_inline(cursor, flags, letter, false)
  }
  flags
}

///|
fn Parser::set_inline(
  self : Parser,
  cursor : StringView,
  flags : Flags,
  letter : String,
  value : Bool,
) -> Flags raise Refused {
  let refuse = fn(msg : String) -> Refused { self.refuse(cursor, msg) }
  match letter {
    "V0" =>
      if self.dialect is Python {
        { ..flags, version: V0, }
      } else {
        raise refuse("bad inline flags: the behaviour set is Python only")
      }
    "V1" =>
      if self.dialect is Python {
        { ..flags, version: V1, }
      } else {
        raise refuse("bad inline flags: the behaviour set is Python only")
      }
    "i" => { ..flags, ignorecase: value, }
    "m" => { ..flags, multiline: value, }
    "s" => { ..flags, dotall: value, }
    "a" => { ..flags, ascii: value, }
    "u" =>
      if self.dialect is Ecma262 {
        { ..flags, unicode: value, }
      } else if value {
        // Under Python the flag is always on, so turning it on is a no-op and
        // turning it off is a refusal — `re` says the same.
        { ..flags, unicode: true, }
      } else {
        raise refuse("bad inline flags: cannot use 'u' flag with a str pattern")
      }
    "x" =>
      if self.dialect is Ecma262 {
        raise refuse("bad inline flags: ECMA-262 has no verbose flag")
      } else {
        { ..flags, verbose: value, }
      }
    "f" => { ..flags, fullcase: value, }
    "b" => { ..flags, bestmatch: value, }
    "e" => { ..flags, enhancematch: value, }
    "p" => { ..flags, posix: value, }
    "r" => { ..flags, reverse: value, }
    "w" => { ..flags, word: value, }
    "v" =>
      if self.dialect is Ecma262 {
        { ..flags, unicode_sets: value, }
      } else {
        raise refuse("bad inline flags: 'v' is ECMA-262 only")
      }
    "L" =>
      raise refuse("bad inline flags: cannot use 'L' flag with a str pattern")
    _ => raise refuse("bad inline flags: unknown flag '\{letter}'")
  }
}

// ---------------------------------------------------------------------------
// Escapes
// ---------------------------------------------------------------------------

///|
/// An escape outside a class: an assertion, a class shorthand, a literal, a
/// backreference, or one of the superset's constructs.
fn Parser::escape(
  self : Parser,
  rest : StringView,
) -> (StringView, Node, Bool) raise Refused {
  // rest points at the backslash.
  if rest.length() == 1 {
    raise self.refuse(rest, "bad escape (end of pattern)")
  }
  let c = rest.at(1).to_int()
  let after = rest.view(start_offset=2)
  // Assertions first: they are not quantifiable, and some share their letter
  // with a class shorthand that only exists inside a class.
  match c {
    'A' => return (after, Anchor(anchor=TextStart), true)
    'Z' => return (after, Anchor(anchor=TextEnd), true)
    'b' =>
      return (
        after,
        Anchor(anchor=WordBoundary(negate=false, ascii=self.flags.ascii)),
        true,
      )
    'B' =>
      return (
        after,
        Anchor(anchor=WordBoundary(negate=true, ascii=self.flags.ascii)),
        true,
      )
    'd' | 'D' | 's' | 'S' | 'w' | 'W' => {
      let set = self.shorthand(c)
      let set = if self.flags.ignorecase { set.fold() } else { set }
      return (after, Class(set~), false)
    }
    _ => ()
  }
  if self.dialect is Ecma262 && (c == 'p' || c == 'P') {
    // `\p{…}` is ECMA-262's own property escape, but only under `u` or `v`;
    // without them Annex B makes `\p` an identity escape — a literal `p`.
    if self.flags.unicode || self.flags.unicode_sets {
      let (after, set) = self.property(after, c == 'P')
      return (after, Class(set~), false)
    }
    let ch = c.unsafe_to_char()
    return (after, Char(code=ch.to_int()), false)
  }
  if self.dialect is Python {
    // The superset's assertions and constructs, which only the Python grammar
    // carries.
    match c {
      'z' => return (after, Anchor(anchor=TextEnd), true)
      'G' => return (after, Anchor(anchor=SearchAnchor), true)
      'K' => return (after, Keep, true)
      'm' => return (after, Anchor(anchor=WordStart), true)
      'M' => return (after, Anchor(anchor=WordEnd), true)
      'h' =>
        return (after, Class(set=horizontal_space(self.flags.ascii)), false)
      'H' =>
        return (
          after,
          Class(set=horizontal_space(self.flags.ascii).complement()),
          false,
        )
      // Under V0 `\v` is the vertical tab, as it is in every other regex
      // dialect; the vertical-whitespace class is the V1 reading.
      'v' =>
        if self.version is V1 {
          return (after, Class(set=vertical_space(self.flags.ascii)), false)
        }
      'V' =>
        if self.version is V1 {
          return (
            after,
            Class(set=vertical_space(self.flags.ascii).complement()),
            false,
          )
        }
      'R' => return (after, Class(set=vertical_space(self.flags.ascii)), false)
      'X' => return (after, Grapheme, false)
      'p' | 'P' => {
        let (after, set) = self.property(after, c == 'P')
        let set = if self.flags.ignorecase { set.fold() } else { set }
        return (after, Class(set~), false)
      }
      'L' => {
        let (after, node) = self.named_list(after)
        return (after, node, false)
      }
      'g' => {
        // `\g<name>` / `\g<1>`, the Perl `\g{name}` / `\g{n}`, and the
        // relative `\g{-1}` (Oniguruma / Perl): `\g{-n}` names the group
        // `n - 1` places before the current group count.
        if after.length() == 0 {
          raise self.refuse(rest, "missing delimiter in \\g")
        }
        let open = after.at(0).to_int()
        let close = if open == '<' {
          '>'.to_int()
        } else if open == '{' {
          '}'.to_int()
        } else {
          raise self.refuse(rest, "missing < or { in \\g")
        }
        let (after, name) = self.gref(after.view(start_offset=1), close)
        let slot = if name.length() > 0 && name.at(0).to_int() == '-' {
          // A relative reference: `\g{-1}` is the last group opened so far.
          match parse_int(name[:].view(start_offset=1)) {
            None =>
              raise self.refuse(after, "invalid group reference '\{name}'")
            Some(mag) => {
              let slot = self.groups - mag + 1
              if slot < 1 || slot > self.groups {
                raise self.refuse(after, "invalid group reference '\{name}'")
              }
              slot
            }
          }
        } else {
          match parse_int(name[:]) {
            Some(n) =>
              if n > self.groups {
                raise self.refuse(after, "invalid group reference \{n}")
              } else {
                n
              }
            None =>
              match self.groupindex.get(name) {
                None => raise self.refuse(after, "unknown group name '\{name}'")
                Some(slots) => slots[0]
              }
          }
        }
        return (after, Backref(slot~, icase=self.flags.ignorecase), false)
      }
      'N' =>
        if after.length() > 0 && after.at(0).to_int() == '{' {
          // `\N{name}`: a character named in the Unicode Character Database.
          let (name, view) = match
            self.read_until_close(after.view(start_offset=1), '}') {
            None => raise self.refuse(rest, "missing }, unterminated name")
            Some(pair) => pair
          }
          match @prop.char_of_name(name) {
            None =>
              raise self.refuse(
                rest,
                "unknown Unicode character name '\{name.to_owned()}'",
              )
            Some(code) => {
              let node = if self.flags.ignorecase {
                Class(set=@prop.CharSet::single(code).fold())
              } else {
                Char(code~)
              }
              return (view, node, false)
            }
          }
        } else {
          // `\N`: any character except a newline — the superset's spelling.
          return (after, Class(set=not_newline()), false)
        }
      'Q' => {
        // `\Q…\E`: quote everything literally until the `\E`. The superset's
        // way to paste a string of metacharacters without escaping each one.
        let (view, items) = self.quote(after)
        return (view, Seq(items~), false)
      }
      _ => ()
    }
  }
  if self.dialect is Ecma262 && c == 'k' {
    // `\k<name>` is ECMA-262's backreference spelling.
    if after.length() == 0 || after.at(0).to_int() != '<' {
      raise self.refuse(rest, "invalid backreference")
    }
    let (after, name) = self.name(after.view(start_offset=1))
    match self.groupindex.get(name) {
      None => raise self.refuse(after, "invalid named capture group reference")
      Some(slots) =>
        return (
          after,
          Backref(slot=slots[0], icase=self.flags.ignorecase),
          false,
        )
    }
  }
  // A `\` followed by decimal digits is a backreference to a group opened so
  // far, and an octal escape otherwise. So `(a)\1` is a backref while
  // `\1(a)` is octal, which is how Python reads the two.
  if c >= '0' && c <= '9' {
    let mut digits = c.unsafe_to_char().to_string()
    let mut view = after
    while view.length() > 0 &&
          view.at(0).to_int() >= '0' &&
          view.at(0).to_int() <= '9' {
      digits = digits + view.at(0).to_int().unsafe_to_char().to_string()
      view = view.view(start_offset=1)
    }
    match parse_int(digits) {
      Some(n) =>
        if n >= 1 && n <= self.groups {
          return (view, Backref(slot=n, icase=self.flags.ignorecase), false)
        } else {
          ()
        }
      None => ()
    }
  }
  // A character escape: hex, octal, unicode, control, or the literal itself.
  let (after, code) = self.char_escape(rest, c, after)
  let node = if self.flags.ignorecase {
    Class(set=@prop.CharSet::single(code).fold())
  } else {
    Char(code~)
  }
  (after, node, false)
}

///|
/// `\d`, `\D`, `\s`, `\S`, `\w`, `\W` — as the flags in force say they mean.
fn Parser::shorthand(self : Parser, c : Int32) -> @prop.CharSet {
  // lexmatch refuses these outright; its grammar points at POSIX classes, so
  // reaching here means the caller did not check.
  if self.dialect is Lexmatch {
    return @prop.CharSet::empty()
  }
  // ECMA-262's `\w`, `\d` and `\s` are ASCII whatever the `u` flag says;
  // Unicode comes in through `\p{…}` alone.
  let ascii = self.flags.ascii || self.dialect is Ecma262
  match c {
    'd' => if ascii { @prop.ascii_digit } else { @prop.digit() }
    'D' => (if ascii { @prop.ascii_digit } else { @prop.digit() }).complement()
    's' => if ascii { @prop.ascii_space } else { @prop.space() }
    'S' => (if ascii { @prop.ascii_space } else { @prop.space() }).complement()
    'w' => if ascii { @prop.ascii_word } else { @prop.word() }
    'W' => (if ascii { @prop.ascii_word } else { @prop.word() }).complement()
    _ => @prop.CharSet::empty()
  }
}

///|
/// `\h` / `\H`: horizontal whitespace — tab, space, and the Unicode spaces.
fn horizontal_space(ascii : Bool) -> @prop.CharSet {
  if ascii {
    @prop.CharSet::of([(0x09, 0x09), (0x20, 0x20)])
  } else {
    @prop.CharSet::of([
      (0x09, 0x09),
      (0x20, 0x20),
      (0xA0, 0xA0),
      (0x1680, 0x1680),
      (0x180E, 0x180E),
      (0x2000, 0x200A),
      (0x202F, 0x202F),
      (0x205F, 0x205F),
      (0x3000, 0x3000),
    ])
  }
}

///|
/// `\v` / `\V` / `\R`: the line separators — LF, VT, FF, CR, NEL, LS, PS.
fn vertical_space(ascii : Bool) -> @prop.CharSet {
  if ascii {
    @prop.CharSet::of([(0x0A, 0x0A), (0x0B, 0x0B), (0x0C, 0x0C), (0x0D, 0x0D)])
  } else {
    @prop.CharSet::of([
      (0x0A, 0x0A),
      (0x0B, 0x0B),
      (0x0C, 0x0C),
      (0x0D, 0x0D),
      (0x85, 0x85),
      (0x2028, 0x2028),
      (0x2029, 0x2029),
    ])
  }
}

///|
/// `\N`: any character except a newline (`\n`).
fn not_newline() -> @prop.CharSet {
  @prop.CharSet::single('\n'.to_int()).complement()
}

///|
/// `\p{…}` and `\P{…}`: a property, negated for `\P` and for a `^` inside the
/// braces.
fn Parser::property(
  self : Parser,
  rest : StringView,
  negate : Bool,
) -> (StringView, @prop.CharSet) raise Refused {
  if rest.length() == 0 || rest.at(0).to_int() != '{' {
    raise self.refuse(rest, "missing { after \\p")
  }
  let (name, after) = match
    self.read_until_close(rest.view(start_offset=1), '}') {
    None => raise self.refuse(rest, "missing }, unterminated property name")
    Some(pair) => pair
  }
  let mut view = name
  let mut negate = negate
  if view.length() > 0 && view.at(0).to_int() == '^' {
    negate = !negate
    view = view.view(start_offset=1)
  }
  match @prop.property(view) {
    None => raise self.refuse(rest, "unknown property '\{view.to_owned()}'")
    Some(set) => {
      let set = if negate { set.complement() } else { set }
      let set = if self.flags.ignorecase { set.fold() } else { set }
      (after, set)
    }
  }
}

///|
/// `\L<name>`: a named list, expanded into the alternation of its items.
fn Parser::named_list(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  let (rest, name) = self.name(rest)
  match self.lists.get(name) {
    None => raise self.refuse(rest, "unknown list name '\{name}'")
    Some(items) => {
      self.named_lists[name] = items
      let branches : Array[Node] = []
      for item in items {
        // Each item is matched literally, character by character.
        let chars : Array[Node] = []
        for ch in item {
          chars.push(Char(code=ch.to_int()))
        }
        branches.push(
          if chars.length() == 1 {
            chars[0]
          } else {
            Seq(items=chars)
          },
        )
      }
      let node = if branches.length() == 1 {
        branches[0]
      } else {
        Alt(items=branches)
      }
      (rest, node)
    }
  }
}

///|
/// The character an escape denotes: hex, octal, unicode, control, or the
/// escaped character itself.
///
/// The digit case is the awkward one — `\1` is a backreference, `\012` an
/// octal escape, and which of the two a given text is depends on how many
/// groups the pattern has opened so far — so it is spelled out here the way
/// Python's parser spells it out.
fn Parser::char_escape(
  self : Parser,
  rest : StringView,
  c : Int32,
  after : StringView,
) -> (StringView, Int32) raise Refused {
  match c {
    'n' => (after, '\n'.to_int())
    'r' => (after, '\r'.to_int())
    't' => (after, '\t'.to_int())
    'f' => (after, '\u{0c}'.to_int())
    'v' => (after, '\u{0b}'.to_int())
    'a' =>
      if self.dialect is Python {
        (after, 0x07)
      } else if self.dialect is Ecma262 && self.flags.unicode {
        // Under `u` ECMA-262 defines no `\a`, and an identity escape of a
        // letter is not one either.
        raise self.refuse(rest, "bad escape \\a")
      } else {
        (after, 'a'.to_int())
      }
    'e' =>
      if self.dialect is Python {
        (after, 0x1B)
      } else if self.dialect is Ecma262 && self.flags.unicode {
        raise self.refuse(rest, "bad escape \\e")
      } else {
        (after, 'e'.to_int())
      }
    'x' =>
      match self.hex(after, 2) {
        None => raise self.refuse(rest, "incomplete escape \\x")
        Some((code, view)) => (view, code)
      }
    'u' => self.unicode_escape(rest, after)
    'U' =>
      if self.dialect is Python {
        match self.hex(after, 8) {
          None => raise self.refuse(rest, "incomplete escape \\U")
          Some((code, view)) => (view, code)
        }
      } else {
        (after, 'U'.to_int())
      }
    'c' =>
      if self.dialect is Ecma262 {
        // A control escape names the letter whose code is its own minus 64.
        if after.length() == 0 {
          raise self.refuse(rest, "invalid control escape")
        }
        let letter = after.at(0).to_int()
        let code = if letter >= 'a' && letter <= 'z' {
          letter - 'a'.to_int() + 1
        } else if letter >= 'A' && letter <= 'Z' {
          letter - 'A'.to_int() + 1
        } else {
          raise self.refuse(rest, "invalid control escape")
        }
        (after.view(start_offset=1), code)
      } else {
        (after, 'c'.to_int())
      }
    '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' => {
      // Octal, or a backreference: decided the way Python decides it.
      if c == '0' {
        // `\0` and `\012` are octal, always.
        let mut digits = "0"
        let mut view = after
        let mut i = 0
        while i < 2 && view.length() > 0 && is_octal_digit(view.at(0).to_int()) {
          digits = digits + view.at(0).to_int().unsafe_to_char().to_string()
          view = view.view(start_offset=1)
          i += 1
        }
        // The digits are octal, so parse them in base eight.
        return (view, octal(digits))
      }
      // Not `\0`: a backreference unless three octal digits follow.
      let mut digits = c.unsafe_to_char().to_string()
      let mut view = after
      if view.length() > 0 && is_octal_digit(view.at(0).to_int()) {
        digits = digits + view.at(0).to_int().unsafe_to_char().to_string()
        view = view.view(start_offset=1)
        if is_octal_digit(c) &&
          is_octal_digit(digits.at(1).to_int()) &&
          view.length() > 0 &&
          is_octal_digit(view.at(0).to_int()) {
          digits = digits + view.at(0).to_int().unsafe_to_char().to_string()
          view = view.view(start_offset=1)
          let code = octal(digits)
          if code > 0o377 {
            raise self.refuse(
              rest,
              "octal escape value \{digits} outside of range 0-0o377",
            )
          }
          return (view, code)
        }
      }
      // A backreference, then — or a refusal naming the group that is not
      // there.
      let slot = match parse_int(digits[:]) {
        None => raise self.refuse(rest, "invalid group reference")
        Some(n) => n
      }
      if slot > self.groups || self.open.contains(slot) {
        raise self.refuse(rest, "invalid group reference \{slot}")
      }
      (view, slot)
    }
    _ => {
      // Anything else: a punctuation escape is the character itself, and an
      // escape of a letter this grammar does not define is a refusal. Under
      // ECMA-262 without `u`, Annex B lets any escape stand for its letter.
      let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      if letter && !(self.dialect is Ecma262 && !self.flags.unicode) {
        raise self.refuse(rest, "bad escape \\\{c.unsafe_to_char()}")
      }
      (after, c)
    }
  }
}

///|
/// Octal digits as a number.
fn octal(digits : StringView) -> Int32 {
  let mut value = 0
  for c in digits {
    value = value * 8 + (c.to_int() - '0'.to_int())
  }
  value
}

///|
/// `\uXXXX`, and `\u{…}` where the grammar has it.
fn Parser::unicode_escape(
  self : Parser,
  rest : StringView,
  after : StringView,
) -> (StringView, Int32) raise Refused {
  let braced = self.dialect is Ecma262 &&
    self.flags.unicode &&
    after.length() > 0 &&
    after.at(0).to_int() == '{'
  if braced {
    return match self.read_until_close(after.view(start_offset=1), '}') {
      None => raise self.refuse(rest, "invalid Unicode escape")
      Some((hex, view)) =>
        match hex_to_int(hex) {
          None => raise self.refuse(rest, "invalid Unicode escape")
          // A code point has to be a scalar value, so anything past the last
          // plane is refused rather than wrapped.
          Some(code) =>
            if code > 0x10FFFF {
              raise self.refuse(rest, "invalid Unicode escape")
            } else {
              (view, code)
            }
        }
    }
  }
  let fixed = if self.dialect is Lexmatch { 4 } else { 4 }
  match self.hex(after, fixed) {
    None =>
      if self.dialect is Ecma262 && !self.flags.unicode {
        // Annex B: `\u` not followed by four hex digits is the letter itself.
        (after, 'u'.to_int())
      } else {
        raise self.refuse(rest, "incomplete escape \\u")
      }
    Some((code, view)) => (view, code)
  }
}

///|
fn is_octal_digit(c : Int32) -> Bool {
  c >= '0' && c <= '7'
}

///|
/// Read exactly `n` hex digits.
fn Parser::hex(
  _self : Parser,
  rest : StringView,
  n : Int32,
) -> (Int32, StringView)? {
  if rest.length() < n {
    return None
  }
  let mut code = 0
  let mut i = 0
  while i < n {
    let c = rest.at(i).to_int()
    let digit = if c >= '0' && c <= '9' {
      c - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c - 'A'.to_int() + 10
    } else {
      return None
    }
    code = code * 16 + digit
    i += 1
  }
  Some((code, rest.view(start_offset=n)))
}

///|
/// Hex digits as a code point, for the `\u{…}` form.
fn hex_to_int(hex : StringView) -> Int32? {
  if hex.length() == 0 {
    return None
  }
  let mut code = 0
  for c in hex {
    let digit = if c.to_int() >= '0' && c.to_int() <= '9' {
      c.to_int() - '0'.to_int()
    } else if c.to_int() >= 'a' && c.to_int() <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c.to_int() >= 'A' && c.to_int() <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    code = code * 16 + digit
  }
  Some(code)
}

// ---------------------------------------------------------------------------
// Character classes
// ---------------------------------------------------------------------------

///|
/// `[…]`, with negation, ranges, POSIX classes, properties, and — where the
/// grammar allows it — set algebra.
fn Parser::klass(
  self : Parser,
  rest : StringView,
) -> (StringView, Node) raise Refused {
  // rest points at `[`.
  let mut view = rest.view(start_offset=1)
  let negate = view.length() > 0 && view.at(0).to_int() == '^'
  if negate {
    view = view.view(start_offset=1)
  }
  // A `]` first is a literal in Python; ECMA-262 reads `[]` as the empty
  // class, and lexmatch refuses it.
  let first_is_literal = self.dialect is Python
  let operands : Array[@prop.CharSet] = []
  let ops : Array[String] = []
  let mut cs = @prop.CharSet::empty()
  let mut first = true
  let going = true
  while going {
    if view.length() == 0 {
      raise self.refuse(view, "unterminated character set")
    }
    let c = view.at(0).to_int()
    if c == ']' && !(first && first_is_literal) {
      view = view.view(start_offset=1)
      break
    }
    if self.dialect is Ecma262 && self.flags.unicode_sets {
      // In `v` mode the punctuation a class expression uses has to be escaped
      // to stand for itself, and a set operator needs something on its left.
      let is_op = c == '&' || c == '|' || c == '-' || c == '~'
      if is_op {
        if first {
          raise self.refuse(view, "invalid character in character class")
        }
      } else if view.length() > 1 &&
        view.at(1).to_int() == c &&
        is_double_reserved(c) {
        raise self.refuse(view, "invalid character in character class")
      } else if is_reserved_in_class(c) {
        raise self.refuse(view, "invalid character in character class")
      }
    }
    first = false
    // A set operator between operands, where the grammar has one.
    if self.set_ops() {
      let op = if c == '-' && view.length() > 1 && view.at(1).to_int() == '-' {
        Some("--")
      } else if c == '&' && view.length() > 1 && view.at(1).to_int() == '&' {
        Some("&&")
      } else if c == '~' &&
        self.version is V1 &&
        view.length() > 1 &&
        view.at(1).to_int() == '~' {
        Some("~~")
      } else if c == '|' &&
        self.version is V1 &&
        view.length() > 1 &&
        view.at(1).to_int() == '|' {
        Some("||")
      } else {
        None
      }
      match op {
        Some(op) => {
          operands.push(cs)
          ops.push(op)
          cs = @prop.CharSet::empty()
          view = view.view(start_offset=2)
          continue
        }
        None => ()
      }
    }
    let (next, part) = self.class_item(view)
    view = next
    match part {
      Many(set~) => {
        if self.dialect is Ecma262 &&
          (self.flags.unicode || self.flags.unicode_sets) &&
          view.length() > 0 &&
          view.at(0).to_int() == '-' {
          // With `u` a class escape is not a range endpoint, so `[\d-a]` is
          // refused; a dash that closes the class is a dash, `[\d-]`. In `v`
          // mode a lone dash has to be escaped and only `--` may follow.
          let after = if view.length() > 1 { view.at(1).to_int() } else { 0 }
          let dash = if self.flags.unicode_sets { '-' } else { ']' }
          if after != dash.to_int() {
            raise self.refuse(view, "invalid character class")
          }
        }
        cs = cs.union(set)
      }
      One(code~) => {
        // A `-` between two single characters is a range; at the end of the
        // class it is a literal dash.
        let lo = code
        if view.length() > 1 &&
          view.at(0).to_int() == '-' &&
          view.at(1).to_int() != ']' {
          let (next, hi) = self.class_item(view.view(start_offset=1))
          view = next
          match hi {
            One(code~) => {
              if lo > code {
                raise self.refuse(
                  view,
                  "bad character range \{lo.unsafe_to_char()}-\{code.unsafe_to_char()}",
                )
              }
              cs = cs.union(@prop.CharSet::of([(lo, code)]))
            }
            Many(set~) =>
              // Without `u`, Annex B reads `[a-\d]` as `a`, `-` and the class.
              if self.dialect is Ecma262 &&
                !(self.flags.unicode || self.flags.unicode_sets) {
                cs = cs
                  .union(@prop.CharSet::single(lo))
                  .union(@prop.CharSet::single('-'.to_int()))
                  .union(set)
              } else {
                raise self.refuse(view, "bad character range")
              }
          }
        } else {
          cs = cs.union(@prop.CharSet::single(lo))
        }
      }
    }
  }
  // The operands fold left to right, as the set algebra specifies.
  operands.push(cs)
  let mut acc = operands[0]
  let mut i = 1
  while i < operands.length() {
    let op = ops[i - 1]
    let next = operands[i]
    acc = if op == "--" {
      acc.difference(next)
    } else if op == "&&" {
      acc.intersection(next)
    } else if op == "~~" {
      acc.symmetric_difference(next)
    } else {
      acc.union(next)
    }
    i += 1
  }
  let set = if negate { acc.complement() } else { acc }
  let set = if self.flags.ignorecase { set.fold() } else { set }
  (view, Class(set~))
}

///|
/// Whether set operators mean anything here.
fn Parser::set_ops(self : Parser) -> Bool {
  match self.dialect {
    Python => self.version is V1
    Ecma262 => self.flags.unicode_sets
    Lexmatch => false
  }
}

///|
/// One item of a character class.
fn Parser::class_item(
  self : Parser,
  rest : StringView,
) -> (StringView, ClassPart) raise Refused {
  let c = rest.at(0).to_int()
  if c == '[' && rest.length() > 1 && rest.at(1).to_int() == ':' {
    // A POSIX class, or a literal `[` if the name is not one.
    match self.posix(rest) {
      Some((set, view)) => return (view, Many(set~))
      None => ()
    }
  }
  if c == '\\' {
    return self.class_escape(rest)
  }
  let (ch, view) = next_char(rest)
  (view, One(code=ch.to_int()))
}

///|
/// `[[:alpha:]]` and the rest of the POSIX set, which is ASCII by definition.
fn Parser::posix(
  self : Parser,
  rest : StringView,
) -> (@prop.CharSet, StringView)? {
  if self.dialect is Ecma262 {
    // ECMA-262 has no POSIX classes: a `[` inside a class is a character.
    return None
  }
  // rest points at `[:`. The name is closed by `:]`.
  let mut i = 2
  while i + 1 < rest.length() {
    if rest.at(i).to_int() == ':' && rest.at(i + 1).to_int() == ']' {
      break
    }
    i += 1
  }
  if i + 1 >= rest.length() {
    return None
  }
  let name = rest.view(start_offset=2, end_offset=i).to_owned()
  match posix_set(name[:]) {
    None => None
    Some(set) => Some((set, rest.view(start_offset=i + 2)))
  }
}

///|
/// The POSIX character classes, ASCII-based in every grammar that has them.
fn posix_set(name : StringView) -> @prop.CharSet? {
  let digits = @prop.CharSet::of([('0'.to_int(), '9'.to_int())])
  let lower = @prop.CharSet::of([('a'.to_int(), 'z'.to_int())])
  let upper = @prop.CharSet::of([('A'.to_int(), 'Z'.to_int())])
  let alpha = lower.union(upper)
  let alnum = alpha.union(digits)
  let space = @prop.ascii_space
  let word = @prop.ascii_word
  match name.to_owned() {
    "alnum" => Some(alnum)
    "alpha" => Some(alpha)
    "ascii" => Some(@prop.CharSet::of([(0, 0x7F)]))
    "blank" =>
      Some(
        @prop.CharSet::of([
          ('\t'.to_int(), '\t'.to_int()),
          (' '.to_int(), ' '.to_int()),
        ]),
      )
    "cntrl" => Some(@prop.CharSet::of([(0, 0x1F), (0x7F, 0x7F)]))
    "digit" => Some(digits)
    "graph" => Some(@prop.CharSet::of([(0x21, 0x7E)]))
    "lower" => Some(lower)
    "print" => Some(@prop.CharSet::of([(0x20, 0x7E)]))
    "punct" =>
      Some(
        @prop.CharSet::of([
          (0x21, 0x2F),
          (0x3A, 0x40),
          (0x5B, 0x60),
          (0x7B, 0x7E),
        ]),
      )
    "space" => Some(space)
    "upper" => Some(upper)
    "word" => Some(word)
    "xdigit" =>
      Some(
        @prop.CharSet::of([
          ('0'.to_int(), '9'.to_int()),
          ('a'.to_int(), 'f'.to_int()),
          ('A'.to_int(), 'F'.to_int()),
        ]),
      )
    _ => None
  }
}

///|
/// An escape inside a class: a shorthand, a property, or a single character.
fn Parser::class_escape(
  self : Parser,
  rest : StringView,
) -> (StringView, ClassPart) raise Refused {
  if rest.length() == 1 {
    raise self.refuse(rest, "bad escape (end of pattern)")
  }
  let c = rest.at(1).to_int()
  let after = rest.view(start_offset=2)
  match c {
    'd' | 'D' | 's' | 'S' | 'w' | 'W' =>
      if self.dialect is Lexmatch {
        raise self.refuse(rest, "use a POSIX character class instead")
      } else {
        (after, Many(set=self.shorthand(c)))
      }
    'p' | 'P' =>
      // ECMA-262 reads `\p{…}` inside a class only under `u` or `v`; without
      // them Annex B makes it an identity escape for the letter itself.
      if self.dialect is Python ||
        (
          self.dialect is Ecma262 &&
          (self.flags.unicode || self.flags.unicode_sets)
        ) {
        let (after, set) = self.property(after, c == 'P')
        (after, Many(set~))
      } else {
        (after, One(code=c))
      }
    'b' =>
      // Inside a class, `\b` is the backspace character.
      (after, One(code=0x08))
    'n' => (after, One(code='\n'.to_int()))
    'r' => (after, One(code='\r'.to_int()))
    't' => (after, One(code='\t'.to_int()))
    'f' => (after, One(code='\u{0c}'.to_int()))
    'v' => (after, One(code='\u{0b}'.to_int()))
    'a' =>
      if self.dialect is Python {
        (after, One(code=0x07))
      } else {
        (after, One(code='a'.to_int()))
      }
    'x' =>
      match self.hex(after, 2) {
        None => raise self.refuse(rest, "incomplete escape \\x")
        Some((code, view)) => (view, One(code~))
      }
    'u' =>
      if self.dialect is Ecma262 &&
        self.flags.unicode &&
        after.length() > 0 &&
        after.at(0).to_int() == '{' {
        match self.read_until_close(after.view(start_offset=1), '}') {
          None => raise self.refuse(rest, "invalid Unicode escape")
          Some((hex, view)) =>
            match hex_to_int(hex) {
              None => raise self.refuse(rest, "invalid Unicode escape")
              Some(code) => (view, One(code~))
            }
        }
      } else if self.dialect is Ecma262 && !self.flags.unicode {
        // Annex B: `\u` not followed by four hex digits is the letter itself.
        match self.hex(after, 4) {
          Some((code, view)) => (view, One(code~))
          None => (after, One(code='u'.to_int()))
        }
      } else {
        match self.hex(after, 4) {
          None => raise self.refuse(rest, "incomplete escape \\u")
          Some((code, view)) => (view, One(code~))
        }
      }
    'U' =>
      if self.dialect is Python {
        match self.hex(after, 8) {
          None => raise self.refuse(rest, "incomplete escape \\U")
          Some((code, view)) => (view, One(code~))
        }
      } else {
        (after, One(code='U'.to_int()))
      }
    '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' => {
      // Octal, always: inside a class there are no backreferences.
      let mut digits = c.unsafe_to_char().to_string()
      let mut view = after
      let mut i = 0
      while i < 2 && view.length() > 0 && is_octal_digit(view.at(0).to_int()) {
        digits = digits + view.at(0).to_int().unsafe_to_char().to_string()
        view = view.view(start_offset=1)
        i += 1
      }
      let code = octal(digits[:])
      if code > 0o377 {
        raise self.refuse(
          rest,
          "octal escape value \{digits} outside of range 0-0o377",
        )
      }
      (view, One(code~))
    }
    '8' | '9' => raise self.refuse(rest, "bad escape \\\{c.unsafe_to_char()}")
    _ => {
      let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      if letter && !(self.dialect is Ecma262 && !self.flags.unicode) {
        raise self.refuse(rest, "bad escape \\\{c.unsafe_to_char()}")
      }
      (after, One(code=c))
    }
  }
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

///|
/// Refuse the pattern, saying where reading stopped.
///
/// Positions are code points, as Python reports them, so the caller can count
/// characters rather than UTF-16 units.
fn Parser::refuse(self : Parser, rest : StringView, msg : String) -> Refused {
  let at = code_point_offset(self.src, rest.start_offset())
  let (line, column) = line_column(self.src, rest.start_offset())
  Pattern(msg~, at~, line~, column~)
}

///|
/// How many code points of `src` come before a UTF-16 offset.
fn code_point_offset(src : StringView, offset : Int32) -> Int32 {
  let mut count = 0
  let mut i = 0
  for c in src {
    if i >= offset {
      break
    }
    count += 1
    i += if c.to_int() >= 0x10000 { 2 } else { 1 }
  }
  count
}

///|
/// Where a UTF-16 offset sits, in lines and code point columns.
fn line_column(src : StringView, offset : Int32) -> (Int32, Int32) {
  let mut line = 1
  let mut column = 1
  let mut i = 0
  for c in src {
    if i >= offset {
      break
    }
    if c == '\n' {
      line += 1
      column = 1
    } else {
      column += 1
    }
    i += if c.to_int() >= 0x10000 { 2 } else { 1 }
  }
  (line, column)
}
