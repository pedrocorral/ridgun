---
id: FR-COMP-005
title: Shared ADT Constructor Names Across Types, Open Type Extensions (expand type), and Automatic Function Clause Merging
status: implemented
priority: must
created: 2026-10-21
updated: 2026-10-21
depends_on:
  - FR-COMP-003
  - FR-COMP-004
verified_by: []
---
# FR-COMP-005 — Shared ADT Constructor Names Across Types, Open Type Extensions (`expand type`), and Automatic Function Clause Merging

## Statement
The Ridgun language and `ridgunc` compiler SHALL support constructor name reuse across distinct `type` declarations, open type extension via `expand type`, and automatic clause merging for `fn ::` / `op ::` declarations:
1. **Shared Constructor Names Across Multiple `type` Structures**:
   - Multiple `type` declarations MAY define sum variants with the same constructor name (such as `Error`, `Var`, `Lit`, `None`, `Empty`), even with different payload types or arities:
     ```ridgun
     type ParseResult = Ok Int   | Error String
     type DbResult    = Rows Int | Error Int String
     type Expr        = Var String | Lit Int
     type Pattern     = Var String | Lit Int | Wild
     ```
   - Pattern matching and constructor calls SHALL resolve shared constructor names using the expected column type from the enclosing `fn ::` or `op ::` signature (and also allow optional `TypeName.CtorName` qualification).
2. **Open Type Extensions (`expand type`)**:
   - `expand type UpperName = ...` SHALL extend an existing sum ADT (`type UpperName = ...`) with additional variant constructors, or extend an existing product record (`type UpperName = field: Type, ...`) with additional fields:
     ```ridgun
     type Error = IoError String | Timeout Int
     expand type Error = AuthError String | DbError Int String

     type ServerConfig = host: String, port: Int
     expand type ServerConfig = tls: Bool, max_conns: Int
     ```
   - `expand` SHALL be a contextual keyword before `type` at top level so existing identifiers named `expand` remain valid.
3. **Automatic `fn ::` / `op ::` Clause Merging (Without `expand fn`)**:
   - Declaring additional clauses for an existing function or operator via standard `fn ::` / `op ::` syntax SHALL merge the new clauses into the function definition:
     ```ridgun
     fn :: format_err Error         => String
           format_err (IoError msg) =  "IO: {msg}"
           format_err (Timeout ms)  =  "Timeout: {ms}ms"
           format_err _             =  "Unknown error"

     fn :: format_err Error                => String
           format_err (AuthError user)     =  "Auth denied: {user}"
           format_err (DbError   code msg) =  "DB [{code}]: {msg}"
     ```
   - When merging clauses, specific pattern clauses (matching a constructor, literal, cons cell, or tuple) SHALL be ordered ahead of catch-all wildcard/variable clauses (`_` or bare variable) from the earlier declaration so extended variants are matched before default fallbacks.
4. **Type-Name Variants Without Redundant Constructor Names (`type Something = String | Int | MyStruct Real Int`)**:
   - In `type` and `expand type` sum declarations, a variant whose name is a built-in type (`String`, `Int`, `Real`/`Float`, `Bool`, `Char`) or another declared `type` / record with no extra type arguments after it SHALL represent a direct member of that type without requiring a duplicate constructor name (such as `Int Int` or `String String`):
     ```ridgun
     type Something = String | Int | MyStruct Real Int
     expand type Something = Bool
     ```
   - Values of a type-name variant MAY be passed either directly as bare values (`describe "hello"`, `describe 42`, `describe True`) or via explicit type-constructor application (`describe (String "hello")`, `describe (Int 42)`), and pattern matching SHALL support both literal patterns (`describe "admin"`, `describe 0`) and typed patterns (`describe (String s)`, `describe (Int n)`, `describe (Bool b)`).

## Rationale
- Allowing constructor names like `Error`, `Var`, `Lit`, and `Empty` to be reused across types eliminates artificial Hungarian prefixes (`PatVar`, `EVar`, `TyVar`) and leverages Ridgun's mandatory tabular type signatures for type-directed disambiguation.
- Allowing bare type names (`String | Int | MyStruct Real Int`) inside `type` and `expand type` avoids redundant `Int Int` / `String String` declarations and lets callers pass `"hello"` or `42` directly without boilerplate wrapper calls.
- Supporting `expand type` together with standard `fn ::` clause merging solves the Expression Problem cleanly without introducing redundant `expand fn` keywords.

## Acceptance Criteria
1. **AC-1 (Shared Constructors)**: Two or more `type` definitions sharing constructor names (`Error`, `Var`, `Lit`) typecheck, pattern-match, and execute without collision.
2. **AC-2 (`expand type` for ADTs and Records)**: `expand type` adds new constructors to sum ADTs and new fields (with accessors and `with` updates) to product records.
3. **AC-3 (Automatic `fn ::` Clause Merging)**: Subsequent `fn ::` declarations for the same function merge their clauses ahead of base catch-all `_` clauses.
4. **AC-4 (Type-Name Variants)**: `type Something = String | Int | MyStruct Real Int` accepts bare `"hello"` / `42` as well as `String "hello"` / `Int 42`, and matches both literal patterns and `(String s)` / `(Int n)` patterns at runtime.
