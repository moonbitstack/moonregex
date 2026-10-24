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
/// The name table, built once from the compact `name_data` blob. Building it in
/// a function (not an array literal) keeps it out of the wasm init function,
/// whose local-count limit a 40 000-entry literal would overflow.
let name_table : Array[(String, Int32)] = build_name_table(name_data)

///|
/// Parse `name_data` — `name=hex` entries, one per line, sorted — into the
/// array `char_of_name` binary-searches.
fn build_name_table(data : String) -> Array[(String, Int32)] {
  let out : Array[(String, Int32)] = []
  let chars : Array[Char] = []
  for c in data {
    chars.push(c)
  }
  let n = chars.length()
  let mut i = 0
  while i < n {
    let mut name = ""
    while i < n && chars[i] != '=' {
      name = name + chars[i].to_string()
      i += 1
    }
    i += 1 // skip '='
    let mut v : Int32 = 0
    while i < n && chars[i] != '\n' {
      v = v * 16 + hex_val(chars[i])
      i += 1
    }
    i += 1 // skip '\n'
    out.push((name, v))
  }
  out
}

///|
fn hex_val(c : Char) -> Int32 {
  let code = c.to_int()
  if code >= '0'.to_int() && code <= '9'.to_int() {
    code - '0'.to_int()
  } else if code >= 'a'.to_int() && code <= 'f'.to_int() {
    code - 'a'.to_int() + 10
  } else {
    0
  }
}

///|
/// The code point a Unicode character name denotes — the table `\N{name}`
/// answers from.
///
/// Names are matched loosely, the way Python's `unicodedata.lookup` reads
/// them: case, spaces, hyphens and underscores are ignored. Control and
/// abbreviation aliases (`NULL`, `TAB`, …) are accepted, and the algorithmic
/// `PREFIX-XXXX` names of the CJK/Tangut ranges are answered from their hex
/// suffix rather than a 300 000-entry table.
pub fn char_of_name(name : StringView) -> Int32? {
  let key = normalise_name(name)
  match bin_name(name_aliases, key) {
    Some(cp) => return Some(cp)
    None => ()
  }
  match bin_name(name_table, key) {
    Some(cp) => return Some(cp)
    None => ()
  }
  // Algorithmic `PREFIX-XXXX` names for the First/Last ranges.
  let kchars : Array[Char] = []
  for c in key {
    kchars.push(c)
  }
  let kn = kchars.length()
  for (prefix, lo, hi) in name_ranges {
    let pchars : Array[Char] = []
    for c in prefix {
      pchars.push(c)
    }
    let pn = pchars.length()
    if kn > pn {
      let mut i = 0
      let mut ok = true
      while i < pn {
        if kchars[i] != pchars[i] {
          ok = false
        }
        i += 1
      }
      if ok {
        match hex_digits(kchars, pn) {
          None => ()
          Some(v) => if v >= lo && v <= hi { return Some(v) }
        }
      }
    }
  }
  None
}

///|
/// Binary-search a `(name, code point)` table.
fn bin_name(table : Array[(String, Int32)], key : String) -> Int32? {
  let mut lo = 0
  let mut hi = table.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let (n, cp) = table[mid]
    if n == key {
      return Some(cp)
    }
    if str_lt(n, key) {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  None
}

///|
/// Lexicographic order over code points. MoonBit's `String <` is not
/// lexicographic, so the name table's binary search cannot rely on it.
fn str_lt(a : String, b : String) -> Bool {
  let ca : Array[Char] = []
  for c in a {
    ca.push(c)
  }
  let cb : Array[Char] = []
  for c in b {
    cb.push(c)
  }
  let n = if ca.length() < cb.length() { ca.length() } else { cb.length() }
  let mut i = 0
  while i < n {
    let x = ca[i].to_int()
    let y = cb[i].to_int()
    if x != y {
      return x < y
    }
    i += 1
  }
  ca.length() < cb.length()
}

///|
/// Read the hex code point out of `chars[from..]`; `None` if fewer than four
/// hex digits remain.
fn hex_digits(chars : Array[Char], from : Int32) -> Int32? {
  if chars.length() - from < 4 {
    return None
  }
  let mut v : Int32 = 0
  let mut i = from
  while i < chars.length() {
    let c = chars[i].to_int()
    let d = if c >= '0'.to_int() && c <= '9'.to_int() {
      c - '0'.to_int()
    } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
      c - 'a'.to_int() + 10
    } else {
      return None
    }
    v = v * 16 + d
    i += 1
  }
  Some(v)
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
