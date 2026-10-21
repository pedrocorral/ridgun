# Ridgun v0.9.5 — Platform Abstraction Layer (PAL) & System Libraries (`posix.rglib`, `io.rglib`) Specification

This specification defines the contract between the **Ridgun Compiler (`ridgunc` v0.9.5)** and the **Ridgun System Libraries (`posix.rglib`, `io.rglib`, `unix-tools`)** across all supported and planned OS targets (`Linux`, `MacOS`, `Windows`) and CPU architectures (`X86_64`, `Arm64`).

---

## 1. Architecture Overview: 2-Layer PAL + Target Sum ADTs

Ridgun avoids exposing raw Linux-only syscall numbers or OS-specific bitflags in portable libraries by splitting system interaction into two compiler layers plus strongly typed target ADTs:

1. **Pre-Declared Target Platform Sum ADTs (`sys os => SysOs`, `sys arch => SysArch`)**:
   - Rather than returning untyped `String`s (which are prone to typos and cannot be checked by the typechecker), `ridgunc` pre-declares two extensible Sum ADTs:
     ```ridgun
     type SysOs   = Linux | MacOS | Windows
     type SysArch = X86_64 | Arm64
     ```
   - `sys os => SysOs` and `sys arch => SysArch` are resolved by the backend at compile time into zero-overhead `NLoadAdt0` constants (`Linux` / `X86_64` on `x86_64-linux`, `Linux` / `Arm64` on `arm64-linux`).
   - Libraries can dispatch cleanly by **tabular pattern matching** on `SysOs` / `SysArch`, compare with `==` (`(sys os) == Linux`), or extend them for custom bare-metal/BSD targets via `expand type SysOs = FreeBSD | BareMetal` (`FR-COMP-005`).

2. **Layer 1 — Cross-Platform PAL Primitives (`sys open mode`, `sys open`, `sys close`, `sys read fd`, `sys write fd`, `sys poll`, `sys terminate`, `sys kill`, `sys call`)**:
   - All flag masks and poll event masks passed to Layer 1 primitives use **Ridgun PAL Normalized Constants**.
   - Each backend (`x86_64.rg` ELF64, `arm64.rg` ELF64, and future `Mach-O` macOS / `PE64` Windows backends) translates those normalized constants into the native OS kernel ABI (`openat`/`poll`/`kill` on Linux, `open`/`poll`/`kill` on macOS, `CreateFileW`/`WaitForSingleObject`/`WSAPoll`/`TerminateProcess` on Windows).
   - Both natural-language space-separated syntax (`sys open mode path "r"`) and underscore-separated syntax (`sys_open_mode path "r"`) are accepted identically.

3. **Layer 2 — Declarative Execution Quotas (`with timeout <duration> do`)**:
   - Integer literals support duration suffixes: `_ms` (`* 1`), `_s` (`* 1000`), and `_min` (`* 60000`).
   - `with timeout 500_ms do <body>` (and combined `with region 64_KB, timeout 500_ms do <body>`) pushes a lexical deadline (`sys time ms + duration_ms`) onto the thread-local PAL deadline stack, clamping to any stricter outer deadline (`min(outer, new)`) and restoring the outer deadline on exit.
   - Inside a `with timeout` block, `sys deadline ms => Int` returns the active epoch deadline (`0` if unbounded), `sys remaining ms => Int` returns the remaining milliseconds (`-1` if unbounded, `0` if expired), and `sys poll fd events -1` automatically clamps its wait time to `sys remaining ms`.

---

## 2. Compiler Built-In PAL Reference (`FR-COMP-007`)

### 2.1 Target Platform Introspection

| Primitive | Signature | Description |
|---|---|---|
| `sys os` | `=> SysOs` | Compile-time target operating system (`Linux \| MacOS \| Windows`). |
| `sys arch` | `=> SysArch` | Compile-time target CPU architecture (`X86_64 \| Arm64`). |

Example of idiomatic multi-OS dispatch in a `.rglib` library without `if/else` chains:

```ridgun
fn :: path separator SysOs   => String
      path separator Linux   =  "/"
      path separator MacOS   =  "/"
      path separator Windows =  "\\"

fn :: null device => String
      null device =  null device for (sys os)

fn :: null device for SysOs   => String
      null device for Windows =  "NUL"
      null device for _       =  "/dev/null"
```

### 2.2 Descriptor / Handle I/O & Readiness Polling

| Primitive | Signature | Normalized PAL Contract |
|---|---|---|
| `sys open mode` | `String String => Int` | Opens `path` with portable mode string `"r"`, `"w"`, `"a"`, `"rw"`, `"w+"`, or `"a+"` (default permission `0644` / `420` when creating). Returns descriptor/handle `>= 0` or negative error code (`-errno`). |
| `sys open` | `String Int Int => Int` | Opens `path` with Ridgun PAL normalized `flags` (`0` = read-only, `1` = write-only, `2` = read-write, `64` = create, `512` = truncate, `1024` = append, `2048` = non-blocking) and permission `mode` (e.g. `420` for `0644`). |
| `sys close` | `Int => Int` | Closes `fd`/handle. Returns `0` on success or negative `-errno`. |
| `sys read fd` | `Int Int => String` | Reads up to `max_bytes` from `fd`/handle (`0` = stdin, `1` = stdout, `2` = stderr, or opened file/pipe/FIFO). Returns `""` on EOF (`0` bytes) or error. |
| `sys write fd` | `Int String => Int` | Writes `data` to `fd`/handle. Returns bytes written (`>= 0`) or negative `-errno`. |
| `sys poll` | `Int Int Int => Int` | Polls `fd` for normalized `events` (`1` = `POLLIN` readable, `4` = `POLLOUT` writable, `8` = `POLLERR`, `16` = `POLLHUP`) with `timeout_ms` (`-1` = infinite or clamped to `sys remaining ms` when inside `with timeout`, `0` = non-blocking poll, `> 0` = max wait in ms). Returns `> 0` ready event bitmask, `0` on timeout, or `< 0` on `-errno`. |

### 2.3 Clocks, Deadlines, Signals & Low-Level Escape Hatch

| Primitive | Signature | Normalized PAL Contract |
|---|---|---|
| `sys time ms` | `=> Int` | Monotonic millisecond clock (`CLOCK_MONOTONIC`). |
| `sys sleep ms` | `Int => ()` | Sleeps for `ms` milliseconds (`nanosleep` / `Sleep`). |
| `sys deadline ms` | `=> Int` | Active lexical deadline in monotonic ms (`0` when outside `with timeout`). |
| `sys remaining ms` | `=> Int` | Milliseconds remaining until active lexical deadline (`-1` when outside `with timeout`, `0` when expired). |
| `sys getpid` | `=> Int` | Current process ID (`> 0`). |
| `sys terminate` | `Int Bool => Int` | Cross-platform process termination: `force = False` sends graceful termination (`SIGTERM` on POSIX), `force = True` forces immediate termination (`SIGKILL` on POSIX, `TerminateProcess` on Windows). Returns `0` or `-errno`. |
| `sys kill` | `Int Int => Int` | Sends normalized signal (`0` = existence probe, `2` = `SIGINT`, `9` = `SIGKILL`, `15` = `SIGTERM`) to `pid` (or process group when `pid < 0`). Returns `0` or `-errno`. |
| `sys call` | `Int Int Int Int Int Int Int => Int` | Low-level target-ABI raw syscall (`nr`, `a1..a6`) for OS-specific drivers. Guard with `sys os` / `sys arch` when used. |

---

## 3. Recommended `.rglib` Library Surface (`io.rglib` & `posix.rglib`)

### 3.1 `io.rglib` — High-Level Timeout-Aware I/O Wrappers

```ridgun
type IoResult = IoOk String | IoTimeout | IoEof | IoError Int

fn :: io read with timeout String Int     => IoResult
      io read with timeout path   wait_ms =
        with timeout wait_ms do
          -- Open non-blocking (0 + 2048 = O_RDONLY | O_NONBLOCK) so FIFO/device open never hangs
          fd = sys open path 2048 0
          io read poll step fd

fn :: io read poll step Int => IoResult
      io read poll step fd
        | fd < 0 = IoError fd
        | otherwise =
          -- timeout_ms = -1 automatically uses `sys remaining ms` from the active `with timeout` block
          ev = sys poll fd 1 (0 - 1)
          io read after poll fd ev

fn :: io read after poll Int Int => IoResult
      io read after poll fd  ev
        | ev == 0 =
          _ = sys close fd
          IoTimeout
        | ev < 0 =
          _ = sys close fd
          IoError ev
        | otherwise =
          chunk = sys read fd fd 65536
          _ = sys close fd
          io wrap chunk chunk

fn :: io wrap chunk String => IoResult
      io wrap chunk ""     =  IoEof
      io wrap chunk s      =  IoOk s
```

### 3.2 `posix.rglib` — Symbolic Constants & Process Helpers

```ridgun
-- Normalized PAL Open Flags
fn :: o rdonly   => Int
      o rdonly   =  0

fn :: o wronly   => Int
      o wronly   =  1

fn :: o rdwr     => Int
      o rdwr     =  2

fn :: o creat    => Int
      o creat    =  64

fn :: o trunc    => Int
      o trunc    =  512

fn :: o append   => Int
      o append   =  1024

fn :: o nonblock => Int
      o nonblock =  2048

-- Normalized PAL Poll Events
fn :: poll in  => Int
      poll in  =  1

fn :: poll out => Int
      poll out =  4

fn :: poll err => Int
      poll err =  8

fn :: poll hup => Int
      poll hup =  16

-- Normalized Signals
fn :: sig int  => Int
      sig int  =  2

fn :: sig kill => Int
      sig kill =  9

fn :: sig term => Int
      sig term =  15

fn :: process exists Int => Bool
      process exists pid =  (sys kill pid 0) == 0
```

---

## 4. Building & Distributing `.rglib` and `.so` Libraries

Compile any library module without requiring `main`:

```bash
# Emit portable Ridgun library bundle (.rglib)
./bin/ridgunc build --lib src/main/ridgun/lib/io.rg -o target/io.rglib

# Emit native ELF64 shared object (.so)
./bin/ridgunc build --so src/main/ridgun/lib/io.rg -o target/libio.so

# Or via stable in a library project (`stable new --lib io`):
./bin/stable built lib
```
