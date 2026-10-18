-- ============================================================
-- Ridgun Test: String Operations (using test library)
-- ============================================================

import test

fn :: lstat_kind (Bool, String, Int, Int, Int, String, String, Int, String) => String
      lstat_kind (_, k, _, _, _, _, _, _, _) = k

fn :: main => ()
      main =
        echo "=== String Equality ==="
        assert_equals "hello" "hello"
        assert_equals "world" "world"
        echo "=== Escape Sequences ==="
        assert_equals "tab\there" "tab\there"
        assert_equals "line1\nline2" "line1\nline2"
        echo "=== Verbatim File I/O, Byte Streams & POSIX Built-ins ==="
        _ = write_file "target/.test_verbatim.txt" "import fake_module\r\nno_trailing_newline"
        assert_equals (read_file "target/.test_verbatim.txt") "import fake_module\r\nno_trailing_newline"
        _ = write_bytes "target/.test_bytes.bin" [0, 65, 255, 10]
        assert_equals (read_bytes "target/.test_bytes.bin") [0, 65, 255, 10]
        assert_equals (lstat_kind (file_lstat "target/.test_bytes.bin")) "file"
        assert_equals (sha256_str "abc") "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        _ = shell_exec "rm -f target/.test_verbatim.txt target/.test_bytes.bin"
        echo "=== All string tests passed ==="
