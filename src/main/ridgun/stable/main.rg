-- ============================================================
-- src/main/ridgun/stable/main.rg
-- `stable` v0.9.1 — The Interactive Build Tool for Ridgun (100% Ridgun)
-- Inspired by Scala's sbt: parses `build.rg` using the Ridgun
-- compiler AST, supports `src/main/ridgun/lib/` + parallel
-- executable folders (`src/main/ridgun/<target>/main.rg`),
-- and provides interactive (`stable> `) and batch commands:
-- `build` / `built [target]`, `run [target] [args...]`, `test`,
-- `compile`, `check`, `clean`, `info`, `reload`, `help`, `exit`.
-- ============================================================
import ast
import lexer
import parser
import analyzer
import typecheck
import compiler
import vm

-- Project configuration loaded from `build.rg`
type StableConfig = ProjectConfig String String String String String String

-- ── String & Shell Helpers in Pure Ridgun ───────────────────

fn :: split_lines_loop String Int Int Int [String] => [String]
split_lines_loop s pos len line_start acc
  | pos >= len = flush_non_empty_line (trim_str (str_slice s line_start len)) acc
  | (str_char_at s pos) == 10 = split_lines_loop s (pos + 1) len (pos + 1) (flush_non_empty_line (trim_str (str_slice s line_start pos)) acc)
  | otherwise = split_lines_loop s (pos + 1) len line_start acc

fn :: flush_non_empty_line String [String] => [String]
flush_non_empty_line "" acc = acc
flush_non_empty_line line acc = acc :: [line]

fn :: split_lines String => [String]
split_lines s = split_lines_loop s 0 (str_len s) 0 []

fn :: is_ws_or_nl Int => Bool
is_ws_or_nl c = c == 32 OR c == 9 OR c == 10 OR c == 13

fn :: split_words_loop String Int Int String [String] => [String]
split_words_loop s pos len cur acc
  | pos >= len = flush_non_empty_line cur acc
  | is_ws_or_nl (str_char_at s pos) = split_words_loop s (pos + 1) len "" (flush_non_empty_line cur acc)
  | otherwise = split_words_loop s (pos + 1) len (cur + (str_slice s pos (pos + 1))) acc

fn :: split_words String => [String]
split_words s = split_words_loop s 0 (str_len s) "" []

fn :: join_space_words [String] => String
join_space_words [] = ""
join_space_words (w:[]) = w
join_space_words (w:ws) = w + " " + (join_space_words ws)

fn :: list_rg_files String => [String]
list_rg_files dir =
  _ = shell_exec ('mkdir -p target && ls -1 ' + dir + '/*.rg ' + dir + '/*/*.rg 2>/dev/null > target/.stable_files.txt || true')
  raw = read_file "target/.stable_files.txt"
  _ = shell_exec "rm -f target/.stable_files.txt"
  split_lines raw

fn :: list_exec_entries String => [String]
list_exec_entries dir =
  _ = shell_exec ('mkdir -p target && ls -1 ' + dir + '/*/main.rg 2>/dev/null > target/.stable_entries.txt || true')
  raw = read_file "target/.stable_entries.txt"
  _ = shell_exec "rm -f target/.stable_entries.txt"
  split_lines raw

fn :: list_test_files String => [String]
list_test_files dir =
  _ = shell_exec ('mkdir -p target && ls -1 ' + dir + '/test_*.rg 2>/dev/null > target/.stable_tfiles.txt || true')
  raw = read_file "target/.stable_tfiles.txt"
  _ = shell_exec "rm -f target/.stable_tfiles.txt"
  split_lines raw

fn :: file_exists String => Bool
file_exists path =
  code = shell_exec ('test -f "' + path + '"')
  code == 0

fn :: prompt_read_line String => (Bool, String)
prompt_read_line prompt =
  cmd = 'mkdir -p target && printf "%s" "' + prompt + '" && IFS= read -r _stable_ln && printf "%s" "$_stable_ln" > target/.stable_line.txt'
  status = shell_exec cmd
  read_prompt_status status

fn :: read_prompt_status Int => (Bool, String)
read_prompt_status 0 =
  line = read_file "target/.stable_line.txt"
  _ = shell_exec "rm -f target/.stable_line.txt"
  (True, trim_str line)
read_prompt_status _ =
  _ = shell_exec "rm -f target/.stable_line.txt"
  (False, "")

-- ── `build.rg` AST Configuration Loader ─────────────────────

fn :: extract_fn_str_body [RFnDef] String String => String
extract_fn_str_body [] _ default_val = default_val
extract_fn_str_body ((FnDef name _ _ ((FnCase _ _ (EStr val)):_)):rest) target default_val
  | name == target = val
  | otherwise = extract_fn_str_body rest target default_val
extract_fn_str_body (_:rest) target default_val =
  extract_fn_str_body rest target default_val

fn :: load_build_config String => StableConfig
load_build_config build_path
  | NOT (file_exists build_path) = ProjectConfig "ridgunc" "0.9.1" "src/main/ridgun/ridgunc/main.rg" "src/main/ridgun" "src/test/ridgun" "target"
  | otherwise = parse_build_config_src (read_file build_path)

fn :: parse_build_config_src String => StableConfig
parse_build_config_src src =
  toks = tokenize_src src
  prog = parse_tokens toks
  extract_config_from_prog prog

fn :: extract_config_from_prog RProgram => StableConfig
extract_config_from_prog (Program fns _) =
  name = extract_fn_str_body fns "project_name" "ridgunc"
  ver = extract_fn_str_body fns "project_version" "0.9.1"
  entry = extract_fn_str_body fns "main_entry" "src/main/ridgun/ridgunc/main.rg"
  sdir = extract_fn_str_body fns "source_dir" "src/main/ridgun"
  tdir = extract_fn_str_body fns "test_dir" "src/test/ridgun"
  out_dir = extract_fn_str_body fns "target_dir" "target"
  ProjectConfig name ver entry sdir tdir out_dir

fn :: config_project_name StableConfig => String
config_project_name (ProjectConfig name _ _ _ _ _) = name

-- ── Task 1: `check` (Typecheck & Static Analysis of Project) ─

fn :: check_module_list [String] Int Int => (Int, Int)
check_module_list [] ok_count err_count = (ok_count, err_count)
check_module_list (path:rest) ok_count err_count =
  raw = read_file path
  toks = tokenize_src raw
  prog = parse_tokens toks
  errs = typecheck_program prog
  check_module_step path rest ok_count err_count prog errs

fn :: check_module_step String [String] Int Int RProgram [RTypeError] => (Int, Int)
check_module_step path rest ok_count err_count prog [] =
  fn_c = count_fn_defs prog
  ty_c = count_type_defs prog
  _ = echo "  [ok]   {path} ({fn_c} fn, {ty_c} types)"
  check_module_list rest (ok_count + 1) err_count
check_module_step path rest ok_count err_count _ errs =
  ec = type_err_count errs
  _ = echo "  [err]  {path}: {ec} error(s)"
  _ = print_err_lines (format_type_errors errs)
  check_module_list rest ok_count (err_count + ec)

fn :: print_err_lines [String] => ()
print_err_lines [] = ()
print_err_lines (l:ls) =
  _ = echo "        " l
  print_err_lines ls

fn :: run_task_check StableConfig => Int
run_task_check (ProjectConfig name ver _ sdir _ _) =
  files = list_rg_files sdir
  _ = echo "[info] Checking project '{name}' v{ver} in {sdir}/ ..."
  finish_task_check (check_module_list files 0 0)

fn :: finish_task_check (Int, Int) => Int
finish_task_check (ok_c, 0) =
  _ = echo "[success] Checked {ok_c} module(s) — 0 errors."
  0
finish_task_check (ok_c, err_c) =
  _ = echo "[error] Checked {ok_c} module(s) — {err_c} error(s) found."
  1

-- ── Task 2: `compile` (Emit .rgc Bytecode Artifacts) ─────────

fn :: base_filename String Int Int Int => String
base_filename path pos len last_slash
  | pos >= len = str_slice path (last_slash + 1) len
  | (str_char_at path pos) == 47 = base_filename path (pos + 1) len pos
  | otherwise = base_filename path (pos + 1) len last_slash

fn :: parent_dir_path String Int Int Int => String
parent_dir_path path pos len last_slash
  | pos >= len = str_slice path 0 last_slash
  | (str_char_at path pos) == 47 = parent_dir_path path (pos + 1) len pos
  | otherwise = parent_dir_path path (pos + 1) len last_slash

fn :: target_name_from_entry String => String
target_name_from_entry entry_path =
  pdir = parent_dir_path entry_path 0 (str_len entry_path) 0
  base_filename pdir 0 (str_len pdir) (0 - 1)

fn :: rgc_artifact_name String String => String
rgc_artifact_name path "main.rg" = (target_name_from_entry path) + "_main.rgc"
rgc_artifact_name _ bname = bname + "c"

fn :: compile_module_list [String] String Int => Int
compile_module_list [] _ count = count
compile_module_list (path:rest) out_dir count =
  bname = base_filename path 0 (str_len path) (0 - 1)
  out_rgc = out_dir + "/" + (rgc_artifact_name path bname)
  fn_c = emit_rgc_file path out_rgc
  _ = echo "  [rgc]  {path} -> {out_rgc} ({fn_c} functions)"
  compile_module_list rest out_dir (count + 1)

fn :: run_task_compile StableConfig => Int
run_task_compile (ProjectConfig name ver entry sdir tdir out_dir) =
  chk = run_task_check (ProjectConfig name ver entry sdir tdir out_dir)
  compile_if_check_ok chk sdir out_dir

fn :: compile_if_check_ok Int String String => Int
compile_if_check_ok 0 sdir out_dir =
  _ = shell_exec ('mkdir -p "' + out_dir + '"')
  files = list_rg_files sdir
  c_count = compile_module_list files out_dir 0
  _ = echo "[success] Compiled {c_count} bytecode artifact(s) into {out_dir}/."
  0
compile_if_check_ok code _ _ = code

-- ── Task 3: `build` / `built` (Build Native ELF Executables) ─

fn :: build_one_target String String String => Int
build_one_target entry_path out_bin ver =
  _ = echo "[info] Building native executable '{out_bin}' from {entry_path} (v{ver}) ..."
  status = build_native_executable entry_path out_bin
  report_stable_build out_bin status

fn :: build_entry_list [String] String String Int => Int
build_entry_list [] _ _ err_acc = err_acc
build_entry_list (epath:rest) out_dir ver err_acc =
  tname = target_name_from_entry epath
  out_bin = out_dir + "/" + tname
  st = build_one_target epath out_bin ver
  build_entry_list rest out_dir ver (err_acc + st)

fn :: run_task_build StableConfig [String] => Int
run_task_build (ProjectConfig name ver entry sdir _ out_dir) [] =
  _ = shell_exec ('mkdir -p "' + out_dir + '"')
  entries = list_exec_entries sdir
  run_task_build_entries entries name ver entry out_dir
run_task_build (ProjectConfig _ ver _ sdir _ out_dir) (tname:_) =
  _ = shell_exec ('mkdir -p "' + out_dir + '"')
  cand_entry = sdir + "/" + tname + "/main.rg"
  out_bin = out_dir + "/" + tname
  build_one_target cand_entry out_bin ver

fn :: run_task_build_entries [String] String String String String => Int
run_task_build_entries [] name ver entry out_dir =
  build_one_target entry (out_dir + "/" + name) ver
run_task_build_entries entries _ ver _ out_dir =
  build_entry_list entries out_dir ver 0

fn :: report_stable_build String Int => Int
report_stable_build out_bin 0 =
  _ = echo "[success] Built native ELF executable: {out_bin}"
  0
report_stable_build out_bin code =
  _ = echo "[error] Build failed for {out_bin} (exit code {code})"
  code

-- ── Task 4: `run` (Build if Needed & Run Native Binary) ─────

fn :: run_task_run StableConfig [String] => Int
run_task_run (ProjectConfig name ver entry sdir tdir out_dir) (first_arg:rest_args)
  | file_exists (sdir + "/" + first_arg + "/main.rg") = run_specific_target first_arg (sdir + "/" + first_arg + "/main.rg") ver out_dir rest_args
  | otherwise = run_default_target (ProjectConfig name ver entry sdir tdir out_dir) ([first_arg] :: rest_args)
run_task_run cfg [] =
  run_default_target cfg []

fn :: run_specific_target String String String String [String] => Int
run_specific_target tname entry_path ver out_dir extra_args =
  out_bin = out_dir + "/" + tname
  ensure_st = ensure_target_built (file_exists out_bin) entry_path out_bin ver
  exec_project_binary ensure_st out_bin extra_args

fn :: run_default_target StableConfig [String] => Int
run_default_target (ProjectConfig name ver entry _ _ out_dir) extra_args =
  out_bin = out_dir + "/" + name
  ensure_st = ensure_target_built (file_exists out_bin) entry out_bin ver
  exec_project_binary ensure_st out_bin extra_args

fn :: ensure_target_built Bool String String String => Int
ensure_target_built True _ _ _ = 0
ensure_target_built False entry_path out_bin ver = build_one_target entry_path out_bin ver

fn :: exec_project_binary Int String [String] => Int
exec_project_binary 0 out_bin extra_args =
  arg_str = join_space_words extra_args
  _ = echo "[info] Running ./{out_bin} {arg_str}"
  shell_exec ("./" + out_bin + " " + arg_str)
exec_project_binary code _ _ = code

-- ── Task 5: `test` (Discover, Check, Build & Run Tests) ─────

fn :: run_test_suites [String] Int Int => (Int, Int)
run_test_suites [] passed failed = (passed, failed)
run_test_suites (tpath:rest) passed failed =
  _ = echo "[info] Compiling & running test suite: {tpath}"
  _ = shell_exec "mkdir -p target"
  st = build_native_executable tpath "target/.stable_test_bin"
  run_single_test_bin st tpath rest passed failed

fn :: run_single_test_bin Int String [String] Int Int => (Int, Int)
run_single_test_bin 0 tpath rest passed failed =
  run_st = shell_exec "./target/.stable_test_bin; _st=$?; rm -f target/.stable_test_bin; exit $_st"
  record_test_outcome run_st tpath rest passed failed
run_single_test_bin _ tpath rest passed failed =
  _ = echo "  [FAIL] {tpath} (compilation/typecheck failed)"
  run_test_suites rest passed (failed + 1)

fn :: record_test_outcome Int String [String] Int Int => (Int, Int)
record_test_outcome 0 tpath rest passed failed =
  _ = echo "  [PASS] {tpath}"
  run_test_suites rest (passed + 1) failed
record_test_outcome _ tpath rest passed failed =
  _ = echo "  [FAIL] {tpath} (non-zero exit status)"
  run_test_suites rest passed (failed + 1)

fn :: run_task_test StableConfig => Int
run_task_test (ProjectConfig name _ _ _ tdir _) =
  suites = list_test_files tdir
  _ = echo "[info] Running test suites for '{name}' in {tdir}/ ..."
  finish_task_test (run_test_suites suites 0 0)

fn :: finish_task_test (Int, Int) => Int
finish_task_test (passed, 0) =
  _ = echo "[success] Passed {passed}/{passed} test suite(s) — 0 failures."
  0
finish_task_test (passed, failed) =
  total = passed + failed
  _ = echo "[error] Passed {passed}/{total} test suite(s) — {failed} failed."
  1

-- ── Task 6: `clean` & `info` & `help` ───────────────────────

fn :: run_task_clean StableConfig => Int
run_task_clean (ProjectConfig _ _ _ _ _ out_dir) =
  _ = shell_exec ('rm -f "' + out_dir + '"/*.rgc "' + out_dir + '"/.stable_* "' + out_dir + '"/.ridgunc_*')
  _ = echo "[success] Cleaned bytecode artifacts in {out_dir}/."
  0

fn :: map_target_names [String] => [String]
map_target_names [] = []
map_target_names (ep:rest) = [target_name_from_entry ep] :: (map_target_names rest)

fn :: run_task_info StableConfig => Int
run_task_info (ProjectConfig name ver entry sdir tdir out_dir) =
  src_files = list_rg_files sdir
  exec_entries = list_exec_entries sdir
  exec_names = join_space_words (map_target_names exec_entries)
  tst_files = list_test_files tdir
  src_c = list_str_len src_files
  tst_c = list_str_len tst_files
  _ = echo "=== Project Info (build.rg) ==="
  _ = echo "  Project Name : {name}"
  _ = echo "  Version      : {ver}"
  _ = echo "  Main Entry   : {entry}"
  _ = echo "  Executables  : {exec_names}"
  _ = echo "  Shared Lib   : {sdir}/lib/"
  _ = echo "  Source Dir   : {sdir}/ ({src_c} modules)"
  _ = echo "  Test Dir     : {tdir}/ ({tst_c} test suites)"
  _ = echo "  Target Dir   : {out_dir}/"
  0

fn :: run_task_help => Int
run_task_help =
  _ = echo "Available `stable` commands:"
  _ = echo "  build | built [target]      Compile all executables (or [target]) into target/<target>"
  _ = echo "  run [target] [args...]      Build (if needed) and run executable (default: main_entry)"
  _ = echo "  test                        Discover, typecheck, compile, and execute all test suites in src/test/ridgun/"
  _ = echo "  check                       Typecheck and run static analysis across all modules in src/main/ridgun/"
  _ = echo "  compile                     Typecheck and emit .rgc bytecode artifacts into target/"
  _ = echo "  clean                       Remove compiled .rgc artifacts from target/"
  _ = echo "  info | status               Display project configuration from build.rg"
  _ = echo "  reload                      Reload project configuration from build.rg"
  _ = echo "  help                        Show this help summary"
  _ = echo "  exit | quit                 Exit the interactive stable shell"
  0

-- ── Command Dispatcher & Interactive REPL Loop ──────────────

fn :: execute_command StableConfig [String] => (Bool, StableConfig, Int)
execute_command cfg [] = (True, cfg, 0)
execute_command cfg ("exit":_) = (False, cfg, 0)
execute_command cfg ("quit":_) = (False, cfg, 0)
execute_command cfg ("q":_) = (False, cfg, 0)
execute_command cfg ("help":_) = (True, cfg, run_task_help)
execute_command cfg ("-h":_) = (True, cfg, run_task_help)
execute_command cfg ("--help":_) = (True, cfg, run_task_help)
execute_command cfg ("version":_) =
  _ = echo "stable 0.9.1 (Ridgun Interactive Build Tool, 100% self-hosted in Ridgun)"
  (True, cfg, 0)
execute_command cfg ("-v":_) =
  _ = echo "stable 0.9.1 (Ridgun Interactive Build Tool, 100% self-hosted in Ridgun)"
  (True, cfg, 0)
execute_command cfg ("info":_) = (True, cfg, run_task_info cfg)
execute_command cfg ("status":_) = (True, cfg, run_task_info cfg)
execute_command _ ("reload":_) =
  new_cfg = load_build_config "build.rg"
  pname = config_project_name new_cfg
  _ = echo "[info] Reloaded build.rg — current project is '{pname}'"
  (True, new_cfg, 0)
execute_command cfg ("check":_) = (True, cfg, run_task_check cfg)
execute_command cfg ("compile":_) = (True, cfg, run_task_compile cfg)
execute_command cfg ("build":extra) = (True, cfg, run_task_build cfg extra)
execute_command cfg ("built":extra) = (True, cfg, run_task_build cfg extra)
execute_command cfg ("run":extra) = (True, cfg, run_task_run cfg extra)
execute_command cfg ("test":_) = (True, cfg, run_task_test cfg)
execute_command cfg ("clean":_) = (True, cfg, run_task_clean cfg)
execute_command cfg (unknown:_) =
  _ = echo "[error] Unknown command: '{unknown}'. Type 'help' for available commands."
  (True, cfg, 1)

fn :: repl_loop StableConfig => ()
repl_loop cfg =
  esc = char_from_code 27
  blue_prompt = esc + "[34mstable>" + esc + "[0m "
  read_res = prompt_read_line blue_prompt
  repl_step cfg read_res

fn :: repl_step StableConfig (Bool, String) => ()
repl_step _ (False, _) =
  echo ""
repl_step cfg (True, line) =
  words = split_words line
  cmd_res = execute_command cfg words
  repl_continue cmd_res

fn :: repl_continue (Bool, StableConfig, Int) => ()
repl_continue (False, _, _) =
  echo "[info] Exiting stable."
repl_continue (True, next_cfg, _) =
  repl_loop next_cfg

fn :: start_interactive_shell StableConfig => ()
start_interactive_shell (ProjectConfig name ver entry sdir tdir out_dir) =
  _ = echo "[info] Welcome to stable 0.9.1 (Ridgun Build Tool — 100% Ridgun)"
  _ = echo "[info] Loading project definition from build.rg ..."
  _ = echo "[info] Set current project to '{name}' v{ver} (main: {entry})"
  _ = echo "[info] Commands: 'built' (or 'build'), 'run', 'test', 'check', 'compile', 'clean', 'info', 'exit'"
  repl_loop (ProjectConfig name ver entry sdir tdir out_dir)

fn :: strip_stable_argv [String] => [String]
strip_stable_argv [] = []
strip_stable_argv (_:rest) = strip_stable_script rest

fn :: strip_stable_script [String] => [String]
strip_stable_script [] = []
strip_stable_script ("run":script:rest)
  | (str_contains script "stable.rg") OR (str_contains script "stable/main.rg") = rest
  | otherwise = ["run", script] :: rest
strip_stable_script (first:rest)
  | (str_contains first "stable.rg") OR (str_contains first "stable/main.rg") = rest
  | otherwise = [first] :: rest

fn :: dispatch_stable_cli StableConfig [String] => ()
dispatch_stable_cli cfg [] = start_interactive_shell cfg
dispatch_stable_cli cfg args =
  _ = execute_command cfg args
  ()

fn :: main => ()
main =
  cfg = load_build_config "build.rg"
  args = strip_stable_argv cli_args
  dispatch_stable_cli cfg args
