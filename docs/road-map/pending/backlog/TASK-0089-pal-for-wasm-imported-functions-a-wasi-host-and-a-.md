---
id: TASK-0089
title: PAL for wasm: imported functions, a WASI host and a browser JavaScript host
status: pending             # pending | going-on | blocked | completed
created: 2026-11-12
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0011-webassembly-is-a-native-backend.md, docs/requirements/decisions/ADR-0012-the-playground-reads-libraries-from-a-virtual-file-system.md]
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0089 — PAL for wasm

## Goal (one sentence)
The PAL (ADR-0008) has a wasm implementation: the module imports write, read, clock, exit, files and arguments.

## Plan
- [ ] Define the import list (module `ridgun`), with types.
- [ ] A WASI host: the imports mapped to WASI preview 1, for wasmtime and Node.
- [ ] A browser host in JavaScript (about 200 lines), run in a Web Worker: stdout to the page; the virtual file system of ADR-0012 (`/home/play/.local/lib/ridgun/` read-only from the manifest, each file fetched on first read; `/work/` in memory; `HOME=/home/play`).
- [ ] The checker reports `net …` for the wasm32 target.

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0011. Needs TASK-0088.

- 2026-11-14: ADR-0012 fixes how the browser host serves files: a manifest and one fetch per library on first read.

## Exact next actions
1. Define the import list (module `ridgun`), with types.
