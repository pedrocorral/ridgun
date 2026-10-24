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
        _ = echo (int_to_str (unwrap (try receive from sq)))
        send 6 to sq
        _ = echo (int_to_str (receive from sq))
        _ = echo (int_to_str (unwrap (try receive from sq)))
        _ = echo (bool_text (agent alive sq))
        stop sq
        echo (bool_text (agent alive sq))
