-- @tests TS-COMP-020
-- case: the value after 'with' must have the element type of the tensor
-- source: spec.md "Tensors" (initial values); FR-COMP-020 §6
-- expect-build-error: cannot fill a tensor of Real with Int

fn :: main => ()
      main =
        t = Tensor[Real * 2] with 1
        echo "unreachable"
