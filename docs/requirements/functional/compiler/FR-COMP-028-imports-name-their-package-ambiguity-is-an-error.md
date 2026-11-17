---
id: FR-COMP-028
title: An import may name its package; an import found in two packages is an error
status: implemented
priority: must
created: 2026-11-17
updated: 2026-11-17
depends_on:
  - FR-COMP-006
  - FR-COMP-012
related:
  - ADR-0010
verified_by: []
---
# FR-COMP-028 — An import may name its package; an import found in two packages is an error

## Statement
1. **The path is part of the name.** `import lib.db.paquete` and `import lib/db/paquete` name the module in the file `lib/db/paquete.ridgun` (or its bundle), from the folder of the importing file. A dot and a slash mean the same. This is the rule of Haskell, where the module `Data.Map` is the file `Data/Map.hs`.
2. **The package may come first.** For a module of an installed package (a folder of `.stable/deps` or of `~/.omni/lib`), `import pk.db.mod` names the module `db/mod` of the package in the folder `pk`. It is looked for where a package keeps its modules: `pk/target/bundles/`, `pk/target/`, `pk/`, `pk/src/main/ridgun/lib/`, `pk/src/main/ridgun/`. `as` works as with any import.
3. **Without the package, the module must be in one package only.** `import mod` that is not a module of the project is looked for in every package folder of the first place that has it (the project's `.stable/deps` before `~/.omni/lib`). When two package folders have it, the build fails and the message names both packages and the import to write. The compiler does not pick one.
4. **What is not ambiguous.** A module of the project comes before any package. A package folder named as the module (`import foo` with the package `foo`) names that package. The same package in two places (the project and `~/.omni/lib`) is the nearer one.

## Rationale
Before 1.0.30 an import was resolved by file name alone and the first file found won, by the order of the folder listing: two packages with a module of the same name were confused in silence, and people concluded that a package and its module must have the same name. GHC stops with "Ambiguous module name ... found in multiple packages" and lets the program name the package (`PackageImports`); this requirement does the same with the path syntax the language already had.

## Acceptance Criteria
1. **AC-1**: with `util` in the packages `pk1` and `pk2`, `import util` fails the build with `import 'util' is ambiguous: the packages 'pk1' and 'pk2' both have it; write the package first, as in 'import pk1.util'`.
2. **AC-2**: `import pk1.util` and `import pk2.util` (or with slashes) each build and give the function of their package.
3. **AC-3**: a module that only one package has is imported by its bare name.
4. **AC-4**: `import pk3.bundled as b` finds `pk3/target/bundled.ridgunlib` and `b.packed` is its function.
5. **AC-5**: `import lib.db.paquete` finds `lib/db/paquete.ridgun` of the project.

## Not in scope
- An import that names no existing module is still not reported by itself (only the use of an undefined name is).
- Every folder of `.stable/deps` and `~/.omni/lib` is visible, not only the packages that `build.ridgun` declares. Haskell restricts imports to declared dependencies; doing so here changes `stable` and `omni` and is a decision of its own.
