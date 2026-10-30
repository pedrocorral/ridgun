---
id: TASK-0043
title: Ridgun v0.9.29 cross-team audit fixes (TL-001, TL-002, RG-100, WR-001..005, RG-103, RG-104, CH-001)
status: completed
created: 2026-10-29
completed: 2026-10-30
requirements: [FR-COMP-001, FR-COMP-006, FR-COMP-013, FR-COMP-014, FR-VM-001, FR-TOOL-002]
tests: [TS-UNIT-001]
security: []
context_files:
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/analyzer.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/arm64.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/stable/main.rg
  - src/main/ridgun/ridgunc/main.rg
  - build.rg
scope:
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/analyzer.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/arm64.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/stable/main.rg
  - src/main/ridgun/ridgunc/main.rg
  - build.rg
  - src/test/ridgun/test core language.rg
  - docs/requirements/functional/compiler/FR-COMP-001-parallel-and-sequential-higher-order-list-ops.md
  - docs/requirements/functional/compiler/FR-COMP-013-generics-closures-and-regression-hardening.md
  - docs/requirements/functional/tooling/FR-TOOL-002-project-scaffolding-dependencies-and-install.md
owner: agent-001
claimed: 2026-10-29T11:11:26Z
claimed_by: agent gemini@solarfall
---
# TASK-0043 — Ridgun v0.9.29 cross-team audit fixes (TL-001, TL-002, RG-100, WR-001..005, RG-103, RG-104, CH-001)

## Goal (one sentence)
Resolve all 11 compiler, runtime, and `stable` issues reported in `/tmp/ridgun-compiler/2026-10-29/report.md` (`TL-001`, `TL-002`, `RG-100`, `WR-001`, `WR-002`, `WR-003`, `WR-004`, `WR-005`, `RG-103`, `RG-104`, `CH-001`), verify all repros and regression tests, and bootstrap `ridgunc` and `stable` `v0.9.29`.

## Plan
- [x] Fix `WR-002` (parameter shadowing global function name in `lookup arity`, `has arity prefix loop`, `filter arity prefix loop`), `WR-003` (`has longer arity prefix` checking operator words across intermediate operand slots), `WR-001` (preserving mangled multi-word function name on excess arguments in `finish postfix or partial`), `CH-001` (actionable parser error with function/token context on stray delimiter / invalid top-level item), and `RG-104` (prioritizing direct `.stable/deps/<spec>` before nested dependency folders in `parser.rg` and `stable/main.rg`).
- [x] Fix `TL-001` (preventing `prep call` from rewriting partial applications of 2-arg functions to `__unpack2__` unless the argument is a tuple unpack expression, and fixing 2-arg indirect closure call slot unpacking), `RG-100` (enabling parallel worker execution for capturing closures in `||map` and `||filter`), and `RG-103` (short-circuit evaluation for boolean `and` / `or` while preserving bitwise `and` / `or` on `Int`), plus `TL-003` (`new_channel` unifying with `Channel` type annotations).
- [x] Fix `TL-002` (lexicographical `String` comparison for `<`, `>`, `<=`, `>=` in runtime and static typechecker), `WR-005` (`write_file` preserving existing file permissions or defaulting to `0644` instead of `0755`), and `WR-004` (eliminating O(N^2) token-stream copying in `parse items mod`, BST-indexed `RModCtx`, `RPrepArityMap`, `RTypeBindMap`, and `RSummaryMap`, reducing `www-ridgun` frontend time from >7 min / >5.2 GB RAM to 16.8s and full native build to <60s within `ulimit -v 4000000`).
- [x] Bump version to `0.9.29`, bootstrap Stage 1 + Stage 2 of `ridgunc` and `stable`, verify all repros in `/tmp/ridgun-compiler/2026-10-29/repros/` and all test suites (`stable check`, `stable test`, `tests/run.rg`), and install to `bin/`.

## Progress log (append-only, newest last)
- 2026-10-29: Root-caused all 11 issues in `/tmp/ridgun-compiler/2026-10-29/report.md` and confirmed `TL-002` (lexicographical string comparison) and `RG-103` (short-circuit `and`/`or`) with user.
- 2026-10-30: Implemented fixes for all 12 issues (`TL-001`, `TL-002`, `TL-003`, `RG-100`, `RG-103`, `RG-104`, `WR-001`, `WR-002`, `WR-003`, `WR-004`, `WR-005`, `CH-001`), optimized `parse items mod`, `resolve scoped state`, `normalize program`, `typecheck program`, and `analyze rprogram`, added regression and compilation-speed tests in `src/test/ridgun/test core language.rg`, and bootstrapped `ridgunc` and `stable` `v0.9.29`.

## Files changed (keep current)
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/analyzer.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/x86_64.rg`
- `src/main/ridgun/lib/arm64.rg`
- `src/main/ridgun/lib/llvm.rg`
- `src/main/ridgun/stable/main.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `build.rg`
- `src/test/ridgun/test core language.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `docs/requirements/functional/compiler/FR-COMP-001-parallel-and-sequential-higher-order-list-ops.md`
- `docs/requirements/functional/compiler/FR-COMP-013-generics-closures-and-regression-hardening.md`
- `docs/requirements/functional/tooling/FR-TOOL-002-project-scaffolding-dependencies-and-install.md`
- `docs/road-map/going-on/TASK-0043-ridgun-v0-9-29-cross-team-audit-fixes-tl-001-tl-00.md`
- `docs/road-map/going-on/STATE.md`

## Verification performed (command → result, newest last)
- `cd /home/boogie/www-ridgun && ulimit -v 4000000 && ridgunc build src/main/ridgun/server/main.rg -o /tmp/www_server_test` → exit code 0 in 59.6s (frontend 16.8s)
- `./bin/stable test` → Passed 6/6 test suites (0 failures)
- `./bin/stable check` → Checked 14/14 modules (0 errors)
- `aix docs validate` → 0 errors

## Exact next actions
1. Complete `TASK-0043` and commit changes.

## Decisions / open questions
- `TL-002`: Runtime lexicographical comparison for `String` on `<`, `>`, `<=`, `>=`.
- `RG-103`: Short-circuit evaluation for boolean `and` / `or`.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
