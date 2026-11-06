---
id: TASK-0054
title: Implement macOS Mach-O 64 and Windows PE32+ native codegen and cross-platform binary emission (FR-COMP-015)
status: completed
created: 2026-11-06
completed: 2026-11-06
requirements: [FR-COMP-015]
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-015-cross-platform-macho64-and-pe64-native-codegen.md
  - src/main/ridgun/lib/macho64.rg
  - src/main/ridgun/lib/pe64.rg
  - src/main/ridgun/lib/elf64.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/arm64.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
  - src/test/ridgun/test cross platform targets.rg
scope:
  - src/main/ridgun/
  - src/test/ridgun/
  - build.rg
  - docs/requirements/functional/compiler/
owner: agent-002
claimed: 2026-11-06T10:50:28Z
claimed_by: agent gemini@solarfall
---
# TASK-0054 — Implement macOS Mach-O 64 and Windows PE32+ native codegen and cross-platform binary emission (`FR-COMP-015`)

## Goal (one sentence)
Implement 100% pure-Ridgun macOS `Mach-O 64` (`x86_64-macos`, `arm64-macos`) and Windows `PE32+` (`x86_64-windows`, `arm64-windows`) binary emitters, self-contained fallback codegen, and `~/.omni/lib` module resolution in `ridgunc` and `stable`, and emit cross-platform binaries and `.tar.gz` release archives for all 6 platforms.

## Plan
- [x] Add `src/main/ridgun/lib/macho64.rg` (`MH_MAGIC_64`, `LC_SEGMENT_64`, `LC_NOTE` page-0 dispatch table, `LC_MAIN`, `LC_LOAD_DYLINKER`, `LC_LOAD_DYLIB`, `LC_CODE_SIGNATURE` ad-hoc SHA-256 `CS_CodeDirectory`).
- [x] Add `src/main/ridgun/lib/pe64.rg` (`MZ` + `PE\0\0`, COFF header, `0x020B` PE32+ Optional Header, `.text`/`.idata`, `KERNEL32.dll` Import Directory / IAT).
- [x] Update `parser.rg`, `llvm.rg`, and `compiler.rg` for target-aware `sys os` / `sys arch` lowering (`MacOS`, `Windows`, `Linux` x `X86_64`, `Arm64`), self-contained direct native fallback when `llc`/`ld` are unavailable, and `~/.omni/lib` + `~/.local/lib/ridgun` library discovery.
- [x] Update `ridgunc/main.rg`, `stable/main.rg`, and `build.rg` (`v0.9.33`) to support `--target x86_64-macos|arm64-macos|x86_64-windows|arm64-windows` and `stable built --target <target>` / `stable built all-targets`.
- [x] Add `src/test/ridgun/test cross platform targets.rg` and generate multi-OS `ridgunc`, `stable`, and `omni` binaries and `.tar.gz` archives under `target/dist/`.

## Progress log (append-only, newest last)
- 2026-11-06: Approved `FR-COMP-015` and created `TASK-0054`.
- 2026-11-06: Implemented `macho64.rg` and `pe64.rg`, updated `parser.rg`, `llvm.rg`, `compiler.rg`, `ridgunc/main.rg`, `stable/main.rg`, and `build.rg` (`v0.9.33`), verified `stable check` (16 modules, 0 errors) and `test cross platform targets.rg` (all assertions pass), updated `bin/ridgunc` and `bin/stable` (`v0.9.33`), and built all 6 platform distributions in `target/dist/ridgun-0.9.33/`.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-015-cross-platform-macho64-and-pe64-native-codegen.md`
- `docs/requirements/functional/compiler/INDEX.md`
- `src/main/ridgun/lib/macho64.rg`
- `src/main/ridgun/lib/pe64.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/llvm.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `build.rg`
- `src/test/ridgun/test cross platform targets.rg`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `aix docs validate` → 0 errors
- `./bin/stable check` → Checked 16 module(s) — 0 errors
- `./bin/ridgunc run --strict "src/test/ridgun/test cross platform targets.rg"` → All 30 assertions passed
- `file target/dist/*/*` → Verified ELF64 (`x86_64`, `aarch64`), Mach-O 64 (`x86_64`, `arm64`), and PE32+ (`x86-64`, `ARM64`) executables and 6 `.tar.gz` release archives

## Exact next actions
1. Task complete.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
