---
id: ADR-0003
title: stable dependencies are package names installed by omni
status: accepted
date: 2026-11-10
supersedes: []
affects:
  - FR-TOOL-002
  - src/main/ridgun/stable/main.rg
---
# ADR-0003 — `stable` dependencies are package names installed by omni

## Context
- `fn :: dependencies` in `build.rg` accepted local paths and git URLs.
- `stable deps` copied a local path, and cloned or pulled a URL with git.
- A git clone is not signed and not pinned to a version.
- omni, Ridgun's package manager, installs only signed releases from ridgun.com. It records each installed package in `omni.lock`: name, version, digest and installed location.
- `stable` and omni therefore had two ways to fetch the same thing, with different rules.
- Every `build.rg` in the ecosystem lists absolute paths such as `/home/boogie/ridgun/libs`. Those paths exist on one machine only, so nobody else can build those projects.

## Options considered
1. **Keep paths and URLs:** nothing changes. `build.rg` stays non-portable, and git keeps bypassing omni's signature and lock.
2. **Names in `build.rg`, plus a local override file:** this keeps a local workflow, but adds a second resolution path that only one machine uses.
3. **Names only:** `build.rg` lists package names. omni installs them. `stable` reads where omni put each one from `omni.lock`.

## Decision
Adopt **Option 3**.
- Each entry of `fn :: dependencies` is a package name, optionally with a version: `solstice`, `json`, `solstice@0.1.0`.
- `stable` rejects an entry that is a path or a URL. That is any entry containing `/`, `\` or `:`, or starting with `.` or `~`.
- `stable` never downloads. It resolves each name through the project's `omni.lock`:
  - **A library:** the artifact is an `.rglib` file, which must exist.
  - **A package:** the artifact is a folder. `stable` synchronizes it into `.stable/deps/<name>/`, the same way it copied a path before.
  - **Not installed:** if the name is missing from `omni.lock`, `stable` reports it and names the fix: `omni install <name>`.
  - **Version mismatch:** if `build.rg` asks for a version and `omni.lock` holds another, `stable` reports it and names the fix: `omni install <name>@<version>`.
  - **Local entry:** if the lock entry is a local one (version `local`), `stable` rejects it.
- `stable add <name>` records the name in `build.rg` and synchronizes it under the same rules.

## Consequences
- **Requirements:** `FR-TOOL-002`.
- **Tests:**
  - `tests/run.rg` tc6 and tc7 declare dependencies by name, with an `omni.lock` entry standing in for omni.
  - tc6 also checks that a path, a URL and an uninstalled name are rejected.
  - `src/test/ridgun/test lib and plugins.rg` adds `mathkit` by name.
- **Code:** `src/main/ridgun/stable/main.rg`. This repository's `build.rg` lists `libs`.
- **Other teams:**
  - omni must write package names, not folders, into `build.rg`, and drop local-path installs.
  - Ecosystem projects must list names instead of absolute paths.
  - This is noted in the compiler team notes.

## Amendment
- ADR-0005 (2026-11-11) adds developer links: a developer may build against a local checkout through `stable dev link`, kept in `~/.stable/dev-links`, never in a project. `build.rg` and `omni.lock` still hold names only.
