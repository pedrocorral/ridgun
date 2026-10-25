-- ============================================================
-- src/main/ridgun/lib/llvm.rg
-- Pure-Ridgun LLVM IR (.ll) Code Generator & Native Linker Driver
-- @implements FR-COMP-004
-- @implements FR-COMP-006
-- @implements FR-COMP-007
-- @implements FR-COMP-009
-- @implements FR-COMP-010
-- @implements FR-COMP-011
-- ============================================================

import elf64
import x86_64

-- ── Tree-Based O(N log N) String Concatenation ──────────────

fn :: join str pairs [String] [String] => [String]
      join str pairs [] acc = acc
      join str pairs (a:[]) acc = acc :: [a]
      join str pairs (a:b:rest) acc = join str pairs rest (acc :: [a + b])

fn :: join str tree [String] => String
      join str tree []       =  ""
      join str tree (s:[])   =  s
      join str tree xs       =  join str tree (join str pairs xs [])

-- ── Rodata String Escaping for LLVM IR Constant ─────────────

fn :: llvm hex digit Int => String
      llvm hex digit 0   =  "0"
      llvm hex digit 1   =  "1"
      llvm hex digit 2   =  "2"
      llvm hex digit 3   =  "3"
      llvm hex digit 4   =  "4"
      llvm hex digit 5   =  "5"
      llvm hex digit 6   =  "6"
      llvm hex digit 7   =  "7"
      llvm hex digit 8   =  "8"
      llvm hex digit 9   =  "9"
      llvm hex digit 10  =  "A"
      llvm hex digit 11  =  "B"
      llvm hex digit 12  =  "C"
      llvm hex digit 13  =  "D"
      llvm hex digit 14  =  "E"
      llvm hex digit _   =  "F"

fn :: llvm escape byte Int => String
      llvm escape byte b
        | b >= 32 AND b <= 126 AND b != 34 AND b != 92 AND b != 123 AND b != 125 = char from code b
        | otherwise =
          u = (b + 256) % 256
          "\\" + (llvm hex digit (u / 16)) + (llvm hex digit (u % 16))

fn :: llvm escape chunk String Int Int String => String
      llvm escape chunk s pos end acc
        | pos >= end = acc
        | otherwise =
          ch = llvm escape byte (str char at s pos)
          llvm escape chunk s (pos + 1) end (acc + ch)

fn :: llvm escape range String Int Int => String
      llvm escape range s start end
        | start >= end = ""
        | (end - start) <= 16 = llvm escape chunk s start end ""
        | otherwise =
          mid = start + ((end - start) / 2)
          (llvm escape range s start mid) + (llvm escape range s mid end)

fn :: llvm escape rodata String => String
      llvm escape rodata ""     =  "\\00"
      llvm escape rodata s      =  llvm escape range s 0 (str len s)

fn :: llvm rodata len String => Int
      llvm rodata len ""     =  1
      llvm rodata len s      =  str len s

-- ── Runtime Declarations & Pure LLVM IR Runtime Helpers ──────

fn :: llvm runtime declarations => String
      llvm runtime declarations =
        d1 = "declare i32 @llvm.bswap.i32(i32) nounwind readnone\ndeclare i64 @llvm.bswap.i64(i64) nounwind readnone\ndeclare i32 @llvm.fshr.i32(i32, i32, i32) nounwind readnone\ndeclare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1) nounwind\ndeclare void @llvm.memset.p0.i64(ptr, i8, i64, i1) nounwind\n"
        d2 = "declare void @__rg_rt_init_frame(ptr, ptr, i64, i64)\ndeclare i64 @__rg_rt_epilogue(ptr, i64, i64)\ndeclare void @__rg_rt_tco_copy(ptr, i64, i64, i64)\ndeclare void @__rg_rt_clear_locals(ptr, i64, i64)\ndeclare i64 @__rg_rt_clone_slot(i64)\ndeclare i64 @__rg_rt_drop_val(i64)\ndeclare i64 @__rg_rt_cmm_move(ptr)\ndeclare i64 @__rg_rt_store_slot(ptr, i64)\ndeclare i64 @__rg_rt_rebind_slot(ptr, i64)\ndeclare i64 @__rg_rt_cmm_drop_slot(ptr)\n"
        d3 = "declare i64 @__rg_rt_load_real_lit(ptr, i64)\ndeclare i64 @__rg_rt_load_str_lit(ptr, i64)\ndeclare i64 @__rg_rt_load_adt0(ptr, i64)\ndeclare i64 @__rg_rt_make_adt(ptr, i64, ptr, i64)\ndeclare i64 @__rg_rt_make_list(ptr, i64)\ndeclare i64 @__rg_rt_make_tuple(ptr, i64)\ndeclare i64 @__rg_rt_make_tensor(ptr, i64)\ndeclare i64 @__rg_rt_str_interp(ptr, i64)\ndeclare i64 @__rg_rt_pack_seq(ptr, i64)\ndeclare i64 @__rg_rt_as_bool(i64)\n"
        d4 = "declare i64 @__rg_rt_match_int(i64, i64)\ndeclare i64 @__rg_rt_match_real(i64, ptr, i64)\ndeclare i64 @__rg_rt_match_str(i64, ptr, i64)\ndeclare i64 @__rg_rt_match_bool(i64, i64)\ndeclare i64 @__rg_rt_match_empty(i64)\ndeclare i64 @__rg_rt_match_nonempty(i64)\ndeclare i64 @__rg_rt_list_head(i64)\ndeclare i64 @__rg_rt_list_tail(i64)\ndeclare i64 @__rg_rt_match_tuple(i64, i64)\ndeclare i64 @__rg_rt_tuple_get(i64, i64)\n"
        d5 = "declare i64 @__rg_rt_match_adt(i64, ptr, i64, i64)\ndeclare i64 @__rg_rt_adt_field(i64, i64)\ndeclare i64 @__rg_rt_adt_set(ptr, i64, i64)\ndeclare i64 @__rg_rt_bool_inv(i64)\ndeclare i64 @__rg_rt_out(i64)\ndeclare i64 @__rg_rt_echo(ptr, i64)\ndeclare i64 @__rg_rt_bin_op(i64, ptr, i64)\ndeclare i64 @__rg_rt_index(ptr, ptr, i64)\ndeclare i64 @__rg_rt_index_set(ptr, ptr, i64, i64)\ndeclare i64 @__rg_rt_seq_select(i64, ptr, i64)\n"
        d6 = "declare i64 @__rg_rt_einsum(ptr, i64, ptr, i64)\ndeclare i64 @__rg_rt_hadamard(i64, ptr, i64, ptr, i64)\ndeclare i64 @__rg_rt_enter_region()\ndeclare i64 @__rg_rt_exit_region(i64, i64)\ndeclare i64 @__rg_rt_call_indirect1(i64, ptr)\ndeclare i64 @__rg_rt_call_indirect2(i64, ptr)\ndeclare i64 @__rg_rt_builtin(i64, ptr, i64)\ndeclare i64 @__rg_rt_pal_dispatch(i64, ptr, i64)\ndeclare void @__rg_rt_drop_slot(ptr)\ndeclare ptr @__rg_rt_alloc_buf(i64)\ndeclare ptr @__rg_rt_box_rc_vec(ptr)\ndeclare i64 @__rg_rt_box_rval(ptr)\ndeclare i64 @__rg_rt_pop_i64(ptr)\ndeclare i64 @__rg_rt_alloc_str(ptr, i64)\n"
        join str tree [d1, d2, d3, d4, d5, d6]

fn :: llvm sha256 helpers => String
      llvm sha256 helpers =
        k = "@__rg_sha256_k = private unnamed_addr constant [64 x i32] [ i32 1116352408, i32 1899447441, i32 -1245643825, i32 -373957723, i32 961987163, i32 1508970993, i32 -1841331548, i32 -1424204075, i32 -670586216, i32 310598401, i32 607225278, i32 1426881987, i32 1925078388, i32 -2132889090, i32 -1680079193, i32 -1046744716, i32 -459576895, i32 -272742522, i32 264347078, i32 604807628, i32 770255983, i32 1249150122, i32 1555081692, i32 1996064986, i32 -1740746414, i32 -1473132947, i32 -1341970488, i32 -1084653625, i32 -958395405, i32 -710438585, i32 113926993, i32 338241895, i32 666307205, i32 773529912, i32 1294757372, i32 1396182291, i32 1695183700, i32 1986661051, i32 -2117940946, i32 -1838011259, i32 -1564481375, i32 -1474664885, i32 -1035236496, i32 -949202525, i32 -778901479, i32 -694614492, i32 -200395387, i32 275423344, i32 430227734, i32 506948616, i32 659060556, i32 883997877, i32 958139571, i32 1322822218, i32 1537002063, i32 1747873779, i32 1955562222, i32 2024104815, i32 -2067236844, i32 -1933114872, i32 -1866530822, i32 -1538233109, i32 -1090935817, i32 -965641998 ], align 16\n@__rg_sha256_lock = internal global i32 0, align 4\n@__rg_sha256_cache_valid = internal global [2 x i32] zeroinitializer, align 4\n@__rg_sha256_cache_next = internal global i32 0, align 4\n@__rg_sha256_cache_keys = internal global [2 x [64 x i8]] zeroinitializer, align 16\n@__rg_sha256_cache_states = internal global [2 x [8 x i32]] zeroinitializer, align 16\n"
        t1 = "define void @__rg_sha256_transform(ptr %state, ptr %block) nounwind {\nentry:\n  %w = alloca [64 x i32], align 16\n  br label %w_load_loop\nw_load_loop:\n  %i0 = phi i64 [ 0, %entry ], [ %i0_next, %w_load_body ]\n  %c0 = icmp slt i64 %i0, 16\n  br i1 %c0, label %w_load_body, label %w_expand_loop\nw_load_body:\n  %b_ptr = getelementptr inbounds i32, ptr %block, i64 %i0\n  %raw_w = load i32, ptr %b_ptr, align 1\n  %be_w = call i32 @llvm.bswap.i32(i32 %raw_w)\n  %w_ptr0 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %i0\n  store i32 %be_w, ptr %w_ptr0, align 4\n  %i0_next = add i64 %i0, 1\n  br label %w_load_loop\nw_expand_loop:\n  %i1 = phi i64 [ 16, %w_load_loop ], [ %i1_next, %w_expand_body ]\n  %c1 = icmp slt i64 %i1, 64\n  br i1 %c1, label %w_expand_body, label %rounds_init\nw_expand_body:\n  %idx_m2 = sub i64 %i1, 2\n  %idx_m7 = sub i64 %i1, 7\n  %idx_m15 = sub i64 %i1, 15\n  %idx_m16 = sub i64 %i1, 16\n  %p_m2 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %idx_m2\n  %p_m7 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %idx_m7\n  %p_m15 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %idx_m15\n  %p_m16 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %idx_m16\n  %w_m2 = load i32, ptr %p_m2, align 4\n  %w_m7 = load i32, ptr %p_m7, align 4\n  %w_m15 = load i32, ptr %p_m15, align 4\n  %w_m16 = load i32, ptr %p_m16, align 4\n  %s0_a = call i32 @llvm.fshr.i32(i32 %w_m15, i32 %w_m15, i32 7)\n  %s0_b = call i32 @llvm.fshr.i32(i32 %w_m15, i32 %w_m15, i32 18)\n  %s0_c = lshr i32 %w_m15, 3\n  %s0_ab = xor i32 %s0_a, %s0_b\n  %s0 = xor i32 %s0_ab, %s0_c\n  %s1_a = call i32 @llvm.fshr.i32(i32 %w_m2, i32 %w_m2, i32 17)\n  %s1_b = call i32 @llvm.fshr.i32(i32 %w_m2, i32 %w_m2, i32 19)\n  %s1_c = lshr i32 %w_m2, 10\n  %s1_ab = xor i32 %s1_a, %s1_b\n  %s1 = xor i32 %s1_ab, %s1_c\n  %t_w1 = add i32 %w_m16, %s0\n  %t_w2 = add i32 %t_w1, %w_m7\n  %w_val = add i32 %t_w2, %s1\n  %w_ptr1 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %i1\n  store i32 %w_val, ptr %w_ptr1, align 4\n  %i1_next = add i64 %i1, 1\n  br label %w_expand_loop\n"
        t2 = "rounds_init:\n  %st0 = getelementptr inbounds i32, ptr %state, i64 0\n  %st1 = getelementptr inbounds i32, ptr %state, i64 1\n  %st2 = getelementptr inbounds i32, ptr %state, i64 2\n  %st3 = getelementptr inbounds i32, ptr %state, i64 3\n  %st4 = getelementptr inbounds i32, ptr %state, i64 4\n  %st5 = getelementptr inbounds i32, ptr %state, i64 5\n  %st6 = getelementptr inbounds i32, ptr %state, i64 6\n  %st7 = getelementptr inbounds i32, ptr %state, i64 7\n  %a0 = load i32, ptr %st0, align 4\n  %b0 = load i32, ptr %st1, align 4\n  %c0_v = load i32, ptr %st2, align 4\n  %d0 = load i32, ptr %st3, align 4\n  %e0 = load i32, ptr %st4, align 4\n  %f0 = load i32, ptr %st5, align 4\n  %g0 = load i32, ptr %st6, align 4\n  %h0 = load i32, ptr %st7, align 4\n  br label %rounds_loop\nrounds_loop:\n  %r = phi i64 [ 0, %rounds_init ], [ %r_next, %rounds_body ]\n  %a = phi i32 [ %a0, %rounds_init ], [ %a_next, %rounds_body ]\n  %b = phi i32 [ %b0, %rounds_init ], [ %a, %rounds_body ]\n  %c = phi i32 [ %c0_v, %rounds_init ], [ %b, %rounds_body ]\n  %d = phi i32 [ %d0, %rounds_init ], [ %c, %rounds_body ]\n  %e = phi i32 [ %e0, %rounds_init ], [ %e_next, %rounds_body ]\n  %f = phi i32 [ %f0, %rounds_init ], [ %e, %rounds_body ]\n  %g = phi i32 [ %g0, %rounds_init ], [ %f, %rounds_body ]\n  %h = phi i32 [ %h0, %rounds_init ], [ %g, %rounds_body ]\n  %cr = icmp slt i64 %r, 64\n  br i1 %cr, label %rounds_body, label %rounds_done\nrounds_body:\n  %ep1_a = call i32 @llvm.fshr.i32(i32 %e, i32 %e, i32 6)\n  %ep1_b = call i32 @llvm.fshr.i32(i32 %e, i32 %e, i32 11)\n  %ep1_c = call i32 @llvm.fshr.i32(i32 %e, i32 %e, i32 25)\n  %ep1_ab = xor i32 %ep1_a, %ep1_b\n  %S1 = xor i32 %ep1_ab, %ep1_c\n  %ef = and i32 %e, %f\n  %not_e = xor i32 %e, -1\n  %neg_eg = and i32 %not_e, %g\n  %ch = xor i32 %ef, %neg_eg\n  %k_ptr = getelementptr inbounds [64 x i32], ptr @__rg_sha256_k, i64 0, i64 %r\n  %k_val = load i32, ptr %k_ptr, align 4\n  %wr_ptr = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %r\n  %wr_val = load i32, ptr %wr_ptr, align 4\n  %t1_1 = add i32 %h, %S1\n  %t1_2 = add i32 %t1_1, %ch\n  %t1_3 = add i32 %t1_2, %k_val\n  %temp1 = add i32 %t1_3, %wr_val\n  %ep0_a = call i32 @llvm.fshr.i32(i32 %a, i32 %a, i32 2)\n  %ep0_b = call i32 @llvm.fshr.i32(i32 %a, i32 %a, i32 13)\n  %ep0_c = call i32 @llvm.fshr.i32(i32 %a, i32 %a, i32 22)\n  %ep0_ab = xor i32 %ep0_a, %ep0_b\n  %S0 = xor i32 %ep0_ab, %ep0_c\n  %ab = and i32 %a, %b\n  %ac = and i32 %a, %c\n  %bc = and i32 %b, %c\n  %ab_ac = xor i32 %ab, %ac\n  %maj = xor i32 %ab_ac, %bc\n  %temp2 = add i32 %S0, %maj\n  %e_next = add i32 %d, %temp1\n  %a_next = add i32 %temp1, %temp2\n  %r_next = add i64 %r, 1\n  br label %rounds_loop\nrounds_done:\n  %fa = add i32 %a0, %a\n  %fb = add i32 %b0, %b\n  %fc = add i32 %c0_v, %c\n  %fd = add i32 %d0, %d\n  %fe = add i32 %e0, %e\n  %ff = add i32 %f0, %f\n  %fg = add i32 %g0, %g\n  %fh = add i32 %h0, %h\n  store i32 %fa, ptr %st0, align 4\n  store i32 %fb, ptr %st1, align 4\n  store i32 %fc, ptr %st2, align 4\n  store i32 %fd, ptr %st3, align 4\n  store i32 %fe, ptr %st4, align 4\n  store i32 %ff, ptr %st5, align 4\n  store i32 %fg, ptr %st6, align 4\n  store i32 %fh, ptr %st7, align 4\n  ret void\n}\n"
        c1 = "define void @__rg_memcpy(ptr %dst, ptr %src, i64 %n) noinline optnone nounwind {{\nentry:\n  br label %loop\nloop:\n  %i = phi i64 [ 0, %entry ], [ %i_next, %body ]\n  %c = icmp slt i64 %i, %n\n  br i1 %c, label %body, label %done\nbody:\n  %sp = getelementptr inbounds i8, ptr %src, i64 %i\n  %dp = getelementptr inbounds i8, ptr %dst, i64 %i\n  %v = load i8, ptr %sp, align 1\n  store i8 %v, ptr %dp, align 1\n  %i_next = add i64 %i, 1\n  br label %loop\ndone:\n  ret void\n}}\ndefine void @__rg_memset(ptr %dst, i8 %val, i64 %n) noinline optnone nounwind {{\nentry:\n  br label %loop\nloop:\n  %i = phi i64 [ 0, %entry ], [ %i_next, %body ]\n  %c = icmp slt i64 %i, %n\n  br i1 %c, label %body, label %done\nbody:\n  %dp = getelementptr inbounds i8, ptr %dst, i64 %i\n  store i8 %val, ptr %dp, align 1\n  %i_next = add i64 %i, 1\n  br label %loop\ndone:\n  ret void\n}}\ndefine i32 @__rg_memeq64(ptr %a, ptr %b) nounwind {{\nentry:\n  br label %loop\nloop:\n  %i = phi i64 [ 0, %entry ], [ %i_next, %cont ]\n  %c = icmp slt i64 %i, 8\n  br i1 %c, label %body, label %eq\nbody:\n  %pa = getelementptr inbounds i64, ptr %a, i64 %i\n  %pb = getelementptr inbounds i64, ptr %b, i64 %i\n  %va = load i64, ptr %pa, align 1\n  %vb = load i64, ptr %pb, align 1\n  %same = icmp eq i64 %va, %vb\n  br i1 %same, label %cont, label %neq\ncont:\n  %i_next = add i64 %i, 1\n  br label %loop\neq:\n  ret i32 1\nneq:\n  ret i32 0\n}}\ndefine void @__rg_sha256_init(ptr %state) nounwind {{\nentry:\n  %s0 = getelementptr inbounds i32, ptr %state, i64 0\n  %s1 = getelementptr inbounds i32, ptr %state, i64 1\n  %s2 = getelementptr inbounds i32, ptr %state, i64 2\n  %s3 = getelementptr inbounds i32, ptr %state, i64 3\n  %s4 = getelementptr inbounds i32, ptr %state, i64 4\n  %s5 = getelementptr inbounds i32, ptr %state, i64 5\n  %s6 = getelementptr inbounds i32, ptr %state, i64 6\n  %s7 = getelementptr inbounds i32, ptr %state, i64 7\n  store i32 1779033703, ptr %s0, align 4\n  store i32 -1150833019, ptr %s1, align 4\n  store i32 1013904242, ptr %s2, align 4\n  store i32 -1521486534, ptr %s3, align 4\n  store i32 1359893119, ptr %s4, align 4\n  store i32 -1694144372, ptr %s5, align 4\n  store i32 528734635, ptr %s6, align 4\n  store i32 1541459225, ptr %s7, align 4\n  ret void\n}}\n"
        c2 = "define i64 @__rg_sha256_feed(ptr %state, ptr %buf, i64 %used, ptr %data, i64 %len) nounwind {{\nentry:\n  %is_empty = icmp sle i64 %len, 0\n  br i1 %is_empty, label %done_early, label %loop\ndone_early:\n  ret i64 %used\nloop:\n  %pos = phi i64 [ 0, %entry ], [ %pos_next, %after_step ]\n  %cur_used = phi i64 [ %used, %entry ], [ %next_used, %after_step ]\n  %rem = sub i64 %len, %pos\n  %has_more = icmp sgt i64 %rem, 0\n  br i1 %has_more, label %step, label %done\nstep:\n  %is_zero_used = icmp eq i64 %cur_used, 0\n  %ge_64 = icmp sge i64 %rem, 64\n  %can_direct = and i1 %is_zero_used, %ge_64\n  br i1 %can_direct, label %direct_block, label %buf_copy\ndirect_block:\n  %blk_ptr = getelementptr inbounds i8, ptr %data, i64 %pos\n  call void @__rg_sha256_transform(ptr %state, ptr %blk_ptr)\n  %pos_d = add i64 %pos, 64\n  br label %after_step\nbuf_copy:\n  %space = sub i64 64, %cur_used\n  %take_lt = icmp slt i64 %rem, %space\n  %take = select i1 %take_lt, i64 %rem, i64 %space\n  %dst_ptr = getelementptr inbounds i8, ptr %buf, i64 %cur_used\n  %src_ptr = getelementptr inbounds i8, ptr %data, i64 %pos\n  call void @__rg_memcpy(ptr %dst_ptr, ptr %src_ptr, i64 %take)\n  %u_after = add i64 %cur_used, %take\n  %pos_b = add i64 %pos, %take\n  %full = icmp eq i64 %u_after, 64\n  br i1 %full, label %flush_buf, label %keep_buf\nflush_buf:\n  call void @__rg_sha256_transform(ptr %state, ptr %buf)\n  br label %after_step\nkeep_buf:\n  br label %after_step\nafter_step:\n  %pos_next = phi i64 [ %pos_d, %direct_block ], [ %pos_b, %flush_buf ], [ %pos_b, %keep_buf ]\n  %next_used = phi i64 [ 0, %direct_block ], [ 0, %flush_buf ], [ %u_after, %keep_buf ]\n  br label %loop\ndone:\n  ret i64 %cur_used\n}}\n"
        c3 = "define void @__rg_sha256_compute2(ptr %data1, i64 %len1, ptr %data2, i64 %len2, ptr %out32) nounwind {{\nentry:\n  %state = alloca [8 x i32], align 16\n  %buf = alloca [64 x i8], align 16\n  %is_64 = icmp eq i64 %len1, 64\n  %non_null1 = icmp ne ptr %data1, null\n  %try_cache = and i1 %is_64, %non_null1\n  br i1 %try_cache, label %spin_lock, label %general_init\nspin_lock:\n  %cas = cmpxchg ptr @__rg_sha256_lock, i32 0, i32 1 acquire monotonic\n  %got = extractvalue {{ i32, i1 }} %cas, 1\n  br i1 %got, label %check_slot0, label %spin_lock\ncheck_slot0:\n  %v0 = load i32, ptr @__rg_sha256_cache_valid, align 4\n  %is_v0 = icmp ne i32 %v0, 0\n  br i1 %is_v0, label %cmp_slot0, label %check_slot1\ncmp_slot0:\n  %m0 = call i32 @__rg_memeq64(ptr @__rg_sha256_cache_keys, ptr %data1)\n  %hit0 = icmp ne i32 %m0, 0\n  br i1 %hit0, label %use_slot0, label %check_slot1\nuse_slot0:\n  call void @__rg_memcpy(ptr %state, ptr @__rg_sha256_cache_states, i64 32)\n  store atomic i32 0, ptr @__rg_sha256_lock release, align 4\n  br label %after_block1\ncheck_slot1:\n  %v1_ptr = getelementptr inbounds [2 x i32], ptr @__rg_sha256_cache_valid, i64 0, i64 1\n  %v1 = load i32, ptr %v1_ptr, align 4\n  %is_v1 = icmp ne i32 %v1, 0\n  br i1 %is_v1, label %cmp_slot1, label %cache_miss\ncmp_slot1:\n  %k1_ptr = getelementptr inbounds [2 x [64 x i8]], ptr @__rg_sha256_cache_keys, i64 0, i64 1\n  %m1 = call i32 @__rg_memeq64(ptr %k1_ptr, ptr %data1)\n  %hit1 = icmp ne i32 %m1, 0\n  br i1 %hit1, label %use_slot1, label %cache_miss\nuse_slot1:\n  %s1_ptr = getelementptr inbounds [2 x [8 x i32]], ptr @__rg_sha256_cache_states, i64 0, i64 1\n  call void @__rg_memcpy(ptr %state, ptr %s1_ptr, i64 32)\n  store atomic i32 0, ptr @__rg_sha256_lock release, align 4\n  br label %after_block1\ncache_miss:\n  store atomic i32 0, ptr @__rg_sha256_lock release, align 4\n  call void @__rg_sha256_init(ptr %state)\n  call void @__rg_sha256_transform(ptr %state, ptr %data1)\n  br label %spin_lock_save\nspin_lock_save:\n  %cas2 = cmpxchg ptr @__rg_sha256_lock, i32 0, i32 1 acquire monotonic\n  %got2 = extractvalue {{ i32, i1 }} %cas2, 1\n  br i1 %got2, label %save_slot, label %spin_lock_save\nsave_slot:\n  %nxt = load i32, ptr @__rg_sha256_cache_next, align 4\n  %slot_idx = and i32 %nxt, 1\n  %nxt_inc = xor i32 %slot_idx, 1\n  store i32 %nxt_inc, ptr @__rg_sha256_cache_next, align 4\n  %idx64 = zext i32 %slot_idx to i64\n  %dst_k = getelementptr inbounds [2 x [64 x i8]], ptr @__rg_sha256_cache_keys, i64 0, i64 %idx64\n  %dst_s = getelementptr inbounds [2 x [8 x i32]], ptr @__rg_sha256_cache_states, i64 0, i64 %idx64\n  %dst_v = getelementptr inbounds [2 x i32], ptr @__rg_sha256_cache_valid, i64 0, i64 %idx64\n  call void @__rg_memcpy(ptr %dst_k, ptr %data1, i64 64)\n  call void @__rg_memcpy(ptr %dst_s, ptr %state, i64 32)\n  store i32 1, ptr %dst_v, align 4\n  store atomic i32 0, ptr @__rg_sha256_lock release, align 4\n  br label %after_block1\n"
        c4 = "after_block1:\n  %u_from_cache = call i64 @__rg_sha256_feed(ptr %state, ptr %buf, i64 0, ptr %data2, i64 %len2)\n  br label %finalize\ngeneral_init:\n  call void @__rg_sha256_init(ptr %state)\n  %u1 = call i64 @__rg_sha256_feed(ptr %state, ptr %buf, i64 0, ptr %data1, i64 %len1)\n  %u2 = call i64 @__rg_sha256_feed(ptr %state, ptr %buf, i64 %u1, ptr %data2, i64 %len2)\n  br label %finalize\nfinalize:\n  %used_fin = phi i64 [ %u_from_cache, %after_block1 ], [ %u2, %general_init ]\n  %p_pad = getelementptr inbounds i8, ptr %buf, i64 %used_fin\n  store i8 -128, ptr %p_pad, align 1\n  %u_pad = add i64 %used_fin, 1\n  %gt_56 = icmp sgt i64 %u_pad, 56\n  br i1 %gt_56, label %pad_two_blocks, label %pad_one_block\npad_two_blocks:\n  %rem_64 = sub i64 64, %u_pad\n  %p_z1 = getelementptr inbounds i8, ptr %buf, i64 %u_pad\n  call void @__rg_memset(ptr %p_z1, i8 0, i64 %rem_64)\n  call void @__rg_sha256_transform(ptr %state, ptr %buf)\n  br label %pad_one_block\npad_one_block:\n  %u_cur = phi i64 [ 0, %pad_two_blocks ], [ %u_pad, %finalize ]\n  %rem_56 = sub i64 56, %u_cur\n  %p_z2 = getelementptr inbounds i8, ptr %buf, i64 %u_cur\n  call void @__rg_memset(ptr %p_z2, i8 0, i64 %rem_56)\n  %tot_bytes = add i64 %len1, %len2\n  %tot_bits = shl i64 %tot_bytes, 3\n  %be_bits = call i64 @llvm.bswap.i64(i64 %tot_bits)\n  %p_len = getelementptr inbounds i8, ptr %buf, i64 56\n  store i64 %be_bits, ptr %p_len, align 8\n  call void @__rg_sha256_transform(ptr %state, ptr %buf)\n  br label %write_out_loop\nwrite_out_loop:\n  %wi = phi i64 [ 0, %pad_one_block ], [ %wi_next, %write_out_body ]\n  %wc = icmp slt i64 %wi, 8\n  br i1 %wc, label %write_out_body, label %done_all\nwrite_out_body:\n  %sp_w = getelementptr inbounds i32, ptr %state, i64 %wi\n  %sv_w = load i32, ptr %sp_w, align 4\n  %be_sv = call i32 @llvm.bswap.i32(i32 %sv_w)\n  %op_w = getelementptr inbounds i32, ptr %out32, i64 %wi\n  store i32 %be_sv, ptr %op_w, align 1\n  %wi_next = add i64 %wi, 1\n  br label %write_out_loop\ndone_all:\n  ret void\n}}\n"
        join str tree [k, t1, t2, c1, c2, c3, c4]

fn :: llvm tensor and builtin helpers => String
      llvm tensor and builtin helpers =
        h1 = "define i64 @__rg_box_i64(i64 %v) nounwind {\nentry:\n  %shl = shl i64 %v, 1\n  %shr = ashr i64 %shl, 1\n  %fits = icmp eq i64 %shr, %v\n  br i1 %fits, label %tag_imm, label %box_heap\ntag_imm:\n  %tagged = or i64 %shl, 1\n  ret i64 %tagged\nbox_heap:\n  %buf = alloca [3 x i64], align 8\n  store i64 0, ptr %buf, align 8\n  %p1 = getelementptr inbounds [3 x i64], ptr %buf, i64 0, i64 1\n  store i64 %v, ptr %p1, align 8\n  %p2 = getelementptr inbounds [3 x i64], ptr %buf, i64 0, i64 2\n  store i64 0, ptr %p2, align 8\n  %boxed = call i64 @__rg_rt_box_rval(ptr %buf)\n  ret i64 %boxed\n}\ndefine i64 @__rg_match_heap_tag(i64 %val, i32 %want_tag) nounwind {\nentry:\n  %non_null = icmp ne i64 %val, 0\n  %low3 = and i64 %val, 7\n  %is_ptr = icmp eq i64 %low3, 0\n  %ok = and i1 %non_null, %is_ptr\n  br i1 %ok, label %chk, label %no\nchk:\n  %p = inttoptr i64 %val to ptr\n  %t = load i32, ptr %p, align 4\n  %m = icmp eq i32 %t, %want_tag\n  %r = zext i1 %m to i64\n  ret i64 %r\nno:\n  ret i64 0\n}\ndefine i64 @__rg_adt_field_neg(i64 %val, i64 %idx) nounwind {\nentry:\n  %p = inttoptr i64 %val to ptr\n  %is_m1 = icmp eq i64 %idx, -1\n  br i1 %is_m1, label %str_len, label %chk_m2\nstr_len:\n  %hp1 = getelementptr inbounds i8, ptr %p, i64 8\n  %hdr1 = load ptr, ptr %hp1, align 8\n  %lp1 = getelementptr inbounds i8, ptr %hdr1, i64 16\n  %l1 = load i64, ptr %lp1, align 8\n  %sh1 = shl i64 %l1, 1\n  %r1 = or i64 %sh1, 1\n  ret i64 %r1\nchk_m2:\n  %is_m2 = icmp eq i64 %idx, -2\n  br i1 %is_m2, label %list_len, label %tensor_dim\nlist_len:\n  %hp2 = getelementptr inbounds i8, ptr %p, i64 16\n  %hdr2 = load ptr, ptr %hp2, align 8\n  %lp2 = getelementptr inbounds i8, ptr %hdr2, i64 16\n  %l2 = load i64, ptr %lp2, align 8\n  %sh2 = shl i64 %l2, 1\n  %r2 = or i64 %sh2, 1\n  ret i64 %r2\ntensor_dim:\n  %dim_i = sub i64 -10, %idx\n  %hp3 = getelementptr inbounds i8, ptr %p, i64 8\n  %shdr = load ptr, ptr %hp3, align 8\n  %sdp = getelementptr inbounds i8, ptr %shdr, i64 8\n  %sdata = load ptr, ptr %sdp, align 8\n  %dp = getelementptr inbounds i64, ptr %sdata, i64 %dim_i\n  %dval = load i64, ptr %dp, align 8\n  %sh3 = shl i64 %dval, 1\n  %r3 = or i64 %sh3, 1\n  ret i64 %r3\n}\ndefine i64 @__rg_not_op(i64 %val) nounwind {\nentry:\n  %low1 = and i64 %val, 1\n  %is_int = icmp ne i64 %low1, 0\n  br i1 %is_int, label %int_not, label %bool_not\nint_not:\n  %r_int = xor i64 %val, -2\n  ret i64 %r_int\nbool_not:\n  %r_bool = call i64 @__rg_rt_bool_inv(i64 %val)\n  ret i64 %r_bool\n}\n"
        h2 = "define i64 @__rg_tensor_index_1d(i64 %base_val, ptr %idx_ptr) nounwind {\nentry:\n  %non_null = icmp ne i64 %base_val, 0\n  %low3 = and i64 %base_val, 7\n  %is_ptr = icmp eq i64 %low3, 0\n  %ok_ptr = and i1 %non_null, %is_ptr\n  br i1 %ok_ptr, label %chk_tag, label %slow\nchk_tag:\n  %bp = inttoptr i64 %base_val to ptr\n  %tag = load i32, ptr %bp, align 4\n  %is_tensor = icmp eq i32 %tag, 5\n  br i1 %is_tensor, label %chk_rank, label %slow\nchk_rank:\n  %shp_p = getelementptr inbounds i8, ptr %bp, i64 8\n  %shdr = load ptr, ptr %shp_p, align 8\n  %rk_p = getelementptr inbounds i8, ptr %shdr, i64 16\n  %rk = load i64, ptr %rk_p, align 8\n  %is_1d = icmp eq i64 %rk, 1\n  br i1 %is_1d, label %chk_idx, label %slow\nchk_idx:\n  %iv = load i64, ptr %idx_ptr, align 8\n  %ibit = and i64 %iv, 1\n  %is_i = icmp ne i64 %ibit, 0\n  br i1 %is_i, label %chk_bounds, label %slow\nchk_bounds:\n  %idx = ashr i64 %iv, 1\n  %ge0 = icmp sge i64 %idx, 0\n  br i1 %ge0, label %chk_len, label %slow\nchk_len:\n  %dhp_p = getelementptr inbounds i8, ptr %bp, i64 16\n  %dhdr = load ptr, ptr %dhp_p, align 8\n  %len_p = getelementptr inbounds i8, ptr %dhdr, i64 16\n  %len = load i64, ptr %len_p, align 8\n  %lt_len = icmp slt i64 %idx, %len\n  br i1 %lt_len, label %fast_load, label %slow\nfast_load:\n  %dp_p = getelementptr inbounds i8, ptr %dhdr, i64 8\n  %dptr = load ptr, ptr %dp_p, align 8\n  %ep = getelementptr inbounds i64, ptr %dptr, i64 %idx\n  %raw = load i64, ptr %ep, align 8\n  store i64 0, ptr %idx_ptr, align 8\n  %boxed = call i64 @__rg_box_i64(i64 %raw)\n  ret i64 %boxed\nslow:\n  %tmp_base = alloca i64, align 8\n  %cloned = call i64 @__rg_rt_clone_slot(i64 %base_val)\n  store i64 %cloned, ptr %tmp_base, align 8\n  %res = call i64 @__rg_rt_index(ptr %tmp_base, ptr %idx_ptr, i64 1)\n  ret i64 %res\n}\n"
        h3 = "define i64 @__rg_tensor_index_2d(i64 %base_val, ptr %idx_ptr) nounwind {\nentry:\n  %non_null = icmp ne i64 %base_val, 0\n  %low3 = and i64 %base_val, 7\n  %is_ptr = icmp eq i64 %low3, 0\n  %ok_ptr = and i1 %non_null, %is_ptr\n  br i1 %ok_ptr, label %chk_tag, label %slow\nchk_tag:\n  %bp = inttoptr i64 %base_val to ptr\n  %tag = load i32, ptr %bp, align 4\n  %is_tensor = icmp eq i32 %tag, 5\n  br i1 %is_tensor, label %chk_rank, label %slow\nchk_rank:\n  %shp_p = getelementptr inbounds i8, ptr %bp, i64 8\n  %shdr = load ptr, ptr %shp_p, align 8\n  %rk_p = getelementptr inbounds i8, ptr %shdr, i64 16\n  %rk = load i64, ptr %rk_p, align 8\n  %is_2d = icmp eq i64 %rk, 2\n  br i1 %is_2d, label %chk_idx, label %slow\nchk_idx:\n  %iv0 = load i64, ptr %idx_ptr, align 8\n  %idx1_ptr = getelementptr inbounds i64, ptr %idx_ptr, i64 1\n  %iv1 = load i64, ptr %idx1_ptr, align 8\n  %both = and i64 %iv0, %iv1\n  %ibit = and i64 %both, 1\n  %is_i = icmp ne i64 %ibit, 0\n  br i1 %is_i, label %chk_bounds, label %slow\nchk_bounds:\n  %i0 = ashr i64 %iv0, 1\n  %i1 = ashr i64 %iv1, 1\n  %ge0_0 = icmp sge i64 %i0, 0\n  %ge0_1 = icmp sge i64 %i1, 0\n  %ge0 = and i1 %ge0_0, %ge0_1\n  br i1 %ge0, label %chk_dims, label %slow\nchk_dims:\n  %sdp_p = getelementptr inbounds i8, ptr %shdr, i64 8\n  %sptr = load ptr, ptr %sdp_p, align 8\n  %d0 = load i64, ptr %sptr, align 8\n  %d1_p = getelementptr inbounds i64, ptr %sptr, i64 1\n  %d1 = load i64, ptr %d1_p, align 8\n  %lt0 = icmp slt i64 %i0, %d0\n  %lt1 = icmp slt i64 %i1, %d1\n  %lt_both = and i1 %lt0, %lt1\n  br i1 %lt_both, label %chk_len, label %slow\nchk_len:\n  %row_off = mul i64 %i0, %d1\n  %flat = add i64 %row_off, %i1\n  %dhp_p = getelementptr inbounds i8, ptr %bp, i64 16\n  %dhdr = load ptr, ptr %dhp_p, align 8\n  %len_p = getelementptr inbounds i8, ptr %dhdr, i64 16\n  %len = load i64, ptr %len_p, align 8\n  %lt_len = icmp slt i64 %flat, %len\n  br i1 %lt_len, label %fast_load, label %slow\nfast_load:\n  %dp_p = getelementptr inbounds i8, ptr %dhdr, i64 8\n  %dptr = load ptr, ptr %dp_p, align 8\n  %ep = getelementptr inbounds i64, ptr %dptr, i64 %flat\n  %raw = load i64, ptr %ep, align 8\n  store i64 0, ptr %idx_ptr, align 8\n  store i64 0, ptr %idx1_ptr, align 8\n  %boxed = call i64 @__rg_box_i64(i64 %raw)\n  ret i64 %boxed\nslow:\n  %tmp_base = alloca i64, align 8\n  %cloned = call i64 @__rg_rt_clone_slot(i64 %base_val)\n  store i64 %cloned, ptr %tmp_base, align 8\n  %res = call i64 @__rg_rt_index(ptr %tmp_base, ptr %idx_ptr, i64 2)\n  ret i64 %res\n}\n"
        h4 = "define i64 @__rg_tensor_index_set_1d(ptr %base_ptr, ptr %idx_ptr, i64 %val) nounwind {\nentry:\n  %vbit = and i64 %val, 1\n  %v_is_int = icmp ne i64 %vbit, 0\n  br i1 %v_is_int, label %val_int, label %val_chk_heap\nval_int:\n  %raw_int = ashr i64 %val, 1\n  br label %chk_base\nval_chk_heap:\n  %v_nn = icmp ne i64 %val, 0\n  %v_l3 = and i64 %val, 7\n  %v_ptr_ok = icmp eq i64 %v_l3, 0\n  %v_ok = and i1 %v_nn, %v_ptr_ok\n  br i1 %v_ok, label %val_chk_tag0, label %slow\nval_chk_tag0:\n  %vp = inttoptr i64 %val to ptr\n  %vtag = load i32, ptr %vp, align 4\n  %v_is_t0 = icmp eq i32 %vtag, 0\n  br i1 %v_is_t0, label %val_heap, label %slow\nval_heap:\n  %vpay_p = getelementptr inbounds i8, ptr %vp, i64 8\n  %raw_heap = load i64, ptr %vpay_p, align 8\n  br label %chk_base\nchk_base:\n  %raw_val = phi i64 [ %raw_int, %val_int ], [ %raw_heap, %val_heap ]\n  %drop_val = phi i64 [ 0, %val_int ], [ %val, %val_heap ]\n  %base_val = load i64, ptr %base_ptr, align 8\n  %b_nn = icmp ne i64 %base_val, 0\n  %b_l3 = and i64 %base_val, 7\n  %b_ptr_ok = icmp eq i64 %b_l3, 0\n  %b_ok = and i1 %b_nn, %b_ptr_ok\n  br i1 %b_ok, label %chk_btag, label %slow\nchk_btag:\n  %bp = inttoptr i64 %base_val to ptr\n  %btag = load i32, ptr %bp, align 4\n  %is_tensor = icmp eq i32 %btag, 5\n  br i1 %is_tensor, label %chk_rank, label %slow\nchk_rank:\n  %shp_p = getelementptr inbounds i8, ptr %bp, i64 8\n  %shdr = load ptr, ptr %shp_p, align 8\n  %rk_p = getelementptr inbounds i8, ptr %shdr, i64 16\n  %rk = load i64, ptr %rk_p, align 8\n  %is_1d = icmp eq i64 %rk, 1\n  br i1 %is_1d, label %chk_idx, label %slow\nchk_idx:\n  %iv = load i64, ptr %idx_ptr, align 8\n  %ibit = and i64 %iv, 1\n  %is_i = icmp ne i64 %ibit, 0\n  br i1 %is_i, label %chk_bounds, label %slow\nchk_bounds:\n  %idx = ashr i64 %iv, 1\n  %ge0 = icmp sge i64 %idx, 0\n  br i1 %ge0, label %chk_len, label %slow\nchk_len:\n  %dhp_p = getelementptr inbounds i8, ptr %bp, i64 16\n  %dhdr = load ptr, ptr %dhp_p, align 8\n  %len_p = getelementptr inbounds i8, ptr %dhdr, i64 16\n  %len = load i64, ptr %len_p, align 8\n  %lt_len = icmp slt i64 %idx, %len\n  br i1 %lt_len, label %fast_store, label %slow\nfast_store:\n  %dp_p = getelementptr inbounds i8, ptr %dhdr, i64 8\n  %dptr = load ptr, ptr %dp_p, align 8\n  %ep = getelementptr inbounds i64, ptr %dptr, i64 %idx\n  store i64 %raw_val, ptr %ep, align 8\n  store i64 0, ptr %idx_ptr, align 8\n  %need_drop = icmp ne i64 %drop_val, 0\n  br i1 %need_drop, label %do_drop, label %finish\ndo_drop:\n  %d_ign = call i64 @__rg_rt_drop_val(i64 %drop_val)\n  br label %finish\nfinish:\n  store i64 0, ptr %base_ptr, align 8\n  ret i64 %base_val\nslow:\n  %res = call i64 @__rg_rt_index_set(ptr %base_ptr, ptr %idx_ptr, i64 1, i64 %val)\n  ret i64 %res\n}\n"
        h5 = "define i64 @__rg_tensor_index_set_2d(ptr %base_ptr, ptr %idx_ptr, i64 %val) nounwind {\nentry:\n  %vbit = and i64 %val, 1\n  %v_is_int = icmp ne i64 %vbit, 0\n  br i1 %v_is_int, label %val_int, label %val_chk_heap\nval_int:\n  %raw_int = ashr i64 %val, 1\n  br label %chk_base\nval_chk_heap:\n  %v_nn = icmp ne i64 %val, 0\n  %v_l3 = and i64 %val, 7\n  %v_ptr_ok = icmp eq i64 %v_l3, 0\n  %v_ok = and i1 %v_nn, %v_ptr_ok\n  br i1 %v_ok, label %val_chk_tag0, label %slow\nval_chk_tag0:\n  %vp = inttoptr i64 %val to ptr\n  %vtag = load i32, ptr %vp, align 4\n  %v_is_t0 = icmp eq i32 %vtag, 0\n  br i1 %v_is_t0, label %val_heap, label %slow\nval_heap:\n  %vpay_p = getelementptr inbounds i8, ptr %vp, i64 8\n  %raw_heap = load i64, ptr %vpay_p, align 8\n  br label %chk_base\nchk_base:\n  %raw_val = phi i64 [ %raw_int, %val_int ], [ %raw_heap, %val_heap ]\n  %drop_val = phi i64 [ 0, %val_int ], [ %val, %val_heap ]\n  %base_val = load i64, ptr %base_ptr, align 8\n  %b_nn = icmp ne i64 %base_val, 0\n  %b_l3 = and i64 %base_val, 7\n  %b_ptr_ok = icmp eq i64 %b_l3, 0\n  %b_ok = and i1 %b_nn, %b_ptr_ok\n  br i1 %b_ok, label %chk_btag, label %slow\nchk_btag:\n  %bp = inttoptr i64 %base_val to ptr\n  %btag = load i32, ptr %bp, align 4\n  %is_tensor = icmp eq i32 %btag, 5\n  br i1 %is_tensor, label %chk_rank, label %slow\nchk_rank:\n  %shp_p = getelementptr inbounds i8, ptr %bp, i64 8\n  %shdr = load ptr, ptr %shp_p, align 8\n  %rk_p = getelementptr inbounds i8, ptr %shdr, i64 16\n  %rk = load i64, ptr %rk_p, align 8\n  %is_2d = icmp eq i64 %rk, 2\n  br i1 %is_2d, label %chk_idx, label %slow\nchk_idx:\n  %iv0 = load i64, ptr %idx_ptr, align 8\n  %idx1_ptr = getelementptr inbounds i64, ptr %idx_ptr, i64 1\n  %iv1 = load i64, ptr %idx1_ptr, align 8\n  %both = and i64 %iv0, %iv1\n  %ibit = and i64 %both, 1\n  %is_i = icmp ne i64 %ibit, 0\n  br i1 %is_i, label %chk_bounds, label %slow\nchk_bounds:\n  %i0 = ashr i64 %iv0, 1\n  %i1 = ashr i64 %iv1, 1\n  %ge0_0 = icmp sge i64 %i0, 0\n  %ge0_1 = icmp sge i64 %i1, 0\n  %ge0 = and i1 %ge0_0, %ge0_1\n  br i1 %ge0, label %chk_dims, label %slow\nchk_dims:\n  %sdp_p = getelementptr inbounds i8, ptr %shdr, i64 8\n  %sptr = load ptr, ptr %sdp_p, align 8\n  %d0 = load i64, ptr %sptr, align 8\n  %d1_p = getelementptr inbounds i64, ptr %sptr, i64 1\n  %d1 = load i64, ptr %d1_p, align 8\n  %lt0 = icmp slt i64 %i0, %d0\n  %lt1 = icmp slt i64 %i1, %d1\n  %lt_both = and i1 %lt0, %lt1\n  br i1 %lt_both, label %chk_len, label %slow\nchk_len:\n  %row_off = mul i64 %i0, %d1\n  %flat = add i64 %row_off, %i1\n  %dhp_p = getelementptr inbounds i8, ptr %bp, i64 16\n  %dhdr = load ptr, ptr %dhp_p, align 8\n  %len_p = getelementptr inbounds i8, ptr %dhdr, i64 16\n  %len = load i64, ptr %len_p, align 8\n  %lt_len = icmp slt i64 %flat, %len\n  br i1 %lt_len, label %fast_store, label %slow\nfast_store:\n  %dp_p = getelementptr inbounds i8, ptr %dhdr, i64 8\n  %dptr = load ptr, ptr %dp_p, align 8\n  %ep = getelementptr inbounds i64, ptr %dptr, i64 %flat\n  store i64 %raw_val, ptr %ep, align 8\n  store i64 0, ptr %idx_ptr, align 8\n  store i64 0, ptr %idx1_ptr, align 8\n  %need_drop = icmp ne i64 %drop_val, 0\n  br i1 %need_drop, label %do_drop, label %finish\ndo_drop:\n  %d_ign = call i64 @__rg_rt_drop_val(i64 %drop_val)\n  br label %finish\nfinish:\n  store i64 0, ptr %base_ptr, align 8\n  ret i64 %base_val\nslow:\n  %res = call i64 @__rg_rt_index_set(ptr %base_ptr, ptr %idx_ptr, i64 2, i64 %val)\n  ret i64 %res\n}\n"
        h6 = "define i64 @__rg_builtin_tensor_fill(ptr %slots_ptr, i64 %count) nounwind {\nentry:\n  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0\n  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1\n  %fill_val = call i64 @__rg_rt_pop_i64(ptr %s0)\n  %d0 = call i64 @__rg_rt_pop_i64(ptr %s1)\n  %is_2d = icmp sge i64 %count, 3\n  br i1 %is_2d, label %read_d1, label %done_dims\nread_d1:\n  %s2 = getelementptr inbounds i64, ptr %slots_ptr, i64 2\n  %d1_v = call i64 @__rg_rt_pop_i64(ptr %s2)\n  br label %done_dims\ndone_dims:\n  %d1 = phi i64 [ %d1_v, %read_d1 ], [ 1, %entry ]\n  %rank = phi i64 [ 2, %read_d1 ], [ 1, %entry ]\n  %s_bytes = shl i64 %rank, 3\n  %s_buf = call ptr @__rg_rt_alloc_buf(i64 %s_bytes)\n  store i64 %d0, ptr %s_buf, align 8\n  br i1 %is_2d, label %store_d1, label %box_shape\nstore_d1:\n  %s_buf1 = getelementptr inbounds i64, ptr %s_buf, i64 1\n  store i64 %d1, ptr %s_buf1, align 8\n  br label %box_shape\nbox_shape:\n  %vec_tmp = alloca [3 x i64], align 8\n  %vp0 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 0\n  %vp1 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 1\n  %vp2 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 2\n  store i64 %rank, ptr %vp0, align 8\n  %s_buf_int = ptrtoint ptr %s_buf to i64\n  store i64 %s_buf_int, ptr %vp1, align 8\n  store i64 %rank, ptr %vp2, align 8\n  %shdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)\n  %tot = mul i64 %d0, %d1\n  %d_bytes = shl i64 %tot, 3\n  %d_buf = call ptr @__rg_rt_alloc_buf(i64 %d_bytes)\n  br label %fill_loop\nfill_loop:\n  %fi = phi i64 [ 0, %box_shape ], [ %fi_next, %fill_body ]\n  %fc = icmp slt i64 %fi, %tot\n  br i1 %fc, label %fill_body, label %box_data\nfill_body:\n  %fp = getelementptr inbounds i64, ptr %d_buf, i64 %fi\n  store i64 %fill_val, ptr %fp, align 8\n  %fi_next = add i64 %fi, 1\n  br label %fill_loop\nbox_data:\n  store i64 %tot, ptr %vp0, align 8\n  %d_buf_int = ptrtoint ptr %d_buf to i64\n  store i64 %d_buf_int, ptr %vp1, align 8\n  store i64 %tot, ptr %vp2, align 8\n  %dhdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)\n  store i64 5, ptr %vp0, align 8\n  %shdr_int = ptrtoint ptr %shdr to i64\n  %dhdr_int = ptrtoint ptr %dhdr to i64\n  store i64 %shdr_int, ptr %vp1, align 8\n  store i64 %dhdr_int, ptr %vp2, align 8\n  %res = call i64 @__rg_rt_box_rval(ptr %vec_tmp)\n  ret i64 %res\n}\n"
        h7 = "define i64 @__rg_builtin_tensor_bitop(ptr %slots_ptr) nounwind {{\nentry:\n  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0\n  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1\n  %s2 = getelementptr inbounds i64, ptr %slots_ptr, i64 2\n  %va = load i64, ptr %s0, align 8\n  %vb = load i64, ptr %s1, align 8\n  %vop = load i64, ptr %s2, align 8\n  store i64 0, ptr %s2, align 8\n  %op_id = ashr i64 %vop, 1\n  %pa = inttoptr i64 %va to ptr\n  %pb = inttoptr i64 %vb to ptr\n  %ashp_p = getelementptr inbounds i8, ptr %pa, i64 8\n  %ashdr = load ptr, ptr %ashp_p, align 8\n  %asdp_p = getelementptr inbounds i8, ptr %ashdr, i64 8\n  %asdata = load ptr, ptr %asdp_p, align 8\n  %ark_p = getelementptr inbounds i8, ptr %ashdr, i64 16\n  %rank = load i64, ptr %ark_p, align 8\n  %s_bytes = shl i64 %rank, 3\n  %s_buf = call ptr @__rg_rt_alloc_buf(i64 %s_bytes)\n  call void @__rg_memcpy(ptr %s_buf, ptr %asdata, i64 %s_bytes)\n  %vec_tmp = alloca [3 x i64], align 8\n  %vp0 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 0\n  %vp1 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 1\n  %vp2 = getelementptr inbounds [3 x i64], ptr %vec_tmp, i64 0, i64 2\n  store i64 %rank, ptr %vp0, align 8\n  %s_buf_int = ptrtoint ptr %s_buf to i64\n  store i64 %s_buf_int, ptr %vp1, align 8\n  store i64 %rank, ptr %vp2, align 8\n  %shdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)\n  %adhp_p = getelementptr inbounds i8, ptr %pa, i64 16\n  %adhdr = load ptr, ptr %adhp_p, align 8\n  %addp_p = getelementptr inbounds i8, ptr %adhdr, i64 8\n  %adata = load ptr, ptr %addp_p, align 8\n  %alen_p = getelementptr inbounds i8, ptr %adhdr, i64 16\n  %tot = load i64, ptr %alen_p, align 8\n  %bdhp_p = getelementptr inbounds i8, ptr %pb, i64 16\n  %bdhdr = load ptr, ptr %bdhp_p, align 8\n  %bddp_p = getelementptr inbounds i8, ptr %bdhdr, i64 8\n  %bdata = load ptr, ptr %bddp_p, align 8\n  %d_bytes = shl i64 %tot, 3\n  %d_buf = call ptr @__rg_rt_alloc_buf(i64 %d_bytes)\n  br label %loop\nloop:\n  %i = phi i64 [ 0, %entry ], [ %i_next, %body_end ]\n  %c = icmp slt i64 %i, %tot\n  br i1 %c, label %body, label %done\nbody:\n  %ap = getelementptr inbounds i64, ptr %adata, i64 %i\n  %bp_e = getelementptr inbounds i64, ptr %bdata, i64 %i\n  %x = load i64, ptr %ap, align 8\n  %y = load i64, ptr %bp_e, align 8\n  %is_and = icmp eq i64 %op_id, 11\n  br i1 %is_and, label %do_and, label %chk_or\ndo_and:\n  %r_and = and i64 %x, %y\n  br label %body_end\nchk_or:\n  %is_or = icmp eq i64 %op_id, 12\n  br i1 %is_or, label %do_or, label %do_xor\ndo_or:\n  %r_or = or i64 %x, %y\n  br label %body_end\ndo_xor:\n  %r_xor = xor i64 %x, %y\n  br label %body_end\nbody_end:\n  %r_val = phi i64 [ %r_and, %do_and ], [ %r_or, %do_or ], [ %r_xor, %do_xor ]\n  %dp = getelementptr inbounds i64, ptr %d_buf, i64 %i\n  store i64 %r_val, ptr %dp, align 8\n  %i_next = add i64 %i, 1\n  br label %loop\ndone:\n  store i64 %tot, ptr %vp0, align 8\n  %d_buf_int = ptrtoint ptr %d_buf to i64\n  store i64 %d_buf_int, ptr %vp1, align 8\n  store i64 %tot, ptr %vp2, align 8\n  %dhdr = call ptr @__rg_rt_box_rc_vec(ptr %vec_tmp)\n  store i64 5, ptr %vp0, align 8\n  %shdr_int = ptrtoint ptr %shdr to i64\n  %dhdr_int = ptrtoint ptr %dhdr to i64\n  store i64 %shdr_int, ptr %vp1, align 8\n  store i64 %dhdr_int, ptr %vp2, align 8\n  %res = call i64 @__rg_rt_box_rval(ptr %vec_tmp)\n  call void @__rg_rt_drop_slot(ptr %s0)\n  call void @__rg_rt_drop_slot(ptr %s1)\n  ret i64 %res\n}}\n"
        h8 = "define void @__rg_extract_str_span(i64 %val, ptr %out_ptr, ptr %out_len) nounwind {\nentry:\n  store ptr null, ptr %out_ptr, align 8\n  store i64 0, ptr %out_len, align 8\n  %nn = icmp ne i64 %val, 0\n  %l3 = and i64 %val, 7\n  %is_p = icmp eq i64 %l3, 0\n  %ok = and i1 %nn, %is_p\n  br i1 %ok, label %chk_t, label %done\nchk_t:\n  %p = inttoptr i64 %val to ptr\n  %t = load i32, ptr %p, align 4\n  %is_s = icmp eq i32 %t, 1\n  br i1 %is_s, label %load_s, label %done\nload_s:\n  %hp = getelementptr inbounds i8, ptr %p, i64 8\n  %hdr = load ptr, ptr %hp, align 8\n  %dp = getelementptr inbounds i8, ptr %hdr, i64 8\n  %dptr = load ptr, ptr %dp, align 8\n  %lp = getelementptr inbounds i8, ptr %hdr, i64 16\n  %dlen = load i64, ptr %lp, align 8\n  store ptr %dptr, ptr %out_ptr, align 8\n  store i64 %dlen, ptr %out_len, align 8\n  br label %done\ndone:\n  ret void\n}\ndefine i64 @__rg_builtin_sha256_raw(ptr %slot_ptr) nounwind {\nentry:\n  %sp_ptr = alloca ptr, align 8\n  %sp_len = alloca i64, align 8\n  %digest = alloca [32 x i8], align 16\n  %val = load i64, ptr %slot_ptr, align 8\n  call void @__rg_extract_str_span(i64 %val, ptr %sp_ptr, ptr %sp_len)\n  %dptr = load ptr, ptr %sp_ptr, align 8\n  %dlen = load i64, ptr %sp_len, align 8\n  call void @__rg_sha256_compute2(ptr %dptr, i64 %dlen, ptr null, i64 0, ptr %digest)\n  %res = call i64 @__rg_rt_load_str_lit(ptr %digest, i64 32)\n  call void @__rg_rt_drop_slot(ptr %slot_ptr)\n  ret i64 %res\n}\ndefine i64 @__rg_builtin_sha256_concat(ptr %slots_ptr) nounwind {\nentry:\n  %p1 = alloca ptr, align 8\n  %l1 = alloca i64, align 8\n  %p2 = alloca ptr, align 8\n  %l2 = alloca i64, align 8\n  %digest = alloca [32 x i8], align 16\n  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0\n  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1\n  %v0 = load i64, ptr %s0, align 8\n  %v1 = load i64, ptr %s1, align 8\n  call void @__rg_extract_str_span(i64 %v0, ptr %p1, ptr %l1)\n  call void @__rg_extract_str_span(i64 %v1, ptr %p2, ptr %l2)\n  %dp1 = load ptr, ptr %p1, align 8\n  %dl1 = load i64, ptr %l1, align 8\n  %dp2 = load ptr, ptr %p2, align 8\n  %dl2 = load i64, ptr %l2, align 8\n  call void @__rg_sha256_compute2(ptr %dp1, i64 %dl1, ptr %dp2, i64 %dl2, ptr %digest)\n  %res = call i64 @__rg_rt_load_str_lit(ptr %digest, i64 32)\n  call void @__rg_rt_drop_slot(ptr %s0)\n  call void @__rg_rt_drop_slot(ptr %s1)\n  ret i64 %res\n}\n"
        h9 = "define i64 @__rg_builtin_sys_pipe() nounwind {{\nentry:\n  %fds = alloca [2 x i32], align 8\n  %f0_p = getelementptr inbounds [2 x i32], ptr %fds, i64 0, i64 0\n  %f1_p = getelementptr inbounds [2 x i32], ptr %fds, i64 0, i64 1\n  store i32 -1, ptr %f0_p, align 4\n  store i32 -1, ptr %f1_p, align 4\n  %rc = call i64 asm sideeffect \"syscall\", \"={{rax}},{{rax}},{{rdi}},~{{rcx}},~{{r11}},~{{memory}}\"(i64 22, ptr %fds)\n  %fd0_32 = load i32, ptr %f0_p, align 4\n  %fd1_32 = load i32, ptr %f1_p, align 4\n  %fd0 = sext i32 %fd0_32 to i64\n  %fd1 = sext i32 %fd1_32 to i64\n  %t0_s = shl i64 %fd0, 1\n  %t0 = or i64 %t0_s, 1\n  %t1_s = shl i64 %fd1, 1\n  %t1 = or i64 %t1_s, 1\n  %tup = alloca [2 x i64], align 8\n  %tp0 = getelementptr inbounds [2 x i64], ptr %tup, i64 0, i64 0\n  %tp1 = getelementptr inbounds [2 x i64], ptr %tup, i64 0, i64 1\n  store i64 %t0, ptr %tp0, align 8\n  store i64 %t1, ptr %tp1, align 8\n  %res = call i64 @__rg_rt_make_tuple(ptr %tup, i64 2)\n  ret i64 %res\n}}\ndefine i64 @__rg_builtin_sys_waitpid(ptr %slots_ptr) nounwind {{\nentry:\n  %s0 = getelementptr inbounds i64, ptr %slots_ptr, i64 0\n  %s1 = getelementptr inbounds i64, ptr %slots_ptr, i64 1\n  %v_pid = load i64, ptr %s0, align 8\n  %v_opt = load i64, ptr %s1, align 8\n  store i64 0, ptr %s0, align 8\n  store i64 0, ptr %s1, align 8\n  %pid = ashr i64 %v_pid, 1\n  %opt = ashr i64 %v_opt, 1\n  %status = alloca i32, align 4\n  store i32 0, ptr %status, align 4\n  %rc = call i64 asm sideeffect \"syscall\", \"={{rax}},{{rax}},{{rdi}},{{rsi}},{{rdx}},{{r10}},~{{rcx}},~{{r11}},~{{memory}}\"(i64 61, i64 %pid, ptr %status, i64 %opt, i64 0)\n  %st = load i32, ptr %status, align 4\n  %sig = and i32 %st, 127\n  %ex_sh = lshr i32 %st, 8\n  %ex = and i32 %ex_sh, 255\n  %sig_code = add i32 %sig, 128\n  %was_sig = icmp ne i32 %sig, 0\n  %code32 = select i1 %was_sig, i32 %sig_code, i32 %ex\n  %code = zext i32 %code32 to i64\n  %neg = icmp slt i64 %rc, 0\n  %r_pid = select i1 %neg, i64 -1, i64 %rc\n  %tp_s = shl i64 %r_pid, 1\n  %tp_v = or i64 %tp_s, 1\n  %tc_s = shl i64 %code, 1\n  %tc_v = or i64 %tc_s, 1\n  %tup = alloca [2 x i64], align 8\n  %tp0 = getelementptr inbounds [2 x i64], ptr %tup, i64 0, i64 0\n  %tp1 = getelementptr inbounds [2 x i64], ptr %tup, i64 0, i64 1\n  store i64 %tp_v, ptr %tp0, align 8\n  store i64 %tc_v, ptr %tp1, align 8\n  %res = call i64 @__rg_rt_make_tuple(ptr %tup, i64 2)\n  ret i64 %res\n}}\n"
        join str tree [h1, h2, h3, h4, h5, h6, h7, h8, h9]

-- ── RNativeInstr => LLVM IR Instruction Emitter ─────────────

fn :: llvm bool tag Int => Int
      llvm bool tag 0   =  2
      llvm bool tag _   =  6

fn :: emit llvm instr RNativeInstr Int Int Int => String
      emit llvm instr (NLabel lid) _ _ _ =
        "  br label %L_{lid}\nL_{lid}:\n"
      emit llvm instr (NJump lid) step _ _ =
        "  br label %L_{lid}\ndead_{step}:\n"
      emit llvm instr (NJumpIfZero lid) step _ _ =
        "  %a_{step} = load i64, ptr %acc, align 8\n  %c_{step} = icmp eq i64 %a_{step}, 0\n  br i1 %c_{step}, label %L_{lid}, label %next_{step}\nnext_{step}:\n"
      emit llvm instr (NJumpIfNonZero lid) step _ _ =
        "  %a_{step} = load i64, ptr %acc, align 8\n  %c_{step} = icmp ne i64 %a_{step}, 0\n  br i1 %c_{step}, label %L_{lid}, label %next_{step}\nnext_{step}:\n"
      emit llvm instr (NLoadImmInt n) _ _ _ =
        tagged = (n * 2) + 1
        "  store i64 {tagged}, ptr %acc, align 8\n"
      emit llvm instr (NLoadImmRaw raw) _ _ _ =
        "  store i64 {raw}, ptr %acc, align 8\n"
      emit llvm instr (NLoadRealLit off len) step _ rodata_len =
        "  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 {off}\n  %r_{step} = call i64 @__rg_rt_load_real_lit(ptr %p_{step}, i64 {len})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NLoadStrLit off len) step _ rodata_len =
        "  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 {off}\n  %r_{step} = call i64 @__rg_rt_load_str_lit(ptr %p_{step}, i64 {len})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NLoadAdt0 -1 0) step _ rodata_len =
        "  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 22\n  %r_{step} = call i64 @__rg_rt_load_adt0(ptr %p_{step}, i64 6)\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NLoadAdt0 off len) step _ rodata_len =
        "  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 {off}\n  %r_{step} = call i64 @__rg_rt_load_adt0(ptr %p_{step}, i64 {len})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCloneSlot slot) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_rt_clone_slot(i64 %v_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMoveSlot slot) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  store i64 0, ptr %s_{step}, align 8\n  store i64 %v_{step}, ptr %acc, align 8\n"
      emit llvm instr (NStoreSlot slot) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_rt_store_slot(ptr %s_{step}, i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NRebindSlot slot) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_rt_rebind_slot(ptr %s_{step}, i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCmmDropSlot slot) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %r_{step} = call i64 @__rg_rt_cmm_drop_slot(ptr %s_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr NDropVal step _ _ =
        "  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_rt_drop_val(i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NClearLocals start_slot end_slot) _ _ _ =
        "  call void @__rg_rt_clear_locals(ptr %frame, i64 {start_slot}, i64 {end_slot})\n"
      emit llvm instr (NMatchInt slot n) step _ _ =
        tagged = (n * 2) + 1
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %c_{step} = icmp eq i64 %v_{step}, {tagged}\n  %r_{step} = zext i1 %c_{step} to i64\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchReal slot off len) step _ rodata_len =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 {off}\n  %r_{step} = call i64 @__rg_rt_match_real(i64 %v_{step}, ptr %p_{step}, i64 {len})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchStr slot off len) step _ rodata_len =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 {off}\n  %r_{step} = call i64 @__rg_rt_match_str(i64 %v_{step}, ptr %p_{step}, i64 {len})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchBool slot b_int) step _ _ =
        btag = llvm bool tag b_int
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %c_{step} = icmp eq i64 %v_{step}, {btag}\n  %r_{step} = zext i1 %c_{step} to i64\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchEmpty slot) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_rt_match_empty(i64 %v_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchNonEmpty slot) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_rt_match_nonempty(i64 %v_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchTuple slot arity) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_rt_match_tuple(i64 %v_{step}, i64 {arity})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchAdt slot _ _ -1) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = and i64 %v_{step}, 1\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchAdt slot _ _ -2) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %m_{step} = and i64 %v_{step}, -5\n  %c_{step} = icmp eq i64 %m_{step}, 2\n  %r_{step} = zext i1 %c_{step} to i64\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchAdt slot _ _ -3) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_match_heap_tag(i64 %v_{step}, i32 1)\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchAdt slot _ _ -4) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_match_heap_tag(i64 %v_{step}, i32 0)\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchAdt slot _ _ -5) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_match_heap_tag(i64 %v_{step}, i32 5)\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMatchAdt slot off len arity) step _ rodata_len =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 {off}\n  %r_{step} = call i64 @__rg_rt_match_adt(i64 %v_{step}, ptr %p_{step}, i64 {len}, i64 {arity})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NListHead slot) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_rt_list_head(i64 %v_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NListTail slot) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_rt_list_tail(i64 %v_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NTupleGet slot idx) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_rt_tuple_get(i64 %v_{step}, i64 {idx})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NAdtField slot idx) step _ _
        | idx < 0 =
          "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_adt_field_neg(i64 %v_{step}, i64 {idx})\n  store i64 %r_{step}, ptr %acc, align 8\n"
        | otherwise =
          "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {slot}\n  %v_{step} = load i64, ptr %s_{step}, align 8\n  %r_{step} = call i64 @__rg_rt_adt_field(i64 %v_{step}, i64 {idx})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NPackSeq arity) step _ _ =
        "  %r_{step} = call i64 @__rg_rt_pack_seq(ptr %frame, i64 {arity})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr NAsBool step _ _ =
        "  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_rt_as_bool(i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr NNot step _ _ =
        "  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_not_op(i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr NOut step _ _ =
        "  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_rt_out(i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NBinOp op_id lhs_slot) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {lhs_slot}\n  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_rt_bin_op(i64 {op_id}, ptr %s_{step}, i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NAdtSet rec_slot idx) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {rec_slot}\n  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_rt_adt_set(ptr %s_{step}, i64 {idx}, i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMakeList start_slot count) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_rt_make_list(ptr %s_{step}, i64 {count})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMakeTuple start_slot count) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_rt_make_tuple(ptr %s_{step}, i64 {count})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMakeTensor start_slot count) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_rt_make_tensor(ptr %s_{step}, i64 {count})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NMakeAdt off len start_slot count) step _ rodata_len =
        "  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 {off}\n  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_rt_make_adt(ptr %p_{step}, i64 {len}, ptr %s_{step}, i64 {count})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NEcho start_slot count) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_rt_echo(ptr %s_{step}, i64 {count})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NStrInterp start_slot count) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_rt_str_interp(ptr %s_{step}, i64 {count})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NIndex base_slot idx_start -1) step _ _ =
        "  %bs_{step} = getelementptr inbounds i64, ptr %frame, i64 {base_slot}\n  %bv_{step} = load i64, ptr %bs_{step}, align 8\n  %is_{step} = getelementptr inbounds i64, ptr %frame, i64 {idx_start}\n  %r_{step} = call i64 @__rg_tensor_index_1d(i64 %bv_{step}, ptr %is_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NIndex base_slot idx_start -2) step _ _ =
        "  %bs_{step} = getelementptr inbounds i64, ptr %frame, i64 {base_slot}\n  %bv_{step} = load i64, ptr %bs_{step}, align 8\n  %is_{step} = getelementptr inbounds i64, ptr %frame, i64 {idx_start}\n  %r_{step} = call i64 @__rg_tensor_index_2d(i64 %bv_{step}, ptr %is_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NIndex base_slot idx_start count) step _ _ =
        "  %bs_{step} = getelementptr inbounds i64, ptr %frame, i64 {base_slot}\n  %is_{step} = getelementptr inbounds i64, ptr %frame, i64 {idx_start}\n  %r_{step} = call i64 @__rg_rt_index(ptr %bs_{step}, ptr %is_{step}, i64 {count})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NIndexSet base_slot idx_start 1) step _ _ =
        "  %bs_{step} = getelementptr inbounds i64, ptr %frame, i64 {base_slot}\n  %is_{step} = getelementptr inbounds i64, ptr %frame, i64 {idx_start}\n  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_tensor_index_set_1d(ptr %bs_{step}, ptr %is_{step}, i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NIndexSet base_slot idx_start 2) step _ _ =
        "  %bs_{step} = getelementptr inbounds i64, ptr %frame, i64 {base_slot}\n  %is_{step} = getelementptr inbounds i64, ptr %frame, i64 {idx_start}\n  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_tensor_index_set_2d(ptr %bs_{step}, ptr %is_{step}, i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NIndexSet base_slot idx_start count) step _ _ =
        "  %bs_{step} = getelementptr inbounds i64, ptr %frame, i64 {base_slot}\n  %is_{step} = getelementptr inbounds i64, ptr %frame, i64 {idx_start}\n  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_rt_index_set(ptr %bs_{step}, ptr %is_{step}, i64 {count}, i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NSeqSelect mask_off mask_len) step _ rodata_len =
        "  %a_{step} = load i64, ptr %acc, align 8\n  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 {mask_off}\n  %r_{step} = call i64 @__rg_rt_seq_select(i64 %a_{step}, ptr %p_{step}, i64 {mask_len})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NEinsum start_slot count spec_off spec_len) step _ rodata_len =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 {spec_off}\n  %r_{step} = call i64 @__rg_rt_einsum(ptr %s_{step}, i64 {count}, ptr %p_{step}, i64 {spec_len})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NHadamard op_id lhs_slot subs_off subs_len) step _ rodata_len =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {lhs_slot}\n  %a_{step} = load i64, ptr %acc, align 8\n  %p_{step} = getelementptr inbounds [{rodata_len} x i8], ptr @__rg_rodata, i64 0, i64 {subs_off}\n  %r_{step} = call i64 @__rg_rt_hadamard(i64 {op_id}, ptr %s_{step}, i64 %a_{step}, ptr %p_{step}, i64 {subs_len})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr NEnterRegion step _ _ =
        "  %r_{step} = call i64 @__rg_rt_enter_region()\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NExitRegion quota) step _ _ =
        "  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_rt_exit_region(i64 {quota}, i64 %a_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCallFn fid start_slot _) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_fn_{fid}(ptr %s_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCallBuiltin 36 start_slot _) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_builtin_sha256_raw(ptr %s_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCallBuiltin 86 _ _) step _ _ =
        "  %r_{step} = call i64 @__rg_builtin_sys_pipe()\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCallBuiltin 87 start_slot _) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_builtin_sys_waitpid(ptr %s_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCallBuiltin 88 start_slot count) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_builtin_tensor_fill(ptr %s_{step}, i64 {count})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCallBuiltin 89 start_slot _) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_builtin_sha256_concat(ptr %s_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCallBuiltin 90 start_slot _) step _ _ =
        "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_builtin_tensor_bitop(ptr %s_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCallBuiltin b_id start_slot count) step _ _
        | b_id >= 70 =
          "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_rt_pal_dispatch(i64 {b_id}, ptr %s_{step}, i64 {count})\n  store i64 %r_{step}, ptr %acc, align 8\n"
        | otherwise =
          "  %s_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_rt_builtin(i64 {b_id}, ptr %s_{step}, i64 {count})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCallIndirect1 fn_slot arg_slot) step _ _ =
        "  %fs_{step} = getelementptr inbounds i64, ptr %frame, i64 {fn_slot}\n  %fv_{step} = load i64, ptr %fs_{step}, align 8\n  %as_{step} = getelementptr inbounds i64, ptr %frame, i64 {arg_slot}\n  %r_{step} = call i64 @__rg_rt_call_indirect1(i64 %fv_{step}, ptr %as_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NCallIndirect2 fn_slot start_slot) step _ _ =
        "  %fs_{step} = getelementptr inbounds i64, ptr %frame, i64 {fn_slot}\n  %fv_{step} = load i64, ptr %fs_{step}, align 8\n  %as_{step} = getelementptr inbounds i64, ptr %frame, i64 {start_slot}\n  %r_{step} = call i64 @__rg_rt_call_indirect2(i64 %fv_{step}, ptr %as_{step})\n  store i64 %r_{step}, ptr %acc, align 8\n"
      emit llvm instr (NTailCall start_slot arity) step num_slots _ =
        "  call void @__rg_rt_tco_copy(ptr %frame, i64 {start_slot}, i64 {arity}, i64 {num_slots})\n  br label %tco_entry\ndead_{step}:\n"
      emit llvm instr NReturn step num_slots _ =
        "  %a_{step} = load i64, ptr %acc, align 8\n  %r_{step} = call i64 @__rg_rt_epilogue(ptr %frame, i64 {num_slots}, i64 %a_{step})\n  ret i64 %r_{step}\ndead_{step}:\n"

fn :: emit llvm instr list [RNativeInstr] Int Int Int [String] => [String]
      emit llvm instr list [] _ _ _ acc = acc
      emit llvm instr list (ins:rest) step num_slots rodata_len acc =
        line = emit llvm instr ins step num_slots rodata_len
        emit llvm instr list rest (step + 1) num_slots rodata_len (acc :: [line])

fn :: llvm alloc slots Int => Int
      llvm alloc slots n
        | n <= 0 = 1
        | otherwise = n

fn :: emit llvm fn RNativeFn Int => String
      emit llvm fn (NativeFn fid _ arity num_slots instrs) rodata_len =
        aslots = llvm alloc slots num_slots
        hdr = "define i64 @__rg_fn_{fid}(ptr %args) nounwind {{\nentry:\n  %acc = alloca i64, align 8\n  %frame = alloca [{aslots} x i64], align 8\n  store i64 0, ptr %acc, align 8\n  call void @__rg_rt_init_frame(ptr %frame, ptr %args, i64 {arity}, i64 {num_slots})\n  br label %tco_entry\ntco_entry:\n"
        body_chunks = emit llvm instr list instrs 0 num_slots rodata_len []
        ftr = "  %a_end = load i64, ptr %acc, align 8\n  %r_end = call i64 @__rg_rt_epilogue(ptr %frame, i64 {num_slots}, i64 %a_end)\n  ret i64 %r_end\n}}\n\n"
        join str tree ([hdr] :: body_chunks :: [ftr])

fn :: emit llvm fn list [RNativeFn] Int [String] => [String]
      emit llvm fn list [] _ acc = acc
      emit llvm fn list (f:fs) rodata_len acc =
        fn_ir = emit llvm fn f rodata_len
        emit llvm fn list fs rodata_len (acc :: [fn_ir])

fn :: llvm target triple String => String
      llvm target triple "arm64"       =  "aarch64-unknown-linux-gnu"
      llvm target triple "arm64-linux" =  "aarch64-unknown-linux-gnu"
      llvm target triple "aarch64"     =  "aarch64-unknown-linux-gnu"
      llvm target triple _             =  "x86_64-unknown-linux-gnu"

fn :: emit llvm ir for target RNativeProg String => String
      emit llvm ir for target (NativeProg main_fid spawn_fid call2_fid binop_fid fns rodata_str) target_arch =
        triple = llvm target triple target_arch
        rlen = llvm rodata len rodata_str
        resc = llvm escape rodata rodata_str
        mod_hdr = "target datalayout = \"e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128\"\ntarget triple = \"{triple}\"\n\n@__rg_page0 = global {{ ptr, ptr, ptr, ptr, [3936 x i8] }} {{ ptr @__rg_fn_{main_fid}, ptr @__rg_fn_{spawn_fid}, ptr @__rg_fn_{call2_fid}, ptr @__rg_fn_{binop_fid}, [3936 x i8] zeroinitializer }}, section \".rg_page0\", align 8\n@__rg_rodata = private unnamed_addr constant [{rlen} x i8] c\"{resc}\", align 16\n\n"
        decls = llvm runtime declarations
        sha_ir = llvm sha256 helpers
        hlp_ir = llvm tensor and builtin helpers
        fn_chunks = emit llvm fn list fns rlen []
        join str tree ([mod_hdr, decls, "\n", sha_ir, "\n", hlp_ir, "\n"] :: fn_chunks)

fn :: emit llvm ir RNativeProg => String
      emit llvm ir nprog       =  emit llvm ir for target nprog "x86_64-linux"

-- ── Linker Script & llc + ld Execution Driver ───────────────

fn :: emit llvm linker script => String
      emit llvm linker script =
        s1 = "ENTRY(_start)\nPHDRS {{\n  all PT_LOAD FILEHDR PHDRS FLAGS(7);\n}}\nSECTIONS {{\n  . = 0x400080;\n  .rg_page0 : {{ KEEP(*(.rg_page0)) }} :all\n  . = 0x401000;\n  _start = .;\n  .rg_rt : {{ KEEP(*__rg_llvm_*.rt(.data)) }} :all\n  .text : ALIGN(16) {{ *(.text .text.*) }} :all\n  .rodata : ALIGN(16) {{ *(.rodata .rodata.*) }} :all\n  .data : ALIGN(16) {{ *(.data .data.*) }} :all\n  .bss : ALIGN(16) {{ *(.bss .bss.* COMMON) . = . + 131072; }} :all\n  /DISCARD/ : {{ *(.note*) *(.eh_frame*) *(.comment*) }}\n}}\n"
        s2 = "__rg_rt_init_frame = 4214136;\n__rg_rt_epilogue = 4214193;\n__rg_rt_tco_copy = 4214263;\n__rg_rt_clear_locals = 4214429;\n__rg_rt_clone_slot = 4214484;\n__rg_rt_drop_val = 4214519;\n__rg_rt_cmm_move = 4214549;\n__rg_rt_store_slot = 4214557;\n__rg_rt_rebind_slot = 4214596;\n__rg_rt_cmm_drop_slot = 4214624;\n__rg_rt_load_real_lit = 4214724;\n__rg_rt_load_str_lit = 4214782;\n__rg_rt_load_adt0 = 4214814;\n__rg_rt_make_adt = 4214846;\n__rg_rt_make_list = 4214925;\n__rg_rt_make_tuple = 4214963;\n__rg_rt_make_tensor = 4215291;\n__rg_rt_str_interp = 4215765;\n__rg_rt_pack_seq = 4215982;\n__rg_rt_as_bool = 4216188;\n"
        s3 = "__rg_rt_match_int = 4216208;\n__rg_rt_match_real = 4216225;\n__rg_rt_match_str = 4216329;\n__rg_rt_match_bool = 4216427;\n__rg_rt_match_empty = 4216452;\n__rg_rt_match_nonempty = 4216495;\n__rg_rt_list_head = 4216538;\n__rg_rt_list_tail = 4216614;\n__rg_rt_match_tuple = 4216754;\n__rg_rt_tuple_get = 4216825;\n__rg_rt_match_adt = 4216940;\n__rg_rt_adt_field = 4217065;\n__rg_rt_adt_set = 4217137;\n__rg_rt_bool_inv = 4217445;\n__rg_rt_out = 4217469;\n__rg_rt_echo = 4217589;\n__rg_rt_bin_op = 4217830;\n__rg_rt_index = 4222964;\n__rg_rt_index_set = 4223746;\n__rg_rt_seq_select = 4224237;\n"
        s4 = "__rg_rt_einsum = 4227142;\n__rg_rt_hadamard = 4227321;\n__rg_rt_enter_region = 4229186;\n__rg_rt_exit_region = 4229444;\n__rg_rt_call_indirect1 = 4230596;\n__rg_rt_call_indirect2 = 4230720;\n__rg_rt_builtin = 4241227;\n__rg_rt_pal_dispatch = 4286080;\n__rg_rt_drop_slot = 4200437;\n__rg_rt_alloc_buf = 4205566;\n__rg_rt_box_rc_vec = 4208821;\n__rg_rt_box_rval = 4209847;\n__rg_rt_pop_i64 = 4212364;\n__rg_rt_alloc_str = 4212489;\n"
        join str tree [s1, s2, s3, s4]

fn :: finish llvm link Int String String => Int
      finish llvm link 0 output_bin tmp_base =
        _ = shell exec ("rm -f \"" + tmp_base + "\".*")
        rc = sys chmod output_bin 493
        check chmod status rc
      finish llvm link _ _ tmp_base =
        _ = shell exec ("rm -f \"" + tmp_base + "\".*")
        _ = echo "[ridgunc llvm] Error: llc/ld native compilation failed"
        1

fn :: build llvm x8664 executable RNativeProg String     => Int
      build llvm x8664 executable nprog       output_bin =
        pid_s = int to str (sys getpid)
        tmp_base = "/tmp/__rg_llvm_" + pid_s
        ll_path = tmp_base + ".ll"
        obj_path = tmp_base + ".o"
        rt_path = tmp_base + ".rt"
        lds_path = tmp_base + ".lds"
        ll_text = emit llvm ir nprog
        _ = write file ll_path ll_text
        rt_bytes = build x8664 rt kernel
        _ = write bytes rt_path rt_bytes
        lds_text = emit llvm linker script
        _ = write file lds_path lds_text
        cmd = "/usr/bin/llc -O2 -filetype=obj \"" + ll_path + "\" -o \"" + obj_path + "\" && /usr/bin/ld -n --no-warn-rwx-segments -T \"" + lds_path + "\" -b binary \"" + rt_path + "\" -b elf64-x86-64 \"" + obj_path + "\" -o \"" + output_bin + "\""
        res = shell exec cmd
        finish llvm link res output_bin tmp_base

fn :: build llvm x8664 so library RNativeProg String    => Int
      build llvm x8664 so library nprog       output_so =
        pid_s = int to str (sys getpid)
        tmp_base = "/tmp/__rg_llvm_so_" + pid_s
        ll_path = tmp_base + ".ll"
        obj_path = tmp_base + ".o"
        rt_path = tmp_base + ".rt"
        lds_path = tmp_base + ".lds"
        ll_text = emit llvm ir nprog
        _ = write file ll_path ll_text
        rt_bytes = build x8664 rt kernel
        _ = write bytes rt_path rt_bytes
        lds_text = emit llvm linker script
        _ = write file lds_path lds_text
        cmd = "/usr/bin/llc -O2 -relocation-model=pic -filetype=obj \"" + ll_path + "\" -o \"" + obj_path + "\" && /usr/bin/ld -shared -n --no-warn-rwx-segments -T \"" + lds_path + "\" -b binary \"" + rt_path + "\" -b elf64-x86-64 \"" + obj_path + "\" -o \"" + output_so + "\""
        res = shell exec cmd
        finish llvm link res output_so tmp_base
