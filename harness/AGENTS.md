# AGENTS.md — Ridgun Agent Harness (`v0.9.10`)

Drop-in agent instructions for any AI coding assistant working on a **Ridgun (`.rg`)** repository.

## 1. Before Touching Any `.rg` File or `build.rg`
1. Read `harness/instructions/ridgun.md` (syntax & memory invariants) and `harness/instructions/stable.md` (`stable` project manager, `build.rg`, libraries, custom tasks, and plugins).
2. Read `harness/skills/implement-code-ridgun/SKILL.md` (complete grammar, anti-patterns table, built-in runtime functions, and toolchain workflow) and `harness/skills/implement-stable-project/SKILL.md` (`stable` commands, `.rglib`/`.so` library builds, custom tasks, and framework plugins).
3. Inspect `harness/skills/implement-code-ridgun/references/cheatsheet.rg`, `harness/skills/implement-stable-project/references/build_cheatsheet.rg`, and `harness/skills/implement-stable-project/references/plugin_cheatsheet.rg` for canonical, verified examples.

## 2. Core Golden Rules of Ridgun (`v0.9.10`)
1. **100% Pure Ridgun Toolchain (Executables & Reusable Libraries)**:
   - The compiler (`./bin/ridgunc` / `target/ridgunc`) and project manager/formatter (`./bin/stable` / `target/stable`) are 100% self-hosted in Ridgun (`src/main/ridgun/`) and emit standalone Linux ELF64 executables (`x86_64` and `ARM64` / Raspberry Pi), `.rglib` library bundles (`ridgunc build --lib`), and ELF64 `ET_DYN` shared objects (`ridgunc build --so`, `stable built lib`) directly without Rust, C, or `rustc`.
2. **Natural Space-Separated Function Names & Unified Tuple/Sequence Signatures (`FR-COMP-005`, `FR-COMP-008`)**:
   - Always use natural spaces instead of `_` in multi-word function names (`fn :: format app err AppErr => String`), `build.rg` settings (`fn :: project name => String`), and built-in calls (`assert equals`, `str len`, `read file`, `sys poll`).
   - Argument sequences and tuples are unified (`FR-COMP-008`): prefer clean space-separated tuple and return type signatures (`=> Int Int [String String] String`, `[String String]`, `(A B)`) over comma-heavy `(Int, Int, [(String, String)], String)`.
3. **Extensible `stable` Tasks & Plugins (`FR-TOOL-003`)**:
   - Projects can define custom `fn :: task <name> => String` commands and `fn :: plugins => [String]` extensions in `build.rg` or `plugins/*.rg` (inspected via `stable tasks` and `stable plugins`).
4. **Tabular 2D Alignment (`=>`, `=`, `->`)**:
   - Type signatures act as column headers; pattern clauses align arguments under their types and `=` under `=>`. Always run `./bin/stable format <file.rg>` after editing.
5. **Unified `=` Block Grammar (`(none)`, `|`, `||`) & Compact Closers (`|.` / `||.`)**:
   - Every clause, local binding (`x =` / `mut x =`), and guard branch (`| cond =` / `| otherwise =`) ends with `=`.
   - Use **`|.`** (preferably inline: `| otherwise = val |.`) when a nested `|` decision tree returns to an outer branch or statement below it.
   - Use **`|| expr -> var`** for parallel DAG bindings (the `where` keyword does not exist in Ridgun), and **`||.`** when returning from an inline `||` block to sequential statements below.
6. **Immutable by Default (`x = ...`) vs Explicit Mutable (`mut x = ...`)**:
   - Local variables are immutable constants unless declared with `mut x = expr`.
   - Logical operators are lowercase words: `and`, `or`, `xor`, `not`.
   - Use `map`, `filter`, `fold` for sequential traversal, and **`||map`** / **`||filter`** for multicore parallel traversal.
7. **Deterministic Memory Without GC (`RMM1` & `RMM2`)**:
   - Incoming function arguments are untouched (`+0 / -0`), local/container assignments increment (`+1`), returned locals are spared in transit, and non-returned locals cascade `-1` on scope exit.

## 3. Verification Loop (Run After Every Change)
```bash
# 1. Format into canonical tabular style
./bin/stable format

# 2. Type-check and run static DAG/RMM analysis across all modules
./bin/stable check

# 3. Compile & run all test suites in parallel
./bin/stable test

# 4. Build standalone ELF64 executables or reusable libraries (.rglib / .so)
./bin/stable built
./bin/stable built lib
./bin/ridgunc build --lib my_lib.rg -o my_lib.rglib
./bin/ridgunc build --so my_lib.rg -o libmy_lib.so
./bin/ridgunc build --target arm64-linux src/main/ridgun/ridgunc/main.rg -o /tmp/ridgunc_arm64
```
