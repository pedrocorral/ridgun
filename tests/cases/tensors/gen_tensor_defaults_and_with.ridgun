-- @tests TS-COMP-020
-- case: an allocation without an initial value uses the element default (False, [], "", the code-0 Char), and 'Tensor[T * dims] with v' gives any initial value: String, ADT, tuple, Char, Real and Int
-- source: spec.md "Tensors" (initial values); FR-COMP-020 §1, §6
-- expect-output:
--   [False, True]
--   [[1, 2, 3], []]
--   1
--   [-, -, -, end]
--   [(Visit ana 1), (Visit eva 2)]
--   (1, uno)
--   [[., ., .], [., x, .]]
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
        chars = Tensor[Char * 2]
        echo (str len chars_(0))
        dashes = Tensor[String * 4] with "-"
        dashes_(3) = "end"
        echo dashes
        visits = Tensor[Visit * 2] with Visit "ana" 1
        visits_(1) = Visit "eva" 2
        echo visits
        pairs = Tensor[(Int, String) * 2] with (1, "uno")
        echo pairs_(0)
        board = Tensor[Char * 2 * 3] with '.'
        board_(1, 1) = 'x'
        echo board
        reals = Tensor[Real * 3] with 2.5
        echo reals_(1)
        ints = Tensor[Int * 2] with 7
        echo ints_(0)
        grid = Tensor[String * 2 * 2] with "x"
        grid_(1, 1) = "y"
        echo grid
