-- @tests TS-COMP-017
-- case: a constructor, with or without arguments, matches inside a tuple pattern and inside a cons pattern (RG-114)
-- source: FR-COMP-005 (algebraic data types and pattern matching); FR-COMP-017 §1; Solstice register RG-114
-- expect-output:
--   PAT picked end 1
--   PAT picked ask 7
--   9
--   5
--   12
--   3
--   0
--   30

type Step = Ask Int | End Bool | Stop

fn :: picked (Step, Int) => Int
      picked (End _, _) =  1
      picked (Ask n, _) =  n
      picked (Stop, k)  =  k

fn :: second (Int, Step) => Int
      second (k, Ask n) =  k + n
      second (k, End True) =  k
      second (_, _)     =  0

fn :: head ask [Step] => Int
      head ask (Ask n : _) =  n
      head ask _           =  0

fn :: both (Step, Step) => Int
      both (Ask a, Ask b) =  a * b
      both (_, _)         =  0

fn :: main => ()
      main =
        echo ("PAT picked end " + (int to str (picked (End True, 0))))
        echo ("PAT picked ask " + (int to str (picked (Ask 7, 0))))
        echo (int to str (picked (Stop, 9)))
        echo (int to str (second (2, Ask 3)))
        echo (int to str (head ask [Ask 12, Stop]))
        echo (int to str (second (3, End True)))
        echo (int to str (second (3, End False)))
        echo (int to str (both (Ask 5, Ask 6)))
