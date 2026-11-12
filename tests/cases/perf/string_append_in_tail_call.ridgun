-- @tests TS-COMP-011
-- case: building a String with `acc + x` in a self tail call is linear: the last use of `acc` is moved and appended to in place when it has one owner, with a buffer that doubles (Solstice, 2026-11-10: 100 000 appends took 2.3 s); a String that is still shared is never changed; chains `acc + sep + x` append too; freed buffers are reused (200 rounds of a 1 MB String stay small)
-- source: TASK-0068; FR-COMP-011; docs/etc/compiler_optimizations.md OPT-020
-- expect-output:
--   1000000 ababab
--   x xyyy
--   [a, ab, abb, abbb]
--   , p, q, r
--   hi!! hi!!? hi!!
--   5050
--   200 1000000
-- max-ms: 3000
-- max-rss-mb: 64

fn :: rep String Int String => String
      rep x n acc =
        | n <= 0    = acc
        | otherwise = rep x (n - 1) (acc + x)

fn :: keep both String Int [String] => [String]
      keep both acc n seen =
        | n <= 0    = seen :: [acc]
        | otherwise = keep both (acc + "b") (n - 1) (seen :: [acc])

fn :: join with String [String] String => String
      join with sep (x:xs) acc = join with sep xs (acc + sep + x)
      join with _ [] acc = acc

fn :: sum to Int Int => Int
      sum to n acc =
        | n <= 0    = acc
        | otherwise = sum to (n - 1) (acc + n)

fn :: rounds Int Int => Int
      rounds k last =
        | k <= 0    = last
        | otherwise = rounds (k - 1) (str len (rep "abcdefgh" 125000 ""))

fn :: main => ()
      main =
        s = rep "ab" 500000 ""
        echo (str len s) (str slice s 0 6)
        base = "x"
        echo base (rep "y" 3 base)
        echo (keep both "a" 3 [])
        echo (join with ", " ["p", "q", "r"] "")
        lit = rep "!" 2 "hi"
        echo lit (rep "?" 1 lit) lit
        echo (sum to 100 0)
        echo 200 (rounds 200 0)
