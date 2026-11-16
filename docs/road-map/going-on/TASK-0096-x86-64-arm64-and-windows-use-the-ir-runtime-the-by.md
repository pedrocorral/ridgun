---
id: TASK-0096
title: x86-64, ARM64 and Windows use the IR runtime; the byte blobs and C sources go
status: going-on
created: 2026-11-15
completed:
requirements: [FR-COMP-022, FR-COMP-023]  # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0013-the-whole-runtime-is-target-neutral-llvm-ir.md, docs/etc/runtime_ext.md]  # THE ONLY files an agent must read to work on this task
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
- [ ] 0b. Threads in the IR runtime (ADR-0013 rule 2): atomic reference counts on shared values, a heap that is safe across threads, channels under a lock, `clone`/`futex` in the PAL, the `||` worker pool and agent jobs on threads; single-threaded targets (wasm32) keep the same IR with the thread hooks as no-ops.
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

## Exact next actions
1. Remaining 10 cases: builtin 116 and `sys call`, sockets, `execve`, the vdso clock case, then threads (agents).
2. 0b: threads in the IR runtime.
3. PAL functions and IR builtins for sockets, `execve`, pipes and `sys call`.
