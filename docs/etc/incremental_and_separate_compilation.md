# Incremental and separate compilation: options for future work

*Status: analysis, 2026-11-17. Source: request 5 of the Vonkeep project (`/tmp/ridgunc-requests.md`). Nothing here is decided except what ADR-0015 already does. Each option is a legitimate direction; the choice is made with measurements.*

## The request

Vonkeep (about 10 000 lines of engine, 16 test programs, each importing the engine) builds a test program for every change. Measured on 2026-11-17 on their side:

| Test program | Build | Run |
|---|---|---|
| smallest | 6 to 9 s | under 1 s |
| middle | 20 to 22 s | 2 to 4 s |
| largest | 34 s | 0.5 s |
| all 16 from nothing | about 200 s | about 30 s |

The run is seconds, the build is minutes. A change of one function rebuilds all 16 programs, because each holds the whole engine, and the smallest program already pays a fixed 5 s, which suggests that every imported source is parsed and type-checked at each build. A static map of what each test reaches does not help: every test reaches about 1 830 of the engine's blocks.

They ask, in this order of value: (1) a build that recompiles only what changed, (2) a compiled form of a library that programs link instead of source text (today `stable build lib` gives a 566 KB ASCII `.ridgunlib` with one summary line per function, and an `import` compiles the 1 592 functions again), (3) a flag with the time of each phase.

## What exists today

- **(3) is done:** `ridgunc build --timings` (1.0.22). On the compiler's own self-build (52 s): load 0.4 s, tokenize 0.8 s, parse 18.9 s, typecheck and analysis 5.4 s, lowering 18.4 s, writing the IR 2.2 s, LLVM 5.7 s with a warm cache.
- **LLVM is incremental and parallel** (ADR-0015): the IR is split into parts, each part's object is cached by the hash of its content. Self-build 164 s to 53 s cold. This is the last stage only.
- **The front end and lowering are not cached**, and they are now the larger part: in the self-build, parse plus lowering are 37 s of 52 s. This is the cost Vonkeep sees.
- The compiler is **whole-program**. Several optimizations use information from the whole program: which parameters are borrowed (`#b` masks, OPT-018) from all the callers, which functions are called in tail position (OPT-019), the numbering of functions, the string pool, the field map. A library compiled alone would need that information as part of its interface.

## Options

These are not exclusive; they are ordered by how much they change the design.

### A. Cache of the front end by content (no change of model)
Keep, for each module, the result of its front end (tokens, AST, type information) under the hash of its source text and of the hashes of the modules it imports, plus the compiler version. A module whose key did not change is not read, parsed or type-checked again. Emission, optimization and linking still see the whole program.
- **Gain:** removes the repeated parse and typecheck of the imported engine (the fixed cost of 5 s on the smallest program, and most of the 20 s on the middle ones, to be measured with `--timings`).
- **Cost:** a stable, versioned serialization of the AST and of the type environment; keys and invalidation (a change in a module invalidates its dependents). The cache file format is part of the compiler version.
- **Same idea as:** the build caches of Go (content hash of a package's inputs) and the query caches of the Rust compiler's incremental mode.

### B. Cache of the lowered code by content
The same, one stage later: keep the lowered native code (NIR) of each function under the hash of the function and of what its lowering reads (the types of its callees, borrow masks, the field map). A change of one function lowers only it and the functions whose inputs changed.
- **Gain:** the lowering time (18 s of the self-build) becomes proportional to the change.
- **Cost:** the lowering reads global tables, so each function's key must list exactly what it read; an omission is a stale result. This needs a dependency-tracking discipline in the compiler (what a function's lowering asked of the environment).

### C. Separate compilation with explicit interfaces
A library is compiled once into a unit that holds compiled code and an **interface**; a program compiles only itself and links the units. This is what most compiled languages do: Rust crates (`rlib` holds metadata and object code), OCaml (`.cmi` interface, `.cmx` for cross-module optimization), Swift (module interfaces), C and C++ (headers and object files).
- **Gain:** the library is compiled when it changes, not for each program that uses it; the 16 test programs would each compile only their own code.
- **Cost, and what it needs from the design:**
  1. The **interface of a function** becomes part of its ABI: its type, its arity, its borrow mask, whether it is a tail-call target, how it is passed in the tail call. Today these are computed by looking at all the callers; they would have to be decided from the function alone (or fixed by declaration) so that a caller in another unit can follow them. A change of interface recompiles the dependents (as OCaml rebuilds the modules that depend on a changed `.cmi`).
  2. **Global tables** (function numbers, string pool, field map, generic instances) must be per unit with a link step that merges them.
  3. **Optimizations across units** (inlining, the borrow inference of a callee that is in another unit) are lost or must be exported in the interface, as `.cmx` does in OCaml.
  4. The `.ridgunlib` format changes from "source plus summaries" to "interface plus compiled code".
- **Risk:** the largest, and it touches the ADR on how functions are called. It needs its own ADR and a plan to migrate the libraries.

### D. A compiled library form that is only a cache
A `.ridgunlib` that holds the serialized front end (option A) or the lowered code (option B) of the library, so `import` loads it without reading source. It answers Vonkeep's item 2 without separate compilation: the library is still compiled together with the program, but from a stored form.

## Suggested order and acceptance

1. **A**, because it attacks the measured fixed cost with no change of model. Done when the smallest Vonkeep-like program (a small `main` importing a large generated library) builds in a time that depends on the size of `main` and not of the library on the second build, shown by a segment test with a time limit (docs/etc/testing_in_segments.md).
2. **B**, if `--timings` shows lowering still dominating after A.
3. **C**, if A and B leave builds dominated by compiling the library's code for each program; decided by an ADR that fixes the interface of a function (point 1 above) before any code is written.
4. **D** can be built over A or B at any time, and gives the `.ridgunlib` that Vonkeep describes.

Every step keeps the rule that a cache key is the hash of everything the result depends on, so a result with unchanged inputs is reused and any other is recomputed (ADR-0015).

## Related

ADR-0015, TASK-0099, `docs/etc/testing_in_segments.md`, `docs/etc/compiler_optimizations.md` (OPT-018, OPT-019).
