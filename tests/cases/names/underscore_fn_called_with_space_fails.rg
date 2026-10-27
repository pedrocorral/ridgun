-- case: calling "report build status" when fn :: report_build_status is declared fails (" " != "_")
-- source: FR-COMP-005 §5 (" " and "_" are distinct in function names in all compilation modes)
-- no-strict
-- expect-build-error: undefined function

fn :: report_build_status String Int => ()
      report_build_status input_path 0 =
        echo ("ok: " + input_path)
      report_build_status _ _ =
        echo "failed"

fn :: main => ()
      main =
        report build status "app.rg" 0
