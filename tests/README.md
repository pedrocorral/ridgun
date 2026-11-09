# Acceptance tests for ridgunc

These are small Ridgun programs. Each one states what the language promises and checks that the compiler keeps the promise. They complement the suites in `src/test/ridgun/`.

Every expected value comes from the language's own documents, and each case says which. A behaviour the documents leave open or contradict isn't turned into a test: it is listed below under "Decisions pending". (`integration.rs` in this folder is the old Rust-era suite; FR-COMP-004 says no `.rs` should remain.)

## Run them
```bash
./bin/ridgunc run tests/run.rg                  # every case under tests/cases/ and the toolchain checks
./bin/ridgunc run tests/run.rg agents lists     # cases whose path contains "agents" or "lists"
./bin/ridgunc run tests/run.rg --no-toolchain   # cases only
./bin/ridgunc run tests/run.rg --llvm           # cases built only for LLVM (the default target)
./bin/ridgunc run tests/run.rg --x86            # cases built only for the pure x86-64 encoder
```
- Every case is built and run twice: for LLVM (the default target) and for the pure x86-64 encoder (`--target x86_64-elf`), as FR-COMP-004 and FR-COMP-020 require. The x86-64 rows end in `[x86_64-elf]`, and the summary counts each backend apart. On x86-64 a case checks output, exit status and `max-rss-mb`; `max-ms` and `max-cpu-ms` are LLVM promises (FR-COMP-011 AC-4) and are not checked there, and every x86-64 run may take 30 s. The toolchain checks use LLVM only.
- Every build is `ridgunc build --strict`. The cases use the canonical style: spaced names in declarations and calls (no `_` in function names or calls), and tuples written `=> Int Int`. Local variables and parameters may contain `_`.
- `RIDGUNC=/path/to/ridgunc` tests another build. The default is `bin/ridgunc`. `STABLE=/path/to/stable` does the same for the `stable deps` checks; the default is `bin/stable`. A relative path in either variable is read from the repository root.
- A toolchain check that needs a shell script writes it to a file in its work folder and runs `bash file.sh`. Never nest a script inside `bash -c '...'`: its `printf '...'` quotes end the outer quotes.
- Work folders go to `~/.cache/ridgun-compiler-tests/work`. They never go to `/tmp`, which is a tmpfs with limited inodes, and never inside a repository.
- Builds and runs are capped at 4 GB of address space and a time limit. A case without `max-ms` may run for 30 s; with `max-ms`, for that limit rounded up to whole seconds, and at least 5 s. A run past its time limit is stopped and exits with 124.
- `tests/run_case.sh` runs each case binary. It reads the binary's CPU time from `times` and its peak resident memory from `VmHWM` in `/proc/<pid>/status`, sampled every 2 ms. Growth in the last 2 ms before the binary exits can go unseen.
- The run ends with the promised behaviours that failed, then the proposals not met. It exits with 1 only if a promised behaviour failed.

## A case
```ridgun
-- case: what it checks, in one line
-- source: where the expectation comes from (FR-COMP-003 §2, spec.md:313-329, book 04:174-181, …)
-- expect-output:
--   first line of standard output
--   second line
-- expect-exit: 3              (optional; 0 by default)
-- max-ms: 1000                (optional: wall-time limit for the run)
-- max-rss-mb: 16              (optional: peak resident memory limit for the run, in MB of 1 024 kB)
-- max-cpu-ms: 150             (optional: user + system CPU limit for the run; a busy wait shows here)
-- kind: proposal               (optional: no document promises it; reported apart, doesn't fail the run)

fn :: main => ()
      main =  …
```
`-- expect-build-error: TEXT` makes the case pass only when the build fails and its output contains TEXT. An empty TEXT accepts any build failure, for removed or forbidden constructs whose message the documents don't fix. `-- uses-libs` copies the ridgun-libs bundles next to the case; no case needs them yet.

`run.rg` also holds toolchain checks that no single program can express, among them:
- `-o` into a folder that doesn't exist either creates the folder or fails. It never reports success without writing the file (FR-COMP-004: build writes the ELF; Solstice register RG-081).
- A type error exits with a non-zero status and writes no binary.
- Build time stays near-linear in the number of functions: 200 → 800 functions takes at most 8× as long. The documents promise nothing here; Solstice register RG-075 measured 26 s for any program importing Solstice.
- Building a program that imports standard libraries (`str`, `io`, `list`, `cli`) completes in under 3 000 ms (RG-075).
- Inside an imported lib, a record field name means the lib's accessor even when the program defines a function with that name (FR-COMP-012; libs report 2026-11-08).

## What the cases cover
| Folder | Cases | Sources |
|---|---|---|
| `lists/` | map / filter / fold values; `\|\|map` / `\|\|filter` equal to them in order on 2 000 elements; `::` joins; `[]`, `(x:[])`, `(a:b:rest)` and literal multi-cons patterns; `sort by ints` / `sort by texts` (order, stability, text order like `<`, run-time-built lists, different lengths exit with status 1) | FR-COMP-001 AC1–3 and §3; spec.md:351, 363-368; book 05:51-69; FR-COMP-021 |
| `functions/` | function values and `(A => B)` parameters; 100 000 000 self tail calls in constant memory; a call that matches no clause exits with status 1; functions that only match a parameter with a pattern take it borrowed, with the same results and no leaks; a lexer-shaped pair of functions calling each other in tail position stays in small memory (OPT-018 regression) | FR-COMP-001 §1; book 07:72-76; book 04:174-181; FR-COMP-017 §2 (RG-114); FR-COMP-011 §7 |
| `guards/` | the four FR-COMP-003 examples: mixfix clamp, guarded binding, the four-level decision tree with `\|.`, and `\|\| … \|\|.` followed by a guarded binding; no guard holding and no `otherwise` exits with status 1 | FR-COMP-003 §1–§3; FR-COMP-017 §2 (RG-114) |
| `variables/` | `mut` reassignment; reassigning a non-`mut` variable must not compile | FR-COMP-003 §4, AC3 |
| `parallel/` | named `\|\|` DAG and anonymous `\|\|` tuple; a DAG cycle must not compile | FR-COMP-003 §4; spec.md:723-746; book 07:110 |
| `adts/` | shared constructors; `expand type` on sums and records; clause merging ahead of catch-alls; type-name variants; constructors inside tuple and cons patterns | FR-COMP-005 §1–§4, AC-1–AC-4; FR-COMP-017 §1 (RG-114) |
| `records/` | `r with f = v, g = w` copies, also as the last line of a block; a user function named like a field wins over the generated accessor | current syntax (see below); Solstice register RG-068; FR-COMP-011 §7 (OPT-016) |
| `strings/` | interpolation and brace escapes; raw `'…'` strings; `str_char_at` out of range is -1; cutting at any index and joining gives the text back; `str_to_int` over the whole 64-bit range | spec.md:28-56; book 03:129-130; FR-COMP-016 §4 (RG-113) |
| `literals/`, `logic/` | `-100`, hex, digit separators, `_KB` / `_MB` / `_GB`; the whole 64-bit `Int` range, with out-of-range literals as compile errors; truth tables of `and` / `or` / `xor` / `not` | book 03:67, 87-98; spec.md:313-329; FR-COMP-016 §1-§3 (RG-113) |
| `agents/` | stateless FIFO with one and two arguments; stateful `S M => S` and `S M => S R`; `ask` in both styles; `try receive`, `stop`, `agent alive`; `try receive` of a record; polling while the agent sleeps costs almost no CPU; 50 000 messages without memory growth | FR-COMP-009 AC-1–AC-3, §3, §6; FR-COMP-002 ("leak-free"); Solstice register RG-063, RG-069, RG-072 |
| `names/` | a parameter or local binding named like a top-level 0-argument function means the parameter or binding | lexical scoping (spec.md:105-123, 674-695); the compiler team's TASK-0024 (RG-073) |
| `files/` | `read_file` gives back exactly what `write_file` wrote, for every byte value | consistency; Solstice register RG-089 |
| `removed/` | `global ::` and `spawn` / `join` must not compile | FR-COMP-009 §5, AC-4 |
| `syntax/` | a top-level line that is no known declaration must not build (today it is dropped silently) | spec.md (a file is a sequence of declarations); Solstice register RG-090 |
| `tensors/` | numeric element types build and keep their values; `Real` elements are `Real`s; tensors of `String`, `Bool`, lists, tuples and ADTs (defaults, `Tensor[T * dims] with v`, numeric tensors of any rank, in-place reads and writes, also through a numeric parameter to a generically made tensor, bounds errors, list conversion, no leaks); `@` on `Real` tensors; `Tensor_GPU` of non-numeric elements and tensor literals of non-numbers are compile errors | spec.md "Tensors"; FR-COMP-018; FR-COMP-020 |
| `strict/` | `--strict` refuses `_` in declared names and function calls, and `(Int, Int)` returns; `" "` and `"_"` never resolve to the same function name | book 02:193-197; FR-COMP-005 §5; FR-COMP-008 |
| `runtime/` | `sys_exit n` exits with n and stops there | FR-VM-002:32,45 |
| `perf/` | **Proposals** (`-- kind: proposal`): building a 20 000-element list at either end in under 1 s; 8 agents on 8 equal jobs at once take no longer than one thread doing them in turn. Also `sort by ints` / `sort by texts` on 100 000 elements, whole program under 1 s (a requirement, not a proposal); creating 1 000 000-element tensors of `String` and of a generic element type, and a 120 × 120 `Real` matrix product, under 1 s; 10 000 000 field reads, small calls with a record pattern, and empty loop turns, under 400 ms | Solstice register RG-085, RG-079; FR-COMP-021 §6; FR-COMP-011 AC-4 |

## Decisions pending
The documents leave these points open, or say different things in different places. No case tests them. Each needs a decision, written in spec.md, and then a case.

- **Integers.**
  - Width: spec.md:281 just says "Integer", tutorials.md:176 "arbitrary precision", book 03:67 "signed 64-bit".
  - Overflow, and `/` and `%` with negative operands (truncation or floor), are unspecified, as is division by zero.
- **Negative literals.** Book 03:67 lists `-100` as an Int literal. spec.md:611 and the PAL guide write `0 - 1` and `(0 - 1)`.
- **Strings: bytes or code points.** spec.md:284,291 say a String is a sequence of code points. The harness skill:213-216 says `str_len` counts bytes and `str_char_at` returns a byte. Today `str_slice` snaps to UTF-8 boundaries while the others count bytes (Solstice register RG-087).
- **Operator precedence.** spec.md:216-222 says symbolic operators bind tighter than application, yet spec.md:356 writes `x + sum_list xs`.
- **Short-circuit `and` / `or`.** Unspecified. FR-COMP-010:26 also makes them bitwise on Int.
- **Record update syntax.** spec.md:517, book 06:42 and the harness show `r with f: v`. The compiler and the owner's decision (2026-10-23) use `r with f = v`, so those documents are stale.
- **Clause merging versus duplicate definitions.** FR-COMP-005 §3 says a second `fn ::` declaration merges its clauses. Since 0.9.17, the same name defined in two imported modules is reported as a duplicate definition. When each one applies needs saying.
- **Local tuple destructuring.** Book 03:84 shows `q, r = divmod 17 5`; the harness skill:36 says it is invalid.
- **Runtime errors.** The exit status and message for division by zero, a failed match, an out-of-range access or a stack overflow are unspecified.
- **Mutual recursion.** Tail calls between different functions aren't promised to be eliminated (Solstice register RG-047).
- **Agents.**
  - Whether agents really run in parallel is left to a static analyser (FR-COMP-009 §6).
  - There's no statement of how 8 busy agents should compare with 1 (Solstice register RG-079: 8 agents at once are 8× slower in total).
- **Stale documents.**
  - spec.md:84-99 describes a `ridgun run` CLI.
  - spec.md:816-854 describes a test library that isn't `src/test/ridgun/test.rg`.
  - spec.md:893,905 and FR-COMP-004:23 still list `global` / `context` / `shared` / `atomic`.
  - tutorials.md uses `spawn` and `let`.

## Adding a case
1. Put a program under the matching `tests/cases/<area>/` folder.
2. Write the `-- case:` and `-- source:` lines, then the expectations. The source is a document and a line or section. When nothing promises the behaviour, say so ("no promise in the docs (proposal)") and put the case under `perf/` or a folder that says it.
3. Derive the expected output from that source by hand, never from running the compiler.
4. Check that it builds with `--strict`: `./bin/ridgunc run tests/run.rg <its path>`.
