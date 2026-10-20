-- ============================================================
-- src/test/ridgun/test_core_language.rg
-- Ridgun Test Suite: ADTs, Custom Operators & Variadics
-- ============================================================

import test

type Shape = Circle Int | Rect Int Int

fn :: area Shape      => Int
      area (Circle r) =  3 * r * r
      area (Rect w h) =  w * h

op :: clamp Int between Int and Int => Int
      clamp x   between lo  and hi
        | x < lo = lo
        | x > hi = hi
        | otherwise = x

fn :: sum_int_list [Int]  => Int
      sum_int_list []     =  0
      sum_int_list (x:xs) =  x + (sum_int_list xs)

fn :: sum_variadic Int... => Int
      sum_variadic items  =  sum_int_list items

fn :: double_val Int => Int
      double_val n   =  n * 2

fn :: is_even Int => Bool
      is_even n   =  (n % 2) == 0

fn :: add_pair Int Int => Int
      add_pair acc x   =  acc + x

fn :: apply_twice (Int => Int) Int => Int
      apply_twice f            x   =  f (f x)

list_len [A]    => Int
list_len []     =  0
list_len (_:xs) =  1 + (list_len xs)

swap A with B => (B, A)
swap x with y =  (y, x)

fst (A, B) => A
fst (a, _) =  a

head_or [A]   A => A
head_or []    d =  d
head_or (x:_) _ =  x

type LsSpec = one_per_line: Bool, color: Bool, width: Int

op :: format String type String with Int  => String
      format label  type type   with with =  "{label}:{type}:{with}"

fn :: guard_block_calc Int Int   => Int
      guard_block_calc idx limit
        | idx >= limit =
          capped = limit - 1
          scaled = capped * 2
          scaled + 10
        | otherwise =
          next_i = idx + 1
          next_i * 3

fn :: elegir Bool [Int] [Int] => [Int]
      elegir cond a     b
        | cond = a
        | otherwise = b

-- @tests FR-COMP-002
fn :: cmm_trace_elegir Bool => (Int, Int, Int, Int, Int, Int)
      cmm_trace_elegir cond =
        base_live = cmm_live_blocks
        base_freed = cmm_cond_freed
        base_spared = cmm_cond_spared
        a = [10, 20, 30]
        b = [40, 50, 60]
        vivos_ab = cmm_live_blocks - base_live
        c = elegir cond a b
        vivos_tras_elegir = cmm_live_blocks - base_live
        _ = list_len a
        vivos_tras_usar_a = cmm_live_blocks - base_live
        _ = list_len c
        vivos_tras_usar_c = cmm_live_blocks - base_live
        delta_freed = cmm_cond_freed - base_freed
        delta_spared = cmm_cond_spared - base_spared
        (vivos_ab, vivos_tras_elegir, vivos_tras_usar_a, vivos_tras_usar_c, delta_freed, delta_spared)

fn :: cmm_check_ptr_identity Bool => (Bool, Bool)
      cmm_check_ptr_identity cond =
        a = [1, 2, 3]
        b = [4, 5, 6]
        c = elegir cond a b
        same_a = cmm_same_ptr a c
        same_b = cmm_same_ptr b c
        (same_a, same_b)

fn :: cmm_trace_cascada Bool Bool => (Int, Int, Int)
      cmm_trace_cascada c1   c2   =
        base = cmm_live_blocks
        a = [1, 2]
        b = [3, 4]
        d = [5, 6]
        c = elegir c1 a b
        e = elegir c2 c d
        vivos_tras_cascada = cmm_live_blocks - base
        _ = list_len a
        vivos_tras_a = cmm_live_blocks - base
        _ = list_len e
        vivos_tras_e = cmm_live_blocks - base
        (vivos_tras_cascada, vivos_tras_a, vivos_tras_e)

fn :: rmm2_trace_nested => (Int, Int, Int)
      rmm2_trace_nested =
        base = cmm_live_blocks
        a = [10, 20]
        b = [30, 40]
        xs = [a, b]
        vivos_inicial = cmm_live_blocks - base
        _ = list_len xs
        vivos_tras_xs = cmm_live_blocks - base
        _ = list_len a
        vivos_final = cmm_live_blocks - base
        (vivos_inicial, vivos_tras_xs, vivos_final)

fn :: main => ()
      main =
        echo "=== Core Language, ADTs, Mixfix, Variadics & Higher-Order Ops ==="
        assert_equals (area (Rect 6 7)) 42
        assert_equals (clamp 150 between 0 and 100) 100
        assert_equals (sum_variadic 10 20 30 40) 100
        assert_equals (apply_twice double_val 5) 20
        assert_equals (list_len [10, 20, 30, 40]) 4
        assert_equals (list_len ["a", "b", "c"]) 3
        assert_equals (swap 7 with "ok") ("ok", 7)
        assert_equals (fst (42, "hello")) 42
        assert_equals (fst ("hello", 42)) "hello"
        assert_equals (head_or [10, 20] 99) 10
        assert_equals (head_or ["x", "y"] "z") "x"
        base_spec = LsSpec False False 80
        spec1 = base_spec with color: True
        spec2 = spec1 with one_per_line: True, width: 120
        assert_equals (color spec1) True
        assert_equals (width spec1) 80
        assert_equals (one_per_line spec2) True
        assert_equals (color spec2) True
        assert_equals (width spec2) 120
        assert_equals (format "box" type "solid" with 64) "box:solid:64"
        assert_equals (guard_block_calc 10 10) 28
        assert_equals (guard_block_calc 4 10) 15
        assert_equals "$\{VAR:-default\}" '${VAR:-default}'
        assert_equals "setenv \{ ok \}" 'setenv { ok }'
        assert_equals "{{double}}" '{double}'
        assert_equals (map double_val [1, 2, 3, 4, 5]) [2, 4, 6, 8, 10]
        assert_equals (seq_map double_val [1, 2, 3, 4, 5]) [2, 4, 6, 8, 10]
        assert_equals (filter is_even [1, 2, 3, 4, 5, 6]) [2, 4, 6]
        assert_equals (seq_filter is_even [1, 2, 3, 4, 5, 6]) [2, 4, 6]
        assert_equals (fold add_pair 0 [1, 2, 3, 4, 5]) 15
        echo "=== RMM2 Assignment & Cascaded Structure Counting ==="
        assert_equals (cmm_check_ptr_identity True) (True, False)
        assert_equals (cmm_check_ptr_identity False) (False, True)
        assert_equals (cmm_trace_elegir True) (2, 1, 1, 0, 2, 1)
        assert_equals (cmm_trace_elegir False) (2, 2, 1, 0, 2, 1)
        assert_equals (cmm_trace_cascada True True) (1, 1, 0)
        assert_equals (cmm_trace_cascada False False) (2, 1, 0)
        assert_equals (rmm2_trace_nested) (3, 1, 0)
        echo "=== All core language tests passed ==="

