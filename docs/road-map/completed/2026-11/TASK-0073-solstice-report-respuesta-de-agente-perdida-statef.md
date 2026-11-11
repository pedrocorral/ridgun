---
id: TASK-0073
title: Solstice report respuesta-de-agente-perdida: stateful step form from the signature
status: completed
created: 2026-11-11
completed: 2026-11-11
requirements: [FR-COMP-009] # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: [src/main/ridgun/lib/compiler.rg, tests/cases/agents/stateful_state_shaped_like_a_pair.rg] # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-11T14:46:11Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0073 — A stateful agent reads its step's result by the step's signature

## Goal (one sentence)
A stateful agent answers every message with what its step returns, whatever its state looks like (Solstice report respuesta-de-agente-perdida, 2026-11-11).

## Plan
- [x] Cause: the generated code chose between `S M => S R` and `S M => S` at run time: a 2-tuple result was taken as "state only" when the current state also matched a 2-tuple. A 2-element list matches too, so a `[Kv]` state that reached 2 elements turned the next result into the new state and the reply. A real 2-tuple state with a `(state, reply)` step broke the same way.
- [x] Fix: the form comes from the step's signature at compile time (marks `:stform:<k>:<fn>`, k = arguments already applied). Agent mode 7 = `(state, reply)`, 8 = state only; 2 stays for steps the compiler cannot see (lambdas, function values), with the old rule. Every mode-2 check accepts 7 and 8, every re-store keeps the agent's mode, and the 4 places that read a step result use the static form first.
- [x] Case `agents/stateful_state_shaped_like_a_pair.rg`; FR-COMP-009 states the rule.
- [x] Bootstrap, suite, unit tests, libs; install 0.9.58; notes.

## Progress log (append-only, newest last)
- 2026-11-11: reproduced on both backends; a 3-element state worked, a 2-element one (1 + 1 over two messages) did not.

## Files changed (keep current)
- src/main/ridgun/lib/compiler.rg, FR-COMP-009, tests/cases/agents/stateful_state_shaped_like_a_pair.rg, version 0.9.58

## Verification performed (command → result, newest last)
- report repro and the new case with stage 1 → expected output; with 0.9.57 → replies lost (list) and wrong (tuple state)
- bootstrap s3/s4 → fixed point (3 bytes); tests/run.rg → 272 of 274, the 2 failures were the new case under --strict (a tuple-state (state, reply) step needs a nested tuple return type); marked `-- no-strict`, agents/ → 24 of 24
- all 8 `src/test/ridgun/test*.rg` → passed; libs `stable test` → 35/35

## Exact next actions
1. None.

## Decisions / open questions
- Lambdas and function values as stateful steps keep the run-time rule; their form is not in a signature the lowering can see.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
