-- case: mut x = …, then x = … in the same scope, updates x
-- source: FR-COMP-003 §4 and AC3; spec.md:674-695
-- expect-output:
--   1
--   3
--   done 6

fn :: main => ()
      main =
        mut x = 1
        _ = echo (int_to_str x)
        x = x + 2
        _ = echo (int_to_str x)
        x = x * 2
        echo ("done " + (int_to_str x))
