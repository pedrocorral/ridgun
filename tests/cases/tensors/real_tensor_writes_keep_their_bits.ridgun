-- @tests TS-COMP-020
-- case: a Real written into a Real tensor of one, two or three dimensions reads back as the same Real, and the writes free every replaced value
-- source: spec.md "Tensors" (element types); FR-COMP-020 §2, §3, §5
-- expect-output:
--   4.75
--   3.75
--   2.5
--   -1.25
--   0.0
--   0

fn :: main => ()
      main =
        base = cmm live blocks
        line = Tensor[Real * 3]
        line_(2) = 4.75
        echo line_(2)
        grid = Tensor[Real * 2 * 2]
        grid_(1, 1) = 3.75
        echo grid_(1, 1)
        cube = Tensor[Real * 2 * 2 * 2]
        cube_(1, 1, 1) = 2.5
        cube_(0, 1, 0) = 0.0 - 1.25
        cube_(0, 1, 0) = 0.0 - 1.25
        echo cube_(1, 1, 1)
        echo cube_(0, 1, 0)
        echo cube_(0, 0, 0)
        leaked = (cmm live blocks) - base
        echo leaked
