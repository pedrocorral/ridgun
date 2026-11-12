---
id: FR-TOOL-002
title: Project scaffolding (new/init), dependency management (deps/add), and binary installation (install) in stable
type: functional
status: implemented
priority: must
domain: TOOL
depends_on:
  - FR-TOOL-001
  - FR-COMP-004
related:
  - ADR-0001
  - ADR-0003
tests: []
---
# FR-TOOL-002 — Project scaffolding (`new` / `init`), dependency management (`deps` / `add`), and binary installation (`install`) in `stable`

## Statement
The `stable` project manager (`src/main/ridgun/stable/main.ridgun`) SHALL support full Ridgun project lifecycle management in 100% pure Ridgun:
1. **Project Scaffolding (`stable new <name>` and `stable init`)**:
   - `stable new <name>` SHALL create a new project directory `<name>/` containing a canonical `build.ridgun` (`project_name = "<name>"`, `project_version = "0.1.0"`, `dependencies = []`), `src/main/ridgun/<name>/main.ridgun`, `src/test/ridgun/test_main.ridgun`, and `.gitignore`.
   - `stable init` SHALL initialize those files in the current working directory if `build.ridgun` does not already exist.
2. **Dependency Management (`dependencies` in `build.ridgun`, `stable deps`, `stable add <dep>`)**:
   - `build.ridgun` MAY declare `fn :: dependencies => [String]` listing package names, each optionally with a version (`solstice`, `json`, `solstice@0.1.0`). omni installs them (ADR-0003).
   - `stable` SHALL reject an entry that is a path or a URL: one containing `/`, `\` or `:`, or starting with `.` or `~`. It SHALL NOT download anything, and SHALL NOT run git.
   - `stable deps` SHALL resolve each name through the project's `omni.lock`:
     - A library's artifact is an `.ridgunlib` file, which SHALL exist.
     - A package's artifact is a folder, which `stable` SHALL synchronize into `.stable/deps/<name>/`, copying its `.ridgunlib` bundles into `.stable/deps/`.
     - `stable deps` and `stable add` SHALL NOT write into the project's own sources. A package's `.ridgun` files stay under `.stable/deps/<name>/`, where `import` finds them.
   - `stable deps` SHALL fail, naming `omni install <name>`, when a name is not in `omni.lock` or its artifact is missing.
   - `stable deps` SHALL fail, naming `omni install <name>@<version>`, when the requested version differs from the locked one.
   - `stable deps` SHALL fail when the lock entry is a local one (version `local`).
   - **Developer links (ADR-0005).** `stable dev link <package> <folder>` SHALL record, in `~/.stable/dev-links` and nowhere else, that `<package>` is built from `<folder>` on this machine. `stable dev unlink <package>` SHALL remove it and `stable dev links` SHALL list them. There SHALL be none by default.
     - `stable` SHALL accept a link only when `<package>` is a package name, `<folder>` is an absolute path without `"`, `$`, `` ` ``, `\`, `|`, `'` or a newline, and `<folder>/build.ridgun` names the project `<package>`. It SHALL check this when it makes the link and every time it uses it, and SHALL stop with an error on an invalid link.
     - When a dependency has a link, `stable deps` and `stable add` SHALL synchronize the linked folder as a package folder, instead of the `omni.lock` entry, and SHALL print a warning naming the folder each time.
   - `stable add <name>` SHALL append `<name>` to `dependencies` in `build.ridgun` and synchronize it under the same rules.
   - `load_rg_source` in `src/main/ridgun/lib/parser.ridgun` SHALL also search `.stable/deps/*/src/main/ridgun/lib/<mod>.ridgun` and `.stable/deps/*/<mod>.ridgun` when resolving `import <mod>`.
   - `stable run [target]` SHALL build the target before running it unless the binary was built from exactly the current sources. It SHALL decide by content, not by file times: a stamp next to the binary (`<binary>.stamp`) holds a hash of every `.ridgun`, `.ridgunlib` and `omni.lock` in the project (outside `target/`), with their paths, and of the compiler binary (its SHA-256). It SHALL create the output folder when it is missing.
3. **Binary Installation (`stable install [target]`)**:
   - `stable install [target]` SHALL compile the project's native ELF64 executable(s) and install them with executable permissions (`0755`) into `~/.local/bin/` (and `bin/`).

4. **No shell (Windows)**:
   - `stable` SHALL create folders, remove and copy files, copy dependency folders, write stamps and start `ridgunc`, the built program, tests and plugins through system calls and argument lists (`sys mkdir`, `remove file`, `remove dir`, `rename path`, `read bytes` / `write bytes`, `sys exec`), never through `/bin/sh`, so it works on Windows without `sh.exe`. Only the command of a user task (`fn :: task ... => String` in `build.ridgun`) goes to the shell.
   - On Windows the programs it builds for the host are named `<name>.exe`, and it finds `ridgunc.exe` next to `stable.exe`.
   - It starts `ridgunc` with `--quiet`: a successful build prints the line of `stable`, not one of `ridgunc` as well.

## Rationale
Providing `new`, `init`, `deps`, `add`, and `install` directly inside `stable` completes Ridgun's self-hosted developer experience without external package managers.

## Acceptance Criteria
- AC1: `stable new <dir>` creates a valid Ridgun project that passes `stable check` and `stable test`.
- AC2: `stable deps` and `stable add` manage `.stable/deps/` from package names locked in `omni.lock`, and `import` resolution searches `.stable/deps/`.
- AC4: `stable deps` rejects a path, a URL, a local lock entry and a name missing from `omni.lock`, and never runs git.
- AC6: after a source changes, `stable run` builds again and runs the new program, also when the change happens in the same second as the previous build; with no change it runs the existing binary without building.
- AC7: after `stable deps` with a package folder that has no `.ridgunlib`, the project's `src/` holds no file of the package, and a program that imports the package's module still builds.
- AC5: with a developer link, `stable deps` copies the linked folder and warns; a link whose package is not a name, whose folder holds a disallowed character, or whose `build.ridgun` names another project is refused; after `stable dev unlink` the name resolves through `omni.lock` again.
- AC3: `stable install` builds and installs native ELF64 binaries into `~/.local/bin/`.
- AC8: under Wine 10 without `sh.exe`, `stable.exe new demo`, then `check`, `build`, `run`, `test` and `clean` in `demo` work as on Linux (`target/demo.exe`; the second `run` does not build again).
