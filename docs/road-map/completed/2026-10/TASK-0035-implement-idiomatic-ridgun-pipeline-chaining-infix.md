---
id: TASK-0035
title: Implement idiomatic Ridgun pipeline chaining (->, infix start, -> (), and _ = removal) across compiler, books, and skills
status: completed
created: 2026-10-27
completed: 2026-10-27
requirements: [FR-COMP-014]
tests: [TS-COMP-001]
security: []
context_files: [docs/requirements/functional/compiler/FR-COMP-014-idiomatic-pipeline-chaining-and-side-effect-statements.md, src/main/ridgun/lib/parser.rg, src/main/ridgun/lib/compiler.rg, src/main/ridgun/ridgunc/main.rg, docs/lang/spec.md]
scope: [src/main/ridgun/**, src/test/ridgun/**, docs/**, .aix/custom/instructions/languages/ridgun.md, .agents/skills/implement-code-ridgun/SKILL.md]
owner: agent-001
claimed: 2026-10-27T10:01:01Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0035 — Implement idiomatic Ridgun pipeline chaining (`->`, infix start, `-> ()`, and `_ =` removal) across compiler, books, and skills

## Goal (one sentence)
Implement idiomatic Ridgun pipeline chaining (`->`), left-operand `op`/`fn` invocation (`xs map f -> filter g -> compact l -> results`), sequence mask stages (`-> (+ _ _ +) ->`), explicit unit discarding (`-> ()`), and `_ =`-free side-effect statements (`FR-COMP-014`) across the compiler, test suite, books, and skills.

## Plan
- [x] Author and register `FR-COMP-014` in `docs/requirements/functional/compiler/INDEX.md`
- [x] Implement `parse_pipe_chain`, `parse_pipe_stage`, `reduce_infix_steps`, `norm_pipe_step`, `-> ()` unit discard, and `_ =`-free statement parsing in `src/main/ridgun/lib/parser.rg` (`-- @implements FR-COMP-014`)
- [x] Refactor `src/main/ridgun/ridgunc/main.rg`, `src/main/ridgun/lib/compiler.rg`, `src/main/ridgun/lib/elf64.rg`, `src/main/ridgun/lib/llvm.rg`, `src/main/ridgun/stable/main.rg`, and all `src/test/ridgun/*.rg` suites to use idiomatic `->` pipelines and eliminate all `_ =` statement bindings
- [x] Add automated test coverage (`-- @tests TS-COMP-001`) in `src/test/ridgun/test core language.rg`
- [x] Update `docs/lang/spec.md`, `.aix/custom/instructions/languages/ridgun.md`, `.agents/skills/implement-code-ridgun/SKILL.md`, and all 7 book editions (`es`, `en`, `ca`, `gl`, `eu`, `pt`, `sv`) + rebuild interactive HTML books (`python3 docs/book/build_book.py`)
- [x] Bootstrap Stage 1 & Stage 2 `bin/ridgunc` and `bin/stable`, run `./bin/stable check`, `./bin/stable test`, `python3 tests/run.py`, and `aix docs validate`

## Progress log (append-only, newest last)
- 2026-10-27: Created and approved `FR-COMP-014` defining the 4 left-to-right pipeline styles (highlighting `2b`: `xs map f -> filter g -> compact l -> results`), universal 1st-argument insertion, `-> (+ _ _ +) ->` sequence masks, `-> ()` explicit unit discard, and `_ =` elimination.
- 2026-10-27: Implemented `FR-COMP-014` in `src/main/ridgun/lib/parser.rg`, refactored compiler/CLI/test `.rg` files to use `->` pipelines and zero `_ =` bindings, updated `docs/lang/spec.md`, language instructions, skills, and all 7 book editions (`es`, `en`, `ca`, `gl`, `eu`, `pt`, `sv`), and rebuilt `bin/ridgunc` and `bin/stable`.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-014-idiomatic-pipeline-chaining-and-side-effect-statements.md`
- `docs/requirements/functional/compiler/INDEX.md`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/elf64.rg`
- `src/main/ridgun/lib/llvm.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test.rg`
- `src/test/ridgun/test core language.rg`
- `src/test/ridgun/test strings.rg`
- `src/test/ridgun/test llvm codegen.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `docs/lang/spec.md`
- `.aix/custom/instructions/languages/ridgun.md`
- `.agents/skills/implement-code-ridgun/SKILL.md`
- `docs/book/es/05-listas-tuplas-y-secuencias.md`, `docs/book/es/07-orden-superior-y-paralelismo-dag.md`
- `docs/book/en/05-lists-tuples-and-sequences.md`, `docs/book/en/07-higher-order-functions-and-dag-parallelism.md`
- `docs/book/ca/05-llistes-tuples-i-sequencies.md`, `docs/book/ca/07-ordre-superior-i-parallelisme-dag.md`
- `docs/book/gl/05-listas-tuplas-e-secuencias.md`, `docs/book/gl/07-orde-superior-e-paralelismo-dag.md`
- `docs/book/eu/05-zerrendak-tuplak-eta-sekuentziak.md`, `docs/book/eu/07-goi-mailako-funtzioak-eta-dag-paralelismoa.md`
- `docs/book/pt/05-listas-tuplas-e-sequencias.md`, `docs/book/pt/07-ordem-superior-e-paralelismo-dag.md`
- `docs/book/sv/05-listor-tupler-och-sekvenser.md`, `docs/book/sv/07-hogre-ordningen-och-dag-parallellism.md`
- `docs/book/*/index.html`, `docs/book/index.html`
- `bin/ridgunc`, `bin/stable`

## Verification performed (command → result, newest last)
- `./bin/ridgunc run "src/test/ridgun/test core language.rg"` → Passed 100% including `FR-COMP-014` pipeline styles (`1`, `2`, `2b`, `3`), sequence masks (`-> (+ _ _ +) ->`), `-> ()` unit discard, and `_ =`-free statements.
- `grep -rn "^[ ]*_ = " src/` → 0 matches across the entire codebase.
- `python3 docs/book/build_book.py` → Regenerated all 7 language HTML editions + root `docs/book/index.html`.
- `./bin/stable check` → `[success] Checked 14 module(s) — 0 errors.`
- `./bin/stable test` → `[success] Passed 6/6 test suite(s) — 0 failures.`
- `python3 tests/run.py` → `40 of 40 promised behaviours passed`.
- `aix docs validate` → `0 errors`.

## Exact next actions
1. Completed.

## Decisions / open questions
- Style `2b` (`xs map f -> filter g -> compact l -> results`) is highlighted as the recommended idiomatic Ridgun style across the specification, books, and skills while keeping styles `1`, `2`, `3`, and traditional `=` / prefix calls 100% supported.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
