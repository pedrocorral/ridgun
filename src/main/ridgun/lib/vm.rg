-- ============================================================
-- src/main/ridgun/vm.rg
-- Self-Hosted Ridgun Bytecode Virtual Machine in Ridgun
-- ============================================================
import ast
import lexer
import parser
import analyzer
import compiler

fn :: fetch_rinstr [RInstr] Int => RInstr
      fetch_rinstr (ins:_)  0   =  ins
      fetch_rinstr (_:rest) n   =  fetch_rinstr rest (n - 1)
      fetch_rinstr []       _   =  BReturn

fn :: get_local_val [Int]  Int => Int
      get_local_val (x:_)  0   =  x
      get_local_val (_:xs) n   =  get_local_val xs (n - 1)
      get_local_val []     _   =  0

fn :: set_local_val [Int]  Int Int => [Int]
      set_local_val (_:xs) 0   val =  [val] :: xs
      set_local_val []     0   val =  [val]
      set_local_val (x:xs) idx val =  [x] :: (set_local_val xs (idx - 1) val)
      set_local_val []     idx val =  [0] :: (set_local_val [] (idx - 1) val)

fn :: rstack_top [Int] => Int
      rstack_top (x:_) =  x
      rstack_top []    =  0

fn :: rstack_pop [Int]  => [Int]
      rstack_pop (_:xs) =  xs
      rstack_pop []     =  []

fn :: pop_n_args [Int]  Int [Int] => ([Int], [Int])
      pop_n_args stack  0   acc   =  (acc, stack)
      pop_n_args (x:xs) n   acc   =  pop_n_args xs (n - 1) ([x] :: acc)
      pop_n_args []     _   acc   =  (acc, [])

fn :: bool_to_rint Bool  => Int
      bool_to_rint True  =  1
      bool_to_rint False =  0

fn :: find_compiled_fn [RCompiledFn] String => RCompiledFn
      find_compiled_fn []            name   =  CompiledFn name 0 [BReturn]
      find_compiled_fn ((CompiledFn fname arity code):rest) target
        | fname == target = CompiledFn fname arity code
        | otherwise = find_compiled_fn rest target

fn :: vm_exec_fn [RCompiledFn] [RInstr] Int [Int] [Int] => Int
      vm_exec_fn fns code ip locals stack =
        ins = fetch_rinstr code ip
        vm_step_instr fns code ins ip locals stack

fn :: vm_step_instr [RCompiledFn] [RInstr] RInstr Int [Int] [Int] => Int
      vm_step_instr fns code (BPushInt n) ip locals stack =
        vm_exec_fn fns code (ip + 1) locals ([n] :: stack)
      vm_step_instr fns code (BPushBool b) ip locals stack =
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint b] :: stack)
      vm_step_instr fns code BPushUnit ip locals stack =
        vm_exec_fn fns code (ip + 1) locals ([0] :: stack)
      vm_step_instr fns code (BLoadLocal slot) ip locals stack =
        v = get_local_val locals slot
        vm_exec_fn fns code (ip + 1) locals ([v] :: stack)
      vm_step_instr fns code (BStoreLocal slot) ip locals stack =
        v = rstack_top stack
        s1 = rstack_pop stack
        new_locals = set_local_val locals slot v
        vm_exec_fn fns code (ip + 1) new_locals s1
      vm_step_instr fns code BPop ip locals stack =
        vm_exec_fn fns code (ip + 1) locals (rstack_pop stack)
      vm_step_instr fns code BAdd ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([a + b] :: s2)
      vm_step_instr fns code BSub ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([a - b] :: s2)
      vm_step_instr fns code BMul ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([a * b] :: s2)
      vm_step_instr fns code BDiv ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([a / b] :: s2)
      vm_step_instr fns code BMod ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([a % b] :: s2)
      vm_step_instr fns code BCmpEq ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a == b)] :: s2)
      vm_step_instr fns code BCmpNeq ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a != b)] :: s2)
      vm_step_instr fns code BCmpGt ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a > b)] :: s2)
      vm_step_instr fns code BCmpLt ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a < b)] :: s2)
      vm_step_instr fns code BCmpGtEq ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a >= b)] :: s2)
      vm_step_instr fns code BCmpLtEq ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_exec_fn fns code (ip + 1) locals ([bool_to_rint (a <= b)] :: s2)
      vm_step_instr fns code (BJump target_ip) _ locals stack =
        vm_exec_fn fns code target_ip locals stack
      vm_step_instr fns code (BJumpIfFalse target_ip) ip locals stack =
        cond = rstack_top stack
        s1 = rstack_pop stack
        vm_branch_false fns code ip target_ip cond locals s1
      vm_step_instr fns code (BJumpIfNeq target_ip) ip locals stack =
        b = rstack_top stack
        s1 = rstack_pop stack
        a = rstack_top s1
        s2 = rstack_pop s1
        vm_branch_neq fns code ip target_ip a b locals s2
      vm_step_instr fns code (BCall callee argc) ip locals stack =
        pop_res = pop_n_args stack argc []
        vm_invoke_callee fns code (ip + 1) locals callee pop_res
      vm_step_instr _ _ BReturn _ _ stack =
        rstack_top stack
      vm_step_instr fns code _ ip locals stack =
        vm_exec_fn fns code (ip + 1) locals stack

fn :: vm_branch_false [RCompiledFn] [RInstr] Int Int Int [Int] [Int] => Int
      vm_branch_false fns code _ target_ip 0 locals stack =
        vm_exec_fn fns code target_ip locals stack
      vm_branch_false fns code ip _ _ locals stack =
        vm_exec_fn fns code (ip + 1) locals stack

fn :: vm_branch_neq [RCompiledFn] [RInstr] Int Int Int Int [Int] [Int] => Int
      vm_branch_neq fns code ip target_ip a b locals stack
        | a == b = vm_exec_fn fns code (ip + 1) locals stack
        | otherwise = vm_exec_fn fns code target_ip locals stack

fn :: vm_invoke_callee [RCompiledFn] [RInstr] Int [Int] String ([Int], [Int]) => Int
      vm_invoke_callee fns caller_code next_ip caller_locals callee (call_args, rest_stack) =
        target_fn = find_compiled_fn fns callee
        ret_val = vm_run_compiled_fn fns target_fn call_args
        vm_exec_fn fns caller_code next_ip caller_locals ([ret_val] :: rest_stack)

fn :: vm_run_compiled_fn [RCompiledFn] RCompiledFn [Int]     => Int
      vm_run_compiled_fn fns           (CompiledFn _ _ callee_code) call_args =
        vm_exec_fn fns callee_code 0 call_args []

fn :: vm_eval_prog RCompiledProg      String     [Int] => Int
      vm_eval_prog (CompiledProg fns) entry_name args  =
        entry_fn = find_compiled_fn fns entry_name
        vm_run_compiled_fn fns entry_fn args

fn :: eval_source_in_ridgun_vm String String     [Int] => Int
      eval_source_in_ridgun_vm src    entry_name args  =
        toks = tokenize_src src
        prog = parse_tokens toks
        compiled = compile_rprogram prog
        vm_eval_prog compiled entry_name args
