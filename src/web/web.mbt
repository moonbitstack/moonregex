// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Give the page one function to call. The whole API is a string in, a JSON
/// string out: the page never touches a MoonBit value, so the two sides only
/// have to agree on a shape that is easy to read in a browser.
#cfg(target="js")
extern "js" fn publish(
  run : (String, String, String, String) -> String,
) -> Unit =
  #| (run) => { globalThis.moonregexWeb = { run: run }; }

///|
/// Runs when the page loads the script: it only hands the function over.
#cfg(target="js")
fn main {
  publish(@engine.run)
}

///|
/// The package ships only to the browser; on the other backends `main` still
/// touches the engine so the import is not dead.
#cfg(not(target="js"))
fn main {
  ignore(@engine.run("", "", "", "search"))
}
