---
id: TASK-0086
title: wasm32 module writer: ridgunc writes a valid .wasm binary
status: completed
created: 2026-11-12
completed: 2026-11-14
requirements: [FR-COMP-026]
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0011-webassembly-is-a-native-backend.md]
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-14T16:09:53Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0086 — wasm32 module writer

## Goal (one sentence)
`src/main/ridgun/lib/wasm32.ridgun` writes a valid WebAssembly binary module from lists of types, imports, functions, a memory, exports, code and data.

## Plan
- [x] Write a new FR for the wasm32 target (or extend FR-COMP-015) with acceptance criteria per task below.
- [x] LEB128 (signed and unsigned) and the section encoder: type, import, function, memory, global, export, code, data.
- [x] A unit test builds a hand-made module (a function that returns 42) and compares its bytes with the expected bytes.
- [ ] Ask the user to approve installing a wasm engine (wasmtime, about 20 MB) before the first run test; none is installed.

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0011. Same role as `elf64.ridgun`. No dependency on the NIR yet.

- 2026-11-14: FR-COMP-026 written. `wasm32.ridgun` encodes types, imports, functions, memory, globals, exports, code (locals grouped into runs) and data. `test wasm.ridgun` checks LEB128 and two whole modules byte for byte (AC1, AC2). `llvm-objdump` reads the full module and agrees section by section. A run test needs a wasm engine (none installed): first run test moves to TASK-0087.

## Verification performed (command → result, newest last)
- `ridgunc check src/main/ridgun/lib/wasm32.ridgun` → 0 errors.
- `test wasm.ridgun` → all 17 assertions ok.
- `llvm-objdump -h -d -s full.wasm` → 8 sections parsed; `answer` with locals i64, i64, i32 and `i64.const 42`.

## Exact next actions
1. Write a new FR for the wasm32 target (or extend FR-COMP-015) with acceptance criteria per task below.
