-- @tests TS-COMP-020
-- case: 'tensor from list' copies a list of any element type into a tensor and 'tensor to list' copies a tensor back; writing the tensor leaves the source list unchanged
-- source: spec.md "Tensors" (lists); FR-COMP-020 §9
-- expect-output:
--   [zz, b, c]
--   [a, b, c]
--   [zz, b, c]
--   [[1], [9, 3]]
--   [[1], [2, 3]]
--   [1, 2, 3]
--   [0.5, 0.0]
--   [0, 0, 9]

fn :: main => ()
      main =
        xs = ["a", "b", "c"]
        t = tensor from list xs
        t_(0) = "zz"
        echo t
        echo xs
        echo (tensor to list t)
        ys = [[1], [2, 3]]
        g = tensor from list ys
        g_(1) = [9, 3]
        echo g
        echo ys
        echo (tensor to list (tensor from list [1, 2, 3]))
        r = Tensor[Real * 2]
        r_(0) = 0.5
        echo (tensor to list r)
        z = Tensor[Int * 3]
        z_(2) = 9
        echo (tensor to list z)
