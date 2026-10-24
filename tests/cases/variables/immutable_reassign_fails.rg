-- case: reassigning a variable that wasn't declared mut is a compile error
-- source: FR-COMP-003 §4 ("SHALL be rejected at compile time") and AC3; spec.md:679
-- expect-build-error:

fn :: main => ()
      main =
        x = 1
        x = 2
        echo (int_to_str x)
