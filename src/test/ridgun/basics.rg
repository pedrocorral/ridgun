-- ============================================================
-- Ridgun Test: Basic Functions
-- ============================================================

-- Simple two-argument function
fn :: sum int int => int
      sum a b     =  a + b

-- Recursive with pattern matching
fn :: factorial int => int
      factorial 0   =  1
      factorial n   =  n * factorial (n - 1)

-- Double recursion with pattern matching
fn :: fib int => int
      fib 0   =  0
      fib 1   =  1
      fib n   =  fib (n - 1) + fib (n - 2)

-- Reverse a list
fn :: reverse [int] => [int]
      reverse []     = []
      reverse (x:xs) = reverse xs :: [x]

-- Length of a list
fn :: list_length [int] => int
      list_length []     = 0
      list_length (_:xs) = 1 + list_length xs

-- Sequence selector: extract first element via seq binding
fn :: first_of_seq int int => int
      first_of_seq (s)     =  s(+ _)

-- Sequence selector: extract endpoints from a 4-seq
fn :: endpoints int int int int => int
      endpoints (s)             =  s(+ _ _ _)

-- Sequence index selector: extract by position
fn :: extreme_points int int int int => int
      extreme_points (s)             =  s(0 3)
