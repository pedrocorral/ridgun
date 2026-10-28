-- ============================================================
-- src/test/ridgun/test llvm codegen.rg
-- Low-Level Unit Tests for LLVM IR (.ll) Codegen & Fast-Path Helpers
-- @implements FR-COMP-004
-- @implements FR-COMP-010
-- @implements FR-COMP-011
-- ============================================================

import llvm

fn :: assert true Bool String => Int
      assert true True _ = 0
      assert true False msg =
        echo "[FAIL] {msg}"
        1

fn :: test llvm instr emission => Int
      test llvm instr emission =
        ir_imm = emit llvm instr (NLoadImmInt 42) 0 4 16
        e1 = assert true (str contains ir_imm "store i64 85, ptr %acc, align 8") "NLoadImmInt 42 tags as 85"
        ir_mov = emit llvm instr (NMoveSlot 2) 1 4 16
        e2 = assert true ((str contains ir_mov "store i64 0, ptr %s_1") and (str contains ir_mov "store i64 %v_1, ptr %acc")) "NMoveSlot zeros source slot and stores to %acc"
        ir_mint = emit llvm instr (NMatchInt 1 7) 2 4 16
        e3 = assert true (str contains ir_mint "icmp eq i64 %v_2, 15") "NMatchInt 7 compares against tagged 15"
        ir_madt_int = emit llvm instr (NMatchAdt 0 0 0 (-1)) 3 4 16
        e4 = assert true (str contains ir_madt_int "and i64 %v_3, 1") "NMatchAdt -1 checks immediate Int bit"
        ir_madt_str = emit llvm instr (NMatchAdt 0 0 0 (-3)) 4 4 16
        e5 = assert true (str contains ir_madt_str "call i64 @__rg_match_heap_tag(i64 %v_4, i32 1)") "NMatchAdt -3 checks heap tag 1 (String)"
        ir_idx1 = emit llvm instr (NIndex 0 1 (-1)) 5 4 16
        e6 = assert true (str contains ir_idx1 "call i64 @__rg_tensor_index_1d(") "NIndex -1 calls @__rg_tensor_index_1d"
        ir_idx2 = emit llvm instr (NIndex 0 1 (-2)) 6 4 16
        e7 = assert true (str contains ir_idx2 "call i64 @__rg_tensor_index_2d(") "NIndex -2 calls @__rg_tensor_index_2d"
        ir_set1 = emit llvm instr (NIndexSet 0 1 1) 7 4 16
        e8 = assert true (str contains ir_set1 "call i64 @__rg_tensor_index_set_1d(") "NIndexSet 1 calls @__rg_tensor_index_set_1d"
        ir_set2 = emit llvm instr (NIndexSet 0 1 2) 8 4 16
        e9 = assert true (str contains ir_set2 "call i64 @__rg_tensor_index_set_2d(") "NIndexSet 2 calls @__rg_tensor_index_set_2d"
        ir_sha = emit llvm instr (NCallBuiltin 36 1 1) 9 4 16
        e10 = assert true (str contains ir_sha "call i64 @__rg_builtin_sha256_raw(") "NCallBuiltin 36 calls @__rg_builtin_sha256_raw"
        ir_shac = emit llvm instr (NCallBuiltin 89 1 2) 10 4 16
        e11 = assert true (str contains ir_shac "call i64 @__rg_builtin_sha256_concat(") "NCallBuiltin 89 calls @__rg_builtin_sha256_concat"
        ir_tfill = emit llvm instr (NCallBuiltin 88 1 3) 11 4 16
        e12 = assert true (str contains ir_tfill "call i64 @__rg_builtin_tensor_fill(") "NCallBuiltin 88 calls @__rg_builtin_tensor_fill"
        ir_tco = emit llvm instr (NTailCall 2 2) 12 4 16
        e13 = assert true ((str contains ir_tco "call void @__rg_rt_tco_copy(") and (str contains ir_tco "br label %tco_entry")) "NTailCall copies args and branches to %tco_entry"
        ir_bin = emit llvm instr (NBinOp 0 1) 13 4 16
        e14 = assert true (str contains ir_bin "call i64 @__rg_fast_bin_op(i64 0,") "NBinOp emits @__rg_fast_bin_op"
        ir_cslot = emit llvm instr (NCloneSlot 2) 14 4 16
        e15 = assert true (str contains ir_cslot "call i64 @__rg_fast_clone_slot(") "NCloneSlot emits @__rg_fast_clone_slot"
        ir_sslot = emit llvm instr (NStoreSlot 2) 15 4 16
        e16 = assert true (str contains ir_sslot "call i64 @__rg_fast_store_slot(") "NStoreSlot emits @__rg_fast_store_slot"
        ir_chr_fast = emit llvm instr (NCallBuiltin 91 3 0) 16 4 16
        e17 = assert true (str contains ir_chr_fast "call i64 @__rg_str_char_at_fast(") "NCallBuiltin 91 emits @__rg_str_char_at_fast"
        ir_chr_gen = emit llvm instr (NCallBuiltin 40 1 2) 17 4 16
        e18 = assert true (str contains ir_chr_gen "call i64 @__rg_builtin_str_char_at(") "NCallBuiltin 40 emits @__rg_builtin_str_char_at"
        ir_rslice = emit llvm instr (NCallBuiltin 92 1 2) 18 4 16
        e19 = assert true (str contains ir_rslice "call i64 @__rg_builtin_tensor_row_slice(") "NCallBuiltin 92 emits @__rg_builtin_tensor_row_slice"
        ir_rset = emit llvm instr (NCallBuiltin 93 1 3) 19 4 16
        e20 = assert true (str contains ir_rset "call i64 @__rg_builtin_tensor_set_row(") "NCallBuiltin 93 emits @__rg_builtin_tensor_set_row"
        ir_cslice = emit llvm instr (NCallBuiltin 94 1 2) 20 4 16
        e21 = assert true (str contains ir_cslice "call i64 @__rg_builtin_tensor_col_slice(") "NCallBuiltin 94 emits @__rg_builtin_tensor_col_slice"
        ir_cset = emit llvm instr (NCallBuiltin 95 1 3) 21 4 16
        e22 = assert true (str contains ir_cset "call i64 @__rg_builtin_tensor_set_col(") "NCallBuiltin 95 emits @__rg_builtin_tensor_set_col"
        ir_ein = emit llvm instr (NEinsum 1 2 0 5) 22 4 16
        e23 = assert true (str contains ir_ein "call i64 @__rg_fast_einsum(") "NEinsum emits @__rg_fast_einsum"
        ir_clr = emit llvm instr (NClearLocals 2 4) 23 4 16
        e24 = assert true (str contains ir_clr "call i64 @__rg_fast_drop_val(") "Small NClearLocals unrolls constant-offset @__rg_fast_drop_val"
        ir_call_reg = emit llvm instr (NCallFn 7 2 2) 24 6 16
        e25 = assert true ((str contains ir_call_reg "call i64 @__rg_fn_7_reg(i64 %cav_24_0, i64 %cav_24_1)") and (str contains ir_call_reg "store i64 0, ptr %cap_24_0")) "OPT-013 NCallFn emits direct register call @__rg_fn_7_reg and zeroes caller slots"
        fn_reg_ir = emit llvm fn (NativeFn 7 "add_two" 2 4 [NMoveSlot 0, NStoreSlot 2, NMoveSlot 1, NBinOp 0 2, NReturn]) 16
        e26 = assert true ((str contains fn_reg_ir "define i64 @__rg_fn_7_reg(i64 %arg_0, i64 %arg_1) inlinehint nounwind") and (str contains fn_reg_ir "define i64 @__rg_fn_7(ptr %args) nounwind")) "OPT-013 emit llvm fn emits @__rg_fn_7_reg and ABI wrapper @__rg_fn_7"
        e1 + e2 + e3 + e4 + e5 + e6 + e7 + e8 + e9 + e10 + e11 + e12 + e13 + e14 + e15 + e16 + e17 + e18 + e19 + e20 + e21 + e22 + e23 + e24 + e25 + e26

fn :: verify llc status Int String => Int
      verify llc status 0 tmp_base =
        shell exec ("rm -f \"" + tmp_base + "\".*")
        0
      verify llc status code tmp_base =
        shell exec ("rm -f \"" + tmp_base + "\".*")
        echo "[FAIL] llc verification failed with exit code {code}"
        1

fn :: test llvm module llc validation => Int
      test llvm module llc validation =
        f1 = NativeFn 1 "main" 0 2 [NLoadImmInt 7, NStoreSlot 0, NCloneSlot 0, NReturn]
        f2 = NativeFn 2 "spawn" 1 1 [NLoadImmRaw 0, NReturn]
        f3 = NativeFn 3 "call2" 2 2 [NLoadImmRaw 0, NReturn]
        f4 = NativeFn 4 "binop" 3 3 [NLoadImmRaw 0, NReturn]
        nprog = NativeProg 1 2 3 4 [f1, f2, f3, f4] "hello_llvm"
        ll_text = emit llvm ir nprog
        pid_s = int to str (sys getpid)
        tmp_base = "/tmp/__rg_test_llvm_" + pid_s
        ll_path = tmp_base + ".ll"
        obj_path = tmp_base + ".o"
        write file ll_path ll_text
        res = shell exec ("/usr/bin/llc -O2 -filetype=obj \"" + ll_path + "\" -o \"" + obj_path + "\"")
        verify llc status res tmp_base

fn :: make repeat str String Int String => String
      make repeat str ch n acc
        | n <= 0 = acc
        | otherwise = make repeat str ch (n - 1) (acc + ch)

fn :: test sha256 primitives => Int
      test sha256 primitives =
        h_empty = sha256 raw ""
        e1 = assert true (((str len h_empty) == 32) and (((str char at h_empty 0) + 256) % 256 == 227) and (((str char at h_empty 31) + 256) % 256 == 85)) "sha256_raw empty vector"
        h_pin = sha256 raw "00679"
        e2 = assert true (((str len h_pin) == 32) and (((str char at h_pin 0) + 256) % 256 == 0) and (((str char at h_pin 31) + 256) % 256 == 251)) "sha256_raw '00679' vector"
        p60 = make repeat str "c" 60 ""
        h_60 = sha256 raw p60
        e3 = assert true (((str len h_60) == 32) and (((str char at h_60 0) + 256) % 256 == 107) and (((str char at h_60 31) + 256) % 256 == 128)) "sha256_raw 60-byte two-block padding vector"
        k64 = make repeat str "6" 64 ""
        m32 = make repeat str "a" 32 ""
        h_cat1 = sha256 raw (k64 + m32)
        h_cat2 = sha256 raw (k64 + m32)
        e4 = assert true ((h_cat1 == h_cat2) and (((str char at h_cat1 0) + 256) % 256 == 86) and (((str char at h_cat1 31) + 256) % 256 == 245)) "sha256_raw(64B + 32B) fusion & midstate cache"
        m60 = make repeat str "b" 60 ""
        h_cat60 = sha256 raw (k64 + m60)
        e5 = assert true ((((str char at h_cat60 0) + 256) % 256 == 232) and (((str char at h_cat60 31) + 256) % 256 == 221)) "sha256_raw(64B + 60B) fusion boundary"
        e1 + e2 + e3 + e4 + e5

fn :: mutate tensor mat Tensor[Int * 3 * 4] => ()
      mutate tensor mat m =
        m_(1, 2) = 999
        m_(2, 3) = -4611686018427387904
        ()

fn :: test tensor primitives => Int
      test tensor primitives =
        t1 = Tensor[Int * 4]
        t1_(0) = 11
        t1_(3) = -4611686018427387904
        e1 = assert true ((t1_(0) == 11) and (t1_(3) == -4611686018427387904)) "1D Tensor fast-path read/write including 64-bit heap-boxed integer"
        m2 = Tensor[Int * 3 * 4]
        mutate tensor mat m2
        e2 = assert true ((m2_(1, 2) == 999) and (m2_(2, 3) == -4611686018427387904)) "2D Tensor in-place argument mutation and fast-path subscript"
        -- Full 64-bit U64 values where bit 63 != bit 62 (0x4000000000000000 .. 0xBFFFFFFFFFFFFFFF)
        u_b62 = (1 shl 62) + 42
        u_b63 = (1 shl 63) or 99
        iv0 = (1779033703 shl 32) or 4089235720
        iv1 = (3144134277 shl 32) or 2227873595
        m64 = Tensor[Int * 2 * 4]
        m64_(0, 0) = u_b62
        m64_(0, 1) = u_b63
        m64_(1, 2) = iv0
        m64_(1, 3) = iv1
        r_b62 = m64_(0, 0)
        r_b63 = m64_(0, 1)
        r_iv0 = m64_(1, 2)
        r_iv1 = m64_(1, 3)
        e3 = assert true ((r_b62 == u_b62) and ((r_b62 shr 62) == 1) and ((r_b62 and 63) == 42)) "2D Tensor preserves bit 62 (0x400000000000002A) without truncation"
        e4 = assert true ((r_b63 == u_b63) and ((r_b63 shr 63) == 1) and ((r_b63 and 127) == 99)) "2D Tensor preserves bit 63 (0x8000000000000063) without truncation"
        e5 = assert true (((r_iv0 xor r_iv1) xor r_iv1) == iv0) "64-bit U64 xor roundtrip on SHA-512/Blake2b IV words"
        rot_v = (r_iv0 rotr 24) rotl 24
        e6 = assert true (rot_v == iv0) "64-bit U64 rotr/rotl roundtrip"
        -- Row/Col slice & set builtins (92..95), arithmetic Hadamard, and 2D Einsum
        m64_(1,) = m64_(0,)
        c_slice1 = m64_(,1)
        e7 = assert true ((m64_(1, 0) == u_b62) and (m64_(1, 1) == u_b63) and (c_slice1_(0) == u_b63) and (c_slice1_(1) == u_b63)) "Row slice/set (92, 93) and col slice (94) preserve 64-bit U64 elements"
        ma = Tensor [[2, 3], [4, 5]]
        mb = Tensor [[10, 20], [30, 40]]
        mh_add = ma_ij + mb_ij
        mh_mul = ma_ij * mb_ij
        mc_ein = ma_ik @ mb_kj
        e8 = assert true ((mh_add_(0, 0) == 12) and (mh_add_(1, 1) == 45) and (mh_mul_(0, 1) == 60) and (mh_mul_(1, 0) == 120)) "SIMD-vectorized flat arithmetic Hadamard (+, *)"
        e9 = assert true ((mc_ein_(0, 0) == 110) and (mc_ein_(0, 1) == 160) and (mc_ein_(1, 0) == 190) and (mc_ein_(1, 1) == 280)) "Fast 2D matrix multiplication NEinsum (A_ik @ B_kj)"
        e1 + e2 + e3 + e4 + e5 + e6 + e7 + e8 + e9

fn :: digest byte sum loop String Int Int Int => Int
      digest byte sum loop s i n acc
        | i >= n = acc
        | otherwise = digest byte sum loop s (i + 1) n (acc xor ((str char at s i) and 255))

fn :: test str char at fastpath => Int
      test str char at fastpath =
        s = "Ridgun!"
        e1 = assert true (((str char at s 0) == 82) and ((str char at s 6) == 33)) "str_char_at fast-path local variable bounds"
        e2 = assert true (((str char at s (-1)) == (-1)) and ((str char at s 7) == (-1))) "str_char_at fast-path out-of-bounds returns -1"
        e3 = assert true (((str char at ("A" + "Z") 1) == 90) and ((str char at ("A" + "Z") 2) == (-1))) "str_char_at general expression builtin 40"
        digest = sha256 raw "00679"
        xsum = digest byte sum loop digest 0 32 0
        e4 = assert true ((xsum >= 0) and (xsum <= 255)) "str_char_at loop over 32-byte raw SHA-256 digest"
        e1 + e2 + e3 + e4

fn :: tco sum loop Int Int => Int
      tco sum loop n acc
        | n <= 0 = acc
        | otherwise = tco sum loop (n - 1) (acc + 1)

fn :: hof triple Int => Int
      hof triple x = x * 3

fn :: hof is even Int => Bool
      hof is even x = (x % 2) == 0

fn :: hof sum acc Int Int => Int
      hof sum acc acc x = acc + x

fn :: test tco loop => Int
      test tco loop =
        res = tco sum loop 50000 0
        e1 = assert true (res == 50000) "TCO 50,000 iterations"
        nums = [1, 2, 3, 4, 5, 6]
        s_named = nums map hof triple -> filter hof is even -> fold hof sum acc 0
        s_lam = nums map (x => x * 3) -> filter (x => (x % 2) == 0) -> fold (acc x => acc + x) 0
        e2 = assert true ((s_named == 36) and (s_lam == 36)) "OPT-014 direct-call map/filter/fold specialization"
        e1 + e2

fn :: finish test suite Int => ()
      finish test suite 0 =
        echo "[PASS] test llvm codegen"
      finish test suite errs =
        echo "[FAIL] test llvm codegen ({errs} error(s))"
        sys exit 1

fn :: main => ()
      main =
        errs = (test llvm instr emission) + (test llvm module llc validation) + (test sha256 primitives) + (test tensor primitives) + (test str char at fastpath) + (test tco loop)
        finish test suite errs
