-- case: try receive gives None when nothing is queued and Some r once ready; stop ends the agent (agent alive: True → False)
-- source: FR-COMP-009 §3-§4 and AC-3
-- expect-output:
--   -1
--   36
--   -1
--   True
--   False

type OptionInt = Some Int | None

fn :: unwrap OptionInt => Int
      unwrap (Some n) =  n
      unwrap None     =  0 - 1

fn :: square Int => Int
      square x =  x * x

fn :: bool text Bool => String
      bool text True  =  "True"
      bool text False =  "False"

fn :: main => ()
      main =
        sq = agent (square)
        echo (int to str (unwrap (try receive from sq)))
        send 6 to sq
        echo (int to str (receive from sq))
        echo (int to str (unwrap (try receive from sq)))
        echo (bool text (agent alive sq))
        stop sq
        echo (bool text (agent alive sq))
