-- @tests TS-COMP-020
-- case: allocating a tensor of an element type without a default value (a tuple) and without an initial value is a compile error
-- source: spec.md "Tensors" (initial values); FR-COMP-020 §6
-- expect-build-error: a tensor of (Int, String) has no default element value; give one with 'Tensor[(Int, String) * n] with v'

fn :: main => ()
      main =
        t = Tensor[(Int, String) * 2]
        echo "unreachable"
