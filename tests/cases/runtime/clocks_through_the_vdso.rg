-- @tests TS-COMP-023
-- case: sys time ns never goes backwards, sys time ms and sys wall time ms give plausible values, and 1 000 000 reads of each clock stay under the limit
-- source: FR-COMP-023 §1, §4 (1 000 000 calls under 200 ms each)
-- expect-output:
--   True
--   True
--   True
--   True
-- max-ms: 600

fn :: ns loop Int Int Bool => Bool
      ns loop i last ok
        | i >= 1000000 = ok
        | otherwise =
          now = sys time ns
          ns loop (i + 1) now (ok and now >= last)

fn :: ms loop Int Int => Int
      ms loop i acc
        | i >= 1000000 = acc
        | otherwise = ms loop (i + 1) (acc + (sys time ms) % 2)

fn :: wall loop Int Int => Int
      wall loop i acc
        | i >= 1000000 = acc
        | otherwise = wall loop (i + 1) (acc + (sys wall time ms) % 2)

fn :: main => ()
      main =
        echo (ns loop 0 0 True)
        echo ((sys time ms) > 0)
        echo ((sys wall time ms) > 1700000000000)
        k = (ms loop 0 0) + (wall loop 0 0)
        echo (k >= 0)
