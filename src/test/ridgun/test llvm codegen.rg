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
        _ = echo "[FAIL] {msg}"
        1

fn :: test llvm instr emission => Int
      test llvm instr emission =
        ir_imm = emit llvm instr (NLoadImmInt 42) 0 4 16
        e1 = assert true (str contains ir_imm "store i64 85, ptr %acc, align 8") "NLoadImmInt 42 tags as 85"
        ir_mov = emit llvm instr (NMoveSlot 2) 1 4 16
        e2 = assert true ((str contains ir_mov "store i64 0, ptr %s_1") AND (str contains ir_mov "store i64 %v_1, ptr %acc")) "NMoveSlot zeros source slot and stores to %acc"
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
        e13 = assert true ((str contains ir_tco "call void @__rg_rt_tco_copy(") AND (str contains ir_tco "br label %tco_entry")) "NTailCall copies args and branches to %tco_entry"
        e1 + e2 + e3 + e4 + e5 + e6 + e7 + e8 + e9 + e10 + e11 + e12 + e13

fn :: verify llc status Int String => Int
      verify llc status 0 tmp_base =
        _ = shell exec ("rm -f \"" + tmp_base + "\".*")
        0
      verify llc status code tmp_base =
        _ = shell exec ("rm -f \"" + tmp_base + "\".*")
        _ = echo "[FAIL] llc verification failed with exit code {code}"
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
        _ = write file ll_path ll_text
        res = shell exec ("/usr/bin/llc -O2 -filetype=obj \"" + ll_path + "\" -o \"" + obj_path + "\"")
        verify llc status res tmp_base

fn :: make repeat str String Int String => String
      make repeat str ch n acc
        | n <= 0 = acc
        | otherwise = make repeat str ch (n - 1) (acc + ch)

fn :: test sha256 primitives => Int
      test sha256 primitives =
        h_empty = sha256 raw ""
        e1 = assert true (((str len h_empty) == 32) AND (((str char at h_empty 0) + 256) % 256 == 227) AND (((str char at h_empty 31) + 256) % 256 == 85)) "sha256_raw empty vector"
        h_pin = sha256 raw "00679"
        e2 = assert true (((str len h_pin) == 32) AND (((str char at h_pin 0) + 256) % 256 == 0) AND (((str char at h_pin 31) + 256) % 256 == 251)) "sha256_raw '00679' vector"
        p60 = make repeat str "c" 60 ""
        h_60 = sha256 raw p60
        e3 = assert true (((str len h_60) == 32) AND (((str char at h_60 0) + 256) % 256 == 107) AND (((str char at h_60 31) + 256) % 256 == 128)) "sha256_raw 60-byte two-block padding vector"
        k64 = make repeat str "6" 64 ""
        m32 = make repeat str "a" 32 ""
        h_cat1 = sha256 raw (k64 + m32)
        h_cat2 = sha256 raw (k64 + m32)
        e4 = assert true ((h_cat1 == h_cat2) AND (((str char at h_cat1 0) + 256) % 256 == 86) AND (((str char at h_cat1 31) + 256) % 256 == 245)) "sha256_raw(64B + 32B) fusion & midstate cache"
        m60 = make repeat str "b" 60 ""
        h_cat60 = sha256 raw (k64 + m60)
        e5 = assert true ((((str char at h_cat60 0) + 256) % 256 == 232) AND (((str char at h_cat60 31) + 256) % 256 == 221)) "sha256_raw(64B + 60B) fusion boundary"
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
        e1 = assert true ((t1_(0) == 11) AND (t1_(3) == -4611686018427387904)) "1D Tensor fast-path read/write including 64-bit heap-boxed integer"
        m2 = Tensor[Int * 3 * 4]
        _ = mutate tensor mat m2
        e2 = assert true ((m2_(1, 2) == 999) AND (m2_(2, 3) == -4611686018427387904)) "2D Tensor in-place argument mutation and fast-path subscript"
        e1 + e2

fn :: tco sum loop Int Int => Int
      tco sum loop n acc
        | n <= 0 = acc
        | otherwise = tco sum loop (n - 1) (acc + 1)

fn :: test tco loop => Int
      test tco loop =
        res = tco sum loop 50000 0
        assert true (res == 50000) "TCO 50,000 iterations"

fn :: finish test suite Int => ()
      finish test suite 0 =
        echo "[PASS] test llvm codegen"
      finish test suite errs =
        _ = echo "[FAIL] test llvm codegen ({errs} error(s))"
        sys exit 1

fn :: main => ()
      main =
        errs = (test llvm instr emission) + (test llvm module llc validation) + (test sha256 primitives) + (test tensor primitives) + (test tco loop)
        finish test suite errs
