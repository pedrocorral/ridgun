---
id: FR-TOOL-003
title: Extensible stable Architecture (Custom Tasks, Plugins, and Open Command Extensions for Frameworks)
type: functional
status: implemented
priority: must
domain: TOOL
depends_on:
  - FR-TOOL-002
  - FR-COMP-005
  - FR-COMP-006
related:
  - ADR-0001
tests: []
---
# FR-TOOL-003 — Extensible `stable` Architecture (Custom Tasks, Plugins, and Open Command Extensions for Frameworks)

## Statement
The `stable` build tool (`src/main/ridgun/stable/main.rg`) SHALL be designed as an open, extensible platform so that application frameworks (such as web frameworks, API generators, database migration runners, and deployment tools) can extend `stable` with custom commands, tasks, and plugins:

1. **Custom Tasks Declared Directly in `build.rg` (`fn :: task <name> => String`)**:
   - Any Ridgun project MAY define custom `stable` commands directly in `build.rg` using natural-language spaces (`fn :: task <word1> <word2> ... => String`):
     ```ridgun
     fn :: task serve => String
           task serve =  "./target/ridgunc run src/main/ridgun/web/server.rg"

     fn :: task routes => String
           task routes =  "./target/ridgunc run src/main/ridgun/web/routes.rg"

     fn :: task db migrate => String
           task db migrate =  "./target/ridgunc run src/main/ridgun/db/migrate.rg"
     ```
   - Running `stable <task-words...> [extra-args...]` (in batch CLI mode or interactive `stable> ` mode) SHALL look up `task_<words>` in `build.rg` and execute the task command (forwarding any extra CLI arguments).
   - `stable tasks` (and `stable info` / `stable help`) SHALL list all custom tasks discovered in `build.rg` and active plugins.

2. **Plugin & Extension System (`fn :: plugins => [String]`, `stable plugin ...`, `.stable/plugins/`)**:
   - `build.rg` MAY declare `fn :: plugins => [String]` listing extension names or paths (e.g., `["web", "openapi"]`).
   - Extensions MAY live in:
     - `plugins/<ext>.rg` or `src/main/ridgun/plugins/<ext>.rg` (project-local extensions)
     - `.stable/plugins/<ext>.rg` or `.stable/deps/<ext>/plugin.rg` (installed/dependency extensions)
   - Each plugin `.rg` file MAY either:
     1. Define `fn :: task <name> => String` declarations (which `stable` automatically merges into the project's available tasks!), or
     2. Be an executable Ridgun plugin module invoked as `stable <plugin> <subcommand> [args...]` (compiled & cached into `target/.stable_plugin_<ext>_bin` and executed with the user's arguments).
   - `stable plugins` SHALL list all configured and discovered plugins and their contributed tasks.

3. **Open ADT Command Architecture in `stable` (`expand type` Ready)**:
   - `stable` SHALL model its command & project descriptors using extensible Ridgun types (`StableConfig`, `StableTask`) and natural-language `op ::` / `fn ::` clauses so that source-level extensions can also use `expand type` and automatic clause merging (`FR-COMP-005`) to add new task handlers without modifying core `stable` dispatch logic.

## Rationale
Modern ecosystems (such as Scala's `sbt`, Rust's `cargo-<subcommand>`, or Elixir's `mix` tasks for Phoenix) thrive because web frameworks and libraries can add domain-specific commands (`stable serve`, `stable routes`, `stable web new`, `stable db migrate`) that feel native to the build tool. Because `build.rg` and plugins are 100% pure Ridgun files, `stable` can merge tasks from `build.rg` and `plugins/*.rg` with zero external scripting languages.

## Acceptance Criteria
- AC1: Defining `fn :: task <name> => String` (single-word or multi-word with spaces) in `build.rg` allows running `stable <name> [args...]` and listing it via `stable tasks`.
- AC2: Declaring `fn :: plugins => [String]` in `build.rg` (or placing a plugin in `plugins/<ext>.rg` / `.stable/plugins/<ext>.rg`) registers the plugin's tasks and subcommands in `stable` and lists them via `stable plugins`.
- AC3: Web-framework style workflows (e.g. `stable routes`, `stable serve`, or plugin subcommands) execute end-to-end and are verified by automated tests.
