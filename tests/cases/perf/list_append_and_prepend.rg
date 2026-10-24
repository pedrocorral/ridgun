-- case: building a 20 000-element list one element at a time is linear, whether elements go at the end or at the front
-- source: no promise in the docs (proposal): Solstice register RG-085 measured prepending ([x] :: acc) at 1 s for
--   10 000 elements and (acc :: [x]) :: [y] at 0.65 s, against 8 ms for acc :: [x]. Limit: 1 s for both directions.
-- expect-output:
--   20000 20000
-- max-ms: 1000

fn :: at end Int [Int] => [Int]
      at end n acc =
        | n == 0    = acc
        | otherwise = at_end (n - 1) (acc :: [n])

fn :: at front Int [Int] => [Int]
      at front n acc =
        | n == 0    = acc
        | otherwise = at_front (n - 1) ([n] :: acc)

fn :: count [Int] Int => Int
      count []     k =  k
      count (_:xs) k =  count xs (k + 1)

fn :: main => ()
      main =  echo ((int_to_str (count (at_end 20000 []) 0)) + " " + (int_to_str (count (at_front 20000 []) 0)))
