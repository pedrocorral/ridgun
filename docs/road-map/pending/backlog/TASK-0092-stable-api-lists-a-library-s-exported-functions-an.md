---
id: TASK-0092
title: stable api lists a library's exported functions and types with signatures and comments
status: pending             # pending | going-on | blocked | completed
created: 2026-11-14
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0092 — stable api

## Goal (one sentence)
`stable api` (and `ridgunc api <file>`) prints, for each module of a library, its exported `fn`, `op` and `type` items: module, kind, name, signature or definition, line, and the `--` comment block above it.

## Plan
- [ ] One line per item, tab-separated; `--json` for JSON.
- [ ] Exports follow the rule `import` already uses for visibility; private helpers stay out.
- [ ] Done when `stable api` in libs lists `json` with signatures and comments and nothing private.

## Progress log (append-only, newest last)
- 2026-11-14: Created. Requested by Solstice / www-ridgun for the package pages of ridgun.com. Source: /tmp/ridgun-compiler/2026-11-12/firmas-exportadas.md.

## Exact next actions
1. One line per item, tab-separated; `--json` for JSON.
