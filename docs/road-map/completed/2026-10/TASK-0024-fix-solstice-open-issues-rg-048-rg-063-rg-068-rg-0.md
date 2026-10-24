---
id: TASK-0024
title: Fix Solstice open issues RG-048, RG-063, RG-068, RG-069, RG-071, RG-072, RG-073, RG-074, RG-075, RG-079
status: completed
created: 2026-10-24
completed: 2026-10-24
requirements: [FR-COMP-002, FR-COMP-004, FR-COMP-005, FR-COMP-006, FR-COMP-009, FR-TOOL-001, FR-TOOL-002]
tests: [TS-COMP-005, TS-FUNC-001]
security: []
context_files: [src/main/ridgun/lib/parser.rg, src/main/ridgun/lib/typecheck.rg, src/main/ridgun/lib/analyzer.rg, src/main/ridgun/lib/compiler.rg, src/main/ridgun/lib/x86_64.rg, src/main/ridgun/stable/main.rg, "src/test/ridgun/test parallel and tensors.rg", "src/test/ridgun/test lib and plugins.rg"]
scope: [src/main/ridgun/, src/test/ridgun/, harness/, .aix/custom/, .agents/, bin/]
owner: agent-001
claimed: 2026-10-24T13:23:49Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0024 — Fix Solstice open issues RG-048, RG-063, RG-068, RG-069, RG-071, RG-072, RG-073, RG-074, RG-075, RG-079

## Goal (one sentence)
Resolve all 11 open compiler, runtime, and tooling issues reported by Solstice (`RG-048`, `RG-063`, `RG-068`, `RG-069`, `RG-071`, `RG-072`, `RG-073`, `RG-074`, `RG-075`, `RG-079`, and record update harness docs) and install the Antigravity `PreToolUse` security guard hook.

## Plan
- [x] Fix `RG-072` (remove 65,536-iteration `pause` spin loop in `async_poll` / `try receive from`)
- [x] Fix `RG-069` (drop return value of `NCallBuiltin 50` `chan_send` in `lower_agent_call`)
- [x] Fix `RG-075` (replace quadratic list-append passes and O(N²) lookups in `parser.rg`, `typecheck.rg`, `analyzer.rg`, `compiler.rg`)
- [x] Fix `RG-073` (allow local parameters/bindings to shadow 0-arg top-level functions)
- [x] Fix `RG-068` (depth-aware `=` scanning in `parser.rg` for parenthesized `with field = val`)
- [x] Fix `RG-063` (polymorphic `Option a` / `Some` / `None` type checking and specialization)
- [x] Fix `RG-071` (remove hard-coded `/home/boogie/ridgun-libs` paths and resolve `.stable/deps` dynamically)
- [x] Fix `RG-048` (deduplicate transitive `.rglib` imports and avoid embedding dependencies into `.rglib` bundles)
- [x] Fix `RG-074` (surface `ridgunc` diagnostics in `stable`)
- [x] Fix `RG-079` (shard heap allocator across 16 cache-line-isolated per-thread arenas in `x86_64.rg`)
- [x] Update harness documentation (`with field = val`) and install `PreToolUse` security guard hook (`.agents/hooks.json`)

## Progress log (append-only, newest last)
- 2026-10-24: Implemented fixes for `RG-072`, `RG-069`, `RG-075`, `RG-073`, `RG-068`, `RG-063`, `RG-071`, `RG-048`, `RG-074`, and `RG-079`, plus `.agents/hooks.json` + `.agents/hooks/safety-guard.sh`, 3-stage self-hosted `ridgunc` and `stable`, and verified 5/5 test suites.

## Files changed (keep current)
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/analyzer.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/x86_64.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `harness/instructions/ridgun.md`
- `.aix/custom/instructions/languages/ridgun.md`
- `.agents/skills/implement-code-ridgun/SKILL.md`
- `.agents/hooks.json`
- `.agents/hooks/safety-guard.sh`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `./target/ridgunc_stage1 build src/main/ridgun/ridgunc/main.rg -o target/ridgunc_stage2 && ./target/ridgunc_stage2 build src/main/ridgun/ridgunc/main.rg -o target/ridgunc_stage3 && sha256sum target/ridgunc_stage2 target/ridgunc_stage3` → `6d89cf91cbd074cf4d5e62a54f200f2de7ee1684c904acf9201bdc80603d7647` (exact match)
- `./bin/stable check && ./bin/stable test` → Checked 13 modules (0 errors), Passed 5/5 test suites (0 failures).
- `/tmp/par serial && /tmp/par rotate && /tmp/par parallel` → `serial: 144 ms`, `rotate: 157 ms`, `parallel: 101 ms` (down from 1110 ms).

## Exact next actions
1. Task completed.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
