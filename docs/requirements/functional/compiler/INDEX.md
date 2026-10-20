# docs/requirements/functional/compiler/ — Compiler & Language Requirements (`COMP`)

| Path | What | Read when |
|---|---|---|
| `FR-COMP-001-parallel-and-sequential-higher-order-list-ops.md` | First-class function values and sequential (`map`, `filter`, `fold`) vs parallel (`||map`, `||filter`) higher-order list operations | Implementing higher-order functions and parallel list combinators in `ridgunc` |
| `FR-COMP-002-compiled-memory-management-cmm.md` | Ridgun Memory Management (RMM): `RMM1` (CMM Linear & Conditional) and `RMM2` (Assignment & Cascaded Structure Counting) | Implementing or modifying memory management and native codegen in `compiler.rg` |
| `FR-COMP-003-unified-equals-grammar-guards-parallel-pipes-and-mut.md` | Unified `=` block grammar (`(none)`, `|`, `||` without `where`) and explicit `mut x = ...` mutable variables | Modifying lexer, parser, formatter, typechecker, or `RMM2` variable reassignment |
