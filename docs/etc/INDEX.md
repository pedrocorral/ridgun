# docs/etc/ — Architecture, VM, parallelism, and roadmap

| Path | What | Read when |
|---|---|---|
| `compiler_optimizations.md` | Compiler Optimization Catalog (`OPT-001`..`OPT-006`) for AST, RMM1/RMM2, `Tensor`, and SHA-256 codegen (`FR-COMP-011`) | Implementing, reviewing, or documenting compiler optimization passes in `compiler.ridgun` and `x86_64.ridgun` |
| `cmm_architecture.md` | Compiled Memory Management (CMM) & Conditional CMM (`ptr(a) != ptr(c)`) (`FR-COMP-002`) | Working on compile-time memory management, liveness, or alias-guarded drops |
| `gentensor.md` | GenTensor internals: representation, lowering kinds, native instructions and the x86-64 assembly of the list conversions (`FR-COMP-020`) | Changing tensors of non-numeric elements, `tensor from list`, `tensor to list` or their x86-64 encodings |
| `runtime_ext.md` | Shared runtime extension: packed `Tensor[U8]` layout, builtin ids 100-124, CRC-32, clocks through the vDSO, the C source and how to rebuild its bytes (`FR-COMP-022`, `FR-COMP-023`) | Changing byte tensors, byte I/O, `crc32 range`, the clocks, or adding a routine shared by the x86-64 and LLVM backends |
| `runtime_windows.md` | Windows system layer: image layout, how a trapped `syscall` becomes a KERNEL32 call, the table of calls, paths, processes, limits, the C source and how to rebuild its bytes (`FR-COMP-015`, `ADR-0007`) | Changing `pe64.ridgun`, the runtime or a code-generator snippet that makes a system call, or adding a call to the Windows layer |
| `low_level_ridgun_runtime_design.md` | Portable low-level Ridgun runtime kernel design vs symbolic assembly (`TASK-0013`) | Evaluating or implementing freestanding/unboxed Ridgun runtime primitives |
| `next_gen_architecture.md` | Approved v2.0 architectural blueprint (DAGs, Freeze, Regions, Tiering, `--seed`) | Implementing v2.0 VM, memory, or static analysis |
| `parallelism.md` | Green threads, work-stealing scheduler, mailboxes, channels | Working on scheduler, threads, or concurrency |
| `interop.md` | C/C++ FFI and Python bridge specification | Working on FFI or PyO3 interop |
| `process.md` | Spiral + V-Model + OWASP SAMM methodology | Planning verification and security gates |
| `fused_elementwise.md` | How an element-wise tensor expression becomes one loop: the `:fuse:` node, the program text, joined statements, results in place, packed `U16`/`U32` tensors, the three vector versions (`FR-COMP-031`) | Changing element-wise operators, `core/fuse.ll`, `llvm fuse fn`, or reading why a tensor loop is slow |
