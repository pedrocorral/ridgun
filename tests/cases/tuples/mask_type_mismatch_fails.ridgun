-- case: a sequence mask (+ + _ _) selecting (Int, String) from a 4-tuple and piping into Int Int fails type checking
-- source: FR-COMP-008 §3 and FR-COMP-014 §3 (sequence masks preserve selected element types)
-- expect-build-error: has type String, expected Int

fn :: print two Int Int => ()
      print two a   b   =
        echo ("a=" + (int to str a) + " b=" + (int to str b))

fn :: main => ()
      main =
        (10, "hola", 12, 13) -> (+ + _ _) -> print two
