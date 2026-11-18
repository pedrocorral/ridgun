---
id: TASK-0095
title: No fixed paths of the development machine in stable and the test runner
status: completed
created: 2026-11-14
completed: 2026-11-18
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [src/main/ridgun/stable/main.ridgun, tests/run.ridgun]
scope: [src/main/ridgun/stable/main.ridgun, tests/run.ridgun, src/test/ridgun/test.ridgun]
owner: agent-001
claimed: 2026-11-18T20:36:16Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0095 — No fixed paths of the development machine in stable and the test runner

## Goal (one sentence)
`stable` and `tests/run.ridgun` find `ridgunc` and the libraries on any machine, with no path of the development machine written in the code.

## Why
Some searches end in a path that only exists on the machine where Ridgun is developed. On another machine that step finds nothing, or, worse, finds a different file that happens to be there.

| Where | Fixed path | What it looks for |
|---|---|---|
| `src/main/ridgun/stable/main.ridgun:343` (`pick ridgunc binary`) | `/home/boogie/ridgun/bin/ridgunc` | `ridgunc`, after `RIDGUNC`, the binary next to `stable`, `bin/ridgunc` and `target/ridgunc`; before `ridgunc` on the `PATH` |
| `tests/run.ridgun:214` (`resolve libs default`) | `/home/boogie/ridgun/libs/target/bundles` | the ridgun-libs bundles, when `RIDGUN_LIBS_BUNDLES` is unset; before `<repo>/.stable/deps` |
| `src/test/ridgun/test.ridgun:4` (comment) | `/home/boogie/ridgun-libs/...` | only a note of where the file is synced from; the path is also stale |

The fixed path in the library search of `parser.ridgun` (`/home/boogie/ridgun/ridgun/.stable/deps`) is not here: TASK-0089 removes it together with `ridgunc --libs` (ADR-0012).

## Plan
- [x] `stable`: drop the fixed path. The order stays `RIDGUNC`, the binary next to `stable`, `bin/ridgunc`, `target/ridgunc`, then `ridgunc` on the `PATH`.
- [x] `tests/run.ridgun`: drop the fixed path. The libraries come from `RIDGUN_LIBS_BUNDLES`, which already exists, else `<repo>/.stable/deps`. Document the variable in `tests/README.md` if it is not there.
- [x] `test.ridgun`: the comment names the ridgun-libs repository and file, not a folder of one machine.
- [x] Look once more for `/home/` in `src/`, `tests/` and `build.ridgun`; nothing left but documentation examples.
- [x] Verify: `stable` builds a project with `RIDGUNC` unset from a folder without `bin/`; the suite with `RIDGUN_LIBS_BUNDLES` set and unset; bootstrap and fixed point (`stable` changes).

## Progress log (append-only, newest last)
- 2026-11-18: Done in 1.0.32 and 1.0.33. The fixed path of `parser.ridgun` (also listed in TASK-0089) was removed in 1.0.32 (the case that relied on it declares `-- uses-libs`); `stable` no longer tries `/home/boogie/ridgun/bin/ridgunc`; `tests/run.ridgun` takes the libraries from `RIDGUN_LIBS_BUNDLES` or `<repo>/.stable/deps`; the comment of `test.ridgun` names the ridgun-libs repository; `tests/README.md` documents the variable. `grep /home/` in `src/`, `tests/` and `build.ridgun` finds only the example path in a comment of `parser.ridgun`.
- 2026-11-14: Created at the user's request, after the fixed paths were found while writing ADR-0012.

## Files changed (keep current)
-

## Verification performed (command → result, newest last)
-

## Exact next actions
1. Remove the fixed path from `pick ridgunc binary` in `stable`.

## Decisions / open questions
- The local workflow sets `RIDGUN_LIBS_BUNDLES=/home/boogie/ridgun/libs/target/bundles` (or keeps the bundles in `.stable/deps`) so the suite keeps finding the libraries here.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
