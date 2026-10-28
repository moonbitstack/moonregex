// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The Unicode answers `\p{…}` is made of.
///
/// Every set here is derived from the Unicode Character Database through the
/// `moonucd` packages — nothing in this repository restates a table. A
/// derivation walks the code space once with the UCD's own predicate, so each
/// set is derived at most once and then kept: the walk is the price of having
/// one source of truth for Unicode, and it is paid on first use, not at load.

///|
/// Which Unicode the answers follow.
pub fn version() -> String {
  @moonucd.version()
}

///|
/// The derived sets, keyed by normalised property name. Deriving one means a
/// walk of the whole code space, so the result is kept rather than recomputed.
let derived : Map[String, CharSet] = Map([])

///|
/// Which families have been derived: categories, scripts, blocks, case folding.
let derived_state : Array[Bool] = [false, false, false, false]

///|
/// Simple case folding, one code point in and one out, sorted by source.
let fold_source : Array[Int32] = []

///|
/// The fold of `fold_source[i]`.
let fold_target : Array[Int32] = []

///|
/// Normalise a property name the way Unicode's loose matching does: case,
/// spaces, hyphens and underscores carry no meaning, so `Uppercase_Letter`,
/// `uppercase-letter` and `UPPERCASELETTER` are one name.
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

// ---------------------------------------------------------------------------
// General categories
// ---------------------------------------------------------------------------

///|
/// The general categories in UCD order; the index is the bucket each code
/// point lands in.
let category_short : Array[String] = [
  "Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd", "Nl", "No", "Pc", "Pd", "Ps",
  "Pe", "Pi", "Pf", "Po", "Sm", "Sc", "Sk", "So", "Zs", "Zl", "Zp", "Cc", "Cf", "Cs",
  "Co", "Cn",
]

///|
/// The same categories under the names the standard also gives them.
let category_long : Array[String] = [
  "Uppercase_Letter", "Lowercase_Letter", "Titlecase_Letter", "Modifier_Letter",
  "Other_Letter", "Nonspacing_Mark", "Spacing_Mark", "Enclosing_Mark", "Decimal_Number",
  "Letter_Number", "Other_Number", "Connector_Punctuation", "Dash_Punctuation", "Open_Punctuation",
  "Close_Punctuation", "Initial_Punctuation", "Final_Punctuation", "Other_Punctuation",
  "Math_Symbol", "Currency_Symbol", "Modifier_Symbol", "Other_Symbol", "Space_Separator",
  "Line_Separator", "Paragraph_Separator", "Control", "Format", "Surrogate", "Private_Use",
  "Unassigned",
]

///|
/// The bucket a category belongs to.
fn category_code(c : @moonucd.Category) -> Int32 {
  match c {
    Lu => 0
    Ll => 1
    Lt => 2
    Lm => 3
    Lo => 4
    Mn => 5
    Mc => 6
    Me => 7
    Nd => 8
    Nl => 9
    No => 10
    Pc => 11
    Pd => 12
    Ps => 13
    Pe => 14
    Pi => 15
    Pf => 16
    Po => 17
    Sm => 18
    Sc => 19
    Sk => 20
    So => 21
    Zs => 22
    Zl => 23
    Zp => 24
    Cc => 25
    Cf => 26
    Cs => 27
    Co => 28
    Cn => 29
  }
}

///|
/// The one-letter families, as the buckets they are the union of.
let category_families : Array[(String, Array[Int32])] = [
  ("L", [0, 1, 2, 3, 4]),
  ("Letter", [0, 1, 2, 3, 4]),
  ("M", [5, 6, 7]),
  ("Mark", [5, 6, 7]),
  ("N", [8, 9, 10]),
  ("Number", [8, 9, 10]),
  ("P", [11, 12, 13, 14, 15, 16, 17]),
  ("Punctuation", [11, 12, 13, 14, 15, 16, 17]),
  ("S", [18, 19, 20, 21]),
  ("Symbol", [18, 19, 20, 21]),
  ("Z", [22, 23, 24]),
  ("Separator", [22, 23, 24]),
  ("C", [25, 26, 27, 28, 29]),
  ("Other", [25, 26, 27, 28, 29]),
]

///|
/// Derive every general category in one walk of the code space.
fn ensure_categories() -> Unit {
  if derived_state[0] {
    return
  }
  derived_state[0] = true
  let buckets : Array[Array[(Int32, Int32)]] = []
  let open : Array[(Int32, Int32)?] = []
  let mut i = 0
  while i < 30 {
    buckets.push([])
    open.push(None)
    i += 1
  }
  let mut cp = 0
  while cp <= 0x10FFFF {
    let code = category_code(@moonucd.category(cp.unsafe_to_char()))
    match open[code] {
      None => open[code] = Some((cp, cp))
      Some((lo, hi)) =>
        if cp == hi + 1 {
          open[code] = Some((lo, cp))
        } else {
          buckets[code].push((lo, hi))
          open[code] = Some((cp, cp))
        }
    }
    cp += 1
  }
  let mut i = 0
  while i < 30 {
    match open[i] {
      None => ()
      Some((lo, hi)) => buckets[i].push((lo, hi))
    }
    i += 1
  }
  let mut i = 0
  while i < 30 {
    let set = CharSet::of(buckets[i])
    derived[normalise_name(category_short[i])] = set
    derived[normalise_name(category_long[i])] = set
    i += 1
  }
  for (name, parts) in category_families {
    let mut set = CharSet::empty()
    for part in parts {
      set = set.union(CharSet::of(buckets[part]))
    }
    derived[normalise_name(name)] = set
  }
}

// ---------------------------------------------------------------------------
// Scripts
// ---------------------------------------------------------------------------

///|
/// Derive every script in one walk: the script changes rarely, so the name is
/// only asked for when it does.
fn ensure_scripts() -> Unit {
  if derived_state[1] {
    return
  }
  derived_state[1] = true
  let buckets : Map[String, Array[(Int32, Int32)]] = Map([])
  let mut open : (Int32, Int32)? = None
  let mut open_name = ""
  let mut last : @script.Script? = None
  let mut cp = 0
  while cp <= 0x10FFFF {
    let s = @script.script(cp.unsafe_to_char())
    let changed = match last {
      None => true
      Some(prev) => s != prev
    }
    if changed {
      match open {
        Some((lo, hi)) => push_range(buckets, open_name, (lo, hi))
        None => ()
      }
      open_name = normalise_name(@script.Script::to_string(s))
      open = Some((cp, cp))
      last = Some(s)
    } else {
      open = Some((open.unwrap().0, cp))
    }
    cp += 1
  }
  match open {
    Some((lo, hi)) => push_range(buckets, open_name, (lo, hi))
    None => ()
  }
  for name, ranges in buckets {
    derived[name] = CharSet::of(ranges)
  }
}

///|
/// Add a range to the bucket for `name`, opening it if this is the first.
fn push_range(
  buckets : Map[String, Array[(Int32, Int32)]],
  name : String,
  range : (Int32, Int32),
) -> Unit {
  match buckets.get(name) {
    None => buckets[name] = [range]
    Some(ranges) => ranges.push(range)
  }
}

// ---------------------------------------------------------------------------
// Blocks
// ---------------------------------------------------------------------------

///|
/// Derive every block in one walk, the same way as the scripts.
fn ensure_blocks() -> Unit {
  if derived_state[2] {
    return
  }
  derived_state[2] = true
  let buckets : Map[String, Array[(Int32, Int32)]] = Map([])
  let mut open : (Int32, Int32)? = None
  let mut open_name = ""
  let mut last : String? = None
  let mut cp = 0
  while cp <= 0x10FFFF {
    let b = @block.block(cp.unsafe_to_char())
    let changed = match (last, b) {
      (None, None) => false
      (Some(a), Some(c)) => a != c
      _ => true
    }
    if changed {
      match open {
        Some((lo, hi)) => push_range(buckets, open_name, (lo, hi))
        None => ()
      }
      open_name = normalise_name(b.unwrap_or(""))
      open = Some((cp, cp))
      last = b
    } else {
      open = Some((open.unwrap().0, cp))
    }
    cp += 1
  }
  match open {
    Some((lo, hi)) => push_range(buckets, open_name, (lo, hi))
    None => ()
  }
  for name, ranges in buckets {
    derived[name] = CharSet::of(ranges)
  }
}

// ---------------------------------------------------------------------------
// Binary properties
// ---------------------------------------------------------------------------

///|
/// The binary properties, under the long and the short name the UCD gives
/// them.
let binary_names : Array[(String, @moonucd.Property)] = [
  ("Alphabetic", @moonucd.Alphabetic),
  ("Alpha", @moonucd.Alphabetic),
  ("Lowercase", @moonucd.Lowercase),
  ("Lower", @moonucd.Lowercase),
  ("Uppercase", @moonucd.Uppercase),
  ("Upper", @moonucd.Uppercase),
  ("Cased", @moonucd.Cased),
  ("Case_Ignorable", @moonucd.CaseIgnorable),
  ("CI", @moonucd.CaseIgnorable),
  ("Changes_When_Lowercased", @moonucd.ChangesWhenLowercased),
  ("CWL", @moonucd.ChangesWhenLowercased),
  ("Changes_When_Uppercased", @moonucd.ChangesWhenUppercased),
  ("CWU", @moonucd.ChangesWhenUppercased),
  ("Changes_When_Titlecased", @moonucd.ChangesWhenTitlecased),
  ("CWT", @moonucd.ChangesWhenTitlecased),
  ("Changes_When_Casefolded", @moonucd.ChangesWhenCasefolded),
  ("CWCF", @moonucd.ChangesWhenCasefolded),
  ("Changes_When_Casemapped", @moonucd.ChangesWhenCasemapped),
  ("CWCM", @moonucd.ChangesWhenCasemapped),
  ("ID_Start", @moonucd.IdStart),
  ("IDS", @moonucd.IdStart),
  ("ID_Continue", @moonucd.IdContinue),
  ("IDC", @moonucd.IdContinue),
  ("XID_Start", @moonucd.XidStart),
  ("XIDS", @moonucd.XidStart),
  ("XID_Continue", @moonucd.XidContinue),
  ("XIDC", @moonucd.XidContinue),
  ("Default_Ignorable_Code_Point", @moonucd.DefaultIgnorableCodePoint),
  ("DI", @moonucd.DefaultIgnorableCodePoint),
  ("Grapheme_Extend", @moonucd.GraphemeExtend),
  ("Gr_Ext", @moonucd.GraphemeExtend),
  ("Grapheme_Base", @moonucd.GraphemeBase),
  ("Gr_Base", @moonucd.GraphemeBase),
  ("Math", @moonucd.Math),
  ("White_Space", @moonucd.WhiteSpace),
  ("WSpace", @moonucd.WhiteSpace),
  ("space", @moonucd.WhiteSpace),
  ("Bidi_Control", @moonucd.BidiControl),
  ("Bidi_C", @moonucd.BidiControl),
  ("Join_Control", @moonucd.JoinControl),
  ("Join_C", @moonucd.JoinControl),
  ("Dash", @moonucd.Dash),
  ("Hyphen", @moonucd.Hyphen),
  ("Quotation_Mark", @moonucd.QuotationMark),
  ("QMark", @moonucd.QuotationMark),
  ("Terminal_Punctuation", @moonucd.TerminalPunctuation),
  ("Term", @moonucd.TerminalPunctuation),
  ("Hex_Digit", @moonucd.HexDigit),
  ("Hex", @moonucd.HexDigit),
  ("ASCII_Hex_Digit", @moonucd.AsciiHexDigit),
  ("AHex", @moonucd.AsciiHexDigit),
  ("Ideographic", @moonucd.Ideographic),
  ("Ideo", @moonucd.Ideographic),
  ("Diacritic", @moonucd.Diacritic),
  ("Dia", @moonucd.Diacritic),
  ("Extender", @moonucd.Extender),
  ("Ext", @moonucd.Extender),
  ("Noncharacter_Code_Point", @moonucd.NoncharacterCodePoint),
  ("NChar", @moonucd.NoncharacterCodePoint),
  ("IDS_Binary_Operator", @moonucd.IdsBinaryOperator),
  ("IDSB", @moonucd.IdsBinaryOperator),
  ("IDS_Trinary_Operator", @moonucd.IdsTrinaryOperator),
  ("IDST", @moonucd.IdsTrinaryOperator),
  ("Radical", @moonucd.Radical),
  ("Unified_Ideograph", @moonucd.UnifiedIdeograph),
  ("UIdeo", @moonucd.UnifiedIdeograph),
  ("Deprecated", @moonucd.Deprecated),
  ("Dep", @moonucd.Deprecated),
  ("Soft_Dotted", @moonucd.SoftDotted),
  ("SD", @moonucd.SoftDotted),
  ("Logical_Order_Exception", @moonucd.LogicalOrderException),
  ("LOE", @moonucd.LogicalOrderException),
  ("Sentence_Terminal", @moonucd.SentenceTerminal),
  ("STerm", @moonucd.SentenceTerminal),
  ("Variation_Selector", @moonucd.VariationSelector),
  ("VS", @moonucd.VariationSelector),
  ("Pattern_White_Space", @moonucd.PatternWhiteSpace),
  ("Pat_WS", @moonucd.PatternWhiteSpace),
  ("Pattern_Syntax", @moonucd.PatternSyntax),
  ("Pat_Syn", @moonucd.PatternSyntax),
  ("Prepended_Concatenation_Mark", @moonucd.PrependedConcatenationMark),
  ("PCM", @moonucd.PrependedConcatenationMark),
  ("Regional_Indicator", @moonucd.RegionalIndicator),
  ("RI", @moonucd.RegionalIndicator),
  ("Emoji", @moonucd.Emoji),
  ("Emoji_Presentation", @moonucd.EmojiPresentation),
  ("EPres", @moonucd.EmojiPresentation),
  ("Emoji_Modifier", @moonucd.EmojiModifier),
  ("EMod", @moonucd.EmojiModifier),
  ("Emoji_Modifier_Base", @moonucd.EmojiModifierBase),
  ("EBase", @moonucd.EmojiModifierBase),
  ("Emoji_Component", @moonucd.EmojiComponent),
  ("EComp", @moonucd.EmojiComponent),
  ("Extended_Pictographic", @moonucd.ExtendedPictographic),
  ("ExtPict", @moonucd.ExtendedPictographic),
]

///|
/// Derive one binary property over the whole code space.
fn ensure_binary(name : String, property : @moonucd.Property) -> CharSet {
  match derived.get(name) {
    Some(set) => set
    None => {
      let ranges : Array[(Int32, Int32)] = []
      let mut open : (Int32, Int32)? = None
      let mut cp = 0
      while cp <= 0x10FFFF {
        if @moonucd.has(cp.unsafe_to_char(), property) {
          match open {
            None => open = Some((cp, cp))
            Some((lo, hi)) =>
              if cp == hi + 1 {
                open = Some((lo, cp))
              } else {
                ranges.push((lo, hi))
                open = Some((cp, cp))
              }
          }
        }
        cp += 1
      }
      match open {
        Some((lo, hi)) => ranges.push((lo, hi))
        None => ()
      }
      let set = CharSet::of(ranges)
      derived[name] = set
      set
    }
  }
}

///|
/// A binary property by name.
fn binary_of(name : String) -> CharSet? {
  for (key, property) in binary_names {
    if normalise_name(key) == name {
      return Some(ensure_binary(name, property))
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Case folding
// ---------------------------------------------------------------------------

///|
/// Derive the simple case folds: the code points the UCD says change under
/// casefolding, and what each one folds to. Multi-code-point folds (`ß` to
/// `ss`) are left out — a class holds code points, not strings.
fn ensure_fold() -> Unit {
  if derived_state[3] {
    return
  }
  derived_state[3] = true
  let mut cp = 0
  while cp <= 0x10FFFF {
    let c = cp.unsafe_to_char()
    if @moonucd.has(c, @moonucd.ChangesWhenCasefolded) {
      let folded = @moonucd.fold(c.to_string())
      let chars : Array[Char] = []
      for ch in folded {
        chars.push(ch)
      }
      if chars.length() == 1 && chars[0].to_int() != cp {
        fold_source.push(cp)
        fold_target.push(chars[0].to_int())
      }
    }
    cp += 1
  }
}

///|
/// The simple fold of a code point; a code point with no fold is its own.
pub fn fold(c : Char) -> Char {
  ensure_fold()
  let cp = c.to_int()
  let mut lo = 0
  let mut hi = fold_source.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let src = fold_source[mid]
    if cp < src {
      hi = mid - 1
    } else if cp > src {
      lo = mid + 1
    } else {
      return fold_target[mid].unsafe_to_char()
    }
  }
  c
}

///|
/// The fold pairs, sorted by source — what a class is closed under.
pub fn fold_pairs() -> Array[(Int32, Int32)] {
  ensure_fold()
  let out : Array[(Int32, Int32)] = []
  let mut i = 0
  while i < fold_source.length() {
    out.push((fold_source[i], fold_target[i]))
    i += 1
  }
  out
}

// ---------------------------------------------------------------------------
// The names \p{…} accepts
// ---------------------------------------------------------------------------

///|
/// A general category: `L`, `Lu`, `Uppercase_Letter`, `casedletter`.
pub fn category(name : StringView) -> CharSet? {
  let key = normalise_name(name)
  ensure_categories()
  derived.get(key)
}

///|
/// A binary property: `Alphabetic`, `White_Space`, `Emoji`.
pub fn binary(name : StringView) -> CharSet? {
  binary_of(normalise_name(name))
}

///|
/// A script: `Latin`, `Latn`, `Han`.
///
/// The short code and the long name are one name to the UCD, so the name is
/// resolved through the UCD's own reader first and only then looked up.
pub fn script(name : StringView) -> CharSet? {
  match @script.Script::of(name) {
    Some(s) => {
      ensure_scripts()
      match derived.get(normalise_name(@script.Script::to_string(s))) {
        Some(set) => Some(set)
        None => None
      }
    }
    None => {
      let key = normalise_name(name)
      ensure_scripts()
      derived.get(key)
    }
  }
}

///|
/// A block: `Basic Latin`, `BasicLatin`, `CJK Unified Ideographs`.
///
/// A block is one range, so the usual answer needs no walk at all; the walk is
/// only for spellings the UCD's reader does not take.
pub fn block(name : StringView) -> CharSet? {
  match @block.range(name) {
    Some((lo, hi)) => Some(CharSet::of([(lo.to_int(), hi.to_int())]))
    None => {
      let key = normalise_name(name)
      ensure_blocks()
      derived.get(key)
    }
  }
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
      let v = value
      if k == "gc" || k == "generalcategory" {
        category(v)
      } else if k == "sc" || k == "script" {
        script(v)
      } else if k == "scx" || k == "scriptextensions" {
        script(v)
      } else if k == "blk" || k == "block" {
        block(v)
      } else if k == "binary" || k == "property" {
        binary(v)
      } else {
        None
      }
    }
  }
}

///|
/// Look a bare name up across the tables, in the order that disambiguates.
fn by_name(name : StringView) -> CharSet? {
  match category(name) {
    Some(set) => Some(set)
    None =>
      match script(name) {
        Some(set) => Some(set)
        None =>
          match block(name) {
            Some(set) => Some(set)
            None =>
              match binary(name) {
                Some(set) => Some(set)
                None =>
                  // One spelling that is not a Unicode property name but is
                  // written like one everywhere else.
                  if normalise_name(name) == "any" {
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
/// The code point a Unicode character name denotes — what `\N{name}` answers
/// from. Names are read loosely, the way `unicodedata.lookup` reads them.
pub fn char_of_name(name : StringView) -> Int32? {
  match @name.lookup(name) {
    Some(c) => Some(c.to_int())
    None => None
  }
}

// ---------------------------------------------------------------------------
// The sets the grammar needs by name
// ---------------------------------------------------------------------------

///|
/// `\w` under the Python and mrab spellings: letters, numbers and the
/// underscore. Python's own words for it are "alphanumeric (as `str.isalnum`
/// has it) plus `_`", which is exactly these categories.
pub fn word() -> CharSet {
  let letters = category("l").unwrap_or(CharSet::empty())
  let numbers = category("n").unwrap_or(CharSet::empty())
  letters.union(numbers).union(CharSet::single('_'.to_int()))
}

///|
/// `\d`: decimal digits, and only those.
pub fn digit() -> CharSet {
  category("nd").unwrap_or(CharSet::empty())
}

///|
/// `\s`: the White_Space property.
pub fn space() -> CharSet {
  binary("whitespace").unwrap_or(CharSet::empty())
}

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
