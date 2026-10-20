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
2. **Function & Operator Signatures (`fn ::`, `op ::`, and Generics `A`..`Z`)**:
   - `fn ::` and `op ::` prefixes are optional (`add Int Int => Int` or `fn :: add Int Int => Int`).
   - Zero parameters: `fn :: main => ()` (never put `()` before `=>`!) followed by `main = ...`.
   - Variadic last parameter: `fn :: sum_all Int... => Int`.
   - **Parametric Polymorphism (`A`..`Z`)**: Single uppercase letters (`A`..`Z`) are polymorphic type variables unified across arguments and substituted into the return type:
     ```ridgun
     list_len [A]    => Int
     list_len []     =  0
     list_len (_:xs) =  1 + (list_len xs)

     fst (A, B) => A
     fst (a, _) =  a

     head_or [A]    A => A
     head_or []     d =  d
     head_or (x:_)  _ =  x
     ```
3. **Unified `=` Grammar (`(none)`, `|`, `||`) & Nested Block Closers (`|.` / `||.`) (`FR-COMP-003`)**:
   - Every function clause (`fn ::`), operator clause (`op ::`), local variable binding (`x =` / `mut x =`), and guard branch (`| cond =` / `| otherwise =`) ends with `=` and accepts: (1) inline expression (with optional `|| expr -> var` below), (2) sequential indented lines `(none)`, (3) conditional guard block `| cond = ...`, or (4) parallel block `|| expr -> var` / `|| expr` (`where` is removed).
   - Guarded clauses always include `=` before the guard block (`name pats =` followed by `| cond = ...`), local variables can be assigned via `|` (`x =` followed by `| cond = ...`), and guards can nest up to 4+ levels (`|` inside `| cond =` or `| otherwise =`).
   - When a nested `|` or `||` block finishes and execution returns to an outer level below it, close the inner block with `|.` (or `||.`), preferably inline at the end of its last line (`| otherwise = val |.`).
4. **Immutable (`x = ...`) vs Mutable (`mut x = ...`) Local Variables**:
   - Local bindings `x = expr` are immutable by default; declare mutable variables with `mut x = expr` and reassign them in the same scope with `x = new_expr` (under `RMM2`, `new_expr` gets `+1` before old `x` gets `-1`).
   - Discard `()` return values of intermediate side-effect calls with `_ = ...`; the last line of the block is the return value.
5. **Logical, Comparison, List & Higher-Order Operators**:
   - Logical operators are lowercase words: `and`, `or`, `xor`, `not` (never `&&`, `||`, `!`).
   - List literal: `[1, 2, 3]`. Pattern destructuring: `[]`, `(x:xs)`, `(a:b:[])`.
   - List concatenation uses `::` between two lists: `[head_item] :: tail_list` or `list_a :: [last_item]`.
   - String concatenation uses `+`: `"hello " + name`.
   - Higher-order collection operations (`FR-COMP-001`): `map f xs`, `filter p xs`, and `fold f init xs` execute sequentially left-to-right; **`||map f xs`** and **`||filter p xs`** execute in parallel across multicore worker threads.
6. **Strings: Interpolated (`"..."`), Brace Escaping (`\{`/`\}` and `{{`/`}}`), and Raw (`'...'`)**:
   - Double quotes `"Hello, {name}!"` interpolate variables `{var}` or expressions `{fn x}`.
   - Escape literal braces inside `"..."` using EITHER `\{` and `\}` (e.g., `"\$\{VAR:-default\}"`) OR `{{` and `}}` (e.g., `"{{braces}}"`).
   - Single quotes `'raw text with {braces} and "quotes"'` are raw strings (no interpolation, no backslash escaping).

## 3. Types, ADTs, Record Updates (`with`), and Contextual Keywords
- **Primitives**: `Int`, `Real`, `String`, `Bool` (`True`, `False`), `()` (Unit), `[T]` (List), `(A, B)` (Tuple), `Tensor(i, j)`.
- **Sum ADTs**:
  ```ridgun
  type Option A = None | Some A
  type Result A E = Ok A | Err E
  ```
  Match constructors in parentheses when they take arguments: `unwrap (Some x) = x`.
- **Product Records & Functional Record Updates (`with`)**:
  ```ridgun
  type LsSpec = one_per_line: Bool, color: Bool, width: Int
  ```
  - Construct positionally: `default_spec = LsSpec False False 80`.
  - Read fields via auto-generated accessors: `color spec`, `width spec`.
  - **Update one or more fields immutably using `with` and colons `:`**:
    ```ridgun
    spec1 = default_spec with color: True
    spec2 = spec1 with one_per_line: True, width: 120
    ```
- **Contextual `type` and `with`**:
  - `type` and `with` are **contextual keywords**: `type` only starts a type declaration at the top level when followed by `UpperName =`.
  - Inside `fn ::`, `op ::`, patterns, blocks, and record definitions, `type` and `with` can be used freely as function names, operator words, parameter names, local variables, or record field names:
    ```ridgun
    op :: format String type String with Int => String
          format label  type kind   with w   =  "{label}:{kind}:{w}"
    ```
- **Low-level Layout Attributes**: `@packed`, `@repr(C)`, `@align(64)` before `type`.
- **Operator Overloading & Natural-Language Mixfix (`op ::`)**:
  - Prefix, infix, postfix, or mixfix: `op :: execute command [String] on StableConfig => (Bool, StableConfig, Int)` or `op :: file String exists => Bool`.
  - Parameter slots in `op ::` can be uppercase type names (`Int`, `String`, `StableConfig`), single-letter type variables (`A`..`Z`), list types (`[String]`, `[A]`), or tuple types (`(Bool, String)`).
  - Longest-match resolution: if `op :: a b c d`, `op :: a b`, and `op :: c d` exist, `a b c d` calls `a_b_c_d`; use parentheses `a b (c d)` to pass the result of `c d` into `a b`.
  - Do not use structural keywords (`fn`, `op`, `import`, `where`, `otherwise`, `do`, `atomic`) as operator words (`type` and `with` ARE allowed).

## 4. Parallelism, Tensors, Concurrency & Memory Regions
- **Parallel Producer-Consumer `where` DAGs**:
  Independent bindings in a `where` block execute in parallel; dataflow dependencies (`->`) form an automatic DAG checked for cycles and disjoint mutations at compile time:
  ```ridgun
  fn :: pipeline Int => Int
        pipeline x   =  left + right
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
| `read_file path` | `String => String` | Read file contents verbatim |
| `write_file path content` | `String String => ()` | Write string to file |
| `shell_exec cmd` | `String => Int` | Execute shell command via `sh -c` and return exit code |
| `cli_args` | `=> [String]` | Command-line arguments list |
| `spawn "fn_name" arg` / `join tid` | `String A => Int` / `Int => B` | Spawn parallel task by function name and join result |

## 6. Verification Procedure (Assume `ridgunc` and `stable` are in `PATH`)
Always invoke `ridgunc` and `stable` directly by name (never prefix them with relative paths):
1. Place shared modules in `src/main/ridgun/lib/` and executable entrypoints in `src/main/ridgun/<target>/main.rg`.
2. Run `stable format [file...]` to apply canonical aesthetic column-alignment formatting (`FR-TOOL-001`, aesthetic only — not enforced by `ridgunc`).
3. Run `stable check` (or `ridgunc check <file.rg>`) to typecheck and run static analysis across all modules (`0 errors`).
4. Run `stable test` (or `ridgunc run <test_file.rg>`) to compile and execute test suites.
5. Run `stable built` (or `ridgunc build <entry.rg> -o <binary>`) to build standalone native ELF binaries.
