---
id: FR-COMP-013
title: User-Defined Generic Types, Lexical Closures, and Production Regression Hardening
status: implemented
priority: must
created: 2026-10-26
updated: 2026-10-26
depends_on:
  - FR-COMP-001
  - FR-COMP-002
  - FR-COMP-005
  - FR-COMP-009
  - FR-COMP-012
verified_by: []
---
# FR-COMP-013 — User-Defined Generic Types, Lexical Closures, and Production Regression Hardening

## Statement
The Ridgun language, `ridgunc` compiler, and `ridgun-libs` standard library SHALL provide user-defined generic types, anonymous lexical closures, leak-free cross-thread/agent memory reclamation, transitive subdirectory imports, and fast incremental runtime emission:

1. **User-Defined Generic Sum ADTs and Product Records (`type Name A B = ...`)**:
   - A `type` declaration MAY declare one or more uppercase type parameters (`A`..`Z` or multi-letter type variables listed after the type name) before `=`:
     - Generic Sum ADTs: `type Result T E = Ok T | Err E`, `type Box A = Box A`, `type Option A = Some A | None`
     - Generic Product Records: `type Page T = items: [T], total: Int`, `type Pair A B = fst: A, snd: B`
   - Parametric type references (`Result Int String`, `Page User`, `[Box Int]`) SHALL be accepted in `fn ::` signatures, nested record fields, and ADT constructor payloads.
   - Constructing, pattern-matching, reading fields, and updating fields (`with field = val`) on generic ADTs and records SHALL instantiate fresh type variables per use site so that distinct instantiations (`Ok 42` vs `Ok "hello"`, `Page [1, 2] 2` vs `Page ["a"] 1`) unify polymorphically without collision in the same module or function.

2. **Lexical Closures / Anonymous Functions (`(x => expr)`, `(a b => expr)`, `(=> expr)`, `((a b) => expr)`)**:
   - Ridgun SHALL support parenthesized anonymous lambda expressions (`(x => expr)`, `(a b => expr)`, `(=> expr)`, `((a b) => expr)`) as first-class function values (`(A => B)`, `(A, B => C)`, `(=> R)`, `((A, B) => C)`).
   - **Mandatory Parentheses**: Every lambda expression SHALL be enclosed in parentheses `(... => ...)`. Writing an unparenthesized `x => expr` on the right-hand side of `=` SHALL be rejected at compile time with `"lambda expression must be enclosed in parentheses: '(x => expr)'"`.
   - **Zero-Parameter Lambdas (`(=> expr)`)**: Consistent with Ridgun's `fn :: main => ()` rule forbidding `()` before `=>`, a zero-parameter lambda SHALL be written `(=> expr)` and its function type in signatures SHALL be written `(=> Type)`. Writing `(() => expr)` as a lambda or `(() => Type)` in a signature SHALL be rejected at compile time with a clear diagnostic.
   - **Multiple Parameters vs. Tuple Destructuring (`(a b => expr)` vs. `((a b) => expr)`)**: `(a b => expr)` declares a multi-parameter lambda (`(A, B => R)`), whereas `((a b) => expr)` (or `((a, b) => expr)`) declares a 1-parameter lambda that destructures a tuple (`((A, B) => R)`). When a call passes a multi-parameter lambda where a 1-tuple lambda is expected (or vice versa), the typechecker SHALL include an explicit diagnostic note distinguishing `(a b => ...)` from `((a b) => ...)`.
   - **Multi-Line Lambda Bodies**: A lambda MAY place a newline after `=>` followed by an indented multi-statement block (or `|` guard block) before the closing `)`:
     ```ridgun
     map (x =>
       doubled = x * 2
       doubled + offset
     ) [1, 2, 3]
     ```
   - **Uppercase Types vs. Lowercase Values (`(Conn => Conn)` vs. `(conn => conn)`)**: `(Conn => Conn)` is a function type and `(conn => conn)` is a lambda value. Writing uppercase type names `(Conn => Conn)` in an expression or lowercase parameter names `(conn => conn)` in a `fn ::` signature SHALL be rejected at compile time with a clear diagnostic.
   - An anonymous lambda MAY capture immutable local variables and function parameters from its enclosing lexical scope (`offset = 10`, `map (x => x + offset) xs`) and pass them to higher-order functions (`map`, `filter`, `fold`, or user-defined higher-order functions taking `(A => B)`).
   - Captured lexical bindings SHALL be lifted deterministically into partial-application closures compatible with `RMM1`/`RMM2` reference counting so that captured heap values (`String`, `[T]`, ADTs, records) are cloned on capture and dropped when the closure is dropped.

3. **Leak-Free Cross-Thread / Agent Arena Reclamation (`RG-069`) and Built-in `Option` (`RG-062`/`RG-063`)**:
   - The native `RMM` 16-arena sharded heap allocator (`x86_64.rg`) SHALL reclaim freed blocks across producer/consumer threads (via cross-arena free-list stealing before slab bump-allocation) so that stateful agents (`S M => S`, `S M => S R`) and multi-argument stateless agents (`A B => R`) exchanging heap messages across threads operate in bounded constant memory without accumulating `mmap` slabs.
   - `type Option A = Some A | None` SHALL be pre-registered as a built-in polymorphic ADT whenever no user-defined `Some`/`None` constructors are declared, allowing `try receive from ag` to return `Some val` or `None` directly without requiring manual `Option` boilerplate.

4. **Transitive Relative Module Imports in Subdirectories (`RG-025`) and Tail-Recursive `str split` (`RG-091`)**:
   - When a file imports a module from a subdirectory (`import "sub/a"` or `import sub/a`) and that module imports a sibling or nested module (`import b` or `import "b"`), `ridgunc` SHALL resolve transitive imports relative to the importing module's own directory first, falling back to the project root directory.
   - `str split` in `str.rg` (`str.rglib`) SHALL use a tail-recursive accumulator loop with a fast first-byte character check (`str_char_at`) before slicing so that splitting long strings does not grow the call stack or allocate redundant intermediate slices.

5. **Cached Native Runtime Image for Fast Compilation**:
   - `ridgunc` SHALL cache the static 90 KB native `.rt` runtime binary and linker script in `/tmp` (keyed by compiler runtime version) and reuse the cached image across invocations so repeated compilations and `stable` builds avoid re-serializing the runtime byte array on every invocation.

## Rationale
- Production feedback from Solstice identified five concrete blockers and ergonomic gaps:
  1. Cross-thread agent memory growth (`RG-069`) when producer and worker threads hash to different allocator arenas.
  2. Re-opened `try receive from` ergonomics (`RG-062`), transitive subdirectory imports (`RG-025`), and `str split` performance (`RG-091`).
  3. Missing user-defined generic types (`type Result T E`, `type Page T`), forcing persistence layers to use agents as untyped wrappers.
  4. Missing lexical closures (`(x => ...)`), forcing repetitive manual context threading across handlers.
  5. Compilation latency across multi-module SDK builds.

## Acceptance Criteria
1. **AC-1 (User-Defined Generic ADTs & Records)**: Declaring and using `type Result T E = Ok T | Err E` and `type Page T = items: [T], total: Int` with multiple concrete instantiations in the same program compiles, typechecks, and runs with expected output.
2. **AC-2 (Lexical Closures)**: Anonymous lambdas (`(x => x + k)`, `(a b => a + b + prefix)`) capturing outer `Int`, `String`, or record variables work in `map`, `filter`, `fold`, and user-defined higher-order functions without memory leaks.
3. **AC-3 (Zero Cross-Thread Agent Leak — `RG-069` & Built-in `Option` — `RG-062`)**: Sending and receiving 50,000+ heap messages (`String` and records) through stateful agents (`S M => S R`) and 2-argument agents completes with max RSS $\le 16\text{ MB}$ (zero extra 4 MB `mmap` slabs beyond startup baseline), and `try receive from ag` works without declaring `type Option`.
4. **AC-4 (Transitive Subdirectory Imports — `RG-025` & Fast `str split` — `RG-091`)**: `main.rg` importing `sub/a.rg` which imports sibling `b.rg` compiles and runs cleanly, and `str split` splits multi-thousand-part strings in tail-recursive $\mathcal{O}(N)$ time.
5. **AC-5 (Regression Battery)**: Dedicated regression tests for `RG-069`, `RG-025`, `RG-091`, `RG-062`, generic types, and closures pass under `python3 tests/run.py` and `./bin/stable test`.
