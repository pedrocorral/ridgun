---
id: TASK-0060
title: Fix the stable deps toolchain checks (RG-107, RG-105)
status: completed
created: 2026-11-09
completed: 2026-11-09
requirements: [FR-TOOL-002]
tests: [TS-COMP-009]
security: []                # VUL-* to address
context_files: [tests/run.rg, tests/README.md, src/main/ridgun/stable/main.rg, docs/road-map/completed/2026-10/TASK-0050-fix-stable-deps-copy-rg105-rg106-rg107-and-add-full-regression-tests.md]
scope: [tests/run.rg, tests/README.md, src/main/ridgun/stable/main.rg]
owner: agent-002
claimed: 2026-11-09T12:03:34Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0060 — Fix the stable deps toolchain checks (RG-107, RG-105)

## Goal (one sentence)
`./bin/ridgunc run tests/run.rg` passes 118 of 118: the two `stable deps` toolchain checks pass, or a real `stable` defect is fixed with a regression check.

## Plan
- [x] Reproduce both failures with 0.9.46 (capped: `ulimit -v 4000000`, `timeout`).
- [x] RG-107 (`build tc6 result`, `tests/run.rg` around line 449): the generated `bash -c '...'` contains `printf '...'` with single quotes inside the single-quoted script; bash reports `syntax error near unexpected token '('` in `~/.cache/ridgun-compiler-tests/work/toolchain/.cmd_run.sh`. The reported output shows the text of an earlier check (`syntax_bad.rg`), so the output file is also stale. Fix the quoting and clear the output file before each check.
- [x] RG-105 (around line 454): the check prints only `fn` (exit 0). Find out whether the check or `stable deps` is wrong; fix the right side.
- [x] If `stable` changes: patch version +0.0.1, candidates in `target/`, then `bin/`. (`stable` did not change: no bump.)

## Progress log (append-only, newest last)
- 2026-11-09: Found during TASK-0059 verification. Both checks fail the same way on 0.9.45 and 0.9.46, so they are not caused by OPT-018.
- 2026-11-09: Reproduced: 116 of 118. Both failures come from the check, not from `stable`. `run sh capture` wraps the script in `bash -c '...'`, and the first `'` of `printf 'fn :: ...'` ends the outer quotes. RG-105: bash ran `printf fn`, so the output was `fn`. RG-107: an unquoted `(` made `.cmd_run.sh` a syntax error, so it never wrote `.cmd_out.txt`, and the check read the output of the syntax-error check before it (CH-001, `syntax_bad.rg`). Run as script files, both scripts print every OK marker with `bin/stable` 0.9.46.
- 2026-11-09: A third fault: the checks `cd` into the work folder, so `STABLE=bin/stable` (relative, as the task suggested) pointed nowhere. `RIDGUNC` had the same problem.
- 2026-11-09: Fix in `tests/run.rg`: (1) the tc6 and tc7 scripts are written to `tc6.sh` / `tc7.sh` in the work folder and run with `bash tc6.sh` / `bash tc7.sh`; (2) `run sh capture` empties `.cmd_out.txt` and `.cmd_time.txt` before each command, so a script that fails to start can no longer show an earlier check's output; (3) new `absolute from` takes a relative `RIDGUNC` / `STABLE` from the repository root. `tests/README.md` documents `STABLE` and the script-file rule.
- 2026-11-09: Process note: `aix` finds its project by walking up to `.aix/config.yaml`. This worktree sits inside the main checkout and has no kit (`.aix/*` is gitignored), so the first `aix task start` changed the main checkout. Those changes were reverted there (nothing else touched). The kit was then copied (gitignored) into the worktree's `.aix/`, and the task was started again here.

## Files changed (keep current)
- `tests/run.rg` — tc6/tc7 run from script files; `run sh capture` clears its output files; `absolute from` for `RIDGUNC` / `STABLE`.
- `tests/README.md` — `STABLE` variable, relative paths, script-file rule for toolchain checks.

## Verification performed (command → result, newest last)
- `ulimit -v 4000000; STABLE=bin/stable timeout 1200 ./bin/ridgunc run tests/run.rg` (before the fix) → 116 of 118; RG-107 "exit 2; output: syntax error at syntax_bad.rg:2:28 …", RG-105 "exit 0; output: fn".
- tc6 and tc7 scripts run by hand as files with `bin/stable` 0.9.46 → `MATCH_OK NO_BUILD_RG_OK FAIL_ON_MISSING_OK` (exit 0) and `REFRESH_OK`.
- `ulimit -v 4000000; timeout 120 ./bin/ridgunc check --strict tests/run.rg` → 0 errors.
- `ulimit -v 4000000; STABLE=bin/stable timeout 1200 ./bin/ridgunc run tests/run.rg` (after the fix) → 118 of 118 promised behaviours passed, exit 0.

## Exact next actions
None.

## Decisions / open questions
- `stable deps` is correct for RG-105 and RG-107; only the test harness changed, so no version bump and no `bin/` replacement.
- Not in scope, for the kit: `aix` run in a git worktree nested under the main checkout acts on the main checkout. It should resolve the worktree, or refuse.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated (none)  - [x] docs INDEX updated (no new docs)  - [x] coverage matrix regenerated (no TS change)
