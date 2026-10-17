-- ============================================================
-- Ridgun Test: Basic Functions
-- ============================================================

-- Simple two-argument function
fn :: sum Int Int => Int
      sum a   b   =  a + b

-- Recursive with pattern matching
fn :: factorial Int => Int
      factorial 0   =  1
      factorial n   =  n * factorial (n - 1)

-- Double recursion with pattern matching
fn :: fib Int => Int
      fib 0   =  0
      fib 1   =  1
      fib n   =  fib (n - 1) + fib (n - 2)

-- Reverse a list
fn :: reverse [Int]  => [Int]
      reverse []     =  []
      reverse (x:xs) =  reverse xs :: [x]

-- Length of a list
fn :: list_length [Int]  => Int
      list_length []     =  0
      list_length (_:xs) =  1 + list_length xs

-- Sequence selector: extract first element via seq binding
fn :: first_of_seq Int Int => Int
      first_of_seq (s)     =  s(+ _)

-- Sequence selector: extract endpoInts from a 4-seq
fn :: endpoints Int Int Int Int => Int
      endpoints (s)             =  s(+ _ _ _)

-- Sequence index selector: extract by position
fn :: extreme_points Int Int Int Int => Int
      extreme_points (s)             =  s(0 3)
