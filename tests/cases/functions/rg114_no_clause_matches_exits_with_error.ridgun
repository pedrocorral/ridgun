-- @tests TS-COMP-017
-- case: a call that matches no clause stops with a runtime error and exit status 1 instead of returning the zero value (RG-114)
-- source: FR-COMP-017 §2; Solstice register RG-114
-- expect-output:
--   before
--   runtime error: no clause of function 'only_one' matches its arguments
-- expect-exit: 1

fn :: only one Int => Int
      only one 1 =  10

fn :: main => ()
      main =
        echo "before"
        echo (int to str (only one 2))
        echo "after"
