# Windows system layer (`FR-COMP-015`, `ADR-0007`, `ADR-0008`)

The x86_64 runtime and the code generator make Linux system calls. A Windows image (`pe64.rg`, x86_64) keeps that code and adds a layer that does each call with KERNEL32. The runtime extension has a Windows build that calls the layer directly, and the PAL socket operations (FR-VM-003) are Winsock calls in the layer. The layer is C (`rtw.c`, below), built once into position-independent bytes kept in `pe64.rg` (`win layer head`, `win layer body`).

## How a call works

1. `pe64.rg` turns every `syscall` (`0F 05`) into `ud2` (`0F 0B`), the same length:
   - in the runtime, at the offsets of `win rt sites` (from `0x401000`);
   - in the program, at the offsets of `win sys sites` for each instruction form (`win encode instrs`).
2. At start the layer registers a vectored exception handler (`on_trap`).
3. A `ud2` raises `STATUS_ILLEGAL_INSTRUCTION`. The handler checks that the bytes at `Rip` are `0F 0B`, reads the Linux registers from the `CONTEXT` (`rax` = number; `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`), does the call, writes the result to `rax` (a negative errno on failure), sets `rcx` and `r11` as the kernel does, adds 2 to `Rip` and resumes the thread.

A call the layer does not know returns `-ENOSYS` (38).

### Direct calls from the runtime extension

A Windows image carries the Windows build of the runtime extension (`rtx.c` built with `RG_WIN`, `win rt ext` in `pe64.rg`) at `0x417290`. Its system calls do not trap: they call `rg_pal(nr, a1 ... a6)` in the layer, whose address the layer writes at `0x4000A0` at start. `rg_pal` runs the same Linux call as the handler, without a thread context. `clone`, `fork`, `vfork`, `execve`, `exit` and `exit_group` need that context, so the extension still makes them with `syscall` (one site). Numbers from 1000 are PAL operations:

| Number | Operation | Arguments |
|---|---|---|
| 1000 | `net connect` | IPv4 address, port, limit ms |
| 1001 | `net listen` | IPv4 address, port, backlog |
| 1002 | `net accept` | handle, limit ms |
| 1003 | `net send` | handle, data, length, limit ms |
| 1004 | `net recv` (into a buffer) | handle, buffer, length, limit ms |
| 1005 | `net shutdown` | handle, how |
| 1006 | `net option` | handle, option index (0 nodelay, 1 keepalive, 2 reuseport, 3 broadcast, 4 rcvbuf, 5 sndbuf), value |
| 1007 | `net local port` | handle |
| 1008 | peer IPv4 address | handle |
| 1009 | `net resolve` | NUL-terminated host name |

## Image layout

| Part | Address | Contents |
|---|---|---|
| Page 0 | `0x400000` | DOS header; page-0 dispatch table (`0x80..0xA0`); the address of `rg_pal` (`0xA0`, written at start); PE headers at `0x400`. The runtime's variables at `0x158..0x178` and `0xF00..0x1000` stay zero; the layer makes the page writable at start. |
| `.text` | `0x401000` | Runtime, program, rodata, then 128 KiB of zero memory. Read, write, execute. |
| `.idata` | after `.text` | Import descriptors for `KERNEL32.dll`, `api-ms-win-core-synch-l1-2-0.dll`, `ADVAPI32.dll` and `WS2_32.dll`, lookup tables, hint/name entries (each as long as its name). |
| `.rgsys` | after `.idata` | The layer. Entry point at offset 0 (`rg_head`: a jump to `rg_win_start`); the import address table at offset 16 (768 bytes, filled by the loader). Read, write, execute. |

ImageBase is `0x400000` with no relocations (`IMAGE_FILE_RELOCS_STRIPPED`). The stack is 8 MiB, reserved and committed: runtime frames reach 16 KiB, which would skip a guard page.

## Start

`rg_win_start`:
1. allocates its tables, registers the handler, makes page 0 writable and writes the address of `rg_pal` at `0x4000A0`;
2. sets the console code pages to UTF-8 (65001) and restores them when the process ends;
3. opens descriptors 0, 1 and 2 on the standard handles;
4. builds the Linux initial stack 128 KiB below its frame: `argc`, `argv` (from `GetCommandLineW`, split with the rules of `CommandLineToArgvW`, in UTF-8), `envp` (from `GetEnvironmentStringsW`, without the `=C:` entries; `Path` is renamed `PATH`), and the auxiliary vector (`AT_PAGESZ`, `AT_RANDOM`);
5. jumps to `0x401000` with every register zero.

## Calls

| Linux call | Windows |
|---|---|
| `read`, `write`, `readv`, `writev`, `lseek`, `close`, `fsync`, `ftruncate` | `ReadFile`, `WriteFile`, `SetFilePointerEx`, `CloseHandle`, `FlushFileBuffers`, `SetEndOfFile`. A closed pipe reads as end of file. Console input loses the CR of CR LF. |
| `open`, `openat` (`AT_FDCWD` or absolute) | `CreateFileW` (shared read, write, delete; `FILE_FLAG_BACKUP_SEMANTICS`, so folders open too). `O_CREAT`, `O_EXCL`, `O_TRUNC`, `O_APPEND`, `O_DIRECTORY` are kept. |
| `stat`, `lstat`, `newfstatat`, `fstat` | `GetFileAttributesExW`, `GetFileInformationByHandle`, `GetFileType`: type, size, times, volume and file index. Modes are `0755` (folder), `0644` or `0444` (read-only file). Links are followed. |
| `getdents64` | `FindFirstFileW` / `FindNextFileW` on `<folder>\*` |
| `mkdir`, `rmdir`, `unlink`, `rename` | `CreateDirectoryW`, `RemoveDirectoryW`, `DeleteFileW`, `MoveFileExW` (replace, copy across volumes) |
| `getcwd`, `chdir`, `access`, `readlink /proc/self/exe` | `GetCurrentDirectoryW` (with `/`), `SetCurrentDirectoryW`, `GetFileAttributesW`, `GetModuleFileNameW` |
| `chmod`, `chown`, `umask` | no effect, return 0 (and `022`) |
| `mmap` (anonymous), `munmap`, `mremap`, `mprotect`, `madvise` | `VirtualAlloc` (committed, top-down), `VirtualFree`, copy to a new block, `VirtualProtect`; `brk` fails |
| `clock_gettime`, `gettimeofday`, `time`, `nanosleep`, `clock_nanosleep`, `sched_yield` | `GetSystemTimePreciseAsFileTime`, `QueryPerformanceCounter`, `Sleep`, `SwitchToThread` |
| `futex` (wait, wake) | `WaitOnAddress`, `WakeByAddressSingle`, `WakeByAddressAll` |
| `clone` (thread) | `CreateThread`; the new thread sets its stack limits in the TEB and loads the parent's registers with `rax = 0` and the given stack |
| `exit`, `exit_group` | `ExitThread`; the process ends (`ExitProcess`) when no other runtime thread is left |
| `fork`, `vfork`, `execve`, `wait4`, `kill` | see below |
| `pipe`, `pipe2`, `dup`, `dup2`, `dup3` | `CreatePipe`, `DuplicateHandle` |
| `poll`, `ppoll` | pipes: `PeekNamedPipe` (data, or closed = `POLLHUP`); console: `WaitForSingleObject`; sockets: `select` with no wait; other handles are always ready |
| `getrandom`, reads of `/dev/urandom` | `SystemFunction036` (`RtlGenRandom`) |
| `getpid`, `gettid`, `getppid`, `getuid`, `getgid`, `uname` | process and thread ids, 1, 1000, 1000, `Windows` / `x86_64` |
| `setresuid`, `setresgid`, `setgroups` | 0 for the ids 1000 and -1, else `-EPERM` |
| `prctl`, `arch_prctl`, `ioctl`, signal calls | `-EINVAL`, `-EINVAL`, `-ENOTTY`, 0 |

### Paths

- `/` and `\` both separate folders.
- `/tmp` and `/tmp/...` are the user's temporary folder (`GetTempPathW`).
- `/dev/null` is `NUL`; `/dev/tty` is `CONIN$` (read) or `CONOUT$`; `/dev/stdin`, `/dev/stdout`, `/dev/stderr` and `/dev/fd/N` duplicate the descriptor.
- Paths are UTF-8 and go to the `W` functions as UTF-16.

### Processes

- `fork` saves the thread's registers (general, flags, SSE) and returns 0: the child path runs on the parent's thread.
- In the child, `dup2` to 0, 1 or 2, `chdir` and `close` change only what the new process will get.
- The child's `execve` starts the program with `CreateProcessW` and resumes the parent after the `fork` with `rax` = the Windows process id. The program is the path, the path with `.exe`, or its last name looked up with `SearchPathW` (so `/usr/bin/git` finds `git.exe` on `PATH`). The command line follows the quoting rules of `CommandLineToArgvW`; the environment is the `envp` of the call.
- `/bin/sh -c <command>` (also `/usr/bin/sh`, `/bin/bash`) runs `sh.exe` when it is on `PATH`, else the `sh.exe` of Git for Windows (`<Git>\bin\sh.exe` next to `<Git>\cmd\git.exe`), else `cmd.exe /d /s /c "<command>"`. The literal path is never used: under Wine it is the host's own `/bin/sh`.
- A program started without a process handle (Wine runs a host binary so) makes `execve` fail with `ENOEXEC`.
- When the child ends without `execve` (`exit(127)`), the parent sees a finished process with that status.
- `execve` outside a child runs the program, waits for it and ends the process with its exit code.
- `wait4` waits with `WaitForSingleObject` (`WNOHANG` supported) and returns the status `code << 8`. `kill` ends a child with `TerminateProcess` (code `128 + signal`).

### Sockets

- A socket is a non-blocking Winsock socket in the descriptor table, so `read`, `write`, `close` and `poll` work on its handle (`recv`, `send`, `closesocket`, `select`).
- Every wait is a `select` with the caller's limit; a negative limit waits without one.
- `WSAStartup` (2.2) runs on the first socket operation.
- `net listen` does not set `SO_REUSEADDR`: on Windows it would let another socket take a port in use. Windows already allows listening on a port held by a closed connection.
- Winsock errors map to Linux errno: `WSAETIMEDOUT` -110, `WSAECONNREFUSED` -111, `WSAECONNRESET` -104, `WSAEADDRINUSE` -98, `WSAEACCES` -13, `WSAENETUNREACH` -101, `WSAEHOSTUNREACH` -113, `WSAENOTSOCK` -9, `WSAENOPROTOOPT` -92, `WSAHOST_NOT_FOUND` -2.
- `net resolve` uses `getaddrinfo` (IPv4).

## Tracing

With the environment variable `RIDGUN_TRACE_SYSCALLS` set (any value), the layer writes two lines per call to standard error, in hex:

```text
[rg> <thread> <address> <number>(<arg 1>,<arg 2>,<arg 3>) = 0
[rg< <thread> <resume address> 0(0,0,0) = <result>
```

A resume address other than the call's address means the call moved the thread (the parent resumed after `fork`). A failed `execve` adds `[rg! <thread> 0 0(<found>,<shell>,<Windows error>) = <errno>`.

## Limits

- Linux socket calls through `sys call`, file mappings (`mmap` of a file), `inotify`, signals and terminal modes are not covered.
- Windows 8 or later (`WaitOnAddress`, `GetSystemTimePreciseAsFileTime`).
- Each trapped call costs a CPU exception. A debugger stops at each `ud2` as a first-chance exception.
- arm64 Windows images still carry the Linux arm64 runtime.

## Building the bytes

The layer uses the flags of the runtime extension plus `-mno-red-zone` (Windows calls run on the same stack) and the target `x86_64-linux-gnu` (an ELF object; the result is raw bytes). Windows functions are called through `__attribute__((ms_abi))` pointers read from `rg_iat`.

```bash
CF="-Os -ffreestanding -fno-builtin -fPIE -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -mgeneral-regs-only -mno-red-zone -fno-zero-initialized-in-bss -ffunction-sections -fdata-sections -fcf-protection=none --target=x86_64-linux-gnu"
clang $CF -c rtw.c -o rtw.o
ld.lld -T rtw.ld -o rtw.elf rtw.o
llvm-objcopy -O binary --only-section=.rgsys rtw.elf rtw.bin
```

Then check:
- `llvm-readobj -r rtw.o` lists only `R_X86_64_PC32` and `R_X86_64_PLT32`;
- `llvm-nm rtw.elf` lists no undefined symbol;
- `rtw.bin` has no `syscall` (`0F 05`) and no `xmm` register.

Bytes 0..15 of `rtw.bin` go to `win layer head`; bytes 16..783 are the import address table (zero, written by `win layer`); the bytes from 784 go to `win layer body`, the trailing zero bytes written as `zero bytes n`. The order of the `I_*` indexes in `rtw.c` is the order of `win kernel32 imports`, `win synch imports`, `win advapi imports` and `win ws2 imports` in `pe64.rg`, each list followed by one null entry. Built with clang 19.1.7: 22 840 bytes.

### `rtw.ld`

```
SECTIONS {
  . = 0;
  .rgsys : { *(.text.rg_head) *(.text .text.*) *(.rodata .rodata.*) *(.data .data.*) *(.bss .bss.*) *(COMMON) }
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.llvm_addrsig) }
}
```

### `rtw.c`

```c
/* Ridgun Windows system layer (FR-COMP-015, ADR-0007).
 *
 * The x86_64 runtime and the code generator speak the Linux system-call
 * ABI. In a Windows image every `syscall` (0F 05) is replaced by `ud2`
 * (0F 0B). This layer registers a vectored exception handler that catches
 * the illegal-instruction fault at those sites, reads the Linux arguments
 * from the thread context (rax = number; rdi, rsi, rdx, r10, r8, r9),
 * does the work with KERNEL32 calls, writes the result to rax and resumes
 * after the instruction, as the kernel would.
 *
 * The image starts here (rg_head): the layer builds the Linux initial
 * stack (argc, argv, envp, auxv) from the Windows command line and
 * environment and jumps to the runtime entry at 0x401000.
 *
 * Freestanding: no libc, position independent. Windows functions are
 * called through the import address table rg_iat, which the PE loader
 * fills; the order of the entries is the order of the names in pe64.rg
 * (`win imports`).
 */
typedef unsigned long long u64;
typedef long long i64;
typedef unsigned int u32;
typedef int i32;
typedef unsigned short u16;
typedef unsigned char u8;
typedef void *H;
#define W __attribute__((ms_abi))
#define HID __attribute__((visibility("hidden")))

/* ── Image head: entry jump, then the import address table ─────────── */
__asm__(".section .text.rg_head,\"ax\",@progbits\n"
        ".globl rg_head\n"
        "rg_head:\n"
        "  jmp rg_win_start\n"
        "  .p2align 4\n"
        ".globl rg_iat\n"
        "rg_iat:\n"
        "  .zero 768\n"
        ".text\n");
extern HID void *rg_iat[];

/* KERNEL32.dll, in import order (pe64.rg `win kernel32 imports`). */
enum {
  I_GetStdHandle, I_WriteFile, I_ReadFile, I_CreateFileW, I_CloseHandle,
  I_VirtualAlloc, I_VirtualFree, I_VirtualProtect, I_VirtualQuery, I_ExitProcess,
  I_ExitThread, I_AddVectoredExceptionHandler, I_GetCommandLineW, I_GetEnvironmentStringsW, I_GetLastError,
  I_SetConsoleOutputCP, I_SetConsoleCP, I_GetConsoleOutputCP, I_GetConsoleCP, I_GetFileType,
  I_GetFileInformationByHandle, I_SetFilePointerEx, I_SetEndOfFile, I_FlushFileBuffers, I_FindFirstFileW,
  I_FindNextFileW, I_FindClose, I_CreateDirectoryW, I_RemoveDirectoryW, I_DeleteFileW,
  I_MoveFileExW, I_GetCurrentDirectoryW, I_SetCurrentDirectoryW, I_GetFileAttributesW, I_GetFileAttributesExW,
  I_GetModuleFileNameW, I_GetTempPathW, I_SearchPathW, I_CreateProcessW, I_WaitForSingleObject,
  I_GetExitCodeProcess, I_TerminateProcess, I_CreateThread, I_Sleep, I_SwitchToThread,
  I_QueryPerformanceCounter, I_QueryPerformanceFrequency, I_GetSystemTimePreciseAsFileTime, I_GetCurrentProcessId, I_GetCurrentThreadId,
  I_GetCurrentProcess, I_CreatePipe, I_DuplicateHandle, I_PeekNamedPipe, I_SetHandleInformation,
  I_GetProcessHeap, I_HeapAlloc, I_HeapFree,
  N_KERNEL32
};
/* api-ms-win-core-synch-l1-2-0.dll, after KERNEL32's null entry. */
enum { I_WaitOnAddress = N_KERNEL32 + 1, I_WakeByAddressSingle, I_WakeByAddressAll, N_SYNCH_END };
/* ADVAPI32.dll, after the synch null entry. */
enum { I_SystemFunction036 = N_SYNCH_END + 1, N_ADVAPI_END };
/* WS2_32.dll, after the ADVAPI32 null entry (pe64.rg `win ws2 imports`). */
enum {
  I_WSAStartup = N_ADVAPI_END + 1, I_WSAGetLastError, I_socket, I_connect, I_bind,
  I_listen, I_accept, I_send, I_recv, I_shutdown,
  I_closesocket, I_setsockopt, I_getsockopt, I_getsockname, I_getpeername,
  I_ioctlsocket, I_select, I_getaddrinfo, I_freeaddrinfo,
  N_WS2_END
};

#define FN(i, R, ...) ((R(W *)(__VA_ARGS__))rg_iat[i])
#define GetStdHandle(a) FN(I_GetStdHandle, H, u32)(a)
#define WriteFile(a, b, c, d, e) FN(I_WriteFile, i32, H, const void *, u32, u32 *, void *)(a, b, c, d, e)
#define ReadFile(a, b, c, d, e) FN(I_ReadFile, i32, H, void *, u32, u32 *, void *)(a, b, c, d, e)
#define CreateFileW(a, b, c, d, e, f, g) FN(I_CreateFileW, H, const u16 *, u32, u32, void *, u32, u32, H)(a, b, c, d, e, f, g)
#define CloseHandle(a) FN(I_CloseHandle, i32, H)(a)
#define VirtualAlloc(a, b, c, d) FN(I_VirtualAlloc, void *, void *, u64, u32, u32)(a, b, c, d)
#define VirtualFree(a, b, c) FN(I_VirtualFree, i32, void *, u64, u32)(a, b, c)
#define VirtualProtect(a, b, c, d) FN(I_VirtualProtect, i32, void *, u64, u32, u32 *)(a, b, c, d)
#define VirtualQuery(a, b, c) FN(I_VirtualQuery, u64, const void *, void *, u64)(a, b, c)
#define ExitProcess(a) FN(I_ExitProcess, void, u32)(a)
#define ExitThread(a) FN(I_ExitThread, void, u32)(a)
#define AddVectoredExceptionHandler(a, b) FN(I_AddVectoredExceptionHandler, void *, u32, void *)(a, b)
#define GetCommandLineW() FN(I_GetCommandLineW, u16 *, void)()
#define GetEnvironmentStringsW() FN(I_GetEnvironmentStringsW, u16 *, void)()
#define GetLastError() FN(I_GetLastError, u32, void)()
#define SetConsoleOutputCP(a) FN(I_SetConsoleOutputCP, i32, u32)(a)
#define SetConsoleCP(a) FN(I_SetConsoleCP, i32, u32)(a)
#define GetConsoleOutputCP() FN(I_GetConsoleOutputCP, u32, void)()
#define GetConsoleCP() FN(I_GetConsoleCP, u32, void)()
#define GetFileType(a) FN(I_GetFileType, u32, H)(a)
#define GetFileInformationByHandle(a, b) FN(I_GetFileInformationByHandle, i32, H, void *)(a, b)
#define SetFilePointerEx(a, b, c, d) FN(I_SetFilePointerEx, i32, H, i64, i64 *, u32)(a, b, c, d)
#define SetEndOfFile(a) FN(I_SetEndOfFile, i32, H)(a)
#define FlushFileBuffers(a) FN(I_FlushFileBuffers, i32, H)(a)
#define FindFirstFileW(a, b) FN(I_FindFirstFileW, H, const u16 *, void *)(a, b)
#define FindNextFileW(a, b) FN(I_FindNextFileW, i32, H, void *)(a, b)
#define FindClose(a) FN(I_FindClose, i32, H)(a)
#define CreateDirectoryW(a, b) FN(I_CreateDirectoryW, i32, const u16 *, void *)(a, b)
#define RemoveDirectoryW(a) FN(I_RemoveDirectoryW, i32, const u16 *)(a)
#define DeleteFileW(a) FN(I_DeleteFileW, i32, const u16 *)(a)
#define MoveFileExW(a, b, c) FN(I_MoveFileExW, i32, const u16 *, const u16 *, u32)(a, b, c)
#define GetCurrentDirectoryW(a, b) FN(I_GetCurrentDirectoryW, u32, u32, u16 *)(a, b)
#define SetCurrentDirectoryW(a) FN(I_SetCurrentDirectoryW, i32, const u16 *)(a)
#define GetFileAttributesW(a) FN(I_GetFileAttributesW, u32, const u16 *)(a)
#define GetFileAttributesExW(a, b, c) FN(I_GetFileAttributesExW, i32, const u16 *, u32, void *)(a, b, c)
#define GetModuleFileNameW(a, b, c) FN(I_GetModuleFileNameW, u32, H, u16 *, u32)(a, b, c)
#define GetTempPathW(a, b) FN(I_GetTempPathW, u32, u32, u16 *)(a, b)
#define SearchPathW(a, b, c, d, e, f) FN(I_SearchPathW, u32, const u16 *, const u16 *, const u16 *, u32, u16 *, u16 **)(a, b, c, d, e, f)
#define CreateProcessW(a, b, c, d, e, f, g, h, i, j) FN(I_CreateProcessW, i32, const u16 *, u16 *, void *, void *, i32, u32, void *, const u16 *, void *, void *)(a, b, c, d, e, f, g, h, i, j)
#define WaitForSingleObject(a, b) FN(I_WaitForSingleObject, u32, H, u32)(a, b)
#define GetExitCodeProcess(a, b) FN(I_GetExitCodeProcess, i32, H, u32 *)(a, b)
#define TerminateProcess(a, b) FN(I_TerminateProcess, i32, H, u32)(a, b)
#define CreateThread(a, b, c, d, e, f) FN(I_CreateThread, H, void *, u64, void *, void *, u32, u32 *)(a, b, c, d, e, f)
#define Sleep(a) FN(I_Sleep, void, u32)(a)
#define SwitchToThread() FN(I_SwitchToThread, i32, void)()
#define QueryPerformanceCounter(a) FN(I_QueryPerformanceCounter, i32, i64 *)(a)
#define QueryPerformanceFrequency(a) FN(I_QueryPerformanceFrequency, i32, i64 *)(a)
#define GetSystemTimePreciseAsFileTime(a) FN(I_GetSystemTimePreciseAsFileTime, void, u64 *)(a)
#define GetCurrentProcessId() FN(I_GetCurrentProcessId, u32, void)()
#define GetCurrentThreadId() FN(I_GetCurrentThreadId, u32, void)()
#define GetCurrentProcess() FN(I_GetCurrentProcess, H, void)()
#define CreatePipe(a, b, c, d) FN(I_CreatePipe, i32, H *, H *, void *, u32)(a, b, c, d)
#define DuplicateHandle(a, b, c, d, e, f, g) FN(I_DuplicateHandle, i32, H, H, H, H *, u32, i32, u32)(a, b, c, d, e, f, g)
#define PeekNamedPipe(a, b, c, d, e, f) FN(I_PeekNamedPipe, i32, H, void *, u32, u32 *, u32 *, u32 *)(a, b, c, d, e, f)
#define SetHandleInformation(a, b, c) FN(I_SetHandleInformation, i32, H, u32, u32)(a, b, c)
#define GetProcessHeap() FN(I_GetProcessHeap, H, void)()
#define HeapAlloc(a, b, c) FN(I_HeapAlloc, void *, H, u32, u64)(a, b, c)
#define HeapFree(a, b, c) FN(I_HeapFree, i32, H, u32, void *)(a, b, c)
#define WaitOnAddress(a, b, c, d) FN(I_WaitOnAddress, i32, volatile void *, void *, u64, u32)(a, b, c, d)
#define WakeByAddressSingle(a) FN(I_WakeByAddressSingle, void, void *)(a)
#define WakeByAddressAll(a) FN(I_WakeByAddressAll, void, void *)(a)
#define RtlGenRandom(a, b) FN(I_SystemFunction036, u8, void *, u32)(a, b)
#define WSAStartup(a, b) FN(I_WSAStartup, i32, u16, void *)(a, b)
#define WSAGetLastError() FN(I_WSAGetLastError, i32, void)()
#define ws_socket(a, b, c) FN(I_socket, u64, i32, i32, i32)(a, b, c)
#define ws_connect(a, b, c) FN(I_connect, i32, u64, const void *, i32)(a, b, c)
#define ws_bind(a, b, c) FN(I_bind, i32, u64, const void *, i32)(a, b, c)
#define ws_listen(a, b) FN(I_listen, i32, u64, i32)(a, b)
#define ws_accept(a, b, c) FN(I_accept, u64, u64, void *, i32 *)(a, b, c)
#define ws_send(a, b, c, d) FN(I_send, i32, u64, const void *, i32, i32)(a, b, c, d)
#define ws_recv(a, b, c, d) FN(I_recv, i32, u64, void *, i32, i32)(a, b, c, d)
#define ws_shutdown(a, b) FN(I_shutdown, i32, u64, i32)(a, b)
#define ws_closesocket(a) FN(I_closesocket, i32, u64)(a)
#define ws_setsockopt(a, b, c, d, e) FN(I_setsockopt, i32, u64, i32, i32, const void *, i32)(a, b, c, d, e)
#define ws_getsockopt(a, b, c, d, e) FN(I_getsockopt, i32, u64, i32, i32, void *, i32 *)(a, b, c, d, e)
#define ws_getsockname(a, b, c) FN(I_getsockname, i32, u64, void *, i32 *)(a, b, c)
#define ws_getpeername(a, b, c) FN(I_getpeername, i32, u64, void *, i32 *)(a, b, c)
#define ws_ioctlsocket(a, b, c) FN(I_ioctlsocket, i32, u64, i32, u32 *)(a, b, c)
#define ws_select(a, b, c, d, e) FN(I_select, i32, i32, void *, void *, void *, const void *)(a, b, c, d, e)
#define ws_getaddrinfo(a, b, c, d) FN(I_getaddrinfo, i32, const char *, const char *, const void *, void **)(a, b, c, d)
#define ws_freeaddrinfo(a) FN(I_freeaddrinfo, void, void *)(a)

#define INVALID ((H)(i64)-1)
#define INFINITE 0xFFFFFFFFu

/* ── Small helpers ──────────────────────────────────────────────────── */
void *memset(void *d, int c, u64 n) {
  void *r = d;
  __asm__ volatile("cld; rep stosb" : "+D"(d), "+c"(n) : "a"(c) : "memory", "cc");
  return r;
}
void *memcpy(void *d, const void *s, u64 n) {
  void *r = d;
  __asm__ volatile("cld; rep movsb" : "+D"(d), "+S"(s), "+c"(n) : : "memory", "cc");
  return r;
}
static u64 slen(const char *s) { u64 n = 0; while (s[n]) n++; return n; }
static u64 wlen(const u16 *s) { u64 n = 0; while (s[n]) n++; return n; }
static int seq(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }
static u64 ld64(const u32 *p) { return (u64)p[0] | ((u64)p[1] << 32); }
static int spre(const char *s, const char *p) { while (*p) if (*s++ != *p++) return 0; return 1; }

static void *alloc(u64 n) { return HeapAlloc(GetProcessHeap(), 8 /* HEAP_ZERO_MEMORY */, n ? n : 1); }
static void release(void *p) { if (p) HeapFree(GetProcessHeap(), 0, p); }

static volatile i32 big_lock;
static void lock(void) { while (__atomic_exchange_n(&big_lock, 1, __ATOMIC_ACQUIRE)) SwitchToThread(); }
static void unlock(void) { __atomic_store_n(&big_lock, 0, __ATOMIC_RELEASE); }

/* UTF-8 -> UTF-16 into d (cap code units, NUL included); returns length. */
static u64 to_w(const char *s, u64 n, u16 *d, u64 cap) {
  u64 o = 0, i = 0;
  while (i < n) {
    u32 c = (u8)s[i], k = 0;
    if (c < 0x80) k = 0;
    else if ((c & 0xE0) == 0xC0) { c &= 0x1F; k = 1; }
    else if ((c & 0xF0) == 0xE0) { c &= 0x0F; k = 2; }
    else if ((c & 0xF8) == 0xF0) { c &= 0x07; k = 3; }
    else { c = 0xFFFD; }
    i++;
    while (k && i < n && ((u8)s[i] & 0xC0) == 0x80) { c = (c << 6) | ((u8)s[i] & 0x3F); i++; k--; }
    if (o + (c >= 0x10000 ? 2 : 1) >= cap) break; /* room for it and the NUL */
    if (c >= 0x10000) { c -= 0x10000; d[o++] = (u16)(0xD800 | (c >> 10)); d[o++] = (u16)(0xDC00 | (c & 0x3FF)); }
    else d[o++] = (u16)c;
  }
  d[o] = 0;
  return o;
}

/* UTF-16 -> UTF-8 into d (cap bytes, NUL included); returns length. */
static u64 to_u8(const u16 *s, u64 n, char *d, u64 cap) {
  u64 o = 0;
  for (u64 i = 0; i < n; i++) {
    u32 c = s[i];
    if (c >= 0xD800 && c < 0xDC00 && i + 1 < n && s[i + 1] >= 0xDC00 && s[i + 1] < 0xE000) {
      c = 0x10000 + ((c - 0xD800) << 10) + (s[i + 1] - 0xDC00);
      i++;
    }
    if (o + 5 >= cap) break;
    if (c < 0x80) d[o++] = (char)c;
    else if (c < 0x800) { d[o++] = (char)(0xC0 | (c >> 6)); d[o++] = (char)(0x80 | (c & 0x3F)); }
    else if (c < 0x10000) { d[o++] = (char)(0xE0 | (c >> 12)); d[o++] = (char)(0x80 | ((c >> 6) & 0x3F)); d[o++] = (char)(0x80 | (c & 0x3F)); }
    else { d[o++] = (char)(0xF0 | (c >> 18)); d[o++] = (char)(0x80 | ((c >> 12) & 0x3F)); d[o++] = (char)(0x80 | ((c >> 6) & 0x3F)); d[o++] = (char)(0x80 | (c & 0x3F)); }
  }
  d[o] = 0;
  return o;
}

/* Linux errno from the last Windows error. */
static i64 err(void) {
  switch (GetLastError()) {
  case 2: case 3: case 15: case 53: case 123: case 161: return -2;   /* ENOENT */
  case 5: case 19: case 1314: return -13;                           /* EACCES */
  case 6: return -9;                                                /* EBADF */
  case 8: case 14: return -12;                                      /* ENOMEM */
  case 17: return -18;                                              /* EXDEV */
  case 32: case 33: return -16;                                     /* EBUSY */
  case 80: case 183: return -17;                                    /* EEXIST */
  case 87: return -22;                                              /* EINVAL */
  case 109: case 232: return -32;                                   /* EPIPE */
  case 112: return -28;                                             /* ENOSPC */
  case 145: return -39;                                             /* ENOTEMPTY */
  case 193: case 216: return -8;                                    /* ENOEXEC */
  case 206: return -36;                                             /* ENAMETOOLONG */
  case 267: return -20;                                             /* ENOTDIR */
  default: return -5;                                               /* EIO */
  }
}

/* ── Paths ───────────────────────────────────────────────────────────── */
#define WPATH 4096
static u16 *tmp_dir; /* WPATH units, allocated at start */
static u64 tmp_len;

/* A Linux path as a Windows path. "/tmp" is the user's temp folder,
 * "/dev/null" is NUL; everything else is passed through ('/' is a
 * separator for the W functions). */
static void wpath(const char *p, u16 *d) {
  if (seq(p, "/dev/null")) { to_w("NUL", 3, d, WPATH); return; }
  if (spre(p, "/tmp") && (p[4] == 0 || p[4] == '/')) {
    u64 n = 0;
    while (n < tmp_len && n + 1 < WPATH) { d[n] = tmp_dir[n]; n++; }
    if (n && (d[n - 1] == '\\' || d[n - 1] == '/')) n--;
    to_w(p + 4, slen(p + 4), d + n, WPATH - n);
    return;
  }
  to_w(p, slen(p), d, WPATH);
}

static void slashes(char *s) { for (; *s; s++) if (*s == '\\') *s = '/'; }

/* ── File descriptors ───────────────────────────────────────────────── */
enum { K_FREE, K_FILE, K_DIR, K_RANDOM, K_SOCK };
#define NFD 1024
typedef struct {
  H h;
  u8 kind, append, find_open, find_pending;
  u16 *path;   /* K_DIR: the directory, for FindFirstFileW */
  H find;      /* K_DIR: the open search */
  u8 *entry;   /* K_DIR: WIN32_FIND_DATAW not yet returned */
} Fd;
static Fd *fds;        /* NFD entries, allocated at start */

static i64 fd_new(H h, u8 kind) {
  lock();
  for (i64 i = 0; i < NFD; i++)
    if (fds[i].kind == K_FREE) {
      memset(&fds[i], 0, sizeof fds[i]);
      fds[i].h = h;
      fds[i].kind = kind;
      unlock();
      return i;
    }
  unlock();
  return -24; /* EMFILE */
}
static Fd *fd_get(i64 fd) { return (fd >= 0 && fd < NFD && fds[fd].kind != K_FREE) ? &fds[fd] : 0; }
static void fd_free(Fd *f) {
  if (f->kind == K_DIR) {
    if (f->find_open) FindClose(f->find);
    release(f->path);
    release(f->entry);
  }
  if (f->kind == K_SOCK) ws_closesocket((u64)f->h);
  else if (f->h && f->h != INVALID) CloseHandle(f->h);
  f->kind = K_FREE;
}

static H dup_h(H h) {
  H r = 0;
  if (!DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), &r, 0, 0, 2 /* SAME_ACCESS */)) return 0;
  return r;
}

/* ── Child-process emulation state (fork + execve on one thread) ────── */
#define NSLOT 64
typedef struct {
  u32 tid, active;
  u64 gpr[17];   /* CONTEXT 0x78 .. 0xF8: rax .. r15, rip */
  u32 eflags, mxcsr;
  u8 flt[512];   /* CONTEXT 0x100: XMM_SAVE_AREA32 */
  H std[3];      /* the child's stdin/stdout/stderr after dup2 */
  u16 *cwd;      /* the child's chdir */
} Vfork;
static Vfork *slots;   /* NSLOT entries, allocated at start */

static Vfork *vfork_of(u32 tid) {
  for (int i = 0; i < NSLOT; i++) if (slots[i].active && slots[i].tid == tid) return &slots[i];
  return 0;
}

#define NPROC 256
typedef struct { i64 pid; H h; i32 status; i32 used; } Proc;
static Proc *procs;    /* NPROC entries, allocated at start */
static i64 zombie_pid = 0x40000000;

static i64 proc_add(i64 pid, H h, i32 status) {
  lock();
  for (int i = 0; i < NPROC; i++)
    if (!procs[i].used) { procs[i].pid = pid; procs[i].h = h; procs[i].status = status; procs[i].used = 1; unlock(); return pid; }
  unlock();
  if (h) CloseHandle(h);
  return -11; /* EAGAIN */
}

/* ── Process-wide state ─────────────────────────────────────────────── */
static u32 main_tid, cp_out, cp_in;
static i32 trace; /* RIDGUN_TRACE_SYSCALLS set: one line per call on stderr */
static i64 qpc_freq;
static volatile i64 live_threads;

static void quit(u32 code) {
  if (cp_out) SetConsoleOutputCP(cp_out);
  if (cp_in) SetConsoleCP(cp_in);
  ExitProcess(code);
}

/* ── CONTEXT access ─────────────────────────────────────────────────── */
enum { C_EFLAGS = 0x44, C_MXCSR = 0x34, C_RAX = 0x78, C_RCX = 0x80, C_RDX = 0x88, C_RSP = 0x98,
       C_RSI = 0xA8, C_RDI = 0xB0, C_R8 = 0xB8, C_R9 = 0xC0, C_R10 = 0xC8, C_R11 = 0xD0, C_RIP = 0xF8, C_FLT = 0x100 };
#define REG(c, o) (*(u64 *)((u8 *)(c) + (o)))

/* Resume the parent of a finished child: its registers at the fork site,
 * with rax = the child's pid. */
static void vfork_return(u8 *c, Vfork *v, i64 pid) {
  memcpy(c + C_RAX, v->gpr, sizeof v->gpr);
  *(u32 *)(c + C_EFLAGS) = v->eflags;
  *(u32 *)(c + C_MXCSR) = v->mxcsr;
  memcpy(c + C_FLT, v->flt, sizeof v->flt);
  for (int i = 0; i < 3; i++) if (v->std[i]) CloseHandle(v->std[i]);
  release(v->cwd);
  v->active = 0;
  REG(c, C_RAX) = (u64)pid;
}

/* ── Linux structures ───────────────────────────────────────────────── */
static void put_time(i64 *st, int idx, u64 ft) {
  i64 t = (i64)ft - 116444736000000000LL;
  st[idx] = t / 10000000;
  st[idx + 1] = (t % 10000000) * 100;
}

/* struct stat (144 bytes) from attributes, size, times and identity. */
static void fill_stat(i64 *st, u32 attrs, u64 size, u64 atime, u64 mtime, u64 ctime, u64 dev, u64 ino, u64 nlink, u32 type) {
  memset(st, 0, 144);
  u32 mode;
  if (type == 2) mode = 0020000 | 0666;                 /* character device */
  else if (type == 3) mode = 0010000 | 0600;            /* pipe */
  else if (attrs & 0x10) mode = 0040000 | 0755;         /* directory */
  else mode = 0100000 | ((attrs & 1) ? 0444 : 0644);    /* regular file */
  st[0] = (i64)dev;
  st[1] = (i64)ino;
  st[2] = (i64)(nlink ? nlink : 1);
  ((u32 *)st)[6] = mode;
  ((u32 *)st)[7] = 1000;
  ((u32 *)st)[8] = 1000;
  st[6] = (i64)size;
  st[7] = 4096;
  st[8] = (i64)((size + 511) / 512);
  put_time(st, 9, atime);
  put_time(st, 11, mtime);
  put_time(st, 13, ctime);
}

static i64 fstat_h(H h, i64 *st) {
  u32 type = GetFileType(h);
  if (type == 1) {
    u32 bi[13]; /* BY_HANDLE_FILE_INFORMATION */
    if (!GetFileInformationByHandle(h, bi)) return err();
    fill_stat(st, bi[0], ((u64)bi[8] << 32) | bi[9], ld64(&bi[3]), ld64(&bi[5]), ld64(&bi[1]), bi[7],
              ((u64)bi[11] << 32) | bi[12], bi[10], 1);
    return 0;
  }
  fill_stat(st, 0, 0, 0, 0, 0, 0, 0, 1, type ? type : 2);
  return 0;
}

static i64 stat_path(const char *p, i64 *st) {
  u16 w[WPATH];
  wpath(p, w);
  u32 d[9]; /* WIN32_FILE_ATTRIBUTE_DATA */
  if (!GetFileAttributesExW(w, 0, d)) return err();
  fill_stat(st, d[0], ((u64)d[7] << 32) | d[8], ld64(&d[3]), ld64(&d[5]), ld64(&d[1]), 0, 0, 1, 1);
  return 0;
}

/* ── Files ──────────────────────────────────────────────────────────── */
static i64 sys_open(const char *p, i64 flags) {
  i64 acc = flags & 3;
  if (seq(p, "/dev/stdin") || seq(p, "/dev/stdout") || seq(p, "/dev/stderr") || spre(p, "/dev/fd/")) {
    i64 n = p[5] == 's' ? (p[8] == 'i' ? 0 : p[8] == 'o' ? 1 : 2) : 0;
    if (p[5] == 'f') for (const char *q = p + 8; *q >= '0' && *q <= '9'; q++) n = n * 10 + (*q - '0');
    Fd *f = fd_get(n);
    if (!f) return -2;
    H h = dup_h(f->h);
    return h ? fd_new(h, K_FILE) : err();
  }
  if (seq(p, "/dev/urandom") || seq(p, "/dev/random")) return fd_new(0, K_RANDOM);
  u16 w[WPATH];
  if (seq(p, "/dev/tty")) to_w(acc == 0 ? "CONIN$" : "CONOUT$", acc == 0 ? 6 : 7, w, WPATH);
  else if (seq(p, "/proc/self/exe")) GetModuleFileNameW(0, w, WPATH);
  else wpath(p, w);
  u32 access = acc == 0 ? 0x80000000u : acc == 1 ? 0x40000000u : 0xC0000000u;
  u32 disp;
  if ((flags & 0x40) && (flags & 0x80)) disp = 1;        /* O_CREAT|O_EXCL: CREATE_NEW */
  else if ((flags & 0x40) && (flags & 0x200)) disp = 2;  /* O_CREAT|O_TRUNC: CREATE_ALWAYS */
  else if (flags & 0x40) disp = 4;                       /* O_CREAT: OPEN_ALWAYS */
  else if (flags & 0x200) disp = 5;                      /* O_TRUNC: TRUNCATE_EXISTING */
  else disp = 3;                                         /* OPEN_EXISTING */
  u32 attrs = GetFileAttributesW(w);
  int is_dir = attrs != 0xFFFFFFFFu && (attrs & 0x10);
  if ((flags & 0x10000) && !is_dir) return attrs == 0xFFFFFFFFu ? -2 : -20; /* O_DIRECTORY */
  if (is_dir) { access = 0x80000000u; disp = 3; }
  H h = CreateFileW(w, access, 7, 0, disp, 0x80 | 0x02000000 /* NORMAL | BACKUP_SEMANTICS */, 0);
  if (h == INVALID) return err();
  i64 fd = fd_new(h, is_dir ? K_DIR : K_FILE);
  if (fd < 0) { CloseHandle(h); return fd; }
  fds[fd].append = (flags & 0x400) != 0;
  if (is_dir) {
    u64 n = wlen(w);
    fds[fd].path = alloc((n + 3) * 2);
    memcpy(fds[fd].path, w, n * 2);
    fds[fd].path[n] = '\\';
    fds[fd].path[n + 1] = '*';
  }
  return fd;
}

static i64 net_send(i64 fd, const u8 *d, i64 n, i64 ms);
static i64 net_recv(i64 fd, u8 *d, i64 n, i64 ms);
static u16 sock_ready(u64 s, u16 ev);

static i64 sys_read(i64 fd, u8 *buf, u64 n) {
  Fd *f = fd_get(fd);
  if (!f) return -9;
  if (f->kind == K_SOCK) return net_recv(fd, buf, (i64)n, -1);
  if (f->kind == K_RANDOM) { if (n > 0x7FFFFFFF) n = 0x7FFFFFFF; return RtlGenRandom(buf, (u32)n) ? (i64)n : -5; }
  if (f->kind == K_DIR) return -21; /* EISDIR */
  u32 got = 0;
  if (n > 0x7FFFFFFF) n = 0x7FFFFFFF;
  if (!ReadFile(f->h, buf, (u32)n, &got, 0)) {
    u32 e = GetLastError();
    if (e == 109 || e == 38) return 0; /* broken pipe, end of file */
    return err();
  }
  if (GetFileType(f->h) == 2) { /* console: drop the CR of CR LF */
    u32 o = 0;
    for (u32 i = 0; i < got; i++) if (buf[i] != '\r') buf[o++] = buf[i];
    got = o;
  }
  return got;
}

static i64 sys_write(i64 fd, const u8 *buf, u64 n) {
  Fd *f = fd_get(fd);
  if (!f) return -9;
  if (f->kind == K_SOCK) return net_send(fd, buf, (i64)n, -1);
  if (f->kind != K_FILE) return -9;
  if (f->append) SetFilePointerEx(f->h, 0, 0, 2);
  u64 done = 0;
  while (done < n) {
    u32 put = 0, k = (n - done) > 0x40000000 ? 0x40000000 : (u32)(n - done);
    if (!WriteFile(f->h, buf + done, k, &put, 0)) return done ? (i64)done : err();
    done += put;
    if (!put) break;
  }
  return (i64)done;
}

/* getdents64: one struct linux_dirent64 per entry. */
static i64 sys_getdents(i64 fd, u8 *buf, u64 cap) {
  Fd *f = fd_get(fd);
  if (!f) return -9;
  if (f->kind != K_DIR) return -20;
  if (!f->entry) f->entry = alloc(600);
  u64 o = 0;
  for (;;) {
    if (!f->find_pending) {
      if (!f->find_open) {
        f->find = FindFirstFileW(f->path, f->entry);
        if (f->find == INVALID) return o ? (i64)o : 0;
        f->find_open = 1;
      } else if (f->find_open == 2 || !FindNextFileW(f->find, f->entry)) {
        f->find_open = 2;
        return (i64)o;
      }
      f->find_pending = 1;
    }
    char name[1024];
    u64 n = to_u8((u16 *)(f->entry + 44), wlen((u16 *)(f->entry + 44)), name, sizeof name);
    u64 rec = (19 + n + 1 + 7) & ~7ull;
    if (o + rec > cap) return o ? (i64)o : -22;
    u8 *d = buf + o;
    memset(d, 0, rec);
    *(u64 *)d = 1;
    *(i64 *)(d + 8) = (i64)(o + rec);
    *(u16 *)(d + 16) = (u16)rec;
    d[18] = (*(u32 *)f->entry & 0x10) ? 4 : 8; /* DT_DIR, DT_REG */
    memcpy(d + 19, name, n + 1);
    o += rec;
    f->find_pending = 0;
  }
}

/* ── Memory ─────────────────────────────────────────────────────────── */
static u32 win_prot(i64 prot) {
  switch (prot & 7) {
  case 0: return 0x01; case 1: return 0x02; case 2: case 3: return 0x04;
  case 4: case 5: return 0x20; default: return 0x40;
  }
}

static i64 sys_mmap(u64 addr, u64 len, i64 prot, i64 flags, i64 fd) {
  if (!(flags & 0x20) && fd != -1) return -19; /* file mappings: ENODEV */
  void *p = 0;
  if (flags & 0x10) { /* MAP_FIXED */
    p = VirtualAlloc((void *)addr, len, 0x1000, win_prot(prot));
    if (!p) p = VirtualAlloc((void *)addr, len, 0x3000, win_prot(prot));
  } else {
    p = VirtualAlloc(0, len, 0x3000 | 0x100000 /* COMMIT|RESERVE|TOP_DOWN */, win_prot(prot));
  }
  return p ? (i64)p : -12;
}

static i64 sys_munmap(u64 addr, u64 len) {
  u64 mbi[6]; /* MEMORY_BASIC_INFORMATION */
  if (!VirtualQuery((void *)addr, mbi, sizeof mbi)) return -22;
  if (mbi[1] == addr) {
    u64 total = 0, at = addr;
    while (VirtualQuery((void *)at, mbi, sizeof mbi) && mbi[1] == addr) { total += mbi[3]; at += mbi[3]; }
    if (len >= total) return VirtualFree((void *)addr, 0, 0x8000) ? 0 : -22;
  }
  return VirtualFree((void *)addr, len, 0x4000) ? 0 : -22;
}

static i64 sys_mremap(u64 old, u64 old_len, u64 new_len, i64 flags) {
  if (new_len <= old_len) {
    if (new_len < old_len) VirtualFree((void *)(old + ((new_len + 4095) & ~4095ull)), old_len - ((new_len + 4095) & ~4095ull), 0x4000);
    return (i64)old;
  }
  if (!(flags & 1)) return -12; /* not MREMAP_MAYMOVE */
  void *p = VirtualAlloc(0, new_len, 0x3000 | 0x100000, 0x04);
  if (!p) return -12;
  memcpy(p, (void *)old, old_len);
  sys_munmap(old, old_len);
  return (i64)p;
}

/* ── Time ───────────────────────────────────────────────────────────── */
static void now_mono(i64 *ts) {
  i64 c = 0;
  QueryPerformanceCounter(&c);
  ts[0] = c / qpc_freq;
  ts[1] = (c % qpc_freq) * 1000000000LL / qpc_freq;
}
static void now_real(i64 *ts) {
  u64 ft = 0;
  GetSystemTimePreciseAsFileTime(&ft);
  put_time(ts, 0, ft);
}
static i64 ms_of(const i64 *ts) {
  if (!ts) return -1;
  i64 ms = ts[0] * 1000 + (ts[1] + 999999) / 1000000;
  return ms < 0 ? 0 : ms;
}

/* ── Processes ──────────────────────────────────────────────────────── */
/* Append one argument with the quoting rules of CommandLineToArgvW. */
static u64 quote_arg(u16 *d, u64 o, const u16 *a) {
  int q = !*a;
  for (const u16 *p = a; *p; p++) if (*p == ' ' || *p == '\t' || *p == '"') q = 1;
  if (!q) { while (*a) d[o++] = *a++; return o; }
  d[o++] = '"';
  for (;;) {
    u64 bs = 0;
    while (*a == '\\') { a++; bs++; }
    if (!*a) { while (bs--) { d[o++] = '\\'; d[o++] = '\\'; } break; }
    if (*a == '"') { bs = bs * 2 + 1; while (bs--) d[o++] = '\\'; d[o++] = '"'; }
    else { while (bs--) d[o++] = '\\'; d[o++] = *a; }
    a++;
  }
  d[o++] = '"';
  return o;
}

static int exists(const u16 *w) {
  u32 a = GetFileAttributesW(w);
  return a != 0xFFFFFFFFu && !(a & 0x10);
}

/* The program to run: the path itself, the path with ".exe", or its
 * last name looked up in PATH. Returns 0 when nothing is found. */
static int find_program(const char *p, u16 *out) {
  u16 w[WPATH];
  wpath(p, w);
  u64 n = wlen(w);
  if (exists(w)) { memcpy(out, w, (n + 1) * 2); return 1; }
  if (n + 5 < WPATH) {
    to_w(".exe", 4, w + n, WPATH - n);
    if (exists(w)) { memcpy(out, w, (n + 5) * 2); return 1; }
    w[n] = 0;
  }
  const u16 *base = w;
  for (const u16 *q = w; *q; q++) if (*q == '/' || *q == '\\') base = q + 1;
  u16 ext[5];
  to_w(".exe", 4, ext, 5);
  return SearchPathW(0, base, ext, WPATH, out, 0) != 0;
}

/* sh.exe of Git for Windows when only Git's cmd folder is on PATH:
 * <Git>\cmd\git.exe -> <Git>\bin\sh.exe. */
static int find_git_sh(u16 *out) {
  u16 name[8], ext[5];
  to_w("git", 3, name, 8);
  to_w(".exe", 4, ext, 5);
  if (!SearchPathW(0, name, ext, WPATH, out, 0)) return 0;
  u64 n = wlen(out), cut = n;
  int seps = 0;
  while (cut > 0 && seps < 2) { cut--; if (out[cut] == '\\' || out[cut] == '/') seps++; }
  if (seps < 2 || cut + 12 >= WPATH) return 0;
  to_w("\\bin\\sh.exe", 11, out + cut, WPATH - cut);
  return exists(out);
}

static u16 *build_env(char **envp) {
  u64 total = 2;
  for (char **e = envp; e && *e; e++) total += slen(*e) + 1;
  u16 *b = alloc(total * 2 + 16);
  u64 o = 0;
  for (char **e = envp; e && *e; e++) o += to_w(*e, slen(*e), b + o, total - o) + 1;
  b[o] = 0;
  b[o + 1] = 0;
  return b;
}

/* Start the program of execve; returns the process handle and pid, or a
 * negative errno. The child's standard handles are std[0..2]. */
static void trace_line(const char *tag, u64 nr, u64 a, u64 b, u64 c, u64 r, u64 rip);
static i64 spawn(const char *path, char **argv, char **envp, H *std, const u16 *cwd, H *hproc) {
  u16 *app = alloc(WPATH * 2);
  u64 cap = 64;
  for (char **a = argv; a && *a; a++) cap += slen(*a) * 2 + 8;
  cap += 2 * WPATH;
  u16 *cmd = alloc(cap * 2), *arg = alloc(cap * 2);
  u64 o = 0;
  int shell = argv && argv[0] && argv[1] && argv[2] && !argv[3] && seq(argv[1], "-c") &&
              (seq(path, "/bin/sh") || seq(path, "/usr/bin/sh") || seq(path, "/bin/bash") || seq(path, "/usr/bin/bash"));
  /* A POSIX shell is sh.exe on PATH, then Git's sh.exe, then cmd.exe; never
   * the literal path, which under Wine is the host's own /bin/sh. */
  int found = shell ? find_program("sh", app) : find_program(path, app);
  if (shell && !found) found = find_git_sh(app);
  if (shell && !found) {
    /* No POSIX shell: run the command with cmd.exe. */
    u16 name[8];
    to_w("cmd.exe", 7, name, 8);
    found = SearchPathW(0, name, 0, WPATH, app, 0) != 0;
    o = quote_arg(cmd, 0, app);
    const char *rest = " /d /s /c \"";
    o += to_w(rest, slen(rest), cmd + o, cap - o);
    o += to_w(argv[2], slen(argv[2]), cmd + o, cap - o);
    cmd[o++] = '"';
  } else {
    for (char **a = argv; a && *a; a++) {
      if (a != argv) cmd[o++] = ' ';
      if (a == argv && found) { o = quote_arg(cmd, o, app); continue; }
      to_w(*a, slen(*a), arg, cap);
      o = quote_arg(cmd, o, arg);
    }
  }
  cmd[o] = 0;
  i64 r = -2;
  if (found) {
    u16 *env = build_env(envp);
    u8 si[104], pi[24];
    memset(si, 0, sizeof si);
    memset(pi, 0, sizeof pi);
    *(u32 *)si = 104;
    *(u32 *)(si + 60) = 0x100; /* STARTF_USESTDHANDLES */
    for (int i = 0; i < 3; i++) {
      ((H *)(si + 80))[i] = std[i];
      if (std[i]) SetHandleInformation(std[i], 1, 1);
    }
    if (CreateProcessW(app, cmd, 0, 0, 1, 0x400 /* CREATE_UNICODE_ENVIRONMENT */, env, cwd, si, pi)) {
      if (*(H *)(pi + 8)) CloseHandle(*(H *)(pi + 8));
      *hproc = *(H *)pi;
      /* No process handle: not a Windows program (Wine runs host binaries so). */
      r = *(H *)pi ? (i64) * (u32 *)(pi + 16) : -8;
    } else r = err();
    for (int i = 0; i < 3; i++) if (std[i]) SetHandleInformation(std[i], 1, 0);
    release(env);
  }
  if (trace && r < 0) /* "[rg! found shell winerror = errno" */
    trace_line("[rg! ", 0, (u64)found, (u64)shell, GetLastError(), (u64)r, 0);
  release(app);
  release(cmd);
  release(arg);
  return r;
}

static i64 sys_execve(u8 *c, const char *path, char **argv, char **envp) {
  Vfork *v = vfork_of(GetCurrentThreadId());
  H std[3];
  for (int i = 0; i < 3; i++) {
    Fd *f = fd_get(i);
    std[i] = v && v->std[i] ? v->std[i] : (f && f->kind == K_FILE ? f->h : 0);
  }
  H h = 0;
  i64 pid = spawn(path, argv, envp, std, v ? v->cwd : 0, &h);
  if (pid < 0) return pid;
  if (v) { /* the child of a fork: the parent goes on */
    vfork_return(c, v, proc_add(pid, h, 0));
    return REG(c, C_RAX);
  }
  /* execve in the process itself: run the program and exit with its code. */
  u32 code = 0;
  WaitForSingleObject(h, INFINITE);
  GetExitCodeProcess(h, &code);
  quit(code);
  return 0;
}

static i64 sys_wait4(i64 pid, i32 *status, i64 options) {
  for (;;) {
    Proc *p = 0;
    lock();
    for (int i = 0; i < NPROC; i++)
      if (procs[i].used && (pid == -1 || procs[i].pid == pid)) { p = &procs[i]; break; }
    unlock();
    if (!p) return -10; /* ECHILD */
    if (p->h) {
      u32 w = WaitForSingleObject(p->h, (options & 1) ? 0 : INFINITE);
      if (w != 0) return (options & 1) ? 0 : -4;
      u32 code = 0;
      GetExitCodeProcess(p->h, &code);
      CloseHandle(p->h);
      p->h = 0;
      p->status = (i32)((code & 0xFF) << 8);
    }
    i64 r = p->pid;
    if (status) *status = p->status;
    p->used = 0;
    return r;
  }
}

static i64 sys_kill(i64 pid, i64 sig) {
  if (pid == (i64)GetCurrentProcessId() || pid == 0) { if (sig) quit(128 + (u32)sig); return 0; }
  for (int i = 0; i < NPROC; i++)
    if (procs[i].used && procs[i].pid == pid) {
      if (sig && procs[i].h) TerminateProcess(procs[i].h, 128 + (u32)sig);
      return 0;
    }
  return -3; /* ESRCH */
}

static i64 sys_pipe(i32 *fdp) {
  H r = 0, w = 0;
  if (!CreatePipe(&r, &w, 0, 0)) return err();
  i64 a = fd_new(r, K_FILE), b = fd_new(w, K_FILE);
  if (a < 0 || b < 0) return -24;
  fdp[0] = (i32)a;
  fdp[1] = (i32)b;
  return 0;
}

static i64 sys_dup2(i64 old, i64 nw) {
  Fd *f = fd_get(old);
  if (!f || f->kind != K_FILE) return -9;
  if (nw < 0 || nw >= NFD) return -9;
  if (old == nw) return nw;
  Vfork *v = vfork_of(GetCurrentThreadId());
  H h = dup_h(f->h);
  if (!h) return err();
  if (v && nw < 3) { if (v->std[nw]) CloseHandle(v->std[nw]); v->std[nw] = h; return nw; }
  lock();
  if (fds[nw].kind != K_FREE) { unlock(); fd_free(&fds[nw]); lock(); }
  memset(&fds[nw], 0, sizeof fds[nw]);
  fds[nw].h = h;
  fds[nw].kind = K_FILE;
  unlock();
  return nw;
}

/* poll / ppoll: pipes are ready when they hold data or are closed; other
 * handles are always ready. */
static i64 do_poll(u8 *pfd, u64 n, i64 ms) {
  i64 start[2];
  now_mono(start);
  for (;;) {
    i64 ready = 0;
    for (u64 i = 0; i < n; i++) {
      u8 *e = pfd + i * 8;
      i32 fd = *(i32 *)e;
      u16 ev = *(u16 *)(e + 4), rev = 0;
      Fd *f = fd_get(fd);
      if (fd < 0) { *(u16 *)(e + 6) = 0; continue; }
      if (!f) rev = 0x20; /* POLLNVAL */
      else if (f->kind == K_SOCK) rev = sock_ready((u64)f->h, ev);
      else if (f->kind == K_FILE && GetFileType(f->h) == 3) {
        u32 avail = 0;
        if (!PeekNamedPipe(f->h, 0, 0, 0, &avail, 0)) rev = 0x10 | (ev & 1); /* POLLHUP */
        else if (avail) rev = ev & 1;
        if (ev & 4) rev |= 4;
      } else if (f->kind == K_FILE && GetFileType(f->h) == 2 && (ev & 1)) {
        if (WaitForSingleObject(f->h, 0) == 0) rev = 1;
        rev |= ev & 4;
      } else rev = ev & 5;
      *(u16 *)(e + 6) = rev;
      if (rev) ready++;
    }
    if (ready) return ready;
    i64 t[2];
    now_mono(t);
    i64 spent = (t[0] - start[0]) * 1000 + (t[1] - start[1]) / 1000000;
    if (ms >= 0 && spent >= ms) return 0;
    Sleep(1);
  }
}

/* ── TCP sockets (FR-VM-003, ADR-0008) ──────────────────────────────── */
/* A socket is a non-blocking Winsock socket in the descriptor table
 * (K_SOCK). Every wait is a select with the caller's limit in ms
 * (negative: no limit). Results are >= 0 or a negative Linux errno. */
static i32 net_ready;
typedef struct { u32 n; u64 s[1]; } FdSet;

static i64 wsa_err(i32 e) {
  switch (e) {
  case 10060: return -110; case 10061: return -111; case 10054: return -104;
  case 10053: return -103; case 10048: return -98;  case 10013: return -13;
  case 10051: return -101; case 10065: return -113; case 10038: return -9;
  case 10035: return -11;  case 10036: return -115; case 10037: return -114;
  case 10058: return -32;  case 10049: return -99;  case 10042: return -92;
  case 10056: return -106; case 10057: return -107; case 10047: return -97;
  case 10024: return -24;  case 10055: return -105; case 10050: return -100;
  case 11001: case 11002: case 11004: return -2;
  default: return -22;
  }
}
static i64 wsa_last(void) { return wsa_err(WSAGetLastError()); }

static int net_start(void) {
  if (__atomic_load_n(&net_ready, __ATOMIC_ACQUIRE)) return 1;
  u8 data[512];
  lock();
  if (!net_ready && WSAStartup(0x202, data) == 0) __atomic_store_n(&net_ready, 1, __ATOMIC_RELEASE);
  unlock();
  return net_ready;
}

/* 1 when s can be read (w = 0) or written (w = 1), 2 on an error
 * condition (a failed connect), -110 when ms ran out. */
static i64 sock_wait(u64 s, int w, i64 ms) {
  FdSet a = {1, {s}}, e = {1, {s}};
  struct { i32 sec, usec; } tv = {(i32)(ms / 1000), (i32)(ms % 1000) * 1000};
  i32 r = ws_select(0, w ? 0 : &a, w ? &a : 0, &e, ms < 0 ? 0 : &tv);
  if (r < 0) return wsa_last();
  if (r == 0) return -110;
  return a.n ? 1 : 2;
}

/* The poll events of s now (1 readable, 4 writable, 8 error). */
static u16 sock_ready(u64 s, u16 ev) {
  FdSet r = {1, {s}}, w = {1, {s}}, e = {1, {s}};
  struct { i32 sec, usec; } tv = {0, 0};
  if (ws_select(0, (ev & 1) ? &r : 0, (ev & 4) ? &w : 0, &e, &tv) <= 0) return 0;
  return (u16)((((ev & 1) && r.n) ? 1 : 0) | (((ev & 4) && w.n) ? 4 : 0) | (e.n ? 8 : 0));
}

/* What is left of a limit of lim ms started at start; -1 without limit. */
static i64 left_ms(i64 lim, const i64 *start) {
  if (lim < 0) return -1;
  i64 t[2];
  now_mono(t);
  i64 spent = (t[0] - start[0]) * 1000 + (t[1] - start[1]) / 1000000;
  return spent >= lim ? 0 : lim - spent;
}

static i64 sock_new(u64 *out) {
  if (!net_start()) return -97;
  u64 s = ws_socket(2, 1, 6);
  if (s == (u64)-1) return wsa_last();
  u32 one = 1;
  ws_ioctlsocket(s, (i32)0x8004667E, &one); /* FIONBIO */
  *out = s;
  return 0;
}
static i64 sock_fd(u64 s) {
  i64 fd = fd_new((H)s, K_SOCK);
  if (fd < 0) ws_closesocket(s);
  return fd;
}
static u64 sock_of(i64 fd) {
  Fd *f = fd_get(fd);
  return (f && f->kind == K_SOCK) ? (u64)f->h : (u64)-1;
}
static void sa_in(u8 *sa, u32 ip, i64 port) {
  memset(sa, 0, 16);
  sa[0] = 2;
  sa[2] = (u8)(port >> 8); sa[3] = (u8)port;
  sa[4] = (u8)(ip >> 24); sa[5] = (u8)(ip >> 16); sa[6] = (u8)(ip >> 8); sa[7] = (u8)ip;
}
static i64 sa_ip(const u8 *sa) { return ((i64)sa[4] << 24) | ((i64)sa[5] << 16) | ((i64)sa[6] << 8) | sa[7]; }

static i64 net_connect(u32 ip, i64 port, i64 ms) {
  u64 s;
  i64 r = sock_new(&s);
  if (r) return r;
  u8 sa[16];
  sa_in(sa, ip, port);
  if (ws_connect(s, sa, 16) != 0) {
    i32 e = WSAGetLastError();
    r = e == 10035 ? sock_wait(s, 1, ms) : wsa_err(e);
    if (r == 2) {
      i32 se = 0, len = 4;
      ws_getsockopt(s, 0xFFFF, 0x1007, &se, &len); /* SO_ERROR */
      r = se ? wsa_err(se) : -111;
    }
    if (r < 0) { ws_closesocket(s); return r; }
  }
  return sock_fd(s);
}

static i64 net_listen(u32 ip, i64 port, i64 backlog) {
  u64 s;
  i64 r = sock_new(&s);
  if (r) return r;
  u8 sa[16];
  sa_in(sa, ip, port);
  if (ws_bind(s, sa, 16) != 0 || ws_listen(s, (i32)backlog) != 0) {
    r = wsa_last();
    ws_closesocket(s);
    return r;
  }
  return sock_fd(s);
}

static i64 net_accept(i64 fd, i64 ms) {
  u64 l = sock_of(fd);
  if (l == (u64)-1) return -9;
  i64 start[2];
  now_mono(start);
  for (;;) {
    u64 s = ws_accept(l, 0, 0);
    if (s != (u64)-1) {
      u32 one = 1;
      ws_ioctlsocket(s, (i32)0x8004667E, &one);
      return sock_fd(s);
    }
    i32 e = WSAGetLastError();
    if (e != 10035) return wsa_err(e);
    i64 w = sock_wait(l, 0, left_ms(ms, start));
    if (w < 0) return w;
  }
}

static i64 net_send(i64 fd, const u8 *d, i64 n, i64 ms) {
  u64 s = sock_of(fd);
  if (s == (u64)-1) return -9;
  i64 start[2], sent = 0;
  now_mono(start);
  while (sent < n) {
    i32 k = (n - sent) > 0x40000000 ? 0x40000000 : (i32)(n - sent);
    i32 r = ws_send(s, d + sent, k, 0);
    if (r > 0) { sent += r; continue; }
    i32 e = WSAGetLastError();
    if (r == 0 || e != 10035) return sent ? sent : wsa_err(e);
    i64 w = sock_wait(s, 1, left_ms(ms, start));
    if (w < 0) return sent ? sent : w;
  }
  return sent;
}

static i64 net_recv(i64 fd, u8 *d, i64 n, i64 ms) {
  u64 s = sock_of(fd);
  if (s == (u64)-1) return -9;
  if (n > 0x40000000) n = 0x40000000;
  i64 start[2];
  now_mono(start);
  for (;;) {
    i32 r = ws_recv(s, d, (i32)n, 0);
    if (r >= 0) return r;
    i32 e = WSAGetLastError();
    if (e != 10035) return wsa_err(e);
    i64 w = sock_wait(s, 0, left_ms(ms, start));
    if (w < 0) return w;
  }
}

/* idx: 0 nodelay, 1 keepalive, 2 reuseport, 3 broadcast, 4 rcvbuf, 5 sndbuf. */
static i64 net_option(i64 fd, i64 idx, i64 value) {
  u64 s = sock_of(fd);
  if (s == (u64)-1) return -9;
  i32 level = 0xFFFF, name;
  switch (idx) {
  case 0: level = 6; name = 1; break;
  case 1: name = 8; break;
  case 3: name = 0x20; break;
  case 4: name = 0x1002; break;
  case 5: name = 0x1001; break;
  default: return -92;
  }
  i32 v = (i32)value;
  return ws_setsockopt(s, level, name, &v, 4) ? wsa_last() : 0;
}

/* The local port (peer = 0) or the peer's IPv4 address (peer = 1). */
static i64 net_name(i64 fd, int peer) {
  u64 s = sock_of(fd);
  if (s == (u64)-1) return -9;
  u8 sa[16];
  i32 len = 16;
  memset(sa, 0, 16);
  if ((peer ? ws_getpeername(s, sa, &len) : ws_getsockname(s, sa, &len)) != 0) return wsa_last();
  if (sa[0] != 2) return -22;
  return peer ? sa_ip(sa) : (((i64)sa[2] << 8) | sa[3]);
}

static i64 net_resolve(const char *name) {
  if (!net_start()) return -2;
  i32 hints[12];
  memset(hints, 0, sizeof hints);
  hints[1] = 2; /* AF_INET */
  hints[2] = 1; /* SOCK_STREAM */
  void *res = 0;
  if (ws_getaddrinfo(name, 0, hints, &res) != 0 || !res) return -2;
  u8 *sa = *(u8 **)((u8 *)res + 32); /* ai_addr */
  i64 ip = sa ? sa_ip(sa) : -2;
  ws_freeaddrinfo(res);
  return ip;
}

/* ── Threads ────────────────────────────────────────────────────────── */
/* Load the 17 registers (CONTEXT order rax .. r15, rip) and jump. */
__asm__(".text\n"
        ".globl rg_jump\n"
        "rg_jump:\n"
        "  movq 128(%rdi), %rax\n"
        "  movq 32(%rdi), %rcx\n"
        "  subq $8, %rcx\n"
        "  movq %rax, (%rcx)\n"
        "  movq 0(%rdi), %rax\n"
        "  movq 16(%rdi), %rdx\n"
        "  movq 24(%rdi), %rbx\n"
        "  movq 40(%rdi), %rbp\n"
        "  movq 48(%rdi), %rsi\n"
        "  movq 64(%rdi), %r8\n"
        "  movq 72(%rdi), %r9\n"
        "  movq 80(%rdi), %r10\n"
        "  movq 88(%rdi), %r11\n"
        "  movq 96(%rdi), %r12\n"
        "  movq 104(%rdi), %r13\n"
        "  movq 112(%rdi), %r14\n"
        "  movq 120(%rdi), %r15\n"
        "  movq %rcx, %rsp\n"
        "  movq 8(%rdi), %rcx\n"
        "  movq 56(%rdi), %rdi\n"
        "  ret\n");
extern HID __attribute__((noreturn)) void rg_jump(u64 *regs);

W static u32 thread_start(void *arg) {
  u64 regs[17];
  memcpy(regs, arg, sizeof regs);
  release(arg);
  u64 mbi[6];
  if (VirtualQuery((void *)(regs[4] - 8), mbi, sizeof mbi)) {
    u64 top = mbi[0] + mbi[3], bottom = mbi[1];
    __asm__ volatile("movq %0, %%gs:0x8\n movq %1, %%gs:0x10" ::"r"(top), "r"(bottom));
  }
  rg_jump(regs);
}

static i64 sys_clone(u8 *c, u64 flags, u64 stack) {
  u64 *regs = alloc(sizeof(u64) * 17);
  memcpy(regs, c + C_RAX, sizeof(u64) * 17);
  regs[0] = 0;                     /* rax: the child sees 0 */
  regs[4] = stack ? stack : REG(c, C_RSP);
  regs[16] = REG(c, C_RIP) + 2;    /* after the trapped instruction */
  (void)flags;
  u32 tid = 0;
  __atomic_add_fetch(&live_threads, 1, __ATOMIC_SEQ_CST);
  H h = CreateThread(0, 65536, (void *)thread_start, regs, 0, &tid);
  if (!h) { __atomic_sub_fetch(&live_threads, 1, __ATOMIC_SEQ_CST); release(regs); return err(); }
  CloseHandle(h);
  return tid;
}

/* ── The system call table ──────────────────────────────────────────── */
static i64 dispatch(u8 *c, i64 nr, i64 a, i64 b, i64 d, i64 e, i64 f, i64 g) {
  (void)g;
  u32 tid = GetCurrentThreadId();
  switch (nr) {
  case 0: return sys_read(a, (u8 *)b, (u64)d);
  case 1: return sys_write(a, (const u8 *)b, (u64)d);
  case 2: return sys_open((const char *)a, b);
  case 257: if (a != -100 && *(const char *)b != '/') return -38; return sys_open((const char *)b, d);
  case 3: {
    Vfork *v = vfork_of(tid);
    if (v) return 0; /* the child's close does not touch the parent's files */
    Fd *x = fd_get(a);
    if (!x) return -9;
    lock(); fd_free(x); unlock();
    return 0;
  }
  case 4: case 6: return stat_path((const char *)a, (i64 *)b);
  case 5: {
    Fd *x = fd_get(a);
    if (!x) return -9;
    if (x->kind == K_RANDOM) { fill_stat((i64 *)b, 0, 0, 0, 0, 0, 0, 0, 1, 2); return 0; }
    return fstat_h(x->h, (i64 *)b);
  }
  case 262: /* newfstatat */
    if (*(const char *)b == 0 && (e & 0x1000)) return dispatch(c, 5, a, d, 0, 0, 0, 0);
    if (a != -100 && *(const char *)b != '/') return -38;
    return stat_path((const char *)b, (i64 *)d);
  case 7: return do_poll((u8 *)a, (u64)b, d);
  case 271: return do_poll((u8 *)a, (u64)b, ms_of((const i64 *)d));
  case 8: {
    Fd *x = fd_get(a);
    if (!x) return -9;
    i64 pos = 0;
    if (!SetFilePointerEx(x->h, b, &pos, (u32)d)) return err();
    return pos;
  }
  case 9: return sys_mmap((u64)a, (u64)b, d, e, f);
  case 10: { u32 old; return VirtualProtect((void *)a, (u64)b, win_prot(d), &old) ? 0 : -22; }
  case 11: return sys_munmap((u64)a, (u64)b);
  case 12: return -12;
  case 25: return sys_mremap((u64)a, (u64)b, (u64)d, e);
  case 28: return 0;                               /* madvise */
  case 13: case 14: case 131: return 0;            /* signals */
  case 16: return -25;                             /* ioctl: ENOTTY */
  case 19: case 20: {                              /* readv, writev */
    i64 total = 0;
    for (i64 i = 0; i < d; i++) {
      u64 *iov = (u64 *)b + i * 2;
      i64 r = nr == 19 ? sys_read(a, (u8 *)iov[0], iov[1]) : sys_write(a, (const u8 *)iov[0], iov[1]);
      if (r < 0) return total ? total : r;
      total += r;
      if ((u64)r < iov[1]) break;
    }
    return total;
  }
  case 21: case 269: {                             /* access, faccessat */
    const char *p = (const char *)(nr == 21 ? a : b);
    u16 w[WPATH];
    wpath(p, w);
    return GetFileAttributesW(w) != 0xFFFFFFFFu ? 0 : err();
  }
  case 22: case 293: return sys_pipe((i32 *)a);
  case 24: SwitchToThread(); return 0;
  case 32: {
    Fd *x = fd_get(a);
    if (!x || x->kind != K_FILE) return -9;
    H h = dup_h(x->h);
    return h ? fd_new(h, K_FILE) : err();
  }
  case 33: case 292: return sys_dup2(a, b);
  case 35: case 230: {                             /* nanosleep, clock_nanosleep */
    const i64 *ts = (const i64 *)(nr == 35 ? a : d);
    if (nr == 230 && (b & 1)) {                    /* TIMER_ABSTIME */
      i64 t[2];
      if (a == 0) now_real(t); else now_mono(t);
      i64 ms = (ts[0] - t[0]) * 1000 + (ts[1] - t[1]) / 1000000;
      if (ms > 0) Sleep((u32)ms);
      return 0;
    }
    Sleep((u32)ms_of(ts));
    return 0;
  }
  case 39: return GetCurrentProcessId();
  case 110: return 1;                              /* getppid */
  case 186: return tid;
  case 56: if (!(a & 0x100)) return -38; return sys_clone(c, (u64)a, (u64)b);
  case 57: case 58: {                              /* fork, vfork */
    if (vfork_of(tid)) return -11;
    lock();
    Vfork *v = 0;
    for (int i = 0; i < NSLOT; i++) if (!slots[i].active) { v = &slots[i]; break; }
    if (!v) { unlock(); return -11; }
    memset(v, 0, sizeof *v);
    v->active = 1;
    v->tid = tid;
    unlock();
    memcpy(v->gpr, c + C_RAX, sizeof v->gpr);
    v->eflags = *(u32 *)(c + C_EFLAGS);
    v->mxcsr = *(u32 *)(c + C_MXCSR);
    memcpy(v->flt, c + C_FLT, sizeof v->flt);
    return 0;                                      /* the child runs first */
  }
  case 59: return sys_execve(c, (const char *)a, (char **)b, (char **)d);
  case 60: case 231: {
    Vfork *v = vfork_of(tid);
    if (v) { /* the child ends without exec: the parent sees a finished child */
      i64 pid = __atomic_add_fetch(&zombie_pid, 1, __ATOMIC_SEQ_CST);
      vfork_return(c, v, proc_add(pid, 0, (i32)((a & 0xFF) << 8)));
      return REG(c, C_RAX);
    }
    if (nr == 60 && tid != main_tid) {
      __atomic_sub_fetch(&live_threads, 1, __ATOMIC_SEQ_CST);
      ExitThread((u32)a);
    }
    if (nr == 60 && __atomic_load_n(&live_threads, __ATOMIC_SEQ_CST) > 0) ExitThread((u32)a);
    quit((u32)a & 0xFF);
    return 0;
  }
  case 61: return sys_wait4(a, (i32 *)b, d);
  case 62: return sys_kill(a, b);
  case 200: case 234: return 0;                    /* tkill, tgkill */
  case 63: {                                       /* uname */
    char *u = (char *)a;
    memset(u, 0, 390);
    memcpy(u, "Windows", 8);
    memcpy(u + 65, "localhost", 10);
    memcpy(u + 130, "10.0", 5);
    memcpy(u + 195, "#1", 3);
    memcpy(u + 260, "x86_64", 7);
    return 0;
  }
  case 72: return (b == 1 || b == 2 || b == 4) ? 0 : (b == 3 ? 2 : -22); /* fcntl */
  case 74: case 75: { Fd *x = fd_get(a); if (!x) return -9; FlushFileBuffers(x->h); return 0; }
  case 77: {                                       /* ftruncate */
    Fd *x = fd_get(a);
    if (!x) return -9;
    i64 pos = 0;
    SetFilePointerEx(x->h, 0, &pos, 1);
    if (!SetFilePointerEx(x->h, b, 0, 0) || !SetEndOfFile(x->h)) return err();
    SetFilePointerEx(x->h, pos, 0, 0);
    return 0;
  }
  case 79: {                                       /* getcwd */
    u16 w[WPATH];
    u32 n = GetCurrentDirectoryW(WPATH, w);
    if (!n || n >= WPATH) return err();
    char *s = (char *)a;
    u64 m = to_u8(w, n, s, (u64)b);
    if (m + 1 > (u64)b) return -34;
    slashes(s);
    return (i64)m + 1;
  }
  case 80: {                                       /* chdir */
    u16 w[WPATH];
    wpath((const char *)a, w);
    Vfork *v = vfork_of(tid);
    if (v) {
      u64 n = wlen(w);
      release(v->cwd);
      v->cwd = alloc((n + 1) * 2);
      memcpy(v->cwd, w, (n + 1) * 2);
      return 0;
    }
    return SetCurrentDirectoryW(w) ? 0 : err();
  }
  case 82: case 264: case 316: {                   /* rename, renameat, renameat2 */
    const char *from = (const char *)(nr == 82 ? a : b), *to = (const char *)(nr == 82 ? b : e);
    u16 w1[WPATH], w2[WPATH];
    wpath(from, w1);
    wpath(to, w2);
    return MoveFileExW(w1, w2, 1 | 2) ? 0 : err();
  }
  case 83: case 258: {                             /* mkdir, mkdirat */
    u16 w[WPATH];
    wpath((const char *)(nr == 83 ? a : b), w);
    return CreateDirectoryW(w, 0) ? 0 : err();
  }
  case 84: { u16 w[WPATH]; wpath((const char *)a, w); return RemoveDirectoryW(w) ? 0 : err(); }
  case 87: case 263: {                             /* unlink, unlinkat */
    u16 w[WPATH];
    wpath((const char *)(nr == 87 ? a : b), w);
    if (nr == 263 && (d & 0x200)) return RemoveDirectoryW(w) ? 0 : err();
    return DeleteFileW(w) ? 0 : err();
  }
  case 89: {                                       /* readlink */
    if (!seq((const char *)a, "/proc/self/exe")) return -22;
    u16 w[WPATH];
    u32 n = GetModuleFileNameW(0, w, WPATH);
    char *s = (char *)b;
    char tmp[WPATH * 3];
    u64 m = to_u8(w, n, tmp, sizeof tmp);
    slashes(tmp);
    if (m > (u64)d) m = (u64)d;
    memcpy(s, tmp, m);
    return (i64)m;
  }
  case 90: case 91: case 92: case 93: case 94: case 268: return 0; /* chmod, chown */
  case 95: return 022;                             /* umask */
  case 96: {                                       /* gettimeofday */
    i64 t[2];
    now_real(t);
    if (a) { ((i64 *)a)[0] = t[0]; ((i64 *)a)[1] = t[1] / 1000; }
    return 0;
  }
  case 201: { i64 t[2]; now_real(t); if (a) *(i64 *)a = t[0]; return t[0]; }
  case 102: case 104: case 107: case 108: return 1000;
  case 116: {                                      /* setgroups */
    for (i64 i = 0; i < a; i++) if (((u32 *)b)[i] != 1000) return -1;
    return 0;
  }
  case 117: case 119:                              /* setresuid, setresgid */
    if ((a != -1 && a != 1000) || (b != -1 && b != 1000) || (d != -1 && d != 1000)) return -1;
    return 0;
  case 157: case 158: return -22;                  /* prctl, arch_prctl */
  case 202: {                                      /* futex */
    i64 op = b & 127;
    if (op == 0 || op == 9) {
      i32 want = (i32)d;
      if (*(volatile i32 *)a != want) return -11;
      i64 ms = op == 0 ? ms_of((const i64 *)e) : -1;
      if (!WaitOnAddress((volatile void *)a, &want, 4, ms < 0 ? INFINITE : (u32)ms)) {
        if (GetLastError() == 1460) return -110;   /* ETIMEDOUT */
      }
      return 0;
    }
    if (op == 1 || op == 10) {
      if (d >= 0x7FFFFFFF) WakeByAddressAll((void *)a);
      else for (i64 i = 0; i < d; i++) WakeByAddressSingle((void *)a);
      return 0;
    }
    return -38;
  }
  case 217: return sys_getdents(a, (u8 *)b, (u64)d);
  case 228: {                                      /* clock_gettime */
    if (a == 0 || a == 5 || a == 11) now_real((i64 *)b);
    else now_mono((i64 *)b);
    return 0;
  }
  case 229: ((i64 *)b)[0] = 0; ((i64 *)b)[1] = 100; return 0; /* clock_getres */
  case 318: {                                      /* getrandom */
    u64 n = (u64)b > 0x7FFFFFFF ? 0x7FFFFFFF : (u64)b;
    return RtlGenRandom((void *)a, (u32)n) ? (i64)n : -5;
  }
  default: return -38;                             /* ENOSYS */
  }
}

/* Trace line: "[rg tid] nr(a, b, c) = r" in hex. */
static u64 hex(char *d, u64 o, u64 v) {
  d[o++] = '0'; d[o++] = 'x';
  int started = 0;
  for (int i = 60; i >= 0; i -= 4) {
    u32 n = (v >> i) & 15;
    if (n || started || i == 0) { d[o++] = "0123456789abcdef"[n]; started = 1; }
  }
  return o;
}
static void trace_line(const char *tag, u64 nr, u64 a, u64 b, u64 c, u64 r, u64 rip) {
  char d[200];
  u64 o = 0;
  for (const char *t = tag; *t; t++) d[o++] = *t;
  o = hex(d, o, GetCurrentThreadId()); d[o++] = ' ';
  o = hex(d, o, rip); d[o++] = ' ';
  o = hex(d, o, nr); d[o++] = '(';
  o = hex(d, o, a); d[o++] = ','; o = hex(d, o, b); d[o++] = ','; o = hex(d, o, c);
  d[o++] = ')'; d[o++] = ' '; d[o++] = '='; d[o++] = ' ';
  o = hex(d, o, r); d[o++] = '\n';
  u32 put;
  if (fds && fds[2].h) WriteFile(fds[2].h, d, (u32)o, &put, 0);
}

/* The vectored exception handler: a `ud2` placed where the Linux code had
 * `syscall`. */
/* Direct entry for the Windows build of the runtime extension
 * (ADR-0008); its address is at 0x4000A0. Below 1000: a Linux system call
 * that needs no thread context. From 1000: a PAL operation. */
HID __attribute__((used)) i64 rg_pal(i64 nr, i64 a, i64 b, i64 d, i64 e, i64 f, i64 g) {
  if (trace) trace_line("[rg> ", nr, a, b, d, 0, 0);
  i64 r;
  switch (nr) {
  case 1000: r = net_connect((u32)a, b, d); break;
  case 1001: r = net_listen((u32)a, b, d); break;
  case 1002: r = net_accept(a, b); break;
  case 1003: r = net_send(a, (const u8 *)b, d, e); break;
  case 1004: r = net_recv(a, (u8 *)b, d, e); break;
  case 1005: { u64 s = sock_of(a); r = s == (u64)-1 ? -9 : (ws_shutdown(s, (i32)b) ? wsa_last() : 0); break; }
  case 1006: r = net_option(a, b, d); break;
  case 1007: r = net_name(a, 0); break;
  case 1008: r = net_name(a, 1); break;
  case 1009: r = net_resolve((const char *)a); break;
  case 56: case 57: case 58: case 59: r = -38; break; /* need the thread context: they trap */
  default: r = dispatch(0, nr, a, b, d, e, f, g);
  }
  if (trace) trace_line("[rg< ", 0, 0, 0, 0, (u64)r, 0);
  return r;
}

W static i32 on_trap(void **ptrs) {
  u32 *rec = ptrs[0];
  u8 *c = ptrs[1];
  if (rec[0] != 0xC000001Du) return 0;       /* EXCEPTION_CONTINUE_SEARCH */
  u8 *rip = (u8 *)REG(c, C_RIP);
  if (rip[0] != 0x0F || rip[1] != 0x0B) return 0;
  u64 at = (u64)rip;
  if (trace) trace_line("[rg> ", REG(c, C_RAX), REG(c, C_RDI), REG(c, C_RSI), REG(c, C_RDX), 0, at);
  i64 r = dispatch(c, (i64)REG(c, C_RAX), (i64)REG(c, C_RDI), (i64)REG(c, C_RSI), (i64)REG(c, C_RDX),
                   (i64)REG(c, C_R10), (i64)REG(c, C_R8), (i64)REG(c, C_R9));
  if (REG(c, C_RIP) == at) {                 /* not resumed elsewhere (fork) */
    REG(c, C_RAX) = (u64)r;
  }
  if (trace) trace_line("[rg< ", 0, 0, 0, 0, REG(c, C_RAX), REG(c, C_RIP));
  REG(c, C_RIP) += 2;
  REG(c, C_RCX) = REG(c, C_RIP);
  REG(c, C_R11) = *(u32 *)(c + C_EFLAGS);
  return -1;                                 /* EXCEPTION_CONTINUE_EXECUTION */
}

/* ── Start: Linux initial stack from the Windows command line ───────── */
/* Split the command line with the rules of CommandLineToArgvW. */
static u64 split_args(const u16 *s, u16 *out, u16 **argv) {
  u64 n = 0, o = 0;
  int first = 1;
  while (*s) {
    while (*s == ' ' || *s == '\t') s++;
    if (!*s) break;
    argv[n++] = out + o;
    int q = 0;
    if (first) { /* the program name: quotes only, no escapes */
      while (*s && (q || (*s != ' ' && *s != '\t'))) { if (*s == '"') q = !q; else out[o++] = *s; s++; }
      first = 0;
    } else {
      while (*s && (q || (*s != ' ' && *s != '\t'))) {
        if (*s == '\\') {
          u64 bs = 0;
          while (*s == '\\') { s++; bs++; }
          if (*s == '"') {
            for (u64 i = 0; i < bs / 2; i++) out[o++] = '\\';
            if (bs & 1) { out[o++] = '"'; s++; }
          } else for (u64 i = 0; i < bs; i++) out[o++] = '\\';
          continue;
        }
        if (*s == '"') {
          if (q && s[1] == '"') { out[o++] = '"'; s += 2; }
          else { q = !q; s++; }
          continue;
        }
        out[o++] = *s++;
      }
    }
    out[o++] = 0;
  }
  return n;
}

__asm__(".text\n"
        ".globl rg_enter\n"
        "rg_enter:\n"
        "  movq %rdi, %rsp\n"
        "  xorl %eax, %eax\n"
        "  xorl %ebx, %ebx\n"
        "  xorl %ecx, %ecx\n"
        "  xorl %edx, %edx\n"
        "  xorl %esi, %esi\n"
        "  xorl %edi, %edi\n"
        "  xorl %ebp, %ebp\n"
        "  xorl %r8d, %r8d\n"
        "  xorl %r9d, %r9d\n"
        "  xorl %r10d, %r10d\n"
        "  xorl %r11d, %r11d\n"
        "  xorl %r12d, %r12d\n"
        "  xorl %r13d, %r13d\n"
        "  xorl %r14d, %r14d\n"
        "  xorl %r15d, %r15d\n"
        "  movl $0x401000, %ecx\n"
        "  jmp *%rcx\n");
extern HID __attribute__((noreturn)) void rg_enter(u64 *sp);

W __attribute__((noreturn, used)) void rg_win_start(void) {
  fds = VirtualAlloc(0, sizeof(Fd) * NFD, 0x3000, 0x04);
  slots = VirtualAlloc(0, sizeof(Vfork) * NSLOT, 0x3000, 0x04);
  procs = VirtualAlloc(0, sizeof(Proc) * NPROC, 0x3000, 0x04);
  tmp_dir = VirtualAlloc(0, WPATH * 2, 0x3000, 0x04);
  AddVectoredExceptionHandler(1, (void *)on_trap);
  u32 old;
  VirtualProtect((void *)0x400000, 0x1000, 0x04, &old); /* the runtime's page-0 variables */
  *(volatile u64 *)0x4000A0 = (u64)rg_pal;              /* the extension's direct entry */
  main_tid = GetCurrentThreadId();
  QueryPerformanceFrequency(&qpc_freq);
  if (qpc_freq <= 0) qpc_freq = 1;
  cp_out = GetConsoleOutputCP();
  cp_in = GetConsoleCP();
  if (cp_out) SetConsoleOutputCP(65001);
  if (cp_in) SetConsoleCP(65001);
  tmp_len = GetTempPathW(WPATH, tmp_dir);
  for (int i = 0; i < 3; i++) {
    H h = GetStdHandle((u32)(-10 - i));
    fds[i].kind = K_FILE;
    fds[i].h = (h == INVALID) ? 0 : h;
  }

  /* Arguments. */
  const u16 *cl = GetCommandLineW();
  u64 cl_len = wlen(cl);
  u16 *wargs = alloc((cl_len + 2) * 2);
  u16 **wargv = alloc((cl_len / 2 + 2) * sizeof(u16 *));
  u64 argc = split_args(cl, wargs, wargv);

  /* Environment ("Path" is named PATH, as Linux programs expect). */
  u16 *wenv = GetEnvironmentStringsW();
  u64 envc = 0, env_units = 0;
  for (u16 *e = wenv; *e; e += wlen(e) + 1) { envc++; env_units += wlen(e) + 1; }

  u64 str_cap = (cl_len + 2) * 3 + env_units * 3 + 96;
  char *strs = alloc(str_cap);
  u64 slots_n = 1 + argc + 1 + envc + 1 + 6;
  u64 *sp = (u64 *)(((u64)__builtin_frame_address(0) - 0x20000 - slots_n * 8) & ~15ull);
  u64 k = 0, o = 0;
  sp[k++] = argc;
  for (u64 i = 0; i < argc; i++) {
    sp[k++] = (u64)(strs + o);
    o += to_u8(wargv[i], wlen(wargv[i]), strs + o, str_cap - o) + 1;
  }
  sp[k++] = 0;
  for (u16 *e = wenv; *e; e += wlen(e) + 1) {
    if (*e == '=') continue; /* per-drive folders ("=C:=C:\...") */
    char *s = strs + o;
    o += to_u8(e, wlen(e), s, str_cap - o) + 1;
    if (spre(s, "Path=")) { s[1] = 'A'; s[2] = 'T'; s[3] = 'H'; }
    if (spre(s, "RIDGUN_TRACE_SYSCALLS=")) trace = 1;
    sp[k++] = (u64)s;
  }
  sp[k++] = 0;
  u64 *rnd = (u64 *)(strs + ((o + 15) & ~15ull));
  if (!RtlGenRandom(rnd, 16)) { QueryPerformanceCounter((i64 *)rnd); rnd[1] = rnd[0] * 0x9E3779B97F4A7C15ull; }
  sp[k++] = 6;  sp[k++] = 4096;      /* AT_PAGESZ */
  sp[k++] = 25; sp[k++] = (u64)rnd;  /* AT_RANDOM */
  sp[k++] = 0;  sp[k++] = 0;         /* AT_NULL */
  release(wargv);
  release(wargs);
  rg_enter(sp);
}
```
