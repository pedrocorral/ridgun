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
related:
  - ADR-0001
  - ADR-0003
tests: []
---
# FR-TOOL-002 — Project scaffolding (`new` / `init`), dependency management (`deps` / `add`), and binary installation (`install`) in `stable`

## Statement
The `stable` project manager (`src/main/ridgun/stable/main.rg`) SHALL support full Ridgun project lifecycle management in 100% pure Ridgun:
1. **Project Scaffolding (`stable new <name>` and `stable init`)**:
   - `stable new <name>` SHALL create a new project directory `<name>/` containing a canonical `build.rg` (`project_name = "<name>"`, `project_version = "0.1.0"`, `dependencies = []`), `src/main/ridgun/<name>/main.rg`, `src/test/ridgun/test_main.rg`, and `.gitignore`.
   - `stable init` SHALL initialize those files in the current working directory if `build.rg` does not already exist.
2. **Dependency Management (`dependencies` in `build.rg`, `stable deps`, `stable add <dep>`)**:
   - `build.rg` MAY declare `fn :: dependencies => [String]` listing package names, each optionally with a version (`solstice`, `json`, `solstice@0.1.0`). omni installs them (ADR-0003).
   - `stable` SHALL reject an entry that is a path or a URL: one containing `/`, `\` or `:`, or starting with `.` or `~`. It SHALL NOT download anything, and SHALL NOT run git.
   - `stable deps` SHALL resolve each name through the project's `omni.lock`:
     - A library's artifact is an `.rglib` file, which SHALL exist.
     - A package's artifact is a folder, which `stable` SHALL synchronize into `.stable/deps/<name>/`, copying its `.rglib` bundles into `.stable/deps/`.
   - `stable deps` SHALL fail, naming `omni install <name>`, when a name is not in `omni.lock` or its artifact is missing.
   - `stable deps` SHALL fail, naming `omni install <name>@<version>`, when the requested version differs from the locked one.
   - `stable deps` SHALL fail when the lock entry is a local one (version `local`).
   - `stable add <name>` SHALL append `<name>` to `dependencies` in `build.rg` and synchronize it under the same rules.
   - `load_rg_source` in `src/main/ridgun/lib/parser.rg` SHALL also search `.stable/deps/*/src/main/ridgun/lib/<mod>.rg` and `.stable/deps/*/<mod>.rg` when resolving `import <mod>`.
3. **Binary Installation (`stable install [target]`)**:
   - `stable install [target]` SHALL compile the project's native ELF64 executable(s) and install them with executable permissions (`0755`) into `~/.local/bin/` (and `bin/`).

## Rationale
Providing `new`, `init`, `deps`, `add`, and `install` directly inside `stable` completes Ridgun's self-hosted developer experience without external package managers.

## Acceptance Criteria
- AC1: `stable new <dir>` creates a valid Ridgun project that passes `stable check` and `stable test`.
- AC2: `stable deps` and `stable add` manage `.stable/deps/` from package names locked in `omni.lock`, and `import` resolution searches `.stable/deps/`.
- AC4: `stable deps` rejects a path, a URL, a local lock entry and a name missing from `omni.lock`, and never runs git.
- AC3: `stable install` builds and installs native ELF64 binaries into `~/.local/bin/`.
