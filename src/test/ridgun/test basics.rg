-- ============================================================
-- Ridgun Test: Basic Functions (using test library)
-- ============================================================

import test

-- ── Functions under test ────────────────────────────────────

fn :: sum Int Int => Int
      sum a   b   =  a + b

fn :: factorial Int => Int
      factorial 0   =  1
      factorial n   =  n * factorial (n - 1)

fn :: fib Int => Int
      fib 0   =  0
      fib 1   =  1
      fib n   =  fib (n - 1) + fib (n - 2)

fn :: double Int => Int
      double x   =  x + x

fn :: quadruple Int => Int
      quadruple x   =  double (double x)

fn :: match real val Float => String
      match real val 0.0   =  "zero"
      match real val 3.14  =  "pi"
      match real val _     =  "other"

fn :: match bool val Bool  => String
      match bool val True  =  "yes"
      match bool val False =  "no"

fn :: match list shape [Int]      => String
      match list shape []         =  "empty"
      match list shape (x:[])     =  "single:{x}"
      match list shape (x:y:rest) =  "pair+:{x},{y}"

fn :: sum tuple3 (Int, Int, Int) => Int
      sum tuple3 (a, b, c)       =  a + b + c

-- ── Tests ───────────────────────────────────────────────────

fn :: main => ()
      main =
        echo "=== Arithmetic ==="
        assert equals (sum 3 4) 7
        assert equals (sum 0 0) 0
        assert equals (10 - 3) 7
        assert equals (2 + 3 * 4) 14
        assert equals ((2 + 3) * 4) 20
        assert equals (100 / 5 / 2) 10
        assert equals (17 % 5) 2
        assert equals (1.5 + 2.25) 3.75
        assert equals (5.0 - 1.5) 3.5
        assert equals (2.5 * 4.0) 10.0
        assert equals (9.0 / 2.0) 4.5
        echo "=== Pattern Matching ==="
        assert equals (factorial 0) 1
        assert equals (factorial 5) 120
        assert equals (fib 10) 55
        assert equals (match real val 0.0) "zero"
        assert equals (match real val 3.14) "pi"
        assert equals (match real val 2.71) "other"
        assert equals (match bool val True) "yes"
        assert equals (match bool val False) "no"
        assert equals (match list shape []) "empty"
        assert equals (match list shape [42]) "single:42"
        assert equals (match list shape [10, 20, 30]) "pair+:10,20"
        assert equals (sum tuple3 (10, 20, 30)) 60
        assert equals ([1, 2] :: [3, 4]) [1, 2, 3, 4]
        echo "=== Higher-order ==="
        assert equals (double 5) 10
        assert equals (quadruple 5) 20
        echo "=== All basic tests passed ==="
