-- @tests TS-COMP-022
-- case: tensor u8 from list stops the program when a value is outside 0..255, as an element write does
-- source: FR-COMP-022 §2, §3
-- expect-output:
--   runtime error: U8 element out of 0..255
-- expect-exit: 1

fn :: main => ()
      main =
        t = tensor u8 from list [1, 2, 256]
        echo "unreachable"
