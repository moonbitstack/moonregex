// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A group, as Python's `re` lets you name it: the whole match, a number, or a
/// name. `Whole` is the preset every group-accepting call falls back to.
pub(all) enum GroupKey {
  /// Group 0, the whole match.
  Whole
  /// A group by number; 1 is the first parenthesis, 0 the whole match.
  Num(n~ : Int32)
  /// A group by name.
  Name(n~ : String)
}

///|
/// The preset flags, for callers who want to tweak one and keep the rest.
pub let flags : @parse.Flags = @parse.flags

///|
/// The preset dialect: Python's `re`.
pub let dialect : @parse.Dialect = @parse.dialect

///|
/// The flags type, re-exported so a caller needs only this package.
pub type Flags = @parse.Flags

///|
pub type Dialect = @parse.Dialect

///|
pub type Version = @parse.Version

///|
/// The Python `re` dialect — the default, and the one most callers want.
pub let python : Dialect = @parse.Python

///|
/// The ECMA-262 `RegExp` dialect — JSON Schema and OpenAPI "string" patterns.
pub let ecma262 : Dialect = @parse.Ecma262

///|
/// The MoonBit `lexmatch` dialect — `@string.Regex` and the lexer.
pub let lexmatch_dialect : Dialect = @parse.Lexmatch

///|
/// The error the grammar and engine raise when a pattern cannot be read or a
/// group the pattern does not have is asked for.
pub type Refused = @parse.Refused

///|
/// Compile `pattern` into a `Pattern`.
///
/// `flags` and `dialect` set the grammar; `lists` feeds `\L<name>` named lists;
/// `partial` turns on partial matching. A pattern the grammar refuses is refused
/// here, with where reading stopped.
pub fn compile(
  pattern : StringView,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> Pattern raise @parse.Refused {
  let ast = @parse.parse(pattern, flags~, dialect~, lists=lists.unwrap_or({}))
  let program = @exec.compile(ast)
  Pattern::{ pat: pattern.to_owned(), flags, dialect, ast, program, partial, }
}

///|
/// Scan `text` for the leftmost match, as Python's `re.search`.
pub fn search(
  pattern : StringView,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> Match? raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).search(
    text,
    pos~,
    endpos~,
    limit~,
  )
}

///|
/// Match only at `pos` (Python's `re.match`): fail unless the pattern matches
/// where the scan begins, not somewhere later in the text.
pub fn prefix(
  pattern : StringView,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  pos~ : Int32 = 0,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> Match? raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).prefix(
    text,
    pos~,
    limit~,
  )
}

///|
/// Match the whole region `pos..endpos` (Python's `re.fullmatch`).
pub fn full(
  pattern : StringView,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> Match? raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).full(
    text,
    pos~,
    endpos~,
    limit~,
  )
}

///|
/// All non-overlapping matches, as Python's `re.findall`.
///
/// With no group named and the pattern holding one or none, the matches (or the
/// single group) are returned. With two or more groups and no `group` given, the
/// call is ambiguous and refused — pass `group` to say which to collect, or use
/// `finditer` to walk `Match` objects that carry them all.
pub fn findall(
  pattern : StringView,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  group~ : GroupKey = Whole,
  overlapped~ : Bool = false,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> Array[String?] raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).findall(
    text,
    group~,
    overlapped~,
    pos~,
    endpos~,
    limit~,
  )
}

///|
/// All matches as `Match` objects, as Python's `re.finditer`.
pub fn finditer(
  pattern : StringView,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  overlapped~ : Bool = false,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> Array[Match] raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).finditer(
    text,
    pos~,
    endpos~,
    overlapped~,
    limit~,
  )
}

///|
/// Split `text` on the pattern, as Python's `re.split`.
pub fn split(
  pattern : StringView,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  maxsplit~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> Array[String?] raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).split(
    text,
    maxsplit~,
    pos~,
    endpos~,
    limit~,
  )
}

///|
/// Replace matches with `repl`, as Python's `re.sub`.
pub fn sub(
  pattern : StringView,
  repl : String,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> String raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).sub(
    text,
    repl,
    count~,
    pos~,
    endpos~,
    limit~,
  )
}

///|
/// Replace matches with `repl`, returning the new text and how many matches
/// were replaced, as Python's `re.subn`.
pub fn subn(
  pattern : StringView,
  repl : String,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> (String, Int32) raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).subn(
    text,
    repl,
    count~,
    pos~,
    endpos~,
    limit~,
  )
}

///|
/// Replace matches with `repl`, as `regex.subf` — `repl` is a format template
/// whose fields name groups (`{}`, `{0}`, `{name}`, `{0[0]}`).
pub fn subf(
  pattern : StringView,
  repl : String,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> String raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).subf(
    text,
    repl,
    count~,
    pos~,
    endpos~,
    limit~,
  )
}

///|
/// Replace matches with `repl`, returning the new text and the count, as
/// `regex.subfn`.
pub fn subfn(
  pattern : StringView,
  repl : String,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> (String, Int32) raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).subfn(
    text,
    repl,
    count~,
    pos~,
    endpos~,
    limit~,
  )
}

///|
/// Replace matches with the result of `f(match)`, as Python's `re.sub` with a
/// callable replacement.
pub fn sub_with(
  pattern : StringView,
  f : (Match) -> String raise @parse.Refused,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> String raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).subn_with(
    text,
    f,
    count~,
    pos~,
    endpos~,
    limit~,
  ).0
}

///|
/// Replace matches with `f(match)`, returning the new text and the count, as
/// Python's `re.subn` with a callable replacement.
pub fn subn_with(
  pattern : StringView,
  f : (Match) -> String raise @parse.Refused,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  count~ : Int32 = 0,
  pos~ : Int32 = 0,
  endpos~ : Int32 = -1,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> (String, Int32) raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).subn_with(
    text,
    f,
    count~,
    pos~,
    endpos~,
    limit~,
  )
}

///|
/// Escape `pattern` so the result matches it literally, under `dialect`.
///
/// The three grammars do not agree on what needs escaping, so the same string
/// comes back spelled three ways:
///
/// - `Python` — Python's `re.escape`: the characters that can mean something to
///   the grammar are backslashed, everything else is left alone. With
///   `special_only` off every non-alphanumeric is escaped; `literal_spaces`
///   stops spaces from being escaped.
/// - `Ecma262` — `RegExp.escape` of ECMA-262: punctuation that is not a syntax
///   character becomes `\x..`, syntax characters are backslashed, and a
///   leading alphanumeric is spelled `\x..` too so the result can never read
///   as a quantifier's neighbour.
/// - `Lexmatch` — the `@string.Regex` grammar: its metacharacters are
///   backslashed and control characters are spelled in the escapes that
///   grammar knows (`\n`, `\t`, `\u{..}`), never `\x..`.
pub fn escape(
  pattern : StringView,
  dialect~ : @parse.Dialect = @parse.Python,
  special_only~ : Bool = true,
  literal_spaces~ : Bool = false,
) -> String {
  match dialect {
    @parse.Python => escape_python(pattern, special_only, literal_spaces)
    @parse.Ecma262 => escape_ecma(pattern)
    @parse.Lexmatch => escape_lexmatch(pattern, special_only)
  }
}

///|
/// Python's `re.escape`: a fixed set of characters carries a backslash.
fn escape_python(
  pattern : StringView,
  special_only : Bool,
  literal_spaces : Bool,
) -> String {
  let buf = StringBuilder::StringBuilder()
  for c in pattern {
    let code = c.to_int()
    let is_alnum = is_ascii_alnum(code)
    let is_space = code == 0x20 ||
      code == 0x09 ||
      code == 0x0A ||
      code == 0x0D ||
      code == 0x0B ||
      code == 0x0C
    if is_alnum {
      buf.write_char(c)
    } else if literal_spaces && is_space {
      buf.write_char(c)
    } else if special_only && !is_python_special(c) {
      buf.write_char(c)
    } else {
      buf.write_char('\\')
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// `RegExp.escape`: the spelling ECMA-262 settled on, whose point is that the
/// result is safe both as a pattern and as the text of one — no ambiguity
/// between a literal and a quantifier.
fn escape_ecma(pattern : StringView) -> String {
  let buf = StringBuilder::StringBuilder()
  let chars : Array[Char] = []
  for c in pattern {
    chars.push(c)
  }
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    let code = c.to_int()
    // A leading alphanumeric could fuse with a quantifier that follows the
    // escaped text, so the standard spells it out.
    if i == 0 && is_ascii_alnum(code) {
      buf.write_string(hex_escape(code, 2))
    } else {
      buf.write_string(encode_for_regexp_escape(code))
    }
    i += 1
  }
  buf.to_string()
}

///|
/// The `EncodeForRegExpEscape` table of ECMA-262.
fn encode_for_regexp_escape(code : Int32) -> String {
  match code {
    0x09 => "\\t"
    0x0A => "\\n"
    0x0B => "\\v"
    0x0C => "\\f"
    0x0D => "\\r"
    _ =>
      if is_ecma_syntax_char(code) {
        "\\" + code.unsafe_to_char().to_string()
      } else if is_ecma_other_punctuator(code) || code == 0x20 {
        hex_escape(code, 2)
      } else if code >= 0xD800 && code <= 0xDFFF {
        "\\u" + hex_digits(code, 4)
      } else {
        // Everything else stands for itself: the standard leaves letters,
        // digits and non-ASCII text alone.
        code.unsafe_to_char().to_string()
      }
  }
}

///|
/// `^ $ \ . * + ? ( ) [ ] { } |` and `/` — the characters a backslash alone
/// makes literal.
fn is_ecma_syntax_char(code : Int32) -> Bool {
  match code {
    0x5E
    | 0x24
    | 0x5C
    | 0x2E
    | 0x2A
    | 0x2B
    | 0x3F
    | 0x28
    | 0x29
    | 0x5B
    | 0x5D
    | 0x7B
    | 0x7D
    | 0x7C
    | 0x2F => true
    _ => false
  }
}

///|
/// `, - = < > # & ! % : ; @ ~ ' ` "` — punctuation the grammar does not read,
/// which the standard still spells out so the output is stable.
fn is_ecma_other_punctuator(code : Int32) -> Bool {
  match code {
    0x2C
    | 0x2D
    | 0x3D
    | 0x3C
    | 0x3E
    | 0x23
    | 0x26
    | 0x21
    | 0x25
    | 0x3A
    | 0x3B
    | 0x40
    | 0x7E
    | 0x27
    | 0x60
    | 0x22 => true
    _ => false
  }
}

///|
/// The `@string.Regex` grammar's escape: its metacharacters take a backslash,
/// and anything invisible is spelled in an escape that grammar knows.
fn escape_lexmatch(pattern : StringView, special_only : Bool) -> String {
  let buf = StringBuilder::StringBuilder()
  for c in pattern {
    let code = c.to_int()
    // Invisible characters first: the grammar spells them, it never carries
    // them raw.
    if code == 0x09 {
      buf.write_string("\\t")
    } else if code == 0x0A {
      buf.write_string("\\n")
    } else if code == 0x0B {
      buf.write_string("\\v")
    } else if code == 0x0C {
      buf.write_string("\\f")
    } else if code == 0x0D {
      buf.write_string("\\r")
    } else if is_lexmatch_special(code) {
      buf.write_char('\\')
      buf.write_char(c)
    } else if special_only || is_ascii_alnum(code) {
      buf.write_char(c)
    } else if code < 0x20 || code == 0x7F {
      buf.write_string("\\u{" + hex_digits(code, 0) + "}")
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn is_lexmatch_special(code : Int32) -> Bool {
  match code {
    0x5C
    | 0x2E
    | 0x2A
    | 0x2B
    | 0x3F
    | 0x28
    | 0x29
    | 0x5B
    | 0x5D
    | 0x7B
    | 0x7D
    | 0x7C
    | 0x5E
    | 0x24
    | 0x2D => true
    _ => false
  }
}

///|
fn is_ascii_alnum(code : Int32) -> Bool {
  (code >= 0x61 && code <= 0x7A) ||
  (code >= 0x41 && code <= 0x5A) ||
  (code >= 0x30 && code <= 0x39)
}

///|
/// `\x..`, with exactly `width` digits when `width` is non-zero.
fn hex_escape(code : Int32, width : Int32) -> String {
  "\\x" + hex_digits(code, width)
}

///|
/// Upper-case hex, zero-padded to `width` digits; `width` 0 means "as many as
/// the value needs".
fn hex_digits(value : Int32, width : Int32) -> String {
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
  while out.length() < width {
    out.push('0')
  }
  let buf = StringBuilder::StringBuilder()
  let mut i = out.length() - 1
  while i >= 0 {
    buf.write_char(out[i])
    i -= 1
  }
  buf.to_string()
}

///|
fn is_python_special(c : Char) -> Bool {
  c == '(' ||
  c == ')' ||
  c == '[' ||
  c == ']' ||
  c == '{' ||
  c == '}' ||
  c == '?' ||
  c == '*' ||
  c == '+' ||
  c == '-' ||
  c == '|' ||
  c == '^' ||
  c == '$' ||
  c == '\\' ||
  c == '.' ||
  c == '&' ||
  c == '~' ||
  c == '#' ||
  c == ' ' ||
  c == '\t' ||
  c == '\n' ||
  c == '\r' ||
  c == '\u{0B}' ||
  c == '\u{0C}'
}

// ---------------------------------------------------------------------------
// Flag constants & module aliases (Python `re` / `regex` surface)
// ---------------------------------------------------------------------------

// MoonBit constrains `let` bindings to lower-case names and `const` to primitive
// types, so the Python `re` flag constants (which are upper-case) are exposed
// here under their lower-case spelling — `i`/`ignorecase`, `m`/`multiline`, and
// so on — each a `Flags` value, so a caller ports a pattern flag-for-flag.

///|
pub let i : Flags = @parse.Flags::new(ignorecase=true)

///|
/// `ignorecase` — Python's `re.IGNORECASE`.
pub let ignorecase : Flags = i

///|
pub let m : Flags = @parse.Flags::new(multiline=true)

///|
/// `multiline` — Python's `re.MULTILINE`.
pub let multiline : Flags = m

///|
pub let s : Flags = @parse.Flags::new(dotall=true)

///|
/// `dotall` — Python's `re.DOTALL`.
pub let dotall : Flags = s

///|
pub let x : Flags = @parse.Flags::new(verbose=true)

///|
/// `verbose` — Python's `re.VERBOSE`.
pub let verbose : Flags = x

///|
pub let a : Flags = @parse.Flags::new(ascii=true)

///|
/// `ascii` — Python's `re.ASCII`.
pub let ascii : Flags = a

///|
pub let u : Flags = @parse.Flags::new(unicode=true)

///|
/// `unicode` — Python's `re.UNICODE`.
pub let unicode : Flags = u

///|
pub let f : Flags = @parse.Flags::new(fullcase=true)

///|
/// `fullcase` — Python's `re.FULLCASE`.
pub let fullcase : Flags = f

///|
pub let w : Flags = @parse.Flags::new(word=true)

///|
/// `word` — `regex.WORD`.
pub let word : Flags = w

///|
pub let b : Flags = @parse.Flags::new(bestmatch=true)

///|
/// `bestmatch` — `regex.BESTMATCH`.
pub let bestmatch : Flags = b

///|
pub let e : Flags = @parse.Flags::new(enhancematch=true)

///|
/// `enhancematch` — `regex.ENHANCEMATCH`.
pub let enhancematch : Flags = e

///|
pub let r : Flags = @parse.Flags::new(reverse=true)

///|
/// `reverse` — `regex.REVERSE`.
pub let reverse : Flags = r

///|
pub let p : Flags = @parse.Flags::new(posix=true)

///|
/// `posix` — `regex.POSIX`.
pub let posix : Flags = p

///|
pub let v0 : Flags = @parse.Flags::new(version=@parse.V0)

///|
/// `version0` — `regex.VERSION0`.
pub let version0 : Flags = v0

///|
pub let v1 : Flags = @parse.Flags::new(version=@parse.V1)

///|
/// `version1` — `regex.VERSION1`.
pub let version1 : Flags = v1

///|
/// The `V0` behaviour set, as a `Version` value — `regex.VERSION0`'s target.
pub let version0_value : @parse.Version = @parse.V0

///|
/// The `V1` behaviour set, as a `Version` value — `regex.VERSION1`'s target.
pub let version1_value : @parse.Version = @parse.V1

///|
/// The version the engine reads a Python pattern under when none is asked for.
pub let default_version : @parse.Version = @parse.V0

///|
/// The library version, as `regex.__version__` reports it.
pub let version : String = "0.1.0"

///|
/// The library version split into `(major, minor, patch)`, as
/// `regex.__version_info__` reports it.
pub let version_info : (Int32, Int32, Int32) = (0, 1, 0)
