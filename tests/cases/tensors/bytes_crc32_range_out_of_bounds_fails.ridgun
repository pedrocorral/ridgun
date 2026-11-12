-- @tests TS-COMP-022
-- case: crc32 range outside the data stops the program with a runtime error and exit status 1
-- source: FR-COMP-022 §8
-- expect-output:
--   891568578
--   runtime error: crc32 range: range out of bounds
-- expect-exit: 1

fn :: main => ()
      main =
        echo (crc32 range "abc" 0 3 0)
        echo (crc32 range "abc" 2 4 0)
