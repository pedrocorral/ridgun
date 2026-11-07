-- @tests TS-COMP-020
-- case: creating, writing, converting and dropping tensors of non-numeric elements in a loop leaves no live heap block behind (RMM)
-- source: spec.md "Tensors"; FR-COMP-020 §5
-- expect-output:
--   leaked: 0

type Visit = Visit String Int

fn :: churn Int => ()
      churn n =
        t = Tensor[String * 4]
        t_(0) = "a" + (int to str n)
        t_(1) = "b"
        t_(0) = "c"
        g = Tensor[String * 2 * 2]
        g_(1, 1) = "z" + (int to str n)
        l = tensor from list ["x", "y"]
        l_(1) = "w"
        back = tensor to list l
        f = tensor fill (Visit "v" n) 3
        f_(2) = Visit "w" n
        ()

fn :: loop Int => ()
      loop n
        | n <= 0 = ()
        | otherwise =
          churn n
          loop (n - 1)

fn :: main => ()
      main =
        base = cmm live blocks
        loop 200
        leaked = (cmm live blocks) - base
        echo ("leaked: " + (int to str leaked))
