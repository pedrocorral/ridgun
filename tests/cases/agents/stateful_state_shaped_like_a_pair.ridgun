-- case: a stateful agent answers every message with what its step returns, whatever its state looks like: a list that reaches 2 elements, a tuple state with a (state, reply) step, a tuple state with a step that returns only the state (Solstice report respuesta-de-agente-perdida, 2026-11-11)
-- source: FR-COMP-009 §1-§2 (S M => S R and S M => S); the form is read from the step's signature
-- no-strict: a (state, reply) step over a tuple state needs a nested tuple return type, which --strict rejects
-- expect-output:
--   1 2 3 4
--   pair 11 21
--   pair 12 22
--   (3, 7)
--   (6, 14)

fn :: remember [Int] Int => [Int] Int
      remember xs n =  ([n] :: xs, list len ([n] :: xs))

fn :: bump (Int, Int) Int => (Int, Int) String
      bump (a, b) n =  ((a + n, b + n), "pair " + (int to str (a + n)) + " " + (int to str (b + n)))

fn :: scale (Int, Int) Int => (Int, Int)
      scale (a, b) n =  (a * n, b * n)

fn :: main => ()
      main =
        r = agent remember []
        echo (ask r 7) (ask r 8) (ask r 9) (ask r 10)
        p = agent bump (10, 20)
        echo (ask p 1)
        echo (ask p 1)
        s = agent scale (3, 7)
        echo (ask s 1)
        echo (ask s 2)
