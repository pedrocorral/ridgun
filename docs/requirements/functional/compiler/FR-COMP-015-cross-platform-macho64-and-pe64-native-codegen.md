---
id: FR-COMP-015
title: Cross-Platform Native Code Generation for macOS Mach-O 64 and Windows PE32+ (.exe) with Self-Contained Toolchain Support
type: functional
domain: compiler
status: implemented
priority: must
created: 2026-11-06
updated: 2026-11-06
depends_on:
  - FR-COMP-004
  - FR-COMP-006
  - FR-COMP-007
verified_by: []
---
# FR-COMP-015 — Cross-Platform Native Code Generation for macOS `Mach-O 64` and Windows `PE32+` (`.exe`) with Self-Contained Toolchain Support

## Statement
The `ridgunc` compiler and `stable` build tool SHALL support 100% pure-Ridgun native cross-compilation and standalone binary emission for **macOS (`Mach-O 64`)** and **Windows (`PE32+` / `PE64` `.exe`)** alongside Linux `ELF64`, enabling `ridgunc`, `stable`, `omni`, and user Ridgun applications/libraries to be built and distributed as zero-dependency native binaries across Linux, macOS, and Windows:

1. **Multi-OS `--target` Support in `ridgunc build` and `stable built`**:
   - `ridgunc build [--target <target>] <entry.rg> -o <out>` and `ridgunc build --so [--target <target>] <lib.rg> -o <out>` SHALL support:
     - `x86_64-linux` (default on Linux `x86_64`, `ELF64` `EM_X86_64 = 62` executable and `.so` shared library)
     - `arm64-linux` / `aarch64-linux` (`ELF64` `EM_AARCH64 = 183` executable and `.so` shared library)
     - `x86_64-macos` / `macos-x86_64` (**macOS 64-bit `Mach-O`** `MH_MAGIC_64 = 0xFEEDFACF`, `CPU_TYPE_X86_64 = 0x01000007` executable and `.dylib` dynamic library)
     - `arm64-macos` / `macos-arm64` / `aarch64-macos` (**macOS Apple Silicon 64-bit `Mach-O`** `MH_MAGIC_64 = 0xFEEDFACF`, `CPU_TYPE_ARM64 = 0x0100000C` executable and `.dylib` dynamic library, including an embedded ad-hoc `LC_CODE_SIGNATURE` SHA-256 `CS_CodeDirectory` superblob)
     - `x86_64-windows` / `windows-x86_64` / `win64` (**Windows 64-bit `PE32+`** `MZ` + `PE\0\0`, `IMAGE_FILE_MACHINE_AMD64 = 0x8664`, Optional Header `0x020B` `.exe` executable and `.dll` dynamic library)
     - `arm64-windows` / `windows-arm64` (**Windows ARM64 `PE32+`** `IMAGE_FILE_MACHINE_ARM64 = 0xAA64` `.exe` executable and `.dll` dynamic library)
   - `stable built [--target <target>]` and `stable built all-targets` SHALL build project executables for the requested target(s) without requiring external C/Rust compilers.

2. **Pure-Ridgun `Mach-O 64` and `PE32+` Binary Emitters (`src/main/ridgun/lib/macho64.rg` and `src/main/ridgun/lib/pe64.rg`)**:
   - `macho64.rg` SHALL emit valid 64-bit Mach-O headers (`MH_EXECUTE = 2` and `MH_DYLIB = 6`), load commands (`LC_SEGMENT_64` for `__PAGEZERO`, `__TEXT` with `__text`/`__rodata`, `__DATA`, `LC_MAIN` / `LC_UNIXTHREAD`, `LC_LOAD_DYLINKER`, `LC_LOAD_DYLIB` for `/usr/lib/libSystem.B.dylib`, `LC_SYMTAB`, `LC_DYSYMTAB`), target-specific `sys os => MacOS` / `sys arch => X86_64 | Arm64` compile-time constants, BSD/Darwin runtime syscall adaptation (`0x2000000 | nr` on `x86_64` and `x16` + `svc #0x80` on `arm64`), and deterministic ad-hoc `LC_CODE_SIGNATURE` superblobs (`CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0`, `CSMAGIC_CODEDIRECTORY = 0xFADE0C02` with SHA-256 4096-byte page hashes).
   - `pe64.rg` SHALL emit valid 64-bit PE32+ headers (DOS `MZ` header at `0x00`, `PE\0\0` signature at `0x80`, 20-byte COFF header, 240-byte PE32+ Optional Header `0x020B` with `ImageBase = 0x400000` and `Subsystem = IMAGE_SUBSYSTEM_WINDOWS_CUI = 3`), section headers (`.text`, `.rdata`, `.data`, `.idata`), a complete `kernel32.dll` Import Directory / Import Address Table (`GetStdHandle`, `WriteFile`, `ReadFile`, `CreateFileA`, `CloseHandle`, `VirtualAlloc`, `VirtualFree`, `CreateDirectoryA`, `GetCommandLineA`, `GetEnvironmentVariableA`, `SetEnvironmentVariableA`, `CreateProcessA`, `WaitForSingleObject`, `GetExitCodeProcess`, `CreateThread`, `GetCurrentProcessId`, `GetTickCount64`, `Sleep`, `TerminateProcess`, `ExitProcess`), and target-specific `sys os => Windows` / `sys arch => X86_64 | Arm64` compile-time constants.

3. **Self-Contained Fallback & Global `.rglib` Discovery (`~/.omni/lib` and `~/.local/lib/ridgun`)**:
   - When `/usr/bin/opt`, `/usr/bin/llc`, or `/usr/bin/ld` are unavailable on the host machine (or when cross-compiling to non-host targets), `ridgunc` SHALL automatically emit native binaries via its built-in pure-Ridgun machine-code emitters (`x86_64.rg`, `arm64.rg`, `macho64.rg`, `pe64.rg`) with zero external toolchain dependencies.
   - `load rg with libs` in `compiler.rg` SHALL search `.stable/deps/`, `target/`, `src/main/ridgun/lib/`, `~/.omni/lib/`, and `~/.local/lib/ridgun/` so standalone downloaded `ridgunc` and `stable` binaries resolve standard libraries installed by `omni setup` from any working directory.

## Rationale
To allow developers on Linux, macOS (Intel and Apple Silicon), and Windows to download `omni`, `ridgunc`, and `stable` and immediately compile and run Ridgun programs without installing Xcode, LLVM, Visual Studio, MinGW, or Rust, `ridgunc` must emit standalone `Mach-O 64` and `PE32+` binaries directly in pure Ridgun and resolve global `.rglib` libraries installed by `omni`.

## Acceptance Criteria
1. **AC-1 (macOS `Mach-O 64` Emission for `x86_64-macos` & `arm64-macos`)**: Given a Ridgun program or library, when `ridgunc build --target x86_64-macos` or `ridgunc build --target arm64-macos` (and `--so` for `.dylib`) is invoked, then `ridgunc` emits a valid 64-bit `Mach-O` binary starting with `0xCF, 0xFA, 0xED, 0xFE` (`MH_MAGIC_64`), matching `cputype` (`CPU_TYPE_X86_64` or `CPU_TYPE_ARM64`), `sys os == MacOS`, and an embedded `LC_CODE_SIGNATURE` SHA-256 code directory.
2. **AC-2 (Windows `PE32+` `.exe` / `.dll` Emission for `x86_64-windows` & `arm64-windows`)**: Given a Ridgun program or library, when `ridgunc build --target x86_64-windows` or `ridgunc build --target arm64-windows` (and `--so` for `.dll`) is invoked, then `ridgunc` emits a valid 64-bit `PE32+` binary starting with `MZ` (`0x4D, 0x5A`), `PE\0\0` at `e_lfanew`, Optional Header magic `0x020B`, `kernel32.dll` import table, and `sys os == Windows`.
3. **AC-3 (Self-Contained Direct Emission & Global `.omni/lib` Resolution)**: Given an environment without `/usr/bin/llc` or a standalone project outside the compiler repo, when `ridgunc build` or `ridgunc check` runs, then it resolves imports from `~/.omni/lib/` / `~/.local/lib/ridgun/` and emits native executables without external compiler tools.
4. **AC-4 (Cross-Platform Distribution Artifacts for `ridgunc` and `stable`)**: `ridgunc` compiles both `src/main/ridgun/ridgunc/main.rg` and `src/main/ridgun/stable/main.rg` into standalone Linux (`ELF64`), macOS (`Mach-O 64`), and Windows (`PE32+` `.exe`) binaries.
