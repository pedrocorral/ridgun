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
- [x] Phase 2 (0.9.37): GenTensor storage (list vectors) with RMM for elements, on LLVM and x86-64; default and initial values (`tensor fill`, replaced by `with` in 0.9.39); bounds errors. ARM64: placeholders only.
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
- 2026-11-07: Initial-value syntax decided by the user (0.9.39): `Tensor[T * dims] with v` replaces `tensor fill`. Defaults: `0` for numbers, the character of code 0 for `Char`, `""`, `False`, `[]`; tuples, records and ADTs need `with`. Bug found on the way: a numeric allocation with 3 or more dimensions kept only the first 2 (heap corruption on write). Fix: new `NGtConv` mode 4 builds a numeric tensor of any rank from `[v, d1, ..., dn]` (LLVM `@__rg_gt_shape_tensor`; x86-64 bytes from `shapefill.s`); `:tensor-zeros:` with 3+ dimensions and `:tensor-with:` use it. Removed `__rg_gt_set1/2`, `__rg_gt_fill1/2` and the `tensor_fill` builtin.
- 2026-11-07: Strict mode rejected the `Char` default (`char_from_code` is a parser-made call with underscores). It is now the pseudo call `:char-zero:`. Comparing every `tests/cases/tensors` output on LLVM and `--target x86_64-elf` (earlier checks compared exit statuses only) showed older pure x86-64 gaps, all fixed in 0.9.39: a read of a tensor variable (`NIndex` with a negative count, a borrowed base) exited with status 101; `Tensor[Int * n]` and `Tensor[Int * r * c]` (`NCallBuiltin 88`) gave `()`; a `Real` written through the runtime index set lost its bits (x86-64 always, LLVM with three or more dimensions). Details in `docs/etc/gentensor.md`. Still missing on the pure x86-64 encoder, outside FR-COMP-020: builtins 89-99, which only LLVM implements (SHA-256 concat, element-wise `A_ij + B_ij`, row and column slices, tagged channels, thread id).

- 2026-11-07: Open questions closed by the user (0.9.41): an index out of range is an error on every tensor; a tensor sent to another agent is a copy, never the original (Ridgun has no shared type). Bounds: `@__rg_tensor_bounds` (LLVM), `x86 tensor bounds` (x86-64), `lower dim bounds` (slices). Before, a numeric read out of range gave 0, a write was dropped, `t_(0 - 1)` read the last element, and a column write past the end corrupted memory. Copies: `:msg-copy:` at every send and agent initial state. Tuple-pattern parameters (`(t, k)`) now get their tensor kind. Found on the way, not fixed: `ask v to (agent (f))` with the agent created inline prints nothing and drops the rest of the program's output (0.9.40 too); `echo` of a `Real` tensor prints raw bits and `Tensor [1.5, 2.5]` keeps 1.0 and 2.0 (older numeric tensor code).

- 2026-11-07 (0.9.42): `echo` and interpolation show numeric tensors by element type (`__rg_tensor_show_real`/`_int` helpers, kept when the type checker emits a `:show` fact; slices follow their base). Tensor literals: all-`Real` → `Tensor[Real]`, stored as bits (`NRealToBits` on LLVM, x86-64; nop on ARM64); all-`Int` → `Tensor[Int]`; mixed → compile error. Cases `real_tensor_literal_and_typed_echo.rg`, `tensor_literal_mixing_int_and_real_fails.rg`; Int-tensor outputs in 3 cases changed from `0.0` to `0`.

- 2026-11-07 (0.9.42, libs report `tensor-from-list-longitud.md`): `tensor from list` copied the whole RC vector of the list from index 0. A list value is a view `[2, vector, start]`: prepending (`[x] :: acc`) and `tail` move `start`, so a list built at run time gave extra default elements in front, and a tail gave its head back. `__rg_gt_vec_of` (LLVM) and `NGtConv` modes 0 and 1 (x86-64, `copy.s`, `totensor.s`) now start at `start` and use `len - start` elements. Case `tensor_from_list_built_at_run_time.rg`.

- 2026-11-07 (0.9.43, libs report: a String read cost 3.5 times an Int read): GenTensor reads now use `NListGet` (LLVM `@__rg_list_get`, x86-64 `listget.s`) instead of the generic bounds check plus runtime index, and `str len` has an LLVM fast path. The libs benchmark (`lectura.rg`, 1M reads): String 127 ms → 52-55 ms, Int 36 ms. Case `gen_tensor_2d_read_out_of_range_exits.rg`.

- 2026-11-08 (0.9.44, libs request `agrupar-contar-ordenar-primitivas.md`): native `sort by ints` / `sort by texts` (FR-COMP-021, `NSortBy`): stable merge sort of tagged indices, LLVM `@__rg_sort_by`, x86-64 `sortby.s` (1099 bytes), ARM64 placeholder. 100k keys: Int 10 ms, String 50 ms on LLVM (162 ms while the merge used `select`/`cmov`; branching lets the CPU overlap the key loads). Cases `lists/sort_by_ints_and_texts.rg`, `lists/sort_by_lists_of_different_lengths_fails.rg`, `perf/sort_by_100k_elements.rg`.

- 2026-11-08 (0.9.45, libs report `hashmap-tensores-y-campos.md`): (1) a record field of a lib that a program function shadowed: a field name that is also a function in another module (the root included) is now qualified like a field collision (`collect field fn collided`, parser), toolchain check in `tests/run.rg`; (2) writes through a `Tensor[Int]`/`Tensor[Real]` parameter to a generically made tensor were lost: they check `NIsList` when the program creates a tensor with a type-variable element (`__rg_gt_poly`); (3) `@` on `Real` tensors gave zeros: `lower real einsum` (loops) plus `NEinsumReal` / `@__rg_fast_einsum_real` on LLVM, and `@` results take the operands' element type; (4) GenTensor creation is native (`NGtConv` mode 5, `repeat.s`): 1M `String` elements 792 → 20 ms. Point 5 (call cost) → TASK-0059. Cases `generic_tensor_written_through_numeric_parameter.rg`, `real_tensor_contraction.rg`, `perf/tensor_creation_of_any_element_type.rg`.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-020-tensors-of-any-element-type.md`, `INDEX.md`
- `src/main/ridgun/lib/parser.rg`, `ast.rg`, `typecheck.rg`, `compiler.rg`, `elf64.rg`, `llvm.rg`, `x86_64.rg`, `arm64.rg`
- `tests/cases/tensors/real_tensor_elements_are_reals.rg`, `int_into_real_tensor_fails.rg`; `docs/lang/spec.md` (Tensors: element typing)
- Phases 2-4: `typecheck.rg`, `compiler.rg`, `parser.rg`, `elf64.rg`, `llvm.rg`, `x86_64.rg`, `arm64.rg`; `docs/etc/gentensor.md`, `docs/etc/INDEX.md`; `docs/lang/spec.md` (Tensors: element types); FR-COMP-018 narrowed to `Tensor_GPU`; FR-COMP-020 implementation status; `tests/README.md`
- Tests: `tests/cases/tensors/gen_tensor_*.rg` (13 cases), `tensor_literal_of_strings_fails.rg`, `tensor_gpu_of_string_fails.rg` and `tensor_gpu_of_bool_in_signature_fails.rg` (renamed from the FR-COMP-018 cases)
- `with` syntax (0.9.39): `parser.rg`, `typecheck.rg`, `compiler.rg`, `llvm.rg`, `x86_64.rg`; `docs/etc/gentensor.md` (mode 4); `docs/lang/spec.md`; FR-COMP-020; `tests/README.md`; tests `gen_tensor_defaults_and_with.rg` (renamed), `numeric_tensor_of_any_rank_with_value.rg`, `tensor_with_wrong_value_type_fails.rg`, `gen_tensor_without_default_fails.rg`, `gen_tensor_memory_is_freed.rg`, `real_tensor_writes_keep_their_bits.rg`; 0.9.41: `tensor_sent_to_agent_is_copied.rg`, `tensor_in_record_message_fails.rg`, `numeric_tensor_read_out_of_range_exits.rg`, `numeric_tensor_write_out_of_range_exits.rg`, `tensor_column_out_of_range_exits.rg`
- `build.rg`, `ridgunc/main.rg`, `stable/main.rg`, `llvm.rg`: 0.9.36 → 0.9.37 → 0.9.38 → 0.9.39 → 0.9.40 → 0.9.41 → 0.9.42 → 0.9.43 → 0.9.44 → 0.9.45
- 0.9.41: `src/test/ridgun/test parallel and tensors.rg` and `docs/book/{en,es,it}/08-*.md` (`compress block`: column pass `blamka p8`)
- 0.9.44 (FR-COMP-021): `docs/requirements/functional/compiler/FR-COMP-021-native-sort-by-keys.md`, `INDEX.md`; `parser.rg`, `typecheck.rg`, `compiler.rg`, `elf64.rg`, `llvm.rg`, `x86_64.rg`, `arm64.rg`; `docs/lang/spec.md` (Lists: sorting by keys); `docs/etc/gentensor.md`; `tests/cases/lists/sort_by_*.rg`, `tests/cases/perf/sort_by_100k_elements.rg`
- 0.9.45: `parser.rg`, `typecheck.rg`, `compiler.rg`, `elf64.rg`, `llvm.rg`, `x86_64.rg`, `arm64.rg`; `docs/lang/spec.md` (contraction rules); FR-COMP-020 status; `docs/etc/gentensor.md`; `tests/run.rg` (toolchain check 8); `tests/cases/tensors/generic_tensor_written_through_numeric_parameter.rg`, `real_tensor_contraction.rg`, `tests/cases/perf/tensor_creation_of_any_element_type.rg`; TASK-0059

## Verification performed (command → result, newest last)
- `aix docs validate` → 0 errors.
- Phase 1, 0.9.36: bootstrap from 0.9.35, stages 2 and 3 identical except the 3 PID bytes. `RIDGUNC=target/ridgunc bin/ridgunc run tests/run.rg` → 79 of 81 (the 2 known `stable deps` failures, RG-105 and RG-107). `test parallel and tensors.rg` → all passed. Real reads print 2.5, -1.25, 3.5 on LLVM and `--target x86_64-linux`. `../libs` `test tensor.rg` and `test linalg.rg` fail to type-check, as expected, until libs stores Ints in Int tensors.

- Phases 2-4, 0.9.37: bootstrap from 0.9.36, stages 2 and 3 identical except the 3 PID bytes. `RIDGUNC=$PWD/target/ridgunc bin/ridgunc run tests/run.rg` → 92 of 94 (the 2 known `stable deps` failures, RG-105 and RG-107). `test parallel and tensors.rg` → all passed. All `tests/cases/tensors` cases also pass on the pure x86-64 encoder (`--target x86_64-elf`). `cmm live blocks` delta 0 after 500 rounds of GenTensor create/write/convert/drop on both backends. Numeric tensor loop (20 x 1M writes and reads): 1.19 s on 0.9.36 and 0.9.37. `aix docs validate` → 0 errors. `../libs` `test tensor.rg` and `test linalg.rg` still fail to type-check until libs stores Ints in Int tensors (told in their request file).
- Shape patterns, 0.9.38: bootstrap from 0.9.37, stages 2 and 3 identical except the 3 PID bytes. Full suite → 93 of 95 (RG-105, RG-107). `test parallel and tensors.rg` → all passed. `gen_tensor_shape_patterns.rg` prints the same on LLVM and `--target x86_64-elf`; every `tests/cases/tensors` case has its expected exit status on the x86-64 encoder. `aix docs validate` → 0 errors.
- `with` syntax and x86-64 fixes, 0.9.39: bootstrap from 0.9.38, stages 2 and 3 identical except the 4 PID digits. Full suite → 96 of 98 (RG-105, RG-107). `test parallel and tensors.rg` → all passed. All 22 `tests/cases/tensors` cases give the same output and exit status on LLVM and `--target x86_64-elf` (11 run, 11 compile errors). `real_tensor_writes_keep_their_bits.rg` fails on the 0.9.39 build before the fix and passes after it. Numeric tensor loop (20M Int and Real writes and reads): 1.67-1.71 s on 0.9.38, 1.72-1.78 s on 0.9.39. `aix docs validate` → 0 errors.
- Bounds and copies, 0.9.41: bootstrap from 0.9.40, stages 2 and 3 identical except the 3 PID digits. Full suite → 101 of 103 (RG-105, RG-107). Every `tests/cases/tensors` and `tests/cases/agents` case gives the same output and exit status on LLVM and `--target x86_64-elf`. The bounds check found a real bug in `test parallel and tensors.rg`: `compress block` ran `blamka p16` (indices 0-15) on the 8-element columns of an `8 x 16` block, reading and writing past each column; the column pass is now `blamka p8`, and the same fix went into the book (en, es, it). After it, the suite passes on both backends with the same output. Numeric tensor loop: 1.69-1.72 s on 0.9.40 and 1.71-1.73 s on 0.9.41. `../libs` tests built with 0.9.40 and 0.9.41 give the same results: `argon2id` and `crypto` pass, `tls` and `mail` pass (the outputs differ only in live server session IDs), and `tensor` and `linalg` still fail to type-check (Real→Int, unchanged).
## Exact next actions
1. ARM64 runtime support for `Real` and GenTensors.
2. Open questions of FR-COMP-020: tensors inside lists, ADTs and records in messages; agent replies.

## Decisions / open questions
- Phase 1 design:
  - Parser keeps the element type in the type string: `Tensor:E(d1,d2)`, `Tensor:E` (bare `Tensor` stays `Tensor`, element unknown). Allocation `Tensor[E * n]` keeps `E` too.
  - `TyTensor RType [String]`: element type plus dims. Unknown element (bare `Tensor`, old literals) = `TyInt`, the current behaviour.
  - `infer index expr ty` returns the element type; `EIndexAssign` checks the value against it.
  - Runtime facts (from `x86 rt slot11 load real lit` in `x86_64.rg`): a `Real` is an RVal with tag `0` and the f64 bits at `+8`; a tensor stores raw 64-bit words, and a read returns them as an `Int` (tagged, or boxed i64 with header `-2^63`).
  - Lowering keeps a map from tensor variables to element types (parameters from the signature, locals from allocations, literals and calls with a declared return type) and emits a new `NRealFromBits` after `NIndex` on `Real` tensors: unwrap the Int to raw bits, build `[0, bits, 0]` and box it (`__rg_rt_box_rval`). LLVM helper in `llvm.rg`; machine code in `x86_64.rg` and `arm64.rg`.
- Decided (0.9.39): initial value is `Tensor[T * dims] with v`.
- Decided (0.9.41): bounds errors on every tensor; copies on send.
- Open (FR-COMP-020): tensors inside lists, ADTs and records in messages; replies with a tensor from an agent's state.
- Open (found 0.9.41): the type checker let `map blamka p16 in z_(,j)` pass an 8-element column to a `Tensor[U64 * 16]` parameter; the static shape check does not cover `map ... in` slices.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
