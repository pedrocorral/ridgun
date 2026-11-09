-- @tests TS-COMP-011
-- case: 10 000 000 record field reads, 10 000 000 calls to a small function that matches its record parameter, and 10 000 000 turns of an empty self tail call loop stay under the limit
-- source: TASK-0059; FR-COMP-011 item 7 (OPT-015..OPT-018); libs report 2026-11-08 (hashmap-tensores-y-campos, point 5: about 1.2 s on 0.9.45)
-- expect-output:
--   30000000 30000000 49999995000000
-- max-ms: 400

type R = ra: Int, rb: String, rc: [Int]

fn :: by field R Int Int Int => Int
      by field r j total acc =
        | j >= total = acc
        | otherwise = by field r (j + 1) total (acc + ra r)

fn :: get a R => Int
      get a (R a _ _) = a

fn :: by pattern R Int Int Int => Int
      by pattern r j total acc =
        | j >= total = acc
        | otherwise = by pattern r (j + 1) total (acc + get a r)

fn :: empty Int Int Int => Int
      empty j total acc =
        | j >= total = acc
        | otherwise = empty (j + 1) total (acc + j)

fn :: main => ()
      main =
        r = R 3 "x" [1, 2]
        n = 10000000
        echo "{by field r 0 n 0} {by pattern r 0 n 0} {empty 0 n 0}"
