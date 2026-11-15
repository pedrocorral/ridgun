---
id: TASK-0097
title: A rebuilt cons pattern is the matched list
status: completed
created: 2026-11-15
completed: 2026-11-15
requirements: [FR-COMP-011]  # FR-*/NFR-* this task delivers or touches
tests: [TS-COMP-011]        # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/etc/compiler_optimizations.md]  # THE ONLY files an agent must read to work on this task
scope: [src/main/ridgun/lib/compiler.ridgun, src/main/runtime/core/binop.ll]  # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-15T18:20:51Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0097 — A rebuilt cons pattern is the matched list

## Goal (one sentence)
A clause that rebuilds the list its cons pattern took apart (`(a:b:rest)` then `(b:rest)`) reuses the matched list on every backend, and the wasm32 runtime patch of TASK-0088 goes away.

## Plan
- [x] `share cons cases` in `compiler.ridgun`: the `:as:` pattern names the matched list; the rebuild reads it (OPT-021, FR-COMP-011 §9).
- [x] Case `tests/cases/perf/rebuilt_cons_pattern_is_the_matched_list.ridgun` on llvm, x86-64 and wasm32.
- [x] Remove the view patch from `rg_list_concat` (`rg_same_prefix`, `rg_view_back`); keep the in-place prepend.
- [x] Bootstrap, suites, unit tests, libs; version 1.0.13.

## Progress log (append-only, newest last)
- 2026-11-15: Created. TASK-0088 patched the runtime: `[b] :: rest` became a view when `b` was the word just before `rest`'s start. The general fix belongs in the compiler.

- 2026-11-15: The case uses 100 000 elements. With 200 000, `ordered` (not a tail call, because of `and`) passes the 8 MiB shadow stack of wasm32 (about 150 000 frames), while the native targets reach 1 000 000. That gap is a separate decision (shadow stack size against reserved memory in the browser), not part of this task.

## Files changed (keep current)
- `src/main/ridgun/lib/compiler.ridgun`, `src/main/runtime/core/binop.ll`, `docs/etc/compiler_optimizations.md`, FR-COMP-011, the new case.

## Verification performed (command → result, newest last)
- The case before the change (1 000 000 elements, compiler 1.0.12): 1.5 s on LLVM; after: 0.84 s, the rest being `count up` itself.
- 1.0.13: bootstrap c1 → c2 → c3, c2 and c3 differ only in the stamp (5 bytes of the temporary file name); with c3: native suite 310/312, the 2 failures being the new case's strict-mode tuple output (fixed: `=> Int [Int]`, then green with `--strict` on llvm, x86-64 and wasm32); wasm32 suite 143/149, the 6 failures being the FR-COMP-026 AC4 exclusions; 11 unit test files, 0 fails; libs `stable test` 35/35. Installed in `bin/`.

## Exact next actions
1. None: the task is complete.
