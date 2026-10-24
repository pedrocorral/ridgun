-- case: 50 000 send/receive round trips on one stateless agent keep memory flat
-- source: FR-COMP-002 (RMM: "leak-free", deterministic release, FR-COMP-002:24) and FR-COMP-009 §4 (agents release their values);
--   Solstice register RG-069 measured 0.56 KB kept per message (RSS 4.2 MB → 32.9 MB for 50 000)
-- expect-output:
--   1250025000
-- max-rss-mb: 16

fn :: identity Int => Int
      identity x =  x

fn :: pump (Agent Int Int) Int Int => Int
      pump ag i acc =
        | i > 50000 = acc
        | otherwise = pump ag (i + 1) (acc + (ask ag i))

fn :: main => ()
      main =
        ag = agent (identity)
        echo (int_to_str (pump ag 1 0))
