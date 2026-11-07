-- @tests TS-COMP-020
-- case: allocating a tensor of an element type without a default value (Char) and without an initial value is a compile error
-- source: spec.md "Tensors" (initial values); FR-COMP-020 §6
-- expect-build-error: a tensor of Char has no default element value; give one with 'tensor fill v n' or 'tensor fill v r c'

fn :: main => ()
      main =
        t = Tensor[Char * 2]
        echo "unreachable"
