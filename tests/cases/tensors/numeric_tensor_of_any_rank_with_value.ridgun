-- @tests TS-COMP-020
-- case: a numeric tensor with three or four dimensions keeps its whole shape, starts at zero or at the value given with 'with', and keeps writes to its last element
-- source: spec.md "Tensors" (initial values); FR-COMP-020 §6
-- expect-output:
--   Tensor(shape=[2, 3, 4], data=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
--   5
--   3
--   0.5

fn :: main => ()
      main =
        zeros = Tensor[Int * 2 * 3 * 4]
        echo zeros
        big = Tensor[Int * 40 * 40 * 40 * 40] with 3
        big_(39, 39, 39, 39) = 5
        echo big_(39, 39, 39, 39)
        echo big_(0, 1, 2, 3)
        halves = Tensor[Real * 2 * 2 * 2] with 0.5
        echo halves_(1, 1, 1)
