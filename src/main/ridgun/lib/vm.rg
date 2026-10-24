-- ============================================================
-- src/main/ridgun/vm.rg
-- Self-Hosted Ridgun Bytecode Virtual Machine in Ridgun
-- @implements FR-COMP-007
-- ============================================================
import ast
import lexer
import parser
import analyzer
import compiler

fn :: fetch rinstr [RInstr] Int => RInstr
      fetch rinstr (ins:_)  0   =  ins
      fetch rinstr (_:rest) n   =  fetch_rinstr rest (n - 1)
      fetch rinstr []       _   =  BReturn

fn :: get local val [Int]  Int => Int
      get local val (x:_)  0   =  x
      get local val (_:xs) n   =  get_local_val xs (n - 1)
      get local val []     _   =  0

fn :: set local val [Int] Int Int => [Int]
      set local val (_:xs) 0 val = [val] :: xs
      set local val [] 0 val = [val]
      set local val (x:xs) idx val = [x] :: (set_local_val xs (idx - 1) val)
      set local val [] idx val = [0] :: (set_local_val [] (idx - 1) val)

fn :: rstack top [Int] => Int
      rstack top (x:_) =  x
      rstack top []    =  0

fn :: rstack pop [Int]  => [Int]
      rstack pop (_:xs) =  xs
      rstack pop []     =  []

fn :: pop n args [Int] Int [Int] => [Int] [Int]
      pop n args stack 0 acc = (acc, stack)
      pop n args (x:xs) n acc = pop_n_args xs (n - 1) ([x] :: acc)
      pop n args [] _ acc = (acc, [])

fn :: bool to rint Bool  => Int
      bool to rint True  =  1
      bool to rint False =  0

fn :: find compiled fn [RCompiledFn] String => RCompiledFn
      find compiled fn []            name   =  CompiledFn name 0 [BReturn]
      find compiled fn ((CompiledFn fname arity code):rest) target
        | fname == target = CompiledFn fname arity code
        | otherwise = find_compiled_fn rest target

fn :: vm exec fn [RCompiledFn] [RInstr] Int [Int] [Int] => Int
      vm exec fn fns code ip locals stack =
        ins = fetch_rinstr code ip
        vm_step_instr fns code ins ip locals stack

fn :: vm step instr [RCompiledFn] [RInstr] RInstr Int [Int] [Int] => Int
      vm step instr fns code (BPushInt n) ip locals stack =
        vm_exec_fn fns code (ip + 1) locals ([n] :: stack)
      vm step instr fns code (BPushBool b) ip locals stack =
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint b] :: stack)
      vm step instr fns code BPushUnit ip locals stack =
        vm_exec_fn fns code (ip + 1) locals ([0] :: stack)
      vm step instr fns code (BLoadLocal slot) ip locals stack =
        v = get_local_val locals slot
        vm_exec_fn fns code (ip + 1) locals ([v] :: stack)
      vm step instr fns code (BStoreLocal slot) ip locals stack =
        v = rstack_top stack
        s1 = rstack_pop stack
        new_locals = set_local_val locals slot v
        vm_exec_fn fns code (ip + 1) new_locals s1
      vm step instr fns code BPop ip locals stack =
        vm_exec_fn fns code (ip + 1) locals (rstack_pop stack)
      vm step instr fns code BAdd ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([a + b] :: s2)
      vm step instr fns code BSub ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([a - b] :: s2)
      vm step instr fns code BMul ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([a * b] :: s2)
      vm step instr fns code BDiv ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([a / b] :: s2)
      vm step instr fns code BMod ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([a % b] :: s2)
      vm step instr fns code BCmpEq ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a == b)] :: s2)
      vm step instr fns code BCmpNeq ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a != b)] :: s2)
      vm step instr fns code BCmpGt ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a > b)] :: s2)
      vm step instr fns code BCmpLt ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a < b)] :: s2)
      vm step instr fns code BCmpGtEq ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a >= b)] :: s2)
      vm step instr fns code BCmpLtEq ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a <= b)] :: s2)
      vm step instr fns code (BJump target_ip) _ locals stack =
        vm_exec_fn fns code target_ip locals stack
      vm step instr fns code (BJumpIfFalse target_ip) ip locals stack =
        cond = rstack_top stack
        s1 = rstack_pop stack
        vm_branch_false fns code ip target_ip cond locals s1
      vm step instr fns code (BJumpIfNeq target_ip) ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_branch_neq fns code ip target_ip a b locals s2
      vm step instr fns code (BPushCtx _) ip locals stack =
        vm_exec_fn fns code (ip + 1) locals (rstack_pop stack)
      vm step instr fns code (BCall callee argc) ip locals stack =
        pop_res = pop_n_args stack argc []
        vm_invoke_callee fns code (ip + 1) locals callee pop_res
      vm step instr _ _ BReturn _ _ stack =
        rstack_top stack
      vm step instr fns code _ ip locals stack =
        vm_exec_fn fns code (ip + 1) locals stack

fn :: vm branch false [RCompiledFn] [RInstr] Int Int Int [Int] [Int] => Int
      vm branch false fns code _ target_ip 0 locals stack =
        vm_exec_fn fns code target_ip locals stack
      vm branch false fns code ip _ _ locals stack =
        vm_exec_fn fns code (ip + 1) locals stack

fn :: vm branch neq [RCompiledFn] [RInstr] Int Int Int Int [Int] [Int] => Int
      vm branch neq fns code ip target_ip a b locals stack
        | a == b = vm_exec_fn fns code (ip + 1) locals stack
        | otherwise = vm_exec_fn fns code target_ip locals stack

fn :: vm invoke callee [RCompiledFn] [RInstr] Int [Int] String ([Int], [Int]) => Int
      vm invoke callee fns caller_code next_ip caller_locals callee (call_args, rest_stack) =
        target_fn = find_compiled_fn fns callee
        ret_val = vm_run_compiled_fn fns target_fn call_args
        vm_exec_fn fns caller_code next_ip caller_locals ([ret_val] :: rest_stack)

fn :: vm run compiled fn [RCompiledFn] RCompiledFn [Int] => Int
      vm run compiled fn fns (CompiledFn _ _ callee_code) call_args =
        vm_exec_fn fns callee_code 0 call_args []

fn :: vm eval prog RCompiledProg String [Int] => Int
      vm eval prog (CompiledProg fns) entry_name args =
        entry_fn = find_compiled_fn fns entry_name
        vm_run_compiled_fn fns entry_fn args

fn :: eval source in ridgun vm String String [Int] => Int
      eval source in ridgun vm src entry_name args =
        toks = tokenize_src src
        prog = parse_tokens toks
        compiled = compile_rprogram prog
        vm_eval_prog compiled entry_name args
