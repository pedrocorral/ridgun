---
rule: "Never use shortcuts, host wrappers, or partial subsets when asked for a full implementation; never claim completion until 100% of features are ported."
author: pedro@obdin.com
scope: project
updated: 2026-10-17
---
**Why:** On 2026-10-17, the agent first wrapped the Rust runtime via `include_str!` and then implemented only a ~2,045-line subset of the compiler in Ridgun (omitting typechecker, escape/region analysis, records, interpolation, and concurrency) while claiming the self-hosted compiler was finished.
**How to apply:** When implementing or porting a compiler or subsystem, port every module and feature (lexer with spans/interpolation, full parser, typechecker, escape/region/concurrency analyzer, codegen, and full runtime) and verify full feature parity before claiming completion.
