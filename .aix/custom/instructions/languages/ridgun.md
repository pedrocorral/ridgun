---
id: custom/languages/ridgun
name: "Ridgun Language Conventions"
description: "Use when writing, refactoring, or reviewing Ridgun (.rg) source files or build.rg: syntax rules, type signatures, guards, ADTs, parallel || DAGs, RMM1/RMM2 memory, regions, and stable/ridgunc ELF64 verification."
applyTo: "**/*.rg,build.rg"
optional: false
---
# Ridgun conventions (`.rg` — `v0.9.12`)

Read and follow the `implement-code-ridgun` skill before editing any `.rg` file.

## Layout and 100% pure-Ridgun ELF64 toolchain (`v0.9.12`)
- Shared modules live in `src/main/ridgun/lib/*.rg`; executable entrypoints live in `src/main/ridgun/<target>/main.rg` (compiled directly to standalone Linux ELF64 executables at `target/<target>` without Rust, C, or `rustc`).
- Library compilation (`FR-COMP-006`): modules without `fn :: main => ()` can be compiled as `.rglib` bundles (`ridgunc build --lib <file.rg> -o <out.rglib>`) and native Linux ELF64 `ET_DYN` shared objects (`ridgunc build --so <file.rg> -o <lib.so>`), or built via `stable built lib` (`fn :: project kind => String` = `"lib"` in `build.rg`, scaffolded via `stable new --lib <name>`).
- Extensible `stable` (`FR-TOOL-003`): projects can declare custom tasks in `build.rg` (`fn :: task <name> => String`) and load plugins (`fn :: plugins => [String]`, `plugins/*.rg`, `.stable/plugins/*.rg`); inspect via `stable tasks` and `stable plugins`.
- Test suites live in `src/test/ridgun/test*.rg` (including space-separated names such as `src/test/ridgun/test basics.rg` and `src/test/ridgun/test core language.rg`) and import `test` (`assert equals` / `assert_equals`, `assert true` / `assert_true`).
- Verify every `.rg` change with `stable check` and `stable test` (or `ridgunc check <file.rg>` / `ridgunc run <file.rg>`); apply canonical tabular formatting with `stable format [file...]` (`FR-TOOL-001`, aesthetic only — not enforced by `ridgunc`); build native ELF64 binaries with `stable built` or `ridgunc build [--target x86_64-linux|arm64-linux] <entry.rg> -o <binary>`.

## Syntax invariants (never violate)
- **Comments**: `--` only (never `//`, `#`, or `/* */`). **Imports**: `import <module>` at top of file (resolved from same dir or `src/main/ridgun/lib/`, no quotes or `.rg`).
- **Signatures, Space-Separated Tuple/Sequence Types (`FR-COMP-008`), Multi-Word `fn ::` Spaces & Generics (`A`..`Z`)**: `fn ::` and `op ::` prefixes are optional (`name T1 T2 => Ret` or `fn :: name T1 T2 => Ret`; multi-word `fn :: format err AppErr => String` or mixfix `op :: word T1 word T2 => Ret`). Multi-word `fn ::` functions, `build.rg` settings (`fn :: project name => String`), and built-ins (`assert equals`, `str len`, `read file`, `cmm live blocks`) use natural spaces (`" "`) instead of `_` (`_`-joined identifiers remain backward-compatible). Argument sequences and tuples are unified (`FR-COMP-008`): space-separated return types (`=> Int Int [String String] String`), space-separated tuple elements inside list brackets (`[String String]` $\equiv$ `[(String, String)]`), and space-separated tuple elements inside parentheses (`(A B)` $\equiv$ `(A, B)`) are 100% interchangeable with comma-separated tuple syntax `(Int, Int, [(String, String)], String)`. Polymorphic type variables are **single uppercase letters (`A`..`Z`)** (e.g., `list len [A] => Int`, `fst (A B) => A`, `swap A with B => B A`), unified across arguments and substituted into the return type. **Never** put `()` before `=>` for 0-arg functions (`fn :: main => ()`, not `fn :: main () => ()`).
- **Contextual `type` and `with`**: `type` and `with` are contextual keywords and can be used freely as function names, operator words in `op ::`, parameter patterns, local variables, and record field names (`type` is only a declaration keyword at top-level `type UpperName = ...`). Do not use structural keywords (`fn`, `op`, `import`, `otherwise`, `do`, `mut`) as operator words.
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
- **Record Updates (`with`)**: Update immutable product records via `record_expr with field1 = val1, field2 = val2`.
- **Shared ADT Constructors, Type-Name Variants, `expand type`, and Automatic `fn ::` Clause Merging (`FR-COMP-005`)**:
  - Multiple `type` declarations may reuse the same constructor names (e.g., `Error`, `Var`, `Lit`, `None`); typechecking disambiguates via expected column types and argument arity/types.
  - Bare type names in sum ADTs (`type Something = String | Int | MyStruct Float Int`) include values of those types directly without redundant `Int Int` / `String String` wrappers; callers may pass bare `"hej"` / `42` or `String "hej"` / `Int 42`, and patterns match both literals and `(String s)` / `(Int n)`.
  - Extend existing Sum ADTs or Product Records with `expand type UpperName = ...` (e.g., `expand type Error = AuthError String | DbError Int String`, `expand type Something = Bool`, or `expand type Config = tls: Bool`).
  - Re-declaring `fn ::` / `op ::` for an existing function automatically merges the new pattern clauses before any base catch-all (`_`) clause (no `expand fn` keyword needed).
- **Operators, Strings & Collection Combinators (`FR-COMP-001`)**:
  - Logical operators are lowercase words: `and`, `or`, `xor`, `not` (never `&&`, `||`, `!`).
  - List prepend/concat: `[x] :: xs` or `xs :: ys` (`:` is only for pattern destructuring `(x:xs)`, never in expressions).
  - String concat: `"a" + "b"`; interpolated strings `"val: {x}"` (escape literal braces with `\{`/`\}` or `{{`/`}}`) vs raw strings `'literal {x}'`.
  - Higher-order list combinators: sequential `map f xs`, `filter p xs`, `fold f init xs`, and multicore parallel **`||map f xs`** and **`||filter p xs`**.
- **Deterministic Memory (`RMM1` / `RMM2`) & Concurrency Safety (`FR-COMP-002`)**:
  - Zero Garbage Collector: `RMM1` handles static last-use drops (`rg_cmm_drop`), zero-copy return moves, and 1-cycle pointer-identity checks (`ptr(a) != ptr(c)`); `RMM2` leaves incoming arguments untouched (`+0 / -0`), increments (`+1`) on local/container assignment, spares the returned local in transit, and cascades `-1` to child structures on scope exit.
  - Parallel `|| expr -> var` bindings must be acyclic and disjoint on slice writes (`|| val -> m[i, j]`); channels and agents enforce affine move ownership (`ErrUseAfterSend`).
- **Native Agent Model (`FR-COMP-009`)**:
  - Any `fn ::` or `op ::` function can be instantiated as an autonomous agent without special declaration keywords: `ag = agent fn` (stateless `M => R`) or `ag = agent fn init_state` (stateful `S M => S` or `S M => S R`).
  - Communicate via `send msg to ag` (or multi-argument `send a b to ag`), `receive from ag`, `try receive from ag` (`Some r | None`), `stop ag`, and `agent alive ag`, typed as `Agent In Out` (or `(Agent In Out)`). Legacy `spawn` and `join` are retired.
- **Declarative Timeouts (`with timeout`) & Cross-Platform PAL Primitives (`FR-COMP-007`)**:
  - Duration suffixes `_ms` (`* 1`), `_s` (`* 1000`), and `_min` (`* 60000`) desugar at lex time to integer milliseconds (`Int`).
  - `with timeout 500_ms do ...` (or `with region 64_MB, timeout 500_ms do ...`) pushes a monotonic deadline onto the execution context stack (`sys deadline ms => Int`, `sys remaining ms => Int`) and automatically clamps `sys poll` inside the block.
  - Cross-platform PAL built-ins & target ADTs (`type SysOs = Linux | MacOS | Windows`, `type SysArch = X86_64 | Arm64`): `sys os => SysOs`, `sys arch => SysArch`, `sys open mode path mode_str => Int`, `sys open path flags mode => Int`, `sys close fd => Int`, `sys read fd fd max_bytes => String`, `sys write fd fd data => Int`, `sys poll fd events timeout_ms => Int`, `sys terminate pid force => Int`, `sys kill pid sig => Int`, `sys call nr a1 a2 a3 a4 a5 a6 => Int`, `sys getpid => Int`, `sys time ms => Int`, `sys sleep ms ms => ()`.
