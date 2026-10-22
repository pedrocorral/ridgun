---
name: implement-code-ridgun
description: Implement, refactor or review Ridgun (.rg) code and build.rg definitions using the exact Ridgun v0.9.7 grammar, type system, RMM1/RMM2 deterministic memory rules, parallel || DAGs, with timeout quotas, PAL primitives, and pure-Ridgun stable/ridgunc ELF64 toolchain; use for any Ridgun (.rg) change.
---
# implement-code-ridgun (`v0.9.7`)

Reading budget: `harness/skills/implement-code-ridgun/references/cheatsheet.rg` (or `docs/lang/spec.md` when a construct is unfamiliar), `build.rg`, and the target `.rg` files under `src/main/ridgun/` or `src/test/ridgun/`.

---

## 1. Project & Architecture Overview (`v0.9.7`)
- **100% Pure Ridgun (Zero Rust / Zero `rustc`)**: Both `ridgunc` (`src/main/ridgun/ridgunc/main.rg`) and `stable` (`src/main/ridgun/stable/main.rg`) are written 100% in Ridgun and emit standalone, statically linked Linux ELF64 executables directly to disk via `elf64.rg`, `x86_64.rg` (`EM_X86_64 = 62`), and `arm64.rg` (`EM_AARCH64 = 183` for Raspberry Pi).
- **Project Layout**:
  - `build.rg`: Pure-Ridgun project manifest (`fn :: project name => String`, `project version`, `main entry`, `source dir`, `test dir`, `target dir`).
  - `src/main/ridgun/lib/*.rg`: Shared library modules (`ast`, `lexer`, `parser`, `typecheck`, `analyzer`, `compiler`, `elf64`, `x86_64`, `arm64`, `formatter`, `vm`). Imported by bare module name (`import ast`).
  - `src/main/ridgun/<target>/main.rg`: Executable entrypoints (`ridgunc/main.rg` -> `target/ridgunc`, `stable/main.rg` -> `target/stable`).
  - `src/test/ridgun/test*.rg`: Executable test suites (`test basics.rg`, `test core language.rg`, etc.; `import test`, `assert equals`, `assert true`), compiled and run in parallel by `stable test` via `||map`.

---

## 2. LLM Anti-Patterns: "Never Write This → Write This Instead"

| Common LLM Mistake (INVALID) | Correct Ridgun `v0.9.5` (VALID) | Why |
|---|---|---|
| `// comment` or `# comment` | `-- comment` | Only `--` starts a comment |
| `import "lib/ast.rg"` | `import ast` | Bare module identifier, no quotes or path |
| `fn :: main () => ()` | `fn :: main => ()` | 0-arg functions never put `()` before `=>` |
| `x : xs` in an expression | `[x] :: xs` | `:` is only for pattern matching `(x:xs)`; `::` concatenates two lists |
| `a && b`, `a \|\| b`, `!a` | `a and b`, `a or b`, `not a`, `a xor b` | Logical operators are lowercase words (`\|\|` is the parallel block/combinator prefix) |
| `where` block | `\|\| expr -> var` | `where` was removed in `FR-COMP-003`; use `\|\|` parallel DAG lines |
| Guard clause without `=` (`clamp x lo hi \| x < lo = lo`) | `clamp x lo hi =` followed by `\| x < lo = lo` | Every clause and guard branch requires `=` (`FR-COMP-003`) |
| Reassigning `x = x + 1` after `x = 0` | `mut x = 0` then `x = x + 1` | Local bindings are immutable unless declared with `mut` |
| `par_map f xs` / `par_filter p xs` | `\|\|map f xs` / `\|\|filter p xs` | Parallel higher-order combinators use the `\|\|` prefix (`FR-COMP-001`) |
| `map (\x -> x * 2) xs` | `map double val xs` (with `fn :: double val Int => Int`) | Higher-order combinators take named top-level functions (`FR-COMP-001` / `FR-COMP-005`) |
| `(a, b) = compute_pair x` in local block | `res = compute pair x` then `a = fst res` (or destructure in function clause `helper (a, b) = ...`) | Local `=` binds a single variable name (`x = ...` or `mut x = ...`) |
| `Some x` in function argument pattern without parens | `unwrap (Some x) = x` | Constructor patterns with arguments must be parenthesized |

---

## 3. Core Syntax & Grammar Rules

### 3.1 Signatures, Natural Spaces in `fn ::`, Clauses & Zero-Noise Generics (`A`..`Z`)
- `fn ::` and `op ::` prefixes are optional (`add Int Int => Int` or `fn :: add Int Int => Int`).
- **Natural-Language Spaces in `fn ::` and Built-in Calls (`FR-COMP-005`)**: Both `fn ::` and `op ::` support multi-word names separated by spaces (`fn :: format app err AppErr => String`, `fn :: project name => String`), and built-in/test functions can be called with spaces (`assert equals a b`, `str len s`, `read file p`, `cmm live blocks`) while keeping `_` backward-compatible.
- **Tabular Column Alignment (`=>`, `=`, `->`)**: Each clause aligns its words and arguments under the corresponding tokens in the signature and aligns `=` under `=>`. Run `stable format` to format automatically.
- **Parametric Polymorphism (`A`..`Z`)**: Single uppercase letters (`A`..`Z`) are polymorphic type variables unified across arguments and substituted into the return type:
  ```ridgun
  fn :: list len [A]    => Int
        list len []     =  0
        list len (_:xs) =  1 + (list len xs)

  fn :: fst (A, B) => A
        fst (a, _) =  a

  fn :: head or [A]   A => A
        head or []    d =  d
        head or (x:_) _ =  x
  ```
- **Variadic Last Parameter (`T...`)**:
  ```ridgun
  fn :: sum variadic Int... => Int
        sum variadic items  =  fold add pair 0 items
  ```

### 3.2 Unified `=` Grammar (`(none)`, `|`, `||`) & Closers (`|.` / `||.`) (`FR-COMP-003`)
Every `=` (in `fn ::`, `op ::`, local bindings `x =` / `mut x =`, and guard branches `| cond =` / `| otherwise =`) accepts four right-hand-side forms:

1. **Sequential Block (`(none)`)**: Indented statements evaluated top-to-bottom; the last expression is the return value. Discard `()` side-effects with `_ = ...`.
2. **Conditional Guard Block (`|`)**:
   - Used in function/operator clauses, conditional local variables (`discount = | is_vip = 20 | otherwise = 0`), and nested 3–4+ level decision trees.
   - When a nested `|` sub-tree finishes and execution returns to an outer branch or statement below it, close the inner block with **`|.`** (preferably inline at the end of its last branch: `| otherwise = val |.`).
   ```ridgun
   fn :: route_request Int    Int  Bool      Bool     Int        Int          => Int
         route_request method role is_signed is_admin payload_kb rate_limited =
           | method == 0 =
             | payload_kb == 0 = 204
             | otherwise       = 200 |.
           | method == 1 =
             | not is_signed = 401
             | otherwise =
               | rate_limited > 0 =
                 | is_admin  = 202
                 | otherwise = 429 |.
               | otherwise = 201 |.
           | otherwise = 405
   ```
3. **Parallel DAG Block (`|| expr -> var` and `||.`)**:
   - Evaluates independent branches in parallel, automatically ordering dataflow dependencies (`->`). Static analysis (`analyzer.rg`) rejects dependency cycles (`ErrDagCycle`) at compile time.
   - Can appear below an inline header expression or at the start/middle of a block (closed with `||.` when sequential lines follow):
   ```ridgun
   -- Header expression fed by parallel || DAG lines below:
   fn :: parallel_dag_calc Int  => Int
         parallel_dag_calc base =  net_a + net_b
           || base * 3          -> raw_a
           || base * 5          -> raw_b
           || raw_a - 2         -> net_a
           || raw_b + 1         -> net_b

   -- Parallel || DAG block at the top of a function, closed with ||. before final expression:
   fn :: parallel_dag_bottom Int  => Int
         parallel_dag_bottom base =
           || base + 10           -> left
           || base * 2            -> right ||.
           left + right
   ```
4. **Anonymous Parallel Tuple (`|| expr`)**:
   - `|| expr_a` followed by `|| expr_b` with no `-> var` evaluates both concurrently and returns `(val_a, val_b)`.

### 3.3 Immutable (`x = ...`) vs Mutable (`mut x = ...`) Local Bindings
- `x = expr` is **immutable**. Rebinding `x = ...` in the same scope without `mut` fails typechecking (`ErrImmutableReassign`).
- Declare mutable variables with `mut x = expr` and update them with `x = new_expr`:
  ```ridgun
  fn :: mut_accum Int => Int
        mut_accum n   =
          mut acc = n
          acc = acc + 10
          acc = acc * 2
          acc
  ```

### 3.4 First-Class Named Functions & Parallel Higher-Order Combinators (`FR-COMP-001`)
- Function types use `(T1 T2 => Ret)` inside signatures: `fn :: apply twice (Int => Int) Int => Int`.
- Pass named top-level functions by bare single-word or space-separated multi-word name (`map double val xs`, `filter is even xs`, `fold add pair 0 xs`).
- **Sequential vs Parallel Combinators**:
  - Sequential (left-to-right, deterministic side-effects): `map f xs`, `filter p xs`, `fold f init xs`.
  - Multicore parallel (work-stealing worker threads): **`||map f xs`** and **`||filter p xs`**.

### 3.5 Types, ADTs, Record Updates (`with`), and Natural-Language Mixfix (`op ::`)
- **Sum ADTs, Shared Constructor Names & Type-Name Variants (`FR-COMP-005`)**:
  - `type Shape = Circle Int | Rect Int Int` or polymorphic `type Option A = None | Some A`.
  - Multiple `type` declarations can share variant constructor names (such as `Error`, `Var`, `Lit`, `None`) with the same or different arities; the typechecker resolves them by expected column type and argument types.
  - Bare built-in type names in sum ADTs (`type Something = String | Int | MyStruct Float Int`) include values of those types directly without redundant `Int Int` or `String String` wrappers; callers can pass bare `"hej"` / `42` or `String "hej"` / `Int 42`, and patterns match both literals (`"admin"`, `0`) and typed patterns (`(String s)`, `(Int n)`).
- **Open Type Extensions (`expand type`) & Automatic `fn ::` Clause Merging (`FR-COMP-005`)**:
  - Append new variants to an existing Sum ADT or new fields to an existing Product Record using `expand type`:
  ```ridgun
  type AppErr = IoError String | Timeout Int

  fn :: format err AppErr        => String
        format err (IoError msg) =  "IO: {msg}"
        format err (Timeout ms)  =  "Timeout: {ms} ms"
        format err _             =  "Unknown error"

  expand type AppErr = AuthError String | DbError Int String

  -- Re-declaring `fn :: format err` merges new clauses BEFORE the `_` catch-all:
  fn :: format err AppErr              => String
        format err (AuthError user)    =  "Auth failed: {user}"
        format err (DbError   code db) =  "DB {code}: {db}"
  ```
- **Product Records & Functional Updates (`with`)**:
  ```ridgun
  type Config = debug: Bool, threads: Int, name: String

  fn :: tune config Config => Config
        tune config cfg    =  cfg with debug: True, threads: 16
  ```
   Auto-generated field accessors: `debug cfg`, `threads cfg`, `name cfg`.
- **Natural-Language Mixfix Operators (`op ::`)**:
  ```ridgun
  op :: clamp Int between Int and Int => Int
        clamp x   between lo  and hi  =
          | x < lo    = lo
          | x > hi    = hi
          | otherwise = x

  op :: swap A with B => (B, A)
        swap a with b =  (b, a)
  ```
  *(Note: `type`, `with`, `and`, `or`, `xor`, `not` are contextual and allowed as words inside `op ::` declarations!)*

---

## 4. Memory Management (`RMM1`, `RMM2` & `with region`) (`FR-COMP-002`)
Ridgun achieves deterministic memory management with **zero Garbage Collector pauses**:
1. **`RMM1` (Compiled Memory Management — Linear & Conditional)**:
   - Frees local allocations immediately after their static last use (`rg_cmm_drop`).
   - Transfers returned local allocations to the caller with zero copy (`rg_cmm_move`).
   - When a function may return one of its heap parameters (`elegir cond a b`), inserts a 1-cycle pointer-identity guard (`ptr(a) != ptr(c)`) so non-returned candidates can be freed safely.
2. **`RMM2` (Assignment & Cascaded Structure Counting)**:
   - **Rule 1 (Arguments Untouched)**: Entering/exiting a function adds `+0 / -0` to argument reference counts.
   - **Rule 2 (`+1` on Assignment)**: Binding a structure to a local variable (`x = s`), rebinding a `mut` variable (`x = new_s`), or storing it inside a parent container increments its reference count (`+1`).
   - **Rule 3 (`-1` on Scope Exit & Child Cascade)**: At function exit, the returned local variable is spared (`-0` in transit), while all other local structure variables are decremented (`-1`). When a parent container's count reaches `0`, it frees its own node and cascades `-1` to its direct children.
3. **Lexical Arena & Timeout Quotas (`with region`, `with timeout`) (`FR-COMP-002`, `FR-COMP-007`)**:
   - `with region 64_KB do expr` allocates inside a bounded arena (`_KB`, `_MB`, `_GB`) and frees the entire region in $O(1)$ on block exit.
   - `with timeout 500_ms do expr` (and `with region 64_MB, timeout 500_ms do expr`) establishes a monotonic deadline (`_ms`, `_s`, `_min`), clamps `sys poll` inside the block, and exposes `sys deadline ms` and `sys remaining ms`.

---

## 5. Tensors, Channels & Concurrency
- **Symbolic Tensor Shapes & Contraction (`Tensor[N, K]`, `@`)**:
  - Compile-time dimension verification: `fn :: linear Tensor[B, In] Tensor[In, Out] => Tensor[B, Out]`.
  - Creation & indexing: `m = zeros [2, 2]`, `m[0, 1] = 3.5`, `v = m[0, 1]`.
  - Einstein summation (`A_ik @ B_kj` or `einsum "ik,kj->ij" a b`) and Hadamard element-wise ops (`a @+ b`, `a @- b`, `a @* b`, `a @/ b`).
- **Affine Channels (`channel`, `send`, `recv`)**:
  - `ch = channel ()`, `_ = send ch msg`, `out = recv ch`.
  - Reading `msg` after `send ch msg` is rejected at compile time (`ErrUseAfterSend`).

---

## 6. Complete Built-in Runtime Functions
| Category | Built-in Function | Signature | Description |
|---|---|---|---|
| **Output & CLI** | `echo a b ...` / `expr out` | variadic `=> ()` / `T => ()` | Print values with newline |
| | `cli_args` | `=> [String]` | Command-line arguments |
| **Strings & Chars** | `str_len s` | `String => Int` | Byte length of string ($O(1)$) |
| | `str_char_at s idx` | `String Int => Int` | Byte/ASCII code at `idx` ($O(1)$, `-1` if out of bounds) |
| | `str_slice s start end` | `String Int Int => String` | Substring `[start..end)` |
| | `char_from_code c` | `Int => String` | 1-byte string from code `c` |
| | `int_to_str n` / `str_to_int s` | `Int => String` / `String => Int` | Integer ↔ String conversion |
| | `str_starts_with s p` | `String String => Bool` | Prefix check |
| | `str_contains s sub` | `String String => Bool` | Substring check |
| | `str_index_of s sub` | `String String => Int` | First index of `sub` (`-1` if not found) |
| | `str_trim s` | `String => String` | Trim ASCII whitespace |
| | `str_replace s old new` | `String String String => String` | Replace all occurrences |
| | `str_split s delim` | `String String => [String]` | Split string into list |
| | `str_to_upper s` / `str_to_lower s` | `String => String` | ASCII case conversion |
| **Collections** | `map f xs` / `\|\|map f xs` | `(A => B) [A] => [B]` | Sequential / Multicore parallel map |
| | `filter p xs` / `\|\|filter p xs` | `(A => Bool) [A] => [A]` | Sequential / Multicore parallel filter |
| | `fold f init xs` | `(B A => B) B [A] => B` | Left fold |
| **File & Byte I/O** | `read_file path` | `String => String` | Read UTF-8 file verbatim |
| | `write_file path text` | `String String => ()` | Write string to file |
| | `append_file path text` | `String String => ()` | Append string to file |
| | `read_bytes path` | `String => [Int]` | Read raw file bytes (`0..255`) |
| | `write_bytes path bytes` | `String [Int] => ()` | Write raw bytes (`0..255`) to file |
| | `sha256_hex text` | `String => String` | Lowercase 64-char SHA-256 hex digest |
| **Filesystem & OS** | `file_exists p` / `is_dir p` / `is_file p` / `is_symlink p` | `String => Bool` | Path metadata predicates |
| | `file_size p` / `file_mtime p` / `file_mode p` | `String => Int` | Size in bytes, mtime, POSIX mode |
| | `list_dir path` | `String => [String]` | Sorted directory entry names |
| | `sys_chmod path mode` | `String Int => Bool` | Change file permissions (e.g. `493` = `0755`) |
| | `sys_mkdir p` / `sys_rmdir p` / `sys_unlink p` | `String => Bool` | Create/remove directory or file |
| | `sys_rename old new` / `sys_symlink tgt lnk` | `String String => Bool` | Atomic rename / symlink |
| | `sys_readlink p` / `sys_getcwd` / `sys_getenv k` | `String => String` / `=> String` | Read symlink, cwd, or env var |
| | `sys_chdir p` | `String => Bool` | Change working directory |
| | `sys_exit code` | `Int => ()` | Exit process immediately |
| | `sys_os` / `sys_arch` | `=> SysOs` / `=> SysArch` | Target OS (`Linux \| MacOS \| Windows`) & CPU arch (`X86_64 \| Arm64`) |
| | `sys_getpid` / `sys_time_ms` | `=> Int` | Process ID / monotonic time in ms |
| | `sys_deadline_ms` / `sys_remaining_ms` | `=> Int` | Active `with timeout` deadline / remaining budget in ms (`0` / `-1` if none) |
| | `sys_sleep_ms ms` | `Int => ()` | Sleep for `ms` milliseconds |
| | `sys_open_mode path mode` | `String String => Int` | Portable open (`"r"`, `"w"`, `"a"`, `"rw"`, `"w+"`, `"a+"` -> `fd >= 0` or `-errno`) |
| | `sys_open path flags mode` | `String Int Int => Int` | PAL descriptor open (`flags`: `0`/`1`/`2`/`64`/`512`/`1024`/`2048` -> `fd >= 0` or `-errno`) |
| | `sys_close fd` | `Int => Int` | Close descriptor (`0` or `-errno`) |
| | `sys_read_fd fd max_bytes` | `Int Int => String` | Unbuffered descriptor read (`""` on EOF/error) |
| | `sys_write_fd fd data` | `Int String => Int` | Unbuffered descriptor write (bytes written or `-errno`) |
| | `sys_poll fd events timeout_ms` | `Int Int Int => Int` | Poll descriptor readiness (`1`=`POLLIN`, `4`=`POLLOUT`; clamped to `with timeout`) |
| | `sys_terminate pid force` | `Int Bool => Int` | Portable process termination (`False` graceful, `True` forced) |
| | `sys_kill pid sig` | `Int Int => Int` | Send normalized signal (`0`/`2`/`9`/`15`) to process `pid` |
| | `sys_call nr a1 a2 a3 a4 a5 a6` | `Int Int Int Int Int Int Int => Int` | Escape hatch for raw 6-arg target-OS ABI syscall |
| | `shell_exec cmd` | `String => Int` | Execute shell command and return exit code |
| **RMM Diagnostics** | `cmm_same_ptr a b` | `[A] [A] => Bool` | `True` if `a` and `b` share the exact same heap pointer |
| | `cmm_live_blocks` / `cmm_cond_freed` / `cmm_cond_spared` | `=> Int` | Live heap blocks, conditional frees, and spared return blocks |

---

## 7. Toolchain & Verification Workflow (`stable` and `ridgunc`)
1. **Scaffold / Dependencies / Plugins (`FR-TOOL-002`, `FR-TOOL-003`)**:
   - `stable new [--lib] <name>` or `stable init [--lib]`: create `build.rg`, `src/main/ridgun/...`, `src/test/ridgun/test main.rg`, and `.gitignore`.
   - `stable deps` or `stable add <git_url_or_path>`: synchronize `dependencies` from `build.rg` into `.stable/deps/`.
   - `stable tasks` / `stable plugins` / `stable <task_name>`: inspect or run custom `fn :: task <name> => String` definitions and `plugins/*.rg` extensions from `build.rg`.
   - `stable install [target]`: build and install native ELF64 binaries into `~/.local/bin/` and `bin/`.
2. **Format**: `./target/stable format [file.rg ...]` (to apply canonical tabular alignment).
3. **Type-check & Static Analysis**: `./target/stable check` (checks all modules in `src/main/ridgun/` in parallel) or `./target/ridgunc check <file.rg>`.
4. **Run Tests**: `./target/stable test` (compiles and runs all `src/test/ridgun/test*.rg` suites in parallel via `||map`).
5. **Build Native ELF64 Executables & Libraries (`FR-COMP-004`, `FR-COMP-006`)**:
   - Project targets: `./target/stable built` (or `./target/stable built lib` for `.rglib` + `.so` libraries)
   - Single file (`x86_64` default): `./target/ridgunc build <entry.rg> -o <output_bin>`
   - Library bundle (`.rglib`) & ELF64 `ET_DYN` shared object (`.so`): `./target/ridgunc build --lib <lib.rg> -o <out.rglib>` and `./target/ridgunc build --so <lib.rg> -o <lib.so>`
   - Cross-compile for `ARM64` (`AArch64` / Raspberry Pi): `./target/ridgunc build --target arm64-linux <entry.rg> -o <output_bin_arm64>`
