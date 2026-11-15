---
id: TASK-0088
title: The whole runtime in target-neutral LLVM IR, used on wasm32 first
status: pending             # pending | going-on | blocked | completed
created: 2026-11-12
completed:
requirements: [FR-COMP-026]  # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0013-the-whole-runtime-is-target-neutral-llvm-ir.md, docs/requirements/decisions/ADR-0011-webassembly-is-a-native-backend.md, docs/etc/runtime_ext.md]
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0088 — The runtime in target-neutral LLVM IR, on wasm32 first

## Goal (one sentence)
Every runtime slot exists once, in target-neutral LLVM IR (ADR-0013), and the wasm32 backend runs the promised behaviours with it.

## Plan
- [ ] Write the runtime from scratch from its contract: the 55 runtime entries declared in `llvm.ridgun` (names and arguments), the value representation (`docs/etc/low_level_ridgun_runtime_design.md`), `rtx.c` and the FRs. No disassembly of the old bytes.
- [ ] Write the IR: `i64` words, explicit pointer conversions, no inline assembly; system operations as PAL calls; page-0 variables as globals.
- [ ] Allocator over one linear memory on wasm32 (`memory.grow` behind the PAL); RMM rules unchanged.
- [ ] Compile the IR with `llc -march=wasm32` and embed the functions in the module that `wasm.ridgun` writes; delete the provisional scalar runtime of `wasm.ridgun`.
- [ ] Agents on one thread on wasm32: a step runs when its message arrives.
- [ ] Run the promised behaviours on wasm32 (except network and true parallelism).

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0011. Needs TASK-0087.
- 2026-11-15: Redefined by ADR-0013: one runtime source in target-neutral LLVM IR for every target, instead of a runtime hand-written in wasm. Moving x86-64, ARM64 and Windows onto it are later tasks.
- 2026-11-15: The runtime is written from scratch from its contract and the suite, not recovered from the old bytes.

## Exact next actions
1. List the 55 runtime entries of `llvm.ridgun` with their arguments, results and meaning, from the code that calls them and the FRs.
