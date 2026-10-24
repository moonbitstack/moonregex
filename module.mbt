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
pub fn match_at(
  pattern : StringView,
  text : String,
  flags~ : @parse.Flags = @parse.flags,
  dialect~ : @parse.Dialect = @parse.Python,
  pos~ : Int32 = 0,
  limit~ : Int32 = 10000000,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> Match? raise @parse.Refused {
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).match_at(
    text,
    pos~,
    limit~,
  )
}

///|
/// Match the whole region `pos..endpos` (Python's `re.fullmatch`).
pub fn fullmatch(
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
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).fullmatch(
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
/// Replace matches with the result of `f(match)`, as Python's `re.sub` with a
/// callable replacement.
pub fn sub_by(
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
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).subn_by(
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
pub fn subn_by(
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
  compile(pattern, flags~, dialect~, lists=lists.unwrap_or({}), partial~).subn_by(
    text,
    f,
    count~,
    pos~,
    endpos~,
    limit~,
  )
}

///|
/// Escape regex metacharacters in `pattern`, as Python's `re.escape`.
///
/// With `special_only` (the preset) only the characters the grammar treats as
/// special are escaped; with it off, everything that is not a letter or digit
/// is. `literal_spaces` leaves spaces unescaped, for callers building a pattern
/// out of literal fragments.
pub fn escape(
  pattern : StringView,
  special_only~ : Bool = true,
  literal_spaces~ : Bool = false,
) -> String {
  let buf = StringBuilder::StringBuilder()
  for c in pattern {
    let code = c.to_int()
    let is_alnum = (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
      (code >= 'A'.to_int() && code <= 'Z'.to_int()) ||
      (code >= '0'.to_int() && code <= '9'.to_int())
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
    } else if special_only && !is_special(c) {
      buf.write_char(c)
    } else {
      buf.write_char('\\')
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn is_special(c : Char) -> Bool {
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
  c == '#'
}

// ---------------------------------------------------------------------------
// Flag constants & module aliases (Python `re` / `regex` surface)
// ---------------------------------------------------------------------------

///|
/// The error the engine raises for a bad pattern or a run that hit its step
/// ceiling — the MoonBit spelling of Python's `regex.error` (type names are
/// upper-case here).
pub type RegexError = @parse.Refused

///|
/// The flag type, for callers who build flags by name (the `RegexFlag` alias of
/// Python's `regex` module).
pub type RegexFlag = @parse.Flags

// MoonBit constrains `let` bindings to lower-case names and `const` to primitive
// types, so the Python `re` flag constants (which are upper-case) are exposed
// here under their lower-case spelling — `i`/`ignorecase`, `m`/`multiline`, and
// so on — each a `Flags` value, so a caller ports a pattern flag-for-flag.

///|
pub let i : RegexFlag = @parse.Flags::new(ignorecase=true)

///|
/// `ignorecase` — Python's `re.IGNORECASE`.
pub let ignorecase : RegexFlag = i

///|
pub let m : RegexFlag = @parse.Flags::new(multiline=true)

///|
/// `multiline` — Python's `re.MULTILINE`.
pub let multiline : RegexFlag = m

///|
pub let s : RegexFlag = @parse.Flags::new(dotall=true)

///|
/// `dotall` — Python's `re.DOTALL`.
pub let dotall : RegexFlag = s

///|
pub let x : RegexFlag = @parse.Flags::new(verbose=true)

///|
/// `verbose` — Python's `re.VERBOSE`.
pub let verbose : RegexFlag = x

///|
pub let a : RegexFlag = @parse.Flags::new(ascii=true)

///|
/// `ascii` — Python's `re.ASCII`.
pub let ascii : RegexFlag = a

///|
pub let u : RegexFlag = @parse.Flags::new(unicode=true)

///|
/// `unicode` — Python's `re.UNICODE`.
pub let unicode : RegexFlag = u

///|
pub let f : RegexFlag = @parse.Flags::new(fullcase=true)

///|
/// `fullcase` — Python's `re.FULLCASE`.
pub let fullcase : RegexFlag = f

///|
pub let w : RegexFlag = @parse.Flags::new(word=true)

///|
/// `word` — `regex.WORD`.
pub let word : RegexFlag = w

///|
pub let t : RegexFlag = @parse.Flags::new()

///|
/// `template` — Python's `re.TEMPLATE` (no implicit flags).
pub let template_flag : RegexFlag = t

///|
pub let b : RegexFlag = @parse.Flags::new(bestmatch=true)

///|
/// `bestmatch` — `regex.BESTMATCH`.
pub let bestmatch : RegexFlag = b

///|
pub let e : RegexFlag = @parse.Flags::new(enhancematch=true)

///|
/// `enhancematch` — `regex.ENHANCEMATCH`.
pub let enhancematch : RegexFlag = e

///|
pub let r : RegexFlag = @parse.Flags::new(reverse=true)

///|
/// `reverse` — `regex.REVERSE`.
pub let reverse : RegexFlag = r

///|
pub let p : RegexFlag = @parse.Flags::new(posix=true)

///|
/// `posix` — `regex.POSIX`.
pub let posix : RegexFlag = p

///|
pub let v0 : RegexFlag = @parse.Flags::new(version=@parse.V0)

///|
/// `version0` — `regex.VERSION0`.
pub let version0 : RegexFlag = v0

///|
pub let v1 : RegexFlag = @parse.Flags::new(version=@parse.V1)

///|
/// `version1` — `regex.VERSION1`.
pub let version1 : RegexFlag = v1

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
/// Clear the compiled-pattern cache. `moonregex` compiles on demand and keeps
/// no cache, so this is a no-op kept for drop-in API compatibility.
pub fn purge() -> Unit {
  ()
}

///|
/// Compile with no grammar flags, as `re.template` does (deprecated in Python;
/// kept for compatibility).
pub fn template(
  pattern : StringView,
  dialect~ : @parse.Dialect = @parse.Python,
  lists? : Map[String, Array[String]],
  partial~ : Bool = false,
) -> Pattern raise @parse.Refused {
  compile(
    pattern,
    flags=@parse.flags,
    dialect~,
    lists=lists.unwrap_or({}),
    partial~,
  )
}
