# docs/requirements/decisions/ — Architecture Decision Records (`ADR-*`)

| ID | File | Title | Status |
|---|---|---|---|
| `ADR-0001` | `ADR-0001-decouple-stable-from-ridgunc-compiler-internals.md` | Decouple `stable` build tool from `ridgunc` compiler internals | `accepted` |
| `ADR-0002` | `ADR-0002-migrate-x86-64-native-codegen-to-pure-llvm-ir.md` | Migrate `x86_64` native codegen backend to pure LLVM IR (`llc` + `ld`) | `accepted` |
| `ADR-0003` | `ADR-0003-stable-dependencies-are-package-names-installed-by-omni.md` | `stable` dependencies are package names installed by omni | `accepted` |
| `ADR-0004` | `ADR-0004-the-prelude-ships-with-ridgunc.md` | The prelude ships with `ridgunc`, at the lowest lookup priority | `accepted` |
| `ADR-0005` | `ADR-0005-developer-links-for-local-checkouts.md` | Developers build against local checkouts through links kept in `~/.stable/dev-links`, never in a project | `accepted` |
| `ADR-0006` | `ADR-0006-opaque-types-keyword-per-type.md` | Opaque types are declared with one keyword per type and checked when the parser resolves names | `accepted` |
| `ADR-0007` | `ADR-0007-windows-system-layer-traps-linux-syscalls.md` | On Windows, a system layer traps the runtime's Linux system calls (`ud2` + vectored handler) and does them with KERNEL32 | `accepted` |
| `ADR-0008` | `ADR-0008-platform-abstraction-layer-one-interface-per-target-implementation.md` | The PAL is one interface of Ridgun operations, implemented once per target and chosen at compile time; user definitions shadow builtins | `accepted` |
| `ADR-0009` | `ADR-0009-lowering-reads-the-types-of-the-checked-program.md` | The lowering reads the types of the checked program; no fact strings, no run-time shape guesses | `proposed` |
| `ADR-0010` | `ADR-0010-source-files-use-the-ridgun-extension.md` | Source files use `.ridgun` and library bundles `.ridgunlib`; the old `.rg` and `.rglib` are still read; `.rgc` and the bytecode VM are removed | `accepted` |
| `ADR-0011` | `ADR-0011-webassembly-is-a-native-backend.md` | WebAssembly is a native backend of ridgunc (NIR to wasm, runtime in wasm, PAL as imports); the playground runs `ridgunc.wasm` in the browser | `accepted` |
| `ADR-0012` | `ADR-0012-the-browser-compiler-reads-libraries-from-a-virtual-file-system.md` | The browser compiler reads libraries from a virtual file system in a Web Worker (`/lib/`, `/work/`, `ridgunc --libs /lib`): a manifest, and each `.ridgunlib` fetched from `ridgun.com/wasm/<version>/lib/` on first read | `accepted` |
| `ADR-0013` | `ADR-0013-the-whole-runtime-is-target-neutral-llvm-ir.md` | The whole runtime is written once in target-neutral LLVM IR and compiled by `llc` for each target; the pure backends embed the output; replaces the runtime as hand-written wasm of ADR-0011 | `accepted` |
| `ADR-0014` | `ADR-0014-threads-in-the-ir-runtime.md` | Threads live in the IR runtime: the runtime owns the worker pool and the jobs, the PAL gives threads and futexes, counts are atomic once there is a second thread, the allocator is sharded by thread; the backends carry no thread code | `accepted` |
| `ADR-0015` | `ADR-0015-compilation-is-memoized-and-parallel-by-call-graph-chunks.md` | Compilation is memoized by content and parallel by chunks of the call graph: the program is split by strongly connected components into modules that LLVM compiles together and caches by hash; build time becomes work/cores + critical path | `proposed` |
