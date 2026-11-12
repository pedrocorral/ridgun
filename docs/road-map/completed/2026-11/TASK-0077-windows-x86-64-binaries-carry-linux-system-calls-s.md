---
id: TASK-0077
title: Windows x86_64 binaries carry Linux system calls (Solstice 2026-11-12)
status: completed
created: 2026-11-12
completed: 2026-11-12
requirements: [FR-COMP-015] # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: [src/main/ridgun/lib/pe64.rg, src/test/ridgun/test cross platform targets.rg, docs/etc/runtime_windows.md] # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-12T09:09:19Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0077 — Windows x86_64 binaries carry Linux system calls (Solstice 2026-11-12), 1.0.2

## Goal (one sentence)
An `x86_64-windows` image does every system call of the runtime and the generated code through KERNEL32, so `ridgunc`, `stable`, `omni` and user programs can run on Windows.

## Plan
- [x] Map the `syscall` sites: 99 in the runtime (disassembly of a PE built by 1.0.1; two more `0F 05` pairs are inside `mov edi, 0x50F00`), 21 in 18 instruction forms of the code generator (`llvm-mc` on each snippet; every `0F 05` pair in them is a real `syscall`).
- [x] Found: the runtime keeps variables in page 0 (`0x158..0x178`, `0xF00..0x1000`); the PE headers were at `0x100..0x258`, read-only. Headers moved to `0x400`; the layer makes the page writable.
- [x] ADR-0007: replace each `syscall` by `ud2` and catch it with a vectored exception handler (`rtw.c`); `fork` + `execve` emulated as `vfork` + `CreateProcessW`.
- [x] `rtw.c` / `rtw.ld` in docs/etc/runtime_windows.md; bytes in `pe64.rg` (`win layer`).
- [x] `pe64.rg`: three sections (`.text`, `.idata`, `.rgsys`), imports from KERNEL32 (58), api-ms-win-core-synch-l1-2-0 (3), ADVAPI32 (1); runtime and snippet sites patched; stack committed (8 MiB); relocations stripped.
- [x] Unit test (`test cross platform targets.rg`): header offsets, 99 runtime sites, every snippet form.
- [x] FR-COMP-015: Windows layer requirement, AC-5, known gaps (macOS, arm64 Windows, `.dll`, sockets); status `approved`.
- [ ] Run `repro.exe` on a Windows machine (Solstice).
- [ ] macOS: Darwin system calls (separate task).

## Progress log (append-only, newest last)
- 2026-11-12: layer written and checked by reading the image; full bootstrap and suites.

## Files changed (keep current)
- src/main/ridgun/lib/pe64.rg
- src/test/ridgun/test cross platform targets.rg
- docs/etc/runtime_windows.md, docs/etc/INDEX.md
- docs/requirements/decisions/ADR-0007-windows-system-layer-traps-linux-syscalls.md, decisions INDEX
- docs/requirements/functional/compiler/FR-COMP-015-cross-platform-macho64-and-pe64-native-codegen.md
- build.rg, ridgunc/main.rg, stable/main.rg (1.0.2)

## Verification performed (command → result, newest last)
- `llvm-readobj --coff-imports repro.exe` → 62 imports from the 3 DLLs; IAT at `.rgsys`+16, matching the `I_*` indexes of rtw.c.
- `llvm-objdump -d repro.exe` → 0 `syscall`, 101 `ud2` (99 patched + 2 unreachable ones already there); the text differs from 1.0.1 only in those 99 bytes (`05` → `0B`).
- Page 0: `PE` at `0x400`; `0x158..0x178` and `0xF00..0x1000` zero; dispatch table unchanged.
- `rtw.o`: only `R_X86_64_PC32` / `PLT32`; `rtw.elf`: no undefined symbol, no `syscall`, no `xmm`; calls to KERNEL32 use the Microsoft x64 convention.
- Native harness of rtw.c's pure helpers: UTF-8 ↔ UTF-16 round trip; 20 000 random argument lists quoted and split back unchanged.
- `test cross platform targets.rg` → 0 fails.
- Wine 10.0 (rootless Podman, Debian trixie, `wine64`): `repro.exe a b` first printed `child` twice and no `child exit`. `RIDGUN_TRACE_SYSCALLS=1` showed `CreateProcessW` returning TRUE with an empty `PROCESS_INFORMATION`: the layer had resolved `/bin/sh` literally to the host's `/bin/sh`, which Wine runs without a handle. Fixed: a POSIX shell is looked up as `sh.exe`, Git's `sh.exe`, then `cmd.exe`; a start without a handle is `ENOEXEC`.
- The `cmd.exe` fallback then failed with `ENOENT`: `to_w` kept room for a surrogate pair on every unit, so `"cmd.exe"` in 8 units became `"cmd.ex"` and the `".exe"` extension `".ex"`. Fixed to check room after decoding; the harness checks exact fits.
- Wine: `repro.exe a b` → arguments, `C:\users\box`, `file:  written`, `child`, `child exit:  0` (AC-5).
- Wine: `ridgunc.exe --version`, `stable.exe --version` → 1.0.2; `ridgunc.exe build hello.rg -o hello.exe --target windows` (2 s) → `hello.exe x y` prints its arguments.
- Wine: `stable.exe new demo` fails ("Path not found." from `cmd.exe`): stable uses `mkdir -p` / `rm -f` through the shell (gap in FR-COMP-015).

## Exact next actions
1. `sys_os` / `sys_arch` from the target, so `ridgunc.exe` defaults to Windows on Windows (new task).
2. `stable` without POSIX shell commands: folders and files through system calls, `ridgunc` started with an argument list (new task).
3. Sockets in the layer, then `omni.exe` installs from ridgun.com inside the Wine box (new task).
4. Solstice runs `repro.exe` on Windows 10/11 and reports.
5. macOS: emit Darwin system calls (new task).

## Decisions / open questions
- ADR-0007. Sockets are not in the layer yet.

## Definition of done checklist
- [ ] requirements referenced are `implemented` (FR-COMP-015 stays `approved` until macOS)  - [x] tests automated & green
- [x] security entries updated (none)  - [x] docs INDEX updated  - [ ] coverage matrix regenerated
