---
id: ADR-0015
title: Compilation is memoized by content and parallel by chunks of the call graph
status: accepted
date: 2026-11-17
supersedes: []
affects: [src/main/ridgun/lib/llvm.ridgun, src/main/ridgun/ridgunc/main.ridgun, tests/segments/run.sh, docs/etc/testing_in_segments.md, TASK-0099]
---
# ADR-0015 — Compilation is memoized by content and parallel by chunks of the call graph

## Context
Measured on 2026-11-17 (segment tests, `tests/segments/run.sh`), building the compiler with itself takes 171 s:

| Phase | Time |
|---|---|
| Front end (lexer, parser, type checker, analyzer) | 17 s (10 %) |
| Lowering and writing the LLVM IR (one file of 105 MB) | 20 s (12 %) |
| `opt -O2` on that one module | 106 s (62 %) |
| `llc -O2` | 45 s |
| `ld` | seconds |

`opt -O1` takes 78 s, 26 % less: the optimization level is not the cause. The cause is the shape of the work: one module, one thread, all of it again after any change. A full verification (three self-builds and every suite) costs 60 to 80 minutes.

## Options considered
1. Lower the optimization level for development builds. Gains 26 % at most, and tests would run a different program from the release.
2. Make the IR smaller (fewer instructions per NIR instruction). Real but linear: the same shape of work.
3. Split the program into chunks that LLVM compiles in parallel, and cache each chunk by the hash of its content.

## Decision
Option 3, done with `llvm-split` (the standard LLVM tool splits a module by its symbol graph and keeps the symbols the parts share, such as the channel lock) instead of a splitter of our own. Compilation of a program is a pure function of its inputs, so:

1. **Chunks follow the call graph.** The functions are grouped by strongly connected component of the call graph (a recursive group is never split) and the components are packed into chunks of balanced size, keeping callers and callees together. Each chunk is a module of its own. A function a chunk calls in another chunk is a `declare`; the small hot helpers of the runtime stay `alwaysinline` in every chunk.
2. **Memoization by content.** The key of a chunk is the hash of its IR text, the optimization level, the target and the compiler version. The object is stored under that key in a cache directory (written to a temporary name and renamed into place, as the runtime object already is). A chunk with an unchanged key is not compiled again. The compiler's output is deterministic (the self-build reaches a fixed point), so equal source gives equal keys.
3. **Parallel by default.** Chunks that are not cached are compiled together, up to the number of cores, then linked. The time of a build is the work divided by the cores plus the longest chain, not the sum of the work.
4. **Same semantics.** Only inlining across chunks is lost. A differential check (the suites with and without chunking give the same outputs) is the proof.
5. The test suites follow the same idea: a case result is a function of the compiler binary, the case source and the flags, so a result with unchanged inputs is not recomputed.

## Result (1.0.21, 2026-11-17, 16 cores)
Building the compiler with itself: 164 s before, 53 s now with an empty cache and 51 s with a full one; the binary is identical in both (0 bytes of difference). `opt` and `llc`: 151 s serial, 24 s in 16 parts. The remaining 45 s are the front end and the IR, not LLVM. The cache key is the hash of the part: `llvm-split` keeps the name of its input in the bitcode, so it runs on a fixed relative name (a first version with the process id in the name never hit the cache). All 22 groups of `tests/cases` on both backends and the 10 unit tests pass with it.

## Consequences
- **Expected (before the measurement above):** the cold build of the compiler from 171 s to about 25 s on 16 cores; a rebuild after a change of a few functions in a few seconds. To be measured, not assumed (segments below).
- **Tests, each with a time limit (docs/etc/testing_in_segments.md):** `chunks-deterministic` (same program, same chunk keys twice, 60 s); `chunks-equivalent` (the outputs of a set of programs are the same with 1 chunk and with N chunks, 120 s); `build-scaling` (cold build time at 1 and at 8 jobs, the second at most half of the first on a machine with 8 cores or more, 240 s); `build-warm` (a second build of the same program compiles no chunk, 60 s).
- **Code to change:** `llvm.ridgun` (emit chunks, the build driver with the cache and the parallel run), `main.ridgun` (a `--jobs` option and the cache directory), the segments file.
- **Risk:** the loss of inlining between chunks can slow hot code. The chunking keeps callers with callees, and the differential and performance suites (`tests/cases/perf`) decide whether the loss matters.
- **Separate and smaller:** the parser is quadratic in the number of statements of one function (`prepend stmt` copies the list at each statement because a borrowed tuple holds it); it costs 17 s of the self-build front end, not the main cost. TASK-0099 records it.
