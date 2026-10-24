// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "fnmatch: * and ?" {
  assert_true(@glob.fnmatch("abc.txt", "*.txt"))
  assert_true(@glob.fnmatch("abc.txt", "a*c.txt"))
  assert_true(@glob.fnmatch("abc.txt", "a?c.txt"))
  assert_true(@glob.fnmatch("a-b-c", "a*b*c"))
  assert_false(@glob.fnmatch("abc.txt", "a?d.txt"))
  assert_false(@glob.fnmatch("abc.txt", "*.csv"))
}

///|
test "fnmatch: character classes" {
  assert_true(@glob.fnmatch("a1", "a[0-9]"))
  assert_false(@glob.fnmatch("ax", "a[0-9]"))
  assert_true(@glob.fnmatch("ax", "a[!0-9]"))
  assert_false(@glob.fnmatch("a1", "a[!0-9]"))
  assert_true(@glob.fnmatch("aZ", "a[A-Z]"))
}

///|
test "fnmatch: brace alternation" {
  assert_true(@glob.fnmatch("cat", "{cat,dog}"))
  assert_true(@glob.fnmatch("dog", "{cat,dog}"))
  assert_false(@glob.fnmatch("fox", "{cat,dog}"))
  assert_true(@glob.fnmatch("ca", "c{a,t}"))
  assert_true(@glob.fnmatch("ct", "c{a,t}"))
}

///|
test "fnmatch: case folding" {
  assert_true(@glob.fnmatch("ABC.TXT", "*.txt", ignorecase=true))
  assert_false(@glob.fnmatch("ABC.TXT", "*.txt"))
  assert_true(@glob.fnmatchcase("ABC.TXT", "*.TXT"))
}

///|
test "fnmatch: escape makes a literal" {
  assert_true(@glob.fnmatch("a*b", "a\\*b"))
  assert_false(@glob.fnmatch("axb", "a\\*b"))
}

///|
test "filter keeps the matching names" {
  let out = @glob.filter(
    ["a.txt", "b.csv", "c.txt", "d.TXT"],
    "*.txt",
    ignorecase=true,
  )
  assert_eq(out, ["a.txt", "c.txt", "d.TXT"])
}

///|
test "glob: * does not cross a separator" {
  let g = @glob.Glob::compile("src/*.mbt")
  assert_true(g.matches("src/foo.mbt"))
  assert_false(g.matches("src/sub/foo.mbt"))
  assert_false(g.matches("src/foo.mbt.bak"))
}

///|
test "glob: ** crosses separators" {
  let g = @glob.Glob::compile("src/**/*.mbt")
  assert_true(g.matches("src/foo.mbt"))
  assert_true(g.matches("src/sub/foo.mbt"))
  assert_true(g.matches("src/a/b/c/foo.mbt"))
  assert_false(g.matches("lib/foo.mbt"))
}

///|
test "glob: ? matches one non-separator character" {
  let g = @glob.Glob::compile("file?.log")
  assert_true(g.matches("file1.log"))
  assert_false(g.matches("file12.log"))
  assert_false(g.matches("file/.log"))
}

///|
test "glob: character classes and braces" {
  assert_true(@glob.Glob::compile("file[0-9].txt").matches("file3.txt"))
  assert_false(@glob.Glob::compile("file[0-9].txt").matches("fileX.txt"))
  assert_true(@glob.Glob::compile("src/{a,b}/*.mbt").matches("src/a/x.mbt"))
  assert_true(@glob.Glob::compile("src/{a,b}/*.mbt").matches("src/b/x.mbt"))
  assert_false(@glob.Glob::compile("src/{a,b}/*.mbt").matches("src/c/x.mbt"))
}

///|
test "glob: backslash separators are normalised" {
  let g = @glob.Glob::compile("a/b/c")
  assert_true(g.matches("a\\b\\c"))
  assert_true(g.matches("a/b/c"))
}

///|
test "GlobSet matches any and reports indices" {
  let set = @glob.GlobSet::compile(["*.txt", "*.csv", "*.md"])
  assert_true(set.matches_any("notes.md"))
  assert_false(set.matches_any("notes.js"))
  assert_eq(set.matches("x.txt"), [0])
  assert_eq(set.matches("x.csv"), [1])
  assert_eq(set.matches("x.txt.csv"), [1])
}

///|
test "match_path and filter_paths" {
  assert_true(@glob.match_path("src/foo.mbt", "src/*.mbt"))
  assert_false(@glob.match_path("src/foo.mbt", "src/*.txt"))
  let out = @glob.filter_paths(["a.txt", "b.csv", "c.txt"], "*.txt")
  assert_eq(out, ["a.txt", "c.txt"])
}
