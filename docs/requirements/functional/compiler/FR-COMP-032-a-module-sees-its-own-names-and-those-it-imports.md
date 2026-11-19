---
id: FR-COMP-032
title: A module sees its own names and those of the modules it imports
status: implemented
priority: must
created: 2026-11-19
updated: 2026-11-19
depends_on:
  - FR-COMP-024
  - FR-COMP-028
related: []
verified_by: []
---
# FR-COMP-032 — A module sees its own names and those of the modules it imports

## Statement
1. **What a module sees.** A module sees its own names, the names of the modules it imports, the names those modules offer with `export`, and the prelude, in that order. What a module imports for its own use is not seen from the modules that import it.
2. **`export m`.** A module that imports `m` and writes `export m` offers the names of `m` to the modules that import it. `m` is written as in the import: `export abs_schema`, `export web/router`.
3. **A name said with its module.** `abstract.TableDef` names what `abstract` defines or offers with `export`.
4. **One name in two modules.** A name that two of the modules a module uses offer does not build: `'X' is in more than one of the modules this one uses; write the module first, as in 'module.X'`.
5. **A name that does not arrive.** A name of a module that is not imported does not build: `'X' is in a module this one does not import: import that module, or the module you import must offer it with 'export'`.
6. **A file is one module.** Two files of one base name in two folders (`store/db` and a library's `db`) are two modules. `import store/db` imports that file alone.
7. **A function and a record field.** A function written with an underscore (`tk_name`) is found in its own module and in the modules that import it, also when a module that is not in scope has a record field of that name.
8. **Words and underscores.** Words are joined into a name only for a function. Two arguments `v n` are never read as a record field `v_n`.
9. **Words of one name among arguments.** Words that together name a function in scope (`Pool "x" vkd capabilities [] 0`) are that name; none of the words is looked up alone, so a function or a field `capabilities` of another module does not split it.
10. **A name of the prelude in a library.** A library, as sources or as a bundle, may define a name the prelude has (`list len`). The library's definition is the one its importers call, and the prelude's own functions keep working.

## Rationale
Up to 1.0.41 a module also saw what its imports imported, three steps away. A type of a library two levels below then clashed with a type of the program (ColdGrid, 2026-11-19). The rule is the one of Haskell: an import brings what the imported module offers, and nothing else.

## Acceptance Criteria
`tests/runtime/run-modules.sh` builds one small project for each:
1. **AC-1**: a name of a module imported by an imported module does not build (point 5).
2. **AC-2**: with `export inner` in the facade, the program prints `42` (point 2).
3. **AC-3**: the same with `import web/router` and `export web/router` (point 2).
4. **AC-4**: `TableDef` in two imported modules does not build and the message says to write the module first (point 4).
5. **AC-5**: `px2/db` and `vk/db` in one program: the type `Sealed` of `vault` is not ambiguous (point 6).
6. **AC-6**: `fn :: tk_name` in `aa` and a field `tk_name` in `bb`: `aa` calls its function (point 7).
7. **AC-7**: `geometric v n 0 big one big one` with a field `v_n` in another module builds (point 8).
8. **AC-8**: `Pool "vonkeep" vkd capabilities [] 0 0` with a field `capabilities` and a function `capabilities` in other modules builds (point 9).
9. **AC-9**: a bundle that defines `list len`: `list len [1, 2, 3]` calls the bundle's function (point 10).

## Not in scope
- Exporting single names, or hiding names of a module.
- `ridgunc check --explain <file>:<line>` (how each name of a line was resolved).
