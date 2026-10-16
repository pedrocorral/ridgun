-- ============================================================
-- 04_sequences_and_operators.rg
-- Custom operators (op ::), sequences, masks s(+ _), s(0 3), s1:s2
-- ============================================================

op :: Int Int switch => Int Int
a b switch = b, a

op :: clamp Int between Int and Int => Int
clamp x between lo and hi
  | x < lo = lo
  | x > hi = hi
  | otherwise = x

fn :: mask_first Int Int => Int
mask_first a b =
  s = a b switch
  s(+ _)

fn :: mask_second Int Int => Int
mask_second a b =
  s = a b switch
  s(_ +)

fn :: chained_switch Int Int => (Int, Int)
chained_switch a b = a b switch switch

fn :: join_and_index => (Int, Int)
join_and_index =
  s1 = 10 20 switch
  s2 = 30 40 switch
  joined = s1:s2
  joined(0 3)

fn :: mask_four_edges => (Int, Int)
mask_four_edges =
  s1 = 10 20 switch
  s2 = 30 40 switch
  joined = s1:s2
  joined(+ _ _ +)

fn :: main => ()
main =
  echo "=== Ridgun 04: Sequences & Custom Operators ==="
  echo "mask_first 3 4         =>" (mask_first 3 4)
  echo "mask_second 3 4        =>" (mask_second 3 4)
  echo "chained_switch 3 4     =>" (chained_switch 3 4)
  echo "join_and_index         =>" join_and_index
  echo "mask_four_edges        =>" mask_four_edges
  echo "clamp 150 between 0 100=>" (clamp 150 between 0 and 100)
