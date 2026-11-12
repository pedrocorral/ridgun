-- case: a function value called with a list as its second argument gets the whole list, with 1 element or more, directly and as a stateful agent's step; closures keep working (Solstice report rg115-paso-lambda, 2026-11-12)
-- source: FR-COMP-001 §1 (first-class function values); FR-COMP-009 §1-§2 (a step gets the whole message)
-- expect-output:
--   ([a], []) ([b, c, k], [k])
--   [d, k] [e, d, k]
--   ([k], 2) ([k], 3)
--   []
--   [a]
--   [b, a]
--   6
--   ([z], 12)

fn :: grow [String] [String] => [String] [String]
      grow keys cmds =  (cmds :: keys, keys)

fn :: keep [String] [String] => [String]
      keep keys cmds =  cmds :: keys

fn :: cnt [String] [String] => [String] Int
      cnt keys cmds =  (keys, list len cmds)

fn :: main => ()
      main =
        gv = grow
        echo (gv [] ["a"]) (gv ["k"] ["b", "c"])
        kv = keep
        c = kv ["k"] ["d"]
        echo c (kv c ["e"])
        cv = cnt
        xs = ["a", "b"]
        echo (cv ["k"] xs) (cv ["k"] ["p", "q", "r"])
        g = agent grow []
        echo (ask g ["a"])
        echo (ask g ["b"])
        echo (ask g ["c"])
        echo (fold (acc row => acc + (list len row)) 0 [[1, 2], [3], [4, 5, 6]])
        off = 10
        cl = (k c => (k, list len c + off))
        echo (cl ["z"] ["p", "q"])
