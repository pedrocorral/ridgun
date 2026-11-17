; src/main/runtime/abi/inline.ll
; The helpers of the LLVM backend that must be inlined into the program
; (ADR-0013): the fast paths of counts, slots, tensor indices and comparisons.
; PERF-EXCEPTION: these are the only runtime functions that travel as text in
; every program module instead of living only in the runtime object; a call
; into the runtime for each of them costs more than the work they do.
; One source: build-linux-x86_64.sh --module writes this text into
; src/main/ridgun/lib/llvminl.ridgun for the compiler, and links a private
; copy (internal linkage) into the runtime object for abi/helpers.ll.
; The declarations of the runtime entry points come first.

declare i32 @llvm.bswap.i32(i32) nounwind readnone
declare i64 @llvm.bswap.i64(i64) nounwind readnone
declare i32 @llvm.fshr.i32(i32, i32, i32) nounwind readnone
declare i64 @llvm.fshr.i64(i64, i64, i64) nounwind readnone
declare i64 @llvm.fshl.i64(i64, i64, i64) nounwind readnone
declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1) nounwind
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1) nounwind
declare void @__rg_rt_init_frame(ptr nocapture, ptr nocapture, i64, i64)
declare i64 @__rg_rt_epilogue(ptr nocapture, i64, i64)
declare void @__rg_rt_tco_copy(ptr nocapture, i64, i64, i64)
declare void @__rg_rt_clear_locals(ptr nocapture, i64, i64)
declare i64 @__rg_rt_clone_slot(i64)
declare i64 @__rg_rt_drop_val(i64)
declare i64 @__rg_rt_cmm_move(ptr nocapture)
declare i64 @__rg_rt_store_slot(ptr nocapture, i64)
declare i64 @__rg_rt_rebind_slot(ptr nocapture, i64)
declare i64 @__rg_rt_cmm_drop_slot(ptr nocapture)
declare i64 @__rg_rt_load_real_lit(ptr, i64)
declare i64 @__rg_rt_load_str_lit(ptr, i64)
declare i64 @__rg_rt_load_adt0(ptr, i64)
declare i64 @__rg_rt_make_adt(ptr, i64, ptr, i64)
declare i64 @__rg_rt_make_list(ptr, i64)
declare i64 @__rg_rt_make_tuple(ptr, i64)
declare i64 @__rg_rt_make_tensor(ptr, i64)
declare i64 @__rg_rt_str_interp(ptr, i64)
declare i64 @__rg_rt_pack_seq(ptr, i64)
declare i64 @__rg_rt_as_bool(i64)
declare i64 @__rg_rt_match_int(i64, i64)
declare i64 @__rg_rt_match_real(i64, ptr, i64)
declare i64 @__rg_rt_match_str(i64, ptr, i64)
declare i64 @__rg_rt_match_bool(i64, i64)
declare i64 @__rg_rt_match_empty(i64)
declare i64 @__rg_rt_match_nonempty(i64)
declare i64 @__rg_rt_list_head(i64)
declare i64 @__rg_rt_list_tail(i64)
declare i64 @__rg_rt_match_tuple(i64, i64)
declare i64 @__rg_rt_tuple_get(i64, i64)
declare i64 @__rg_rt_match_adt(i64, ptr, i64, i64)
declare i64 @__rg_rt_adt_field(i64, i64)
declare i64 @__rg_rt_adt_set(ptr, i64, i64)
declare i64 @__rg_rt_bool_inv(i64)
declare i64 @__rg_rt_out(i64)
declare i64 @__rg_rt_echo(ptr, i64)
declare i64 @__rg_rt_bin_op(i64, ptr, i64)
declare i64 @__rg_rt_index(ptr, ptr, i64)
declare i64 @__rg_rt_index_set(ptr, ptr, i64, i64)
declare i64 @__rg_rt_seq_select(i64, ptr, i64)
declare i64 @__rg_rt_einsum(ptr, i64, ptr, i64)
declare i64 @__rg_rt_hadamard(i64, ptr, i64, ptr, i64)
declare i64 @__rg_rt_enter_region()
declare i64 @__rg_rt_exit_region(i64, i64)
declare i64 @__rg_rt_call_indirect1(i64, ptr)
declare i64 @__rg_rt_call_indirect2(i64, ptr)
declare i64 @__rg_rt_builtin(i64, ptr, i64)
declare i64 @__rg_rt_pal_dispatch(i64, ptr, i64)
declare i64 @__rg_rt_ext(i64, ptr, i64)
declare void @__rg_rt_drop_slot(ptr)
declare noalias ptr @__rg_rt_alloc_buf(i64)
declare noalias ptr @__rg_rt_box_rc_vec(ptr)
declare i64 @__rg_rt_box_rval(ptr)
declare i64 @__rg_rt_pop_i64(ptr)
declare i64 @__rg_rt_alloc_str(ptr, i64)

define i64 @__rg_box_i64(i64 %v) alwaysinline nounwind {
entry:
  %shl = shl i64 %v, 1
  %shr = ashr i64 %shl, 1
  %fits = icmp eq i64 %shr, %v
  br i1 %fits, label %tag_imm, label %box_heap
tag_imm:
  %tagged = or i64 %shl, 1
  ret i64 %tagged
box_heap:
  %boxed = call i64 @__rg_box_i64_slow(i64 %v)
  ret i64 %boxed
}

define i64 @__rg_match_heap_tag(i64 %val, i32 %want_tag) alwaysinline nounwind {
entry:
  %non_null = icmp ne i64 %val, 0
  %low3 = and i64 %val, 7
  %is_ptr = icmp eq i64 %low3, 0
  %ok = and i1 %non_null, %is_ptr
  br i1 %ok, label %chk, label %no
chk:
  %p = inttoptr i64 %val to ptr
  %t = load i64, ptr %p, align 8
  %w64 = sext i32 %want_tag to i64
  %m = icmp eq i64 %t, %w64
  %r = zext i1 %m to i64
  ret i64 %r
no:
  ret i64 0
}

define i64 @__rg_match_adt_fast(i64 %val, ptr %tp, i64 %tlen, i64 %arity) alwaysinline nounwind {
entry:
  %z = icmp eq i64 %val, 0
  %low = and i64 %val, 7
  %imm = icmp ne i64 %low, 0
  %bad = or i1 %z, %imm
  br i1 %bad, label %no, label %chk
chk:
  %p = inttoptr i64 %val to ptr
  %tag = load i32, ptr %p, align 8
  %is_adt = icmp eq i32 %tag, 4
  br i1 %is_adt, label %name, label %no
name:
  %np = getelementptr inbounds i8, ptr %p, i64 8
  %nh = load ptr, ptr %np, align 8
  %ndp = getelementptr inbounds i8, ptr %nh, i64 8
  %nd = load ptr, ptr %ndp, align 8
  %nlp = getelementptr inbounds i8, ptr %nh, i64 16
  %nl = load i64, ptr %nlp, align 8
  %same_len = icmp eq i64 %nl, %tlen
  br i1 %same_len, label %loop, label %no
loop:
  %i = phi i64 [ 0, %name ], [ %i1, %step ]
  %more = icmp ult i64 %i, %tlen
  br i1 %more, label %cmp, label %ar
cmp:
  %ap = getelementptr inbounds i8, ptr %nd, i64 %i
  %a = load i8, ptr %ap, align 1
  %bp = getelementptr inbounds i8, ptr %tp, i64 %i
  %b = load i8, ptr %bp, align 1
  %eq = icmp eq i8 %a, %b
  br i1 %eq, label %step, label %no
step:
  %i1 = add i64 %i, 1
  br label %loop
ar:
  %fhp = getelementptr inbounds i8, ptr %p, i64 16
  %fh = load ptr, ptr %fhp, align 8
  %flp = getelementptr inbounds i8, ptr %fh, i64 16
  %fl = load i64, ptr %flp, align 8
  %ok = icmp eq i64 %fl, %arity
  %r = zext i1 %ok to i64
  ret i64 %r
no:
  ret i64 0
}

define i64 @__rg_adt_field_fast(i64 %val, i64 %idx) alwaysinline nounwind {
entry:
  %z = icmp eq i64 %val, 0
  %low = and i64 %val, 7
  %imm = icmp ne i64 %low, 0
  %bad = or i1 %z, %imm
  br i1 %bad, label %slow, label %chk
chk:
  %p = inttoptr i64 %val to ptr
  %tag = load i32, ptr %p, align 8
  %is_adt = icmp eq i32 %tag, 4
  br i1 %is_adt, label %rd, label %slow
rd:
  %hp = getelementptr inbounds i8, ptr %p, i64 16
  %h = load ptr, ptr %hp, align 8
  %lp = getelementptr inbounds i8, ptr %h, i64 16
  %len = load i64, ptr %lp, align 8
  %ok = icmp ult i64 %idx, %len
  br i1 %ok, label %get, label %slow
get:
  %dp = getelementptr inbounds i8, ptr %h, i64 8
  %d = load ptr, ptr %dp, align 8
  %fp = getelementptr inbounds i64, ptr %d, i64 %idx
  %f = load i64, ptr %fp, align 8
  %c = call i64 @__rg_fast_clone_slot(i64 %f)
  ret i64 %c
slow:
  %r = call i64 @__rg_rt_adt_field(i64 %val, i64 %idx)
  ret i64 %r
}

define i64 @__rg_adt_field_neg(i64 %val, i64 %idx) alwaysinline nounwind {
entry:
  %p = inttoptr i64 %val to ptr
  %is_m1 = icmp eq i64 %idx, -1
  br i1 %is_m1, label %str_len, label %chk_m2
str_len:
  %tg = load i64, ptr %p, align 8
  %is_list = icmp eq i64 %tg, 2
  %hp1 = getelementptr inbounds i8, ptr %p, i64 8
  %hdr1 = load ptr, ptr %hp1, align 8
  %lp1 = getelementptr inbounds i8, ptr %hdr1, i64 16
  %l1 = load i64, ptr %lp1, align 8
  %stp = getelementptr inbounds i8, ptr %p, i64 16
  %st0 = load i64, ptr %stp, align 8
  %st1 = select i1 %is_list, i64 %st0, i64 0
  %ln = sub i64 %l1, %st1
  %sh1 = shl i64 %ln, 1
  %r1 = or i64 %sh1, 1
  ret i64 %r1
chk_m2:
  %is_m2 = icmp eq i64 %idx, -2
  br i1 %is_m2, label %list_len, label %tensor_dim
list_len:
  %hp2 = getelementptr inbounds i8, ptr %p, i64 16
  %hdr2 = load ptr, ptr %hp2, align 8
  %lp2 = getelementptr inbounds i8, ptr %hdr2, i64 16
  %l2 = load i64, ptr %lp2, align 8
  %sh2 = shl i64 %l2, 1
  %r2 = or i64 %sh2, 1
  ret i64 %r2
tensor_dim:
  %dim_i = sub i64 -10, %idx
  %hp3 = getelementptr inbounds i8, ptr %p, i64 8
  %shdr = load ptr, ptr %hp3, align 8, !invariant.load !0
  %sdp = getelementptr inbounds i8, ptr %shdr, i64 8
  %sdata = load ptr, ptr %sdp, align 8, !invariant.load !0
  %dp = getelementptr inbounds i64, ptr %sdata, i64 %dim_i
  %dval = load i64, ptr %dp, align 8, !invariant.load !0
  %sh3 = shl i64 %dval, 1
  %r3 = or i64 %sh3, 1
  ret i64 %r3
}

define i64 @__rg_not_op(i64 %val) alwaysinline nounwind {
entry:
  %low1 = and i64 %val, 1
  %is_int = icmp ne i64 %low1, 0
  br i1 %is_int, label %int_not, label %chk_u64
int_not:
  %r_int = xor i64 %val, -2
  ret i64 %r_int
chk_u64:
  %nn = icmp ne i64 %val, 0
  %l3 = and i64 %val, 7
  %is_p = icmp eq i64 %l3, 0
  %ok_p = and i1 %nn, %is_p
  br i1 %ok_p, label %chk_u64_hdr, label %bool_not
chk_u64_hdr:
  %p = inttoptr i64 %val to ptr
  %hdr = load i64, ptr %p, align 8
  %is_u64 = icmp eq i64 %hdr, -9223372036854775808
  br i1 %is_u64, label %u64_not, label %bool_not
u64_not:
  %pay_p = getelementptr inbounds i8, ptr %p, i64 8
  %raw = load i64, ptr %pay_p, align 8
  %ign = call i64 @__rg_rt_drop_val(i64 %val)
  %inv = xor i64 %raw, -1
  %r_u64 = call i64 @__rg_box_i64(i64 %inv)
  ret i64 %r_u64
bool_not:
  %r_bool = call i64 @__rg_rt_bool_inv(i64 %val)
  ret i64 %r_bool
}

define i64 @__rg_fast_clone_slot(i64 %v) inlinehint nounwind {
entry:
  %is_z = icmp eq i64 %v, 0
  %low3 = and i64 %v, 7
  %is_imm = icmp ne i64 %low3, 0
  %fast = or i1 %is_z, %is_imm
  br i1 %fast, label %done, label %slow
done:
  ret i64 %v
slow:
  %c = call i64 @__rg_rt_clone_slot(i64 %v)
  ret i64 %c
}

define i64 @__rg_fast_drop_val(i64 %v) inlinehint nounwind {
entry:
  %is_z = icmp eq i64 %v, 0
  %low3 = and i64 %v, 7
  %is_imm = icmp ne i64 %low3, 0
  %fast = or i1 %is_z, %is_imm
  br i1 %fast, label %done, label %slow
done:
  ret i64 0
slow:
  %d = call i64 @__rg_rt_drop_val(i64 %v)
  ret i64 %d
}

define i64 @__rg_fast_store_slot(ptr %slot_ptr, i64 %val) inlinehint nounwind {
entry:
  %old = load i64, ptr %slot_ptr, align 8
  store i64 %val, ptr %slot_ptr, align 8
  %is_z = icmp eq i64 %old, 0
  %low3 = and i64 %old, 7
  %is_imm = icmp ne i64 %low3, 0
  %fast = or i1 %is_z, %is_imm
  br i1 %fast, label %done, label %slow
done:
  ret i64 0
slow:
  %d = call i64 @__rg_rt_drop_val(i64 %old)
  ret i64 0
}

define i64 @__rg_fast_cmm_drop_slot(ptr %slot_ptr) inlinehint nounwind {
entry:
  %old = load i64, ptr %slot_ptr, align 8
  store i64 0, ptr %slot_ptr, align 8
  %is_z = icmp eq i64 %old, 0
  %low3 = and i64 %old, 7
  %is_imm = icmp ne i64 %low3, 0
  %fast = or i1 %is_z, %is_imm
  br i1 %fast, label %done, label %slow
done:
  ret i64 0
slow:
  %d = call i64 @__rg_cmm_drop_val_slow(i64 %old)
  ret i64 %d
}

define i64 @__rg_fast_rebind_slot(ptr %slot_ptr, i64 %val) inlinehint nounwind {
entry:
  %old = load i64, ptr %slot_ptr, align 8
  store i64 %val, ptr %slot_ptr, align 8
  %is_z = icmp eq i64 %old, 0
  %low3 = and i64 %old, 7
  %is_imm = icmp ne i64 %low3, 0
  %fast = or i1 %is_z, %is_imm
  br i1 %fast, label %done, label %slow
done:
  ret i64 0
slow:
  %d = call i64 @__rg_cmm_drop_val_slow(i64 %old)
  ret i64 0
}

define i64 @__rg_fast_as_bool(i64 %v) inlinehint nounwind {
entry:
  %is_z = icmp eq i64 %v, 0
  %low3 = and i64 %v, 7
  %is_imm = icmp ne i64 %low3, 0
  %fast = or i1 %is_z, %is_imm
  br i1 %fast, label %imm, label %slow
imm:
  %is_true = icmp eq i64 %v, 6
  %b = zext i1 %is_true to i64
  ret i64 %b
slow:
  %ign = call i64 @__rg_rt_drop_val(i64 %v)
  ret i64 0
}

define i64 @__rg_exec_int_op(i64 %op_id, i64 %x, i64 %y) alwaysinline nounwind {
entry:
  switch i64 %op_id, label %op_default [
    i64 0, label %op_add
    i64 1, label %op_sub
    i64 2, label %op_mul
    i64 3, label %op_div
    i64 4, label %op_mod
    i64 5, label %op_eq
    i64 6, label %op_neq
    i64 7, label %op_gt
    i64 8, label %op_lt
    i64 9, label %op_ge
    i64 10, label %op_le
    i64 11, label %op_and
    i64 12, label %op_or
    i64 13, label %op_xor
    i64 17, label %op_shl
    i64 18, label %op_shr
    i64 19, label %op_rotr
    i64 20, label %op_rotl
  ]
op_add:
  %r_add = add i64 %x, %y
  br label %box_res
op_sub:
  %r_sub = sub i64 %x, %y
  br label %box_res
op_mul:
  %r_mul = mul i64 %x, %y
  br label %box_res
op_div:
  %y_z1 = icmp eq i64 %y, 0
  %y_min1 = icmp eq i64 %y, -1
  %x_min1 = icmp eq i64 %x, -9223372036854775808
  %ovf1 = and i1 %x_min1, %y_min1
  %bad_div = or i1 %y_z1, %ovf1
  br i1 %bad_div, label %div_zero, label %div_ok
div_zero:
  %r_div_z = select i1 %y_z1, i64 0, i64 -9223372036854775808
  br label %box_res
div_ok:
  %r_div = sdiv i64 %x, %y
  br label %box_res
op_mod:
  %y_z2 = icmp eq i64 %y, 0
  %y_min2 = icmp eq i64 %y, -1
  %x_min2 = icmp eq i64 %x, -9223372036854775808
  %ovf2 = and i1 %x_min2, %y_min2
  %bad_mod = or i1 %y_z2, %ovf2
  br i1 %bad_mod, label %mod_zero, label %mod_ok
mod_zero:
  br label %box_res
mod_ok:
  %r_mod = srem i64 %x, %y
  br label %box_res
op_eq:
  %c_eq = icmp eq i64 %x, %y
  %b_eq = select i1 %c_eq, i64 6, i64 2
  ret i64 %b_eq
op_neq:
  %c_neq = icmp ne i64 %x, %y
  %b_neq = select i1 %c_neq, i64 6, i64 2
  ret i64 %b_neq
op_gt:
  %c_gt = icmp sgt i64 %x, %y
  %b_gt = select i1 %c_gt, i64 6, i64 2
  ret i64 %b_gt
op_lt:
  %c_lt = icmp slt i64 %x, %y
  %b_lt = select i1 %c_lt, i64 6, i64 2
  ret i64 %b_lt
op_ge:
  %c_ge = icmp sge i64 %x, %y
  %b_ge = select i1 %c_ge, i64 6, i64 2
  ret i64 %b_ge
op_le:
  %c_le = icmp sle i64 %x, %y
  %b_le = select i1 %c_le, i64 6, i64 2
  ret i64 %b_le
op_and:
  %r_and = and i64 %x, %y
  br label %box_res
op_or:
  %r_or = or i64 %x, %y
  br label %box_res
op_xor:
  %r_xor = xor i64 %x, %y
  br label %box_res
op_shl:
  %sh_a = and i64 %y, 63
  %r_shl = shl i64 %x, %sh_a
  br label %box_res
op_shr:
  %sh_b = and i64 %y, 63
  %r_shr = lshr i64 %x, %sh_b
  br label %box_res
op_rotr:
  %r_rotr = call i64 @llvm.fshr.i64(i64 %x, i64 %x, i64 %y)
  br label %box_res
op_rotl:
  %r_rotl = call i64 @llvm.fshl.i64(i64 %x, i64 %x, i64 %y)
  br label %box_res
op_default:
  br label %box_res
box_res:
  %raw_res = phi i64 [ %r_add, %op_add ], [ %r_sub, %op_sub ], [ %r_mul, %op_mul ], [ %r_div_z, %div_zero ], [ %r_div, %div_ok ], [ 0, %mod_zero ], [ %r_mod, %mod_ok ], [ %r_and, %op_and ], [ %r_or, %op_or ], [ %r_xor, %op_xor ], [ %r_shl, %op_shl ], [ %r_shr, %op_shr ], [ %r_rotr, %op_rotr ], [ %r_rotl, %op_rotl ], [ 0, %op_default ]
  %boxed = call i64 @__rg_box_i64(i64 %raw_res)
  ret i64 %boxed
}

define i64 @__rg_fast_bin_op(i64 %op_id, ptr %lhs_ptr, i64 %rhs) inlinehint nounwind {
entry:
  %lhs = load i64, ptr %lhs_ptr, align 8
  store i64 0, ptr %lhs_ptr, align 8
  %both = and i64 %lhs, %rhs
  %b0 = and i64 %both, 1
  %is_imm_int = icmp ne i64 %b0, 0
  br i1 %is_imm_int, label %fast_int, label %chk_bool_op
fast_int:
  %x = ashr i64 %lhs, 1
  %y = ashr i64 %rhs, 1
  %res = call i64 @__rg_exec_int_op(i64 %op_id, i64 %x, i64 %y)
  ret i64 %res
chk_bool_op:
  %l_b = and i64 %lhs, -5
  %r_b = and i64 %rhs, -5
  %l_is_b = icmp eq i64 %l_b, 2
  %r_is_b = icmp eq i64 %r_b, 2
  %both_b = and i1 %l_is_b, %r_is_b
  br i1 %both_b, label %fast_bool, label %slow
fast_bool:
  switch i64 %op_id, label %slow [
    i64 11, label %b_and
    i64 12, label %b_or
    i64 13, label %b_xor
    i64 5, label %b_eq
    i64 6, label %b_neq
  ]
b_and:
  %rb_and = and i64 %lhs, %rhs
  ret i64 %rb_and
b_or:
  %rb_or = or i64 %lhs, %rhs
  ret i64 %rb_or
b_xor:
  %xb = xor i64 %lhs, %rhs
  %rb_xor = or i64 %xb, 2
  ret i64 %rb_xor
b_eq:
  %ce = icmp eq i64 %lhs, %rhs
  %rb_eq = select i1 %ce, i64 6, i64 2
  ret i64 %rb_eq
b_neq:
  %cn = icmp ne i64 %lhs, %rhs
  %rb_neq = select i1 %cn, i64 6, i64 2
  ret i64 %rb_neq
slow:
  %res_s = call i64 @__rg_bin_op_u64_or_slow(i64 %op_id, i64 %lhs, i64 %rhs)
  ret i64 %res_s
}

define i64 @__rg_str_char_at_fast(i64 %sv, i64 %iv) inlinehint nounwind {
entry:
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
  ret i64 %res_in
oob:
  ret i64 -1
slow:
  %res_slow = call i64 @__rg_str_char_at_slow(i64 %sv, i64 %iv)
  ret i64 %res_slow
}

define i64 @__rg_tensor_index_1d(i64 %base_val, ptr %idx_ptr) inlinehint nounwind {
entry:
  %iv = load i64, ptr %idx_ptr, align 8
  store i64 0, ptr %idx_ptr, align 8
  %non_null = icmp ne i64 %base_val, 0
  %low3 = and i64 %base_val, 7
  %is_ptr = icmp eq i64 %low3, 0
  %ok_ptr = and i1 %non_null, %is_ptr
  br i1 %ok_ptr, label %chk_tag, label %slow
chk_tag:
  %bp = inttoptr i64 %base_val to ptr
  %tag = load i32, ptr %bp, align 4, !invariant.load !0
  %is_tensor = icmp eq i32 %tag, 5
  br i1 %is_tensor, label %chk_rank, label %slow
chk_rank:
  %shp_p = getelementptr inbounds i8, ptr %bp, i64 8
  %shdr = load ptr, ptr %shp_p, align 8, !invariant.load !0
  %rk_p = getelementptr inbounds i8, ptr %shdr, i64 16
  %rk = load i64, ptr %rk_p, align 8, !invariant.load !0
  %is_1d = icmp eq i64 %rk, 1
  br i1 %is_1d, label %chk_idx, label %slow
chk_idx:
  %ibit = and i64 %iv, 1
  %is_i = icmp ne i64 %ibit, 0
  br i1 %is_i, label %chk_bounds, label %slow
chk_bounds:
  %idx = ashr i64 %iv, 1
  %ge0 = icmp sge i64 %idx, 0
  br i1 %ge0, label %chk_len, label %slow
chk_len:
  %dhp_p = getelementptr inbounds i8, ptr %bp, i64 16
  %dhdr = load ptr, ptr %dhp_p, align 8, !invariant.load !0
  %len_p = getelementptr inbounds i8, ptr %dhdr, i64 16
  %len = load i64, ptr %len_p, align 8, !invariant.load !0
  %lt_len = icmp slt i64 %idx, %len
  br i1 %lt_len, label %fast_load, label %slow
fast_load:
  %dp_p = getelementptr inbounds i8, ptr %dhdr, i64 8
  %dptr = load ptr, ptr %dp_p, align 8, !invariant.load !0
  %ep = getelementptr inbounds i64, ptr %dptr, i64 %idx
  %raw = load i64, ptr %ep, align 8
  %boxed = call i64 @__rg_box_i64(i64 %raw)
  ret i64 %boxed
slow:
  %res = call i64 @__rg_tensor_index_1d_slow(i64 %base_val, i64 %iv)
  ret i64 %res
}

define i64 @__rg_tensor_index_2d(i64 %base_val, ptr %idx_ptr) inlinehint nounwind {
entry:
  %iv0 = load i64, ptr %idx_ptr, align 8
  %idx1_ptr = getelementptr inbounds i64, ptr %idx_ptr, i64 1
  %iv1 = load i64, ptr %idx1_ptr, align 8
  store i64 0, ptr %idx_ptr, align 8
  store i64 0, ptr %idx1_ptr, align 8
  %non_null = icmp ne i64 %base_val, 0
  %low3 = and i64 %base_val, 7
  %is_ptr = icmp eq i64 %low3, 0
  %ok_ptr = and i1 %non_null, %is_ptr
  br i1 %ok_ptr, label %chk_tag, label %slow
chk_tag:
  %bp = inttoptr i64 %base_val to ptr
  %tag = load i32, ptr %bp, align 4, !invariant.load !0
  %is_tensor = icmp eq i32 %tag, 5
  br i1 %is_tensor, label %chk_rank, label %slow
chk_rank:
  %shp_p = getelementptr inbounds i8, ptr %bp, i64 8
  %shdr = load ptr, ptr %shp_p, align 8, !invariant.load !0
  %rk_p = getelementptr inbounds i8, ptr %shdr, i64 16
  %rk = load i64, ptr %rk_p, align 8, !invariant.load !0
  %is_2d = icmp eq i64 %rk, 2
  br i1 %is_2d, label %chk_idx, label %slow
chk_idx:
  %both = and i64 %iv0, %iv1
  %ibit = and i64 %both, 1
  %is_i = icmp ne i64 %ibit, 0
  br i1 %is_i, label %chk_bounds, label %slow
chk_bounds:
  %i0 = ashr i64 %iv0, 1
  %i1 = ashr i64 %iv1, 1
  %ge0_0 = icmp sge i64 %i0, 0
  %ge0_1 = icmp sge i64 %i1, 0
  %ge0 = and i1 %ge0_0, %ge0_1
  br i1 %ge0, label %chk_dims, label %slow
chk_dims:
  %sdp_p = getelementptr inbounds i8, ptr %shdr, i64 8
  %sptr = load ptr, ptr %sdp_p, align 8, !invariant.load !0
  %d0 = load i64, ptr %sptr, align 8, !invariant.load !0
  %d1_p = getelementptr inbounds i64, ptr %sptr, i64 1
  %d1 = load i64, ptr %d1_p, align 8, !invariant.load !0
  %lt0 = icmp slt i64 %i0, %d0
  %lt1 = icmp slt i64 %i1, %d1
  %lt_both = and i1 %lt0, %lt1
  br i1 %lt_both, label %chk_len, label %slow
chk_len:
  %row_off = mul i64 %i0, %d1
  %flat = add i64 %row_off, %i1
  %dhp_p = getelementptr inbounds i8, ptr %bp, i64 16
  %dhdr = load ptr, ptr %dhp_p, align 8, !invariant.load !0
  %len_p = getelementptr inbounds i8, ptr %dhdr, i64 16
  %len = load i64, ptr %len_p, align 8, !invariant.load !0
  %lt_len = icmp slt i64 %flat, %len
  br i1 %lt_len, label %fast_load, label %slow
fast_load:
  %dp_p = getelementptr inbounds i8, ptr %dhdr, i64 8
  %dptr = load ptr, ptr %dp_p, align 8, !invariant.load !0
  %ep = getelementptr inbounds i64, ptr %dptr, i64 %flat
  %raw = load i64, ptr %ep, align 8
  %boxed = call i64 @__rg_box_i64(i64 %raw)
  ret i64 %boxed
slow:
  %res = call i64 @__rg_tensor_index_2d_slow(i64 %base_val, i64 %iv0, i64 %iv1)
  ret i64 %res
}

define i64 @__rg_tensor_index_set_1d(ptr %base_ptr, ptr %idx_ptr, i64 %val) inlinehint nounwind {
entry:
  %base_val = load i64, ptr %base_ptr, align 8
  store i64 0, ptr %base_ptr, align 8
  %iv = load i64, ptr %idx_ptr, align 8
  store i64 0, ptr %idx_ptr, align 8
  %vbit = and i64 %val, 1
  %v_is_int = icmp ne i64 %vbit, 0
  br i1 %v_is_int, label %val_int, label %val_chk_heap
val_int:
  %raw_int = ashr i64 %val, 1
  br label %chk_base
val_chk_heap:
  %v_nn = icmp ne i64 %val, 0
  %v_l3 = and i64 %val, 7
  %v_ptr_ok = icmp eq i64 %v_l3, 0
  %v_ok = and i1 %v_nn, %v_ptr_ok
  br i1 %v_ok, label %val_chk_tag0, label %slow
val_chk_tag0:
  %vp = inttoptr i64 %val to ptr
  %vtag = load i32, ptr %vp, align 4
  %v_is_t0 = icmp eq i32 %vtag, 0
  br i1 %v_is_t0, label %val_heap, label %slow
val_heap:
  %vpay_p = getelementptr inbounds i8, ptr %vp, i64 8
  %raw_heap = load i64, ptr %vpay_p, align 8
  br label %chk_base
chk_base:
  %raw_val = phi i64 [ %raw_int, %val_int ], [ %raw_heap, %val_heap ]
  %drop_val = phi i64 [ 0, %val_int ], [ %val, %val_heap ]
  %b_nn = icmp ne i64 %base_val, 0
  %b_l3 = and i64 %base_val, 7
  %b_ptr_ok = icmp eq i64 %b_l3, 0
  %b_ok = and i1 %b_nn, %b_ptr_ok
  br i1 %b_ok, label %chk_btag, label %slow
chk_btag:
  %bp = inttoptr i64 %base_val to ptr
  %btag = load i32, ptr %bp, align 4, !invariant.load !0
  %is_tensor = icmp eq i32 %btag, 5
  br i1 %is_tensor, label %chk_rank, label %slow
chk_rank:
  %shp_p = getelementptr inbounds i8, ptr %bp, i64 8
  %shdr = load ptr, ptr %shp_p, align 8, !invariant.load !0
  %rk_p = getelementptr inbounds i8, ptr %shdr, i64 16
  %rk = load i64, ptr %rk_p, align 8, !invariant.load !0
  %is_1d = icmp eq i64 %rk, 1
  br i1 %is_1d, label %chk_idx, label %slow
chk_idx:
  %ibit = and i64 %iv, 1
  %is_i = icmp ne i64 %ibit, 0
  br i1 %is_i, label %chk_bounds, label %slow
chk_bounds:
  %idx = ashr i64 %iv, 1
  %ge0 = icmp sge i64 %idx, 0
  br i1 %ge0, label %chk_len, label %slow
chk_len:
  %dhp_p = getelementptr inbounds i8, ptr %bp, i64 16
  %dhdr = load ptr, ptr %dhp_p, align 8, !invariant.load !0
  %len_p = getelementptr inbounds i8, ptr %dhdr, i64 16
  %len = load i64, ptr %len_p, align 8, !invariant.load !0
  %lt_len = icmp slt i64 %idx, %len
  br i1 %lt_len, label %fast_store, label %slow
fast_store:
  %dp_p = getelementptr inbounds i8, ptr %dhdr, i64 8
  %dptr = load ptr, ptr %dp_p, align 8, !invariant.load !0
  %ep = getelementptr inbounds i64, ptr %dptr, i64 %idx
  store i64 %raw_val, ptr %ep, align 8
  %need_drop = icmp ne i64 %drop_val, 0
  br i1 %need_drop, label %do_drop, label %finish
do_drop:
  %d_ign = call i64 @__rg_rt_drop_val(i64 %drop_val)
  br label %finish
finish:
  ret i64 %base_val
slow:
  %res = call i64 @__rg_tensor_index_set_1d_slow(i64 %base_val, i64 %iv, i64 %val)
  ret i64 %res
}

define i64 @__rg_tensor_index_set_2d(ptr %base_ptr, ptr %idx_ptr, i64 %val) inlinehint nounwind {
entry:
  %base_val = load i64, ptr %base_ptr, align 8
  store i64 0, ptr %base_ptr, align 8
  %iv0 = load i64, ptr %idx_ptr, align 8
  %idx1_ptr = getelementptr inbounds i64, ptr %idx_ptr, i64 1
  %iv1 = load i64, ptr %idx1_ptr, align 8
  store i64 0, ptr %idx_ptr, align 8
  store i64 0, ptr %idx1_ptr, align 8
  %vbit = and i64 %val, 1
  %v_is_int = icmp ne i64 %vbit, 0
  br i1 %v_is_int, label %val_int, label %val_chk_heap
val_int:
  %raw_int = ashr i64 %val, 1
  br label %chk_base
val_chk_heap:
  %v_nn = icmp ne i64 %val, 0
  %v_l3 = and i64 %val, 7
  %v_ptr_ok = icmp eq i64 %v_l3, 0
  %v_ok = and i1 %v_nn, %v_ptr_ok
  br i1 %v_ok, label %val_chk_tag0, label %slow
val_chk_tag0:
  %vp = inttoptr i64 %val to ptr
  %vtag = load i32, ptr %vp, align 4
  %v_is_t0 = icmp eq i32 %vtag, 0
  br i1 %v_is_t0, label %val_heap, label %slow
val_heap:
  %vpay_p = getelementptr inbounds i8, ptr %vp, i64 8
  %raw_heap = load i64, ptr %vpay_p, align 8
  br label %chk_base
chk_base:
  %raw_val = phi i64 [ %raw_int, %val_int ], [ %raw_heap, %val_heap ]
  %drop_val = phi i64 [ 0, %val_int ], [ %val, %val_heap ]
  %b_nn = icmp ne i64 %base_val, 0
  %b_l3 = and i64 %base_val, 7
  %b_ptr_ok = icmp eq i64 %b_l3, 0
  %b_ok = and i1 %b_nn, %b_ptr_ok
  br i1 %b_ok, label %chk_btag, label %slow
chk_btag:
  %bp = inttoptr i64 %base_val to ptr
  %btag = load i32, ptr %bp, align 4, !invariant.load !0
  %is_tensor = icmp eq i32 %btag, 5
  br i1 %is_tensor, label %chk_rank, label %slow
chk_rank:
  %shp_p = getelementptr inbounds i8, ptr %bp, i64 8
  %shdr = load ptr, ptr %shp_p, align 8, !invariant.load !0
  %rk_p = getelementptr inbounds i8, ptr %shdr, i64 16
  %rk = load i64, ptr %rk_p, align 8, !invariant.load !0
  %is_2d = icmp eq i64 %rk, 2
  br i1 %is_2d, label %chk_idx, label %slow
chk_idx:
  %both = and i64 %iv0, %iv1
  %ibit = and i64 %both, 1
  %is_i = icmp ne i64 %ibit, 0
  br i1 %is_i, label %chk_bounds, label %slow
chk_bounds:
  %i0 = ashr i64 %iv0, 1
  %i1 = ashr i64 %iv1, 1
  %ge0_0 = icmp sge i64 %i0, 0
  %ge0_1 = icmp sge i64 %i1, 0
  %ge0 = and i1 %ge0_0, %ge0_1
  br i1 %ge0, label %chk_dims, label %slow
chk_dims:
  %sdp_p = getelementptr inbounds i8, ptr %shdr, i64 8
  %sptr = load ptr, ptr %sdp_p, align 8, !invariant.load !0
  %d0 = load i64, ptr %sptr, align 8, !invariant.load !0
  %d1_p = getelementptr inbounds i64, ptr %sptr, i64 1
  %d1 = load i64, ptr %d1_p, align 8, !invariant.load !0
  %lt0 = icmp slt i64 %i0, %d0
  %lt1 = icmp slt i64 %i1, %d1
  %lt_both = and i1 %lt0, %lt1
  br i1 %lt_both, label %chk_len, label %slow
chk_len:
  %row_off = mul i64 %i0, %d1
  %flat = add i64 %row_off, %i1
  %dhp_p = getelementptr inbounds i8, ptr %bp, i64 16
  %dhdr = load ptr, ptr %dhp_p, align 8, !invariant.load !0
  %len_p = getelementptr inbounds i8, ptr %dhdr, i64 16
  %len = load i64, ptr %len_p, align 8, !invariant.load !0
  %lt_len = icmp slt i64 %flat, %len
  br i1 %lt_len, label %fast_store, label %slow
fast_store:
  %dp_p = getelementptr inbounds i8, ptr %dhdr, i64 8
  %dptr = load ptr, ptr %dp_p, align 8, !invariant.load !0
  %ep = getelementptr inbounds i64, ptr %dptr, i64 %flat
  store i64 %raw_val, ptr %ep, align 8
  %need_drop = icmp ne i64 %drop_val, 0
  br i1 %need_drop, label %do_drop, label %finish
do_drop:
  %d_ign = call i64 @__rg_rt_drop_val(i64 %drop_val)
  br label %finish
finish:
  ret i64 %base_val
slow:
  %res = call i64 @__rg_tensor_index_set_2d_slow(i64 %base_val, i64 %iv0, i64 %iv1, i64 %val)
  ret i64 %res
}

define i64 @__rg_is_list(i64 %v) alwaysinline nounwind {
entry:
  %nz = icmp ne i64 %v, 0
  %l3 = and i64 %v, 7
  %isp = icmp eq i64 %l3, 0
  %ok = and i1 %nz, %isp
  br i1 %ok, label %chk, label %no
chk:
  %p = inttoptr i64 %v to ptr
  %t = load i32, ptr %p, align 4
  %is = icmp eq i32 %t, 2
  %r = select i1 %is, i64 6, i64 2
  ret i64 %r
no:
  ret i64 2
}

define i64 @__rg_is_gen(i64 %v) alwaysinline nounwind {
entry:
  %b1 = and i64 %v, 1
  %isint = icmp ne i64 %b1, 0
  br i1 %isint, label %num, label %c2
c2:
  %z = icmp eq i64 %v, 0
  br i1 %z, label %gen, label %c3
c3:
  %l3 = and i64 %v, 7
  %imm = icmp ne i64 %l3, 0
  br i1 %imm, label %gen, label %c4
c4:
  %p = inttoptr i64 %v to ptr
  %t = load i32, ptr %p, align 4
  %isnum = icmp eq i32 %t, 0
  br i1 %isnum, label %num, label %gen
num:
  ret i64 2
gen:
  ret i64 6
}

define i64 @__rg_list_get(i64 %base, i64 %iv) inlinehint nounwind {
entry:
  %ib = and i64 %iv, 1
  %isi = icmp ne i64 %ib, 0
  br i1 %isi, label %chk, label %oob
chk:
  %i = ashr i64 %iv, 1
  %bp = inttoptr i64 %base to ptr
  %vp = getelementptr inbounds i8, ptr %bp, i64 8
  %vec = load ptr, ptr %vp, align 8
  %stp = getelementptr inbounds i8, ptr %bp, i64 16
  %st = load i64, ptr %stp, align 8
  %lp = getelementptr inbounds i8, ptr %vec, i64 16
  %len0 = load i64, ptr %lp, align 8
  %len = sub i64 %len0, %st
  %ge = icmp sge i64 %i, 0
  %lt = icmp slt i64 %i, %len
  %ok = and i1 %ge, %lt
  br i1 %ok, label %get, label %oob
get:
  %bufp = getelementptr inbounds i8, ptr %vec, i64 8
  %buf = load ptr, ptr %bufp, align 8
  %j = add i64 %i, %st
  %ep = getelementptr inbounds i64, ptr %buf, i64 %j
  %v = load i64, ptr %ep, align 8
  %c = call i64 @__rg_fast_clone_slot(i64 %v)
  ret i64 %c
oob:
  call void @__rg_tensor_oob()
  ret i64 0
}

define ptr @__rg_gt_vec_of(i64 %v, i64 %off, ptr %len_out) alwaysinline nounwind {
entry:
  %nz = icmp ne i64 %v, 0
  %l3 = and i64 %v, 7
  %isp = icmp eq i64 %l3, 0
  %ok = and i1 %nz, %isp
  br i1 %ok, label %rd, label %none
rd:
  %p = inttoptr i64 %v to ptr
  %hp = getelementptr inbounds i8, ptr %p, i64 %off
  %hdr = load ptr, ptr %hp, align 8
  %bp = getelementptr inbounds i8, ptr %hdr, i64 8
  %buf0 = load ptr, ptr %bp, align 8
  %lp = getelementptr inbounds i8, ptr %hdr, i64 16
  %len0 = load i64, ptr %lp, align 8
  %islist = icmp eq i64 %off, 8
  %stp = getelementptr inbounds i8, ptr %p, i64 16
  %st0 = load i64, ptr %stp, align 8
  %st = select i1 %islist, i64 %st0, i64 0
  %buf = getelementptr inbounds i64, ptr %buf0, i64 %st
  %len = sub i64 %len0, %st
  store i64 %len, ptr %len_out, align 8
  ret ptr %buf
none:
  store i64 0, ptr %len_out, align 8
  ret ptr null
}

define i64 @__rg_gt_raw_word(i64 %v) alwaysinline nounwind {
entry:
  %b1 = and i64 %v, 1
  %isint = icmp ne i64 %b1, 0
  br i1 %isint, label %tagged, label %chk
tagged:
  %raw_t = ashr i64 %v, 1
  ret i64 %raw_t
chk:
  %l3 = and i64 %v, 7
  %nz = icmp ne i64 %v, 0
  %isp = icmp eq i64 %l3, 0
  %ptr_ok = and i1 %nz, %isp
  br i1 %ptr_ok, label %boxed, label %other
boxed:
  %p = inttoptr i64 %v to ptr
  %pp = getelementptr inbounds i8, ptr %p, i64 8
  %raw_b = load i64, ptr %pp, align 8
  ret i64 %raw_b
other:
  ret i64 %v
}

define i1 @__rg_sort_is_str(i64 %v) alwaysinline nounwind {
entry:
  %nz = icmp ne i64 %v, 0
  %l3 = and i64 %v, 7
  %isp = icmp eq i64 %l3, 0
  %ok = and i1 %nz, %isp
  br i1 %ok, label %chk, label %no
chk:
  %p = inttoptr i64 %v to ptr
  %t = load i32, ptr %p, align 4
  %is = icmp eq i32 %t, 1
  ret i1 %is
no:
  ret i1 false
}

define i1 @__rg_sort_str_less(i64 %a, i64 %b) inlinehint nounwind {
entry:
  %oka = call i1 @__rg_sort_is_str(i64 %a)
  %okb = call i1 @__rg_sort_is_str(i64 %b)
  %ok = and i1 %oka, %okb
  br i1 %ok, label %fast, label %slow
slow:
  %lts = call i1 @__rg_sort_str_less_slow(i64 %a, i64 %b)
  ret i1 %lts
fast:
  %pa = inttoptr i64 %a to ptr
  %pb = inttoptr i64 %b to ptr
  %hap = getelementptr inbounds i8, ptr %pa, i64 8
  %ha = load ptr, ptr %hap, align 8
  %hbp = getelementptr inbounds i8, ptr %pb, i64 8
  %hb = load ptr, ptr %hbp, align 8
  %dap = getelementptr inbounds i8, ptr %ha, i64 8
  %da = load ptr, ptr %dap, align 8
  %dbp = getelementptr inbounds i8, ptr %hb, i64 8
  %db = load ptr, ptr %dbp, align 8
  %lap = getelementptr inbounds i8, ptr %ha, i64 16
  %la = load i64, ptr %lap, align 8
  %lbp = getelementptr inbounds i8, ptr %hb, i64 16
  %lb = load i64, ptr %lbp, align 8
  %alt = icmp ult i64 %la, %lb
  %m = select i1 %alt, i64 %la, i64 %lb
  br label %l8
l8:
  %i = phi i64 [ 0, %fast ], [ %i8, %e8 ]
  %r = sub i64 %m, %i
  %h8 = icmp uge i64 %r, 8
  br i1 %h8, label %c8, label %lb1
c8:
  %qap = getelementptr inbounds i8, ptr %da, i64 %i
  %qa = load i64, ptr %qap, align 1
  %qbp = getelementptr inbounds i8, ptr %db, i64 %i
  %qb = load i64, ptr %qbp, align 1
  %eq = icmp eq i64 %qa, %qb
  br i1 %eq, label %e8, label %d8
e8:
  %i8 = add i64 %i, 8
  br label %l8
d8:
  %sa = call i64 @llvm.bswap.i64(i64 %qa)
  %sb = call i64 @llvm.bswap.i64(i64 %qb)
  %lt8 = icmp ult i64 %sa, %sb
  ret i1 %lt8
lb1:
  %j = phi i64 [ %i, %l8 ], [ %j1, %be ]
  %more = icmp ult i64 %j, %m
  br i1 %more, label %bb, label %tail
bb:
  %cap = getelementptr inbounds i8, ptr %da, i64 %j
  %c1 = load i8, ptr %cap, align 1
  %cbp = getelementptr inbounds i8, ptr %db, i64 %j
  %c2 = load i8, ptr %cbp, align 1
  %ceq = icmp eq i8 %c1, %c2
  br i1 %ceq, label %be, label %bd
be:
  %j1 = add i64 %j, 1
  br label %lb1
bd:
  %lt1 = icmp ult i8 %c1, %c2
  ret i1 %lt1
tail:
  %ltl = icmp ult i64 %la, %lb
  ret i1 %ltl
}

define i1 @__rg_sort_less(i64 %ka, i64 %kb, i64 %texts) alwaysinline nounwind {
entry:
  %ist = icmp ne i64 %texts, 0
  br i1 %ist, label %t, label %n
n:
  %ra = call i64 @__rg_gt_raw_word(i64 %ka)
  %rb = call i64 @__rg_gt_raw_word(i64 %kb)
  %lt = icmp slt i64 %ra, %rb
  ret i1 %lt
t:
  %l2 = call i1 @__rg_sort_str_less(i64 %ka, i64 %kb)
  ret i1 %l2
}

define i64 @__rg_u8_get1(i64 %t, i64 %iv) alwaysinline nounwind {
entry:
  %tb = inttoptr i64 %t to ptr
  %dhp = getelementptr inbounds i8, ptr %tb, i64 16
  %dh = load ptr, ptr %dhp, align 8, !invariant.load !0
  %wpp = getelementptr inbounds i8, ptr %dh, i64 8
  %w = load ptr, ptr %wpp, align 8, !invariant.load !0
  %rk = load i64, ptr %w, align 8, !invariant.load !0
  %d1p = getelementptr inbounds i64, ptr %w, i64 1
  %d1 = load i64, ptr %d1p, align 8, !invariant.load !0
  %i = ashr i64 %iv, 1
  %isint = trunc i64 %iv to i1
  %r1 = icmp eq i64 %rk, 1
  %inb = icmp ult i64 %i, %d1
  %c0 = and i1 %isint, %r1
  %ok = and i1 %c0, %inb
  br i1 %ok, label %fast, label %slow
fast:
  %bp0 = getelementptr inbounds i64, ptr %w, i64 2
  %bp = getelementptr inbounds i8, ptr %bp0, i64 %i
  %b = load i8, ptr %bp, align 1
  %bz = zext i8 %b to i64
  %bs = shl i64 %bz, 1
  %r = or i64 %bs, 1
  ret i64 %r
slow:
  %rs = call i64 @__rg_u8_get1_slow(i64 %t, i64 %iv)
  ret i64 %rs
}

define void @__rg_u8_set1(i64 %t, i64 %iv, i64 %vv) alwaysinline nounwind {
entry:
  %tb = inttoptr i64 %t to ptr
  %dhp = getelementptr inbounds i8, ptr %tb, i64 16
  %dh = load ptr, ptr %dhp, align 8, !invariant.load !0
  %wpp = getelementptr inbounds i8, ptr %dh, i64 8
  %w = load ptr, ptr %wpp, align 8, !invariant.load !0
  %rk = load i64, ptr %w, align 8, !invariant.load !0
  %d1p = getelementptr inbounds i64, ptr %w, i64 1
  %d1 = load i64, ptr %d1p, align 8, !invariant.load !0
  %i = ashr i64 %iv, 1
  %v = ashr i64 %vv, 1
  %ii = and i64 %iv, %vv
  %isint = trunc i64 %ii to i1
  %r1 = icmp eq i64 %rk, 1
  %inb = icmp ult i64 %i, %d1
  %vok = icmp ult i64 %v, 256
  %c0 = and i1 %isint, %r1
  %c1 = and i1 %c0, %inb
  %ok = and i1 %c1, %vok
  br i1 %ok, label %fast, label %slow
fast:
  %bp0 = getelementptr inbounds i64, ptr %w, i64 2
  %bp = getelementptr inbounds i8, ptr %bp0, i64 %i
  %b = trunc i64 %v to i8
  store i8 %b, ptr %bp, align 1
  ret void
slow:
  call void @__rg_u8_set1_slow(i64 %t, i64 %iv, i64 %vv)
  ret void
}

define void @__rg_memcpy(ptr %dst, ptr %src, i64 %n) inlinehint nounwind {
entry:
  %c = icmp sgt i64 %n, 0
  br i1 %c, label %do_copy, label %done
do_copy:
  call void asm sideeffect "rep movsb", "{rdi},{rsi},{rcx},~{rdi},~{rsi},~{rcx},~{memory},~{dirflag},~{fpsr},~{flags}"(ptr %dst, ptr %src, i64 %n)
  br label %done
done:
  ret void
}

define void @__rg_memset(ptr %dst, i8 %val, i64 %n) inlinehint nounwind {
entry:
  %c = icmp sgt i64 %n, 0
  br i1 %c, label %do_set, label %done
do_set:
  call void asm sideeffect "rep stosb", "{rdi},{al},{rcx},~{rdi},~{rcx},~{memory},~{dirflag},~{fpsr},~{flags}"(ptr %dst, i8 %val, i64 %n)
  br label %done
done:
  ret void
}
