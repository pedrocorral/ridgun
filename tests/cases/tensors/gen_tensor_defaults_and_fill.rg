-- @tests TS-COMP-020
-- case: an allocation without an initial value uses the element default (False, [], ""), and 'tensor fill' gives any initial value: ADT, tuple, Char, Real and Int
-- source: spec.md "Tensors" (initial values); FR-COMP-020 §1, §6
-- expect-output:
--   [False, True]
--   [[1, 2, 3], []]
--   [-, -, -, end]
--   [(Visit ana 1), (Visit eva 2)]
--   (1, uno)
--   [c, c]
--   2.5
--   7
--   [[x, x], [x, y]]

type Visit = Visit String Int

fn :: main => ()
      main =
        flags = Tensor[Bool * 2]
        flags_(1) = True
        echo flags
        lists = Tensor[[Int] * 2]
        lists_(0) = [1, 2, 3]
        echo lists
        dashes = tensor fill "-" 4
        dashes_(3) = "end"
        echo dashes
        visits = tensor fill (Visit "ana" 1) 2
        visits_(1) = Visit "eva" 2
        echo visits
        pairs = tensor fill (1, "uno") 2
        echo pairs_(0)
        chars = tensor fill 'c' 2
        echo chars
        reals = tensor fill 2.5 3
        echo reals_(1)
        ints = tensor fill 7 2
        echo ints_(0)
        grid = tensor fill "x" 2 2
        grid_(1, 1) = "y"
        echo grid
