---
id: TASK-0099
title: Per-phase timings of the compiler and scaling tests for each phase and for the runtime (find where a slowdown is, not search from scratch)
status: completed
created: 2026-11-17
completed: 2026-11-18
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-18T20:36:16Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0099 — Per-phase timings of the compiler and scaling tests

## Goal (one sentence)
Find where a slowdown is by measuring each phase and its scaling, instead of searching from scratch or rebuilding the whole compiler.

## Plan
- [x] `ridgunc build --timings` prints the time of each phase (1.0.22).
- [x] Segment tests with a time limit for the runtime and the compiler (`tests/segments/run.sh`), the method written in `docs/etc/testing_in_segments.md`.
- [x] A probe of the stages of the front end and of the parser (`tests/segments/phase_probe.ridgun`, `parse_stages_probe.ridgun`) and a scaling method: three or four sizes, the exponent between them.
- [x] Use it: parallel and memoized LLVM (ADR-0015, self-build 164 s to 53 s), then the front end and the lowering made linear (1.0.34, 1.0.35: 48 s to 27 s).
- [x] `tests/run-groups.sh` keeps the full log of every group, so a failure seen once leaves its reason.
- [ ] Not in this task, left as follow-ups: the front-end cache (TASK-0100), separate compilation (TASK-0101, TASK-0102), and the quadratic of a function with thousands of statements (`lookup local`).

## Progress log (append-only, newest last)
- 2026-11-17: Segment tests written (`tests/segments/run.sh`, `phase_probe.ridgun`, docs/etc/testing_in_segments.md). Measured: building the compiler with itself 171 s = front end 17 s + IR 20 s + `opt -O2` 106 s + `llc` 45 s + `ld`; `opt -O1` 78 s. The parser is quadratic in the statements of one function (500: 8 ms, 1 000: 24, 2 000: 111, 4 000: 483; lexer, type checker and analyzer are linear): `prepend stmt s (ss, rest) = ([s] :: ss, rest)` copies the list at each statement, because `borrow pat ok (PatTuple _)` makes the tuple a borrowed argument and the clone of `ss` makes the list shared. Fix for the parser: an accumulator instead of the tuple; general fix: do not borrow a parameter whose bound variable is extended in place, and release an owned tuple once its fields are bound. ADR-0015 proposes the main remedy (chunks of the call graph, memoized by content, parallel).
- 2026-11-18: Front end and lowering made linear (1.0.34, 1.0.35). Root causes: (1) a list rebuilt as `[x] :: (rest)` or `[e] :: es` copies the rest at every element, and a function that returns a tuple (list, rest) that the caller prepends to copies it too (list literals in the parser and in `lift`: 4x per doubling); (2) `nc emit` kept the instruction list reversed and put each instruction in front; (3) the lowering of the compiler passes a state through a chain of lets, and a variable used as an argument was cloned, so the callee saw two owners and its in-place update copied (OPT-023 moves the only use); (4) `soften name keywords` compared every token with every declared name (now grouped by first word). Self-build 48 s to 27 s (parse 20 to 6 s, lowering 18 to 6.7 s). Open: a function with thousands of statements is still quadratic (`lookup local` is a linear search of the names of the function); about 50 helpers still rebuild a list with `::` in front (the map-like ones can use `map`).

## Files changed (keep current)
`src/main/ridgun/lib/timing.ridgun`, `parser.ridgun`, `compiler.ridgun`, `ast.ridgun`, `llvm.ridgun`; `tests/segments/`, `tests/run-groups.sh`; `docs/etc/testing_in_segments.md`, `docs/etc/compiler_optimizations.md` (OPT-023); ADR-0015.

## Verification performed (command → result, newest last)
- Self-build, `ridgunc build --timings`: parse 20.1 s to 6.3 s, lowering 18 s to 6.7 s, total 48 s to 27 s; bootstrap fixed point.
- Scaling probes: a list literal of 2 000 to 32 000 numbers is linear in the parser, in `lift` and in the lowering; a chain of lets of 32 000 steps 7 700 ms to 7 ms.
- Native suite 23 groups, unit tests 10, libs 35 of 35, 21 projects of the ecosystem unchanged.

## Exact next actions
None in this task. TASK-0100 is the next step for the time of a rebuild.

## Decisions / open questions
The `cmm cond freed/spared` counters of the RMM2 trace test changed by one with OPT-023 (the caller has one conditional drop less); the live blocks did not.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated

