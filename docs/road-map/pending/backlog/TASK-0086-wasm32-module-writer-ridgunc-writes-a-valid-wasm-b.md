---
id: TASK-0086
title: wasm32 module writer: ridgunc writes a valid .wasm binary
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
# TASK-0086 — wasm32 module writer

## Goal (one sentence)
`src/main/ridgun/lib/wasm32.ridgun` writes a valid WebAssembly binary module from lists of types, imports, functions, a memory, exports, code and data.

## Plan
- [ ] Write a new FR for the wasm32 target (or extend FR-COMP-015) with acceptance criteria per task below.
- [ ] LEB128 (signed and unsigned) and the section encoder: type, import, function, memory, global, export, code, data.
- [ ] A unit test builds a hand-made module (a function that returns 42) and compares its bytes with the expected bytes.
- [ ] Ask the user to approve installing a wasm engine (wasmtime, about 20 MB) before the first run test; none is installed.

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0011. Same role as `elf64.ridgun`. No dependency on the NIR yet.

## Exact next actions
1. Write a new FR for the wasm32 target (or extend FR-COMP-015) with acceptance criteria per task below.
