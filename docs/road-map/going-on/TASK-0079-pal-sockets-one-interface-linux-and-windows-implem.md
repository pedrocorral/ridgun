---
id: TASK-0079
title: PAL sockets: one interface, Linux and Windows implementations
status: going-on
created: 2026-11-12
completed:
requirements: [FR-VM-003, FR-COMP-007, ADR-0008]
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0008-platform-abstraction-layer-one-interface-per-target-implementation.md, docs/requirements/functional/vm/FR-VM-003-pal-network-sockets.md, docs/etc/runtime_ext.md, docs/etc/runtime_windows.md]
scope: [src/main/ridgun/lib/compiler.rg, src/main/ridgun/lib/parser.rg, src/main/ridgun/lib/typecheck.rg, src/main/ridgun/lib/x86_64.rg, src/main/ridgun/lib/pe64.rg, tests/cases/net]
owner: agent-001
claimed: 2026-11-12T13:22:38Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0079 — PAL sockets: one interface, Linux and Windows implementations

## Goal (one sentence)
Libraries open, use and close TCP connections with `net …` builtins that work the same on Linux and on Windows (FR-VM-003), with no Linux numbers and no trap on Windows.

## Plan
- [ ] 1.0.4: a user definition shadows a builtin of the same name (ADR-0008 point 5, FR-COMP-007 AC-5); `ridgunc run` removes its program.
- [ ] 1.0.5: `net …` builtins on Linux in the runtime extension (ids from 125); suite case `tests/cases/net/tcp_loopback_echo.rg`.
- [ ] 1.0.6: Windows: a Windows build of the runtime extension that calls the layer through a table (pointer at `0x400200`, set by the layer at start); Winsock in the layer (`WS2_32.dll` imports, sockets in the handle table, `sys close` / `sys poll` / read / write on them); the 26 extension trap sites go away. Check AC3 under Wine.
- [ ] Notes for libs: `socket.rg` can move from `sys call` to `net …`.

## Progress log (append-only, newest last)
- 2026-11-12: libs `socket.rg` read: its `sys tcp connect`, `sys accept`, `sys send`, `sys recv`… return libs' own codes (-2 timeout, -3 refused, -7 invalid). The PAL builtins are named `net …` (no clash) and return errno; libs maps them.
- 2026-11-12: shadowing implemented as a renaming pass before lowering (`shadow builtins` in compiler.rg); case `tests/cases/names/user_function_shadows_builtin_of_same_name.rg` passes on both backends; libs `test posix.rg` 0 fails.
- 2026-11-12: Linux `net …` (ids 125-135) in rtx.c, split into a common part and per-system `os_*` functions (Linux system calls; the Windows part calls the layer). Timeouts of -1 read `sys remaining ms` through the PAL entry 0x416680 (the general builtin entry returns 0 for id 73). Host names: /etc/hosts, `localhost`, then a UDP A query to the resolv.conf nameserver.
- 2026-11-12: Solstice report `sysos-literal-rewritten`: `sys os` now lowers to the marker `NLoadAdt0 -2 0`; Windows and macOS specialize only the marker, the Linux backends encode it as `Linux`.
## Files changed (keep current)
- 1.0.5: rtx.c (`x86 rt ext`, docs/etc/runtime_ext.md), parser.rg / typecheck.rg / compiler.rg (`net …`), pe64.rg (trap sites; `sys os` marker), macho64.rg, x86_64.rg, llvm.rg, arm64.rg; FR-VM-003; docs/lang/pal-and-system-libraries.md; `tests/cases/net/*`, `tests/cases/adts/sys_os_and_os_constructors_are_different_values.rg`; unit tests (sites, `sys os` specialization).
- 1.0.4: `src/main/ridgun/lib/compiler.rg` (`shadow builtins`), `src/main/ridgun/ridgunc/main.rg` (`run` removes its program), versions; FR-COMP-007 (names, AC-5), FR-COMP-015; `tests/cases/names/user_function_shadows_builtin_of_same_name.rg`.
## Verification performed (command → result, newest last)
- 1.0.4 (`fullG.sh`): bootstrap s3/s4 differ only in the 4 stamp bytes; suite 298 of 298 own cases (the 4 `net/` cases of 1.0.5 were in the tree and do not build with 1.0.4); unit tests 0 fails; libs 35/35.
- 1.0.5 (`fullK.sh`): bootstrap s3/s4 differ only in the stamp; suite 302/304, the 2 failures were the new `sys os` case in strict mode (`sys_os`), fixed and rerun with s3: `adts net names` 38/38; unit tests 0 fails; libs 35/35. Wine: the `sys os` case as `.exe` prints `Linux -> linux`, `sys os -> windows`.
- 1.0.6 draft (scratch `var/w`): both `net` cases built with `--target x86_64-windows` print the Linux output under Wine.
## Exact next actions
1. Windows: Winsock in rtw.c, the RG_WIN build of rtx.c (`win rt ext`), WS2_32.dll imports; AC3 under Wine (1.0.6).
## Decisions / open questions
- `trim_str` and `list_str_len` are parser-only builtins (no native code): the compiler's own definitions already run, and keep running after the renaming pass.
- calipso tests and the blogbox demo define `stop`; until 1.0.4 the agent builtin `stop` hid them. From 1.0.4 their own function runs.
## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
