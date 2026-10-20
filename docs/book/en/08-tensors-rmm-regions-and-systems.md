# Chapter 08: Tensors, RMM Compiled Memory (`RMM1`/`RMM2`), Regions, and Systems

So far we have seen the friendly, elegant, mathematical side of Ridgun: pure functions, algebraic data types, *pattern matching*, decision trees with `|` / `|.`, and parallel `||` graphs with `->` that put every core of your processor to work without asking you for a single `Mutex`.

At this point, a veteran systems programmer at the back of the room usually raises a hand with a half-smile and asks:

> *"All of this is lovely for computing invoices or compiling ASTs, but what happens when I need to multiply matrices of millions of floats at breakneck speed? What about memory? Is there a Garbage Collector hiding under the rug waiting for the worst possible moment to freeze my program for 200 milliseconds? And how do I talk to a real Unix operating system?"*

Excellent questions. Let's pop the hood of Ridgun and see how it handles low-level systems work, numerical computing, and deterministic memory.

---

## 8.1. The Memory Dilemma: Neither Garbage Collector Nor Borrow Checker Fights (`RMM1` and `RMM2`)

In modern programming languages there are usually two irreconcilable camps:

1. **The Garbage Collector camp (Java, Go, Python, JS, Haskell, OCaml):** you allocate memory freely and, every now and then, an invisible garbage truck stops all traffic in your program to trace which objects are still alive and which are dead. It is wonderfully convenient... until you are building an ultra-fast systems tool or a strict-latency server and the garbage truck decides to double-park.
2. **The manual control / Borrow Checker camp (C, C++, Rust):** there is no garbage collector, but in exchange you either juggle raw pointers by hand (risking a `Segmentation fault` or *use-after-free*) or spend half the afternoon arguing with the *borrow checker* about why `'a` does not live as long as `'b`.

Ridgun solves this dilemma at the root with **Ridgun Memory Management (`RMM`)**, a deterministic system of two complementary policies (**`RMM1`** and **`RMM2`**) combined with **lexical regions (`with region`)**:

### Policy `RMM1` — Compiled Memory Management (Linear and Conditional CMM)
When the compiler statically knows the flow of local variables inside a function:
- **Linear CMM**: `ridgunc` computes at compile time the **exact last line** where each local variable (`a`, `b`, ...) is read and inserts its deterministic deallocation (`rg_cmm_drop`) immediately afterward, or transfers ownership with zero copies (`rg_cmm_move`) when the variable is returned as the result.
- **Conditional CMM (`ptr(a) != ptr(c)`)**: what if a function like `choose cond a b` returns either `a` or `b` depending on a runtime condition? `ridgunc` builds the ancestor table and emits a **1-CPU-cycle** pointer-identity guard: when `b` is no longer used while `c` remains alive, it checks `if ptr(b) != ptr(c) { free(b) }`. The unchosen branch is freed immediately and the chosen one survives intact.

### Policy `RMM2` — Assignment Counting and Structural Cascade
And what happens when you nest data structures inside other data structures (`xs = [a, b]`), reassign mutable variables (`mut x = ...`), or chain complex calls? That is where **`RMM2`** steps in, governing the entire lifecycle through four airtight mathematical rules:

1. **Incoming function arguments are untouched (`+0` on entry, `-0` on exit)**: passing a list or a record into a function never increments or decrements reference counters needlessly.
2. **Every assignment to a local variable or container slot adds `+1`**:
   - `a = [10, 20]` $\rightarrow$ block `M1` is born with counter `1`.
   - `xs = [a, b]` $\rightarrow$ list `xs` is born with `1`, and because it holds references to `a` and `b`, both climb to `2`.
   - If you reassign a mutable variable (`mut x = ...` and later `x = new_val`), `RMM2` applies **`+1`** to the new value first before applying **`-1`** to the old one.
3. **Upon exiting the function, local variables that are NOT returned receive `-1`**: if a structure's counter reaches `0`, its memory is freed on the spot and **it cascades `-1`, one by one, to each of its direct children**.
4. **The value returned by the function is exempt in transit**: it receives its local-variable `-1` without being destroyed as it crosses the return boundary, so when the caller writes `c = my_func ()`, the `+1` from that assignment leaves its counter at `1`.

```ridgun
choose Bool [Int] [Int] => [Int]
choose cond a     b     =
  | cond      = a
  | otherwise = b

rmm2_example Bool => Int
rmm2_example cond =
  a = [10, 20, 30]         -- M1 (rc = 1)
  b = [40, 50, 60]         -- M2 (rc = 1)
  c = choose cond a b      -- `c` gets +1; the unchosen list dies right here (rc -> 0)
  (count a) + (count c)    -- On exit, `a` and `c` get -1 and 0 live blocks remain
```

---

## 8.2. Quota-Bounded Lexical Regions (`with region`): $O(1)$ Memory Firewalls

Alongside `RMM1` and `RMM2`, whenever you are parsing an external network packet, a massive file, or a batch of untrusted data and want to enforce a **strict RAM ceiling**, you wrap the computation in a **`with region`** block:

```ridgun
process_frame String => Result
process_frame raw    =
  with region 64_KB do
    clean = map clean_line (split_lines raw)
    count_valid clean
```

1. **Hardware/runtime-guaranteed quota**: if code inside the block attempts to allocate even a single byte beyond `64_KB` (`65,536` bytes), the runtime cleanly aborts the block, frees the entire temporary arena in constant $O(1)$ time, and returns `Err OutOfMemory` without crashing the process.
2. **Instantaneous deallocation on exit**: the moment the `with region` block finishes, all temporary memory in the arena vanishes in one stroke with zero fragmentation.

---

## 8.3. Native Tensors, Einstein Contraction (`@`), and Symbolic Dimensions

If you have ever programmed in Python with NumPy or PyTorch, you have almost certainly suffered the classic crash 41 minutes into a training run:

```text
RuntimeError: mat1 and mat2 shapes cannot be multiplied (128x64 and 32x128)
```

In Ridgun, **`Tensor`** values are first-class native citizens and their dimensions are part of the type signature:

```ridgun
-- If (N × K) and (K × M) go in, (N × M) MUST come out!
multiply_matrices Tensor[N, K] Tensor[K, M] => Tensor[N, M]
multiply_matrices a            b            =  a_ik @ b_kj
```

Notice three standout details:
1. **Static dimension verification (`Tensor[N, K]`)**: the inner axis `K` of the first matrix must match the leading axis `K` of the second. If you try to pass incompatible dimensions, `ridgunc check` stops you before executing a single instruction.
2. **Einstein index notation (`a_ik @ b_kj`) and Hadamard broadcasting (`a_ij * b_j`)**:
   - With **`@`**, indices repeated across all operands (`k`) are contracted (summed over) while unique indices (`i`, `j`) survive in the output tensor.
   - With **`+`, `-`, `*`, `/`**, indices align dimensions and perform automatic *broadcasting* (`a_ij * b_j` multiplies each row `i` of `a` by vector `b_j` without needing `unsqueeze` or `reshape`).
3. ***In-place* mutation for numerical algorithms**:
   ```ridgun
   make_identity_matrix => Tensor
   make_identity_matrix =
     m = Tensor [[1.0, 0.0], [0.0, 1.0]]
     m[0, 1] = 0.5
     m
   ```

---

## 8.4. Context Variables (`context ::`) and Atomic Shared State (`shared ::`)

In 99% of your code you will pass data as function parameters. But for that 1% where you need environment configuration or a global cross-thread counter without polluting 40 intermediate function signatures, Ridgun provides two explicit, safe mechanisms:

### 1. `context ::` — Task-isolated dynamic scope (`with ... = ... do`)
```ridgun
context :: log_path : String = "/var/log/app.log"

log_event String => ()
log_event msg    =  echo "[{log_path}] {msg}"

main => ()
main =
  log_event "Normal startup"
  with log_path = "/tmp/test.log" do
    log_event "Inside isolated test"
```

### 2. `shared ::` and `atomic` — Concurrent state with per-line atomic locking
```ridgun
shared :: total_requests : Int = 0

record_visit => Int
record_visit =
  atomic total_requests = total_requests + 1
  total_requests
```

---

## 8.5. Hardware Access (`hardware ::`) and POSIX Systems Primitives

The `ridgunc` compiler itself, the `stable` build manager, and Unix systems utilities are written in Ridgun. To make that possible, the language includes memory-mapped register blocks (`hardware ::`) and direct POSIX primitives:

```ridgun
hardware :: UART0 @ 0x1000_0000
  tx_data : Int @ 0x00
  status  : Int @ 0x04
```

And for interacting with the operating system:

| Primitive | Signature | What It Does |
|---|---|---|
| `cli_args` | `=> [String]` | Command-line arguments (`argv`). |
| `read_file` / `write_file` | `String => String` / `String String => ()` | Full file reading and writing on disk. |
| `read_bytes` / `write_bytes` | `String => [Int]` / `String [Int] => ()` | Exact byte-by-byte binary reading and writing (`0..255`). |
| `list_dir` / `file_lstat` | `String => [String]` / `String => ...` | Directory listing and POSIX metadata inspection (`lstat`). |
| `sha256_file` / `sha256_str` | `String => String` | Native SHA-256 cryptographic hash. |
| `sys_exec` / `shell_exec` | `... => Int` | Operating system process execution. |
| `sys_getcwd` / `sys_chdir` | `=> String` / `String => Int` | Query or change the current working directory. |
| `sys_getenv` / `sys_setenv` | `String => String` / `String String => Int` | Process environment variables. |
| `sys_getuid` / `sys_getgid` | `=> Int` | Real process UID and GID (`doas`, security tools). |
| `sys_exit` | `Int => ()` | Terminate the process with an exit code. |

---

## 8.6. Real-World Case Study: Building `rg-wc`, a Parallel Unix Utility

Let's bring together everything we have learned from Chapter 01 to Chapter 08 in a real systems program: a parallel version of the Unix `wc` utility (line and byte counter across multiple files) written in pure Ridgun:

```ridgun
-- 1. Model file metrics using an ADT record (Chapter 06)
type Metrics = file: String, lines: Int, bytes: Int

-- 2. Count newline characters (ASCII code 10) with TCO tail recursion (Chapter 04)
fn :: count_newlines String Int Int Int => Int
      count_newlines text   pos end acc =
        | pos >= end                    = acc
        | (str_char_at text pos) == 10  = count_newlines text (pos + 1) end (acc + 1)
        | otherwise                     = count_newlines text (pos + 1) end acc

fn :: line_count String => Int
      line_count text   =  count_newlines text 0 (str_len text) 0

-- 3. Analyze a file and return its Metrics record
fn :: analyze_file String => Metrics
      analyze_file path   =
        content = read_file path
        || line_count content -> n_lines
        || str_len content    -> n_bytes ||.
        Metrics path n_lines n_bytes

-- 4. Format each row and sum totals using `fold` and `||` (Chapter 07)
fn :: format_metric Metrics => String
      format_metric m       =  "{lines m}\t{bytes m}\t{file m}"

fn :: sum_lines Int Metrics => Int
      sum_lines acc m       =  acc + (lines m)

fn :: sum_bytes Int Metrics => Int
      sum_bytes acc m       =  acc + (bytes m)

fn :: generate_report [String] => String
      generate_report paths    =
        metrics = map analyze_file paths
        || map format_metric metrics -> rows
        || fold sum_lines 0 metrics  -> total_l
        || fold sum_bytes 0 metrics  -> total_b ||.
        "{rows}\nTotal: {total_l} lines, {total_b} bytes"

fn :: main => ()
      main =
        echo (generate_report ["README.md", "AGENTS.md"])
```

Pause for a second and look at those ~40 lines of code:
- There is not a single `null`, unchecked exception, or `Mutex`.
- `count_newlines` compiles down to a native `loop` using 0 bytes of stack thanks to automatic TCO.
- `map analyze_file paths` processes files in parallel across all cores of your CPU, and the `||` block computes the formatted rows, total lines, and total bytes simultaneously.
- Temporary memory is freed deterministically via **`RMM1`/`RMM2`**.
- And when you run `ridgunc build rg_wc.rg -o rg-wc`, you get a self-contained ~350 KB native binary ready to copy into `/usr/local/bin`.

---

## 8.7. Final Roadmap: The 10 Golden Rules of the Ridgun Programmer

1. **Always write the contract (`=>`) first and the equations (`=`) second:** thinking about types first makes the compiler work for you.
2. **Let `stable format` typeset your tables:** type with single spaces and let the tool align columns, `=>`, `=`, and `->`.
3. **Remember the universal `=` rule:** after any `=` you can open a sequential block, a `|` guard tree, or a parallel `||` graph.
4. **Use `|.` and `||.` only when closing a nested block to return to an outer level:** keep deep decision trees compact and unambiguous.
5. **Immutable by default (`x = ...`), explicitly mutable (`mut x = ...`):** reach for `mut` only when a local accumulator genuinely calls for it.
6. **Use clear lowercase boolean operators (`and`, `or`, `xor`, `not`) and always close your guards with `| otherwise =`.**
7. **Model your domain with ADTs (`type`):** use records with `with field: value` and sum types (`Option`, `Result`) instead of `null`.
8. **Parallelize by declaring dependencies with `|| expr -> var` and `map` / `filter`:** let the compiler verify acyclicity and distribute work across cores.
9. **Give your Tensors symbolic dimensions (`Tensor[N, K]`) and your contractions explicit indices (`a_ik @ b_kj`).**
10. **Trust `RMM` (`RMM1`/`RMM2`), bound untrusted inputs with `with region`, and always verify with `stable check` and `stable test`.**

Happy hacking in Ridgun!
