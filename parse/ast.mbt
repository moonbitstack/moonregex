// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which way a lookaround looks, and whether it wants to find something.
pub enum Look {
  /// `(?=…)` / `(?!…)`
  Ahead(positive~ : Bool)
  /// `(?<=…)` / `(?<!…)`
  Behind(positive~ : Bool)
} derive(Eq, Debug)

///|
pub extend Look with Eq::{equal, not_equal}

///|
pub extend Look with Debug::{to_repr}

///|
/// An assertion: something true of a position rather than of the text in it.
///
/// Every dialect difference about anchors is settled here at parse time —
/// `^` under `m` is a different node from `^` without it, and Python's `$`
/// (which also matches before a trailing newline) from ECMA-262's (which does
/// not) — so the executor reads one meaning per node.
pub enum Anchor {
  /// `^`: start of line when `multiline`, of the text otherwise.
  StartLine(multiline~ : Bool)
  /// `$`: end of line when `multiline`, of the text otherwise.
  /// `before_final_newline` is Python's `$`, which also sits before a newline
  /// at the very end; ECMA-262's does not.
  EndLine(multiline~ : Bool, before_final_newline~ : Bool)
  /// `\A`: the start of the text, whatever the flags say.
  TextStart
  /// `\Z`, `\z`: the end of the text, whatever the flags say.
  TextEnd
  /// `\b`, `\B`: a word boundary, over the ASCII or the Unicode word set.
  WordBoundary(negate~ : Bool, ascii~ : Bool)
  /// `\m`, `\M`: the mrab-regex variants, at the start and the end of a word.
  WordStart
  WordEnd
  /// `\G`: where the search started, so a scan cannot drift.
  SearchAnchor
} derive(Eq, Debug)

///|
pub extend Anchor with Eq::{equal, not_equal}

///|
pub extend Anchor with Debug::{to_repr}

///|
/// What a conditional tests.
pub enum Cond {
  /// `(?(1)yes|no)`: whether a group took part in the match.
  ByGroup(slot~ : Int32)
  /// `(?(?=…)yes|no)`: whether a lookaround holds here.
  ByLook(node~ : Node, look~ : Look)
  /// `(?(R)…)`, `(?(R1)…)`, `(?(R&name)…)`: whether we are inside a recursion.
  ByRecurse(target~ : RecurseCond)
} derive(Eq, Debug)

///|
pub extend Cond with Eq::{equal, not_equal}

///|
pub extend Cond with Debug::{to_repr}

///|
/// How much fuzz a fuzzy quantifier allows.
///
/// mrab-regex writes these as `{e<=1}`, `{i<=2,d<=1}`, `{2i+1d+1s<=3}`: a
/// budget over insertions, deletions and substitutions, either counted or
/// weighed. The representation is settled here before any of it executes, so
/// the executor grows one interpreter for fuzzy nodes rather than a fuzzy
/// branch in every path.
pub struct FuzzySpec {
  /// `i<=n`: how many insertions.
  insertions : Int32?
  /// `d<=n`: how many deletions.
  deletions : Int32?
  /// `s<=n`: how many substitutions.
  substitutions : Int32?
  /// `e<=n`: how many errors of any kind, when not broken down.
  errors : Int32?
  /// A weighted budget, with the weights it is weighed by.
  cost : (Int32, Int32, Int32)?
} derive(Eq, Debug)

///|
pub extend FuzzySpec with Eq::{equal, not_equal}

///|
pub extend FuzzySpec with Debug::{to_repr}

///|
/// What a recursion calls back into.
pub enum Recurse {
  /// `(?R)`: the whole pattern.
  Whole
  /// `(?1)`: a capture group by number.
  Group(slot~ : Int32)
  /// `(?&name)`: a capture group by name.
  Named(name~ : String)
} derive(Eq, Debug)

///|
/// A control verb from the `regex` superset: `(*ACCEPT)`, `(*FAIL)`, and the
/// rest. `Accept` ends the whole match at the current position; `Fail` forces
/// the current match attempt to fail; `Mark` records a name; `Prune` and `Skip`
/// carry the position past a failure so the scan does not retry it.
pub enum VerbKind {
  /// `(*ACCEPT)`: end the match successfully here.
  Accept
  /// `(*FAIL)` / `(*F)`: make this match attempt fail.
  Fail
  /// `(*COMMIT)`: fail the entire match, no further search.
  Commit
  /// `(*MARK:name)` / `(*:name)`: record a name on the match.
  Mark(name~ : String)
  /// `(*PRUNE)` / `(*PRUNE:name)`: fail and do not backtrack before this point.
  Prune(name~ : String?)
  /// `(*SKIP)` / `(*SKIP:name)`: fail and resume the scan after the mark.
  Skip(name~ : String?)
  /// `(*THEN)` / `(*THEN:name)`: fail and jump to the next alternative.
  Then(name~ : String?)
  /// `(*LIMIT_MATCH:n)`: set the match step ceiling.
  LimitMatch(n~ : Int32)
  /// `(*LIMIT_RECURSION:n)`: set the recursion depth ceiling.
  LimitRecursion(n~ : Int32)
  /// `(*VERSION)`: accept the current engine version (a no-op).
  Version
  /// `(*FENCE)`: prevent any backtracking past this point.
  Fence
} derive(Eq, Debug)

///|
pub extend VerbKind with Eq::{equal, not_equal}

///|
pub extend VerbKind with Debug::{to_repr}

///|
pub extend Recurse with Eq::{equal, not_equal}

///|
pub extend Recurse with Debug::{to_repr}

///|
/// The target of a recursion condition `(?(R)…)`.
pub enum RecurseCond {
  /// `(?(R))`: inside any recursion.
  AnyRecursion
  /// `(?(R1))`: inside a recursion of group `slot`.
  GroupRecursion(slot~ : Int32)
  /// `(?(R&name))`: inside a recursion of named group `name`.
  NamedRecursion(name~ : String)
} derive(Eq, Debug)

///|
pub extend RecurseCond with Eq::{equal, not_equal}

///|
pub extend RecurseCond with Debug::{to_repr}

///|
/// One node of the syntax tree every dialect is lowered into.
///
/// The tree is resolved: flags have been folded into the nodes that care
/// (`(?s:.)` is an `Any` that eats newlines, `(?i)k` is a class holding both
/// cases), so the executor never asks which grammar a node came from.
pub enum Node {
  /// Matches the empty string.
  Empty
  /// One literal code point.
  Char(code~ : Int32)
  /// `.`: any character, newlines included when `dotall`.
  Any(dotall~ : Bool)
  /// A character class, negation and folding already applied.
  Class(set~ : @prop.CharSet)
  /// Things one after another.
  Seq(items~ : Array[Node])
  /// Things one instead of another.
  Alt(items~ : Array[Node])
  /// `node` repeated `min` to `max` times (`None` for no ceiling), greedily
  /// or not.
  Repeat(node~ : Node, min~ : Int32, max~ : Int32?, greedy~ : Bool)
  /// A capture group; slot 0 is the whole match, 1 up are the parenthesised
  /// ones in the order their parentheses open.
  Group(slot~ : Int32, node~ : Node)
  /// `(?>…)`: once through, no backtracking into it.
  Atomic(node~ : Node)
  /// A lookaround.
  Lookaround(node~ : Node, look~ : Look)
  /// A backreference to what a group captured, case-folded when `icase`.
  Backref(slot~ : Int32, icase~ : Bool)
  /// A conditional: test, then one branch or the other.
  Cond(probe~ : Cond, yes~ : Node, no~ : Node?)
  /// An assertion.
  Anchor(anchor~ : Anchor)
  /// `\K`: everything before here stops counting towards the match.
  Keep
  /// `\X`: one grapheme cluster.
  Grapheme
  /// The enclosed node, matched with a budget of edits.
  Fuzzy(spec~ : FuzzySpec, node~ : Node)
  /// `(?(DEFINE)…)`: declare subroutines, match empty. The body's groups are
  /// registered (and compiled into sub-programs) but never matched inline.
  Define(node~ : Node)
  /// A recursive call back into the pattern.
  Recurse(target~ : Recurse)
  /// A control verb: `(*ACCEPT)`, `(*FAIL)`, `(*MARK:name)`, `(*PRUNE)`,
  /// `(*SKIP)`.
  Verb(kind~ : VerbKind)
} derive(Eq, Debug)

///|
pub extend Node with Eq::{equal, not_equal}

///|
pub extend Node with Debug::{to_repr}

///|
/// A parsed pattern: the tree, and what the parse learned about it.
///
/// `flags` is the compile-time flags with the pattern's own global inline
/// flags merged in — what `Pattern::flags` answers.
pub struct Ast {
  root : Node
  /// How many capture groups the pattern has, group 0 included.
  groups : Int32
  /// Group name to the slots carrying it. An array, because ECMA-262 since
  /// 2025 allows the same name in different branches.
  groupindex : Map[String, Array[Int32]]
  /// `\L<name>` named lists, expanded at compile time.
  named_lists : Map[String, Array[String]]
  /// The effective flags, global inline flags merged in.
  flags : Flags
}

///|
/// The tree on its own, for the executor.
pub fn Ast::root(self : Ast) -> Node {
  self.root
}

///|
/// How many capture groups the pattern has.
pub fn Ast::groups(self : Ast) -> Int32 {
  self.groups
}

///|
/// Group name to the slots carrying it.
pub fn Ast::groupindex(self : Ast) -> Map[String, Array[Int32]] {
  self.groupindex
}

///|
/// The named lists the pattern declared with `\L<name>`.
pub fn Ast::named_lists(self : Ast) -> Map[String, Array[String]] {
  self.named_lists
}

///|
/// The effective flags.
pub fn Ast::flags(self : Ast) -> Flags {
  self.flags
}

///|
/// The syntax tree as text: what `Pattern::dump` answers.
///
/// Not the pattern — a parse and re-print loses spacing and comments, and
/// folds flags into the nodes — but close enough to read a pattern back from,
/// which is what tests and debugging want.
pub fn Ast::dump(self : Ast) -> String {
  let buf = StringBuilder::StringBuilder()
  dump_node(self.root, buf)
  buf.to_string()
}

///|
fn dump_node(node : Node, buf : StringBuilder) -> Unit {
  match node {
    Empty => buf.write_string("")
    Char(code~) => dump_char(code, buf)
    Any(dotall~) => buf.write_string(if dotall { "\\n" } else { "." })
    Class(set~) => dump_class(set, buf)
    Seq(items~) =>
      for item in items {
        dump_node(item, buf)
      }
    Alt(items~) => {
      let mut first = true
      for item in items {
        if !first {
          buf.write_string("|")
        }
        first = false
        dump_node(item, buf)
      }
    }
    Repeat(node~, min~, max~, greedy~) => {
      dump_node(node, buf)
      match max {
        None =>
          if min == 0 {
            buf.write_string("*")
          } else if min == 1 {
            buf.write_string("+")
          } else {
            buf.write_string("{")
            buf.write_string(min.to_string())
            buf.write_string(",}")
          }
        Some(max) =>
          if min == max {
            buf.write_string("{")
            buf.write_string(min.to_string())
            buf.write_string("}")
          } else if min == 0 && max == 1 {
            buf.write_string("?")
          } else if min == 0 {
            buf.write_string("{")
            buf.write_string(max.to_string())
            buf.write_string("}")
          } else {
            buf.write_string("{")
            buf.write_string(min.to_string())
            buf.write_string(",")
            buf.write_string(max.to_string())
            buf.write_string("}")
          }
      }
      if !greedy {
        buf.write_string("?")
      }
    }
    Group(slot~, node~) => {
      ignore(slot)
      buf.write_string("(")
      dump_node(node, buf)
      buf.write_string(")")
    }
    Atomic(node~) => {
      buf.write_string("(?>")
      dump_node(node, buf)
      buf.write_string(")")
    }
    Lookaround(node~, look~) => {
      buf.write_string(
        match look {
          Ahead(positive=true) => "(?="
          Ahead(positive=false) => "(?!"
          Behind(positive=true) => "(?<="
          Behind(positive=false) => "(?<!"
        },
      )
      dump_node(node, buf)
      buf.write_string(")")
    }
    Backref(slot~, ..) => {
      buf.write_string("\\")
      buf.write_string(slot.to_string())
    }
    Cond(probe~, yes~, no~) => {
      buf.write_string("(?(")
      match probe {
        ByGroup(slot~) => buf.write_string("\{slot}")
        ByLook(..) => buf.write_string("?")
        ByRecurse(target~) =>
          buf.write_string(
            match target {
              AnyRecursion => "R"
              GroupRecursion(slot~) => "R\{slot}"
              NamedRecursion(name~) => "R&" + name
            },
          )
      }
      dump_node(yes, buf)
      match no {
        None => ()
        Some(no) => {
          buf.write_string("|")
          dump_node(no, buf)
        }
      }
      buf.write_string(")")
    }
    Anchor(anchor~) =>
      buf.write_string(
        match anchor {
          StartLine(multiline=true) => "^"
          StartLine(multiline=false) => "\\A"
          EndLine(multiline=true, ..) => "$"
          EndLine(multiline=false, before_final_newline=true) => "$"
          EndLine(multiline=false, before_final_newline=false) => "\\Z"
          TextStart => "\\A"
          TextEnd => "\\Z"
          WordBoundary(negate=false, ..) => "\\b"
          WordBoundary(negate=true, ..) => "\\B"
          WordStart => "\\m"
          WordEnd => "\\M"
          SearchAnchor => "\\G"
        },
      )
    Keep => buf.write_string("\\K")
    Grapheme => buf.write_string("\\X")
    Fuzzy(spec~, node~) => {
      dump_node(node, buf)
      buf.write_string(dump_fuzzy(spec))
    }
    Define(node~) => {
      buf.write_string("(?(DEFINE)")
      dump_node(node, buf)
      buf.write_string(")")
    }
    Recurse(target~) =>
      match target {
        Whole => buf.write_string("(?R)")
        Group(slot~) => {
          buf.write_string("(?")
          buf.write_string(slot.to_string())
          buf.write_string(")")
        }
        Named(name~) => {
          buf.write_string("(?&")
          buf.write_string(name)
          buf.write_string(")")
        }
      }
    Verb(kind~) =>
      buf.write_string(
        match kind {
          Accept => "(*ACCEPT)"
          Fail => "(*FAIL)"
          Commit => "(*COMMIT)"
          Mark(name~) => "(*MARK:" + name + ")"
          Prune(name~) => verb_arg("(*PRUNE", name)
          Skip(name~) => verb_arg("(*SKIP", name)
          Then(name~) => verb_arg("(*THEN", name)
          LimitMatch(n~) => "(*LIMIT_MATCH:\{n})"
          LimitRecursion(n~) => "(*LIMIT_RECURSION:\{n})"
          Version => "(*VERSION)"
          Fence => "(*FENCE)"
        },
      )
  }
}

///|
fn verb_arg(verb : String, name : String?) -> String {
  match name {
    None => verb + ")"
    Some(n) => verb + ":" + n + ")"
  }
}

///|
fn dump_fuzzy(spec : FuzzySpec) -> String {
  let parts : Array[String] = []
  match spec.insertions {
    Some(n) => parts.push("i<=\{n}")
    None => ()
  }
  match spec.deletions {
    Some(n) => parts.push("d<=\{n}")
    None => ()
  }
  match spec.substitutions {
    Some(n) => parts.push("s<=\{n}")
    None => ()
  }
  match spec.errors {
    Some(n) => parts.push("e<=\{n}")
    None => ()
  }
  match spec.cost {
    None => ()
    Some((i, d, s)) =>
      if i == 1 && d == 1 && s == 1 {
        parts.push("e<=1")
      } else {
        parts.push("\{i}i+\{d}d+\{s}s<=1")
      }
  }
  "{" + parts.join(",") + "}"
}

///|
fn hex_of(code : Int32) -> String {
  let table = "0123456789ABCDEF"
  let buf = StringBuilder::StringBuilder()
  let mut n = code
  if n == 0 {
    buf.write_char('0')
    return buf.to_string()
  }
  // Collect the digits backwards, then write them in order.
  let digs : Array[Char] = []
  while n > 0 {
    digs.push(table[n % 16].to_int().unsafe_to_char())
    n = n / 16
  }
  let mut i = digs.length() - 1
  while i >= 0 {
    buf.write_char(digs[i])
    i -= 1
  }
  buf.to_string()
}

///|
fn dump_char(code : Int32, buf : StringBuilder) -> Unit {
  // Printable ASCII stands for itself; everything else is spelled out, so the
  // dump is unambiguous about what the tree holds.
  if code >= 0x20 && code < 0x7F {
    buf.write_char(code.unsafe_to_char())
  } else {
    buf.write_string("\\x")
    buf.write_string(hex_of(code))
  }
}

///|
fn dump_class(set : @prop.CharSet, buf : StringBuilder) -> Unit {
  buf.write_string("[")
  for (lo, hi) in set.ranges() {
    if lo == hi {
      dump_char(lo, buf)
    } else {
      dump_char(lo, buf)
      buf.write_string("-")
      dump_char(hi, buf)
    }
  }
  buf.write_string("]")
}
