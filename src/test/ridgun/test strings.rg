-- ============================================================
-- src/test/ridgun/test strings.rg
-- Ridgun Test: String Operations (using test library)
-- ============================================================

import test

fn :: lstat kind (Bool, String, Int, Int, Int, String, String, Int, String) => String
      lstat kind (_, k, _, _, _, _, _, _, _) = k

fn :: main => ()
      main =
        echo "=== String Equality ==="
        assert equals "hello" "hello"
        assert equals "world" "world"
        echo "=== Escape Sequences ==="
        assert equals "tab\there" "tab\there"
        assert equals "line1\nline2" "line1\nline2"
        echo "=== Verbatim File I/O, Byte Streams & POSIX Built-ins ==="
        _ = write file "target/.test_verbatim.txt" "import fake_module\r\nno_trailing_newline"
        assert equals (read file "target/.test_verbatim.txt") "import fake_module\r\nno_trailing_newline"
        _ = write bytes "target/.test_bytes.bin" [0, 65, 255, 10]
        assert equals (read bytes "target/.test_bytes.bin") [0, 65, 255, 10]
        assert equals (lstat kind (file lstat "target/.test_bytes.bin")) "file"
        assert equals (sha256 str "abc") "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        _ = shell exec "rm -f target/.test_verbatim.txt target/.test_bytes.bin"
        echo "=== All string tests passed ==="
