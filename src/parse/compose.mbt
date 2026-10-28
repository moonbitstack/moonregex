// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Patterns built in code.
///
/// A pattern written as text and a pattern assembled from parts are the same
/// kind of value here — both are a syntax tree the executor runs — so `+`, `|`,
/// `repeat` and `capture` compose without ever going back through a string.

///|
/// An `Ast` matching exactly `text`, character for character.
pub fn literal(text : StringView) -> Ast {
  let nodes : Array[Node] = []
  for c in text {
    nodes.push(Char(code=c.to_int()))
  }
  let root = if nodes.length() == 0 {
    Empty
  } else if nodes.length() == 1 {
    nodes[0]
  } else {
    Seq(items=nodes)
  }
  Ast::built(root, groups=0, groupindex=Map([]), flags~)
}

///|
/// One after the other: `a + b`.
pub fn concat(a : Ast, b : Ast) -> Ast {
  let root = Seq(items=[a.root, b.root.shift_slots(a.groups)])
  Ast::built(
    root,
    groups=a.groups + b.groups,
    groupindex=merge_index(a.groupindex, b.groupindex, a.groups),
    flags=a.flags,
  )
}

///|
/// One or the other: `a | b`.
pub fn either(a : Ast, b : Ast) -> Ast {
  let root = Alt(items=[a.root, b.root.shift_slots(a.groups)])
  Ast::built(
    root,
    groups=a.groups + b.groups,
    groupindex=merge_index(a.groupindex, b.groupindex, a.groups),
    flags=a.flags,
  )
}

///|
/// `a.repeat(…)`.
pub fn repeated(
  a : Ast,
  min~ : Int32,
  max? : Int32,
  greedy~ : Bool,
) -> Ast raise Refused {
  if min < 0 {
    raise Pattern(msg="repeat count is negative", at=0, line=1, column=1)
  }
  match max {
    Some(m) =>
      if m < min {
        raise Pattern(
          msg="repeat count \{m} is below the minimum \{min}",
          at=0,
          line=1,
          column=1,
        )
      }
    None => ()
  }
  Ast::built(
    Repeat(node=a.root, min~, max~, greedy~),
    groups=a.groups,
    groupindex=a.groupindex,
    flags=a.flags,
  )
}

///|
/// `a.capture(name)` — one more group, numbered after the ones already there.
pub fn captured(a : Ast, name~ : String) -> Ast raise Refused {
  if name.length() == 0 {
    raise Pattern(msg="group name is empty", at=0, line=1, column=1)
  }
  let slot = a.groups + 1
  let index = copy_index(a.groupindex)
  match index.get(name) {
    None => index[name] = [slot]
    Some(slots) => index[name] = slots + [slot]
  }
  Ast::built(
    Group(slot~, node=a.root),
    groups=slot,
    groupindex=index,
    flags=a.flags,
  )
}

///|
fn copy_index(index : Map[String, Array[Int32]]) -> Map[String, Array[Int32]] {
  let out : Map[String, Array[Int32]] = Map([])
  for name, slots in index {
    out[name] = slots.copy()
  }
  out
}

///|
/// The right-hand pattern's group names, with its slots moved past the
/// left-hand pattern's.
fn merge_index(
  left : Map[String, Array[Int32]],
  right : Map[String, Array[Int32]],
  by : Int32,
) -> Map[String, Array[Int32]] {
  let out = copy_index(left)
  for name, slots in right {
    let moved = slots.map(slot => slot + by)
    match out.get(name) {
      None => out[name] = moved
      Some(had) => out[name] = had + moved
    }
  }
  out
}
