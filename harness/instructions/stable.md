---
id: custom/tools/stable
name: "Stable Build System, Library & Plugin Conventions"
description: "Use when creating, editing, or running build.rg, stable plugins (plugins/*.rg, .stable/plugins/*.rg), custom stable tasks, dependencies, or library/executable builds with stable."
applyTo: "build.rg,plugins/**/*.rg,.stable/plugins/**/*.rg"
optional: false
---
# `stable` project manager, library & plugin conventions (`v0.9.3`)

Read and follow the `implement-stable-project` and `implement-code-ridgun` skills before editing `build.rg` or `plugins/*.rg`.

## 1. Pure-Ridgun Project Manifest (`build.rg`)
- `stable` never uses YAML, TOML, or JSON. Every project is configured by a pure Ridgun `build.rg` file at the repository root using natural space-separated `fn ::` declarations (`_`-separated names remain backward-compatible):
  ```ridgun
  fn :: project name => String
        project name =  "my_project"

  fn :: project version => String
        project version =  "0.1.0"

  -- "exe" (default executable), "lib" (.rglib + ELF64 .so library), or "both"
  fn :: project kind => String
        project kind =  "both"

  fn :: main entry => String
        main entry =  "src/main/ridgun/my_project/main.rg"

  fn :: source dir => String
        source dir =  "src/main/ridgun"

  fn :: test dir => String
        test dir =  "src/test/ridgun"

  fn :: target dir => String
        target dir =  "target"

  fn :: dependencies => [String]
        dependencies =  []

  fn :: plugins => [String]
        plugins =  []
  ```

## 2. Standard `stable` CLI Commands
- `stable info` — Display project metadata, directories, targets, custom tasks, and active plugins from `build.rg`.
- `stable new <name>` / `stable init` — Scaffold a new executable Ridgun project (`build.rg`, `src/main/ridgun/<name>/main.rg`, `src/test/ridgun/test main.rg`, `.gitignore`).
- `stable new --lib <name>` / `stable init --lib` — Scaffold a reusable library project (`project kind = "lib"`, `src/main/ridgun/lib/<name>.rg` without `main`, `src/test/ridgun/test <name>.rg`).
- `stable check [file.rg ...]` — Type-check and run static `||` DAG + `RMM1`/`RMM2` analysis across all project modules in parallel (`||map`).
- `stable test` — Compile and execute all `src/test/ridgun/test*.rg` test suites in parallel (`||map`).
- `stable format [file.rg ...]` — Format `.rg` files into canonical 2D tabular alignment (`=>`, `=`, `->`) (`FR-TOOL-001`).
- `stable built [target]` — Compile native Linux ELF64 executables (`target/<target>`) or libraries (`when project kind == "lib"` or `"both"`).
- `stable built lib` (or `stable build lib`) — Compile reusable library artifacts (`target/<name>.rglib` and native ELF64 `ET_DYN` shared object `target/lib<name>.so`) (`FR-COMP-006`).
- `stable run [args...]` — Compile and run the project's `main entry`.
- `stable install [target]` — Build and install native ELF64 binaries into `~/.local/bin/` and `bin/`.
- `stable deps` / `stable add <git_url_or_path>` — Synchronize dependencies declared in `fn :: dependencies => [String]` into `.stable/deps/`.
- `stable tasks` — List all custom `fn :: task <name> => String` commands discovered in `build.rg` and loaded plugins.
- `stable plugins` — List all loaded `stable` plugin modules (`fn :: plugins => [String]`, `plugins/*.rg`, `.stable/plugins/*.rg`).
- `stable clean` — Remove compiled artifacts from `target/`.

## 3. Custom Tasks in `build.rg` (`FR-TOOL-003`)
- Any zero-argument function in `build.rg` whose name starts with `task ` (or `task_`) and returns `String` defines a custom `stable` subcommand:
  ```ridgun
  fn :: task serve => String
        task serve =  "./target/web_server --port 8080"

  fn :: task db migrate => String
        task db migrate =  "./target/ridgunc run src/main/ridgun/db/migrate.rg"
  ```
- Running `stable serve` or `stable db migrate` evaluates the task function and executes the returned command string (appending any extra CLI arguments passed after the task name).

## 4. Extensible Plugins & Framework Commands (`FR-TOOL-003`)
- `stable` loads plugin `.rg` files from:
  1. `fn :: plugins => [String]` in `build.rg` (file paths or bare plugin names),
  2. `plugins/*.rg` in the project root,
  3. `.stable/plugins/*.rg` in the project's `.stable/` directory.
- A plugin `.rg` file can:
  1. Define `fn :: task <words...> => String` commands (automatically registered in `stable tasks` and runnable via `stable <words...>`),
  2. Or define an executable `fn :: main => ()` entrypoint (invoked directly via `stable <plugin_name> [args...]`),
  3. Or extend `StableCommand` using Ridgun's open type extension (`expand type StableCommand = ...`) and clause merging when building custom `stable` distributions.
