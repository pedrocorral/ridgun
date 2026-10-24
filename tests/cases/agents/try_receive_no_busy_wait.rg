-- case: polling an agent with try receive while it sleeps 400 ms costs almost no CPU
-- source: FR-COMP-009 §6 (try receive polls without blocking; the handler runs in the background); Solstice register
--   RG-072 (each try receive spun about 2 ms of CPU), fixed by the compiler team's TASK-0024 (no pause spin loop)
-- expect-output:
--   7
-- max-cpu-ms: 150

type OptionInt = Some Int | None

fn :: slow Int => Int
      slow n =
        _ = sys_sleep_ms 400
        n

fn :: poll (Agent Int Int) Int => Int
      poll ag tries =  poll_result ag tries (try receive from ag)

fn :: poll result (Agent Int Int) Int OptionInt => Int
      poll result _  _     (Some n) =  n
      poll result ag tries None
        | tries <= 0 = 0 - 1
        | otherwise  =
            _ = sys_sleep_ms 5
            poll ag (tries - 1)

fn :: main => ()
      main =
        ag = agent (slow)
        send 7 to ag
        echo (int_to_str (poll ag 1000))
