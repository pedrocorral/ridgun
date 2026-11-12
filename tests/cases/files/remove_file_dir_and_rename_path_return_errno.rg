-- @tests TS-VM-002
-- case: remove file, remove dir and rename path work on files and folders without a shell and return 0 or -errno
--   (rename replaces the target; removing a folder with files is ENOTEMPTY; a missing path is ENOENT)
-- source: FR-VM-002 (remove_file, remove_dir, rename_path); Solstice report windows-macos-runtime, addendum (2026-11-12)
-- expect-output:
--   rename: 0 new
--   replace: 0 second
--   remove dir with a file: -39
--   remove file: 0 then -2
--   remove dir: 0 then -2
--   left: []

fn :: main => ()
      main =
        sys mkdir "rur" 493
        sys mkdir "rur/sub" 493
        write file "rur/a.txt" "new"
        echo "rename:" (rename path "rur/a.txt" "rur/b.txt") (read file "rur/b.txt")
        write file "rur/c.txt" "second"
        echo "replace:" (rename path "rur/c.txt" "rur/b.txt") (read file "rur/b.txt")
        echo "remove dir with a file:" (remove dir "rur")
        echo "remove file:" (remove file "rur/b.txt") "then" (remove file "rur/b.txt")
        echo "remove dir:" (remove dir "rur/sub") "then" (remove dir "rur/sub")
        remove dir "rur"
        echo "left:" (list dir "rur")
