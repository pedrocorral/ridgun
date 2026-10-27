-- case: `r with f = v, g = w` makes an updated copy (the original is unchanged), also as the last line of a block
-- source: record update syntax `r with f = v` (current; `with f: v` is obsolete — the project owner's decision 2026-10-23;
--   spec.md:517, book 06:42 and harness still show the old form); spec.md block rules (the last line is the block's value);
--   Solstice register RG-068 (a last line `r with f = v` is misread as a binding)
-- expect-output:
--   ana 30
--   ana 31
--   eva 31
--   bea 40

type Person = name: String, age: Int

fn :: show Person => String
      show p =  (name p) + " " + (int to str (age p))

fn :: older Person => Person
      older p =
        n = age p
        p with age = n + 1

fn :: renamed Person String Int => Person
      renamed p new_name new_age =  p with name = new_name, age = new_age

fn :: main => ()
      main =
        a = Person "ana" 30
        b = older a
        echo (show a)
        echo (show b)
        echo (show (b with name = "eva"))
        echo (show (renamed a "bea" 40))
