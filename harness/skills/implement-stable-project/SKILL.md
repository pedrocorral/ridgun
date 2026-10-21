---
name: implement-stable-project
description: Configure, scaffold, build, and extend Ridgun projects with `stable` (`build.rg`), including executable and reusable library compilation (`.rglib` and ELF64 `.so`), custom `fn :: task` commands, `plugins/*.rg` framework extensions, dependency management, and canonical formatting; use whenever working with `stable`, `build.rg`, libraries, or plugins.
---
# implement-stable-project (`v0.9.3`)

Reading budget: `harness/skills/implement-stable-project/references/build_cheatsheet.rg`, `harness/skills/implement-stable-project/references/plugin_cheatsheet.rg`, and the project's `build.rg`.

---

## 1. Overview of `stable` (`v0.9.3`)
`stable` (`src/main/ridgun/stable/main.rg`) is Ridgun's 100% self-hosted project manager, build orchestrator, test runner, dependency manager, canonical tabular formatter, and extensible plugin host.
- **No external config formats**: `stable` uses `build.rg` (pure Ridgun functions) instead of TOML, YAML, or JSON.
- **Multicore parallel execution**: `stable check`, `stable test`, and `stable format` process files concurrently via Ridgun's `||map`.
- **Dual build modes (`FR-COMP-004`, `FR-COMP-006`)**: Compiles standalone Linux ELF64 executables (`ET_EXEC`), reusable Ridgun library bundles (`.rglib`), and native Linux ELF64 shared objects (`ET_DYN`, `.so`).
- **Extensible architecture (`FR-TOOL-003`)**: Supports custom single-word and multi-word `fn :: task <name> => String` commands in `build.rg`, external plugin modules (`plugins/*.rg`, `.stable/plugins/*.rg`, `fn :: plugins => [String]`), and open `expand type StableCommand` extensions for web frameworks and domain toolchains.

---

## 2. `build.rg` Specification & Schema

Every setting in `build.rg` is a zero-argument Ridgun function (`fn :: <setting name> => <Type>`) using natural spaces (`_`-separated identifiers are also accepted for backward compatibility):

| Function Signature in `build.rg` | Default if Omitted | Description |
|---|---|---|
| `fn :: project name => String` | `"ridgunc"` | Project or library name (used for `target/<name>.rglib` and `target/lib<name>.so`) |
| `fn :: project version => String` | `"0.1.0"` | Semantic version string |
| `fn :: project kind => String` | `"exe"` | `"exe"` (executables only), `"lib"` (`.rglib` + `.so` library), or `"both"` |
| `fn :: main entry => String` | `"src/main/ridgun/<name>/main.rg"` | Main `.rg` entrypoint (or library entrypoint when `project kind == "lib"`) |
| `fn :: source dir => String` | `"src/main/ridgun"` | Root directory for source modules and targets |
| `fn :: test dir => String` | `"src/test/ridgun"` | Directory containing `test*.rg` test suites |
| `fn :: target dir => String` | `"target"` | Output directory for compiled ELF64 binaries, `.rglib` bundles, and `.so` libraries |
| `fn :: dependencies => [String]` | `[]` | List of Git URLs or local paths synchronized by `stable deps` into `.stable/deps/` |
| `fn :: plugins => [String]` | `[]` | List of plugin names or `.rg` paths loaded by `stable` |
| `fn :: task <words...> => String` | *(none)* | Custom `stable <words...>` command returning the shell/ridgunc command to run |

---

## 3. Complete `stable` CLI Reference

| Command | Action |
|---|---|
| `stable info` | Print project name, version, kind, directories, discovered targets, custom tasks, and plugins |
| `stable new <name>` | Scaffold a new executable project in `<name>/` (`build.rg`, `src/main/ridgun/<name>/main.rg`, `src/test/ridgun/test main.rg`, `.gitignore`) |
| `stable new --lib <name>` | Scaffold a new reusable library project in `<name>/` (`project kind = "lib"`, `src/main/ridgun/lib/<name>.rg` without `main`, `src/test/ridgun/test <name>.rg`) |
| `stable init [--lib]` | Initialize `build.rg` and standard directories in the current working directory |
| `stable check [file.rg ...]` | Run lexer, parser, typechecker (`A..Z` generics, `mut`, ADTs, tensor shapes), and static `||` DAG analyzer across all `.rg` files |
| `stable test` | Compile and run all `src/test/ridgun/test*.rg` suites in parallel (`||map`) |
| `stable format [file.rg ...]` | Format `.rg` files in-place into canonical 2D tabular column alignment (`FR-TOOL-001`) |
| `stable built [target]` | Build project targets into `target/` (builds executables, libraries, or both according to `project kind`) |
| `stable built lib` | Explicitly build library artifacts (`target/<name>.rglib` and `target/lib<name>.so`) (`FR-COMP-006`) |
| `stable run [args...]` | Compile and execute `main entry`, forwarding `[args...]` |
| `stable install [target]` | Build and install ELF64 executables into `~/.local/bin/` and `./bin/` |
| `stable deps` | Fetch/copy all entries from `fn :: dependencies => [String]` into `.stable/deps/` |
| `stable add <url_or_path>` | Append a dependency to `build.rg` and synchronize `.stable/deps/` |
| `stable tasks` | List all custom `fn :: task <name> => String` commands from `build.rg` and loaded plugins |
| `stable plugins` | List all active plugin `.rg` modules |
| `stable <custom_task> [args...]` | Execute a custom single-word or multi-word task or plugin command |
| `stable clean` | Clean compiled outputs in `target/` |

---

## 4. Building & Importing Reusable Libraries (`FR-COMP-006`)

### 4.1 Library Source Rules (No `main` Required)
A Ridgun library module (`src/main/ridgun/lib/<name>.rg` or standalone `<name>.rg`) contains `type`, `expand type`, `fn ::`, and `op ::` declarations and **does not need `fn :: main => ()`**.
- During library compilation, `compiler.rg` (`lower_library_to_native`) disables `main`-rooted dead-code elimination so **all** top-level functions, operators, and types remain exported.

### 4.2 Compiling `.rglib` and `.so` Artifacts
- **With `stable`**:
  ```bash
  stable new --lib mathkit
  cd mathkit
  stable built lib
  # Produces:
  #   target/mathkit.rglib    (Self-contained Ridgun library bundle for `import`)
  #   target/libmathkit.so    (Native Linux ELF64 ET_DYN shared object, e_type = 3)
  ```
- **With `ridgunc` directly**:
  ```bash
  ridgunc build --lib geom_lib.rg -o target/geom_lib.rglib
  ridgunc build --so  geom_lib.rg -o target/libgeom_lib.so
  ridgunc build --so --target arm64-linux geom_lib.rg -o target/libgeom_lib_arm64.so
  ```

### 4.3 Importing a `.rglib` Bundle in Another Project
Any `.rg` file can import a compiled `.rglib` bundle either by path or by bare module name (searched in the file's directory, `target/`, `dist/`, `lib/`, and `.stable/deps/`):
```ridgun
import "target/mathkit.rglib"
-- or:
import mathkit
```

---

## 5. Extending `stable`: Custom Tasks & Framework Plugins (`FR-TOOL-003`)

### 5.1 Custom Single-Word & Multi-Word Tasks in `build.rg`
Define any `fn :: task <words...> => String` in `build.rg`:
```ridgun
fn :: task serve => String
      task serve =  "./bin/ridgunc run src/main/ridgun/web/server.rg"

fn :: task db migrate => String
      task db migrate =  "./bin/ridgunc run src/main/ridgun/db/migrate.rg"
```
- `stable tasks` lists `serve` and `db migrate`.
- `stable serve` or `stable db migrate --env prod` runs the task command and appends any extra CLI flags (`--env prod`).

### 5.2 Creating Reusable Plugins (`plugins/*.rg` & `.stable/plugins/*.rg`)
To build reusable extensions (e.g., for a web framework, database toolkit, or deployment pipeline):
1. Place a `.rg` file in `plugins/<plugin_name>.rg` or `.stable/plugins/<plugin_name>.rg` (or list it in `fn :: plugins => [String]` in `build.rg`).
2. **Task-style plugin**: Define `fn :: task <words...> => String` inside the plugin `.rg` file. `stable` automatically merges all plugin tasks into `stable tasks` and dispatches `stable <words...>`.
3. **Executable-style plugin**: Define `fn :: main => ()` inside `plugins/<plugin_name>.rg`. Running `stable <plugin_name> [args...]` executes the plugin directly via `ridgunc run` with `cli_args`.
4. **Open ADT Command Extension (`expand type StableCommand`)**: Inside `stable/main.rg` or custom `stable` distributions, `StableCommand` is extended openly via:
   ```ridgun
   expand type StableCommand = CmdCustomTask String String [String] | CmdPluginExec String [String]
   ```
   and `dispatch command` clauses merge automatically before the catch-all clause (`FR-COMP-005`).
