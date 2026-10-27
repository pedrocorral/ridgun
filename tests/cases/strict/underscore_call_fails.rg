-- case: --strict refuses "_" in a function call even when the function was declared with spaces
-- source: FR-COMP-005 §5 (--strict forbids "_" in function declarations and calls; " " != "_")
-- expect-build-error: strict mode

fn :: report build status String Int => ()
      report build status input_path 0 =
        echo ("ok: " + input_path)
      report build status _ _ =
        echo "failed"

fn :: main => ()
      main =
        report_build_status "app.rg" 0
