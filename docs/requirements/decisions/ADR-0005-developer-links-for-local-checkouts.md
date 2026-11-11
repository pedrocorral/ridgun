---
id: ADR-0005
title: Developers build against local checkouts through developer links
status: accepted
date: 2026-11-11
supersedes: []
affects:
  - ADR-0003
  - FR-TOOL-002
  - src/main/ridgun/stable/main.rg
---
# ADR-0005 — Developers build against local checkouts through developer links

## Context
- ADR-0003 made `build.rg` list package names only. omni installs them and `stable` reads them from `omni.lock`.
- A developer who works on a package and on a project that uses it at the same time needs the project to build against the package's checkout, before any release exists.
- ADR-0003 removed every way to do that.
- A local path must not become a way in for an attacker. A cloned repository, or an installed package, must not be able to make `stable` read or copy a folder of the attacker's choice.

## Options considered
1. **Paths in `build.rg` again:** every project carries them. Anyone who clones a project gets them, and so does every machine where the path means something else.
2. **An override file in the project (`build.local.rg` or similar):** a repository can ship that file, so cloning a project would turn it on.
3. **Links kept outside every project:** each developer makes them on their own machine, with an explicit command.

## Decision
Adopt **Option 3**.
- `stable dev link <package> <folder>` makes a link; `stable dev unlink <package>` removes it; `stable dev links` lists them.
- The links live in `~/.stable/dev-links`. No project, repository or package holds them, so none can bring or turn one on. There are none by default.
- `build.rg` and `omni.lock` still hold names only. ADR-0003 stays in force for them.
- When a dependency has a link, `stable deps` and `stable add` copy the linked folder instead of the package omni installed, and print a warning each time.
- A link is valid only when:
  - the package is a name (no `/`, `\`, `:`, `@`, leading `.` or `~`);
  - the folder is an absolute path without `"`, `$`, `` ` ``, `\`, `|`, `'` or a newline, since `stable` copies it with a shell command;
  - the folder has a `build.rg` whose `project name` is the package name.
- `stable` checks those rules when it makes a link and again every time it uses one. An invalid link stops the build with an error; it never falls back to omni silently.

## Consequences
- A developer can work on a package and on its users together, on their own machine only.
- Builds on other machines, and in CI, are the same as before: names resolved through omni.
- A link left in place keeps applying to every project on that machine. The warning on every use makes that visible.
