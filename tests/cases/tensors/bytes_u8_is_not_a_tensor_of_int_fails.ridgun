-- @tests TS-COMP-022
-- case: a Tensor[U8] cannot be passed where a Tensor[Int] is expected, because its elements are packed bytes
-- source: FR-COMP-022 §1
-- expect-build-error: has type Tensor[U8], expected Tensor[Int]

fn :: first Tensor[Int] => Int
      first t =  t_(0)

fn :: main => ()
      main =
        t = Tensor[U8 * 2]
        echo (first t)
