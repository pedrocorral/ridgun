---
id: TASK-0088
title: Ridgun runtime and memory allocator as wasm functions
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
# TASK-0088 — Runtime and memory as wasm

## Goal (one sentence)
The runtime slots of `arm64.ridgun` (lists, strings, ADTs, matching, builtins, RMM) exist as wasm functions in `wasm.ridgun`.

## Plan
- [ ] Allocator over one linear memory, growing with `memory.grow`; RMM rules unchanged.
- [ ] Port the slots one by one, in the order of `arm64.ridgun`; each with a run test.
- [ ] Agents on one thread: a step runs when its message arrives.

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0011. Needs TASK-0087. The largest task: about the size of the ARM64 runtime.

## Exact next actions
1. Allocator over one linear memory, growing with `memory.grow`; RMM rules unchanged.
