-- case: an agent whose step is a lambda or a function value answers like one whose step is a named function: a list state that grows to 2 elements, a list reply, a tuple state with a step that returns only the state (Solstice report rg115-paso-lambda, 2026-11-12)
-- source: FR-COMP-009 §1-§2 (S M => S R and S M => S); the form of a lambda or a function value is read from its type when the agent is made
-- no-strict: a step over a tuple state needs a nested tuple return type, which --strict rejects
-- expect-output:
--   1 2 3
--   I1 OK .
--   Tx .
--   OK OK .
--   Tx .
--   (3, 7)
--   (6, 14)
--   (6, 14)

type Rep = ROk | RInt Int | RText String

fn :: remember [Int] Int => [Int] Int
      remember xs n =  ([n] :: xs, list len ([n] :: xs))

fn :: serve [String] [String] => [String] [Rep]
      serve keys cmds =  step keys cmds []

fn :: step [String] [String] [Rep] => [String] [Rep]
      step keys [] acc =  (keys, rev reps acc [])
      step keys ("i":cs) acc =  step (["a"] :: keys) cs ([RInt 1] :: acc)
      step keys ("t":cs) acc =  step keys cs ([RText "x"] :: acc)
      step keys (_:cs) acc =  step (["b"] :: keys) cs ([ROk] :: acc)

fn :: rev reps [Rep] [Rep] => [Rep]
      rev reps [] acc =  acc
      rev reps (x:xs) acc =  rev reps xs ([x] :: acc)

fn :: show [Rep] => String
      show [] =  "."
      show (ROk:rs) =  "OK " + (show rs)
      show ((RInt n):rs) =  "I" + (int to str n) + " " + (show rs)
      show ((RText t):rs) =  "T" + t + " " + (show rs)

fn :: scale (Int, Int) Int => (Int, Int)
      scale (a, b) n =  (a * n, b * n)

fn :: main => ()
      main =
        r = agent (xs n => remember xs n) []
        echo (ask r 7) (ask r 8) (ask r 9)
        a = agent (k c => serve k c) []
        echo (show (ask a ["i", "s"]))
        echo (show (ask a ["t"]))
        sv = serve
        b = agent sv []
        echo (show (ask b ["s", "s"]))
        echo (show (ask b ["t"]))
        s = agent (st n => scale st n) (3, 7)
        echo (ask s 1)
        echo (ask s 2)
        sc = scale
        t = agent sc (3, 7)
        echo (ask t 2)
