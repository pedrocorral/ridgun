-- case: a self tail call runs 100 000 000 times in constant stack (and memory)
-- source: book 04:174-181 ("sum_fast_loop 100_000_000 0 … will consume exactly 0 extra bytes of stack"); FR-COMP-004 (TCO)
-- expect-output:
--   5000000050000000
-- max-rss-mb: 64
-- max-ms: 20000

fn :: sum fast loop Int Int => Int
      sum fast loop 0 acc =  acc
      sum fast loop n acc =  sum fast loop (n - 1) (acc + n)

fn :: main => ()
      main =  echo (int to str (sum fast loop 100000000 0))
