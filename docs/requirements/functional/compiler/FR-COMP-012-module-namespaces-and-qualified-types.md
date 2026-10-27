---
id: FR-COMP-012
title: Module Namespaces, Qualified Types/Constructors/Functions, and Aliased Imports
status: implemented
priority: must
created: 2026-10-26
updated: 2026-10-27
depends_on:
  - FR-COMP-005
  - FR-COMP-006
verified_by: []
---
# FR-COMP-012 — Module Namespaces, Qualified Types/Constructors/Functions, and Aliased Imports

## Statement
The Ridgun language and `ridgunc` compiler SHALL support module-scoped namespaces and strict per-module import visibility for `type`, `expand type`, `fn ::`, and `op ::` declarations so that each module sees only its own declarations and the declarations of the modules it imports, allowing distinct modules to define identically named types, records, constructors, fields, and functions without collision while remaining 100% backward-compatible with unqualified imports:
1. **Module Scoping via `import` and `module ::`**:
   - Importing a `.rg` or `.rglib` module (`import http`, `import "crypto/sha256"`, `import db as d`) SHALL associate its top-level declarations with the module's canonical name (the module basename without directory or `.rg`/`.rglib` extension, e.g. `http`, `sha256`, `db`) and record a directed import edge from the importing module to the imported module.
   - An explicit `module :: <name>` directive (e.g., `module :: http`, `module :: db`, or `module :: main`) SHALL set the active module namespace for subsequent top-level declarations in the current file without clobbering outer module frames when nested files are imported.
2. **Module Aliases (`import <spec> as <alias>`) and Local Type Aliases (`type <Local> = <mod.Type>`)**:
   - `import <spec> as <alias>` SHALL bind `<alias>` within the importing module's scope to the imported module's canonical namespace so `<alias>.<Type>`, `<alias>.<Ctor>`, `<alias>.<field>`, and `<alias>.<fn>` resolve to that module's declarations even when different modules bind the same `<alias>` to different targets.
   - `type <LocalName> = <mod.TypeName>` SHALL define a local type and constructor alias for `<mod.TypeName>`.
3. **Strict Per-Module Import Visibility & Collision-Free Multi-Module Resolution**:
   - Two or more modules (including the root application module) MAY define `type` declarations with the same name (`type Config = ...`, `type Conn = ...`, `type Value = ...`, `type Changeset = ...`), record fields with the same name (`port: Int`), and functions with the same name (`fn :: query ...`, `fn :: json_get_str ...`, `fn :: validate_required ...`) without colliding when compiled together.
   - Inside any module `M` (including the root application module), unqualified references to types, constructors, record fields (including `with field = val`), and functions (including multi-word calls) SHALL resolve strictly according to `M`'s import graph in three priority tiers:
     1. **Tier 1 (Own module `M`)**: Declarations defined in `M` itself (across all files belonging to `module :: M`).
     2. **Tier 2 (Direct imports of `M`)**: Declarations defined in modules directly imported by `M` (`import D`). If a single direct import `D` of `M` defines the name, it resolves unambiguously to `D`'s declaration even if other modules in the program (not directly imported by `M`, such as transitive dependencies or the root application) also define the same name. If two or more direct imports of `M` define the same name and `M` does not define it, an unqualified reference in `M` SHALL be rejected as ambiguous unless qualified (`d1.Name` vs `d2.Name`).
     3. **Tier 3 (Transitive imports of `M`)**: Declarations defined in modules transitively imported through `M`'s direct imports, consulted only when neither Tier 1 nor Tier 2 defines the name.
   - Declarations in unimported sibling modules (and declarations in the root application module when `M` is an imported library module) SHALL NOT be visible unqualified inside `M`.
   - Across modules, declarations in module `m` (or alias `a`) SHALL be addressable via qualified dot notation:
     - Qualified types in signatures and type definitions (`http.Config`, `db.Config`, `a.Config`)
     - Qualified record and sum ADT constructors in expressions and patterns (`http.Config "localhost" 8080`, `http.Ok 200`, `http.Status.Ok 200`, `ParseResult.Error "msg"`)
     - Qualified record field accessors and `with` updates (`http.port cfg`, `db.port dcfg`, `cfg with http.port = 9090`)
     - Qualified function calls, including natural-language multi-word calls (`http.default_config`, `http.default config`, `http.check status cfg`)
   - Unambiguous declarations defined in an imported module SHALL remain accessible both **unqualified** (`Vec2`, `vec_add`) and **qualified** (`mathlib.Vec2`, `mathlib.vec_add`).

## Rationale
- Real-world libraries and applications naturally reuse domain type names (`Config`, `Conn`, `Value`, `Changeset`, `Error`, `Status`, `Client`, `Header`) and operation names (`query`, `json_get_str`, `connect`, `default_config`, `parse`, `validate_required`).
- Strict per-module import visibility ensures that a library `orm` importing `db_abstract` resolves `Conn`, `Value`, and `query` to `db_abstract` even when `solstice` and the application also define `Conn`, `Value`, or `query`, and that an application importing `solstice` (which internally imports `codec`) and `json` resolves `json_get_str` in the application to its direct import `json` while `solstice` resolves `json_get_str` to its own direct import `codec`.

## Acceptance Criteria
1. **AC-1 (Multi-Module Same-Named Types & Records)**: Importing or declaring two modules (`http` and `db`) that both define `type Config = ...` (with different field layouts and overlapping field names like `port: Int`) and `type Status = Ok ... | Error ...` compiles, typechecks, and executes without collision using `http.Config` and `db.Config`.
2. **AC-2 (Module Aliases & Type Aliases)**: `import db as d` allows `d.Config`, `d.Status`, `d.Ok`, `d.port`, and `d.connect`, and `type HttpConfig = http.Config` allows `HttpConfig` to be used interchangeably with `http.Config`.
3. **AC-3 (Qualified Constructors & Pattern Matching)**: Both `Mod.Ctor`, `Type.Ctor`, and `Mod.Type.Ctor` work in constructor expressions and pattern matching alongside type-directed unqualified constructors (`FR-COMP-005`).
4. **AC-4 (Qualified Functions & Multi-Word Calls)**: Both underscore (`http.check_status cfg`) and natural-language space-separated (`http.check status cfg`) qualified function calls resolve and execute properly.
5. **AC-5 (Strict Per-Module Import Visibility & Direct-Over-Transitive Priority)**: Each module resolves unqualified names only from its own namespace and its imported modules (`Tier 1: own -> Tier 2: direct imports -> Tier 3: transitive imports`), isolating library modules from sibling modules and root application declarations, and rejecting unqualified references to unimported sibling modules.
6. **AC-6 (100% Backward Compatibility)**: Existing single-module and multi-module programs using unqualified imports (`ridgunc`, `stable`, `tests/run.py`) continue to pass without modification.
