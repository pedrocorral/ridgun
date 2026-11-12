-- @tests TS-COMP-020
-- case: @ on Real tensors computes with Reals: a matrix product in a function and in main, the result indices in order of first appearance, a full contraction as a tensor of shape [1], three operands, a rank-3 operand, and no leaked blocks
-- source: spec.md "Tensors" (tensor contraction @); FR-COMP-020 §6; libs reports 2026-11-07 (einsum-real) and 2026-11-08 (point 3)
-- expect-output:
--   Tensor(shape=[2, 2], data=[21.0, 300.0, 54.0, 650.0])
--   Tensor(shape=[2, 2], data=[21.0, 300.0, 54.0, 650.0])
--   300.0
--   Tensor(shape=[1], data=[671.0])
--   Tensor(shape=[2, 2], data=[14.0, 33.5, 33.5, 83.25])
--   Tensor(shape=[2], data=[1.0, 42250.0])
--   Tensor(shape=[2, 2, 2], data=[1.0, 0.0, 0.0, 3000.0, 4.0, 0.0, 0.0, 6500.0])
--   Tensor(shape=[2, 2], data=[21, 300, 54, 600])
--   True

fn :: mm Tensor[Real * r * k] Tensor[Real * k * c] => Tensor[Real * r * c]
      mm a b = a_ik @ b_kj

fn :: rounds Int Tensor[Real * r * k] Tensor[Real * k * c] Tensor[Real * r * k * c] => ()
      rounds 0 a b c =  ()
      rounds n a b c =
        q = mm a b
        w = a_ij @ a_ij @ c_ijk
        rounds (n - 1) a b c

fn :: main => ()
      main =
        a = Tensor[Real * 2 * 3]
        a_(0, 0) = 1.0
        a_(0, 1) = 2.0
        a_(0, 2) = 3.0
        a_(1, 0) = 4.0
        a_(1, 1) = 5.0
        a_(1, 2) = 6.5
        b = Tensor[Real * 3 * 2]
        b_(0, 0) = 1.0
        b_(1, 0) = 10.0
        b_(2, 1) = 100.0
        c = Tensor[Real * 2 * 3 * 2]
        c_(1, 2, 1) = 1000.0
        c_(0, 0, 0) = 1.0
        echo (mm a b)
        p = a_ki @ b_ij
        echo p
        echo p_(0, 1)
        echo (a_ij @ b_ji)
        echo (a_ij @ a_kj)
        echo (a_ij @ a_ij @ c_ijk)
        echo (a_ij @ c_kjl)
        ai = Tensor[Int * 2 * 3]
        ai_(0, 0) = 1
        ai_(0, 1) = 2
        ai_(0, 2) = 3
        ai_(1, 0) = 4
        ai_(1, 1) = 5
        ai_(1, 2) = 6
        bi = Tensor[Int * 3 * 2]
        bi_(0, 0) = 1
        bi_(1, 0) = 10
        bi_(2, 1) = 100
        echo (ai_ik @ bi_kj)
        b0 = cmm live blocks
        rounds 200 a b c
        b1 = cmm live blocks
        echo ((b1 - b0) <= 0)
