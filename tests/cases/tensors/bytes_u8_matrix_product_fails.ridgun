-- @tests TS-COMP-022
-- case: the matrix product of byte tensors is a compile error
-- source: FR-COMP-022 (operations that are not defined on Tensor[U8])
-- expect-build-error: matrix product is not available on Tensor[U8]

fn :: main => ()
      main =
        t = Tensor[U8 * 2 * 2]
        u = t @ t
        echo "built"
