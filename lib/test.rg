-- ============================================================
-- Ridgun Standard Library: Unit Testing
-- ============================================================
-- Import: import test
-- Usage:  test "name" does assert (expr) equals expected
-- ============================================================

-- ── Assertions ─────────────────────────────────────────────

-- Integer equality
op :: assert Int equals Int => ()
      assert a equals b
        | a == b    = echo "  ✓ PASS"
        | otherwise = echo "  ✗ FAIL: expected {b}, got {a}"

-- Real equality
op :: assert Real equals Real => ()
      assert a equals b
        | a == b    = echo "  ✓ PASS"
        | otherwise = echo "  ✗ FAIL: expected {b}, got {a}"

-- String equality
op :: assert String equals String => ()
      assert a equals b
        | a == b    = echo "  ✓ PASS"
        | otherwise = echo "  ✗ FAIL: expected \"{b}\", got \"{a}\""

-- Boolean: is true
op :: assert Bool is true => ()
      assert b is true
        | b         = echo "  ✓ PASS"
        | otherwise = echo "  ✗ FAIL: expected true, got false"

-- Boolean: is false
op :: assert Bool is false => ()
      assert b is false
        | b         = echo "  ✗ FAIL: expected false, got true"
        | otherwise = echo "  ✓ PASS"

-- ── Test Runner ────────────────────────────────────────────

-- Named test case: prints the test name, then runs the body
op :: test String does () => ()
      test name does body = echo "● {name}"

-- Section header: groups related tests
op :: describe String does () => ()
      describe name does body = echo "\n═══ {name} ═══"

-- ── Summary ────────────────────────────────────────────────
-- Output is purely terminal-based via echo.
-- ✓ PASS / ✗ FAIL results are printed as tests execute.
-- No counters yet — keep it simple for now.
