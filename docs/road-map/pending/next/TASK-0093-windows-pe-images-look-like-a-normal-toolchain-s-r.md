---
id: TASK-0093
title: Windows PE images look like a normal toolchain's: read-only .text, .data/.bss, NX_COMPAT, checksum
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
# TASK-0093 — Windows PE images like a normal toolchain's

## Goal (one sentence)
An antivirus on a real Windows machine removes `omni.exe` (1.0.3); the PE images must stop looking like packed malware.

## Plan
- [ ] Code in a read-only executable `.text`; data in a non-executable `.data` and `.bss` (no writable+executable section).
- [ ] `DllCharacteristics` with `NX_COMPAT`; if possible `DYNAMIC_BASE` with a `.reloc` section.
- [ ] A valid `CheckSum`.
- [ ] Later, with ADR-0008: call KERNEL32 directly instead of `ud2` traps and a vectored handler (ADR-0007).
- [ ] Check on a real Windows machine, not only Wine.

## Progress log (append-only, newest last)
- 2026-11-14: Created. Requested by Solstice / omni. Source: /tmp/ridgun-compiler/2026-11-12/windows-defender-flags-exe.md. Code signing and reporting the false positive to Microsoft are Pedro's decision.

## Exact next actions
1. Code in a read-only executable `.text`; data in a non-executable `.data` and `.bss` (no writable+executable section).
