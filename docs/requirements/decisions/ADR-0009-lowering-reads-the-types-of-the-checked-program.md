---
id: ADR-0009
title: The lowering reads the types of the checked program; no fact strings, no run-time shape guesses
status: proposed
date: 2026-11-12
supersedes: []
affects: [FR-COMP-001, FR-COMP-009, FR-COMP-020, FR-COMP-022, src/main/ridgun/lib/typecheck.rg, src/main/ridgun/lib/compiler.rg, src/main/ridgun/lib/ast.rg]
---
# ADR-0009 — The lowering reads the types of the checked program

## Context
The type checker computes a type for every expression and then throws it away. The lowering (`compiler.rg`) works on the untyped AST. When it needs a type, it does one of three things:

1. It reads a **fact string** that the checker smuggles out as a fake type error, `TypeError ":tensor-elem:" "fn|key|kind"`. Lowering then looks the string up per function.
2. It reads a **mark** that a name-prefixed key stores in an integer map (`":stform:k:name"`, `"#g f"`, `"#fa f k"`…). These are derived from signature *strings*.
3. It **guesses at run time** from the value's shape, for example "is this a 2-tuple?". The guess fails because, at run time, a list of n elements also matches an n-tuple.

Each of the 2026-11-11/12 reports was patched in one of these three ways:
- RG-115, twice;
- a function value that got the head of its list argument;
- a record field read at another record's position (1.0.8).

The patches are correct, but every new case adds another key format. Each patch also fixes only the cases its author thought of.

## Options considered
1. **Keep patching.** Fast per report. The fact channel and the marks grow with every case, and run-time guesses stay wrong whenever shapes coincide.
2. **Typed lowering.** The checker returns the program with a type on every expression and pattern, and the lowering reads those types. This is one change to the interface between `typecheck.rg` and `compiler.rg`, plus a rewrite of the places listed below.
3. **Tag every run-time value fully** (tuples apart from lists, records by type). This fixes the guesses but not the fact channel, and it costs memory and time on every value.

## Decision
Option 2. Ship it in the first version after the current stability fixes. Until then, new reports are still fixed as patches, and every patch is added to the inventory below so that the typed lowering removes it.

The typed program SHALL give the lowering, for each expression, its resolved type: type variables instantiated where the checker knows them, and lambdas with their inferred types. The lowering SHALL decide from that type alone in every case below, and SHALL report an internal error when a type it needs is missing, never guess.

## Inventory: patches the typed lowering replaces
| Mechanism | Where | Replaced by |
|---|---|---|
| Fact strings `:tensor-elem:` (tensor element kinds, `Tensor[U8]` facts, string `+` facts, message copy facts, show facts) | `typecheck.rg` (`tensor elem info`, `with u8 call fact`, `str add fact`, `with msg copy facts`, `with show tensor facts`, `param tensor infos`); `compiler.rg` (`fn tensor elems`, `env tensor kind`) | The element type of the expression's tensor type |
| Tensor kind `"U"` and its run-time check `NIsList` / `NIsGen` | `compiler.rg` | A static element type; `"U"` disappears |
| Agent step form from signature strings, `:stform:k:name` | `compiler.rg` (`add step form marks`, `step form of`, `type key`) | The step's function type |
| Agent step form of a lambda or function value, `:agstep:` + `:lamret:` (1.0.7) | `typecheck.rg` (`with agent step fact`, `lambda ret binds`); `compiler.rg` (`typed step mode`) | The step's function type; lambdas get real inferred signatures |
| Agent mode 2: the run-time guess of the step's result shape | `compiler.rg` (agent send, receive, try receive) | Removed: mode 7 or 8 is always known |
| Record field position: one global name → position map; fields at different positions dispatched by constructor at run time, `#fa`/`#fo`/`#fl`/`#fn` keys (1.0.8) | `compiler.rg` (`add field alts`, `lower field alt`) | The record type of the argument gives the position |
| Field accessor used as a value is typed as the last record that has the field | `typecheck.rg` (field binds) | The accessor's type at the use site |
| Closure call convention: function values are name strings, closures are `(name, captures)` 2-tuples tested with `NMatchTuple`; closure rest marked with `__rg_rest__` (1.0.7) | `compiler.rg` (`emit indirect1/2 call`, `build call2 dispatch instrs`, `rest tag off`) | The call site knows whether the callee is a closure and its arity: no shape test, no marker |
| `__unpack2__`: deciding at lowering time whether a single argument is a tuple to unpack | `compiler.rg` (`prep call`) | The argument's tuple type |
| Name-prefixed marks in the arity map (`#g` getter, `#u` unit return, `#b` borrow mask) | `compiler.rg` | Typed function entries (borrow masks stay an analysis result, kept in a typed table) |

## Consequences
- **Requirements to update:** FR-COMP-009 §1–§2 (no run-time rule for the step form), FR-COMP-020 (no `"U"` kind), FR-COMP-001 (field accessors and function values by type).
- **Tests to update:** none should change their expected output. The suite and the unit tests are the acceptance test: every patch's case stays green after its mechanism is removed.
- **Code to update:**
  - `ast.rg`: a typed expression form, or a type table keyed by expression.
  - `typecheck.rg`: return the typed program instead of fact strings.
  - `compiler.rg`: read types; delete the mechanisms in the inventory.
  - The backends do not change. The run-time ambiguity between tuples and lists stays, but nothing reads it any more.
- **Rule until then:** a fix that adds a fact string, a mark or a run-time shape test is a patch. It is listed in this inventory in the same commit.
