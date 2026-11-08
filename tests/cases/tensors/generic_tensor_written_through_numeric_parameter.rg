-- @tests TS-COMP-020
-- case: a tensor made by a generic function (Tensor[V * n] with v) keeps writes made through a Tensor[Int] or Tensor[Real] parameter, as well as writes through a generic parameter, and a numeric tensor keeps writes made through a generic parameter
-- source: spec.md "Tensors" (writes in place, tensors passed by reference); FR-COMP-020 §5; libs report 2026-11-08 (hashmap-tensores-y-campos, point 2)
-- expect-output:
--   42
--   43
--   44
--   7.25
--   0.5

fn :: mk V Int => Tensor[V * n]
      mk v c = Tensor[V * c] with v

fn :: wr int Tensor[Int * n] Int Int => ()
      wr int t i v =
        t_(i) = v

fn :: wr real Tensor[Real * n] Int Real => ()
      wr real t i v =
        t_(i) = v

fn :: wr gen Tensor[V * n] Int V => ()
      wr gen t i v =
        t_(i) = v

fn :: rd gen Tensor[V * n] Int => V
      rd gen t i = t_(i)

fn :: main => ()
      main =
        t = mk 7 4
        wr int t 1 42
        echo (rd gen t 1)
        wr gen t 2 43
        echo (rd gen t 2)
        u = Tensor[Int * 4]
        wr gen u 0 44
        echo u_(0)
        g = mk 0.5 3
        wr real g 1 7.25
        echo (rd gen g 1)
        echo (rd gen g 0)
