// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How a tree is written back out in the `lexmatch` grammar.
///
/// Lowering asks one question: can the engine in the core library run this?
/// The only way into that engine is its own grammar, so the tree is printed in
/// it. Printing is therefore not decoration — a node the grammar has no
/// spelling for prints as `None`, and the whole lowering gives up, which is
/// exactly the subset test.

///|
/// The highest repeat count the lexmatch grammar accepts.
const MAX_LEXMATCH_REPEAT : Int32 = 256

///|
/// The slot-to-name view of a tree, which the printer needs to write
/// `(?<name>…)` rather than a bare `(…)`.
fn slot_names(groupindex : Map[String, Array[Int32]]) -> Map[Int32, String] {
  let out : Map[Int32, String] = Map([])
  for name, slots in groupindex {
    for slot in slots {
      if !out.contains(slot) {
        out[slot] = name
      }
    }
  }
  out
}

///|
/// The tree as a `lexmatch` pattern, or `None` when it says something that
/// grammar cannot.
fn render(root : Node, names : Map[Int32, String]) -> String? {
  let buf = StringBuilder::StringBuilder()
  if !render_into(root, names, buf) {
    return None
  }
  Some(buf.to_string())
}

///|
fn render_into(
  node : Node,
  names : Map[Int32, String],
  buf : StringBuilder,
) -> Bool {
  match node {
    Empty => true
    Char(code~) => {
      write_code(buf, code)
      true
    }
    Any(dotall~) =>
      if dotall {
        // The grammar's `.` crosses newlines, which is what `dotall` means.
        buf.write_string(".")
        true
      } else {
        render_class(buf, [(0, 0x09), (0x0B, 0x10FFFF)])
      }
    Class(set~) => render_class(buf, set.ranges())
    Seq(items~) => {
      let mut ok = true
      for item in items {
        if !render_into(item, names, buf) {
          ok = false
        }
      }
      ok
    }
    Alt(items~) => {
      let mut ok = true
      let mut first = true
      for item in items {
        if !first {
          buf.write_string("|")
        }
        first = false
        if !render_into(item, names, buf) {
          ok = false
        }
      }
      ok
    }
    Repeat(node~, min~, max~, greedy~) => {
      let too_many = match max {
        None => min > MAX_LEXMATCH_REPEAT
        Some(m) => min > MAX_LEXMATCH_REPEAT || m > MAX_LEXMATCH_REPEAT
      }
      if too_many {
        return false
      }
      // A quantifier binds to one atom, so a sequence or an alternation has
      // to be wrapped first.
      let needs_group = match node {
        Seq(items~) => items.length() != 1
        Alt(_) => true
        _ => false
      }
      if needs_group {
        buf.write_string("(?:")
      }
      if !render_into(node, names, buf) {
        return false
      }
      if needs_group {
        buf.write_string(")")
      }
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
        Some(m) =>
          if min == 0 && m == 1 {
            buf.write_string("?")
          } else if min == m {
            buf.write_string("{")
            buf.write_string(min.to_string())
            buf.write_string("}")
          } else if min == 0 {
            buf.write_string("{0,")
            buf.write_string(m.to_string())
            buf.write_string("}")
          } else {
            buf.write_string("{")
            buf.write_string(min.to_string())
            buf.write_string(",")
            buf.write_string(m.to_string())
            buf.write_string("}")
          }
      }
      if !greedy {
        buf.write_string("?")
      }
      true
    }
    Group(slot~, node~) => {
      buf.write_string("(")
      match names.get(slot) {
        None => ()
        Some(name) => {
          buf.write_string("?<")
          buf.write_string(name)
          buf.write_string(">")
        }
      }
      if !render_into(node, names, buf) {
        return false
      }
      buf.write_string(")")
      true
    }
    Anchor(anchor~) =>
      match anchor {
        // `^` and `$` in the grammar are anchored to the whole text, which is
        // what these mean.
        StartLine(multiline=false) => {
          buf.write_string("^")
          true
        }
        TextStart => {
          buf.write_string("^")
          true
        }
        EndLine(multiline=false, before_final_newline=false) => {
          buf.write_string("$")
          true
        }
        TextEnd => {
          buf.write_string("$")
          true
        }
        WordBoundary(negate~, ascii~) =>
          if ascii {
            buf.write_string(if negate { "\\B" } else { "\\b" })
            true
          } else {
            // The grammar's word boundary is ASCII-only.
            false
          }
        _ => false
      }
    // Everything below is outside what the core engine can run.
    Atomic(_)
    | Lookaround(_)
    | Backref(_)
    | Cond(_)
    | Keep
    | Grapheme
    | Fuzzy(_)
    | Define(_)
    | Recurse(_)
    | Verb(_) => false
  }
}

///|
/// Print a class, choosing whichever of the set and its complement is
/// shorter.
fn render_class(buf : StringBuilder, ranges : Array[(Int32, Int32)]) -> Bool {
  if ranges.length() == 0 {
    // The empty set: everything, negated.
    buf.write_string("[^")
    write_code(buf, 0)
    buf.write_string("-")
    write_code(buf, 0x10FFFF)
    buf.write_string("]")
    return true
  }
  let complement = @prop.CharSet::of(ranges).complement().ranges()
  if complement.length() > 0 && complement.length() < ranges.length() {
    write_class_body(buf, complement, true)
  } else {
    write_class_body(buf, ranges, false)
  }
  true
}

///|
/// Print `[...]`, negated when `negate`.
///
/// Surrogates are left out: they are not scalar values, so a class that lists
/// them cannot be written as characters at all.
fn write_class_body(
  buf : StringBuilder,
  ranges : Array[(Int32, Int32)],
  negate : Bool,
) -> Unit {
  buf.write_string("[")
  if negate {
    buf.write_string("^")
  }
  let mut wrote = false
  for (lo, hi) in ranges {
    let pieces = split_surrogates(lo, hi)
    for (a, b) in pieces {
      wrote = true
      write_code(buf, a)
      if b != a {
        buf.write_string("-")
        write_code(buf, b)
      }
    }
  }
  if !wrote {
    // Nothing survived the surrogate cut, so the set is empty.
    buf.write_string("^")
    write_code(buf, 0)
    buf.write_string("-")
    write_code(buf, 0x10FFFF)
  }
  buf.write_string("]")
}

///|
/// A range with the surrogate block cut out of it.
fn split_surrogates(lo : Int32, hi : Int32) -> Array[(Int32, Int32)] {
  let out : Array[(Int32, Int32)] = []
  if hi < 0xD800 || lo > 0xDFFF {
    out.push((lo, hi))
    return out
  }
  if lo < 0xD800 {
    out.push((lo, 0xD7FF))
  }
  if hi > 0xDFFF {
    out.push((0xE000, hi))
  }
  out
}

///|
/// One code point, spelled so no context can mistake it: an alphanumeric
/// stands for itself, everything else is `\\u{…}`.
fn write_code(buf : StringBuilder, code : Int32) -> Unit {
  let is_alnum = (code >= 0x61 && code <= 0x7A) ||
    (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x30 && code <= 0x39)
  if is_alnum {
    buf.write_char(code.unsafe_to_char())
  } else {
    buf.write_string("\\u{")
    buf.write_string(hex_text(code))
    buf.write_string("}")
  }
}

///|
/// The tree as a `lexmatch` pattern — what the core library's engine reads.
///
/// `None` when the tree uses something that grammar cannot say, which is the
/// line between the two engines: everything above it can be handed to the core
/// library, everything below has to run here.
pub fn Ast::to_lexmatch(self : Ast) -> String? {
  render(self.root, slot_names(self.groupindex))
}

///|
fn hex_text(value : Int32) -> String {
  let digits = "0123456789ABCDEF"
  let out : Array[Char] = []
  let mut n = value
  if n == 0 {
    out.push('0')
  }
  while n > 0 {
    out.push(digits[n % 16].to_int().unsafe_to_char())
    n = n / 16
  }
  let buf = StringBuilder::StringBuilder()
  let mut i = out.length() - 1
  while i >= 0 {
    buf.write_char(out[i])
    i -= 1
  }
  buf.to_string()
}
