# Testing in segments, with a time limit

*Status: rule in force since 2026-11-17. Applies to every change of the compiler, the runtime and the libraries of this repository.*

## Why

A full verification of the compiler costs 60 to 80 minutes: three self-builds of about 5 minutes each, then every suite. When it fails or slows down, the cost is paid again and nobody knows which part is at fault. A wait with no limit also hides a hang as "still running".

## The rule

1. **A change is verified first by the short test of the segment it touches.** Each segment has a test that runs in seconds to a few minutes and says which part failed.
2. **Every test has a time limit.** A test that passes the limit is reported as `TIMEOUT`, which counts as a failure. Nobody waits for a test without a limit. The limit is part of the segment definition, not a habit of the person running it.
3. **A full rebuild and the full suites run once, at the end of a piece of work, and in the background with a limit.** They confirm the result; they are not the way to find a fault.
4. **Never start a full rebuild to check something a segment can check.** If a segment is missing, write the segment first.
5. **Timing is judged by scaling, not by absolute milliseconds.** Run the same work at N and at 2N: about twice as long is linear, about four times is quadratic. Absolute limits are kept wide (they catch a hang, not a few percent) because machines differ.

## How we work: fast analysis, fast identification of errors

From 2026-11-17 on, this is how every analysis proceeds. The aim is to know *where* a fault is within minutes, not hours.

1. **Reproduce with the smallest input, in seconds.** A fault found with a 5-minute build is a fault not yet understood.
2. **Measure at three or four sizes, not one.** The exponent between sizes tells linear from quadratic at once (see `tests/segments/run.sh`, `scaling`).
3. **Narrow by segment before reading code.** Run the segment tests; the first one that fails or times out names the area. Only then read that area.
4. **One hypothesis at a time, each with an experiment that answers in under a minute.** State the hypothesis, run the experiment, write down the result, then move on. An experiment that takes longer than two minutes is replaced by a smaller one.
5. **Every experiment has a time limit** (`timeout`). A hang is a result, not a wait.
6. **No full rebuild to find a fault.** Rebuilds and full suites come at the end of the work, once, to confirm.
7. **Write the finding down at once** in the task log: the input, the numbers, the area. A test that failed once becomes a segment.

## The segments

`tests/segments/run.sh` runs the segments and prints one line each: `PASS`, `FAIL` or `TIMEOUT`, with the time taken.

| Segment | What it checks | Limit | Needs a compiler build |
|---|---|---|---|
| `runtime-build` | the IR runtime compiles for Linux x86-64 and wasm32 with no undefined symbol | 120 s | no |
| `runtime-threads` | counts, allocator, locks, slots, cross-thread free, channels, jobs, receive with timeout (`tests/runtime/threads.ll`, 10 rounds) | 180 s | no |
| `runtime-scaling` | four agents against one thread on small-text work: CPU time of four agents stays below 3 times that of one (a shared cache line or a lock shows here) | 120 s | no (uses the installed compiler) |
| `compiler-frontend` | lexer, parser, analyzer and type checker (`ridgunc check`) on n and 2n functions of 1 500 to 3 000; the time ratio stays under 3 | 120 s | no |
| `compiler-build` | the whole pipeline (`ridgunc build`) on a program of 300 and 600 functions called from one `main`; the ratio stays under 3 | 240 s | no |
| `cases-<group>` | one folder of `tests/cases/` on the installed compiler (`lists`, `agents`, `perf`, ...) | 300 s | no |

Segments for the compiler phases (lexer, parser, analyzer, type checker, lowering, LLVM IR emission, `opt`, `llc`, `ld`) are TASK-0099. They need `ridgunc build --timings`, which prints the milliseconds of each phase.

## Baseline found on 2026-11-17

`compiler-frontend` fails: a program of 1 500 functions called from one `main` takes 1 086 ms and 3 000 take 3 680 ms (ratio 3.3). One function with n statements, `ridgunc check`: 500 statements 26 ms, 1 000 53 ms, 2 000 160 ms, 4 000 597 ms. The time doubles up to 1 000 statements and then grows by 3 and 3.7 times: a phase of the front end is quadratic in the size of one function body. This is the first thing the segments found; the cause is not yet located (TASK-0099).

## After ADR-0015 (1.0.21)

The self-build takes about 1 minute (it took 2 min 50 s) and the 22 groups of `tests/cases` take about 2 minutes per backend, so a full confirmation is now a few minutes, not an hour. The rule stays: segments first, full runs at the end.

## Adding a segment

Add a function to `tests/segments/run.sh` with a name, a limit and a command. The command must exit 0 on success and must not need a rebuild of the compiler. Write down in this table what the segment checks and its limit.

## What a failure tells you

- `runtime-build` fails: the IR does not compile or a symbol is missing (the script prints it).
- `runtime-threads` fails on `Tn`: the piece named in the header of `tests/runtime/threads.ll` is wrong (T1 counts, T2 mutex, T3 slots, T4 allocator, T6 channels, T7 jobs, T8 timeout).
- `runtime-scaling` fails: threads are slowed by something they share. Look for per-thread data that sit on one cache line, or a lock on a hot path (this is how the allocator regression of 2026-11-17 showed: four agents used five times the CPU).
- `cases-<group>` fails: read the case, then bisect inside the group.
