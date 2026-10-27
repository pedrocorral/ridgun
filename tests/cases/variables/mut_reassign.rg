-- case: mut x = …, then x = … in the same scope, updates x
-- source: FR-COMP-003 §4 and AC3; spec.md:674-695
-- expect-output:
--   1
--   3
--   done 6

fn :: main => ()
      main =
        mut x = 1
        echo (int to str x)
        x = x + 2
        echo (int to str x)
        x = x * 2
        echo ("done " + (int to str x))
