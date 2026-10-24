-- case: --strict refuses "_" in a fn declaration's name
-- source: book 02:193-197 (--strict: "_" in fn/op names is a compile error)
-- expect-build-error: strict mode

fn :: add_one Int => Int
      add_one x =  x + 1

fn :: main => ()
      main =  echo (int_to_str (add_one 1))
