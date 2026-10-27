-- case: FR-COMP-003 Case 3's four-level decision tree with |. closers, every leaf reached once
-- source: FR-COMP-003 §3 (evaluate_payment, verbatim body; names spaced for --strict)
-- expect-output:
--   REJECTED_ACCOUNT_LOCKED
--   ERROR_INVALID_AMOUNT
--   APPROVED_ENTERPRISE_DUAL_SIG
--   RISK_COMMITTEE_REVIEW
--   REJECTED_ENTERPRISE_LIMIT
--   APPROVED_ENTERPRISE_INTL
--   HELD_COMPLIANCE_INTL
--   APPROVED_ENTERPRISE_STANDARD
--   APPROVED_VIP_2FA
--   REQUEST_VIP_SMS
--   APPROVED_VIP_DIRECT
--   APPROVED_RETAIL_2FA
--   REJECTED_RETAIL_RISK
--   APPROVED_RETAIL_LOW_AMOUNT

type Account = is_locked: Bool
type Customer = tier: String, tenure: Int
type Payment = amount: Int, country: String, has_dual_signature: Bool, has_2fa: Bool, risk: Int

fn :: is whitelisted String => Bool
      is whitelisted c =  c == "CA"

fn :: evaluate payment Account Customer Payment => String
      evaluate payment account customer payment =
        | is_locked account   = "REJECTED_ACCOUNT_LOCKED"
        | amount payment <= 0 = "ERROR_INVALID_AMOUNT"
        | otherwise =
            | tier customer == "ENTERPRISE" =
                | amount payment > 50000 =
                    | has_dual_signature payment = "APPROVED_ENTERPRISE_DUAL_SIG"
                    | tenure customer > 10       = "RISK_COMMITTEE_REVIEW"
                    | otherwise                  = "REJECTED_ENTERPRISE_LIMIT" |.
                | country payment != "US" =
                    | is whitelisted (country payment) = "APPROVED_ENTERPRISE_INTL"
                    | otherwise                        = "HELD_COMPLIANCE_INTL" |.
                | otherwise = "APPROVED_ENTERPRISE_STANDARD" |.
            | tier customer == "VIP" =
                | amount payment > 10000 =
                    | has_2fa payment = "APPROVED_VIP_2FA"
                    | otherwise       = "REQUEST_VIP_SMS" |.
                | otherwise = "APPROVED_VIP_DIRECT" |.
            | otherwise =
                | amount payment > 1000 =
                    | has_2fa payment and risk payment < 30 = "APPROVED_RETAIL_2FA"
                    | otherwise                             = "REJECTED_RETAIL_RISK" |.
                | otherwise = "APPROVED_RETAIL_LOW_AMOUNT"

fn :: main => ()
      main =
        open = Account False
        ent = Customer "ENTERPRISE" 12
        ent_new = Customer "ENTERPRISE" 2
        vip = Customer "VIP" 1
        retail = Customer "RETAIL" 1
        echo (evaluate payment (Account True) ent (Payment 100 "US" False False 0))
        echo (evaluate payment open ent (Payment 0 "US" False False 0))
        echo (evaluate payment open ent (Payment 60000 "US" True False 0))
        echo (evaluate payment open ent (Payment 60000 "US" False False 0))
        echo (evaluate payment open ent_new (Payment 60000 "US" False False 0))
        echo (evaluate payment open ent (Payment 100 "CA" False False 0))
        echo (evaluate payment open ent (Payment 100 "FR" False False 0))
        echo (evaluate payment open ent (Payment 100 "US" False False 0))
        echo (evaluate payment open vip (Payment 20000 "US" False True 0))
        echo (evaluate payment open vip (Payment 20000 "US" False False 0))
        echo (evaluate payment open vip (Payment 500 "US" False False 0))
        echo (evaluate payment open retail (Payment 2000 "US" False True 10))
        echo (evaluate payment open retail (Payment 2000 "US" False True 50))
        echo (evaluate payment open retail (Payment 10 "US" False False 0))
