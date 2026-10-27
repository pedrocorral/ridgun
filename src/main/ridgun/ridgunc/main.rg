-- ============================================================
-- src/main/ridgun/ridgunc/main.rg
-- Self-Hosted Ridgun Compiler CLI Driver (ridgunc v0.9.24)
-- Shared Library (`src/main/ridgun/lib/`): ast.rg, lexer.rg,
-- parser.rg, analyzer.rg, typecheck.rg, compiler.rg, vm.rg,
-- elf64.rg, x86_64.rg, arm64.rg, llvm.rg
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

fn :: strip runner args [String] => [String]
      strip runner args []       =  []
      strip runner args (_:rest) =  strip script prefix rest

fn :: strip script prefix [String]     => [String]
      strip script prefix []           =  []
      strip script prefix ("run":script:rest)
        | (str contains script "ridgunc.rg") OR (str contains script "ridgunc/main.rg") = rest
        | otherwise = ["run", script] :: rest
      strip script prefix (first:rest)
        | (str contains first "ridgunc.rg") OR (str contains first "ridgunc/main.rg") = rest
        | otherwise = [first] :: rest

fn :: print error lines [String]    => ()
      print error lines []          =  ()
      print error lines (line:rest) =
        echo line
        print error lines rest

fn :: has strict flag [String]       => Bool
      has strict flag []             =  False
      has strict flag ("--strict":_) =  True
      has strict flag (_:rest)       =  has strict flag rest

fn :: strip strict flag [String]          => [String]
      strip strict flag []                =  []
      strip strict flag ("--strict":rest) =  strip strict flag rest
      strip strict flag (x:rest)          =  [x] :: (strip strict flag rest)

fn :: verify strict source String     [RTypeError] => ()
      verify strict source _          []           =  ()
      verify strict source input_path s_errs       =
        s_errs -> type err count -> err_c
        s_errs -> format type errors -> print error lines
        echo "[ridgunc --strict] {input_path}: {err_c} strict mode error(s) found."
        sys exit 1

fn :: verify strict if enabled Bool String => ()
      verify strict if enabled False _ = ()
      verify strict if enabled True input_path =
        input_path -> load rg with libs -> tokenize src -> check strict tokens -> verify strict source input_path _

fn :: run cli check Bool        String     => ()
      run cli check strict_mode input_path =
        input_path -> load rg with libs -> run cli check loaded strict_mode input_path _

fn :: strict check errors Bool  [RToken] => [RTypeError]
      strict check errors False _        =  []
      strict check errors True  toks     =  check strict tokens toks

fn :: run cli check loaded Bool String String => ()
      run cli check loaded _ input_path "" =
        echo "[ridgunc check] Error: empty or missing source file: {input_path}"
        sys exit 1
      run cli check loaded strict_mode input_path raw_src =
        raw_src -> tokenize src -> toks
        toks -> parse tokens -> prog
        errs = (typecheck program prog) :: (strict check errors strict_mode toks)
        report check result input_path prog errs

fn :: report check result String RProgram [RTypeError] => ()
      report check result input_path prog []
        | ((count fn defs prog) == 0) AND ((count type defs prog) == 0) =
          echo "[ridgunc check] {input_path}: Error: 0 function(s), 0 type(s) found."
          sys exit 1
        | otherwise =
          prog -> count fn defs -> fn_c
          prog -> count type defs -> ty_c
          prog -> analyze rprogram -> summaries
          echo "[ridgunc check] {input_path}: {fn_c} function(s), {ty_c} type(s)"
          echo "[ridgunc check] Type checking & static analysis passed — 0 error(s)."
          echo "[ridgunc check] Static strategies:" summaries
      report check result input_path _ errs =
        errs -> type err count -> err_c
        errs -> format type errors -> print error lines
        echo "[ridgunc check] {input_path}: {err_c} error(s) found."
        sys exit 1

fn :: run cli compile Bool String String => ()
      run cli compile strict_mode input_path output_rgc =
        verify strict if enabled strict_mode input_path
        emit rgc file input_path output_rgc -> fn_c
        report compile status input_path output_rgc fn_c

fn :: report compile status String String Int => ()
      report compile status input_path output_rgc fn_c
        | fn_c >= 0 =
          echo "[ridgunc compile] {input_path} -> {output_rgc} ({fn_c} functions)"
        | otherwise =
          echo "[ridgunc compile] Failed to compile {input_path}"
          sys exit 1

fn :: str ends with suffix String String => Bool
      str ends with suffix s suf =
        slen = str len s
        suflen = str len suf
        slen >= suflen AND (str slice s (slen - suflen) slen) == suf

fn :: strip rg ext String => String
      strip rg ext path
        | str ends with suffix path ".rg" = str slice path 0 ((str len path) - 3)
        | otherwise = path

fn :: run cli build lib Bool String String String => ()
      run cli build lib strict_mode input_path output_out target_arch
        | str ends with suffix output_out ".so" =
          verify strict if enabled strict_mode input_path
          build native target so library input_path output_out target_arch -> report so status input_path output_out _
        | str ends with suffix output_out ".rglib" =
          verify strict if enabled strict_mode input_path
          emit rglib file input_path output_out -> report rglib status input_path output_out _
        | otherwise =
          verify strict if enabled strict_mode input_path
          rglib_out = output_out + ".rglib"
          so_out = output_out + ".so"
          emit rglib file input_path rglib_out -> report rglib status input_path rglib_out _
          build native target so library input_path so_out target_arch -> report so status input_path so_out _

fn :: run cli build so Bool String String String => ()
      run cli build so strict_mode input_path output_so target_arch =
        verify strict if enabled strict_mode input_path
        build native target so library input_path output_so target_arch -> status
        report so status input_path output_so status

fn :: report rglib status String String Int => ()
      report rglib status input_path output_lib 0 =
        echo "[ridgunc build --lib] Ridgun library bundle created: {input_path} -> {output_lib}"
      report rglib status _ output_lib code =
        echo "[ridgunc build --lib] Failed to build {output_lib} (exit code {code})"
        sys exit 1

fn :: report so status String String Int => ()
      report so status input_path output_so 0 =
        echo "[ridgunc build --so] Native ELF64 shared library (.so) created: {input_path} -> {output_so}"
      report so status _ output_so code =
        echo "[ridgunc build --so] Failed to build {output_so} (exit code {code})"
        sys exit 1

fn :: run cli build Bool String String => ()
      run cli build strict_mode input_path output_bin =
        verify strict if enabled strict_mode input_path
        build native executable input_path output_bin -> status
        report build status input_path output_bin status

fn :: run cli build target Bool String String String => ()
      run cli build target strict_mode input_path output_bin target_arch =
        verify strict if enabled strict_mode input_path
        build native target executable input_path output_bin target_arch -> status
        report build status input_path output_bin status

fn :: report build status String String Int => ()
      report build status input_path output_bin 0 =
        echo "[ridgunc build] Native ELF executable created: {input_path} -> {output_bin}"
      report build status _ output_bin code =
        echo "[ridgunc build] Failed to build {output_bin} (exit code {code})"
        sys exit 1

fn :: quote shell args [String] => String
      quote shell args []       =  ""
      quote shell args (a:as)   =  " \"" + a + "\"" + (quote shell args as)

fn :: run cli run Bool        String     [String] => ()
      run cli run strict_mode input_path run_args =
        verify strict if enabled strict_mode input_path
        sys mkdir "target" 493
        build native fast executable input_path "target/.ridgunc_run_bin" -> status
        exec built run status (quote shell args run_args)

fn :: exec built run Int String => ()
      exec built run 0   q_args =
        shell exec ("./target/.ridgunc_run_bin" + q_args + "; _st=$?; rm -f target/.ridgunc_run_bin; exit $_st") -> code
        sys exit code
      exec built run _   _      =  sys exit 1

fn :: run self hosted pipeline demo => ()
      run self hosted pipeline demo =
        sample_src = "fn :: fact Int => Int\nfact 0 = 1\nfact n = n * (fact (n - 1))\n\nfn :: fib Int => Int\nfib 0 = 0\nfib 1 = 1\nfib n = (fib (n - 1)) + (fib (n - 2))\n\nfn :: compute Int => Int\ncompute x =\n  a = fact x\n  b = fib 10\n  a + b\n"
        sample_src -> tokenize src -> toks
        toks -> parse tokens -> prog
        prog -> typecheck program -> errs
        prog -> analyze rprogram -> strats
        eval source in ridgun vm sample_src "fact" [6] -> r_fact6
        eval source in ridgun vm sample_src "fib" [10] -> r_fib10
        eval source in ridgun vm sample_src "compute" [5] -> r_comp5
        echo "=== Self-Hosted Ridgun Compiler (ridgunc.rg) ==="
        echo "Tokens lexed        =>" (count tokens toks)
        echo "Functions parsed    =>" (count fn defs prog)
        echo "Typecheck errors    =>" (type err count errs)
        echo "Static strategies   =>" strats
        echo "VM eval fact(6)     =>" r_fact6
        echo "VM eval fib(10)     =>" r_fib10
        echo "VM eval compute(5)  =>" r_comp5

fn :: run cli version => ()
      run cli version =
        echo "ridgunc 0.9.24 (self-hosted Ridgun compiler, x86_64-unknown-linux-gnu)"

fn :: run cli help => ()
      run cli help =
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

fn :: dispatch cli Bool        [String]        => ()
      dispatch cli _           []              =  run self hosted pipeline demo
      dispatch cli _           ("version":_)   =  run cli version
      dispatch cli _           ("-v":_)        =  run cli version
      dispatch cli _           ("--version":_) =  run cli version
      dispatch cli _           ("help":_)      =  run cli help
      dispatch cli _           ("-h":_)        =  run cli help
      dispatch cli _           ("--help":_)    =  run cli help
      dispatch cli strict_mode ("run":input_path:run_args) = run cli run strict_mode input_path run_args
      dispatch cli strict_mode ("check":input_path:_) = run cli check strict_mode input_path
      dispatch cli strict_mode ("compile":input_path:"-o":output_rgc:_) = run cli compile strict_mode input_path output_rgc
      dispatch cli strict_mode ("compile":input_path:_) = run cli compile strict_mode input_path "{input_path}c"
      dispatch cli strict_mode ("build":"--lib":"--target":target_arch:input_path:"-o":output_out:_) = run cli build lib strict_mode input_path output_out target_arch
      dispatch cli strict_mode ("build":"--lib":input_path:"-o":output_out:"--target":target_arch:_) = run cli build lib strict_mode input_path output_out target_arch
      dispatch cli strict_mode ("build":"--lib":input_path:"-o":output_out:_) = run cli build lib strict_mode input_path output_out "x86_64-linux"
      dispatch cli strict_mode ("build":"--lib":input_path:_) = run cli build lib strict_mode input_path (strip rg ext input_path) "x86_64-linux"
      dispatch cli strict_mode ("build":input_path:"--lib":"-o":output_out:_) = run cli build lib strict_mode input_path output_out "x86_64-linux"
      dispatch cli strict_mode ("build":input_path:"--lib":_) = run cli build lib strict_mode input_path (strip rg ext input_path) "x86_64-linux"
      dispatch cli strict_mode ("build":"--so":"--target":target_arch:input_path:"-o":output_so:_) = run cli build so strict_mode input_path output_so target_arch
      dispatch cli strict_mode ("build":"--so":input_path:"-o":output_so:"--target":target_arch:_) = run cli build so strict_mode input_path output_so target_arch
      dispatch cli strict_mode ("build":"--so":input_path:"-o":output_so:_) = run cli build so strict_mode input_path output_so "x86_64-linux"
      dispatch cli strict_mode ("build":"--so":input_path:_) = run cli build so strict_mode input_path ((strip rg ext input_path) + ".so") "x86_64-linux"
      dispatch cli strict_mode ("build":input_path:"--so":"-o":output_so:"--target":target_arch:_) = run cli build so strict_mode input_path output_so target_arch
      dispatch cli strict_mode ("build":input_path:"--so":"-o":output_so:_) = run cli build so strict_mode input_path output_so "x86_64-linux"
      dispatch cli strict_mode ("build":input_path:"--so":_) = run cli build so strict_mode input_path ((strip rg ext input_path) + ".so") "x86_64-linux"
      dispatch cli strict_mode ("build":"--target":target_arch:input_path:"-o":output_bin:_) = run cli build target strict_mode input_path output_bin target_arch
      dispatch cli strict_mode ("build":"--target":target_arch:input_path:_) = run cli build target strict_mode input_path "a.out" target_arch
      dispatch cli strict_mode ("build":input_path:"-o":output_bin:"--target":target_arch:_) = run cli build target strict_mode input_path output_bin target_arch
      dispatch cli strict_mode ("build":input_path:"--target":target_arch:"-o":output_bin:_) = run cli build target strict_mode input_path output_bin target_arch
      dispatch cli strict_mode ("build":input_path:"--target":target_arch:_) = run cli build target strict_mode input_path "a.out" target_arch
      dispatch cli strict_mode ("build":input_path:"-o":output_bin:_) = run cli build strict_mode input_path output_bin
      dispatch cli strict_mode ("build":input_path:_) = run cli build strict_mode input_path "a.out"
      dispatch cli _           _               =  run self hosted pipeline demo

fn :: main => ()
      main =
        args = strip runner args cli args
        strict_mode = has strict flag args
        clean_args = strip strict flag args
        dispatch cli strict_mode clean_args
