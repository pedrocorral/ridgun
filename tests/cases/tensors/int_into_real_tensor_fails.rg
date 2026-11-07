-- @tests TS-COMP-020
-- case: storing an Int in an element of a Real tensor is a compile error, so the declared element type is respected
-- source: spec.md "Tensors"; FR-COMP-020 §2
-- expect-build-error: cannot store Int in an element of tensor 'r' of Real

fn :: main => ()
      main =
        r = Tensor[Real * 2]
        r_(0) = 1
        echo r_(0)
