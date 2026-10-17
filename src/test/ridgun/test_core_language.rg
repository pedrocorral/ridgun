-- ============================================================
-- src/test/ridgun/test_core_language.rg
-- Ridgun Test Suite: ADTs, Custom Operators & Variadics
-- ============================================================

import test

type Shape = Circle Int | Rect Int Int

fn :: area Shape => Int
area (Circle r) = 3 * r * r
area (Rect w h) = w * h

op :: clamp Int between Int and Int => Int
clamp x between lo and hi
  | x < lo = lo
  | x > hi = hi
  | otherwise = x

fn :: sum_int_list [Int] => Int
sum_int_list [] = 0
sum_int_list (x:xs) = x + (sum_int_list xs)

fn :: sum_variadic Int... => Int
sum_variadic items = sum_int_list items

fn :: main => ()
main =
  echo "=== Core Language, ADTs, Mixfix & Variadics ==="
  assert_equals (area (Rect 6 7)) 42
  assert_equals (clamp 150 between 0 and 100) 100
  assert_equals (sum_variadic 10 20 30 40) 100
  echo "=== All core language tests passed ==="
