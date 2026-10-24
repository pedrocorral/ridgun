-- case: a top-level line that is no declaration Ridgun knows is a build error, not silently dropped
-- source: spec.md (a source file is a sequence of declarations: fn, op, type, import, …); a typo in a declaration
--   must not vanish. Solstice register RG-090: 0.9.18 (592878f) builds this file and runs it
-- expect-build-error:

this is not ridgun at all :: 42 ]]

fn :: main => ()
      main =  echo "built"
