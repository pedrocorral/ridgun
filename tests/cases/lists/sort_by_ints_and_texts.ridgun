-- @tests TS-COMP-021
-- case: sort by ints and sort by texts return the elements ordered by their keys, keep equal keys in input order, order texts like < (bytes, prefix first), and work on empty, one-element, record and run-time-built lists
-- source: spec.md "Lists" (sort by ints, sort by texts); FR-COMP-021
-- expect-output:
--   [1, 2, 3]
--   [a, a2, b, c]
--   [, Z, a, ab, b, z, é]
--   True
--   []
--   [5]
--   [y, x, z]
--   [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
--   [-9223372036854775807, -5, 0, 9223372036854775807]
--   [/src/abcdefghijklmnopq09, /src/abcdefghijklmnopq1, /src/abcdefghijklmnopq10]
--   [3, 2, 1]
--   [one, two, three]

type Visit = Visit String Int

fn :: name Visit => String
      name (Visit s _) =  s

fn :: digits Int Int [Int] => [Int]
      digits i n acc
        | i >= n = acc
        | otherwise = digits (i + 1) n ([(i * 7) % 10] :: acc)

fn :: ordered [String] => Bool
      ordered (a:b:rest) =  (not (b < a)) and (ordered (b:rest))
      ordered _ =  True

fn :: tail of [Int] => [Int]
      tail of (_:xs) =  xs
      tail of [] =  []

fn :: main => ()
      main =
        echo (sort by ints [3, 1, 2] [3, 1, 2])
        echo (sort by ints ["c", "a", "b", "a2"] [3, 1, 2, 1])
        ws = ["b", "ab", "a", "", "Z", "é", "z"]
        sw = sort by texts ws ws
        echo sw
        echo (ordered sw)
        echo (sort by ints [] [])
        echo (sort by ints [5] [5])
        vs = [Visit "x" 2, Visit "y" 1, Visit "z" 2]
        echo ((sort by ints vs [2, 1, 2]) map name)
        ds = digits 0 10 []
        echo (sort by ints ds ds)
        echo (sort by ints [0 - 5, 9223372036854775807, 0, 0 - 9223372036854775807] [0 - 5, 9223372036854775807, 0, 0 - 9223372036854775807])
        long = ["/src/abcdefghijklmnopq10", "/src/abcdefghijklmnopq1", "/src/abcdefghijklmnopq09"]
        echo (sort by texts long long)
        t = tail of [9, 1, 2, 3]
        echo (sort by ints t [3, 2, 1])
        echo (sort by texts ["one", "two", "three"] ["a", "b", "c"])
