---
id: FR-COMP-017
title: Constructor Patterns inside Tuples and a Runtime Error when No Clause Matches (RG-114)
type: functional
domain: compiler
status: implemented
priority: must
created: 2026-11-07
updated: 2026-11-07
depends_on:
  - FR-COMP-005
verified_by: [TS-COMP-017]
---
# FR-COMP-017 — Constructor Patterns inside Tuples and a Runtime Error when No Clause Matches (RG-114)

## Statement
1. **Constructors inside tuple and cons patterns.** A constructor pattern, with or without arguments, SHALL match in any element of a tuple pattern and as the head of a cons pattern: `(End _, _)`, `(Ask n, _)`, `(k, Ask n)`, `(Ask a, Ask b)`, `(Ask n : rest)`. Each element is the constructor applied to the sub-patterns written up to the next `,`, `:` or `)`.
2. **No matching clause.** When a call matches none of a function's clauses (every pattern fails, or the guards of the last clause are all false and it has no `otherwise`), the program SHALL stop: it writes `runtime error: no clause of function '<name>' matches its arguments` to standard error and exits with status 1. It SHALL NOT return the zero value of the result type.

## Rationale
Before 0.9.34 the parser read `(End _, _)` as `End` with three arguments and left the arguments of a constructor in a later tuple element unparsed, so such patterns never matched. The call then fell through every clause and silently returned `0` (an empty `Conn`, HTTP status 0, in edtech). Solstice register RG-114.

## Acceptance Criteria
1. **AC-1**: The RG-114 reproduction prints `PAT picked end 1`; `(Ask n, _)`, `(k, Ask n)`, `(Ask a, Ask b)`, `(Stop, k)` and `(Ask n : _)` match as written (`tests/cases/adts/rg114_constructor_in_tuple_pattern.ridgun`).
2. **AC-2**: A call with no matching pattern, and a call where no guard holds and there is no `otherwise`, print the lines before it and exit with status 1 (`tests/cases/functions/rg114_no_clause_matches_exits_with_error.ridgun`, `tests/cases/guards/rg114_guards_without_otherwise_exit_with_error.ridgun`).
