-- @tests TS-COMP-020
-- case: reading a numeric tensor of three dimensions outside its shape stops the program with a runtime error and exit status 1 instead of returning 0
-- source: spec.md "Tensors" (index out of range); FR-COMP-020 §8
-- expect-output:
--   7
--   runtime error: tensor index out of range
-- expect-exit: 1

fn :: main => ()
      main =
        t = Tensor[Int * 2 * 2 * 2] with 7
        echo t_(1, 1, 1)
        echo t_(1, 2, 0)
        echo "not reached"
