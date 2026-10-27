-- case: a top-level function name in argument position is a function value; a (A => B) parameter can be called
-- source: FR-COMP-001 §1 (first-class function values); book 07:72-76 (function types (A => B))
-- expect-output:
--   12
--   apply twice: 7
--   composed: 16

fn :: double Int => Int
      double x =  x * 2

fn :: inc Int => Int
      inc x =  x + 1

fn :: apply (Int => Int) Int => Int
      apply f x =  f x

fn :: twice (Int => Int) Int => Int
      twice f x =  f (f x)

fn :: compose (Int => Int) (Int => Int) Int => Int
      compose f g x =  g (f x)

fn :: main => ()
      main =
        echo (int to str (apply double 6))
        echo ("apply twice: " + (int to str (twice inc 5)))
        echo ("composed: " + (int to str (compose inc double 7)))
