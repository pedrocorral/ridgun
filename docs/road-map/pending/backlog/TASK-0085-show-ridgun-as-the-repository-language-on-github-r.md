---
id: TASK-0085
title: Show Ridgun as the repository language on GitHub: remove linguist-detectable=false when Linguist knows .ridgun
status: pending             # pending | going-on | blocked | completed
created: 2026-11-12
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
# TASK-0085 — Show Ridgun as the repository language on GitHub

## Goal (one sentence)
When GitHub Linguist knows `.ridgun`, repositories and new projects show "Ridgun" as their language.

## Plan
- [ ] Wait until Linguist accepts Ridgun. It asks for about 2,000 `.ridgun` files published by third parties, and a request.
- [ ] Remove `* linguist-detectable=false` from `.gitattributes` in every Ridgun repository.
- [ ] Remove it from `gitattributes content` in `src/main/ridgun/stable/main.ridgun`, and update its test in `test lib and plugins.ridgun`.

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0010 (TASK-0084). Until then, `.gitattributes` hides every file from GitHub's language statistics. Without it, GitHub labels the repositories Rouge (`.rg`) or Emacs Lisp. Source: /tmp/ridgun-gitattributes.md.

## Exact next actions
1. Nothing until Linguist knows Ridgun.
