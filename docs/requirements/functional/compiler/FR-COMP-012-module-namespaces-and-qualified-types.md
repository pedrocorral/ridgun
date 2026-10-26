---
id: FR-COMP-012
title: Module Namespaces, Qualified Types/Constructors/Functions, and Aliased Imports
status: implemented
priority: must
created: 2026-10-26
updated: 2026-10-26
depends_on:
  - FR-COMP-005
  - FR-COMP-006
verified_by: []
---
# FR-COMP-012 — Module Namespaces, Qualified Types/Constructors/Functions, and Aliased Imports

## Statement
The Ridgun language and `ridgunc` compiler SHALL support module-scoped namespaces for `type`, `expand type`, `fn ::`, and `op ::` declarations so that distinct modules can define identically named types, records, constructors, fields, and functions without collision while remaining 100% backward-compatible with unqualified imports:
1. **Module Scoping via `import` and `module ::`**:
   - Importing a `.rg` or `.rglib` module (`import http`, `import "crypto/sha256"`, `import db as d`) SHALL associate its top-level declarations with the module's canonical name (the module basename without directory or `.rg`/`.rglib` extension, e.g. `http`, `sha256`, `db`).
   - An explicit `module :: <name>` directive (e.g., `module :: http`, `module :: db`, or `module :: main`) SHALL set the active module namespace for subsequent top-level declarations in the current file.
2. **Module Aliases (`import <spec> as <alias>`) and Local Type Aliases (`type <Local> = <mod.Type>`)**:
   - `import <spec> as <alias>` SHALL bind `<alias>` to the imported module's canonical namespace so `<alias>.<Type>`, `<alias>.<Ctor>`, `<alias>.<field>`, and `<alias>.<fn>` resolve to that module's declarations.
   - `type <LocalName> = <mod.TypeName>` SHALL define a local type and constructor alias for `<mod.TypeName>`.
3. **Collision-Free Multi-Module Types, Records, Constructors, Fields, and Functions**:
   - Two or more modules MAY define `type` declarations with the same name (`type Config = ...`, `type Status = ...`, `type Error = ...`), record fields with the same name (`port: Int`), and functions with the same name (`fn :: default config => Config`, `fn :: connect Config => Status`) without colliding when imported together.
   - Inside module `m`, unqualified references to `m`'s own types, record constructors, record fields (including `with field = val`), and functions SHALL resolve to `m`'s own declarations.
   - Across modules, declarations in module `m` (or alias `a`) SHALL be addressable via qualified dot notation:
     - Qualified types in signatures and type definitions (`http.Config`, `db.Config`, `a.Config`)
     - Qualified record and sum ADT constructors in expressions and patterns (`http.Config "localhost" 8080`, `http.Ok 200`, `http.Status.Ok 200`, `ParseResult.Error "msg"`)
     - Qualified record field accessors and `with` updates (`http.port cfg`, `db.port dcfg`, `cfg with http.port = 9090`)
     - Qualified function calls, including natural-language multi-word calls (`http.default_config`, `http.default config`, `http.check status cfg`)
   - Unambiguous declarations defined in a single imported module SHALL remain accessible both **unqualified** (`Vec2`, `vec_add`) and **qualified** (`mathlib.Vec2`, `mathlib.vec_add`).

## Rationale
- Real-world libraries naturally reuse domain type names (`Config`, `Error`, `Status`, `Client`, `Header`, `Options`, `State`) and operation names (`connect`, `default_config`, `parse`, `validate`).
- Module-scoped namespaces eliminate global flat-namespace collisions across `.rg` and `.rglib` modules while preserving Ridgun's concise unqualified syntax whenever names are unambiguous.

## Acceptance Criteria
1. **AC-1 (Multi-Module Same-Named Types & Records)**: Importing or declaring two modules (`http` and `db`) that both define `type Config = ...` (with different field layouts and overlapping field names like `port: Int`) and `type Status = Ok ... | Error ...` compiles, typechecks, and executes without collision using `http.Config` and `db.Config`.
2. **AC-2 (Module Aliases & Type Aliases)**: `import db as d` allows `d.Config`, `d.Status`, `d.Ok`, `d.port`, and `d.connect`, and `type HttpConfig = http.Config` allows `HttpConfig` to be used interchangeably with `http.Config`.
3. **AC-3 (Qualified Constructors & Pattern Matching)**: Both `Mod.Ctor`, `Type.Ctor`, and `Mod.Type.Ctor` work in constructor expressions and pattern matching alongside type-directed unqualified constructors (`FR-COMP-005`).
4. **AC-4 (Qualified Functions & Multi-Word Calls)**: Both underscore (`http.check_status cfg`) and natural-language space-separated (`http.check status cfg`) qualified function calls resolve and execute properly.
5. **AC-5 (100% Backward Compatibility)**: Existing single-module and multi-module programs using unqualified imports (`ridgunc`, `stable`, `tests/run.py`) continue to pass without modification.
