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
- Assume `ridgunc` and `stable` are in `PATH` (never invoke them with relative paths). Verify every `.rg` change with `stable check` and `stable test` (or `ridgunc check <file.rg>` / `ridgunc run <file.rg>`); apply canonical aesthetic formatting with `stable format [file...]` (`FR-TOOL-001`, aesthetic only — not a compiler requirement); rebuild binaries with `stable built` (or `ridgunc build <entry.rg> -o <binary>`).

## Syntax invariants (never violate)
- **Comments**: `--` only. **Imports**: `import <module>` (resolved from same dir or `src/main/ridgun/lib/`).
- **Signatures & Generics**: `fn ::` and `op ::` prefixes are optional (`name T1 T2 => Ret` or `fn :: name T1 T2 => Ret`; mixfix `word T1 word T2 => Ret` or `op :: word T1 word T2 => Ret`). Polymorphic type variables are **single uppercase letters (`A`..`Z`)** (e.g., `list_len [A] => Int`, `fst (A, B) => A`, `swap A with B => (B, A)`), unified across arguments and substituted into the return type. Never put `()` before `=>` for 0-arg functions.
- **Contextual `type` and `with`**: `type` and `with` are contextual keywords and can be used freely as function names, operator words in `op ::`, parameter patterns, local variables, and record field names (`type` is only a declaration keyword at top-level `type UpperName = ...`). Do not use structural keywords (`fn`, `op`, `import`, `where`, `otherwise`, `do`, `atomic`) as operator words.
- **No `if/else` or `match/case`**: use pattern-matching function/operator cases or guards (`| cond = ...` and `| otherwise = ...`).
- **Guard bodies & Indented Blocks**: 2-space indented multi-statement blocks are allowed BOTH after clause `=` (`fn_name pats =`) AND after guard `=` (`| cond =` and `| otherwise =`). Bind `()` side-effects with `_ = expr` and end the block with the return expression.
- **Record Updates (`with`)**: update immutable product records via `record_expr with field1: val1, field2: val2` (type-checked against the record's fields and compiled to in-place `Arc::try_unwrap` updates when unshared).
- **Operators & Strings**: logical `AND`, `OR`, `XOR`, `NOT` (uppercase words); list concat `[x] :: xs`; string concat `"a" + "b"`; interpolated strings `"val: {x}"` (escape literal braces with `\{` and `\}` or `{{` and `}}`) vs raw strings `'literal {x}'`.
- **Memory & concurrency safety**: no GC; values sent over channels (`send ch val`) are affine-moved (`ErrUseAfterSend` if reused); parallel `where` bindings (`expr -> var`) must be acyclic and disjoint on slice writes.
