---
name: implement-stable-project
description: Configure, scaffold, build, and extend Ridgun projects with `stable` (`build.ridgun`), including executable and reusable library compilation (`.ridgunlib` and ELF64 `.so`), custom `fn :: task` commands, `plugins/*.ridgun` framework extensions, dependency management, and canonical formatting; use whenever working with `stable`, `build.ridgun`, libraries, or plugins.
---
# implement-stable-project (`v0.9.30`)

Reading budget: `harness/skills/implement-stable-project/references/build_cheatsheet.ridgun`, `harness/skills/implement-stable-project/references/plugin_cheatsheet.ridgun`, and the project's `build.ridgun`.

---

## 1. Overview of `stable` (`v0.9.30`)
`stable` (`src/main/ridgun/stable/main.ridgun`) is Ridgun's 100% self-hosted project manager, build orchestrator, test runner, dependency manager, canonical tabular formatter, and extensible plugin host.
- **No external config formats**: `stable` uses `build.ridgun` (pure Ridgun functions) instead of TOML, YAML, or JSON.
- **Multicore parallel execution**: `stable check`, `stable test`, and `stable format` process files concurrently via Ridgun's `||map`.
- **Dual build modes (`FR-COMP-004`, `FR-COMP-006`)**: Compiles standalone Linux ELF64 executables (`ET_EXEC`), reusable Ridgun library bundles (`.ridgunlib`), and native Linux ELF64 shared objects (`ET_DYN`, `.so`).
- **Extensible architecture (`FR-TOOL-003`)**: Supports custom single-word and multi-word `fn :: task <name> => String` commands in `build.ridgun`, external plugin modules (`plugins/*.ridgun`, `.stable/plugins/*.ridgun`, `fn :: plugins => [String]`), and open `expand type StableCommand` extensions for web frameworks and domain toolchains.

---

## 2. `build.ridgun` Specification & Schema

Every setting in `build.ridgun` is a zero-argument Ridgun function (`fn :: <setting name> => <Type>`) using natural spaces (`_`-separated identifiers are also accepted for backward compatibility):

| Function Signature in `build.ridgun` | Default if Omitted | Description |
|---|---|---|
| `fn :: project name => String` | `"ridgunc"` | Project or library name (used for `target/<name>.ridgunlib` and `target/lib<name>.so`) |
| `fn :: project version => String` | `"0.1.0"` | Semantic version string |
| `fn :: project kind => String` | `"exe"` | `"exe"` (executables only), `"lib"` (`.ridgunlib` + `.so` library), or `"both"` |
| `fn :: main entry => String` | `"src/main/ridgun/<name>/main.ridgun"` | Main `.ridgun` entrypoint (or library entrypoint when `project kind == "lib"`) |
| `fn :: source dir => String` | `"src/main/ridgun"` | Root directory for source modules and targets |
| `fn :: test dir => String` | `"src/test/ridgun"` | Directory containing `test*.ridgun` test suites |
| `fn :: target dir => String` | `"target"` | Output directory for compiled ELF64 binaries, `.ridgunlib` bundles, and `.so` libraries |
| `fn :: dependencies => [String]` | `[]` | Package names (`json`, `solstice@0.1.0`) installed by omni (`omni install <name>`, locked in `omni.lock`) and synchronized by `stable deps` into `.stable/deps/`; paths and URLs are rejected (ADR-0003) |
| `fn :: plugins => [String]` | `[]` | List of plugin names or `.ridgun` paths loaded by `stable` |
| `fn :: task <words...> => String` | *(none)* | Custom `stable <words...>` command returning the shell/ridgunc command to run |

---

## 3. Complete `stable` CLI Reference

| Command | Action |
|---|---|
| `stable info` | Print project name, version, kind, directories, discovered targets, custom tasks, and plugins |
| `stable --version` / `stable -v` | Print `stable 0.9.30` version banner |
| `stable new <name>` | Scaffold a new executable project in `<name>/` (`build.ridgun`, `src/main/ridgun/<name>/main.ridgun`, `src/test/ridgun/test main.ridgun`, `.gitignore`) |
| `stable new --lib <name>` | Scaffold a new reusable library project in `<name>/` (`project kind = "lib"`, `src/main/ridgun/lib/<name>.ridgun` without `main`, `src/test/ridgun/test <name>.ridgun`) |
| `stable init [--lib]` | Initialize `build.ridgun` and standard directories in the current working directory |
| `stable check [file.ridgun ...]` | Run lexer, parser, typechecker (`A..Z` generics, `mut`, ADTs, tensor shapes), and static `||` DAG analyzer across all `.ridgun` files |
| `stable test` | Compile and run all `src/test/ridgun/test*.ridgun` suites in parallel (`||map`) |
| `stable format [file.ridgun ...]` | Format `.ridgun` files in-place into canonical 2D tabular column alignment (`FR-TOOL-001`) |
| `stable built [target]` | Build project targets into `target/` (builds executables, libraries, or both according to `project kind`) |
| `stable built lib` | Explicitly build library artifacts (`target/<name>.ridgunlib` and `target/lib<name>.so`) (`FR-COMP-006`) |
| `stable run [args...]` | Compile and execute `main entry`, forwarding `[args...]` |
| `stable install [target]` | Build and install ELF64 executables into `~/.local/bin/` and `./bin/` |
| `stable deps` | Copy each package that `fn :: dependencies => [String]` names, from where `omni.lock` says omni installed it, into `.stable/deps/` |
| `stable add <package>[@<version>]` | Synchronize a package omni installed into `.stable/deps/`, then append its name to `build.ridgun` |
| `stable dev link <package> <folder>` / `dev unlink <package>` / `dev links` | Developers only: build `<package>` from a local checkout instead of omni's copy; links live in `~/.stable/dev-links`, never in a project; every use warns (ADR-0005) |
| `stable tasks` | List all custom `fn :: task <name> => String` commands from `build.ridgun` and loaded plugins |
| `stable plugins` | List all active plugin `.ridgun` modules |
| `stable <custom_task> [args...]` | Execute a custom single-word or multi-word task or plugin command |
| `stable clean` | Clean compiled outputs in `target/` |

---

## 4. Building & Importing Reusable Libraries (`FR-COMP-006`)

### 4.1 Library Source Rules (No `main` Required)
A Ridgun library module (`src/main/ridgun/lib/<name>.ridgun` or standalone `<name>.ridgun`) contains `type`, `expand type`, `fn ::`, and `op ::` declarations and **does not need `fn :: main => ()`**.
- During library compilation, `compiler.ridgun` (`lower_library_to_native`) disables `main`-rooted dead-code elimination so **all** top-level functions, operators, and types remain exported.

### 4.2 Compiling `.ridgunlib` and `.so` Artifacts
- **With `stable`**:
  ```bash
  stable new --lib mathkit
  cd mathkit
  stable built lib
  # Produces:
  #   target/mathkit.ridgunlib (Self-contained Ridgun library bundle for `import`)
  #   target/libmathkit.so    (Native Linux ELF64 ET_DYN shared object, e_type = 3)
  ```
- **With `ridgunc` directly**:
  ```bash
  ridgunc build --lib mathkit.ridgun -o target/mathkit.ridgunlib
  ridgunc build --so  mathkit.ridgun -o target/libmathkit.so
  ridgunc build --so --target arm64-linux mathkit.ridgun -o target/libmathkit.arm64.so
  ```

### 4.3 Importing a `.ridgunlib` Bundle in Another Project
Any `.ridgun` file can import a compiled `.ridgunlib` bundle either by path or by bare module name (searched in the file's directory, `target/`, `dist/`, `lib/`, and `.stable/deps/`):
```ridgun
import "target/mathkit.ridgunlib"
-- or:
import mathkit
```

---

## 5. Extending `stable`: Custom Tasks & Framework Plugins (`FR-TOOL-003`)

### 5.1 Custom Single-Word & Multi-Word Tasks in `build.ridgun`
Define any `fn :: task <words...> => String` in `build.ridgun`:
```ridgun
fn :: task serve => String
      task serve =  "./bin/ridgunc run src/main/ridgun/web/server.ridgun"

fn :: task db migrate => String
      task db migrate =  "./bin/ridgunc run src/main/ridgun/db/migrate.ridgun"
```
- `stable tasks` lists `serve` and `db migrate`.
- `stable serve` or `stable db migrate --env prod` runs the task command and appends any extra CLI flags (`--env prod`).

### 5.2 Creating Reusable Plugins (`plugins/*.ridgun` & `.stable/plugins/*.ridgun`)
To build reusable extensions (e.g., for a web framework, database toolkit, or deployment pipeline):
1. Place a `.ridgun` file in `plugins/<plugin_name>.ridgun` or `.stable/plugins/<plugin_name>.ridgun` (or list it in `fn :: plugins => [String]` in `build.ridgun`).
2. **Task-style plugin**: Define `fn :: task <words...> => String` inside the plugin `.ridgun` file. `stable` automatically merges all plugin tasks into `stable tasks` and dispatches `stable <words...>`.
3. **Executable-style plugin**: Define `fn :: main => ()` inside `plugins/<plugin name>.ridgun`. Running `stable <plugin name> [args...]` executes the plugin directly via `ridgunc run` with `cli args`.
4. **Open ADT Command Extension (`expand type StableCommand`)**: Inside `stable/main.ridgun` or custom `stable` distributions, `StableCommand` is extended openly via:
   ```ridgun
   expand type StableCommand = CmdCustomTask String String [String] | CmdPluginExec String [String]
   ```
   and `dispatch command` clauses merge automatically before the catch-all clause (`FR-COMP-005`).
