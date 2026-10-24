// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which Unicode the tables answer to.
///
/// A pattern that leans on `\p{...}` behaves differently between Unicode
/// versions when characters move between categories, so the version is part of
/// the answer, not decoration.
pub fn version() -> String {
  unicode_version
}

///|
/// Normalise a property name the way the mrab-regex superset does: lower case,
/// separators gone. `Uppercase_Letter`, `UPPERCASELETTER` and
/// `uppercase-letter` all name the same thing.
///
/// Property names are ASCII, so the ASCII fold is the whole of it.
fn normalise_name(name : StringView) -> String {
  let buf = StringBuilder::StringBuilder()
  for c in name.to_lower() {
    if c == '_' || c == '-' || c == ' ' {
      continue
    }
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// A general category: `L`, `Lu`, `Uppercase_Letter`, `casedletter`.
pub fn category(name : StringView) -> CharSet? {
  gc_of(normalise_name(name))
}

///|
/// A binary property: `Alphabetic`, `White_Space`, `Emoji`.
pub fn binary(name : StringView) -> CharSet? {
  binary_of(normalise_name(name))
}

///|
/// A script: `Latin`, `Latn`, `Han`.
pub fn script(name : StringView) -> CharSet? {
  script_of(normalise_name(name))
}

///|
/// A block: `Basic Latin`, `BasicLatin`, `CJK Unified Ideographs`.
pub fn block(name : StringView) -> CharSet? {
  block_of(normalise_name(name))
}

///|
/// Any property, however it is spelled — the shape `\p{...}` takes.
///
/// `name=value` is accepted too: `Script=Latin`, `General_Category=Lu`,
/// `Block=CJK Unified Ideographs`. The left side picks the table, the right
/// side the entry; without it, every table is searched in the order a Unicode
/// name would be looked up: category, script, block, binary property.
pub fn property(name : StringView) -> CharSet? {
  match name.split_once("=") {
    None => by_name(name)
    Some((kind, value)) => {
      let k = normalise_name(kind)
      let v = normalise_name(value)
      if k == "gc" || k == "generalcategory" {
        gc_of(v)
      } else if k == "sc" || k == "script" {
        script_of(v)
      } else if k == "blk" || k == "block" {
        block_of(v)
      } else if k == "binary" || k == "property" {
        binary_of(v)
      } else {
        None
      }
    }
  }
}

///|
/// Look a bare name up across the tables, in the order that disambiguates.
fn by_name(name : StringView) -> CharSet? {
  let key = normalise_name(name)
  match gc_of(key) {
    Some(set) => Some(set)
    None =>
      match script_of(key) {
        Some(set) => Some(set)
        None =>
          match block_of(key) {
            Some(set) => Some(set)
            None =>
              match binary_of(key) {
                Some(set) => Some(set)
                None =>
                  // One spelling that is not a Unicode property name but is
                  // written like one everywhere else.
                  if key == "any" {
                    Some(CharSet::any())
                  } else {
                    None
                  }
              }
          }
      }
  }
}

///|
/// Simple case folding: one code point in, its folded form out.
///
/// Folding is not case conversion — it is the equivalence classes case-
/// insensitive matching compares in, so `K` (Kelvin sign) folds to `k` and
/// `ſ` folds to `s`, while a character with no fold folds to itself.
pub fn fold(c : Char) -> Char {
  let cp = c.to_int()
  let pairs = casefold_pairs
  let mut lo = 0
  let mut hi = pairs.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let (src, dst) = pairs[mid]
    if cp < src {
      hi = mid - 1
    } else if cp > src {
      lo = mid + 1
    } else {
      return match dst.to_char() {
        Some(c) => c
        // The tables only hold scalar values, so this is unreachable; a
        // surrogate code point in a fold table would fold to itself.
        None => c
      }
    }
  }
  c
}

///|
/// `\w` under the Python and mrab spellings: letters, numbers and the
/// underscore. Python's own words for it are "alphanumeric (as `str.isalnum`
/// has it) plus `_`", which is exactly these categories.
pub let word : CharSet = {
  let letters = gc_of("l").unwrap_or(CharSet::empty())
  let numbers = gc_of("n").unwrap_or(CharSet::empty())
  letters.union(numbers).union(CharSet::single('_'.to_int()))
}

///|
/// `\d`: decimal digits, and only those.
pub let digit : CharSet = gc_of("nd").unwrap_or(CharSet::empty())

///|
/// `\s`: the White_Space property.
pub let space : CharSet = binary_of("whitespace").unwrap_or(CharSet::empty())

///|
/// The same three, restricted to ASCII, which is what the `A` flag and the
/// ECMA-262 dialect without `u` mean by them.
pub let ascii_word : CharSet = CharSet::of([
  ('0'.to_int(), '9'.to_int()),
  ('A'.to_int(), 'Z'.to_int()),
  ('_'.to_int(), '_'.to_int()),
  ('a'.to_int(), 'z'.to_int()),
])

///|
pub let ascii_digit : CharSet = CharSet::of([('0'.to_int(), '9'.to_int())])

///|
pub let ascii_space : CharSet = CharSet::of([
  (0x09, 0x0D),
  (' '.to_int(), ' '.to_int()),
])
