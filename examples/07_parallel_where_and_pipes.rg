-- ============================================================
-- 07_parallel_where_and_pipes.rg
-- Implicit where Producer-Consumer DAG & || parallel pipes
-- ============================================================

fn :: fib Int => Int
fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)

fn :: fact Int => Int
fact 0 = 1
fact n = n * fact (n - 1)

fn :: parallel_where_dag => Int
parallel_where_dag = f10 + f6 + dependent
  where
    fib 10 -> f10
    fact 6 -> f6
    f10 * 2 -> dependent

fn :: parallel_pipe_stages => (Int, Int, Int)
parallel_pipe_stages =
  || fib 8
  || fib 9
  || fact 5

fn :: main => ()
main =
  echo "=== Ridgun 07: Parallel where-DAG & || Pipes ==="
  echo "parallel_where_dag   =>" parallel_where_dag
  echo "parallel_pipe_stages =>" parallel_pipe_stages
