---
id: TASK-0087
title: Translate the NIR to wasm instructions
status: pending             # pending | going-on | blocked | completed
created: 2026-11-12
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0011-webassembly-is-a-native-backend.md]
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0087 — NIR to wasm instructions

## Goal (one sentence)
`src/main/ridgun/lib/wasm.ridgun` translates each NIR function to wasm code.

## Plan
- [ ] Values are `i64`; addresses are `i32` (wrap at each load and store).
- [ ] Each function is a `loop` with a `br_table` that selects the next NIR block (labels become block indexes).
- [ ] Calls to runtime slots become `call` to runtime function indexes.
- [ ] `emit elf for target` in `compiler.ridgun` gains `"wasm32"`.

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0011. Needs TASK-0086.

## Exact next actions
1. Values are `i64`; addresses are `i32` (wrap at each load and store).
