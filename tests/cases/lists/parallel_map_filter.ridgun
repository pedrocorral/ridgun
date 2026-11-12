-- case: ||map and ||filter give exactly what map and filter give, in the original order, on 2 000 elements
-- source: FR-COMP-001 §3 (order preserved) and AC1-AC2
-- expect-output:
--   [1, 4, 9, 16]
--   [2, 4]
--   same map: True
--   same filter: True
--   first 3 of ||map: [0, 1, 4]

fn :: square Int => Int
      square x =  x * x

fn :: is even Int => Bool
      is even x =  (x % 2) == 0

fn :: upto Int Int [Int] => [Int]
      upto i n acc =
        | i >= n    = acc
        | otherwise = upto (i + 1) n (acc :: [i])

fn :: same [Int] [Int] => Bool
      same []     []     =  True
      same (a:as) (b:bs) =  a == b and (same as bs)
      same _      _      =  False

fn :: take three [Int] => [Int]
      take three (a:b:c:_) =  [a, b, c]
      take three xs        =  xs

fn :: show ints [Int] => String
      show ints []     =  "[]"
      show ints (x:xs) =  "[" + (int to str x) + (show rest xs) + "]"

fn :: show rest [Int] => String
      show rest []     =  ""
      show rest (x:xs) =  ", " + (int to str x) + (show rest xs)

fn :: main => ()
      main =
        xs = upto 0 2000 []
        echo (show ints (||map square [1, 2, 3, 4]))
        echo (show ints (||filter is even [1, 2, 3, 4]))
        echo ("same map: " + (bool text (same (||map square xs) (map square xs))))
        echo ("same filter: " + (bool text (same (||filter is even xs) (filter is even xs))))
        echo ("first 3 of ||map: " + (show ints (take three (||map square xs))))

fn :: bool text Bool => String
      bool text True  =  "True"
      bool text False =  "False"
