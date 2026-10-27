# road-map/completed/2026-10/
Tasks completed this month, newest last.

| Task | Title | Requirements |
|---|---|---|
| `TASK-0009-adopt-natural-spaces-instead-of-underscores-in-fn-.md` | Adopt natural spaces instead of underscores in `fn ::`, built-in calls, `build.rg`, and `.rg` filenames | `FR-COMP-005` |
| `TASK-0010-compile-ridgun-modules-and-projects-as-reusable-li.md` | Compile Ridgun modules and projects as reusable libraries (`.rglib` and ELF64 `.so`) | `FR-COMP-006` |
| `TASK-0011-make-stable-extensible-with-custom-build-rg-tasks-.md` | Make `stable` extensible with custom `build.rg` tasks, plugins, and framework extensions | `FR-TOOL-003` |
| `TASK-0012-implement-low-level-linux-fd-poll-syscall-primitiv.md` | Implement cross-platform PAL I/O, polling, process & syscall primitives and declarative `with timeout` blocks | `FR-COMP-007` |
| `TASK-0014-refactor-stable-to-consume-standard-libraries-str-.md` | Refactor `stable` to consume standard libraries (`str`, `posix`, `io`, `list`, `cli`) from `ridgun-libs` | `FR-TOOL-002`, `FR-TOOL-003`, `FR-COMP-006` |
| `TASK-0022-implement-first-class-typed-tensor-subscript-views.md` | Implement first-class typed `Tensor[...]`, subscript views, `map f in m_(i,)`, and native bitwise operations | `FR-COMP-010`, `ADR-0001` |
| `TASK-0025-fix-acceptance-suite-issues-rg-081-rg-085-rg-087-r.md` | Fix acceptance suite issues (`RG-081`, `RG-085`, `RG-087`, `RG-089`, `RG-090`) and add `sys_pipe` / `sys_waitpid` PAL built-ins | `FR-COMP-007`, `FR-COMP-009`, `FR-VM-001` |
| `TASK-0030-module-namespaces-qualified-types-constructors-fun.md` | Module Namespaces, Qualified Types/Constructors/Functions, and Aliased Imports (`FR-COMP-012`) | `FR-COMP-005`, `FR-COMP-006`, `FR-COMP-012` |
| `TASK-0032-canonicalize-lambda-syntax-to-x-expr-and-a-b-expr.md` | Canonicalize lambda syntax to `(x => expr)` and `(a b => expr)` | `FR-COMP-013` |
| `TASK-0033-fix-rg-093-blocking-agent-waits-rg-094-argon2id-ll.md` | Fix `RG-093` blocking agent waits, `RG-094` Argon2id LLVM `opt -O2`, and `RG-095` multi-file module namespaces | `FR-COMP-009`, `FR-COMP-012` |
| `TASK-0034-enforce-strict-per-module-import-visibility-each-m.md` | Enforce strict per-module import visibility (each module sees only its own names and its explicit imports) | `FR-COMP-012` |
| `TASK-0035-implement-idiomatic-ridgun-pipeline-chaining-infix.md` | Implement idiomatic Ridgun pipeline chaining (`->`, infix start, `-> (+ _ _ +) ->`, `-> ()`, and `_ =` removal) across compiler, books, and skills | `FR-COMP-014` |
