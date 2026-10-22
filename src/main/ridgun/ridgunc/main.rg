-- ============================================================
-- src/main/ridgun/ridgunc/main.rg
-- Self-Hosted Ridgun Compiler CLI Driver (ridgunc v0.9.12)
-- Shared Library (`src/main/ridgun/lib/`): ast.rg, lexer.rg,
-- parser.rg, analyzer.rg, typecheck.rg, compiler.rg, vm.rg,
-- elf64.rg, x86_64.rg, arm64.rg
-- @implements FR-COMP-004
-- @implements FR-COMP-006
-- ============================================================
import ast
import lexer
import parser
import analyzer
import typecheck
import compiler
import vm

fn :: strip_runner_args [String] => [String]
      strip_runner_args []       =  []
      strip_runner_args (_:rest) =  strip_script_prefix rest

fn :: strip_script_prefix [String]     => [String]
      strip_script_prefix []           =  []
      strip_script_prefix ("run":script:rest)
        | (str_contains script "ridgunc.rg") OR (str_contains script "ridgunc/main.rg") = rest
        | otherwise = ["run", script] :: rest
      strip_script_prefix (first:rest)
        | (str_contains first "ridgunc.rg") OR (str_contains first "ridgunc/main.rg") = rest
        | otherwise = [first] :: rest

fn :: print_error_lines [String]    => ()
      print_error_lines []          =  ()
      print_error_lines (line:rest) =
        _ = echo line
        print_error_lines rest

fn :: run_cli_check String     => ()
      run_cli_check input_path =
        raw_src = load_rg_with_libs input_path
        toks = tokenize_src raw_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        report_check_result input_path prog errs

fn :: report_check_result String     RProgram [RTypeError] => ()
      report_check_result input_path prog     []           =
        fn_c = count_fn_defs prog
        ty_c = count_type_defs prog
        summaries = analyze_rprogram prog
        echo "[ridgunc check] {input_path}: {fn_c} function(s), {ty_c} type(s)"
        echo "[ridgunc check] Type checking & static analysis passed — 0 error(s)."
        echo "[ridgunc check] Static strategies:" summaries
      report_check_result input_path _        errs         =
        err_c = type_err_count errs
        _ = print_error_lines (format_type_errors errs)
        echo "[ridgunc check] {input_path}: {err_c} error(s) found."

fn :: run_cli_compile String     String     => ()
      run_cli_compile input_path output_rgc =
        fn_c = emit_rgc_file input_path output_rgc
        echo "[ridgunc compile] {input_path} -> {output_rgc} ({fn_c} functions)"

fn :: str_ends_with_suffix String String => Bool
      str_ends_with_suffix s      suf    =
        slen = str_len s
        suflen = str_len suf
        slen >= suflen AND (str_slice s (slen - suflen) slen) == suf

fn :: strip_rg_ext String => String
      strip_rg_ext path
        | str_ends_with_suffix path ".rg" = str_slice path 0 ((str_len path) - 3)
        | otherwise = path

fn :: run_cli_build_lib String     String     String      => ()
      run_cli_build_lib input_path output_out target_arch
        | str_ends_with_suffix output_out ".so" =
          st = build native target so library input_path output_out target_arch
          report_so_status input_path output_out st
        | str_ends_with_suffix output_out ".rglib" =
          st = emit_rglib_file input_path output_out
          report_rglib_status input_path output_out st
        | otherwise =
          rglib_out = output_out + ".rglib"
          so_out = output_out + ".so"
          st1 = emit_rglib_file input_path rglib_out
          st2 = build native target so library input_path so_out target_arch
          _ = report_rglib_status input_path rglib_out st1
          report_so_status input_path so_out st2

fn :: run_cli_build_so String     String    String      => ()
      run_cli_build_so input_path output_so target_arch =
        status = build native target so library input_path output_so target_arch
        report_so_status input_path output_so status

fn :: report_rglib_status String     String     Int  => ()
      report_rglib_status input_path output_lib 0    =
        echo "[ridgunc build --lib] Ridgun library bundle created: {input_path} -> {output_lib}"
      report_rglib_status _          output_lib code =
        echo "[ridgunc build --lib] Failed to build {output_lib} (exit code {code})"

fn :: report_so_status String     String    Int  => ()
      report_so_status input_path output_so 0    =
        echo "[ridgunc build --so] Native ELF64 shared library (.so) created: {input_path} -> {output_so}"
      report_so_status _          output_so code =
        echo "[ridgunc build --so] Failed to build {output_so} (exit code {code})"

fn :: run_cli_build String     String     => ()
      run_cli_build input_path output_bin =
        status = build native executable input_path output_bin
        report_build_status input_path output_bin status

fn :: run_cli_build_target String     String     String      => ()
      run_cli_build_target input_path output_bin target_arch =
        status = build native target executable input_path output_bin target_arch
        report_build_status input_path output_bin status

fn :: report_build_status String     String     Int  => ()
      report_build_status input_path output_bin 0    =
        echo "[ridgunc build] Native ELF executable created: {input_path} -> {output_bin}"
      report_build_status _          output_bin code =
        echo "[ridgunc build] Failed to build {output_bin} (exit code {code})"

fn :: run_cli_run String     => ()
      run_cli_run input_path =
        _ = sys_mkdir "target" 493
        status = build native fast executable input_path "target/.ridgunc_run_bin"
        exec_built_run status

fn :: exec_built_run Int => ()
      exec_built_run 0   =
        _ = shell_exec "./target/.ridgunc_run_bin; _st=$?; rm -f target/.ridgunc_run_bin; exit $_st"
        ()
      exec_built_run _   =  ()

fn :: run_self_hosted_pipeline_demo => ()
      run_self_hosted_pipeline_demo =
        sample_src = "fn :: fact Int => Int\nfact 0 = 1\nfact n = n * (fact (n - 1))\n\nfn :: fib Int => Int\nfib 0 = 0\nfib 1 = 1\nfib n = (fib (n - 1)) + (fib (n - 2))\n\nfn :: compute Int => Int\ncompute x =\n  a = fact x\n  b = fib 10\n  a + b\n"
        toks = tokenize_src sample_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        strats = analyze_rprogram prog
        r_fact6 = eval_source_in_ridgun_vm sample_src "fact" [6]
        r_fib10 = eval_source_in_ridgun_vm sample_src "fib" [10]
        r_comp5 = eval_source_in_ridgun_vm sample_src "compute" [5]
        echo "=== Self-Hosted Ridgun Compiler (ridgunc.rg) ==="
        echo "Tokens lexed        =>" (count_tokens toks)
        echo "Functions parsed    =>" (count_fn_defs prog)
        echo "Typecheck errors    =>" (type_err_count errs)
        echo "Static strategies   =>" strats
        echo "VM eval fact(6)     =>" r_fact6
        echo "VM eval fib(10)     =>" r_fib10
        echo "VM eval compute(5)  =>" r_comp5

fn :: run_cli_version => ()
      run_cli_version =
        echo "ridgunc 0.9.12 (self-hosted Ridgun compiler, x86_64-unknown-linux-gnu)"

fn :: run_cli_help => ()
      run_cli_help =
        echo "Usage: ridgunc <command> [options] <file.rg>"
        echo ""
        echo "Commands:"
        echo "  run     <file.rg>                              Compile and execute a Ridgun source file"
        echo "  check   <file.rg>                              Typecheck and analyze static strategies"
        echo "  compile <file.rg> [-o out.rgc]                 Emit .rgc bytecode artifact"
        echo "  build   <file.rg> [-o binary] [--target arch]  Build standalone native ELF64 executable"
        echo "  build   --lib <file.rg> [-o out.rglib]         Build reusable Ridgun library (.rglib & .so)"
        echo "  build   --so  <file.rg> [-o out.so]            Build native ELF64 shared library (ET_DYN .so)"
        echo "  version | -v | --version                       Show compiler version"
        echo "  help    | -h | --help                          Show this help message"

fn :: dispatch_cli [String]        => ()
      dispatch_cli []              =  run_self_hosted_pipeline_demo
      dispatch_cli ("version":_)   =  run_cli_version
      dispatch_cli ("-v":_)        =  run_cli_version
      dispatch_cli ("--version":_) =  run_cli_version
      dispatch_cli ("help":_)      =  run_cli_help
      dispatch_cli ("-h":_)        =  run_cli_help
      dispatch_cli ("--help":_)    =  run_cli_help
      dispatch_cli ("run":input_path:_) = run_cli_run input_path
      dispatch_cli ("check":input_path:_) = run_cli_check input_path
      dispatch_cli ("compile":input_path:"-o":output_rgc:_) = run_cli_compile input_path output_rgc
      dispatch_cli ("compile":input_path:_) = run_cli_compile input_path "{input_path}c"
      dispatch_cli ("build":"--lib":"--target":target_arch:input_path:"-o":output_out:_) = run_cli_build_lib input_path output_out target_arch
      dispatch_cli ("build":"--lib":input_path:"-o":output_out:"--target":target_arch:_) = run_cli_build_lib input_path output_out target_arch
      dispatch_cli ("build":"--lib":input_path:"-o":output_out:_) = run_cli_build_lib input_path output_out "x86_64-linux"
      dispatch_cli ("build":"--lib":input_path:_) = run_cli_build_lib input_path (strip_rg_ext input_path) "x86_64-linux"
      dispatch_cli ("build":input_path:"--lib":"-o":output_out:_) = run_cli_build_lib input_path output_out "x86_64-linux"
      dispatch_cli ("build":input_path:"--lib":_) = run_cli_build_lib input_path (strip_rg_ext input_path) "x86_64-linux"
      dispatch_cli ("build":"--so":"--target":target_arch:input_path:"-o":output_so:_) = run_cli_build_so input_path output_so target_arch
      dispatch_cli ("build":"--so":input_path:"-o":output_so:"--target":target_arch:_) = run_cli_build_so input_path output_so target_arch
      dispatch_cli ("build":"--so":input_path:"-o":output_so:_) = run_cli_build_so input_path output_so "x86_64-linux"
      dispatch_cli ("build":"--so":input_path:_) = run_cli_build_so input_path ((strip_rg_ext input_path) + ".so") "x86_64-linux"
      dispatch_cli ("build":input_path:"--so":"-o":output_so:"--target":target_arch:_) = run_cli_build_so input_path output_so target_arch
      dispatch_cli ("build":input_path:"--so":"-o":output_so:_) = run_cli_build_so input_path output_so "x86_64-linux"
      dispatch_cli ("build":input_path:"--so":_) = run_cli_build_so input_path ((strip_rg_ext input_path) + ".so") "x86_64-linux"
      dispatch_cli ("build":"--target":target_arch:input_path:"-o":output_bin:_) = run_cli_build_target input_path output_bin target_arch
      dispatch_cli ("build":"--target":target_arch:input_path:_) = run_cli_build_target input_path "a.out" target_arch
      dispatch_cli ("build":input_path:"-o":output_bin:"--target":target_arch:_) = run_cli_build_target input_path output_bin target_arch
      dispatch_cli ("build":input_path:"--target":target_arch:"-o":output_bin:_) = run_cli_build_target input_path output_bin target_arch
      dispatch_cli ("build":input_path:"--target":target_arch:_) = run_cli_build_target input_path "a.out" target_arch
      dispatch_cli ("build":input_path:"-o":output_bin:_) = run_cli_build input_path output_bin
      dispatch_cli ("build":input_path:_) = run_cli_build input_path "a.out"
      dispatch_cli _               =  run_self_hosted_pipeline_demo

fn :: main => ()
      main =
        args = strip_runner_args cli_args
        dispatch_cli args
