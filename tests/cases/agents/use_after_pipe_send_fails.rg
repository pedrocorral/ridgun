-- case: using a variable v after piping it into an agent (v -> send to ag) is rejected with UseAfterChannelSendError
-- source: FR-COMP-002 and FR-COMP-009 (affine ownership transfer on agent/channel send)
-- expect-build-error: UseAfterChannelSendError on 'v'

fn :: worker Int => Int
      worker x   =  x + 1

fn :: main => ()
      main =
        ag = agent (worker)
        v = 42
        v -> send to ag
        echo (int to str v)
