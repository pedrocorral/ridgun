; src/main/runtime/abi/helpers.ll
; The helpers of the compiled program that are not inlined (ADR-0013): tensor
; slices and bit operations, list and tensor conversions, the stable sort,
; SHA-256, the slow paths of the inline helpers. Both backends call them by
; name; they are compiled once into the runtime object.
; Not a module of its own: the build script compiles abi/inline.ll followed
; by this file as one module (the declarations and the inline helpers come
; from there).
;
; Notes kept from the compiler source, where these helpers were strings:
; TASK-0096 (ADR-0014): the old runtime's pool lives at a fixed address that
; only its blob knows. With the IR runtime a job is spawned by the runtime
; builtin 57: it hands the job to a worker thread or runs it at once. The old
; helper stays for the programs linked with the old blob.

; The body of the length of a String or List by `NAdtField slot -1` (the
; block after the label `str_len:`). An IR runtime List can be a tail that
; shares the vector of the list it came from, so its length is the length of
; the vector minus the list's start (the third word of the list value).

; `@__rg_real_to_int_bits`: the runtime index set (`@__rg_rt_index_set`)
; stores an `Int`; a `Real` would lose its bits. It turns a `Real` into the
; `Int` with the same 64 bits (dropping the `Real`); other values pass.
; `@__rg_tensor_bounds`: before the runtime index calls, stop with
; `runtime error: tensor index out of range` (stderr, exit status 1) when
; an Int index of a numeric tensor (heap tag 5) is outside its dimension.
; Fewer indices than the rank (a row) check only the indices given.

; FR-COMP-021: `sort by ints` / `sort by texts` (`NSortBy`). A stable
; bottom-up merge sort of tagged indices; keys are read through the index.
; The spare buffer holds tagged Ints at the end and is freed as a list.
; The merge branches on each comparison (takei / takej) instead of a
; select: with a select every step waits for the previous key loads
; (index, String, header, bytes), and texts sort about 3 times slower.

; FR-COMP-022: one-dimensional reads and writes of a `Tensor[U8]`
; (builtins 105 and 106 with one index) in line: an Int index in range and,
; for a write, an Int value in 0..255 go straight to the byte; anything else
; goes to the shared runtime extension (`@__rg_rt_ext`), which stops with
; the runtime error. Layout: data word 0 = rank, word 1 = length, bytes
; from word 2 (`docs/etc/runtime_ext.md`).

@__rg_tensor_oob_msg = private unnamed_addr constant [41 x i8] c"runtime error: tensor index out of range\0A"
@__rg_sort_len_msg = private unnamed_addr constant [57 x i8] c"runtime error: sort by: the lists have different lengths\0A"
@__rg_sha256_k = private unnamed_addr constant [64 x i32] [ i32 1116352408, i32 1899447441, i32 -1245643825, i32 -373957723, i32 961987163, i32 1508970993, i32 -1841331548, i32 -1424204075, i32 -670586216, i32 310598401, i32 607225278, i32 1426881987, i32 1925078388, i32 -2132889090, i32 -1680079193, i32 -1046744716, i32 -459576895, i32 -272742522, i32 264347078, i32 604807628, i32 770255983, i32 1249150122, i32 1555081692, i32 1996064986, i32 -1740746414, i32 -1473132947, i32 -1341970488, i32 -1084653625, i32 -958395405, i32 -710438585, i32 113926993, i32 338241895, i32 666307205, i32 773529912, i32 1294757372, i32 1396182291, i32 1695183700, i32 1986661051, i32 -2117940946, i32 -1838011259, i32 -1564481375, i32 -1474664885, i32 -1035236496, i32 -949202525, i32 -778901479, i32 -694614492, i32 -200395387, i32 275423344, i32 430227734, i32 506948616, i32 659060556, i32 883997877, i32 958139571, i32 1322822218, i32 1537002063, i32 1747873779, i32 1955562222, i32 2024104815, i32 -2067236844, i32 -1933114872, i32 -1866530822, i32 -1538233109, i32 -1090935817, i32 -965641998 ], align 16
@__rg_sha256_lock = internal global i32 0, align 4
@__rg_sha256_cache_valid = internal global [2 x i32] zeroinitializer, align 4
@__rg_sha256_cache_next = internal global i32 0, align 4
@__rg_sha256_cache_keys = internal global [2 x [64 x i8]] zeroinitializer, align 16
@__rg_sha256_cache_states = internal global [2 x [8 x i32]] zeroinitializer, align 16

define i64 @__rg_box_i64_slow(i64 %v) noinline nounwind {
entry:
  %buf = alloca [3 x i64], align 8
  store i64 -9223372036854775808, ptr %buf, align 8
  %p1 = getelementptr inbounds [3 x i64], ptr %buf, i64 0, i64 1
  store i64 %v, ptr %p1, align 8
  %p2 = getelementptr inbounds [3 x i64], ptr %buf, i64 0, i64 2
  store i64 0, ptr %p2, align 8
  %boxed = call i64 @__rg_rt_box_rval(ptr %buf)
  ret i64 %boxed
}

define i64 @__rg_cmm_drop_val_slow(i64 %v) noinline nounwind {
entry:
  %tmp = alloca i64, align 8
  store i64 %v, ptr %tmp, align 8
  %r = call i64 @__rg_rt_cmm_drop_slot(ptr %tmp)
  ret i64 %r
}

define i64 @__rg_make_empty_list() noinline nounwind {
entry:
  %tmp = alloca i64, align 8
  store i64 0, ptr %tmp, align 8
  %r = call i64 @__rg_rt_make_list(ptr %tmp, i64 0)
  ret i64 %r
}

define i64 @__rg_make_list_1(i64 %v0) noinline nounwind {
entry:
  %tmp = alloca i64, align 8
  store i64 %v0, ptr %tmp, align 8
  %r = call i64 @__rg_rt_make_list(ptr %tmp, i64 1)
  ret i64 %r
}

define i64 @__rg_make_tuple_2(i64 %v0, i64 %v1) noinline nounwind {
entry:
  %tmp = alloca [2 x i64], align 8
  %p0 = getelementptr inbounds [2 x i64], ptr %tmp, i64 0, i64 0
  %p1 = getelementptr inbounds [2 x i64], ptr %tmp, i64 0, i64 1
  store i64 %v0, ptr %p0, align 8
  store i64 %v1, ptr %p1, align 8
  %r = call i64 @__rg_rt_make_tuple(ptr %tmp, i64 2)
  ret i64 %r
}

define i64 @__rg_bin_op_u64_or_slow(i64 %op_id, i64 %lhs, i64 %rhs) noinline nounwind {
entry:
  %tmp_lhs = alloca i64, align 8
  %lb0 = and i64 %lhs, 1
  %l_is_imm = icmp ne i64 %lb0, 0
  br i1 %l_is_imm, label %lhs_imm, label %lhs_chk_heap
lhs_imm:
  %lx_imm = ashr i64 %lhs, 1
  br label %chk_rhs
lhs_chk_heap:
  %l_nn = icmp ne i64 %lhs, 0
  %l_l3 = and i64 %lhs, 7
  %l_ptr = icmp eq i64 %l_l3, 0
  %l_ok = and i1 %l_nn, %l_ptr
  br i1 %l_ok, label %lhs_load_hdr, label %rt_fallback
lhs_load_hdr:
  %lp = inttoptr i64 %lhs to ptr
  %lhdr = load i64, ptr %lp, align 8
  %l_is_u64 = icmp eq i64 %lhdr, -9223372036854775808
  br i1 %l_is_u64, label %lhs_heap_u64, label %rt_fallback
lhs_heap_u64:
  %lpay_p = getelementptr inbounds i8, ptr %lp, i64 8
  %lx_heap = load i64, ptr %lpay_p, align 8
  br label %chk_rhs
chk_rhs:
  %x = phi i64 [ %lx_imm, %lhs_imm ], [ %lx_heap, %lhs_heap_u64 ]
  %ldrop = phi i64 [ 0, %lhs_imm ], [ %lhs, %lhs_heap_u64 ]
  %rb0 = and i64 %rhs, 1
  %r_is_imm = icmp ne i64 %rb0, 0
  br i1 %r_is_imm, label %rhs_imm, label %rhs_chk_heap
rhs_imm:
  %ry_imm = ashr i64 %rhs, 1
  br label %exec_u64
rhs_chk_heap:
  %r_nn = icmp ne i64 %rhs, 0
  %r_l3 = and i64 %rhs, 7
  %r_ptr = icmp eq i64 %r_l3, 0
  %r_ok = and i1 %r_nn, %r_ptr
  br i1 %r_ok, label %rhs_load_hdr, label %rt_fallback
rhs_load_hdr:
  %rp = inttoptr i64 %rhs to ptr
  %rhdr = load i64, ptr %rp, align 8
  %r_is_u64 = icmp eq i64 %rhdr, -9223372036854775808
  br i1 %r_is_u64, label %rhs_heap_u64, label %rt_fallback
rhs_heap_u64:
  %rpay_p = getelementptr inbounds i8, ptr %rp, i64 8
  %ry_heap = load i64, ptr %rpay_p, align 8
  br label %exec_u64
exec_u64:
  %y = phi i64 [ %ry_imm, %rhs_imm ], [ %ry_heap, %rhs_heap_u64 ]
  %rdrop = phi i64 [ 0, %rhs_imm ], [ %rhs, %rhs_heap_u64 ]
  %c_ld = icmp ne i64 %ldrop, 0
  br i1 %c_ld, label %do_ldrop, label %after_ldrop
do_ldrop:
  %ign_l = call i64 @__rg_rt_drop_val(i64 %ldrop)
  br label %after_ldrop
after_ldrop:
  %c_rd = icmp ne i64 %rdrop, 0
  br i1 %c_rd, label %do_rdrop, label %after_rdrop
do_rdrop:
  %ign_r = call i64 @__rg_rt_drop_val(i64 %rdrop)
  br label %after_rdrop
after_rdrop:
  %res_u64 = call i64 @__rg_exec_int_op(i64 %op_id, i64 %x, i64 %y)
  ret i64 %res_u64
rt_fallback:
  store i64 %lhs, ptr %tmp_lhs, align 8
  %res_rt = call i64 @__rg_rt_bin_op(i64 %op_id, ptr %tmp_lhs, i64 %rhs)
  ret i64 %res_rt
}

define i64 @__rg_str_char_at_slow(i64 %sv, i64 %iv) noinline nounwind {
entry:
  %tmp = alloca [2 x i64], align 8
  %p0 = getelementptr inbounds [2 x i64], ptr %tmp, i64 0, i64 0
  %p1 = getelementptr inbounds [2 x i64], ptr %tmp, i64 0, i64 1
  %c_sv = call i64 @__rg_fast_clone_slot(i64 %sv)
  store i64 %c_sv, ptr %p0, align 8
  store i64 %iv, ptr %p1, align 8
  %res = call i64 @__rg_rt_builtin(i64 40, ptr %tmp, i64 2)
  ret i64 %res
}

define i64 @__rg_builtin_str_len(ptr %slots_ptr) noinline nounwind {
entry:
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %sv = load i64, ptr %s0, align 8
  %snn = icmp ne i64 %sv, 0
  %sl3 = and i64 %sv, 7
  %sptr_ok = icmp eq i64 %sl3, 0
  %sok = and i1 %snn, %sptr_ok
  br i1 %sok, label %chk_tag, label %slow
chk_tag:
  %sp = inttoptr i64 %sv to ptr
  %stag = load i32, ptr %sp, align 4
  %is_str = icmp eq i32 %stag, 1
  br i1 %is_str, label %fast, label %slow
fast:
  %hp = getelementptr inbounds i8, ptr %sp, i64 8
  %hdr = load ptr, ptr %hp, align 8
  %lp = getelementptr inbounds i8, ptr %hdr, i64 16
  %dlen = load i64, ptr %lp, align 8
  %shl = shl i64 %dlen, 1
  %res = or i64 %shl, 1
  store i64 0, ptr %s0, align 8
  %ign = call i64 @__rg_rt_drop_val(i64 %sv)
  ret i64 %res
slow:
  %res_slow = call i64 @__rg_rt_builtin(i64 10, ptr %slots_ptr, i64 1)
  ret i64 %res_slow
}

define i64 @__rg_builtin_str_char_at(ptr %slots_ptr) noinline nounwind {
entry:
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %sv = load i64, ptr %s0, align 8
  %iv = load i64, ptr %s1, align 8
  %ibit = and i64 %iv, 1
  %is_i = icmp ne i64 %ibit, 0
  br i1 %is_i, label %chk_s, label %slow
chk_s:
  %snn = icmp ne i64 %sv, 0
  %sl3 = and i64 %sv, 7
  %sptr_ok = icmp eq i64 %sl3, 0
  %sok = and i1 %snn, %sptr_ok
  br i1 %sok, label %chk_tag, label %slow
chk_tag:
  %sp = inttoptr i64 %sv to ptr
  %stag = load i32, ptr %sp, align 4
  %is_str = icmp eq i32 %stag, 1
  br i1 %is_str, label %chk_bounds, label %slow
chk_bounds:
  %idx = ashr i64 %iv, 1
  %hp = getelementptr inbounds i8, ptr %sp, i64 8
  %hdr = load ptr, ptr %hp, align 8
  %lp = getelementptr inbounds i8, ptr %hdr, i64 16
  %dlen = load i64, ptr %lp, align 8
  %in_b = icmp ult i64 %idx, %dlen
  br i1 %in_b, label %load_b, label %oob
load_b:
  %dp = getelementptr inbounds i8, ptr %hdr, i64 8
  %dptr = load ptr, ptr %dp, align 8
  %bp = getelementptr inbounds i8, ptr %dptr, i64 %idx
  %b8 = load i8, ptr %bp, align 1
  %b64 = zext i8 %b8 to i64
  %shl = shl i64 %b64, 1
  %res_in = or i64 %shl, 1
  br label %finish_fast
oob:
  br label %finish_fast
finish_fast:
  %res_fast = phi i64 [ %res_in, %load_b ], [ -1, %oob ]
  store i64 0, ptr %s0, align 8
  store i64 0, ptr %s1, align 8
  %ign = call i64 @__rg_rt_drop_val(i64 %sv)
  ret i64 %res_fast
slow:
  %res_slow = call i64 @__rg_rt_builtin(i64 40, ptr %slots_ptr, i64 2)
  ret i64 %res_slow
}

define i64 @__rg_tensor_index_1d_slow(i64 %base_val, i64 %iv) noinline nounwind {
entry:
  %tmp_base = alloca i64, align 8
  %tmp_idx = alloca i64, align 8
  %cloned = call i64 @__rg_rt_clone_slot(i64 %base_val)
  store i64 %cloned, ptr %tmp_base, align 8
  store i64 %iv, ptr %tmp_idx, align 8
  %bc = call i64 @__rg_tensor_bounds(i64 %base_val, ptr %tmp_idx, i64 1)
  %res = call i64 @__rg_rt_index(ptr %tmp_base, ptr %tmp_idx, i64 1)
  ret i64 %res
}

define i64 @__rg_tensor_index_2d_slow(i64 %base_val, i64 %iv0, i64 %iv1) noinline nounwind {
entry:
  %tmp_base = alloca i64, align 8
  %tmp_idx = alloca [2 x i64], align 8
  %cloned = call i64 @__rg_rt_clone_slot(i64 %base_val)
  store i64 %cloned, ptr %tmp_base, align 8
  %ip0 = getelementptr inbounds [2 x i64], ptr %tmp_idx, i64 0, i64 0
  %ip1 = getelementptr inbounds [2 x i64], ptr %tmp_idx, i64 0, i64 1
  store i64 %iv0, ptr %ip0, align 8
  store i64 %iv1, ptr %ip1, align 8
  %bc = call i64 @__rg_tensor_bounds(i64 %base_val, ptr %tmp_idx, i64 2)
  %res = call i64 @__rg_rt_index(ptr %tmp_base, ptr %tmp_idx, i64 2)
  ret i64 %res
}

define i64 @__rg_tensor_index_set_1d_slow(i64 %base_val, i64 %iv, i64 %val) noinline nounwind {
entry:
  %tmp_base = alloca i64, align 8
  %tmp_idx = alloca i64, align 8
  store i64 %base_val, ptr %tmp_base, align 8
  store i64 %iv, ptr %tmp_idx, align 8
  %bc = call i64 @__rg_tensor_bounds(i64 %base_val, ptr %tmp_idx, i64 1)
  %vb = call i64 @__rg_real_to_int_bits(i64 %val)
  %res = call i64 @__rg_rt_index_set(ptr %tmp_base, ptr %tmp_idx, i64 1, i64 %vb)
  ret i64 %res
}

define i64 @__rg_tensor_index_set_2d_slow(i64 %base_val, i64 %iv0, i64 %iv1, i64 %val) noinline nounwind {
entry:
  %tmp_base = alloca i64, align 8
  %tmp_idx = alloca [2 x i64], align 8
  store i64 %base_val, ptr %tmp_base, align 8
  %ip0 = getelementptr inbounds [2 x i64], ptr %tmp_idx, i64 0, i64 0
  %ip1 = getelementptr inbounds [2 x i64], ptr %tmp_idx, i64 0, i64 1
  store i64 %iv0, ptr %ip0, align 8
  store i64 %iv1, ptr %ip1, align 8
  %bc = call i64 @__rg_tensor_bounds(i64 %base_val, ptr %tmp_idx, i64 2)
  %vb = call i64 @__rg_real_to_int_bits(i64 %val)
  %res = call i64 @__rg_rt_index_set(ptr %tmp_base, ptr %tmp_idx, i64 2, i64 %vb)
  ret i64 %res
}

define i64 @__rg_builtin_tensor_fill(ptr %slots_ptr, i64 %count) noinline nounwind {
entry:
  %vec_tmp = alloca [3 x i64], align 8
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %fill_val = call i64 @__rg_rt_pop_i64(ptr %s0)
  %d0 = call i64 @__rg_rt_pop_i64(ptr %s1)
  %is_2d = icmp sge i64 %count, 3
  br i1 %is_2d, label %read_d1, label %done_dims
read_d1:
  %s2 = getelementptr inbounds i64, ptr %slots_ptr, i64 2
  %d1_v = call i64 @__rg_rt_pop_i64(ptr %s2)
  br label %done_dims
done_dims:
  %d1 = phi i64 [ %d1_v, %read_d1 ], [ 1, %entry ]
  %rank = phi i64 [ 2, %read_d1 ], [ 1, %entry ]
  %s_bytes = shl i64 %rank, 3
  %s_buf = call ptr @__rg_rt_alloc_buf(i64 %s_bytes)
  store i64 %d0, ptr %s_buf, align 8
  br i1 %is_2d, label %store_d1, label %box_shape
store_d1:
  %s_buf1 = getelementptr inbounds i64, ptr %s_buf, i64 1
  store i64 %d1, ptr %s_buf1, align 8
  br label %box_shape
box_shape:
  %vp0 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 0
  %vp1 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 1
  %vp2 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 2
  store i64 %rank, ptr %vp0, align 8
  %s_buf_int = ptrtoint ptr %s_buf to i64
  store i64 %s_buf_int, ptr %vp1, align 8
  store i64 %rank, ptr %vp2, align 8
  %shdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  %tot = mul i64 %d0, %d1
  %d_bytes = shl i64 %tot, 3
  %d_buf = call ptr @__rg_rt_alloc_buf(i64 %d_bytes)
  %has_elems = icmp sgt i64 %tot, 0
  br i1 %has_elems, label %do_fill, label %box_data
do_fill:
  call void asm sideeffect "rep stosq", "{rdi},{rax},{rcx},~{rdi},~{rcx},~{memory},~{dirflag},~{fpsr},~{flags}"(ptr %d_buf, i64 %fill_val, i64 %tot)
  br label %box_data
box_data:
  store i64 %tot, ptr %vp0, align 8
  %d_buf_int = ptrtoint ptr %d_buf to i64
  store i64 %d_buf_int, ptr %vp1, align 8
  store i64 %tot, ptr %vp2, align 8
  %dhdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  store i64 5, ptr %vp0, align 8
  %shdr_int = ptrtoint ptr %shdr to i64
  %dhdr_int = ptrtoint ptr %dhdr to i64
  store i64 %shdr_int, ptr %vp1, align 8
  store i64 %dhdr_int, ptr %vp2, align 8
  %res = call i64 @__rg_rt_box_rval(ptr %vec_tmp)
  ret i64 %res
}

define i64 @__rg_builtin_tensor_bitop(ptr %slots_ptr) noinline nounwind {
entry:
  %vec_tmp = alloca [3 x i64], align 8
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %s2 = getelementptr inbounds i64, ptr %slots_ptr, i64 2
  %va = load i64, ptr %s0, align 8
  %vb = load i64, ptr %s1, align 8
  %vop = load i64, ptr %s2, align 8
  store i64 0, ptr %s2, align 8
  %op_id = ashr i64 %vop, 1
  %pa = inttoptr i64 %va to ptr
  %pb = inttoptr i64 %vb to ptr
  %ashp_p = getelementptr inbounds i8, ptr %pa, i64 8
  %ashdr = load ptr, ptr %ashp_p, align 8
  %asdp_p = getelementptr inbounds i8, ptr %ashdr, i64 8
  %asdata = load ptr, ptr %asdp_p, align 8
  %ark_p = getelementptr inbounds i8, ptr %ashdr, i64 16
  %rank = load i64, ptr %ark_p, align 8
  %s_bytes = shl i64 %rank, 3
  %s_buf = call ptr @__rg_rt_alloc_buf(i64 %s_bytes)
  call void @__rg_memcpy(ptr %s_buf, ptr %asdata, i64 %s_bytes)
  %vp0 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 0
  %vp1 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 1
  %vp2 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 2
  store i64 %rank, ptr %vp0, align 8
  %s_buf_int = ptrtoint ptr %s_buf to i64
  store i64 %s_buf_int, ptr %vp1, align 8
  store i64 %rank, ptr %vp2, align 8
  %shdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  %adhp_p = getelementptr inbounds i8, ptr %pa, i64 16
  %adhdr = load ptr, ptr %adhp_p, align 8
  %addp_p = getelementptr inbounds i8, ptr %adhdr, i64 8
  %adata = load ptr, ptr %addp_p, align 8
  %alen_p = getelementptr inbounds i8, ptr %adhdr, i64 16
  %tot = load i64, ptr %alen_p, align 8
  %bdhp_p = getelementptr inbounds i8, ptr %pb, i64 16
  %bdhdr = load ptr, ptr %bdhp_p, align 8
  %bddp_p = getelementptr inbounds i8, ptr %bdhdr, i64 8
  %bdata = load ptr, ptr %bddp_p, align 8
  %d_bytes = shl i64 %tot, 3
  %d_buf = call ptr @__rg_rt_alloc_buf(i64 %d_bytes)
  switch i64 %op_id, label %loop_xor [
    i64 0, label %loop_add
    i64 1, label %loop_sub
    i64 2, label %loop_mul
    i64 11, label %loop_and
    i64 12, label %loop_or
    i64 3, label %loop_div
    i64 4, label %loop_rem
    i64 17, label %loop_shl
    i64 18, label %loop_shr
    i64 19, label %loop_rotr
    i64 20, label %loop_rotl
    i64 100, label %loop_fadd
    i64 101, label %loop_fsub
    i64 102, label %loop_fmul
    i64 103, label %loop_fdiv
  ]
loop_add:
  %ia = phi i64 [ 0, %entry ], [ %ia_next, %body_add ]
  %ca = icmp slt i64 %ia, %tot
  br i1 %ca, label %body_add, label %done
body_add:
  %apa = getelementptr inbounds i64, ptr %adata, i64 %ia
  %bpa = getelementptr inbounds i64, ptr %bdata, i64 %ia
  %xa = load i64, ptr %apa, align 8
  %ya = load i64, ptr %bpa, align 8
  %ra = add i64 %xa, %ya
  %dpa = getelementptr inbounds i64, ptr %d_buf, i64 %ia
  store i64 %ra, ptr %dpa, align 8
  %ia_next = add i64 %ia, 1
  br label %loop_add
loop_sub:
  %is = phi i64 [ 0, %entry ], [ %is_next, %body_sub ]
  %cs = icmp slt i64 %is, %tot
  br i1 %cs, label %body_sub, label %done
body_sub:
  %aps = getelementptr inbounds i64, ptr %adata, i64 %is
  %bps = getelementptr inbounds i64, ptr %bdata, i64 %is
  %xs = load i64, ptr %aps, align 8
  %ys = load i64, ptr %bps, align 8
  %rs = sub i64 %xs, %ys
  %dps = getelementptr inbounds i64, ptr %d_buf, i64 %is
  store i64 %rs, ptr %dps, align 8
  %is_next = add i64 %is, 1
  br label %loop_sub
loop_mul:
  %im = phi i64 [ 0, %entry ], [ %im_next, %body_mul ]
  %cm = icmp slt i64 %im, %tot
  br i1 %cm, label %body_mul, label %done
body_mul:
  %apm = getelementptr inbounds i64, ptr %adata, i64 %im
  %bpm = getelementptr inbounds i64, ptr %bdata, i64 %im
  %xm = load i64, ptr %apm, align 8
  %ym = load i64, ptr %bpm, align 8
  %rm = mul i64 %xm, %ym
  %dpm = getelementptr inbounds i64, ptr %d_buf, i64 %im
  store i64 %rm, ptr %dpm, align 8
  %im_next = add i64 %im, 1
  br label %loop_mul
loop_and:
  %in = phi i64 [ 0, %entry ], [ %in_next, %body_and ]
  %cn = icmp slt i64 %in, %tot
  br i1 %cn, label %body_and, label %done
body_and:
  %apn = getelementptr inbounds i64, ptr %adata, i64 %in
  %bpn = getelementptr inbounds i64, ptr %bdata, i64 %in
  %xn = load i64, ptr %apn, align 8
  %yn = load i64, ptr %bpn, align 8
  %rn = and i64 %xn, %yn
  %dpn = getelementptr inbounds i64, ptr %d_buf, i64 %in
  store i64 %rn, ptr %dpn, align 8
  %in_next = add i64 %in, 1
  br label %loop_and
loop_or:
  %io = phi i64 [ 0, %entry ], [ %io_next, %body_or ]
  %co = icmp slt i64 %io, %tot
  br i1 %co, label %body_or, label %done
body_or:
  %apo = getelementptr inbounds i64, ptr %adata, i64 %io
  %bpo = getelementptr inbounds i64, ptr %bdata, i64 %io
  %xo = load i64, ptr %apo, align 8
  %yo = load i64, ptr %bpo, align 8
  %ro = or i64 %xo, %yo
  %dpo = getelementptr inbounds i64, ptr %d_buf, i64 %io
  store i64 %ro, ptr %dpo, align 8
  %io_next = add i64 %io, 1
  br label %loop_or
; 3 / and 4 % (a divisor of 0 gives 0), 19 rotr, 20 rotl, and 100 to 103: the words as Reals (+ - * /).
loop_div:
  %i_div = phi i64 [ 0, %entry ], [ %i_div_next, %body_div ]
  %c_div = icmp slt i64 %i_div, %tot
  br i1 %c_div, label %body_div, label %done
body_div:
  %ap_div = getelementptr inbounds i64, ptr %adata, i64 %i_div
  %bp_div = getelementptr inbounds i64, ptr %bdata, i64 %i_div
  %x_div = load i64, ptr %ap_div, align 8
  %y_div = load i64, ptr %bp_div, align 8
  %z_div = icmp eq i64 %y_div, 0
  %m_div = icmp eq i64 %y_div, -1
  %s0_div = select i1 %z_div, i64 1, i64 %y_div
  %s_div = select i1 %m_div, i64 1, i64 %s0_div
  %q_div = sdiv i64 %x_div, %s_div
  %n_div = sub i64 0, %x_div
  %q1_div = select i1 %m_div, i64 %n_div, i64 %q_div
  %r_div = select i1 %z_div, i64 0, i64 %q1_div
  %dp_div = getelementptr inbounds i64, ptr %d_buf, i64 %i_div
  store i64 %r_div, ptr %dp_div, align 8
  %i_div_next = add i64 %i_div, 1
  br label %loop_div
loop_rem:
  %i_rem = phi i64 [ 0, %entry ], [ %i_rem_next, %body_rem ]
  %c_rem = icmp slt i64 %i_rem, %tot
  br i1 %c_rem, label %body_rem, label %done
body_rem:
  %ap_rem = getelementptr inbounds i64, ptr %adata, i64 %i_rem
  %bp_rem = getelementptr inbounds i64, ptr %bdata, i64 %i_rem
  %x_rem = load i64, ptr %ap_rem, align 8
  %y_rem = load i64, ptr %bp_rem, align 8
  %z_rem = icmp eq i64 %y_rem, 0
  %m_rem = icmp eq i64 %y_rem, -1
  %s0_rem = select i1 %z_rem, i64 1, i64 %y_rem
  %s_rem = select i1 %m_rem, i64 1, i64 %s0_rem
  %q_rem = srem i64 %x_rem, %s_rem
  %bad_rem = or i1 %z_rem, %m_rem
  %r_rem = select i1 %bad_rem, i64 0, i64 %q_rem
  %dp_rem = getelementptr inbounds i64, ptr %d_buf, i64 %i_rem
  store i64 %r_rem, ptr %dp_rem, align 8
  %i_rem_next = add i64 %i_rem, 1
  br label %loop_rem
loop_rotr:
  %i_rotr = phi i64 [ 0, %entry ], [ %i_rotr_next, %body_rotr ]
  %c_rotr = icmp slt i64 %i_rotr, %tot
  br i1 %c_rotr, label %body_rotr, label %done
body_rotr:
  %ap_rotr = getelementptr inbounds i64, ptr %adata, i64 %i_rotr
  %bp_rotr = getelementptr inbounds i64, ptr %bdata, i64 %i_rotr
  %x_rotr = load i64, ptr %ap_rotr, align 8
  %y_rotr = load i64, ptr %bp_rotr, align 8
  %r_rotr = call i64 @llvm.fshr.i64(i64 %x_rotr, i64 %x_rotr, i64 %y_rotr)
  %dp_rotr = getelementptr inbounds i64, ptr %d_buf, i64 %i_rotr
  store i64 %r_rotr, ptr %dp_rotr, align 8
  %i_rotr_next = add i64 %i_rotr, 1
  br label %loop_rotr
loop_rotl:
  %i_rotl = phi i64 [ 0, %entry ], [ %i_rotl_next, %body_rotl ]
  %c_rotl = icmp slt i64 %i_rotl, %tot
  br i1 %c_rotl, label %body_rotl, label %done
body_rotl:
  %ap_rotl = getelementptr inbounds i64, ptr %adata, i64 %i_rotl
  %bp_rotl = getelementptr inbounds i64, ptr %bdata, i64 %i_rotl
  %x_rotl = load i64, ptr %ap_rotl, align 8
  %y_rotl = load i64, ptr %bp_rotl, align 8
  %r_rotl = call i64 @llvm.fshl.i64(i64 %x_rotl, i64 %x_rotl, i64 %y_rotl)
  %dp_rotl = getelementptr inbounds i64, ptr %d_buf, i64 %i_rotl
  store i64 %r_rotl, ptr %dp_rotl, align 8
  %i_rotl_next = add i64 %i_rotl, 1
  br label %loop_rotl
loop_fadd:
  %i_fadd = phi i64 [ 0, %entry ], [ %i_fadd_next, %body_fadd ]
  %c_fadd = icmp slt i64 %i_fadd, %tot
  br i1 %c_fadd, label %body_fadd, label %done
body_fadd:
  %ap_fadd = getelementptr inbounds i64, ptr %adata, i64 %i_fadd
  %bp_fadd = getelementptr inbounds i64, ptr %bdata, i64 %i_fadd
  %x_fadd = load i64, ptr %ap_fadd, align 8
  %y_fadd = load i64, ptr %bp_fadd, align 8
  %fx_fadd = bitcast i64 %x_fadd to double
  %fy_fadd = bitcast i64 %y_fadd to double
  %fr_fadd = fadd double %fx_fadd, %fy_fadd
  %r_fadd = bitcast double %fr_fadd to i64
  %dp_fadd = getelementptr inbounds i64, ptr %d_buf, i64 %i_fadd
  store i64 %r_fadd, ptr %dp_fadd, align 8
  %i_fadd_next = add i64 %i_fadd, 1
  br label %loop_fadd
loop_fsub:
  %i_fsub = phi i64 [ 0, %entry ], [ %i_fsub_next, %body_fsub ]
  %c_fsub = icmp slt i64 %i_fsub, %tot
  br i1 %c_fsub, label %body_fsub, label %done
body_fsub:
  %ap_fsub = getelementptr inbounds i64, ptr %adata, i64 %i_fsub
  %bp_fsub = getelementptr inbounds i64, ptr %bdata, i64 %i_fsub
  %x_fsub = load i64, ptr %ap_fsub, align 8
  %y_fsub = load i64, ptr %bp_fsub, align 8
  %fx_fsub = bitcast i64 %x_fsub to double
  %fy_fsub = bitcast i64 %y_fsub to double
  %fr_fsub = fsub double %fx_fsub, %fy_fsub
  %r_fsub = bitcast double %fr_fsub to i64
  %dp_fsub = getelementptr inbounds i64, ptr %d_buf, i64 %i_fsub
  store i64 %r_fsub, ptr %dp_fsub, align 8
  %i_fsub_next = add i64 %i_fsub, 1
  br label %loop_fsub
loop_fmul:
  %i_fmul = phi i64 [ 0, %entry ], [ %i_fmul_next, %body_fmul ]
  %c_fmul = icmp slt i64 %i_fmul, %tot
  br i1 %c_fmul, label %body_fmul, label %done
body_fmul:
  %ap_fmul = getelementptr inbounds i64, ptr %adata, i64 %i_fmul
  %bp_fmul = getelementptr inbounds i64, ptr %bdata, i64 %i_fmul
  %x_fmul = load i64, ptr %ap_fmul, align 8
  %y_fmul = load i64, ptr %bp_fmul, align 8
  %fx_fmul = bitcast i64 %x_fmul to double
  %fy_fmul = bitcast i64 %y_fmul to double
  %fr_fmul = fmul double %fx_fmul, %fy_fmul
  %r_fmul = bitcast double %fr_fmul to i64
  %dp_fmul = getelementptr inbounds i64, ptr %d_buf, i64 %i_fmul
  store i64 %r_fmul, ptr %dp_fmul, align 8
  %i_fmul_next = add i64 %i_fmul, 1
  br label %loop_fmul
loop_fdiv:
  %i_fdiv = phi i64 [ 0, %entry ], [ %i_fdiv_next, %body_fdiv ]
  %c_fdiv = icmp slt i64 %i_fdiv, %tot
  br i1 %c_fdiv, label %body_fdiv, label %done
body_fdiv:
  %ap_fdiv = getelementptr inbounds i64, ptr %adata, i64 %i_fdiv
  %bp_fdiv = getelementptr inbounds i64, ptr %bdata, i64 %i_fdiv
  %x_fdiv = load i64, ptr %ap_fdiv, align 8
  %y_fdiv = load i64, ptr %bp_fdiv, align 8
  %fx_fdiv = bitcast i64 %x_fdiv to double
  %fy_fdiv = bitcast i64 %y_fdiv to double
  %fr_fdiv = fdiv double %fx_fdiv, %fy_fdiv
  %r_fdiv = bitcast double %fr_fdiv to i64
  %dp_fdiv = getelementptr inbounds i64, ptr %d_buf, i64 %i_fdiv
  store i64 %r_fdiv, ptr %dp_fdiv, align 8
  %i_fdiv_next = add i64 %i_fdiv, 1
  br label %loop_fdiv
; shl and shr (logical) of each word of a by the count in the word of b, taken modulo 64 as for
; Int (`rg_int_op`): the same loop shape as the others, so LLVM vectorises it (psllq, psrlq).
loop_shl:
  %il = phi i64 [ 0, %entry ], [ %il_next, %body_shl ]
  %cl = icmp slt i64 %il, %tot
  br i1 %cl, label %body_shl, label %done
body_shl:
  %apl = getelementptr inbounds i64, ptr %adata, i64 %il
  %bpl = getelementptr inbounds i64, ptr %bdata, i64 %il
  %xl = load i64, ptr %apl, align 8
  %yl = load i64, ptr %bpl, align 8
  %yl6 = and i64 %yl, 63
  %rl = shl i64 %xl, %yl6
  %dpl = getelementptr inbounds i64, ptr %d_buf, i64 %il
  store i64 %rl, ptr %dpl, align 8
  %il_next = add i64 %il, 1
  br label %loop_shl
loop_shr:
  %ir = phi i64 [ 0, %entry ], [ %ir_next, %body_shr ]
  %cr = icmp slt i64 %ir, %tot
  br i1 %cr, label %body_shr, label %done
body_shr:
  %apr = getelementptr inbounds i64, ptr %adata, i64 %ir
  %bpr = getelementptr inbounds i64, ptr %bdata, i64 %ir
  %xr = load i64, ptr %apr, align 8
  %yr = load i64, ptr %bpr, align 8
  %yr6 = and i64 %yr, 63
  %rr = lshr i64 %xr, %yr6
  %dpr = getelementptr inbounds i64, ptr %d_buf, i64 %ir
  store i64 %rr, ptr %dpr, align 8
  %ir_next = add i64 %ir, 1
  br label %loop_shr
loop_xor:
  %ix = phi i64 [ 0, %entry ], [ %ix_next, %body_xor ]
  %cx = icmp slt i64 %ix, %tot
  br i1 %cx, label %body_xor, label %done
body_xor:
  %apx = getelementptr inbounds i64, ptr %adata, i64 %ix
  %bpx = getelementptr inbounds i64, ptr %bdata, i64 %ix
  %xx = load i64, ptr %apx, align 8
  %yx = load i64, ptr %bpx, align 8
  %rx = xor i64 %xx, %yx
  %dpx = getelementptr inbounds i64, ptr %d_buf, i64 %ix
  store i64 %rx, ptr %dpx, align 8
  %ix_next = add i64 %ix, 1
  br label %loop_xor
done:
  store i64 %tot, ptr %vp0, align 8
  %d_buf_int = ptrtoint ptr %d_buf to i64
  store i64 %d_buf_int, ptr %vp1, align 8
  store i64 %tot, ptr %vp2, align 8
  %dhdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  store i64 5, ptr %vp0, align 8
  %shdr_int = ptrtoint ptr %shdr to i64
  %dhdr_int = ptrtoint ptr %dhdr to i64
  store i64 %shdr_int, ptr %vp1, align 8
  store i64 %dhdr_int, ptr %vp2, align 8
  %res = call i64 @__rg_rt_box_rval(ptr %vec_tmp)
  call void @__rg_rt_drop_slot(ptr %s0)
  call void @__rg_rt_drop_slot(ptr %s1)
  ret i64 %res
}

define void @__rg_extract_str_span(i64 %val, ptr %out_ptr, ptr %out_len) nounwind {
entry:
  store ptr null, ptr %out_ptr, align 8
  store i64 0, ptr %out_len, align 8
  %nn = icmp ne i64 %val, 0
  %l3 = and i64 %val, 7
  %is_p = icmp eq i64 %l3, 0
  %ok = and i1 %nn, %is_p
  br i1 %ok, label %chk_t, label %done
chk_t:
  %p = inttoptr i64 %val to ptr
  %t = load i32, ptr %p, align 4
  %is_s = icmp eq i32 %t, 1
  br i1 %is_s, label %load_s, label %done
load_s:
  %hp = getelementptr inbounds i8, ptr %p, i64 8
  %hdr = load ptr, ptr %hp, align 8
  %dp = getelementptr inbounds i8, ptr %hdr, i64 8
  %dptr = load ptr, ptr %dp, align 8
  %lp = getelementptr inbounds i8, ptr %hdr, i64 16
  %dlen = load i64, ptr %lp, align 8
  store ptr %dptr, ptr %out_ptr, align 8
  store i64 %dlen, ptr %out_len, align 8
  br label %done
done:
  ret void
}

define i64 @__rg_builtin_sha256_raw(ptr %slot_ptr) noinline nounwind {
entry:
  %sp_ptr = alloca ptr, align 8
  %sp_len = alloca i64, align 8
  %digest = alloca [32 x i8], align 16
  %val = load i64, ptr %slot_ptr, align 8
  call void @__rg_extract_str_span(i64 %val, ptr %sp_ptr, ptr %sp_len)
  %dptr = load ptr, ptr %sp_ptr, align 8
  %dlen = load i64, ptr %sp_len, align 8
  call void @__rg_sha256_compute2(ptr %dptr, i64 %dlen, ptr null, i64 0, ptr %digest)
  %res = call i64 @__rg_rt_load_str_lit(ptr %digest, i64 32)
  call void @__rg_rt_drop_slot(ptr %slot_ptr)
  ret i64 %res
}

define i64 @__rg_builtin_sha256_concat(ptr %slots_ptr) noinline nounwind {
entry:
  %p1 = alloca ptr, align 8
  %l1 = alloca i64, align 8
  %p2 = alloca ptr, align 8
  %l2 = alloca i64, align 8
  %digest = alloca [32 x i8], align 16
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %v0 = load i64, ptr %s0, align 8
  %v1 = load i64, ptr %s1, align 8
  call void @__rg_extract_str_span(i64 %v0, ptr %p1, ptr %l1)
  call void @__rg_extract_str_span(i64 %v1, ptr %p2, ptr %l2)
  %dp1 = load ptr, ptr %p1, align 8
  %dl1 = load i64, ptr %l1, align 8
  %dp2 = load ptr, ptr %p2, align 8
  %dl2 = load i64, ptr %l2, align 8
  call void @__rg_sha256_compute2(ptr %dp1, i64 %dl1, ptr %dp2, i64 %dl2, ptr %digest)
  %res = call i64 @__rg_rt_load_str_lit(ptr %digest, i64 32)
  call void @__rg_rt_drop_slot(ptr %s0)
  call void @__rg_rt_drop_slot(ptr %s1)
  ret i64 %res
}

define i64 @__rg_builtin_sys_pipe() noinline nounwind {
entry:
  %fds = alloca [2 x i32], align 8
  %tup = alloca [2 x i64], align 8
  %f0_p = getelementptr inbounds [2 x i32], ptr %fds, i64 0, i64 0
  %f1_p = getelementptr inbounds [2 x i32], ptr %fds, i64 0, i64 1
  store i32 -1, ptr %f0_p, align 4
  store i32 -1, ptr %f1_p, align 4
  %rc = call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},~{rcx},~{r11},~{memory}"(i64 22, ptr %fds)
  %fd0_32 = load i32, ptr %f0_p, align 4
  %fd1_32 = load i32, ptr %f1_p, align 4
  %fd0 = sext i32 %fd0_32 to i64
  %fd1 = sext i32 %fd1_32 to i64
  %t0_s = shl i64 %fd0, 1
  %t0 = or i64 %t0_s, 1
  %t1_s = shl i64 %fd1, 1
  %t1 = or i64 %t1_s, 1
  %tp0 = getelementptr inbounds [2 x i64], ptr %tup, i64 0, i64 0
  %tp1 = getelementptr inbounds [2 x i64], ptr %tup, i64 0, i64 1
  store i64 %t0, ptr %tp0, align 8
  store i64 %t1, ptr %tp1, align 8
  %res = call i64 @__rg_rt_make_tuple(ptr %tup, i64 2)
  ret i64 %res
}

define i64 @__rg_builtin_sys_waitpid(ptr %slots_ptr) noinline nounwind {
entry:
  %status = alloca i32, align 4
  %tup = alloca [2 x i64], align 8
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %v_pid = load i64, ptr %s0, align 8
  %v_opt = load i64, ptr %s1, align 8
  store i64 0, ptr %s0, align 8
  store i64 0, ptr %s1, align 8
  %pid = ashr i64 %v_pid, 1
  %opt = ashr i64 %v_opt, 1
  store i32 0, ptr %status, align 4
  %rc = call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},~{rcx},~{r11},~{memory}"(i64 61, i64 %pid, ptr %status, i64 %opt, i64 0)
  %st = load i32, ptr %status, align 4
  %sig = and i32 %st, 127
  %ex_sh = lshr i32 %st, 8
  %ex = and i32 %ex_sh, 255
  %sig_code = add i32 %sig, 128
  %was_sig = icmp ne i32 %sig, 0
  %code32 = select i1 %was_sig, i32 %sig_code, i32 %ex
  %code = zext i32 %code32 to i64
  %neg = icmp slt i64 %rc, 0
  %r_pid = select i1 %neg, i64 -1, i64 %rc
  %tp_s = shl i64 %r_pid, 1
  %tp_v = or i64 %tp_s, 1
  %tc_s = shl i64 %code, 1
  %tc_v = or i64 %tc_s, 1
  %tp0 = getelementptr inbounds [2 x i64], ptr %tup, i64 0, i64 0
  %tp1 = getelementptr inbounds [2 x i64], ptr %tup, i64 0, i64 1
  store i64 %tp_v, ptr %tp0, align 8
  store i64 %tc_v, ptr %tp1, align 8
  %res = call i64 @__rg_rt_make_tuple(ptr %tup, i64 2)
  ret i64 %res
}

define i64 @__rg_builtin_tensor_row_slice(ptr %slots_ptr) noinline nounwind {
entry:
  %vec_tmp = alloca [3 x i64], align 8
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %vm = load i64, ptr %s0, align 8
  %vr = load i64, ptr %s1, align 8
  store i64 0, ptr %s1, align 8
  %r = ashr i64 %vr, 1
  %pm = inttoptr i64 %vm to ptr
  %mshp_p = getelementptr inbounds i8, ptr %pm, i64 8
  %mshdr = load ptr, ptr %mshp_p, align 8
  %msdp_p = getelementptr inbounds i8, ptr %mshdr, i64 8
  %msptr = load ptr, ptr %msdp_p, align 8
  %d0 = load i64, ptr %msptr, align 8
  %d1_p = getelementptr inbounds i64, ptr %msptr, i64 1
  %d1 = load i64, ptr %d1_p, align 8
  %s_buf = call ptr @__rg_rt_alloc_buf(i64 8)
  store i64 %d1, ptr %s_buf, align 8
  %vp0 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 0
  %vp1 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 1
  %vp2 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 2
  store i64 1, ptr %vp0, align 8
  %s_buf_int = ptrtoint ptr %s_buf to i64
  store i64 %s_buf_int, ptr %vp1, align 8
  store i64 1, ptr %vp2, align 8
  %shdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  %d_bytes = shl i64 %d1, 3
  %d_buf = call ptr @__rg_rt_alloc_buf(i64 %d_bytes)
  %ge0 = icmp sge i64 %r, 0
  %lt0 = icmp slt i64 %r, %d0
  %in_b = and i1 %ge0, %lt0
  br i1 %in_b, label %copy_row, label %zero_row
copy_row:
  %mdhp_p = getelementptr inbounds i8, ptr %pm, i64 16
  %mdhdr = load ptr, ptr %mdhp_p, align 8
  %mddp_p = getelementptr inbounds i8, ptr %mdhdr, i64 8
  %mdata = load ptr, ptr %mddp_p, align 8
  %row_off = mul i64 %r, %d1
  %src_p = getelementptr inbounds i64, ptr %mdata, i64 %row_off
  call void @__rg_memcpy(ptr %d_buf, ptr %src_p, i64 %d_bytes)
  br label %box_out
zero_row:
  call void @__rg_memset(ptr %d_buf, i8 0, i64 %d_bytes)
  br label %box_out
box_out:
  store i64 %d1, ptr %vp0, align 8
  %d_buf_int = ptrtoint ptr %d_buf to i64
  store i64 %d_buf_int, ptr %vp1, align 8
  store i64 %d1, ptr %vp2, align 8
  %dhdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  store i64 5, ptr %vp0, align 8
  %shdr_int = ptrtoint ptr %shdr to i64
  %dhdr_int = ptrtoint ptr %dhdr to i64
  store i64 %shdr_int, ptr %vp1, align 8
  store i64 %dhdr_int, ptr %vp2, align 8
  %res = call i64 @__rg_rt_box_rval(ptr %vec_tmp)
  call void @__rg_rt_drop_slot(ptr %s0)
  ret i64 %res
}

define i64 @__rg_builtin_tensor_set_row(ptr %slots_ptr) noinline nounwind {
entry:
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %s2 = getelementptr inbounds i64, ptr %slots_ptr, i64 2
  %vm = load i64, ptr %s0, align 8
  %vr = load i64, ptr %s1, align 8
  %vv = load i64, ptr %s2, align 8
  store i64 0, ptr %s0, align 8
  store i64 0, ptr %s1, align 8
  %r = ashr i64 %vr, 1
  %pm = inttoptr i64 %vm to ptr
  %mshp_p = getelementptr inbounds i8, ptr %pm, i64 8
  %mshdr = load ptr, ptr %mshp_p, align 8
  %msdp_p = getelementptr inbounds i8, ptr %mshdr, i64 8
  %msptr = load ptr, ptr %msdp_p, align 8
  %d0 = load i64, ptr %msptr, align 8
  %d1_p = getelementptr inbounds i64, ptr %msptr, i64 1
  %d1 = load i64, ptr %d1_p, align 8
  %ge0 = icmp sge i64 %r, 0
  %lt0 = icmp slt i64 %r, %d0
  %in_b = and i1 %ge0, %lt0
  br i1 %in_b, label %do_copy, label %done
do_copy:
  %pv = inttoptr i64 %vv to ptr
  %vdhp_p = getelementptr inbounds i8, ptr %pv, i64 16
  %vdhdr = load ptr, ptr %vdhp_p, align 8
  %vddp_p = getelementptr inbounds i8, ptr %vdhdr, i64 8
  %vdata = load ptr, ptr %vddp_p, align 8
  %vlen_p = getelementptr inbounds i8, ptr %vdhdr, i64 16
  %vlen = load i64, ptr %vlen_p, align 8
  %use_vlen = icmp slt i64 %vlen, %d1
  %cnt = select i1 %use_vlen, i64 %vlen, i64 %d1
  %nbytes = shl i64 %cnt, 3
  %mdhp_p = getelementptr inbounds i8, ptr %pm, i64 16
  %mdhdr = load ptr, ptr %mdhp_p, align 8
  %mddp_p = getelementptr inbounds i8, ptr %mdhdr, i64 8
  %mdata = load ptr, ptr %mddp_p, align 8
  %row_off = mul i64 %r, %d1
  %dst_p = getelementptr inbounds i64, ptr %mdata, i64 %row_off
  call void @__rg_memcpy(ptr %dst_p, ptr %vdata, i64 %nbytes)
  br label %done
done:
  call void @__rg_rt_drop_slot(ptr %s2)
  ret i64 %vm
}

define i64 @__rg_builtin_tensor_col_slice(ptr %slots_ptr) noinline nounwind {
entry:
  %vec_tmp = alloca [3 x i64], align 8
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %vm = load i64, ptr %s0, align 8
  %vc = load i64, ptr %s1, align 8
  store i64 0, ptr %s1, align 8
  %c = ashr i64 %vc, 1
  %pm = inttoptr i64 %vm to ptr
  %mshp_p = getelementptr inbounds i8, ptr %pm, i64 8
  %mshdr = load ptr, ptr %mshp_p, align 8
  %msdp_p = getelementptr inbounds i8, ptr %mshdr, i64 8
  %msptr = load ptr, ptr %msdp_p, align 8
  %d0 = load i64, ptr %msptr, align 8
  %d1_p = getelementptr inbounds i64, ptr %msptr, i64 1
  %d1 = load i64, ptr %d1_p, align 8
  %s_buf = call ptr @__rg_rt_alloc_buf(i64 8)
  store i64 %d0, ptr %s_buf, align 8
  %vp0 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 0
  %vp1 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 1
  %vp2 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 2
  store i64 1, ptr %vp0, align 8
  %s_buf_int = ptrtoint ptr %s_buf to i64
  store i64 %s_buf_int, ptr %vp1, align 8
  store i64 1, ptr %vp2, align 8
  %shdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  %d_bytes = shl i64 %d0, 3
  %d_buf = call ptr @__rg_rt_alloc_buf(i64 %d_bytes)
  %mdhp_p = getelementptr inbounds i8, ptr %pm, i64 16
  %mdhdr = load ptr, ptr %mdhp_p, align 8
  %mddp_p = getelementptr inbounds i8, ptr %mdhdr, i64 8
  %mdata = load ptr, ptr %mddp_p, align 8
  br label %loop
loop:
  %r = phi i64 [ 0, %entry ], [ %r_next, %body ]
  %cond = icmp slt i64 %r, %d0
  br i1 %cond, label %body, label %box_out
body:
  %row_off = mul i64 %r, %d1
  %idx = add i64 %row_off, %c
  %sp = getelementptr inbounds i64, ptr %mdata, i64 %idx
  %val = load i64, ptr %sp, align 8
  %dp = getelementptr inbounds i64, ptr %d_buf, i64 %r
  store i64 %val, ptr %dp, align 8
  %r_next = add i64 %r, 1
  br label %loop
box_out:
  store i64 %d0, ptr %vp0, align 8
  %d_buf_int = ptrtoint ptr %d_buf to i64
  store i64 %d_buf_int, ptr %vp1, align 8
  store i64 %d0, ptr %vp2, align 8
  %dhdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  store i64 5, ptr %vp0, align 8
  %shdr_int = ptrtoint ptr %shdr to i64
  %dhdr_int = ptrtoint ptr %dhdr to i64
  store i64 %shdr_int, ptr %vp1, align 8
  store i64 %dhdr_int, ptr %vp2, align 8
  %res = call i64 @__rg_rt_box_rval(ptr %vec_tmp)
  call void @__rg_rt_drop_slot(ptr %s0)
  ret i64 %res
}

define i64 @__rg_builtin_tensor_set_col(ptr %slots_ptr) noinline nounwind {
entry:
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %s2 = getelementptr inbounds i64, ptr %slots_ptr, i64 2
  %vm = load i64, ptr %s0, align 8
  %vc = load i64, ptr %s1, align 8
  %vv = load i64, ptr %s2, align 8
  store i64 0, ptr %s0, align 8
  store i64 0, ptr %s1, align 8
  %c = ashr i64 %vc, 1
  %pm = inttoptr i64 %vm to ptr
  %mshp_p = getelementptr inbounds i8, ptr %pm, i64 8
  %mshdr = load ptr, ptr %mshp_p, align 8
  %msdp_p = getelementptr inbounds i8, ptr %mshdr, i64 8
  %msptr = load ptr, ptr %msdp_p, align 8
  %d0 = load i64, ptr %msptr, align 8
  %d1_p = getelementptr inbounds i64, ptr %msptr, i64 1
  %d1 = load i64, ptr %d1_p, align 8
  %pv = inttoptr i64 %vv to ptr
  %vdhp_p = getelementptr inbounds i8, ptr %pv, i64 16
  %vdhdr = load ptr, ptr %vdhp_p, align 8
  %vddp_p = getelementptr inbounds i8, ptr %vdhdr, i64 8
  %vdata = load ptr, ptr %vddp_p, align 8
  %vlen_p = getelementptr inbounds i8, ptr %vdhdr, i64 16
  %vlen = load i64, ptr %vlen_p, align 8
  %use_vlen = icmp slt i64 %vlen, %d0
  %limit = select i1 %use_vlen, i64 %vlen, i64 %d0
  %mdhp_p = getelementptr inbounds i8, ptr %pm, i64 16
  %mdhdr = load ptr, ptr %mdhp_p, align 8
  %mddp_p = getelementptr inbounds i8, ptr %mdhdr, i64 8
  %mdata = load ptr, ptr %mddp_p, align 8
  br label %loop
loop:
  %r = phi i64 [ 0, %entry ], [ %r_next, %body ]
  %cond = icmp slt i64 %r, %limit
  br i1 %cond, label %body, label %done
body:
  %vp = getelementptr inbounds i64, ptr %vdata, i64 %r
  %val = load i64, ptr %vp, align 8
  %row_off = mul i64 %r, %d1
  %idx = add i64 %row_off, %c
  %dp = getelementptr inbounds i64, ptr %mdata, i64 %idx
  store i64 %val, ptr %dp, align 8
  %r_next = add i64 %r, 1
  br label %loop
done:
  call void @__rg_rt_drop_slot(ptr %s2)
  ret i64 %vm
}

define i64 @__rg_fast_einsum(ptr %slots_ptr, i64 %count, ptr %spec_ptr, i64 %spec_len) noinline nounwind {
entry:
  %vec_tmp = alloca [3 x i64], align 8
  %is_c2 = icmp eq i64 %count, 2
  %is_s5 = icmp eq i64 %spec_len, 5
  %ok_cs = and i1 %is_c2, %is_s5
  br i1 %ok_cs, label %chk_spec, label %slow
chk_spec:
  %c0 = load i8, ptr %spec_ptr, align 1
  %p1 = getelementptr inbounds i8, ptr %spec_ptr, i64 1
  %c1 = load i8, ptr %p1, align 1
  %p2 = getelementptr inbounds i8, ptr %spec_ptr, i64 2
  %c2 = load i8, ptr %p2, align 1
  %p3 = getelementptr inbounds i8, ptr %spec_ptr, i64 3
  %c3 = load i8, ptr %p3, align 1
  %p4 = getelementptr inbounds i8, ptr %spec_ptr, i64 4
  %c4 = load i8, ptr %p4, align 1
  %is_comma = icmp eq i8 %c2, 44
  %mid_eq = icmp eq i8 %c1, %c3
  %out_ne = icmp ne i8 %c0, %c4
  %c0_ne_c1 = icmp ne i8 %c0, %c1
  %c4_ne_c1 = icmp ne i8 %c4, %c1
  %ok1 = and i1 %is_comma, %mid_eq
  %ok2 = and i1 %out_ne, %c0_ne_c1
  %ok3 = and i1 %ok1, %ok2
  %ok_spec = and i1 %ok3, %c4_ne_c1
  br i1 %ok_spec, label %chk_tensors, label %slow
chk_tensors:
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %va = load i64, ptr %s0, align 8
  %vb = load i64, ptr %s1, align 8
  %ann = icmp ne i64 %va, 0
  %al3 = and i64 %va, 7
  %ap_ok = icmp eq i64 %al3, 0
  %a_ok = and i1 %ann, %ap_ok
  %bnn = icmp ne i64 %vb, 0
  %bl3 = and i64 %vb, 7
  %bp_ok = icmp eq i64 %bl3, 0
  %b_ok = and i1 %bnn, %bp_ok
  %both_ok = and i1 %a_ok, %b_ok
  br i1 %both_ok, label %chk_tags, label %slow
chk_tags:
  %pa = inttoptr i64 %va to ptr
  %pb = inttoptr i64 %vb to ptr
  %atag = load i32, ptr %pa, align 4
  %btag = load i32, ptr %pb, align 4
  %at5 = icmp eq i32 %atag, 5
  %bt5 = icmp eq i32 %btag, 5
  %tags_ok = and i1 %at5, %bt5
  br i1 %tags_ok, label %chk_ranks, label %slow
chk_ranks:
  %ashp_p = getelementptr inbounds i8, ptr %pa, i64 8
  %ashdr = load ptr, ptr %ashp_p, align 8
  %ark_p = getelementptr inbounds i8, ptr %ashdr, i64 16
  %ark = load i64, ptr %ark_p, align 8
  %bshp_p = getelementptr inbounds i8, ptr %pb, i64 8
  %bshdr = load ptr, ptr %bshp_p, align 8
  %brk_p = getelementptr inbounds i8, ptr %bshdr, i64 16
  %brk = load i64, ptr %brk_p, align 8
  %ar2 = icmp eq i64 %ark, 2
  %br2 = icmp eq i64 %brk, 2
  %rks_ok = and i1 %ar2, %br2
  br i1 %rks_ok, label %chk_dims, label %slow
chk_dims:
  %asdp_p = getelementptr inbounds i8, ptr %ashdr, i64 8
  %asptr = load ptr, ptr %asdp_p, align 8
  %M = load i64, ptr %asptr, align 8
  %ak_p = getelementptr inbounds i64, ptr %asptr, i64 1
  %K = load i64, ptr %ak_p, align 8
  %bsdp_p = getelementptr inbounds i8, ptr %bshdr, i64 8
  %bsptr = load ptr, ptr %bsdp_p, align 8
  %bK = load i64, ptr %bsptr, align 8
  %bn_p = getelementptr inbounds i64, ptr %bsptr, i64 1
  %N = load i64, ptr %bn_p, align 8
  %k_eq = icmp eq i64 %K, %bK
  %m_gt0 = icmp sgt i64 %M, 0
  %k_gt0 = icmp sgt i64 %K, 0
  %n_gt0 = icmp sgt i64 %N, 0
  %mk_ok = and i1 %m_gt0, %k_gt0
  %mkn_ok = and i1 %mk_ok, %n_gt0
  %dims_ok = and i1 %k_eq, %mkn_ok
  br i1 %dims_ok, label %init_c, label %slow
init_c:
  %s_buf = call ptr @__rg_rt_alloc_buf(i64 16)
  store i64 %M, ptr %s_buf, align 8
  %s_buf1 = getelementptr inbounds i64, ptr %s_buf, i64 1
  store i64 %N, ptr %s_buf1, align 8
  %vp0 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 0
  %vp1 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 1
  %vp2 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 2
  store i64 2, ptr %vp0, align 8
  %s_buf_int = ptrtoint ptr %s_buf to i64
  store i64 %s_buf_int, ptr %vp1, align 8
  store i64 2, ptr %vp2, align 8
  %shdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  %tot = mul i64 %M, %N
  %d_bytes = shl i64 %tot, 3
  %d_buf = call ptr @__rg_rt_alloc_buf(i64 %d_bytes)
  call void asm sideeffect "rep stosq", "{rdi},{rax},{rcx},~{rdi},~{rcx},~{memory},~{dirflag},~{fpsr},~{flags}"(ptr %d_buf, i64 0, i64 %tot)
  %adhp_p = getelementptr inbounds i8, ptr %pa, i64 16
  %adhdr = load ptr, ptr %adhp_p, align 8
  %addp_p = getelementptr inbounds i8, ptr %adhdr, i64 8
  %adata = load ptr, ptr %addp_p, align 8
  %bdhp_p = getelementptr inbounds i8, ptr %pb, i64 16
  %bdhdr = load ptr, ptr %bdhp_p, align 8
  %bddp_p = getelementptr inbounds i8, ptr %bdhdr, i64 8
  %bdata = load ptr, ptr %bddp_p, align 8
  br label %loop_i
loop_i:
  %i = phi i64 [ 0, %init_c ], [ %i_next, %next_i ]
  %ci = icmp slt i64 %i, %M
  br i1 %ci, label %loop_k, label %box_out
loop_k:
  %k = phi i64 [ 0, %loop_i ], [ %k_next, %next_k ]
  %ck = icmp slt i64 %k, %K
  br i1 %ck, label %prep_j, label %next_i
prep_j:
  %ai_off = mul i64 %i, %K
  %aik_idx = add i64 %ai_off, %k
  %aik_p = getelementptr inbounds i64, ptr %adata, i64 %aik_idx
  %aik = load i64, ptr %aik_p, align 8
  %bk_off = mul i64 %k, %N
  %ci_off = mul i64 %i, %N
  br label %loop_j
loop_j:
  %j = phi i64 [ 0, %prep_j ], [ %j_next, %body_j ]
  %cj = icmp slt i64 %j, %N
  br i1 %cj, label %body_j, label %next_k
body_j:
  %bkj_idx = add i64 %bk_off, %j
  %bkj_p = getelementptr inbounds i64, ptr %bdata, i64 %bkj_idx
  %bkj = load i64, ptr %bkj_p, align 8
  %cij_idx = add i64 %ci_off, %j
  %cij_p = getelementptr inbounds i64, ptr %d_buf, i64 %cij_idx
  %cij_old = load i64, ptr %cij_p, align 8
  %prod = mul i64 %aik, %bkj
  %cij_new = add i64 %cij_old, %prod
  store i64 %cij_new, ptr %cij_p, align 8
  %j_next = add i64 %j, 1
  br label %loop_j
next_k:
  %k_next = add i64 %k, 1
  br label %loop_k
next_i:
  %i_next = add i64 %i, 1
  br label %loop_i
box_out:
  store i64 %tot, ptr %vp0, align 8
  %d_buf_int = ptrtoint ptr %d_buf to i64
  store i64 %d_buf_int, ptr %vp1, align 8
  store i64 %tot, ptr %vp2, align 8
  %dhdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  store i64 5, ptr %vp0, align 8
  %shdr_int = ptrtoint ptr %shdr to i64
  %dhdr_int = ptrtoint ptr %dhdr to i64
  store i64 %shdr_int, ptr %vp1, align 8
  store i64 %dhdr_int, ptr %vp2, align 8
  %res = call i64 @__rg_rt_box_rval(ptr %vec_tmp)
  call void @__rg_rt_drop_slot(ptr %s0)
  call void @__rg_rt_drop_slot(ptr %s1)
  ret i64 %res
slow:
  %res_s = call i64 @__rg_rt_einsum(ptr %slots_ptr, i64 %count, ptr %spec_ptr, i64 %spec_len)
  ret i64 %res_s
}

define i64 @__rg_fast_einsum_real(ptr %slots_ptr, i64 %count, ptr %spec_ptr, i64 %spec_len) noinline nounwind {
entry:
  %vec_tmp = alloca [3 x i64], align 8
  %is_c2 = icmp eq i64 %count, 2
  %is_s5 = icmp eq i64 %spec_len, 5
  %ok_cs = and i1 %is_c2, %is_s5
  br i1 %ok_cs, label %chk_spec, label %slow
chk_spec:
  %c0 = load i8, ptr %spec_ptr, align 1
  %p1 = getelementptr inbounds i8, ptr %spec_ptr, i64 1
  %c1 = load i8, ptr %p1, align 1
  %p2 = getelementptr inbounds i8, ptr %spec_ptr, i64 2
  %c2 = load i8, ptr %p2, align 1
  %p3 = getelementptr inbounds i8, ptr %spec_ptr, i64 3
  %c3 = load i8, ptr %p3, align 1
  %p4 = getelementptr inbounds i8, ptr %spec_ptr, i64 4
  %c4 = load i8, ptr %p4, align 1
  %is_comma = icmp eq i8 %c2, 44
  %mid_eq = icmp eq i8 %c1, %c3
  %out_ne = icmp ne i8 %c0, %c4
  %c0_ne_c1 = icmp ne i8 %c0, %c1
  %c4_ne_c1 = icmp ne i8 %c4, %c1
  %ok1 = and i1 %is_comma, %mid_eq
  %ok2 = and i1 %out_ne, %c0_ne_c1
  %ok3 = and i1 %ok1, %ok2
  %ok_spec = and i1 %ok3, %c4_ne_c1
  br i1 %ok_spec, label %chk_tensors, label %slow
chk_tensors:
  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0
  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1
  %va = load i64, ptr %s0, align 8
  %vb = load i64, ptr %s1, align 8
  %ann = icmp ne i64 %va, 0
  %al3 = and i64 %va, 7
  %ap_ok = icmp eq i64 %al3, 0
  %a_ok = and i1 %ann, %ap_ok
  %bnn = icmp ne i64 %vb, 0
  %bl3 = and i64 %vb, 7
  %bp_ok = icmp eq i64 %bl3, 0
  %b_ok = and i1 %bnn, %bp_ok
  %both_ok = and i1 %a_ok, %b_ok
  br i1 %both_ok, label %chk_tags, label %slow
chk_tags:
  %pa = inttoptr i64 %va to ptr
  %pb = inttoptr i64 %vb to ptr
  %atag = load i32, ptr %pa, align 4
  %btag = load i32, ptr %pb, align 4
  %at5 = icmp eq i32 %atag, 5
  %bt5 = icmp eq i32 %btag, 5
  %tags_ok = and i1 %at5, %bt5
  br i1 %tags_ok, label %chk_ranks, label %slow
chk_ranks:
  %ashp_p = getelementptr inbounds i8, ptr %pa, i64 8
  %ashdr = load ptr, ptr %ashp_p, align 8
  %ark_p = getelementptr inbounds i8, ptr %ashdr, i64 16
  %ark = load i64, ptr %ark_p, align 8
  %bshp_p = getelementptr inbounds i8, ptr %pb, i64 8
  %bshdr = load ptr, ptr %bshp_p, align 8
  %brk_p = getelementptr inbounds i8, ptr %bshdr, i64 16
  %brk = load i64, ptr %brk_p, align 8
  %ar2 = icmp eq i64 %ark, 2
  %br2 = icmp eq i64 %brk, 2
  %rks_ok = and i1 %ar2, %br2
  br i1 %rks_ok, label %chk_dims, label %slow
chk_dims:
  %asdp_p = getelementptr inbounds i8, ptr %ashdr, i64 8
  %asptr = load ptr, ptr %asdp_p, align 8
  %M = load i64, ptr %asptr, align 8
  %ak_p = getelementptr inbounds i64, ptr %asptr, i64 1
  %K = load i64, ptr %ak_p, align 8
  %bsdp_p = getelementptr inbounds i8, ptr %bshdr, i64 8
  %bsptr = load ptr, ptr %bsdp_p, align 8
  %bK = load i64, ptr %bsptr, align 8
  %bn_p = getelementptr inbounds i64, ptr %bsptr, i64 1
  %N = load i64, ptr %bn_p, align 8
  %k_eq = icmp eq i64 %K, %bK
  %m_gt0 = icmp sgt i64 %M, 0
  %k_gt0 = icmp sgt i64 %K, 0
  %n_gt0 = icmp sgt i64 %N, 0
  %mk_ok = and i1 %m_gt0, %k_gt0
  %mkn_ok = and i1 %mk_ok, %n_gt0
  %dims_ok = and i1 %k_eq, %mkn_ok
  br i1 %dims_ok, label %init_c, label %slow
init_c:
  %s_buf = call ptr @__rg_rt_alloc_buf(i64 16)
  store i64 %M, ptr %s_buf, align 8
  %s_buf1 = getelementptr inbounds i64, ptr %s_buf, i64 1
  store i64 %N, ptr %s_buf1, align 8
  %vp0 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 0
  %vp1 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 1
  %vp2 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 2
  store i64 2, ptr %vp0, align 8
  %s_buf_int = ptrtoint ptr %s_buf to i64
  store i64 %s_buf_int, ptr %vp1, align 8
  store i64 2, ptr %vp2, align 8
  %shdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  %tot = mul i64 %M, %N
  %d_bytes = shl i64 %tot, 3
  %d_buf = call ptr @__rg_rt_alloc_buf(i64 %d_bytes)
  call void asm sideeffect "rep stosq", "{rdi},{rax},{rcx},~{rdi},~{rcx},~{memory},~{dirflag},~{fpsr},~{flags}"(ptr %d_buf, i64 0, i64 %tot)
  %adhp_p = getelementptr inbounds i8, ptr %pa, i64 16
  %adhdr = load ptr, ptr %adhp_p, align 8
  %addp_p = getelementptr inbounds i8, ptr %adhdr, i64 8
  %adata = load ptr, ptr %addp_p, align 8
  %bdhp_p = getelementptr inbounds i8, ptr %pb, i64 16
  %bdhdr = load ptr, ptr %bdhp_p, align 8
  %bddp_p = getelementptr inbounds i8, ptr %bdhdr, i64 8
  %bdata = load ptr, ptr %bddp_p, align 8
  br label %loop_i
loop_i:
  %i = phi i64 [ 0, %init_c ], [ %i_next, %next_i ]
  %ci = icmp slt i64 %i, %M
  br i1 %ci, label %loop_k, label %box_out
loop_k:
  %k = phi i64 [ 0, %loop_i ], [ %k_next, %next_k ]
  %ck = icmp slt i64 %k, %K
  br i1 %ck, label %prep_j, label %next_i
prep_j:
  %ai_off = mul i64 %i, %K
  %aik_idx = add i64 %ai_off, %k
  %aik_p = getelementptr inbounds i64, ptr %adata, i64 %aik_idx
  %aik = load i64, ptr %aik_p, align 8
  %bk_off = mul i64 %k, %N
  %ci_off = mul i64 %i, %N
  br label %loop_j
loop_j:
  %j = phi i64 [ 0, %prep_j ], [ %j_next, %body_j ]
  %cj = icmp slt i64 %j, %N
  br i1 %cj, label %body_j, label %next_k
body_j:
  %bkj_idx = add i64 %bk_off, %j
  %bkj_p = getelementptr inbounds i64, ptr %bdata, i64 %bkj_idx
  %bkj = load i64, ptr %bkj_p, align 8
  %cij_idx = add i64 %ci_off, %j
  %cij_p = getelementptr inbounds i64, ptr %d_buf, i64 %cij_idx
  %cij_old = load i64, ptr %cij_p, align 8
  %aikd = bitcast i64 %aik to double
  %bkjd = bitcast i64 %bkj to double
  %cod = bitcast i64 %cij_old to double
  %pd = fmul double %aikd, %bkjd
  %nd = fadd double %cod, %pd
  %cij_new = bitcast double %nd to i64
  store i64 %cij_new, ptr %cij_p, align 8
  %j_next = add i64 %j, 1
  br label %loop_j
next_k:
  %k_next = add i64 %k, 1
  br label %loop_k
next_i:
  %i_next = add i64 %i, 1
  br label %loop_i
box_out:
  store i64 %tot, ptr %vp0, align 8
  %d_buf_int = ptrtoint ptr %d_buf to i64
  store i64 %d_buf_int, ptr %vp1, align 8
  store i64 %tot, ptr %vp2, align 8
  %dhdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)
  store i64 5, ptr %vp0, align 8
  %shdr_int = ptrtoint ptr %shdr to i64
  %dhdr_int = ptrtoint ptr %dhdr to i64
  store i64 %shdr_int, ptr %vp1, align 8
  store i64 %dhdr_int, ptr %vp2, align 8
  %res = call i64 @__rg_rt_box_rval(ptr %vec_tmp)
  call void @__rg_rt_drop_slot(ptr %s0)
  call void @__rg_rt_drop_slot(ptr %s1)
  ret i64 %res
slow:
  ret i64 0
}

define void @__rg_tensor_oob() noinline nounwind {
entry:
  %slot = alloca i64, align 8
  %w = call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 1, i64 2, ptr @__rg_tensor_oob_msg, i64 41)
  store i64 3, ptr %slot, align 8
  %r = call i64 @__rg_rt_builtin(i64 24, ptr %slot, i64 1)
  ret void
}

define i64 @__rg_tensor_bounds(i64 %base, ptr %idx, i64 %count) noinline nounwind {
entry:
  %nz = icmp ne i64 %base, 0
  %l3 = and i64 %base, 7
  %isp = icmp eq i64 %l3, 0
  %ok = and i1 %nz, %isp
  br i1 %ok, label %chk_tag, label %done
chk_tag:
  %bp = inttoptr i64 %base to ptr
  %tag = load i32, ptr %bp, align 4
  %ist = icmp eq i32 %tag, 5
  br i1 %ist, label %chk_rank, label %done
chk_rank:
  %shp_p = getelementptr inbounds i8, ptr %bp, i64 8
  %shdr = load ptr, ptr %shp_p, align 8
  %rk_p = getelementptr inbounds i8, ptr %shdr, i64 16
  %rk = load i64, ptr %rk_p, align 8
  %cnt_ok = icmp sle i64 %count, %rk
  br i1 %cnt_ok, label %init, label %done
init:
  %sb_p = getelementptr inbounds i8, ptr %shdr, i64 8
  %sbuf = load ptr, ptr %sb_p, align 8
  br label %loop
loop:
  %i = phi i64 [ 0, %init ], [ %i1, %next ]
  %more = icmp slt i64 %i, %count
  br i1 %more, label %body, label %done
body:
  %ip = getelementptr inbounds i64, ptr %idx, i64 %i
  %iv = load i64, ptr %ip, align 8
  %ib = and i64 %iv, 1
  %isi = icmp ne i64 %ib, 0
  br i1 %isi, label %chk, label %next
chk:
  %x = ashr i64 %iv, 1
  %dp = getelementptr inbounds i64, ptr %sbuf, i64 %i
  %d = load i64, ptr %dp, align 8
  %neg = icmp slt i64 %x, 0
  %big = icmp sge i64 %x, %d
  %bad = or i1 %neg, %big
  br i1 %bad, label %oob, label %next
oob:
  call void @__rg_tensor_oob()
  br label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 0
}

define i64 @__rg_real_to_int_bits(i64 %v) noinline nounwind {
entry:
  %nz = icmp ne i64 %v, 0
  %l3 = and i64 %v, 7
  %isp = icmp eq i64 %l3, 0
  %ok = and i1 %nz, %isp
  br i1 %ok, label %chk, label %pass
chk:
  %p = inttoptr i64 %v to ptr
  %hdr = load i64, ptr %p, align 8
  %is_real = icmp eq i64 %hdr, 0
  br i1 %is_real, label %conv, label %pass
conv:
  %pp = getelementptr inbounds i8, ptr %p, i64 8
  %raw = load i64, ptr %pp, align 8
  %ign = call i64 @__rg_rt_drop_val(i64 %v)
  %r = call i64 @__rg_box_i64(i64 %raw)
  ret i64 %r
pass:
  ret i64 %v
}

define i64 @__rg_real_from_bits(i64 %v) noinline nounwind {
entry:
  %buf = alloca [3 x i64], align 8
  %low = and i64 %v, 1
  %is_tag = icmp ne i64 %low, 0
  br i1 %is_tag, label %tagged, label %chk_zero
tagged:
  %raw_t = ashr i64 %v, 1
  br label %box
chk_zero:
  %is_zero = icmp eq i64 %v, 0
  br i1 %is_zero, label %box, label %chk_ptr
chk_ptr:
  %l3 = and i64 %v, 7
  %is_ptr = icmp eq i64 %l3, 0
  br i1 %is_ptr, label %chk_hdr, label %pass
chk_hdr:
  %p = inttoptr i64 %v to ptr
  %hdr = load i64, ptr %p, align 8
  %is_u64 = icmp eq i64 %hdr, -9223372036854775808
  br i1 %is_u64, label %boxed, label %pass
boxed:
  %pp = getelementptr inbounds i8, ptr %p, i64 8
  %raw_b = load i64, ptr %pp, align 8
  %ign = call i64 @__rg_rt_drop_val(i64 %v)
  br label %box
pass:
  ret i64 %v
box:
  %raw = phi i64 [ %raw_t, %tagged ], [ 0, %chk_zero ], [ %raw_b, %boxed ]
  %b0 = getelementptr inbounds [3 x i64], ptr %buf, i64 0, i64 0
  store i64 0, ptr %b0, align 8
  %b1 = getelementptr inbounds [3 x i64], ptr %buf, i64 0, i64 1
  store i64 %raw, ptr %b1, align 8
  %b2 = getelementptr inbounds [3 x i64], ptr %buf, i64 0, i64 2
  store i64 0, ptr %b2, align 8
  %r = call i64 @__rg_rt_box_rval(ptr %buf)
  ret i64 %r
}

define i64 @__rg_list_set(i64 %base, i64 %iv, i64 %val) noinline nounwind {
entry:
  %bp = inttoptr i64 %base to ptr
  %vp = getelementptr inbounds i8, ptr %bp, i64 8
  %vec = load ptr, ptr %vp, align 8
  %bufp = getelementptr inbounds i8, ptr %vec, i64 8
  %buf = load ptr, ptr %bufp, align 8
  %i = ashr i64 %iv, 1
  %ep = getelementptr inbounds i64, ptr %buf, i64 %i
  %old = load i64, ptr %ep, align 8
  store i64 %val, ptr %ep, align 8
  %d = call i64 @__rg_fast_drop_val(i64 %old)
  ret i64 0
}

define i64 @__rg_gt_rcvec(ptr %buf, i64 %len) noinline nounwind {
entry:
  %tmp = alloca [3 x i64], align 8
  %t1 = getelementptr inbounds [3 x i64], ptr %tmp, i64 0, i64 1
  %t2 = getelementptr inbounds [3 x i64], ptr %tmp, i64 0, i64 2
  store i64 %len, ptr %tmp, align 8
  %bi = ptrtoint ptr %buf to i64
  store i64 %bi, ptr %t1, align 8
  store i64 %len, ptr %t2, align 8
  %h = call ptr @__rg_rt_box_rc_vec(ptr %tmp)
  %hi = ptrtoint ptr %h to i64
  ret i64 %hi
}

define i64 @__rg_gt_rval(i64 %tag, i64 %a, i64 %b) noinline nounwind {
entry:
  %tmp = alloca [3 x i64], align 8
  %t1 = getelementptr inbounds [3 x i64], ptr %tmp, i64 0, i64 1
  %t2 = getelementptr inbounds [3 x i64], ptr %tmp, i64 0, i64 2
  store i64 %tag, ptr %tmp, align 8
  store i64 %a, ptr %t1, align 8
  store i64 %b, ptr %t2, align 8
  %r = call i64 @__rg_rt_box_rval(ptr %tmp)
  ret i64 %r
}

define i64 @__rg_gt_list_copy(i64 %src) noinline nounwind {
entry:
  %lenp = alloca i64, align 8
  %buf = call ptr @__rg_gt_vec_of(i64 %src, i64 8, ptr %lenp)
  %len = load i64, ptr %lenp, align 8
  %has = icmp sgt i64 %len, 0
  br i1 %has, label %alloc, label %empty
empty:
  %e = call i64 @__rg_make_empty_list()
  ret i64 %e
alloc:
  %bytes = shl i64 %len, 3
  %nb = call ptr @__rg_rt_alloc_buf(i64 %bytes)
  br label %loop
loop:
  %i = phi i64 [ 0, %alloc ], [ %inx, %loop ]
  %sip = getelementptr inbounds i64, ptr %buf, i64 %i
  %v = load i64, ptr %sip, align 8
  %c = call i64 @__rg_fast_clone_slot(i64 %v)
  %dip = getelementptr inbounds i64, ptr %nb, i64 %i
  store i64 %c, ptr %dip, align 8
  %inx = add i64 %i, 1
  %more = icmp slt i64 %inx, %len
  br i1 %more, label %loop, label %box
box:
  %h = call i64 @__rg_gt_rcvec(ptr %nb, i64 %len)
  %r = call i64 @__rg_gt_rval(i64 2, i64 %h, i64 0)
  ret i64 %r
}

define i64 @__rg_gt_repeat(i64 %src) noinline nounwind {
entry:
  %lenp = alloca i64, align 8
  %buf = call ptr @__rg_gt_vec_of(i64 %src, i64 8, ptr %lenp)
  %len = load i64, ptr %lenp, align 8
  %two = icmp sge i64 %len, 2
  br i1 %two, label %rd, label %empty
rd:
  %v = load i64, ptr %buf, align 8
  %np = getelementptr inbounds i64, ptr %buf, i64 1
  %nv = load i64, ptr %np, align 8
  %nb1 = and i64 %nv, 1
  %ntag = icmp ne i64 %nb1, 0
  %n0 = ashr i64 %nv, 1
  %n = select i1 %ntag, i64 %n0, i64 0
  %has = icmp sgt i64 %n, 0
  br i1 %has, label %alloc, label %empty
empty:
  %e = call i64 @__rg_make_empty_list()
  ret i64 %e
alloc:
  %bytes = shl i64 %n, 3
  %nb = call ptr @__rg_rt_alloc_buf(i64 %bytes)
  br label %loop
loop:
  %i = phi i64 [ 0, %alloc ], [ %inx, %loop ]
  %c = call i64 @__rg_fast_clone_slot(i64 %v)
  %dip = getelementptr inbounds i64, ptr %nb, i64 %i
  store i64 %c, ptr %dip, align 8
  %inx = add i64 %i, 1
  %more = icmp slt i64 %inx, %n
  br i1 %more, label %loop, label %box
box:
  %h = call i64 @__rg_gt_rcvec(ptr %nb, i64 %n)
  %r = call i64 @__rg_gt_rval(i64 2, i64 %h, i64 0)
  ret i64 %r
}

define i64 @__rg_gt_list_tensor(i64 %src) noinline nounwind {
entry:
  %lenp = alloca i64, align 8
  %buf = call ptr @__rg_gt_vec_of(i64 %src, i64 8, ptr %lenp)
  %len = load i64, ptr %lenp, align 8
  %sb = call ptr @__rg_rt_alloc_buf(i64 8)
  store i64 %len, ptr %sb, align 8
  %sh = call i64 @__rg_gt_rcvec(ptr %sb, i64 1)
  %bytes = shl i64 %len, 3
  %bytes8 = add i64 %bytes, 8
  %db = call ptr @__rg_rt_alloc_buf(i64 %bytes8)
  %has = icmp sgt i64 %len, 0
  br i1 %has, label %loop, label %box
loop:
  %i = phi i64 [ 0, %entry ], [ %inx, %next ]
  %sip = getelementptr inbounds i64, ptr %buf, i64 %i
  %v = load i64, ptr %sip, align 8
  %b1 = and i64 %v, 1
  %isint = icmp ne i64 %b1, 0
  br i1 %isint, label %tagged, label %chk
tagged:
  %raw_t = ashr i64 %v, 1
  br label %next
chk:
  %l3 = and i64 %v, 7
  %nz = icmp ne i64 %v, 0
  %isp = icmp eq i64 %l3, 0
  %ptr_ok = and i1 %nz, %isp
  br i1 %ptr_ok, label %boxed, label %next
boxed:
  %p = inttoptr i64 %v to ptr
  %pp = getelementptr inbounds i8, ptr %p, i64 8
  %raw_b = load i64, ptr %pp, align 8
  br label %next
next:
  %w = phi i64 [ %raw_t, %tagged ], [ %raw_b, %boxed ], [ %v, %chk ]
  %dip = getelementptr inbounds i64, ptr %db, i64 %i
  store i64 %w, ptr %dip, align 8
  %inx = add i64 %i, 1
  %more = icmp slt i64 %inx, %len
  br i1 %more, label %loop, label %box
box:
  %dh = call i64 @__rg_gt_rcvec(ptr %db, i64 %len)
  %r = call i64 @__rg_gt_rval(i64 5, i64 %sh, i64 %dh)
  ret i64 %r
}

define i64 @__rg_gt_tensor_list(i64 %src, i64 %real) noinline nounwind {
entry:
  %lenp = alloca i64, align 8
  %buf = call ptr @__rg_gt_vec_of(i64 %src, i64 16, ptr %lenp)
  %len = load i64, ptr %lenp, align 8
  %has = icmp sgt i64 %len, 0
  br i1 %has, label %alloc, label %empty
empty:
  %e = call i64 @__rg_make_empty_list()
  ret i64 %e
alloc:
  %bytes = shl i64 %len, 3
  %nb = call ptr @__rg_rt_alloc_buf(i64 %bytes)
  %isreal = icmp ne i64 %real, 0
  br label %loop
loop:
  %i = phi i64 [ 0, %alloc ], [ %inx, %next ]
  %sip = getelementptr inbounds i64, ptr %buf, i64 %i
  %w = load i64, ptr %sip, align 8
  br i1 %isreal, label %mkreal, label %mkint
mkreal:
  %rv = call i64 @__rg_gt_rval(i64 0, i64 %w, i64 0)
  br label %next
mkint:
  %iv = call i64 @__rg_box_i64(i64 %w)
  br label %next
next:
  %c = phi i64 [ %rv, %mkreal ], [ %iv, %mkint ]
  %dip = getelementptr inbounds i64, ptr %nb, i64 %i
  store i64 %c, ptr %dip, align 8
  %inx = add i64 %i, 1
  %more = icmp slt i64 %inx, %len
  br i1 %more, label %loop, label %box
box:
  %h = call i64 @__rg_gt_rcvec(ptr %nb, i64 %len)
  %r = call i64 @__rg_gt_rval(i64 2, i64 %h, i64 0)
  ret i64 %r
}

define i64 @__rg_gt_shape_tensor(i64 %src) noinline nounwind {
entry:
  %lenp = alloca i64, align 8
  %buf = call ptr @__rg_gt_vec_of(i64 %src, i64 8, ptr %lenp)
  %len = load i64, ptr %lenp, align 8
  %v0 = load i64, ptr %buf, align 8
  %fill = call i64 @__rg_gt_raw_word(i64 %v0)
  %rank = sub i64 %len, 1
  %sbytes = shl i64 %len, 3
  %sb = call ptr @__rg_rt_alloc_buf(i64 %sbytes)
  br label %dims
dims:
  %i = phi i64 [ 1, %entry ], [ %inx, %dbody ]
  %tot = phi i64 [ 1, %entry ], [ %tot2, %dbody ]
  %more = icmp slt i64 %i, %len
  br i1 %more, label %dbody, label %mkshape
dbody:
  %dp = getelementptr inbounds i64, ptr %buf, i64 %i
  %dv = load i64, ptr %dp, align 8
  %d = ashr i64 %dv, 1
  %im1 = sub i64 %i, 1
  %sp = getelementptr inbounds i64, ptr %sb, i64 %im1
  store i64 %d, ptr %sp, align 8
  %tot2 = mul i64 %tot, %d
  %inx = add i64 %i, 1
  br label %dims
mkshape:
  %sh = call i64 @__rg_gt_rcvec(ptr %sb, i64 %rank)
  %dbytes = shl i64 %tot, 3
  %dbytes8 = add i64 %dbytes, 8
  %db = call ptr @__rg_rt_alloc_buf(i64 %dbytes8)
  br label %fl
fl:
  %j = phi i64 [ 0, %mkshape ], [ %jn, %flbody ]
  %fmore = icmp slt i64 %j, %tot
  br i1 %fmore, label %flbody, label %box
flbody:
  %fp = getelementptr inbounds i64, ptr %db, i64 %j
  store i64 %fill, ptr %fp, align 8
  %jn = add i64 %j, 1
  br label %fl
box:
  %dh = call i64 @__rg_gt_rcvec(ptr %db, i64 %tot)
  %r = call i64 @__rg_gt_rval(i64 5, i64 %sh, i64 %dh)
  ret i64 %r
}

define void @__rg_sort_len_err() noinline nounwind {
entry:
  %slot = alloca i64, align 8
  %w = call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 1, i64 2, ptr @__rg_sort_len_msg, i64 57)
  store i64 3, ptr %slot, align 8
  %r = call i64 @__rg_rt_builtin(i64 24, ptr %slot, i64 1)
  ret void
}

define i1 @__rg_sort_str_less_slow(i64 %a, i64 %b) noinline nounwind {
entry:
  %slot = alloca i64, align 8
  %ca = call i64 @__rg_fast_clone_slot(i64 %a)
  %cb = call i64 @__rg_fast_clone_slot(i64 %b)
  store i64 %ca, ptr %slot, align 8
  %rs = call i64 @__rg_fast_bin_op(i64 8, ptr %slot, i64 %cb)
  %lts = icmp eq i64 %rs, 6
  ret i1 %lts
}

define i64 @__rg_sort_by(i64 %xs, i64 %keys, i64 %texts) noinline nounwind {
entry:
  %lxp = alloca i64, align 8
  %lkp = alloca i64, align 8
  %xb = call ptr @__rg_gt_vec_of(i64 %xs, i64 8, ptr %lxp)
  %kb = call ptr @__rg_gt_vec_of(i64 %keys, i64 8, ptr %lkp)
  %n = load i64, ptr %lxp, align 8
  %nk = load i64, ptr %lkp, align 8
  %same = icmp eq i64 %n, %nk
  br i1 %same, label %chk0, label %bad
bad:
  call void @__rg_sort_len_err()
  ret i64 0
chk0:
  %has = icmp sgt i64 %n, 0
  br i1 %has, label %alloc, label %empty
empty:
  %e = call i64 @__rg_make_empty_list()
  ret i64 %e
alloc:
  %bytes = shl i64 %n, 3
  %a = call ptr @__rg_rt_alloc_buf(i64 %bytes)
  %b = call ptr @__rg_rt_alloc_buf(i64 %bytes)
  br label %init
init:
  %i0 = phi i64 [ 0, %alloc ], [ %i0n, %init ]
  %t0 = shl i64 %i0, 1
  %tag0 = or i64 %t0, 1
  %ap0 = getelementptr inbounds i64, ptr %a, i64 %i0
  store i64 %tag0, ptr %ap0, align 8
  %bp0 = getelementptr inbounds i64, ptr %b, i64 %i0
  store i64 1, ptr %bp0, align 8
  %i0n = add i64 %i0, 1
  %im = icmp slt i64 %i0n, %n
  br i1 %im, label %init, label %passes
passes:
  %w = phi i64 [ 1, %init ], [ %w2, %pass_end ]
  %src = phi ptr [ %a, %init ], [ %dst, %pass_end ]
  %dst = phi ptr [ %b, %init ], [ %src, %pass_end ]
  %wmore = icmp slt i64 %w, %n
  br i1 %wmore, label %runs, label %finish
runs:
  %lo = phi i64 [ 0, %passes ], [ %lo2, %rr_done ]
  %lomore = icmp slt i64 %lo, %n
  br i1 %lomore, label %run, label %pass_end
run:
  %mid0 = add i64 %lo, %w
  %midlt = icmp slt i64 %mid0, %n
  %mid = select i1 %midlt, i64 %mid0, i64 %n
  %w2x = shl i64 %w, 1
  %hi0 = add i64 %lo, %w2x
  %hilt = icmp slt i64 %hi0, %n
  %hi = select i1 %hilt, i64 %hi0, i64 %n
  %c0a = icmp slt i64 %lo, %mid
  %c0b = icmp slt i64 %mid, %hi
  %c0 = and i1 %c0a, %c0b
  br i1 %c0, label %mcmp, label %rl0
mcmp:
  %ii = phi i64 [ %lo, %run ], [ %ii_n, %takei ], [ %ii, %takej ]
  %jj = phi i64 [ %mid, %run ], [ %jj, %takei ], [ %jj_n, %takej ]
  %kk = phi i64 [ %lo, %run ], [ %kk_i, %takei ], [ %kk_j, %takej ]
  %vip = getelementptr inbounds i64, ptr %src, i64 %ii
  %vi = load i64, ptr %vip, align 8
  %vjp = getelementptr inbounds i64, ptr %src, i64 %jj
  %vj = load i64, ptr %vjp, align 8
  %xi = ashr i64 %vi, 1
  %xj = ashr i64 %vj, 1
  %kip = getelementptr inbounds i64, ptr %kb, i64 %xi
  %ki = load i64, ptr %kip, align 8
  %kjp = getelementptr inbounds i64, ptr %kb, i64 %xj
  %kj = load i64, ptr %kjp, align 8
  %jless = call i1 @__rg_sort_less(i64 %kj, i64 %ki, i64 %texts)
  %dkp = getelementptr inbounds i64, ptr %dst, i64 %kk
  br i1 %jless, label %takej, label %takei
takei:
  store i64 %vi, ptr %dkp, align 8
  %ii_n = add i64 %ii, 1
  %kk_i = add i64 %kk, 1
  %mi = icmp slt i64 %ii_n, %mid
  br i1 %mi, label %mcmp, label %rl0
takej:
  store i64 %vj, ptr %dkp, align 8
  %jj_n = add i64 %jj, 1
  %kk_j = add i64 %kk, 1
  %mj = icmp slt i64 %jj_n, %hi
  br i1 %mj, label %mcmp, label %rl0
rl0:
  %ri0 = phi i64 [ %lo, %run ], [ %ii_n, %takei ], [ %ii, %takej ]
  %rj0 = phi i64 [ %mid, %run ], [ %jj, %takei ], [ %jj_n, %takej ]
  %rk0 = phi i64 [ %lo, %run ], [ %kk_i, %takei ], [ %kk_j, %takej ]
  br label %rl
rl:
  %ri = phi i64 [ %ri0, %rl0 ], [ %ri_n, %rlb ]
  %rk = phi i64 [ %rk0, %rl0 ], [ %rk_n, %rlb ]
  %rlm = icmp slt i64 %ri, %mid
  br i1 %rlm, label %rlb, label %rr
rlb:
  %rsp = getelementptr inbounds i64, ptr %src, i64 %ri
  %rv = load i64, ptr %rsp, align 8
  %rdp = getelementptr inbounds i64, ptr %dst, i64 %rk
  store i64 %rv, ptr %rdp, align 8
  %ri_n = add i64 %ri, 1
  %rk_n = add i64 %rk, 1
  br label %rl
rr:
  %rj = phi i64 [ %rj0, %rl ], [ %rj_n, %rrb ]
  %rk2 = phi i64 [ %rk, %rl ], [ %rk2_n, %rrb ]
  %rrm = icmp slt i64 %rj, %hi
  br i1 %rrm, label %rrb, label %rr_done
rrb:
  %rsp2 = getelementptr inbounds i64, ptr %src, i64 %rj
  %rv2 = load i64, ptr %rsp2, align 8
  %rdp2 = getelementptr inbounds i64, ptr %dst, i64 %rk2
  store i64 %rv2, ptr %rdp2, align 8
  %rj_n = add i64 %rj, 1
  %rk2_n = add i64 %rk2, 1
  br label %rr
rr_done:
  %lo2 = add i64 %lo, %w2x
  br label %runs
pass_end:
  %w2 = shl i64 %w, 1
  br label %passes
finish:
  br label %fill
fill:
  %fi = phi i64 [ 0, %finish ], [ %fin, %fill ]
  %fp = getelementptr inbounds i64, ptr %src, i64 %fi
  %fv = load i64, ptr %fp, align 8
  %fx = ashr i64 %fv, 1
  %xp = getelementptr inbounds i64, ptr %xb, i64 %fx
  %xv = load i64, ptr %xp, align 8
  %c = call i64 @__rg_fast_clone_slot(i64 %xv)
  store i64 %c, ptr %fp, align 8
  %fin = add i64 %fi, 1
  %fm = icmp slt i64 %fin, %n
  br i1 %fm, label %fill, label %box
box:
  %h = call i64 @__rg_gt_rcvec(ptr %src, i64 %n)
  %res = call i64 @__rg_gt_rval(i64 2, i64 %h, i64 0)
  %h2 = call i64 @__rg_gt_rcvec(ptr %dst, i64 %n)
  %r2 = call i64 @__rg_gt_rval(i64 2, i64 %h2, i64 0)
  %ign = call i64 @__rg_rt_drop_val(i64 %r2)
  ret i64 %res
}

define i64 @__rg_u8_get1_slow(i64 %t, i64 %iv) noinline nounwind {
entry:
  %s = alloca [2 x i64], align 8
  %s1 = getelementptr inbounds [2 x i64], ptr %s, i64 0, i64 1
  store i64 %iv, ptr %s, align 8
  store i64 %t, ptr %s1, align 8
  %r = call i64 @__rg_rt_ext(i64 105, ptr %s, i64 2)
  ret i64 %r
}

define void @__rg_u8_set1_slow(i64 %t, i64 %iv, i64 %vv) noinline nounwind {
entry:
  %s = alloca [3 x i64], align 8
  %s1 = getelementptr inbounds [3 x i64], ptr %s, i64 0, i64 1
  %s2 = getelementptr inbounds [3 x i64], ptr %s, i64 0, i64 2
  store i64 %iv, ptr %s, align 8
  store i64 %vv, ptr %s1, align 8
  store i64 %t, ptr %s2, align 8
  %r = call i64 @__rg_rt_ext(i64 106, ptr %s, i64 3)
  ret void
}

define void @__rg_sha256_transform(ptr %state, ptr %block) noinline nounwind {
entry:
  %w = alloca [64 x i32], align 16
  br label %w_load_loop
w_load_loop:
  %i0 = phi i64 [ 0, %entry ], [ %i0_next, %w_load_body ]
  %c0 = icmp slt i64 %i0, 16
  br i1 %c0, label %w_load_body, label %w_expand_loop
w_load_body:
  %b_ptr = getelementptr inbounds i32, ptr %block, i64 %i0
  %raw_w = load i32, ptr %b_ptr, align 1
  %be_w = call i32 @llvm.bswap.i32(i32 %raw_w)
  %w_ptr0 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %i0
  store i32 %be_w, ptr %w_ptr0, align 4
  %i0_next = add i64 %i0, 1
  br label %w_load_loop
w_expand_loop:
  %i1 = phi i64 [ 16, %w_load_loop ], [ %i1_next, %w_expand_body ]
  %c1 = icmp slt i64 %i1, 64
  br i1 %c1, label %w_expand_body, label %rounds_init
w_expand_body:
  %idx_m2 = sub i64 %i1, 2
  %idx_m7 = sub i64 %i1, 7
  %idx_m15 = sub i64 %i1, 15
  %idx_m16 = sub i64 %i1, 16
  %p_m2 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %idx_m2
  %p_m7 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %idx_m7
  %p_m15 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %idx_m15
  %p_m16 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %idx_m16
  %w_m2 = load i32, ptr %p_m2, align 4
  %w_m7 = load i32, ptr %p_m7, align 4
  %w_m15 = load i32, ptr %p_m15, align 4
  %w_m16 = load i32, ptr %p_m16, align 4
  %s0_a = call i32 @llvm.fshr.i32(i32 %w_m15, i32 %w_m15, i32 7)
  %s0_b = call i32 @llvm.fshr.i32(i32 %w_m15, i32 %w_m15, i32 18)
  %s0_c = lshr i32 %w_m15, 3
  %s0_ab = xor i32 %s0_a, %s0_b
  %s0 = xor i32 %s0_ab, %s0_c
  %s1_a = call i32 @llvm.fshr.i32(i32 %w_m2, i32 %w_m2, i32 17)
  %s1_b = call i32 @llvm.fshr.i32(i32 %w_m2, i32 %w_m2, i32 19)
  %s1_c = lshr i32 %w_m2, 10
  %s1_ab = xor i32 %s1_a, %s1_b
  %s1 = xor i32 %s1_ab, %s1_c
  %t_w1 = add i32 %w_m16, %s0
  %t_w2 = add i32 %t_w1, %w_m7
  %w_val = add i32 %t_w2, %s1
  %w_ptr1 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %i1
  store i32 %w_val, ptr %w_ptr1, align 4
  %i1_next = add i64 %i1, 1
  br label %w_expand_loop
rounds_init:
  %st0 = getelementptr inbounds i32, ptr %state, i64 0
  %st1 = getelementptr inbounds i32, ptr %state, i64 1
  %st2 = getelementptr inbounds i32, ptr %state, i64 2
  %st3 = getelementptr inbounds i32, ptr %state, i64 3
  %st4 = getelementptr inbounds i32, ptr %state, i64 4
  %st5 = getelementptr inbounds i32, ptr %state, i64 5
  %st6 = getelementptr inbounds i32, ptr %state, i64 6
  %st7 = getelementptr inbounds i32, ptr %state, i64 7
  %a0 = load i32, ptr %st0, align 4
  %b0 = load i32, ptr %st1, align 4
  %c0_v = load i32, ptr %st2, align 4
  %d0 = load i32, ptr %st3, align 4
  %e0 = load i32, ptr %st4, align 4
  %f0 = load i32, ptr %st5, align 4
  %g0 = load i32, ptr %st6, align 4
  %h0 = load i32, ptr %st7, align 4
  br label %rounds_loop
rounds_loop:
  %r = phi i64 [ 0, %rounds_init ], [ %r_next, %rounds_body ]
  %a = phi i32 [ %a0, %rounds_init ], [ %a_next, %rounds_body ]
  %b = phi i32 [ %b0, %rounds_init ], [ %a, %rounds_body ]
  %c = phi i32 [ %c0_v, %rounds_init ], [ %b, %rounds_body ]
  %d = phi i32 [ %d0, %rounds_init ], [ %c, %rounds_body ]
  %e = phi i32 [ %e0, %rounds_init ], [ %e_next, %rounds_body ]
  %f = phi i32 [ %f0, %rounds_init ], [ %e, %rounds_body ]
  %g = phi i32 [ %g0, %rounds_init ], [ %f, %rounds_body ]
  %h = phi i32 [ %h0, %rounds_init ], [ %g, %rounds_body ]
  %cr = icmp slt i64 %r, 64
  br i1 %cr, label %rounds_body, label %rounds_done
rounds_body:
  %ep1_a = call i32 @llvm.fshr.i32(i32 %e, i32 %e, i32 6)
  %ep1_b = call i32 @llvm.fshr.i32(i32 %e, i32 %e, i32 11)
  %ep1_c = call i32 @llvm.fshr.i32(i32 %e, i32 %e, i32 25)
  %ep1_ab = xor i32 %ep1_a, %ep1_b
  %S1 = xor i32 %ep1_ab, %ep1_c
  %ef = and i32 %e, %f
  %not_e = xor i32 %e, -1
  %neg_eg = and i32 %not_e, %g
  %ch = xor i32 %ef, %neg_eg
  %k_ptr = getelementptr inbounds [64 x i32], ptr @__rg_sha256_k, i64 0, i64 %r
  %k_val = load i32, ptr %k_ptr, align 4
  %wr_ptr = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %r
  %wr_val = load i32, ptr %wr_ptr, align 4
  %t1_1 = add i32 %h, %S1
  %t1_2 = add i32 %t1_1, %ch
  %t1_3 = add i32 %t1_2, %k_val
  %temp1 = add i32 %t1_3, %wr_val
  %ep0_a = call i32 @llvm.fshr.i32(i32 %a, i32 %a, i32 2)
  %ep0_b = call i32 @llvm.fshr.i32(i32 %a, i32 %a, i32 13)
  %ep0_c = call i32 @llvm.fshr.i32(i32 %a, i32 %a, i32 22)
  %ep0_ab = xor i32 %ep0_a, %ep0_b
  %S0 = xor i32 %ep0_ab, %ep0_c
  %ab = and i32 %a, %b
  %ac = and i32 %a, %c
  %bc = and i32 %b, %c
  %ab_ac = xor i32 %ab, %ac
  %maj = xor i32 %ab_ac, %bc
  %temp2 = add i32 %S0, %maj
  %e_next = add i32 %d, %temp1
  %a_next = add i32 %temp1, %temp2
  %r_next = add i64 %r, 1
  br label %rounds_loop
rounds_done:
  %fa = add i32 %a0, %a
  %fb = add i32 %b0, %b
  %fc = add i32 %c0_v, %c
  %fd = add i32 %d0, %d
  %fe = add i32 %e0, %e
  %ff = add i32 %f0, %f
  %fg = add i32 %g0, %g
  %fh = add i32 %h0, %h
  store i32 %fa, ptr %st0, align 4
  store i32 %fb, ptr %st1, align 4
  store i32 %fc, ptr %st2, align 4
  store i32 %fd, ptr %st3, align 4
  store i32 %fe, ptr %st4, align 4
  store i32 %ff, ptr %st5, align 4
  store i32 %fg, ptr %st6, align 4
  store i32 %fh, ptr %st7, align 4
  ret void
}

define i32 @__rg_memeq64(ptr %a, ptr %b) nounwind {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %cont ]
  %c = icmp slt i64 %i, 8
  br i1 %c, label %body, label %eq
body:
  %pa = getelementptr inbounds i64, ptr %a, i64 %i
  %pb = getelementptr inbounds i64, ptr %b, i64 %i
  %va = load i64, ptr %pa, align 1
  %vb = load i64, ptr %pb, align 1
  %same = icmp eq i64 %va, %vb
  br i1 %same, label %cont, label %neq
cont:
  %i_next = add i64 %i, 1
  br label %loop
eq:
  ret i32 1
neq:
  ret i32 0
}

define void @__rg_sha256_init(ptr %state) nounwind {
entry:
  %s0 = getelementptr inbounds i32, ptr %state, i64 0
  %s1 = getelementptr inbounds i32, ptr %state, i64 1
  %s2 = getelementptr inbounds i32, ptr %state, i64 2
  %s3 = getelementptr inbounds i32, ptr %state, i64 3
  %s4 = getelementptr inbounds i32, ptr %state, i64 4
  %s5 = getelementptr inbounds i32, ptr %state, i64 5
  %s6 = getelementptr inbounds i32, ptr %state, i64 6
  %s7 = getelementptr inbounds i32, ptr %state, i64 7
  store i32 1779033703, ptr %s0, align 4
  store i32 -1150833019, ptr %s1, align 4
  store i32 1013904242, ptr %s2, align 4
  store i32 -1521486534, ptr %s3, align 4
  store i32 1359893119, ptr %s4, align 4
  store i32 -1694144372, ptr %s5, align 4
  store i32 528734635, ptr %s6, align 4
  store i32 1541459225, ptr %s7, align 4
  ret void
}

define i64 @__rg_sha256_feed(ptr %state, ptr %buf, i64 %used, ptr %data, i64 %len) nounwind {
entry:
  %is_empty = icmp sle i64 %len, 0
  br i1 %is_empty, label %done_early, label %loop
done_early:
  ret i64 %used
loop:
  %pos = phi i64 [ 0, %entry ], [ %pos_next, %after_step ]
  %cur_used = phi i64 [ %used, %entry ], [ %next_used, %after_step ]
  %rem = sub i64 %len, %pos
  %has_more = icmp sgt i64 %rem, 0
  br i1 %has_more, label %step, label %done
step:
  %is_zero_used = icmp eq i64 %cur_used, 0
  %ge_64 = icmp sge i64 %rem, 64
  %can_direct = and i1 %is_zero_used, %ge_64
  br i1 %can_direct, label %direct_block, label %buf_copy
direct_block:
  %blk_ptr = getelementptr inbounds i8, ptr %data, i64 %pos
  call void @__rg_sha256_transform(ptr %state, ptr %blk_ptr)
  %pos_d = add i64 %pos, 64
  br label %after_step
buf_copy:
  %space = sub i64 64, %cur_used
  %take_lt = icmp slt i64 %rem, %space
  %take = select i1 %take_lt, i64 %rem, i64 %space
  %dst_ptr = getelementptr inbounds i8, ptr %buf, i64 %cur_used
  %src_ptr = getelementptr inbounds i8, ptr %data, i64 %pos
  call void @__rg_memcpy(ptr %dst_ptr, ptr %src_ptr, i64 %take)
  %u_after = add i64 %cur_used, %take
  %pos_b = add i64 %pos, %take
  %full = icmp eq i64 %u_after, 64
  br i1 %full, label %flush_buf, label %keep_buf
flush_buf:
  call void @__rg_sha256_transform(ptr %state, ptr %buf)
  br label %after_step
keep_buf:
  br label %after_step
after_step:
  %pos_next = phi i64 [ %pos_d, %direct_block ], [ %pos_b, %flush_buf ], [ %pos_b, %keep_buf ]
  %next_used = phi i64 [ 0, %direct_block ], [ 0, %flush_buf ], [ %u_after, %keep_buf ]
  br label %loop
done:
  ret i64 %cur_used
}

define void @__rg_sha256_compute2(ptr %data1, i64 %len1, ptr %data2, i64 %len2, ptr %out32) noinline nounwind {
entry:
  %state = alloca [8 x i32], align 16
  %buf = alloca [64 x i8], align 16
  %is_64 = icmp eq i64 %len1, 64
  %non_null1 = icmp ne ptr %data1, null
  %try_cache = and i1 %is_64, %non_null1
  br i1 %try_cache, label %spin_lock, label %general_init
spin_lock:
  %cas = cmpxchg ptr @__rg_sha256_lock, i32 0, i32 1 acquire monotonic
  %got = extractvalue { i32, i1 } %cas, 1
  br i1 %got, label %check_slot0, label %spin_lock
check_slot0:
  %v0 = load i32, ptr @__rg_sha256_cache_valid, align 4
  %is_v0 = icmp ne i32 %v0, 0
  br i1 %is_v0, label %cmp_slot0, label %check_slot1
cmp_slot0:
  %m0 = call i32 @__rg_memeq64(ptr @__rg_sha256_cache_keys, ptr %data1)
  %hit0 = icmp ne i32 %m0, 0
  br i1 %hit0, label %use_slot0, label %check_slot1
use_slot0:
  call void @__rg_memcpy(ptr %state, ptr @__rg_sha256_cache_states, i64 32)
  store atomic i32 0, ptr @__rg_sha256_lock release, align 4
  br label %after_block1
check_slot1:
  %v1_ptr = getelementptr inbounds [2 x i32], ptr @__rg_sha256_cache_valid, i64 0, i64 1
  %v1 = load i32, ptr %v1_ptr, align 4
  %is_v1 = icmp ne i32 %v1, 0
  br i1 %is_v1, label %cmp_slot1, label %cache_miss
cmp_slot1:
  %k1_ptr = getelementptr inbounds [2 x [64 x i8]], ptr @__rg_sha256_cache_keys, i64 0, i64 1
  %m1 = call i32 @__rg_memeq64(ptr %k1_ptr, ptr %data1)
  %hit1 = icmp ne i32 %m1, 0
  br i1 %hit1, label %use_slot1, label %cache_miss
use_slot1:
  %s1_ptr = getelementptr inbounds [2 x [8 x i32]], ptr @__rg_sha256_cache_states, i64 0, i64 1
  call void @__rg_memcpy(ptr %state, ptr %s1_ptr, i64 32)
  store atomic i32 0, ptr @__rg_sha256_lock release, align 4
  br label %after_block1
cache_miss:
  store atomic i32 0, ptr @__rg_sha256_lock release, align 4
  call void @__rg_sha256_init(ptr %state)
  call void @__rg_sha256_transform(ptr %state, ptr %data1)
  br label %spin_lock_save
spin_lock_save:
  %cas2 = cmpxchg ptr @__rg_sha256_lock, i32 0, i32 1 acquire monotonic
  %got2 = extractvalue { i32, i1 } %cas2, 1
  br i1 %got2, label %save_slot, label %spin_lock_save
save_slot:
  %nxt = load i32, ptr @__rg_sha256_cache_next, align 4
  %slot_idx = and i32 %nxt, 1
  %nxt_inc = xor i32 %slot_idx, 1
  store i32 %nxt_inc, ptr @__rg_sha256_cache_next, align 4
  %idx64 = zext i32 %slot_idx to i64
  %dst_k = getelementptr inbounds [2 x [64 x i8]], ptr @__rg_sha256_cache_keys, i64 0, i64 %idx64
  %dst_s = getelementptr inbounds [2 x [8 x i32]], ptr @__rg_sha256_cache_states, i64 0, i64 %idx64
  %dst_v = getelementptr inbounds [2 x i32], ptr @__rg_sha256_cache_valid, i64 0, i64 %idx64
  call void @__rg_memcpy(ptr %dst_k, ptr %data1, i64 64)
  call void @__rg_memcpy(ptr %dst_s, ptr %state, i64 32)
  store i32 1, ptr %dst_v, align 4
  store atomic i32 0, ptr @__rg_sha256_lock release, align 4
  br label %after_block1
after_block1:
  %u_from_cache = call i64 @__rg_sha256_feed(ptr %state, ptr %buf, i64 0, ptr %data2, i64 %len2)
  br label %finalize
general_init:
  call void @__rg_sha256_init(ptr %state)
  %u1 = call i64 @__rg_sha256_feed(ptr %state, ptr %buf, i64 0, ptr %data1, i64 %len1)
  %u2 = call i64 @__rg_sha256_feed(ptr %state, ptr %buf, i64 %u1, ptr %data2, i64 %len2)
  br label %finalize
finalize:
  %used_fin = phi i64 [ %u_from_cache, %after_block1 ], [ %u2, %general_init ]
  %p_pad = getelementptr inbounds i8, ptr %buf, i64 %used_fin
  store i8 -128, ptr %p_pad, align 1
  %u_pad = add i64 %used_fin, 1
  %gt_56 = icmp sgt i64 %u_pad, 56
  br i1 %gt_56, label %pad_two_blocks, label %pad_one_block
pad_two_blocks:
  %rem_64 = sub i64 64, %u_pad
  %p_z1 = getelementptr inbounds i8, ptr %buf, i64 %u_pad
  call void @__rg_memset(ptr %p_z1, i8 0, i64 %rem_64)
  call void @__rg_sha256_transform(ptr %state, ptr %buf)
  br label %pad_one_block
pad_one_block:
  %u_cur = phi i64 [ 0, %pad_two_blocks ], [ %u_pad, %finalize ]
  %rem_56 = sub i64 56, %u_cur
  %p_z2 = getelementptr inbounds i8, ptr %buf, i64 %u_cur
  call void @__rg_memset(ptr %p_z2, i8 0, i64 %rem_56)
  %tot_bytes = add i64 %len1, %len2
  %tot_bits = shl i64 %tot_bytes, 3
  %be_bits = call i64 @llvm.bswap.i64(i64 %tot_bits)
  %p_len = getelementptr inbounds i8, ptr %buf, i64 56
  store i64 %be_bits, ptr %p_len, align 8
  call void @__rg_sha256_transform(ptr %state, ptr %buf)
  br label %write_out_loop
write_out_loop:
  %wi = phi i64 [ 0, %pad_one_block ], [ %wi_next, %write_out_body ]
  %wc = icmp slt i64 %wi, 8
  br i1 %wc, label %write_out_body, label %done_all
write_out_body:
  %sp_w = getelementptr inbounds i32, ptr %state, i64 %wi
  %sv_w = load i32, ptr %sp_w, align 4
  %be_sv = call i32 @llvm.bswap.i32(i32 %sv_w)
  %op_w = getelementptr inbounds i32, ptr %out32, i64 %wi
  store i32 %be_sv, ptr %op_w, align 1
  %wi_next = add i64 %wi, 1
  br label %write_out_loop
done_all:
  ret void
}

; The product without carries of two words: its low (hi = 0) or its high
; 64 bits. With the instruction for it (PCLMULQDQ, at CPU level 3 and up:
; core/fuse.ll) or bit by bit (core/binop.ll).
declare i64 @rg_cpu_level()
declare i64 @rg_clmul_soft(i64, i64, i64)
declare <2 x i64> @llvm.x86.pclmulqdq(<2 x i64>, <2 x i64>, i8)

define i64 @__rg_clmul_hw(i64 %a, i64 %b, i64 %hi) noinline nounwind "target-features"="+sse2,+pclmul" {
entry:
  %va = insertelement <2 x i64> zeroinitializer, i64 %a, i32 0
  %vb = insertelement <2 x i64> zeroinitializer, i64 %b, i32 0
  %p = call <2 x i64> @llvm.x86.pclmulqdq(<2 x i64> %va, <2 x i64> %vb, i8 0)
  %lo = extractelement <2 x i64> %p, i32 0
  %h = extractelement <2 x i64> %p, i32 1
  %wanthi = icmp ne i64 %hi, 0
  %r = select i1 %wanthi, i64 %h, i64 %lo
  ret i64 %r
}

define i64 @__rg_clmul(i64 %a, i64 %b, i64 %hi) nounwind {
entry:
  %l = call i64 @rg_cpu_level()
  %has = icmp uge i64 %l, 3
  br i1 %has, label %hw, label %soft
hw:
  %r1 = call i64 @__rg_clmul_hw(i64 %a, i64 %b, i64 %hi)
  ret i64 %r1
soft:
  %r2 = call i64 @rg_clmul_soft(i64 %a, i64 %b, i64 %hi)
  ret i64 %r2
}
