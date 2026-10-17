# Agent Preferences

Preferences and guidelines for AI agents working on the Ridgun project.

---

## Command Execution

- **NO excessive waiting time.** When running terminal commands, use short synchronous waits (`WaitMsBeforeAsync` of 5000ms or less). Commands should return as soon as they finish — never block with long async polling loops.
- If a command completes within the sync window, read the output immediately.
- If a command goes to background, check status with `WaitDurationSeconds: 0` — do not set large wait durations.

## Syntax Highlighting (`editors/vscode/`)

- **Always validate JSON** after editing `ridgun.tmLanguage.json`, `package.json`, or `language-configuration.json`. Run: `python3 -c "import json; json.load(open('<file>'))"` after every edit.
- A broken grammar file can crash or silently disable highlighting in the IDE — never skip validation.

## Documentation

- **Every change must be documented.** Any change to the language (syntax, types, operators, keywords), functionality, or features must be properly documented **before or alongside** the implementation. Never leave a feature undocumented.
- Update all relevant files: `doc/lang/spec.md`, `doc/lang/samples.rg`, syntax highlighting grammar, and README as needed.

## Git Commits

- Always write commit messages in **English**.
- Always use `user.name = "Pedro Corral"` and `user.email = "pedro@obdin.com"` when creating git commits.

