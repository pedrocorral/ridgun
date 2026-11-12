-- case: a guarded mixfix operator clause (= before |), as in FR-COMP-003 Case 1
-- source: FR-COMP-003 §1 (docs/requirements/functional/compiler/FR-COMP-003-*.md, Case 1)
-- expect-output:
--   0
--   10
--   5

op :: clamp Int between Int and Int => Int
      clamp x between lo and hi =
        | x < lo    = lo
        | x > hi    = hi
        | otherwise = x

fn :: main => ()
      main =
        echo (int to str (clamp (0 - 3) between 0 and 10))
        echo (int to str (clamp 42 between 0 and 10))
        echo (int to str (clamp 5 between 0 and 10))
