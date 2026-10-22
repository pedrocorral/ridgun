-- ============================================================
-- build.rg — Ridgun Project Build Definition for `stable`
-- ============================================================

fn :: project name => String
      project name =  "ridgunc"

fn :: project kind => String
      project kind =  "bin"

fn :: project version => String
      project version =  "0.9.7"

fn :: main entry => String
      main entry =  "src/main/ridgun/ridgunc/main.rg"

fn :: source dir => String
      source dir =  "src/main/ridgun"

fn :: test dir => String
      test dir =  "src/test/ridgun"

fn :: target dir => String
      target dir =  "target"

fn :: dependencies => [String]
      dependencies =  ["/home/boogie/ridgun-libs"]

fn :: task check all => String
      task check all =  "./bin/stable check"

fn :: task verify docs => String
      task verify docs =  "aix docs validate"
