# Acceptance tests for ridgunc

These are small Ridgun programs. Each one states what the language promises and checks that the compiler keeps the promise. They complement the suites in `src/test/ridgun/`.

Every expected value comes from the language's own documents, and each case says which. A behaviour the documents leave open or contradict isn't turned into a test: it is listed below under "Decisions pending". (`integration.rs` in this folder is the old Rust-era suite; FR-COMP-004 says no `.rs` should remain.)

## Run them
```bash
./bin/ridgunc run tests/run.rg                  # every case under tests/cases/ and the toolchain checks
./bin/ridgunc run tests/run.rg agents lists     # cases whose path contains "agents" or "lists"
./bin/ridgunc run tests/run.rg --no-toolchain   # cases only
```
- Every build is `ridgunc build --strict`. The cases use the canonical style: spaced names in declarations, and tuples written `=> Int Int`. Calls may keep `_`.
- `RIDGUNC=/path/to/ridgunc` tests another build. The default is `bin/ridgunc`.
- Work folders go to `~/.cache/ridgun-compiler-tests/work`. They never go to `/tmp`, which is a tmpfs with limited inodes, and never inside a repository.
- Builds and runs are capped at 4 GB of address space and a time limit.
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
-- max-rss-mb: 16              (optional: peak resident memory limit for the run)
-- max-cpu-ms: 150             (optional: user + system CPU limit for the run; a busy wait shows here)
-- kind: proposal               (optional: no document promises it; reported apart, doesn't fail the run)

fn :: main => ()
      main =  …
```
`-- expect-build-error: TEXT` makes the case pass only when the build fails and its output contains TEXT. An empty TEXT accepts any build failure, for removed or forbidden constructs whose message the documents don't fix. `-- uses-libs` copies the ridgun-libs bundles next to the case; no case needs them yet.

`run.rg` also holds four toolchain checks that no single program can express:
- `-o` into a folder that doesn't exist either creates the folder or fails. It never reports success without writing the file (FR-COMP-004: build writes the ELF; Solstice register RG-081).
- A type error exits with a non-zero status and writes no binary.
- Build time stays near-linear in the number of functions: 200 → 800 functions takes at most 8× as long. The documents promise nothing here; Solstice register RG-075 measured 26 s for any program importing Solstice.
- Building a program that imports standard libraries (`str`, `io`, `list`, `cli`) completes in under 3 000 ms (RG-075).

## What the cases cover
| Folder | Cases | Sources |
|---|---|---|
| `lists/` | map / filter / fold values; `\|\|map` / `\|\|filter` equal to them in order on 2 000 elements; `::` joins; `[]`, `(x:[])`, `(a:b:rest)` and literal multi-cons patterns | FR-COMP-001 AC1–3 and §3; spec.md:351, 363-368; book 05:51-69 |
| `functions/` | function values and `(A => B)` parameters; 100 000 000 self tail calls in constant memory | FR-COMP-001 §1; book 07:72-76; book 04:174-181 |
| `guards/` | the four FR-COMP-003 examples: mixfix clamp, guarded binding, the four-level decision tree with `\|.`, and `\|\| … \|\|.` followed by a guarded binding | FR-COMP-003 §1–§3 |
| `variables/` | `mut` reassignment; reassigning a non-`mut` variable must not compile | FR-COMP-003 §4, AC3 |
| `parallel/` | named `\|\|` DAG and anonymous `\|\|` tuple; a DAG cycle must not compile | FR-COMP-003 §4; spec.md:723-746; book 07:110 |
| `adts/` | shared constructors; `expand type` on sums and records; clause merging ahead of catch-alls; type-name variants | FR-COMP-005 §1–§4, AC-1–AC-4 |
| `records/` | `r with f = v, g = w` copies, also as the last line of a block | current syntax (see below); Solstice register RG-068 |
| `strings/` | interpolation and brace escapes; raw `'…'` strings; `str_char_at` out of range is -1; cutting at any index and joining gives the text back | spec.md:28-56; book 03:129-130 |
| `literals/`, `logic/` | `-100`, hex, digit separators, `_KB` / `_MB` / `_GB`; truth tables of `and` / `or` / `xor` / `not` | book 03:67, 87-98; spec.md:313-329 |
| `agents/` | stateless FIFO with one and two arguments; stateful `S M => S` and `S M => S R`; `ask` in both styles; `try receive`, `stop`, `agent alive`; `try receive` of a record; polling while the agent sleeps costs almost no CPU; 50 000 messages without memory growth | FR-COMP-009 AC-1–AC-3, §3, §6; FR-COMP-002 ("leak-free"); Solstice register RG-063, RG-069, RG-072 |
| `names/` | a parameter or local binding named like a top-level 0-argument function means the parameter or binding | lexical scoping (spec.md:105-123, 674-695); the compiler team's TASK-0024 (RG-073) |
| `files/` | `read_file` gives back exactly what `write_file` wrote, for every byte value | consistency; Solstice register RG-089 |
| `removed/` | `global ::` and `spawn` / `join` must not compile | FR-COMP-009 §5, AC-4 |
| `syntax/` | a top-level line that is no known declaration must not build (today it is dropped silently) | spec.md (a file is a sequence of declarations); Solstice register RG-090 |
| `strict/` | `--strict` refuses `_` in declared names and `(Int, Int)` returns | book 02:193-197; FR-COMP-008 |
| `runtime/` | `sys_exit n` exits with n and stops there | FR-VM-002:32,45 |
| `perf/` | **Proposals** (`-- kind: proposal`): building a 20 000-element list at either end in under 1 s; 8 agents on 8 equal jobs at once take no longer than one thread doing them in turn | Solstice register RG-085, RG-079 |

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
- **`_` aliases of spaced names.** spec.md:126 and FR-COMP-005:58 promise them for built-ins and test functions. That a user's `foo bar` is also callable as `foo_bar` is relied on everywhere but not written down.
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
