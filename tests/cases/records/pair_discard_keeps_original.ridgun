-- case: discarding one part of a returned pair with `_` releases only that part; the record it was copied from keeps its lists, before and after a kept copy (compiler defect report 2026-11-11, item 1)
-- source: RMM1/RMM2 (a value is released once, by its last owner); FR-COMP-011
-- expect-output:
--   items id=1 open=True   kept id=1 open=True
--   names alpha   n 0 1
--   alone id=1 open=True 0
--   middle 1 3

type Ex  = ex_id: Int, ex_open: Bool
type Box = bx_items: [Ex], bx_names: [String], bx_n: Int

fn :: step Box => Box Int
      step b   =  (b with bx_n = (bx_n b) + 1, bx_n b)

fn :: three Box => Int Box Int
      three b  =  (1, b with bx_n = 9, 3)

fn :: show [Ex]    => String
      show []      =  "(empty)"
      show (e:_)   =  "id={ex_id e} open={ex_open e}"

fn :: first name [String] => String
      first name []    =  "(empty)"
      first name (s:_) =  s

fn :: main => ()
      main =
        a = Box [Ex 1 True] ["alpha"] 0
        k1, n1 = step a
        _, n2 = step a
        echo "items {show (bx_items a)}   kept {show (bx_items k1)}"
        echo "names {first name (bx_names a)}   n {n1} {bx_n k1}"
        b = Box [Ex 1 True] ["beta"] 0
        _, m = step b
        echo "alone {show (bx_items b)} {m}"
        x, _, z = three b
        echo "middle {x} {z}"
