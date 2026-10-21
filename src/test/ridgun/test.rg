-- ============================================================
-- src/test/ridgun/test.rg
-- Ridgun Standard Test Library (`import test`)
-- ============================================================

fn :: assert equals A      A        => ()
      assert equals actual expected
        | actual == expected = echo "  [ok]  " actual "==" expected
        | otherwise = echo "  [FAIL] expected:" expected "got:" actual

fn :: assert true Bool => ()
      assert true cond
        | cond = echo "  [ok]   True"
        | otherwise = echo "  [FAIL] expected True, got False"
