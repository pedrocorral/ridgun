-- @tests TS-COMP-021
-- case: sort by ints and sort by texts with a key list of a different length stop the program with a runtime error and exit status 1
-- source: spec.md "Lists" (sort by ints, sort by texts); FR-COMP-021
-- expect-output:
--   [1, 2]
--   runtime error: sort by: the lists have different lengths
-- expect-exit: 1

fn :: main => ()
      main =
        echo (sort by ints [2, 1] [2, 1])
        echo (sort by texts ["a", "b", "c"] ["x", "y"])
