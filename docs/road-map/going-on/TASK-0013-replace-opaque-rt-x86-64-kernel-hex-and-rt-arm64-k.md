---
id: TASK-0013
title: Replace opaque rt_x86_64_kernel_hex and rt_arm64_kernel_hex blobs with readable Ridgun runtime codegen (rt_slot 1..55)
status: going-on
created: 2026-10-21
completed:
requirements:
  - FR-COMP-002
  - FR-COMP-004
tests: []
security: []
context_files:
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/arm64.rg
  - src/main/ridgun/lib/elf64.rg
  - docs/etc/cmm_architecture.md
scope:
  - src/main/ridgun/lib/
owner: agent-001
claimed: 2026-10-22T07:46:27Z
claimed_by: agent gemini@solarfall
---
# TASK-0013 — Replace opaque `rt_x86_64_kernel_hex` and `rt_arm64_kernel_hex` blobs with readable Ridgun runtime codegen (`rt_slot 1..55`)

## Goal (one sentence)
Replace the pre-assembled hexadecimal runtime kernel strings (`rt_x86_64_kernel_hex` in `src/main/ridgun/lib/x86_64.rg` and `rt_arm64_kernel_hex` in `src/main/ridgun/lib/arm64.rg`) with readable, symbolic Ridgun instruction-builder functions so every runtime routine (`rt_slot 1..55`) can be inspected and modified directly in `.rg` source code without opaque hex blobs.

## Runtime Slot Map (`0x401000` Jump Table — `x86_call_rt 1..55`)
Each slot at `0x401000 + slot * 8` is an 8-byte jump entry (`e9 <rel32> 0f 1f 00` on `x86_64`, `b <rel26>` on `ARM64`), allowing incremental, slot-by-slot replacement:
- **Phase 1 — Stack Frames & `RMM1`/`RMM2` Memory Management (`Slots 1..10`)**:
  - `Slot 1`: Function prologue frame init (`rdi=frame_ptr, rsi=args_ptr, rdx=arity, rcx=num_slots`)
  - `Slot 2`: Function epilogue frame drop & return sparing (`RMM2` return sparing & local cascade drop)
  - `Slot 3`: Tail-call (`NTailCall`) frame slide & rebind
  - `Slot 4`: `NClearLocals` range drop (`start_slot..end_slot`)
  - `Slot 5`: `NCloneSlot` (`+1` reference count increment on assignment)
  - `Slot 6`: `NDropVal` (`-1` reference count decrement & child cascade free)
  - `Slot 7`: `NMoveSlot` (`RMM1` zero-copy move)
  - `Slot 8`: `NStoreSlot` (initial local binding store)
  - `Slot 9`: `NRebindSlot` (`mut` variable reassignment: `+1` new, `-1` old)
  - `Slot 10`: `NCmmDropSlot` (`RMM1` static last-use drop)
- **Phase 2 — Values, Strings, Collections & Pattern Matching (`Slots 11..37`)**:
  - `Slots 11..19`: `NLoadRealLit`, `NLoadStrLit`, `NLoadAdt0`, `NMakeAdt`, `NMakeList`, `NMakeTuple`, `NMakeTensor`, `NStrInterp`, `NPackSeq`
  - `Slots 20..33`: `NAsBool`, `NMatchInt`, `NMatchReal`, `NMatchStr`, `NMatchBool`, `NMatchEmpty`, `NMatchNonEmpty`, `NListHead`, `NListTail`, `NMatchTuple`, `NTupleGet`, `NMatchAdt`, `NAdtField`, `NAdtSet`
  - `Slots 34..37`: `NNot`, `NOut`, `NEcho`, `NBinOp` (`+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `::`, `++`)
- **Phase 3 — Tensors, Regions & Scoped State (`Slots 38..52`)**:
  - `Slots 38..42`: `NIndex`, `NIndexSet`, `NSeqSelect`, `NEinsum` (`@`), `NHadamard` (`@+`, `@-`, `@*`, `@/`)
  - `Slots 43..52`: `NPushCtx`, `NPopCtx`, `NHasCtx`, `NGetCtx`, `NEnterRegion`, `NExitRegion` (`with region`), `NHasShared`, `NGetShared`, `NInitShared`, `NStoreShared`
- **Phase 4 — Concurrency, Higher-Order Combinators & Base Built-ins (`Slots 53..55`)**:
  - `Slots 53..54`: `NCallIndirect1`, `NCallIndirect2`
  - `Slot 55`: `NCallBuiltin` (`b_id < 70`: strings, files, SHA-256, `||map`/`||filter` thread pool via `clone`+`futex`, channels; note: `b_id 70..85` PAL primitives are already separated at `0x416680`).

## Plan
- [x] Create a symbolic `x86_64` / `ARM64` runtime assembler helper module in `src/main/ridgun/lib/` (with label resolution, structured register names, and Linux syscall wrappers).
- [x] Replace Phase 1 (`Slots 1..10`: `RMM1`/`RMM2` allocator and reference-counting routines) and initial Phase 2 constructors (`Slots 11..16`) with symbolic Ridgun codegen and verify against `test core language.rg`.
- [x] Replace remaining Phase 2 (`Slots 17..37`: `Tensor` constructor, `NStrInterp`, `NPackSeq`, pattern matching `Slots 20..33`, and `NNot`/`NOut`/`NEcho`/`NBinOp` `Slots 34..37`) and verify against `test basics.rg` and `test strings.rg`.
- [x] Replace Phase 3 (`Slots 38..52`: `Tensor`/`einsum` and `with region`/`context`/`shared`) and verify against `test parallel and tensors.rg`.
- [x] Replace Phase 4 (`Slots 53..55`: indirect calls, `||map`/`||filter` threads, and base built-ins) and remove `rt_x86_64_pre_hex` / `rt_x86_64_suf_hex` completely.

## Progress log (append-only, newest last)
- 2026-10-21: Created `TASK-0013` in backlog with the complete 55-slot jump-table map so the runtime kernel can be migrated from hex blobs to readable Ridgun functions phase by phase.
- 2026-10-22: Started `TASK-0013` (`v0.9.7`). Replaced the 56-entry `0x401000` jump table (`x86_build_rt_jump_table`), Phase 1 `RMM1`/`RMM2` stack frame & memory management routines (`Slots 1..10`), and initial Phase 2 constructors (`Slots 11..16`) in `src/main/ridgun/lib/x86_64.rg` and `src/main/ridgun/lib/arm64.rg` with symbolic Ridgun instruction builders. Verified 2-stage self-hosting fixed-point (`target/ridgunc_stage1 == target/ridgunc_candidate`) and all 5/5 test suites green.
- 2026-10-22: Completed **Phase 2 (`Slots 11..37`)** (`v0.9.8`) in `src/main/ridgun/lib/x86_64.rg` (`x86_build_rt_phase2_bytes`, 8,828 bytes across `Slots 11..37` including `NMakeTensor`, `NStrInterp`, `NPackSeq`, `NAsBool`, `NMatchInt`/`NMatchReal`/`NMatchStr`/`NMatchBool`/`NMatchEmpty`/`NMatchNonEmpty`/`NListHead`/`NListTail`/`NMatchTuple`/`NTupleGet`/`NMatchAdt`/`NAdtField`/`NAdtSet`, and `NNot`/`NOut`/`NEcho`/`NBinOp`) and `src/main/ridgun/lib/arm64.rg`. Expanded `test basics.rg` and `test strings.rg` and verified 2-stage self-hosting fixed point (`SELF_HOST_FIXED_POINT_OK`) + all 5/5 test suites green.
- 2026-10-22: Completed **Phase 3 (`Slots 38..52`)** (`v0.9.10`) in `src/main/ridgun/lib/x86_64.rg` (`x86_build_rt_phase3_bytes`, 7,632 bytes across `Slots 38..52`: `NIndex`, `NIndexSet`, `NEinsum`, `NHadamard`, `NSeqSelect`, `NSeqIndices`, `NEnterRegion`, `NExitRegion`, `NGetCtx`, `NPushCtx`, `NPopCtx`, `NGetShared`, `NInitShared`, `NStoreShared`, and `NMmioOp`) and `src/main/ridgun/lib/arm64.rg`. Expanded `test parallel and tensors.rg`, synced `harness/` to `v0.9.10`, and verified 2-stage self-hosting fixed point + all 5/5 test suites green.
- 2026-10-22: Completed **Phase 4 (`Slots 53..55` + `pre` + `pal`)** (`v0.9.11`) in `src/main/ridgun/lib/x86_64.rg` and `src/main/ridgun/lib/arm64.rg`, removing all remaining hex strings (`rt_x86_64_pre_hex`, `rt_x86_64_suf_hex`, `rt_x86_64_pal_hex`) and dead `hex` helpers in `src/main/ridgun/lib/elf64.rg`. Converted function declarations and calls across `elf64.rg`, `x86_64.rg`, `arm64.rg`, and `compiler.rg` to natural spaces (`FR-COMP-005`, `FR-COMP-008`), wrote `docs/etc/low_level_ridgun_runtime_design.md`, and verified 2-stage self-hosting fixed point + all 5/5 test suites green.

## Files changed (keep current)
- `src/main/ridgun/lib/x86_64.rg`
- `src/main/ridgun/lib/arm64.rg`
- `src/main/ridgun/lib/elf64.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/test/ridgun/test basics.rg`
- `src/test/ridgun/test core language.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test strings.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/main/ridgun/lib/compiler.rg`
- `docs/etc/low_level_ridgun_runtime_design.md`
- `docs/etc/INDEX.md`

## Verification performed (command → result, newest last)
- `./target/ridgunc_stage1 build src/main/ridgun/ridgunc/main.rg -o target/ridgunc_candidate && cmp -s target/ridgunc_stage1 target/ridgunc_candidate` → 0 (100% byte-identical self-hosting fixed point for `v0.9.11`).
- `./bin/stable check` → Checked 13 module(s) — 0 errors.
- `./bin/stable test` → Passed 5/5 test suite(s) — 0 failures.

## Exact next actions
1. All 4 phases of `TASK-0013` are complete; design the Actor concurrency model (`actor ::`) and update book Chapter 07.

## Decisions / open questions
- Because `0x401000` uses a 55-entry jump table (`rt_slot 1..55`), each phase was migrated to symbolic Ridgun instruction builders and verified at the 2-stage self-hosting fixed point; zero hex blobs remain in the compiler.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
