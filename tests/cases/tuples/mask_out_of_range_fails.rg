-- case: an out-of-range sequence mask (+ _ _ _ _ +) on a 4-tuple (10, 11, 12, 13) piped to Int Int is rejected at compile time
-- source: FR-COMP-008 §3 and FR-COMP-014 §3 (sequence masks must match tuple arity and preserve element types)
-- expect-build-error: sequence mask has 6 position(s), expected 4

fn :: print two Int Int => ()
      print two a   b   =
        echo ("a=" + (int to str a) + " b=" + (int to str b))

fn :: main => ()
      main =
        (10, 11, 12, 13) -> (+ _ _ _ _ +) -> print two
