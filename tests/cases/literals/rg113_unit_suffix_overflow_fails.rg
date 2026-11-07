-- @tests TS-COMP-016
-- case: a unit suffix that pushes a literal above the Int maximum is a compile error (RG-113)
-- source: FR-COMP-016 §2; Solstice register RG-113
-- expect-build-error: integer literal '9000000000_GB' is out of range for Int

fn :: main => ()
      main =  echo (int to str 9000000000_GB)
