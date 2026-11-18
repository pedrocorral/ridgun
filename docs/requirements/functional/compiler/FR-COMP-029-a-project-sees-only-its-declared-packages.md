---
id: FR-COMP-029
title: A project sees only the packages it declares
status: implemented
priority: must
created: 2026-11-18
updated: 2026-11-18
depends_on:
  - FR-COMP-028
related:
  - ADR-0003
  - ADR-0005
verified_by: []
---
# FR-COMP-029 — A project sees only the packages it declares

## Statement
1. **A project.** A build is in a project when the folder it runs in has a `build.ridgun`. `stable` always runs `ridgunc` there.
2. **Declared packages only.** In a project an import that is not a module of the project is looked for only in the packages that `fn :: dependencies` of `build.ridgun` lists, in the project's `.stable/deps` (where `stable deps` puts them), and in the bundles that `stable deps` copied there. Other folders of `.stable/deps`, `~/.omni/lib`, `~/.local/lib/ridgun`, `~/.stable/deps` and the folders above the project are not looked into. This is the rule of Cabal: a module is visible only when its package is in `build-depends`.
3. **The forms of an entry.** `"libs"` and `"libs@0.3"` name the package `libs`. A path to a package folder (`"/home/me/libs"`) names the package of the last part of the path and the build looks into that folder. A path to one module file (`"/home/me/libs/src/main/ridgun/lib/str.ridgun"`) makes that module visible.
4. **A hidden package is named.** When an import is not found among the declared packages but an installed package has the module, the build fails with a message that names the package and the command to declare it (`stable add <package>`), as GHC does ("member of the hidden package"). When the module is found only as a loose file outside every declared package, the message gives its path.
5. **Outside a project** (no `build.ridgun` in the current folder) every installed package is visible, as before: the rule of plain `ghc`.

## Rationale
Before 1.0.31 a build looked into every folder of `.stable/deps`, into three folders of the home directory and into one fixed path of the machine the compiler was written on. A project could build on one machine and fail on another, a stale folder left by an old `stable deps` could win over a declared package, and two installed packages with a module of the same name were ambiguous (FR-COMP-028) even when the project used only one of them. With this rule the build depends on `build.ridgun` and on nothing else.

## Acceptance Criteria
1. **AC-1**: with `util` in `pk1` and `pk2` and `dependencies = ["pk2@1.0"]`, `import util` builds and gives the function of `pk2` (no ambiguity: `pk1` is hidden).
2. **AC-2**: with the same file, `import only` (a module of `pk1`) fails with `module 'only' is in the package 'pk1', which build.ridgun does not list in its dependencies; add it with 'stable add pk1'`.
3. **AC-3**: `dependencies = ["<path>/pk1"]` makes the modules of that folder visible.
4. **AC-4**: without a `build.ridgun` the same imports resolve as in FR-COMP-028.
5. **AC-5**: the 21 projects of the ecosystem checked on 2026-11-18 (`ridgunc check` of each main entry) give the same result as with 1.0.30.

## Not in scope
- `stable deps` does not remove from `.stable/deps` what `build.ridgun` no longer lists; such a folder is now hidden, and an import of it says so.
- Outside a project the fixed path `/home/boogie/ridgun/ridgun/.stable/deps` is still in the list of places (`all deps places` in `parser.ridgun`). It should go; the acceptance cases run outside a project and may depend on it.
