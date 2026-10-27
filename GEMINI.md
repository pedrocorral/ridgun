Read and follow `AGENTS.md` at the repository root. It is the single source of agent instructions for this project. Skills are available under `.agents/skills/` (installed from `.aix/skills/` by `aix install`).

## Scoped instructions
Read these before working on matching files:
- `custom/languages/ridgun` (when touching **/*.rg, build.rg): read `.aix/custom/instructions/languages/ridgun.md` — Use when writing, refactoring, or reviewing Ridgun (.rg) source files or build.rg: syntax rules, idiomatic -> pipeline chaining (xs map f -> filter g -> results), (+ _ _ +) sequence masks, -> () unit discard, _ =-free blocks, type signatures, guards, ADTs, parallel || DAGs, RMM1/RMM2 memory, regions, and stable/ridgunc ELF64 verification.
- `custom/tools/stable` (when touching build.rg, plugins/**/*.rg, .stable/plugins/**/*.rg): read `.aix/custom/instructions/tools/stable.md` — Use when creating, editing, or running build.rg, stable plugins (plugins/*.rg, .stable/plugins/*.rg), custom stable tasks, dependencies, or library/executable builds with stable.

