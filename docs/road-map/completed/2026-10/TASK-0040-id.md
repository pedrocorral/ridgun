---
id: TASK-0040
title: Colorize bracketed status tags in stable CLI output
status: completed
created: 2026-10-27
completed: 2026-10-27
requirements:
  - FR-TOOL-001
  - FR-TOOL-002
  - FR-TOOL-003
tests:
  - TS-TOOL-001
  - TS-TOOL-002
  - TS-TOOL-003
security: []
context_files:
  - src/main/ridgun/stable/main.rg
  - src/test/ridgun/test lib and plugins.rg
scope:
  - src/main/ridgun/stable/main.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/test/ridgun/test lib and plugins.rg
  - build.rg
  - bin/stable
  - bin/ridgunc
owner: agent-001
claimed: 2026-10-27T19:53:06Z
claimed_by: agent gemini@solarfall
---
# TASK-0040 — Colorize bracketed status tags in stable CLI output

## Goal (one sentence)
Colorize the inner text of bracketed status tags in `stable` (`ok`, `success`, `PASS` in green; `info`, `fmt`, `rgc`, `dep`, `plugin`, `task:...` in cyan; `error`, `err`, `FAIL` in red) while keeping the brackets `[` and `]` uncolored and preserving column alignment.

## Plan
- [x] Update `log info`, `log success`, `log error`, `log step` (`ok`, `err`, `PASS`, `FAIL`, `rgc`, `fmt`, `dep`, `plugin`), and `run custom shell task` (`task:...`) in `src/main/ridgun/stable/main.rg` to colorize only the inner text inside `[` and `]`.
- [x] Update `src/test/ridgun/test lib and plugins.rg` to match the ANSI-colored tags in `stable` output and bump version to `0.9.26`.
- [x] Build `bin/ridgunc` and `bin/stable` (`v0.9.26`), verify `stable check`, `stable test`, `tests/run.rg`, and `aix docs validate`.

## Progress log (append-only, newest last)
- 2026-10-27: Created and claimed `TASK-0040` (`agent-001`).
- 2026-10-27: Implemented `tag ansi code` and `colorize tag` in `src/main/ridgun/stable/main.rg`, updated `src/test/ridgun/test lib and plugins.rg`, built `ridgunc` and `stable` `v0.9.26`, and verified all test suites.

## Files changed (keep current)
- `src/main/ridgun/stable/main.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `./bin/stable check` → `Checked 14 module(s) — 0 errors.`
- `./bin/ridgunc run "src/test/ridgun/test lib and plugins.rg"` → `All library compilation, stable plugin & PAL timeout tests passed`
- `./bin/ridgunc run tests/run.rg` → `54 of 54 promised behaviours passed`

## Exact next actions
1. Task complete.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
