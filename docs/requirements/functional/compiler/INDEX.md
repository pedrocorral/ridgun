# docs/requirements/functional/compiler/ — Compiler & Language Requirements (`COMP`)

| Path | What | Read when |
|---|---|---|
| `FR-COMP-001-parallel-and-sequential-higher-order-list-ops.md` | First-class function values and parallel (`map`, `filter`) vs sequential (`seq_map`, `seq_filter`, `fold`) higher-order list operations | Implementing higher-order functions and parallel list combinators in `ridgunc` |
| `FR-COMP-002-compiled-memory-management-cmm.md` | Compiled Memory Management (CMM) and Conditional Pointer-Identity Drop Guards (`ptr(a) != ptr(c)`) without GC or runtime `Arc` | Implementing or modifying memory management and native codegen in `compiler.rg` |
