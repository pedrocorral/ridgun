-- case: a stateless agent answers single and multi-argument messages in FIFO order
-- source: FR-COMP-009 §1-§3 and AC-1
-- expect-output:
--   9
--   16
--   25
--   7
--   12

fn :: square Int => Int
      square x =  x * x

fn :: add Int Int => Int
      add a b =  a + b

fn :: main => ()
      main =
        sq = agent (square)
        send 3 to sq
        send 4 to sq
        send 5 to sq
        echo (int to str (receive from sq))
        echo (int to str (receive from sq))
        echo (int to str (receive from sq))
        ad = agent (add)
        send 3 4 to ad
        send 5 7 to ad
        echo (int to str (receive from ad))
        echo (int to str (receive from ad))
