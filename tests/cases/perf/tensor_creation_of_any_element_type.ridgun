-- @tests TS-COMP-020
-- case: creating a Tensor[String * n] and a tensor of a generic element type with 1 000 000 elements each, and a 120 x 120 Real matrix product, all stay under the limit
-- source: FR-COMP-020 (tensors of any element type); libs report 2026-11-08 (hashmap-tensores-y-campos, points 3 and 4: 0.75 µs per element before 0.9.45)
-- expect-output:
--   1000000 1000000 7 180.0
-- max-ms: 1000

fn :: mk V Int => Tensor[V * n]
      mk v c = Tensor[V * c] with v

fn :: mm Tensor[Real * r * k] Tensor[Real * k * c] => Tensor[Real * r * c]
      mm a b = a_ik @ b_kj

fn :: len gen Tensor[V * n] => Int
      len gen (Tensor[V * k] t) = k

fn :: main => ()
      main =
        n = 1000000
        s = Tensor[String * n]
        g = mk 7 n
        a = Tensor[Real * 120 * 120] with 1.5
        b = Tensor[Real * 120 * 120] with 1.0
        p = mm a b
        echo "{len gen s} {len gen g} {g_(999999)} {p_(5, 9)}"
