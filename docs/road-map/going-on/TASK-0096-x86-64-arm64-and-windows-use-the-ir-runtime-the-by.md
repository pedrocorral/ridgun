---
id: TASK-0096
title: x86-64, ARM64 and Windows use the IR runtime; the byte blobs and C sources go
status: going-on
created: 2026-11-15
completed:
requirements: [FR-COMP-022, FR-COMP-023]  # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0013-the-whole-runtime-is-target-neutral-llvm-ir.md, docs/requirements/decisions/ADR-0014-threads-in-the-ir-runtime.md, docs/etc/runtime_ext.md]  # THE ONLY files an agent must read to work on this task
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-16T13:06:10Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
# TASK-0096 — The other targets use the IR runtime

## Goal (one sentence)
x86-64 (pure and LLVM), ARM64 and Windows run on the target-neutral IR runtime of TASK-0088, and the old runtime pieces are deleted (ADR-0013).

## Plan
Order fixed on 2026-11-16 after reading both runtimes (see the log): the IR runtime is single-threaded today and the pure encoder calls internals of the old blob, so those two come before any switch.
- [ ] 0a (PAL written, flat-image script pending). Linux x86-64 PAL in IR (`src/main/runtime/pal/linux-x86_64.ll`): the 21 `__rg_pal_*` functions with inline-assembly system calls, `memcpy`/`memmove`/`memset`; build script producing the flat position-independent runtime at the fixed address.
- [ ] 0b. Threads in the IR runtime (ADR-0014; order: backend calls builtin 57 so jobs run synchronously, thread-safe counts/allocator/channels with the PAL thread interface, the pool, builtin 51): atomic reference counts on shared values, a heap that is safe across threads, channels under a lock, `clone`/`futex` in the PAL, the `||` worker pool and agent jobs on threads; single-threaded targets (wasm32) keep the same IR with the thread hooks as no-ops.
- [ ] 0c. The rt jump table slots of the old blob map to `__rg_rt_*` symbols; the inline routines of `x86_64.ridgun` that call old-blob internals by absolute address (gt conv, sort by, list get, locked builtin, tensor bounds, index set) call the IR functions instead.
- [ ] x86-64 pure encoder: embed the runtime compiled by `llc` as position-independent code at a fixed address, as `rtx.c` is today.
- [ ] LLVM backend: link the same IR; keep the hot functions inlinable; drop the linker-script blob and the duplicated helpers of `llvm.ridgun`.
- [ ] Linux and Windows PAL in IR plus small inline-assembly parts (system calls, `clone`); delete `x86 rt ext`, `win rt ext` and their C sources.
- [ ] ARM64: replace the stubs of `arm64.ridgun` with the runtime compiled for aarch64.
- [ ] The 310 promised behaviours pass on every backend; bootstrap reproducible.

## Progress log (append-only, newest last)
- 2026-11-15: Created with ADR-0013. Needs TASK-0088.

- 2026-11-16: Started. Findings from reading the code: (1) `agents.ll` runs every job synchronously on one thread (the deadlock message says so) and `heap.ll` has one bump pointer and free lists with no lock; the old blob has a work-stealing pool, futexes, spin locks and atomic counts. Switching x86-64 before 0b would lose `||map`/`||filter` and threaded agents. (2) `x86_64.ridgun` inline routines call old-blob internals by absolute address (e.g. `alloc_buf 4205566`, `box_rc_vec 4208821`), so they cannot survive the swap (0c). (3) The `__rg_rt_*` C-ABI entry points of the IR runtime match what the LLVM backend already declares, so the jump-table slots map one to one. `llc`, `clang`, `ld` availability checked: llc and clang present.

- 2026-11-16: 0a PAL written: `src/main/runtime/pal/linux-x86_64.ll` (the 21 `__rg_pal_*` functions on raw system calls, `_start`, first 64 MiB chunk by `mmap`, `trunc` on the bits because `llc` calls it without SSE4.1). Core + PAL link with no undefined symbol and compile with `llc -O2 -relocation-model=pic` (72 018 bytes of code, 2 048 of bss). Not run yet: it needs the flat-image build script and a backend that links it. Also found: the IR runtime has no builtins for sockets, `execve`, pipes and `sys call` (the 6 behaviours wasm32 excludes by AC4), which native Linux has; they need new PAL functions (socket, fork/exec, pipe, raw syscall) and IR builtins before the 310 behaviours can pass on x86-64.

- 2026-11-16: Measured the IR runtime on the LLVM backend for Linux x86-64 (candidate compiler with the development switch `RIDGUN_IR_RT=<object>`, object from `src/main/runtime/build-linux-x86_64.sh`: core + `abi/llvm.ll` + `pal/linux-x86_64.ll`): `--llvm` suite 139 of 149. Failures: 4 agent cases (timeouts: the backend's own job helper starts threads through the old blob), `sys call` builtin 116 (2 cases), net x2, `clocks_through_the_vdso`, `execve_passes_the_whole_argv`. `abi/llvm.ll` gives the entry points the backend's helpers call in the old blob (`alloc_buf`, `box_rc_vec`, `box_rval`, `pop_i64`, `alloc_str`, `drop_slot`, `ext`, `pal_dispatch`). The switch itself (llvm.ridgun) is not committed yet: it goes with the next compiler change and the version bump.

- 2026-11-16: Block A done in the IR runtime (1.0.14). New `src/main/runtime/posix/posix.ll`: `sys call` (83, 116), `sys exec` (62), `execve` (120), `shell exec` (17), pipe, waitpid, kill, terminate, chmod, getpid, getuid, getgid, the users and groups builtins (25-30), `read pass` (31) and the TCP sockets (125-135, with /etc/hosts, localhost and DNS over UDP). `core/system.ll` builds the child environment (ours, then `sys setenv`, then the given list; a later entry wins), as the old runtime does. The Linux PAL reads the clocks through the vDSO. Each builtin was compared with the old runtime on the same program (identical output), except `sys username (-5)` (old: `root`, a quirk; new: `-5`). Tests added: `runtime/sys_call_numbers_buffers_and_errors`, `runtime/processes_exec_wait_pipe_kill_and_chmod`, `runtime/users_groups_shell_and_ids`, `net/tcp_argument_errors_partial_reads_and_options`. With `RIDGUN_IR_RT` the LLVM suite gives 147 of 153; the 6 that fail need threads (4 agent cases, `syscall_variadic_padding_and_agent_dce`, and the proposal `perf/parallel_agents_not_slower`). Default runtime: native suite 306 of 306 (153 on each backend), wasm32 143 (the same cases as before fail: they need a POSIX system). Not tested here: DNS over UDP (no network), `read pass` on a real terminal. Builtin 51 (`receive_from_timeout`) is the only id without an IR implementation; it belongs to block B.

- 2026-11-16: ADR-0014 step (a) done (1.0.15): with the IR runtime (development switch) the LLVM backend's `__rg_builtin_job_spawn` calls builtin 57 instead of reading the old pool at address 4288300; jobs run at once. LLVM suite with the IR runtime: 153 of 153. Default runtime: native 306 of 306, wasm32 143 (unchanged).

- 2026-11-16: ADR-0014 step (b) done (1.0.16). `core/threads.ll`: `rg_mt` flag, thread slot from the stack region (no TLS), futex mutex, atomic counts when the flag is set, per-slot live-block counters (one cache line each), `rg_thread_start`. Allocator sharded by slot (`heap.ll`); channel builtins under a lock (`agents.ll`); PAL thread interface on Linux (`clone` in assembly, futex, yield, thread id) and refusals on wasm32. `tests/runtime/threads.ll` + `run-threads.sh`: T1 shared counts, T2 mutex, T3 slots, T4 cross-thread free, T5 slot reuse, T6 channels (4 producers, 4 consumers); 100 rounds pass; each piece broken on purpose fails its test. LLVM suite on the IR runtime 153 of 153; default native 306, wasm 143, unit tests 10, libs 35.

## Exact next actions
1. ADR-0014 step (c): the pool and parallel jobs (builtins 57-59, 96-99, `||map`, `||filter`), the backend helpers for channels and tagged replies removed; the Vonkeep benchmark (`/tmp/ridgunc-requests.md`, request 2) is the acceptance test. Then step (d) builtin 51, then the IR runtime becomes the default on x86-64.
2. 0b: threads in the IR runtime.
3. PAL functions and IR builtins for sockets, `execve`, pipes and `sys call`.
