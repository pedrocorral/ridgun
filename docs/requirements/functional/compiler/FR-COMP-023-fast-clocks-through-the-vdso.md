---
id: FR-COMP-023
title: Fast Clocks Through the vDSO
type: functional
domain: compiler
status: implemented
priority: must
created: 2026-11-09
updated: 2026-11-09
depends_on: []
related: [FR-COMP-022]
verified_by: [TS-COMP-023]
---
# FR-COMP-023 — Fast Clocks Through the vDSO

## Statement
Reading a clock in Ridgun SHALL cost what it costs in C: a call into the kernel vDSO, with no system call and no allocation.

```ridgun
fn :: sys time ms => Int        -- monotonic clock, milliseconds (exists)
fn :: sys time ns => Int        -- monotonic clock, nanoseconds
fn :: sys wall time ms => Int   -- wall clock, milliseconds since 1970-01-01 UTC
```

## Requirements
1. **Values.** `sys time ns` is `CLOCK_MONOTONIC` in nanoseconds and never goes backwards. `sys time ms` is the same clock in milliseconds. `sys wall time ms` is `CLOCK_REALTIME` in whole milliseconds since 1970-01-01 00:00:00 UTC. The results are plain `Int`s.
2. **vDSO.** The process finds `__vdso_clock_gettime` once, from the auxiliary vector (`AT_SYSINFO_EHDR`), and keeps its address. Every clock read calls it. Without a vDSO the clocks use the `clock_gettime` system call.
3. **One implementation.** The three clocks share one routine in the shared runtime, used by every backend that uses that runtime.
4. **Speed.** 1,000,000 calls of any of the three clocks take under 200 ms on the reference machine (vDSO about 17 ns, system call about 320 ns).

## Rationale
Eterval reads the clock twice per latency measurement. Today `sys time ms` costs 357 ns per call, and libs needs eight system calls (15 µs) for nanoseconds or wall time (report `reloj-bytes-crc32`, 2026-11-08).

## Out of scope
- Other clocks (`CLOCK_PROCESS_CPUTIME_ID`, `CLOCK_BOOTTIME`) and time zones.

## Implementation status
Implemented in 0.9.48 (TASK-0063): `clock_read` in the shared runtime extension (`docs/etc/runtime_ext.md`, builtins 100-102). The first read gets the auxiliary vector with `prctl(PR_GET_AUXV)` (Linux 6.4 and later) or `/proc/self/auxv`: the start code of the runtime does not keep the initial stack pointer, and changing it would move every runtime address. Test: `tests/cases/runtime/clocks_through_the_vdso.ridgun`.
