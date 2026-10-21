-- ============================================================
-- src/main/ridgun/compiler.rg
-- Self-Hosted Ridgun AST-to-Bytecode & Native AOT Compiler
-- Full Ridgun v0.9.0 Spec: Sum & Record ADTs, Operator Overloading,
-- Variadics, Sequences/Masks/FlatJoin, Tensors/Einsum/Hadamard,
-- Where-DAGs, ParPipes, Channels/Spawn/Join, Scoped Globals/Context/
-- Shared Atomics, and Bare-Metal Hardware MMIO & Region Quotas.
-- @implements FR-COMP-001
-- @implements FR-COMP-006
-- @implements FR-VM-001
-- @implements FR-VM-002
-- ============================================================
import ast
import lexer
import parser
import analyzer
import typecheck
import elf64
import x86_64
import arm64

-- ── Local Variable Table Helpers ────────────────────────────

fn :: list_str_len [String] => Int
      list_str_len []       =  0
      list_str_len (_:xs)   =  1 + (list_str_len xs)

fn :: pat_list_len [RPattern] => Int
      pat_list_len []         =  0
      pat_list_len (_:xs)     =  1 + (pat_list_len xs)

fn :: find_local_idx [String] String Int => Int
      find_local_idx []       _      _   =  -1
      find_local_idx (x:xs)   target idx
        | x == target = idx
        | otherwise = find_local_idx xs target (idx + 1)

fn :: lookup_local [String] String => Int
      lookup_local locals   name   =  find_local_idx locals name 0

fn :: ensure_local [String] String => ([String], Int)
      ensure_local locals   name   =
        existing = lookup_local locals name
        ensure_local_branch locals name existing

fn :: ensure_local_branch [String] String Int      => ([String], Int)
      ensure_local_branch locals   name   existing
        | existing >= 0 = (locals, existing)
        | otherwise = (locals :: [name], list_str_len locals)

fn :: rinstr_len [RInstr] => Int
      rinstr_len []       =  0
      rinstr_len (_:xs)   =  1 + (rinstr_len xs)

-- ── Pattern Binding & Match Emission (Bytecode) ─────────────

fn :: bind_pat_vars [RPattern]      Int [String] => [String]
      bind_pat_vars []              _   locals   =  locals
      bind_pat_vars ((PatVar v):ps) idx locals   =
        bind_pat_vars ps (idx + 1) (locals :: [v])
      bind_pat_vars ((PatSeqBind v):ps) idx locals =
        bind_pat_vars ps (idx + 1) (locals :: [v])
      bind_pat_vars (_:ps)          idx locals   =
        bind_pat_vars ps (idx + 1) (locals :: ['_arg_' + (int_to_str idx)])

fn :: emit_pat_checks [RPattern]       Int  Int     => [RInstr]
      emit_pat_checks []               _    _       =  []
      emit_pat_checks ((PatInt n):ps)  slot fail_ip =
        [BLoadLocal slot, BPushInt n, BJumpIfNeq fail_ip] :: (emit_pat_checks ps (slot + 1) fail_ip)
      emit_pat_checks ((PatReal r):ps) slot fail_ip =
        [BLoadLocal slot, BPushReal r, BJumpIfNeq fail_ip] :: (emit_pat_checks ps (slot + 1) fail_ip)
      emit_pat_checks ((PatStr s):ps)  slot fail_ip =
        [BLoadLocal slot, BPushStr s, BJumpIfNeq fail_ip] :: (emit_pat_checks ps (slot + 1) fail_ip)
      emit_pat_checks ((PatBool b):ps) slot fail_ip =
        [BLoadLocal slot, BPushBool b, BJumpIfNeq fail_ip] :: (emit_pat_checks ps (slot + 1) fail_ip)
      emit_pat_checks (PatEmpty:ps)    slot fail_ip =
        [BLoadLocal slot, BJumpIfNotEmpty fail_ip] :: (emit_pat_checks ps (slot + 1) fail_ip)
      emit_pat_checks (_:ps)           slot fail_ip =
        emit_pat_checks ps (slot + 1) fail_ip

-- ── Expression Lowering to [RInstr] ─────────────────────────

fn :: compile_binop RBinOp     => RInstr
      compile_binop OpAdd      =  BAdd
      compile_binop OpSub      =  BSub
      compile_binop OpMul      =  BMul
      compile_binop OpDiv      =  BDiv
      compile_binop OpMod      =  BMod
      compile_binop OpEq       =  BCmpEq
      compile_binop OpNeq      =  BCmpNeq
      compile_binop OpGt       =  BCmpGt
      compile_binop OpLt       =  BCmpLt
      compile_binop OpGtEq     =  BCmpGtEq
      compile_binop OpLtEq     =  BCmpLtEq
      compile_binop OpAnd      =  BAnd
      compile_binop OpOr       =  BOr
      compile_binop OpXor      =  BXor
      compile_binop OpConcat   =  BListConcat 2
      compile_binop OpFlatJoin =  BSeqFlatJoin
      compile_binop OpMatMul   =  BMul

fn :: compile_rexpr RExpr              [String] => ([RInstr], [String])
      compile_rexpr (EInt n)           locals   =  ([BPushInt n], locals)
      compile_rexpr (EReal r)          locals   =  ([BPushReal r], locals)
      compile_rexpr (EStr s)           locals   =  ([BPushStr s], locals)
      compile_rexpr (EStrInterp parts) locals   =
        p_res = compile_rexpr_list parts locals
        append_instr (BStrInterp (rexpr_list_len parts)) p_res
      compile_rexpr (EBool b)          locals   =  ([BPushBool b], locals)
      compile_rexpr EUnit              locals   =  ([BPushUnit], locals)
      compile_rexpr (EVar name)        locals   =
        idx = lookup_local locals name
        compile_var_lookup name idx locals
      compile_rexpr (ENot inner)       locals   =
        r1 = compile_rexpr inner locals
        append_instr BNot r1
      compile_rexpr (EOut inner)       locals   =
        r1 = compile_rexpr inner locals
        append_instr BOut r1
      compile_rexpr (EBin bop l r)     locals   =
        r1 = compile_rexpr l locals
        compile_bin_rhs bop r r1
      compile_rexpr (ECall fname args) locals   =
        args_res = compile_rexpr_list args locals
        append_instr (BCall fname (rexpr_list_len args)) args_res
      compile_rexpr (EEcho args)       locals   =
        args_res = compile_rexpr_list args locals
        append_instr (BEcho (rexpr_list_len args)) args_res
      compile_rexpr (EList elems)      locals   =
        elems_res = compile_rexpr_list elems locals
        append_instr (BListConcat (rexpr_list_len elems)) elems_res
      compile_rexpr (ETuple elems)     locals   =
        elems_res = compile_rexpr_list elems locals
        append_instr (BMakeTuple (rexpr_list_len elems)) elems_res
      compile_rexpr (ETensor elems)    locals   =
        elems_res = compile_rexpr_list elems locals
        append_instr (BMakeTensor (rexpr_list_len elems)) elems_res
      compile_rexpr (EEinsum es subs)  locals   =
        es_res = compile_rexpr_list es locals
        append_instr (BTensorEinsum subs) es_res
      compile_rexpr (EHadamard bop l s1 r s2) locals =
        r1 = compile_rexpr l locals
        r2 = compile_rexpr_after r r1
        append_instr (BTensorHadamard bop s1 s2) r2
      compile_rexpr (EIndex base idxs) locals   =
        b_res = compile_rexpr base locals
        i_res = compile_rexpr_list_after idxs b_res
        append_instr (BTensorGet (rexpr_list_len idxs)) i_res
      compile_rexpr (EIndexAssign target idxs val_e) locals =
        slot_res = ensure_local locals target
        compile_index_assign_bc slot_res idxs val_e
      compile_rexpr (ESeqSelect base mask) locals =
        b_res = compile_rexpr base locals
        append_instr (BSeqSelectMask mask) b_res
      compile_rexpr (EBlock stmts)     locals   =
        compile_rblock stmts locals
      compile_rexpr (EGuard guards)    locals   =
        compile_rguard_expr guards locals
      compile_rexpr (EWhere body binds) locals  =
        w_res = compile_where_list binds locals
        compile_where_body body w_res
      compile_rexpr (EParPipe branches) locals  =
        b_res = compile_rexpr_list branches locals
        append_instr (BMakeTuple (rexpr_list_len branches)) b_res
      compile_rexpr (EWithCtx ctx_name val_e body) locals =
        v_res = compile_rexpr val_e locals
        v_push = append_instr (BPushCtx ctx_name) v_res
        b_res = compile_rexpr_after body v_push
        append_instr (BPopCtx ctx_name) b_res
      compile_rexpr (EWithRegion quota body) locals =
        b_res = compile_rexpr body locals
        wrap_region_bc quota b_res
      compile_rexpr (EAtomicUpdate var_name val_e) locals =
        v_res = compile_rexpr val_e locals
        append_instr (BAtomicStore var_name) v_res
      compile_rexpr (ELoadContext ctx_name def_e) locals =
        d_res = compile_rexpr def_e locals
        append_instr (BLoadCtx ctx_name) d_res
      compile_rexpr (ELoadShared var_name def_e) locals =
        d_res = compile_rexpr def_e locals
        append_instr (BLoadShared var_name) d_res

fn :: compile_rexpr_after RExpr ([RInstr], [String]) => ([RInstr], [String])
      compile_rexpr_after e     (c1, locals1)        =
        r2 = compile_rexpr e locals1
        merge_code_pair c1 r2

fn :: compile_rexpr_list_after [RExpr] ([RInstr], [String]) => ([RInstr], [String])
      compile_rexpr_list_after es (c1, locals1) =
        r2 = compile_rexpr_list es locals1
        merge_code_pair c1 r2

fn :: compile_index_assign_bc ([String], Int) [RExpr] RExpr => ([RInstr], [String])
      compile_index_assign_bc (locals1, slot) idxs val_e =
        i_res = compile_rexpr_list idxs locals1
        v_res = compile_rexpr_after val_e i_res
        finish_index_assign_bc slot (rexpr_list_len idxs) v_res

fn :: finish_index_assign_bc Int Int ([RInstr], [String]) => ([RInstr], [String])
      finish_index_assign_bc slot ndim (code, locals2) =
        ([BLoadLocal slot] :: code :: [BTensorSet ndim, BStoreLocal slot, BPushUnit], locals2)

fn :: wrap_region_bc Int   ([RInstr], [String]) => ([RInstr], [String])
      wrap_region_bc quota (b_code, locals1)    =
        ([BEnterRegion quota] :: b_code :: [BExitRegion], locals1)

fn :: compile_var_lookup String Int [String] => ([RInstr], [String])
      compile_var_lookup name   idx locals
        | idx >= 0 = ([BLoadLocal idx], locals)
        | otherwise = ([BCall name 0], locals)

fn :: append_instr RInstr ([RInstr], [String]) => ([RInstr], [String])
      append_instr ins    (code, locals)       =  (code :: [ins], locals)

fn :: compile_bin_rhs RBinOp RExpr ([RInstr], [String]) => ([RInstr], [String])
      compile_bin_rhs bop    r     (l_code, locals1)    =
        r_res = compile_rexpr r locals1
        merge_bin_code (compile_binop bop) l_code r_res

fn :: merge_bin_code RInstr [RInstr] ([RInstr], [String]) => ([RInstr], [String])
      merge_bin_code ins l_code (r_code, locals2) =
        (l_code :: r_code :: [ins], locals2)

fn :: rexpr_list_len [RExpr] => Int
      rexpr_list_len []      =  0
      rexpr_list_len (_:xs)  =  1 + (rexpr_list_len xs)

fn :: compile_rexpr_list [RExpr] [String] => ([RInstr], [String])
      compile_rexpr_list []      locals   =  ([], locals)
      compile_rexpr_list (e:es)  locals   =
        r1 = compile_rexpr e locals
        compile_rexpr_list_cont es r1

fn :: compile_rexpr_list_cont [RExpr] ([RInstr], [String]) => ([RInstr], [String])
      compile_rexpr_list_cont es (c1, locals1) =
        r2 = compile_rexpr_list es locals1
        merge_code_pair c1 r2

fn :: merge_code_pair [RInstr] ([RInstr], [String]) => ([RInstr], [String])
      merge_code_pair c1       (c2, locals2)        =  (c1 :: c2, locals2)

fn :: compile_rguard_expr [RGuard] [String] => ([RInstr], [String])
      compile_rguard_expr []       locals   =  ([BPushUnit], locals)
      compile_rguard_expr ((GuardBranch _ body):[]) locals =
        compile_rexpr body locals
      compile_rguard_expr ((GuardBranch _ body):_) locals =
        compile_rexpr body locals

fn :: compile_rblock [RStmt]           [String] => ([RInstr], [String])
      compile_rblock []                locals   =  ([BPushUnit], locals)
      compile_rblock ((StmtExpr e):[]) locals   =  compile_rexpr e locals
      compile_rblock ((StmtLet v e):rest) locals =
        e_res = compile_rexpr e locals
        compile_rblock_after_let v rest e_res
      compile_rblock ((StmtMut v e):rest) locals =
        e_res = compile_rexpr e locals
        compile_rblock_after_let v rest e_res
      compile_rblock ((StmtAtomic v e):rest) locals =
        e_res = compile_rexpr (EAtomicUpdate v e) locals
        compile_rblock_after_expr rest e_res
      compile_rblock ((StmtIndexAssign t idxs e):rest) locals =
        e_res = compile_rexpr (EIndexAssign t idxs e) locals
        compile_rblock_after_expr rest e_res
      compile_rblock ((StmtExpr e):rest) locals =
        e_res = compile_rexpr e locals
        compile_rblock_after_expr rest e_res

fn :: compile_rblock_after_let String [RStmt] ([RInstr], [String]) => ([RInstr], [String])
      compile_rblock_after_let v rest (e_code, locals1) =
        slot_res = ensure_local locals1 v
        compile_rblock_store_let rest e_code slot_res

fn :: compile_rblock_store_let [RStmt] [RInstr] ([String], Int) => ([RInstr], [String])
      compile_rblock_store_let [] e_code (locals2, slot) =
        (e_code :: [BStoreLocal slot, BLoadLocal slot], locals2)
      compile_rblock_store_let rest e_code (locals2, slot) =
        r_more = compile_rblock rest locals2
        merge_code_pair (e_code :: [BStoreLocal slot]) r_more

fn :: compile_rblock_after_expr [RStmt] ([RInstr], [String]) => ([RInstr], [String])
      compile_rblock_after_expr [] (e_code, locals1) = (e_code, locals1)
      compile_rblock_after_expr rest (e_code, locals1) =
        r_more = compile_rblock rest locals1
        merge_code_pair (e_code :: [BPop]) r_more

fn :: compile_where_list [RWhereBind] [String] => ([RInstr], [String])
      compile_where_list []           locals   =  ([], locals)
      compile_where_list ((WhereBind e v _):wbs) locals =
        e_res = compile_rexpr e locals
        compile_where_list_step v wbs e_res

fn :: compile_where_list_step String [RWhereBind] ([RInstr], [String]) => ([RInstr], [String])
      compile_where_list_step v wbs (e_code, locals1) =
        slot_res = ensure_local locals1 v
        compile_where_store wbs e_code slot_res

fn :: compile_where_store [RWhereBind] [RInstr] ([String], Int) => ([RInstr], [String])
      compile_where_store wbs e_code (locals2, slot) =
        more = compile_where_list wbs locals2
        merge_code_pair (e_code :: [BStoreLocal slot]) more

fn :: compile_where_body RExpr ([RInstr], [String]) => ([RInstr], [String])
      compile_where_body body  (w_code, locals1)    =
        b_res = compile_rexpr body locals1
        merge_code_pair w_code b_res

-- ── Function & Case Lowering (Bytecode) ─────────────────────

fn :: compile_guards [RGuard] [String] Int     => [RInstr]
      compile_guards []       _        _       =  []
      compile_guards ((GuardBranch cond body):gs) locals base_ip =
        c_res = compile_rexpr cond locals
        b_res = compile_rexpr body locals
        emit_guard_branch gs locals base_ip c_res b_res

fn :: emit_guard_branch [RGuard] [String] Int ([RInstr], [String]) ([RInstr], [String]) => [RInstr]
      emit_guard_branch gs locals base_ip (c_code, _) (b_code, _) =
        next_guard_ip = base_ip + (rinstr_len c_code) + 1 + (rinstr_len b_code) + 1
        this_guard = c_code :: [BJumpIfFalse next_guard_ip] :: b_code :: [BReturn]
        this_guard :: (compile_guards gs locals next_guard_ip)

fn :: compile_single_case RFnCase Int     => [RInstr]
      compile_single_case (FnCase pats guards body) base_ip =
        locals = bind_pat_vars pats 0 []
        compile_case_inner pats guards body locals base_ip

fn :: compile_case_inner [RPattern] [RGuard] RExpr [String] Int => [RInstr]
      compile_case_inner pats [] body locals base_ip =
        b_res = compile_rexpr body locals
        finish_case_with_body pats base_ip b_res
      compile_case_inner pats guards _ locals base_ip =
        p_pre = emit_pat_checks pats 0 0
        g_code = compile_guards guards locals (base_ip + (rinstr_len p_pre))
        fail_ip = base_ip + (rinstr_len p_pre) + (rinstr_len g_code)
        p_checks = emit_pat_checks pats 0 fail_ip
        p_checks :: g_code

fn :: finish_case_with_body [RPattern] Int     ([RInstr], [String]) => [RInstr]
      finish_case_with_body pats       base_ip (b_code, _)          =
        p_pre = emit_pat_checks pats 0 0
        fail_ip = base_ip + (rinstr_len p_pre) + (rinstr_len b_code) + 1
        p_checks = emit_pat_checks pats 0 fail_ip
        p_checks :: b_code :: [BReturn]

fn :: compile_cases_seq [RFnCase] Int     => [RInstr]
      compile_cases_seq []        _       =  []
      compile_cases_seq (c:cs)    base_ip =
        c_code = compile_single_case c base_ip
        next_ip = base_ip + (rinstr_len c_code)
        c_code :: (compile_cases_seq cs next_ip)

fn :: compile_rfndef RFnDef => RCompiledFn
      compile_rfndef (FnDef name params _ cases) =
        arity = list_str_len params
        code = compile_cases_seq cases 0
        CompiledFn name arity code

fn :: compile_rfndef_list [RFnDef] => [RCompiledFn]
      compile_rfndef_list []       =  []
      compile_rfndef_list (f:fs)   =  [compile_rfndef f] :: (compile_rfndef_list fs)

fn :: compile_rprogram RProgram        => RCompiledProg
      compile_rprogram (Program fns _) =
        CompiledProg (compile_rfndef_list fns)

-- ── Pre-Codegen Normalization (Variadic Packing & Tuple-Chain Unpacking) ──

type RCgSig = CgSig String Int Bool

fn :: str_ends_with_dots String => Bool
      str_ends_with_dots s      =
        len = str_len s
        len > 3 AND (str_slice s (len - 3) len) == "..."

fn :: params_has_variadic [String] => Bool
      params_has_variadic []       =  False
      params_has_variadic (p:[])   =  str_ends_with_dots p
      params_has_variadic (_:ps)   =  params_has_variadic ps

fn :: infer_fndef_arity [String] [RFnCase] => Int
      infer_fndef_arity params   ((FnCase ((PatSeqBind _):[]) _ _):_) = list_str_len params
      infer_fndef_arity _        ((FnCase pats _ _):_) = pat_list_len pats
      infer_fndef_arity params   []        =  list_str_len params

fn :: build_cg_sigs [RFnDef] => [RCgSig]
      build_cg_sigs []       =  []
      build_cg_sigs ((FnDef name params _ cases):fs) =
        [CgSig name (infer_fndef_arity params cases) (params_has_variadic params)] :: (build_cg_sigs fs)

fn :: lookup_cg_sig [RCgSig] String => (Bool, Int, Bool)
      lookup_cg_sig []       _      =  (False, 0, False)
      lookup_cg_sig ((CgSig name arity is_var):rest) target
        | name == target = (True, arity, is_var)
        | otherwise = lookup_cg_sig rest target

fn :: prep_expr RExpr              [RCgSig] => RExpr
      prep_expr (ENot inner)       sigs     =  ENot (prep_expr inner sigs)
      prep_expr (EOut inner)       sigs     =  EOut (prep_expr inner sigs)
      prep_expr (EBin bop l r)     sigs     =  EBin bop (prep_expr l sigs) (prep_expr r sigs)
      prep_expr (ECall fname args) sigs     =
        p_args = prep_expr_list args sigs
        prep_call fname p_args (lookup_cg_sig sigs fname)
      prep_expr (EEcho args)       sigs     =  EEcho (prep_expr_list args sigs)
      prep_expr (EStrInterp parts) sigs     =  EStrInterp (prep_expr_list parts sigs)
      prep_expr (EList elems)      sigs     =  EList (prep_expr_list elems sigs)
      prep_expr (ETuple elems)     sigs     =  ETuple (prep_expr_list elems sigs)
      prep_expr (ETensor elems)    sigs     =  ETensor (prep_expr_list elems sigs)
      prep_expr (EEinsum es subs)  sigs     =  EEinsum (prep_expr_list es sigs) subs
      prep_expr (EHadamard bop l s1 r s2) sigs = EHadamard bop (prep_expr l sigs) s1 (prep_expr r sigs) s2
      prep_expr (EIndex base idxs) sigs     =  EIndex (prep_expr base sigs) (prep_expr_list idxs sigs)
      prep_expr (EIndexAssign t idxs v) sigs = EIndexAssign t (prep_expr_list idxs sigs) (prep_expr v sigs)
      prep_expr (ESeqSelect b m)   sigs     =  ESeqSelect (prep_expr b sigs) m
      prep_expr (EBlock stmts)     sigs     =  EBlock (prep_stmt_list stmts sigs)
      prep_expr (EGuard guards)    sigs     =  EGuard (prep_guard_list guards sigs)
      prep_expr (EWhere body binds) sigs    =  EWhere (prep_expr body sigs) (prep_where_list binds sigs)
      prep_expr (EParPipe branches) sigs    =  EParPipe (prep_expr_list branches sigs)
      prep_expr (EWithCtx c v b)   sigs     =  EWithCtx c (prep_expr v sigs) (prep_expr b sigs)
      prep_expr (EWithRegion q b)  sigs     =  EWithRegion q (prep_expr b sigs)
      prep_expr (EAtomicUpdate v e) sigs    =  EAtomicUpdate v (prep_expr e sigs)
      prep_expr (ELoadContext c e) sigs     =  ELoadContext c (prep_expr e sigs)
      prep_expr (ELoadShared v e)  sigs     =  ELoadShared v (prep_expr e sigs)
      prep_expr (EVar v)           sigs     =  prep_var v (lookup_cg_sig sigs v)
      prep_expr e                  _        =  e

fn :: prep_var String (Bool, Int, Bool) => RExpr
      prep_var v      (True, 0, False)  =  ECall v []
      prep_var v      _                 =  EVar v

fn :: prep_call String [RExpr]         (Bool, Int, Bool) => RExpr
      prep_call fname  args            (True, arity, True)
        | arity <= 1 = ECall fname [EList args]
        | otherwise = ECall fname ((take_exprs args (arity - 1)) :: [EList (drop_exprs args (arity - 1))])
      prep_call fname  (single_arg:[]) (True, 2, False)  =
        ECall "__unpack2__" [EVar fname, single_arg]
      prep_call fname  args            _                 =  ECall fname args

fn :: prep_expr_list [RExpr] [RCgSig] => [RExpr]
      prep_expr_list []      _        =  []
      prep_expr_list (e:es)  sigs     =  [prep_expr e sigs] :: (prep_expr_list es sigs)

fn :: prep_stmt_list [RStmt]            [RCgSig] => [RStmt]
      prep_stmt_list []                 _        =  []
      prep_stmt_list ((StmtLet v e):ss) sigs     =  [StmtLet v (prep_expr e sigs)] :: (prep_stmt_list ss sigs)
      prep_stmt_list ((StmtMut v e):ss) sigs     =  [StmtMut v (prep_expr e sigs)] :: (prep_stmt_list ss sigs)
      prep_stmt_list ((StmtExpr e):ss)  sigs     =  [StmtExpr (prep_expr e sigs)] :: (prep_stmt_list ss sigs)
      prep_stmt_list ((StmtAtomic v e):ss) sigs  =  [StmtAtomic v (prep_expr e sigs)] :: (prep_stmt_list ss sigs)
      prep_stmt_list ((StmtIndexAssign t idxs e):ss) sigs = [StmtIndexAssign t (prep_expr_list idxs sigs) (prep_expr e sigs)] :: (prep_stmt_list ss sigs)

fn :: prep_where_list [RWhereBind] [RCgSig] => [RWhereBind]
      prep_where_list []           _        =  []
      prep_where_list ((WhereBind e v idxs):wbs) sigs = [WhereBind (prep_expr e sigs) v idxs] :: (prep_where_list wbs sigs)

fn :: prep_guard_list [RGuard] [RCgSig] => [RGuard]
      prep_guard_list []       _        =  []
      prep_guard_list ((GuardBranch c b):gs) sigs = [GuardBranch (prep_expr c sigs) (prep_expr b sigs)] :: (prep_guard_list gs sigs)

fn :: prep_case_list [RFnCase] [RCgSig] => [RFnCase]
      prep_case_list []        _        =  []
      prep_case_list ((FnCase pats guards body):cs) sigs =
        [FnCase pats (prep_guard_list guards sigs) (prep_expr body sigs)] :: (prep_case_list cs sigs)

fn :: prep_fndef_list [RFnDef] [RCgSig] => [RFnDef]
      prep_fndef_list []       _        =  []
      prep_fndef_list ((FnDef name params ret_ty cases):fs) sigs =
        [FnDef name params ret_ty (prep_case_list cases sigs)] :: (prep_fndef_list fs sigs)

-- ── Pure-Ridgun Native IR Lowering (RProgram => RNativeProg) ──
-- @implements FR-COMP-002
-- @implements FR-COMP-004

type RStrEntry = StrEntry String Int Int

type RStrPool = StrPool String [RStrEntry]

type RFnEntry = FnEntry String Int Int

type RFieldEntry = FieldEntry String Int

type RNativeEnv = NativeEnv String Int [String] [RStrEntry] [RFnEntry] [RFieldEntry]

type RNativeCode = NativeCode [RNativeInstr] Int Int

fn :: nc_instrs RNativeCode => [RNativeInstr]
      nc_instrs (NativeCode instrs _ _) = instrs

fn :: nc_lbl RNativeCode => Int
      nc_lbl (NativeCode _ lbl _) = lbl

fn :: nc_max_sp RNativeCode => Int
      nc_max_sp (NativeCode _ _ msp) = msp

fn :: nc_set_lbl RNativeCode Int     => RNativeCode
      nc_set_lbl (NativeCode instrs _ msp) new_lbl = NativeCode instrs new_lbl msp

fn :: nc_emit RNativeCode RNativeInstr Int     => RNativeCode
      nc_emit (NativeCode instrs lbl msp) ins used_sp =
        NativeCode (instrs :: [ins]) lbl (max_int msp used_sp)

fn :: nc_emit_list RNativeCode [RNativeInstr] Int     => RNativeCode
      nc_emit_list (NativeCode instrs lbl msp) more used_sp =
        NativeCode (instrs :: more) lbl (max_int msp used_sp)

-- ── String Pool (.rodata) Collection & Interning ─────────────

fn :: join_comma [String] => String
      join_comma []       =  ""
      join_comma (s:[])   =  s
      join_comma (s:ss)   =  s + "," + (join_comma ss)

fn :: collect_pat_strs RPattern         [String] => [String]
      collect_pat_strs (PatReal r)      acc      =  add_unique_str r acc
      collect_pat_strs (PatStr s)       acc      =  add_unique_str s acc
      collect_pat_strs (PatCons h t)    acc      =  collect_pat_strs t (collect_pat_strs h acc)
      collect_pat_strs (PatTuple ps)    acc      =  collect_pat_list_strs ps acc
      collect_pat_strs (PatCtor c args) acc      =  collect_pat_list_strs args (add_unique_str c acc)
      collect_pat_strs _                acc      =  acc

fn :: collect_pat_list_strs [RPattern] [String] => [String]
      collect_pat_list_strs []         acc      =  acc
      collect_pat_list_strs (p:ps)     acc      =  collect_pat_list_strs ps (collect_pat_strs p acc)

fn :: collect_expr_strs RExpr              [String] => [String]
      collect_expr_strs (EReal r)          acc      =  add_unique_str r acc
      collect_expr_strs (EStr s)           acc      =  add_unique_str s acc
      collect_expr_strs (EVar v)           acc      =  add_unique_str v acc
      collect_expr_strs (ENot inner)       acc      =  collect_expr_strs inner acc
      collect_expr_strs (EOut inner)       acc      =  collect_expr_strs inner acc
      collect_expr_strs (EBin _ l r)       acc      =  collect_expr_strs r (collect_expr_strs l acc)
      collect_expr_strs (ECall fname args) acc      =  collect_expr_list_strs args (add_unique_str fname acc)
      collect_expr_strs (EEcho args)       acc      =  collect_expr_list_strs args acc
      collect_expr_strs (EStrInterp parts) acc      =  collect_expr_list_strs parts acc
      collect_expr_strs (EList elems)      acc      =  collect_expr_list_strs elems acc
      collect_expr_strs (ETuple elems)     acc      =  collect_expr_list_strs elems acc
      collect_expr_strs (ETensor elems)    acc      =  collect_expr_list_strs elems acc
      collect_expr_strs (EEinsum es subs)  acc      =  collect_expr_list_strs es (add_unique_str (join_comma subs) acc)
      collect_expr_strs (EHadamard _ l s1 r s2) acc =  collect_expr_strs r (collect_expr_strs l (add_unique_str (s1 + "," + s2) acc))
      collect_expr_strs (EIndex base idxs) acc      =  collect_expr_list_strs idxs (collect_expr_strs base acc)
      collect_expr_strs (EIndexAssign _ idxs v) acc =  collect_expr_strs v (collect_expr_list_strs idxs acc)
      collect_expr_strs (ESeqSelect b m)   acc      =  collect_expr_strs b (add_unique_str m acc)
      collect_expr_strs (EBlock stmts)     acc      =  collect_stmt_list_strs stmts acc
      collect_expr_strs (EGuard guards)    acc      =  collect_guard_list_strs guards acc
      collect_expr_strs (EWhere body binds) acc     =  collect_where_list_strs binds (collect_expr_strs body acc)
      collect_expr_strs (EParPipe branches) acc     =  collect_expr_list_strs branches acc
      collect_expr_strs (EWithCtx c v b)   acc      =  collect_expr_strs b (collect_expr_strs v (add_unique_str c acc))
      collect_expr_strs (EWithRegion _ b)  acc      =  collect_expr_strs b acc
      collect_expr_strs (EAtomicUpdate v e) acc     =  collect_expr_strs e (add_unique_str v acc)
      collect_expr_strs (ELoadContext c e) acc      =  collect_expr_strs e (add_unique_str c acc)
      collect_expr_strs (ELoadShared v e)  acc      =  collect_expr_strs e (add_unique_str v acc)
      collect_expr_strs _                  acc      =  acc

fn :: collect_expr_list_strs [RExpr] [String] => [String]
      collect_expr_list_strs []      acc      =  acc
      collect_expr_list_strs (e:es)  acc      =  collect_expr_list_strs es (collect_expr_strs e acc)

fn :: collect_stmt_list_strs [RStmt]            [String] => [String]
      collect_stmt_list_strs []                 acc      =  acc
      collect_stmt_list_strs ((StmtLet _ e):ss) acc      =  collect_stmt_list_strs ss (collect_expr_strs e acc)
      collect_stmt_list_strs ((StmtMut _ e):ss) acc      =  collect_stmt_list_strs ss (collect_expr_strs e acc)
      collect_stmt_list_strs ((StmtExpr e):ss)  acc      =  collect_stmt_list_strs ss (collect_expr_strs e acc)
      collect_stmt_list_strs ((StmtAtomic v e):ss) acc   =  collect_stmt_list_strs ss (collect_expr_strs e (add_unique_str v acc))
      collect_stmt_list_strs ((StmtIndexAssign _ idxs e):ss) acc =
        collect_stmt_list_strs ss (collect_expr_strs e (collect_expr_list_strs idxs acc))

fn :: collect_where_list_strs [RWhereBind] [String] => [String]
      collect_where_list_strs []           acc      =  acc
      collect_where_list_strs ((WhereBind e _ _):wbs) acc =
        collect_where_list_strs wbs (collect_expr_strs e acc)

fn :: collect_guard_list_strs [RGuard] [String] => [String]
      collect_guard_list_strs []       acc      =  acc
      collect_guard_list_strs ((GuardBranch c b):gs) acc =
        collect_guard_list_strs gs (collect_expr_strs b (collect_expr_strs c acc))

fn :: collect_case_list_strs [RFnCase] [String] => [String]
      collect_case_list_strs []        acc      =  acc
      collect_case_list_strs ((FnCase pats guards body):cs) acc =
        a1 = collect_pat_list_strs pats acc
        a2 = collect_guard_list_strs guards a1
        collect_case_list_strs cs (collect_expr_strs body a2)

fn :: collect_fndef_list_strs [RFnDef] [String] => [String]
      collect_fndef_list_strs []       acc      =  acc
      collect_fndef_list_strs ((FnDef name _ _ cases):fs) acc =
        collect_fndef_list_strs fs (collect_case_list_strs cases (add_unique_str name acc))

fn :: build_str_pool_loop [String] Int     String [RStrEntry] => RStrPool
      build_str_pool_loop []       _       rodata entries     =  StrPool rodata entries
      build_str_pool_loop (s:ss)   cur_off rodata entries     =
        slen = str_len s
        build_str_pool_loop ss (cur_off + slen) (rodata + s) (entries :: [StrEntry s cur_off slen])

fn :: build_str_pool [RFnDef] [String]   => RStrPool
      build_str_pool fns      extra_strs =
        base_strs = ["", "+", "-", "*", "/", "%"] :: extra_strs
        all_strs = collect_fndef_list_strs fns base_strs
        build_str_pool_loop all_strs 0 "" []

fn :: pool_rodata RStrPool      => String
      pool_rodata (StrPool s _) =  s

fn :: pool_entries RStrPool        => [RStrEntry]
      pool_entries (StrPool _ tbl) =  tbl

fn :: lookup_str_off [RStrEntry] String => Int
      lookup_str_off []          _      =  0
      lookup_str_off ((StrEntry k off _):rest) target
        | k == target = off
        | otherwise = lookup_str_off rest target

-- ── Function & Record Field Tables ───────────────────────────

fn :: has_field_entry [RFieldEntry] String => Bool
      has_field_entry []            _      =  False
      has_field_entry ((FieldEntry k _):rest) target
        | k == target = True
        | otherwise = has_field_entry rest target

fn :: collect_fields_from_list [RField] Int [RFieldEntry] => [RFieldEntry]
      collect_fields_from_list []       _   acc           =  acc
      collect_fields_from_list ((TypeField fname _):fs) idx acc
        | has_field_entry acc fname = collect_fields_from_list fs (idx + 1) acc
        | otherwise = collect_fields_from_list fs (idx + 1) (acc :: [FieldEntry fname idx])

fn :: collect_typedef_fields [RTypeDef] [RFieldEntry] => [RFieldEntry]
      collect_typedef_fields []         acc           =  acc
      collect_typedef_fields ((TypeDef _ _ fields):ts) acc =
        collect_typedef_fields ts (collect_fields_from_list fields 0 acc)

fn :: lookup_field_idx [RFieldEntry] String => Int
      lookup_field_idx []            _      =  0
      lookup_field_idx ((FieldEntry k idx):rest) target
        | k == target = idx
        | otherwise = lookup_field_idx rest target

fn :: collect_field_names [RFieldEntry] => [String]
      collect_field_names []            =  []
      collect_field_names ((FieldEntry k _):rest) = [k] :: (collect_field_names rest)

fn :: build_field_cg_sigs [RFieldEntry] [String] => [RCgSig]
      build_field_cg_sigs []            _        =  []
      build_field_cg_sigs ((FieldEntry fname _):rest) fn_names
        | str_in_list fname fn_names = build_field_cg_sigs rest fn_names
        | otherwise = [CgSig fname 1 False] :: (build_field_cg_sigs rest fn_names)

fn :: build_fn_table_fndefs [RFnDef] Int      [RFnEntry] => [RFnEntry]
      build_fn_table_fndefs []       _        acc        =  acc
      build_fn_table_fndefs ((FnDef name params _ cases):fs) next_fid acc =
        arity = infer_fndef_arity params cases
        build_fn_table_fndefs fs (next_fid + 1) (acc :: [FnEntry name next_fid arity])

fn :: build_fn_table_fields [RFieldEntry] [String] Int [RFnEntry] => [RFnEntry]
      build_fn_table_fields [] _ _ acc = acc
      build_fn_table_fields ((FieldEntry fname _):rest) fn_names next_fid acc
        | str_in_list fname fn_names = build_fn_table_fields rest fn_names next_fid acc
        | otherwise = build_fn_table_fields rest fn_names (next_fid + 1) (acc :: [FnEntry fname next_fid 1])

fn :: lookup_fn_id [RFnEntry] String => Int
      lookup_fn_id []         _      =  0
      lookup_fn_id ((FnEntry k fid _):rest) target
        | k == target = fid
        | otherwise = lookup_fn_id rest target

fn :: lookup_fn_arity [RFnEntry] String => Int
      lookup_fn_arity []         _      =  -1
      lookup_fn_arity ((FnEntry k _ arity):rest) target
        | k == target = arity
        | otherwise = lookup_fn_arity rest target

-- ── Local Variable Collection & RMM2 Liveness Helpers ────────

fn :: collect_pat_vars RPattern         [String] => [String]
      collect_pat_vars (PatVar v)       acc      =  add_unique_str v acc
      collect_pat_vars (PatSeqBind v)   acc      =  add_unique_str v acc
      collect_pat_vars (PatCons h t)    acc      =  collect_pat_vars t (collect_pat_vars h acc)
      collect_pat_vars (PatTuple ps)    acc      =  collect_pat_list_vars ps acc
      collect_pat_vars (PatCtor _ args) acc      =  collect_pat_list_vars args acc
      collect_pat_vars _                acc      =  acc

fn :: collect_pat_list_vars [RPattern] [String] => [String]
      collect_pat_list_vars []         acc      =  acc
      collect_pat_list_vars (p:ps)     acc      =  collect_pat_list_vars ps (collect_pat_vars p acc)

fn :: add_bound_var String [String] => [String]
      add_bound_var "_"    acc      =  acc
      add_bound_var v      acc      =  add_unique_str v acc

fn :: collect_expr_bound_vars RExpr              [String] => [String]
      collect_expr_bound_vars (ENot inner)       acc      =  collect_expr_bound_vars inner acc
      collect_expr_bound_vars (EOut inner)       acc      =  collect_expr_bound_vars inner acc
      collect_expr_bound_vars (EBin _ l r)       acc      =  collect_expr_bound_vars r (collect_expr_bound_vars l acc)
      collect_expr_bound_vars (ECall _ args)     acc      =  collect_expr_list_bound_vars args acc
      collect_expr_bound_vars (EEcho args)       acc      =  collect_expr_list_bound_vars args acc
      collect_expr_bound_vars (EStrInterp parts) acc      =  collect_expr_list_bound_vars parts acc
      collect_expr_bound_vars (EList elems)      acc      =  collect_expr_list_bound_vars elems acc
      collect_expr_bound_vars (ETuple elems)     acc      =  collect_expr_list_bound_vars elems acc
      collect_expr_bound_vars (ETensor elems)    acc      =  collect_expr_list_bound_vars elems acc
      collect_expr_bound_vars (EEinsum es _)     acc      =  collect_expr_list_bound_vars es acc
      collect_expr_bound_vars (EHadamard _ l _ r _) acc   =  collect_expr_bound_vars r (collect_expr_bound_vars l acc)
      collect_expr_bound_vars (EIndex base idxs) acc      =  collect_expr_list_bound_vars idxs (collect_expr_bound_vars base acc)
      collect_expr_bound_vars (EIndexAssign t idxs v) acc =  collect_expr_bound_vars v (collect_expr_list_bound_vars idxs (add_bound_var t acc))
      collect_expr_bound_vars (ESeqSelect b _)   acc      =  collect_expr_bound_vars b acc
      collect_expr_bound_vars (EBlock stmts)     acc      =  collect_stmt_list_bound_vars stmts acc
      collect_expr_bound_vars (EGuard guards)    acc      =  collect_guard_list_bound_vars guards acc
      collect_expr_bound_vars (EWhere body binds) acc     =  collect_where_list_bound_vars binds (collect_expr_bound_vars body acc)
      collect_expr_bound_vars (EParPipe branches) acc     =  collect_expr_list_bound_vars branches acc
      collect_expr_bound_vars (EWithCtx _ v b)   acc      =  collect_expr_bound_vars b (collect_expr_bound_vars v acc)
      collect_expr_bound_vars (EWithRegion _ b)  acc      =  collect_expr_bound_vars b acc
      collect_expr_bound_vars (EAtomicUpdate _ e) acc     =  collect_expr_bound_vars e acc
      collect_expr_bound_vars (ELoadContext _ e) acc      =  collect_expr_bound_vars e acc
      collect_expr_bound_vars (ELoadShared _ e)  acc      =  collect_expr_bound_vars e acc
      collect_expr_bound_vars _                  acc      =  acc

fn :: collect_expr_list_bound_vars [RExpr] [String] => [String]
      collect_expr_list_bound_vars []      acc      =  acc
      collect_expr_list_bound_vars (e:es)  acc      =  collect_expr_list_bound_vars es (collect_expr_bound_vars e acc)

fn :: collect_stmt_list_bound_vars [RStmt]            [String] => [String]
      collect_stmt_list_bound_vars []                 acc      =  acc
      collect_stmt_list_bound_vars ((StmtLet v e):ss) acc      =
        collect_stmt_list_bound_vars ss (add_bound_var v (collect_expr_bound_vars e acc))
      collect_stmt_list_bound_vars ((StmtMut v e):ss) acc      =
        collect_stmt_list_bound_vars ss (add_bound_var v (collect_expr_bound_vars e acc))
      collect_stmt_list_bound_vars ((StmtExpr e):ss)  acc      =
        collect_stmt_list_bound_vars ss (collect_expr_bound_vars e acc)
      collect_stmt_list_bound_vars ((StmtAtomic _ e):ss) acc   =
        collect_stmt_list_bound_vars ss (collect_expr_bound_vars e acc)
      collect_stmt_list_bound_vars ((StmtIndexAssign t idxs e):ss) acc =
        collect_stmt_list_bound_vars ss (collect_expr_bound_vars e (collect_expr_list_bound_vars idxs (add_bound_var t acc)))

fn :: collect_where_list_bound_vars [RWhereBind] [String] => [String]
      collect_where_list_bound_vars []           acc      =  acc
      collect_where_list_bound_vars ((WhereBind e v _):wbs) acc =
        collect_where_list_bound_vars wbs (add_bound_var v (collect_expr_bound_vars e acc))

fn :: collect_guard_list_bound_vars [RGuard] [String] => [String]
      collect_guard_list_bound_vars []       acc      =  acc
      collect_guard_list_bound_vars ((GuardBranch c b):gs) acc =
        collect_guard_list_bound_vars gs (collect_expr_bound_vars b (collect_expr_bound_vars c acc))

fn :: collect_cases_all_locals [RFnCase] [String] => [String]
      collect_cases_all_locals []        acc      =  acc
      collect_cases_all_locals ((FnCase pats guards body):cs) acc =
        a1 = collect_pat_list_vars pats acc
        a2 = collect_guard_list_bound_vars guards a1
        collect_cases_all_locals cs (collect_expr_bound_vars body a2)

fn :: cmm_expr_vars RExpr              [String] => [String]
      cmm_expr_vars (EVar name)        acc      =  add_unique_str name acc
      cmm_expr_vars (ENot inner)       acc      =  cmm_expr_vars inner acc
      cmm_expr_vars (EOut inner)       acc      =  cmm_expr_vars inner acc
      cmm_expr_vars (EBin _ l r)       acc      =  cmm_expr_vars r (cmm_expr_vars l acc)
      cmm_expr_vars (ECall "__record_update__" (base_e:rest_args)) acc =
        cmm_expr_list_vars rest_args (cmm_expr_vars base_e acc)
      cmm_expr_vars (ECall "__unpack2__" (_:single_arg:[])) acc =
        cmm_expr_vars single_arg acc
      cmm_expr_vars (ECall fname args) acc      =  cmm_expr_list_vars args (add_unique_str fname acc)
      cmm_expr_vars (EEcho args)       acc      =  cmm_expr_list_vars args acc
      cmm_expr_vars (EStrInterp parts) acc      =  cmm_expr_list_vars parts acc
      cmm_expr_vars (EList elems)      acc      =  cmm_expr_list_vars elems acc
      cmm_expr_vars (ETuple elems)     acc      =  cmm_expr_list_vars elems acc
      cmm_expr_vars (ETensor elems)    acc      =  cmm_expr_list_vars elems acc
      cmm_expr_vars (EEinsum es _)     acc      =  cmm_expr_list_vars es acc
      cmm_expr_vars (EHadamard _ l _ r _) acc   =  cmm_expr_vars r (cmm_expr_vars l acc)
      cmm_expr_vars (EIndex base idxs) acc      =  cmm_expr_list_vars idxs (cmm_expr_vars base acc)
      cmm_expr_vars (EIndexAssign t idxs v) acc =  cmm_expr_vars v (cmm_expr_list_vars idxs (add_unique_str t acc))
      cmm_expr_vars (ESeqSelect b _)   acc      =  cmm_expr_vars b acc
      cmm_expr_vars (EBlock stmts)     acc      =  cmm_stmts_vars stmts acc
      cmm_expr_vars (EGuard guards)    acc      =  cmm_guards_vars guards acc
      cmm_expr_vars (EWhere body binds) acc     =  cmm_where_vars binds body acc
      cmm_expr_vars (EParPipe branches) acc     =  cmm_expr_list_vars branches acc
      cmm_expr_vars (EWithCtx _ v b)   acc      =  cmm_expr_vars b (cmm_expr_vars v acc)
      cmm_expr_vars (EWithRegion _ b)  acc      =  cmm_expr_vars b acc
      cmm_expr_vars (EAtomicUpdate _ e) acc     =  cmm_expr_vars e acc
      cmm_expr_vars (ELoadContext _ e) acc      =  cmm_expr_vars e acc
      cmm_expr_vars (ELoadShared _ e)  acc      =  cmm_expr_vars e acc
      cmm_expr_vars _                  acc      =  acc

fn :: cmm_guards_vars [RGuard] [String] => [String]
      cmm_guards_vars []       acc      =  acc
      cmm_guards_vars ((GuardBranch c b):gs) acc =
        cmm_guards_vars gs (cmm_expr_vars b (cmm_expr_vars c acc))

fn :: cmm_expr_list_vars [RExpr] [String] => [String]
      cmm_expr_list_vars []      acc      =  acc
      cmm_expr_list_vars (e:es)  acc      =  cmm_expr_list_vars es (cmm_expr_vars e acc)

fn :: cmm_stmts_vars [RStmt]            [String] => [String]
      cmm_stmts_vars []                 acc      =  acc
      cmm_stmts_vars ((StmtLet _ e):ss) acc      =  cmm_stmts_vars ss (cmm_expr_vars e acc)
      cmm_stmts_vars ((StmtMut _ e):ss) acc      =  cmm_stmts_vars ss (cmm_expr_vars e acc)
      cmm_stmts_vars ((StmtExpr e):ss)  acc      =  cmm_stmts_vars ss (cmm_expr_vars e acc)
      cmm_stmts_vars ((StmtAtomic _ e):ss) acc   =  cmm_stmts_vars ss (cmm_expr_vars e acc)
      cmm_stmts_vars ((StmtIndexAssign t idxs e):ss) acc =
        cmm_stmts_vars ss (cmm_expr_vars e (cmm_expr_list_vars idxs (add_unique_str t acc)))

fn :: cmm_where_vars [RWhereBind] RExpr [String] => [String]
      cmm_where_vars []           body  acc      =  cmm_expr_vars body acc
      cmm_where_vars ((WhereBind e _ []):wbs) body acc =
        cmm_where_vars wbs body (cmm_expr_vars e acc)
      cmm_where_vars ((WhereBind e v _):wbs) body acc =
        cmm_where_vars wbs body (cmm_expr_vars e (add_unique_str v acc))

fn :: cmm_filter_in_list [String] [String] => [String]
      cmm_filter_in_list []       _        =  []
      cmm_filter_in_list (x:xs)   allowed
        | x != "_" AND (str_in_list x allowed) = [x] :: (cmm_filter_in_list xs allowed)
        | otherwise = cmm_filter_in_list xs allowed

fn :: cmm_filter_not_in_list [String] [String] => [String]
      cmm_filter_not_in_list []       _        =  []
      cmm_filter_not_in_list (x:xs)   excluded
        | x != "_" AND (NOT (str_in_list x excluded)) = [x] :: (cmm_filter_not_in_list xs excluded)
        | otherwise = cmm_filter_not_in_list xs excluded

fn :: cmm_remove_str String [String] => [String]
      cmm_remove_str _      []       =  []
      cmm_remove_str target (x:xs)
        | x == target = cmm_remove_str target xs
        | otherwise = [x] :: (cmm_remove_str target xs)

-- ── Environment Accessors & Builtin ID Mapping ───────────────

fn :: env_fn_name RNativeEnv => String
      env_fn_name (NativeEnv fn_name _ _ _ _ _) = fn_name

fn :: env_arity RNativeEnv => Int
      env_arity (NativeEnv _ arity _ _ _ _) = arity

fn :: env_str_off RNativeEnv String => Int
      env_str_off (NativeEnv _ _ _ str_tbl _ _) s = lookup_str_off str_tbl s

fn :: env_fn_id RNativeEnv String => Int
      env_fn_id (NativeEnv _ _ _ _ fn_tbl _) fname = lookup_fn_id fn_tbl fname

fn :: env_fn_arity RNativeEnv String => Int
      env_fn_arity (NativeEnv _ _ _ _ fn_tbl _) fname = lookup_fn_arity fn_tbl fname

fn :: env_field_idx RNativeEnv String => Int
      env_field_idx (NativeEnv _ _ _ _ _ field_tbl) fname = lookup_field_idx field_tbl fname

fn :: env_var_slot RNativeEnv String => Int
      env_var_slot (NativeEnv _ arity all_locals _ _ _) name =
        idx = lookup_local all_locals name
        env_var_slot_idx arity idx

fn :: env_var_slot_idx Int   Int => Int
      env_var_slot_idx arity idx
        | idx >= 0 = arity + idx
        | otherwise = 0

fn :: binop_id RBinOp     => Int
      binop_id OpAdd      =  0
      binop_id OpSub      =  1
      binop_id OpMul      =  2
      binop_id OpDiv      =  3
      binop_id OpMod      =  4
      binop_id OpEq       =  5
      binop_id OpNeq      =  6
      binop_id OpGt       =  7
      binop_id OpLt       =  8
      binop_id OpGtEq     =  9
      binop_id OpLtEq     =  10
      binop_id OpAnd      =  11
      binop_id OpOr       =  12
      binop_id OpXor      =  13
      binop_id OpConcat   =  14
      binop_id OpFlatJoin =  15
      binop_id OpMatMul   =  16

fn :: binop_op_tag RBinOp => String
      binop_op_tag OpAdd  =  "+"
      binop_op_tag OpSub  =  "-"
      binop_op_tag OpMul  =  "*"
      binop_op_tag OpDiv  =  "/"
      binop_op_tag OpMod  =  "%"
      binop_op_tag _      =  "+"

fn :: builtin_zero_arg_id String            => Int
      builtin_zero_arg_id "cli_args"        =  0
      builtin_zero_arg_id "new_mailbox"     =  1
      builtin_zero_arg_id "mailbox"         =  1
      builtin_zero_arg_id "new_channel"     =  1
      builtin_zero_arg_id "channel"         =  1
      builtin_zero_arg_id "sys_getcwd"      =  2
      builtin_zero_arg_id "sys_getuid"      =  3
      builtin_zero_arg_id "sys_getgid"      =  4
      builtin_zero_arg_id "cmm_live_blocks" =  5
      builtin_zero_arg_id "cmm_cond_spared" =  6
      builtin_zero_arg_id "cmm_cond_freed"  =  7
      builtin_zero_arg_id _                 =  -1

fn :: builtin_call_id String             => Int
      builtin_call_id "cli_args"         =  0
      builtin_call_id "new_mailbox"      =  1
      builtin_call_id "mailbox"          =  1
      builtin_call_id "new_channel"      =  1
      builtin_call_id "channel"          =  1
      builtin_call_id "sys_getcwd"       =  2
      builtin_call_id "sys_getuid"       =  3
      builtin_call_id "sys_getgid"       =  4
      builtin_call_id "cmm_live_blocks"  =  5
      builtin_call_id "cmm_cond_spared"  =  6
      builtin_call_id "cmm_cond_freed"   =  7
      builtin_call_id "str_len"          =  10
      builtin_call_id "char_from_code"   =  11
      builtin_call_id "int_to_str"       =  12
      builtin_call_id "str_to_int"       =  13
      builtin_call_id "read_file"        =  14
      builtin_call_id "load_rg_source"   =  15
      builtin_call_id "read_bytes"       =  16
      builtin_call_id "shell_exec"       =  17
      builtin_call_id "list_dir"         =  18
      builtin_call_id "file_lstat"       =  19
      builtin_call_id "sha256_file"      =  20
      builtin_call_id "sha256_str"       =  21
      builtin_call_id "sys_chdir"        =  22
      builtin_call_id "sys_getenv"       =  23
      builtin_call_id "sys_exit"         =  24
      builtin_call_id "sys_username"     =  25
      builtin_call_id "sys_lookup_uid_gid" = 26
      builtin_call_id "sys_user_groups"  =  27
      builtin_call_id "sys_setresgid"    =  28
      builtin_call_id "sys_setgroups"    =  29
      builtin_call_id "sys_setresuid"    =  30
      builtin_call_id "sys_read_pass"    =  31
      builtin_call_id "receive_from"     =  32
      builtin_call_id "chan_recv"        =  32
      builtin_call_id "try_receive_from" =  33
      builtin_call_id "chan_try_recv"    =  33
      builtin_call_id "join"             =  34
      builtin_call_id "new_bounded_channel" = 35
      builtin_call_id "str_char_at"      =  40
      builtin_call_id "str_concat"       =  41
      builtin_call_id "str_starts_with"  =  42
      builtin_call_id "str_contains"     =  43
      builtin_call_id "write_bytes"      =  44
      builtin_call_id "write_file"       =  45
      builtin_call_id "sys_mkdir"        =  46
      builtin_call_id "sys_chmod"        =  47
      builtin_call_id "sys_setenv"       =  48
      builtin_call_id "cmm_same_ptr"     =  49
      builtin_call_id "send_through"     =  50
      builtin_call_id "chan_send"        =  50
      builtin_call_id "receive_from_timeout" = 51
      builtin_call_id "spawn"            =  52
      builtin_call_id "map"              =  53
      builtin_call_id "seq_map"          =  53
      builtin_call_id "||map"            =  54
      builtin_call_id "par_map"          =  54
      builtin_call_id "filter"           =  55
      builtin_call_id "seq_filter"       =  55
      builtin_call_id "||filter"         =  56
      builtin_call_id "par_filter"       =  56
      builtin_call_id "str_slice"        =  60
      builtin_call_id "fold"             =  61
      builtin_call_id "sys_exec"         =  62
      builtin_call_id "sys_execve"       =  63
      builtin_call_id _                  =  -1

-- ── Expression & Statement Lowering to Native IR ─────────────

fn :: lower_cmm_drops RNativeEnv [String] Int     RNativeCode => RNativeCode
      lower_cmm_drops _          []       _       st          =  st
      lower_cmm_drops env        (x:xs)   used_sp st          =
        slot = env_var_slot env x
        st1 = nc_emit st (NCmmDropSlot slot) used_sp
        lower_cmm_drops env xs used_sp st1

fn :: lower_unused_let_drop RNativeEnv String [String] Int RNativeCode => RNativeCode
      lower_unused_let_drop env v live_after used_sp st
        | str_in_list v live_after = st
        | otherwise = nc_emit st (NCmmDropSlot (env_var_slot env v)) used_sp

fn :: lower_let_var_store RNativeEnv String [String] Int RNativeCode => RNativeCode
      lower_let_var_store env v bound_locals used_sp st
        | (lookup_local bound_locals v) >= 0 = nc_emit st (NRebindSlot (env_var_slot env v)) used_sp
        | otherwise = nc_emit st (NStoreSlot (env_var_slot env v)) used_sp

fn :: lower_expr_list_to_slots RNativeEnv [RExpr] [String] Int Int RNativeCode => RNativeCode
      lower_expr_list_to_slots _ [] _ _ _ st = st
      lower_expr_list_to_slots env (e:es) bound_locals sp idx st =
        cur_slot = sp + idx
        st1 = lower_expr env e bound_locals cur_slot st
        st2 = nc_emit st1 (NStoreSlot cur_slot) (cur_slot + 1)
        lower_expr_list_to_slots env es bound_locals sp (idx + 1) st2

fn :: lower_int_list_to_slots [Int]  Int Int RNativeCode => RNativeCode
      lower_int_list_to_slots []     _   _   st          =  st
      lower_int_list_to_slots (n:ns) sp  idx st          =
        cur_slot = sp + idx
        st1 = nc_emit_list st [NLoadImmInt n, NStoreSlot cur_slot] (cur_slot + 1)
        lower_int_list_to_slots ns sp (idx + 1) st1

fn :: lower_record_updates RNativeEnv [RExpr] [String] Int RNativeCode => RNativeCode
      lower_record_updates env ((EStr fname):val_e:rest) bound_locals sp st =
        st1 = nc_emit st (NStoreSlot sp) (sp + 1)
        st2 = lower_expr env val_e bound_locals (sp + 1) st1
        fidx = env_field_idx env fname
        st3 = nc_emit st2 (NAdtSet sp fidx) (sp + 1)
        lower_record_updates env rest bound_locals sp st3
      lower_record_updates _ _ _ _ st = st

fn :: lower_var_expr RNativeEnv String [String] Int RNativeCode => RNativeCode
      lower_var_expr env name bound_locals sp st
        | (lookup_local bound_locals name) >= 0 =
          nc_emit st (NCloneSlot (env_var_slot env name)) sp
        | is_upper_ident name =
          off = env_str_off env name
          nc_emit st (NLoadAdt0 off (str_len name)) sp
        | (builtin_zero_arg_id name) >= 0 =
          nc_emit st (NCallBuiltin (builtin_zero_arg_id name) sp 0) (sp + 1)
        | (env_fn_arity env name) == 0 =
          nc_emit st (NCallFn (env_fn_id env name) sp 0) (sp + 1)
        | otherwise =
          off = env_str_off env name
          nc_emit st (NLoadStrLit off (str_len name)) sp

fn :: prim_type_tag_id String   => Int
      prim_type_tag_id "Int"    =  1
      prim_type_tag_id "U8"     =  1
      prim_type_tag_id "U16"    =  1
      prim_type_tag_id "U32"    =  1
      prim_type_tag_id "U64"    =  1
      prim_type_tag_id "I8"     =  1
      prim_type_tag_id "I16"    =  1
      prim_type_tag_id "I32"    =  1
      prim_type_tag_id "I64"    =  1
      prim_type_tag_id "Usize"  =  1
      prim_type_tag_id "Bool"   =  2
      prim_type_tag_id "String" =  3
      prim_type_tag_id "Char"   =  3
      prim_type_tag_id "Real"   =  4
      prim_type_tag_id "Float"  =  4
      prim_type_tag_id _        =  0

fn :: lower_call_expr RNativeEnv String [RExpr] [String] Int RNativeCode => RNativeCode
      lower_call_expr env fname [] bound_locals sp st
        | (lookup_local bound_locals fname) >= 0 =
          nc_emit st (NCloneSlot (env_var_slot env fname)) sp
      lower_call_expr env fname (a1:[]) bound_locals sp st
        | (lookup_local bound_locals fname) >= 0 =
          st1 = lower_expr env a1 bound_locals sp st
          st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
          nc_emit st2 (NCallIndirect1 (env_var_slot env fname) sp) (sp + 1)
        | (prim_type_tag_id fname) > 0 =
          lower_expr env a1 bound_locals sp st
      lower_call_expr env fname (a1:a2:[]) bound_locals sp st
        | (lookup_local bound_locals fname) >= 0 =
          st1 = lower_expr_list_to_slots env [a1, a2] bound_locals sp 0 st
          nc_emit st1 (NCallIndirect2 (env_var_slot env fname) sp) (sp + 2)
      lower_call_expr env fname args bound_locals sp st
        | is_upper_ident fname =
          count = rexpr_list_len args
          off = env_str_off env fname
          slen = str_len fname
          lower_adt_ctor_call env args bound_locals off slen count sp st
        | (builtin_call_id fname) >= 0 =
          count = rexpr_list_len args
          st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
          nc_emit st1 (NCallBuiltin (builtin_call_id fname) sp count) (sp + count + 1)
        | otherwise =
          count = rexpr_list_len args
          st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
          nc_emit st1 (NCallFn (env_fn_id env fname) sp count) (sp + count + 1)

fn :: lower_adt_ctor_call RNativeEnv [RExpr] [String] Int Int Int Int RNativeCode => RNativeCode
      lower_adt_ctor_call _ [] _ off slen 0 sp st =
        nc_emit st (NLoadAdt0 off slen) sp
      lower_adt_ctor_call env args bound_locals off slen count sp st =
        st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
        nc_emit st1 (NMakeAdt off slen sp count) (sp + count + 1)

fn :: lower_expr RNativeEnv RExpr [String] Int RNativeCode => RNativeCode
      lower_expr _ (EInt n) _ sp st =
        nc_emit st (NLoadImmInt n) sp
      lower_expr env (EReal r) _ sp st =
        off = env_str_off env r
        nc_emit st (NLoadRealLit off (str_len r)) sp
      lower_expr env (EStr s) _ sp st =
        off = env_str_off env s
        nc_emit st (NLoadStrLit off (str_len s)) sp
      lower_expr env (EStrInterp parts) bound_locals sp st =
        count = rexpr_list_len parts
        st1 = lower_expr_list_to_slots env parts bound_locals sp 0 st
        nc_emit st1 (NStrInterp sp count) (sp + count + 1)
      lower_expr _ (EBool True) _ sp st =
        nc_emit st (NLoadImmRaw 6) sp
      lower_expr _ (EBool False) _ sp st =
        nc_emit st (NLoadImmRaw 2) sp
      lower_expr _ EUnit _ sp st =
        nc_emit st (NLoadImmRaw 0) sp
      lower_expr env (EVar name) bound_locals sp st =
        lower_var_expr env name bound_locals sp st
      lower_expr env (ENot inner) bound_locals sp st =
        st1 = lower_expr env inner bound_locals sp st
        nc_emit st1 NNot sp
      lower_expr env (EOut inner) bound_locals sp st =
        st1 = lower_expr env inner bound_locals sp st
        nc_emit st1 NOut sp
      lower_expr env (EBin bop l r) bound_locals sp st =
        st1 = lower_expr env l bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_expr env r bound_locals (sp + 1) st2
        nc_emit st3 (NBinOp (binop_id bop) sp) (sp + 1)
      lower_expr env (ECall "__record_update__" (base_e:rest_args)) bound_locals sp st =
        st1 = lower_expr env base_e bound_locals sp st
        lower_record_updates env rest_args bound_locals sp st1
      lower_expr env (ECall "__unpack2__" ((EVar fn_target):single_arg:[])) bound_locals sp st =
        st1 = lower_expr env single_arg bound_locals sp st
        fid = env_fn_id env fn_target
        ins_list = [NStoreSlot sp, NTupleGet sp 0, NStoreSlot (sp + 1), NTupleGet sp 1, NStoreSlot (sp + 2), NClearLocals sp (sp + 1), NCallFn fid (sp + 1) 2]
        nc_emit_list st1 ins_list (sp + 3)
      lower_expr env (ECall fname args) bound_locals sp st =
        lower_call_expr env fname args bound_locals sp st
      lower_expr env (EEcho args) bound_locals sp st =
        count = rexpr_list_len args
        st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
        nc_emit st1 (NEcho sp count) (sp + count + 1)
      lower_expr env (EList elems) bound_locals sp st =
        count = rexpr_list_len elems
        st1 = lower_expr_list_to_slots env elems bound_locals sp 0 st
        nc_emit st1 (NMakeList sp count) (sp + count + 1)
      lower_expr env (ETuple elems) bound_locals sp st =
        count = rexpr_list_len elems
        st1 = lower_expr_list_to_slots env elems bound_locals sp 0 st
        nc_emit st1 (NMakeTuple sp count) (sp + count + 1)
      lower_expr env (ETensor elems) bound_locals sp st =
        count = rexpr_list_len elems
        st1 = lower_expr_list_to_slots env elems bound_locals sp 0 st
        nc_emit st1 (NMakeTensor sp count) (sp + count + 1)
      lower_expr env (EEinsum es subs) bound_locals sp st =
        count = rexpr_list_len es
        spec = join_comma subs
        off = env_str_off env spec
        st1 = lower_expr_list_to_slots env es bound_locals sp 0 st
        nc_emit st1 (NEinsum sp count off (str_len spec)) (sp + count + 1)
      lower_expr env (EHadamard bop l s1 r s2) bound_locals sp st =
        subs = s1 + "," + s2
        off = env_str_off env subs
        st1 = lower_expr env l bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_expr env r bound_locals (sp + 1) st2
        nc_emit st3 (NHadamard (binop_id bop) sp off (str_len subs)) (sp + 1)
      lower_expr env (EIndex base idxs) bound_locals sp st =
        count = rexpr_list_len idxs
        st1 = lower_expr env base bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_expr_list_to_slots env idxs bound_locals (sp + 1) 0 st2
        nc_emit st3 (NIndex sp (sp + 1) count) (sp + count + 2)
      lower_expr env (EIndexAssign target idxs val_e) bound_locals sp st =
        count = rexpr_list_len idxs
        tslot = env_var_slot env target
        st1 = nc_emit_list st [NCloneSlot tslot, NStoreSlot sp] (sp + 1)
        st2 = lower_expr_list_to_slots env idxs bound_locals (sp + 1) 0 st1
        st3 = lower_expr env val_e bound_locals (sp + 1 + count) st2
        nc_emit st3 (NIndexSet sp (sp + 1) count) (sp + count + 2)
      lower_expr env (ESeqSelect base mask) bound_locals sp st =
        off = env_str_off env mask
        st1 = lower_expr env base bound_locals sp st
        nc_emit st1 (NSeqSelect off (str_len mask)) sp
      lower_expr env (EBlock stmts) bound_locals sp st =
        lower_stmts_cmm env stmts bound_locals [] sp st
      lower_expr env (EGuard guards) bound_locals sp st =
        end_lbl = nc_lbl st
        st1 = nc_set_lbl st (end_lbl + 1)
        lower_expr_guards env guards bound_locals end_lbl sp st1
      lower_expr env (EWhere body binds) bound_locals sp st =
        lower_where_cmm env binds body bound_locals [] sp st
      lower_expr env (EParPipe branches) bound_locals sp st =
        count = rexpr_list_len branches
        st1 = lower_expr_list_to_slots env branches bound_locals sp 0 st
        nc_emit st1 (NMakeTuple sp count) (sp + count + 1)
      lower_expr env (EWithCtx ctx_name val_e body) bound_locals sp st =
        off = env_str_off env ctx_name
        klen = str_len ctx_name
        st1 = lower_expr env val_e bound_locals sp st
        st2 = nc_emit st1 (NPushCtx off klen) sp
        st3 = lower_expr env body bound_locals sp st2
        nc_emit st3 (NPopCtx off klen) sp
      lower_expr env (EWithRegion quota body) bound_locals sp st =
        st1 = nc_emit st NEnterRegion sp
        st2 = lower_expr env body bound_locals sp st1
        nc_emit st2 (NExitRegion quota) sp
      lower_expr env (EAtomicUpdate var_name val_e) bound_locals sp st =
        off = env_str_off env var_name
        klen = str_len var_name
        st1 = lower_expr env val_e bound_locals sp st
        nc_emit st1 (NStoreShared off klen) sp
      lower_expr env (ELoadContext ctx_name def_e) bound_locals sp st =
        off = env_str_off env ctx_name
        klen = str_len ctx_name
        else_lbl = nc_lbl st
        end_lbl = else_lbl + 1
        st1 = nc_set_lbl st (else_lbl + 2)
        st2 = nc_emit_list st1 [NHasCtx off klen, NJumpIfZero else_lbl, NGetCtx off klen, NJump end_lbl, NLabel else_lbl] sp
        st3 = lower_expr env def_e bound_locals sp st2
        nc_emit st3 (NLabel end_lbl) sp
      lower_expr env (ELoadShared var_name def_e) bound_locals sp st =
        off = env_str_off env var_name
        klen = str_len var_name
        else_lbl = nc_lbl st
        end_lbl = else_lbl + 1
        st1 = nc_set_lbl st (else_lbl + 2)
        st2 = nc_emit_list st1 [NHasShared off klen, NJumpIfZero else_lbl, NGetShared off klen, NJump end_lbl, NLabel else_lbl] sp
        st3 = lower_expr env def_e bound_locals sp st2
        nc_emit_list st3 [NInitShared off klen, NLabel end_lbl] sp

fn :: lower_expr_guards RNativeEnv [RGuard] [String] Int Int RNativeCode => RNativeCode
      lower_expr_guards _ [] _ end_lbl sp st =
        nc_emit_list st [NLoadImmRaw 0, NLabel end_lbl] sp
      lower_expr_guards env ((GuardBranch cond body):gs) bound_locals end_lbl sp st =
        next_lbl = nc_lbl st
        st1 = nc_set_lbl st (next_lbl + 1)
        st2 = lower_expr env cond bound_locals sp st1
        st3 = nc_emit_list st2 [NAsBool, NJumpIfZero next_lbl] sp
        st4 = lower_expr env body bound_locals sp st3
        st5 = nc_emit_list st4 [NJump end_lbl, NLabel next_lbl] sp
        lower_expr_guards env gs bound_locals end_lbl sp st5

fn :: lower_final_block_expr RNativeEnv RExpr [String] [String] Int RNativeCode => RNativeCode
      lower_final_block_expr env (EVar v) bound_locals _ sp st
        | (lookup_local bound_locals v) >= 0 =
          nc_emit st (NMoveSlot (env_var_slot env v)) sp
      lower_final_block_expr env e bound_locals [] sp st =
        lower_expr env e bound_locals sp st
      lower_final_block_expr env e bound_locals dead_vars sp st =
        st1 = lower_expr env e bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_cmm_drops env dead_vars (sp + 1) st2
        nc_emit st3 (NMoveSlot sp) (sp + 1)

fn :: lower_let_binding_stmt RNativeEnv String RExpr [String] [String] [RStmt] Int RNativeCode => RNativeCode
      lower_let_binding_stmt env v e bound_locals scope_vars rest sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        st1 = lower_expr env e bound_locals sp st
        st2 = lower_let_var_store env v bound_locals sp st1
        st3 = lower_cmm_drops env dead_inputs sp st2
        st4 = lower_unused_let_drop env v live_after sp st3
        lower_stmts_cmm env rest (add_unique_str v bound_locals) (add_unique_str v scope_vars) sp st4

fn :: lower_stmts_cmm RNativeEnv [RStmt] [String] [String] Int RNativeCode => RNativeCode
      lower_stmts_cmm _ [] _ _ sp st =
        nc_emit st (NLoadImmRaw 0) sp
      lower_stmts_cmm env ((StmtExpr e):[]) bound_locals scope_vars sp st =
        used = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        lower_final_block_expr env e bound_locals used sp st
      lower_stmts_cmm env ((StmtAtomic v e):[]) bound_locals scope_vars sp st =
        used = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        off = env_str_off env v
        st1 = lower_expr env e bound_locals sp st
        st2 = nc_emit st1 (NStoreShared off (str_len v)) sp
        st3 = lower_cmm_drops env used sp st2
        nc_emit st3 (NLoadImmRaw 0) sp
      lower_stmts_cmm env ((StmtIndexAssign t idxs e):[]) bound_locals _ sp st =
        count = rexpr_list_len idxs
        tslot = env_var_slot env t
        st1 = lower_expr_list_to_slots env idxs bound_locals sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot, NLoadImmRaw 0] (sp + count + 1)
      lower_stmts_cmm env ((StmtLet v e):[]) bound_locals scope_vars sp st
        | v == "_" =
          used = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
          st1 = lower_expr env e bound_locals sp st
          st2 = nc_emit st1 NDropVal sp
          st3 = lower_cmm_drops env used sp st2
          nc_emit st3 (NLoadImmRaw 0) sp
        | otherwise =
          used = cmm_remove_str v (cmm_filter_in_list (cmm_expr_vars e []) scope_vars)
          st1 = lower_expr env e bound_locals sp st
          st2 = lower_let_var_store env v bound_locals sp st1
          st3 = lower_cmm_drops env used sp st2
          nc_emit st3 (NMoveSlot (env_var_slot env v)) sp
      lower_stmts_cmm env ((StmtMut v e):[]) bound_locals scope_vars sp st =
        lower_stmts_cmm env [StmtLet v e] bound_locals scope_vars sp st
      lower_stmts_cmm env ((StmtLet v e):rest) bound_locals scope_vars sp st
        | v == "_" =
          used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
          live_after = cmm_stmts_vars rest []
          dead_now = cmm_filter_not_in_list used_in_e live_after
          st1 = lower_expr env e bound_locals sp st
          st2 = nc_emit st1 NDropVal sp
          st3 = lower_cmm_drops env dead_now sp st2
      lower_stmts_cmm env rest bound_locals scope_vars sp st3
        | otherwise =
          lower_let_binding_stmt env v e bound_locals scope_vars rest sp st
      lower_stmts_cmm env ((StmtMut v e):rest) bound_locals scope_vars sp st =
        lower_let_binding_stmt env v e bound_locals scope_vars rest sp st
      lower_stmts_cmm env ((StmtAtomic v e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        dead_now = cmm_filter_not_in_list used_in_e live_after
        off = env_str_off env v
        st1 = lower_expr env e bound_locals sp st
        st2 = nc_emit st1 (NStoreShared off (str_len v)) sp
        st3 = lower_cmm_drops env dead_now sp st2
        lower_stmts_cmm env rest bound_locals scope_vars sp st3
      lower_stmts_cmm env ((StmtIndexAssign t idxs e):rest) bound_locals scope_vars sp st =
        count = rexpr_list_len idxs
        tslot = env_var_slot env t
        st1 = lower_expr_list_to_slots env idxs bound_locals sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        st3 = nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        lower_stmts_cmm env rest bound_locals scope_vars sp st3
      lower_stmts_cmm env ((StmtExpr e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        dead_now = cmm_filter_not_in_list used_in_e live_after
        st1 = lower_expr env e bound_locals sp st
        st2 = nc_emit st1 NDropVal sp
        st3 = lower_cmm_drops env dead_now sp st2
        lower_stmts_cmm env rest bound_locals scope_vars sp st3

fn :: lower_where_cmm RNativeEnv [RWhereBind] RExpr [String] [String] Int RNativeCode => RNativeCode
      lower_where_cmm env [] body bound_locals scope_vars sp st =
        used = cmm_filter_in_list (cmm_expr_vars body []) scope_vars
        lower_final_block_expr env body bound_locals used sp st
      lower_where_cmm env ((WhereBind e v []):wbs) body bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_where_vars wbs body []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        st1 = lower_expr env e bound_locals sp st
        st2 = lower_let_var_store env v bound_locals sp st1
        st3 = lower_cmm_drops env dead_inputs sp st2
        st4 = lower_unused_let_drop env v live_after sp st3
        lower_where_cmm env wbs body (add_unique_str v bound_locals) (add_unique_str v scope_vars) sp st4
      lower_where_cmm env ((WhereBind e v idxs):wbs) body bound_locals scope_vars sp st =
        count = int_list_len idxs
        tslot = env_var_slot env v
        st1 = lower_int_list_to_slots idxs sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        st3 = nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        lower_where_cmm env wbs body bound_locals scope_vars sp st3

-- ── Tail-Call Optimization (TCO) & Tail Return Lowering ─────

fn :: expr_has_self_tail_call String RExpr           => Bool
      expr_has_self_tail_call target (ECall fname _) =  fname == target
      expr_has_self_tail_call target (EBlock stmts)  =  stmts_have_self_tail_call target stmts
      expr_has_self_tail_call target (EGuard guards) =  guards_have_self_tail_call target guards
      expr_has_self_tail_call target (EWhere body _) =  expr_has_self_tail_call target body
      expr_has_self_tail_call _      _               =  False

fn :: stmts_have_self_tail_call String [RStmt]           => Bool
      stmts_have_self_tail_call _      []                =  False
      stmts_have_self_tail_call target ((StmtExpr e):[]) =  expr_has_self_tail_call target e
      stmts_have_self_tail_call target (_:rest)          =  stmts_have_self_tail_call target rest

fn :: guards_have_self_tail_call String [RGuard] => Bool
      guards_have_self_tail_call _      []       =  False
      guards_have_self_tail_call target ((GuardBranch _ body):gs)
        | expr_has_self_tail_call target body = True
        | otherwise = guards_have_self_tail_call target gs

fn :: can_move_param_var String [String] [String]   [String]   => Bool
      can_move_param_var v      locals   scope_vars later_vars =
        ((lookup_local locals v) >= 0) AND (NOT (str_in_list v scope_vars)) AND (NOT (str_in_list v later_vars))

fn :: lower_tco_arg_expr RNativeEnv RExpr [RExpr] [String] [String] Int RNativeCode => RNativeCode
      lower_tco_arg_expr env (EVar v) es bound_locals scope_vars sp st
        | can_move_param_var v bound_locals scope_vars (cmm_expr_list_vars es []) =
          nc_emit st (NMoveSlot (env_var_slot env v)) sp
      lower_tco_arg_expr env (EBin OpConcat (EVar v) rhs) es bound_locals scope_vars sp st
        | can_move_param_var v bound_locals scope_vars (cmm_expr_vars rhs (cmm_expr_list_vars es [])) =
          vslot = env_var_slot env v
          st1 = nc_emit_list st [NMoveSlot vslot, NStoreSlot sp] (sp + 1)
          st2 = lower_expr env rhs bound_locals (sp + 1) st1
          nc_emit st2 (NBinOp 14 sp) (sp + 1)
      lower_tco_arg_expr env (ETuple elems) es bound_locals scope_vars sp st =
        count = rexpr_list_len elems
        st1 = lower_tco_arg_list_to_slots env elems es bound_locals scope_vars sp 0 st
        nc_emit st1 (NMakeTuple sp count) (sp + count + 1)
      lower_tco_arg_expr env (ECall fname args) es bound_locals scope_vars sp st
        | (lookup_local bound_locals fname) < 0 AND (NOT (is_upper_ident fname)) AND (builtin_call_id fname) < 0 AND fname != "__record_update__" AND fname != "__unpack2__" =
          count = rexpr_list_len args
          st1 = lower_tco_arg_list_to_slots env args es bound_locals scope_vars sp 0 st
          nc_emit st1 (NCallFn (env_fn_id env fname) sp count) (sp + count + 1)
      lower_tco_arg_expr env e _ bound_locals _ sp st =
        lower_expr env e bound_locals sp st

fn :: lower_tco_arg_list_to_slots RNativeEnv [RExpr] [RExpr] [String] [String] Int Int RNativeCode => RNativeCode
      lower_tco_arg_list_to_slots _ [] _ _ _ _ _ st = st
      lower_tco_arg_list_to_slots env (e:es) after bound_locals scope_vars sp idx st =
        cur_slot = sp + idx
        st1 = lower_tco_arg_expr env e (es :: after) bound_locals scope_vars cur_slot st
        st2 = nc_emit st1 (NStoreSlot cur_slot) (cur_slot + 1)
        lower_tco_arg_list_to_slots env es after bound_locals scope_vars sp (idx + 1) st2

fn :: lower_tail_return RNativeEnv RExpr [String] Int RNativeCode => RNativeCode
      lower_tail_return env expr bound_locals sp st =
        lower_tail_return_cmm env expr bound_locals [] sp st

fn :: lower_tail_return_cmm RNativeEnv RExpr [String] [String] Int RNativeCode => RNativeCode
      lower_tail_return_cmm env (ECall fname args) bound_locals scope_vars sp st
        | fname == (env_fn_name env) AND (rexpr_list_len args) == (env_arity env) AND (lookup_local bound_locals fname) < 0 =
          arity = env_arity env
          st1 = lower_tco_arg_list_to_slots env args [] bound_locals scope_vars sp 0 st
          st2 = lower_cmm_drops env scope_vars (sp + arity + 1) st1
          nc_emit st2 (NTailCall sp arity) (sp + arity + 1)
      lower_tail_return_cmm env (EBlock stmts) bound_locals scope_vars sp st =
        lower_tail_stmts_cmm env stmts bound_locals scope_vars sp st
      lower_tail_return_cmm env (EGuard guards) bound_locals scope_vars sp st
        | guards_have_self_tail_call (env_fn_name env) guards =
          lower_tail_guards_cmm env guards bound_locals scope_vars sp st
      lower_tail_return_cmm env (EWhere body binds) bound_locals scope_vars sp st =
        lower_tail_where_cmm env binds body bound_locals scope_vars sp st
      lower_tail_return_cmm env (EVar v) bound_locals _ sp st
        | (lookup_local bound_locals v) >= 0 =
          nc_emit_list st [NMoveSlot (env_var_slot env v), NReturn] sp
      lower_tail_return_cmm env expr bound_locals scope_vars sp st =
        used = cmm_filter_in_list (cmm_expr_vars expr []) scope_vars
        lower_tail_return_expr env expr bound_locals scope_vars used sp st

fn :: lower_tail_return_expr RNativeEnv RExpr [String] [String] [String] Int RNativeCode => RNativeCode
      lower_tail_return_expr env expr bound_locals scope_vars [] sp st =
        st1 = lower_tco_arg_expr env expr [] bound_locals scope_vars sp st
        nc_emit st1 NReturn sp
      lower_tail_return_expr env expr bound_locals scope_vars used sp st =
        st1 = lower_tco_arg_expr env expr [] bound_locals scope_vars sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_cmm_drops env used (sp + 1) st2
        nc_emit_list st3 [NMoveSlot sp, NReturn] (sp + 1)

fn :: lower_tail_guards_cmm RNativeEnv [RGuard] [String] [String] Int RNativeCode => RNativeCode
      lower_tail_guards_cmm env [] _ scope_vars sp st =
        st1 = lower_cmm_drops env scope_vars sp st
        nc_emit_list st1 [NLoadImmRaw 0, NReturn] sp
      lower_tail_guards_cmm env ((GuardBranch cond body):gs) bound_locals scope_vars sp st =
        next_lbl = nc_lbl st
        st1 = nc_set_lbl st (next_lbl + 1)
        st2 = lower_expr env cond bound_locals sp st1
        st3 = nc_emit_list st2 [NAsBool, NJumpIfZero next_lbl] sp
        st4 = lower_tail_return_cmm env body bound_locals scope_vars sp st3
        st5 = nc_emit st4 (NLabel next_lbl) sp
        lower_tail_guards_cmm env gs bound_locals scope_vars sp st5

fn :: lower_tail_let_stmt RNativeEnv String RExpr [String] [String] [RStmt] Int RNativeCode => RNativeCode
      lower_tail_let_stmt env v e bound_locals scope_vars rest sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        st1 = lower_expr env e bound_locals sp st
        st2 = lower_let_var_store env v bound_locals sp st1
        st3 = lower_cmm_drops env dead_inputs sp st2
        st4 = lower_unused_let_drop env v live_after sp st3
        lower_tail_stmts_cmm env rest (add_unique_str v bound_locals) (add_unique_str v scope_vars) sp st4

fn :: lower_tail_stmts_cmm RNativeEnv [RStmt] [String] [String] Int RNativeCode => RNativeCode
      lower_tail_stmts_cmm _ [] _ _ sp st =
        nc_emit_list st [NLoadImmRaw 0, NReturn] sp
      lower_tail_stmts_cmm env ((StmtExpr e):[]) bound_locals scope_vars sp st =
        lower_tail_return_cmm env e bound_locals scope_vars sp st
      lower_tail_stmts_cmm env ((StmtLet v e):rest) bound_locals scope_vars sp st
        | v == "_" =
          used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
          live_after = cmm_stmts_vars rest []
          dead_now = cmm_filter_not_in_list used_in_e live_after
          st1 = lower_expr env e bound_locals sp st
          st2 = nc_emit st1 NDropVal sp
          st3 = lower_cmm_drops env dead_now sp st2
      lower_tail_stmts_cmm env rest bound_locals scope_vars sp st3
        | otherwise =
          lower_tail_let_stmt env v e bound_locals scope_vars rest sp st
      lower_tail_stmts_cmm env ((StmtMut v e):rest) bound_locals scope_vars sp st =
        lower_tail_let_stmt env v e bound_locals scope_vars rest sp st
      lower_tail_stmts_cmm env ((StmtAtomic v e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        dead_now = cmm_filter_not_in_list used_in_e live_after
        off = env_str_off env v
        st1 = lower_expr env e bound_locals sp st
        st2 = nc_emit st1 (NStoreShared off (str_len v)) sp
        st3 = lower_cmm_drops env dead_now sp st2
        lower_tail_stmts_cmm env rest bound_locals scope_vars sp st3
      lower_tail_stmts_cmm env ((StmtIndexAssign t idxs e):rest) bound_locals scope_vars sp st =
        count = rexpr_list_len idxs
        tslot = env_var_slot env t
        st1 = lower_expr_list_to_slots env idxs bound_locals sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        st3 = nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        lower_tail_stmts_cmm env rest bound_locals scope_vars sp st3
      lower_tail_stmts_cmm env ((StmtExpr e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        dead_now = cmm_filter_not_in_list used_in_e live_after
        st1 = lower_expr env e bound_locals sp st
        st2 = nc_emit st1 NDropVal sp
        st3 = lower_cmm_drops env dead_now sp st2
        lower_tail_stmts_cmm env rest bound_locals scope_vars sp st3

fn :: lower_tail_where_cmm RNativeEnv [RWhereBind] RExpr [String] [String] Int RNativeCode => RNativeCode
      lower_tail_where_cmm env [] body bound_locals scope_vars sp st =
        lower_tail_return_cmm env body bound_locals scope_vars sp st
      lower_tail_where_cmm env ((WhereBind e v []):wbs) body bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_where_vars wbs body []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        st1 = lower_expr env e bound_locals sp st
        st2 = lower_let_var_store env v bound_locals sp st1
        st3 = lower_cmm_drops env dead_inputs sp st2
        st4 = lower_unused_let_drop env v live_after sp st3
        lower_tail_where_cmm env wbs body (add_unique_str v bound_locals) (add_unique_str v scope_vars) sp st4
      lower_tail_where_cmm env ((WhereBind e v idxs):wbs) body bound_locals scope_vars sp st =
        count = int_list_len idxs
        tslot = env_var_slot env v
        st1 = lower_int_list_to_slots idxs sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        st3 = nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        lower_tail_where_cmm env wbs body bound_locals scope_vars sp st3

-- ── Pattern Matching & Binding Lowering ──────────────────────

fn :: pat_needs_check RPattern       => Bool
      pat_needs_check PatWild        =  False
      pat_needs_check (PatVar _)     =  False
      pat_needs_check (PatSeqBind _) =  False
      pat_needs_check _              =  True

fn :: pat_has_vars RPattern         => Bool
      pat_has_vars (PatVar _)       =  True
      pat_has_vars (PatSeqBind _)   =  True
      pat_has_vars (PatCons h t)    =  (pat_has_vars h) OR (pat_has_vars t)
      pat_has_vars (PatTuple ps)    =  pat_list_has_vars ps
      pat_has_vars (PatCtor _ args) =  pat_list_has_vars args
      pat_has_vars _                =  False

fn :: pat_list_has_vars [RPattern] => Bool
      pat_list_has_vars []         =  False
      pat_list_has_vars (p:ps)
        | pat_has_vars p = True
        | otherwise = pat_list_has_vars ps

fn :: lower_pat_cond RNativeEnv RPattern Int Int Int RNativeCode => RNativeCode
      lower_pat_cond _ PatWild _ _ _ st = st
      lower_pat_cond _ (PatVar _) _ _ _ st = st
      lower_pat_cond _ (PatSeqBind _) _ _ _ st = st
      lower_pat_cond _ (PatInt n) slot fail_lbl sp st =
        nc_emit_list st [NMatchInt slot n, NJumpIfZero fail_lbl] sp
      lower_pat_cond env (PatReal r) slot fail_lbl sp st =
        off = env_str_off env r
        nc_emit_list st [NMatchReal slot off (str_len r), NJumpIfZero fail_lbl] sp
      lower_pat_cond env (PatStr s) slot fail_lbl sp st =
        off = env_str_off env s
        nc_emit_list st [NMatchStr slot off (str_len s), NJumpIfZero fail_lbl] sp
      lower_pat_cond _ (PatBool True) slot fail_lbl sp st =
        nc_emit_list st [NMatchBool slot 1, NJumpIfZero fail_lbl] sp
      lower_pat_cond _ (PatBool False) slot fail_lbl sp st =
        nc_emit_list st [NMatchBool slot 0, NJumpIfZero fail_lbl] sp
      lower_pat_cond _ PatEmpty slot fail_lbl sp st =
        nc_emit_list st [NMatchEmpty slot, NJumpIfZero fail_lbl] sp
      lower_pat_cond env (PatCons h t) slot fail_lbl sp st =
        st1 = nc_emit_list st [NMatchNonEmpty slot, NJumpIfZero fail_lbl] sp
        st2 = lower_pat_cons_sub env h slot True fail_lbl sp st1
        lower_pat_cons_sub env t slot False fail_lbl sp st2
      lower_pat_cond env (PatTuple ps) slot fail_lbl sp st =
        arity = pat_list_len ps
        st1 = nc_emit_list st [NMatchTuple slot arity, NJumpIfZero fail_lbl] sp
        lower_tuple_pat_conds env ps slot 0 fail_lbl sp st1
      lower_pat_cond env (PatCtor c (sub_p:[])) slot fail_lbl sp st
        | (prim_type_tag_id c) > 0 =
          st1 = nc_emit_list st [NMatchAdt slot 0 0 (0 - (prim_type_tag_id c)), NJumpIfZero fail_lbl] sp
          lower_pat_cond env sub_p slot fail_lbl sp st1
      lower_pat_cond env (PatCtor c args) slot fail_lbl sp st =
        arity = pat_list_len args
        off = env_str_off env c
        st1 = nc_emit_list st [NMatchAdt slot off (str_len c) arity, NJumpIfZero fail_lbl] sp
        lower_adt_pat_conds env args slot 0 fail_lbl sp st1

fn :: lower_pat_cons_sub RNativeEnv RPattern Int Bool Int Int RNativeCode => RNativeCode
      lower_pat_cons_sub env sub_p slot is_head fail_lbl sp st
        | NOT (pat_needs_check sub_p) = st
        | is_head =
          st1 = nc_emit_list st [NListHead slot, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_cond env sub_p sp fail_lbl (sp + 1) st1
          nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
        | otherwise =
          st1 = nc_emit_list st [NListTail slot, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_cond env sub_p sp fail_lbl (sp + 1) st1
          nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)

fn :: lower_tuple_pat_conds RNativeEnv [RPattern] Int Int Int Int RNativeCode => RNativeCode
      lower_tuple_pat_conds _ [] _ _ _ _ st = st
      lower_tuple_pat_conds env (p:ps) slot idx fail_lbl sp st
        | NOT (pat_needs_check p) = lower_tuple_pat_conds env ps slot (idx + 1) fail_lbl sp st
        | otherwise =
          st1 = nc_emit_list st [NTupleGet slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_cond env p sp fail_lbl (sp + 1) st1
          st3 = nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower_tuple_pat_conds env ps slot (idx + 1) fail_lbl sp st3

fn :: lower_adt_pat_conds RNativeEnv [RPattern] Int Int Int Int RNativeCode => RNativeCode
      lower_adt_pat_conds _ [] _ _ _ _ st = st
      lower_adt_pat_conds env (p:ps) slot idx fail_lbl sp st
        | NOT (pat_needs_check p) = lower_adt_pat_conds env ps slot (idx + 1) fail_lbl sp st
        | otherwise =
          st1 = nc_emit_list st [NAdtField slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_cond env p sp fail_lbl (sp + 1) st1
          st3 = nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower_adt_pat_conds env ps slot (idx + 1) fail_lbl sp st3

fn :: lower_pat_list_cond RNativeEnv [RPattern] Int Int Int RNativeCode => RNativeCode
      lower_pat_list_cond _ [] _ _ _ st = st
      lower_pat_list_cond env (p:ps) idx fail_lbl sp st =
        st1 = lower_pat_cond env p idx fail_lbl sp st
        lower_pat_list_cond env ps (idx + 1) fail_lbl sp st1

fn :: lower_pat_binds RNativeEnv RPattern Int Bool Int RNativeCode => RNativeCode
      lower_pat_binds env (PatVar v) slot True sp st =
        nc_emit_list st [NMoveSlot slot, NStoreSlot (env_var_slot env v)] sp
      lower_pat_binds env (PatVar v) slot False sp st =
        nc_emit_list st [NCloneSlot slot, NStoreSlot (env_var_slot env v)] sp
      lower_pat_binds env (PatSeqBind v) slot True sp st =
        nc_emit_list st [NMoveSlot slot, NStoreSlot (env_var_slot env v)] sp
      lower_pat_binds env (PatSeqBind v) slot False sp st =
        nc_emit_list st [NCloneSlot slot, NStoreSlot (env_var_slot env v)] sp
      lower_pat_binds env (PatCons h t) slot _ sp st =
        st1 = lower_pat_cons_bind env h slot True sp st
        lower_pat_cons_bind env t slot False sp st1
      lower_pat_binds env (PatTuple ps) slot _ sp st =
        lower_tuple_pat_binds env ps slot 0 sp st
      lower_pat_binds env (PatCtor c (sub_p:[])) slot move_ok sp st
        | (prim_type_tag_id c) > 0 =
          lower_pat_binds env sub_p slot move_ok sp st
      lower_pat_binds env (PatCtor _ args) slot _ sp st =
        lower_adt_pat_binds env args slot 0 sp st
      lower_pat_binds _ _ _ _ _ st = st

fn :: lower_pat_cons_bind RNativeEnv RPattern Int Bool Int RNativeCode => RNativeCode
      lower_pat_cons_bind env sub_p slot is_head sp st
        | NOT (pat_has_vars sub_p) = st
        | is_head =
          st1 = nc_emit_list st [NListHead slot, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_binds env sub_p sp True (sp + 1) st1
          nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
        | otherwise =
          st1 = nc_emit_list st [NListTail slot, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_binds env sub_p sp True (sp + 1) st1
          nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)

fn :: lower_tuple_pat_binds RNativeEnv [RPattern] Int Int Int RNativeCode => RNativeCode
      lower_tuple_pat_binds _ [] _ _ _ st = st
      lower_tuple_pat_binds env (p:ps) slot idx sp st
        | NOT (pat_has_vars p) = lower_tuple_pat_binds env ps slot (idx + 1) sp st
        | otherwise =
          st1 = nc_emit_list st [NTupleGet slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_binds env p sp True (sp + 1) st1
          st3 = nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower_tuple_pat_binds env ps slot (idx + 1) sp st3

fn :: lower_adt_pat_binds RNativeEnv [RPattern] Int Int Int RNativeCode => RNativeCode
      lower_adt_pat_binds _ [] _ _ _ st = st
      lower_adt_pat_binds env (p:ps) slot idx sp st
        | NOT (pat_has_vars p) = lower_adt_pat_binds env ps slot (idx + 1) sp st
        | otherwise =
          st1 = nc_emit_list st [NAdtField slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_binds env p sp True (sp + 1) st1
          st3 = nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower_adt_pat_binds env ps slot (idx + 1) sp st3

fn :: lower_pat_list_binds RNativeEnv [RPattern] Int Int Bool Int RNativeCode => RNativeCode
      lower_pat_list_binds _ [] _ _ _ _ st = st
      lower_pat_list_binds env ((PatSeqBind v):[]) _ arity _ sp st =
        nc_emit_list st [NPackSeq arity, NStoreSlot (env_var_slot env v)] sp
      lower_pat_list_binds env ((PatVar v):ps) idx arity True sp st =
        st1 = nc_emit_list st [NMoveSlot idx, NStoreSlot (env_var_slot env v)] sp
        lower_pat_list_binds env ps (idx + 1) arity True sp st1
      lower_pat_list_binds env (p:ps) idx arity move_args sp st =
        st1 = lower_pat_binds env p idx False sp st
        lower_pat_list_binds env ps (idx + 1) arity move_args sp st1

fn :: guards_have_otherwise [RGuard] => Bool
      guards_have_otherwise []       =  False
      guards_have_otherwise ((GuardBranch (EBool True) _):_) = True
      guards_have_otherwise (_:gs)   =  guards_have_otherwise gs

fn :: lower_case_guards RNativeEnv [RGuard] [String] Int RNativeCode => RNativeCode
      lower_case_guards _ [] _ _ st = st
      lower_case_guards env ((GuardBranch cond body):gs) bound_locals sp st =
        next_lbl = nc_lbl st
        st1 = nc_set_lbl st (next_lbl + 1)
        st2 = lower_expr env cond bound_locals sp st1
        st3 = nc_emit_list st2 [NAsBool, NJumpIfZero next_lbl] sp
        st4 = lower_tail_return env body bound_locals sp st3
        st5 = nc_emit st4 (NLabel next_lbl) sp
        lower_case_guards env gs bound_locals sp st5

fn :: lower_single_case RNativeEnv RFnCase Bool Int RNativeCode => RNativeCode
      lower_single_case env (FnCase pats [] body) _ sp st =
        arity = env_arity env
        fail_lbl = nc_lbl st
        st1 = nc_set_lbl st (fail_lbl + 1)
        st2 = lower_pat_list_cond env pats 0 fail_lbl sp st1
        st3 = lower_pat_list_binds env pats 0 arity True sp st2
        bound_locals = collect_pat_list_vars pats []
        st4 = lower_tail_return env body bound_locals sp st3
        nc_emit_list st4 [NLabel fail_lbl, NClearLocals arity (nc_max_sp st4)] sp
      lower_single_case env (FnCase pats guards _) is_last sp st =
        arity = env_arity env
        fail_lbl = nc_lbl st
        st1 = nc_set_lbl st (fail_lbl + 1)
        st2 = lower_pat_list_cond env pats 0 fail_lbl sp st1
        move_args = is_last OR (guards_have_otherwise guards)
        st3 = lower_pat_list_binds env pats 0 arity move_args sp st2
        bound_locals = collect_pat_list_vars pats []
        st4 = lower_case_guards env guards bound_locals sp st3
        nc_emit_list st4 [NLabel fail_lbl, NClearLocals arity (nc_max_sp st4)] sp

fn :: lower_cases_list RNativeEnv [RFnCase] Int RNativeCode => RNativeCode
      lower_cases_list _          []        _   st          =  st
      lower_cases_list env        (c:[])    sp  st          =  lower_single_case env c True sp st
      lower_cases_list env        (c:cs)    sp  st          =
        st1 = lower_single_case env c False sp st
        lower_cases_list env cs sp st1

fn :: lower_fndef RFnDef [RStrEntry] [RFnEntry] [RFieldEntry] => RNativeFn
      lower_fndef (FnDef name params _ cases) str_tbl fn_tbl field_tbl =
        fid = lookup_fn_id fn_tbl name
        arity = infer_fndef_arity params cases
        all_locals = collect_cases_all_locals cases []
        base_sp = arity + (list_str_len all_locals)
        env = NativeEnv name arity all_locals str_tbl fn_tbl field_tbl
        init_st = NativeCode [] 1 (max_int (base_sp + 1) 2)
        st1 = lower_cases_list env cases base_sp init_st
        st2 = nc_emit_list st1 [NLoadImmRaw 0, NReturn] (base_sp + 1)
        NativeFn fid name arity (nc_max_sp st2) (nc_instrs st2)

fn :: lower_fndef_list [RFnDef] [RStrEntry] [RFnEntry] [RFieldEntry] => [RNativeFn]
      lower_fndef_list [] _ _ _ = []
      lower_fndef_list (f:fs) str_tbl fn_tbl field_tbl =
        [lower_fndef f str_tbl fn_tbl field_tbl] :: (lower_fndef_list fs str_tbl fn_tbl field_tbl)

fn :: lower_field_getter_fns [RFieldEntry] [String] [RFnEntry] => [RNativeFn]
      lower_field_getter_fns []            _        _          =  []
      lower_field_getter_fns ((FieldEntry fname idx):rest) fn_names fn_tbl
        | str_in_list fname fn_names = lower_field_getter_fns rest fn_names fn_tbl
        | otherwise =
          fid = lookup_fn_id fn_tbl fname
          [NativeFn fid fname 1 2 [NAdtField 0 idx, NReturn]] :: (lower_field_getter_fns rest fn_names fn_tbl)

-- ── Call-Graph Tree-Shaking & Dispatch Function Synthesis ────

fn :: collect_refs_expr RExpr              [String] => [String]
      collect_refs_expr (EVar name)        acc      =  add_unique_str name acc
      collect_refs_expr (ENot inner)       acc      =  collect_refs_expr inner acc
      collect_refs_expr (EOut inner)       acc      =  collect_refs_expr inner acc
      collect_refs_expr (EBin bop l r)     acc      =  collect_refs_expr r (collect_refs_expr l (add_unique_str (binop_op_tag bop) acc))
      collect_refs_expr (ECall "spawn" ((EStr s):args)) acc = collect_refs_expr_list args (add_unique_str s (add_unique_str "spawn" acc))
      collect_refs_expr (ECall fname args) acc      =  collect_refs_expr_list args (add_unique_str fname acc)
      collect_refs_expr (EEcho args)       acc      =  collect_refs_expr_list args acc
      collect_refs_expr (EStrInterp parts) acc      =  collect_refs_expr_list parts acc
      collect_refs_expr (EList elems)      acc      =  collect_refs_expr_list elems acc
      collect_refs_expr (ETuple elems)     acc      =  collect_refs_expr_list elems acc
      collect_refs_expr (ETensor elems)    acc      =  collect_refs_expr_list elems acc
      collect_refs_expr (EEinsum es _)     acc      =  collect_refs_expr_list es acc
      collect_refs_expr (EHadamard _ l _ r _) acc   =  collect_refs_expr r (collect_refs_expr l acc)
      collect_refs_expr (EIndex base idxs) acc      =  collect_refs_expr_list idxs (collect_refs_expr base acc)
      collect_refs_expr (EIndexAssign _ idxs v) acc =  collect_refs_expr v (collect_refs_expr_list idxs acc)
      collect_refs_expr (ESeqSelect b _)   acc      =  collect_refs_expr b acc
      collect_refs_expr (EBlock stmts)     acc      =  collect_refs_stmts stmts acc
      collect_refs_expr (EGuard guards)    acc      =  collect_refs_guards guards acc
      collect_refs_expr (EWhere body binds) acc     =  collect_refs_where binds (collect_refs_expr body acc)
      collect_refs_expr (EParPipe branches) acc     =  collect_refs_expr_list branches acc
      collect_refs_expr (EWithCtx _ v b)   acc      =  collect_refs_expr b (collect_refs_expr v acc)
      collect_refs_expr (EWithRegion _ b)  acc      =  collect_refs_expr b acc
      collect_refs_expr (EAtomicUpdate _ e) acc     =  collect_refs_expr e acc
      collect_refs_expr (ELoadContext _ e) acc      =  collect_refs_expr e acc
      collect_refs_expr (ELoadShared _ e)  acc      =  collect_refs_expr e acc
      collect_refs_expr _                  acc      =  acc

fn :: collect_refs_expr_list [RExpr] [String] => [String]
      collect_refs_expr_list []      acc      =  acc
      collect_refs_expr_list (e:es)  acc      =  collect_refs_expr_list es (collect_refs_expr e acc)

fn :: collect_refs_stmts [RStmt]            [String] => [String]
      collect_refs_stmts []                 acc      =  acc
      collect_refs_stmts ((StmtLet _ e):ss) acc      =  collect_refs_stmts ss (collect_refs_expr e acc)
      collect_refs_stmts ((StmtMut _ e):ss) acc      =  collect_refs_stmts ss (collect_refs_expr e acc)
      collect_refs_stmts ((StmtExpr e):ss)  acc      =  collect_refs_stmts ss (collect_refs_expr e acc)
      collect_refs_stmts ((StmtAtomic _ e):ss) acc   =  collect_refs_stmts ss (collect_refs_expr e acc)
      collect_refs_stmts ((StmtIndexAssign _ idxs e):ss) acc =
        collect_refs_stmts ss (collect_refs_expr e (collect_refs_expr_list idxs acc))

fn :: collect_refs_where [RWhereBind] [String] => [String]
      collect_refs_where []           acc      =  acc
      collect_refs_where ((WhereBind e _ _):wbs) acc = collect_refs_where wbs (collect_refs_expr e acc)

fn :: collect_refs_guards [RGuard] [String] => [String]
      collect_refs_guards []       acc      =  acc
      collect_refs_guards ((GuardBranch c b):gs) acc =
        collect_refs_guards gs (collect_refs_expr b (collect_refs_expr c acc))

fn :: collect_refs_cases [RFnCase] [String] => [String]
      collect_refs_cases []        acc      =  acc
      collect_refs_cases ((FnCase _ guards body):cs) acc =
        collect_refs_cases cs (collect_refs_expr body (collect_refs_guards guards acc))

fn :: find_fndef_cases [RFnDef] String => [RFnCase]
      find_fndef_cases []       _      =  []
      find_fndef_cases ((FnDef name _ _ cases):fs) target
        | name == target = cases
        | otherwise = find_fndef_cases fs target

fn :: expand_reachable_worklist [String] [RFnDef] [String] => [String]
      expand_reachable_worklist []       _        visited  =  visited
      expand_reachable_worklist (w:ws)   all_fns  visited
        | str_in_list w visited = expand_reachable_worklist ws all_fns visited
        | otherwise = expand_reachable_worklist (ws :: (collect_refs_cases (find_fndef_cases all_fns w) [])) all_fns (visited :: [w])

fn :: filter_reachable_fndefs [RFnDef] [String]  => [RFnDef]
      filter_reachable_fndefs []       _         =  []
      filter_reachable_fndefs ((FnDef name params ret cases):fs) reachable
        | str_in_list name reachable = [FnDef name params ret cases] :: (filter_reachable_fndefs fs reachable)
        | otherwise = filter_reachable_fndefs fs reachable

fn :: collect_fn_names [RFnDef] => [String]
      collect_fn_names []       =  []
      collect_fn_names ((FnDef name _ _ _):fs) = [name] :: (collect_fn_names fs)

fn :: find_entry_fn_name [RFnDef] String   => String
      find_entry_fn_name []       fallback =  fallback
      find_entry_fn_name ((FnDef name params _ cases):fs) fallback
        | name == "main" = "main"
        | name == "demo_all" = "demo_all"
        | (infer_fndef_arity params cases) == 0 = find_entry_fn_name fs name
        | otherwise = find_entry_fn_name fs fallback

fn :: build_spawn_dispatch_instrs [RFnEntry] [RStrEntry] Int [RNativeInstr] => [RNativeInstr]
      build_spawn_dispatch_instrs [] _ _ acc =
        acc :: [NLoadImmRaw 0, NReturn]
      build_spawn_dispatch_instrs ((FnEntry name fid arity):rest) str_tbl lbl acc
        | arity == 1 =
          off = lookup_str_off str_tbl name
          arm = [NMatchStr 0 off (str_len name), NJumpIfZero lbl, NMoveSlot 1, NStoreSlot 2, NCallFn fid 2 1, NReturn, NLabel lbl]
      build_spawn_dispatch_instrs rest str_tbl (lbl + 1) (acc :: arm)
        | otherwise =
          build_spawn_dispatch_instrs rest str_tbl lbl acc

fn :: build_call2_dispatch_instrs [RFnEntry] [RStrEntry] Int [RNativeInstr] => [RNativeInstr]
      build_call2_dispatch_instrs [] _ _ acc =
        acc :: [NLoadImmRaw 0, NReturn]
      build_call2_dispatch_instrs ((FnEntry name fid arity):rest) str_tbl lbl acc
        | arity == 2 =
          off = lookup_str_off str_tbl name
          arm = [NMatchStr 0 off (str_len name), NJumpIfZero lbl, NMoveSlot 1, NStoreSlot 3, NMoveSlot 2, NStoreSlot 4, NCallFn fid 3 2, NReturn, NLabel lbl]
      build_call2_dispatch_instrs rest str_tbl (lbl + 1) (acc :: arm)
        | otherwise =
          build_call2_dispatch_instrs rest str_tbl lbl acc

fn :: is_overloadable_binop_name String => Bool
      is_overloadable_binop_name "+"    =  True
      is_overloadable_binop_name "-"    =  True
      is_overloadable_binop_name "*"    =  True
      is_overloadable_binop_name "/"    =  True
      is_overloadable_binop_name "%"    =  True
      is_overloadable_binop_name _      =  False

fn :: build_binop_dispatch_instrs [RFnEntry] [RStrEntry] Int [RNativeInstr] => [RNativeInstr]
      build_binop_dispatch_instrs [] _ _ acc =
        acc :: [NLoadImmRaw 0, NReturn]
      build_binop_dispatch_instrs ((FnEntry name fid arity):rest) str_tbl lbl acc
        | arity == 2 AND (is_overloadable_binop_name name) =
          off = lookup_str_off str_tbl name
          arm = [NMatchStr 0 off (str_len name), NJumpIfZero lbl, NMoveSlot 1, NStoreSlot 3, NMoveSlot 2, NStoreSlot 4, NCallFn fid 3 2, NReturn, NLabel lbl]
      build_binop_dispatch_instrs rest str_tbl (lbl + 1) (acc :: arm)
        | otherwise =
          build_binop_dispatch_instrs rest str_tbl lbl acc

fn :: lower_program_to_native RProgram => RNativeProg
      lower_program_to_native (Program raw_fns tys) =
        field_tbl = collect_typedef_fields tys []
        raw_fn_names = collect_fn_names raw_fns
        sigs = (build_cg_sigs raw_fns) :: (build_field_cg_sigs field_tbl raw_fn_names)
        all_fns = prep_fndef_list raw_fns sigs
        entry_name = find_entry_fn_name all_fns "main"
        reachable = expand_reachable_worklist [entry_name] all_fns []
        fns = filter_reachable_fndefs all_fns reachable
        fn_names = collect_fn_names fns
        str_pool = build_str_pool fns (collect_field_names field_tbl)
        rodata_str = pool_rodata str_pool
        str_tbl = pool_entries str_pool
        fn_tbl1 = build_fn_table_fndefs fns 5 []
        fn_tbl = build_fn_table_fields field_tbl fn_names (5 + (list_str_len fn_names)) fn_tbl1
        entry_fid = lookup_fn_id fn_tbl entry_name
        main_wrapper = NativeFn 1 "__rg_entry_main" 0 2 [NCallFn entry_fid 0 0, NReturn]
        spawn_disp = NativeFn 2 "__rg_dispatch_spawn" 2 4 (build_spawn_dispatch_instrs fn_tbl str_tbl 1 [])
        call2_disp = NativeFn 3 "__rg_dispatch_call2" 3 6 (build_call2_dispatch_instrs fn_tbl str_tbl 1 [])
        binop_disp = NativeFn 4 "__rg_dispatch_binop" 3 6 (build_binop_dispatch_instrs fn_tbl str_tbl 1 [])
        user_native_fns = lower_fndef_list fns str_tbl fn_tbl field_tbl
        field_native_fns = lower_field_getter_fns field_tbl fn_names fn_tbl
        all_native_fns = [main_wrapper, spawn_disp, call2_disp, binop_disp] :: user_native_fns :: field_native_fns
        NativeProg 1 2 3 4 all_native_fns rodata_str

fn :: build_lib_entry_wrapper Int       => RNativeFn
      build_lib_entry_wrapper 0         =  NativeFn 1 "__rg_entry_main" 0 2 [NLoadImmRaw 0, NReturn]
      build_lib_entry_wrapper entry_fid =  NativeFn 1 "__rg_entry_main" 0 2 [NCallFn entry_fid 0 0, NReturn]

fn :: lower_library_to_native RProgram => RNativeProg
      lower_library_to_native (Program raw_fns tys) =
        field_tbl = collect_typedef_fields tys []
        raw_fn_names = collect_fn_names raw_fns
        sigs = (build_cg_sigs raw_fns) :: (build_field_cg_sigs field_tbl raw_fn_names)
        fns = prep_fndef_list raw_fns sigs
        fn_names = collect_fn_names fns
        str_pool = build_str_pool fns (collect_field_names field_tbl)
        rodata_str = pool_rodata str_pool
        str_tbl = pool_entries str_pool
        fn_tbl1 = build_fn_table_fndefs fns 5 []
        fn_tbl = build_fn_table_fields field_tbl fn_names (5 + (list_str_len fn_names)) fn_tbl1
        entry_fid = lookup_fn_id fn_tbl "main"
        main_wrapper = build_lib_entry_wrapper entry_fid
        spawn_disp = NativeFn 2 "__rg_dispatch_spawn" 2 4 (build_spawn_dispatch_instrs fn_tbl str_tbl 1 [])
        call2_disp = NativeFn 3 "__rg_dispatch_call2" 3 6 (build_call2_dispatch_instrs fn_tbl str_tbl 1 [])
        binop_disp = NativeFn 4 "__rg_dispatch_binop" 3 6 (build_binop_dispatch_instrs fn_tbl str_tbl 1 [])
        user_native_fns = lower_fndef_list fns str_tbl fn_tbl field_tbl
        field_native_fns = lower_field_getter_fns field_tbl fn_names fn_tbl
        all_native_fns = [main_wrapper, spawn_disp, call2_disp, binop_disp] :: user_native_fns :: field_native_fns
        NativeProg 1 2 3 4 all_native_fns rodata_str

-- ── Bytecode (.rgc), Library (.rglib / .so), & ELF64 Emission ─

fn :: join_summaries [String] => String
      join_summaries []       =  ""
      join_summaries (s:ss)   =  "-- SUMMARY: {s}\n" + (join_summaries ss)

fn :: emit_rgc_payload RProgram String  => String
      emit_rgc_payload prog     raw_src =
        fn_count = count_fn_defs prog
        ty_count = count_type_defs prog
        summaries = join_summaries (analyze_rprogram prog)
        "RGC1\n-- SELF_HOSTED_COMPILER: ridgunc v0.9.4\n-- FUNCTIONS: {fn_count}\n-- TYPES: {ty_count}\n{summaries}{raw_src}"

fn :: emit_rgc_file String     String      => Int
      emit_rgc_file input_path output_path =
        raw_src = load_rg_with_libs input_path
        toks = tokenize_src raw_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        emit_rgc_after_check prog raw_src output_path errs

fn :: emit_rgc_after_check RProgram String  String      [RTypeError] => Int
      emit_rgc_after_check prog     raw_src output_path []           =
        payload = emit_rgc_payload prog raw_src
        _ = write_file output_path payload
        count_fn_defs prog
      emit_rgc_after_check _        _       _           errs         =
        _ = echo (format_type_errors errs)
        0 - (type_err_count errs)

fn :: emit_rglib_payload RProgram String  => String
      emit_rglib_payload prog     raw_src =
        fn_count = count_fn_defs prog
        ty_count = count_type_defs prog
        summaries = join_summaries (analyze_rprogram prog)
        "-- RGLIB1\n-- SELF_HOSTED_COMPILER: ridgunc v0.9.4\n-- FUNCTIONS: {fn_count}\n-- TYPES: {ty_count}\n{summaries}{raw_src}"

fn :: emit_rglib_file String     String      => Int
      emit_rglib_file input_path output_path =
        raw_src = load_rg_with_libs input_path
        toks = tokenize_src raw_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        emit_rglib_after_check prog raw_src output_path errs

fn :: emit_rglib_after_check RProgram String  String      [RTypeError] => Int
      emit_rglib_after_check prog     raw_src output_path []           =
        payload = emit_rglib_payload prog raw_src
        _ = write_file output_path payload
        0
      emit_rglib_after_check _        _       _           errs         =
        _ = echo (format_type_errors errs)
        1

fn :: emit_elf_for_target RNativeProg String        => [Int]
      emit_elf_for_target nprog       "arm64"       =  emit_arm64_elf nprog
      emit_elf_for_target nprog       "arm64-linux" =  emit_arm64_elf nprog
      emit_elf_for_target nprog       "aarch64"     =  emit_arm64_elf nprog
      emit_elf_for_target nprog       _             =  emit_x86_64_elf nprog

fn :: emit_shared_elf_for_target RNativeProg String        => [Int]
      emit_shared_elf_for_target nprog       "arm64"       =  emit_arm64_shared_elf nprog
      emit_shared_elf_for_target nprog       "arm64-linux" =  emit_arm64_shared_elf nprog
      emit_shared_elf_for_target nprog       "aarch64"     =  emit_arm64_shared_elf nprog
      emit_shared_elf_for_target nprog       _             =  emit_x86_64_shared_elf nprog

fn :: build_native_target_executable String     String     String      => Int
      build_native_target_executable input_path output_bin target_arch =
        raw_src = load_rg_with_libs input_path
        toks = tokenize_src raw_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        build_native_target_after_check prog output_bin target_arch errs

fn :: build_native_target_after_check RProgram String String [RTypeError] => Int
      build_native_target_after_check prog output_bin target_arch [] =
        nprog = lower_program_to_native prog
        elf_bytes = emit_elf_for_target nprog target_arch
        write_elf64_executable output_bin elf_bytes
      build_native_target_after_check _ _ _ errs =
        _ = echo (format_type_errors errs)
        1

fn :: build_native_target_shared_library String     String    String      => Int
      build_native_target_shared_library input_path output_so target_arch =
        raw_src = load_rg_with_libs input_path
        toks = tokenize_src raw_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        build_native_shared_after_check prog output_so target_arch errs

fn :: build_native_shared_after_check RProgram String String [RTypeError] => Int
      build_native_shared_after_check prog output_so target_arch [] =
        nprog = lower_library_to_native prog
        elf_bytes = emit_shared_elf_for_target nprog target_arch
        write_elf64_executable output_so elf_bytes
      build_native_shared_after_check _ _ _ errs =
        _ = echo (format_type_errors errs)
        1

fn :: build_native_shared_library String     String    => Int
      build_native_shared_library input_path output_so =
        build_native_target_shared_library input_path output_so "x86_64-linux"

fn :: build_native_executable String     String     => Int
      build_native_executable input_path output_bin =
        build_native_target_executable input_path output_bin "x86_64-linux"

fn :: build_native_fast_executable String     String     => Int
      build_native_fast_executable input_path output_bin =
        build_native_target_executable input_path output_bin "x86_64-linux"
