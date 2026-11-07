-- @tests TS-COMP-016
-- case: a decimal literal above the Int maximum is a compile error instead of a silently wrapped value (RG-113)
-- source: FR-COMP-016 §2; Solstice register RG-113
-- expect-build-error: integer literal '9223372036854775808' is out of range for Int

fn :: main => ()
      main =  echo (int to str 9223372036854775808)
