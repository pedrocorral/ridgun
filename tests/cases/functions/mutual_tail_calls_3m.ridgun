-- @tests TS-COMP-011
-- case: calls in tail position between different functions reuse the frame: a pair that passes a fresh tuple runs 3 000 000 rounds, a pair of unit functions 3 000 000 rounds, and a ring of three functions with different frame sizes that carries a string 1 000 000 times round, all in small constant memory (before OPT-019 each round kept a frame, about 200 bytes, and 3 000 000 rounds crashed)
-- source: TASK-0061; FR-COMP-004 (TCO); docs/etc/compiler_optimizations.md OPT-019 and "Rule: tail calls stay last"
-- expect-output:
--   4499998500000
--   9000000
--   1000000 ring
-- max-rss-mb: 64
-- max-ms: 15000

fn :: step tuple (Int, Int) Int => Int
      step tuple (i, acc) n = loop tuple (i + 1) (acc + i) n

fn :: loop tuple Int Int Int => Int
      loop tuple i acc n
        | i >= n = acc
        | otherwise = step tuple (i, acc) n

fn :: ping Int Int => ()
      ping 0 k = echo (int to str k)
      ping n k = pong (n - 1) (k + 1)

fn :: pong Int Int => ()
      pong n k = ping n (k + 2)

fn :: ring a Int Int String => String
      ring a 0 k s = (int to str k) + " " + s
      ring a n k s = ring b (n - 1) (k + 1) s

fn :: ring b Int Int String => String
      ring b n k s =
        x = n * 2
        y = x + k
        z = y - x
        w = z + 0
        ring c n w s

fn :: ring c Int Int String => String
      ring c n k s = ring a n k s

fn :: main => ()
      main =
        echo (int to str (loop tuple 0 0 3000000))
        ping 3000000 0
        echo (ring a 1000000 0 "ring")
