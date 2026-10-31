-- case: an unknown constructor in a pattern reports 'unknown constructor' instead of guessing Int for its payload (RG-106)
-- source: FR-COMP-005 (algebraic data types and pattern matching)
-- @tests TS-UNIT-001
-- expect-build-error: unknown constructor 'Nope' in pattern

type V = A Int | B String

fn :: x V => String
      x (Nope s) =  s
      x _        =  ""

fn :: main => ()
      main =  echo (x (B "1"))
