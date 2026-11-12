-- case: an immutable String parameter can be sent to two agents in the same function (RG-108)
-- source: FR-COMP-002 and FR-COMP-009 (only mutable variables trigger UseAfterChannelSendError)
-- @tests TS-COMP-009
-- expect-output:
--   2

fn :: guess String => Int
      guess s =  str len s

fn :: burst String => Int
      burst email =
        g1 = agent guess
        g2 = agent guess
        send email to g1
        send email to g2
        (receive from g1) + (receive from g2)

fn :: main => ()
      main =  echo (int to str (burst "x"))
