-- ============================================================
-- tests/run.rg
-- Pure Ridgun acceptance & performance test runner for ridgunc
-- Usage:
--   ./bin/ridgunc run tests/run.rg                  (all cases + toolchain checks)
--   ./bin/ridgunc run tests/run.rg lists strings    (cases matching filter)
--   ./bin/ridgunc run tests/run.rg --no-toolchain   (cases only)
--   ./bin/ridgunc run tests/run.rg --llvm           (cases built only for LLVM)
--   ./bin/ridgunc run tests/run.rg --x86            (cases built only with --target x86_64-elf)
-- Every case is built and run on both backends by default; tests/run_case.sh
-- runs each case binary and measures its CPU time and peak resident memory.
-- ============================================================

type CaseHeader = Header String String Bool String Bool String Bool Int Bool Int Bool Int Bool Int Bool Bool

type CaseResult = Result String Bool Bool String

fn :: is ws char Int => Bool
      is ws char 32 = True
      is ws char 9  = True
      is ws char 10 = True
      is ws char 13 = True
      is ws char _  = False

fn :: trim lead loop String Int Int => String
      trim lead loop s pos len
        | pos >= len = ""
        | is ws char (str char at s pos) = trim lead loop s (pos + 1) len
        | otherwise = str slice s pos len

fn :: trim trail loop String Int => String
      trim trail loop s end_pos
        | end_pos <= 0 = ""
        | is ws char (str char at s (end_pos - 1)) = trim trail loop s (end_pos - 1)
        | otherwise = str slice s 0 end_pos

fn :: trim ws String => String
      trim ws s =
        s1 = trim lead loop s 0 (str len s)
        trim trail loop s1 (str len s1)

fn :: strip trailing newline len String Int => String
      strip trailing newline len s n
        | n <= 0 = ""
        | (str char at s (n - 1)) == 10 or (str char at s (n - 1)) == 13 =
          strip trailing newline (str slice s 0 (n - 1))
        | otherwise = s

fn :: strip trailing newline String => String
      strip trailing newline s =
        strip trailing newline len s (str len s)

fn :: split lines loop String Int Int Int [String] => [String]
      split lines loop s start pos len acc
        | pos >= len = acc :: [str slice s start len]
        | (str char at s pos) == 10 =
          line = strip trailing newline (str slice s start pos)
          split lines loop s (pos + 1) (pos + 1) len (acc :: [line])
        | otherwise = split lines loop s start (pos + 1) len acc

fn :: split lines String => [String]
      split lines "" = []
      split lines s = split lines loop s 0 0 (str len s) []

fn :: join lines [String] => String
      join lines [] = ""
      join lines (x:[]) = x
      join lines (x:xs) = x + "\n" + (join lines xs)

fn :: list len [String] => Int
      list len [] = 0
      list len (_:xs) = 1 + (list len xs)

fn :: result list len [CaseResult] => Int
      result list len [] = 0
      result list len (_:xs) = 1 + (result list len xs)

fn :: nth line [String] Int => String
      nth line [] _ = "(nothing)"
      nth line (x:_) 0 = x
      nth line (_:xs) n = nth line xs (n - 1)

fn :: max int Int Int => Int
      max int a b
        | a >= b = a
        | otherwise = b

fn :: is ident char Int => Bool
      is ident char ch =
        (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or (ch >= 48 and ch <= 57) or ch == 95

fn :: sanitize step String Int Int String Bool => String
      sanitize step s pos len acc True =
        sanitize case name loop s (pos + 1) len (acc + (str slice s pos (pos + 1)))
      sanitize step s pos len acc False =
        sanitize case name loop s (pos + 1) len (acc + "_")

fn :: sanitize case name loop String Int Int String => String
      sanitize case name loop s pos len acc
        | pos >= len = acc
        | otherwise =
          sanitize step s pos len acc (is ident char (str char at s pos))

fn :: sanitize case name String => String
      sanitize case name rel =
        base = str slice rel 0 ((str len rel) - 3)
        sanitize case name loop base 0 (str len base) ""

fn :: collect expect output [String] [String] => String [String]
      collect expect output [] acc = (join lines acc, [])
      collect expect output (line:rest) acc
        | str starts with line "--   " =
          collect expect output rest (acc :: [str slice line 5 (str len line)])
        | line == "--" =
          collect expect output rest (acc :: [""])
        | otherwise = (join lines acc, [line] :: rest)

fn :: parse header expect step (String, [String]) CaseHeader => CaseHeader
      parse header expect step (out_text, rem_lines) (Header c_desc src _ _ has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop) =
        parse header lines rem_lines (Header c_desc src True out_text has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)

fn :: parse header lines [String] CaseHeader => CaseHeader
      parse header lines [] hdr = hdr
      parse header lines (line:rest) (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)
        | not (str starts with line "--") =
          Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop
        | str starts with line "-- expect-output:" =
          parse header expect step (collect expect output rest []) (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)
        | str starts with line "-- case:" =
          v = trim ws (str slice line 8 (str len line))
          parse header lines rest (Header v src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)
        | str starts with line "-- source:" =
          v = trim ws (str slice line 10 (str len line))
          parse header lines rest (Header c_desc v has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)
        | str starts with line "-- expect-build-error:" =
          v = trim ws (str slice line 22 (str len line))
          parse header lines rest (Header c_desc src has_out out_s True v has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)
        | str starts with line "-- expect-exit:" =
          v = str to int (trim ws (str slice line 15 (str len line)))
          parse header lines rest (Header c_desc src has_out out_s has_berr berr_s True v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)
        | str starts with line "-- max-ms:" =
          v = str to int (trim ws (str slice line 10 (str len line)))
          parse header lines rest (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v True v has_rss rss_v has_cpu cpu_v libs prop)
        | str starts with line "-- max-rss-mb:" =
          v = str to int (trim ws (str slice line 14 (str len line)))
          parse header lines rest (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v True v has_cpu cpu_v libs prop)
        | str starts with line "-- max-cpu-ms:" =
          v = str to int (trim ws (str slice line 14 (str len line)))
          parse header lines rest (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v True v libs prop)
        | (trim ws line) == "-- uses-libs" =
          parse header lines rest (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v True prop)
        | (trim ws line) == "-- kind: proposal" =
          parse header lines rest (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs True)
        | otherwise =
          parse header lines rest (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)

fn :: parse case header String => CaseHeader
      parse case header path =
        empty_hdr = Header "" "" False "" False "" False 0 False 0 False 0 False 0 False False
        path -> read file -> split lines -> parse header lines _ empty_hdr

fn :: strip dot digits String Int Int String => String
      strip dot digits s pos len acc
        | pos >= len = acc
        | (str char at s pos) == 46 = strip dot digits s (pos + 1) len acc
        | otherwise = strip dot digits s (pos + 1) len (acc + (str slice s pos (pos + 1)))

fn :: parse time token trimmed String => Int
      parse time token trimmed "" = 0
      parse time token trimmed t =
        str to int (strip dot digits t 0 (str len t) "")

fn :: parse time token ms String => Int
      parse time token ms s =
        parse time token trimmed (trim ws s)

fn :: parse bash time space String Int Int => Int
      parse bash time space t pos len
        | pos >= len = parse time token ms t
        | (str char at t pos) == 32 =
          u_ms = parse time token ms (str slice t 0 pos)
          s_ms = parse time token ms (str slice t (pos + 1) len)
          u_ms + s_ms
        | otherwise = parse bash time space t (pos + 1) len

fn :: parse bash time ms String => Int
      parse bash time ms raw =
        t = trim ws raw
        parse bash time space t 0 (str len t)

fn :: extract lstat ok (Bool, String, Int, Int, Int, String, String, Int, String) => Bool
      extract lstat ok (ok, _, _, _, _, _, _, _, _) = ok

fn :: file exists String => Bool
      file exists path =
        extract lstat ok (file lstat path)

fn :: pick non empty String String => String
      pick non empty "" fallback = fallback
      pick non empty s _ = s

-- checks run inside work folders, so a relative RIDGUNC / STABLE is taken from the repository root
fn :: absolute from String String => String
      absolute from repo path
        | str starts with path "/" = path
        | otherwise = repo + "/" + path

fn :: resolve ridgunc path String => String
      resolve ridgunc path repo =
        absolute from repo (pick non empty (sys getenv "RIDGUNC") (repo + "/bin/ridgunc"))

fn :: resolve libs default String => String
      resolve libs default repo
        | file exists "/home/boogie/ridgun/libs/target/bundles" = "/home/boogie/ridgun/libs/target/bundles"
        | otherwise = repo + "/.stable/deps"

fn :: resolve libs bundles dir String => String
      resolve libs bundles dir repo =
        pick non empty (sys getenv "RIDGUN_LIBS_BUNDLES") (resolve libs default repo)

fn :: resolve work root from home String => String
      resolve work root from home "" = "/tmp/ridgun-compiler-tests-work"
      resolve work root from home home = home + "/.cache/ridgun-compiler-tests/work"

fn :: resolve work root => String
      resolve work root =
        resolve work root from home (sys getenv "HOME")

fn :: run sh capture String String Int => Int String Int Int
      run sh capture cmd cwd timeout_s =
        out_f = cwd + "/.cmd_out.txt"
        time_f = cwd + "/.cmd_time.txt"
        script_f = cwd + "/.cmd_run.sh"
        script_body = "#!/usr/bin/env bash\ncd \"" + cwd + "\" || exit 1\nulimit -v 4000000\nTIMEFORMAT='%3U %3S'\n{ time timeout " + (int to str timeout_s) + "s " + cmd + " > \"" + out_f + "\" 2>&1; } 2> \"" + time_f + "\"\nexit $?\n"
        write file out_f ""
        write file time_f ""
        write file script_f script_body
        t0 = sys time ms
        code = shell exec ("bash \"" + script_f + "\"")
        t1 = sys time ms
        wall_ms = t1 - t0
        out_txt = read file out_f
        cpu_ms = parse bash time ms (read file time_f)
        (code, out_txt, wall_ms, cpu_ms)

fn :: case runner script => String
      case runner script = (sys getcwd) + "/tests/run_case.sh"

fn :: run case capture String String Int => Int String Int Int Int
      run case capture exe cwd timeout_s =
        out_f = cwd + "/.cmd_out.txt"
        time_f = cwd + "/.cmd_time.txt"
        rss_f = cwd + "/.cmd_rss.txt"
        shell exec ("rm -f \"" + out_f + "\" \"" + time_f + "\" \"" + rss_f + "\"") -> ()
        t0 = sys time ms
        code = shell exec ("bash \"" + case runner script + "\" \"" + cwd + "\" " + (int to str timeout_s) + " \"" + out_f + "\" \"" + time_f + "\" \"" + rss_f + "\" \"" + exe + "\"")
        t1 = sys time ms
        wall_ms = t1 - t0
        out_txt = read file out_f
        cpu_ms = parse bash time ms (read file time_f)
        rss_kb = str to int (pick non empty (trim ws (read file rss_f)) "0")
        (code, out_txt, wall_ms, cpu_ms, rss_kb)

fn :: drop str lines [String] Int => [String]
      drop str lines xs 0 = xs
      drop str lines [] _ = []
      drop str lines (_:xs) n = drop str lines xs (n - 1)

fn :: tail lines count [String] Int Int => [String]
      tail lines count xs n keep
        | n <= keep = xs
        | otherwise = drop str lines xs (n - keep)

fn :: tail lines [String] Int => [String]
      tail lines xs keep =
        tail lines count xs (list len xs) keep

fn :: join indented [String] => String
      join indented [] = ""
      join indented (x:[]) = x
      join indented (x:xs) = x + "\n       " + (join indented xs)

fn :: diff lines step [String] [String] Int Int [String] String String => [String]
      diff lines step w g idx total acc a b
        | a == b = diff lines loop w g (idx + 1) total acc
        | otherwise =
          msg = "       line " + (int to str (idx + 1)) + ": expected '" + a + "'\n                got      '" + b + "'"
          diff lines loop w g (idx + 1) total (acc :: [msg])

fn :: diff lines loop [String] [String] Int Int [String] => [String]
      diff lines loop w g idx total acc
        | idx >= total = acc
        | (list len acc) >= 6 = acc :: ["       ..."]
        | otherwise =
          diff lines step w g idx total acc (nth line w idx) (nth line g idx)

fn :: format output diff String String => String
      format output diff want got =
        w = split lines (strip trailing newline want)
        g = split lines (strip trailing newline got)
        total = max int (list len w) (list len g)
        join lines (diff lines loop w g 0 total [])

fn :: copy libs if needed Bool String String => ()
      copy libs if needed False _ _ = ()
      copy libs if needed True work libs_dir =
        shell exec ("mkdir -p \"" + work + "/.stable/deps\" && cp -f \"" + libs_dir + "\"/*.rglib \"" + work + "/.stable/deps/\" 2>/dev/null || true") -> ()

fn :: check build error result String Bool String String Bool => CaseResult
      check build error result rel True want_err _ prop =
        Result rel False prop ("built, but the build had to fail with: " + want_err)
      check build error result rel False want_err out_txt prop
        | want_err == "" or (str contains out_txt want_err) = Result rel True prop ""
        | otherwise =
          last4 = join indented (tail lines (split lines (trim ws out_txt)) 4)
          Result rel False prop ("the build failed, but without '" + want_err + "':\n       " + last4)

fn :: select want exit Bool Int => Int
      select want exit True v = v
      select want exit False _ = 0

fn :: check exit val Int Int [String] => [String]
      check exit val code want_ex acc
        | code != want_ex = acc :: ["exit " + (int to str code) + ", expected " + (int to str want_ex)]
        | otherwise = acc

fn :: check exit problem Int Bool Int [String] => [String]
      check exit problem code has_ex ex_v acc =
        check exit val code (select want exit has_ex ex_v) acc

fn :: check output problem String Bool String [String] => [String]
      check output problem _ False _ acc = acc
      check output problem out_txt True want_out acc
        | (strip trailing newline out_txt) != (strip trailing newline want_out) =
          acc :: ["output differs:\n" + (format output diff want_out out_txt)]
        | otherwise = acc

fn :: check ms problem Int Bool Int [String] => [String]
      check ms problem _ False _ acc = acc
      check ms problem ms True max_ms acc
        | ms > max_ms = acc :: ["took " + (int to str ms) + " ms, limit " + (int to str max_ms) + " ms"]
        | otherwise = acc

fn :: check cpu problem Int Int Bool Int [String] => [String]
      check cpu problem _ _ False _ acc = acc
      check cpu problem cpu_ms wall_ms True max_cpu acc
        | cpu_ms > max_cpu =
          acc :: ["used " + (int to str cpu_ms) + " ms of CPU in " + (int to str wall_ms) + " ms of wall time, limit " + (int to str max_cpu) + " ms"]
        | otherwise = acc

fn :: check rss problem Int Bool Int [String] => [String]
      check rss problem _ False _ acc = acc
      check rss problem rss_kb True max_mb acc
        | rss_kb > (max_mb * 1024) =
          acc :: ["peak resident memory " + (int to str ((rss_kb + 1023) / 1024)) + " MB (" + (int to str rss_kb) + " kB), limit " + (int to str max_mb) + " MB"]
        | otherwise = acc

fn :: finish case problems String Bool [String] => CaseResult
      finish case problems rel prop [] = Result rel True prop ""
      finish case problems rel prop probs = Result rel False prop (join indented probs)

fn :: evaluate case run String CaseHeader (Int, String, Int, Int, Int) => CaseResult
      evaluate case run rel (Header _ _ has_out out_s _ _ has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v _ prop) (code, out_txt, wall_ms, cpu_ms, rss_kb) =
        p0 = check exit problem code has_ex ex_v []
        p1 = check output problem out_txt has_out out_s p0
        p2 = check ms problem wall_ms has_ms ms_v p1
        p3 = check cpu problem cpu_ms wall_ms has_cpu cpu_v p2
        p4 = check rss problem rss_kb has_rss rss_v p3
        finish case problems rel prop p4

fn :: case timeout seconds CaseHeader => Int
      case timeout seconds (Header _ _ _ _ _ _ _ _ True ms_v _ _ _ _ _ _) =
        max int 5 ((ms_v + 999) / 1000)
      case timeout seconds _ = 30

fn :: run built case String String CaseHeader => CaseResult
      run built case label work hdr =
        exe = work + "/target/case"
        evaluate case run label hdr (run case capture exe work (case timeout seconds hdr))

fn :: finish case build String String String CaseHeader (Int, String, Int, Int) => CaseResult
      finish case build label work exe (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop) (b_code, b_out, _, _) =
        built = b_code == 0 and (file exists exe)
        dispatch built case label work built ( b_out ) (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)

fn :: dispatch built case String String Bool String CaseHeader => CaseResult
      dispatch built case label _ built b_out (Header _ _ _ _ True berr_s _ _ _ _ _ _ _ _ _ prop) =
        check build error result label built berr_s b_out prop
      dispatch built case label _ False b_out (Header _ _ _ _ False _ _ _ _ _ _ _ _ _ _ prop) =
        last4 = join indented (tail lines (split lines (trim ws b_out)) 4)
        Result label False prop ("does not build:\n       " + last4)
      dispatch built case label work True _ hdr =
        run built case label work hdr

fn :: strict flag for case String => String
      strict flag for case full_path
        | str contains (read file full_path) "-- no-strict" = " "
        | otherwise = " --strict "

fn :: backend label String => String
      backend label "" = ""
      backend label target = " [" + target + "]"

fn :: backend target flag String => String
      backend target flag "" = ""
      backend target flag target = " --target " + target

fn :: backend work root String String => String
      backend work root work_root "" = work_root + "/llvm"
      backend work root work_root target = work_root + "/" + target

-- Wall-time and CPU limits are promises for LLVM (FR-COMP-011 AC-4); on another target a case checks
-- output, exit status and memory (FR-COMP-004 AC-5, FR-COMP-020) and may run for the default 30 s.
fn :: backend header String CaseHeader => CaseHeader
      backend header "" hdr = hdr
      backend header _ (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v _ ms_v has_rss rss_v _ cpu_v libs prop) =
        Header c_desc src has_out out_s has_berr berr_s has_ex ex_v False ms_v has_rss rss_v False cpu_v libs prop

fn :: execute case with header String String String String String String CaseHeader => CaseResult
      execute case with header _ label _ _ _ _ (Header _ "" _ _ _ _ _ _ _ _ _ _ _ _ _ prop) =
        Result label False prop "the case has no '-- source:' line"
      execute case with header full_path label ridgunc libs_dir work target (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop) =
        shell exec ("mkdir -p \"" + work + "/target\" && cp -f \"" + full_path + "\" \"" + work + "/main.rg\"") -> ()
        copy libs if needed libs work libs_dir
        exe = work + "/target/case"
        hdr = backend header target (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)
        sflag = strict flag for case full_path
        tflag = backend target flag target
        finish case build label work exe hdr (run sh capture ("\"" + ridgunc + "\" build" + sflag + "main.rg -o \"" + exe + "\"" + tflag) work 600)

fn :: execute single case String String String String String String => CaseResult
      execute single case repo ridgunc libs_dir work_root target rel =
        full_path = repo + "/tests/cases/" + rel
        hdr = parse case header full_path
        work = (backend work root work_root target) + "/" + (sanitize case name rel)
        execute case with header full_path (rel + (backend label target)) ridgunc libs_dir work target hdr

fn :: step word next Int String String => String
      step word next 0 ch acc = "step " + ch + acc
      step word next next_i ch acc = step word loop next_i (ch + acc)

fn :: step word loop Int String => String
      step word loop i acc =
        ch = char from code (97 + (i % 26))
        step word next (i / 26) ch acc

fn :: step fn name Int => String
      step fn name i = step word loop i ""

fn :: gen many fns loop Int Int String => String
      gen many fns loop idx limit acc
        | idx >= limit = acc
        | otherwise =
          nm = step fn name idx
          decl = "fn :: " + nm + " Int => Int\n      " + nm + " x =  x + " + (int to str idx) + "\n\n"
          gen many fns loop (idx + 1) limit (acc + decl)

fn :: append call term String String => String
      append call term "" term = term
      append call term acc term = acc + " + " + term

fn :: gen many calls loop Int Int String => String
      gen many calls loop idx limit acc
        | idx >= limit = acc
        | otherwise =
          nm = step fn name idx
          term = "(" + nm + " 1)"
          gen many calls loop (idx + 50) limit (append call term acc term)

fn :: gen many program Int => String
      gen many program n =
        defs = gen many fns loop 0 n ""
        calls = gen many calls loop 0 n ""
        defs + "fn :: main => ()\n      main =  echo (int to str (" + calls + "))\n"

fn :: build tc1 result String (Int, String, Int, Int) => CaseResult
      build tc1 result d (c1, o1, _, _) =
        ex1 = file exists (d + "/no/such/folder/hello")
        ok1 = ex1 or c1 != 0
        Result "toolchain: -o into a folder that doesn't exist either creates it or fails (exit != 0); never reports success without the file (Solstice register RG-081)" ok1 False ("exit " + (int to str c1) + "; output: " + (trim ws o1))

fn :: build tc2 result String (Int, String, Int, Int) => CaseResult
      build tc2 result d (c2, o2, _, _) =
        ok2 = c2 != 0 and (not (file exists (d + "/bad")))
        Result "toolchain: a type error exits with a non-zero status and writes no binary" ok2 False ("exit " + (int to str c2) + "; output: " + (trim ws o2))

fn :: build tc3 result (Int, String, Int, Int) (Int, String, Int, Int) => CaseResult
      build tc3 result (cm1, _, tm1, _) (cm2, _, tm2, _) =
        base_t = max int tm1 300
        ok3 = cm1 == 0 and cm2 == 0 and tm2 <= (base_t * 8)
        Result "toolchain: build time is near-linear in the number of functions (200 -> 800 functions: at most 8x the time; quadratic is 16x)" ok3 False ("200 functions " + (int to str tm1) + " ms (exit " + (int to str cm1) + "), 800 functions " + (int to str tm2) + " ms (exit " + (int to str cm2) + ")")

fn :: build tc4 result (Int, String, Int, Int) => CaseResult
      build tc4 result (cl, _, tl, _) =
        ok4 = cl == 0 and tl <= 3000
        Result "toolchain: building a program that imports standard libraries (str, io, list, cli) completes in under 3000 ms (RG-075)" ok4 False ("built in " + (int to str tl) + " ms (exit " + (int to str cl) + ")")

fn :: build tc5 result (Int, String, Int, Int) => CaseResult
      build tc5 result (cs, os, _, _) =
        ok5 = cs != 0 and (str contains os "syntax error at") and (str contains os "syntax_bad.rg:2:")
        Result "toolchain: a syntax error reports 'syntax error at <file>:<line>:<col>' instead of 'type error in function syntax' (CH-001)" ok5 False ("exit " + (int to str cs) + "; output: " + (trim ws os))

fn :: build tc6 result (Int, String, Int, Int) => CaseResult
      build tc6 result (c6, o6, _, _) =
        ok6 = c6 == 0 and (str contains o6 "MATCH_OK") and (str contains o6 "NO_BUILD_RG_OK") and (str contains o6 "FAIL_ON_MISSING_OK")
        Result "toolchain: stable deps copies the folder omni.lock names for a package without missing files, excludes root build.rg from lib/ (RG-107), and rejects paths, URLs, local lock entries, a wrong version and a name omni did not install (ADR-0003)" ok6 False ("exit " + (int to str c6) + "; output: " + (trim ws o6))

fn :: build tc7 result (Int, String, Int, Int) => CaseResult
      build tc7 result (c7, o7, _, _) =
        ok7 = c7 == 0 and (str contains o7 "REFRESH_OK")
        Result "toolchain: stable deps refreshes updated .rglib bundles from the package folder omni installed (RG-105)" ok7 False ("exit " + (int to str c7) + "; output: " + (trim ws o7))

fn :: build tc8 result (Int, String, Int, Int) => CaseResult
      build tc8 result (c8, o8, _, _) =
        ok8 = c8 == 0 and (trim ws o8) == "1 []"
        Result "toolchain: inside an imported lib, a record field name means the lib's accessor even when the program defines a function with that name (FR-COMP-012; libs report 2026-11-08)" ok8 False ("exit " + (int to str c8) + "; output: " + (trim ws o8))

fn :: build tc9 result (Int, String, Int, Int) => CaseResult
      build tc9 result (c9, o9, _, _) =
        ok9 = c9 == 0 and (trim ws o9) == "True k:a"
        Result "toolchain: inside an imported module, a multi-word call whose first word is a parameter keeps its name even when the program defines a function named like another of its words (FR-COMP-012; Solstice report 2026-11-10)" ok9 False ("exit " + (int to str c9) + "; output: " + (trim ws o9))

fn :: build tc10 result (Int, String, Int, Int) => CaseResult
      build tc10 result (c10, o10, _, _) =
        ok10 = c10 == 0 and (trim ws o10) == "[7] [a] [2, 1] 5 5\nPRELUDE_OK"
        Result "toolchain: a prelude name defined by an imported module means the module's function, with no ambiguity error, also when the name holds an operator word (`list nth or`, as in libs); a module that imports nothing gets the prelude's; `ridgunc prelude` prints the prelude (FR-COMP-024)" ok10 False ("exit " + (int to str c10) + "; output: " + (trim ws o10))

fn :: build tc11 result (Int, String, Int, Int) => CaseResult
      build tc11 result (c11, o11, _, _) =
        ok11 = c11 == 0 and (trim ws o11) == "200000 120 10"
        Result "toolchain: read bytes \"/dev/stdin\" reads every byte when stdin is a pipe, also past the first 64 KiB (FR-COMP-022; libs report tensor-u8 2026-11-09, item 6)" ok11 False ("exit " + (int to str c11) + "; output: " + (trim ws o11))

fn :: build tc12 result (Int, String, Int, Int) => CaseResult
      build tc12 result (c12, o12, _, _) =
        ok12 = c12 == 0 and (trim ws o12) == "LINK_OK\nREFUSE_OK\nUNLINK_OK"
        Result "toolchain: `stable dev link` builds a dependency from a local checkout with a warning, only from ~/.stable/dev-links; links to another project, a path as name or a folder with shell characters are refused; an invalid link stops `stable deps`; after `stable dev unlink` the name resolves through omni again (FR-TOOL-002 AC5, ADR-0005)" ok12 False ("exit " + (int to str c12) + "; output: " + (trim ws o12))

fn :: build tc13 result (Int, String, Int, Int) => CaseResult
      build tc13 result (c13, o13, _, _) =
        ok13 = c13 == 0 and (trim ws o13) == "FIRST_OK\nREBUILT_OK\nCACHED_OK"
        Result "toolchain: `stable run` creates target/, rebuilds when a source changed since the last build (also within the same second) and runs the existing binary when nothing changed (FR-TOOL-002; compiler defect report 2026-11-11, item 3)" ok13 False ("exit " + (int to str c13) + "; output: " + (trim ws o13))

fn :: build tc14 result (Int, String, Int, Int) => CaseResult
      build tc14 result (c14, o14, _, _) =
        ok14 = c14 == 0 and (trim ws o14) == "SOURCES_CLEAN_OK\nIMPORT_OK"
        Result "toolchain: `stable deps` keeps a package under .stable/deps and writes nothing into the project's sources; its modules still import (FR-TOOL-002 AC7; stable feedback 2026-11-12)" ok14 False ("exit " + (int to str c14) + "; output: " + (trim ws o14))

fn :: resolve stable path String => String
      resolve stable path repo =
        absolute from repo (pick non empty (sys getenv "STABLE") (repo + "/bin/stable"))

fn :: run toolchain checks String String String String => [CaseResult]
      run toolchain checks repo ridgunc libs_dir work_root =
        d = work_root + "/toolchain"
        stable_bin = resolve stable path repo
        shell exec ("rm -rf \"" + d + "\" && mkdir -p \"" + d + "\"") -> ()
        write file (d + "/hello.rg") "fn :: main => ()\n      main =  echo \"hello\"\n"
        r1 = build tc1 result d (run sh capture ("\"" + ridgunc + "\" build --strict hello.rg -o no/such/folder/hello") d 600)
        write file (d + "/bad.rg") "fn :: main => ()\n      main =  echo (1 + \"a\")\n"
        r2 = build tc2 result d (run sh capture ("\"" + ridgunc + "\" build --strict bad.rg -o bad") d 600)
        write file (d + "/many200.rg") (gen many program 200)
        write file (d + "/many800.rg") (gen many program 800)
        m1_res = run sh capture ("\"" + ridgunc + "\" build many200.rg -o many200") d 600
        m2_res = run sh capture ("\"" + ridgunc + "\" build many800.rg -o many800") d 600
        r3 = build tc3 result m1_res m2_res
        copy libs if needed True d libs_dir
        write file (d + "/lib_perf.rg") "import str\nimport io\nimport list\nimport cli\n\nfn :: main => ()\n      main =  echo (str trim left \"  hello  \")\n"
        r4 = build tc4 result (run sh capture ("\"" + ridgunc + "\" build --strict lib_perf.rg -o lib_perf") d 600)
        write file (d + "/syntax_bad.rg") "fn :: broken Int => [Int]\n      broken x = [x, x + 1]]\n"
        r5 = build tc5 result (run sh capture ("\"" + ridgunc + "\" check syntax_bad.rg") d 600)
        tc6_sh = "set -e; O=\"" + d + "/outer\"; mkdir -p \"$O/src/main/ridgun/lib\" \"$O/alpha\" \"$O/zeta\" \"$O/inner/src/main/ridgun\"; cd \"$O\"; printf 'fn :: project name => String\\n      project name =  \"outer\"\\nfn :: project kind => String\\n      project kind =  \"lib\"\\nfn :: project version => String\\n      project version =  \"0.1.0\"\\n' > build.rg; printf 'fn :: hello => Int\\n      hello =  1\\n' > src/main/ridgun/lib/outer.rg; touch alpha/a zeta/z README.md; cd inner; printf 'fn :: project name => String\\n      project name =  \"inner\"\\nfn :: project version => String\\n      project version =  \"0.1.0\"\\nfn :: main entry => String\\n      main entry =  \"main.rg\"\\nfn :: dependencies => [String]\\n      dependencies =  [\"outer\"]\\n' > build.rg; printf 'fn :: locked packages => [String]\\n      locked packages =  [\"outer|outer||0.1.0||%s\"]\\n' \"$O\" > omni.lock; printf 'fn :: main => ()\\n      main =  echo 1\\n' > src/main/ridgun/main.rg; \"" + stable_bin + "\" deps >/dev/null; S=$(ls -A \"$O\" | sort | tr '\\n' ' '); C=$(ls -A .stable/deps/outer | sort | tr '\\n' ' '); [ \"$S\" = \"$C\" ] && echo MATCH_OK; [ ! -e src/main/ridgun/lib/build.rg ] && echo NO_BUILD_RG_OK; for dep in /nonexistent/rg_dep_xyz https://example.invalid/x.git git@example.invalid:x.git ../outer missingpkg outer@9.9.9; do printf 'fn :: project name => String\\n      project name =  \"bad\"\\nfn :: dependencies => [String]\\n      dependencies =  [\"%s\"]\\n' \"$dep\" > build.rg; if \"" + stable_bin + "\" deps >/dev/null 2>&1; then exit 1; fi; done; printf 'fn :: locked packages => [String]\\n      locked packages =  [\"outer|||local||%s\"]\\n' \"$O\" > omni.lock; printf 'fn :: dependencies => [String]\\n      dependencies =  [\"outer\"]\\n' > build.rg; if \"" + stable_bin + "\" deps >/dev/null 2>&1; then exit 1; fi; [ ! -e .stable/deps/x.git ] && [ ! -e .stable/deps/x ] && echo FAIL_ON_MISSING_OK"
        write file (d + "/tc6.sh") tc6_sh
        r6 = build tc6 result (run sh capture "bash tc6.sh" d 60)
        tc7_sh = "set -e; B=\"" + d + "/rg105\"; mkdir -p \"$B/dep/src/main/ridgun/lib\" \"$B/dep/target/bundles\" \"$B/app\"; printf 'fn :: project name => String\\n      project name =  \"dep\"\\n' > \"$B/dep/build.rg\"; echo \"version 1\" > \"$B/dep/target/bundles/thing.rglib\"; printf 'fn :: project name => String\\n      project name =  \"app\"\\n\\nfn :: dependencies => [String]\\n      dependencies =  [\"dep\"]\\n' > \"$B/app/build.rg\"; printf 'fn :: locked packages => [String]\\n      locked packages =  [\"dep|dep||0.1.0||%s\"]\\n' \"$B/dep\" > \"$B/app/omni.lock\"; cd \"$B/app\"; \"" + stable_bin + "\" deps >/dev/null; V1=$(cat .stable/deps/thing.rglib); echo \"version 2\" > \"$B/dep/target/bundles/thing.rglib\"; \"" + stable_bin + "\" deps >/dev/null; V2=$(cat .stable/deps/thing.rglib); [ \"$V1\" = \"version 1\" ] && [ \"$V2\" = \"version 2\" ] && echo REFRESH_OK"
        write file (d + "/tc7.sh") tc7_sh
        r7 = build tc7 result (run sh capture "bash tc7.sh" d 60)
        write file (d + "/box.rg") "module :: box\n\ntype Box = items: [Int], size: Int\n\nfn :: box new => Box\n      box new = Box [1, 2, 3] 3\n\nfn :: box first Box => Int\n      box first b = first of (items b)\n\nfn :: first of [Int] => Int\n      first of (x:_) = x\n"
        write file (d + "/field_main.rg") "import box\n\nfn :: items Int => [Int]\n      items n = []\n\nfn :: main => ()\n      main =\n        echo \"{{box first box new}} {{items 5}}\"\n"
        r8 = build tc8 result (run sh capture ("\"" + ridgunc + "\" build field_main.rg -o field_main >/dev/null && ./field_main") d 600)
        write file (d + "/errmod.rg") "type K = KNone | KBad\ntype E = kind: K, msg: String\n\nfn :: err kind eq K K => Bool\n      err kind eq KNone KNone =  True\n      err kind eq KBad  KBad  =  True\n      err kind eq _     _     =  False\n\nfn :: is ok E => Bool\n      is ok err =  err kind eq (kind err) KNone\n"
        write file (d + "/local_head_main.rg") "import errmod\n\nfn :: kind String => String\n      kind s =  \"k:\" + s\n\nfn :: main => ()\n      main =\n        echo (is ok (E KNone \"x\")) (kind \"a\")\n"
        r9 = build tc9 result (run sh capture ("\"" + ridgunc + "\" build local_head_main.rg -o local_head_main >/dev/null && ./local_head_main") d 600)
        write file (d + "/intlist.rg") "fn :: list take [Int] Int => [Int]\n      list take _ _ =  [7]\n\nfn :: list nth [Int] Int => Int\n      list nth xs i =  list nth or xs i 0\n\nfn :: list nth or [Int] Int Int => Int\n      list nth or _ _ _ =  5\n"
        write file (d + "/other.rg") "fn :: other take => [String]\n      other take =  list take [\"a\", \"b\"] 1\n"
        write file (d + "/prelude_main.rg") "import intlist\nimport other\n\nfn :: main => ()\n      main =  echo (list take [1, 2] 1) (other take) (list reverse [1, 2]) (list nth or [1] 0 0) (list nth [1] 0)\n"
        write file (d + "/tc10.sh") ("set -e; \"" + ridgunc + "\" build prelude_main.rg -o prelude_main >/dev/null; ./prelude_main; \"" + ridgunc + "\" prelude | grep -q '^fn :: list reverse' && echo PRELUDE_OK")
        r10 = build tc10 result (run sh capture "bash tc10.sh" d 600)
        write file (d + "/stdin_bytes.rg") "fn :: size of Tensor[U8] => Int\n      size of (Tensor[U8 * n] _) = n\n\nfn :: main => ()\n      main =\n        t = read bytes \"/dev/stdin\"\n        echo (size of t) (t_(0)) (t_(199999))\n"
        write file (d + "/tc11.sh") ("set -e; \"" + ridgunc + "\" build stdin_bytes.rg -o stdin_bytes >/dev/null; yes x | head -c 200000 | ./stdin_bytes")
        r11 = build tc11 result (run sh capture "bash tc11.sh" d 600)
        r12 = build tc12 result (run sh capture ("bash \"" + repo + "/tests/toolchain/stable_dev_links.sh\" \"" + stable_bin + "\" \"" + d + "\"") d 120)
        r13 = build tc13 result (run sh capture ("bash \"" + repo + "/tests/toolchain/stable_run_rebuilds.sh\" \"" + stable_bin + "\" \"" + d + "\"") d 600)
        r14 = build tc14 result (run sh capture ("bash \"" + repo + "/tests/toolchain/stable_deps_keeps_sources.sh\" \"" + stable_bin + "\" \"" + d + "\"") d 600)
        [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14]

fn :: print case result CaseResult => ()
      print case result (Result name True _ _) =
        echo ("ok    " + name)
      print case result (Result name False True msg) =
        echo ("UNMET " + name + "\n       " + msg)
      print case result (Result name False False msg) =
        echo ("FAIL  " + name + "\n       " + msg)

fn :: matches any filter String [String] => Bool
      matches any filter _ [] = False
      matches any filter rel (f:fs)
        | str contains rel f = True
        | otherwise = matches any filter rel fs

fn :: filter cases by args [String] [String] => [String]
      filter cases by args cases [] = cases
      filter cases by args [] _ = []
      filter cases by args (c:cs) filters
        | matches any filter c filters = [c] :: (filter cases by args cs filters)
        | otherwise = filter cases by args cs filters

fn :: split non empty lines String => [String]
      split non empty lines "" = []
      split non empty lines raw = split lines raw

fn :: discover cases String String => [String]
      discover cases repo work_root =
        list_f = work_root + "/.cases_list.txt"
        cases_dir = repo + "/tests/cases"
        shell exec ("cd \"" + cases_dir + "\" && find . -name '*.rg' | sed 's|^\\./||' | sort > \"" + list_f + "\"") -> ()
        split non empty lines (trim ws (read file list_f))

fn :: strip runner argv [String] => [String]
      strip runner argv [] = []
      strip runner argv (_:"run":_:rest) = rest
      strip runner argv (_:rest) = rest

fn :: has no toolchain flag [String] => Bool
      has no toolchain flag [] = False
      has no toolchain flag ("--no-toolchain":_) = True
      has no toolchain flag (_:xs) = has no toolchain flag xs

fn :: non flag args [String] => [String]
      non flag args [] = []
      non flag args (a:as)
        | str starts with a "--" = non flag args as
        | otherwise = [a] :: (non flag args as)

fn :: has flag String [String] => Bool
      has flag _ [] = False
      has flag f (x:xs)
        | x == f = True
        | otherwise = has flag f xs

fn :: select backends Bool Bool => [String]
      select backends True False = [""]
      select backends False True = ["x86_64-elf"]
      select backends _ _ = ["", "x86_64-elf"]

fn :: run case on backends String [String] String String String String [CaseResult] => [CaseResult]
      run case on backends _ [] _ _ _ _ acc = acc
      run case on backends c (t:ts) repo ridgunc libs_dir work_root acc =
        res = execute single case repo ridgunc libs_dir work_root t c
        print case result res
        run case on backends c ts repo ridgunc libs_dir work_root (acc :: [res])

fn :: run case list [String] [String] String String String String [CaseResult] => [CaseResult]
      run case list [] _ _ _ _ _ acc = acc
      run case list (c:cs) targets repo ridgunc libs_dir work_root acc =
        run case list cs targets repo ridgunc libs_dir work_root (run case on backends c targets repo ridgunc libs_dir work_root acc)

fn :: print result list [CaseResult] => ()
      print result list [] = ()
      print result list (r:rs) =
        print case result r
        print result list rs

fn :: maybe run toolchain Bool [String] String String String String => [CaseResult]
      maybe run toolchain False [] repo ridgunc libs_dir work_root =
        tc = run toolchain checks repo ridgunc libs_dir work_root
        print result list tc
        tc
      maybe run toolchain _ _ _ _ _ _ = []

fn :: collect failed names [CaseResult] => [String]
      collect failed names [] = []
      collect failed names ((Result name False False _):rs) = [name] :: (collect failed names rs)
      collect failed names (_:rs) = collect failed names rs

fn :: collect unmet names [CaseResult] => [String]
      collect unmet names [] = []
      collect unmet names ((Result name False True _):rs) = [name] :: (collect unmet names rs)
      collect unmet names (_:rs) = collect unmet names rs

fn :: count promised [CaseResult] => Int
      count promised [] = 0
      count promised ((Result _ _ True _):rs) = count promised rs
      count promised (_:rs) = 1 + (count promised rs)

fn :: join lines indent [String] => String
      join lines indent [] = ""
      join lines indent (x:[]) = x
      join lines indent (x:xs) = x + "\n  " + (join lines indent xs)

fn :: format summary list [String] => String
      format summary list [] = ""
      format summary list xs = ":\n  " + (join lines indent xs)

fn :: report unmet [String] => ()
      report unmet [] = ()
      report unmet unmet =
        n = list len unmet
        echo ((int to str n) + " proposal(s) not met (no document promises them; they don't fail the run):\n  " + (join lines indent unmet))

fn :: exit by failed count Int => ()
      exit by failed count 0 = sys exit 0
      exit by failed count _ = sys exit 1

fn :: same bool Bool Bool => Bool
      same bool True True = True
      same bool False False = True
      same bool _ _ = False

fn :: is x86 row String => Bool
      is x86 row name = str contains name (backend label "x86_64-elf")

fn :: backend tally [CaseResult] Bool Int Int => Int Int
      backend tally [] _ total passed = (total, passed)
      backend tally ((Result name ok prop _):rs) want_x86 total passed
        | prop or (not (same bool (is x86 row name) want_x86)) = backend tally rs want_x86 total passed
        | ok = backend tally rs want_x86 (total + 1) (passed + 1)
        | otherwise = backend tally rs want_x86 (total + 1) passed

fn :: format tally String (Int, Int) => String
      format tally label (0, _) = label + " not run"
      format tally label (total, passed) = label + " " + (int to str passed) + " of " + (int to str total)

fn :: finish test run [CaseResult] => ()
      finish test run rows =
        failed = collect failed names rows
        unmet = collect unmet names rows
        promised_c = count promised rows
        failed_c = list len failed
        passed_c = promised_c - failed_c
        echo ("\n" + (int to str passed_c) + " of " + (int to str promised_c) + " promised behaviours passed" + (format summary list failed))
        echo ("by backend: " + (format tally "llvm" (backend tally rows False 0 0)) + "; " + (format tally "x86_64-elf" (backend tally rows True 0 0)))
        report unmet unmet
        exit by failed count failed_c

fn :: print banner String String String => ()
      print banner repo ridgunc work_root =
        hdr_f = work_root + "/.banner.txt"
        shell exec ("git -c safe.directory=\"" + repo + "\" log -1 --format='%h %cd' --date='format:%Y-%m-%d %H:%M' > \"" + hdr_f + "\" 2>/dev/null") -> ()
        head_s = trim ws (read file hdr_f)
        shell exec ("\"" + ridgunc + "\" --version 2>/dev/null | head -n 1 > \"" + hdr_f + "\"") -> ()
        ver_s = trim ws (read file hdr_f)
        echo ("ridgun " + head_s + "; " + ridgunc + " " + ver_s + "\n")

fn :: main => ()
      main =
        raw_args = strip runner argv cli args
        no_tc = has no toolchain flag raw_args
        filters = non flag args raw_args
        targets = select backends (has flag "--llvm" raw_args) (has flag "--x86" raw_args)
        repo = sys getcwd
        ridgunc = resolve ridgunc path repo
        libs_dir = resolve libs bundles dir repo
        work_root = resolve work root
        shell exec ("rm -rf \"" + work_root + "\" && mkdir -p \"" + work_root + "\"") -> ()
        print banner repo ridgunc work_root
        all_cases = discover cases repo work_root
        selected = filter cases by args all_cases filters
        case_rows = run case list selected targets repo ridgunc libs_dir work_root []
        tc_rows = maybe run toolchain no_tc filters repo ridgunc libs_dir work_root
        finish test run (case_rows :: tc_rows)
