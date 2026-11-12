---
id: FR-VM-003
title: PAL network sockets (TCP), one interface with a Linux and a Windows implementation
status: approved
priority: must
created: 2026-11-12
updated: 2026-11-12
depends_on: [FR-COMP-007, FR-VM-002]
verified_by: [TS-VM-003]
related: [ADR-0008, ADR-0007]
---
# FR-VM-003 — PAL network sockets (TCP)

## Statement
The runtime SHALL provide TCP sockets as PAL operations (ADR-0008). A program or library uses them the same way on every target. Each target implements them with its own system: Linux system calls, Windows Winsock.

### 1. Operations
In the table, a **handle** is a non-negative `Int` that `sys close`, `sys poll`, `sys read fd` and `sys write fd` also accept. A **result** is a value `>= 0` or a negative errno (section 2).

| Builtin | Arguments | Result |
|---|---|---|
| `net connect` | host, port, timeout ms | a handle of a connected TCP socket |
| `net listen` | host, port, backlog | a handle of a listening TCP socket. Port `0` takes a free port. A port that a closed connection still holds (`TIME_WAIT`) can be listened on again: Linux sets `SO_REUSEADDR`, which Windows does by default. A port with a listener returns `-98` |
| `net accept` | listening handle, timeout ms | a handle of the accepted connection |
| `net send` | handle, data (`String` or `Tensor[U8]`), timeout ms | the number of bytes sent. Fewer than the length means the timeout ended first; a negative value means no byte was sent |
| `net recv into` | handle, `Tensor[U8]`, from, count, timeout ms | the number of bytes received into the tensor from index `from`; `0` when the peer closed the connection |
| `net recv` | handle, max bytes, timeout ms | the bytes received as a `String`; `""` when the connection is closed, the timeout ended or an error happened |
| `net shutdown` | handle, how (`0` read, `1` write, `2` both) | `0` |
| `net option` | handle, name, value | `0`. The names are `"nodelay"`, `"keepalive"`, `"reuseport"`, `"broadcast"`, `"rcvbuf"` and `"sndbuf"`. A name the target does not have returns `-92` (`ENOPROTOOPT`) |
| `net local port` | handle | the local port |
| `net peer ip` | handle | the peer's address as text (`"127.0.0.1"`), `""` on error |
| `net resolve` | host name | the first IPv4 address of the name as text, `""` when there is none |

- **Host:** `host` is an IPv4 address in text form or a host name. `net connect` resolves a host name as `net resolve` does. `net listen` also accepts `""`, which means every local address (`0.0.0.0`).
- **Timeouts:** a timeout of `-1` waits without limit, and `0` does not wait. Inside a `with timeout` block, a timeout of `-1` uses the time left in the block (FR-COMP-007).
- **Name resolution:** `net resolve` reads the system's host table first, then asks its DNS server.
  - **Linux:** `/etc/hosts`, then the first `nameserver` of `/etc/resolv.conf`, through a UDP query for an A record.
  - **Windows:** `getaddrinfo`.

### 2. Errors
Every target returns the negative Linux errno numbers below. Each implementation maps its own codes to them.

| Error | Value |
|---|---|
| timeout ended | `-110` (`ETIMEDOUT`) |
| connection refused | `-111` (`ECONNREFUSED`) |
| connection reset | `-104` (`ECONNRESET`) |
| broken pipe | `-32` (`EPIPE`) |
| address in use | `-98` (`EADDRINUSE`) |
| permission denied | `-13` (`EACCES`) |
| network unreachable | `-101` (`ENETUNREACH`) |
| host unreachable | `-113` (`EHOSTUNREACH`) |
| host name not found | `-2` (`ENOENT`) |
| invalid argument or handle | `-22` (`EINVAL`) or `-9` (`EBADF`) |

### 3. Implementation
- **Linux:** the operations live in the runtime extension (`rtx.c`) and use Linux system calls.
- **Windows:**
  - The operations live in the Windows layer (`rtw.c`), with Winsock imported from `WS2_32.dll`.
  - The image carries a Windows build of the runtime extension that calls the layer directly, with no trap (ADR-0008).
  - A socket is an entry of the layer's handle table, so `sys close`, `sys poll`, `sys read fd` and `sys write fd` work on it.
- **Other targets:** ARM64 Linux and macOS do not have these operations yet (FR-COMP-022, FR-COMP-015).

## Rationale
Libraries open sockets today through `sys call` with Linux numbers: `libs` `socket.rg`, and `http`, `tls`, `mail` and `ws` on top of it. Those calls only work on Linux. With these operations a library opens, uses and closes a TCP connection the same way on Linux and Windows, without knowing either system's numbers.

## Acceptance criteria
- AC1: On Linux (LLVM and x86-64), a program does the following on `127.0.0.1` with one thread. It prints the same lines on both backends (`tests/cases/net/tcp_loopback_echo.rg`).
  1. It listens on port `0` and reads the port with `net local port`.
  2. It connects, accepts and sends `"ping"` both ways.
  3. It receives with `net recv` and `net recv into`.
  4. It shuts down writing and sees `0` from the other side.
  5. It closes everything.
- AC2: `net connect` to a closed local port returns `-111`. `net accept` with a timeout of `100` and no client returns `-110`. `net resolve "localhost"` returns `"127.0.0.1"`.
- AC3: The program of AC1, built with `--target x86_64-windows`, prints the same lines under Wine.
- AC4: `net option` with `"nodelay"` returns `0` on a connected socket. An unknown option name returns `-92`.
