-- @tests TS-COMP-020
-- case: an element of a Real tensor is a Real (it prints as a number and takes part in Real arithmetic), through a parameter, a return value and two indices; Int tensors keep Int elements
-- source: spec.md "Tensors"; FR-COMP-020 §2
-- expect-output:
--   2.5
--   -1.25
--   3.5
--   2.5
--   3.75
--   0.0
--   8

fn :: first of Tensor[Real * n] => Real
      first of t =  t_(0)

fn :: make reals => Tensor[Real * 2]
      make reals =
        r = Tensor[Real * 2]
        r_(0) = 2.5
        r_(1) = -1.25
        r

fn :: main => ()
      main =
        r = (make reals)
        echo r_(0)
        echo r_(1)
        echo (r_(0) + 1.0)
        echo (first of r)
        m = Tensor[Real * 2 * 2]
        m_(1, 1) = 3.75
        echo m_(1, 1)
        echo m_(0, 0)
        i = Tensor[Int * 2]
        i_(0) = 7
        echo (i_(0) + 1)
