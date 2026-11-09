---
rule: "Run every compiler, bootstrap stage and test binary under a memory cap (`ulimit -v` 3-4 GB) and a timeout; an optimization must never add work after a call in tail position."
author: pedro@obdin.com
scope: project
updated: 2026-11-09
---
**Why:** On 2026-11-08 `OPT-018` (borrowed pattern parameters) dropped a scratch value after calls such as `lex loop at` -> `lex step`. The call was no longer the last instruction, so the backend kept a real call instead of a jump. Every pending frame held the token list, `::` copied it each round, and memory grew quadratically. The self-built compiler (stage 2) passed 7 GB in 3 s on `check`, and uncapped runs crashed the whole machine twice.
**How to apply:** Wrap every build, bootstrap stage and run in `ulimit -v 4000000; timeout N` (or `RLIMIT_AS` in a scratch runner); `tests/run.rg` already caps at 4 GB. Before trusting a new compiler, compare its stage-2 peak memory on `check` and on a self-build with the installed one. Any lowering that emits code after a call must leave calls in tail position alone (see `borrow tail fns` and `docs/etc/compiler_optimizations.md`, "Rule: tail calls stay last"); `tests/cases/functions/tail_call_to_pattern_parameter_function.rg` guards this.
