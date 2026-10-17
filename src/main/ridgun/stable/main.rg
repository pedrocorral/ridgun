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

op :: split lines loop String at Int of Int from Int        into [String] => [String]
      split lines loop s      at pos of len from line_start into acc
        | pos >= len = flush non empty line (trim_str (str_slice s line_start len)) into acc
        | (str_char_at s pos) == 10 = split lines loop s at (pos + 1) of len from (pos + 1) into (flush non empty line (trim_str (str_slice s line_start pos)) into acc)
        | otherwise = split lines loop s at (pos + 1) of len from line_start into acc

op :: split lines of String => [String]
      split lines of s      =  split lines loop s at 0 of (str_len s) from 0 into []

op :: char Int is whitespace => Bool
      char c   is whitespace =  c == 32 OR c == 9 OR c == 10 OR c == 13

op :: split words loop String at Int of Int word String into [String] => [String]
      split words loop s      at pos of len word cur    into acc
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
      list rg files in dir =
        _ = shell_exec ('mkdir -p target && ls -1 ' + dir + '/*.rg ' + dir + '/*/*.rg 2>/dev/null > target/.stable_files.txt || true')
        raw = read_file "target/.stable_files.txt"
        _ = shell_exec "rm -f target/.stable_files.txt"
        split lines of raw

op :: list exec entries in String => [String]
      list exec entries in dir =
        _ = shell_exec ('mkdir -p target && ls -1 ' + dir + '/*/main.rg 2>/dev/null > target/.stable_entries.txt || true')
        raw = read_file "target/.stable_entries.txt"
        _ = shell_exec "rm -f target/.stable_entries.txt"
        split lines of raw

op :: list test files in String => [String]
      list test files in dir =
        _ = shell_exec ('mkdir -p target && ls -1 ' + dir + '/test_*.rg 2>/dev/null > target/.stable_tfiles.txt || true')
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
      decode prompt status 0 =
        line = read_file "target/.stable_line.txt"
        _ = shell_exec "rm -f target/.stable_line.txt"
        (True, trim_str line)
      decode prompt status _ =
        _ = shell_exec "rm -f target/.stable_line.txt"
        (False, "")

-- ── `build.rg` AST Configuration Loader ─────────────────────

op :: extract function body from [RFnDef]                                                  named String default String      => String
      extract function body from []                                                        named _      default default_val =  default_val
      extract function body from ((FnDef fn_name _ _ ((FnCase _ _ (EStr val)):_)):rem_fns) named target default default_val
        | fn_name == target = val
        | otherwise = extract function body from rem_fns named target default default_val
      extract function body from (_:rem_fns)                                               named target default default_val =
        extract function body from rem_fns named target default default_val

op :: load build config from String     => StableConfig
      load build config from build_path
        | NOT (file build_path exists) = ProjectConfig "ridgunc" "0.9.3" "src/main/ridgun/ridgunc/main.rg" "src/main/ridgun" "src/test/ridgun" "target"
        | otherwise = parse build config source (read_file build_path)

op :: parse build config source String => StableConfig
      parse build config source src =
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

op :: project name of StableConfig                       => String
      project name of (ProjectConfig name_str _ _ _ _ _) =  name_str

-- ── Task 1: `check` (Typecheck & Static Analysis of Project) ─

op :: check modules [String]         ok Int  err Int   => (Int, Int)
      check modules []               ok ok_c err err_c =  (ok_c, err_c)
      check modules (path:rem_files) ok ok_c err err_c =
        raw = read_file path
        toks = tokenize_src raw
        prog_ast = parse_tokens toks
        errs = typecheck_program prog_ast
        check module step path rest rem_files ok ok_c err err_c prog prog_ast errors errs

op :: check module step String rest [String]  ok Int  err Int   prog RProgram errors [RTypeError] => (Int, Int)
      check module step path   rest rem_files ok ok_c err err_c prog prog_ast errors [] =
        fn_c = count_fn_defs prog_ast
        ty_c = count_type_defs prog_ast
        _ = echo "  [ok]   {path} ({fn_c} fn, {ty_c} types)"
        check modules rem_files ok (ok_c + 1) err err_c
      check module step path   rest rem_files ok ok_c err err_c prog _        errors errs =
        ec = type_err_count errs
        _ = echo "  [err]  {path}: {ec} error(s)"
        _ = print error lines (format_type_errors errs)
        check modules rem_files ok ok_c err (err_c + ec)

op :: print error lines [String] => ()
      print error lines []       =  ()
      print error lines (l:ls) =
        _ = echo "        " l
        print error lines ls

op :: run task check on StableConfig                            => Int
      run task check on (ProjectConfig name_str ver _ sdir _ _) =
        files = list rg files in sdir
        _ = echo "[info] Checking project '{name_str}' v{ver} in {sdir}/ ..."
        finish task check with (check modules files ok 0 err 0)

op :: finish task check with (Int, Int)    => Int
      finish task check with (ok_c, 0) =
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

op :: compile modules [String]         into String  count Int   => Int
      compile modules []               into _       count c_acc =  c_acc
      compile modules (path:rem_files) into out_dir count c_acc =
        bname = base filename of path at 0 len (str_len path) slash (0 - 1)
        out_rgc = out_dir + "/" + (rgc artifact name for path base bname)
        fn_c = emit_rgc_file path out_rgc
        _ = echo "  [rgc]  {path} -> {out_rgc} ({fn_c} functions)"
        compile modules rem_files into out_dir count (c_acc + 1)

op :: run task compile on StableConfig                                           => Int
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
      build target from entry_path into out_bin version ver =
        _ = echo "[info] Building native executable '{out_bin}' from {entry_path} (v{ver}) ..."
        st_code = build_native_executable entry_path out_bin
        report build of out_bin status st_code

op :: build entry list [String]            into String  version String errors Int     => Int
      build entry list []                  into _       version _      errors err_acc =  err_acc
      build entry list (epath:rem_entries) into out_dir version ver    errors err_acc =
        tname = target name from entry epath
        out_bin = out_dir + "/" + tname
        st_code = build target from epath into out_bin version ver
        build entry list rem_entries into out_dir version ver errors (err_acc + st_code)

op :: run task build on StableConfig                                        args [String]  => Int
      run task build on (ProjectConfig name_str ver main_ep sdir _ out_dir) args [] =
        _ = shell_exec ('mkdir -p "' + out_dir + '"')
        entries = list exec entries in sdir
        build discovered entries entries name name_str version ver entry main_ep into out_dir
      run task build on (ProjectConfig _ ver _ sdir _ out_dir)              args (tname:_) =
        _ = shell_exec ('mkdir -p "' + out_dir + '"')
        cand_entry = sdir + "/" + tname + "/main.rg"
        out_bin = out_dir + "/" + tname
        build target from cand_entry into out_bin version ver

op :: build discovered entries [String] name String   version String entry String  into String  => Int
      build discovered entries []       name name_str version ver    entry main_ep into out_dir =
        build target from main_ep into (out_dir + "/" + name_str) version ver
      build discovered entries entries  name _        version ver    entry _       into out_dir =
        build entry list entries into out_dir version ver errors 0

op :: report build of String  status Int  => Int
      report build of out_bin status 0 =
        _ = echo "[success] Built native ELF executable: {out_bin}"
        0
      report build of out_bin status code =
        _ = echo "[error] Build failed for {out_bin} (exit code {code})"
        code

-- ── Task 4: `run` (Build if Needed & Run Native Binary) ─────

op :: run task run on StableConfig                                           args [String]              => Int
      run task run on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args (first_arg:rest_args)
        | file (sdir + "/" + first_arg + "/main.rg") exists = run specific target first_arg from (sdir + "/" + first_arg + "/main.rg") version ver in out_dir args rest_args
        | otherwise = run default target for (ProjectConfig name_str ver main_ep sdir tdir out_dir) args ([first_arg] :: rest_args)
      run task run on cfg                                                    args [] =
        run default target for cfg args []

op :: run specific target String from String     version String in String  args [String]   => Int
      run specific target tname  from entry_path version ver    in out_dir args extra_args =
        out_bin = out_dir + "/" + tname
        ensure_st = ensure target built (file out_bin exists) from entry_path into out_bin version ver
        exec binary if built ensure_st path out_bin args extra_args

op :: run default target for StableConfig                                     args [String]   => Int
      run default target for (ProjectConfig name_str ver main_ep _ _ out_dir) args extra_args =
        out_bin = out_dir + "/" + name_str
        ensure_st = ensure target built (file out_bin exists) from main_ep into out_bin version ver
        exec binary if built ensure_st path out_bin args extra_args

op :: ensure target built Bool  from String     into String  version String => Int
      ensure target built True  from _          into _       version _      =  0
      ensure target built False from entry_path into out_bin version ver =
        build target from entry_path into out_bin version ver

op :: exec binary if built Int  path String  args [String]   => Int
      exec binary if built 0    path out_bin args extra_args =
        arg_str = join words extra_args with spaces
        _ = echo "[info] Running ./{out_bin} {arg_str}"
        shell_exec ("./" + out_bin + " " + arg_str)
      exec binary if built code path _       args _          =  code

-- ── Task 5: `test` (Discover, Check, Build & Run Tests) ─────

op :: execute test suites [String]           passed Int    failed Int    => (Int, Int)
      execute test suites []                 passed pass_c failed fail_c =  (pass_c, fail_c)
      execute test suites (tpath:rem_suites) passed pass_c failed fail_c =
        _ = echo "[info] Compiling & running test suite: {tpath}"
        _ = shell_exec "mkdir -p target"
        st_code = build_native_executable tpath "target/.stable_test_bin"
        run single test binary st_code suite tpath rest rem_suites passed pass_c failed fail_c

op :: run single test binary Int suite String rest [String]   passed Int    failed Int    => (Int, Int)
      run single test binary 0   suite tpath  rest rem_suites passed pass_c failed fail_c =
        run_st = shell_exec "./target/.stable_test_bin; _st=$?; rm -f target/.stable_test_bin; exit $_st"
        record test outcome run_st suite tpath rest rem_suites passed pass_c failed fail_c
      run single test binary _   suite tpath  rest rem_suites passed pass_c failed fail_c =
        _ = echo "  [FAIL] {tpath} (compilation/typecheck failed)"
        execute test suites rem_suites passed pass_c failed (fail_c + 1)

op :: record test outcome Int suite String rest [String]   passed Int    failed Int    => (Int, Int)
      record test outcome 0   suite tpath  rest rem_suites passed pass_c failed fail_c =
        _ = echo "  [PASS] {tpath}"
        execute test suites rem_suites passed (pass_c + 1) failed fail_c
      record test outcome _   suite tpath  rest rem_suites passed pass_c failed fail_c =
        _ = echo "  [FAIL] {tpath} (non-zero exit status)"
        execute test suites rem_suites passed pass_c failed (fail_c + 1)

op :: run task test on StableConfig                          => Int
      run task test on (ProjectConfig name_str _ _ _ tdir _) =
        suites = list test files in tdir
        _ = echo "[info] Running test suites for '{name_str}' in {tdir}/ ..."
        finish task test with (execute test suites suites passed 0 failed 0)

op :: finish task test with (Int, Int)       => Int
      finish task test with (pass_c, 0) =
        _ = echo "[success] Passed {pass_c}/{pass_c} test suite(s) — 0 failures."
        0
      finish task test with (pass_c, fail_c) =
        total = pass_c + fail_c
        _ = echo "[error] Passed {pass_c}/{total} test suite(s) — {fail_c} failed."
        1

-- ── Task 6: `format` (Canonical Aesthetic Formatting) ───────

op :: read raw file at String => String
      read raw file at path =
        _ = shell_exec ('mkdir -p target && cp "' + path + '" target/.stable_fmt.raw')
        raw = read_file "target/.stable_fmt.raw"
        _ = shell_exec "rm -f target/.stable_fmt.raw"
        raw

op :: report unchanged file String => Int
      report unchanged file path =
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
      format file at path =
        raw = read raw file at path
        formatted_src = format ridgun source raw
        apply formatted content path orig raw formatted formatted_src

op :: format file list [String]         changed Int   total Int   => (Int, Int)
      format file list []               changed chg_c total tot_c =  (chg_c, tot_c)
      format file list (path:rem_paths) changed chg_c total tot_c =
        delta = format file at path
        format file list rem_paths changed (chg_c + delta) total (tot_c + 1)

op :: include build file if present => [String]
      include build file if present
        | file "build.rg" exists = ["build.rg"]
        | otherwise = []

op :: finish task format with (Int, Int)     => Int
      finish task format with (chg_c, tot_c) =
        _ = echo "[success] Formatted {chg_c}/{tot_c} file(s) using canonical Ridgun style."
        0

op :: run task format on StableConfig                             args [String]     => Int
      run task format on (ProjectConfig name_str _ _ sdir tdir _) args [] =
        b_files = include build file if present
        s_files = list rg files in sdir
        t_files = list rg files in tdir
        all_files = b_files :: s_files :: t_files
        _ = echo "[info] Formatting project '{name_str}' source files ..."
        finish task format with (format file list all_files changed 0 total 0)
      run task format on _                                        args target_paths =
        _ = echo "[info] Formatting specified Ridgun file(s) ..."
        finish task format with (format file list target_paths changed 0 total 0)

-- ── Task 7: `clean` & `info` & `help` ───────────────────────

op :: run task clean on StableConfig                      => Int
      run task clean on (ProjectConfig _ _ _ _ _ out_dir) =
        _ = shell_exec ('rm -f "' + out_dir + '"/*.rgc "' + out_dir + '"/.stable_* "' + out_dir + '"/.ridgunc_*')
        _ = echo "[success] Cleaned bytecode artifacts in {out_dir}/."
        0

op :: map target names of [String]     => [String]
      map target names of []           =  []
      map target names of (ep:rem_eps) =  [target name from entry ep] :: (map target names of rem_eps)

op :: run task info on StableConfig                                           => Int
      run task info on (ProjectConfig name_str ver main_ep sdir tdir out_dir) =
        src_files = list rg files in sdir
        exec_entries = list exec entries in sdir
        exec_names = join words (map target names of exec_entries) with spaces
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

op :: run task help => Int
      run task help =
        _ = echo "Available `stable` commands:"
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

op :: execute command [String]         on StableConfig => (Bool, StableConfig, Int)
      execute command []               on cfg          =  (True, cfg, 0)
      execute command ("exit":_)       on cfg          =  (False, cfg, 0)
      execute command ("quit":_)       on cfg          =  (False, cfg, 0)
      execute command ("q":_)          on cfg          =  (False, cfg, 0)
      execute command ("help":_)       on cfg          =  (True, cfg, run task help)
      execute command ("-h":_)         on cfg          =  (True, cfg, run task help)
      execute command ("--help":_)     on cfg          =  (True, cfg, run task help)
      execute command ("version":_)    on cfg =
        _ = echo "stable 0.9.3 (Ridgun Interactive Build Tool, 100% self-hosted in Ridgun)"
        (True, cfg, 0)
      execute command ("-v":_)         on cfg =
        _ = echo "stable 0.9.3 (Ridgun Interactive Build Tool, 100% self-hosted in Ridgun)"
        (True, cfg, 0)
      execute command ("info":_)       on cfg          =  (True, cfg, run task info on cfg)
      execute command ("status":_)     on cfg          =  (True, cfg, run task info on cfg)
      execute command ("reload":_)     on _ =
        new_cfg = load build config from "build.rg"
        pname = project name of new_cfg
        _ = echo "[info] Reloaded build.rg — current project is '{pname}'"
        (True, new_cfg, 0)
      execute command ("check":_)      on cfg          =  (True, cfg, run task check on cfg)
      execute command ("format":extra) on cfg          =  (True, cfg, run task format on cfg args extra)
      execute command ("fmt":extra)    on cfg          =  (True, cfg, run task format on cfg args extra)
      execute command ("compile":_)    on cfg          =  (True, cfg, run task compile on cfg)
      execute command ("build":extra)  on cfg          =  (True, cfg, run task build on cfg args extra)
      execute command ("built":extra)  on cfg          =  (True, cfg, run task build on cfg args extra)
      execute command ("run":extra)    on cfg          =  (True, cfg, run task run on cfg args extra)
      execute command ("test":_)       on cfg          =  (True, cfg, run task test on cfg)
      execute command ("clean":_)      on cfg          =  (True, cfg, run task clean on cfg)
      execute command (unknown:_)      on cfg =
        _ = echo "[error] Unknown command: '{unknown}'. Type 'help' for available commands."
        (True, cfg, 1)

op :: repl loop for StableConfig => ()
      repl loop for cfg =
        esc = char_from_code 27
        blue_prompt = esc + "[34mstable>" + esc + "[0m "
        read_res = read prompt line with blue_prompt
        repl step for cfg input read_res

op :: repl step for StableConfig input (Bool, String) => ()
      repl step for _            input (False, _) =
        echo ""
      repl step for cfg          input (True, line) =
        words = split words of line
        cmd_res = execute command words on cfg
        repl continue with cmd_res

op :: repl continue with (Bool, StableConfig, Int) => ()
      repl continue with (False, _, _) =
        echo "[info] Exiting stable."
      repl continue with (True, next_cfg, _) =
        repl loop for next_cfg

op :: start interactive shell for StableConfig                                           => ()
      start interactive shell for (ProjectConfig name_str ver main_ep sdir tdir out_dir) =
        _ = echo "[info] Welcome to stable 0.9.3 (Ridgun Build Tool — 100% Ridgun)"
        _ = echo "[info] Loading project definition from build.rg ..."
        _ = echo "[info] Set current project to '{name_str}' v{ver} (main: {main_ep})"
        _ = echo "[info] Commands: 'built' (or 'build'), 'run', 'test', 'check', 'compile', 'clean', 'info', 'exit'"
        repl loop for (ProjectConfig name_str ver main_ep sdir tdir out_dir)

op :: strip stable argv [String]     => [String]
      strip stable argv []           =  []
      strip stable argv (_:rem_args) =  strip stable script rem_args

op :: strip stable script [String]                => [String]
      strip stable script []                      =  []
      strip stable script ("run":script:rem_args)
        | (str_contains script "stable.rg") OR (str_contains script "stable/main.rg") = rem_args
        | otherwise = ["run", script] :: rem_args
      strip stable script (first_arg:rem_args)
        | (str_contains first_arg "stable.rg") OR (str_contains first_arg "stable/main.rg") = rem_args
        | otherwise = [first_arg] :: rem_args

op :: dispatch stable cli [String]  on StableConfig => ()
      dispatch stable cli []        on cfg          =  start interactive shell for cfg
      dispatch stable cli args_list on cfg =
        _ = execute command args_list on cfg
        ()

fn :: main => ()
      main =
        cfg = load build config from "build.rg"
        args_list = strip stable argv cli_args
        dispatch stable cli args_list on cfg
