---
id: TASK-0020
title: Evaluate changing agent creation keyword to agentic so agent can be used as a variable identifier
status: pending             # pending | going-on | blocked | completed
created: 2026-10-23
completed:
requirements: [FR-COMP-009]
tests: [TS-COMP-005]
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/analyzer.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test parallel and tensors.rg
scope:
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/analyzer.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test parallel and tensors.rg
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0020 — Evaluate changing agent creation keyword to agentic so agent can be used as a variable identifier

## Goal (one sentence)
Evaluate and implement changing (or aliasing) the agent-instantiation instruction from `agent <fn> [init_state]` to `agentic <fn> [init_state]` (and `agentic alive <ag>`) so that `agent` is freed up to be used as a normal variable/parameter identifier (`agent :: Agent In Out`) across user scopes and libraries.

## Plan
- [ ] Decide whether `agentic` replaces `agent` outright as the agent constructor keyword (`ag = agentic fn`, `ag = agentic fn init_state`) or whether `agent` is only treated as a keyword in prefix call position while remaining valid as a parameter/variable name (`fn :: ask (Agent a b) a => b` with parameter `agent`).
- [ ] Update `FR-COMP-009`, `src/main/ridgun/lib/parser.rg`, `analyzer.rg`, `typecheck.rg`, and `compiler.rg` to support `agentic` and allow `agent` as a variable name in function parameters, `let` bindings, and expressions (`send msg to agent`, `receive from agent`, `ask agent msg`, `stop agent`).
- [ ] Update `src/test/ridgun/test parallel and tensors.rg`, `/tmp/ridgun_agent_libraries_spec.md`, and book chapters (`docs/book/`).
- [ ] Re-verify 2-stage self-hosting fixed point (`ridgunc_stage2 == ridgunc_stage3`) and full test suite.
## Progress log (append-only, newest last)
- 2026-10-23: Documented future backlog task per user request.
## Files changed (keep current)
-
## Verification performed (command → result, newest last)
-
## Exact next actions
1. Confirm with the user whether `agentic` replaces `agent` completely or coexists while allowing `agent` as a variable identifier, then run `aix task start TASK-0020`.
## Decisions / open questions
- Should `agentic` completely replace `agent` as the constructor instruction (`agentic fn` / `agentic fn init_state`), or should `agentic` be the primary keyword with `agent` usable as any local variable/parameter identifier?
## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
