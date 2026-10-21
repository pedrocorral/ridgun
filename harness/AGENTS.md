# AGENTS.md — Ridgun Agent Harness (`v0.9.3`)

Drop-in agent instructions for any AI coding assistant working on a **Ridgun (`.rg`)** repository.

## 1. Before Touching Any `.rg` File
1. Read `harness/instructions/ridgun.md` (syntax & memory invariants).
2. Read `harness/skills/implement-code-ridgun/SKILL.md` (complete grammar, anti-patterns table, built-in runtime functions, and toolchain workflow).
3. Inspect `harness/skills/implement-code-ridgun/references/cheatsheet.rg` for canonical, verified examples of every Ridgun construct.

## 2. Core Golden Rules of Ridgun (`v0.9.3`)
1. **100% Pure Ridgun Toolchain**:
   - The compiler (`target/ridgunc`) and project manager/formatter (`target/stable`) are 100% self-hosted in Ridgun (`src/main/ridgun/`) and emit standalone Linux ELF64 executables (`x86_64` and `ARM64` / Raspberry Pi) directly without Rust, C, or `rustc`.
2. **Tabular 2D Alignment (`=>`, `=`, `->`)**:
   - Type signatures act as column headers; pattern clauses align arguments under their types and `=` under `=>`. Always run `./target/stable format <file.rg>` after editing.
3. **Unified `=` Block Grammar (`(none)`, `|`, `||`) & Compact Closers (`|.` / `||.`)**:
   - Every clause, local binding (`x =` / `mut x =`), and guard branch (`| cond =` / `| otherwise =`) ends with `=`.
   - Use **`|.`** (preferably inline: `| otherwise = val |.`) when a nested `|` decision tree returns to an outer branch or statement below it.
   - Use **`|| expr -> var`** for parallel DAG bindings (the `where` keyword does not exist in Ridgun), and **`||.`** when returning from an inline `||` block to sequential statements below.
4. **Immutable by Default (`x = ...`) vs Explicit Mutable (`mut x = ...`)**:
   - Local variables are immutable constants unless declared with `mut x = expr`.
   - Logical operators are lowercase words: `and`, `or`, `xor`, `not`.
   - Use `map`, `filter`, `fold` for sequential traversal, and **`||map`** / **`||filter`** for multicore parallel traversal.
5. **Deterministic Memory Without GC (`RMM1` & `RMM2`)**:
   - Incoming function arguments are untouched (`+0 / -0`), local/container assignments increment (`+1`), returned locals are spared in transit, and non-returned locals cascade `-1` on scope exit.

## 3. Verification Loop (Run After Every Change)
```bash
# 1. Format into canonical tabular style
./target/stable format

# 2. Type-check and run static DAG/RMM analysis across all modules
./target/stable check

# 3. Compile & run all test suites in parallel
./target/stable test

# 4. Build standalone ELF64 executables (x86_64 or ARM64 Raspberry Pi)
./target/stable built
./target/ridgunc build --target arm64-linux src/main/ridgun/ridgunc/main.rg -o /tmp/ridgunc_arm64
```
