# Ridgun AI Agent Harness (`v0.9.30`)

This directory (`/home/boogie/ridgun/harness/`) contains the self-contained **skills, scoped instructions, root agent guidelines, and runnable reference cheatsheet** needed for any AI coding agent (Antigravity/Gemini, Claude Code, Cursor, Codex, AIX, etc.) to understand, write, refactor, and verify **Ridgun (`.ridgun`)** code accurately on the first try.

---

## Contents of `harness/`

| File | Purpose | When an Agent Reads It |
|---|---|---|
| [`AGENTS.md`](AGENTS.md) | Root agent entry point & golden rules for Ridgun and `stable` (`v0.9.30`) | Session start |
| [`instructions/ridgun.md`](instructions/ridgun.md) | Compact scoped instruction (`applyTo: "**/*.ridgun,build.ridgun"`) covering syntax invariants, idiomatic `->` pipeline chaining (`xs map f -> filter g -> results`, `FR-COMP-014`), `(+ _ _ +)` sequence masks, `-> ()` unit discard, `_ =`-free blocks, natural space-separated names (`FR-COMP-005`), unified space-separated tuple/sequence type signatures (`FR-COMP-008`), the Native Agent Model (`agent`, `send ... to`, `receive from`, `try receive from`, `stop`, `FR-COMP-009`), `=` / `\|` / `\|\|` / `\|.` / `\|\|.`, `mut`, `\|\|map` / `\|\|filter`, `with timeout`, PAL I/O primitives, and `RMM1`/`RMM2` | Automatically loaded whenever touching any `.ridgun` file or `build.ridgun` |
| [`instructions/stable.md`](instructions/stable.md) | Scoped instruction (`applyTo: "build.ridgun,plugins/**/*.ridgun,.stable/plugins/**/*.ridgun"`) covering `stable` project manifests (`build.ridgun`), `.ridgunlib`/`.so` library builds, custom `fn :: task` commands, and `stable` plugins | Automatically loaded when touching `build.ridgun` or `plugins/*.ridgun` |
| [`skills/implement-code-ridgun/SKILL.md`](skills/implement-code-ridgun/SKILL.md) | Complete Ridgun implementation skill: LLM anti-pattern table ("Never Write This → Write This Instead"), full grammar, idiomatic `->` pipeline chaining (`FR-COMP-014`), `(+ _ _ +)` sequence masks, `-> ()`, `_ =`-free blocks, generics (`A`..`Z`), space-separated tuple/return signatures (`FR-COMP-008`), Native Agent Model (`FR-COMP-009`), mixfix (`op ::`), `RMM1`/`RMM2` memory rules, complete built-in runtime table, and ELF64 `stable`/`ridgunc` CLI workflow | Before writing, refactoring, or reviewing any `.ridgun` code |
| [`skills/implement-code-ridgun/references/cheatsheet.ridgun`](skills/implement-code-ridgun/references/cheatsheet.ridgun) | Verified, canonical `.ridgun` source file demonstrating all major Ridgun `v0.9.30` constructs in tabular format (`./bin/ridgunc check` clean) | One-read syntax & alignment reference |
| [`skills/implement-stable-project/SKILL.md`](skills/implement-stable-project/SKILL.md) | Complete `stable` project manager, library builder (`--lib`, `.ridgunlib`, `.so`), custom task (`fn :: task`), dependency (`stable deps`), and framework plugin (`plugins/*.ridgun`, `expand type StableCommand`) skill | Before scaffolding projects, editing `build.ridgun`, building libraries, or creating `stable` plugins |
| [`skills/implement-stable-project/references/build_cheatsheet.ridgun`](skills/implement-stable-project/references/build_cheatsheet.ridgun) | Verified `build.ridgun` reference showing metadata, `project kind`, `dependencies`, `plugins`, and custom single/multi-word `task` definitions | Reference when creating or editing `build.ridgun` |
| [`skills/implement-stable-project/references/plugin_cheatsheet.ridgun`](skills/implement-stable-project/references/plugin_cheatsheet.ridgun) | Verified `stable` plugin reference (`plugins/*.ridgun`) showing exported tasks, `expand type` command extensions, and executable plugin entrypoints | Reference when creating `stable` extensions or framework plugins |

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
