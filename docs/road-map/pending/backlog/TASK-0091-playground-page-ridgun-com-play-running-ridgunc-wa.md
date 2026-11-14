---
id: TASK-0091
title: Playground page ridgun.com/play running ridgunc.wasm in the browser
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
# TASK-0091 — Playground page

## Goal (one sentence)
`ridgun.com/play`: a static page where a visitor writes a program, `ridgunc.wasm` compiles it in the browser, and the output shows on the page.

## Plan
- [ ] Work in the www-ridgun repository: editor, the JavaScript host from TASK-0089, `ridgunc.wasm` served compressed.
- [ ] Examples to start from; a share link that carries the code in the URL fragment (never sent to the server).
- [ ] Publish under `ridgun.com/play/<ridgunc version>/`: `ridgunc.wasm`, the host, and `lib/` with the ridgun-libs bundles of the matching release and `lib/manifest.txt` (ADR-0012); immutable files, long cache life, compressed by the server.
- [ ] No server-side compile or run.

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0011. Needs TASK-0090.

- 2026-11-14: ADR-0012: the libraries are files under `lib/` with a manifest, fetched on first read.

## Exact next actions
1. Work in the www-ridgun repository: editor, the JavaScript host from TASK-0089, `ridgunc.wasm` served compressed.
