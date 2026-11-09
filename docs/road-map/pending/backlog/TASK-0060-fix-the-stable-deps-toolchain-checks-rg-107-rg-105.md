---
id: TASK-0060
title: Fix the stable deps toolchain checks (RG-107, RG-105)
status: pending             # pending | going-on | blocked | completed
created: 2026-11-09
completed:
requirements: [FR-TOOL-002]
tests: [TS-COMP-009]
security: []                # VUL-* to address
context_files: [tests/run.rg, tests/README.md, src/main/ridgun/stable/main.rg, docs/road-map/completed/2026-10/TASK-0050-fix-stable-deps-copy-rg105-rg106-rg107-and-add-full-regression-tests.md]
scope: [tests/run.rg, src/main/ridgun/stable/main.rg]
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0060 — Fix the stable deps toolchain checks (RG-107, RG-105)

## Goal (one sentence)
`./bin/ridgunc run tests/run.rg` passes 118 of 118: the two `stable deps` toolchain checks pass, or a real `stable` defect is fixed with a regression check.

## Plan
- [ ] Reproduce both failures with 0.9.46 (capped: `ulimit -v 4000000`, `timeout`).
- [ ] RG-107 (`build tc6 result`, `tests/run.rg` around line 449): the generated `bash -c '...'` contains `printf '...'` with single quotes inside the single-quoted script; bash reports `syntax error near unexpected token '('` in `~/.cache/ridgun-compiler-tests/work/toolchain/.cmd_run.sh`. The reported output shows the text of an earlier check (`syntax_bad.rg`), so the output file is also stale. Fix the quoting and clear the output file before each check.
- [ ] RG-105 (around line 454): the check prints only `fn` (exit 0). Find out whether the check or `stable deps` is wrong; fix the right side.
- [ ] If `stable` changes: patch version +0.0.1, candidates in `target/`, then `bin/`.

## Progress log (append-only, newest last)
- 2026-11-09: Found during TASK-0059 verification. Both checks fail the same way on 0.9.45 and 0.9.46, so they are not caused by OPT-018.

## Files changed (keep current)
-

## Verification performed (command → result, newest last)
-

## Exact next actions
1. Run `STABLE=bin/stable ./bin/ridgunc run tests/run.rg` under a memory cap and read the full output of both checks.

## Decisions / open questions

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
