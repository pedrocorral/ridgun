-- @tests TS-COMP-022
-- case: crc32 range over 100 MB of a Tensor[U8], 1 000 000 conversions of 4 bytes to a String and 10 000 000 byte reads stay under the limit
-- source: FR-COMP-022 §9 (crc32 range 100 MB under 0.5 s; tensor to str of 4 bytes 1 000 000 times under 1 s)
-- expect-output:
--   557995341 4000000 0
-- max-ms: 1500

fn :: crc loop Tensor[U8] Int Int => Int
      crc loop t i acc
        | i >= 10 = acc
        | otherwise = crc loop t (i + 1) (crc32 range t 0 10000000 acc)

fn :: str loop Tensor[U8] Int Int => Int
      str loop t i acc
        | i >= 1000000 = acc
        | otherwise = str loop t (i + 1) (acc + (str len (tensor to str t)))

fn :: read loop Tensor[U8] Int Int => Int
      read loop t i acc
        | i >= 10000000 = acc
        | otherwise = read loop t (i + 1) (acc + t_(i))

fn :: main => ()
      main =
        big = Tensor[U8 * 10000000]
        c = crc loop big 0 0
        n = str loop (tensor from str "abcd") 0 0
        r = read loop big 0 0
        echo "{c} {n} {r}"
