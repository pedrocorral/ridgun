-- @tests TS-COMP-020
-- case: a tensor literal of Reals keeps its values, and echo or string interpolation shows every numeric tensor (variable, function result, slice) with its element type
-- source: spec.md "Tensors" (element typing, showing); FR-COMP-020 §2, §10
-- expect-output:
--   Tensor(shape=[3], data=[1.5, 2.5, 0.75])
--   0.75
--   4.75
--   Tensor(shape=[2, 2], data=[1.5, 2.0, 3.25, -4.0])
--   row = Tensor(shape=[2], data=[3.25, -4.0])
--   Tensor(shape=[2, 3], data=[7, 7, 7, 7, 7, 7])
--   Tensor(shape=[2], data=[7, 7])
--   Tensor(shape=[2], data=[0.5, 0.5])
--   Tensor(shape=[3], data=[1, 2, 3])

fn :: total Tensor[Real * 3] => Real
      total v =  v_(0) + v_(1) + v_(2)

fn :: halves Int => Tensor[Real * n]
      halves n =  Tensor[Real * n] with 0.5

fn :: main => ()
      main =
        x = 0.75
        a = Tensor [1.5, 2.5, x]
        echo a
        echo a_(2)
        echo (total a)
        m = Tensor [[1.5, 2.0], [3.25, -4.0]]
        echo m
        echo "row = {m_(1,)}"
        n = Tensor[Int * 2 * 3] with 7
        echo n
        echo n_(,2)
        echo (halves 2)
        echo (Tensor [1, 2, 3])
