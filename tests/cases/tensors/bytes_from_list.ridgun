-- @tests TS-COMP-022
-- case: tensor u8 from list makes a Tensor[U8] with the given bytes in one allocation (libs report tensor-u8, 2026-11-09)
-- source: FR-COMP-022 §3
-- expect-output:
--   137 71 4
--   [137, 80, 78, 71]
--   1542176421
--   0
--   True

fn :: first byte Tensor[U8] => Int
      first byte t = t_(0)

fn :: main => ()
      main =
        png = tensor u8 from list [137, 80, 78, 71]
        echo (first byte png) png_(3) (tensor to str png -> str len)
        echo (tensor to list png)
        echo (crc32 range png 0 4 0)
        e = tensor u8 from list []
        echo (crc32 range e 0 0 0)
        echo (png == (tensor u8 from list [137, 80, 78, 71]))
