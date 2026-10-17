-- ============================================================
-- src/test/ridgun/test_parallel_and_tensors.rg
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

fn :: parallel_dag_calc => Int
      parallel_dag_calc =  a + b
        where
          fib 10        -> a
          fact 6        -> b

fn :: tensor_mut_calc => Int
      tensor_mut_calc =
        m = Tensor [[1, 2], [3, 4]]
        m[0, 1] = 50
        m[0][1] + m[1][0]

fn :: main => ()
      main =
        echo "=== Parallel where-DAG & Tensor Mutation ==="
        assert_equals parallel_dag_calc 775
        assert_equals tensor_mut_calc 53
        echo "=== All parallel & tensor tests passed ==="
