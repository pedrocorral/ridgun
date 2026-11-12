-- @tests TS-COMP-016
-- case: str_to_int returns every 64-bit Int, keeps its parsing rules, and gives 0 for invalid or out-of-range text, also when passed to map (RG-113)
-- source: tutorials.md:168; FR-COMP-016 §4; Solstice register RG-113
-- expect-output:
--   9223372036854775807
--   9223372036854775806
--   -9223372036854775808
--   1234567890123456789
--   4611686018427387904
--   -4611686018427387905
--   9223372036854775807
--   9223372036854775807
--   -9223372036854775808
--   0
--   0
--   0
--   42
--   0
--   [9223372036854775807, -9223372036854775807]

fn :: main => ()
      main =
        echo (int to str (str to int "9223372036854775807"))
        echo (int to str (str to int "9223372036854775806"))
        echo (int to str (str to int "-9223372036854775808"))
        echo (int to str (str to int "1234567890123456789"))
        echo (int to str (str to int "4611686018427387904"))
        echo (int to str (str to int "-4611686018427387905"))
        echo (int to str (str to int "  9_223_372_036_854_775_807  "))
        echo (int to str (str to int "0x7FFFFFFFFFFFFFFF"))
        echo (int to str (str to int "0x-8000000000000000"))
        echo (int to str (str to int "9223372036854775808"))
        echo (int to str (str to int "-9223372036854775809"))
        echo (int to str (str to int "99999999999999999999"))
        echo (int to str (str to int " 42 "))
        echo (int to str (str to int "12abc"))
        ["9223372036854775807", "-9223372036854775807"] map str to int -> echo
