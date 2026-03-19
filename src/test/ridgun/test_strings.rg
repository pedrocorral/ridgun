-- ============================================================
-- Ridgun Test: String Operations (using test library)
-- ============================================================

import test

fn :: main => ()
      main =
        echo "=== String Equality ==="
        assert_equals "hello" "hello"
        assert_equals "world" "world"
        echo "=== Escape Sequences ==="
        assert_equals "tab\there" "tab\there"
        assert_equals "line1\nline2" "line1\nline2"
        echo "=== All string tests passed ==="
