---
id: TASK-0027
title: Add gedit and GNOME Text Editor support (ridgun.lang, formatter tool, and installer) in editors/gedit/
status: completed
created: 2026-10-25
completed: 2026-10-25
requirements:
  - FR-TOOL-001
tests: []
security: []
context_files:
  - docs/requirements/functional/tooling/FR-TOOL-001-canonical-source-code-formatting.md
  - editors/gedit/ridgun.lang
  - editors/gedit/ridgun-format
  - editors/gedit/install.sh
  - editors/gedit/README.md
scope:
  - editors/gedit/**
owner: agent-001
claimed: 2026-10-25T14:31:57Z
claimed_by: agent gemini@solarfall
---
# TASK-0027 — Add gedit and GNOME Text Editor support in `editors/gedit/`

## Goal (one sentence)
Provide GtkSourceView syntax highlighting (`ridgun.lang`), an External Tools formatting script (`ridgun-format`) backed by `stable format` (`FR-TOOL-001`), and an installer script (`install.sh`) under `editors/gedit/`.

## Plan
- [x] Create `editors/gedit/ridgun.lang` for GtkSourceView 3/4/5 (`gedit` and `gnome-text-editor`).
- [x] Create `editors/gedit/ridgun-format` for `gedit` External Tools (`Ctrl+Alt+F`) and CLI usage.
- [x] Create `editors/gedit/install.sh` and `editors/gedit/README.md`, and verify formatting output.

## Progress log (append-only, newest last)
- 2026-10-25: Created `ridgun.lang`, `ridgun-format`, `install.sh`, and `README.md` under `editors/gedit/`, installed them locally, and verified `ridgun-format` via stdin and XML validation.

## Files changed (keep current)
- `editors/gedit/ridgun.lang`
- `editors/gedit/ridgun-format`
- `editors/gedit/install.sh`
- `editors/gedit/README.md`

## Verification performed (command → result, newest last)
- `./editors/gedit/install.sh` → installed `ridgun.lang` and `ridgun-format`
- `printf 'fn :: add Int Int => Int\nadd x y = x + y\nadd 0 y = y\n' | ./editors/gedit/ridgun-format` → aligned output

## Exact next actions
1. Mark `TASK-0027` done.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
