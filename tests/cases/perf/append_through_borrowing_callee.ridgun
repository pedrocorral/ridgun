-- @tests TS-COMP-011
-- case: a loop that appends to its list through a callee that borrows a tuple parameter stays linear: the list is moved into the callee, not cloned, so `acc :: [h]` appends in place (Solstice report 2026-11-10: 8 000 steps took 835 ms, 100 000 took minutes); a local passed both to a borrowed and to an owned parameter of the same call is still read correctly
-- source: TASK-0067; FR-COMP-011; docs/etc/compiler_optimizations.md OPT-018
-- expect-output:
--   100000 x x
--   200000 7
--   4 a
-- max-ms: 2000
-- max-rss-mb: 64

fn :: scan Int Int [String] => [String]
      scan n i acc =
        | i >= n           = acc
        | otherwise        =
          step = (i + 1, "x")
          scan n (first step) (emit step acc)

fn :: first (Int String) => Int
      first (j, _) =  j

fn :: emit (Int String) [String] => [String]
      emit (_, h) acc =  acc :: [h]

fn :: count up [Int] Int => [Int]
      count up acc n =
        | n <= 0    = acc
        | otherwise = count up (push pair (n, 7) acc) (n - 1)

fn :: push pair (Int Int) [Int] => [Int]
      push pair (_, v) acc =  acc :: [v, v]

fn :: last of [Int] => Int
      last of (x:[]) = x
      last of (_:xs) = last of xs
      last of []     = 0

fn :: first str [String] => String
      first str (x:_) = x
      first str []    = ""

fn :: last str [String] => String
      last str (x:[]) = x
      last str (_:xs) = last str xs
      last str []     = ""

fn :: keep (Int String) (Int String) => Int String
      keep (a, _) t =  (a + (first t), "a")

fn :: twice (Int String) Int => Int String
      twice p n =
        | n <= 0    = p
        | otherwise = twice (keep p p) (n - 1)

fn :: snd of (Int String) => String
      snd of (_, s) =  s

fn :: main => ()
      main =
        ps = scan 100000 0 []
        echo (fold (a _ => a + 1) 0 ps) (first str ps) (last str ps)
        xs = count up [] 100000
        echo (fold (a _ => a + 1) 0 xs) (last of xs)
        r = twice (1, "b") 2
        echo (first r) (snd of r)
