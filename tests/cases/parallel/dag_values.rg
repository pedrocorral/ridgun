-- case: a named || DAG feeding the header expression, and anonymous || branches returning a tuple in declaration order
-- source: FR-COMP-003 §4 (parallel_dag_calc, both_metrics; tuple written "=> Int Int" for --strict, FR-COMP-008); spec.md:723-746;
--   the tuple is taken apart by a tuple pattern in a parameter (tutorials.md:81-96, FR-COMP-008: (A B) ≡ (A, B))
-- expect-output:
--   775
--   55 3628800

fn :: fib Int => Int
      fib n =
        | n < 2     = n
        | otherwise = (fib (n - 1)) + (fib (n - 2))

fn :: fact Int => Int
      fact n =
        | n <= 1    = 1
        | otherwise = n * (fact (n - 1))

fn :: parallel dag calc => Int
      parallel dag calc =  a + b
        || fib 10       -> a
        || fact 6       -> b

fn :: both metrics Int => Int Int
      both metrics x =
        || fib x
        || fact x

fn :: show pair (Int Int) => String
      show pair (a, b) =  (int to str a) + " " + (int to str b)

fn :: main => ()
      main =
        echo (int to str (parallel dag calc))
        echo (show pair (both metrics 10))
