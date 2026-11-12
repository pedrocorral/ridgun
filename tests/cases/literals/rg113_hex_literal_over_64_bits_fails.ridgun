-- @tests TS-COMP-016
-- case: a hexadecimal literal with more than 16 significant digits is a compile error (RG-113)
-- source: FR-COMP-016 §3; Solstice register RG-113
-- expect-build-error: integer literal '0x1_0000_0000_0000_0000' is out of range for Int

fn :: main => ()
      main =  echo (int to str 0x1_0000_0000_0000_0000)
