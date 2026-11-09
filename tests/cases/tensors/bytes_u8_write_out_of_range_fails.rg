-- @tests TS-COMP-022
-- case: writing an Int outside 0..255 to a Tensor[U8] element stops the program with a runtime error and exit status 1
-- source: FR-COMP-022 §2
-- expect-output:
--   1
--   runtime error: U8 element out of 0..255
-- expect-exit: 1

fn :: main => ()
      main =
        t = Tensor[U8 * 2]
        t_(0) = 1
        echo t_(0)
        t_(1) = 256
        echo "unreachable"
