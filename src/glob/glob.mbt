// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Turn a shell/fnmatch pattern into a regex fragment (no anchors).
///
/// `*` and `?` become `.*` and `.`; `[...]` becomes a character class (with `!`
/// or `^` for negation); `{a,b,c}` becomes an alternation; and `\` escapes the
/// next character. This is the `fnmatch` reading, where `*` may cross a path
/// separator.
pub fn translate(pattern : StringView) -> String {
  translate_impl(pattern, false)
}

///|
/// Whether `name` matches the shell pattern `pat`.
///
/// By default the match is case-sensitive (POSIX `fnmatch`). Pass
/// `ignorecase=true` to fold case first, the way `fnmatch` does on a
/// case-insensitive filesystem.
pub fn fnmatch(
  name : String,
  pat : StringView,
  ignorecase~ : Bool = false,
) -> Bool raise @moonregex.Refused {
  let re = "^" + translate_impl(pat, false) + "$"
  let flags = if ignorecase {
    @moonregex.Flags::new(ignorecase=true)
  } else {
    @moonregex.flags
  }
  @moonregex.fullmatch(re, name, flags~) is Some(_)
}

///|
/// `fnmatch` without any case folding — an exact, case-sensitive match.
pub fn fnmatchcase(
  name : String,
  pat : StringView,
) -> Bool raise @moonregex.Refused {
  fnmatch(name, pat, ignorecase=false)
}

///|
/// The names that match `pat`, in the order given (Python's `fnmatch.filter`).
pub fn filter(
  names : Array[String],
  pat : StringView,
  ignorecase~ : Bool = false,
) -> Array[String] raise @moonregex.Refused {
  let re = "^" + translate_impl(pat, false) + "$"
  let flags = if ignorecase {
    @moonregex.Flags::new(ignorecase=true)
  } else {
    @moonregex.flags
  }
  let p = @moonregex.compile(re, flags~, dialect=@moonregex.python)
  let out : Array[String] = []
  for name in names {
    if p.fullmatch(name) is Some(_) {
      out.push(name)
    }
  }
  out
}

///|
/// A compiled glob: a pattern plus the regex it became.
pub struct Glob {
  priv pattern : String
  priv regex : @moonregex.Pattern
}

///|
/// Compile a path glob.
///
/// `*` matches a run of characters that are not separators; `**` matches a run
/// that may include them (zero or more path segments); `?` matches one
/// non-separator character; `[...]` is a character class; `{a,b}` is an
/// alternation; and `\` escapes the next character. Both `/` and `\` are treated
/// as separators, so Windows and POSIX paths match the same pattern.
pub fn Glob::compile(
  pattern : StringView,
  ignorecase~ : Bool = false,
) -> Glob raise @moonregex.Refused {
  let norm = normalise_sep(pattern.to_owned())
  let body = translate_impl(norm, true)
  let re = "^" + body + "$"
  let flags = if ignorecase {
    @moonregex.Flags::new(ignorecase=true)
  } else {
    @moonregex.flags
  }
  let p = @moonregex.compile(re, flags~, dialect=@moonregex.python)
  Glob::{ pattern: pattern.to_owned(), regex: p, }
}

///|
/// Whether `path` matches the glob, as a whole anchored match.
pub fn Glob::matches(
  self : Glob,
  path : String,
) -> Bool raise @moonregex.Refused {
  let p = normalise_sep(path)
  self.regex.fullmatch(p) is Some(_)
}

///|
/// The pattern this glob was compiled from.
pub fn Glob::pattern(self : Glob) -> String {
  self.pattern
}

///|
/// A set of globs matched together — the workhorse behind an ignore file or a
/// list of include patterns.
pub struct GlobSet {
  priv globs : Array[Glob]
}

///|
/// Compile several patterns into one set.
pub fn GlobSet::compile(
  patterns : Array[String],
  ignorecase~ : Bool = false,
) -> GlobSet raise @moonregex.Refused {
  let gs : Array[Glob] = []
  for p in patterns {
    gs.push(Glob::compile(p, ignorecase~))
  }
  GlobSet::{ globs: gs, }
}

///|
/// Whether any pattern in the set matches `path`.
pub fn GlobSet::matches_any(
  self : GlobSet,
  path : String,
) -> Bool raise @moonregex.Refused {
  for g in self.globs {
    if g.matches(path) {
      return true
    }
  }
  false
}

///|
/// The indices of every pattern in the set that matches `path`.
pub fn GlobSet::matches(
  self : GlobSet,
  path : String,
) -> Array[Int32] raise @moonregex.Refused {
  let out : Array[Int32] = []
  for i = 0; i < self.globs.length(); i = i + 1 {
    if self.globs[i].matches(path) {
      out.push(i)
    }
  }
  out
}

///|
/// The patterns the set was compiled from, in order.
pub fn GlobSet::patterns(self : GlobSet) -> Array[String] {
  let out : Array[String] = []
  for g in self.globs {
    out.push(g.pattern)
  }
  out
}

///|
/// Match one `path` against one glob `pattern` (compiling the pattern inline).
pub fn match_path(
  path : String,
  pattern : StringView,
  ignorecase~ : Bool = false,
) -> Bool raise @moonregex.Refused {
  Glob::compile(pattern, ignorecase~).matches(path)
}

///|
/// The paths that match the glob `pattern`, in the order given.
pub fn filter_paths(
  paths : Array[String],
  pattern : StringView,
  ignorecase~ : Bool = false,
) -> Array[String] raise @moonregex.Refused {
  let g = Glob::compile(pattern, ignorecase~)
  let out : Array[String] = []
  for p in paths {
    if g.matches(p) {
      out.push(p)
    }
  }
  out
}

///|
/// A regex metacharacter must be escaped when carried over literally.
fn is_regex_special(code : Int32) -> Bool {
  code == '.'.to_int() ||
  code == '^'.to_int() ||
  code == '$'.to_int() ||
  code == '*'.to_int() ||
  code == '+'.to_int() ||
  code == '?'.to_int() ||
  code == '('.to_int() ||
  code == ')'.to_int() ||
  code == '['.to_int() ||
  code == ']'.to_int() ||
  code == '{'.to_int() ||
  code == '}'.to_int() ||
  code == '|'.to_int() ||
  code == '\\'.to_int()
}

///|
/// Write one literal character, escaping it if the regex would read it as syntax.
fn write_literal(buf : StringBuilder, c : UInt16) -> Unit {
  if is_regex_special(c.to_int()) {
    buf.write_char('\\')
  }
  buf.write_char(c.unsafe_to_char())
}

///|
/// Translate a pattern to a regex fragment. `pathname` decides whether `*` and
/// `?` may cross a separator: `fnmatch` lets them, `Glob` does not.
fn translate_impl(pat : StringView, pathname : Bool) -> String {
  let buf = StringBuilder::StringBuilder()
  let n = pat.length()
  let mut i = 0
  while i < n {
    let code = pat.at(i).to_int()
    if code == '*'.to_int() {
      if pathname && i + 1 < n && pat.at(i + 1).to_int() == '*'.to_int() {
        // `**`: coupled to a following slash, it spans whole directories.
        if i + 2 < n && pat.at(i + 2).to_int() == '/'.to_int() {
          buf.write_string("(?:[^/]*/)*")
          i = i + 3
        } else {
          buf.write_string(".*")
          i = i + 2
        }
      } else {
        buf.write_string(if pathname { "[^/]*" } else { ".*" })
        i = i + 1
      }
      continue
    }
    if code == '?'.to_int() {
      buf.write_string(if pathname { "[^/]" } else { "." })
      i = i + 1
      continue
    }
    if code == '['.to_int() {
      let (frag, consumed) = translate_class(pat, i)
      buf.write_string(frag)
      i = i + consumed
      continue
    }
    if code == '{'.to_int() {
      let (frag, consumed) = translate_brace(pat, i, pathname)
      buf.write_string(frag)
      i = i + consumed
      continue
    }
    if code == '\\'.to_int() {
      if i + 1 < n {
        buf.write_char('\\')
        buf.write_char(pat.at(i + 1).unsafe_to_char())
        i = i + 2
      } else {
        buf.write_char('\\')
        i = i + 1
      }
      continue
    }
    write_literal(buf, pat.at(i))
    i = i + 1
  }
  buf.to_string()
}

///|
/// Translate a `[...]` character class. With no closing `]` the `[` is taken
/// literally, so a malformed class never breaks compilation.
fn translate_class(pat : StringView, i : Int32) -> (String, Int32) {
  let n = pat.length()
  let mut j = i + 1
  let mut closed = false
  while j < n {
    let code = pat.at(j).to_int()
    if code == '\\'.to_int() {
      j = j + 2
      continue
    }
    if code == ']'.to_int() {
      closed = true
      break
    }
    j = j + 1
  }
  if !closed {
    let buf = StringBuilder::StringBuilder()
    buf.write_char('\\')
    buf.write_char('[')
    let mut t = i + 1
    while t < n {
      let code = pat.at(t).to_int()
      if code == '\\'.to_int() {
        if t + 1 < n {
          buf.write_char('\\')
          buf.write_char(pat.at(t + 1).unsafe_to_char())
          t = t + 2
          continue
        } else {
          buf.write_char('\\')
          t = t + 1
          continue
        }
      }
      buf.write_char(pat.at(t).unsafe_to_char())
      t = t + 1
    }
    (buf.to_string(), n - i)
  } else {
    let buf = StringBuilder::StringBuilder()
    buf.write_char('[')
    let mut k = i + 1
    if k < j &&
      (pat.at(k).to_int() == '!'.to_int() || pat.at(k).to_int() == '^'.to_int()) {
      buf.write_char('^')
      k = k + 1
    }
    while k < j {
      let code = pat.at(k).to_int()
      if code == '\\'.to_int() {
        if k + 1 < j {
          buf.write_char('\\')
          buf.write_char(pat.at(k + 1).unsafe_to_char())
          k = k + 2
          continue
        } else {
          buf.write_char('\\')
          k = k + 1
          continue
        }
      }
      // A `lo-hi` range, unless `-` is the last char before `]`.
      if k + 2 < j &&
        pat.at(k + 1).to_int() == '-'.to_int() &&
        pat.at(k + 2).to_int() != ']'.to_int() {
        buf.write_char(pat.at(k).unsafe_to_char())
        buf.write_char('-')
        buf.write_char(pat.at(k + 2).unsafe_to_char())
        k = k + 3
        continue
      }
      if code == '^'.to_int() {
        buf.write_char('\\')
        buf.write_char('^')
      } else if is_regex_special(code) {
        buf.write_char('\\')
        buf.write_char(pat.at(k).unsafe_to_char())
      } else {
        buf.write_char(pat.at(k).unsafe_to_char())
      }
      k = k + 1
    }
    buf.write_char(']')
    (buf.to_string(), j + 1 - i)
  }
}

///|
/// Translate a `{a,b,c}` alternation, honouring nested braces and classes.
fn translate_brace(
  pat : StringView,
  i : Int32,
  pathname : Bool,
) -> (String, Int32) {
  let n = pat.length()
  let mut depth = 1
  let mut j = i + 1
  while j < n && depth > 0 {
    let code = pat.at(j).to_int()
    if code == '\\'.to_int() {
      j = j + 2
      continue
    }
    if code == '{'.to_int() {
      depth = depth + 1
    } else if code == '}'.to_int() {
      depth = depth - 1
      if depth == 0 {
        break
      }
    }
    j = j + 1
  }
  if depth != 0 {
    // No matching `}`: take `{` as a literal.
    let buf = StringBuilder::StringBuilder()
    buf.write_char('\\')
    buf.write_char('{')
    (buf.to_string(), 1)
  } else {
    let content = pat.view(start_offset=i + 1, end_offset=j)
    let items = split_top_level(content)
    let buf = StringBuilder::StringBuilder()
    buf.write_string("(?:")
    let mut first = true
    for item in items {
      if !first {
        buf.write_char('|')
      } else {
        first = false
      }
      buf.write_string(translate_impl(item, pathname))
    }
    buf.write_char(')')
    (buf.to_string(), j + 1 - i)
  }
}

///|
/// Split a brace body on top-level commas (those not inside `[]` or `{}`).
fn split_top_level(s : StringView) -> Array[StringView] {
  let out : Array[StringView] = []
  let n = s.length()
  let mut start = 0
  let mut depth = 0
  let mut class_depth = 0
  let mut k = 0
  while k < n {
    let code = s.at(k).to_int()
    if code == '\\'.to_int() {
      k = k + 2
      continue
    }
    if code == '['.to_int() {
      class_depth = class_depth + 1
    } else if code == ']'.to_int() && class_depth > 0 {
      class_depth = class_depth - 1
    } else if class_depth == 0 && code == '{'.to_int() {
      depth = depth + 1
    } else if class_depth == 0 && code == '}'.to_int() && depth > 0 {
      depth = depth - 1
    } else if class_depth == 0 && depth == 0 && code == ','.to_int() {
      out.push(s.view(start_offset=start, end_offset=k))
      start = k + 1
    }
    k = k + 1
  }
  out.push(s.view(start_offset=start, end_offset=n))
  out
}

///|
/// Treat `\` as a path separator, so one pattern covers POSIX and Windows.
fn normalise_sep(s : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for c in s {
    if c == '\\' {
      buf.write_char('/')
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}
