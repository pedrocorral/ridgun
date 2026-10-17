-- ============================================================
-- src/main/ridgun/ridgunc/main.rg
-- Self-Hosted Ridgun Compiler CLI Driver (ridgunc v0.9.3)
-- Shared Library (`src/main/ridgun/lib/`): ast.rg, lexer.rg,
-- parser.rg, analyzer.rg, typecheck.rg, compiler.rg, vm.rg
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

fn :: strip_script_prefix [String]            => [String]
      strip_script_prefix []                  =  []
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
        raw_src = read_file input_path
        toks = tokenize_src raw_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        report_check_result input_path prog errs

fn :: report_check_result String     RProgram [RTypeError] => ()
      report_check_result input_path prog     [] =
        fn_c = count_fn_defs prog
        ty_c = count_type_defs prog
        summaries = analyze_rprogram prog
        echo "[ridgunc check] {input_path}: {fn_c} function(s), {ty_c} type(s)"
        echo "[ridgunc check] Type checking & static analysis passed — 0 error(s)."
        echo "[ridgunc check] Static strategies:" summaries
      report_check_result input_path _        errs =
        err_c = type_err_count errs
        _ = print_error_lines (format_type_errors errs)
        echo "[ridgunc check] {input_path}: {err_c} error(s) found."

fn :: run_cli_compile String     String     => ()
      run_cli_compile input_path output_rgc =
        fn_c = emit_rgc_file input_path output_rgc
        echo "[ridgunc compile] {input_path} -> {output_rgc} ({fn_c} functions)"

fn :: run_cli_build String     String     => ()
      run_cli_build input_path output_bin =
        status = build_native_executable input_path output_bin
        report_build_status input_path output_bin status

fn :: report_build_status String     String     Int  => ()
      report_build_status input_path output_bin 0 =
        echo "[ridgunc build] Native ELF executable created: {input_path} -> {output_bin}"
      report_build_status _          output_bin code =
        echo "[ridgunc build] Failed to build {output_bin} (exit code {code})"

fn :: run_cli_run String     => ()
      run_cli_run input_path =
        _ = shell_exec "mkdir -p target"
        status = build_native_executable input_path "target/.ridgunc_run_bin"
        exec_built_run status

fn :: exec_built_run Int => ()
      exec_built_run 0 =
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
        echo "ridgunc 0.9.3 (self-hosted Ridgun compiler, x86_64-unknown-linux-gnu)"

fn :: run_cli_help => ()
      run_cli_help =
        echo "Usage: ridgunc <command> [options] <file.rg>"
        echo ""
        echo "Commands:"
        echo "  run     <file.rg>              Compile and execute a Ridgun source file"
        echo "  check   <file.rg>              Typecheck and analyze static strategies"
        echo "  compile <file.rg> [-o out.rgc] Emit .rgc bytecode artifact"
        echo "  build   <file.rg> [-o binary]  Build standalone native ELF executable"
        echo "  version | -v | --version       Show compiler version"
        echo "  help    | -h | --help          Show this help message"

fn :: dispatch_cli [String]                                 => ()
      dispatch_cli []                                       =  run_self_hosted_pipeline_demo
      dispatch_cli ("version":_)                            =  run_cli_version
      dispatch_cli ("-v":_)                                 =  run_cli_version
      dispatch_cli ("--version":_)                          =  run_cli_version
      dispatch_cli ("help":_)                               =  run_cli_help
      dispatch_cli ("-h":_)                                 =  run_cli_help
      dispatch_cli ("--help":_)                             =  run_cli_help
      dispatch_cli ("run":input_path:_)                     =  run_cli_run input_path
      dispatch_cli ("check":input_path:_)                   =  run_cli_check input_path
      dispatch_cli ("compile":input_path:"-o":output_rgc:_) =  run_cli_compile input_path output_rgc
      dispatch_cli ("compile":input_path:_)                 =  run_cli_compile input_path "{input_path}c"
      dispatch_cli ("build":input_path:"-o":output_bin:_)   =  run_cli_build input_path output_bin
      dispatch_cli ("build":input_path:_)                   =  run_cli_build input_path "a.out"
      dispatch_cli _                                        =  run_self_hosted_pipeline_demo

fn :: main => ()
      main =
        args = strip_runner_args cli_args
        dispatch_cli args
