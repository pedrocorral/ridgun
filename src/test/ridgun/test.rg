-- ============================================================
-- src/test/ridgun/test.rg
-- Ridgun Standard Test Assertion Library (`import test`)
-- Synced with `/home/boogie/ridgun-libs/src/main/ridgun/lib/test.rg`
-- ============================================================

fn :: fail test String => ()
      fail test msg    =
        echo "[FAIL] {msg}"
        sys exit 1

-- ── Non-Exiting Predicate Helpers ────────────────────────────

fn :: check eq A      A        => Bool
      check eq actual expected =  actual == expected

fn :: check str eq String String   => Bool
      check str eq actual expected =  actual == expected

fn :: check true Bool => Bool
      check true cond =  cond

-- ── Standard 2-Arg & 1-Arg Assertions (with fail-fast exit) ──

fn :: assert equals A      A        => ()
      assert equals actual expected
        | actual == expected = echo "  [ok]  " actual "==" expected
        | otherwise = fail test "assert_equals failed: got {actual}, expected {expected}"

fn :: assert true Bool => ()
      assert true cond
        | cond = echo "  [ok]   True"
        | otherwise = fail test "assert_true failed: expected True, got False"

-- ── Message-Annotated Assertions (`ridgun-libs` RG-011) ──────

fn :: assert false Bool String => ()
      assert false cond label
        | NOT cond = echo "  [ok]   False ({label})"
        | otherwise = fail test "assert_false failed: {label}"

fn :: assert str eq String String String => ()
      assert str eq actual expected label
        | actual == expected = echo "  [ok]   {label}: '{actual}' == '{expected}'"
        | otherwise = fail test "assert_str_eq failed ({label}): got '{actual}', expected '{expected}'"

fn :: assert int equals Int Int String => ()
      assert int equals actual expected label
        | actual == expected = echo "  [ok]   {label}: {actual} == {expected}"
        | otherwise = fail test "assert_int_equals failed ({label}): got {actual}, expected {expected}"

-- ── Concise Label-Free Assertion Helpers (`ridgun-libs`) ─────

fn :: assert ok Bool => ()
      assert ok cond =  assert true cond

fn :: assert not Bool => ()
      assert not cond =  assert false cond "assert_not"

fn :: assert eq A      A        => ()
      assert eq actual expected =  assert equals actual expected
