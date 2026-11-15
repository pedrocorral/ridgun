---
id: TASK-0088
title: The whole runtime in target-neutral LLVM IR, used on wasm32 first
status: completed
created: 2026-11-12
completed: 2026-11-15
requirements: [FR-COMP-026]  # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0013-the-whole-runtime-is-target-neutral-llvm-ir.md, docs/requirements/decisions/ADR-0011-webassembly-is-a-native-backend.md, docs/etc/runtime_ext.md]
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-15T12:31:14Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0088 — The runtime in target-neutral LLVM IR, on wasm32 first

## Goal (one sentence)
Every runtime slot exists once, in target-neutral LLVM IR (ADR-0013), and the wasm32 backend runs the promised behaviours with it.

## Plan
- [x] Write the runtime from scratch from its contract: the 55 runtime entries declared in `llvm.ridgun` (names and arguments), the value representation (`docs/etc/low_level_ridgun_runtime_design.md`), `rtx.c` and the FRs. No disassembly of the old bytes.
- [x] Write the IR: `i64` words, explicit pointer conversions, no inline assembly; system operations as PAL calls; page-0 variables as globals.
- [x] Allocator over one linear memory on wasm32 (`memory.grow` behind the PAL); RMM rules unchanged.
- [x] Compile the IR with `llc -march=wasm32` and embed the functions in the module that `wasm.ridgun` writes; delete the provisional scalar runtime of `wasm.ridgun`.
- [x] Agents on one thread on wasm32: a step runs when its message arrives.
- [x] Run the promised behaviours on wasm32 (except network and true parallelism).

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0011. Needs TASK-0087.
- 2026-11-15: Redefined by ADR-0013: one runtime source in target-neutral LLVM IR for every target, instead of a runtime hand-written in wasm. Moving x86-64, ARM64 and Windows onto it are later tasks.
- 2026-11-15: The runtime is written from scratch from its contract and the suite, not recovered from the old bytes.
- 2026-11-15: The runtime is hand-written LLVM IR in `src/main/runtime/core/` (heap, value, frame, call, binop, builtins, format, system, agents, tensor, bytes) and one PAL file per target (`src/main/runtime/pal/wasm32.ll`, WASI preview 1). `src/main/runtime/build-wasm32.sh` (stable task `wasm runtime`) links it with `llvm-link`, compiles it with `llc -march=wasm32` and writes the functions into `src/main/ridgun/lib/wasmrt.ridgun`, which `wasm.ridgun` embeds. Tail calls are wasm `return_call`.
- 2026-11-15: Test host: `tests/wasm/wasi-host.c` implements the WASI imports over Linux; `tests/wasm/host-build.sh` turns a module into a Linux executable with `wasm2c --enable-tail-call` and patches two wabt 1.0.36 tail-call bugs in its output (recorded in the script). `tests/run.ridgun --wasm` builds every case through `tests/wasm/build-case.sh`.
- 2026-11-15: Patch, recorded for a general fix: `(b:rest)` is lowered as `[b] :: rest`; the runtime makes it constant time when the left items are the words just before `rest`'s start (a view of the same vector), and prepends in place into the room before a List's start. The compiler could lower the rebuilt cons pattern to the original tail directly.

## Verification performed (command → result, newest last)
- `ridgunc run tests/run.ridgun --wasm --no-toolchain` → 142 of 148 on wasm32. The 6 failures are the FR-COMP-026 AC4 exclusions: network (2), `sys call` (2), `sys execve`, `sys pipe`.
- 1.0.12: bootstrap s1 → s2 → s3, s2 and s3 differ only in the stamp (4 bytes); with s3: suite 310/310 (llvm 162, x86 148); 11 unit test files, 0 fails (`test wasm` and `test wasm backend` included); libs `stable test` 35/35. Installed in `bin/`.

## Exact next actions
1. None: the task is complete. Moving x86-64, ARM64 and Windows onto the IR runtime is TASK-0096.
