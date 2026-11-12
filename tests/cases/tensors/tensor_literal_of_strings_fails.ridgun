-- @tests TS-COMP-020
-- case: a tensor literal of non-numeric elements is a compile error that points to 'tensor from list'
-- source: spec.md "Tensors" (lists)
-- expect-build-error: a tensor literal holds numbers, not String; use 'tensor from list' for other element types

fn :: main => ()
      main =
        t = Tensor ["a", "b"]
        echo "unreachable"
