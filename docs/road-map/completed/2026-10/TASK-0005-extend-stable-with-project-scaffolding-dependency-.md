---
id: TASK-0005
title: Extend stable with project scaffolding, dependency management, and binary installation
status: completed
created: 2026-10-17
completed: 2026-10-21
requirements: [FR-TOOL-002]
tests: []
security: []
context_files: [src/main/ridgun/stable/main.rg, build.rg, src/main/ridgun/lib/compiler.rg]
scope: [src/main/ridgun/stable/main.rg, build.rg, src/main/ridgun/lib/compiler.rg]
owner: agent-001
claimed: 2026-10-21T10:10:01Z
claimed_by: agent gemini@solarfall
policy: anarchy
---
# TASK-0005 — Extend `stable` with project scaffolding, dependency management, and binary installation

## Goal (one sentence)
Extend `stable` (`src/main/ridgun/stable/main.rg`) so it manages the entire Ridgun project lifecycle, including project scaffolding (`new` / `init`), library dependency resolution (`dependencies` in `build.rg`, `deps`, `add`), and binary installation (`install`).

## Plan
- [x] Align module/package resolution design and `import` search path rules.
- [x] Add `new <name>` and `init` commands to `stable/main.rg` to scaffold `build.rg` (`0.1.0`), `src/main/ridgun/<name>/main.rg`, `src/test/ridgun/test_main.rg`, and `.gitignore`.
- [x] Extend `build.rg` AST loader in `stable/main.rg` to parse `dependencies` (Git repositories and local paths) and add `deps` / `add` commands to sync dependencies into `.stable/deps/`.
- [x] Update module synchronization in `stable/main.rg` so imported dependency `.rg` modules are linked into `src/main/ridgun/lib/`.
- [x] Add `install` command to `stable/main.rg` to build and install native Ridgun ELF64 executables into `~/.local/bin/` and `bin/`.

## Progress log (append-only, newest last)
- 2026-10-17: Created backlog task; waiting on core architectural decision before implementation.
- 2026-10-21: Implemented `new`, `init`, `deps`, `add`, and `install` in `src/main/ridgun/stable/main.rg` (`FR-TOOL-002`) and expanded the AArch64 runtime kernel in `src/main/ridgun/lib/arm64.rg` (`FR-COMP-004`).
## Files changed (keep current)
- `src/main/ridgun/stable/main.rg`
- `src/main/ridgun/lib/arm64.rg`
- `docs/requirements/functional/tooling/FR-TOOL-002-project-scaffolding-dependencies-and-install.md`
- `docs/requirements/functional/tooling/INDEX.md`
## Verification performed (command → result, newest last)
- `./target/stable format && ./target/stable check` → 13 modules checked, 0 errors.
- `./target/stable built` → rebuilt `target/ridgunc` and `target/stable`.
## Exact next actions
1. Task complete.
## Decisions / open questions
- Resolved: `stable deps` / `stable add` syncs repositories into `.stable/deps/<name>` and copies shared `.rg` modules into `src/main/ridgun/lib/`.
## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
