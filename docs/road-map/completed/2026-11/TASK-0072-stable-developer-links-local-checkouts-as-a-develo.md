---
id: TASK-0072
title: stable developer links: local checkouts as a developer-only exception
status: completed
created: 2026-11-11
completed: 2026-11-11
requirements: [FR-TOOL-002, ADR-0005] # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: [src/main/ridgun/stable/main.rg, tests/run.rg, tests/toolchain/stable_dev_links.sh, docs/requirements] # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-11T14:12:29Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0072 — `stable` developer links

## Goal (one sentence)
A developer can build a dependency from a local checkout on their own machine, as an explicit exception that no project, repository or package can turn on (ADR-0005).

## Plan
- [x] `stable dev link <package> <folder>`, `dev unlink`, `dev links`; links in `~/.stable/dev-links`, none by default.
- [x] Checked when made and on every use: package is a name, folder absolute and without shell characters, its build.rg names the package. Invalid link = error, no silent fallback. Warning on every use.
- [x] ADR-0005, FR-TOOL-002 AC5, ADR-0003 amendment, stable instructions and skills.
- [x] Runner check tc12 (`tests/toolchain/stable_dev_links.sh`).
- [x] Build, suite, install 0.9.57, notes.

## Progress log (append-only, newest last)
- 2026-11-11: user asked to allow local packages again, only as a developer exception, nothing by default, not usable to attack.

## Files changed (keep current)
- src/main/ridgun/stable/main.rg, tests/run.rg, tests/toolchain/stable_dev_links.sh, ADR-0005, ADR-0003, decisions INDEX, FR-TOOL-002, harness and .aix stable docs, version 0.9.57

## Verification performed (command → result, newest last)
- stable_dev_links.sh with the new stable → LINK_OK REFUSE_OK UNLINK_OK; with 0.9.56 → exit 1
- bootstrap s2/s3 → fixed point (3 bytes); tests/run.rg → 272 of 272, tc12 included; `test lib and plugins.rg` → passed

## Exact next actions
1. None.

## Decisions / open questions
- build.rg and omni.lock keep names only (ADR-0003 stands).

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
