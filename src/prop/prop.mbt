// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A set of code points, kept as sorted disjoint inclusive ranges.
///
/// Character classes, `\p{...}`, `\w` and the rest are all this one shape, so
/// the set algebra a pattern needs — union for `[a-z]`, difference for `--`,
/// intersection for `&&`, complement for `[^…]` — lives here once.
pub struct CharSet {
  ranges : Array[(Int32, Int32)]
} derive(Eq)

///|
pub extend CharSet with Eq::{equal, not_equal}

///|
/// A set prints as its name and how much it holds, never as its ranges: a
/// category can carry four thousand of them, and no failure message is
/// improved by reading them.
pub impl @debug.Debug for CharSet with fn to_repr(self : CharSet) -> @debug.Repr {
  @debug.Repr::opaque_("CharSet", Repr(self.ranges.length()))
}

///|
pub extend CharSet with @debug.Debug::{to_repr}

///|
fn imax(a : Int32, b : Int32) -> Int32 {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn imin(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// Build a set from ranges, sorting and merging them first.
///
/// The input may be in any order and may overlap; the stored form is always
/// sorted, disjoint and coalesced, which is what makes `contains` a binary
/// search and the algebra linear.
pub fn CharSet::of(ranges : Array[(Int32, Int32)]) -> CharSet {
  let sorted = ranges.copy()
  sorted.sort_by((a, b) => a.0 - b.0)
  let out : Array[(Int32, Int32)] = []
  for r in sorted {
    if out.length() > 0 && r.0 <= out[out.length() - 1].1 + 1 {
      let last = out[out.length() - 1]
      out[out.length() - 1] = (last.0, imax(last.1, r.1))
    } else {
      out.push(r)
    }
  }
  { ranges: out, }
}

///|
/// The empty set.
pub fn CharSet::empty() -> CharSet {
  { ranges: [], }
}

///|
/// A set holding exactly one code point.
pub fn CharSet::single(c : Int32) -> CharSet {
  { ranges: [(c, c)], }
}

///|
/// Every code point, surrogates included.
pub fn CharSet::any() -> CharSet {
  { ranges: [(0, 0x10FFFF)], }
}

///|
/// Whether a code point is in the set.
pub fn CharSet::contains(self : CharSet, c : Int32) -> Bool {
  let ranges = self.ranges
  let mut lo = 0
  let mut hi = ranges.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let (a, b) = ranges[mid]
    if c < a {
      hi = mid - 1
    } else if c > b {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Whether the set holds nothing.
pub fn CharSet::is_empty(self : CharSet) -> Bool {
  self.ranges.length() == 0
}

///|
/// The stored ranges, sorted and disjoint.
pub fn CharSet::ranges(self : CharSet) -> Array[(Int32, Int32)] {
  self.ranges
}

///|
/// Union: `[a-z]` or, in the V1 set algebra, `||`.
pub fn CharSet::union(self : CharSet, other : CharSet) -> CharSet {
  CharSet::of(self.ranges + other.ranges)
}

///|
/// Difference: the V1 set algebra's `--`.
pub fn CharSet::difference(self : CharSet, other : CharSet) -> CharSet {
  let out : Array[(Int32, Int32)] = []
  for (a, b) in self.ranges {
    let mut lo = a
    for (c, d) in other.ranges {
      if d < lo {
        continue
      }
      if c > b {
        break
      }
      if c > lo {
        out.push((lo, imin(b, c - 1)))
      }
      lo = imax(lo, d + 1)
      if lo > b {
        break
      }
    }
    if lo <= b {
      out.push((lo, b))
    }
  }
  { ranges: out, }
}

///|
/// Intersection: the V1 set algebra's `&&`.
pub fn CharSet::intersection(self : CharSet, other : CharSet) -> CharSet {
  let out : Array[(Int32, Int32)] = []
  let mut i = 0
  let mut j = 0
  while i < self.ranges.length() && j < other.ranges.length() {
    let (a, b) = self.ranges[i]
    let (c, d) = other.ranges[j]
    let lo = imax(a, c)
    let hi = imin(b, d)
    if lo <= hi {
      out.push((lo, hi))
    }
    if b < d {
      i += 1
    } else {
      j += 1
    }
  }
  { ranges: out, }
}

///|
/// Symmetric difference: the V1 set algebra's `~~`.
pub fn CharSet::symmetric_difference(
  self : CharSet,
  other : CharSet,
) -> CharSet {
  self.union(other).difference(self.intersection(other))
}

///|
/// Complement over every code point: what `[^…]` means.
pub fn CharSet::complement(self : CharSet) -> CharSet {
  CharSet::any().difference(self)
}

///|
/// Close the set under simple case folding: add the folded form of everything
/// in it, and the unfolded form of everything that folds into it.
///
/// This is what `(?i)` does to a class at parse time: fold the pattern, not
/// the input, so the executor stays a plain membership test. Only single code
/// point folds exist here, so `ß` does not grow an `ss` — matching it against
/// `SS` is out of scope, exactly as it is in Python's `re`.
pub fn CharSet::fold(self : CharSet) -> CharSet {
  let extra : Array[(Int32, Int32)] = []
  for (src, dst) in fold_pairs() {
    if src == dst {
      continue
    }
    if self.contains(src) {
      extra.push((dst, dst))
    }
    if self.contains(dst) {
      extra.push((src, src))
    }
  }
  CharSet::of(self.ranges + extra)
}
