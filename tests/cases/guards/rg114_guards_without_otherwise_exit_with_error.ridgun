-- @tests TS-COMP-017
-- case: when no guard of the last clause holds and there is no otherwise, the call stops with a runtime error and exit status 1 (RG-114)
-- source: FR-COMP-017 §2; Solstice register RG-114
-- expect-output:
--   1
--   before
--   runtime error: no clause of function 'sign' matches its arguments
-- expect-exit: 1

fn :: sign Int => Int
      sign n
        | n > 0 = 1
        | n < 0 = 0 - 1

fn :: main => ()
      main =
        echo (int to str (sign 5))
        echo "before"
        echo (int to str (sign 0))
        echo "after"
