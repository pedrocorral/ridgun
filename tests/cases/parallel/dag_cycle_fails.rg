-- case: a || DAG whose bindings depend on each other in a cycle is rejected at compile time
-- source: book 07:110 (cycles rejected at compile time); spec.md:723-735 (dependency waves)
-- expect-build-error:

fn :: loop dag => Int
      loop dag =  a + b
        || b + 1 -> a
        || a + 1 -> b

fn :: main => ()
      main =  echo (int_to_str loop_dag)
