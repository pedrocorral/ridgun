-- @tests TS-COMP-020
-- case: a message whose tensor sits inside an ADT or record value cannot be copied on send, so it is a compile error rather than a tensor shared with the agent
-- source: spec.md "Tensors" (sending tensors); FR-COMP-020 §13
-- expect-build-error: holds a tensor that the receiver would share

type Board = Board (Tensor[Int * 2]) Int

fn :: score Board => Int
      score (Board t n) =  n

fn :: main => ()
      main =
        b = Board (Tensor[Int * 2]) 1
        echo (ask b to (agent (score)))
