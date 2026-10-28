// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A `Scanner` walks a fixed text from left to right, each call picking up
/// where the last left off — Python's `regex.Scanner`, and the loop `re`'s
/// `finditer` runs internally. Build one with `Pattern::scanner`.
pub struct Scanner {
  priv pattern : Pattern
  priv text : String
  /// The current scan position, held in a one-element array so the cursor can be
  /// advanced through an immutable receiver (arrays are reference-mutable).
  priv pos : Array[Int32]
}

///|
/// Bind a `Pattern` to a text so its methods can scan that text incrementally.
pub fn Pattern::scanner(self : Pattern, text : String) -> Scanner {
  Scanner::{ pattern: self, text, pos: [0], }
}

///|
/// The next match from the current position, advancing past it; `None` once the
/// text is exhausted — Python's `Scanner.search`.
pub fn Scanner::search(self : Scanner) -> Match? raise @parse.Refused {
  match self.pattern.search(self.text, pos=self.pos[0]) {
    None => None
    Some(m) => {
      self.pos[0] = m.end()
      Some(m)
    }
  }
}

///|
/// A match anchored at the current position, advancing past it; `None` if the
/// pattern does not match there — Python's `Scanner.match`.
pub fn Scanner::prefix(self : Scanner) -> Match? raise @parse.Refused {
  match self.pattern.prefix(self.text, pos=self.pos[0]) {
    None => None
    Some(m) => {
      self.pos[0] = m.end()
      Some(m)
    }
  }
}

///|
/// A full match of the region from the current position, advancing past it;
/// `None` otherwise — Python's `Scanner.full`.
pub fn Scanner::full(self : Scanner) -> Match? raise @parse.Refused {
  match self.pattern.full(self.text, pos=self.pos[0]) {
    None => None
    Some(m) => {
      self.pos[0] = m.end()
      Some(m)
    }
  }
}

///|
/// Every remaining match from the current position, as group strings, advancing
/// to the end of the text — Python's `Scanner.findall`.
pub fn Scanner::findall(
  self : Scanner,
  group~ : GroupKey = Whole,
  overlapped~ : Bool = false,
) -> Array[String?] raise @parse.Refused {
  let r = self.pattern.findall(self.text, group~, overlapped~, pos=self.pos[0])
  self.pos[0] = cp_length(self.text)
  r
}

///|
/// Every remaining match from the current position, as `Match` objects,
/// advancing to the end of the text — Python's `Scanner.finditer`.
pub fn Scanner::finditer(
  self : Scanner,
  overlapped~ : Bool = false,
) -> Array[Match] raise @parse.Refused {
  let r = self.pattern.finditer(self.text, overlapped~, pos=self.pos[0])
  self.pos[0] = cp_length(self.text)
  r
}

///|
/// Split the remaining text on the pattern, advancing to the end — Python's
/// `Scanner.split`.
pub fn Scanner::split(
  self : Scanner,
  maxsplit~ : Int32 = 0,
) -> Array[String?] raise @parse.Refused {
  let r = self.pattern.split(self.text, maxsplit~, pos=self.pos[0])
  self.pos[0] = cp_length(self.text)
  r
}

///|
/// Replace every remaining match with `repl`, returning the new text and
/// advancing to the end — Python's `Scanner.subn` / `Scanner.sub`.
pub fn Scanner::subn(
  self : Scanner,
  repl : String,
  count~ : Int32 = 0,
) -> (String, Int32) raise @parse.Refused {
  let r = self.pattern.subn(self.text, repl, count~, pos=self.pos[0])
  self.pos[0] = cp_length(self.text)
  r
}

///|
/// Replace every remaining match with `repl`, returning the new text —
/// Python's `Scanner.sub`.
pub fn Scanner::sub(
  self : Scanner,
  repl : String,
  count~ : Int32 = 0,
) -> String raise @parse.Refused {
  self.subn(repl, count~).0
}
