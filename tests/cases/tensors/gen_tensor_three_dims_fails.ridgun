-- @tests TS-COMP-020
-- case: a tensor of non-numeric elements with three dimensions is a compile error
-- source: spec.md "Tensors" (element types)
-- expect-build-error: a tensor of non-numeric elements has one or two dimensions

fn :: main => ()
      main =
        t = Tensor[String * 2 * 2 * 2]
        echo "unreachable"
