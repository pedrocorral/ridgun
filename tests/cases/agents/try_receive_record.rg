-- case: try receive returns Some r also when the agent's response is a record
-- source: FR-COMP-009 §3 (try receive from returns Some r when a response is ready, for any response type R);
--   Solstice register RG-063 (records couldn't come back through try receive), fixed by the compiler team's TASK-0024
-- expect-output:
--   none yet
--   3 6

type Point = px: Int, py: Int
type OptionPoint = Some Point | None

fn :: make point Int => Point
      make point n =  Point n (n * 2)

fn :: wait for (Agent Int Point) Int => String
      wait for ag tries =  wait result ag tries (try receive from ag)

fn :: wait result (Agent Int Point) Int OptionPoint => String
      wait result _  _     (Some p) =  (int to str (px p)) + " " + (int to str (py p))
      wait result ag tries None
        | tries <= 0 = "no answer after 2 s"
        | otherwise  =
            sys sleep ms 10
            wait for ag (tries - 1)

fn :: describe OptionPoint => String
      describe (Some _) =  "already there"
      describe None     =  "none yet"

fn :: main => ()
      main =
        ag = agent (make point)
        echo (describe (try receive from ag))
        send 3 to ag
        echo (wait for ag 200)
