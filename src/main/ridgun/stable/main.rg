-- ============================================================
-- src/main/ridgun/stable/main.rg
-- `stable` v0.9.7 — The Interactive Build Tool for Ridgun (100% Ridgun)
-- Written in Ridgun's natural-language mixfix operator style (`op :: ...`).
-- Inspired by Scala's sbt: parses `build.rg` using the Ridgun
-- compiler AST, supports `src/main/ridgun/lib/` + parallel
-- executable folders (`src/main/ridgun/<target>/main.rg`),
-- and provides interactive (`stable> `) and batch commands:
-- `build` / `built [target]`, `run [target] [args...]`, `test`,
-- `compile`, `check`, `clean`, `info`, `reload`, `help`, `exit`.
-- @implements FR-COMP-006
-- @implements FR-TOOL-001
-- @implements FR-TOOL-002
-- @implements FR-TOOL-003
-- ============================================================
import ast
import lexer
import parser
import analyzer
import typecheck
import compiler
import vm
import formatter
import str
import io
import list
import cli

-- Project configuration loaded from `build.rg`
type StableConfig = ProjectConfig String String String String String String

-- Custom task entry loaded from `build.rg` or a `.stable/plugins/*.rg` extension
type StableTask = TaskEntry String String String String

-- Core command sum type + open extension variants via `expand type` (`FR-TOOL-003`)
type StableCommand = CmdNoop | CmdExit | CmdHelp | CmdVersion | CmdInfo | CmdReload | CmdCheck | CmdCompile | CmdTest | CmdClean | CmdDeps | CmdTasks | CmdPlugins | CmdNew [String] | CmdInit [String] | CmdAdd [String] | CmdInstall [String] | CmdFormat [String] | CmdBuild [String] | CmdBuildLib [String] | CmdRun [String]

expand type StableCommand = CmdCustomTask String String [String] | CmdPluginExec String [String]

-- ── String & Filesystem Operators (powered by `str` & `io` libraries) ──

op :: flush non empty line String into [String] => [String]
      flush non empty line ""     into acc      =  acc
      flush non empty line line   into acc      =  acc :: [line]

op :: filter non empty trimmed [String] into [String] => [String]
      filter non empty trimmed []       into acc      =  acc
      filter non empty trimmed (l:ls)   into acc      =
        filter non empty trimmed ls into (flush non empty line (str trim l) into acc)

op :: split lines of String => [String]
      split lines of s      =  filter non empty trimmed (str split s "\n") into []

op :: char Int is whitespace => Bool
      char c   is whitespace =  is ascii space c

op :: split words loop String at Int of Int word String into [String] => [String]
      split words loop s at pos of len word cur into acc
        | pos >= len = flush non empty line cur into acc
        | char (str_char_at s pos) is whitespace = split words loop s at (pos + 1) of len word "" into (flush non empty line cur into acc)
        | otherwise = split words loop s at (pos + 1) of len word (cur + (str_slice s pos (pos + 1))) into acc

op :: split words of String => [String]
      split words of s      =  split words loop s at 0 of (str_len s) word "" into []

op :: join words [String] with spaces => String
      join words ws       with spaces =  str join ws " "

op :: collect flat rg in String entries [String] => [String]
      collect flat rg in _      entries []       =  []
      collect flat rg in dir    entries (e:es)   =
        full = dir + "/" + e
        append flat rg if match full to (collect flat rg in dir entries es)

op :: append flat rg if match String to [String] => [String]
      append flat rg if match full   to rest
        | (is file full) AND (str ends with full ".rg") = [full] :: rest
        | otherwise = rest

op :: collect sub rg in String entries [String] => [String]
      collect sub rg in _      entries []       =  []
      collect sub rg in dir    entries (e:es)   =
        sub = dir + "/" + e
        append sub rg if dir sub to (collect sub rg in dir entries es)

op :: append sub rg if dir String to [String] => [String]
      append sub rg if dir sub    to rest
        | is dir sub = (collect flat rg in sub entries (list_dir sub)) :: rest
        | otherwise  = rest

op :: list rg files in String => [String]
      list rg files in dir
        | NOT (is dir dir) = []
        | otherwise =
          ents = list str sort (list_dir dir)
          (collect flat rg in dir entries ents) :: (collect sub rg in dir entries ents)

op :: collect exec entries in String entries [String] => [String]
      collect exec entries in _      entries []       =  []
      collect exec entries in dir    entries (e:es)   =
        cand = dir + "/" + e + "/main.rg"
        append if file exists cand to (collect exec entries in dir entries es)

op :: append if file exists String to [String] => [String]
      append if file exists path   to rest
        | is file path = [path] :: rest
        | otherwise    = rest

op :: list exec entries in String => [String]
      list exec entries in dir
        | NOT (is dir dir) = []
        | otherwise = collect exec entries in dir entries (list str sort (list_dir dir))

op :: is test filename String => Bool
      is test filename name   =
        (str ends with name ".rg") AND ((str_starts_with name "test_") OR (str_starts_with name "test "))

op :: collect test files in String entries [String] => [String]
      collect test files in _      entries []       =  []
      collect test files in dir    entries (e:es)   =
        full = dir + "/" + e
        append test file if match e full to (collect test files in dir entries es)

op :: append test file if match String String to [String] => [String]
      append test file if match name   full   to rest
        | (is file full) AND (is test filename name) = [full] :: rest
        | otherwise = rest

op :: list test files in String => [String]
      list test files in dir
        | NOT (is dir dir) = []
        | otherwise = collect test files in dir entries (list str sort (list_dir dir))

op :: file String exists => Bool
      file path   exists =  is file path

-- ── Structured Console Logging Functions ─────────────────────

fn :: log info String => ()
      log info msg    =  echo "[info] {msg}"

fn :: log success String => ()
      log success msg    =  echo "[success] {msg}"

fn :: log error String => ()
      log error msg    =  echo "[error] {msg}"

fn :: log step String String => ()
      log step tag    msg    =
        padded = str pad right "[{tag}]" 7 " "
        echo "  {padded}{msg}"

fn :: log ok String => ()
      log ok msg    =  log step "ok" msg

fn :: log err String => ()
      log err msg    =  log step "err" msg

fn :: log pass String => ()
      log pass msg    =  log step "PASS" msg

fn :: log fail String => ()
      log fail msg    =  log step "FAIL" msg

fn :: log section String => ()
      log section title  =  echo "=== {title} ==="

op :: read prompt line with String     => (Bool, String)
      read prompt line with prompt_str =
        cmd = 'mkdir -p target && printf "%s" "' + prompt_str + '" && IFS= read -r _stable_ln && printf "%s" "$_stable_ln" > target/.stable_line.txt'
        st_code = shell_exec cmd
        decode prompt status st_code

op :: decode prompt status Int => (Bool, String)
      decode prompt status 0   =
        line = read_file "target/.stable_line.txt"
        _ = shell_exec "rm -f target/.stable_line.txt"
        (True, str trim line)
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
        | NOT (file build_path exists) = ProjectConfig "ridgunc" "0.9.7" "src/main/ridgun/ridgunc/main.rg" "src/main/ridgun" "src/test/ridgun" "target"
        | otherwise = parse build config source (read_file build_path)

op :: parse build config source String => StableConfig
      parse build config source src    =
        toks = tokenize_src src
        prog_ast = parse_tokens toks
        extract config from program prog_ast

op :: extract config from program RProgram        => StableConfig
      extract config from program (Program fns _) =
        name_str = extract function body from fns named "project_name" default "ridgunc"
        ver = extract function body from fns named "project_version" default "0.9.7"
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
        raw = load_rg_with_libs path
        toks = tokenize_src raw
        prog_ast = parse_tokens toks
        errs = typecheck_program prog_ast
        report check module path prog prog_ast errors errs

op :: report check module String prog RProgram errors [RTypeError] => (Int, Int)
      report check module path   prog prog_ast errors []           =
        fn_c = count_fn_defs prog_ast
        ty_c = count_type_defs prog_ast
        _ = log ok "{path} ({fn_c} fn, {ty_c} types)"
        (1, 0)
      report check module path   prog _        errors errs         =
        ec = type_err_count errs
        _ = log err "{path}: {ec} error(s)"
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
        _ = log info "Checking project '{name_str}' v{ver} in {sdir}/ ..."
        finish task check with (check modules files ok 0 err 0)

op :: finish task check with (Int, Int)    => Int
      finish task check with (ok_c, 0)     =
        _ = log success "Checked {ok_c} module(s) — 0 errors."
        0
      finish task check with (ok_c, err_c) =
        _ = log error "Checked {ok_c} module(s) — {err_c} error(s) found."
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
        _ = log step "rgc" "{path} -> {out_rgc} ({fn_c} functions)"
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
        _ = log success "Compiled {c_count} bytecode artifact(s) into {out_dir}/."
        0
      compile if check status code from _      into _       =  code

-- ── Task 3: `build` / `built` (Executables & Reusable Libraries) ─

op :: load project kind from String     => String
      load project kind from build_path
        | NOT (file build_path exists) = "bin"
        | otherwise =
          toks = tokenize_src (read_file build_path)
          extract kind from program (parse_tokens toks)

op :: extract kind from program RProgram        => String
      extract kind from program (Program fns _) =
        extract function body from fns named "project_kind" default "bin"

op :: resolve lib entry for String in String default String  => String
      resolve lib entry for tname  in sdir   default main_ep
        | file tname exists = tname
        | file (sdir + "/lib/" + tname + ".rg") exists = sdir + "/lib/" + tname + ".rg"
        | file (sdir + "/" + tname + "/lib.rg") exists = sdir + "/" + tname + "/lib.rg"
        | file (sdir + "/" + tname + "/main.rg") exists = sdir + "/" + tname + "/main.rg"
        | file (sdir + "/" + tname + ".rg") exists = sdir + "/" + tname + ".rg"
        | otherwise = main_ep

op :: build library artifacts from String into String named String version String => Int
      build library artifacts from entry_path into out_dir named lib_name version ver =
        _ = shell_exec ('mkdir -p "' + out_dir + '"')
        out_rglib = out_dir + "/" + lib_name + ".rglib"
        out_so = out_dir + "/lib" + lib_name + ".so"
        _ = log info "Building Ridgun library '{lib_name}' from {entry_path} (v{ver}) ..."
        st1 = emit_rglib_file entry_path out_rglib
        st2 = build_native_shared_library entry_path out_so
        report library build of out_rglib so out_so status1 st1 status2 st2

op :: report library build of String    so String status1 Int status2 Int => Int
      report library build of out_rglib so out_so status1 0   status2 0   =
        _ = log success "Built Ridgun library bundle: {out_rglib}"
        _ = log success "Built native ELF64 shared object: {out_so}"
        0
      report library build of out_rglib so out_so status1 st1 status2 st2 =
        _ = log error "Library build failed for {out_rglib} / {out_so} (status {st1}, {st2})"
        1

op :: run task build lib on StableConfig args [String]  => Int
      run task build lib on (ProjectConfig name_str ver main_ep sdir _ out_dir) args [] =
        lib_ep = resolve lib entry for name_str in sdir default main_ep
        build library artifacts from lib_ep into out_dir named name_str version ver
      run task build lib on (ProjectConfig _ ver main_ep sdir _ out_dir) args (tname:_) =
        lib_ep = resolve lib entry for tname in sdir default main_ep
        build library artifacts from lib_ep into out_dir named tname version ver

op :: build target from String     into String  version String => Int
      build target from entry_path into out_bin version ver    =
        _ = log info "Building native executable '{out_bin}' from {entry_path} (v{ver}) ..."
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

op :: run task build on StableConfig args [String]       => Int
      run task build on cfg          args ("lib":rest)   =
        run task build lib on cfg args rest
      run task build on cfg          args ("--lib":rest) =
        run task build lib on cfg args rest
      run task build on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args []
        | (load project kind from "build.rg") == "lib" =
          run task build lib on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args []
        | otherwise =
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
        _ = log success "Built native ELF executable: {out_bin}"
        0
      report build of out_bin status code =
        _ = log error "Build failed for {out_bin} (exit code {code})"
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
        _ = log info "Running ./{out_bin} {arg_str}"
        shell_exec ("./" + out_bin + " " + arg_str)
      exec binary if built code path _       args _          =  code

-- ── Task 5: `test` (Discover, Check, Build & Run Tests) ─────

fn :: run_single_test_suite String => (Int, Int)
      run_single_test_suite tpath  =
        _ = log info "Compiling & running test suite: {tpath}"
        bname = base filename of tpath at 0 len (str_len tpath) slash (0 - 1)
        bin_path = "target/.stable_test_" + bname + "_bin"
        st_code = build_native_fast_executable tpath bin_path
        run built test binary st_code suite tpath binary bin_path

op :: run built test binary Int suite String binary String   => (Int, Int)
      run built test binary 0   suite tpath  binary bin_path =
        run_st = shell_exec ('"./' + bin_path + '"; _st=$?; rm -f "' + bin_path + '"; exit $_st')
        record single test outcome run_st suite tpath
      run built test binary _   suite tpath  binary _        =
        _ = log fail "{tpath} (compilation/typecheck failed)"
        (0, 1)

op :: record single test outcome Int suite String => (Int, Int)
      record single test outcome 0   suite tpath  =
        _ = log pass "{tpath}"
        (1, 0)
      record single test outcome _   suite tpath  =
        _ = log fail "{tpath} (non-zero exit status)"
        (0, 1)

op :: execute test suites [String] passed Int    failed Int    => (Int, Int)
      execute test suites suites   passed pass_c failed fail_c =
        _ = shell_exec "mkdir -p target"
        results = map run_single_test_suite suites
        sum check results results ok pass_c err fail_c

op :: run task test on StableConfig => Int
      run task test on (ProjectConfig name_str _ _ _ tdir _) =
        suites = list test files in tdir
        _ = log info "Running test suites for '{name_str}' in {tdir}/ ..."
        finish task test with (execute test suites suites passed 0 failed 0)

op :: finish task test with (Int, Int)       => Int
      finish task test with (pass_c, 0)      =
        _ = log success "Passed {pass_c}/{pass_c} test suite(s) — 0 failures."
        0
      finish task test with (pass_c, fail_c) =
        total = pass_c + fail_c
        _ = log error "Passed {pass_c}/{total} test suite(s) — {fail_c} failed."
        1

-- ── Task 6: `format` (Canonical Aesthetic Formatting) ───────

op :: read raw file at String => String
      read raw file at path   =  read_file path

op :: report unchanged file String => Int
      report unchanged file path   =
        _ = log ok "{path} (already formatted)"
        0

op :: save formatted file String content String    => Int
      save formatted file path   content formatted =
        _ = write_file path formatted
        _ = log step "fmt" "{path} (formatted)"
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
        _ = log success "Formatted {chg_c}/{tot_c} file(s) using canonical Ridgun style."
        0

op :: run task format on StableConfig args [String]     => Int
      run task format on (ProjectConfig name_str _ _ sdir tdir _) args [] =
        b_files = include build file if present
        s_files = list rg files in sdir
        t_files = list rg files in tdir
        all_files = b_files :: s_files :: t_files
        _ = log info "Formatting project '{name_str}' source files ..."
        finish task format with (format file list all_files changed 0 total 0)
      run task format on _            args target_paths =
        _ = log info "Formatting specified Ridgun file(s) ..."
        finish task format with (format file list target_paths changed 0 total 0)

-- ── Task 7: `clean` & `info` & `help` ───────────────────────

op :: run task clean on StableConfig => Int
      run task clean on (ProjectConfig _ _ _ _ _ out_dir) =
        _ = shell_exec ('rm -f "' + out_dir + '"/*.rgc "' + out_dir + '"/*.rglib "' + out_dir + '"/*.so "' + out_dir + '"/.stable_* "' + out_dir + '"/.ridgunc_*')
        _ = log success "Cleaned bytecode and library artifacts in {out_dir}/."
        0

op :: collect target names of [String]     => [String]
      collect target names of []           =  []
      collect target names of (ep:rem_eps) =  [target name from entry ep] :: (collect target names of rem_eps)

op :: run task info on StableConfig => Int
      run task info on (ProjectConfig name_str ver main_ep sdir tdir out_dir) =
        pkind = load project kind from "build.rg"
        src_files = list rg files in sdir
        exec_entries = list exec entries in sdir
        exec_names = join words (collect target names of exec_entries) with spaces
        tst_files = list test files in tdir
        src_c = list_str_len src_files
        tst_c = list_str_len tst_files
        _ = log section "Project Info (build.rg)"
        _ = echo "  Project Name : {name_str}"
        _ = echo "  Project Kind : {pkind}"
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
        build_content = "-- build.rg — Ridgun Project Build Definition\n\nfn :: project name => String\n      project name =  \"" + pname + "\"\n\nfn :: project version => String\n      project version =  \"0.1.0\"\n\nfn :: main entry => String\n      main entry =  \"src/main/ridgun/" + pname + "/main.rg\"\n\nfn :: source dir => String\n      source dir =  \"src/main/ridgun\"\n\nfn :: test dir => String\n      test dir =  \"src/test/ridgun\"\n\nfn :: target dir => String\n      target dir =  \"target\"\n\nfn :: dependencies => [String]\n      dependencies =  []\n"
        main_content = "-- src/main/ridgun/" + pname + "/main.rg\n\nfn :: greet String => String\n      greet who    =  \"Hello from \" + who + \"!\"\n\nfn :: main => ()\n      main =  echo (greet \"" + pname + "\")\n"
        test_lib_content = "-- src/test/ridgun/test.rg — Standard Test Assertions (`import test`)\n\nfn :: fail test String => ()\n      fail test msg    =\n        _ = echo \"[FAIL] \" msg\n        sys_exit 1\n\nfn :: assert equals A      A        => ()\n      assert equals actual expected\n        | actual == expected = echo \"  [ok]  \" actual \"==\" expected\n        | otherwise = fail test \"assert_equals failed\"\n\nfn :: assert true Bool => ()\n      assert true cond\n        | cond = echo \"  [ok]   True\"\n        | otherwise = fail test \"assert_true failed\"\n"
        test_content = "-- src/test/ridgun/test main.rg\nimport test\n\nfn :: main => ()\n      main =\n        _ = assert true True\n        echo \"=== All " + pname + " tests passed ===\"\n"
        gitignore_content = "/target/\n/.stable/\n"
        _ = write_file (root + "/build.rg") build_content
        _ = write_file (root + "/src/main/ridgun/" + pname + "/main.rg") main_content
        _ = write_file (root + "/src/test/ridgun/test.rg") test_lib_content
        _ = write_file (root + "/src/test/ridgun/test main.rg") test_content
        _ = write_file (root + "/.gitignore") gitignore_content
        _ = log success "Scaffolded Ridgun project '{pname}' in {root}/"
        0

op :: scaffold lib project named String in String => Int
      scaffold lib project named pname  in root   =
        _ = shell_exec ('mkdir -p "' + root + '/src/main/ridgun/lib" "' + root + '/src/test/ridgun" "' + root + '/target"')
        build_content = "-- build.rg — Ridgun Library Project Definition\n\nfn :: project name => String\n      project name =  \"" + pname + "\"\n\nfn :: project kind => String\n      project kind =  \"lib\"\n\nfn :: project version => String\n      project version =  \"0.1.0\"\n\nfn :: main entry => String\n      main entry =  \"src/main/ridgun/lib/" + pname + ".rg\"\n\nfn :: source dir => String\n      source dir =  \"src/main/ridgun\"\n\nfn :: test dir => String\n      test dir =  \"src/test/ridgun\"\n\nfn :: target dir => String\n      target dir =  \"target\"\n\nfn :: dependencies => [String]\n      dependencies =  []\n"
        lib_content = "-- src/main/ridgun/lib/" + pname + ".rg\n\nfn :: greet String => String\n      greet who    =  \"Hello from library \" + who + \"!\"\n"
        test_lib_content = "-- src/test/ridgun/test.rg — Standard Test Assertions (`import test`)\n\nfn :: fail test String => ()\n      fail test msg    =\n        _ = echo \"[FAIL] \" msg\n        sys_exit 1\n\nfn :: assert equals A      A        => ()\n      assert equals actual expected\n        | actual == expected = echo \"  [ok]  \" actual \"==\" expected\n        | otherwise = fail test \"assert_equals failed\"\n\nfn :: assert true Bool => ()\n      assert true cond\n        | cond = echo \"  [ok]   True\"\n        | otherwise = fail test \"assert_true failed\"\n"
        test_content = "-- src/test/ridgun/test main.rg\nimport test\nimport " + pname + "\n\nfn :: main => ()\n      main =\n        _ = assert equals (greet \"" + pname + "\") \"Hello from library " + pname + "!\"\n        echo \"=== All " + pname + " library tests passed ===\"\n"
        gitignore_content = "/target/\n/.stable/\n"
        _ = write_file (root + "/build.rg") build_content
        _ = write_file (root + "/src/main/ridgun/lib/" + pname + ".rg") lib_content
        _ = write_file (root + "/src/test/ridgun/test.rg") test_lib_content
        _ = write_file (root + "/src/test/ridgun/test main.rg") test_content
        _ = write_file (root + "/.gitignore") gitignore_content
        _ = log success "Scaffolded Ridgun library project '{pname}' in {root}/"
        0

op :: run task new args [String]   => Int
      run task new args extra_args =
        pos_args = cli positionals extra_args
        is_lib = cli has flag extra_args "--lib" "-l"
        run task new target pos_args lib is_lib

op :: run task new target [String]  lib Bool   => Int
      run task new target []        lib _      =
        _ = log error "Usage: stable new [--lib] <project_name>"
        1
      run task new target (pname:_) lib is_lib
        | file (pname + "/build.rg") exists =
          _ = log error "Project '{pname}' already exists at {pname}/build.rg"
          1
        | is_lib = scaffold lib project named pname in pname
        | otherwise = scaffold project named pname in pname

op :: run task init args [String]   => Int
      run task init args extra_args
        | file "build.rg" exists =
          _ = log info "build.rg already exists in current directory."
          0
        | otherwise =
          cwd = sys_getcwd
          pname = base filename of cwd at 0 len (str_len cwd) slash (0 - 1)
          init current dir named pname lib (cli has flag extra_args "--lib" "-l")

op :: init current dir named String lib Bool  => Int
      init current dir named pname  lib True  =  scaffold lib project named pname in "."
      init current dir named pname  lib False =  scaffold project named pname in "."

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
        _ = shell_exec ('if ls "' + dest + '"/target/bundles/*.rglib >/dev/null 2>&1; then cp -f "' + dest + '"/target/bundles/*.rglib .stable/deps/ 2>/dev/null || true; elif ls "' + dest + '"/target/*.rglib >/dev/null 2>&1; then cp -f "' + dest + '"/target/*.rglib .stable/deps/ 2>/dev/null || true; elif ls "' + dest + '"/*.rglib >/dev/null 2>&1; then cp -f "' + dest + '"/*.rglib .stable/deps/ 2>/dev/null || true; else cp -f "' + dest + '"/src/main/ridgun/lib/*.rg src/main/ridgun/lib/ 2>/dev/null || cp -f "' + dest + '"/*.rg src/main/ridgun/lib/ 2>/dev/null || true; fi')
        _ = log step "dep" "{dep} -> {dest}"
        st

op :: sync dependency list [String] => Int
      sync dependency list []       =
        _ = log ok "No external dependencies declared in build.rg."
        0
      sync dependency list (d:ds)   =
        _ = sync single dependency d
        sync dependency list ds

op :: run task deps => Int
      run task deps =
        deps = load dependencies from "build.rg"
        _ = log info "Synchronizing dependencies from build.rg into .stable/deps/ ..."
        _ = sync dependency list deps
        _ = log success "Dependencies synchronized."
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
        _ = log error "Usage: stable add <git_url_or_path>"
        1
      run task add args (new_dep:_) =
        cur_deps = load dependencies from "build.rg"
        all_deps = cur_deps :: [new_dep]
        dep_block = '\nfn :: dependencies => [String]\n      dependencies =  [' + (format dep items all_deps) + ']\n'
        _ = append dep block if needed dep_block
        _ = sync single dependency new_dep
        _ = log success "Added dependency '{new_dep}'."
        0

op :: install built binaries Int from String  => Int
      install built binaries 0   from out_dir =
        home = env get or "HOME" "."
        inst_dir = home + "/.local/bin"
        _ = shell_exec ('mkdir -p "' + inst_dir + '" bin && for f in "' + out_dir + '"/*; do if [ -f "$f" ] && [ -x "$f" ]; then cp -f "$f" "' + inst_dir + '/" && cp -f "$f" bin/; fi; done')
        _ = log success "Installed executable(s) from {out_dir}/ into {inst_dir}/ and bin/."
        0
      install built binaries st  from _       =  st

op :: run task install on StableConfig args [String] => Int
      run task install on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args extra =
        build_st = run task build on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args extra
        install built binaries build_st from out_dir

-- ── Task 9: Custom Tasks, Plugins, and Framework Extensions (`FR-TOOL-003`) ──

op :: task display name of String   => String
      task display name of raw_name =
        str replace raw_name "_" " "

op :: extract tasks from fns [RFnDef]    origin String     => [StableTask]
      extract tasks from fns []          origin _          =  []
      extract tasks from fns ((FnDef fn_name _ _ ((FnCase _ _ (EStr cmd)):_)):rem_fns) origin orig_label
        | (str_starts_with fn_name "task_") AND ((str_len fn_name) > 5) =
          raw_key = str_slice fn_name 5 (str_len fn_name)
          disp = task display name of raw_key
          [TaskEntry raw_key disp cmd orig_label] :: (extract tasks from fns rem_fns origin orig_label)
        | otherwise = extract tasks from fns rem_fns origin orig_label
      extract tasks from fns (_:rem_fns) origin orig_label =
        extract tasks from fns rem_fns origin orig_label

op :: extract tasks from program RProgram        origin String => [StableTask]
      extract tasks from program (Program fns _) origin orig   =
        extract tasks from fns fns origin orig

op :: load tasks from file String origin String => [StableTask]
      load tasks from file path   origin orig
        | NOT (file path exists) = []
        | otherwise =
          prog = parse_tokens (tokenize_src (read_file path))
          extract tasks from program prog origin orig

op :: extract plugins from program RProgram        => [String]
      extract plugins from program (Program fns _) =
        extract list function body from fns named "plugins"

op :: load declared plugins from String     => [String]
      load declared plugins from build_path
        | NOT (file build_path exists) = []
        | otherwise =
          toks = tokenize_src (read_file build_path)
          extract plugins from program (parse_tokens toks)

op :: resolve plugin path for String => String
      resolve plugin path for p
        | file p exists = p
        | file ("plugins/" + p + ".rg") exists = "plugins/" + p + ".rg"
        | file (".stable/plugins/" + p + ".rg") exists = ".stable/plugins/" + p + ".rg"
        | file (".stable/deps/" + p + "/plugin.rg") exists = ".stable/deps/" + p + "/plugin.rg"
        | otherwise = ""

op :: resolve plugin list [String]   => [String]
      resolve plugin list []         =  []
      resolve plugin list (p:rem_ps) =
        resolved = resolve plugin path for p
        append resolved plugin resolved to (resolve plugin list rem_ps)

op :: append resolved plugin String to [String] => [String]
      append resolved plugin ""     to acc      =  acc
      append resolved plugin path   to acc
        | str_in_list path acc = acc
        | otherwise = [path] :: acc

op :: discover plugin files => [String]
      discover plugin files =
        auto_p1 = list rg files in "plugins"
        auto_p2 = list rg files in ".stable/plugins"
        auto_files = auto_p1 :: auto_p2
        decl_names = load declared plugins from "build.rg"
        decl_files = resolve plugin list decl_names
        list str dedup (decl_files :: auto_files)

op :: load tasks from plugins [String]     => [StableTask]
      load tasks from plugins []           =  []
      load tasks from plugins (pp:rem_pps) =
        (load tasks from file pp origin pp) :: (load tasks from plugins rem_pps)

op :: load all custom tasks => [StableTask]
      load all custom tasks =
        build_tasks = load tasks from file "build.rg" origin "build.rg"
        plugin_files = discover plugin files
        plugin_tasks = load tasks from plugins plugin_files
        build_tasks :: plugin_tasks

op :: words [String] start with [String] => Bool
      words _        start with []       =  True
      words []       start with (_:_)    =  False
      words (a:as)   start with (b:bs)
        | a == b = words as start with bs
        | otherwise = False

op :: match task entry StableTask against [String] => (Bool, Int, String, String, [String])
      match task entry (TaskEntry key disp cmd _) against args_list =
        t_words = split words of disp
        t_len = list_str_len t_words
        match task words key disp cmd t_words t_len against args_list

op :: match task words String String String [String] Int against [String] => (Bool, Int, String, String, [String])
      match task words _ _ _ _ _ against [] = (False, 0, "", "", [])
      match task words key disp cmd t_words t_len against (first_w:rest_w)
        | first_w == key = (True, 1, disp, cmd, rest_w)
        | words ([first_w] :: rest_w) start with t_words = (True, t_len, disp, cmd, list str drop ([first_w] :: rest_w) t_len)
        | otherwise = (False, 0, "", "", [])

op :: pick longer task match (Bool, Int, String, String, [String]) and (Bool, Int, String, String, [String]) => (Bool, Int, String, String, [String])
      pick longer task match (False, _, _, _, _) and m2 = m2
      pick longer task match m1 and (False, _, _, _, _) = m1
      pick longer task match (True, len1, d1, c1, e1) and (True, len2, d2, c2, e2)
        | len2 > len1 = (True, len2, d2, c2, e2)
        | otherwise = (True, len1, d1, c1, e1)

op :: find matching custom task in [StableTask] for [String] => (Bool, Int, String, String, [String])
      find matching custom task in [] for _ = (False, 0, "", "", [])
      find matching custom task in (t:rem_ts) for args_list =
        m1 = match task entry t against args_list
        m2 = find matching custom task in rem_ts for args_list
        pick longer task match m1 and m2

op :: print custom tasks [StableTask] => ()
      print custom tasks []           =  ()
      print custom tasks ((TaskEntry _ disp cmd orig):rem_ts) =
        _ = echo "  {disp}  ->  {cmd}  [{orig}]"
        print custom tasks rem_ts

op :: run task tasks => Int
      run task tasks =
        custom_ts = load all custom tasks
        _ = log section "Built-in `stable` Tasks"
        _ = echo "  new [--lib] <name>, init [--lib], deps, add <dep>, install [target]"
        _ = echo "  build | built [lib | target], run [target], test, check, format, compile, clean"
        _ = echo "  info | status, tasks, plugins, reload, help, exit"
        _ = log section "Custom Project & Plugin Tasks"
        report custom task list custom_ts

op :: report custom task list [StableTask] => Int
      report custom task list []           =
        _ = echo "  (none declared — add `fn :: task <name> => String` in build.rg or plugins/*.rg)"
        0
      report custom task list custom_ts    =
        _ = print custom tasks custom_ts
        0

op :: print plugin files [String]     => ()
      print plugin files []           =  ()
      print plugin files (pp:rem_pps) =
        p_tasks = load tasks from file pp origin pp
        t_count = count custom tasks p_tasks
        _ = log step "plugin" "{pp} ({t_count} custom task(s))"
        print plugin files rem_pps

op :: count custom tasks [StableTask] => Int
      count custom tasks []           =  0
      count custom tasks (_:rem_ts)   =  1 + (count custom tasks rem_ts)

op :: run task plugins => Int
      run task plugins =
        pfiles = discover plugin files
        _ = log section "Loaded `stable` Plugins"
        report plugin file list pfiles

op :: report plugin file list [String] => Int
      report plugin file list []       =
        _ = echo "  (no plugins loaded — add `fn :: plugins => [String]` in build.rg or create plugins/<name>.rg)"
        0
      report plugin file list pfiles   =
        _ = print plugin files pfiles
        0

op :: run custom shell task String command String extra [String]   => Int
      run custom shell task disp   command cmd    extra []         =
        _ = echo "[task:{disp}] {cmd}"
        shell_exec cmd
      run custom shell task disp   command cmd    extra extra_args =
        arg_str = join words extra_args with spaces
        full_cmd = cmd + " " + arg_str
        _ = echo "[task:{disp}] {full_cmd}"
        shell_exec full_cmd

op :: run executable plugin String args [String]   => Int
      run executable plugin ppath  args extra_args =
        _ = shell_exec "mkdir -p target"
        bname = base filename of ppath at 0 len (str_len ppath) slash (0 - 1)
        bin_path = "target/.stable_plugin_" + bname + "_bin"
        st = build_native_fast_executable ppath bin_path
        exec plugin binary st path bin_path args extra_args

op :: exec plugin binary Int path String   args [String]   => Int
      exec plugin binary 0   path bin_path args extra_args =
        arg_str = join words extra_args with spaces
        shell_exec ('"./' + bin_path + '" ' + arg_str + '; _st=$?; rm -f "' + bin_path + '"; exit $_st')
      exec plugin binary st  path _        args _          =  st

op :: run task help => Int
      run task help =
        _ = echo "Available `stable` commands:"
        _ = echo "  new [--lib] <name>          Create a new Ridgun project (or library with --lib)"
        _ = echo "  init [--lib]                Initialize build.rg and src/ in the current directory"
        _ = echo "  deps                        Synchronize dependencies from build.rg into .stable/deps/"
        _ = echo "  add <dep>                   Add a Git URL or path dependency to build.rg and sync .stable/deps/"
        _ = echo "  install [target]            Build and install native ELF64 executable(s) into ~/.local/bin/ and bin/"
        _ = echo "  build | built [target]      Compile all executables (or [target]) into target/<target>"
        _ = echo "  build lib | built lib       Compile reusable library (.rglib and native ELF64 .so) into target/"
        _ = echo "  run [target] [args...]      Build (if needed) and run executable (default: main_entry)"
        _ = echo "  test                        Discover, typecheck, compile, and execute all test suites in src/test/ridgun/"
        _ = echo "  check                       Typecheck and run static analysis across all modules in src/main/ridgun/"
        _ = echo "  format [file...]            Apply canonical aesthetic column-alignment formatting to .rg files"
        _ = echo "  compile                     Typecheck and emit .rgc bytecode artifacts into target/"
        _ = echo "  clean                       Remove compiled .rgc/.rglib/.so artifacts from target/"
        _ = echo "  tasks                       List built-in commands and custom tasks from build.rg & plugins"
        _ = echo "  plugins                     List discovered and configured stable plugins"
        _ = echo "  info | status               Display project configuration from build.rg"
        _ = echo "  reload                      Reload project configuration from build.rg"
        _ = echo "  help                        Show this help summary"
        _ = echo "  exit | quit                 Exit the interactive stable shell"
        0

-- ── Command Parser & Extensible `StableCommand` Dispatcher ───

op :: parse stable command [String]          => (Bool, StableCommand, String)
      parse stable command []                =  (True, CmdNoop, "")
      parse stable command ("exit":_)        =  (True, CmdExit, "")
      parse stable command ("quit":_)        =  (True, CmdExit, "")
      parse stable command ("q":_)           =  (True, CmdExit, "")
      parse stable command ("help":_)        =  (True, CmdHelp, "")
      parse stable command ("-h":_)          =  (True, CmdHelp, "")
      parse stable command ("--help":_)      =  (True, CmdHelp, "")
      parse stable command ("version":_)     =  (True, CmdVersion, "")
      parse stable command ("-v":_)          =  (True, CmdVersion, "")
      parse stable command ("info":_)        =  (True, CmdInfo, "")
      parse stable command ("status":_)      =  (True, CmdInfo, "")
      parse stable command ("reload":_)      =  (True, CmdReload, "")
      parse stable command ("check":_)       =  (True, CmdCheck, "")
      parse stable command ("new":extra)     =  (True, CmdNew extra, "")
      parse stable command ("init":extra)    =  (True, CmdInit extra, "")
      parse stable command ("deps":_)        =  (True, CmdDeps, "")
      parse stable command ("add":extra)     =  (True, CmdAdd extra, "")
      parse stable command ("install":extra) =  (True, CmdInstall extra, "")
      parse stable command ("format":extra)  =  (True, CmdFormat extra, "")
      parse stable command ("fmt":extra)     =  (True, CmdFormat extra, "")
      parse stable command ("compile":_)     =  (True, CmdCompile, "")
      parse stable command ("build":"lib":extra) = (True, CmdBuildLib extra, "")
      parse stable command ("built":"lib":extra) = (True, CmdBuildLib extra, "")
      parse stable command ("build":"--lib":extra) = (True, CmdBuildLib extra, "")
      parse stable command ("built":"--lib":extra) = (True, CmdBuildLib extra, "")
      parse stable command ("build":extra)   =  (True, CmdBuild extra, "")
      parse stable command ("built":extra)   =  (True, CmdBuild extra, "")
      parse stable command ("run":extra)     =  (True, CmdRun extra, "")
      parse stable command ("test":_)        =  (True, CmdTest, "")
      parse stable command ("clean":_)       =  (True, CmdClean, "")
      parse stable command ("tasks":_)       =  (True, CmdTasks, "")
      parse stable command ("plugins":_)     =  (True, CmdPlugins, "")
      parse stable command args_list         =
        custom_ts = load all custom tasks
        t_match = find matching custom task in custom_ts for args_list
        resolve extension command args_list match t_match

op :: resolve extension command [String] match (Bool, Int, String, String, [String]) => (Bool, StableCommand, String)
      resolve extension command _ match (True, _, disp, cmd, extra) =
        (True, CmdCustomTask disp cmd extra, "")
      resolve extension command (first_w:rest_w) match (False, _, _, _, _) =
        ppath = resolve plugin path for first_w
        resolve plugin exec command first_w rest_w path ppath
      resolve extension command [] match (False, _, _, _, _) =
        (True, CmdNoop, "")

op :: resolve plugin exec command String [String] path String => (Bool, StableCommand, String)
      resolve plugin exec command first_w _ path "" =
        (False, CmdNoop, first_w)
      resolve plugin exec command _ rest_w path ppath =
        (True, CmdPluginExec ppath rest_w, "")

-- Core `StableCommand` dispatch clauses
op :: dispatch command StableCommand on StableConfig => (Bool, StableConfig, Int)
      dispatch command CmdNoop on cfg = (True, cfg, 0)
      dispatch command CmdExit on cfg = (False, cfg, 0)
      dispatch command CmdHelp on cfg = (True, cfg, run task help)
      dispatch command CmdVersion on cfg =
        _ = echo "stable 0.9.7 (Ridgun Interactive Build Tool, 100% self-hosted in Ridgun)"
        (True, cfg, 0)
      dispatch command CmdInfo on cfg = (True, cfg, run task info on cfg)
      dispatch command CmdReload on _ =
        new_cfg = load build config from "build.rg"
        pname = project name of new_cfg
        _ = log info "Reloaded build.rg — current project is '{pname}'"
        (True, new_cfg, 0)
      dispatch command CmdCheck on cfg = (True, cfg, run task check on cfg)
      dispatch command (CmdNew extra) on cfg = (True, cfg, run task new args extra)
      dispatch command (CmdInit extra) on cfg = (True, cfg, run task init args extra)
      dispatch command CmdDeps on cfg = (True, cfg, run task deps)
      dispatch command (CmdAdd extra) on cfg = (True, cfg, run task add args extra)
      dispatch command (CmdInstall extra) on cfg = (True, cfg, run task install on cfg args extra)
      dispatch command (CmdFormat extra) on cfg = (True, cfg, run task format on cfg args extra)
      dispatch command CmdCompile on cfg = (True, cfg, run task compile on cfg)
      dispatch command (CmdBuildLib extra) on cfg = (True, cfg, run task build lib on cfg args extra)
      dispatch command (CmdBuild extra) on cfg = (True, cfg, run task build on cfg args extra)
      dispatch command (CmdRun extra) on cfg = (True, cfg, run task run on cfg args extra)
      dispatch command CmdTest on cfg = (True, cfg, run task test on cfg)
      dispatch command CmdClean on cfg = (True, cfg, run task clean on cfg)
      dispatch command CmdTasks on cfg = (True, cfg, run task tasks)
      dispatch command CmdPlugins on cfg = (True, cfg, run task plugins)

-- Extension `StableCommand` dispatch clauses (merged automatically for `expand type StableCommand`)
op :: dispatch command StableCommand on StableConfig => (Bool, StableConfig, Int)
      dispatch command (CmdCustomTask disp cmd extra) on cfg =
        (True, cfg, run custom shell task disp command cmd extra extra)
      dispatch command (CmdPluginExec ppath extra) on cfg =
        (True, cfg, run executable plugin ppath args extra)

op :: execute command [String] on StableConfig => (Bool, StableConfig, Int)
      execute command words    on cfg          =
        parsed = parse stable command words
        execute parsed command parsed on cfg

op :: execute parsed command (Bool, StableCommand, String) on StableConfig => (Bool, StableConfig, Int)
      execute parsed command (True, cmd, _) on cfg =
        dispatch command cmd on cfg
      execute parsed command (False, _, unknown) on cfg =
        _ = log error "Unknown command: '{unknown}'. Type 'help' or 'tasks' for available commands."
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
        log info "Exiting stable."
      repl continue with (True, next_cfg, _)       =
        repl loop for next_cfg

op :: start interactive shell for StableConfig => ()
      start interactive shell for (ProjectConfig name_str ver main_ep sdir tdir out_dir) =
        _ = log info "Welcome to stable 0.9.7 (Ridgun Build Tool — 100% Ridgun)"
        _ = log info "Loading project definition from build.rg ..."
        _ = log info "Set current project to '{name_str}' v{ver} (main: {main_ep})"
        _ = log info "Commands: 'built' (or 'build'), 'run', 'test', 'check', 'compile', 'clean', 'info', 'exit'"
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

op :: exit if non zero Int => ()
      exit if non zero 0   =  ()
      exit if non zero st  =  sys_exit st

op :: dispatch stable cli [String]  on StableConfig => ()
      dispatch stable cli []        on cfg          =  start interactive shell for cfg
      dispatch stable cli args_list on cfg          =
        res = execute command args_list on cfg
        exit if non zero (trd3 res)

fn :: trd3 (Bool, StableConfig, Int) => Int
      trd3 (_, _, st)                =  st

fn :: main => ()
      main =
        cfg = load build config from "build.rg"
        args_list = strip stable argv cli_args
        dispatch stable cli args_list on cfg
