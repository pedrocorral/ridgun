-- case: `spawn` / `join` were removed and must not compile
-- source: FR-COMP-009 §5 and AC-4
-- expect-build-error:

fn :: work Int => Int
      work x =  x + 1

fn :: main => ()
      main =
        h = spawn (work 1)
        echo (int_to_str (join h))
