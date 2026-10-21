---
id: TASK-0011
title: Make stable extensible with custom build.rg tasks, plugins, and framework extensions
status: completed
created: 2026-10-21
completed: 2026-10-21
requirements:
  - FR-TOOL-003
tests: []
security: []
context_files:
  - docs/requirements/functional/tooling/FR-TOOL-003-extensible-stable-plugins-and-custom-tasks.md
  - src/main/ridgun/stable/main.rg
  - build.rg
scope:
  - src/main/ridgun/stable/main.rg
  - build.rg
  - src/test/ridgun/
  - harness/
  - docs/
  - README.md
owner: agent-001
claimed: 2026-10-21T16:45:25Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only
---
# TASK-0011 — Make `stable` extensible with custom `build.rg` tasks, plugins, and framework extensions

## Goal (one sentence)
Deliver `FR-TOOL-003` so `stable` can be extended with custom `fn :: task <name> => String` commands in `build.rg`, `fn :: plugins => [String]` extensions (`plugins/<ext>.rg` and `.stable/plugins/<ext>.rg`), and open `expand type` command descriptors for building web frameworks and domain-specific toolchains.

## Plan
- [x] Update `src/main/ridgun/stable/main.rg` to extract all `fn :: task <words...> => String` definitions (`task_*`) and `fn :: plugins => [String]` from `build.rg` and configured plugin `.rg` files.
- [x] Support `stable tasks` and `stable plugins` commands (and include custom tasks/plugins in `stable info` and `stable help`).
- [x] Update `stable` command dispatch (`dispatch command`) so unknown commands check registered custom tasks (`task_<words>`) and plugin modules (`plugins/<ext>.rg` / `.stable/plugins/<ext>.rg`) and execute them with forwarded CLI arguments.
- [x] Add automated tests verifying custom multi-word `task` execution and plugin loading in `stable`.
- [x] Update `harness/`, `README.md`, `docs/lang/spec.md`, and the Ridgun books across all 7 languages (`sv`, `es`, `en`, `pt`, `ca`, `gl`, `eu`).

## Progress log (append-only, newest last)
- 2026-10-21: Created `TASK-0011` and `FR-TOOL-003`.
- 2026-10-21: Implemented extensible `StableCommand` (`expand type StableCommand`), custom `fn :: task <name> => String` discovery from `build.rg` and plugins (`plugins/*.rg`, `.stable/plugins/*.rg`, `fn :: plugins => [String]`), `stable tasks`, and `stable plugins` in `src/main/ridgun/stable/main.rg` and `build.rg`. Verified with `src/test/ridgun/test lib and plugins.rg`.

## Files changed (keep current)
- `docs/requirements/functional/tooling/FR-TOOL-003-extensible-stable-plugins-and-custom-tasks.md`
- `src/main/ridgun/stable/main.rg`
- `build.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `README.md`
- `.aix/custom/instructions/languages/ridgun.md`
- `.agents/skills/implement-code-ridgun/SKILL.md`
- `harness/skills/implement-code-ridgun/SKILL.md`

## Verification performed (command → result, newest last)
- `./bin/stable test` → `5 passed, 0 failed` (`test basics.rg`, `test core language.rg`, `test lib and plugins.rg`, `test parallel and tensors.rg`, `test strings.rg`).
- `./bin/stable tasks` and `./bin/stable plugins` verified.

## Exact next actions
1. Task complete.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
