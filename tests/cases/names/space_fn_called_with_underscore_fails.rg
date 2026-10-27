-- case: calling report_build_status when fn :: report build status is declared fails even without --strict (" " != "_")
-- source: FR-COMP-005 §5 (" " and "_" are distinct in function names in all compilation modes)
-- no-strict
-- expect-build-error: undefined function 'report_build_status'

fn :: report build status String Int => ()
      report build status input_path 0 =
        echo ("ok: " + input_path)
      report build status _ _ =
        echo "failed"

fn :: main => ()
      main =
        report_build_status "app.rg" 0
