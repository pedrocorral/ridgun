---
id: TASK-0080
title: Agent step form from a lambda's or function value's type, and whole list arguments to function values (RG-115)
status: completed
created: 2026-11-12
completed: 2026-11-12
requirements: [FR-COMP-009, FR-COMP-001]
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [src/main/ridgun/lib/typecheck.rg, src/main/ridgun/lib/compiler.rg]
scope: [src/main/ridgun/lib/typecheck.rg, src/main/ridgun/lib/compiler.rg, tests/cases/agents/, tests/cases/functions/]
owner: agent-001
claimed: 2026-11-12T15:56:25Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0080 — Agent step form from a lambda's or function value's type (RG-115)

## Goal (one sentence)
A stateful agent whose step is a lambda or a function value reads the step's result by the step's type, and a function value gets a list argument whole.

## Plan
- [x] Type checker: infer each lifted lambda's body type (`:lamret:<name>`), and at `agent f init` record the form as the lowering fact `:agstep:<name>:<k>` (8 state only, 7 (state, reply)).
- [x] Lowering: when the signature marks give no form (mode 2), use the fact.
- [x] `__rg_dispatch_call2`: a closure passes its rest arguments inside the reserved constructor `__rg_rest__`; any other second argument is passed whole (a non-empty list was taken for a closure's rest and lost all but its head).
- [x] Cases agents/step_from_lambda_or_function_value.rg and functions/function_value_with_list_argument.rg.
- [x] Full verification, 1.0.7, notes for Solstice.

## Progress log (append-only, newest last)
- 2026-11-12: Solstice report rg115-paso-lambda: RG-115 still happened with a lambda or a function value as the step. Two causes: the form fell back to the run-time rule (lambdas are `__rg_lambda_N` with type-variable signatures), and the call2 dispatcher took the head of any non-empty list second argument.

## Files changed (keep current)
- src/main/ridgun/lib/typecheck.rg, src/main/ridgun/lib/compiler.rg
- docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
- tests/cases/agents/step_from_lambda_or_function_value.rg, tests/cases/functions/function_value_with_list_argument.rg
- build.rg, src/main/ridgun/ridgunc/main.rg, src/main/ridgun/stable/main.rg (1.0.7)

## Verification performed (command → result, newest last)
- Solstice repro with lambdas, with a function value and with named steps → `I1 OK .|Tx .|OK OK .|Tx .|OK Tx .|Tx .|` on llvm and x86_64-elf.
- Bootstrap s1→s4: s3 and s4 differ only in the 4 stamp bytes.
- `tests/run.rg` → 308 of 308 (llvm 161, x86_64-elf 147). Unit tests (8 files) → 0 fails. libs `stable test` → 35/35.
- `ridgunc.exe`, `stable.exe` and the net and `sys os` cases build for x86_64-windows.

## Exact next actions
1. None. The general fix (types reach the lowering, so no fact channel and no run-time guessing) is planned in the typed-lowering task.

## Decisions / open questions
- The closure marker is a constructor, not a 1-tuple: the run-time tuple match also accepts a list of the same length.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
