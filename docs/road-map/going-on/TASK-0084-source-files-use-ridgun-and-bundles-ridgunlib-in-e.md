---
id: TASK-0084
title: Source files use .ridgun and bundles .ridgunlib in every repository; .rgc and the bytecode VM removed
status: going-on
created: 2026-11-12
completed:
requirements: [FR-COMP-006, FR-TOOL-002]
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0010-source-files-use-the-ridgun-extension.md, docs/lang/file-extensions.md]
scope: [src/, tests/, docs/, editors/, build.ridgun, README.md, .gitattributes]
owner: agent-001
claimed: 2026-11-12T20:38:58Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0084 — Source files use .ridgun and bundles .ridgunlib; .rgc and the bytecode VM removed

## Goal (one sentence)
Every Ridgun repository (except solstice, edtech and calipso) names its sources `.ridgun`, its bundles `.ridgunlib` and its build file `build.ridgun`, and the toolchain still reads the old names.

## Plan
- [x] ADR-0010 and the migration guide `docs/lang/file-extensions.md`.
- [x] Parser import resolution: new names first, old names second; an explicit library extension never resolves to a local source.
- [x] `ridgunc` and `stable`: read both names, write only new names; `build.ridgun` first, `build.rg` second.
- [x] Remove `.rgc`, `ridgunc compile`, `stable compile`, `vm.rg` and the VM demo.
- [x] Rename the 195 files in this repository with `git mv`; update tests, editors, README, docs and the book in 8 languages.
- [x] `.gitattributes` with `* linguist-detectable=false`; `stable new` and `stable init` write it when missing (TASK-0085 removes it later).
- [x] Version 1.0.10; bootstrap from r1; fixed point; suite; unit tests; libs; Windows .exe.
- [x] Install 1.0.10 into `bin/`.
- [ ] Rename the other repositories: omni (done, 0.2.1), unix-tools, www-ridgun, AIX, apps, ide, editors, web, libs/db. libs was renamed by its own team.

## Progress log (append-only, newest last)
- 2026-11-12: Started. ADR-0010 accepted. `.rgc` turned out to be the checked source with an `RGC1` header, not bytecode, and nothing used it: removed with the VM.
- 2026-11-12: Fix: `import "io.rglib"` resolved the local fixture `io.ridgun`, because the local candidate list stripped library extensions. Now it strips only source extensions.
- 2026-11-12: Fix: removing the compile section also removed `op :: sum ints` in `stable`; restored.

## Files changed (keep current)
- `src/main/ridgun/lib/parser.ridgun`, `src/main/ridgun/lib/compiler.ridgun`, `src/main/ridgun/ridgunc/main.ridgun`, `src/main/ridgun/stable/main.ridgun`; `src/main/ridgun/lib/vm.rg` deleted.
- `src/test/ridgun/test lib and plugins.ridgun`, `tests/run.ridgun`, `tests/toolchain/*.sh`, `tests/README.md`.
- ADR-0010, `docs/lang/file-extensions.md`, FR-COMP-006 (AC-4), FR-TOOL-002 (AC8), README, book chapter 2 (8 languages), editors (VS Code, gedit, Emacs), `.gitattributes`.
- All `*.rg` files renamed to `*.ridgun`; `build.rg` to `build.ridgun`.

## Verification performed (command → result, newest last)
- r1 → s1 → s2 → s3 → s4 from `.ridgun` sources: s3/s4 differ only in the stamp (3 bytes).
- `tests/run.ridgun` with s3 → 310 of 310. libs → 35 of 35. `ridgunc.exe` and `stable.exe` build; 13 agent and parallel `.exe` cases run in Wine.
- After the import fix: t1 (built by s3) builds t2, they differ only in the stamp (4 bytes); suite 310 of 310; unit tests basics and core language green.
- The 8 unit tests in `src/test/ridgun/` with t1 and stable_t → 0 fails each.

## Exact next actions
1. Rename the other repositories and patch their read-side code to accept both names.

## Decisions / open questions
- solstice, edtech and calipso keep `.rg`; the toolchain keeps reading the old names for them.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [x] docs INDEX updated  - [ ] coverage matrix regenerated
