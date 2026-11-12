-- case: functions declared with => () automatically discard a non-() final expression value without requiring -> ()
-- source: FR-COMP-014 §4 (automatic unit return discarding on => () functions)
-- expect-output:
--   side-effect: 21
--   done: 0

fn :: compute and log Int => ()
      compute and log x   =
        echo ("side-effect: " + (int to str x))
        "discarded-heap-string-" + (int to str (x * 2))

fn :: main => ()
      main =
        base = cmm live blocks
        compute and log 21
        leaked = (cmm live blocks) - base
        echo ("done: " + (int to str leaked))
