-- ============================================================
-- src/main/ridgun/stable/main.rg
-- `stable` v1.0.8 — The Interactive Build Tool for Ridgun (100% Ridgun)
-- Written in Ridgun's natural-language mixfix operator style (`op :: ...`).
-- Decoupled from `ridgunc` internals per ADR-0001: delegates `check`,
-- `compile`, `build`, `build lib`, and test/plugin compilation to the
-- standalone `ridgunc` CLI binary instead of embedding the compiler.
-- @implements FR-COMP-006
-- @implements FR-COMP-015
-- @implements FR-TOOL-001
-- @implements FR-TOOL-002
-- @implements FR-TOOL-003
-- ============================================================
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
type StableCommand = CmdNoop | CmdExit | CmdHelp | CmdVersion | CmdInfo | CmdReload | CmdCheck | CmdCompile | CmdTest | CmdClean | CmdDeps | CmdTasks | CmdPlugins | CmdNew [String] | CmdInit [String] | CmdAdd [String] | CmdDev [String] | CmdInstall [String] | CmdFormat [String] | CmdBuild [String] | CmdBuildLib [String] | CmdRun [String]

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
        | char (str char at s pos) is whitespace = split words loop s at (pos + 1) of len word "" into (flush non empty line cur into acc)
        | otherwise = split words loop s at (pos + 1) of len word (cur + (str slice s pos (pos + 1))) into acc

op :: split words of String => [String]
      split words of s      =  split words loop s at 0 of (str len s) word "" into []

op :: join words [String] with spaces => String
      join words ws       with spaces =  str join ws " "

op :: collect flat rg in String entries [String] => [String]
      collect flat rg in _      entries []       =  []
      collect flat rg in dir    entries (e:es)   =
        full = dir + "/" + e
        append flat rg if match full to (collect flat rg in dir entries es)

op :: append flat rg if match String to [String] => [String]
      append flat rg if match full   to rest
        | (is file full) and (str ends with full ".rg") = [full] :: rest
        | otherwise = rest

op :: collect sub rg in String entries [String] => [String]
      collect sub rg in _      entries []       =  []
      collect sub rg in dir    entries (e:es)   =
        sub = dir + "/" + e
        append sub rg if dir sub to (collect sub rg in dir entries es)

op :: append sub rg if dir String to [String] => [String]
      append sub rg if dir sub    to rest
        | is dir sub = (collect flat rg in sub entries (list dir sub)) :: rest
        | otherwise  = rest

op :: list rg files in String => [String]
      list rg files in dir
        | not (is dir dir) = []
        | otherwise =
          ents = list str sort (list dir dir)
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
        | not (is dir dir) = []
        | otherwise = collect exec entries in dir entries (list str sort (list dir dir))

op :: is test filename String => Bool
      is test filename name   =
        (str ends with name ".rg") and ((str starts with name "test_") or (str starts with name "test "))

op :: collect test files in String entries [String] => [String]
      collect test files in _      entries []       =  []
      collect test files in dir    entries (e:es)   =
        full = dir + "/" + e
        append test file if match e full to (collect test files in dir entries es)

op :: append test file if match String String to [String] => [String]
      append test file if match name   full   to rest
        | (is file full) and (is test filename name) = [full] :: rest
        | otherwise = rest

op :: list test files in String => [String]
      list test files in dir
        | not (is dir dir) = []
        | otherwise = collect test files in dir entries (list str sort (list dir dir))

-- ── Structured Console Logging Functions ─────────────────────

fn :: tag ansi code String => String
      tag ansi code "ok"      =  "32"
      tag ansi code "success" =  "32"
      tag ansi code "PASS"    =  "32"
      tag ansi code "error"   =  "31"
      tag ansi code "err"     =  "31"
      tag ansi code "FAIL"    =  "31"
      tag ansi code "warn"    =  "33"
      tag ansi code _         =  "36"

fn :: colorize tag String => String
      colorize tag tag    =
        esc = char from code 27
        code = tag ansi code tag
        "[" + esc + "[" + code + "m" + tag + esc + "[0m]"

fn :: log info String => ()
      log info msg    =
        ctag = colorize tag "info"
        echo "{ctag} {msg}"

fn :: log success String => ()
      log success msg    =
        ctag = colorize tag "success"
        echo "{ctag} {msg}"

fn :: log error String => ()
      log error msg    =
        ctag = colorize tag "error"
        echo "{ctag} {msg}"

fn :: log warn String => ()
      log warn msg    =
        ctag = colorize tag "warn"
        echo "{ctag} {msg}"

fn :: log step String String => ()
      log step tag    msg    =
        ctag = colorize tag tag
        vis_pad = str repeat " " (7 - ((str len tag) + 2))
        echo "  {ctag}{vis_pad}{msg}"

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

op :: read prompt line with String     => Bool String
      read prompt line with prompt_str =
        sys write fd 1 prompt_str -> ()
        read stdin line ""

-- One byte at a time up to the end of the line; False at the end of the input.
op :: read stdin line String => Bool String
      read stdin line acc =  next stdin char (sys read fd 0 1) acc

op :: next stdin char String String => Bool String
      next stdin char ""   acc =  (acc != "", str trim acc)
      next stdin char "\n" acc =  (True, str trim acc)
      next stdin char c    acc =  read stdin line (acc + c)

-- ── Files, folders and tools without a shell ───────────────────
-- Windows has no `sh`, so stable makes folders, removes and copies files and starts tools through system
-- calls and argument lists. Only the commands of user tasks (`fn :: task ...` in build.rg) go to the shell.

op :: is path sep Int => Bool
      is path sep c =  c == 47 or c == 92

op :: host exe ext => String
      host exe ext =  exe ext on (host os)

op :: host os => SysOs
      host os =  sys os

op :: exe ext on SysOs => String
      exe ext on Windows =  ".exe"
      exe ext on _       =  ""

-- `mkdir -p`: the missing parents first.
op :: ensure folder String => ()
      ensure folder path
        | path == "" = ()
        | is dir path = ()
        | otherwise =
          ensure folder (parent dir of path at 0 len (str len path) slash 0)
          sys mkdir path 493
          ()

op :: discard file String => ()
      discard file path =  remove file path -> ()

-- `rm -rf`: a link is removed, not followed.
op :: remove tree String => ()
      remove tree path
        | is dir path =
          remove entries (list dir path) in path
          remove dir path -> ()
        | otherwise = discard file path

op :: remove entries [String] in String => ()
      remove entries []     in _   =  ()
      remove entries (e:es) in dir =
        remove tree (dir + "/" + e)
        remove entries es in dir

-- `cp`: the bytes and the permission bits.
op :: copy file String to String => ()
      copy file src to dst =
        write bytes dst (read bytes src)
        sys chmod dst (file mode src) -> ()

-- A folder with everything under it, except the names in `skip` (at any depth) and links.
op :: copy tree String to String skipping [String] => ()
      copy tree src to dst skipping skip
        | is dir src =
          ensure folder dst
          copy entries (list str sort (list dir src)) from src to dst skipping skip
        | is file src = copy file src to dst
        | otherwise = ()

op :: copy entries [String] from String to String skipping [String] => ()
      copy entries []     from _   to _   skipping _    =  ()
      copy entries (e:es) from src to dst skipping skip
        | name e is in skip = copy entries es from src to dst skipping skip
        | otherwise =
          copy tree (src + "/" + e) to (dst + "/" + e) skipping skip
          copy entries es from src to dst skipping skip

op :: name String is in [String] => Bool
      name _ is in []     =  False
      name n is in (x:xs) =  n == x or (name n is in xs)

-- ── `build.rg` Declarative Configuration & `ridgunc` CLI Bridge ──

op :: base filename of String at Int len Int       slash Int        => String
      base filename of path   at pos len total_len slash last_slash
        | pos >= total_len = str slice path (last_slash + 1) total_len
        | is path sep (str char at path pos) = base filename of path at (pos + 1) len total_len slash pos
        | otherwise = base filename of path at (pos + 1) len total_len slash last_slash

op :: parent dir of String at Int len Int       slash Int        => String
      parent dir of path   at pos len total_len slash last_slash
        | pos >= total_len = str slice path 0 last_slash
        | is path sep (str char at path pos) = parent dir of path at (pos + 1) len total_len slash pos
        | otherwise = parent dir of path at (pos + 1) len total_len slash last_slash

op :: target name from entry String     => String
      target name from entry entry_path =
        pdir = parent dir of entry_path at 0 len (str len entry_path) slash 0
        base filename of pdir at 0 len (str len pdir) slash (0 - 1)

op :: first cli arg of [String] => String
      first cli arg of []       =  ""
      first cli arg of (a:_)    =  a

op :: pick sibling ridgunc in String => String
      pick sibling ridgunc in pdir
        | file (pdir + "/ridgunc_candidate" + host exe ext) exists = pdir + "/ridgunc_candidate" + host exe ext
        | otherwise = pdir + "/ridgunc" + host exe ext

op :: sibling ridgunc from argv0 String => String
      sibling ridgunc from argv0 a0
        | (str contains a0 "/") or (str contains a0 "\\") =
          pdir = parent dir of a0 at 0 len (str len a0) slash 0
          pick sibling ridgunc in pdir
        | otherwise = ""

op :: resolve ridgunc binary => String
      resolve ridgunc binary =
        env_rg = env get or "RIDGUNC" ""
        sib_rg = sibling ridgunc from argv0 (first cli arg of cli args)
        pick ridgunc binary env_rg sibling sib_rg

op :: pick ridgunc binary String sibling String => String
      pick ridgunc binary env_rg sibling sib_rg
        | (env_rg != "") and (file env_rg exists) = env_rg
        | (sib_rg != "") and (file sib_rg exists) = sib_rg
        | file "bin/ridgunc" exists = "bin/ridgunc"
        | file "target/ridgunc" exists = "target/ridgunc"
        | file "/home/boogie/ridgun/bin/ridgunc" exists = "/home/boogie/ridgun/bin/ridgunc"
        | otherwise = "ridgunc"

op :: strict args from String => [String]
      strict args from build_path
        | (load strict flag from build_path) == "" = []
        | otherwise = ["--strict"]

op :: verify artifact built Int at String   => Int
      verify artifact built 0   at out_path
        | file out_path exists = 0
        | otherwise = 1
      verify artifact built _   at _        =  1

op :: invoke ridgunc build String     into String  => Int
      invoke ridgunc build entry_path into out_bin =
        rg_bin = resolve ridgunc binary
        discard file out_bin
        sys exec rg_bin (["build", "--quiet"] :: (strict args from "build.rg") :: [entry_path, "-o", out_bin]) [] -> verify artifact built at out_bin

op :: invoke ridgunc build target String     into String  for String      => Int
      invoke ridgunc build target entry_path into out_bin for target_arch =
        rg_bin = resolve ridgunc binary
        discard file out_bin
        sys exec rg_bin (["build", "--quiet", "--target", target_arch] :: (strict args from "build.rg") :: [entry_path, "-o", out_bin]) [] -> verify artifact built at out_bin

op :: invoke ridgunc rglib String     into String    => Int
      invoke ridgunc rglib entry_path into out_rglib =
        rg_bin = resolve ridgunc binary
        discard file out_rglib
        sys exec rg_bin (["build", "--quiet", "--lib"] :: (strict args from "build.rg") :: [entry_path, "-o", out_rglib]) [] -> verify artifact built at out_rglib

op :: invoke ridgunc so String     into String => Int
      invoke ridgunc so entry_path into out_so =
        rg_bin = resolve ridgunc binary
        discard file out_so
        sys exec rg_bin (["build", "--quiet", "--so"] :: (strict args from "build.rg") :: [entry_path, "-o", out_so]) [] -> verify artifact built at out_so

op :: extract quoted strings String at Int len Int in quote Bool cur String into [String] => [String]
      extract quoted strings s at pos len n in quote False cur _ into acc
        | pos >= n = acc
        | (str char at s pos) == 34 = extract quoted strings s at (pos + 1) len n in quote True cur "" into acc
        | otherwise = extract quoted strings s at (pos + 1) len n in quote False cur "" into acc
      extract quoted strings s at pos len n in quote True cur buf into acc
        | pos >= n = acc :: [buf]
        | ((str char at s pos) == 92) and ((pos + 1) < n) =
          esc_ch = str slice s (pos + 1) (pos + 2)
      extract quoted strings s at (pos + 2) len n in quote True cur (buf + esc_ch) into acc
        | (str char at s pos) == 34 =
      extract quoted strings s at (pos + 1) len n in quote False cur "" into (acc :: [buf])
        | otherwise =
          ch = str slice s pos (pos + 1)
          extract quoted strings s at (pos + 1) len n in quote True cur (buf + ch) into acc

op :: quoted strings in String => [String]
      quoted strings in s      =  extract quoted strings s at 0 len (str len s) in quote False cur "" into []

op :: is declaration header line String => Bool
      is declaration header line l      =
        (str starts with l "--") or (str starts with l "fn ") or (str starts with l "fn::") or (str starts with l "op ") or (str starts with l "op::") or (str starts with l "type ") or (str starts with l "expand ") or (str starts with l "opaque ") or (str starts with l "import ") or (str starts with l "|")

op :: parse clause key and rhs String => String String
      parse clause key and rhs line
        | is declaration header line line = ("", "")
        | otherwise = split clause at equals line idx (str index of line "=")

op :: split clause at equals String idx Int    => String String
      split clause at equals line   idx eq_idx
        | eq_idx <= 0 = ("", "")
        | otherwise =
          lhs_words = split words of (str slice line 0 eq_idx)
          lhs_key = str join lhs_words "_"
          rhs_txt = str trim (str slice line (eq_idx + 1) (str len line))
          (lhs_key, rhs_txt)

op :: first string or default [String] default String      => String
      first string or default []       default default_val =  default_val
      first string or default (s:_)    default _           =  s

op :: extract function body from [String] named String default String => String
      extract function body from [] named _ default default_val = default_val
      extract function body from (l:ls) named target default default_val =
        pair = parse clause key and rhs l
        match function clause pair rest ls named target default default_val

op :: match function clause (String, String) rest [String] named String default String => String
      match function clause (k, rhs) rest ls named target default default_val
        | (k == target) and (str starts with rhs "\"") =
          first string or default (quoted strings in rhs) default default_val
        | otherwise = extract function body from ls named target default default_val

op :: extract bool body from [String] named String default Bool        => Bool
      extract bool body from []       named _      default default_val =  default_val
      extract bool body from (l:ls)   named target default default_val =
        pair = parse clause key and rhs l
        match bool clause pair rest ls named target default default_val

op :: match bool clause (String, String) rest [String] named String default Bool => Bool
      match bool clause (k, rhs) rest _ named target default _
        | (k == target) and ((rhs == "True") or (rhs == "\"true\"")) = True
        | (k == target) and ((rhs == "False") or (rhs == "\"false\"")) = False
      match bool clause _ rest ls named target default default_val =
        extract bool body from ls named target default default_val

op :: strict flag for Bool  => String
      strict flag for True  =  "--strict "
      strict flag for False =  ""

op :: load strict flag from String     => String
      load strict flag from build_path
        | not (file build_path exists) = ""
        | otherwise =
          lines = split lines of (read file build_path)
          strict flag for (extract bool body from lines named "strict_mode" default False)

op :: load build config from String     => StableConfig
      load build config from build_path
        | not (file build_path exists) = ProjectConfig "" "0.1.0" "" "src/main/ridgun" "src/test/ridgun" "target"
        | otherwise = parse build config source (read file build_path)

op :: parse build config source String => StableConfig
      parse build config source src    =
        cwd = sys getcwd
        def_name = base filename of cwd at 0 len (str len cwd) slash (0 - 1)
        lines = split lines of src
        name_str = extract function body from lines named "project_name" default def_name
        ver = extract function body from lines named "project_version" default "0.1.0"
        main_ep = extract function body from lines named "main_entry" default ("src/main/ridgun/" + name_str + "/main.rg")
        sdir = extract function body from lines named "source_dir" default "src/main/ridgun"
        tdir = extract function body from lines named "test_dir" default "src/test/ridgun"
        out_dir = extract function body from lines named "target_dir" default "target"
        ProjectConfig name_str ver main_ep sdir tdir out_dir

op :: project name of StableConfig => String
      project name of (ProjectConfig name_str _ _ _ _ _) = name_str

op :: no project loaded error => Int
      no project loaded error =
        log error "No project found in current directory (missing build.rg). Run 'stable init' or 'stable new <name>'."
        1

-- ── Task 1: `check` (Typecheck & Static Analysis of Project) ─

fn :: check single module String => Int Int
      check single module path   =
        rg_bin = resolve ridgunc binary
        st = sys exec rg_bin (["check", "--quiet"] :: (strict args from "build.rg") :: [path]) []
        report check module path status st

op :: report check module String status Int => Int Int
      report check module path   status 0   =
        log ok "{path}"
        (1, 0)
      report check module path   status _   =
        log err "{path}: error(s)"
        (0, 1)

op :: sum check results [(Int, Int)] ok Int  err Int   => Int Int
      sum check results []           ok ok_c err err_c =  (ok_c, err_c)
      sum check results ((o, e):rem_results) ok ok_c err err_c =
        sum check results rem_results ok (ok_c + o) err (err_c + e)

op :: check modules [String] ok Int  err Int   => Int Int
      check modules files    ok ok_c err err_c =
        files map (check single module) -> sum check results ok ok_c err err_c

op :: run task check on StableConfig => Int
      run task check on (ProjectConfig "" _ _ _ _ _) =
        no project loaded error
      run task check on (ProjectConfig name_str ver _ sdir _ _) =
        files = list rg files in sdir
        log info "Checking project '{name_str}' v{ver} in {sdir}/ ..."
        finish task check with (check modules files ok 0 err 0)

op :: finish task check with (Int, Int)    => Int
      finish task check with (ok_c, 0)     =
        log success "Checked {ok_c} module(s) — 0 errors."
        0
      finish task check with (ok_c, err_c) =
        log error "Checked {ok_c} module(s) — {err_c} error(s) found."
        1

-- ── Task 2: `compile` (Emit .rgc Bytecode Artifacts) ─────────

op :: rgc artifact name for String base String    => String
      rgc artifact name for path   base "main.rg" =  (target name from entry path) + "_main.rgc"
      rgc artifact name for _      base bname     =  bname + "c"

op :: pair paths [String]         with dir String  => [(String, String)]
      pair paths []               with dir _       =  []
      pair paths (path:rem_files) with dir out_dir =
        [(out_dir, path)] :: (pair paths rem_files with dir out_dir)

fn :: compile single module (String, String) => Int
      compile single module (out_dir, path)  =
        bname = base filename of path at 0 len (str len path) slash (0 - 1)
        out_rgc = out_dir + "/" + (rgc artifact name for path base bname)
        rg_bin = resolve ridgunc binary
        sys exec rg_bin (["compile"] :: (strict args from "build.rg") :: [path, "-o", out_rgc]) [] -> ()
        log step "rgc" "{path} -> {out_rgc}"
        1

op :: sum ints [Int]     acc Int   => Int
      sum ints []        acc total =  total
      sum ints (n:rem_n) acc total =  sum ints rem_n acc (total + n)

op :: compile modules [String] into String  count Int   => Int
      compile modules files    into out_dir count c_acc =
        pair paths files with dir out_dir -> map (compile single module) -> sum ints acc c_acc

op :: run task compile on StableConfig => Int
      run task compile on (ProjectConfig name_str ver main_ep sdir tdir out_dir) =
        chk = run task check on (ProjectConfig name_str ver main_ep sdir tdir out_dir)
        compile if check status chk from sdir into out_dir

op :: compile if check status Int  from String into String  => Int
      compile if check status 0    from sdir   into out_dir =
        ensure folder out_dir
        files = list rg files in sdir
        c_count = compile modules files into out_dir count 0
        log success "Compiled {c_count} bytecode artifact(s) into {out_dir}/."
        0
      compile if check status code from _      into _       =  code

-- ── Task 3: `build` / `built` (Executables & Reusable Libraries) ─

op :: load project kind from String     => String
      load project kind from build_path
        | not (file build_path exists) = "bin"
        | otherwise =
          lines = split lines of (read file build_path)
          extract function body from lines named "project_kind" default "bin"

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
        ensure folder out_dir
        out_rglib = out_dir + "/" + lib_name + ".rglib"
        out_so = out_dir + "/lib" + lib_name + ".so"
        log info "Building Ridgun library '{lib_name}' from {entry_path} (v{ver}) ..."
        st1 = invoke ridgunc rglib entry_path into out_rglib
        st2 = invoke ridgunc so entry_path into out_so
        report library build of out_rglib so out_so status1 st1 status2 st2

op :: report library build of String    so String status1 Int status2 Int => Int
      report library build of out_rglib so out_so status1 0   status2 0   =
        log success "Built Ridgun library bundle: {out_rglib}"
        log success "Built native ELF64 shared object: {out_so}"
        0
      report library build of out_rglib so out_so status1 st1 status2 st2 =
        log error "Library build failed for {out_rglib} / {out_so} (status {st1}, {st2})"
        1

op :: run task build lib on StableConfig args [String]  => Int
      run task build lib on (ProjectConfig "" _ _ _ _ _) args _ =
        no project loaded error
      run task build lib on (ProjectConfig name_str ver main_ep sdir _ out_dir) args [] =
        lib_ep = resolve lib entry for name_str in sdir default main_ep
        build library artifacts from lib_ep into out_dir named name_str version ver
      run task build lib on (ProjectConfig _ ver main_ep sdir _ out_dir) args (tname:_) =
        lib_ep = resolve lib entry for tname in sdir default main_ep
        build library artifacts from lib_ep into out_dir named tname version ver

op :: build target from String     into String  version String => Int
      build target from entry_path into out_bin version ver
        | not (file entry_path exists) =
          log error "Entry point not found: {entry_path}"
          1
        | otherwise =
          log info "Building native executable '{out_bin}' from {entry_path} (v{ver}) ..."
          st_code = invoke ridgunc build entry_path into out_bin
          report build of out_bin status st_code

op :: pair entries [String] with dir String version String => [(String, String, String)]
      pair entries [] with dir _ version _ = []
      pair entries (epath:rem_paths) with dir out_dir version ver =
        [(out_dir, ver, epath)] :: (pair entries rem_paths with dir out_dir version ver)

fn :: build single entry (String, String, String) => Int
      build single entry (out_dir, ver, epath)    =
        tname = target name from entry epath
        out_bin = out_dir + "/" + tname + host exe ext
        build target from epath into out_bin version ver

op :: build entry list [String] into String version String errors Int => Int
      build entry list entries into out_dir version ver errors err_acc =
        pair entries entries with dir out_dir version ver -> map (build single entry) -> sum ints acc err_acc

op :: target binary ext for String           => String
      target binary ext for "x86_64-windows" =  ".exe"
      target binary ext for "windows-x86_64" =  ".exe"
      target binary ext for "windows"        =  ".exe"
      target binary ext for "win64"          =  ".exe"
      target binary ext for "pe64"           =  ".exe"
      target binary ext for "arm64-windows"  =  ".exe"
      target binary ext for "windows-arm64"  =  ".exe"
      target binary ext for "aarch64-windows" = ".exe"
      target binary ext for _                =  ""

op :: build target from String     into String  for String      version String => Int
      build target from entry_path into out_bin for target_arch version ver
        | not (file entry_path exists) =
          log error "Entry point not found: {entry_path}"
          1
        | otherwise =
          log info "Building native executable '{out_bin}' ({target_arch}) from {entry_path} (v{ver}) ..."
          st_code = invoke ridgunc build target entry_path into out_bin for target_arch
          report build of out_bin status st_code

op :: pair entries [String] with dir String target String version String => [(String, String, String, String)]
      pair entries [] with dir _ target _ version _ = []
      pair entries (epath:rem_paths) with dir out_dir target target_arch version ver =
        [(out_dir, target_arch, ver, epath)] :: (pair entries rem_paths with dir out_dir target target_arch version ver)

fn :: build single target entry (String, String, String, String) => Int
      build single target entry (out_dir, target_arch, ver, epath) =
        tname = target name from entry epath
        ext = target binary ext for target_arch
        out_bin = out_dir + "/" + tname + ext
        build target from epath into out_bin for target_arch version ver

op :: build entry list [String] into String for String version String errors Int => Int
      build entry list entries into out_dir for target_arch version ver errors err_acc =
        pair entries entries with dir out_dir target target_arch version ver -> map (build single target entry) -> sum ints acc err_acc

op :: build discovered entries [String] name String version String entry String into String for String => Int
      build discovered entries [] name name_str version ver entry main_ep into out_dir for target_arch =
        ext = target binary ext for target_arch
        build target from main_ep into (out_dir + "/" + name_str + ext) for target_arch version ver
      build discovered entries entries name _ version ver entry _ into out_dir for target_arch =
        build entry list entries into out_dir for target_arch version ver errors 0

op :: build for target list [String] on StableConfig errors Int => Int
      build for target list [] on _ errors err_acc = err_acc
      build for target list (t_arch:rem_archs) on (ProjectConfig name_str ver main_ep sdir tdir out_dir) errors err_acc =
        sub_out = out_dir + "/dist/" + t_arch
        ensure folder sub_out
        entries = list exec entries in sdir
        st = build discovered entries entries name name_str version ver entry main_ep into sub_out for t_arch
        build for target list rem_archs on (ProjectConfig name_str ver main_ep sdir tdir out_dir) errors (err_acc + st)

op :: run task build on StableConfig args [String]       => Int
      run task build on (ProjectConfig "" _ _ _ _ _) args _ =
        no project loaded error
      run task build on cfg          args ("lib":rest)   =
        run task build lib on cfg args rest
      run task build on cfg          args ("--lib":rest) =
        run task build lib on cfg args rest
      run task build on cfg          args ("all-targets":_) =
        build for target list ["x86_64-linux", "arm64-linux", "x86_64-macos", "arm64-macos", "x86_64-windows", "arm64-windows"] on cfg errors 0
      run task build on (ProjectConfig name_str ver main_ep sdir _ out_dir) args ("--target":target_arch:[]) =
        ensure folder out_dir
        entries = list exec entries in sdir
        build discovered entries entries name name_str version ver entry main_ep into out_dir for target_arch
      run task build on (ProjectConfig _ ver _ sdir _ out_dir) args ("--target":target_arch:tname:_) =
        ensure folder out_dir
        cand_entry = sdir + "/" + tname + "/main.rg"
        ext = target binary ext for target_arch
        out_bin = out_dir + "/" + tname + ext
        build target from cand_entry into out_bin for target_arch version ver
      run task build on (ProjectConfig _ ver _ sdir _ out_dir) args (tname:"--target":target_arch:_) =
        ensure folder out_dir
        cand_entry = sdir + "/" + tname + "/main.rg"
        ext = target binary ext for target_arch
        out_bin = out_dir + "/" + tname + ext
        build target from cand_entry into out_bin for target_arch version ver
      run task build on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args []
        | (load project kind from "build.rg") == "lib" =
          run task build lib on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args []
        | otherwise =
          ensure folder out_dir
          entries = list exec entries in sdir
          build discovered entries entries name name_str version ver entry main_ep into out_dir
      run task build on (ProjectConfig _ ver _ sdir _ out_dir) args (tname:_) =
        ensure folder out_dir
        cand_entry = sdir + "/" + tname + "/main.rg"
        out_bin = out_dir + "/" + tname + host exe ext
        build target from cand_entry into out_bin version ver

op :: build discovered entries [String] name String version String entry String into String => Int
      build discovered entries [] name name_str version ver entry main_ep into out_dir =
        build target from main_ep into (out_dir + "/" + name_str + host exe ext) version ver
      build discovered entries entries name _ version ver entry _ into out_dir =
        build entry list entries into out_dir version ver errors 0

op :: report build of String  status Int  => Int
      report build of out_bin status 0    =
        log success "Built native executable: {out_bin}"
        0
      report build of out_bin status code =
        log error "Build failed for {out_bin} (exit code {code})"
        code

-- ── Task 4: `run` (Build if Needed & Run Native Binary) ─────

op :: run task run on StableConfig args [String] => Int
      run task run on (ProjectConfig "" _ _ _ _ _) args _ =
        no project loaded error
      run task run on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args (first_arg:rest_args)
        | file (sdir + "/" + first_arg + "/main.rg") exists = run specific target first_arg from (sdir + "/" + first_arg + "/main.rg") version ver in out_dir args rest_args
        | otherwise = run default target for (ProjectConfig name_str ver main_ep sdir tdir out_dir) args ([first_arg] :: rest_args)
      run task run on cfg          args []       =
        run default target for cfg args []

op :: run specific target String from String version String in String args [String] => Int
      run specific target tname from entry_path version ver in out_dir args extra_args =
        out_bin = out_dir + "/" + tname + host exe ext
        ensure_st = ensure target built (binary is current out_bin) from entry_path into out_bin version ver
        exec binary if built ensure_st path out_bin args extra_args

op :: run default target for StableConfig args [String]   => Int
      run default target for (ProjectConfig name_str ver main_ep _ _ out_dir) args extra_args =
        out_bin = out_dir + "/" + name_str + host exe ext
        ensure_st = ensure target built (binary is current out_bin) from main_ep into out_bin version ver
        exec binary if built ensure_st path out_bin args extra_args

op :: ensure target built Bool from String into String version String => Int
      ensure target built True from _ into _ version _ = 0
      ensure target built False from entry_path into out_bin version ver =
        ensure folder (parent dir of out_bin at 0 len (str len out_bin) slash 0)
        st = build target from entry_path into out_bin version ver
        record source stamp st out_bin

-- `stable run` rebuilds unless the binary was built from exactly the current sources. The stamp next to the
-- binary (<binary>.stamp) is a hash of every .rg, .rglib and omni.lock in the project (target/ aside), with
-- their paths, and of the compiler's version. It compares contents, not file times, so a source rewritten in
-- the same second as the last build is still seen.
op :: source stamp => String
      source stamp =
        lines = stamp files in "." top True -> map (f => (sha256 file f) + "  " + f + "\n")
        rg_bin = resolve ridgunc binary
        sha256 str ((str join lines "") + (compiler stamp of rg_bin))

op :: compiler stamp of String => String
      compiler stamp of rg_bin
        | file rg_bin exists = sha256 file rg_bin
        | otherwise = rg_bin

-- The sources a build reads, folder by folder in name order; ./target and ./.git are left out.
op :: stamp files in String top Bool => [String]
      stamp files in dir top at_top =  stamp entries (list str sort (list dir dir)) in dir top at_top

op :: stamp entries [String] in String top Bool => [String]
      stamp entries []     in _   top _      =  []
      stamp entries (e:es) in dir top at_top =
        full = dir + "/" + e
        rest = stamp entries es in dir top at_top
        stamp entry full name e top at_top then rest

op :: stamp entry String name String top Bool then [String] => [String]
      stamp entry full name e top at_top then rest
        | at_top and (e == "target" or e == ".git") = rest
        | is dir full = (stamp files in full top False) :: rest
        | (is file full) and ((str ends with e ".rg") or (str ends with e ".rglib") or e == "omni.lock") = [full] :: rest
        | otherwise = rest

op :: binary is current String => Bool
      binary is current out_bin
        | not (file out_bin exists) = False
        | not (file (out_bin + ".stamp") exists) = False
        | otherwise = (source stamp) == (read file (out_bin + ".stamp"))

op :: record source stamp Int String => Int
      record source stamp 0 out_bin =
        write file (out_bin + ".stamp") (source stamp)
        0
      record source stamp st out_bin =
        discard file (out_bin + ".stamp")
        st

op :: exec binary if built Int  path String  args [String]   => Int
      exec binary if built 0    path out_bin args extra_args =
        arg_str = join words extra_args with spaces
        log info "Running {out_bin} {arg_str}"
        sys exec out_bin extra_args []
      exec binary if built code path _       args _          =  code

-- ── Task 5: `test` (Discover, Check, Build & Run Tests) ─────

fn :: run single test suite String => Int Int
      run single test suite tpath  =
        log info "Compiling & running test suite: {tpath}"
        bname = base filename of tpath at 0 len (str len tpath) slash (0 - 1)
        bin_path = "target/.stable_test_" + bname + "_bin" + host exe ext
        st_code = invoke ridgunc build tpath into bin_path
        run built test binary st_code suite tpath binary bin_path

op :: run built test binary Int suite String binary String   => Int Int
      run built test binary 0   suite tpath  binary bin_path =
        run_st = sys exec bin_path [] []
        discard file bin_path
        record single test outcome run_st suite tpath
      run built test binary _   suite tpath  binary _        =
        log fail "{tpath} (compilation/typecheck failed)"
        (0, 1)

op :: record single test outcome Int suite String => Int Int
      record single test outcome 0   suite tpath  =
        log pass "{tpath}"
        (1, 0)
      record single test outcome _   suite tpath  =
        log fail "{tpath} (non-zero exit status)"
        (0, 1)

op :: execute test suites [String] passed Int    failed Int    => Int Int
      execute test suites suites   passed pass_c failed fail_c =
        ensure folder "target"
        suites map (run single test suite) -> sum check results ok pass_c err fail_c

op :: run task test on StableConfig => Int
      run task test on (ProjectConfig "" _ _ _ _ _) =
        no project loaded error
      run task test on (ProjectConfig name_str _ _ _ tdir _) =
        suites = list test files in tdir
        log info "Running test suites for '{name_str}' in {tdir}/ ..."
        finish task test with (execute test suites suites passed 0 failed 0)

op :: finish task test with (Int, Int)       => Int
      finish task test with (pass_c, 0)      =
        log success "Passed {pass_c}/{pass_c} test suite(s) — 0 failures."
        0
      finish task test with (pass_c, fail_c) =
        total = pass_c + fail_c
        log error "Passed {pass_c}/{total} test suite(s) — {fail_c} failed."
        1

-- ── Task 6: `format` (Canonical Aesthetic Formatting) ───────

op :: read raw file at String => String
      read raw file at path   =  read file path

op :: report unchanged file String => Int
      report unchanged file path   =
        log ok "{path} (already formatted)"
        0

op :: save formatted file String content String    => Int
      save formatted file path   content formatted =
        write file path formatted
        log step "fmt" "{path} (formatted)"
        1

op :: apply formatted content String orig String formatted String        => Int
      apply formatted content path   orig raw    formatted formatted_src
        | raw == formatted_src = report unchanged file path
        | otherwise = save formatted file path content formatted_src

op :: format file at String => Int
      format file at path   =
        raw = read raw file at path
        raw -> format ridgun source -> apply formatted content path orig raw formatted _

fn :: format single file String => Int
      format single file path   =  format file at path

op :: format file list [String] changed Int   total Int   => Int Int
      format file list paths    changed chg_c total tot_c =
        paths map (format single file) -> deltas
        (sum ints deltas acc chg_c, tot_c + (list str len paths))

op :: include build file if present => [String]
      include build file if present
        | file "build.rg" exists = ["build.rg"]
        | otherwise = []

op :: finish task format with (Int, Int)     => Int
      finish task format with (chg_c, tot_c) =
        log success "Formatted {chg_c}/{tot_c} file(s) using canonical Ridgun style."
        0

op :: run task format on StableConfig args [String]     => Int
      run task format on (ProjectConfig "" _ _ _ _ _) args [] =
        no project loaded error
      run task format on (ProjectConfig name_str _ _ sdir tdir _) args [] =
        b_files = include build file if present
        s_files = list rg files in sdir
        t_files = list rg files in tdir
        all_files = b_files :: s_files :: t_files
        log info "Formatting project '{name_str}' source files ..."
        finish task format with (format file list all_files changed 0 total 0)
      run task format on _            args target_paths =
        log info "Formatting specified Ridgun file(s) ..."
        finish task format with (format file list target_paths changed 0 total 0)

-- ── Task 7: `clean` & `info` & `help` ───────────────────────

op :: is build leftover String => Bool
      is build leftover e =
        (str ends with e ".rgc") or (str ends with e ".rglib") or (str ends with e ".so") or (str starts with e ".stable_") or (str starts with e ".ridgunc_")

op :: remove leftovers [String] in String => ()
      remove leftovers []     in _   =  ()
      remove leftovers (e:es) in dir
        | (is build leftover e) and (is file (dir + "/" + e)) =
          discard file (dir + "/" + e)
          remove leftovers es in dir
        | otherwise = remove leftovers es in dir

op :: run task clean on StableConfig => Int
      run task clean on (ProjectConfig "" _ _ _ _ _) =
        no project loaded error
      run task clean on (ProjectConfig _ _ _ _ _ out_dir) =
        remove leftovers (list dir out_dir) in out_dir
        log success "Cleaned bytecode and library artifacts in {out_dir}/."
        0

op :: collect target names of [String]     => [String]
      collect target names of []           =  []
      collect target names of (ep:rem_eps) =  [target name from entry ep] :: (collect target names of rem_eps)

op :: run task info on StableConfig => Int
      run task info on (ProjectConfig "" _ _ _ _ _) =
        no project loaded error
      run task info on (ProjectConfig name_str ver main_ep sdir tdir out_dir) =
        pkind = load project kind from "build.rg"
        src_files = list rg files in sdir
        exec_entries = list exec entries in sdir
        exec_names = join words (collect target names of exec_entries) with spaces
        tst_files = list test files in tdir
        src_c = list str len src_files
        tst_c = list str len tst_files
        log section "Project Info (build.rg)"
        echo "  Project Name : {name_str}"
        echo "  Project Kind : {pkind}"
        echo "  Version      : {ver}"
        echo "  Main Entry   : {main_ep}"
        echo "  Executables  : {exec_names}"
        echo "  Shared Lib   : {sdir}/lib/"
        echo "  Source Dir   : {sdir}/ ({src_c} modules)"
        echo "  Test Dir     : {tdir}/ ({tst_c} test suites)"
        echo "  Target Dir   : {out_dir}/"
        0

-- ── Task 8: `new`, `init`, `deps`, `add`, and `install` (`FR-TOOL-002`) ──

op :: extract list function body from [String] named String => [String]
      extract list function body from []       named _      =  []
      extract list function body from (l:ls)   named target =
        pair = parse clause key and rhs l
        match list function clause pair rest ls named target

op :: match list function clause (String, String) rest [String] named String => [String]
      match list function clause (k, rhs) rest ls named target
        | (k == target) and (str starts with rhs "[") = quoted strings in rhs
        | (k == target) and (str starts with rhs "\"") =
          split words of (first string or default (quoted strings in rhs) default "")
        | otherwise = extract list function body from ls named target

op :: load dependencies from String     => [String]
      load dependencies from build_path
        | not (file build_path exists) = []
        | otherwise =
          lines = split lines of (read file build_path)
          extract list function body from lines named "dependencies"

op :: scaffold project named String in String => Int
      scaffold project named pname  in root   =
        ensure folder (root + "/src/main/ridgun/" + pname)
        ensure folder (root + "/src/main/ridgun/lib")
        ensure folder (root + "/src/test/ridgun")
        ensure folder (root + "/target")
        build_content = "-- build.rg — Ridgun Project Build Definition\n\nfn :: project name => String\n      project name =  \"" + pname + "\"\n\nfn :: project version => String\n      project version =  \"0.1.0\"\n\nfn :: main entry => String\n      main entry =  \"src/main/ridgun/" + pname + "/main.rg\"\n\nfn :: source dir => String\n      source dir =  \"src/main/ridgun\"\n\nfn :: test dir => String\n      test dir =  \"src/test/ridgun\"\n\nfn :: target dir => String\n      target dir =  \"target\"\n\nfn :: dependencies => [String]\n      dependencies =  []\n"
        main_content = "-- src/main/ridgun/" + pname + "/main.rg\n\nfn :: greet String => String\n      greet who    =  \"Hello from \" + who + \"!\"\n\nfn :: main => ()\n      main =  echo (greet \"" + pname + "\")\n"
        test_lib_content = "-- src/test/ridgun/test.rg — Standard Test Assertions (`import test`)\n\nfn :: fail test String => ()\n      fail test msg    =\n        echo \"[FAIL] \" msg\n        sys exit 1\n\nfn :: assert equals A      A        => ()\n      assert equals actual expected\n        | actual == expected = echo \"  [ok]  \" actual \"==\" expected\n        | otherwise = fail test \"assert equals failed\"\n\nfn :: assert true Bool => ()\n      assert true cond\n        | cond = echo \"  [ok]   True\"\n        | otherwise = fail test \"assert true failed\"\n"
        test_content = "-- src/test/ridgun/test main.rg\nimport test\n\nfn :: main => ()\n      main =\n        assert true True\n        echo \"=== All " + pname + " tests passed ===\"\n"
        gitignore_content = "/target/\n/.stable/\n"
        write file (root + "/build.rg") build_content
        write file (root + "/src/main/ridgun/" + pname + "/main.rg") main_content
        write file (root + "/src/test/ridgun/test.rg") test_lib_content
        write file (root + "/src/test/ridgun/test main.rg") test_content
        write file (root + "/.gitignore") gitignore_content
        log success "Scaffolded Ridgun project '{pname}' in {root}/"
        0

op :: scaffold lib project named String in String => Int
      scaffold lib project named pname  in root   =
        ensure folder (root + "/src/main/ridgun/lib")
        ensure folder (root + "/src/test/ridgun")
        ensure folder (root + "/target")
        build_content = "-- build.rg — Ridgun Library Project Definition\n\nfn :: project name => String\n      project name =  \"" + pname + "\"\n\nfn :: project kind => String\n      project kind =  \"lib\"\n\nfn :: project version => String\n      project version =  \"0.1.0\"\n\nfn :: main entry => String\n      main entry =  \"src/main/ridgun/lib/" + pname + ".rg\"\n\nfn :: source dir => String\n      source dir =  \"src/main/ridgun\"\n\nfn :: test dir => String\n      test dir =  \"src/test/ridgun\"\n\nfn :: target dir => String\n      target dir =  \"target\"\n\nfn :: dependencies => [String]\n      dependencies =  []\n"
        lib_content = "-- src/main/ridgun/lib/" + pname + ".rg\n\nfn :: greet String => String\n      greet who    =  \"Hello from library \" + who + \"!\"\n"
        test_lib_content = "-- src/test/ridgun/test.rg — Standard Test Assertions (`import test`)\n\nfn :: fail test String => ()\n      fail test msg    =\n        echo \"[FAIL] \" msg\n        sys exit 1\n\nfn :: assert equals A      A        => ()\n      assert equals actual expected\n        | actual == expected = echo \"  [ok]  \" actual \"==\" expected\n        | otherwise = fail test \"assert equals failed\"\n\nfn :: assert true Bool => ()\n      assert true cond\n        | cond = echo \"  [ok]   True\"\n        | otherwise = fail test \"assert true failed\"\n"
        test_content = "-- src/test/ridgun/test main.rg\nimport test\nimport " + pname + "\n\nfn :: main => ()\n      main =\n        assert equals (greet \"" + pname + "\") \"Hello from library " + pname + "!\"\n        echo \"=== All " + pname + " library tests passed ===\"\n"
        gitignore_content = "/target/\n/.stable/\n"
        write file (root + "/build.rg") build_content
        write file (root + "/src/main/ridgun/lib/" + pname + ".rg") lib_content
        write file (root + "/src/test/ridgun/test.rg") test_lib_content
        write file (root + "/src/test/ridgun/test main.rg") test_content
        write file (root + "/.gitignore") gitignore_content
        log success "Scaffolded Ridgun library project '{pname}' in {root}/"
        0

op :: run task new args [String]   => Int
      run task new args extra_args =
        pos_args = cli positionals extra_args
        is_lib = cli has flag extra_args "--lib" "-l"
        run task new target pos_args lib is_lib

op :: run task new target [String]  lib Bool   => Int
      run task new target []        lib _      =
        log error "Usage: stable new [--lib] <project_name>"
        1
      run task new target (pname:_) lib is_lib
        | file (pname + "/build.rg") exists =
          log error "Project '{pname}' already exists at {pname}/build.rg"
          1
        | is_lib = scaffold lib project named pname in pname
        | otherwise = scaffold project named pname in pname

op :: run task init args [String]   => Int
      run task init args extra_args
        | file "build.rg" exists =
          log info "build.rg already exists in current directory."
          0
        | otherwise =
          cwd = sys getcwd
          pname = base filename of cwd at 0 len (str len cwd) slash (0 - 1)
          init current dir named pname lib (cli has flag extra_args "--lib" "-l")

op :: init current dir named String lib Bool  => Int
      init current dir named pname  lib True  =  scaffold lib project named pname in "."
      init current dir named pname  lib False =  scaffold project named pname in "."

-- Dependencies (ADR-0003): build.rg lists package names (`json`, `solstice@0.1.0`); omni installs them and
-- records each one in the project's omni.lock as name|product|library|version|digest|artifact. stable never
-- downloads: it reads the artifact omni installed, an .rglib file or a package folder.
op :: is path or url String => Bool
      is path or url dep =  (str contains dep "/") or (str contains dep "\\") or (str contains dep ":") or (str starts with dep ".") or (str starts with dep "~")

op :: dep name of String => String
      dep name of dep
        | (str index of dep "@") < 0 = dep
        | otherwise = str slice dep 0 (str index of dep "@")

op :: dep version of String => String
      dep version of dep
        | (str index of dep "@") < 0 = ""
        | otherwise = str slice dep ((str index of dep "@") + 1) (str len dep)

op :: find locked String in [String] => [String]
      find locked _    in []     =  []
      find locked name in (e:es)
        | (list str nth or (str split e "|") 0 "") == name = str split e "|"
        | otherwise = find locked name in es

op :: omni lock entries => [String]
      omni lock entries
        | not (file "omni.lock" exists) = []
        | otherwise = extract list function body from (split lines of (read file "omni.lock")) named "locked_packages"

op :: not installed String => Int
      not installed dep =
        log error "Dependency '{dep}' is not installed: run `omni install {dep}`."
        1

op :: sync locked dependency String String String [String] => Int
      sync locked dependency dep _    _    []    =  not installed dep
      sync locked dependency dep name want entry
        | (list str nth or entry 3 "") == "local" =
          log error "Dependency '{name}' is a local path in omni.lock; install it from ridgun.com: `omni install {dep}`."
          1
        | (want != "") and (want != (list str nth or entry 3 "")) = version mismatch dep name (list str nth or entry 3 "")
        | str ends with (list str nth or entry 5 "") ".rglib" = sync locked library dep name (list str nth or entry 5 "")
        | otherwise = sync locked package dep name (list str nth or entry 5 "")

op :: version mismatch String String String => Int
      version mismatch dep name locked =
        log error "build.rg asks for {dep}, omni.lock has {name} {locked}: run `omni install {dep}`."
        1

op :: sync locked library String String String => Int
      sync locked library dep name art
        | file art exists =
          log step "dep" "{name} -> {art}"
          0
        | otherwise = not installed dep

op :: sync locked package String String String => Int
      sync locked package dep name dir
        | not (is dir dir) = not installed dep
        | otherwise =
          dest = ".stable/deps/" + name
          ensure folder ".stable/deps"
          remove tree dest
          copy tree dir to dest skipping [".stable", "target"]
          finish sync single dependency dir name dest (copied status of dest)

op :: copied status of String => Int
      copied status of dest
        | is dir dest = 0
        | otherwise = 1

-- The .rglib files of the first of these folders that has any go to .stable/deps: the one named after the
-- dependency always, the others only when no folder of that name is there.
op :: first bundle folder [String] => String
      first bundle folder []     =  ""
      first bundle folder (d:ds)
        | (rglib names in d) != [] = d
        | otherwise = first bundle folder ds

op :: rglib names in String => [String]
      rglib names in d
        | not (is dir d) = []
        | otherwise = list str sort (list dir d) -> filter (e => (str ends with e ".rglib") and (is file (d + "/" + e)))

op :: copy bundles String named String => ()
      copy bundles ""  named _     =  ()
      copy bundles dir named bname =  copy bundle list (rglib names in dir) from dir named bname

op :: copy bundle list [String] from String named String => ()
      copy bundle list []     from _   named _     =  ()
      copy bundle list (f:fs) from dir named bname
        | (rglib base of f) == bname or (not (is dir (".stable/deps/" + (rglib base of f)))) =
          copy file (dir + "/" + f) to (".stable/deps/" + f)
          copy bundle list fs from dir named bname
        | otherwise = copy bundle list fs from dir named bname

op :: rglib base of String => String
      rglib base of f =  str slice f 0 ((str len f) - 6)

-- A dependency stays under .stable/deps: ridgunc reads .stable/deps/<name>/src/main/ridgun/lib/<module>.rg,
-- so nothing is copied into the project's own sources (FR-TOOL-002 AC7).
op :: finish sync single dependency String String String Int => Int
      finish sync single dependency dep bname dest 0 =
        copy bundles (first bundle folder [dep + "/target/bundles", dep + "/target", dest + "/target/bundles", dest + "/target", dest]) named bname
        log step "dep" "{dep} -> {dest}"
        0
      finish sync single dependency dep _ _ st =
        log error "Failed to synchronize dependency: {dep}"
        st

-- Developer links (ADR-0005): a developer may build against a local checkout of a package instead of the
-- copy omni installed. Links live in ~/.stable/dev-links, outside every project, so no repository or package can
-- bring or turn one on, and there are none by default. build.rg and omni.lock still hold only names. A link is
-- checked when it is made and every time it is used, and every use prints a warning.
op :: dev links file => String
      dev links file =  (env get or "HOME" "") + "/.stable/dev-links"

op :: dev link entries => [String]
      dev link entries
        | (env get or "HOME" "") == "" = []
        | not (file (dev links file) exists) = []
        | otherwise = dev link lines (split lines of (read file (dev links file)))

op :: dev link lines [String] => [String]
      dev link lines []     =  []
      dev link lines (l:ls)
        | str contains l "|" = [str trim l] :: (dev link lines ls)
        | otherwise = dev link lines ls

op :: dev link name of String => String
      dev link name of entry =  list str nth or (str split entry "|") 0 ""

op :: dev link dir of String => String
      dev link dir of entry =  list str nth or (str split entry "|") 1 ""

op :: find dev link String in [String] => String
      find dev link _    in []     =  ""
      find dev link name in (e:es)
        | (dev link name of e) == name = dev link dir of e
        | otherwise = find dev link name in es

op :: without dev link String in [String] => [String]
      without dev link _    in []     =  []
      without dev link name in (e:es)
        | (dev link name of e) == name = without dev link name in es
        | otherwise = [e] :: (without dev link name in es)

-- Characters a link may not hold: they would let a folder name run shell code when the package is copied.
op :: has unsafe char String => Bool
      has unsafe char s =  (str contains s "\"") or (str contains s "$") or (str contains s "`") or (str contains s "\\") or (str contains s "|") or (str contains s "\n") or (str contains s "'")

-- "" when name -> dir is a valid developer link, else the reason it is not.
op :: dev link problem String String => String
      dev link problem name dir
        | (name == "") or (is path or url name) or (has unsafe char name) or (str contains name "@") = "'" + name + "' is not a package name"
        | has unsafe char dir = "the folder path holds a character that is not allowed (\" $ ` \\ | ' or a newline)"
        | not (str starts with dir "/") = "the folder must be an absolute path"
        | not (file (dir + "/build.rg") exists) = dir + " has no build.rg"
        | (linked project name dir) != name = dir + "/build.rg names the project '" + (linked project name dir) + "', not '" + name + "'"
        | otherwise = ""

op :: linked project name String => String
      linked project name dir =  extract function body from (split lines of (read file (dir + "/build.rg"))) named "project_name" default ""

op :: absolute dir String => String
      absolute dir dir
        | str starts with dir "/" = dir
        | dir == "." = sys getcwd
        | str starts with dir "./" = (sys getcwd) + "/" + (str slice dir 2 (str len dir))
        | otherwise = (sys getcwd) + "/" + dir

op :: write dev links [String] => ()
      write dev links entries =
        ensure folder ((env get or "HOME" "") + "/.stable")
        write file (dev links file) (dev links text entries) -> ()

op :: dev links text [String] => String
      dev links text []     =  ""
      dev links text (e:es) =  e + "\n" + (dev links text es)

op :: run task dev args [String] => Int
      run task dev args ("link":name:dir:[]) =  make dev link name (absolute dir dir) (dev link problem name (absolute dir dir))
      run task dev args ("unlink":name:[])   =  remove dev link name (find dev link name in (dev link entries))
      run task dev args ("links":[])         =  list dev links (dev link entries)
      run task dev args _                    =
        log error "Usage: stable dev link <package> <folder> | stable dev unlink <package> | stable dev links"
        1

op :: make dev link String String String => Int
      make dev link name dir "" =
        write dev links ((without dev link name in (dev link entries)) :: [name + "|" + dir])
        log warn ("Developer link: every project that depends on '" + name + "' now builds it from " + dir + ", not from the package omni installed. Remove it with `stable dev unlink " + name + "`.")
        0
      make dev link name dir problem =
        log error ("Cannot link '" + name + "': " + problem + ".")
        1

op :: remove dev link String String => Int
      remove dev link name "" =
        log error ("There is no developer link for '" + name + "'.")
        1
      remove dev link name _  =
        write dev links (without dev link name in (dev link entries))
        log success ("Removed the developer link for '" + name + "'; `stable deps` uses the package omni installed again.")
        0

op :: list dev links [String] => Int
      list dev links [] =
        log info "No developer links."
        0
      list dev links es =
        log warn ("Developer links in " + (dev links file) + ":")
        print dev links es
        0

op :: print dev links [String] => ()
      print dev links []     =  ()
      print dev links (e:es) =
        echo ("  " + (dev link name of e) + " -> " + (dev link dir of e))
        print dev links es

op :: sync single dependency String => Int
      sync single dependency dep
        | is path or url dep =
          log error "Dependency '{dep}' is a path or URL: build.rg lists package names, installed with omni (`omni install <name>`). To build against a local checkout on your machine, use `stable dev link <name> <folder>`."
          1
        | otherwise = sync named dependency dep (find dev link (dep name of dep) in (dev link entries))

op :: sync named dependency String String => Int
      sync named dependency dep "" =  sync locked dependency dep (dep name of dep) (dep version of dep) (find locked (dep name of dep) in (omni lock entries))
      sync named dependency dep dir =  sync dev linked dep (dep name of dep) dir (dev link problem (dep name of dep) dir)

op :: sync dev linked String String String String => Int
      sync dev linked dep name dir "" =
        log warn ("Developer link: '" + name + "' comes from " + dir + ", not from omni. `stable dev unlink " + name + "` goes back to the installed package.")
        sync locked package dep name dir
      sync dev linked _ name dir problem =
        log error ("The developer link '" + name + "' -> " + dir + " is not valid: " + problem + ". Fix it or remove it with `stable dev unlink " + name + "`.")
        1

op :: sync dependency rest [String] Int => Int
      sync dependency rest ds 0  = sync dependency list ds
      sync dependency rest _  st = st

op :: sync dependency list [String] => Int
      sync dependency list []       =
        log ok "No external dependencies declared in build.rg."
        0
      sync dependency list (d:[])   =
        sync single dependency d
      sync dependency list (d:ds)   =
        st = sync single dependency d
        sync dependency rest ds st

op :: finish task deps Int => Int
      finish task deps 0 =
        log success "Dependencies synchronized."
        0
      finish task deps st =
        st

op :: run task deps => Int
      run task deps =
        deps = load dependencies from "build.rg"
        log info "Synchronizing dependencies from build.rg into .stable/deps/ ..."
        st = sync dependency list deps
        finish task deps st

op :: format dep items [String] => String
      format dep items []       =  ""
      format dep items (d:[])   =  '"' + d + '"'
      format dep items (d:ds)   =  '"' + d + '", ' + (format dep items ds)

op :: replace dep line [String] with String => [String]
      replace dep line []     with _    =  []
      replace dep line (l:ls) with line
        | str starts with (str trim l) "dependencies =" = [line] :: (replace dep line ls with line)
        | otherwise = [l] :: (replace dep line ls with line)

op :: write dependencies [String] => ()
      write dependencies deps
        | not (file "build.rg" exists) = write file "build.rg" ('fn :: dependencies => [String]\n      dependencies =  [' + (format dep items deps) + ']\n') -> ()
        | str contains (read file "build.rg") "fn :: dependencies" =
          write file "build.rg" (str join (replace dep line (str split (read file "build.rg") "\n") with ('      dependencies =  [' + (format dep items deps) + ']')) "\n") -> ()
        | otherwise = write file "build.rg" ((read file "build.rg") + '\nfn :: dependencies => [String]\n      dependencies =  [' + (format dep items deps) + ']\n') -> ()

op :: add dep unique [String] String => [String]
      add dep unique deps new_dep
        | list str contains deps new_dep = deps
        | otherwise = deps :: [new_dep]


-- build.rg gets the name only once it is synchronized, so a failed `stable add` leaves build.rg as it was.
op :: finish task add String Int => Int
      finish task add new_dep 0 =
        write dependencies (add dep unique (load dependencies from "build.rg") new_dep)
        log success "Added dependency '{new_dep}'."
        0
      finish task add _ st =  st

op :: run task add args [String]    => Int
      run task add args []          =
        log error "Usage: stable add <package>[@<version>]"
        1
      run task add args (new_dep:_) =  finish task add new_dep (sync single dependency new_dep)

op :: install built binaries Int from String  => Int
      install built binaries 0   from out_dir =
        home = env get or "HOME" "."
        inst_dir = home + "/.local/bin"
        ensure folder inst_dir
        ensure folder "bin"
        install files (list str sort (list dir out_dir)) from out_dir into inst_dir
        log success "Installed executable(s) from {out_dir}/ into {inst_dir}/ and bin/."
        0
      install built binaries st  from _       =  st

-- Every executable file of the output folder goes to bin/, and to ~/.local/bin unless a link is there.
op :: install files [String] from String into String => ()
      install files []     from _       into _        =  ()
      install files (f:fs) from out_dir into inst_dir
        | is installable (out_dir + "/" + f) =
          discard file ("bin/" + f)
          copy file (out_dir + "/" + f) to ("bin/" + f)
          install copy (out_dir + "/" + f) to (inst_dir + "/" + f)
          install files fs from out_dir into inst_dir
        | otherwise = install files fs from out_dir into inst_dir

op :: is installable String => Bool
      is installable path =  (is file path) and (((file mode path) / 64) % 2 == 1)

op :: install copy String to String => ()
      install copy src to dst
        | is symlink dst = ()
        | otherwise =
          discard file dst
          copy file src to dst

op :: run task install on StableConfig args [String] => Int
      run task install on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args extra =
        build_st = run task build on (ProjectConfig name_str ver main_ep sdir tdir out_dir) args extra
        install built binaries build_st from out_dir

-- ── Task 9: Custom Tasks, Plugins, and Framework Extensions (`FR-TOOL-003`) ──

op :: task display name of String   => String
      task display name of raw_name =
        str replace raw_name "_" " "

op :: extract tasks from lines [String] origin String     => [StableTask]
      extract tasks from lines []       origin _          =  []
      extract tasks from lines (l:ls)   origin orig_label =
        pair = parse clause key and rhs l
        match task clause pair rest ls origin orig_label

op :: match task clause (String, String) rest [String] origin String => [StableTask]
      match task clause (k, rhs) rest ls origin orig_label
        | (str starts with k "task_") and ((str len k) > 5) and (str starts with rhs "\"") =
          raw_key = str slice k 5 (str len k)
          disp = task display name of raw_key
          cmd = first string or default (quoted strings in rhs) default ""
          [TaskEntry raw_key disp cmd orig_label] :: (extract tasks from lines ls origin orig_label)
        | otherwise = extract tasks from lines ls origin orig_label

op :: load tasks from file String origin String => [StableTask]
      load tasks from file path   origin orig
        | not (file path exists) = []
        | otherwise =
          lines = split lines of (read file path)
          extract tasks from lines lines origin orig

op :: load declared plugins from String     => [String]
      load declared plugins from build_path
        | not (file build_path exists) = []
        | otherwise =
          lines = split lines of (read file build_path)
          extract list function body from lines named "plugins"

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
        | list str contains acc path = acc
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

op :: match task entry StableTask against [String] => Bool Int String String [String]
      match task entry (TaskEntry key disp cmd _) against args_list =
        t_words = split words of disp
        t_len = list str len t_words
        match task words key disp cmd t_words t_len against args_list

op :: match task words String String String [String] Int against [String] => Bool Int String String [String]
      match task words _ _ _ _ _ against [] = (False, 0, "", "", [])
      match task words key disp cmd t_words t_len against (first_w:rest_w)
        | first_w == key = (True, 1, disp, cmd, rest_w)
        | words ([first_w] :: rest_w) start with t_words = (True, t_len, disp, cmd, list str drop ([first_w] :: rest_w) t_len)
        | otherwise = (False, 0, "", "", [])

op :: pick longer task match (Bool, Int, String, String, [String]) and (Bool, Int, String, String, [String]) => Bool Int String String [String]
      pick longer task match (False, _, _, _, _) and m2 = m2
      pick longer task match m1 and (False, _, _, _, _) = m1
      pick longer task match (True, len1, d1, c1, e1) and (True, len2, d2, c2, e2)
        | len2 > len1 = (True, len2, d2, c2, e2)
        | otherwise = (True, len1, d1, c1, e1)

op :: find matching custom task in [StableTask] for [String] => Bool Int String String [String]
      find matching custom task in [] for _ = (False, 0, "", "", [])
      find matching custom task in (t:rem_ts) for args_list =
        m1 = match task entry t against args_list
        m2 = find matching custom task in rem_ts for args_list
        pick longer task match m1 and m2

op :: print custom tasks [StableTask] => ()
      print custom tasks []           =  ()
      print custom tasks ((TaskEntry _ disp cmd orig):rem_ts) =
        echo "  {disp}  ->  {cmd}  [{orig}]"
        print custom tasks rem_ts

op :: run task tasks => Int
      run task tasks =
        custom_ts = load all custom tasks
        log section "Built-in `stable` Tasks"
        echo "  new [--lib] <name>, init [--lib], deps, add <dep>, dev link | unlink | links, install [target]"
        echo "  build | built [lib | target], run [target], test, check, format, compile, clean"
        echo "  info | status, tasks, plugins, reload, help, exit"
        log section "Custom Project & Plugin Tasks"
        report custom task list custom_ts

op :: report custom task list [StableTask] => Int
      report custom task list []           =
        echo "  (none declared — add `fn :: task <name> => String` in build.rg or plugins/*.rg)"
        0
      report custom task list custom_ts    =
        print custom tasks custom_ts
        0

op :: print plugin files [String]     => ()
      print plugin files []           =  ()
      print plugin files (pp:rem_pps) =
        p_tasks = load tasks from file pp origin pp
        t_count = count custom tasks p_tasks
        log step "plugin" "{pp} ({t_count} custom task(s))"
        print plugin files rem_pps

op :: count custom tasks [StableTask] => Int
      count custom tasks []           =  0
      count custom tasks (_:rem_ts)   =  1 + (count custom tasks rem_ts)

op :: run task plugins => Int
      run task plugins =
        pfiles = discover plugin files
        log section "Loaded `stable` Plugins"
        report plugin file list pfiles

op :: report plugin file list [String] => Int
      report plugin file list []       =
        echo "  (no plugins loaded — add `fn :: plugins => [String]` in build.rg or create plugins/<name>.rg)"
        0
      report plugin file list pfiles   =
        print plugin files pfiles
        0

op :: run custom shell task String command String extra [String]   => Int
      run custom shell task disp   command cmd    extra []         =
        ctag = colorize tag ("task:" + disp)
        echo "{ctag} {cmd}"
        shell exec cmd
      run custom shell task disp   command cmd    extra extra_args =
        arg_str = join words extra_args with spaces
        full_cmd = cmd + " " + arg_str
        ctag = colorize tag ("task:" + disp)
        echo "{ctag} {full_cmd}"
        shell exec full_cmd

op :: run executable plugin String args [String]   => Int
      run executable plugin ppath  args extra_args =
        ensure folder "target"
        bname = base filename of ppath at 0 len (str len ppath) slash (0 - 1)
        bin_path = "target/.stable_plugin_" + bname + "_bin" + host exe ext
        st = invoke ridgunc build ppath into bin_path
        exec plugin binary st path bin_path args extra_args

op :: exec plugin binary Int path String   args [String]   => Int
      exec plugin binary 0   path bin_path args extra_args =
        st = sys exec bin_path extra_args []
        discard file bin_path
        st
      exec plugin binary st  path _        args _          =  st

op :: run task help => Int
      run task help =
        echo "Available `stable` commands:"
        echo "  new [--lib] <name>          Create a new Ridgun project (or library with --lib)"
        echo "  init [--lib]                Initialize build.rg and src/ in the current directory"
        echo "  deps                        Synchronize the omni-installed packages build.rg lists into .stable/deps/"
        echo "  add <package>               Add a package installed by omni to build.rg and sync .stable/deps/"
        echo "  dev link <package> <folder> For developers: build <package> from a local checkout on this machine (~/.stable/dev-links)"
        echo "  dev unlink <package>        Remove a developer link; dev links lists them"
        echo "  install [target]            Build and install native ELF64 executable(s) into ~/.local/bin/ and bin/"
        echo "  build | built [target]      Compile all executables (or [target]) into target/<target>"
        echo "  build lib | built lib       Compile reusable library (.rglib and native ELF64 .so) into target/"
        echo "  run [target] [args...]      Build (if needed) and run executable (default: main_entry)"
        echo "  test                        Discover, typecheck, compile, and execute all test suites in src/test/ridgun/"
        echo "  check                       Typecheck and run static analysis across all modules in src/main/ridgun/"
        echo "  format [file...]            Apply canonical aesthetic column-alignment formatting to .rg files"
        echo "  compile                     Typecheck and emit .rgc bytecode artifacts into target/"
        echo "  clean                       Remove compiled .rgc/.rglib/.so artifacts from target/"
        echo "  tasks                       List built-in commands and custom tasks from build.rg & plugins"
        echo "  plugins                     List discovered and configured stable plugins"
        echo "  info | status               Display project configuration from build.rg"
        echo "  reload                      Reload project configuration from build.rg"
        echo "  help                        Show this help summary"
        echo "  exit | quit                 Exit the interactive stable shell"
        0

-- ── Command Parser & Extensible `StableCommand` Dispatcher ───

op :: parse stable command [String]          => Bool StableCommand String
      parse stable command []                =  (True, CmdNoop, "")
      parse stable command ("exit":_)        =  (True, CmdExit, "")
      parse stable command ("quit":_)        =  (True, CmdExit, "")
      parse stable command ("q":_)           =  (True, CmdExit, "")
      parse stable command ("help":_)        =  (True, CmdHelp, "")
      parse stable command ("-h":_)          =  (True, CmdHelp, "")
      parse stable command ("--help":_)      =  (True, CmdHelp, "")
      parse stable command ("version":_)     =  (True, CmdVersion, "")
      parse stable command ("-v":_)          =  (True, CmdVersion, "")
      parse stable command ("--version":_)   =  (True, CmdVersion, "")
      parse stable command ("info":_)        =  (True, CmdInfo, "")
      parse stable command ("status":_)      =  (True, CmdInfo, "")
      parse stable command ("reload":_)      =  (True, CmdReload, "")
      parse stable command ("check":_)       =  (True, CmdCheck, "")
      parse stable command ("new":extra)     =  (True, CmdNew extra, "")
      parse stable command ("init":extra)    =  (True, CmdInit extra, "")
      parse stable command ("deps":_)        =  (True, CmdDeps, "")
      parse stable command ("add":extra)     =  (True, CmdAdd extra, "")
      parse stable command ("dev":extra)     =  (True, CmdDev extra, "")
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

op :: resolve extension command [String] match (Bool, Int, String, String, [String]) => Bool StableCommand String
      resolve extension command _ match (True, _, disp, cmd, extra) =
        (True, CmdCustomTask disp cmd extra, "")
      resolve extension command (first_w:rest_w) match (False, _, _, _, _) =
        ppath = resolve plugin path for first_w
        resolve plugin exec command first_w rest_w path ppath
      resolve extension command [] match (False, _, _, _, _) =
        (True, CmdNoop, "")

op :: resolve plugin exec command String [String] path String => Bool StableCommand String
      resolve plugin exec command first_w _ path "" =
        (False, CmdNoop, first_w)
      resolve plugin exec command _ rest_w path ppath =
        (True, CmdPluginExec ppath rest_w, "")

-- Core `StableCommand` dispatch clauses
op :: dispatch command StableCommand on StableConfig => Bool StableConfig Int
      dispatch command CmdNoop on cfg = (True, cfg, 0)
      dispatch command CmdExit on cfg = (False, cfg, 0)
      dispatch command CmdHelp on cfg = (True, cfg, run task help)
      dispatch command CmdVersion on cfg =
        echo "stable 1.0.8 (Ridgun Interactive Build Tool, 100% self-hosted in Ridgun)"
        (True, cfg, 0)
      dispatch command CmdInfo on cfg = (True, cfg, run task info on cfg)
      dispatch command CmdReload on _ =
        reload project config from "build.rg"
      dispatch command CmdCheck on cfg = (True, cfg, run task check on cfg)
      dispatch command (CmdNew extra) on cfg = (True, cfg, run task new args extra)
      dispatch command (CmdInit extra) on _ =
        init_st = run task init args extra
        new_cfg = load build config from "build.rg"
        (True, new_cfg, init_st)
      dispatch command CmdDeps on cfg
        | (project name of cfg) == "" = (True, cfg, no project loaded error)
        | otherwise = (True, cfg, run task deps)
      dispatch command (CmdAdd extra) on cfg = (True, cfg, run task add args extra)
      dispatch command (CmdDev extra) on cfg = (True, cfg, run task dev args extra)
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
op :: dispatch command StableCommand on StableConfig => Bool StableConfig Int
      dispatch command (CmdCustomTask disp cmd extra) on cfg =
        (True, cfg, run custom shell task disp command cmd extra extra)
      dispatch command (CmdPluginExec ppath extra) on cfg =
        (True, cfg, run executable plugin ppath args extra)

op :: execute command [String] on StableConfig => Bool StableConfig Int
      execute command words    on cfg          =
        parsed = parse stable command words
        execute parsed command parsed on cfg

op :: execute parsed command (Bool, StableCommand, String) on StableConfig => Bool StableConfig Int
      execute parsed command (True, cmd, _) on cfg =
        dispatch command cmd on cfg
      execute parsed command (False, _, unknown) on cfg =
        log error "Unknown command: '{unknown}'. Type 'help' or 'tasks' for available commands."
        (True, cfg, 1)

op :: repl loop for StableConfig => ()
      repl loop for cfg          =
        esc = char from code 27
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

op :: reload project config from String     => Bool StableConfig Int
      reload project config from build_path =
        new_cfg = load build config from build_path
        pname = project name of new_cfg
        report reload config new_cfg name pname

op :: report reload config StableConfig name String => Bool StableConfig Int
      report reload config new_cfg      name ""     =
        log error "No build.rg found in current directory."
        (True, new_cfg, 1)
      report reload config new_cfg      name pname  =
        log info "Reloaded build.rg — current project is '{pname}'"
        (True, new_cfg, 0)

op :: start interactive shell for StableConfig => ()
      start interactive shell for (ProjectConfig "" ver main_ep sdir tdir out_dir) =
        log info "Welcome to stable 1.0.8 (Ridgun Build Tool — 100% Ridgun)"
        log info "No build.rg found in current directory. Run 'init' or 'new <name>' to create a project."
        log info "Commands: 'new', 'init', 'help', 'exit'"
        repl loop for (ProjectConfig "" ver main_ep sdir tdir out_dir)
      start interactive shell for (ProjectConfig name_str ver main_ep sdir tdir out_dir) =
        log info "Welcome to stable 1.0.8 (Ridgun Build Tool — 100% Ridgun)"
        log info "Loading project definition from build.rg ..."
        log info "Set current project to '{name_str}' v{ver} (main: {main_ep})"
        log info "Commands: 'built' (or 'build'), 'run', 'test', 'check', 'compile', 'clean', 'info', 'exit'"
        repl loop for (ProjectConfig name_str ver main_ep sdir tdir out_dir)

op :: strip stable argv [String]     => [String]
      strip stable argv []           =  []
      strip stable argv (_:rem_args) =  strip stable script rem_args

op :: strip stable script [String] => [String]
      strip stable script []       =  []
      strip stable script ("run":script:rem_args)
        | (str contains script "stable.rg") or (str contains script "stable/main.rg") = rem_args
        | otherwise = ["run", script] :: rem_args
      strip stable script (first_arg:rem_args)
        | (str contains first_arg "stable.rg") or (str contains first_arg "stable/main.rg") = rem_args
        | otherwise = [first_arg] :: rem_args

op :: exit if non zero Int => ()
      exit if non zero 0   =  ()
      exit if non zero st  =  sys exit st

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
        args_list = strip stable argv cli args
        dispatch stable cli args_list on cfg
