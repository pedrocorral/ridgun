-- ============================================================
-- src/test/ridgun/test parallel and tensors.rg
-- Ridgun Test Suite: Parallel where-DAG, Tensors & Regions
-- ============================================================

import test

fn :: fib Int => Int
      fib 0   =  0
      fib 1   =  1
      fib n   =  (fib (n - 1)) + (fib (n - 2))

fn :: fact Int => Int
      fact 0   =  1
      fact n   =  n * (fact (n - 1))

fn :: parallel dag calc => Int
      parallel dag calc =  a + b
        where
          fib 10        -> a
          fact 6        -> b

fn :: tensor slice calc => Int
      tensor slice calc =
        m = Tensor [[1, 2], [3, 4]]
        m[0, 1] = 50
        m[0][1] + m[1][0]

fn :: main => ()
      main =
        echo "=== Parallel where-DAG & Tensor Mutation ==="
        assert equals (parallel dag calc) 775
        assert equals (tensor slice calc) 53
        echo "=== All parallel & tensor tests passed ==="
