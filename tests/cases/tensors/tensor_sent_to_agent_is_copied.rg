-- @tests TS-COMP-020
-- case: a tensor sent to an agent (alone, in a tuple, as a function result, as the initial state) or through a channel is a copy: writes on the receiving side never reach the sender's tensor
-- source: spec.md "Tensors" (sending tensors); FR-COMP-020 §13
-- expect-output:
--   5
--   Tensor(shape=[2], data=[0.0, 5.0])
--   b
--   [, b]
--   x
--   [[x, x], [x, x]]
--   2.5
--   2.5
--   0.5
--   3
--   [one, two]
--   7
--   Tensor(shape=[2], data=[7.0, 7.0])

fn :: poke Tensor[Int * n] => Int
      poke t =
        t_(0) = 99
        t_(1)

fn :: poke names Tensor[String * n] => String
      poke names t =
        t_(0) = "agent"
        t_(1)

fn :: poke grid Tensor[String * r * c] => String
      poke grid t =
        t_(0, 0) = "agent"
        t_(1, 1)

fn :: poke pair (Tensor[Real * n], Int) => Real
      poke pair (t, k) =
        t_(0) = 9.5
        t_(1)

fn :: halves => Tensor[Real * 2]
      halves =  Tensor[Real * 2] with 0.5

fn :: count calls Tensor[Int * n] Int => Tensor[Int * n] Int
      count calls t x =
        t_(0) = t_(0) + x
        (t, t_(0))

fn :: main => ()
      main =
        t = Tensor[Int * 2]
        t_(1) = 5
        ints = agent (poke)
        echo (ask t to ints)
        echo t
        names = Tensor[String * 2]
        names_(1) = "b"
        strs = agent (poke names)
        echo (ask names to strs)
        echo names
        grid = Tensor[String * 2 * 2] with "x"
        grids = agent (poke grid)
        echo (ask grid to grids)
        echo grid
        reals = Tensor[Real * 2] with 2.5
        pairs = agent (poke pair)
        echo (ask (reals, 1) to pairs)
        echo reals_(0)
        echo (ask (halves, 2) to pairs)
        start = Tensor[Int * 1]
        counter = agent (count calls) start
        echo (ask 3 to counter)
        start_(0) = 100
        ch = new channel
        words = Tensor[String * 2] with "one"
        words_(1) = "two"
        send words through ch
        words_(0) = "changed"
        echo (receive from ch)
        sevens = Tensor[Int * 2] with 7
        send sevens through ch
        sevens_(1) = 0
        got = receive from ch
        echo got_(1)
        echo got
