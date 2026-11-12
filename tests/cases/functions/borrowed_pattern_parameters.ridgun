-- @tests TS-COMP-011
-- case: functions that only match a parameter with a pattern take it borrowed: same results with a local, a temporary, the same record twice, a constructor of several variants, a tuple, a string and a list; a function passed to map still works; a self tail call reads a field of a parameter it passes on; no leaked blocks after 300 rounds
-- source: TASK-0059; FR-COMP-011 item 7 (OPT-015..OPT-018); libs report 2026-11-08 (hashmap-tensores-y-campos, point 5)
-- expect-output:
--   hola
--   m3
--   12
--   12
--   0
--   14
--   12
--   15
--   1
--   0
--   x4
--   9
--   0
--   4
--   42
--   [hola, m2]
--   (R 7 hola [1, 2])
--   True

type R = ra: Int, rb: String, rc: [Int]

type Shape = Circle Int | Rect Int Int | Empty

fn :: get b R => String
      get b (R _ b _) = b

fn :: area Shape => Int
      area (Circle r) = 3 * r * r
      area (Rect w h) = w * h
      area Empty = 0

fn :: both R R => Int
      both (R a _ _) (R b _ _) = a + b

fn :: mixed R Int R => Int
      mixed (R a _ _) k r2 = a + k + (ra r2)

fn :: word String => Int
      word "uno" = 1
      word _ = 0

fn :: pair (Int, String) => String
      pair (n, s) = s + "{n}"

fn :: first [Int] => Int
      first [] = 0
      first (x:_) = x

fn :: mk Int => R
      mk n = R n "m{n}" [n, n]

fn :: lens R => Int
      lens r = str len (rb r)

fn :: loop R Int Int => Int
      loop r j acc
        | j >= 3 = acc
        | otherwise = loop r (j + 1) (acc + (ra r) + (area (Rect j (ra r))))

fn :: stress Int R Shape => ()
      stress 0 _ _ = ()
      stress n r s =
        a = get b r
        b = get b (mk n)
        c = area s
        d = area (Rect n 2)
        e = both r r
        f = both r (mk n)
        g = mixed r n (mk 1)
        h = word (rb r)
        i = pair (n, rb r)
        k = lens (mk n)
        stress (n - 1) r s

fn :: main => ()
      main =
        r = R 7 "hola" [1, 2]
        echo (get b r)
        echo (get b (mk 3))
        echo (area (Circle 2))
        s = Rect 3 4
        echo (area s)
        echo (area Empty)
        echo (both r r)
        echo (both r (mk 5))
        echo (mixed r 1 r)
        echo (word "uno")
        echo (word (rb r))
        echo (pair (4, "x"))
        echo (first [9, 8])
        echo (first [])
        echo (lens r)
        echo (loop r 0 0)
        echo ([r, mk 2] map get b)
        echo r
        b0 = cmm live blocks
        stress 300 r s
        b1 = cmm live blocks
        echo ((b1 - b0) <= 0)
