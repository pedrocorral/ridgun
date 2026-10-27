-- ============================================================
-- tests/run.rg
-- Pure Ridgun acceptance & performance test runner for ridgunc
-- Usage:
--   ./bin/ridgunc run tests/run.rg                  (all cases + toolchain checks)
--   ./bin/ridgunc run tests/run.rg lists strings    (cases matching filter)
--   ./bin/ridgunc run tests/run.rg --no-toolchain   (cases only)
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
        | (str char at s (n - 1)) == 10 OR (str char at s (n - 1)) == 13 =
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
        (ch >= 65 AND ch <= 90) OR (ch >= 97 AND ch <= 122) OR (ch >= 48 AND ch <= 57) OR ch == 95

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
        | NOT (str starts with line "--") =
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

fn :: resolve ridgunc path String => String
      resolve ridgunc path repo =
        pick non empty (sys getenv "RIDGUNC") (repo + "/bin/ridgunc")

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
        write file script_f script_body
        t0 = sys time ms
        code = shell exec ("bash \"" + script_f + "\"")
        t1 = sys time ms
        wall_ms = t1 - t0
        out_txt = read file out_f
        cpu_ms = parse bash time ms (read file time_f)
        (code, out_txt, wall_ms, cpu_ms)

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
        | want_err == "" OR (str contains out_txt want_err) = Result rel True prop ""
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

fn :: finish case problems String Bool [String] => CaseResult
      finish case problems rel prop [] = Result rel True prop ""
      finish case problems rel prop probs = Result rel False prop (join indented probs)

fn :: evaluate case run String CaseHeader (Int, String, Int, Int) => CaseResult
      evaluate case run rel (Header _ _ has_out out_s _ _ has_ex ex_v has_ms ms_v _ _ has_cpu cpu_v _ prop) (code, out_txt, wall_ms, cpu_ms) =
        p0 = check exit problem code has_ex ex_v []
        p1 = check output problem out_txt has_out out_s p0
        p2 = check ms problem wall_ms has_ms ms_v p1
        p3 = check cpu problem cpu_ms wall_ms has_cpu cpu_v p2
        finish case problems rel prop p3

fn :: run built case String String CaseHeader => CaseResult
      run built case rel work hdr =
        exe = work + "/target/case"
        evaluate case run rel hdr (run sh capture ("\"" + exe + "\"") work 300)

fn :: finish case build String String String CaseHeader (Int, String, Int, Int) => CaseResult
      finish case build rel work exe (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop) (b_code, b_out, _, _) =
        built = b_code == 0 AND (file exists exe)
        dispatch built case rel work built ( b_out ) (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop)

fn :: dispatch built case String String Bool String CaseHeader => CaseResult
      dispatch built case rel _ built b_out (Header _ _ _ _ True berr_s _ _ _ _ _ _ _ _ _ prop) =
        check build error result rel built berr_s b_out prop
      dispatch built case rel _ False b_out (Header _ _ _ _ False _ _ _ _ _ _ _ _ _ _ prop) =
        last4 = join indented (tail lines (split lines (trim ws b_out)) 4)
        Result rel False prop ("does not build:\n       " + last4)
      dispatch built case rel work True _ hdr =
        run built case rel work hdr

fn :: strict flag for case String => String
      strict flag for case full_path
        | str contains (read file full_path) "-- no-strict" = " "
        | otherwise = " --strict "

fn :: execute case with header String String String String String CaseHeader => CaseResult
      execute case with header _ rel _ _ _ (Header _ "" _ _ _ _ _ _ _ _ _ _ _ _ _ prop) =
        Result rel False prop "the case has no '-- source:' line"
      execute case with header full_path rel ridgunc libs_dir work_root (Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop) =
        name = sanitize case name rel
        work = work_root + "/" + name
        shell exec ("mkdir -p \"" + work + "/target\" && cp -f \"" + full_path + "\" \"" + work + "/main.rg\"") -> ()
        copy libs if needed libs work libs_dir
        exe = work + "/target/case"
        hdr = Header c_desc src has_out out_s has_berr berr_s has_ex ex_v has_ms ms_v has_rss rss_v has_cpu cpu_v libs prop
        sflag = strict flag for case full_path
        finish case build rel work exe hdr (run sh capture ("\"" + ridgunc + "\" build" + sflag + "main.rg -o \"" + exe + "\"") work 600)

fn :: execute single case String String String String String => CaseResult
      execute single case repo ridgunc libs_dir work_root rel =
        full_path = repo + "/tests/cases/" + rel
        hdr = parse case header full_path
        execute case with header full_path rel ridgunc libs_dir work_root hdr

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
        ok1 = ex1 OR c1 != 0
        Result "toolchain: -o into a folder that doesn't exist either creates it or fails (exit != 0); never reports success without the file (Solstice register RG-081)" ok1 False ("exit " + (int to str c1) + "; output: " + (trim ws o1))

fn :: build tc2 result String (Int, String, Int, Int) => CaseResult
      build tc2 result d (c2, o2, _, _) =
        ok2 = c2 != 0 AND (NOT (file exists (d + "/bad")))
        Result "toolchain: a type error exits with a non-zero status and writes no binary" ok2 False ("exit " + (int to str c2) + "; output: " + (trim ws o2))

fn :: build tc3 result (Int, String, Int, Int) (Int, String, Int, Int) => CaseResult
      build tc3 result (cm1, _, tm1, _) (cm2, _, tm2, _) =
        base_t = max int tm1 300
        ok3 = cm1 == 0 AND cm2 == 0 AND tm2 <= (base_t * 8)
        Result "toolchain: build time is near-linear in the number of functions (200 -> 800 functions: at most 8x the time; quadratic is 16x)" ok3 False ("200 functions " + (int to str tm1) + " ms (exit " + (int to str cm1) + "), 800 functions " + (int to str tm2) + " ms (exit " + (int to str cm2) + ")")

fn :: build tc4 result (Int, String, Int, Int) => CaseResult
      build tc4 result (cl, _, tl, _) =
        ok4 = cl == 0 AND tl <= 3000
        Result "toolchain: building a program that imports standard libraries (str, io, list, cli) completes in under 3000 ms (RG-075)" ok4 False ("built in " + (int to str tl) + " ms (exit " + (int to str cl) + ")")

fn :: run toolchain checks String String String => [CaseResult]
      run toolchain checks ridgunc libs_dir work_root =
        d = work_root + "/toolchain"
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
        [r1, r2, r3, r4]

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

fn :: run case list [String] String String String String [CaseResult] => [CaseResult]
      run case list [] _ _ _ _ acc = acc
      run case list (c:cs) repo ridgunc libs_dir work_root acc =
        res = execute single case repo ridgunc libs_dir work_root c
        print case result res
        run case list cs repo ridgunc libs_dir work_root (acc :: [res])

fn :: print result list [CaseResult] => ()
      print result list [] = ()
      print result list (r:rs) =
        print case result r
        print result list rs

fn :: maybe run toolchain Bool [String] String String String => [CaseResult]
      maybe run toolchain False [] ridgunc libs_dir work_root =
        tc = run toolchain checks ridgunc libs_dir work_root
        print result list tc
        tc
      maybe run toolchain _ _ _ _ _ = []

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

fn :: finish test run [CaseResult] => ()
      finish test run rows =
        failed = collect failed names rows
        unmet = collect unmet names rows
        promised_c = count promised rows
        failed_c = list len failed
        passed_c = promised_c - failed_c
        echo ("\n" + (int to str passed_c) + " of " + (int to str promised_c) + " promised behaviours passed" + (format summary list failed))
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
        repo = sys getcwd
        ridgunc = resolve ridgunc path repo
        libs_dir = resolve libs bundles dir repo
        work_root = resolve work root
        shell exec ("rm -rf \"" + work_root + "\" && mkdir -p \"" + work_root + "\"") -> ()
        print banner repo ridgunc work_root
        all_cases = discover cases repo work_root
        selected = filter cases by args all_cases filters
        case_rows = run case list selected repo ridgunc libs_dir work_root []
        tc_rows = maybe run toolchain no_tc filters ridgunc libs_dir work_root
        finish test run (case_rows :: tc_rows)
