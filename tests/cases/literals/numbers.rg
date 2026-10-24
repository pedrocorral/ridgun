-- case: Int literal forms: negative, hexadecimal, digit separators and the _KB/_MB/_GB suffixes
-- source: book 03:67 (-100, 0xFF00, 1_000_000), book 03:87-98 (64_KB = 65536, 16_MB = 16777216, 0xFF_00)
-- expect-output:
--   -100
--   65280
--   1000000
--   65536
--   16777216
--   65280
--   1073741824

fn :: main => ()
      main =
        _ = echo (int_to_str (-100))
        _ = echo (int_to_str 0xFF00)
        _ = echo (int_to_str 1_000_000)
        _ = echo (int_to_str 64_KB)
        _ = echo (int_to_str 16_MB)
        _ = echo (int_to_str 0xFF_00)
        echo (int_to_str 1_GB)
