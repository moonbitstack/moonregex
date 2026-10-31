// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The Unicode answers `\p{…}` is made of.
///
/// Every set here is a table `moonucd` already generated from the Unicode
/// Character Database, read as ranges: a category, a binary property, a script
/// and a block are one lookup each, so nothing below walks the code space, and
/// a set is built at most once and then kept.

///|
/// Which Unicode the answers follow.
pub fn version() -> String {
  @moonucd.version()
}

///|
/// The sets already built, by normalised name: a pattern asks for the same
/// family more than once, and building one sorts a few thousand ranges.
let sets : Map[String, CharSet] = Map([])

///|
/// The set `build` makes, kept under `key` once it is made.
fn memo(key : String, build : () -> CharSet?) -> CharSet? {
  match sets.get(key) {
    Some(set) => Some(set)
    None =>
      match build() {
        Some(set) => {
          sets[key] = set
          Some(set)
        }
        None => None
      }
  }
}

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
/// The general categories in UCD order, under the two-letter name and under
/// the long one the standard also gives them.
let category_short : Array[String] = [
  "Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd", "Nl", "No", "Pc", "Pd", "Ps",
  "Pe", "Pi", "Pf", "Po", "Sm", "Sc", "Sk", "So", "Zs", "Zl", "Zp", "Cc", "Cf", "Cs",
  "Co", "Cn",
]

///|
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
let categories : Array[@moonucd.Category] = [
  @moonucd.Lu,
  @moonucd.Ll,
  @moonucd.Lt,
  @moonucd.Lm,
  @moonucd.Lo,
  @moonucd.Mn,
  @moonucd.Mc,
  @moonucd.Me,
  @moonucd.Nd,
  @moonucd.Nl,
  @moonucd.No,
  @moonucd.Pc,
  @moonucd.Pd,
  @moonucd.Ps,
  @moonucd.Pe,
  @moonucd.Pi,
  @moonucd.Pf,
  @moonucd.Po,
  @moonucd.Sm,
  @moonucd.Sc,
  @moonucd.Sk,
  @moonucd.So,
  @moonucd.Zs,
  @moonucd.Zl,
  @moonucd.Zp,
  @moonucd.Cc,
  @moonucd.Cf,
  @moonucd.Cs,
  @moonucd.Co,
  @moonucd.Cn,
]

///|
/// The one-letter families, as the categories they are the union of.
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
/// A general category: `L`, `Lu`, `Uppercase_Letter`, `casedletter`.
pub fn category(name : StringView) -> CharSet? {
  let key = normalise_name(name)
  memo(key, fn() {
    for i, short in category_short {
      if normalise_name(short) == key || normalise_name(category_long[i]) == key {
        return Some(CharSet::of(categories[i].ranges()))
      }
    }
    for (family, parts) in category_families {
      if normalise_name(family) == key {
        let ranges : Array[(Int32, Int32)] = []
        for part in parts {
          for range in categories[part].ranges() {
            ranges.push(range)
          }
        }
        return Some(CharSet::of(ranges))
      }
    }
    None
  })
}

// ---------------------------------------------------------------------------
// Scripts and blocks
// ---------------------------------------------------------------------------

///|
/// A script: `Latin`, `Latn`, `Han`.
///
/// The short code and the long name are one name to the UCD, so its own reader
/// resolves the name and the table answers with that script's ranges.
pub fn script(name : StringView) -> CharSet? {
  memo(normalise_name(name), fn() {
    match @script.Script::of(name) {
      Some(s) => Some(CharSet::of(s.ranges()))
      None => None
    }
  })
}

///|
/// A block: `Basic Latin`, `BasicLatin`, `CJK Unified Ideographs`.
///
/// A block is one range, so the usual answer needs no table of its own.
pub fn block(name : StringView) -> CharSet? {
  match @block.range(name) {
    Some((lo, hi)) => Some(CharSet::of([(lo.to_int(), hi.to_int())]))
    None => None
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
/// A binary property by name.
fn binary_of(name : String) -> CharSet? {
  memo(name, fn() {
    for (key, property) in binary_names {
      if normalise_name(key) == name {
        return Some(CharSet::of(property.ranges()))
      }
    }
    None
  })
}

// ---------------------------------------------------------------------------
// Case folding
// ---------------------------------------------------------------------------

///|
/// The simple fold of a code point: the one character it becomes when case
/// stops counting. A code point whose fold is longer than one character, `ß`
/// to `ss`, is its own, since a class holds code points, not strings.
pub fn fold(c : Char) -> Char {
  @moonucd.simple_fold(c)
}

///|
/// The pair list, kept once it is built: a pattern closes many classes under
/// case, and every one of them reads the same pairs.
let fold_pair_cache : Array[(Int32, Int32)] = []

///|
/// Whether it has been built yet.
let fold_pair_ready : Array[Bool] = [false]

///|
/// The fold pairs both ways, sorted by source — what a class is closed under.
///
/// The code points that change under casefolding are the ones a class grows
/// from, and each of them brings its whole fold class with it, so the pairs
/// come out of the orbit table instead of a walk of the code space.
pub fn fold_pairs() -> Array[(Int32, Int32)] {
  if !fold_pair_ready[0] {
    fold_pair_ready[0] = true
    for (lo, hi) in @moonucd.ChangesWhenCasefolded.ranges() {
      for cp in lo..<(hi + 1) {
        let orbit = @moonucd.fold_orbit(cp.unsafe_to_char())
        for x in orbit {
          for y in orbit {
            if x != y {
              fold_pair_cache.push((x.to_int(), y.to_int()))
            }
          }
        }
      }
    }
  }
  fold_pair_cache.copy()
}

// ---------------------------------------------------------------------------
// The names \p{…} accepts
// ---------------------------------------------------------------------------

///|
/// A binary property: `Alphabetic`, `White_Space`, `Emoji`.
pub fn binary(name : StringView) -> CharSet? {
  binary_of(normalise_name(name))
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
