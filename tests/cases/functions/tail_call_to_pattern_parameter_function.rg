-- @tests TS-COMP-011
-- case: a lexer-shaped loop (`loop at` passes a fresh tuple to `step`, which only matches it with a pattern and calls `loop at` back in tail position) runs 40 000 rounds in small memory; regression for OPT-018, which put work after that call, so the tail call was lost: every pending frame kept the accumulated list alive, `::` had to copy it each round, and memory grew quadratically (the self-built compiler passed 7 GB in 3 s on `check`)
-- source: TASK-0059; FR-COMP-004 (TCO); docs/etc/compiler_optimizations.md OPT-018 "Tail calls"; src/main/ridgun/lib/lexer.rg `lex loop at` / `lex step`
-- expect-output:
--   40000
-- max-rss-mb: 64
-- max-ms: 5000

type Tok = TNum Int | TSym String | TEnd

fn :: one tok String Int Int => Tok Int
      one tok src p len
        | (str char at src p) == 97 = (TSym "a", p + 1)
        | otherwise = (TNum p, p + 1)

fn :: step (Tok, Int) String Int [Tok] => [Tok]
      step (tok, next_p) src len rev_acc = loop at src next_p len ([tok] :: rev_acc)

fn :: loop at String Int Int [Tok] => [Tok]
      loop at src p len rev_acc
        | p >= len = rev_acc
        | otherwise = step (one tok src p len) src len rev_acc

fn :: count toks [Tok] Int => Int
      count toks [] n = n
      count toks (_:xs) n = count toks xs (n + 1)

fn :: build str Int String => String
      build str 0 acc = acc
      build str n acc = build str (n - 1) (acc + "ab")

fn :: main => ()
      main =
        src = build str 20000 ""
        echo (int to str (count toks (loop at src 0 (str len src) []) 0))
