# AGENTS.md — Ridgun Agent Harness (`v0.9.21`)

Drop-in agent instructions for any AI coding assistant working on a **Ridgun (`.rg`)** repository.

## 1. Before Touching Any `.rg` File or `build.rg`
1. Read `harness/instructions/ridgun.md` (syntax & memory invariants) and `harness/instructions/stable.md` (`stable` project manager, `build.rg`, libraries, custom tasks, and plugins).
2. Read `harness/skills/implement-code-ridgun/SKILL.md` (complete grammar, idiomatic `->` pipeline chaining, `(+ _ _ +)` sequence masks, `_ =`-free blocks, anti-patterns table, built-in runtime functions, and toolchain workflow) and `harness/skills/implement-stable-project/SKILL.md` (`stable` commands, `.rglib`/`.so` library builds, custom tasks, and framework plugins).
3. Inspect `harness/skills/implement-code-ridgun/references/cheatsheet.rg`, `harness/skills/implement-stable-project/references/build_cheatsheet.rg`, and `harness/skills/implement-stable-project/references/plugin_cheatsheet.rg` for canonical, verified examples.

## 2. Core Golden Rules of Ridgun (`v0.9.21`)
1. **100% Pure Ridgun Toolchain (Executables & Reusable Libraries)**:
   - The compiler (`./bin/ridgunc` / `target/ridgunc`) and project manager/formatter (`./bin/stable` / `target/stable`) are 100% self-hosted in Ridgun (`src/main/ridgun/`) and emit standalone Linux ELF64 executables (`x86_64` and `ARM64` / Raspberry Pi), `.rglib` library bundles (`ridgunc build --lib`), and ELF64 `ET_DYN` shared objects (`ridgunc build --so`, `stable built lib`) directly without Rust, C, or `rustc`.
2. **Idiomatic Left-to-Right Pipeline Chaining (`->`), `(+ _ _ +)` Sequence Masks & `_ =`-Free Blocks (`FR-COMP-014`)**:
   - Prefer the recommended idiomatic Ridgun pipeline style (`2b`): start with a natural infix call and chain stages with `->` into a terminal target variable (`xs map (x => x * 2) -> filter (x => x > 6) -> compact limit 14 -> results`).
   - Any value piped from the left of `->` (or left of an infix call `x f a b`) enters as the **first argument** of the right-hand `fn ::` or `op ::` (`x -> f a b` $\equiv$ `x f a b` $\equiv$ `f x a b`, or use `_` placeholder: `payload -> write_file path _`).
   - Filter/unpack multi-value tuple returns right inside a pipeline using `-> (+ _ _ +) ->` (`parse header packet "v0.9.21" -> (+ _ _ +) -> combine status -> summary`), and pipe into agents via `-> send to ag` or `-> ask to ag`.
   - Never write `_ =` before side-effect statements (`echo`, `write_file`, `shell_exec`, `log`, etc.); append `-> ()` (`shell_exec cmd -> ()`) when the final expression of a `=> ()` function needs to discard a non-`()` return value.
3. **Natural Space-Separated Function Names & Unified Tuple/Sequence Signatures (`FR-COMP-005`, `FR-COMP-008`)**:
   - Always use natural spaces instead of `_` in multi-word function names (`fn :: format app err AppErr => String`), `build.rg` settings (`fn :: project name => String`), and built-in calls (`assert equals`, `str len`, `read file`, `sys poll`).
   - Argument sequences and tuples are unified (`FR-COMP-008`): prefer clean space-separated tuple and return type signatures (`=> Int Int [String String] String`, `[String String]`, `(A B)`) over comma-heavy `(Int, Int, [(String, String)], String)`.
4. **Extensible `stable` Tasks & Plugins (`FR-TOOL-003`)**:
   - Projects can define custom `fn :: task <name> => String` commands and `fn :: plugins => [String]` extensions in `build.rg` or `plugins/*.rg` (inspected via `stable tasks` and `stable plugins`).
5. **Tabular 2D Alignment (`=>`, `=`, `->`)**:
   - Type signatures act as column headers; pattern clauses align arguments under their types and `=` under `=>`. Always run `./bin/stable format <file.rg>` after editing.
6. **Unified `=` Block Grammar (`(none)`, `|`, `||`) & Compact Closers (`|.` / `||.`)**:
   - Every clause, local binding (`x =` / `mut x =`), and guard branch (`| cond =` / `| otherwise =`) ends with `=`.
   - Use **`|.`** (preferably inline: `| otherwise = val |.`) when a nested `|` decision tree returns to an outer branch or statement below it.
   - Use **`|| expr -> var`** for parallel DAG bindings (the `where` keyword does not exist in Ridgun), and **`||.`** when returning from an inline `||` block to sequential statements below.
7. **Immutable by Default (`x = ...`) vs Explicit Mutable (`mut x = ...`)**:
   - Local variables are immutable constants unless declared with `mut x = expr`.
   - Logical operators are lowercase words: `and`, `or`, `xor`, `not`.
   - Use `xs map f`, `xs filter p`, `xs fold init f` for sequential traversal, and **`xs ||map f`** / **`xs ||filter p`** for multicore parallel traversal.
8. **Deterministic Memory Without GC (`RMM1` & `RMM2`)**:
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
