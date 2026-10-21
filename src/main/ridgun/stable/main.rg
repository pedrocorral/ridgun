-- ============================================================
-- src/main/ridgun/stable/main.rg
-- `stable` v0.9.3 — The Interactive Build Tool for Ridgun (100% Ridgun)
-- Written in Ridgun's natural-language mixfix operator style (`op :: ...`).
-- Inspired by Scala's sbt: parses `build.rg` using the Ridgun
-- compiler AST, supports `src/main/ridgun/lib/` + parallel
-- executable folders (`src/main/ridgun/<target>/main.rg`),
-- and provides interactive (`stable> `) and batch commands:
-- `build` / `built [target]`, `run [target] [args...]`, `test`,
-- `compile`, `check`, `clean`, `info`, `reload`, `help`, `exit`.
-- @implements FR-TOOL-001
-- @implements FR-TOOL-002
-- ============================================================
import ast
import lexer
import parser
import analyzer
import typecheck
import compiler
import vm
import formatter

-- Project configuration loaded from `build.rg`
type StableConfig = ProjectConfig String String String String String String

-- ── String & Shell Operators in Pure Ridgun ──────────────────

op :: flush non empty line String into [String] => [String]
      flush non empty line ""     into acc      =  acc
      flush non empty line line   into acc      =  acc :: [line]

op :: split lines loop String at Int of Int from Int into [String] => [String]
      split lines loop s at pos of len from line_start into acc
        | pos >= len = flush non empty line (trim_str (str_slice s line_start len)) into acc
        | (str_char_at s pos) == 10 = split lines loop s at (pos + 1) of len from (pos + 1) into (flush non empty line (trim_str (str_slice s line_start pos)) into acc)
        | otherwise = split lines loop s at (pos + 1) of len from line_start into acc

op :: split lines of String => [String]
      split lines of s      =  split lines loop s at 0 of (str_len s) from 0 into []

op :: char Int is whitespace => Bool
      char c   is whitespace =  c == 32 OR c == 9 OR c == 10 OR c == 13

op :: split words loop String at Int of Int word String into [String] => [String]
      split words loop s at pos of len word cur into acc
        | pos >= len = flush non empty line cur into acc
        | char (str_char_at s pos) is whitespace = split words loop s at (pos + 1) of len word "" into (flush non empty line cur into acc)
        | otherwise = split words loop s at (pos + 1) of len word (cur + (str_slice s pos (pos + 1))) into acc

op :: split words of String => [String]
      split words of s      =  split words loop s at 0 of (str_len s) word "" into []

op :: join words [String] with spaces => String
      join words []       with spaces =  ""
      join words (w:[])   with spaces =  w
      join words (w:ws)   with spaces =  w + " " + (join words ws with spaces)

op :: list rg files in String => [String]
      list rg files in dir    =
        _ = shell_exec ('mkdir -p target && ls -1 "' + dir + '"/*.rg "' + dir + '"/*/*.rg 2>/dev/null > target/.stable_files.txt || true')
        raw = read_file "target/.stable_files.txt"
        _ = shell_exec "rm -f target/.stable_files.txt"
        split lines of raw

op :: list exec entries in String => [String]
      list exec entries in dir    =
        _ = shell_exec ('mkdir -p target && ls -1 "' + dir + '"/*/main.rg 2>/dev/null > target/.stable_entries.txt || true')
        raw = read_file "target/.stable_entries.txt"
        _ = shell_exec "rm -f target/.stable_entries.txt"
        split lines of raw

op :: list test files in String => [String]
      list test files in dir    =
        _ = shell_exec ('mkdir -p target && ls -1 "' + dir + '"/test_*.rg "' + dir + '"/test\ *.rg 2>/dev/null > target/.stable_tfiles.txt || true')
        raw = read_file "target/.stable_tfiles.txt"
        _ = shell_exec "rm -f target/.stable_tfiles.txt"
        split lines of raw

op :: file String exists => Bool
      file path   exists =
        code = shell_exec ('test -f "' + path + '"')
        code == 0

op :: read prompt line with String     => (Bool, String)
      read prompt line with prompt_str =
        cmd = 'mkdir -p target && printf "%s" "' + prompt_str + '" && IFS= read -r _stable_ln && printf "%s" "$_stable_ln" > target/.stable_line.txt'
        st_code = shell_exec cmd
        decode prompt status st_code

op :: decode prompt status Int => (Bool, String)
      decode prompt status 0   =
        line = read_file "target/.stable_line.txt"
        _ = shell_exec "rm -f target/.stable_line.txt"
        (True, trim_str line)
      decode prompt status _   =
        _ = shell_exec "rm -f target/.stable_line.txt"
        (False, "")

-- ── `build.rg` AST Configuration Loader ─────────────────────

op :: extract function body from [RFnDef] named String default String => String
      extract function body from [] named _ default default_val = default_val
      extract function body from ((FnDef fn_name _ _ ((FnCase _ _ (EStr val)):_)):rem_fns) named target default default_val
        | fn_name == target = val
        | otherwise = extract function body from rem_fns named target default default_val
      extract function body from (_:rem_fns) named target default default_val =
        extract function body from rem_fns named target default default_val

op :: load build config from String     => StableConfig
      load build config from build_path
        | NOT (file build_path exists) = ProjectConfig "ridgunc" "0.9.3" "src/main/ridgun/ridgunc/main.rg" "src/main/ridgun" "src/test/ridgun" "target"
        | otherwise = parse build config source (read_file build_path)

op :: parse build config source String => StableConfig
      parse build config source src    =
        toks = tokenize_src src
        prog_ast = parse_tokens toks
        extract config from program prog_ast

op :: extract config from program RProgram        => StableConfig
      extract config from program (Program fns _) =
        name_str = extract function body from fns named "project_name" default "ridgunc"
        ver = extract function body from fns named "project_version" default "0.9.3"
        main_ep = extract function body from fns named "main_entry" default "src/main/ridgun/ridgunc/main.rg"
        sdir = extract function body from fns named "source_dir" default "src/main/ridgun"
        tdir = extract function body from fns named "test_dir" default "src/test/ridgun"
        out_dir = extract function body from fns named "target_dir" default "target"
        ProjectConfig name_str ver main_ep sdir tdir out_dir

op :: project name of StableConfig => String
      project name of (ProjectConfig name_str _ _ _ _ _) = name_str

-- ── Task 1: `check` (Typecheck & Static Analysis of Project) ─

fn :: check_single_module String => (Int, Int)
      check_single_module path   =
        raw = load_rg_source path
        toks = tokenize_src raw
        prog_ast = parse_tokens toks
        errs = typecheck_program prog_ast
        report check module path prog prog_ast errors errs

op :: report check module String prog RProgram errors [RTypeError] => (Int, Int)
      report check module path   prog prog_ast errors []           =
        fn_c = count_fn_defs prog_ast
        ty_c = count_type_defs prog_ast
        _ = echo "  [ok]   {path} ({fn_c} fn, {ty_c} types)"
        (1, 0)
      report check module path   prog _        errors errs         =
        ec = type_err_count errs
        _ = echo "  [err]  {path}: {ec} error(s)"
        _ = print error lines (format_type_errors errs)
        (0, ec)

op :: sum check results [(Int, Int)] ok Int  err Int   => (Int, Int)
      sum check results []           ok ok_c err err_c =  (ok_c, err_c)
      sum check results ((o, e):rem_results) ok ok_c err err_c =
        sum check results rem_results ok (ok_c + o) err (err_c + e)

op :: check modules [String] ok Int  err Int   => (Int, Int)
      check modules files    ok ok_c err err_c =
        results = map check_single_module files
        sum check results results ok ok_c err err_c

op :: print error lines [String] => ()
      print error lines []       =  ()
      print error lines (l:ls)   =
        _ = echo "        " l
        print error lines ls

op :: run task check on StableConfig => Int
      run task check on (ProjectConfig name_str ver _ sdir _ _) =
        files = list rg files in sdir
        _ = echo "[info] Checking project '{name_str}' v{ver} in {sdir}/ ..."
        finish task check with (check modules files ok 0 err 0)

op :: finish task check with (Int, Int)    => Int
      finish task check with (ok_c, 0)     =
        _ = echo "[success] Checked {ok_c} module(s) — 0 errors."
        0
      finish task check with (ok_c, err_c) =
        _ = echo "[error] Checked {ok_c} module(s) — {err_c} error(s) found."
        1

-- ── Task 2: `compile` (Emit .rgc Bytecode Artifacts) ─────────

op :: base filename of String at Int len Int       slash Int        => String
      base filename of path   at pos len total_len slash last_slash
        | pos >= total_len = str_slice path (last_slash + 1) total_len
        | (str_char_at path pos) == 47 = base filename of path at (pos + 1) len total_len slash pos
        | otherwise = base filename of path at (pos + 1) len total_len slash last_slash

op :: parent dir of String at Int len Int       slash Int        => String
      parent dir of path   at pos len total_len slash last_slash
        | pos >= total_len = str_slice path 0 last_slash
        | (str_char_at path pos) == 47 = parent dir of path at (pos + 1) len total_len slash pos
        | otherwise = parent dir of path at (pos + 1) len total_len slash last_slash

op :: target name from entry String     => String
      target name from entry entry_path =
        pdir = parent dir of entry_path at 0 len (str_len entry_path) slash 0
        base filename of pdir at 0 len (str_len pdir) slash (0 - 1)

op :: rgc artifact name for String base String    => String
      rgc artifact name for path   base "main.rg" =  (target name from entry path) + "_main.rgc"
      rgc artifact name for _      base bname     =  bname + "c"

op :: pair paths [String]         with dir String  => [(String, String)]
      pair paths []               with dir _       =  []
      pair paths (path:rem_files) with dir out_dir =
        [(out_dir, path)] :: (pair paths rem_files with dir out_dir)

fn :: compile_single_module (String, String) => Int
      compile_single_module (out_dir, path)  =
        bname = base filename of path at 0 len (str_len path) slash (0 - 1)
        out_rgc = out_dir + "/" + (rgc artifact name for path base bname)
        fn_c = emit_rgc_file path out_rgc
        _ = echo "  [rgc]  {path} -> {out_rgc} ({fn_c} functions)"
        1

op :: sum ints [Int]     acc Int   => Int
      sum ints []        acc total =  total
      sum ints (n:rem_n) acc total =  sum ints rem_n acc (total + n)

op :: compile modules [String] into String  count Int   => Int
      compile modules files    into out_dir count c_acc =
        pairs = pair paths files with dir out_dir
        counts = map compile_single_module pairs
        sum ints counts acc c_acc

op :: run task compile on StableConfig => Int
      run task compile on (ProjectConfig name_str ver main_ep sdir tdir out_dir) =
        chk = run task check on (ProjectConfig name_str ver main_ep sdir tdir out_dir)
        compile if check status chk from sdir into out_dir

op :: compile if check status Int  from String into String  => Int
      compile if check status 0    from sdir   into out_dir =
        _ = shell_exec ('mkdir -p "' + out_dir + '"')
        files = list rg files in sdir
        c_count = compile modules files into out_dir count 0
        _ = echo "[success] Compiled {c_count} bytecode artifact(s) into {out_dir}/."
        0
      compile if check status code from _      into _       =  code

-- ── Task 3: `build` / `built` (Build Native ELF Executables) ─

op :: build target from String     into String  version String => Int
      build target from entry_path into out_bin version ver    =
        _ = echo "[info] Building native executable '{out_bin}' from {entry_path} (v{ver}) ..."
        st_code = build_native_executable entry_path out_bin
        report build of out_bin status st_code

op :: pair entries [String] with dir String version String => [(String, String, String)]
      pair entries [] with dir _ version _ = []
      pair entries (epath:rem_paths) with dir out_dir version ver =
        [(out_dir, ver, epath)] :: (pair entries rem_paths with dir out_dir version ver)

fn :: build_single_entry (String, String, String) => Int
      build_single_entry (out_dir, ver, epath)    =
        tname = target name from entry epath
        out_bin = out_dir + "/" + tname
        build target from epath into out_bin version ver

op :: build entry list [String] into String version String errors Int => Int
      build entry list entries into out_dir version ver errors err_acc =
        triples = pair entries entries with dir out_dir version ver
        codes = map build_single_entry triples
        sum ints codes acc err_acc

op :: run task build on StableConfig args [String]  => Int
      run task build on (ProjectConfig name_str ver main_ep sdir _ out_dir) args [] =
        _ = shell_exec ('mkdir -p "' + out_dir + '"')
        entries = list exec entries in sdir
        build discovered entries entries name name_str version ver entry main_ep into out_dir
      run task build on (ProjectConfig _ ver _ sdir _ out_dir) args (tname:_) =
        _ = shell_exec ('mkdir -p "' + out_dir + '"')
        cand_entry = sdir + "/" + tname + "/main.rg"
        out_bin = out_dir + "/" + tname
        build target from cand_entry into out_bin version ver

op :: build discovered entries [String] name String version String entry String into String => Int
      build discovered entries [] name name_str version ver entry main_ep into out_dir =
        build target from main_ep into (out_dir + "/" + name_str) version ver
      build discovered entries entries name _ version ver entry _ into out_dir =
        build entry list entries into out_dir version ver errors 0

op :: report build of String  status Int  => Int
      report build of out_bin status 0    =
        _ = echo "[success] Built native ELF executable: {out_bin}"
        0
      report build of out_bin status code =
        _ = echo "[error] Build failed for {out_bin} (exit code {code})"
        code

-- ── Task 4: `run` (Build if Needed & Run Native Binary) ─────

op :: run task run on StableConfig args [String] => Int
      run task run on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args (first_arg:rest_args)
        | file (sdir + "/" + first_arg + "/main.rg") exists = run specific target first_arg from (sdir + "/" + first_arg + "/main.rg") version ver in out_dir args rest_args
        | otherwise = run default target for (ProjectConfig name_str ver main_ep sdir tdir out_dir) args ([first_arg] :: rest_args)
      run task run on cfg          args []       =
        run default target for cfg args []

op :: run specific target String from String version String in String args [String] => Int
      run specific target tname from entry_path version ver in out_dir args extra_args =
        out_bin = out_dir + "/" + tname
        ensure_st = ensure target built (file out_bin exists) from entry_path into out_bin version ver
        exec binary if built ensure_st path out_bin args extra_args

op :: run default target for StableConfig args [String]   => Int
      run default target for (ProjectConfig name_str ver main_ep _ _ out_dir) args extra_args =
        out_bin = out_dir + "/" + name_str
        ensure_st = ensure target built (file out_bin exists) from main_ep into out_bin version ver
        exec binary if built ensure_st path out_bin args extra_args

op :: ensure target built Bool from String into String version String => Int
      ensure target built True from _ into _ version _ = 0
      ensure target built False from entry_path into out_bin version ver =
        build target from entry_path into out_bin version ver

op :: exec binary if built Int  path String  args [String]   => Int
      exec binary if built 0    path out_bin args extra_args =
        arg_str = join words extra_args with spaces
        _ = echo "[info] Running ./{out_bin} {arg_str}"
        shell_exec ("./" + out_bin + " " + arg_str)
      exec binary if built code path _       args _          =  code

-- ── Task 5: `test` (Discover, Check, Build & Run Tests) ─────

fn :: run_single_test_suite String => (Int, Int)
      run_single_test_suite tpath  =
        _ = echo "[info] Compiling & running test suite: {tpath}"
        bname = base filename of tpath at 0 len (str_len tpath) slash (0 - 1)
        bin_path = "target/.stable_test_" + bname + "_bin"
        st_code = build_native_fast_executable tpath bin_path
        run built test binary st_code suite tpath binary bin_path

op :: run built test binary Int suite String binary String   => (Int, Int)
      run built test binary 0   suite tpath  binary bin_path =
        run_st = shell_exec ('"./' + bin_path + '"; _st=$?; rm -f "' + bin_path + '"; exit $_st')
        record single test outcome run_st suite tpath
      run built test binary _   suite tpath  binary _        =
        _ = echo "  [FAIL] {tpath} (compilation/typecheck failed)"
        (0, 1)

op :: record single test outcome Int suite String => (Int, Int)
      record single test outcome 0   suite tpath  =
        _ = echo "  [PASS] {tpath}"
        (1, 0)
      record single test outcome _   suite tpath  =
        _ = echo "  [FAIL] {tpath} (non-zero exit status)"
        (0, 1)

op :: execute test suites [String] passed Int    failed Int    => (Int, Int)
      execute test suites suites   passed pass_c failed fail_c =
        _ = shell_exec "mkdir -p target"
        results = map run_single_test_suite suites
        sum check results results ok pass_c err fail_c

op :: run task test on StableConfig => Int
      run task test on (ProjectConfig name_str _ _ _ tdir _) =
        suites = list test files in tdir
        _ = echo "[info] Running test suites for '{name_str}' in {tdir}/ ..."
        finish task test with (execute test suites suites passed 0 failed 0)

op :: finish task test with (Int, Int)       => Int
      finish task test with (pass_c, 0)      =
        _ = echo "[success] Passed {pass_c}/{pass_c} test suite(s) — 0 failures."
        0
      finish task test with (pass_c, fail_c) =
        total = pass_c + fail_c
        _ = echo "[error] Passed {pass_c}/{total} test suite(s) — {fail_c} failed."
        1

-- ── Task 6: `format` (Canonical Aesthetic Formatting) ───────

op :: read raw file at String => String
      read raw file at path   =  read_file path

op :: report unchanged file String => Int
      report unchanged file path   =
        _ = echo "  [ok]   {path} (already formatted)"
        0

op :: save formatted file String content String    => Int
      save formatted file path   content formatted =
        _ = write_file path formatted
        _ = echo "  [fmt]  {path} (formatted)"
        1

op :: apply formatted content String orig String formatted String        => Int
      apply formatted content path   orig raw    formatted formatted_src
        | raw == formatted_src = report unchanged file path
        | otherwise = save formatted file path content formatted_src

op :: format file at String => Int
      format file at path   =
        raw = read raw file at path
        formatted_src = format ridgun source raw
        apply formatted content path orig raw formatted formatted_src

fn :: format_single_file String => Int
      format_single_file path   =  format file at path

op :: format file list [String] changed Int   total Int   => (Int, Int)
      format file list paths    changed chg_c total tot_c =
        deltas = map format_single_file paths
        (sum ints deltas acc chg_c, tot_c + (list_str_len paths))

op :: include build file if present => [String]
      include build file if present
        | file "build.rg" exists = ["build.rg"]
        | otherwise = []

op :: finish task format with (Int, Int)     => Int
      finish task format with (chg_c, tot_c) =
        _ = echo "[success] Formatted {chg_c}/{tot_c} file(s) using canonical Ridgun style."
        0

op :: run task format on StableConfig args [String]     => Int
      run task format on (ProjectConfig name_str _ _ sdir tdir _) args [] =
        b_files = include build file if present
        s_files = list rg files in sdir
        t_files = list rg files in tdir
        all_files = b_files :: s_files :: t_files
        _ = echo "[info] Formatting project '{name_str}' source files ..."
        finish task format with (format file list all_files changed 0 total 0)
      run task format on _            args target_paths =
        _ = echo "[info] Formatting specified Ridgun file(s) ..."
        finish task format with (format file list target_paths changed 0 total 0)

-- ── Task 7: `clean` & `info` & `help` ───────────────────────

op :: run task clean on StableConfig => Int
      run task clean on (ProjectConfig _ _ _ _ _ out_dir) =
        _ = shell_exec ('rm -f "' + out_dir + '"/*.rgc "' + out_dir + '"/.stable_* "' + out_dir + '"/.ridgunc_*')
        _ = echo "[success] Cleaned bytecode artifacts in {out_dir}/."
        0

op :: collect target names of [String]     => [String]
      collect target names of []           =  []
      collect target names of (ep:rem_eps) =  [target name from entry ep] :: (collect target names of rem_eps)

op :: run task info on StableConfig => Int
      run task info on (ProjectConfig name_str ver main_ep sdir tdir out_dir) =
        src_files = list rg files in sdir
        exec_entries = list exec entries in sdir
        exec_names = join words (collect target names of exec_entries) with spaces
        tst_files = list test files in tdir
        src_c = list_str_len src_files
        tst_c = list_str_len tst_files
        _ = echo "=== Project Info (build.rg) ==="
        _ = echo "  Project Name : {name_str}"
        _ = echo "  Version      : {ver}"
        _ = echo "  Main Entry   : {main_ep}"
        _ = echo "  Executables  : {exec_names}"
        _ = echo "  Shared Lib   : {sdir}/lib/"
        _ = echo "  Source Dir   : {sdir}/ ({src_c} modules)"
        _ = echo "  Test Dir     : {tdir}/ ({tst_c} test suites)"
        _ = echo "  Target Dir   : {out_dir}/"
        0

-- ── Task 8: `new`, `init`, `deps`, `add`, and `install` (`FR-TOOL-002`) ──

op :: extract string list from [RExpr]         => [String]
      extract string list from []              =  []
      extract string list from ((EStr s):rest) =  [s] :: (extract string list from rest)
      extract string list from (_:rest)        =  extract string list from rest

op :: extract list function body from [RFnDef]    named String => [String]
      extract list function body from []          named _      =  []
      extract list function body from ((FnDef fn_name _ _ ((FnCase _ _ (EList items)):_)):rem_fns) named target
        | fn_name == target = extract string list from items
        | otherwise = extract list function body from rem_fns named target
      extract list function body from ((FnDef fn_name _ _ ((FnCase _ _ (EStr val)):_)):rem_fns) named target
        | fn_name == target = split words of val
        | otherwise = extract list function body from rem_fns named target
      extract list function body from (_:rem_fns) named target =
        extract list function body from rem_fns named target

op :: extract deps from program RProgram        => [String]
      extract deps from program (Program fns _) =
        extract list function body from fns named "dependencies"

op :: load dependencies from String     => [String]
      load dependencies from build_path
        | NOT (file build_path exists) = []
        | otherwise =
          toks = tokenize_src (read_file build_path)
          extract deps from program (parse_tokens toks)

op :: scaffold project named String in String => Int
      scaffold project named pname  in root   =
        _ = shell_exec ('mkdir -p "' + root + '/src/main/ridgun/' + pname + '" "' + root + '/src/main/ridgun/lib" "' + root + '/src/test/ridgun" "' + root + '/target"')
        build_content = '-- build.rg — Ridgun Project Build Definition\n\nfn :: project name => String\n      project name =  "' + pname + '"\n\nfn :: project version => String\n      project version =  "0.1.0"\n\nfn :: main entry => String\n      main entry =  "src/main/ridgun/' + pname + '/main.rg"\n\nfn :: source dir => String\n      source dir =  "src/main/ridgun"\n\nfn :: test dir => String\n      test dir =  "src/test/ridgun"\n\nfn :: target dir => String\n      target dir =  "target"\n\nfn :: dependencies => [String]\n      dependencies =  []\n'
        main_content = '-- src/main/ridgun/' + pname + '/main.rg\n\nfn :: greet String => String\n      greet who    =  "Hello from " + who + "!"\n\nfn :: main => ()\n      main =  echo (greet "' + pname + '")\n'
        test_content = '-- src/test/ridgun/test main.rg\n\nfn :: main => ()\n      main =  echo "=== All ' + pname + ' tests passed ==="\n'
        gitignore_content = '/target/\n/.stable/\n'
        _ = write_file (root + "/build.rg") build_content
        _ = write_file (root + "/src/main/ridgun/" + pname + "/main.rg") main_content
        _ = write_file (root + "/src/test/ridgun/test main.rg") test_content
        _ = write_file (root + "/.gitignore") gitignore_content
        _ = echo "[success] Scaffolded Ridgun project '{pname}' in {root}/"
        0

op :: run task new args [String]  => Int
      run task new args []        =
        _ = echo "[error] Usage: stable new <project_name>"
        1
      run task new args (pname:_)
        | file (pname + "/build.rg") exists =
          _ = echo "[error] Project '{pname}' already exists at {pname}/build.rg"
          1
        | otherwise = scaffold project named pname in pname

op :: run task init args [String] => Int
      run task init args _
        | file "build.rg" exists =
          _ = echo "[info] build.rg already exists in current directory."
          0
        | otherwise =
          cwd = sys_getcwd
          pname = base filename of cwd at 0 len (str_len cwd) slash (0 - 1)
          scaffold project named pname in "."

op :: fetch dependency source String into String => Int
      fetch dependency source dep    into dest
        | (str_starts_with dep "http://") OR (str_starts_with dep "https://") OR (str_starts_with dep "git@") =
          shell_exec ('if [ -d "' + dest + '/.git" ]; then git -C "' + dest + '" pull -q; else git clone -q "' + dep + '" "' + dest + '"; fi')
        | otherwise =
          shell_exec ('rm -rf "' + dest + '" && cp -r "' + dep + '" "' + dest + '"')

op :: sync single dependency String => Int
      sync single dependency dep    =
        bname = base filename of dep at 0 len (str_len dep) slash (0 - 1)
        dest = ".stable/deps/" + bname
        _ = shell_exec 'mkdir -p .stable/deps src/main/ridgun/lib'
        st = fetch dependency source dep into dest
        _ = shell_exec ('cp -f "' + dest + '"/src/main/ridgun/lib/*.rg src/main/ridgun/lib/ 2>/dev/null || cp -f "' + dest + '"/*.rg src/main/ridgun/lib/ 2>/dev/null || true')
        _ = echo "  [dep]  {dep} -> {dest}"
        st

op :: sync dependency list [String] => Int
      sync dependency list []       =
        _ = echo "  [ok]   No external dependencies declared in build.rg."
        0
      sync dependency list (d:ds)   =
        _ = sync single dependency d
        sync dependency list ds

op :: run task deps => Int
      run task deps =
        deps = load dependencies from "build.rg"
        _ = echo "[info] Synchronizing dependencies from build.rg into .stable/deps/ ..."
        _ = sync dependency list deps
        _ = echo "[success] Dependencies synchronized."
        0

op :: format dep items [String] => String
      format dep items []       =  ""
      format dep items (d:[])   =  '"' + d + '"'
      format dep items (d:ds)   =  '"' + d + '", ' + (format dep items ds)

op :: append dep block if needed String    => ()
      append dep block if needed dep_block
        | NOT (file "build.rg" exists) = write_file "build.rg" dep_block
        | str_contains (read_file "build.rg") "dependencies" = ()
        | otherwise = write_file "build.rg" ((read_file "build.rg") + dep_block)

op :: run task add args [String]    => Int
      run task add args []          =
        _ = echo "[error] Usage: stable add <git_url_or_path>"
        1
      run task add args (new_dep:_) =
        cur_deps = load dependencies from "build.rg"
        all_deps = cur_deps :: [new_dep]
        dep_block = '\nfn :: dependencies => [String]\n      dependencies =  [' + (format dep items all_deps) + ']\n'
        _ = append dep block if needed dep_block
        _ = sync single dependency new_dep
        _ = echo "[success] Added dependency '{new_dep}'."
        0

op :: install built binaries Int from String  => Int
      install built binaries 0   from out_dir =
        home = sys_getenv "HOME"
        inst_dir = home + "/.local/bin"
        _ = shell_exec ('mkdir -p "' + inst_dir + '" bin && for f in "' + out_dir + '"/*; do if [ -f "$f" ] && [ -x "$f" ]; then cp -f "$f" "' + inst_dir + '/" && cp -f "$f" bin/; fi; done')
        _ = echo "[success] Installed executable(s) from {out_dir}/ into {inst_dir}/ and bin/."
        0
      install built binaries st  from _       =  st

op :: run task install on StableConfig args [String] => Int
      run task install on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args extra =
        build_st = run task build on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args extra
        install built binaries build_st from out_dir

op :: run task help => Int
      run task help =
        _ = echo "Available `stable` commands:"
        _ = echo "  new <name>                  Create a new Ridgun project directory with build.rg and src/"
        _ = echo "  init                        Initialize build.rg and src/ in the current directory"
        _ = echo "  deps                        Synchronize dependencies from build.rg into .stable/deps/"
        _ = echo "  add <dep>                   Add a Git URL or path dependency to build.rg and sync .stable/deps/"
        _ = echo "  install [target]            Build and install native ELF64 executable(s) into ~/.local/bin/ and bin/"
        _ = echo "  build | built [target]      Compile all executables (or [target]) into target/<target>"
        _ = echo "  run [target] [args...]      Build (if needed) and run executable (default: main_entry)"
        _ = echo "  test                        Discover, typecheck, compile, and execute all test suites in src/test/ridgun/"
        _ = echo "  check                       Typecheck and run static analysis across all modules in src/main/ridgun/"
        _ = echo "  format [file...]            Apply canonical aesthetic column-alignment formatting to .rg files"
        _ = echo "  compile                     Typecheck and emit .rgc bytecode artifacts into target/"
        _ = echo "  clean                       Remove compiled .rgc artifacts from target/"
        _ = echo "  info | status               Display project configuration from build.rg"
        _ = echo "  reload                      Reload project configuration from build.rg"
        _ = echo "  help                        Show this help summary"
        _ = echo "  exit | quit                 Exit the interactive stable shell"
        0

-- ── Command Dispatcher & Interactive REPL Loop ──────────────

op :: execute command [String] on StableConfig => (Bool, StableConfig, Int)
      execute command [] on cfg = (True, cfg, 0)
      execute command ("exit":_) on cfg = (False, cfg, 0)
      execute command ("quit":_) on cfg = (False, cfg, 0)
      execute command ("q":_) on cfg = (False, cfg, 0)
      execute command ("help":_) on cfg = (True, cfg, run task help)
      execute command ("-h":_) on cfg = (True, cfg, run task help)
      execute command ("--help":_) on cfg = (True, cfg, run task help)
      execute command ("version":_) on cfg =
        _ = echo "stable 0.9.3 (Ridgun Interactive Build Tool, 100% self-hosted in Ridgun)"
        (True, cfg, 0)
      execute command ("-v":_) on cfg =
        _ = echo "stable 0.9.3 (Ridgun Interactive Build Tool, 100% self-hosted in Ridgun)"
        (True, cfg, 0)
      execute command ("info":_) on cfg = (True, cfg, run task info on cfg)
      execute command ("status":_) on cfg = (True, cfg, run task info on cfg)
      execute command ("reload":_) on _ =
        new_cfg = load build config from "build.rg"
        pname = project name of new_cfg
        _ = echo "[info] Reloaded build.rg — current project is '{pname}'"
        (True, new_cfg, 0)
      execute command ("check":_) on cfg = (True, cfg, run task check on cfg)
      execute command ("new":extra) on cfg = (True, cfg, run task new args extra)
      execute command ("init":extra) on cfg = (True, cfg, run task init args extra)
      execute command ("deps":_) on cfg = (True, cfg, run task deps)
      execute command ("add":extra) on cfg = (True, cfg, run task add args extra)
      execute command ("install":extra) on cfg = (True, cfg, run task install on cfg args extra)
      execute command ("format":extra) on cfg = (True, cfg, run task format on cfg args extra)
      execute command ("fmt":extra) on cfg = (True, cfg, run task format on cfg args extra)
      execute command ("compile":_) on cfg = (True, cfg, run task compile on cfg)
      execute command ("build":extra) on cfg = (True, cfg, run task build on cfg args extra)
      execute command ("built":extra) on cfg = (True, cfg, run task build on cfg args extra)
      execute command ("run":extra) on cfg = (True, cfg, run task run on cfg args extra)
      execute command ("test":_) on cfg = (True, cfg, run task test on cfg)
      execute command ("clean":_) on cfg = (True, cfg, run task clean on cfg)
      execute command (unknown:_) on cfg =
        _ = echo "[error] Unknown command: '{unknown}'. Type 'help' for available commands."
        (True, cfg, 1)

op :: repl loop for StableConfig => ()
      repl loop for cfg          =
        esc = char_from_code 27
        blue_prompt = esc + "[34mstable>" + esc + "[0m "
        read_res = read prompt line with blue_prompt
        repl step for cfg input read_res

op :: repl step for StableConfig input (Bool, String) => ()
      repl step for _            input (False, _)     =
        echo ""
      repl step for cfg          input (True, line)   =
        words = split words of line
        cmd_res = execute command words on cfg
        repl continue with cmd_res

op :: repl continue with (Bool, StableConfig, Int) => ()
      repl continue with (False, _, _)             =
        echo "[info] Exiting stable."
      repl continue with (True, next_cfg, _)       =
        repl loop for next_cfg

op :: start interactive shell for StableConfig => ()
      start interactive shell for (ProjectConfig name_str ver main_ep sdir tdir out_dir) =
        _ = echo "[info] Welcome to stable 0.9.3 (Ridgun Build Tool — 100% Ridgun)"
        _ = echo "[info] Loading project definition from build.rg ..."
        _ = echo "[info] Set current project to '{name_str}' v{ver} (main: {main_ep})"
        _ = echo "[info] Commands: 'built' (or 'build'), 'run', 'test', 'check', 'compile', 'clean', 'info', 'exit'"
        repl loop for (ProjectConfig name_str ver main_ep sdir tdir out_dir)

op :: strip stable argv [String]     => [String]
      strip stable argv []           =  []
      strip stable argv (_:rem_args) =  strip stable script rem_args

op :: strip stable script [String] => [String]
      strip stable script []       =  []
      strip stable script ("run":script:rem_args)
        | (str_contains script "stable.rg") OR (str_contains script "stable/main.rg") = rem_args
        | otherwise = ["run", script] :: rem_args
      strip stable script (first_arg:rem_args)
        | (str_contains first_arg "stable.rg") OR (str_contains first_arg "stable/main.rg") = rem_args
        | otherwise = [first_arg] :: rem_args

op :: dispatch stable cli [String]  on StableConfig => ()
      dispatch stable cli []        on cfg          =  start interactive shell for cfg
      dispatch stable cli args_list on cfg          =
        _ = execute command args_list on cfg
        ()

fn :: main => ()
      main =
        cfg = load build config from "build.rg"
        args_list = strip stable argv cli_args
        dispatch stable cli args_list on cfg
