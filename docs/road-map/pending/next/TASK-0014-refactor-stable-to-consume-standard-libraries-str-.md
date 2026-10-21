---
id: TASK-0014
title: Refactor stable to consume standard libraries (str, posix, io) from ridgun-libs
status: pending
created: 2026-10-21
completed:
requirements:
  - FR-TOOL-002
  - FR-TOOL-003
  - FR-COMP-006
tests: []
security: []
context_files:
  - src/main/ridgun/stable/main.rg
  - build.rg
  - docs/lang/pal-and-system-libraries.md
scope:
  - src/main/ridgun/stable/main.rg
  - build.rg
owner:
claimed:
claimed_by:
---
# TASK-0014 — Refactor `stable` to consume standard libraries (`str`, `posix`, `io`) from `ridgun-libs`

## Goal (one sentence)
Dogfood `/home/boogie/ridgun-libs` (`str.rglib`, `posix.rglib`, `io.rglib`) inside `src/main/ridgun/stable/main.rg` by replacing hand-rolled string helpers and temporary-file `shell_exec "ls -1 ..."` directory scans with standard library calls.

## Plan
- [ ] Declare `/home/boogie/ridgun-libs` in `build.rg` (`dependencies`) or bundle `str.rglib`, `posix.rglib`, and `io.rglib` into `.stable/deps/` / `lib/`.
- [ ] Replace ad-hoc string helpers in `src/main/ridgun/stable/main.rg` (`split lines of`, `split words of`, `join words ... with spaces`) with `str` library functions (`str split`, `str join`, `str trim`, `str ends with`).
- [ ] Replace `shell_exec ('ls -1 ... > target/.stable_files.txt')` temporary file hacks in `src/main/ridgun/stable/main.rg` with pure Ridgun directory and metadata traversal via `io` / `posix` (`list_dir`, `is dir`, `file exists`, `sys mkdir`).
- [ ] Rebuild `bin/stable` (`stage2`) and verify `./bin/stable check` and `./bin/stable test` pass with 0 errors.

## Progress log (append-only, newest last)
- 2026-10-21: Created `TASK-0014` in `pending/next/` per user request so `stable` consumes `ridgun-libs` as a real application.

## Files changed (keep current)
-

## Verification performed (command → result, newest last)
-

## Exact next actions
1. Start `TASK-0014` with `aix task start TASK-0014` once `ridgun-libs` finishes updating its `v0.9.5` `.rglib` bundles.

## Decisions / open questions
- Keep `ridgunc` zero-dependency (so it can always bootstrap `ridgun-libs` from source), while `stable` imports `str.rglib`, `posix.rglib`, and `io.rglib` from `ridgun-libs`.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
