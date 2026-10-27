-- case: a || block closed with ||. and a guarded binding closed with |., then a final expression (FR-COMP-003 Case 3)
-- source: FR-COMP-003 §3 (charge_order)
-- expect-output:
--   150
--   50

fn :: fetch base fee Int => Int
      fetch base fee p =  p

fn :: compute risk score Int => Int
      compute risk score p =  p - 10

fn :: charge order Int => Int
      charge order payment =
        || fetch base fee payment   -> base_fee
        || compute risk score payment -> risk_score ||.
        surcharge =
          | risk_score > 80 = 50
          | otherwise       = 0 |.
        base_fee + surcharge

fn :: main => ()
      main =
        echo (int to str (charge order 100))
        echo (int to str (charge order 50))
