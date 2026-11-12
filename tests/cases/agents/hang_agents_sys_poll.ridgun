-- case: 8 concurrent agents each spawning an inner agent calling sys poll finish without deadlock
-- source: FR-COMP-009 (agents and nested agents run concurrently without worker pool starvation)
-- @tests TS-COMP-009
-- expect-output:
--   n=8 wrong=0
-- max-ms: 5000

fn :: inner step Int Int => Int Int
      inner step s x =  (s, nap x)

fn :: nap Int => Int
      nap x =
        sys poll (0 - 1) 1 5
        x

fn :: client Int => Int
      client id =
        conn = agent inner step 0
        ask many conn id 20 0

fn :: ask many (Agent Int Int) Int Int Int => Int
      ask many _    _  0 bad =  bad
      ask many conn id n bad =
        r = ask (id * 1000 + n) to conn
        ask many conn id (n - 1) (bad + (bad of r (id * 1000 + n)))

fn :: bad of Int Int => Int
      bad of r want
        | r == want = 0
        | otherwise = 1

fn :: new client Int => Agent Int Int
      new client _ =  agent client

fn :: send all [Agent Int Int] Int => ()
      send all []     _ =  ()
      send all (c:cs) i =
        send (i + 0) to c
        send all cs (i + 1)

fn :: sum all [Agent Int Int] => Int
      sum all []     =  0
      sum all (c:cs) =  (receive from c) + (sum all cs)

fn :: upto Int Int => [Int]
      upto a b
        | a > b     = []
        | otherwise = [a] :: (upto (a + 1) b)

fn :: second arg [String] => String
      second arg (_:x:_) =  x
      second arg _       =  "8"

fn :: main => ()
      main =
        n = str to int (second arg (cli args))
        cs = map new client (upto 1 n)
        send all cs 1
        echo ("n=" + (int to str n) + " wrong=" + (int to str (sum all cs)))
