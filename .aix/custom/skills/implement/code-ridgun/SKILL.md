---
name: implement-code-ridgun
description: Implement, refactor or review Ridgun (.rg) code and build.rg definitions using the exact Ridgun v0.9.x grammar, type system, memory-region rules, parallel where-DAGs, and stable/ridgunc toolchain; use for any Ridgun (.rg) change.
---
# implement-code-ridgun

Reading budget: `docs/lang/spec.md` (only when a construct is unfamiliar), `build.rg`, and the target `.rg` files under `src/main/ridgun/` or `src/test/ridgun/`.

## 1. Project & Directory Layout (v0.9.1+)
- `build.rg`: Root project definition (`project_name`, `project_version`, `main_entry`, `source_dir`, `test_dir`, `target_dir`).
- `src/main/ridgun/lib/*.rg`: Shared library modules (imported by name, e.g. `import ast`, from any executable or test).
- `src/main/ridgun/<target>/main.rg`: Parallel executable entrypoints; each `<target>/main.rg` compiles to `target/<target>`.
- `src/test/ridgun/test_*.rg`: Executable test suites importing `test` (`import test`, `assert_equals`, `assert_true`).

## 2. Core Syntax Rules & LLM Pitfalls to Avoid
1. **Comments & Imports**: Line comments use `--` (never `//` or `#`). Top-of-file imports use `import module_name` (no quotes, no `.rg` extension).
2. **Function Signatures (`fn ::`)**:
   - With parameters: `fn :: add Int Int => Int` followed by cases `add x y = x + y`.
   - Zero parameters: `fn :: main => ()` (no `()` before `=>`!) followed by `main = ...`.
   - Variadic last parameter: `fn :: sum_all Int... => Int`.
3. **Pattern Matching & Guards (`|`) — CRITICAL**:
   - Multiple cases repeat the function name:
     ```ridgun
     fn :: fib Int => Int
     fib 0 = 0
     fib 1 = 1
     fib n = (fib (n - 1)) + (fib (n - 2))
     ```
   - Guards omit `=` after patterns and put `| cond = expr` on indented lines:
     ```ridgun
     fn :: clamp Int Int Int => Int
     clamp x lo hi
       | x < lo = lo
       | x > hi = hi
       | otherwise = x
     ```
   - **NEVER put a newline immediately after `=` in a guard (`| cond =`)**. The expression after `| cond =` MUST start on the same line. If a guarded branch needs multiple statements, call a helper function.
   - **No `if/then/else` or `match/case` keywords**: always use pattern matching cases or guards (`| cond = expr` / `| otherwise = expr`).
4. **Indented Statement Blocks**:
   - Allowed ONLY after an unguarded `fn_name pats =` followed by a newline and 2-space indentation:
     ```ridgun
     fn :: run_step String => Int
     run_step path =
       raw = read_file path
       _ = echo "Loaded {path}"
       str_len raw
     ```
   - Discard `()` return values of intermediate side-effect calls with `_ = ...`; the last line of the block is the return value.
5. **Logical, Comparison & List Operators**:
   - Logical operators are UPPERCASE words: `AND`, `OR`, `XOR`, `NOT` (never `&&`, `||`, `!`).
   - List literal: `[1, 2, 3]`. Pattern destructuring: `[]`, `(x:xs)`, `(a:b:[])`.
   - List concatenation uses `::` between two lists: `[head_item] :: tail_list` or `list_a :: [last_item]`.
   - String concatenation uses `+`: `"hello " + name`.
6. **Strings: Interpolated (`"..."`) vs Raw (`'...'`)**:
   - Double quotes `"Hello, {name}!"` interpolate variables `{var}` or expressions `{fn x}`. Escape literal braces as `{{` and `}}`.
   - Single quotes `'raw text with {braces} and "quotes"'` are raw strings (no interpolation, no backslash escaping).

## 3. Types, ADTs, Records, and Custom Operators
- **Primitives**: `Int`, `Real`, `String`, `Bool` (`True`, `False`), `()` (Unit), `[T]` (List), `(A, B)` (Tuple), `Tensor(i, j)`.
- **Sum ADTs**:
  ```ridgun
  type Option a = None | Some a
  type Result a e = Ok a | Err e
  ```
  Match constructors in parentheses when they take arguments: `unwrap (Some x) = x`.
- **Product Records**:
  ```ridgun
  type Point = x: Real, y: Real
  ```
  Construct with `Point 3.0 4.0`; access fields via auto-generated functions `x pt`, `y pt`.
- **Low-level Layout Attributes**: `@packed`, `@repr(C)`, `@align(64)` before `type`.
- **Operator Overloading & Natural-Language Mixfix (`op ::`)**:
  - Prefix, infix, postfix, or mixfix: `op :: execute command [String] on StableConfig => (Bool, StableConfig, Int)` or `op :: file String exists => Bool`.
  - Parameter slots in `op ::` can be uppercase type names (`Int`, `String`, `StableConfig`), list types (`[String]`), or tuple types (`(Bool, String)`).
  - Longest-match resolution: if `op :: a b c d`, `op :: a b`, and `op :: c d` exist, `a b c d` calls `a_b_c_d`; use parentheses `a b (c d)` to pass the result of `c d` into `a b`.
  - Never use reserved lexer keywords (`fn`, `op`, `type`, `import`, `where`, `otherwise`, `do`, `atomic`) as operator keyword words (`with` is explicitly allowed).

## 4. Parallelism, Tensors, Concurrency & Memory Regions
- **Parallel Producer-Consumer `where` DAGs**:
  Independent bindings in a `where` block execute in parallel; dataflow dependencies (`->`) form an automatic DAG checked for cycles and disjoint mutations at compile time:
  ```ridgun
  fn :: pipeline Int => Int
  pipeline x = left + right
    where
      heavy_a x -> left
      heavy_b x -> right
  ```
  Disjoint slice write in `where`: `compute_cell i j -> grid[i, j]`.
- **Parallel Pipes (`||`)**: `branch_a x || branch_b x` evaluates branches concurrently into a tuple.
- **Tensors & Einstein Summation**:
  - Symbolic shapes checked at compile time: `fn :: matmul Tensor(i, k) Tensor(k, j) => Tensor(i, j)`.
  - Einsum contraction: `A_ik * B_kj`. Hadamard element-wise op: `A_ij + B_ij` or `A_ij * B_ij`.
  - Indexing & in-place mutation: `val = m[0, 1]` and `m[0, 1] = 9.5`.
- **Channels & Affine Ownership**:
  - `ch = channel ()`, ` _ = send ch payload`, `msg = recv ch`.
  - **Affine move rule**: after `send ch payload`, `payload` is moved and MUST NOT be read again in the sender (enforced by static analyzer `ErrUseAfterSend`).
- **Scoped Context, Shared Atomics & Region Quotas**:
  - `context logger = "default"` / `with logger = "json" do expr`.
  - `shared hits = 0` / `atomic hits = hits + 1`.
  - `with region 64_KB do expr` (enforces deterministic non-GC region byte quota; units `_KB`, `_MB`, `_GB`).
  - Bare-metal MMIO: `hardware UART at 0x4000_1000` with `STATUS : u32 @ 0x00`.

## 5. Built-in Runtime Functions (`src/main/ridgun/lib/compiler.rg`)
| Function | Signature | Description |
|---|---|---|
| `echo a b ...` | variadic `=> ()` | Print space-separated values with newline |
| `expr out` | postfix `T => ()` | Print value and return `()` |
| `str_len s` | `String => Int` | Length of string |
| `str_char_at s idx` | `String Int => Int` | ASCII/Unicode code point at index (`-1` if out of bounds) |
| `str_slice s start end` | `String Int Int => String` | Substring `[start..end)` |
| `char_from_code code` | `Int => String` | Single-character string from code point (e.g. `27` for ESC) |
| `int_to_str n` / `str_to_int s` | `Int => String` / `String => Int` | Integer/string conversion (supports `0x` hex and `_`) |
| `str_starts_with s p` | `String String => Bool` | Prefix check |
| `str_contains s needle` | `String String => Bool` | Substring check |
| `read_file path` | `String => String` | Read file contents (recursively resolves `import` for `.rg`) |
| `write_file path content` | `String String => ()` | Write string to file |
| `shell_exec cmd` | `String => Int` | Execute shell command via `sh -c` and return exit code |
| `cli_args` | `=> [String]` | Command-line arguments list |
| `spawn "fn_name" arg` / `join tid` | `String a => Int` / `Int => b` | Spawn parallel task by function name and join result |

## 6. Verification Procedure
1. Place shared modules in `src/main/ridgun/lib/` and executable entrypoints in `src/main/ridgun/<target>/main.rg`.
2. Run `./target/stable format [file...]` to apply canonical aesthetic column-alignment formatting (`FR-TOOL-001`, aesthetic only — not enforced by `ridgunc`).
3. Run `./target/stable check` to typecheck and run static analysis across all modules (`0 errors`).
4. Run `./target/stable test` to compile and execute all `src/test/ridgun/test_*.rg` suites.
5. If compiler/tool sources changed, run `./target/stable built` (or `./target/stable built <target>`) to rebuild native binaries in `target/`.
