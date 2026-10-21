---
id: custom/languages/ridgun
name: "Ridgun Language Conventions"
description: "Use when writing, refactoring, or reviewing Ridgun (.rg) source files or build.rg: syntax rules, type signatures, guards, ADTs, parallel || DAGs, RMM1/RMM2 memory, regions, and stable/ridgunc ELF64 verification."
applyTo: "**/*.rg,build.rg"
optional: false
---
# Ridgun conventions (`.rg` — `v0.9.3`)

Read and follow the `implement-code-ridgun` skill before editing any `.rg` file.

## Layout and 100% pure-Ridgun ELF64 toolchain (`v0.9.3`)
- Shared modules live in `src/main/ridgun/lib/*.rg`; executable entrypoints live in `src/main/ridgun/<target>/main.rg` (compiled directly to standalone Linux ELF64 executables at `target/<target>` without Rust, C, or `rustc`).
- Test suites live in `src/test/ridgun/test_*.rg` and import `test` (`assert_equals`, `assert_true`).
- Verify every `.rg` change with `stable check` and `stable test` (or `ridgunc check <file.rg>` / `ridgunc run <file.rg>`); apply canonical tabular formatting with `stable format [file...]` (`FR-TOOL-001`, aesthetic only — not enforced by `ridgunc`); build native ELF64 binaries with `stable built` or `ridgunc build [--target x86_64-linux|arm64-linux] <entry.rg> -o <binary>`.

## Syntax invariants (never violate)
- **Comments**: `--` only (never `//`, `#`, or `/* */`). **Imports**: `import <module>` at top of file (resolved from same dir or `src/main/ridgun/lib/`, no quotes or `.rg`).
- **Signatures & Generics (`A`..`Z`)**: `fn ::` and `op ::` prefixes are optional (`name T1 T2 => Ret` or `fn :: name T1 T2 => Ret`; mixfix `word T1 word T2 => Ret` or `op :: word T1 word T2 => Ret`). Polymorphic type variables are **single uppercase letters (`A`..`Z`)** (e.g., `list_len [A] => Int`, `fst (A, B) => A`, `swap A with B => (B, A)`), unified across arguments and substituted into the return type. **Never** put `()` before `=>` for 0-arg functions (`fn :: main => ()`, not `fn :: main () => ()`).
- **Contextual `type` and `with`**: `type` and `with` are contextual keywords and can be used freely as function names, operator words in `op ::`, parameter patterns, local variables, and record field names (`type` is only a declaration keyword at top-level `type UpperName = ...`). Do not use structural keywords (`fn`, `op`, `import`, `otherwise`, `do`, `atomic`, `mut`) as operator words.
- **Unified `=` Grammar (`(none)`, `|`, `||`) & Nested Block Closers (`|.` / `||.`) (`FR-COMP-003`)**:
  - Every function clause (`fn ::`), operator clause (`op ::`), local variable binding (`x =` / `mut x =`), and guard branch (`| cond =` / `| otherwise =`) **requires `=`** and accepts:
    1. Inline expression (optionally followed on indented lines below by `|| expr -> var` parallel DAG bindings),
    2. Sequential block (indented lines with no prefix),
    3. Conditional guard block (`| cond = ...` and `| otherwise = ...`),
    4. Parallel DAG block (`|| expr -> var` or `|| expr`). **Note:** The `where` keyword does not exist in Ridgun; always use `|| expr -> var`.
  - Guarded clauses always include `=` before the guard block (`name pats =` followed by `| cond = ...`), local variables can be assigned via `|` (`x =` followed by `| cond = ...`), and guards can nest 3–4+ levels deep (`|` inside `| cond =` or `| otherwise =`).
  - When a nested `|` or `||` block finishes and execution continues at an outer/parent level below it, close the inner block with **`|.`** (for `|`) or **`||.`** (for `||`), preferably inline at the end of its last line (`| otherwise = val |.`). At the end of a function where no outer branch follows, omit `|.` / `||.`.
- **Immutable (`x = ...`) vs Mutable (`mut x = ...`) Local Variables**:
  - Local bindings `x = expr` are immutable by default; rebinding `x = ...` in the same scope without a prior `mut` is a compile-time error (`ErrImmutableReassign`).
  - Declare mutable variables with `mut x = expr` and update them in the same scope with `x = new_expr` (under `RMM2`, `new_expr` gets `+1` before the old `x` gets `-1`).
- **Record Updates (`with`)**: Update immutable product records via `record_expr with field1: val1, field2: val2`.
- **Shared ADT Constructors, `expand type`, and Automatic `fn ::` Clause Merging (`FR-COMP-005`)**:
  - Multiple `type` declarations may reuse the same constructor names (e.g., `Error`, `Var`, `Lit`, `None`); typechecking disambiguates via expected column types and argument arity/types.
  - Extend existing Sum ADTs or Product Records with `expand type UpperName = ...` (e.g., `expand type Error = AuthError String | DbError Int String` or `expand type Config = tls: Bool`).
  - Re-declaring `fn ::` / `op ::` for an existing function automatically merges the new pattern clauses before any base catch-all (`_`) clause (no `expand fn` keyword needed).
- **Operators, Strings & Collection Combinators (`FR-COMP-001`)**:
  - Logical operators are lowercase words: `and`, `or`, `xor`, `not` (never `&&`, `||`, `!`).
  - List prepend/concat: `[x] :: xs` or `xs :: ys` (`:` is only for pattern destructuring `(x:xs)`, never in expressions).
  - String concat: `"a" + "b"`; interpolated strings `"val: {x}"` (escape literal braces with `\{`/`\}` or `{{`/`}}`) vs raw strings `'literal {x}'`.
  - Higher-order list combinators: sequential `map f xs`, `filter p xs`, `fold f init xs`, and multicore parallel **`||map f xs`** and **`||filter p xs`**.
- **Deterministic Memory (`RMM1` / `RMM2`) & Concurrency Safety (`FR-COMP-002`)**:
  - Zero Garbage Collector: `RMM1` handles static last-use drops (`rg_cmm_drop`), zero-copy return moves, and 1-cycle pointer-identity checks (`ptr(a) != ptr(c)`); `RMM2` leaves incoming arguments untouched (`+0 / -0`), increments (`+1`) on local/container assignment, spares the returned local in transit, and cascades `-1` to child structures on scope exit.
  - Parallel `|| expr -> var` bindings must be acyclic and disjoint on slice writes (`|| val -> m[i, j]`); channels enforce affine move ownership (`ErrUseAfterSend`).
