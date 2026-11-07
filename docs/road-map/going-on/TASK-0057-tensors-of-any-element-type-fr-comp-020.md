---
id: TASK-0057
title: Tensors of any element type (FR-COMP-020)
status: going-on
created: 2026-11-07
completed:
requirements: [FR-COMP-020]
tests: [TS-COMP-020]
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-020-tensors-of-any-element-type.md
  - docs/requirements/functional/compiler/FR-COMP-018-tensor-element-types-are-numeric.md
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/arm64.rg
scope:
  - src/main/ridgun/
  - build.rg
  - tests/cases/tensors/
  - tests/README.md
  - docs/lang/spec.md
  - docs/requirements/functional/compiler/
owner: agent-002
claimed: 2026-11-07T15:00:02Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0057 — Tensors of any element type (`FR-COMP-020`)

## Goal (one sentence)
Let `Tensor` hold any element type with the same syntax as numeric tensors, as promised to ridgun-libs instead of their `Array A` request.

## Plan
- [x] Phase 1 (0.9.36): element type in `TyTensor` and in the type checker; `t_(i)` has the element type (fixes `Real` elements typed as `Int`).
- [x] Phase 2 (0.9.37): GenTensor storage (list vectors) with RMM for elements, on LLVM and x86-64; default and initial values (`tensor fill`); bounds errors. ARM64: placeholders only.
- [x] Phase 3 (0.9.37): native `tensor from list` / `tensor to list` (`NGtConv`).
- [x] Phase 4 (0.9.37): compile errors for numeric-only operations, `Tensor_GPU` and parallel writes with non-numeric elements.
- [ ] Each phase: acceptance cases, spec.md, bootstrap fixed point, suites, `../libs` tensor tests, version bump.

## Progress log (append-only, newest last)
- 2026-11-07: Decided with the user: one name, `Tensor`, for every element type; GenTensor internally. FR-COMP-020 written and approved; promised to ridgun-libs in `/tmp/ridgun-compiler/2026-11-07/agrupar-contar-ordenar-primitivas.md` (4 phases, about 3-5 days).
- 2026-11-07: Phase 1 study. `infer index expr ty` types every tensor element as `Int`; the element type is dropped by the parser (`parse tensor bracket dims`). Lowering is untyped, and a tensor element is a raw 64-bit word: `t_(1) = 2.5` stores the f64 bits, `t_(1) = 1` stores an Int. `../libs` relies on this: `linalg.rg` and `test linalg.rg` declare `Tensor[Real * ...]` but write Int literals (`m_(0, 0) = 1`), add elements to Int accumulators (`la trace loop`) and check them with `assert int equals`. Typing elements by their declared type breaks that code.
- 2026-11-07: Decision (user): the declared element type is respected. `../libs` must change `Tensor[Real * ...]` to `Tensor[Int * ...]` where it stores integers; told in their request file. Origin: FR-COMP-010 (TASK-0022, commit 625a197, 2026-10-23) specified `Tensor[T]` with element type `T`, but the parser drops `T` and the type checker types every element as `Int`.
- 2026-11-07: Phase 1 implemented (0.9.36). Parser keeps the element type (`Tensor:E(dims)`; allocations wrapped in `:typed-tensor:`). Type checker: `TyTensor RType [String]`; reads have the element type; a write of another type is an error (`cannot store <T> in an element of tensor '<t>' of <E>`). Lowering: `RNativeEnv` carries the function's Real tensor variables (`real tensor vars`, `real tensor fns` in `compiler.rg`); a read of one emits `NRealFromBits` (LLVM helper `@__rg_real_from_bits`; inline x86-64 sequence; NOP on ARM64, whose runtime has no Real support yet: rt slot 11 is a NOP). `../libs` `test tensor.rg` (`test tensor matmul`) also stores Ints in Real tensors; added to their request file.

- 2026-11-07: Phases 2-4 implemented (0.9.37). A GenTensor is a list vector (1D) or a vector of row vectors (2D), not a new heap tag. The type checker sends a kind per tensor variable (`:tensor-elem:` infos: N, R, G, U) to the lowering. New native instructions `NIsList`, `NIsGen`, `NListSet` and `NGtConv` (LLVM IR in `llvm.rg`; x86-64 machine code in `x86_64.rg`, assembled from the source in `docs/etc/gentensor.md`; ARM64 placeholders). Bugs found on the way: the doubling allocator shared vectors when `n` was odd (writes vanished), so allocation is a plain append loop; tail-call arguments bypassed the native lowering of the `__rg_gt_*` stubs (`is gt pseudo name` excludes them). Phase 4 errors: einsum, arithmetic, matrix product, element-wise and bitwise operators, `not`, row and column helpers, parallel writes. `Tensor_GPU` keeps FR-COMP-018.
- 2026-11-07: Shape patterns on GenTensors (0.9.38): new element kind `L` (elements are lists) so that a 1D tensor of lists and a 2D tensor are told apart; `:tensor-pat:` lowering dispatches on `NIsList` and asks `__rg_gt_shape` for rank and dimensions.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-020-tensors-of-any-element-type.md`, `INDEX.md`
- `src/main/ridgun/lib/parser.rg`, `ast.rg`, `typecheck.rg`, `compiler.rg`, `elf64.rg`, `llvm.rg`, `x86_64.rg`, `arm64.rg`
- `tests/cases/tensors/real_tensor_elements_are_reals.rg`, `int_into_real_tensor_fails.rg`; `docs/lang/spec.md` (Tensors: element typing)
- Phases 2-4: `typecheck.rg`, `compiler.rg`, `parser.rg`, `elf64.rg`, `llvm.rg`, `x86_64.rg`, `arm64.rg`; `docs/etc/gentensor.md`, `docs/etc/INDEX.md`; `docs/lang/spec.md` (Tensors: element types); FR-COMP-018 narrowed to `Tensor_GPU`; FR-COMP-020 implementation status; `tests/README.md`
- Tests: `tests/cases/tensors/gen_tensor_*.rg` (13 cases), `tensor_literal_of_strings_fails.rg`, `tensor_gpu_of_string_fails.rg` and `tensor_gpu_of_bool_in_signature_fails.rg` (renamed from the FR-COMP-018 cases)
- `build.rg`, `ridgunc/main.rg`, `stable/main.rg`, `llvm.rg`: 0.9.36 → 0.9.37 → 0.9.38

## Verification performed (command → result, newest last)
- `aix docs validate` → 0 errors.
- Phase 1, 0.9.36: bootstrap from 0.9.35, stages 2 and 3 identical except the 3 PID bytes. `RIDGUNC=target/ridgunc bin/ridgunc run tests/run.rg` → 79 of 81 (the 2 known `stable deps` failures, RG-105 and RG-107). `test parallel and tensors.rg` → all passed. Real reads print 2.5, -1.25, 3.5 on LLVM and `--target x86_64-linux`. `../libs` `test tensor.rg` and `test linalg.rg` fail to type-check, as expected, until libs stores Ints in Int tensors.

- Phases 2-4, 0.9.37: bootstrap from 0.9.36, stages 2 and 3 identical except the 3 PID bytes. `RIDGUNC=$PWD/target/ridgunc bin/ridgunc run tests/run.rg` → 92 of 94 (the 2 known `stable deps` failures, RG-105 and RG-107). `test parallel and tensors.rg` → all passed. All `tests/cases/tensors` cases also pass on the pure x86-64 encoder (`--target x86_64-elf`). `cmm live blocks` delta 0 after 500 rounds of GenTensor create/write/convert/drop on both backends. Numeric tensor loop (20 x 1M writes and reads): 1.19 s on 0.9.36 and 0.9.37. `aix docs validate` → 0 errors. `../libs` `test tensor.rg` and `test linalg.rg` still fail to type-check until libs stores Ints in Int tensors (told in their request file).
- Shape patterns, 0.9.38: bootstrap from 0.9.37, stages 2 and 3 identical except the 3 PID bytes. Full suite → 93 of 95 (RG-105, RG-107). `test parallel and tensors.rg` → all passed. `gen_tensor_shape_patterns.rg` prints the same on LLVM and `--target x86_64-elf`; every `tests/cases/tensors` case has its expected exit status on the x86-64 encoder. `aix docs validate` → 0 errors.
## Exact next actions
1. User decision: the name of the initial-value allocation (provisional `tensor fill v n`, `tensor fill v r c`).
2. ARM64 runtime support for `Real` and GenTensors.
3. Open questions of FR-COMP-020: bounds checks on numeric tensors; sending a GenTensor to an agent.

## Decisions / open questions
- Phase 1 design:
  - Parser keeps the element type in the type string: `Tensor:E(d1,d2)`, `Tensor:E` (bare `Tensor` stays `Tensor`, element unknown). Allocation `Tensor[E * n]` keeps `E` too.
  - `TyTensor RType [String]`: element type plus dims. Unknown element (bare `Tensor`, old literals) = `TyInt`, the current behaviour.
  - `infer index expr ty` returns the element type; `EIndexAssign` checks the value against it.
  - Runtime facts (from `x86 rt slot11 load real lit` in `x86_64.rg`): a `Real` is an RVal with tag `0` and the f64 bits at `+8`; a tensor stores raw 64-bit words, and a read returns them as an `Int` (tagged, or boxed i64 with header `-2^63`).
  - Lowering keeps a map from tensor variables to element types (parameters from the signature, locals from allocations, literals and calls with a declared return type) and emits a new `NRealFromBits` after `NIndex` on `Real` tensors: unwrap the Int to raw bits, build `[0, bits, 0]` and box it (`__rg_rt_box_rval`). LLVM helper in `llvm.rg`; machine code in `x86_64.rg` and `arm64.rg`.
- Open (FR-COMP-020): syntax for an allocation with an initial value; bounds checks on numeric tensors; sending a non-numeric tensor to another agent.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
