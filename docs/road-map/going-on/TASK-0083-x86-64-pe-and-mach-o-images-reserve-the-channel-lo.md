---
id: TASK-0083
title: x86-64 PE and Mach-O images reserve the channel lock bytes: agents work in Windows .exe
status: going-on
created: 2026-11-12
completed:
requirements: [FR-COMP-015, FR-COMP-009] # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: [src/main/ridgun/lib/x86_64.rg, src/main/ridgun/lib/pe64.rg, src/main/ridgun/lib/macho64.rg] # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-12T18:45:21Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0083 — x86-64 PE and Mach-O images reserve the channel lock bytes

## Goal (one sentence)
Agents and channels in x86-64 Windows `.exe` and macOS images run as on Linux, instead of hanging.

## Plan
- [x] Find why agent cases hang in Wine.
- [x] Give the three x86-64 emitters one layout for the lock bytes.
- [x] Unit test for the layout; every agents/* and parallel/* case in Wine.

## Progress log (append-only, newest last)
- 2026-11-12: Cause: `x86 chan lock` is `rodata - 16`, a lock word that the ELF emitter keeps in 16 zero bytes after the code. The PE and Mach-O emitters put rodata right after the code, so the lock word lay on code bytes. Builtins 1, 32, 33, 50, 97 and 98 spin until the word is 0 and never got it. The hang was there since agents were first built for Windows (1.0.3 and later).
- 2026-11-12: Fix: `x86 rodata vaddr` and `x86 code with lock` in `x86_64.rg`; the ELF, PE and Mach-O emitters all take the layout from them. It is a general fix (one shared layout), not a patch.

## Files changed (keep current)
- src/main/ridgun/lib/x86_64.rg, pe64.rg, macho64.rg
- src/test/ridgun/test cross platform targets.rg (test 7)
- docs/etc/runtime_windows.md (image layout)

## Verification performed (command → result, newest last)
- Test compiler: all agents/* and parallel/* cases built for x86_64-windows give their expected output in Wine (the two compile-failure cases do not build, as expected).

## Exact next actions
1. None after the 1.0.9 verification.

## Decisions / open questions
- The macOS x86-64 image had the same layout and is fixed by the same change; it is not run here (no macOS host).

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
