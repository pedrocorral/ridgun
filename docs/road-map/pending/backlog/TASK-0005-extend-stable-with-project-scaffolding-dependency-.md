---
id: TASK-0005
title: Extend stable with project scaffolding, dependency management, and binary installation
status: pending             # pending | going-on | blocked | completed
created: 2026-10-17
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [src/main/ridgun/stable.rg, build.rg, src/main/ridgun/compiler.rg]
scope: [src/main/ridgun/stable.rg, build.rg, src/main/ridgun/compiler.rg]
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0005 — Extend `stable` with project scaffolding, dependency management, and binary installation

## Goal (one sentence)
Extend `stable` (`src/main/ridgun/stable.rg`) so it manages the entire Ridgun project lifecycle, including project scaffolding (`new` / `init`), library dependency resolution (`dependencies` in `build.rg`, `deps`, `add`), and binary installation (`install`).

## Plan
- [ ] Align module/package resolution design and `import` search path rules (blocked on upstream architectural decision).
- [ ] Add `new <name>` and `init` commands to `stable.rg` to scaffold `build.rg` (`0.1.0`), `src/main/ridgun/main.rg`, `src/test/ridgun/test_main.rg`, and `.gitignore`.
- [ ] Extend `build.rg` AST loader in `stable.rg` to parse `dependencies` (Git repositories and local paths) and add `deps` / `add` commands to sync dependencies into `.stable/deps/`.
- [ ] Update module resolution in `compiler.rg` and `stable.rg` to resolve `import` statements across project sources and `.stable/deps/`.
- [ ] Add `install` command to `stable.rg` to build and install native Ridgun executables into `~/.local/bin/` or `bin/`.

## Progress log (append-only, newest last)
- 2026-10-17: Created backlog task; waiting on core architectural decision before implementation.
## Files changed (keep current)
-
## Verification performed (command → result, newest last)
-
## Exact next actions
1. Decide the foundational architectural question with the user before implementing `TASK-0005`.
## Decisions / open questions
- Pending foundational decision from user that affects how modules/packages and `stable` interact.
## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
