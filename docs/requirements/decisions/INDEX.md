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
