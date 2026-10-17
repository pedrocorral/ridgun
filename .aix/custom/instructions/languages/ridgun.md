---
id: custom/languages/ridgun
name: "Ridgun Language Conventions"
description: "Use when writing, refactoring, or reviewing Ridgun (.rg) source files or build.rg: syntax rules, type signatures, guards, ADTs, parallel where-DAGs, regions, and stable/ridgunc verification."
applyTo: "**/*.rg,build.rg"
optional: false
---
# Ridgun conventions (`.rg`)

Read and follow the `implement-code-ridgun` skill before editing any `.rg` file.

## Layout and toolchain (`v0.9.3`)
- Shared modules live in `src/main/ridgun/lib/*.rg`; executable entrypoints live in `src/main/ridgun/<target>/main.rg` (compiled to `target/<target>`).
- Test suites live in `src/test/ridgun/test_*.rg` and import `test` (`assert_equals`, `assert_true`).
- Verify every `.rg` change with `./target/stable check` and `./target/stable test`; apply canonical aesthetic formatting with `./target/stable format [file...]` (`FR-TOOL-001`, aesthetic only — not a compiler requirement); rebuild binaries with `./target/stable built`.

## Syntax invariants (never violate)
- **Comments**: `--` only. **Imports**: `import <module>` (resolved from same dir or `src/main/ridgun/lib/`).
- **Signatures**: `fn :: name T1 T2 => Ret` or natural-language `op :: word T1 word (T2, T3) => Ret` (never put `()` before `=>` for 0-arg functions; in `op ::`, never use reserved lexer keywords like `fn`, `op`, `type`, `import`, `where`, `otherwise` as operator words).
- **No `if/else` or `match/case`**: use pattern-matching function/operator cases or guards (`| cond = expr` and `| otherwise = expr`).
- **Single-line guard bodies**: in `| cond = expr`, `expr` MUST be on the same line as `=`. Extract a helper function/operator when a branch needs a multi-statement block.
- **Blocks**: 2-space indented statement blocks are valid only after `fn_name pats =` or `op_words pats =`; bind `()` side-effects with `_ = expr` and end with the return expression.
- **Operators**: logical `AND`, `OR`, `XOR`, `NOT` (uppercase words); list concat `[x] :: xs`; string concat `"a" + "b"`; interpolated strings `"val: {x}"` vs raw strings `'literal {x}'`.
- **Memory & concurrency safety**: no GC; values sent over channels (`send ch val`) are affine-moved (`ErrUseAfterSend` if reused); parallel `where` bindings (`expr -> var`) must be acyclic and disjoint on slice writes.
