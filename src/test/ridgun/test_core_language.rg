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

fn :: main => ()
      main =
        echo "=== Core Language, ADTs, Mixfix, Variadics & Higher-Order Ops ==="
        assert_equals (area (Rect 6 7)) 42
        assert_equals (clamp 150 between 0 and 100) 100
        assert_equals (sum_variadic 10 20 30 40) 100
        assert_equals (apply_twice double_val 5) 20
        assert_equals (map double_val [1, 2, 3, 4, 5]) [2, 4, 6, 8, 10]
        assert_equals (seq_map double_val [1, 2, 3, 4, 5]) [2, 4, 6, 8, 10]
        assert_equals (filter is_even [1, 2, 3, 4, 5, 6]) [2, 4, 6]
        assert_equals (seq_filter is_even [1, 2, 3, 4, 5, 6]) [2, 4, 6]
        assert_equals (fold add_pair 0 [1, 2, 3, 4, 5]) 15
        echo "=== All core language tests passed ==="
