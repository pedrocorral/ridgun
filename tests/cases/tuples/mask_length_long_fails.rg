-- case: a 5-position sequence mask (+ + + + +) on a 4-tuple (10, 11, 12, 13) is rejected at compile time
-- source: FR-COMP-008 §3 and FR-COMP-014 §3 (sequence masks must match tuple arity)
-- expect-build-error: sequence mask has 5 position(s), expected 4

fn :: main => ()
      main =
        t = (10, 11, 12, 13) -> (+ + + + +)
        echo "unreachable"
