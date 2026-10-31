-- case: a local variable bound via -> with the same name as a record field is treated as a local binding when referenced in subsequent statements
-- source: FR-COMP-014 (pipeline local variable binding) and FR-COMP-005 (record field accessors)
-- @tests TS-UNIT-001
-- expect-output:
--   4

type Plan = target: Int, other: Int

fn :: look String => Int
      look s =  str len s

fn :: use local String => Int
      use local s =
        look s -> target
        target + 1

fn :: main => ()
      main =  echo (int to str (use local "abc"))
