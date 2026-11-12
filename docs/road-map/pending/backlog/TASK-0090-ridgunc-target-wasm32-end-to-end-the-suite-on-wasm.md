---
id: TASK-0090
title: ridgunc --target wasm32 end to end, the suite on wasm, and ridgunc.wasm
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
# TASK-0090 — --target wasm32 end to end

## Goal (one sentence)
`ridgunc build --target wasm32` produces a runnable `.wasm`; the suite passes on it; `ridgunc` builds itself to `ridgunc.wasm`.

## Plan
- [ ] `ridgunc` help and `stable` know the target.
- [ ] `tests/run.ridgun` gains the wasm backend (all cases except network and true parallelism).
- [ ] `ridgunc.wasm` compiles a program to `.wasm` under the WASI host, and the result matches the Linux build.

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0011. Needs TASK-0089.

## Exact next actions
1. `ridgunc` help and `stable` know the target.
