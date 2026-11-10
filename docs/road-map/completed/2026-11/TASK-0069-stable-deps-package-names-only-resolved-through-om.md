---
id: TASK-0069
title: stable deps: package names only, resolved through omni.lock
status: completed
created: 2026-11-10
completed: 2026-11-10
requirements: [FR-TOOL-002]
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0003-stable-dependencies-are-package-names-installed-by-omni.md, src/main/ridgun/stable/main.rg]
scope: [src/main/ridgun/stable/main.rg, tests/run.rg, "src/test/ridgun/test lib and plugins.rg", docs/requirements]
owner: agent-001
claimed: 2026-11-10T14:48:52Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0069 — stable deps: package names only, resolved through omni.lock

## Goal (one sentence)
`build.rg` lists package names only; `stable` takes each one from where omni installed it (`omni.lock`), never downloads, and rejects paths and URLs (ADR-0003).

## Plan
- [x] ADR-0003 and FR-TOOL-002
- [x] `stable deps` / `stable add`: names only, resolved through `omni.lock`; no git, no paths
- [x] tc6, tc7 and `test lib and plugins.rg` by name, with an `omni.lock` entry standing in for omni
- [x] 0.9.53

## Progress log (append-only, newest last)
- 2026-11-10: the user asked for `stable` to use omni and to drop every local path.
  - `stable` used to clone and pull URL dependencies with git, unsigned and unpinned.
  - Every `build.rg` in the ecosystem lists absolute paths of one machine.
- 2026-11-10: implemented and verified.
  - `stable add` writes the name to `build.rg` only once it is synchronized.
  - This repository's `build.rg` lists `libs`.

## Files changed (keep current)
- `src/main/ridgun/stable/main.rg`: dependency resolution, `stable add`, help text.
- `tests/run.rg`: tc6 and tc7.
- `src/test/ridgun/test lib and plugins.rg`: `stable add mathkit`.
- `build.rg`: dependency `libs`.
- `docs/requirements/decisions/ADR-0003-*.md`, `docs/requirements/decisions/INDEX.md`, FR-TOOL-002.
- `harness/` and `.aix/custom/`: the stable instructions and the two skills.
- Version 0.9.53 in `build.rg`, ridgunc and stable.

## Verification performed (command → result, newest last)
- ridgunc 0.9.53 built by 0.9.52, a version string change only, followed by stable 0.9.53 → OK.
- tc6 and tc7, run by hand against the new stable → `MATCH_OK NO_BUILD_RG_OK FAIL_ON_MISSING_OK`, `REFRESH_OK`.
  - tc6 rejects a path, two URLs, `../outer`, an uninstalled name, a wrong version and a local lock entry.
- `stable add` with `../pk`, `nopkg` and `pk@9.9.9` → exit 1 and `build.rg` unchanged; `pk` → added once.
- `test lib and plugins.rg` → all passed.

## Exact next actions
1. None here. omni and the ecosystem `build.rg` files are other teams' work, described in the compiler team notes.

## Decisions / open questions
- No local override file: the user asked that no local path remain.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated (git fetching removed)  - [x] docs INDEX updated  - [ ] coverage matrix regenerated
