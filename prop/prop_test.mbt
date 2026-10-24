// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "general categories, spelled every way" {
  let lu = @prop.category("Lu").unwrap()
  assert_true(lu.contains('A'.to_int()))
  assert_false(lu.contains('a'.to_int()))
  // The same category under three spellings.
  assert_eq(
    @prop.category("Lu").unwrap(),
    @prop.category("Uppercase_Letter").unwrap(),
  )
  assert_eq(
    @prop.category("Lu").unwrap(),
    @prop.category("uppercaseletter").unwrap(),
  )
  // One-letter groups are the union of their members.
  let l = @prop.category("L").unwrap()
  assert_true(l.contains('A'.to_int()))
  assert_true(l.contains('π'.to_int()))
  assert_false(l.contains('1'.to_int()))
}

///|
test "binary properties and scripts" {
  assert_true(@prop.binary("White_Space").unwrap().contains(' '.to_int()))
  assert_true(@prop.binary("White_Space").unwrap().contains('\t'.to_int()))
  assert_false(@prop.binary("White_Space").unwrap().contains('a'.to_int()))
  let latin = @prop.script("Latin").unwrap()
  assert_true(latin.contains('a'.to_int()))
  assert_false(latin.contains('Д'.to_int()))
  let greek = @prop.script("Grek").unwrap()
  assert_true(greek.contains('Δ'.to_int()))
  // A block, and the property=value spelling.
  assert_true(@prop.block("Basic Latin").unwrap().contains('~'.to_int()))
  assert_true(@prop.property("Script=Greek").unwrap().contains('Δ'.to_int()))
  assert_true(
    @prop.property("General_Category=Decimal_Number")
    .unwrap()
    .contains('7'.to_int()),
  )
  assert_true(@prop.property("any").unwrap().contains(0x10FFFF))
  // "ASCII" is the block alias PropertyValueAliases.txt records for it.
  assert_true(@prop.property("ASCII").unwrap().contains('~'.to_int()))
  assert_false(@prop.property("ASCII").unwrap().contains('é'.to_int()))
}

///|
test "case folding is an equivalence, both ways" {
  assert_eq(@prop.fold('A'), 'a')
  assert_eq(@prop.fold('a'), 'a')
  // Kelvin sign folds to k, and the reverse direction holds too.
  assert_eq(@prop.fold('K'), 'k')
  assert_eq(@prop.fold('K'), 'k')
  assert_eq(@prop.fold('ſ'), 's')
  assert_eq(@prop.fold('1'), '1')
  let cs = @prop.CharSet::single('k'.to_int()).fold()
  assert_true(cs.contains('K'.to_int()))
  assert_true(cs.contains('k'.to_int()))
  assert_true(cs.contains('K'.to_int()))
}

///|
test "the word, digit and space sets" {
  assert_true(@prop.word.contains('a'.to_int()))
  assert_true(@prop.word.contains('_'.to_int()))
  assert_true(@prop.word.contains('7'.to_int()))
  assert_false(@prop.word.contains('-'.to_int()))
  assert_true(@prop.digit.contains('9'.to_int()))
  assert_false(@prop.digit.contains('a'.to_int()))
  assert_true(@prop.space.contains('\n'.to_int()))
  assert_true(@prop.ascii_word.contains('_'.to_int()))
  assert_false(@prop.ascii_word.contains('π'.to_int()))
}

///|
test "set algebra" {
  let az = @prop.CharSet::of([('a'.to_int(), 'z'.to_int())])
  let vowels = @prop.CharSet::of([
    ('a'.to_int(), 'a'.to_int()),
    ('e'.to_int(), 'e'.to_int()),
  ])
  // Two consonants stand between a and e... no: b-d and f-z survive.
  assert_eq(az.difference(vowels).ranges().length(), 2)
  assert_true(az.difference(vowels).contains('b'.to_int()))
  assert_false(az.difference(vowels).contains('a'.to_int()))
  assert_false(az.difference(vowels).contains('e'.to_int()))
  assert_eq(az.intersection(vowels), vowels)
  assert_true(az.complement().contains('0'.to_int()))
  assert_false(az.complement().contains('m'.to_int()))
  assert_true(
    az.union(@prop.CharSet::single('0'.to_int())).contains('0'.to_int()),
  )
}

///|
test "version is recorded" {
  assert_true(@prop.version() != "")
}
