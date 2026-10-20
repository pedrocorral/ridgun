-- ============================================================
-- src/main/ridgun/compiler.rg
-- Self-Hosted Ridgun AST-to-Bytecode & Native AOT Compiler
-- Full Ridgun v0.9.0 Spec: Sum & Record ADTs, Operator Overloading,
-- Variadics, Sequences/Masks/FlatJoin, Tensors/Einsum/Hadamard,
-- Where-DAGs, ParPipes, Channels/Spawn/Join, Scoped Globals/Context/
-- Shared Atomics, and Bare-Metal Hardware MMIO & Region Quotas.
-- @implements FR-COMP-001
-- @implements FR-VM-001
-- @implements FR-VM-002
-- ============================================================
import ast
import lexer
import parser
import analyzer
import typecheck

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

fn :: compile_rblock [RStmt]           [String] => ([RInstr], [String])
      compile_rblock []                locals   =  ([BPushUnit], locals)
      compile_rblock ((StmtExpr e):[]) locals   =  compile_rexpr e locals
      compile_rblock ((StmtLet v e):rest) locals =
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

-- ── Native Code Generator (RProgram => Standalone Native Code) ──

fn :: mangle_fn_name String => String
      mangle_fn_name "+"    =  "rg_fn___op_add"
      mangle_fn_name "-"    =  "rg_fn___op_sub"
      mangle_fn_name "*"    =  "rg_fn___op_mul"
      mangle_fn_name "/"    =  "rg_fn___op_div"
      mangle_fn_name "%"    =  "rg_fn___op_mod"
      mangle_fn_name name   =  "rg_fn_" + name

fn :: escape_char_rust Int => String
      escape_char_rust c
        | c == 92 = (char_from_code 92) + (char_from_code 92)
        | c == 34 = (char_from_code 92) + (char_from_code 34)
        | c == 10 = (char_from_code 92) + "n"
        | c == 13 = (char_from_code 92) + "r"
        | c == 9 = (char_from_code 92) + "t"
        | otherwise = char_from_code c

fn :: needs_escape String => Bool
      needs_escape s      =
        (str_contains s (char_from_code 92)) OR (str_contains s (char_from_code 34)) OR (str_contains s (char_from_code 10)) OR (str_contains s (char_from_code 13)) OR (str_contains s (char_from_code 9))

fn :: escape_rust_range String Int   Int => String
      escape_rust_range s      start end
        | end <= start = ""
        | NOT (needs_escape (str_slice s start end)) = str_slice s start end
        | (end - start) == 1 = escape_char_rust (str_char_at s start)
        | otherwise = (escape_rust_range s start ((start + end) / 2)) + (escape_rust_range s ((start + end) / 2) end)

fn :: escape_rust_str String => String
      escape_rust_str s      =  escape_rust_range s 0 (str_len s)

fn :: find_char_from String Int Int Int       => Int
      find_char_from s      pos len target_ch
        | pos >= len = len
        | (str_char_at s pos) == target_ch = pos
        | otherwise = find_char_from s (pos + 1) len target_ch

fn :: emit_interp_loop String Int Int [String] => String
      emit_interp_loop s      pos len locals
        | pos >= len = 'rg_str("")'
        | otherwise = emit_interp_at s pos len locals (find_char_from s pos len 123)

fn :: emit_interp_at String Int Int [String] Int => String
      emit_interp_at s pos len locals open_idx
        | open_idx >= len = 'rg_str("' + (escape_rust_str (str_slice s pos len)) + '")'
        | otherwise = emit_interp_close s pos len locals open_idx (find_char_from s (open_idx + 1) len 125)

fn :: emit_interp_close String Int Int [String] Int Int => String
      emit_interp_close s pos len locals open_idx close_idx
        | close_idx >= len = 'rg_str("' + (escape_rust_str (str_slice s pos len)) + '")'
        | otherwise = emit_interp_check s pos len locals open_idx close_idx (str_slice s (open_idx + 1) close_idx)

fn :: emit_interp_check String Int Int [String] Int Int String => String
      emit_interp_check s pos len locals open_idx close_idx cand
        | (lookup_local locals cand) >= 0 = 'rg_fn_str_concat(rg_str("' + (escape_rust_str (str_slice s pos open_idx)) + '"), rg_fn_str_concat(rg_to_str(&lv_' + cand + '), ' + (emit_interp_loop s (close_idx + 1) len locals) + '))'
        | otherwise = 'rg_fn_str_concat(rg_str("' + (escape_rust_str (str_slice s pos (open_idx + 1))) + '"), ' + (emit_interp_loop s (open_idx + 1) len locals) + ')'

fn :: emit_str_lit String [String] => String
      emit_str_lit s      _        =  'rg_str("' + (escape_rust_str s) + '")'

-- ── Pattern Lowering to Native Rust Conditions & Bindings ───

fn :: emit_pat_cond RPattern        String => String
      emit_pat_cond PatWild         _      =  'true'
      emit_pat_cond (PatVar _)      _      =  'true'
      emit_pat_cond (PatSeqBind _)  _      =  'true'
      emit_pat_cond (PatInt n)      scrut  =  'rg_match_int(' + scrut + ', ' + (int_to_str n) + ')'
      emit_pat_cond (PatReal r)     scrut  =  'rg_match_real(' + scrut + ', ' + r + ')'
      emit_pat_cond (PatStr s)      scrut  =  'rg_match_str(' + scrut + ', "' + (escape_rust_str s) + '")'
      emit_pat_cond (PatBool True)  scrut  =  'rg_match_bool(' + scrut + ', true)'
      emit_pat_cond (PatBool False) scrut  =  'rg_match_bool(' + scrut + ', false)'
      emit_pat_cond PatEmpty        scrut  =  'rg_is_empty(' + scrut + ')'
      emit_pat_cond (PatCons h t)   scrut  =
        '(rg_is_non_empty(' + scrut + ') && ' + (emit_pat_cond h ('(&rg_list_head(' + scrut + '))')) + ' && ' + (emit_pat_cond t ('(&rg_list_tail(' + scrut + '))')) + ')'
      emit_pat_cond (PatTuple ps)   scrut  =
        '(rg_is_tuple(' + scrut + ', ' + (int_to_str (pat_list_len ps)) + ') && ' + (emit_tuple_pat_conds ps scrut 0) + ')'
      emit_pat_cond (PatCtor ctor args) scrut =
        '(rg_is_adt(' + scrut + ', "' + ctor + '", ' + (int_to_str (pat_list_len args)) + ') && ' + (emit_adt_pat_conds args scrut 0) + ')'

fn :: emit_tuple_pat_conds [RPattern] String Int => String
      emit_tuple_pat_conds []         _      _   =  'true'
      emit_tuple_pat_conds (p:ps)     scrut  idx =
        sub_scrut = '(&rg_tuple_get(' + scrut + ', ' + (int_to_str idx) + '))'
        (emit_pat_cond p sub_scrut) + ' && ' + (emit_tuple_pat_conds ps scrut (idx + 1))

fn :: emit_adt_pat_conds [RPattern] String Int => String
      emit_adt_pat_conds []         _      _   =  'true'
      emit_adt_pat_conds (p:ps)     scrut  idx =
        sub_scrut = '(&rg_adt_field(' + scrut + ', ' + (int_to_str idx) + '))'
        (emit_pat_cond p sub_scrut) + ' && ' + (emit_adt_pat_conds ps scrut (idx + 1))

fn :: emit_pat_list_cond [RPattern] Int => String
      emit_pat_list_cond []         _   =  'true'
      emit_pat_list_cond (p:[])     idx =  emit_pat_cond p ('&_arg_' + (int_to_str idx))
      emit_pat_list_cond (p:ps)     idx =
        (emit_pat_cond p ('&_arg_' + (int_to_str idx))) + ' && ' + (emit_pat_list_cond ps (idx + 1))

fn :: emit_seq_arg_clones Int Int   => String
      emit_seq_arg_clones idx arity
        | idx >= arity = ""
        | (idx + 1) == arity = '_arg_' + (int_to_str idx) + '.clone()'
        | otherwise = '_arg_' + (int_to_str idx) + '.clone(), ' + (emit_seq_arg_clones (idx + 1) arity)

fn :: emit_pat_binds RPattern         String => String
      emit_pat_binds (PatVar v)       scrut  =  "    let mut lv_" + v + ": RVal = (" + scrut + ").clone();\n"
      emit_pat_binds (PatSeqBind v)   scrut  =  "    let mut lv_" + v + ": RVal = (" + scrut + ").clone();\n"
      emit_pat_binds (PatCons h t)    scrut  =
        (emit_pat_binds h ('(&rg_list_head(' + scrut + '))')) + (emit_pat_binds t ('(&rg_list_tail(' + scrut + '))'))
      emit_pat_binds (PatTuple ps)    scrut  =  emit_tuple_pat_binds ps scrut 0
      emit_pat_binds (PatCtor _ args) scrut  =  emit_adt_pat_binds args scrut 0
      emit_pat_binds _                _      =  ""

fn :: emit_tuple_pat_binds [RPattern] String Int => String
      emit_tuple_pat_binds []         _      _   =  ""
      emit_tuple_pat_binds (p:ps)     scrut  idx =
        sub_scrut = '(&rg_tuple_get(' + scrut + ', ' + (int_to_str idx) + '))'
        (emit_pat_binds p sub_scrut) + (emit_tuple_pat_binds ps scrut (idx + 1))

fn :: emit_adt_pat_binds [RPattern] String Int => String
      emit_adt_pat_binds []         _      _   =  ""
      emit_adt_pat_binds (p:ps)     scrut  idx =
        sub_scrut = '(&rg_adt_field(' + scrut + ', ' + (int_to_str idx) + '))'
        (emit_pat_binds p sub_scrut) + (emit_adt_pat_binds ps scrut (idx + 1))

fn :: emit_pat_list_binds [RPattern] Int Int   => String
      emit_pat_list_binds []         _   _     =  ""
      emit_pat_list_binds ((PatSeqBind v):[]) _ arity =
        "    let mut lv_" + v + ": RVal = rg_pack_seq(vec![" + (emit_seq_arg_clones 0 arity) + "]);\n"
      emit_pat_list_binds (p:ps)     idx arity =
        (emit_pat_binds p ('&_arg_' + (int_to_str idx))) + (emit_pat_list_binds ps (idx + 1) arity)

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

-- ── Ridgun Memory Management (RMM2) Local Variable Liveness Pass ──
-- @implements FR-COMP-002

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
      cmm_expr_vars (EWhere body binds) acc     =  cmm_where_vars binds body acc
      cmm_expr_vars (EParPipe branches) acc     =  cmm_expr_list_vars branches acc
      cmm_expr_vars (EWithCtx _ v b)   acc      =  cmm_expr_vars b (cmm_expr_vars v acc)
      cmm_expr_vars (EWithRegion _ b)  acc      =  cmm_expr_vars b acc
      cmm_expr_vars (EAtomicUpdate _ e) acc     =  cmm_expr_vars e acc
      cmm_expr_vars (ELoadContext _ e) acc      =  cmm_expr_vars e acc
      cmm_expr_vars (ELoadShared _ e)  acc      =  cmm_expr_vars e acc
      cmm_expr_vars _                  acc      =  acc

fn :: cmm_expr_list_vars [RExpr] [String] => [String]
      cmm_expr_list_vars []      acc      =  acc
      cmm_expr_list_vars (e:es)  acc      =  cmm_expr_list_vars es (cmm_expr_vars e acc)

fn :: cmm_stmts_vars [RStmt]            [String] => [String]
      cmm_stmts_vars []                 acc      =  acc
      cmm_stmts_vars ((StmtLet _ e):ss) acc      =  cmm_stmts_vars ss (cmm_expr_vars e acc)
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

fn :: emit_cmm_uncond_drops [String] String => String
      emit_cmm_uncond_drops []       _      =  ""
      emit_cmm_uncond_drops (x:xs)   indent =
        indent + "rg_cmm_drop(&mut lv_" + x + ");\n" + (emit_cmm_uncond_drops xs indent)

-- ── Expression & Statement Lowering to Native Rust ──────────

fn :: binop_op_tag RBinOp => String
      binop_op_tag OpAdd  =  "+"
      binop_op_tag OpSub  =  "-"
      binop_op_tag OpMul  =  "*"
      binop_op_tag OpDiv  =  "/"
      binop_op_tag OpMod  =  "%"
      binop_op_tag _      =  "+"

fn :: emit_binop_rust RBinOp     String String => String
      emit_binop_rust OpAdd      lc     rc     =  'rg_add(' + lc + ', ' + rc + ')'
      emit_binop_rust OpSub      lc     rc     =  'rg_sub(' + lc + ', ' + rc + ')'
      emit_binop_rust OpMul      lc     rc     =  'rg_mul(' + lc + ', ' + rc + ')'
      emit_binop_rust OpDiv      lc     rc     =  'rg_div(' + lc + ', ' + rc + ')'
      emit_binop_rust OpMod      lc     rc     =  'rg_mod(' + lc + ', ' + rc + ')'
      emit_binop_rust OpEq       lc     rc     =  'RVal::Bool((' + lc + ') == (' + rc + '))'
      emit_binop_rust OpNeq      lc     rc     =  'RVal::Bool((' + lc + ') != (' + rc + '))'
      emit_binop_rust OpGt       lc     rc     =  'rg_cmp_gt(&(' + lc + '), &(' + rc + '))'
      emit_binop_rust OpLt       lc     rc     =  'rg_cmp_lt(&(' + lc + '), &(' + rc + '))'
      emit_binop_rust OpGtEq     lc     rc     =  'rg_cmp_gte(&(' + lc + '), &(' + rc + '))'
      emit_binop_rust OpLtEq     lc     rc     =  'rg_cmp_lte(&(' + lc + '), &(' + rc + '))'
      emit_binop_rust OpAnd      lc     rc     =  'RVal::Bool(rg_as_bool(&(' + lc + ')) && rg_as_bool(&(' + rc + ')))'
      emit_binop_rust OpOr       lc     rc     =  'RVal::Bool(rg_as_bool(&(' + lc + ')) || rg_as_bool(&(' + rc + ')))'
      emit_binop_rust OpXor      lc     rc     =  'RVal::Bool(rg_as_bool(&(' + lc + ')) ^ rg_as_bool(&(' + rc + ')))'
      emit_binop_rust OpConcat   lc     rc     =  'rg_list_concat(' + lc + ', ' + rc + ')'
      emit_binop_rust OpFlatJoin lc     rc     =  'rg_seq_flat_join(' + lc + ', ' + rc + ')'
      emit_binop_rust OpMatMul   lc     rc     =  'rg_einsum(&[' + lc + ', ' + rc + '], &["ij", "jk"])'

fn :: emit_str_csv [String] => String
      emit_str_csv []       =  ""
      emit_str_csv (s:[])   =  '"' + (escape_rust_str s) + '"'
      emit_str_csv (s:ss)   =  '"' + (escape_rust_str s) + '", ' + (emit_str_csv ss)

fn :: emit_int_rval_csv [Int]  => String
      emit_int_rval_csv []     =  ""
      emit_int_rval_csv (n:[]) =  'RVal::Int(' + (int_to_str n) + ')'
      emit_int_rval_csv (n:ns) =  'RVal::Int(' + (int_to_str n) + '), ' + (emit_int_rval_csv ns)

fn :: format_real_lit String => String
      format_real_lit r
        | str_contains r "." = r + "f64"
        | otherwise = r + ".0f64"

fn :: emit_record_updates String [RExpr] [String] => String
      emit_record_updates cur    ((EStr fname):val_e:rest) locals =
        emit_record_updates ('rg_set_' + fname + '(' + cur + ', ' + (emit_native_expr val_e locals) + ')') rest locals
      emit_record_updates cur    _       _        =  cur

fn :: emit_native_expr RExpr              [String] => String
      emit_native_expr (EInt n)           _        =  'RVal::Int(' + (int_to_str n) + ')'
      emit_native_expr (EReal r)          _        =  'RVal::Real(' + (format_real_lit r) + ')'
      emit_native_expr (EStr s)           locals   =  emit_str_lit s locals
      emit_native_expr (EStrInterp parts) locals   =  'rg_str_interp(&[' + (emit_native_expr_csv parts locals) + '])'
      emit_native_expr (EBool True)       _        =  'RVal::Bool(true)'
      emit_native_expr (EBool False)      _        =  'RVal::Bool(false)'
      emit_native_expr EUnit              _        =  'RVal::Unit'
      emit_native_expr (EVar name)        locals   =  emit_native_var name locals
      emit_native_expr (ENot inner)       locals   =  'RVal::Bool(!rg_as_bool(&(' + (emit_native_expr inner locals) + ')))'
      emit_native_expr (EOut inner)       locals   =  'rg_out(' + (emit_native_expr inner locals) + ')'
      emit_native_expr (EBin bop l r)     locals   =
        emit_binop_rust bop (emit_native_expr l locals) (emit_native_expr r locals)
      emit_native_expr (ECall "__record_update__" (base_e:rest_args)) locals =
        emit_record_updates (emit_native_expr base_e locals) rest_args locals
      emit_native_expr (ECall "__unpack2__" ((EVar fn_target):single_arg:[])) locals =
        '{ let _u = ' + (emit_native_expr single_arg locals) + '; ' + (mangle_fn_name fn_target) + '(rg_tuple_get(&_u, 0), rg_tuple_get(&_u, 1)) }'
      emit_native_expr (ECall fname [])   locals
        | (lookup_local locals fname) >= 0 = 'lv_' + fname + '.clone()'
        | otherwise = (mangle_fn_name fname) + '()'
      emit_native_expr (ECall fname (a1:[])) locals
        | (lookup_local locals fname) >= 0 = 'rg_call1(&lv_' + fname + ', ' + (emit_native_expr a1 locals) + ')'
      emit_native_expr (ECall fname (a1:a2:[])) locals
        | (lookup_local locals fname) >= 0 = 'rg_call2(&lv_' + fname + ', ' + (emit_native_expr a1 locals) + ', ' + (emit_native_expr a2 locals) + ')'
      emit_native_expr (ECall fname args) locals
        | is_upper_ident fname = 'rg_adt("' + fname + '", vec![' + (emit_native_expr_csv args locals) + '])'
        | otherwise = (mangle_fn_name fname) + '(' + (emit_native_expr_csv args locals) + ')'
      emit_native_expr (EEcho args)       locals   =  'rg_echo(&[' + (emit_native_expr_csv args locals) + '])'
      emit_native_expr (EList elems)      locals   =  'rg_list(vec![' + (emit_native_expr_csv elems locals) + '])'
      emit_native_expr (ETuple elems)     locals   =  'rg_tuple(vec![' + (emit_native_expr_csv elems locals) + '])'
      emit_native_expr (ETensor elems)    locals   =  'rg_tensor(vec![' + (emit_native_expr_csv elems locals) + '])'
      emit_native_expr (EEinsum es subs)  locals   =
        'rg_einsum(&[' + (emit_native_expr_csv es locals) + '], &[' + (emit_str_csv subs) + '])'
      emit_native_expr (EHadamard bop l s1 r s2) locals =
        'rg_hadamard("' + (binop_op_tag bop) + '", &(' + (emit_native_expr l locals) + '), "' + s1 + '", &(' + (emit_native_expr r locals) + '), "' + s2 + '")'
      emit_native_expr (EIndex base idxs) locals   =
        'rg_index(&(' + (emit_native_expr base locals) + '), &[' + (emit_native_expr_csv idxs locals) + '])'
      emit_native_expr (EIndexAssign target idxs val_e) locals =
        'rg_index_set(lv_' + target + '.clone(), &[' + (emit_native_expr_csv idxs locals) + '], ' + (emit_native_expr val_e locals) + ')'
      emit_native_expr (ESeqSelect base mask) locals =
        'rg_seq_select(&(' + (emit_native_expr base locals) + '), "' + (escape_rust_str mask) + '")'
      emit_native_expr (EBlock stmts)     locals   =  '{' + "\n" + (emit_native_stmts stmts locals) + "\n" + '}'
      emit_native_expr (EWhere body binds) locals  =  '{' + "\n" + (emit_native_where binds body locals) + "\n" + '}'
      emit_native_expr (EParPipe branches) locals  =  'rg_tuple(vec![' + (emit_native_expr_csv branches locals) + '])'
      emit_native_expr (EWithCtx ctx_name val_e body) locals =
        'rg_with_ctx("' + ctx_name + '", ' + (emit_native_expr val_e locals) + ', || ' + (emit_native_expr body locals) + ')'
      emit_native_expr (EWithRegion quota body) locals =
        'rg_with_region_limit(' + (int_to_str quota) + 'usize, || ' + (emit_native_expr body locals) + ')'
      emit_native_expr (EAtomicUpdate var_name val_e) locals =
        'rg_store_shared("' + var_name + '", ' + (emit_native_expr val_e locals) + ')'
      emit_native_expr (ELoadContext ctx_name def_e) locals =
        'rg_load_ctx("' + ctx_name + '", || ' + (emit_native_expr def_e locals) + ')'
      emit_native_expr (ELoadShared var_name def_e) locals =
        'rg_load_shared("' + var_name + '", || ' + (emit_native_expr def_e locals) + ')'

fn :: is_zero_arg_builtin_var String            => Bool
      is_zero_arg_builtin_var "cli_args"        =  True
      is_zero_arg_builtin_var "new_mailbox"     =  True
      is_zero_arg_builtin_var "mailbox"         =  True
      is_zero_arg_builtin_var "new_channel"     =  True
      is_zero_arg_builtin_var "channel"         =  True
      is_zero_arg_builtin_var "sys_getcwd"      =  True
      is_zero_arg_builtin_var "sys_getuid"      =  True
      is_zero_arg_builtin_var "sys_getgid"      =  True
      is_zero_arg_builtin_var "cmm_live_blocks" =  True
      is_zero_arg_builtin_var "cmm_cond_spared" =  True
      is_zero_arg_builtin_var "cmm_cond_freed"  =  True
      is_zero_arg_builtin_var _                 =  False

fn :: emit_native_var String [String] => String
      emit_native_var name   locals
        | (lookup_local locals name) >= 0 = 'lv_' + name + '.clone()'
        | is_upper_ident name = 'rg_adt0("' + name + '")'
        | is_zero_arg_builtin_var name = (mangle_fn_name name) + '()'
        | otherwise = 'rg_str("' + (escape_rust_str name) + '")'

fn :: emit_native_expr_csv [RExpr] [String] => String
      emit_native_expr_csv []      _        =  ""
      emit_native_expr_csv (e:[])  locals   =  emit_native_expr e locals
      emit_native_expr_csv (e:es)  locals   =
        (emit_native_expr e locals) + ', ' + (emit_native_expr_csv es locals)

fn :: emit_final_block_expr RExpr       [String] [String] => String
      emit_final_block_expr (EVar v)    locals   _
        | (lookup_local locals v) >= 0 = "    rg_cmm_move(&mut lv_" + v + ")"
      emit_final_block_expr e           locals   []       =
        "    " + (emit_native_expr e locals)
      emit_final_block_expr e           locals   dead_vars =
        "    let _cmm_ret: RVal = " + (emit_native_expr e locals) + ";\n" + (emit_cmm_uncond_drops dead_vars "    ") + "    _cmm_ret"

fn :: emit_let_binding_stmt String RExpr [String] [String] [RStmt] => String
      emit_let_binding_stmt v e locals scope_vars rest =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        drop_inputs_code = emit_cmm_uncond_drops dead_inputs "    "
        drop_v_code = emit_unused_let_drop v live_after "    "
        bind_code = emit_let_var_decl v e locals
        bind_code + drop_inputs_code + drop_v_code + (emit_native_stmts_cmm rest (add_unique_str v locals) (add_unique_str v scope_vars))

fn :: emit_unused_let_drop String [String]   String => String
      emit_unused_let_drop v      live_after indent
        | str_in_list v live_after = ""
        | otherwise = indent + "rg_cmm_drop(&mut lv_" + v + ");\n"

fn :: emit_let_var_decl String RExpr [String] => String
      emit_let_var_decl v      e     locals
        | (lookup_local locals v) >= 0 =
            "    let _cmm_reb_" + v + ": RVal = " + (emit_native_expr e locals) + ";\n    rg_cmm_drop(&mut lv_" + v + ");\n    lv_" + v + " = _cmm_reb_" + v + ";\n"
        | otherwise =
            "    let mut lv_" + v + ": RVal = " + (emit_native_expr e locals) + ";\n"

fn :: emit_native_stmts [RStmt] [String] => String
      emit_native_stmts stmts   locals   =  emit_native_stmts_cmm stmts locals []

fn :: emit_native_stmts_cmm [RStmt]            [String] [String]   => String
      emit_native_stmts_cmm []                 _        _          =  'RVal::Unit'
      emit_native_stmts_cmm ((StmtExpr e):[])  locals   scope_vars =
        used = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        emit_final_block_expr e locals used
      emit_native_stmts_cmm ((StmtAtomic v e):[]) locals scope_vars =
        used = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        '    let _ = rg_store_shared("' + v + '", ' + (emit_native_expr e locals) + ');' + "\n" + (emit_cmm_uncond_drops used "    ") + '    RVal::Unit'
      emit_native_stmts_cmm ((StmtIndexAssign t idxs e):[]) locals _ =
        "    lv_" + t + " = rg_index_set(rg_cmm_move(&mut lv_" + t + "), &[" + (emit_native_expr_csv idxs locals) + "], " + (emit_native_expr e locals) + ");\n    RVal::Unit"
      emit_native_stmts_cmm ((StmtLet v e):[]) locals scope_vars
        | v == "_" =
            used = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
            "    let _ = " + (emit_native_expr e locals) + ";\n" + (emit_cmm_uncond_drops used "    ") + "    RVal::Unit"
        | otherwise =
            used = cmm_remove_str v (cmm_filter_in_list (cmm_expr_vars e []) scope_vars)
            "    let mut lv_" + v + ": RVal = " + (emit_native_expr e locals) + ";\n" + (emit_cmm_uncond_drops used "    ") + "    rg_cmm_move(&mut lv_" + v + ")"
      emit_native_stmts_cmm ((StmtLet v e):rest) locals scope_vars
        | v == "_" =
            used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
            live_after = cmm_stmts_vars rest []
            dead_now = cmm_filter_not_in_list used_in_e live_after
            "    let _ = " + (emit_native_expr e locals) + ";\n" + (emit_cmm_uncond_drops dead_now "    ") + (emit_native_stmts_cmm rest locals scope_vars)
        | otherwise =
            emit_let_binding_stmt v e locals scope_vars rest
      emit_native_stmts_cmm ((StmtAtomic v e):rest) locals scope_vars =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        dead_now = cmm_filter_not_in_list used_in_e live_after
        '    let _ = rg_store_shared("' + v + '", ' + (emit_native_expr e locals) + ');' + "\n" + (emit_cmm_uncond_drops dead_now "    ") + (emit_native_stmts_cmm rest locals scope_vars)
      emit_native_stmts_cmm ((StmtIndexAssign t idxs e):rest) locals scope_vars =
        "    lv_" + t + " = rg_index_set(rg_cmm_move(&mut lv_" + t + "), &[" + (emit_native_expr_csv idxs locals) + "], " + (emit_native_expr e locals) + ");\n" + (emit_native_stmts_cmm rest locals scope_vars)
      emit_native_stmts_cmm ((StmtExpr e):rest) locals scope_vars =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        dead_now = cmm_filter_not_in_list used_in_e live_after
        "    let _ = " + (emit_native_expr e locals) + ";\n" + (emit_cmm_uncond_drops dead_now "    ") + (emit_native_stmts_cmm rest locals scope_vars)

fn :: emit_native_where [RWhereBind] RExpr [String] => String
      emit_native_where binds        body  locals   =  emit_native_where_cmm binds body locals []

fn :: emit_native_where_cmm [RWhereBind] RExpr [String] [String] => String
      emit_native_where_cmm []           body  locals   scope_vars =
        used = cmm_filter_in_list (cmm_expr_vars body []) scope_vars
        emit_final_block_expr body locals used
      emit_native_where_cmm ((WhereBind e v []):wbs) body locals scope_vars =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_where_vars wbs body []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        drop_inputs_code = emit_cmm_uncond_drops dead_inputs "    "
        drop_v_code = emit_unused_let_drop v live_after "    "
        "    let mut lv_" + v + ": RVal = " + (emit_native_expr e locals) + ";\n" + drop_inputs_code + drop_v_code + (emit_native_where_cmm wbs body (add_unique_str v locals) (add_unique_str v scope_vars))
      emit_native_where_cmm ((WhereBind e v idxs):wbs) body locals scope_vars =
        "    lv_" + v + " = rg_index_set(rg_cmm_move(&mut lv_" + v + "), &[" + (emit_int_rval_csv idxs) + "], " + (emit_native_expr e locals) + ");\n" + (emit_native_where_cmm wbs body locals scope_vars)

-- ── Function, Record Field Accessor, TCO & Tree-Shaking ─────

fn :: expr_has_self_tail_call String RExpr           => Bool
      expr_has_self_tail_call target (ECall fname _) =  fname == target
      expr_has_self_tail_call target (EBlock stmts)  =  stmts_have_self_tail_call target stmts
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

fn :: cases_have_self_tail_call String [RFnCase] => Bool
      cases_have_self_tail_call _      []        =  False
      cases_have_self_tail_call target ((FnCase _ [] body):cs)
        | expr_has_self_tail_call target body = True
        | otherwise = cases_have_self_tail_call target cs
      cases_have_self_tail_call target ((FnCase _ guards _):cs)
        | guards_have_self_tail_call target guards = True
        | otherwise = cases_have_self_tail_call target cs

fn :: emit_tco_tmp_binds [RExpr] Int [String] => String
      emit_tco_tmp_binds []      _   _        =  ""
      emit_tco_tmp_binds (e:es)  idx locals   =
        'let _tco_' + (int_to_str idx) + ': RVal = ' + (emit_native_expr e locals) + '; ' + (emit_tco_tmp_binds es (idx + 1) locals)

fn :: emit_tco_arg_assigns Int Int   => String
      emit_tco_arg_assigns idx arity
        | idx >= arity = ""
        | otherwise = '_arg_' + (int_to_str idx) + ' = _tco_' + (int_to_str idx) + '; ' + (emit_tco_arg_assigns (idx + 1) arity)

fn :: emit_tail_return String Int   RExpr              [String] => String
      emit_tail_return target arity expr               locals   =
        emit_tail_return_cmm target arity expr locals []

fn :: emit_tail_return_cmm String Int   RExpr              [String] [String]   => String
      emit_tail_return_cmm target arity (ECall fname args) locals   _
        | fname == target AND (expr_list_count args) == arity AND (lookup_local locals fname) < 0 = '{ ' + (emit_tco_tmp_binds args 0 locals) + (emit_tco_arg_assigns 0 arity) + 'continue; }'
      emit_tail_return_cmm target arity (EBlock stmts)     locals   scope_vars =
        "{\n" + (emit_tail_stmts_cmm target arity stmts locals scope_vars) + "\n}"
      emit_tail_return_cmm target arity (EWhere body binds) locals  scope_vars =
        "{\n" + (emit_tail_where_cmm target arity binds body locals scope_vars) + "\n}"
      emit_tail_return_cmm _      _     (EVar v)           locals   _
        | (lookup_local locals v) >= 0 = 'return rg_cmm_move(&mut lv_' + v + ');'
      emit_tail_return_cmm _      _     expr               locals   scope_vars =
        used = cmm_filter_in_list (cmm_expr_vars expr []) scope_vars
        emit_tail_return_expr expr locals used

fn :: emit_tail_return_expr RExpr [String] [String] => String
      emit_tail_return_expr expr  locals   []       =
        'return ' + (emit_native_expr expr locals) + ';'
      emit_tail_return_expr expr  locals   used     =
        '{ let _cmm_ret: RVal = ' + (emit_native_expr expr locals) + '; ' + (emit_cmm_uncond_drops used "") + 'return _cmm_ret; }'

fn :: emit_tail_let_stmt String Int String RExpr [String] [String] [RStmt] => String
      emit_tail_let_stmt target arity v e locals scope_vars rest =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        drop_inputs_code = emit_cmm_uncond_drops dead_inputs "    "
        drop_v_code = emit_unused_let_drop v live_after "    "
        bind_code = emit_let_var_decl v e locals
        bind_code + drop_inputs_code + drop_v_code + (emit_tail_stmts_cmm target arity rest (add_unique_str v locals) (add_unique_str v scope_vars))

fn :: emit_tail_stmts_cmm String Int   [RStmt]            [String] [String]   => String
      emit_tail_stmts_cmm _      _     []                 _        _          =  '    return RVal::Unit;'
      emit_tail_stmts_cmm target arity ((StmtExpr e):[])  locals   scope_vars =
        '    ' + (emit_tail_return_cmm target arity e locals scope_vars)
      emit_tail_stmts_cmm target arity ((StmtLet v e):rest) locals scope_vars
        | v == "_" =
            used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
            live_after = cmm_stmts_vars rest []
            dead_now = cmm_filter_not_in_list used_in_e live_after
            "    let _ = " + (emit_native_expr e locals) + ";\n" + (emit_cmm_uncond_drops dead_now "    ") + (emit_tail_stmts_cmm target arity rest locals scope_vars)
        | otherwise =
            emit_tail_let_stmt target arity v e locals scope_vars rest
      emit_tail_stmts_cmm target arity ((StmtAtomic v e):rest) locals scope_vars =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        dead_now = cmm_filter_not_in_list used_in_e live_after
        '    let _ = rg_store_shared("' + v + '", ' + (emit_native_expr e locals) + ');' + "\n" + (emit_cmm_uncond_drops dead_now "    ") + (emit_tail_stmts_cmm target arity rest locals scope_vars)
      emit_tail_stmts_cmm target arity ((StmtIndexAssign t idxs e):rest) locals scope_vars =
        "    lv_" + t + " = rg_index_set(rg_cmm_move(&mut lv_" + t + "), &[" + (emit_native_expr_csv idxs locals) + "], " + (emit_native_expr e locals) + ");\n" + (emit_tail_stmts_cmm target arity rest locals scope_vars)
      emit_tail_stmts_cmm target arity ((StmtExpr e):rest) locals scope_vars =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        dead_now = cmm_filter_not_in_list used_in_e live_after
        "    let _ = " + (emit_native_expr e locals) + ";\n" + (emit_cmm_uncond_drops dead_now "    ") + (emit_tail_stmts_cmm target arity rest locals scope_vars)

fn :: emit_tail_where_cmm String Int [RWhereBind] RExpr [String] [String] => String
      emit_tail_where_cmm target arity [] body locals scope_vars =
        '    ' + (emit_tail_return_cmm target arity body locals scope_vars)
      emit_tail_where_cmm target arity ((WhereBind e v []):wbs) body locals scope_vars =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_where_vars wbs body []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        drop_inputs_code = emit_cmm_uncond_drops dead_inputs "    "
        drop_v_code = emit_unused_let_drop v live_after "    "
        "    let mut lv_" + v + ": RVal = " + (emit_native_expr e locals) + ";\n" + drop_inputs_code + drop_v_code + (emit_tail_where_cmm target arity wbs body (add_unique_str v locals) (add_unique_str v scope_vars))
      emit_tail_where_cmm target arity ((WhereBind e v idxs):wbs) body locals scope_vars =
        "    lv_" + v + " = rg_index_set(rg_cmm_move(&mut lv_" + v + "), &[" + (emit_int_rval_csv idxs) + "], " + (emit_native_expr e locals) + ");\n" + (emit_tail_where_cmm target arity wbs body locals scope_vars)

fn :: emit_native_guards String Int   [RGuard] [String] => String
      emit_native_guards _      _     []       _        =  ""
      emit_native_guards target arity ((GuardBranch cond body):gs) locals =
        '    if rg_as_bool(&(' + (emit_native_expr cond locals) + ')) {' + "\n      " + (emit_tail_return target arity body locals) + "\n    " + '}' + "\n" + (emit_native_guards target arity gs locals)

fn :: emit_native_case String RFnCase Int   => String
      emit_native_case target (FnCase pats [] body) arity =
        cond = emit_pat_list_cond pats 0
        binds = emit_pat_list_binds pats 0 arity
        locals = collect_pat_list_vars pats []
        '  if ' + cond + ' {' + "\n" + binds + "    " + (emit_tail_return target arity body locals) + "\n  " + '}' + "\n"
      emit_native_case target (FnCase pats guards _) arity =
        cond = emit_pat_list_cond pats 0
        binds = emit_pat_list_binds pats 0 arity
        locals = collect_pat_list_vars pats []
        '  if ' + cond + ' {' + "\n" + binds + (emit_native_guards target arity guards locals) + '  }' + "\n"

fn :: emit_native_cases String [RFnCase] Int   => String
      emit_native_cases _      []        _     =  ""
      emit_native_cases target (c:cs)    arity =  (emit_native_case target c arity) + (emit_native_cases target cs arity)

fn :: emit_param_sig Bool  Int Int   => String
      emit_param_sig _     idx arity
        | idx >= arity = ""
      emit_param_sig True  idx arity
        | (idx + 1) == arity = 'mut _arg_' + (int_to_str idx) + ': RVal'
        | otherwise = 'mut _arg_' + (int_to_str idx) + ': RVal, ' + (emit_param_sig True (idx + 1) arity)
      emit_param_sig False idx arity
        | (idx + 1) == arity = '_arg_' + (int_to_str idx) + ': RVal'
        | otherwise = '_arg_' + (int_to_str idx) + ': RVal, ' + (emit_param_sig False (idx + 1) arity)

fn :: emit_native_fndef RFnDef => String
      emit_native_fndef (FnDef name params _ cases) =
        arity = infer_fndef_arity params cases
        is_tco = cases_have_self_tail_call name cases
        sig = emit_param_sig is_tco 0 arity
        body_code = emit_native_cases name cases arity
        emit_native_fndef_wrap name sig is_tco body_code

fn :: emit_native_fndef_wrap String String Bool  String    => String
      emit_native_fndef_wrap name   sig    True  body_code =
        'fn ' + (mangle_fn_name name) + '(' + sig + ') -> RVal {' + "\n  loop {\n" + body_code + "    return RVal::Unit;\n  }\n" + '}' + "\n\n"
      emit_native_fndef_wrap name   sig    False body_code =
        'fn ' + (mangle_fn_name name) + '(' + sig + ') -> RVal {' + "\n" + body_code + "  RVal::Unit\n" + '}' + "\n\n"

fn :: emit_native_fndef_list [RFnDef] => String
      emit_native_fndef_list []       =  ""
      emit_native_fndef_list (f:fs)   =  (emit_native_fndef f) + (emit_native_fndef_list fs)

-- ── Call-Graph Tree-Shaking (Dead-Code Elimination) ──────────

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

fn :: emit_record_accessors [RField] Int [String] => (String, [String])
      emit_record_accessors []       _   emitted  =  ("", emitted)
      emit_record_accessors ((TypeField fname _):fs) idx emitted
        | (lookup_local emitted fname) >= 0 = emit_record_accessors fs (idx + 1) emitted
        | otherwise = prepend_code_str ('fn rg_fn_' + fname + '(_arg_0: RVal) -> RVal { rg_adt_field(&_arg_0, ' + (int_to_str idx) + ') }' + "\n" + 'fn rg_set_' + fname + '(_arg_0: RVal, _val: RVal) -> RVal { rg_adt_set(_arg_0, ' + (int_to_str idx) + ', _val) }' + "\n") (emit_record_accessors fs (idx + 1) (emitted :: [fname]))

fn :: prepend_code_str String (String, [String]) => (String, [String])
      prepend_code_str s      (rest_s, emitted)  =  (s + rest_s, emitted)

fn :: emit_typedef_accessors [RTypeDef] [String] => String
      emit_typedef_accessors []         _        =  ""
      emit_typedef_accessors ((TypeDef _ _ []):ts) emitted = emit_typedef_accessors ts emitted
      emit_typedef_accessors ((TypeDef _ _ fields):ts) emitted =
        r1 = emit_record_accessors fields 0 emitted
        emit_typedef_accessors_cont ts r1

fn :: emit_typedef_accessors_cont [RTypeDef] (String, [String]) => String
      emit_typedef_accessors_cont ts         (code1, emitted1)  =
        code1 + (emit_typedef_accessors ts emitted1)

fn :: collect_fn_names [RFnDef] => [String]
      collect_fn_names []       =  []
      collect_fn_names ((FnDef name _ _ _):fs) = [name] :: (collect_fn_names fs)

fn :: emit_spawn_arms [RFnDef] => String
      emit_spawn_arms []       =  ""
      emit_spawn_arms ((FnDef name params _ cases):fs)
        | (infer_fndef_arity params cases) == 1 = '        "' + (escape_rust_str name) + '" => ' + (mangle_fn_name name) + '(arg),' + "\n" + (emit_spawn_arms fs)
        | otherwise = emit_spawn_arms fs

fn :: emit_call2_arms [RFnDef] => String
      emit_call2_arms []       =  ""
      emit_call2_arms ((FnDef name params _ cases):fs)
        | (infer_fndef_arity params cases) == 2 = '        "' + (escape_rust_str name) + '" => ' + (mangle_fn_name name) + '(a, b),' + "\n" + (emit_call2_arms fs)
        | otherwise = emit_call2_arms fs

fn :: emit_binop_overload_arms [RFnDef] => String
      emit_binop_overload_arms []       =  ""
      emit_binop_overload_arms ((FnDef name params _ cases):fs)
        | (name == "+" OR name == "-" OR name == "*" OR name == "/" OR name == "%") AND (infer_fndef_arity params cases) == 2 = '        "' + name + '" => ' + (mangle_fn_name name) + '(a, b),' + "\n" + (emit_binop_overload_arms fs)
        | otherwise = emit_binop_overload_arms fs

fn :: emit_dispatch_tables [RFnDef] => String
      emit_dispatch_tables fns      =
        'fn rg_dispatch_spawn(fn_name: &str, arg: RVal) -> RVal {' + "\n" + '    match fn_name {' + "\n" + (emit_spawn_arms fns) + '        _ => RVal::Unit,' + "\n" + '    }' + "\n" + '}' + "\n\n" + 'fn rg_dispatch_call2(fn_name: &str, a: RVal, b: RVal) -> RVal {' + "\n" + '    match fn_name {' + "\n" + (emit_call2_arms fns) + '        _ => RVal::Unit,' + "\n" + '    }' + "\n" + '}' + "\n\n" + 'fn rg_dispatch_binop(op: &str, a: RVal, b: RVal) -> RVal {' + "\n" + '    match op {' + "\n" + (emit_binop_overload_arms fns) + '        _ => RVal::Unit,' + "\n" + '    }' + "\n" + '}' + "\n\n"

fn :: find_entry_fn_name [RFnDef] String   => String
      find_entry_fn_name []       fallback =  fallback
      find_entry_fn_name ((FnDef name params _ cases):fs) fallback
        | name == "main" = "main"
        | name == "demo_all" = "demo_all"
        | (infer_fndef_arity params cases) == 0 = find_entry_fn_name fs name
        | otherwise = find_entry_fn_name fs fallback

fn :: emit_runtime_preamble => String
      emit_runtime_preamble = '#![allow(unused_variables, dead_code, non_snake_case, unused_parens, unused_mut)]
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{Mutex, OnceLock};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::ops::Deref;
use std::path::{Path, PathBuf};

static RG_CMM_LIVE_BLOCKS: AtomicUsize = AtomicUsize::new(0);
static RG_CMM_COND_SPARED: AtomicUsize = AtomicUsize::new(0);
static RG_CMM_COND_FREED: AtomicUsize = AtomicUsize::new(0);

struct CmmHeader<T> {
    links: AtomicUsize,
    tracked: bool,
    data: T,
}

pub struct CmmBox<T>(*mut CmmHeader<T>);

unsafe impl<T: Send + Sync> Send for CmmBox<T> {}
unsafe impl<T: Send + Sync> Sync for CmmBox<T> {}

impl<T> CmmBox<T> {
    #[inline]
    pub fn new(data: T) -> Self {
        RG_CMM_LIVE_BLOCKS.fetch_add(1, Ordering::Relaxed);
        let ptr = Box::into_raw(Box::new(CmmHeader {
            links: AtomicUsize::new(1),
            tracked: true,
            data,
        }));
        CmmBox(ptr)
    }

    #[inline]
    pub fn new_untracked(data: T) -> Self {
        let ptr = Box::into_raw(Box::new(CmmHeader {
            links: AtomicUsize::new(1),
            tracked: false,
            data,
        }));
        CmmBox(ptr)
    }

    #[inline]
    pub fn raw_ptr(&self) -> usize {
        self.0 as usize
    }

    #[inline]
    pub fn links(&self) -> usize {
        unsafe { (*self.0).links.load(Ordering::Relaxed) }
    }

    #[inline]
    pub fn is_tracked(&self) -> bool {
        unsafe { (*self.0).tracked }
    }

    #[inline]
    pub fn clone(this: &Self) -> Self {
        Clone::clone(this)
    }

    #[inline]
    pub fn try_unwrap(this: Self) -> Result<T, Self> {
        unsafe {
            if (*this.0).links.load(Ordering::Relaxed) == 1 {
                let ptr = this.0;
                std::mem::forget(this);
                let boxed = Box::from_raw(ptr);
                if boxed.tracked {
                    RG_CMM_LIVE_BLOCKS.fetch_sub(1, Ordering::Relaxed);
                }
                Ok(boxed.data)
            } else {
                Err(this)
            }
        }
    }
}

impl<T> Clone for CmmBox<T> {
    #[inline]
    fn clone(&self) -> Self {
        unsafe {
            (*self.0).links.fetch_add(1, Ordering::Relaxed);
        }
        CmmBox(self.0)
    }
}

impl<T> Deref for CmmBox<T> {
    type Target = T;
    #[inline]
    fn deref(&self) -> &T {
        unsafe { &(*self.0).data }
    }
}

impl<T> Drop for CmmBox<T> {
    #[inline]
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {
                if (*self.0).links.fetch_sub(1, Ordering::Release) == 1 {
                    std::sync::atomic::fence(Ordering::Acquire);
                    let boxed = Box::from_raw(self.0);
                    if boxed.tracked {
                        RG_CMM_LIVE_BLOCKS.fetch_sub(1, Ordering::Relaxed);
                    }
                }
            }
        }
    }
}

impl<T: PartialEq> PartialEq for CmmBox<T> {
    #[inline]
    fn eq(&self, other: &Self) -> bool {
        self.0 == other.0 || (**self) == (**other)
    }
}

impl<T: std::fmt::Debug> std::fmt::Debug for CmmBox<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        (**self).fmt(f)
    }
}

impl<T: std::fmt::Display> std::fmt::Display for CmmBox<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        (**self).fmt(f)
    }
}

type Rc<T> = CmmBox<T>;

#[derive(Clone, Debug)]
enum RVal {
    Int(i64),
    Real(f64),
    Str(Rc<String>),
    Bool(bool),
    Unit,
    List(Rc<Vec<RVal>>, usize),
    Tuple(Rc<Vec<RVal>>),
    Adt(Rc<String>, Rc<Vec<RVal>>),
    Tensor(Rc<Vec<usize>>, Rc<Vec<f64>>),
}

#[inline]
fn rg_cmm_ptr(v: &RVal) -> usize {
    match v {
        RVal::Str(rc) => rc.raw_ptr(),
        RVal::List(rc, _) => rc.raw_ptr(),
        RVal::Tuple(rc) => rc.raw_ptr(),
        RVal::Adt(_, rc) => rc.raw_ptr(),
        RVal::Tensor(_, rc) => rc.raw_ptr(),
        _ => 0,
    }
}

#[inline]
fn rg_cmm_links(v: &RVal) -> usize {
    match v {
        RVal::Str(rc) if rc.is_tracked() => rc.links(),
        RVal::List(rc, _) if rc.is_tracked() => rc.links(),
        RVal::Tuple(rc) if rc.is_tracked() => rc.links(),
        RVal::Adt(_, rc) if rc.is_tracked() => rc.links(),
        RVal::Tensor(_, rc) if rc.is_tracked() => rc.links(),
        _ => 0,
    }
}

#[inline]
fn rg_cmm_move(v: &mut RVal) -> RVal {
    std::mem::replace(v, RVal::Unit)
}

#[inline]
fn rg_cmm_drop(v: &mut RVal) {
    let lk = rg_cmm_links(v);
    if lk > 1 {
        RG_CMM_COND_SPARED.fetch_add(1, Ordering::Relaxed);
    } else if lk == 1 {
        RG_CMM_COND_FREED.fetch_add(1, Ordering::Relaxed);
    }
    let _ = std::mem::replace(v, RVal::Unit);
}

#[inline] fn rg_fn_cmm_live_blocks() -> RVal { RVal::Int(RG_CMM_LIVE_BLOCKS.load(Ordering::Relaxed) as i64) }
#[inline] fn rg_fn_cmm_cond_spared() -> RVal { RVal::Int(RG_CMM_COND_SPARED.load(Ordering::Relaxed) as i64) }
#[inline] fn rg_fn_cmm_cond_freed() -> RVal { RVal::Int(RG_CMM_COND_FREED.load(Ordering::Relaxed) as i64) }
#[inline] fn rg_fn_cmm_same_ptr(a: RVal, b: RVal) -> RVal {
    let pa = rg_cmm_ptr(&a);
    RVal::Bool(pa != 0 && pa == rg_cmm_ptr(&b))
}

impl PartialEq for RVal {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (RVal::Int(a), RVal::Int(b)) => a == b,
            (RVal::Real(a), RVal::Real(b)) => (a - b).abs() < 1e-12,
            (RVal::Str(a), RVal::Str(b)) => a == b,
            (RVal::Bool(a), RVal::Bool(b)) => a == b,
            (RVal::Unit, RVal::Unit) => true,
            (RVal::List(a, sa), RVal::List(b, sb)) => a[(*sa).min(a.len())..] == b[(*sb).min(b.len())..],
            (RVal::Tuple(a), RVal::Tuple(b)) => a == b,
            (RVal::Adt(ca, fa), RVal::Adt(cb, fb)) => ca == cb && fa == fb,
            (RVal::Tensor(sa, da), RVal::Tensor(sb, db)) => sa == sb && da == db,
            _ => false,
        }
    }
}

impl std::fmt::Display for RVal {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            RVal::Int(n) => write!(f, "{}", n),
            RVal::Real(r) => if r.fract() == 0.0 { write!(f, "{:.1}", r) } else { write!(f, "{}", r) },
            RVal::Str(s) => write!(f, "{}", s),
            RVal::Bool(b) => write!(f, "{}", if *b { "True" } else { "False" }),
            RVal::Unit => write!(f, "()"),
            RVal::List(rc, st) => {
                let items = &rc[(*st).min(rc.len())..];
                let strs: Vec<String> = items.iter().map(|v| format!("{}", v)).collect();
                write!(f, "[{}]", strs.join(", "))
            }
            RVal::Tuple(items) => {
                let strs: Vec<String> = items.iter().map(|v| format!("{}", v)).collect();
                write!(f, "({})", strs.join(", "))
            }
            RVal::Adt(c, fields) => {
                if fields.is_empty() { write!(f, "{}", c) } else {
                    let strs: Vec<String> = fields.iter().map(|v| format!("{}", v)).collect();
                    write!(f, "({} {})", c, strs.join(" "))
                }
            }
            RVal::Tensor(shape, data) => write!(f, "Tensor(shape={:?}, data={:?})", shape, data),
        }
    }
}

thread_local! {
    static RG_CTX: RefCell<HashMap<String, Vec<RVal>>> = RefCell::new(HashMap::new());
    static RG_REGION_ACTIVE: Cell<bool> = const { Cell::new(false) };
    static RG_REGION_USED: Cell<usize> = const { Cell::new(0) };
}

static RG_SHARED: OnceLock<Mutex<HashMap<String, RVal>>> = OnceLock::new();
static RG_CHANNELS: OnceLock<Mutex<Vec<VecDeque<RVal>>>> = OnceLock::new();
static RG_THREADS: OnceLock<Mutex<Vec<Option<RVal>>>> = OnceLock::new();

fn rg_estimate_bytes(v: &RVal) -> usize {
    match v {
        RVal::Int(_) | RVal::Real(_) | RVal::Bool(_) | RVal::Unit => 8,
        RVal::Str(s) => 16 + s.len(),
        RVal::List(rc, st) => 16 + rc[(*st).min(rc.len())..].iter().map(rg_estimate_bytes).sum::<usize>(),
        RVal::Tuple(rc) => 16 + rc.iter().map(rg_estimate_bytes).sum::<usize>(),
        RVal::Adt(_, f) => 16 + f.iter().map(rg_estimate_bytes).sum::<usize>(),
        RVal::Tensor(sh, d) => 24 + sh.len() * 8 + d.len() * 8,
    }
}

#[inline]
fn rg_charge_region(v: &RVal) {
    if RG_REGION_ACTIVE.with(|a| a.get()) {
        let cost = ((rg_estimate_bytes(v) + 7) & !7);
        RG_REGION_USED.with(|u| u.set(u.get().saturating_add(cost)));
    }
}

fn rg_with_region_limit<F: FnOnce() -> RVal>(quota: usize, f: F) -> RVal {
    let prev_active = RG_REGION_ACTIVE.with(|a| a.replace(true));
    let prev_used = RG_REGION_USED.with(|u| u.replace(0));
    let val = f();
    let used = RG_REGION_USED.with(|u| u.replace(prev_used));
    RG_REGION_ACTIVE.with(|a| a.set(prev_active));
    if used > quota {
        rg_adt("Err", vec![rg_adt0("OutOfMemory")])
    } else {
        rg_adt("Ok", vec![val])
    }
}

fn rg_with_ctx<F: FnOnce() -> RVal>(name: &str, val: RVal, f: F) -> RVal {
    RG_CTX.with(|c| { c.borrow_mut().entry(name.to_string()).or_default().push(val); });
    let res = f();
    RG_CTX.with(|c| { if let Some(v) = c.borrow_mut().get_mut(name) { v.pop(); } });
    res
}

fn rg_load_ctx<F: FnOnce() -> RVal>(name: &str, def_fn: F) -> RVal {
    let found = RG_CTX.with(|c| c.borrow().get(name).and_then(|v| v.last().cloned()));
    match found { Some(v) => v, None => def_fn() }
}

fn rg_load_shared<F: FnOnce() -> RVal>(name: &str, def_fn: F) -> RVal {
    let mut g = RG_SHARED.get_or_init(|| Mutex::new(HashMap::new())).lock().unwrap();
    if let Some(v) = g.get(name) { return v.clone(); }
    let init = def_fn();
    g.insert(name.to_string(), init.clone());
    init
}

fn rg_store_shared(name: &str, val: RVal) -> RVal {
    let mut g = RG_SHARED.get_or_init(|| Mutex::new(HashMap::new())).lock().unwrap();
    g.insert(name.to_string(), val);
    RVal::Unit
}

#[inline] fn rg_str(s: &str) -> RVal { RVal::Str(Rc::new(s.to_string())) }
#[inline] fn rg_to_str(v: &RVal) -> RVal { match v { RVal::Str(_) => v.clone(), o => RVal::Str(Rc::new(format!("{}", o))) } }
#[inline] fn rg_str_interp(parts: &[RVal]) -> RVal { let s: String = parts.iter().map(|v| format!("{}", v)).collect(); RVal::Str(Rc::new(s)) }
#[inline] fn rg_list(v: Vec<RVal>) -> RVal { let r = RVal::List(Rc::new(v), 0); rg_charge_region(&r); r }
#[inline] fn rg_tuple(v: Vec<RVal>) -> RVal { let r = RVal::Tuple(Rc::new(v)); rg_charge_region(&r); r }
#[inline] fn rg_adt0(c: &str) -> RVal { RVal::Adt(Rc::new_untracked(c.to_string()), Rc::new_untracked(Vec::new())) }
#[inline] fn rg_adt(c: &str, f: Vec<RVal>) -> RVal { let r = RVal::Adt(Rc::new_untracked(c.to_string()), Rc::new(f)); rg_charge_region(&r); r }
#[inline] fn rg_as_int(v: &RVal) -> i64 { match v { RVal::Int(n) => *n, RVal::Real(r) => *r as i64, _ => 0 } }
#[inline] fn rg_as_real(v: &RVal) -> f64 { match v { RVal::Real(r) => *r, RVal::Int(n) => *n as f64, _ => 0.0 } }
#[inline] fn rg_as_bool(v: &RVal) -> bool { match v { RVal::Bool(b) => *b, _ => false } }
#[inline] fn rg_match_int(v: &RVal, t: i64) -> bool { matches!(v, RVal::Int(n) if *n == t) }
#[inline] fn rg_match_real(v: &RVal, t: f64) -> bool { matches!(v, RVal::Real(r) if (*r - t).abs() < 1e-12) }
#[inline] fn rg_match_str(v: &RVal, t: &str) -> bool { matches!(v, RVal::Str(s) if s.as_str() == t) }
#[inline] fn rg_match_bool(v: &RVal, t: bool) -> bool { matches!(v, RVal::Bool(b) if *b == t) }
#[inline] fn rg_is_empty(v: &RVal) -> bool { match v { RVal::List(rc, st) => *st >= rc.len(), _ => true } }
#[inline] fn rg_is_non_empty(v: &RVal) -> bool { match v { RVal::List(rc, st) => *st < rc.len(), _ => false } }
#[inline] fn rg_list_head(v: &RVal) -> RVal { match v { RVal::List(rc, st) => rc.get(*st).cloned().unwrap_or(RVal::Unit), _ => RVal::Unit } }
#[inline] fn rg_list_tail(v: &RVal) -> RVal { match v { RVal::List(rc, st) => if *st + 1 >= rc.len() { RVal::List(Rc::new(Vec::new()), 0) } else { RVal::List(Rc::clone(rc), *st + 1) }, _ => RVal::List(Rc::new(Vec::new()), 0) } }
#[inline] fn rg_is_tuple(v: &RVal, len: usize) -> bool { match v { RVal::Tuple(items) => items.len() == len, RVal::List(rc, st) => rc.len().saturating_sub(*st) == len, _ => false } }
#[inline] fn rg_tuple_get(v: &RVal, idx: usize) -> RVal { match v { RVal::Tuple(items) => items.get(idx).cloned().unwrap_or(RVal::Unit), RVal::List(rc, st) => rc.get(*st + idx).cloned().unwrap_or(RVal::Unit), _ => RVal::Unit } }
#[inline] fn rg_is_adt(v: &RVal, exp: &str, arity: usize) -> bool { match v { RVal::Adt(c, f) => c.as_str() == exp && f.len() == arity, _ => false } }
#[inline] fn rg_adt_field(v: &RVal, idx: usize) -> RVal { match v { RVal::Adt(_, f) => f.get(idx).cloned().unwrap_or(RVal::Unit), _ => RVal::Unit } }
#[inline] fn rg_adt_set(v: RVal, idx: usize, val: RVal) -> RVal { match v { RVal::Adt(c, rc) => { let mut f = match Rc::try_unwrap(rc) { Ok(vec) => vec, Err(r) => (*r).clone() }; if idx < f.len() { f[idx] = val; } RVal::Adt(c, Rc::new(f)) } o => o } }

#[inline]
fn rg_add(a: RVal, b: RVal) -> RVal {
    match (&a, &b) {
        (RVal::Str(sa), RVal::Str(sb)) => RVal::Str(Rc::new(format!("{}{}", sa, sb))),
        (RVal::Real(_), _) | (_, RVal::Real(_)) => RVal::Real(rg_as_real(&a) + rg_as_real(&b)),
        (RVal::Adt(..), RVal::Adt(..)) => rg_dispatch_binop("+", a, b),
        _ => RVal::Int(rg_as_int(&a) + rg_as_int(&b)),
    }
}

#[inline]
fn rg_sub(a: RVal, b: RVal) -> RVal {
    match (&a, &b) {
        (RVal::Real(_), _) | (_, RVal::Real(_)) => RVal::Real(rg_as_real(&a) - rg_as_real(&b)),
        (RVal::Adt(..), RVal::Adt(..)) => rg_dispatch_binop("-", a, b),
        _ => RVal::Int(rg_as_int(&a) - rg_as_int(&b)),
    }
}

#[inline]
fn rg_mul(a: RVal, b: RVal) -> RVal {
    match (&a, &b) {
        (RVal::Real(_), _) | (_, RVal::Real(_)) => RVal::Real(rg_as_real(&a) * rg_as_real(&b)),
        (RVal::Adt(..), RVal::Adt(..)) => rg_dispatch_binop("*", a, b),
        _ => RVal::Int(rg_as_int(&a) * rg_as_int(&b)),
    }
}

#[inline]
fn rg_div(a: RVal, b: RVal) -> RVal {
    match (&a, &b) {
        (RVal::Real(_), _) | (_, RVal::Real(_)) => RVal::Real(rg_as_real(&a) / rg_as_real(&b)),
        (RVal::Adt(..), RVal::Adt(..)) => rg_dispatch_binop("/", a, b),
        _ => RVal::Int(rg_as_int(&a) / rg_as_int(&b)),
    }
}

#[inline]
fn rg_mod(a: RVal, b: RVal) -> RVal {
    match (&a, &b) {
        (RVal::Adt(..), RVal::Adt(..)) => rg_dispatch_binop("%", a, b),
        _ => RVal::Int(rg_as_int(&a) % rg_as_int(&b)),
    }
}

#[inline] fn rg_cmp_gt(a: &RVal, b: &RVal) -> RVal { match (a, b) { (RVal::Real(_), _) | (_, RVal::Real(_)) => RVal::Bool(rg_as_real(a) > rg_as_real(b)), _ => RVal::Bool(rg_as_int(a) > rg_as_int(b)) } }
#[inline] fn rg_cmp_lt(a: &RVal, b: &RVal) -> RVal { match (a, b) { (RVal::Real(_), _) | (_, RVal::Real(_)) => RVal::Bool(rg_as_real(a) < rg_as_real(b)), _ => RVal::Bool(rg_as_int(a) < rg_as_int(b)) } }
#[inline] fn rg_cmp_gte(a: &RVal, b: &RVal) -> RVal { match (a, b) { (RVal::Real(_), _) | (_, RVal::Real(_)) => RVal::Bool(rg_as_real(a) >= rg_as_real(b)), _ => RVal::Bool(rg_as_int(a) >= rg_as_int(b)) } }
#[inline] fn rg_cmp_lte(a: &RVal, b: &RVal) -> RVal { match (a, b) { (RVal::Real(_), _) | (_, RVal::Real(_)) => RVal::Bool(rg_as_real(a) <= rg_as_real(b)), _ => RVal::Bool(rg_as_int(a) <= rg_as_int(b)) } }

fn rg_list_concat(a: RVal, b: RVal) -> RVal {
    if let RVal::List(ref rc_b, st_b) = b {
        if st_b > 0 {
            if let RVal::List(ref rc_a, st_a) = a {
                if st_a + 1 == rc_a.len() && rc_b.get(st_b - 1) == Some(&rc_a[st_a]) {
                    return RVal::List(Rc::clone(rc_b), st_b - 1);
                }
            }
        }
    }
    let mut out = match a {
        RVal::List(rc, 0) => match Rc::try_unwrap(rc) { Ok(v) => v, Err(r) => (*r).clone() },
        RVal::List(rc, st) => rc[st.min(rc.len())..].to_vec(),
        other => vec![other],
    };
    match b {
        RVal::List(rc, st) => out.extend_from_slice(&rc[st.min(rc.len())..]),
        other => out.push(other),
    }
    let r = RVal::List(Rc::new(out), 0);
    rg_charge_region(&r);
    r
}

fn rg_seq_flat_join(a: RVal, b: RVal) -> RVal {
    let mut items = Vec::new();
    for v in [a, b] {
        match v {
            RVal::Tuple(rc) => items.extend_from_slice(&rc),
            RVal::List(rc, st) => items.extend_from_slice(&rc[st.min(rc.len())..]),
            single => items.push(single),
        }
    }
    rg_tuple(items)
}

fn rg_pack_seq(args: Vec<RVal>) -> RVal {
    if args.len() == 1 {
        if matches!(&args[0], RVal::List(..) | RVal::Tuple(..)) {
            return args.into_iter().next().unwrap();
        }
    }
    rg_list(args)
}

fn rg_seq_select(seq: &RVal, mask: &str) -> RVal {
    let items: Vec<RVal> = match seq {
        RVal::Tuple(rc) => (**rc).clone(),
        RVal::List(rc, st) => rc[(*st).min(rc.len())..].to_vec(),
        other => vec![other.clone()],
    };
    let selected: Vec<RVal> = if mask.contains("+") || mask.contains("_") {
        mask.as_bytes().iter().enumerate().filter(|(_, &b)| b == 43u8).filter_map(|(i, _)| items.get(i).cloned()).collect()
    } else {
        mask.split_whitespace().filter_map(|t| t.parse::<usize>().ok()).filter_map(|i| items.get(i).cloned()).collect()
    };
    if selected.len() == 1 {
        selected.into_iter().next().unwrap()
    } else {
        RVal::Tuple(Rc::new(selected))
    }
}

fn rg_flatten_tensor(elems: &[RVal], shape: &mut Vec<usize>, flat: &mut Vec<f64>, rec: bool) {
    if rec { shape.push(elems.len()); }
    for (i, el) in elems.iter().enumerate() {
        match el {
            RVal::List(rc, st) => rg_flatten_tensor(&rc[(*st).min(rc.len())..], shape, flat, rec && i == 0),
            RVal::Tuple(rc) => rg_flatten_tensor(rc, shape, flat, rec && i == 0),
            sc => flat.push(rg_as_real(sc)),
        }
    }
}

fn rg_tensor(elems: Vec<RVal>) -> RVal {
    if elems.len() == 1 {
        if let RVal::List(rc, st) = &elems[0] {
            let mut sh = Vec::new();
            let mut fl = Vec::new();
            rg_flatten_tensor(&rc[(*st).min(rc.len())..], &mut sh, &mut fl, true);
            let r = RVal::Tensor(Rc::new(sh), Rc::new(fl));
            rg_charge_region(&r);
            return r;
        }
    }
    let mut sh = Vec::new();
    let mut fl = Vec::new();
    rg_flatten_tensor(&elems, &mut sh, &mut fl, true);
    let r = RVal::Tensor(Rc::new(sh), Rc::new(fl));
    rg_charge_region(&r);
    r
}

fn rg_strides(shape: &[usize]) -> Vec<usize> {
    let mut st = vec![1usize; shape.len()];
    for i in (0..shape.len().saturating_sub(1)).rev() { st[i] = st[i + 1] * shape[i + 1]; }
    st
}

fn rg_index(base: &RVal, idxs: &[RVal]) -> RVal {
    let u_idxs: Vec<usize> = idxs.iter().map(|v| rg_as_int(v).max(0) as usize).collect();
    match base {
        RVal::Tensor(shape, data) => {
            let strides = rg_strides(shape);
            let offset: usize = u_idxs.iter().zip(strides.iter()).map(|(&i, &s)| i * s).sum();
            if u_idxs.len() >= shape.len() {
                let val = data.get(offset).copied().unwrap_or(0.0);
                if val.fract() == 0.0 { RVal::Int(val as i64) } else { RVal::Real(val) }
            } else {
                let sub_shape = shape[u_idxs.len()..].to_vec();
                let slen: usize = sub_shape.iter().product();
                RVal::Tensor(Rc::new(sub_shape), Rc::new(data[offset..(offset + slen).min(data.len())].to_vec()))
            }
        }
        RVal::List(rc, st) => rc.get(*st + u_idxs.first().copied().unwrap_or(0)).cloned().unwrap_or(RVal::Unit),
        RVal::Tuple(rc) => rc.get(u_idxs.first().copied().unwrap_or(0)).cloned().unwrap_or(RVal::Unit),
        _ => RVal::Unit,
    }
}

fn rg_index_set(base: RVal, idxs: &[RVal], new_val: RVal) -> RVal {
    let u_idxs: Vec<usize> = idxs.iter().map(|v| rg_as_int(v).max(0) as usize).collect();
    if let RVal::Tensor(shape, data) = base {
        let strides = rg_strides(&shape);
        let offset: usize = u_idxs.iter().zip(strides.iter()).map(|(&i, &s)| i * s).sum();
        let mut new_data = (*data).clone();
        if offset < new_data.len() { new_data[offset] = rg_as_real(&new_val); }
        return RVal::Tensor(shape, Rc::new(new_data));
    }
    base
}

fn rg_einsum(tensors: &[RVal], subs: &[&str]) -> RVal {
    let mut idx_order: Vec<char> = Vec::new();
    let mut idx_counts: HashMap<char, usize> = HashMap::new();
    let mut idx_dims: HashMap<char, usize> = HashMap::new();
    for (t, sub) in tensors.iter().zip(subs.iter()) {
        if let RVal::Tensor(sh, _) = t {
            for (ch, &dim) in sub.chars().zip(sh.iter()) {
                if !idx_order.contains(&ch) { idx_order.push(ch); }
                *idx_counts.entry(ch).or_insert(0) += 1;
                idx_dims.insert(ch, dim);
            }
        }
    }
    let free: Vec<char> = idx_order.iter().copied().filter(|c| idx_counts.get(c).copied().unwrap_or(0) == 1).collect();
    let out_shape: Vec<usize> = if free.is_empty() { vec![1] } else { free.iter().map(|c| idx_dims[c]).collect() };
    let out_strides = rg_strides(&out_shape);
    let out_len: usize = out_shape.iter().product();
    let mut out_data = vec![0.0f64; out_len];
    let all_dims: Vec<usize> = idx_order.iter().map(|c| idx_dims[c]).collect();
    let total_iters: usize = all_dims.iter().product::<usize>().max(1);
    let all_strides = rg_strides(&all_dims);
    let t_strides: Vec<Vec<usize>> = tensors.iter().map(|t| match t { RVal::Tensor(sh, _) => rg_strides(sh), _ => Vec::new() }).collect();
    for flat_iter in 0..total_iters {
        let mut cmap: HashMap<char, usize> = HashMap::new();
        for (p, &ch) in idx_order.iter().enumerate() {
            cmap.insert(ch, (flat_iter / all_strides[p]) % all_dims[p]);
        }
        let mut prod = 1.0f64;
        for (ti, (t, sub)) in tensors.iter().zip(subs.iter()).enumerate() {
            if let RVal::Tensor(_, d) = t {
                let st = &t_strides[ti];
                let off: usize = sub.chars().enumerate().map(|( dm, ch)| cmap[&ch] * st[dm]).sum();
                prod *= d.get(off).copied().unwrap_or(0.0);
            }
        }
        let out_off: usize = if free.is_empty() { 0 } else { free.iter().enumerate().map(|(dm, ch)| cmap[ch] * out_strides[dm]).sum() };
        if out_off < out_data.len() { out_data[out_off] += prod; }
    }
    RVal::Tensor(Rc::new(out_shape), Rc::new(out_data))
}

fn rg_hadamard(op: &str, left: &RVal, s1: &str, right: &RVal, s2: &str) -> RVal {
    if let (RVal::Tensor(sh1, d1), RVal::Tensor(sh2, d2)) = (left, right) {
        let st1 = rg_strides(sh1);
        let st2 = rg_strides(sh2);
        let s1_ch: Vec<char> = s1.chars().collect();
        let mut out = vec![0.0f64; d1.len()];
        for fi in 0..d1.len() {
            let mut cmap: HashMap<char, usize> = HashMap::new();
            for (dm, &ch) in s1_ch.iter().enumerate() { cmap.insert(ch, (fi / st1[dm]) % sh1[dm]); }
            let roff: usize = s2.chars().enumerate().map(|(dm, ch)| cmap.get(&ch).copied().unwrap_or(0) * st2[dm]).sum();
            let lv = d1[fi];
            let rv = d2.get(roff).copied().unwrap_or(0.0);
            out[fi] = match op { "+" => lv + rv, "-" => lv - rv, "*" => lv * rv, "/" => lv / rv, _ => lv };
        }
        return RVal::Tensor(Rc::clone(sh1), Rc::new(out));
    }
    RVal::Unit
}

fn rg_fn_channel() -> RVal {
    let mut chs = RG_CHANNELS.get_or_init(|| Mutex::new(Vec::new())).lock().unwrap();
    let id = chs.len();
    chs.push(VecDeque::new());
    RVal::Int(id as i64)
}

fn rg_fn_new_channel() -> RVal { rg_fn_channel() }

fn rg_fn_send_through(val: RVal, ch: RVal) -> RVal {
    let cid = rg_as_int(&ch).max(0) as usize;
    let mut chs = RG_CHANNELS.get_or_init(|| Mutex::new(Vec::new())).lock().unwrap();
    while chs.len() <= cid { chs.push(VecDeque::new()); }
    chs[cid].push_back(val);
    rg_adt("Ok", vec![RVal::Unit])
}

fn rg_fn_receive_from(ch: RVal) -> RVal {
    let cid = rg_as_int(&ch).max(0) as usize;
    let mut chs = RG_CHANNELS.get_or_init(|| Mutex::new(Vec::new())).lock().unwrap();
    chs.get_mut(cid).and_then(|q| q.pop_front()).unwrap_or(RVal::Unit)
}

fn rg_fn_try_receive_from(ch: RVal) -> RVal {
    let cid = rg_as_int(&ch).max(0) as usize;
    let mut chs = RG_CHANNELS.get_or_init(|| Mutex::new(Vec::new())).lock().unwrap();
    match chs.get_mut(cid).and_then(|q| q.pop_front()) {
        Some(v) => rg_adt("Ok", vec![v]),
        None => rg_adt("Err", vec![rg_adt0("Empty")]),
    }
}

fn rg_fn_receive_from_timeout(ch: RVal, _ticks: RVal) -> RVal {
    let cid = rg_as_int(&ch).max(0) as usize;
    let mut chs = RG_CHANNELS.get_or_init(|| Mutex::new(Vec::new())).lock().unwrap();
    match chs.get_mut(cid).and_then(|q| q.pop_front()) {
        Some(v) => rg_adt("Ok", vec![v]),
        None => rg_adt("Err", vec![rg_adt0("Timeout")]),
    }
}

fn rg_fn_spawn(fn_name: RVal, arg: RVal) -> RVal {
    let name_str = match &fn_name { RVal::Str(s) => s.as_str().to_string(), _ => String::new() };
    let res = rg_dispatch_spawn(&name_str, arg);
    let mut ths = RG_THREADS.get_or_init(|| Mutex::new(Vec::new())).lock().unwrap();
    let tid = ths.len();
    ths.push(Some(res));
    RVal::Int(tid as i64)
}

fn rg_fn_join(tid: RVal) -> RVal {
    let id = rg_as_int(&tid).max(0) as usize;
    let mut ths = RG_THREADS.get_or_init(|| Mutex::new(Vec::new())).lock().unwrap();
    ths.get_mut(id).and_then(|o| o.take()).unwrap_or(RVal::Unit)
}

fn rg_echo(args: &[RVal]) -> RVal {
    let parts: Vec<String> = args.iter().map(|v| format!("{}", v)).collect();
    println!("{}", parts.join(" "));
    RVal::Unit
}

fn rg_out(v: RVal) -> RVal { println!("{}", v); RVal::Unit }

fn rg_fn_str_len(s: RVal) -> RVal { match s { RVal::Str(st) => RVal::Int(if st.is_ascii() { st.len() as i64 } else { st.chars().count() as i64 }), _ => RVal::Int(0) } }

fn rg_fn_str_char_at(s: RVal, i: RVal) -> RVal {
    let idx = rg_as_int(&i);
    if idx < 0 { return RVal::Int(-1); }
    match s {
        RVal::Str(st) => RVal::Int(if st.is_ascii() { st.as_bytes().get(idx as usize).map(|&b| b as i64).unwrap_or(-1) } else { st.chars().nth(idx as usize).map(|c| c as i64).unwrap_or(-1) }),
        _ => RVal::Int(-1),
    }
}

fn rg_fn_str_slice(s: RVal, a: RVal, b: RVal) -> RVal {
    let start = rg_as_int(&a).max(0) as usize;
    let end = rg_as_int(&b).max(0) as usize;
    match s {
        RVal::Str(st) => if st.is_ascii() {
            let sc = start.min(st.len()); let ec = end.min(st.len()).max(sc);
            RVal::Str(Rc::new(st[sc..ec].to_string()))
        } else {
            let chs: Vec<char> = st.chars().collect();
            let sc = start.min(chs.len()); let ec = end.min(chs.len()).max(sc);
            RVal::Str(Rc::new(chs[sc..ec].iter().collect()))
        },
        _ => rg_str(""),
    }
}

fn rg_fn_char_from_code(c: RVal) -> RVal {
    let ch = std::char::from_u32(rg_as_int(&c).max(0) as u32).unwrap_or(char::from(0u8));
    RVal::Str(Rc::new(ch.to_string()))
}

fn rg_fn_str_concat(a: RVal, b: RVal) -> RVal { RVal::Str(Rc::new(format!("{}{}", a, b))) }
fn rg_fn_int_to_str(n: RVal) -> RVal { RVal::Str(Rc::new(rg_as_int(&n).to_string())) }

fn rg_fn_str_to_int(s: RVal) -> RVal {
    let raw = match &s { RVal::Str(st) => st.trim(), _ => "0" };
    let cl = raw.replace("_", "");
    let v = if let Some(h) = cl.strip_prefix("0x").or_else(|| cl.strip_prefix("0X")) { i64::from_str_radix(h, 16).unwrap_or(0) } else { cl.parse::<i64>().unwrap_or(0) };
    RVal::Int(v)
}

fn rg_fn_str_starts_with(s: RVal, p: RVal) -> RVal {
    match (s, p) { (RVal::Str(a), RVal::Str(b)) => RVal::Bool(a.starts_with(b.as_str())), _ => RVal::Bool(false) }
}

fn rg_fn_str_contains(s: RVal, n: RVal) -> RVal {
    match (s, n) { (RVal::Str(a), RVal::Str(b)) => RVal::Bool(a.contains(b.as_str())), _ => RVal::Bool(false) }
}

fn rg_resolve_imports(src: &str, fpath: &Path, vis: &mut HashSet<PathBuf>) -> String {
    let pdir = fpath.parent().unwrap_or(Path::new("."));
    let mut imps = String::new();
    let mut body = String::new();
    for line in src.lines() {
        let tr = line.trim();
        if let Some(rest) = tr.strip_prefix("import ") {
            let m = rest.trim();
            let cands = [
                pdir.join(format!("{}.rg", m)),
                pdir.join("../lib").join(format!("{}.rg", m)),
                Path::new("src/main/ridgun/lib").join(format!("{}.rg", m)),
                Path::new("src/main/ridgun").join(format!("{}.rg", m)),
            ];
            if let Some(cand) = cands.iter().find(|p| p.exists()) {
                let cn = cand.canonicalize().unwrap_or_else(|_| cand.clone());
                if vis.insert(cn.clone()) {
                    if let Ok(sub) = std::fs::read_to_string(&cn) {
                        imps.push_str(&rg_resolve_imports(&sub, &cn, vis));
                        imps.push_str("\n");
                    }
                }
            }
            body.push_str("-- "); body.push_str(line); body.push_str("\n");
        } else {
            body.push_str(line); body.push_str("\n");
        }
    }
    format!("{}{}", imps, body)
}

fn rg_call1(f: &RVal, a: RVal) -> RVal {
    let fname = match f { RVal::Str(s) => s.as_str(), _ => "" };
    rg_dispatch_spawn(fname, a)
}

fn rg_call2(f: &RVal, a: RVal, b: RVal) -> RVal {
    let fname = match f { RVal::Str(s) => s.as_str(), _ => "" };
    rg_dispatch_call2(fname, a, b)
}

fn rg_fn_seq_map(f: RVal, xs: RVal) -> RVal {
    let fname = match &f { RVal::Str(s) => s.as_str(), _ => "" };
    match xs {
        RVal::List(rc, st) => {
            let slice = &rc[st.min(rc.len())..];
            let out: Vec<RVal> = slice.iter().map(|v| rg_dispatch_spawn(fname, v.clone())).collect();
            rg_list(out)
        }
        _ => rg_list(Vec::new()),
    }
}

fn rg_fn_map(f: RVal, xs: RVal) -> RVal {
    let fname = match &f { RVal::Str(s) => s.as_str().to_string(), _ => String::new() };
    match xs {
        RVal::List(rc, st) => {
            let slice = &rc[st.min(rc.len())..];
            if slice.len() < 4 {
                let out: Vec<RVal> = slice.iter().map(|v| rg_dispatch_spawn(&fname, v.clone())).collect();
                return rg_list(out);
            }
            let n_workers = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).min(slice.len()).max(1);
            let chunk_sz = (slice.len() + n_workers - 1) / n_workers;
            let mut out = Vec::with_capacity(slice.len());
            std::thread::scope(|s| {
                let mut handles = Vec::new();
                for chunk in slice.chunks(chunk_sz) {
                    let fn_c = fname.clone();
                    let items: Vec<RVal> = chunk.to_vec();
                    handles.push(s.spawn(move || {
                        items.into_iter().map(|v| rg_dispatch_spawn(&fn_c, v)).collect::<Vec<RVal>>()
                    }));
                }
                for h in handles {
                    if let Ok(part) = h.join() { out.extend(part); }
                }
            });
            rg_list(out)
        }
        _ => rg_list(Vec::new()),
    }
}

fn rg_fn_seq_filter(f: RVal, xs: RVal) -> RVal {
    let fname = match &f { RVal::Str(s) => s.as_str(), _ => "" };
    match xs {
        RVal::List(rc, st) => {
            let slice = &rc[st.min(rc.len())..];
            let out: Vec<RVal> = slice.iter().filter(|v| rg_as_bool(&rg_dispatch_spawn(fname, (*v).clone()))).cloned().collect();
            rg_list(out)
        }
        _ => rg_list(Vec::new()),
    }
}

fn rg_fn_filter(f: RVal, xs: RVal) -> RVal {
    let fname = match &f { RVal::Str(s) => s.as_str().to_string(), _ => String::new() };
    match xs {
        RVal::List(rc, st) => {
            let slice = &rc[st.min(rc.len())..];
            if slice.len() < 4 {
                let out: Vec<RVal> = slice.iter().filter(|v| rg_as_bool(&rg_dispatch_spawn(&fname, (*v).clone()))).cloned().collect();
                return rg_list(out);
            }
            let n_workers = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).min(slice.len()).max(1);
            let chunk_sz = (slice.len() + n_workers - 1) / n_workers;
            let mut out = Vec::new();
            std::thread::scope(|s| {
                let mut handles = Vec::new();
                for chunk in slice.chunks(chunk_sz) {
                    let fn_c = fname.clone();
                    let items: Vec<RVal> = chunk.to_vec();
                    handles.push(s.spawn(move || {
                        items.into_iter().filter(|v| rg_as_bool(&rg_dispatch_spawn(&fn_c, v.clone()))).collect::<Vec<RVal>>()
                    }));
                }
                for h in handles {
                    if let Ok(part) = h.join() { out.extend(part); }
                }
            });
            rg_list(out)
        }
        _ => rg_list(Vec::new()),
    }
}

fn rg_fn_fold(f: RVal, init: RVal, xs: RVal) -> RVal {
    let fname = match &f { RVal::Str(s) => s.as_str(), _ => "" };
    let mut acc = init;
    if let RVal::List(rc, st) = xs {
        for v in &rc[st.min(rc.len())..] {
            acc = rg_dispatch_call2(fname, acc, v.clone());
        }
    }
    acc
}

fn rg_read_raw_string(path_str: &str) -> String {
    let bytes = if path_str == "-" || path_str == "/dev/stdin" {
        use std::io::Read;
        let mut buf = Vec::new();
        let _ = std::io::stdin().read_to_end(&mut buf);
        buf
    } else {
        std::fs::read(path_str).unwrap_or_default()
    };
    match String::from_utf8(bytes) {
        Ok(s) => s,
        Err(e) => e.into_bytes().into_iter().map(|b| b as char).collect(),
    }
}

fn rg_fn_read_file(p: RVal) -> RVal {
    let path_str = match &p { RVal::Str(s) => s.as_str(), _ => "" };
    RVal::Str(Rc::new(rg_read_raw_string(path_str)))
}

fn rg_fn_load_rg_source(p: RVal) -> RVal {
    let path_str = match &p { RVal::Str(s) => s.as_str(), _ => "" };
    let raw = std::fs::read_to_string(path_str).unwrap_or_default();
    let fp = Path::new(path_str);
    let mut vis = HashSet::new();
    if let Ok(c) = fp.canonicalize() { vis.insert(c); }
    RVal::Str(Rc::new(rg_resolve_imports(&raw, fp, &mut vis)))
}

fn rg_fn_read_bytes(p: RVal) -> RVal {
    let path_str = match &p { RVal::Str(s) => s.as_str(), _ => "" };
    let bytes = if path_str == "-" || path_str == "/dev/stdin" {
        use std::io::Read;
        let mut buf = Vec::new();
        let _ = std::io::stdin().read_to_end(&mut buf);
        buf
    } else {
        std::fs::read(path_str).unwrap_or_default()
    };
    let out: Vec<RVal> = bytes.into_iter().map(|b| RVal::Int(b as i64)).collect();
    rg_list(out)
}

fn rg_fn_write_bytes(p: RVal, bs: RVal) -> RVal {
    let path_str = match &p { RVal::Str(s) => s.as_str(), _ => "" };
    if let RVal::List(rc, st) = bs {
        let raw: Vec<u8> = rc[st.min(rc.len())..].iter().map(|v| (rg_as_int(v) & 0xFF) as u8).collect();
        if path_str == "-" || path_str == "/dev/stdout" {
            use std::io::Write;
            let _ = std::io::stdout().write_all(&raw);
        } else {
            let _ = std::fs::write(path_str, &raw);
        }
    }
    RVal::Unit
}

fn rg_fn_write_file(p: RVal, c: RVal) -> RVal {
    if let (RVal::Str(ps), RVal::Str(cs)) = (p, c) { let _ = std::fs::write(ps.as_str(), cs.as_str()); }
    RVal::Unit
}

fn rg_fn_shell_exec(cmd: RVal) -> RVal {
    let cs = match &cmd { RVal::Str(s) => s.as_str(), _ => "" };
    let st = std::process::Command::new("sh").arg("-c").arg(cs).status().map(|s| s.code().unwrap_or(1) as i64).unwrap_or(-1);
    RVal::Int(st)
}

fn rg_fn_cli_args() -> RVal {
    let v: Vec<RVal> = std::env::args().map(|s| RVal::Str(Rc::new(s))).collect();
    RVal::List(Rc::new(v), 0)
}

fn rg_fn_list_dir(p: RVal) -> RVal {
    let path_str = match &p { RVal::Str(s) => s.as_str(), _ => "." };
    let mut names: Vec<String> = Vec::new();
    if let Ok(rd) = std::fs::read_dir(path_str) {
        for entry in rd.flatten() {
            if let Some(n) = entry.file_name().to_str() {
                names.push(n.to_string());
            }
        }
    }
    names.sort();
    rg_list(names.into_iter().map(|s| RVal::Str(Rc::new(s))).collect())
}

fn rg_lookup_id_name(file_path: &str, id: u32) -> String {
    let id_str = id.to_string();
    if let Ok(content) = std::fs::read_to_string(file_path) {
        for line in content.lines() {
            let parts: Vec<&str> = line.split(":").collect();
            if parts.len() >= 3 && parts[2] == id_str {
                return parts[0].to_string();
            }
        }
    }
    id_str
}

fn rg_fn_file_lstat(p: RVal) -> RVal {
    use std::os::unix::fs::{MetadataExt, FileTypeExt};
    let path_str = match &p { RVal::Str(s) => s.as_str(), _ => "" };
    match std::fs::symlink_metadata(path_str) {
        Ok(meta) => {
            let ft = meta.file_type();
            let kind = if ft.is_dir() { "dir" }
                else if ft.is_symlink() { "link" }
                else if ft.is_fifo() { "fifo" }
                else if ft.is_socket() { "sock" }
                else if ft.is_block_device() { "block" }
                else if ft.is_char_device() { "char" }
                else { "file" };
            let mode = (meta.mode() & 0o7777) as i64;
            let nlink = meta.nlink() as i64;
            let size = meta.len() as i64;
            let owner = rg_lookup_id_name("/etc/passwd", meta.uid());
            let group = rg_lookup_id_name("/etc/group", meta.gid());
            let mtime = meta.mtime();
            let link_target = if ft.is_symlink() {
                std::fs::read_link(path_str).ok().and_then(|pb| pb.to_str().map(|s| s.to_string())).unwrap_or_default()
            } else {
                String::new()
            };
            rg_tuple(vec![
                RVal::Bool(true),
                rg_str(kind),
                RVal::Int(mode),
                RVal::Int(nlink),
                RVal::Int(size),
                rg_str(&owner),
                rg_str(&group),
                RVal::Int(mtime),
                rg_str(&link_target),
            ])
        }
        Err(_) => rg_tuple(vec![
            RVal::Bool(false),
            rg_str(""),
            RVal::Int(0),
            RVal::Int(0),
            RVal::Int(0),
            rg_str(""),
            rg_str(""),
            RVal::Int(0),
            rg_str(""),
        ]),
    }
}

fn rg_sha256_bytes(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    let mut h: [u32; 8] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut msg = data.to_vec();
    msg.push(0x80);
    while (msg.len() % 64) != 56 { msg.push(0); }
    msg.extend_from_slice(&bit_len.to_be_bytes());
    for chunk in msg.chunks_exact(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([chunk[i*4], chunk[i*4+1], chunk[i*4+2], chunk[i*4+3]]);
        }
        for i in 16..64 {
            let s0 = w[i-15].rotate_right(7) ^ w[i-15].rotate_right(18) ^ (w[i-15] >> 3);
            let s1 = w[i-2].rotate_right(17) ^ w[i-2].rotate_right(19) ^ (w[i-2] >> 10);
            w[i] = w[i-16].wrapping_add(s0).wrapping_add(w[i-7]).wrapping_add(s1);
        }
        let (mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]);
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);
            hh = g; g = f; f = e; e = d.wrapping_add(temp1); d = c; c = b; b = a; a = temp1.wrapping_add(temp2);
        }
        h[0] = h[0].wrapping_add(a); h[1] = h[1].wrapping_add(b); h[2] = h[2].wrapping_add(c); h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e); h[5] = h[5].wrapping_add(f); h[6] = h[6].wrapping_add(g); h[7] = h[7].wrapping_add(hh);
    }
    format!("{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}", h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
}

fn rg_fn_sha256_file(p: RVal) -> RVal {
    let path_str = match &p { RVal::Str(s) => s.as_str(), _ => "" };
    let bytes = std::fs::read(path_str).unwrap_or_default();
    rg_str(&rg_sha256_bytes(&bytes))
}

fn rg_fn_sha256_str(s: RVal) -> RVal {
    let st = match &s { RVal::Str(v) => v.as_bytes(), _ => &[] };
    rg_str(&rg_sha256_bytes(st))
}

fn rg_fn_sys_mkdir(p: RVal, mode: RVal) -> RVal {
    use std::os::unix::fs::PermissionsExt;
    let path_str = match &p { RVal::Str(s) => s.as_str(), _ => "" };
    let m = (rg_as_int(&mode) & 0o7777) as u32;
    if std::fs::create_dir_all(path_str).is_ok() {
        let _ = std::fs::set_permissions(path_str, std::fs::Permissions::from_mode(m));
        RVal::Int(0)
    } else {
        RVal::Int(-1)
    }
}

fn rg_fn_sys_chmod(p: RVal, mode: RVal) -> RVal {
    use std::os::unix::fs::PermissionsExt;
    let path_str = match &p { RVal::Str(s) => s.as_str(), _ => "" };
    let m = (rg_as_int(&mode) & 0o7777) as u32;
    if std::fs::set_permissions(path_str, std::fs::Permissions::from_mode(m)).is_ok() {
        RVal::Int(0)
    } else {
        RVal::Int(-1)
    }
}

fn rg_extract_str_vec(v: &RVal) -> Vec<String> {
    match v {
        RVal::List(rc, st) => rc[(*st).min(rc.len())..].iter().map(|x| format!("{}", x)).collect(),
        _ => Vec::new(),
    }
}

fn rg_fn_sys_exec(prog: RVal, args: RVal, env_list: RVal) -> RVal {
    let prog_str = match &prog { RVal::Str(s) => s.as_str(), _ => "" };
    let arg_vec = rg_extract_str_vec(&args);
    let env_vec = rg_extract_str_vec(&env_list);
    let mut cmd = std::process::Command::new(prog_str);
    cmd.args(&arg_vec);
    for kv in env_vec {
        if let Some((k, v)) = kv.split_once("=") {
            cmd.env(k, v);
        }
    }
    let st = cmd.status().map(|s| s.code().unwrap_or(1) as i64).unwrap_or(-1);
    RVal::Int(st)
}

fn rg_fn_sys_chdir(p: RVal) -> RVal {
    let path_str = match &p { RVal::Str(s) => s.as_str(), _ => "." };
    if std::env::set_current_dir(path_str).is_ok() { RVal::Int(0) } else { RVal::Int(-1) }
}

fn rg_fn_sys_getcwd() -> RVal {
    let cwd = std::env::current_dir().ok().and_then(|p| p.to_str().map(|s| s.to_string())).unwrap_or_default();
    rg_str(&cwd)
}

fn rg_fn_sys_getenv(k: RVal) -> RVal {
    let key = match &k { RVal::Str(s) => s.as_str(), _ => "" };
    let val = std::env::var(key).unwrap_or_default();
    rg_str(&val)
}

fn rg_fn_sys_setenv(k: RVal, v: RVal) -> RVal {
    if let (RVal::Str(ks), RVal::Str(vs)) = (k, v) {
        std::env::set_var(ks.as_str(), vs.as_str());
        RVal::Int(0)
    } else {
        RVal::Int(-1)
    }
}

fn rg_fn_sys_exit(code: RVal) -> RVal {
    std::process::exit(rg_as_int(&code) as i32);
}

extern "C" {
    fn getuid() -> u32;
    fn getgid() -> u32;
    fn setresgid(rgid: u32, egid: u32, sgid: u32) -> i32;
    fn setresuid(ruid: u32, euid: u32, suid: u32) -> i32;
    fn setgroups(size: usize, list: *const u32) -> i32;
}

fn rg_fn_sys_getuid() -> RVal { RVal::Int(unsafe { getuid() } as i64) }
fn rg_fn_sys_getgid() -> RVal { RVal::Int(unsafe { getgid() } as i64) }

fn rg_fn_sys_username(uid: RVal) -> RVal {
    let u = rg_as_int(&uid).max(0) as u32;
    rg_str(&rg_lookup_id_name("/etc/passwd", u))
}

fn rg_fn_sys_lookup_uid_gid(user: RVal) -> RVal {
    let uname = match &user { RVal::Str(s) => s.as_str(), _ => "" };
    if let Ok(content) = std::fs::read_to_string("/etc/passwd") {
        for line in content.lines() {
            let parts: Vec<&str> = line.split(":").collect();
            if parts.len() >= 4 && parts[0] == uname {
                let u = parts[2].parse::<i64>().unwrap_or(-1);
                let g = parts[3].parse::<i64>().unwrap_or(-1);
                return rg_tuple(vec![RVal::Int(u), RVal::Int(g)]);
            }
        }
    }
    rg_tuple(vec![RVal::Int(-1), RVal::Int(-1)])
}

fn rg_fn_sys_user_groups(user: RVal) -> RVal {
    let uname = match &user { RVal::Str(s) => s.as_str(), _ => "" };
    let mut groups: Vec<String> = Vec::new();
    let mut pri_gid: Option<u32> = None;
    if let Ok(content) = std::fs::read_to_string("/etc/passwd") {
        for line in content.lines() {
            let parts: Vec<&str> = line.split(":").collect();
            if parts.len() >= 4 && parts[0] == uname {
                pri_gid = parts[3].parse::<u32>().ok();
                break;
            }
        }
    }
    if let Ok(content) = std::fs::read_to_string("/etc/group") {
        for line in content.lines() {
            let parts: Vec<&str> = line.split(":").collect();
            if parts.len() >= 4 {
                let gname = parts[0];
                let gid_ok = pri_gid.map(|g| parts[2] == g.to_string()).unwrap_or(false);
                let mem_ok = parts[3].split(",").any(|m| m == uname);
                if (gid_ok || mem_ok) && !groups.contains(&gname.to_string()) {
                    groups.push(gname.to_string());
                }
            }
        }
    }
    rg_list(groups.into_iter().map(|s| RVal::Str(Rc::new(s))).collect())
}

fn rg_fn_sys_setresgid(gid: RVal) -> RVal {
    let g = rg_as_int(&gid) as u32;
    RVal::Int(unsafe { setresgid(g, g, g) } as i64)
}

fn rg_fn_sys_setgroups(gids: RVal) -> RVal {
    let gs: Vec<u32> = match &gids {
        RVal::List(rc, st) => rc[(*st).min(rc.len())..].iter().map(|v| rg_as_int(v) as u32).collect(),
        _ => Vec::new(),
    };
    RVal::Int(unsafe { setgroups(gs.len(), gs.as_ptr()) } as i64)
}

fn rg_fn_sys_setresuid(uid: RVal) -> RVal {
    let u = rg_as_int(&uid) as u32;
    RVal::Int(unsafe { setresuid(u, u, u) } as i64)
}

fn rg_fn_sys_execve(prog: RVal, args: RVal, env_list: RVal) -> RVal {
    use std::os::unix::process::CommandExt;
    let prog_str = match &prog { RVal::Str(s) => s.as_str(), _ => "" };
    let arg_vec = rg_extract_str_vec(&args);
    let env_vec = rg_extract_str_vec(&env_list);
    let mut cmd = std::process::Command::new(prog_str);
    cmd.args(&arg_vec);
    cmd.env_clear();
    for kv in env_vec {
        if let Some((k, v)) = kv.split_once("=") {
            cmd.env(k, v);
        }
    }
    let _err = cmd.exec();
    RVal::Int(-1)
}

fn rg_fn_sys_read_pass(prompt: RVal) -> RVal {
    use std::io::{BufRead, Write};
    let pr = match &prompt { RVal::Str(s) => s.as_str(), _ => "" };
    if let Ok(mut tty) = std::fs::OpenOptions::new().read(true).write(true).open("/dev/tty") {
        let _ = tty.write_all(pr.as_bytes());
        let _ = tty.flush();
        let mut reader = std::io::BufReader::new(tty);
        let mut line = String::new();
        let _ = reader.read_line(&mut line);
        return rg_str(line.trim_end());
    }
    let mut line = String::new();
    let _ = std::io::stdin().read_line(&mut line);
    rg_str(line.trim_end())
}
'

fn :: emit_native_program RProgram => String
      emit_native_program (Program raw_fns tys) =
        sigs = build_cg_sigs raw_fns
        all_fns = prep_fndef_list raw_fns sigs
        entry = find_entry_fn_name all_fns "main"
        reachable = expand_reachable_worklist [entry] all_fns []
        fns = filter_reachable_fndefs all_fns reachable
        preamble = emit_runtime_preamble
        acc_defs = emit_typedef_accessors tys (collect_fn_names fns)
        fn_defs = emit_native_fndef_list fns
        dispatches = emit_dispatch_tables fns
        preamble + acc_defs + fn_defs + dispatches + 'fn main() {' + "\n" + '  let child = std::thread::Builder::new().stack_size(268435456).spawn(|| {' + "\n" + '    let _ = ' + (mangle_fn_name entry) + '();' + "\n" + '  }).unwrap();' + "\n" + '  let _ = child.join();' + "\n" + '}' + "\n"

-- ── Bytecode (.rgc) & Native Executable Emission ────────────

fn :: join_summaries [String] => String
      join_summaries []       =  ""
      join_summaries (s:ss)   =  "-- SUMMARY: {s}\n" + (join_summaries ss)

fn :: emit_rgc_payload RProgram String  => String
      emit_rgc_payload prog     raw_src =
        fn_count = count_fn_defs prog
        ty_count = count_type_defs prog
        summaries = join_summaries (analyze_rprogram prog)
        "RGC1\n-- SELF_HOSTED_COMPILER: ridgunc v0.9.3\n-- FUNCTIONS: {fn_count}\n-- TYPES: {ty_count}\n{summaries}{raw_src}"

fn :: emit_rgc_file String     String      => Int
      emit_rgc_file input_path output_path =
        raw_src = load_rg_source input_path
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

fn :: build_native_executable String     String     => Int
      build_native_executable input_path output_bin =
        raw_src = load_rg_source input_path
        toks = tokenize_src raw_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        build_native_after_check prog output_bin errs

fn :: build_native_after_check RProgram String     [RTypeError] => Int
      build_native_after_check prog     output_bin []           =
        native_rs = emit_native_program prog
        tmp_rs = output_bin + "_gen.rs"
        tmp_bin = output_bin + "_tmp"
        _ = write_file tmp_rs native_rs
        cmd = "rustc --edition 2021 --crate-name ridgun_bin -C opt-level=z -C lto=fat -C codegen-units=1 -C panic=abort -C strip=symbols -A warnings " + tmp_rs + " -o " + tmp_bin + " && mv -f " + tmp_bin + " " + output_bin + "; _st=$?; rm -f " + tmp_rs + " " + tmp_bin + "; exit $_st"
        shell_exec cmd
      build_native_after_check _        _          errs         =
        _ = echo (format_type_errors errs)
        1
