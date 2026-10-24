-- case: a stateful agent (S M => S and S M => S R) keeps its state across messages; ask answers synchronously
-- source: FR-COMP-009 §1-§2 and AC-2 (ask in both styles)
-- expect-output:
--   15
--   22
--   30
--   42
--   hits 1
--   hits 2

fn :: add visit Int Int => Int
      add visit total n =  total + n

type Counter = hits: Int

fn :: hit Counter String => Counter String
      hit c _ =
        c2 = (c with hits = (hits c) + 1)
        (c2, "hits " + (int_to_str (hits c2)))

fn :: main => ()
      main =
        acc = agent (add visit) 10
        send 5 to acc
        _ = echo (int_to_str (receive from acc))
        send 7 to acc
        _ = echo (int_to_str (receive from acc))
        _ = echo (int_to_str (ask acc 8))
        _ = echo (int_to_str (ask 12 to acc))
        stop acc
        ctr = agent (hit) (Counter 0)
        _ = echo (ask ctr "a")
        echo (ask ctr "b")
