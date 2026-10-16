-- ============================================================
-- 03_lists_and_recursion.rg
-- Lists [T], (x:xs) pattern matching, :: concat, tail recursion
-- ============================================================

fn :: sum_list [Int] => Int
sum_list [] = 0
sum_list (x:xs) = x + sum_list xs

fn :: reverse_acc [Int] [Int] => [Int]
reverse_acc [] acc = acc
reverse_acc (x:xs) acc = reverse_acc xs ([x] :: acc)

fn :: reverse_list [Int] => [Int]
reverse_list xs = reverse_acc xs []

fn :: filter_gt [Int] Int => [Int]
filter_gt [] _ = []
filter_gt (x:xs) threshold
  | x > threshold = [x] :: (filter_gt xs threshold)
  | otherwise = filter_gt xs threshold

fn :: map_double [Int] => [Int]
map_double [] = []
map_double (x:xs) = [x * 2] :: (map_double xs)

fn :: main => ()
main =
  echo "=== Ridgun 03: Lists & Recursion ==="
  nums = [10, 25, 5, 40, 15]
  echo "sum_list     =>" (sum_list nums)
  echo "reverse_list =>" (reverse_list nums)
  echo "filter_gt 12 =>" (filter_gt nums 12)
  echo "map_double   =>" (map_double nums)
