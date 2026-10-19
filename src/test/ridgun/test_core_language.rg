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
        echo "=== All core language tests passed ==="
