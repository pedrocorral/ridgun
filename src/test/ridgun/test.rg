-- ============================================================
-- src/test/ridgun/test.rg
-- Ridgun Standard Test Library (`import test`)
-- ============================================================

fn :: assert_equals a a => ()
assert_equals actual expected
  | actual == expected = echo "  [ok]  " actual "==" expected
  | otherwise = echo "  [FAIL] expected:" expected "got:" actual

fn :: assert_true Bool => ()
assert_true cond
  | cond = echo "  [ok]   True"
  | otherwise = echo "  [FAIL] expected True, got False"
