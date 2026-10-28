// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Format-string substitution — `regex.subf` / `regex.subfn` / `Pattern.subf`.
///
/// The replacement is a Python `str.format`-shaped template whose fields name
/// groups: `{}` is the whole match, `{0}` a numbered group, `{name}` a named
/// group, and `{0[0]}`/`{name[0]}` a group's first capture. `{{` and `}}` write
/// a literal brace. A field may carry a `:spec` — `[[fill]align][width]
/// [.precision][type]` — applied to the captured text.
///
/// Types `s` (the default), `d`, `x`, `X`, `o` and `b` are honoured; float
/// types (`f`, `e`, `g`, `%`) are passed through after width/alignment, because
/// they need a `str.format`-grade float formatter that is deliberately out of
/// scope here.

///|
/// Format `fmt` against match `m`, `regex` `subf`-style.
fn expandf(fmt : String, m : Match) -> String raise @parse.Refused {
  let chars : Array[Char] = []
  for c in fmt {
    chars.push(c)
  }
  let n = chars.length()
  let buf = StringBuilder::StringBuilder()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '{' {
      if i + 1 < n && chars[i + 1] == '{' {
        buf.write_char('{')
        i = i + 2
        continue
      }
      // Find the closing brace of this field (the first unescaped `}`).
      let mut j = i + 1
      while j < n && chars[j] != '}' {
        j = j + 1
      }
      if j >= n {
        // Unbalanced: write the rest literally, as `str.format` would refuse;
        // we refuse loudly instead, per the architecture's discipline.
        raise @parse.Pattern(
          msg="unterminated '{' in subf replacement",
          at=0,
          line=1,
          column=1,
        )
      }
      let body = collect(chars, i + 1, j)
      buf.write_string(format_field(body, m))
      i = j + 1
    } else if c == '}' {
      if i + 1 < n && chars[i + 1] == '}' {
        buf.write_char('}')
        i = i + 2
        continue
      }
      buf.write_char('}')
      i = i + 1
    } else {
      buf.write_char(c)
      i = i + 1
    }
  }
  buf.to_string()
}

///|
/// Collect the characters in `chars[start..end)` into a `String`.
fn collect(chars : Array[Char], start : Int32, end : Int32) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut i = start
  while i < end {
    buf.write_char(chars[i])
    i = i + 1
  }
  buf.to_string()
}

///|
/// Resolve one `{field[:spec]}` body against the match and return its text.
fn format_field(body : String, m : Match) -> String raise @parse.Refused {
  let (field, spec) = split_spec(body)
  let value = group_text(field, m)
  match value {
    None => ""
    Some(s) => apply_spec(s, spec)
  }
}

///|
/// Split a field body into its `field` name and its `:spec` (empty when none).
fn split_spec(body : String) -> (String, String) {
  let chars : Array[Char] = []
  for c in body {
    chars.push(c)
  }
  let n = chars.length()
  let mut i = 0
  while i < n {
    if chars[i] == ':' {
      return (collect(chars, 0, i), collect(chars, i + 1, n))
    }
    i = i + 1
  }
  (body, "")
}

///|
/// The text a field names, or `None` when that group took no part.
fn group_text(field : String, m : Match) -> String? raise @parse.Refused {
  // A `[k]` capture suffix: only the first capture (`[0]`) is stored.
  let (base, capture) = split_capture(field)
  if capture > 0 {
    return None
  }
  let key = parse_field_key(base)
  m.group(key)
}

///|
/// Split a `name[k]` field into `name` and `k`; a field without the suffix
/// yields `(field, 0)`.
fn split_capture(field : String) -> (String, Int32) {
  let chars : Array[Char] = []
  for c in field {
    chars.push(c)
  }
  let n = chars.length()
  if n > 0 && chars[n - 1] == ']' {
    let mut i = n - 2
    while i >= 0 && chars[i] != '[' {
      i = i - 1
    }
    if i >= 0 {
      let name = collect(chars, 0, i)
      let idx = collect(chars, i + 1, n - 1)
      return (name, decimal_of(idx))
    }
  }
  (field, 0)
}

///|
/// Turn a field name into a group key: empty or digits → a number, else a name.
fn parse_field_key(base : String) -> Group {
  if base.length() == 0 {
    return Whole
  }
  let mut digits = true
  for c in base {
    if !(c >= '0' && c <= '9') {
      digits = false
    }
  }
  if digits {
    Num(n=decimal_of(base))
  } else {
    Name(n=base)
  }
}

///|
/// Apply a format spec to a captured string.
fn apply_spec(value : String, spec : String) -> String {
  let s = parse_spec(spec)
  match s.type_ {
    'd' => pad(integer_radix(value, 10, false), s)
    'x' => pad(integer_radix(value, 16, false), s)
    'X' => pad(integer_radix(value, 16, true), s)
    'o' => pad(integer_radix(value, 8, false), s)
    'b' => pad(integer_radix(value, 2, false), s)
    _ => pad(truncate(value, s.precision), s)
  }
}

///|
/// A parsed format spec: fill, alignment, width, precision and type character.
priv struct Spec {
  fill : Char
  align : Char
  width : Int32
  precision : Int32
  type_ : Char
}

///|
/// Parse a `:spec` into its parts. The default — `Spec { fill=' ',
/// align='<', width=-1, precision=-1, type_='s' }` — left-aligns a string
/// without padding, which is `str.format`'s own default for strings.
fn parse_spec(spec : String) -> Spec {
  let chars : Array[Char] = []
  for c in spec {
    chars.push(c)
  }
  let n = chars.length()
  let mut i = 0
  let mut fill : Char = ' '
  let mut align : Char = '<'
  // [[fill]align]
  if i < n {
    let c = chars[i]
    if c == '<' || c == '>' || c == '^' {
      align = c
      i = i + 1
    } else if i + 1 < n &&
      (chars[i + 1] == '<' || chars[i + 1] == '>' || chars[i + 1] == '^') {
      fill = c
      align = chars[i + 1]
      i = i + 2
    }
  }
  // [width]
  let mut width : Int32 = -1
  let mut j = i
  while j < n && chars[j] >= '0' && chars[j] <= '9' {
    j = j + 1
  }
  if j > i {
    width = decimal_of(collect(chars, i, j))
    i = j
  }
  // [.precision]
  let mut precision : Int32 = -1
  if i < n && chars[i] == '.' {
    let mut k = i + 1
    while k < n && chars[k] >= '0' && chars[k] <= '9' {
      k = k + 1
    }
    if k > i + 1 {
      precision = decimal_of(collect(chars, i + 1, k))
      i = k
    } else {
      precision = 0
      i = i + 1
    }
  }
  // [type]
  let type_ : Char = if i < n { chars[i] } else { 's' }
  Spec::{ fill, align, width, precision, type_, }
}

///|
/// Truncate `value` to `precision` code points; `precision < 0` keeps it whole.
fn truncate(value : String, precision : Int32) -> String {
  if precision < 0 {
    return value
  }
  let chars : Array[Char] = []
  for c in value {
    chars.push(c)
  }
  let mut n = chars.length()
  if precision < n {
    n = precision
  }
  let buf = StringBuilder::StringBuilder()
  let mut i = 0
  while i < n {
    buf.write_char(chars[i])
    i = i + 1
  }
  buf.to_string()
}

///|
/// Pad a formatted value to the spec's width, filling and aligning per the
/// spec. `width < 0` leaves the value alone.
fn pad(value : String, s : Spec) -> String {
  if s.width < 0 {
    return value
  }
  let len = cp_length(value)
  if len >= s.width {
    return value
  }
  let pad_n = s.width - len
  let fill_s = s.fill.to_string()
  let buf = StringBuilder::StringBuilder()
  if s.align == '<' {
    buf.write_string(value)
    let mut k = 0
    while k < pad_n {
      buf.write_string(fill_s)
      k = k + 1
    }
  } else if s.align == '^' {
    let left = pad_n / 2
    let right = pad_n - left
    let mut k = 0
    while k < left {
      buf.write_string(fill_s)
      k = k + 1
    }
    buf.write_string(value)
    let mut k2 = 0
    while k2 < right {
      buf.write_string(fill_s)
      k2 = k2 + 1
    }
  } else {
    // '>' — right-align.
    let mut k = 0
    while k < pad_n {
      buf.write_string(fill_s)
      k = k + 1
    }
    buf.write_string(value)
  }
  buf.to_string()
}

///|
/// Re-render `value` in the given base, or pass it through when it is not an
/// integer. `upper` selects upper-case digits for base 16.
fn integer_radix(value : String, base : Int32, upper : Bool) -> String {
  match parse_int(value) {
    None => value
    Some(n) => radix_of(n, base, upper)
  }
}

///|
/// Parse an optional-sign decimal integer; `None` when `value` is not one.
fn parse_int(value : String) -> Int32? {
  let chars : Array[Char] = []
  for c in value {
    chars.push(c)
  }
  let n = chars.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if chars[0] == '-' || chars[0] == '+' {
    neg = chars[0] == '-'
    i = 1
  }
  if i >= n {
    return None
  }
  let mut acc : Int32 = 0
  let mut j = i
  while j < n {
    let c = chars[j]
    if c < '0' || c > '9' {
      return None
    }
    acc = acc * 10 + (c.to_int() - '0'.to_int())
    j = j + 1
  }
  Some(if neg { -acc } else { acc })
}

///|
/// Format `n` in `base` (2, 8, 10, 16). Negative numbers are re-emitted with a
/// leading `-` and the magnitude shown in the base.
fn radix_of(n : Int32, base : Int32, upper : Bool) -> String {
  let table = if upper { "0123456789ABCDEF" } else { "0123456789abcdef" }
  let neg = n < 0
  let mut mag = if neg { -n } else { n }
  if mag == 0 {
    return "0"
  }
  let digs : Array[Char] = []
  while mag > 0 {
    digs.push(table[mag % base].to_int().unsafe_to_char())
    mag = mag / base
  }
  let buf = StringBuilder::StringBuilder()
  if neg {
    buf.write_char('-')
  }
  let mut i = digs.length() - 1
  while i >= 0 {
    buf.write_char(digs[i])
    i = i - 1
  }
  buf.to_string()
}
