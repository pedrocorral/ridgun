-- case: a local binding whose value is a guard block, then a final expression (FR-COMP-003 Case 2)
-- source: FR-COMP-003 §2 (compute_invoice)
-- expect-output:
--   80
--   90
--   40

fn :: compute invoice Int Bool => Int
      compute invoice base is_vip =
        discount =
          | is_vip    = 20
          | base > 50 = 10
          | otherwise = 0
        base - discount

fn :: main => ()
      main =
        echo (int to str (compute invoice 100 True))
        echo (int to str (compute invoice 100 False))
        echo (int to str (compute invoice 40 False))
