-- case: --strict refuses "_" in a built-in function call (e.g. str_len instead of str len)
-- source: FR-COMP-005 §5 (--strict forbids "_" in all function and built-in calls)
-- expect-build-error: strict mode

fn :: main => ()
      main =
        input_path = "hello.rg"
        echo (int to str (str_len input_path))
