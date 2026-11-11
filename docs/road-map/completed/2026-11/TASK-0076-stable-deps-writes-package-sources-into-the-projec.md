---
id: TASK-0076
title: stable deps writes package sources into the project (stable feedback 2026-11-12)
status: completed
created: 2026-11-11
completed: 2026-11-11
requirements: [FR-TOOL-002] # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: [src/main/ridgun/stable/main.rg, tests/run.rg, tests/toolchain] # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-11T20:54:59Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0076 — stable deps writes package sources into the project (stable feedback 2026-11-12), 1.0.1

## Goal (one sentence)
`stable deps` keeps every package under `.stable/deps/` and writes nothing into the project's sources.

## Plan
- [x] Cause: for a package folder without an `.rglib`, `finish sync single dependency` fell back to copying the package's `src/main/ridgun/lib/*.rg` into the project's `src/main/ridgun/lib/`. ridgunc already reads `.stable/deps/<name>/src/main/ridgun/lib/<module>.rg`, so the copy only left untracked, stale files. Removed the fallback and the `mkdir` of `src/main/ridgun/lib`.
- [x] FR-TOOL-002: the rule and AC7.
- [x] Unit test `test lib and plugins.rg` expected the version to start with `stable 0.`; now `stable 1.`.
- [x] Runner check tc14 (tests/toolchain/stable_deps_keeps_sources.sh): reproduced with stable 1.0.0 (pkg.rg and pkg_wire.rg appeared in src/), passes with the fix.

## Progress log (append-only, newest last)
- 2026-11-12: fixed, full bootstrap and suites run.

## Files changed (keep current)
- src/main/ridgun/stable/main.rg; tests/run.rg; tests/toolchain/stable_deps_keeps_sources.sh; FR-TOOL-002; versions 1.0.1

## Verification performed (command → result, newest last)
- tc14 with the installed stable before the fix → fails, package files in src/.
- bootstrap fixed point (3 bytes); suite 294/294 (tc14 ok); 8 unit test files 0 fails (test lib and plugins.rg: its two `stable 0.` version checks now expect `stable 1.`); libs 35/35 → installed as 1.0.1.

## Exact next actions
1. None.

## Decisions / open questions
- Files already copied into a project stay until someone deletes them once.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [ ] coverage matrix regenerated
