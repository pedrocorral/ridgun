-- @tests TS-COMP-020
-- case: a column slice and a column write outside a numeric matrix stop the program with a runtime error and exit status 1 instead of reading or writing past the tensor
-- source: spec.md "Tensors" (index out of range); FR-COMP-020 §8
-- expect-output:
--   Tensor(shape=[2], data=[7, 7])
--   runtime error: tensor index out of range
-- expect-exit: 1

fn :: main => ()
      main =
        m = Tensor[Int * 2 * 3] with 7
        echo m_(,2)
        c = Tensor[Int * 2] with 1
        m_(,3) = c
        echo "not reached"
