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
- **Unified `=` Grammar (`(none)`, `|`, `||`) & Nested Block Closers (`|.` / `||.`) (`FR-COMP-003`)**:
  - Every function clause (`fn ::`), operator clause (`op ::`), local variable binding (`x =` / `mut x =`), and guard branch (`| cond =` / `| otherwise =`) ends with `=` and accepts: (1) inline expression (with optional `|| expr -> var` below), (2) sequential indented lines `(none)`, (3) conditional guard block `| cond = ...`, or (4) parallel block `|| expr -> var` / `|| expr` (`where` is removed).
  - Guarded clauses always include `=` before the guard block (`name pats =` followed by `| cond = ...`), local variables can be assigned via `|` (`x =` followed by `| cond = ...`), and guards can nest (`|` inside `| cond =` or `| otherwise =`).
  - When a nested `|` or `||` block finishes and execution returns to an outer level below it, close the inner block with `|.` (or `||.`), preferably inline at the end of its last line (`| otherwise = val |.`).
- **Immutable (`x = ...`) vs Mutable (`mut x = ...`) Local Variables**: local bindings `x = expr` are immutable by default; declare mutable variables with `mut x = expr` and reassign them in the same scope with `x = new_expr` (under `RMM2`, `new_expr` gets `+1` before old `x` gets `-1`).
- **Record Updates (`with`)**: update immutable product records via `record_expr with field1: val1, field2: val2` (type-checked against the record's fields and compiled to in-place `Arc::try_unwrap` updates when unshared).
- **Operators, Strings & Collection Combinators**: logical `and`, `or`, `xor`, `not` (lowercase words); list concat `[x] :: xs`; string concat `"a" + "b"`; interpolated strings `"val: {x}"` (escape literal braces with `\{` and `\}` or `{{` and `}}`) vs raw strings `'literal {x}'`; sequential higher-order list operations `map`, `filter`, `fold` alongside multicore parallel `||map` and `||filter` (`FR-COMP-001`).
- **Memory & concurrency safety (`RMM1` / `RMM2`)**: no GC; incoming function arguments are untouched (`+0 / -0`), local structure assignments get `+1` and cascade `-1` to direct children when `rc == 0` (`FR-COMP-002`); parallel `|| expr -> var` bindings must be acyclic and disjoint on slice writes.
