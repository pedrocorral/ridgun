# Ridgun AI Agent Harness (`v0.9.11`)

This directory (`/home/boogie/ridgun/harness/`) contains the self-contained **skills, scoped instructions, root agent guidelines, and runnable reference cheatsheet** needed for any AI coding agent (Antigravity/Gemini, Claude Code, Cursor, Codex, AIX, etc.) to understand, write, refactor, and verify **Ridgun (`.rg`)** code accurately on the first try.

---

## Contents of `harness/`

| File | Purpose | When an Agent Reads It |
|---|---|---|
| [`AGENTS.md`](AGENTS.md) | Root agent entry point & golden rules for Ridgun and `stable` (`v0.9.11`) | Session start |
| [`instructions/ridgun.md`](instructions/ridgun.md) | Compact scoped instruction (`applyTo: "**/*.rg,build.rg"`) covering syntax invariants, natural space-separated names (`FR-COMP-005`), unified space-separated tuple/sequence type signatures (`FR-COMP-008`), `=` / `\|` / `\|\|` / `\|.` / `\|\|.`, `mut`, `\|\|map` / `\|\|filter`, `with timeout`, PAL I/O primitives, and `RMM1`/`RMM2` | Automatically loaded whenever touching any `.rg` file or `build.rg` |
| [`instructions/stable.md`](instructions/stable.md) | Scoped instruction (`applyTo: "build.rg,plugins/**/*.rg,.stable/plugins/**/*.rg"`) covering `stable` project manifests (`build.rg`), `.rglib`/`.so` library builds, custom `fn :: task` commands, and `stable` plugins | Automatically loaded when touching `build.rg` or `plugins/*.rg` |
| [`skills/implement-code-ridgun/SKILL.md`](skills/implement-code-ridgun/SKILL.md) | Complete Ridgun implementation skill: LLM anti-pattern table ("Never Write This → Write This Instead"), full grammar, generics (`A`..`Z`), space-separated tuple/return signatures (`FR-COMP-008`), mixfix (`op ::`), `RMM1`/`RMM2` memory rules, complete built-in runtime table, and ELF64 `stable`/`ridgunc` CLI workflow | Before writing, refactoring, or reviewing any `.rg` code |
| [`skills/implement-code-ridgun/references/cheatsheet.rg`](skills/implement-code-ridgun/references/cheatsheet.rg) | Verified, canonical `.rg` source file demonstrating all major Ridgun `v0.9.11` constructs in tabular format (`./bin/ridgunc check` clean) | One-read syntax & alignment reference |
| [`skills/implement-stable-project/SKILL.md`](skills/implement-stable-project/SKILL.md) | Complete `stable` project manager, library builder (`--lib`, `.rglib`, `.so`), custom task (`fn :: task`), dependency (`stable deps`), and framework plugin (`plugins/*.rg`, `expand type StableCommand`) skill | Before scaffolding projects, editing `build.rg`, building libraries, or creating `stable` plugins |
| [`skills/implement-stable-project/references/build_cheatsheet.rg`](skills/implement-stable-project/references/build_cheatsheet.rg) | Verified `build.rg` reference showing metadata, `project kind`, `dependencies`, `plugins`, and custom single/multi-word `task` definitions | Reference when creating or editing `build.rg` |
| [`skills/implement-stable-project/references/plugin_cheatsheet.rg`](skills/implement-stable-project/references/plugin_cheatsheet.rg) | Verified `stable` plugin reference (`plugins/*.rg`) showing exported tasks, `expand type` command extensions, and executable plugin entrypoints | Reference when creating `stable` extensions or framework plugins |

---

## How to Install in Any Project or Agent Runtime

### 1. AIX / Antigravity / Gemini CLI / Claude Code
Copy the instructions and skills into your workspace's `.aix/` and `.agents/` directories (already synced in this repository):
```bash
cp harness/instructions/ridgun.md .aix/custom/instructions/languages/ridgun.md
cp harness/instructions/stable.md .aix/custom/instructions/tools/stable.md
cp -r harness/skills/implement-code-ridgun/* .aix/custom/skills/implement/code-ridgun/
cp -r harness/skills/implement-stable-project/* .aix/custom/skills/implement/stable-project/
```

### 2. Standalone Repository Setup
For a new Ridgun repository without AIX, copy `harness/AGENTS.md` to the repository root as `AGENTS.md` (or `CLAUDE.md` / `GEMINI.md`) and keep `harness/` at the root so agents can load `harness/instructions/ridgun.md`, `harness/instructions/stable.md`, `harness/skills/implement-code-ridgun/SKILL.md`, and `harness/skills/implement-stable-project/SKILL.md`.
