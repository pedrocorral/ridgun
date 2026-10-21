---
id: FR-TOOL-002
title: Project scaffolding (new/init), dependency management (deps/add), and binary installation (install) in stable
type: functional
status: implemented
priority: must
domain: TOOL
depends_on:
  - FR-TOOL-001
  - FR-COMP-004
related: []
tests: []
---
# FR-TOOL-002 — Project scaffolding (`new` / `init`), dependency management (`deps` / `add`), and binary installation (`install`) in `stable`

## Statement
The `stable` project manager (`src/main/ridgun/stable/main.rg`) SHALL support full Ridgun project lifecycle management in 100% pure Ridgun:
1. **Project Scaffolding (`stable new <name>` and `stable init`)**:
   - `stable new <name>` SHALL create a new project directory `<name>/` containing a canonical `build.rg` (`project_name = "<name>"`, `project_version = "0.1.0"`, `dependencies = []`), `src/main/ridgun/<name>/main.rg`, `src/test/ridgun/test_main.rg`, and `.gitignore`.
   - `stable init` SHALL initialize those files in the current working directory if `build.rg` does not already exist.
2. **Dependency Management (`dependencies` in `build.rg`, `stable deps`, `stable add <dep>`)**:
   - `build.rg` MAY declare `fn :: dependencies => [String]` listing Git repository URLs or local paths.
   - `stable add <dep>` SHALL append `<dep>` to `dependencies` in `build.rg` and sync it into `.stable/deps/`.
   - `stable deps` SHALL synchronize all declared dependencies into `.stable/deps/` (via `git clone` for remote URLs or `cp -r` for local paths).
   - `load_rg_source` in `src/main/ridgun/lib/parser.rg` SHALL also search `.stable/deps/*/src/main/ridgun/lib/<mod>.rg` and `.stable/deps/*/<mod>.rg` when resolving `import <mod>`.
3. **Binary Installation (`stable install [target]`)**:
   - `stable install [target]` SHALL compile the project's native ELF64 executable(s) and install them with executable permissions (`0755`) into `~/.local/bin/` (and `bin/`).

## Rationale
Providing `new`, `init`, `deps`, `add`, and `install` directly inside `stable` completes Ridgun's self-hosted developer experience without external package managers.

## Acceptance Criteria
- AC1: `stable new <dir>` creates a valid Ridgun project that passes `stable check` and `stable test`.
- AC2: `stable deps` and `stable add` manage `.stable/deps/` and `import` resolution searches `.stable/deps/`.
- AC3: `stable install` builds and installs native ELF64 binaries into `~/.local/bin/`.
