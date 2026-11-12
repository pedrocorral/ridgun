-- @tests TS-COMP-020
-- case: a tensor literal that mixes Int and Real elements is a compile error, because a tensor holds one element type
-- source: spec.md "Tensors" (element typing); FR-COMP-020 §2
-- expect-build-error: a tensor literal mixes Int and Real elements

fn :: main => ()
      main =
        t = Tensor [1, 2.5]
        echo t
