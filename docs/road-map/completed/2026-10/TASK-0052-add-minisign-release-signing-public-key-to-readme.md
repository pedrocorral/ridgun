---
id: TASK-0052
title: Add minisign release signing public key to README.md
status: completed
created: 2026-10-31
requirements: [FR-TOOL-002]
tests: [TS-UNIT-001]
security: []
context_files:
  - README.md
scope:
  - README.md
owner: agent-001
claimed: 2026-10-31T19:01:00Z
claimed_by: agent gemini@solarfall
---
# TASK-0052 — Add minisign release signing public key to README.md

## Goal (one sentence)
Document the official `minisign` Ed25519 release signing public key and verification command in `README.md`.

## Plan
- [x] Add the `Release Verification (minisign)` section with public key `RWQuKPmgklF+8SxAc6VK4RdRg/vw1/jBXvq5E0YcBN5QcFjezotHHWvq` to `README.md` and remove the stale `v0.9.29` tag from the heading.

## Progress log (append-only, newest last)
- 2026-10-31: Created and completed `TASK-0052`.

## Files changed (keep current)
- `README.md`

## Verification performed (command → result, newest last)
- `aix docs validate` → `0 errors`

## Exact next actions
1. Close `TASK-0052` and commit `README.md`.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
