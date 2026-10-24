-- case: 8 agents doing 8 equal CPU-bound jobs at once take no longer than one thread doing them one after another
-- source: no promise in the docs (proposal): FR-COMP-009 §6 leaves parallel execution to the analyser. Solstice
--   register RG-079 measured 8 agents at once 8× slower in total; the compiler team's TASK-0024 reports 101 ms in
--   parallel against 144 ms serial after sharding the allocator. Needs more than one core.
-- expect-output:
--   same results: True
--   parallel not slower: True
-- kind: proposal
-- uses-libs

import posix

fn :: fib Int => Int
      fib n =
        | n < 2     = n
        | otherwise = (fib (n - 1)) + (fib (n - 2))

fn :: bool text Bool => String
      bool text True  =  "True"
      bool text False =  "False"

fn :: main => ()
      main =
        t0 = sys_monotonic_ms
        serial = (fib 25) + (fib 25) + (fib 25) + (fib 25) + (fib 25) + (fib 25) + (fib 25) + (fib 25)
        t1 = sys_monotonic_ms
        a1 = agent (fib)
        a2 = agent (fib)
        a3 = agent (fib)
        a4 = agent (fib)
        a5 = agent (fib)
        a6 = agent (fib)
        a7 = agent (fib)
        a8 = agent (fib)
        send 25 to a1
        send 25 to a2
        send 25 to a3
        send 25 to a4
        send 25 to a5
        send 25 to a6
        send 25 to a7
        send 25 to a8
        par = (receive from a1) + (receive from a2) + (receive from a3) + (receive from a4) + (receive from a5) + (receive from a6) + (receive from a7) + (receive from a8)
        t2 = sys_monotonic_ms
        _ = echo ("same results: " + (bool_text (par == serial)))
        echo ("parallel not slower: " + (bool_text ((t2 - t1) <= (t1 - t0) + 20)))
