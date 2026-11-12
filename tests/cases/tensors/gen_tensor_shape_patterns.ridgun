-- @tests TS-COMP-020
-- case: shape patterns match tensors of non-numeric elements by rank and bind their dimensions, also for list elements, generic element types and numeric tensors
-- source: spec.md "Tensors" (element types); FR-COMP-020 Statement
-- expect-output:
--   grid 2x3 z
--   row 4 d
--   5
--   204
--   23
--   4
--   34
--   209
--   35

fn :: describe Tensor[String] => String
      describe (Tensor[String * r * c] g) =  "grid " + (int to str r) + "x" + (int to str c) + " " + g_(r - 1, c - 1)
      describe (Tensor[String * n] v) =  "row " + (int to str n) + " " + v_(n - 1)

fn :: count lists Tensor[[Int]] => Int
      count lists (Tensor[[Int] * n] v) =  n
      count lists (Tensor[[Int] * r * c] g) =  r * 100 + c

fn :: generic size Tensor[A] => Int
      generic size (Tensor[A * r * c] g) =  r * 10 + c
      generic size (Tensor[A * n] v) =  n

fn :: shape sum Tensor[Int] => Int
      shape sum (Tensor[Int * f * c] m) = f * 100 + c + m_(0, 0)
      shape sum (Tensor[Int * n] v) = n * 10 + v_(0)

fn :: main => ()
      main =
        g = Tensor[String * 2 * 3]
        g_(1, 2) = "z"
        echo (describe g)
        v = tensor from list ["a", "b", "c", "d"]
        echo (describe v)
        ls = Tensor[[Int] * 5]
        echo (count lists ls)
        lg = Tensor[[Int] * 2 * 4]
        echo (count lists lg)
        echo (generic size g)
        echo (generic size v)
        echo (generic size (Tensor[Int * 3 * 4]))
        echo (shape sum (Tensor [[7, 1], [2, 3]]))
        echo (shape sum (Tensor [5, 6, 7]))
