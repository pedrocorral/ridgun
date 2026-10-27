-- case: map, filter and fold give the values FR-COMP-001's acceptance criteria state, in order
-- source: FR-COMP-001 AC1-AC3 (docs/requirements/functional/compiler/FR-COMP-001-*.md:40-42)
-- expect-output:
--   [1, 4, 9, 16]
--   [2, 4]
--   10
--   []
--   []
--   7

fn :: square Int => Int
      square x =  x * x

fn :: is even Int => Bool
      is even x =  (x % 2) == 0

fn :: add Int Int => Int
      add a b =  a + b

fn :: show ints [Int] => String
      show ints []     =  "[]"
      show ints (x:xs) =  "[" + (int to str x) + (show rest xs) + "]"

fn :: show rest [Int] => String
      show rest []     =  ""
      show rest (x:xs) =  ", " + (int to str x) + (show rest xs)

fn :: main => ()
      main =
        echo (show ints (map square [1, 2, 3, 4]))
        echo (show ints (filter is even [1, 2, 3, 4]))
        echo (int to str (fold add 0 [1, 2, 3, 4]))
        echo (show ints (map square []))
        echo (show ints (filter is even [1, 3, 5]))
        echo (int to str (fold add 7 []))
