-- case: `global ::` was removed in 0.9.18 and must not compile
-- source: FR-COMP-009 §5 ("SHALL be removed from the language"); road-map TASK-0023
-- expect-build-error:

global :: counter Int = 0

fn :: main => ()
      main =  echo "built"
