---
id: FR-COMP-015
title: Cross-Platform Native Code Generation for macOS Mach-O 64 and Windows PE32+ (.exe) with Self-Contained Toolchain Support
type: functional
domain: compiler
status: approved
priority: must
created: 2026-11-06
updated: 2026-11-12
depends_on:
  - FR-COMP-004
  - FR-COMP-006
  - FR-COMP-007
related: [ADR-0007, ADR-0008]
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
   - Without `--target`, `ridgunc build` and `ridgunc run` SHALL build for the host the compiler runs on: `ridgunc.exe` on Windows builds an `x86_64-windows` `.exe`, and `ridgunc run` on Windows names its program `.exe`. The host is read with `sys os`.
   - `ridgunc build --quiet` (also `--lib`, `--so` and `check`) SHALL print nothing on success; errors are still printed. `stable` uses it, so it never redirects the compiler's output through a shell.

2. **Pure-Ridgun `Mach-O 64` and `PE32+` Binary Emitters (`src/main/ridgun/lib/macho64.rg` and `src/main/ridgun/lib/pe64.rg`)**:
   - `macho64.rg` SHALL emit valid 64-bit Mach-O headers (`MH_EXECUTE = 2` and `MH_DYLIB = 6`), load commands (`LC_SEGMENT_64` for `__PAGEZERO`, `__TEXT` with `__text`/`__rodata`, `__DATA`, `LC_MAIN` / `LC_UNIXTHREAD`, `LC_LOAD_DYLINKER`, `LC_LOAD_DYLIB` for `/usr/lib/libSystem.B.dylib`, `LC_SYMTAB`, `LC_DYSYMTAB`), target-specific `sys os => MacOS` / `sys arch => X86_64 | Arm64` compile-time constants, BSD/Darwin runtime syscall adaptation (`0x2000000 | nr` on `x86_64` and `x16` + `svc #0x80` on `arm64`), and deterministic ad-hoc `LC_CODE_SIGNATURE` superblobs (`CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0`, `CSMAGIC_CODEDIRECTORY = 0xFADE0C02` with SHA-256 4096-byte page hashes).
   - `pe64.rg` SHALL emit valid 64-bit PE32+ images: DOS `MZ` header at `0x00` with `e_lfanew` pointing to `PE\0\0`, a 20-byte COFF header, a 240-byte PE32+ Optional Header `0x020B` with `ImageBase = 0x400000` and `Subsystem = IMAGE_SUBSYSTEM_WINDOWS_CUI = 3`, an Import Directory and Import Address Table, and target-specific `sys os => Windows` / `sys arch => X86_64 | Arm64` compile-time constants.
   - **x86_64 Windows system layer (`ADR-0007`, `docs/etc/runtime_windows.md`):** an `x86_64-windows` image SHALL contain no `syscall` instruction. Each one in the runtime and in the generated code becomes `ud2`, and a layer in the section `.rgsys` SHALL do the Linux call it stands for with `KERNEL32.dll` (plus `WaitOnAddress` / `WakeByAddress*` from `api-ms-win-core-synch-l1-2-0.dll` and `SystemFunction036` from `ADVAPI32.dll`). The layer SHALL cover at least what `ridgunc`, `stable` and `omni` use:
     - the command line (`cli args`, UTF-8) and the environment;
     - files and folders: open, read, write, seek, stat, list, create, rename, remove, the working folder;
     - processes: start a program or a shell command (`/bin/sh -c` runs `sh.exe` from `PATH` or Git for Windows, else `cmd.exe /c`), wait for its exit code, pipes;
     - memory, clocks, sleep, threads (`clone`, `futex`) and random bytes.
   - The page-0 variables of the runtime (`0x158..0x178`, `0xF00..0x1000`) SHALL stay outside the PE headers, which start at `0x400`.

3. **Self-Contained Fallback & Global `.rglib` Discovery (`~/.omni/lib` and `~/.local/lib/ridgun`)**:
   - When `/usr/bin/opt`, `/usr/bin/llc`, or `/usr/bin/ld` are unavailable on the host machine (or when cross-compiling to non-host targets), `ridgunc` SHALL automatically emit native binaries via its built-in pure-Ridgun machine-code emitters (`x86_64.rg`, `arm64.rg`, `macho64.rg`, `pe64.rg`) with zero external toolchain dependencies.
   - `load rg with libs` in `compiler.rg` SHALL search `.stable/deps/`, `target/`, `src/main/ridgun/lib/`, `~/.omni/lib/`, and `~/.local/lib/ridgun/` so standalone downloaded `ridgunc` and `stable` binaries resolve standard libraries installed by `omni setup` from any working directory.

## Rationale
To allow developers on Linux, macOS (Intel and Apple Silicon), and Windows to download `omni`, `ridgunc`, and `stable` and immediately compile and run Ridgun programs without installing Xcode, LLVM, Visual Studio, MinGW, or Rust, `ridgunc` must emit standalone `Mach-O 64` and `PE32+` binaries directly in pure Ridgun and resolve global `.rglib` libraries installed by `omni`.

## Acceptance Criteria
1. **AC-1 (macOS `Mach-O 64` Emission for `x86_64-macos` & `arm64-macos`)**: Given a Ridgun program or library, when `ridgunc build --target x86_64-macos` or `ridgunc build --target arm64-macos` (and `--so` for `.dylib`) is invoked, then `ridgunc` emits a valid 64-bit `Mach-O` binary starting with `0xCF, 0xFA, 0xED, 0xFE` (`MH_MAGIC_64`), matching `cputype` (`CPU_TYPE_X86_64` or `CPU_TYPE_ARM64`), `sys os == MacOS`, and an embedded `LC_CODE_SIGNATURE` SHA-256 code directory.
2. **AC-2 (Windows `PE32+` `.exe` / `.dll` Emission for `x86_64-windows` & `arm64-windows`)**: Given a Ridgun program or library, when `ridgunc build --target x86_64-windows` or `ridgunc build --target arm64-windows` (and `--so` for `.dll`) is invoked, then `ridgunc` emits a valid 64-bit `PE32+` binary starting with `MZ` (`0x4D, 0x5A`), `PE\0\0` at `e_lfanew`, Optional Header magic `0x020B`, an import table for `KERNEL32.dll`, and `sys os == Windows`. For `x86_64-windows` no `syscall` instruction is left (the two `0F 05` byte pairs inside `mov edi, 0x50F00` are not instructions).
3. **AC-3 (Self-Contained Direct Emission & Global `.omni/lib` Resolution)**: Given an environment without `/usr/bin/llc` or a standalone project outside the compiler repo, when `ridgunc build` or `ridgunc check` runs, then it resolves imports from `~/.omni/lib/` / `~/.local/lib/ridgun/` and emits native executables without external compiler tools.
4. **AC-4 (Cross-Platform Distribution Artifacts for `ridgunc` and `stable`)**: `ridgunc` compiles both `src/main/ridgun/ridgunc/main.rg` and `src/main/ridgun/stable/main.rg` into standalone Linux (`ELF64`), macOS (`Mach-O 64`), and Windows (`PE32+` `.exe`) binaries.
5. **AC-5 (Windows x86_64 programs run):** the program below, built with `--target x86_64-windows` and run on Windows 10 or 11 as `repro a b`, prints its arguments, the user folder from `USERPROFILE`, `file:  written`, `child` and `child exit:  0`, as the Linux build does.
   ```ridgun
   fn :: main => ()
         main =
           echo "args: " (cli_args)
           echo "home: " (sys_getenv "HOME") (sys_getenv "USERPROFILE")
           _ = sys_mkdir "repro-dir" 493
           write_file "repro-dir/f.txt" "written"
           echo "file: " (read_file "repro-dir/f.txt")
           echo "child exit: " (shell_exec "echo child")
   ```

## Known gaps (status `approved`, not `implemented`)
- **macOS:** Mach-O images still carry the Linux system call numbers; the `0x2000000` class and the Darwin ABI are not emitted yet. AC-1 checks only the headers.
- **arm64 Windows:** the image carries the Linux arm64 runtime; the system layer is x86_64 only.
- **Windows `.dll`:** the image starts the runtime from its entry point, as an `.exe` does.
- **Windows x86_64:** sockets, file mappings and signals are not in the layer yet. AC-5 passes under Wine 10.0 (Debian trixie, 64-bit console), not yet on a Windows machine. Under Wine, `ridgunc.exe` builds and runs a Windows program.
- **`ridgunc run`:** it leaves the program it built in `target/.ridgunc_run_bin` (`.exe` on Windows). It will remove it with `sys_unlink` once the compiler that builds `ridgunc` knows that builtin (1.0.4).
