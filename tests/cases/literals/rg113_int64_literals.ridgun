-- @tests TS-COMP-016
-- case: Int literals keep all 64 bits: values from 2^62 up, the Int maximum, the Int minimum written with a unary minus, hex bit patterns and literal patterns (RG-113)
-- source: tutorials.md:168 ("Int - 64-bit integers"); FR-COMP-016 §1-§3; Solstice register RG-113
-- expect-output:
--   4611686018427387903
--   4611686018427387904
--   9223372036854775807
--   9223372036854775806
--   -9223372036854775807
--   -9223372036854775808
--   -4611686018427387905
--   9223372036854775807
--   -9223372036854775808
--   -1
--   1
--   1
--   2
--   3
--   0

fn :: classify Int => Int
      classify 9223372036854775807  =  1
      classify -9223372036854775808 =  2
      classify 4611686018427387904  =  3
      classify _                    =  0

fn :: main => ()
      main =
        echo (int to str 4611686018427387903)
        echo (int to str 4611686018427387904)
        echo (int to str 9223372036854775807)
        echo (int to str (9223372036854775807 - 1))
        echo (int to str (-9223372036854775807))
        echo (int to str (-9223372036854775808))
        echo (int to str (-4611686018427387905))
        echo (int to str 0x7FFF_FFFF_FFFF_FFFF)
        echo (int to str 0x8000000000000000)
        echo (int to str 0xFFFFFFFFFFFFFFFF)
        big = 9_223_372_036_854_775_807
        echo (int to str (big - 9223372036854775806))
        echo (int to str (classify 9223372036854775807))
        echo (int to str (classify (-9223372036854775808)))
        echo (int to str (classify 4611686018427387904))
        echo (int to str (classify 4611686018427387903))
