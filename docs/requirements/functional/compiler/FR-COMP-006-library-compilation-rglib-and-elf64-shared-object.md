---
id: FR-COMP-006
title: Library Compilation (.ridgunlib Package Bundles) Without Requiring main
status: implemented
priority: must
created: 2026-10-21
updated: 2026-11-17
depends_on:
  - FR-COMP-004
  - FR-COMP-005
related:
  - ADR-0001
  - ADR-0010
  - ADR-0016
verified_by: []
---
# FR-COMP-006 — Library Compilation (`.ridgunlib` Package Bundles) Without Requiring `main`

> 2026-11-17 (ADR-0016): the Linux ELF64 `.so` output was removed; it could not be loaded and exported nothing. A library is its `.ridgunlib`.

## Statement
The `ridgunc` compiler (`src/main/ridgun/ridgunc/main.ridgun`, `src/main/ridgun/lib/compiler.ridgun`, `src/main/ridgun/lib/elf64.ridgun`) and the `stable` project manager (`src/main/ridgun/stable/main.ridgun`) SHALL support compiling Ridgun modules and projects as reusable libraries (in addition to standalone executables):

1. **Library Compilation Mode in `ridgunc` (`ridgunc build --lib <input.ridgun> [-o <out>]`)**:
   - `ridgunc build --lib <input.ridgun> [-o <output>]` SHALL compile a Ridgun module as a library without requiring a `fn :: main => ()` entry point.
   - During library compilation, call-graph reachability in `compiler.ridgun` SHALL treat **all top-level functions and operators (`fn ::`, `op ::`) and all type definitions (`type`, `expand type`)** in the module as public roots so that no exported library functions or record accessors are tree-shaken away.
   - Depending on the output path extension (or default when `-o` is omitted):
     - If `-o <path>.ridgunlib` (or default `<stem>.ridgunlib`): emits a pre-verified, self-contained **Ridgun Library Bundle (`.ridgunlib`)** header + resolved module source (with all internal `import` statements expanded and type-checked, plus exported symbol/type manifest comments `-- RIDGUNLIB1`, `-- EXPORT_FN:`, `-- EXPORT_TYPE:`).
     - If `-o <path>.so` (or `build --so`) for a Linux target: stops with a message that names ADR-0016 and writes nothing.
     - When `stable built lib` (or `stable build lib` / `project kind = "lib"` in `build.ridgun`) is executed, `stable` SHALL emit `target/<project_name>.ridgunlib`.

2. **Project Kind & Library Packaging in `build.ridgun` (`project kind`)**:
   - `build.ridgun` MAY declare `fn :: project kind => String` (or `project_kind`) returning `"lib"`, `"app"`, or `"both"` (default `"app"` when `src/main/ridgun/<target>/main.ridgun` exists, or `"lib"` when only `src/main/ridgun/lib/*.ridgun` exists).
   - `stable new --lib <name>` (or `stable new lib <name>`) SHALL scaffold a library project (`project kind = "lib"`, `src/main/ridgun/lib/<name>.ridgun`, `src/test/ridgun/test <name>.ridgun`).
   - `stable built lib` (or `stable built` when `project kind` is `"lib"` or `"both"`) SHALL bundle all modules in `src/main/ridgun/lib/*.ridgun` into `target/<name>.ridgunlib`.

3. **Importing `.ridgunlib` and Library Packages Across Projects**:
   - When a Ridgun source file writes `import <libname>`, module resolution SHALL search:
     1. `<current_dir>/<libname>.ridgun` and `src/main/ridgun/lib/<libname>.ridgun`
     2. `target/lib<libname>.ridgunlib` and `.stable/deps/*/target/lib<libname>.ridgunlib`
     3. `.stable/deps/*/src/main/ridgun/lib/<libname>.ridgun`
   - An import may name its package (`import pk.db.mod`), and a bare import found in two packages is an error: FR-COMP-028.
   - Importing a library exposes all of its `type`, `expand type`, `fn ::`, and `op ::` declarations to the consumer project so types can even be further extended via `expand type` (`FR-COMP-005`).

## Rationale
Applications such as web frameworks, database drivers, HTTP routers, and numeric/tensor toolkits must be distributable and compilable as libraries without a dummy `main` entrypoint, as Ridgun-native `.ridgunlib` bundles (preserving polymorphic types, `expand type`, and mixfix operators).

## Acceptance Criteria
1. **AC-1 (`ridgunc build --lib` Without `main`)**: A `.ridgun` module with no `main` function compiles cleanly via `ridgunc build --lib <file.ridgun> -o <out.ridgunlib>`, preserving all top-level functions and types without tree-shaking them away.
2. **AC-2 (No Linux shared object, ADR-0016)**: `ridgunc build --lib <file.ridgun> -o <out>` and `stable built lib` write no `.so`; `ridgunc build --so` for a Linux target ends with exit status 1.
3. **AC-3 (`stable built lib` & `project kind = "lib"`)**: Running `stable built lib` produces `target/<name>.ridgunlib`, and another Ridgun program can `import` and call functions/types from the compiled library.
4. **AC-4 (File names, ADR-0010)**: `ridgunc build --lib <file.ridgun>` without `-o` writes `<file>.ridgunlib`. Imports find a source file as `.ridgun`, then `.rg`, and a bundle as `.ridgunlib`, then `.rglib`, in each place they look. An import that names its file (`import "io.rglib"`) finds it under either name.
