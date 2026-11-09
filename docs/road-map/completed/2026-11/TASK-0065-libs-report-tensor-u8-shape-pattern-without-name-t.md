---
id: TASK-0065
title: Libs report tensor-u8: shape pattern without name, tensor u8 from list, operator words in names, constructor patterns, full execve argv
status: completed
created: 2026-11-09
completed: 2026-11-09
requirements: [FR-COMP-022, FR-COMP-005, FR-VM-002]
tests: [TS-COMP-022, TS-COMP-005, TS-VM-002]
security: []
context_files: [docs/requirements/functional/compiler/FR-COMP-022-bytes-are-a-packed-tensor-u8.md, docs/etc/runtime_ext.md, src/main/ridgun/lib/parser.rg]
scope: [src/main/ridgun/lib/, tests/cases/, docs/]
owner: agent-001
claimed: 2026-11-09T19:28:00Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0065 — Libs report tensor-u8: shape pattern without name, tensor u8 from list, operator words in names, constructor patterns, full execve argv

## Goal (one sentence)
Answer the libs report `tensor-u8` (2026-11-09, ridgunc 0.9.49): a shape pattern gives the real dimensions of a `Tensor[U8]` without a name, fixed bytes can be written as a list, and a function whose name holds an operator word can be called, a `Tensor[U8]` bound inside any pattern is read by bytes, and `sys execve` passes the whole argv.

## Plan
- [x] Reproduce the three points on both backends (`/tmp/ridgun-compiler/2026-11-09/tensor-u8/`).
- [x] Shape pattern `(Tensor[U8 * n] _)` / `(Tensor[U8 * n])`: the parser gives the tensor a hidden name (`_tp_<element>`), so the type checker records its element kind and lowering reads the dimensions of a packed tensor.
- [x] `tensor u8 from list [Int] => Tensor[U8]`: runtime extension builtin 119, one allocation, error outside 0..255.
- [x] Operator words in function names: calls work in any position (spec: every lowercase word of a signature is part of the name).
- [x] `Tensor[U8]` bound in a constructor, list cons, tuple or `Some` pattern: the type checker records the element kind of every variable a parameter pattern binds.
- [x] `sys execve path argv envp`: argv passed whole (argv[0] included), `-errno` on failure; runtime extension builtin 120.
- [x] LLVM runtime cache named by a fingerprint of its content, not by version.
- [x] Tests, docs (FR-COMP-022, FR-VM-002, spec, runtime_ext.md, skill), bootstrap, suites, install 0.9.50; answer libs.

## Progress log (append-only, newest last)
- 2026-11-09: Point 1: the shape pattern took its element kind only from the fact recorded for the bound variable; with `_` there was none, so lowering used the numeric path and read the storage words (rank + dimensions + packed words: 300 bytes gave 40).
- 2026-11-09: Point 3: rejecting operator words in declarations would break about 50 existing functions (libs, ecosystem, compiler: `pred and`, `assert not`, `first str or`, and libs' own `shl` / `shr`), and the spec already says every lowercase word of a signature is part of the name. So calls were made to work instead: one normalisation rule for `and`, `or`, `xor`, `shl`, `shr`, `rotl`, `rotr` in the middle or at the end of a name (it existed for `and` / `or` only), `and` / `or` / `xor` accepted as the first word of a name in operand position, a `not` rule for names that start with `not`, and the shift words added to the word set that selects candidate functions (without them `rot shl` was never a candidate).
- 2026-11-09: LLVM builds of a program using builtin 119 crashed with a stage 1 still at 0.9.49: the LLVM runtime cache is named by version only, so it held the old runtime. Bumped to 0.9.50 and documented the pitfall in `docs/etc/runtime_ext.md`.
- 2026-11-09: The report gained points 4 and 5. Point 4: element-kind facts were recorded only for a parameter that is a plain variable or a tuple; a variable bound inside a constructor (`ROk _ p`), a list cons or `Some` had none, so lowering read the storage words. `pat tensor info` now walks every pattern shape with the constructor's parameter types. `Option Tensor[U8]` travels as a string, so `parse type str` reads back `Tensor[E]` / `Tensor[E](dims)`.
- 2026-11-09: Point 5: `sys execve` (was id 63, put `path` as argv[0]) is now runtime extension builtin 120: NUL-terminated copies and pointer tables in one block, then `execve(2)`. Nobody used the old form (libs, ecosystem, compiler).
- 2026-11-09: The same stale-cache trap hit id 120 on LLVM (execve did nothing). Fixed for good: the cache file is named by a fingerprint of the runtime bytes and the linker script, so a changed runtime never reuses an old file (about 20 ms per build).

## Files changed (keep current)
- `src/main/ridgun/lib/parser.rg`: hidden name for unnamed tensor patterns; `op name word`, `can lead mixfix`, generic operator-word rules in `norm expr`; `and` / `or` / `xor` as name words in `parse atom base`; shift words in `collect expr ident words set`; arity entries for `tensor_u8_from_list`.
- `src/main/ridgun/lib/typecheck.rg`: `tensor_u8_from_list` type; element-kind facts for every pattern shape (`param tensor infos`, `pat tensor info`); `Tensor[E]` strings read back by `parse type str`.
- `src/main/ridgun/lib/compiler.rg`: builtin ids 119 and 120.
- `src/main/ridgun/lib/llvm.rg`: runtime cache named by fingerprint (`rt fingerprint`, `llvm rt cache base`).
- `src/main/ridgun/lib/x86_64.rg`: runtime extension bytes (11 120).
- `docs/etc/runtime_ext.md` (C source, ids 119 and 120, cache note), FR-COMP-022, FR-VM-002, `docs/lang/spec.md`, Ridgun skill.
- Tests: `tests/cases/tensors/bytes_shape_pattern_without_name.rg`, `bytes_from_list.rg`, `bytes_from_list_out_of_range_fails.rg`, `tests/cases/names/operator_words_in_function_names.rg`, `tests/cases/tensors/bytes_in_constructor_pattern.rg`, `tests/cases/runtime/execve_passes_the_whole_argv.rg`.
- Version 0.9.50: `build.rg`, `ridgunc/main.rg`, `stable/main.rg`.
- `src/test/ridgun/test lib and plugins.rg`: reads `.so` bytes with `tensor to list (read bytes ...)` (0.9.48 change) and checks the `stable` version format, not a fixed 0.9.30.

## Verification performed (command → result, newest last)
All runs capped (`ulimit -v` 4 GB, timeout).
- Stage 1, LLVM and x86-64: libs' `patron.rg` gives `300 300` / `5 5`; `xor-en-nombre.rg` gives `5`; `tensor u8 from list` builds, reads, converts, compares and stops on 256; 10 names with operator words in every position give the expected sums; operators outside names unchanged.
- The four new cases pass on both backends.
- Stage 1 with points 4–5, LLVM and x86-64: libs' `constructor.rg` gives `[97, 98, 99, 100]`, `98`, `abcd`; `sys execve "/bin/cat" ["mycat", "/proc/self/cmdline"]` shows `mycat`; a missing program returns `-2`; output written before the exec is flushed.
- The two new cases (constructor / cons / `Some` patterns, execve) pass on both backends.
- Bootstrap s1 → s4: s3 and s4 differ in 2 bytes (temporary file name), fixed point.
- `tests/run.rg` with s3 and its `stable`: 256 of 256 (llvm 132, x86-64 124).
- `src/test/ridgun/test*.rg` (8 files) built by s3: all pass on LLVM and x86-64.
- libs `stable test` with s3 and its `stable`: 34 of 35, as with 0.9.49 (only `test mail`: its SMTP test server does not start here).
- Installed: s3 and its `stable` in `target/*_candidate` and `bin/`.

## Exact next actions
1. None: done; libs answered in the shared compiler notes.

## Decisions / open questions
- `tensor from list` keeps giving `Tensor[Int]` for `[Int]`; the type of an expression does not depend on where it is used. Bytes from a list have their own builtin.
- An operator-word name call followed by another operator at the same level still needs parentheses (`(mask xor 6 3) == 5`), as for `and` / `or` before.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated (none)  - [x] docs INDEX updated (no new docs)  - [x] coverage matrix regenerated (not kept in this project)
