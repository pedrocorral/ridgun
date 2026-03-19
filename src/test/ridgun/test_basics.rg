-- ============================================================
-- Ridgun Test: Basic Functions (using test library)
-- ============================================================

import test

-- ── Functions under test ────────────────────────────────────

fn :: sum Int Int => Int
      sum a b = a + b

fn :: factorial Int => Int
      factorial 0 = 1
      factorial n = n * factorial (n - 1)

fn :: fib Int => Int
      fib 0 = 0
      fib 1 = 1
      fib n = fib (n - 1) + fib (n - 2)

fn :: double Int => Int
      double x = x + x

fn :: quadruple Int => Int
      quadruple x = double (double x)

-- ── Tests ───────────────────────────────────────────────────

fn :: main => ()
      main =
        echo "=== Arithmetic ==="
        assert_equals (sum 3 4) 7
        assert_equals (sum 0 0) 0
        assert_equals (10 - 3) 7
        assert_equals (2 + 3 * 4) 14
        assert_equals ((2 + 3) * 4) 20
        assert_equals (100 / 5 / 2) 10
        echo "=== Pattern Matching ==="
        assert_equals (factorial 0) 1
        assert_equals (factorial 5) 120
        assert_equals (fib 10) 55
        echo "=== Higher-order ==="
        assert_equals (double 5) 10
        assert_equals (quadruple 5) 20
        echo "=== All basic tests passed ==="
