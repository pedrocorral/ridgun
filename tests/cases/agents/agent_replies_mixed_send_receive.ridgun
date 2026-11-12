-- case: 8 concurrent client agents sharing 1 stateful agent via send + receive from receive their own replies without mixing
-- source: FR-COMP-009 (replies from a shared agent are associated with the requesting thread)
-- @tests TS-COMP-009
-- expect-output:
--   wrong answers: 0
-- max-ms: 10000

type St = last: Int, switches: Int
type Req = rconn: (Agent Int Int), rid: Int

fn :: conn step St Int => St Int
      conn step s x =  conn reply s x (x / 100000)

fn :: conn reply St Int Int => St Int
      conn reply s x who
        | x == 0 - 1      = (s, switches s)
        | who == (last s) = (s, x)
        | otherwise       = (St who ((switches s) + 1), x)

fn :: client Req => Int
      client r =  ask many (rconn r) (rid r) 300 0

fn :: ask many (Agent Int Int) Int Int Int => Int
      ask many _    _  0 bad =  bad
      ask many conn id n bad =
        send (id * 100000 + n) to conn
        r = receive from conn
        ask many conn id (n - 1) (bad + (wrong r id n) + (busy 50000 0))

fn :: busy Int Int => Int
      busy 0 acc =  acc * 0
      busy n acc =  busy (n - 1) (acc + n % 7)

fn :: wrong Int Int Int => Int
      wrong r id n
        | r == id * 100000 + n = 0
        | otherwise            = 1

fn :: new client Int => Agent Req Int
      new client _ =  agent client

fn :: send all [Agent Req Int] (Int => (Agent Int Int)) Int => ()
      send all []     _ _ =  ()
      send all (c:cs) f i =
        send (Req (f i) (i + 0)) to c
        send all cs f (i + 1)

fn :: sum all [Agent Req Int] => Int
      sum all []     =  0
      sum all (c:cs) =  (receive from c) + (sum all cs)

fn :: main => ()
      main =
        shared = agent conn step (St 0 0)
        cs = map new client [1, 2, 3, 4, 5, 6, 7, 8]
        send all cs (_ => shared) 1
        echo ("wrong answers: " + (int to str (sum all cs)))
