---
id: TASK-0014
title: Refactor stable to consume standard libraries (str, posix, io) from ridgun-libs
status: completed
created: 2026-10-21
completed: 2026-10-21
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
owner: agent-001
claimed: 2026-10-21T20:04:59Z
claimed_by: agent gemini@solarfall
---
# TASK-0014 — Refactor `stable` to consume standard libraries (`str`, `posix`, `io`) from `ridgun-libs`

## Goal (one sentence)
Dogfood `/home/boogie/ridgun-libs` (`str.rglib`, `posix.rglib`, `io.rglib`) inside `src/main/ridgun/stable/main.rg` by replacing hand-rolled string helpers and temporary-file `shell_exec "ls -1 ..."` directory scans with standard library calls.

## Plan
- [x] Declare `/home/boogie/ridgun-libs` in `build.rg` (`dependencies`) or bundle `str.rglib`, `posix.rglib`, and `io.rglib` into `.stable/deps/` / `lib/`.
- [x] Replace ad-hoc string helpers in `src/main/ridgun/stable/main.rg` (`split lines of`, `split words of`, `join words ... with spaces`) with `str` library functions (`str split`, `str join`, `str trim`, `str ends with`, `str replace`, `str pad right`).
- [x] Replace `shell_exec ('ls -1 ... > target/.stable_files.txt')` temporary file hacks in `src/main/ridgun/stable/main.rg` with pure Ridgun directory and metadata traversal via `io` (`list_dir`, `is dir`, `is file`) and `list` (`list str sort`, `list str dedup`, `list str drop`) + `cli` (`cli has flag`, `cli positionals`, `env get or`).
- [x] Replace raw `echo "[info] ..."` / `echo "[error] ..."` calls with dedicated logging functions (`log info`, `log success`, `log error`, `log ok`, `log err`, `log pass`, `log fail`, `log step`, `log section`).
- [x] Upgrade `src/test/ridgun/test.rg` and `src/test/ridgun/test lib and plugins.rg` with comprehensive multi-angle tests for `stable` and verify `target/stable_candidate` 100% before updating `bin/stable` (`v0.9.6`).

## Progress log (append-only, newest last)
- 2026-10-21: Created `TASK-0014` in `pending/next/` per user request so `stable` consumes `ridgun-libs` as a real application.
- 2026-10-21: Refactored `src/main/ridgun/stable/main.rg` to import `str`, `io`, `list`, and `cli` from `/home/boogie/ridgun-libs`, added dedicated `log *` functions, fixed batch CLI exit-code propagation (`exit if non zero`), expanded `test.rg` and `test lib and plugins.rg` with 6 multi-angle test sections, verified `target/stable_candidate` 100%, backed up `bin/stable.bak` & `bin/ridgunc.bak`, and updated `bin/stable` & `bin/ridgunc` to `v0.9.6`.

## Files changed (keep current)
- `build.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `README.md`

## Verification performed (command → result, newest last)
- `./target/stable_candidate check` → `Checked 13 module(s) — 0 errors.`
- `./target/stable_candidate test` → `Passed 5/5 test suite(s) — 0 failures.`
- `./bin/stable test` → `Passed 5/5 test suite(s) — 0 failures.`
- `aix docs validate` → `0 errors, 1 warnings`

## Exact next actions
1. Completed (`v0.9.6`).

## Decisions / open questions
- Keep `ridgunc` zero-dependency (so it can always bootstrap `ridgun-libs` from source), while `stable` imports `str.rglib`, `posix.rglib`, `io.rglib`, `list.rglib`, and `cli.rglib` from `ridgun-libs`.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
