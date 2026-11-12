-- @tests TS-COMP-016
-- case: 9223372036854775808 is valid only with a unary minus; after a binary minus it is out of range (RG-113)
-- source: FR-COMP-016 §2; Solstice register RG-113
-- expect-build-error: integer literal '9223372036854775808' is out of range for Int

fn :: main => ()
      main =  echo (int to str (0 - 9223372036854775808))
