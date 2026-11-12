-- @tests TS-COMP-021
-- case: sort by ints and sort by texts each order 100 000 pseudo-random elements, and the whole program (building the lists included) stays under the limit
-- source: FR-COMP-021 (100 000 Int keys in under 100 ms); libs request 2026-11-07 (agrupar-contar-ordenar-primitivas)
-- expect-output:
--   True True
-- max-ms: 1000

fn :: gen ints Int Int Int [Int] => [Int]
      gen ints i n seed acc
        | i >= n = acc
        | otherwise = gen ints (i + 1) n ((seed * 1103515245 + 12345) % 2147483648) ([seed] :: acc)

fn :: gen strs [Int] [String] => [String]
      gen strs [] acc =  acc
      gen strs (x:xs) acc =  gen strs xs ([int to str x] :: acc)

fn :: ints ordered [Int] => Bool
      ints ordered (a:b:rest) =  (a <= b) and (ints ordered (b:rest))
      ints ordered _ =  True

fn :: texts ordered [String] => Bool
      texts ordered (a:b:rest) =  (not (b < a)) and (texts ordered (b:rest))
      texts ordered _ =  True

fn :: main => ()
      main =
        xs = gen ints 0 100000 42 []
        ss = gen strs xs []
        si = sort by ints xs xs
        st = sort by texts ss ss
        echo "{ints ordered si} {texts ordered st}"
