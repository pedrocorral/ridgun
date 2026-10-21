# Ridgun AI Agent Harness (`v0.9.3`)

This directory (`/home/boogie/ridgun/harness/`) contains the self-contained **skills, scoped instructions, root agent guidelines, and runnable reference cheatsheet** needed for any AI coding agent (Antigravity/Gemini, Claude Code, Cursor, Codex, AIX, etc.) to understand, write, refactor, and verify **Ridgun (`.rg`)** code accurately on the first try.

---

## Contents of `harness/`

| File | Purpose | When an Agent Reads It |
|---|---|---|
| [`AGENTS.md`](AGENTS.md) | Root agent entry point & golden rules for Ridgun `v0.9.3` | Session start |
| [`instructions/ridgun.md`](instructions/ridgun.md) | Compact scoped instruction (`applyTo: "**/*.rg,build.rg"`) covering syntax invariants, `=` / `\|` / `\|\|` / `\|.` / `\|\|.`, `mut`, `\|\|map` / `\|\|filter`, and `RMM1`/`RMM2` | Automatically loaded whenever touching any `.rg` file or `build.rg` |
| [`skills/implement-code-ridgun/SKILL.md`](skills/implement-code-ridgun/SKILL.md) | Complete Ridgun implementation skill: LLM anti-pattern table ("Never Write This → Write This Instead"), full grammar, generics (`A`..`Z`), mixfix (`op ::`), `RMM1`/`RMM2` memory rules, complete built-in runtime table, and ELF64 `stable`/`ridgunc` CLI workflow | Before writing, refactoring, or reviewing any `.rg` code |
| [`skills/implement-code-ridgun/references/cheatsheet.rg`](skills/implement-code-ridgun/references/cheatsheet.rg) | Verified, canonical `.rg` source file demonstrating all major Ridgun `v0.9.3` constructs in tabular format (`./target/ridgunc check` clean) | One-read syntax & alignment reference |

---

## How to Install in Any Project or Agent Runtime

### 1. AIX / Antigravity / Gemini CLI / Claude Code
Copy the instruction and skill into your workspace's `.aix/` and `.agents/` directories (already synced in this repository):
```bash
cp harness/instructions/ridgun.md .aix/custom/instructions/languages/ridgun.md
cp -r harness/skills/implement-code-ridgun/* .aix/custom/skills/implement/code-ridgun/
```

### 2. Standalone Repository Setup
For a new Ridgun repository without AIX, copy `harness/AGENTS.md` to the repository root as `AGENTS.md` (or `CLAUDE.md` / `GEMINI.md`) and keep `harness/` at the root so agents can load `harness/instructions/ridgun.md` and `harness/skills/implement-code-ridgun/SKILL.md`.
