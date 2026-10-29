// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The ECMA-262 frontend, against ECMA-262 itself.
///
/// `src/ecma_vectors_test.mbt` holds two lists: the patterns test262 marks as
/// "must not compile" for `RegExp`, and what a real ECMA-262 engine answers
/// for a corpus of patterns and subjects. Neither list is written by hand, so
/// the frontend is pinned to the standard rather than to a reading of it.

///|
/// The flag letters ECMA-262 uses, as `Flags`.
fn ecma_flags(letters : String) -> @moonregex.Flags {
  let mut ignorecase = false
  let mut multiline = false
  let mut dotall = false
  let mut unicode = false
  let mut unicode_sets = false
  for c in letters {
    if c == 'i' {
      ignorecase = true
    } else if c == 'm' {
      multiline = true
    } else if c == 's' {
      dotall = true
    } else if c == 'u' {
      unicode = true
    } else if c == 'v' {
      unicode_sets = true
    }
  }
  @moonregex.Flags::new(
    ignorecase~,
    multiline~,
    dotall~,
    unicode~,
    unicode_sets~,
  )
}

///|
test "test262 patterns the ECMA-262 grammar must refuse" {
  for row in ecma_refused {
    let fields = split_field(row, '\t')
    let pattern = unescape(fields[0])
    let flags = ecma_flags(fields[1])
    let refused = try {
      let _ = @moonregex.compile(pattern, flags~, dialect=@moonregex.ecma262)
      false
    } catch {
      _ => true
    }
    if !refused {
      fail(
        "vector \{row}\n  /\{pattern}/ (\{fields[1]}) was accepted, and ECMA-262 refuses it",
      )
    }
  }
}

///|
test "an ECMA-262 engine, replayed" {
  for line in ecma_cases {
    let fields = split_field(line, '\t')
    let pattern = unescape(fields[1])
    let flags = ecma_flags(fields[2])
    let text = unescape(fields[3])
    let p = @moonregex.compile(pattern, flags~, dialect=@moonregex.ecma262) catch {
      e => fail("/\{pattern}/ (\{fields[2]}) was refused: \{e}")
    }
    let spans = walk_spans(p, text)
    if spans != fields[5] {
      fail(
        "/\{pattern}/ (\{fields[2]}) on \"\{text}\": spans \{spans}, want \{fields[5]}",
      )
    }
  }
}
