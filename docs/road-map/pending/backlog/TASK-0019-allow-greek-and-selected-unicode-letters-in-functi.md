---
id: TASK-0019
title: Allow Greek and selected Unicode letters in function, operator, and variable identifiers
status: pending             # pending | going-on | blocked | completed
created: 2026-10-23
completed:
requirements: [FR-COMP-001, FR-COMP-005]
tests: [TS-COMP-001, TS-COMP-002]
security: []
context_files:
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test core language.rg
scope:
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test core language.rg
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0019 — Allow Greek and selected Unicode letters in function, operator, and variable identifiers

## Goal (one sentence)
Extend the Ridgun lexer, parser, typechecker, and codegen to allow Greek letters (`α..ω`, `Α..Ω`), Latin-extended letters (`á, é, í, ó, ú, ñ, ü`, etc.), and selected Unicode mathematical/scientific letters as part of function names (`fn ::`), mixfix operators (`op ::`), and variable identifiers.

## Plan
- [ ] Extend UTF-8 identifier scanning in `src/main/ridgun/lib/lexer.rg` (`is_ident_start`, `is_ident_char`) to accept multi-byte UTF-8 sequences for Greek (`U+0370..U+03FF`), Latin-1 Supplement / Latin Extended (`U+00C0..U+024F`), and selected Unicode letter/subscript blocks while distinguishing uppercase (`Α..Ω`, `Á..Ü`, constructor/type start) from lowercase (`α..ω`, `á..ü`, variable/function/operator start).
- [ ] Verify `parser.rg`, `typecheck.rg`, `formatter.rg`, and `compiler.rg` preserve UTF-8 identifier bytes cleanly across mixfix joining (`join_op_word`), `rodata` string tables, and symbol resolution.
- [ ] Add regression tests in `src/test/ridgun/test core language.rg` covering Greek and Unicode identifiers in variables (`α`, `θ`, `λ`, `Δx`), functions (`fn ::`), and mixfix operators (`op ::`).
- [ ] Re-verify 2-stage self-hosting fixed point (`ridgunc_stage2 == ridgunc_stage3`) and full test suite.
## Progress log (append-only, newest last)
- 2026-10-23: Documented future backlog task per user request.
## Files changed (keep current)
-
## Verification performed (command → result, newest last)
-
## Exact next actions
1. Start with `aix task start TASK-0019` when ready to implement.
## Decisions / open questions
- Define the exact whitelist of Unicode codepoint ranges allowed in lowercase vs uppercase identifiers versus operator-only symbols.
## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
