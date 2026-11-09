---
id: TASK-0062
title: Runner enforces max-rss-mb and runs every case on the x86-64 backend
status: completed
created: 2026-11-09
completed: 2026-11-09
requirements: [FR-COMP-004, FR-COMP-020]
tests: []
security: []                # VUL-* to address
context_files: [tests/run.rg, tests/README.md, tests/cases/functions/mutual_tail_calls_3m.rg]
scope: [tests/run.rg, tests/run_case.sh, tests/README.md]
owner: agent-002
claimed: 2026-11-09T12:56:30Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0062 — Runner enforces max-rss-mb and runs every case on the x86-64 backend

## Goal (one sentence)
`tests/run.rg` fails a case whose peak resident memory exceeds its `-- max-rss-mb:` header, and builds and runs every case for LLVM and for the pure x86-64 encoder (`--target x86_64-elf`), reporting each backend apart.

## Plan
- [x] Measure each case run's peak RSS without `/usr/bin/time` (not installed) and without Python: new `tests/run_case.sh` (pure Bash) polls `VmHWM` in `/proc/<pid>/status` every 2 ms, takes the CPU time from `times` deltas (the poller's own CPU is not counted), keeps `ulimit -v 4000000` and the time limit (exit 124 as timeout(1)).
- [x] `evaluate case run` checks `max-rss-mb` (MB of 1 024 kB).
- [x] Every case on both backends by default; `--llvm` / `--x86` restrict to one. Rows on x86-64 end in `[x86_64-elf]`; the summary prints `by backend: llvm P of N; x86_64-elf P of N`. Toolchain checks stay LLVM only.
- [x] Prove with a temporary case over its limit (not committed).
- [x] README.

## Progress log (append-only, newest last)
- 2026-11-09: Branch fast-forwarded onto TASK-0061 (372d34d, ridgunc 0.9.47) so `mutual_tail_calls_3m.rg` and the compiler that passes it are here.
- 2026-11-09: Sampling checked against `getrusage(RUSAGE_CHILDREN)` from a throwaway scratch script: 6 280 vs 6 176 kB (mutual_tail_calls_3m), 70 736 vs 68 532 kB (a 3 000 000-element list).

## Files changed (keep current)
- tests/run_case.sh (new), tests/run.rg, tests/README.md

## Verification performed (command → result, newest last)
- `ridgunc check --strict tests/run.rg` → 0 errors.
- `ridgunc run tests/run.rg --no-toolchain functions` → 18 of 18 (9 per backend); `mutual_tail_calls_3m` peak about 6.3 MB on both backends (limit 64 MB).
- Temporary `tests/cases/zztmp/rss_over_limit.rg` (`max-rss-mb: 16`, 3 000 000-element list) → FAIL on both backends: "peak resident memory 70 MB (70728 kB), limit 16 MB" / 67 MB on x86-64. Temporary `zztmp/hangs.rg` (sleeps 20 s, `max-ms: 1000`) → exit 124 after 5 s on both. Both removed.

- Full `ridgunc run tests/run.rg` (both backends, x86-64 without time limits) → 227 of 230; `by backend: llvm 117 of 119; x86_64-elf 110 of 111`. Failing: the two known `stable deps` toolchain checks (TASK-0060, fixed on its own branch) and `literals/rg113_int64_literals.rg [x86_64-elf]` (known). The temporary over-limit case, rerun after the x86-64 time-limit change, still fails on both backends (70 MB / 69 MB, limit 16 MB).

## Exact next actions
1. None.

## Decisions / open questions
- Peak RSS is sampled, not exact: growth in the last 2 ms before exit can go unseen (documented in the README). Exact `getrusage` would need a non-Bash helper.
- Wall-time and CPU limits are LLVM promises (FR-COMP-011 AC-4 says "on LLVM"); on x86-64 a case checks output, exit status and memory, and has the default 30 s time limit (the largest `max-ms` is 20 s). The first full run had `perf/field_reads_and_small_calls.rg` failing on x86-64 at 2 050 ms against its 400 ms LLVM limit.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [ ] coverage matrix regenerated
