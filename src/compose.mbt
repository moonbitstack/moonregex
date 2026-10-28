// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The bridge to the core library's engine.
///
/// Core ships a regular-expression engine of its own, addressed through
/// `@string.Regex` and the `lexmatch` grammar, with a small set of combinators
/// to build patterns in code. This library reads three bigger grammars and
/// runs the parts of them core cannot. The two meet here: a pattern that says
/// nothing core cannot say is lowered onto core's engine, and the combinators
/// are the same five, spelled the same way, so a pattern assembled in code and
/// a pattern written as text are interchangeable.

///|
/// The pattern as a core `@string.Regex`, when the core engine can run it.
///
/// The core engine speaks one grammar, so this answers only for the patterns
/// that fit inside it: literals, classes, `.`, `^`, `$`, `\b`, `\B`, groups,
/// alternation, quantifiers up to 256. Anything else — backreferences,
/// lookaround, conditionals, recursion, atomic groups, fuzzy matching, `\X`,
/// Unicode word boundaries, Python's `$` — answers `None`, and the pattern
/// runs on this library's own engine instead.
///
/// The result is an ordinary `@string.Regex`: it can be handed to core's
/// `execute`, `find`, `split`, `replace_by`, or to the lexer.
pub fn Pattern::lower(self : Pattern) -> @string.Regex? {
  match self.ast.to_lexmatch() {
    None => None
    Some(text) => Some(@string.Regex::Regex(text)) catch { _ => None }
  }
}

///|
/// Build a `Pattern` out of an `Ast` assembled in code.
fn Pattern::from_ast(ast : @parse.Ast) -> Pattern {
  let program = @exec.compile(ast)
  let pat = match ast.to_lexmatch() {
    Some(text) => text
    None => ast.dump()
  }
  Pattern::{
    pat,
    flags: ast.flags(),
    dialect: @parse.Lexmatch,
    ast,
    program,
    partial: false,
  }
}

///|
/// A pattern that matches `text` literally, as `@string.Regex::string` does.
///
/// Nothing in `text` is read as syntax — the caller does not have to escape
/// it first.
pub fn Pattern::string(text : StringView) -> Pattern {
  Pattern::from_ast(@parse.literal(text))
}

///|
/// This pattern followed by `other`, as `Regex + Regex` in core.
///
/// The result carries this pattern's flags; `other`'s groups are renumbered to
/// follow these, so the composed pattern numbers its groups the way a written
/// one would.
pub impl Add for Pattern with fn add(self : Pattern, other : Pattern) -> Pattern {
  Pattern::from_ast(@parse.concat(self.ast, other.ast))
}

///|
#deprecated
pub extend Pattern with Add::{add}

///|
/// This pattern or `other`, as `Regex | Regex` in core.
pub impl BitOr for Pattern with fn lor(self : Pattern, other : Pattern) -> Pattern {
  Pattern::from_ast(@parse.either(self.ast, other.ast))
}

///|
#deprecated
pub extend Pattern with BitOr::{lor}

///|
/// This pattern repeated, as `Regex::repeat` in core: `min` to `max` times,
/// greedily unless `greedy` is off.
pub fn Pattern::repeat(
  self : Pattern,
  min~ : Int32 = 0,
  max? : Int32,
  greedy~ : Bool = true,
) -> Pattern raise @parse.Refused {
  Pattern::from_ast(@parse.repeated(self.ast, min~, max?, greedy~))
}

///|
/// This pattern wrapped in a named capture group, as `Regex::capture` in core.
///
/// The group is numbered after the ones the pattern already has, and
/// `groupindex` gains `name`.
pub fn Pattern::capture(
  self : Pattern,
  name : String,
) -> Pattern raise @parse.Refused {
  Pattern::from_ast(@parse.captured(self.ast, name~))
}
