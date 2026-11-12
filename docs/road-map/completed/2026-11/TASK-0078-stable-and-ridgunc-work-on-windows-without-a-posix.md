---
id: TASK-0078
title: stable and ridgunc work on Windows without a POSIX shell
status: completed
created: 2026-11-12
completed: 2026-11-12
requirements: [FR-VM-002, FR-TOOL-002, FR-COMP-015, FR-COMP-022]
tests: [TS-VM-002]
security: []                # VUL-* to address
context_files: [docs/etc/runtime_ext.md, docs/etc/runtime_windows.md, src/main/ridgun/stable/main.rg, src/main/ridgun/ridgunc/main.rg]
scope: [src/main/ridgun/stable/main.rg, src/main/ridgun/ridgunc/main.rg, src/main/ridgun/lib/x86_64.rg, src/main/ridgun/lib/pe64.rg, src/main/ridgun/lib/compiler.rg, src/main/ridgun/lib/parser.rg, src/main/ridgun/lib/typecheck.rg]
owner: agent-001
claimed: 2026-11-12T11:33:59Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0078 — stable and ridgunc work on Windows without a POSIX shell

## Goal (one sentence)
`stable.exe new/build/run/test/check/clean/deps/install` and `ridgunc.exe build` work on Windows (checked under Wine) without `sh.exe`, as they do on Linux.

## Plan
- [x] Runtime extension: `remove file`, `remove dir`, `rename path` (ids 122-124), so files and folders need no `rm` / `mv` (Solstice addendum: libs `posix.rg` uses Linux numbers).
- [x] ridgunc: `build --quiet`; on Windows the default target is Windows and `--version` names it (`sys os`).
- [x] stable: folders, removal, copies and tool launches through system calls and `sys exec` argument lists; only user-defined task commands keep the shell.
- [x] Windows layer sites for the new runtime calls; Wine run of `stable.exe new/build/run/test`.
- [x] Docs (FR-VM-002, FR-TOOL-002, FR-COMP-015, runtime_ext.md), suite case, bootstrap, tests, libs.

## Progress log (append-only, newest last)
- 2026-11-12: started after 1.0.2; Solstice report windows-macos-runtime and its addendum read again.
- 2026-11-12: rtx.c ids 122-124 (unlinkat 263, unlinkat with AT_REMOVEDIR, renameat 264); 26 new Windows layer sites (101 in all); parser, typecheck and compiler know the three builtins; suite case added.
- 2026-11-12: ridgunc 1.0.3: `--quiet`, host default target (`sys os`), `--version` names the host, `run` builds an `.exe` on Windows.
- 2026-11-12: stable 1.0.3: no shell except user task commands; source stamp in Ridgun (SHA-256 of sources and of the compiler binary); copies, removals and folders through system calls; ridgunc launched with `sys exec` and `--quiet`.
- 2026-11-12: Wine: stable.exe new/check/build/run/test/compile/clean and ridgunc.exe build work without sh.exe.
- 2026-11-12: full run: bootstrap, suite 296/296, unit tests green, libs 34/35: libs `posix.rg` defines `sys unlink` / `sys rmdir` / `sys rename` (returning `Bool`) and the builtins of the same names took precedence. Builtins renamed to `remove file`, `remove dir`, `rename path`; libs `test posix.rg` passes again.

## Files changed (keep current)
- src/main/ridgun/lib/x86_64.rg (runtime extension bytes), pe64.rg (layer sites), parser.rg, typecheck.rg, compiler.rg
- src/main/ridgun/ridgunc/main.rg, src/main/ridgun/stable/main.rg, build.rg (1.0.3)
- src/test/ridgun/test cross platform targets.rg; tests/cases/files/remove_file_dir_and_rename_path_return_errno.rg
- docs: FR-VM-002, FR-TOOL-002, FR-COMP-015, docs/etc/runtime_ext.md, docs/etc/INDEX.md

## Verification performed (command → result, newest last)
- s3 run tests/run.rg on the new case → passes on llvm and x86_64-elf.
- stable 1.0.3 on Linux: new, check, build, run (twice, no rebuild), test, compile, clean, dev link + deps, install → all work.
- Wine 10.0: ridgunc.exe --version → x86_64-pc-windows; stable.exe new demo, check, build (target/demo.exe), run, run, test, compile, clean → all work, no sh.exe.
- After the rename: bootstrap s1→s4 (s3/s4 differ only in the 4 build-stamp bytes); suite 296/296 (llvm 155, x86_64-elf 141); 8 unit test files, 0 fails; libs 35/35 (`test tls.rg` once timed out on badssl.com, network; passes on rerun, twice, 0 fails).
- Wine with the published 1.0.3 exes: ridgunc.exe --version, stable.exe new/check/build/run/run/test/compile/clean, ridgunc.exe run hello.rg; the suite case as a .exe prints the same as on Linux (-39, -2 included).

## Exact next actions
1. 1.0.4: `ridgunc run` removes `target/.ridgunc_run_bin` with `remove file` (the 1.0.2 compiler that builds ridgunc 1.0.3 does not know the builtin).
2. Parser quirk: an op named `make dirs` / `mk dirs` used as a statement in a guard block gives "unknown or invalid top-level declaration"; `ensure folder` passes. Find the cause.
3. ADR for the PAL (platform abstraction layer, after FR-COMP-007): one interface, one implementation per target chosen at compile time; user definitions shadow builtins. Then sockets as its first family, omni.exe, macOS.

## Decisions / open questions
- A "run a program with its output to a file" primitive is not added: `sys exec` lives in the opaque base runtime and its environment handling cannot be repeated outside it. `ridgunc build --quiet` answers the small Solstice request instead.
- ridgunc's own source cannot use builtins newer than the installed compiler (bootstrap); stable can.
- A builtin takes precedence over a user function of the same name, so a new builtin can break a library that already uses the name. The PAL ADR should state that a user definition shadows a builtin.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
