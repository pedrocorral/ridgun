-- @tests TS-COMP-020
-- case: tensor from list gives exactly the list's elements in order, also for lists built at run time by prepending and for the tail of a list, with Int, String and record elements
-- source: spec.md "Tensors" (lists); FR-COMP-020 §9; libs report 2026-11-07 (tensor from list length)
-- expect-output:
--   [5, 4, 3, 2, 1]
--   1000
--   999
--   [2, 3]
--   [c, b, a]
--   [2, 1]

type Visit = Visit String Int

fn :: gen ints Int Int [Int] => [Int]
      gen ints i n acc
        | i >= n = acc
        | otherwise = gen ints (i + 1) n ([i + 1] :: acc)

fn :: gen visits Int [Visit] => [Visit]
      gen visits 0 acc =  acc
      gen visits n acc =  gen visits (n - 1) ([Visit "v" n] :: acc)

fn :: count Visit => Int
      count (Visit _ n) =  n

fn :: drop first [Int] => [Int]
      drop first (x:xs) =  xs

fn :: main => ()
      main =
        echo (tensor to list (tensor from list (gen ints 0 5 [])))
        big = tensor from list (gen ints 0 1000 [])
        echo big_(0)
        echo big_(1)
        echo (tensor to list (tensor from list (drop first [1, 2, 3])))
        names = tensor from list (["c"] :: (["b"] :: ["a"]))
        echo (tensor to list names)
        vs = tensor from list (gen visits 2 [])
        echo [count vs_(1), count vs_(0)]
