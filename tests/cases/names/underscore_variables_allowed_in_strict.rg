-- case: parameters, local variables, pipe bindings, and record fields may always contain "_" even in --strict mode
-- source: FR-COMP-005 §5 (variables and record fields are single-token data bindings and always allow "_")
-- expect-output:
--   app.rg:10:64

type BuildCfg = max_conns Int, target_arch String

fn :: compute total Int Bool => Int
      compute total base_val strict_mode =
        local_bonus =
          | strict_mode = 4
          | otherwise   = 0
        mut mut_acc = base_val
        mut_acc = mut_acc + local_bonus
        mut_acc

fn :: format summary String BuildCfg => String
      format summary input_path build_cfg =
        compute total 6 True -> final_total
        input_path + ":" + (int to str final_total) + ":" + (int to str (max_conns build_cfg))

fn :: main => ()
      main =
        my_cfg = BuildCfg 64 "x86_64"
        echo (format summary "app.rg" my_cfg)
