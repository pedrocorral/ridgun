---
id: FR-COMP-006
title: Library Compilation (.rglib Package Bundles and ELF64 Shared Objects .so) Without Requiring main
status: implemented
priority: must
created: 2026-10-21
updated: 2026-10-21
depends_on:
  - FR-COMP-004
  - FR-COMP-005
related:
  - ADR-0001
verified_by: []
---
# FR-COMP-006 — Library Compilation (`.rglib` Package Bundles and ELF64 Shared Objects `.so`) Without Requiring `main`

## Statement
The `ridgunc` compiler (`src/main/ridgun/ridgunc/main.rg`, `src/main/ridgun/lib/compiler.rg`, `src/main/ridgun/lib/elf64.rg`) and the `stable` project manager (`src/main/ridgun/stable/main.rg`) SHALL support compiling Ridgun modules and projects as reusable libraries (in addition to standalone executables):

1. **Library Compilation Mode in `ridgunc` (`ridgunc build --lib <input.rg> [-o <out>]`)**:
   - `ridgunc build --lib <input.rg> [-o <output>]` SHALL compile a Ridgun module as a library without requiring a `fn :: main => ()` entry point.
   - During library compilation, call-graph reachability in `compiler.rg` SHALL treat **all top-level functions and operators (`fn ::`, `op ::`) and all type definitions (`type`, `expand type`)** in the module as public roots so that no exported library functions or record accessors are tree-shaken away.
   - Depending on the output path extension (or default when `-o` is omitted):
     - If `-o <path>.rglib` (or default `<stem>.rglib`): emits a pre-verified, self-contained **Ridgun Library Bundle (`.rglib`)** header + resolved module source (with all internal `import` statements expanded and type-checked, plus exported symbol/type manifest comments `-- RGLIB1`, `-- EXPORT_FN:`, `-- EXPORT_TYPE:`).
     - If `-o <path>.so`: emits a native **Linux ELF64 Shared Object (`ET_DYN = 3`, `x86_64` or `ARM64`)** containing the compiled machine code of all library functions.
     - When `stable built lib` (or `stable build lib` / `project kind = "lib"` in `build.rg`) is executed, `stable` SHALL emit **both** `target/lib<project_name>.rglib` and `target/lib<project_name>.so`.

2. **Project Kind & Library Packaging in `build.rg` (`project kind`)**:
   - `build.rg` MAY declare `fn :: project kind => String` (or `project_kind`) returning `"lib"`, `"app"`, or `"both"` (default `"app"` when `src/main/ridgun/<target>/main.rg` exists, or `"lib"` when only `src/main/ridgun/lib/*.rg` exists).
   - `stable new --lib <name>` (or `stable new lib <name>`) SHALL scaffold a library project (`project kind = "lib"`, `src/main/ridgun/lib/<name>.rg`, `src/test/ridgun/test <name>.rg`).
   - `stable built lib` (or `stable built` when `project kind` is `"lib"` or `"both"`) SHALL bundle all modules in `src/main/ridgun/lib/*.rg` into `target/lib<name>.rglib` and compile `target/lib<name>.so`.

3. **Importing `.rglib` and Library Packages Across Projects**:
   - When a Ridgun source file writes `import <libname>`, module resolution SHALL search:
     1. `<current_dir>/<libname>.rg` and `src/main/ridgun/lib/<libname>.rg`
     2. `target/lib<libname>.rglib` and `.stable/deps/*/target/lib<libname>.rglib`
     3. `.stable/deps/*/src/main/ridgun/lib/<libname>.rg`
   - Importing a library exposes all of its `type`, `expand type`, `fn ::`, and `op ::` declarations to the consumer project so types can even be further extended via `expand type` (`FR-COMP-005`).

## Rationale
Applications such as web frameworks, database drivers, HTTP routers, and numeric/tensor toolkits must be distributable and compilable as libraries without a dummy `main` entrypoint, both as Ridgun-native `.rglib` bundles (preserving polymorphic types, `expand type`, and mixfix operators) and as native ELF64 `ET_DYN` shared objects (`.so`).

## Acceptance Criteria
1. **AC-1 (`ridgunc build --lib` Without `main`)**: A `.rg` module with no `main` function compiles cleanly via `ridgunc build --lib <file.rg> -o <out.rglib>` and `ridgunc build --lib <file.rg> -o <out.so>`, preserving all top-level functions and types without tree-shaking them away.
2. **AC-2 (`ELF64 ET_DYN` Shared Object `.so`)**: Emitted `.so` binaries have ELF header `e_type == 3` (`ET_DYN`) and contain the compiled native code for all library functions.
3. **AC-3 (`stable built lib` & `project kind = "lib"`)**: Running `stable built lib` produces `target/lib<name>.rglib` and `target/lib<name>.so`, and another Ridgun program can `import` and call functions/types from the compiled library.
