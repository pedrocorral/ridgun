-- ============================================================
-- src/main/ridgun/compiler.rg
-- Self-Hosted Ridgun AST-to-Bytecode & Native AOT Compiler
-- Full Ridgun v0.9.0 Spec: Sum & Record ADTs, Operator Overloading,
-- Variadics, Sequences/Masks/FlatJoin, Tensors/Einsum/Hadamard,
-- Where-DAGs, ParPipes, Channels/Spawn/Join, Scoped Globals/Context/
-- Shared Atomics, and Bare-Metal Hardware MMIO & Region Quotas.
-- @implements FR-COMP-001
-- @implements FR-COMP-006
-- @implements FR-COMP-007
-- @implements FR-COMP-008
-- @implements FR-COMP-009
-- @implements FR-COMP-010
-- @implements FR-COMP-011
-- @implements FR-COMP-012
-- @implements FR-COMP-013
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
import llvm

-- ── Local Variable Table Helpers ────────────────────────────

fn :: list str len [String] => Int
      list str len []       =  0
      list str len (_:xs)   =  1 + (list_str_len xs)

fn :: pat list len [RPattern] => Int
      pat list len []         =  0
      pat list len (_:xs)     =  1 + (pat_list_len xs)

fn :: find local idx [String] String Int => Int
      find local idx [] _ _ = -1
      find local idx (x:xs) target idx
        | x == target = idx
        | otherwise = find_local_idx xs target (idx + 1)

fn :: lookup local [String] String => Int
      lookup local locals   name   =  find_local_idx locals name 0

fn :: ensure local [String] String => [String] Int
      ensure local locals   name   =
        existing = lookup_local locals name
        ensure_local_branch locals name existing

fn :: ensure local branch [String] String Int => [String] Int
      ensure local branch locals name existing
        | existing >= 0 = (locals, existing)
        | otherwise = (locals :: [name], list_str_len locals)

fn :: rinstr len [RInstr] => Int
      rinstr len []       =  0
      rinstr len (_:xs)   =  1 + (rinstr_len xs)

-- ── Pattern Binding & Match Emission (Bytecode) ─────────────

fn :: bind pat vars [RPattern] Int [String] => [String]
      bind pat vars [] _ locals = locals
      bind pat vars ((PatVar v):ps) idx locals =
        bind_pat_vars ps (idx + 1) (locals :: [v])
      bind pat vars ((PatSeqBind v):ps) idx locals =
        bind_pat_vars ps (idx + 1) (locals :: [v])
      bind pat vars (_:ps) idx locals =
        bind_pat_vars ps (idx + 1) (locals :: ['_arg_' + (int_to_str idx)])

fn :: emit pat checks [RPattern] Int Int => [RInstr]
      emit pat checks [] _ _ = []
      emit pat checks ((PatInt n):ps) slot fail_ip =
        [BLoadLocal slot, BPushInt n, BJumpIfNeq fail_ip] :: (emit_pat_checks ps (slot + 1) fail_ip)
      emit pat checks ((PatReal r):ps) slot fail_ip =
        [BLoadLocal slot, BPushReal r, BJumpIfNeq fail_ip] :: (emit_pat_checks ps (slot + 1) fail_ip)
      emit pat checks ((PatStr s):ps) slot fail_ip =
        [BLoadLocal slot, BPushStr s, BJumpIfNeq fail_ip] :: (emit_pat_checks ps (slot + 1) fail_ip)
      emit pat checks ((PatBool b):ps) slot fail_ip =
        [BLoadLocal slot, BPushBool b, BJumpIfNeq fail_ip] :: (emit_pat_checks ps (slot + 1) fail_ip)
      emit pat checks (PatEmpty:ps) slot fail_ip =
        [BLoadLocal slot, BJumpIfNotEmpty fail_ip] :: (emit_pat_checks ps (slot + 1) fail_ip)
      emit pat checks (_:ps) slot fail_ip =
        emit_pat_checks ps (slot + 1) fail_ip

-- ── Expression Lowering to [RInstr] ─────────────────────────

fn :: compile binop RBinOp     => RInstr
      compile binop OpAdd      =  BAdd
      compile binop OpSub      =  BSub
      compile binop OpMul      =  BMul
      compile binop OpDiv      =  BDiv
      compile binop OpMod      =  BMod
      compile binop OpEq       =  BCmpEq
      compile binop OpNeq      =  BCmpNeq
      compile binop OpGt       =  BCmpGt
      compile binop OpLt       =  BCmpLt
      compile binop OpGtEq     =  BCmpGtEq
      compile binop OpLtEq     =  BCmpLtEq
      compile binop OpAnd      =  BAnd
      compile binop OpOr       =  BOr
      compile binop OpXor      =  BXor
      compile binop OpConcat   =  BListConcat 2
      compile binop OpFlatJoin =  BSeqFlatJoin
      compile binop OpMatMul   =  BMul
      compile binop OpShl      =  BMul
      compile binop OpShr      =  BDiv
      compile binop OpRotr     =  BXor
      compile binop OpRotl     =  BXor

fn :: compile rexpr RExpr              [String] => [RInstr] [String]
      compile rexpr (EInt n)           locals   =  ([BPushInt n], locals)
      compile rexpr (EReal r)          locals   =  ([BPushReal r], locals)
      compile rexpr (EStr s)           locals   =  ([BPushStr s], locals)
      compile rexpr (EStrInterp parts) locals   =
        p_res = compile_rexpr_list parts locals
        append_instr (BStrInterp (rexpr_list_len parts)) p_res
      compile rexpr (EBool b)          locals   =  ([BPushBool b], locals)
      compile rexpr EUnit              locals   =  ([BPushUnit], locals)
      compile rexpr (EVar name)        locals   =
        idx = lookup_local locals name
        compile_var_lookup name idx locals
      compile rexpr (ENot inner)       locals   =
        r1 = compile_rexpr inner locals
        append_instr BNot r1
      compile rexpr (EOut inner)       locals   =
        r1 = compile_rexpr inner locals
        append_instr BOut r1
      compile rexpr (EBin bop l r)     locals   =
        r1 = compile_rexpr l locals
        compile_bin_rhs bop r r1
      compile rexpr (ECall fname args) locals   =
        args_res = compile_rexpr_list args locals
        append_instr (BCall fname (rexpr_list_len args)) args_res
      compile rexpr (EEcho args)       locals   =
        args_res = compile_rexpr_list args locals
        append_instr (BEcho (rexpr_list_len args)) args_res
      compile rexpr (EList elems)      locals   =
        elems_res = compile_rexpr_list elems locals
        append_instr (BListConcat (rexpr_list_len elems)) elems_res
      compile rexpr (ETuple elems)     locals   =
        elems_res = compile_rexpr_list elems locals
        append_instr (BMakeTuple (rexpr_list_len elems)) elems_res
      compile rexpr (ETensor elems)    locals   =
        elems_res = compile_rexpr_list elems locals
        append_instr (BMakeTensor (rexpr_list_len elems)) elems_res
      compile rexpr (EEinsum es subs)  locals   =
        es_res = compile_rexpr_list es locals
        append_instr (BTensorEinsum subs) es_res
      compile rexpr (EHadamard bop l s1 r s2) locals =
        r1 = compile_rexpr l locals
        r2 = compile_rexpr_after r r1
        append_instr (BTensorHadamard bop s1 s2) r2
      compile rexpr (EIndex base idxs) locals   =
        b_res = compile_rexpr base locals
        i_res = compile_rexpr_list_after idxs b_res
        append_instr (BTensorGet (rexpr_list_len idxs)) i_res
      compile rexpr (EIndexAssign target idxs val_e) locals =
        slot_res = ensure_local locals target
        compile_index_assign_bc slot_res idxs val_e
      compile rexpr (ESeqSelect base mask) locals =
        b_res = compile_rexpr base locals
        append_instr (BSeqSelectMask mask) b_res
      compile rexpr (EBlock stmts)     locals   =
        compile_rblock stmts locals
      compile rexpr (EGuard guards)    locals   =
        compile_rguard_expr guards locals
      compile rexpr (EWhere body binds) locals  =
        w_res = compile_where_list binds locals
        compile_where_body body w_res
      compile rexpr (EParPipe branches) locals  =
        b_res = compile_rexpr_list branches locals
        append_instr (BMakeTuple (rexpr_list_len branches)) b_res
      compile rexpr (EWithCtx ctx_name val_e body) locals =
        v_res = compile_rexpr val_e locals
        v_push = append_instr (BPushCtx ctx_name) v_res
        b_res = compile_rexpr_after body v_push
        append_instr (BPopCtx ctx_name) b_res
      compile rexpr (EWithRegion quota body) locals =
        b_res = compile_rexpr body locals
        wrap_region_bc quota b_res

fn :: compile rexpr after RExpr ([RInstr], [String]) => [RInstr] [String]
      compile rexpr after e     (c1, locals1)        =
        r2 = compile_rexpr e locals1
        merge_code_pair c1 r2

fn :: compile rexpr list after [RExpr] ([RInstr], [String]) => [RInstr] [String]
      compile rexpr list after es (c1, locals1) =
        r2 = compile_rexpr_list es locals1
        merge_code_pair c1 r2

fn :: compile index assign bc ([String], Int) [RExpr] RExpr => [RInstr] [String]
      compile index assign bc (locals1, slot) idxs val_e =
        i_res = compile_rexpr_list idxs locals1
        v_res = compile_rexpr_after val_e i_res
        finish_index_assign_bc slot (rexpr_list_len idxs) v_res

fn :: finish index assign bc Int Int ([RInstr], [String]) => [RInstr] [String]
      finish index assign bc slot ndim (code, locals2) =
        ([BLoadLocal slot] :: code :: [BTensorSet ndim, BStoreLocal slot, BPushUnit], locals2)

fn :: wrap region bc Int   ([RInstr], [String]) => [RInstr] [String]
      wrap region bc quota (b_code, locals1)    =
        ([BEnterRegion quota] :: b_code :: [BExitRegion], locals1)

fn :: compile var lookup String Int [String] => [RInstr] [String]
      compile var lookup name idx locals
        | idx >= 0 = ([BLoadLocal idx], locals)
        | otherwise = ([BCall name 0], locals)

fn :: append instr RInstr ([RInstr], [String]) => [RInstr] [String]
      append instr ins    (code, locals)       =  (code :: [ins], locals)

fn :: compile bin rhs RBinOp RExpr ([RInstr], [String]) => [RInstr] [String]
      compile bin rhs bop r (l_code, locals1) =
        r_res = compile_rexpr r locals1
        merge_bin_code (compile_binop bop) l_code r_res

fn :: merge bin code RInstr [RInstr] ([RInstr], [String]) => [RInstr] [String]
      merge bin code ins l_code (r_code, locals2) =
        (l_code :: r_code :: [ins], locals2)

fn :: rexpr list len [RExpr] => Int
      rexpr list len []      =  0
      rexpr list len (_:xs)  =  1 + (rexpr_list_len xs)

fn :: compile rexpr list [RExpr] [String] => [RInstr] [String]
      compile rexpr list []      locals   =  ([], locals)
      compile rexpr list (e:es)  locals   =
        r1 = compile_rexpr e locals
        compile_rexpr_list_cont es r1

fn :: compile rexpr list cont [RExpr] ([RInstr], [String]) => [RInstr] [String]
      compile rexpr list cont es (c1, locals1) =
        r2 = compile_rexpr_list es locals1
        merge_code_pair c1 r2

fn :: merge code pair [RInstr] ([RInstr], [String]) => [RInstr] [String]
      merge code pair c1       (c2, locals2)        =  (c1 :: c2, locals2)

fn :: compile rguard expr [RGuard] [String] => [RInstr] [String]
      compile rguard expr []       locals   =  ([BPushUnit], locals)
      compile rguard expr ((GuardBranch _ body):[]) locals =
        compile_rexpr body locals
      compile rguard expr ((GuardBranch _ body):_) locals =
        compile_rexpr body locals

fn :: compile rblock [RStmt]           [String] => [RInstr] [String]
      compile rblock []                locals   =  ([BPushUnit], locals)
      compile rblock ((StmtExpr e):[]) locals   =  compile_rexpr e locals
      compile rblock ((StmtLet v e):rest) locals =
        e_res = compile_rexpr e locals
        compile_rblock_after_let v rest e_res
      compile rblock ((StmtMut v e):rest) locals =
        e_res = compile_rexpr e locals
        compile_rblock_after_let v rest e_res
      compile rblock ((StmtIndexAssign t idxs e):rest) locals =
        e_res = compile_rexpr (EIndexAssign t idxs e) locals
        compile_rblock_after_expr rest e_res
      compile rblock ((StmtExpr e):rest) locals =
        e_res = compile_rexpr e locals
        compile_rblock_after_expr rest e_res

fn :: compile rblock after let String [RStmt] ([RInstr], [String]) => [RInstr] [String]
      compile rblock after let v rest (e_code, locals1) =
        slot_res = ensure_local locals1 v
        compile_rblock_store_let rest e_code slot_res

fn :: compile rblock store let [RStmt] [RInstr] ([String], Int) => [RInstr] [String]
      compile rblock store let [] e_code (locals2, slot) =
        (e_code :: [BStoreLocal slot, BLoadLocal slot], locals2)
      compile rblock store let rest e_code (locals2, slot) =
        r_more = compile_rblock rest locals2
        merge_code_pair (e_code :: [BStoreLocal slot]) r_more

fn :: compile rblock after expr [RStmt] ([RInstr], [String]) => [RInstr] [String]
      compile rblock after expr [] (e_code, locals1) = (e_code, locals1)
      compile rblock after expr rest (e_code, locals1) =
        r_more = compile_rblock rest locals1
        merge_code_pair (e_code :: [BPop]) r_more

fn :: compile where list [RWhereBind] [String] => [RInstr] [String]
      compile where list []           locals   =  ([], locals)
      compile where list ((WhereBind e v _):wbs) locals =
        e_res = compile_rexpr e locals
        compile_where_list_step v wbs e_res

fn :: compile where list step String [RWhereBind] ([RInstr], [String]) => [RInstr] [String]
      compile where list step v wbs (e_code, locals1) =
        slot_res = ensure_local locals1 v
        compile_where_store wbs e_code slot_res

fn :: compile where store [RWhereBind] [RInstr] ([String], Int) => [RInstr] [String]
      compile where store wbs e_code (locals2, slot) =
        more = compile_where_list wbs locals2
        merge_code_pair (e_code :: [BStoreLocal slot]) more

fn :: compile where body RExpr ([RInstr], [String]) => [RInstr] [String]
      compile where body body  (w_code, locals1)    =
        b_res = compile_rexpr body locals1
        merge_code_pair w_code b_res

-- ── Function & Case Lowering (Bytecode) ─────────────────────

fn :: compile guards [RGuard] [String] Int     => [RInstr]
      compile guards []       _        _       =  []
      compile guards ((GuardBranch cond body):gs) locals base_ip =
        c_res = compile_rexpr cond locals
        b_res = compile_rexpr body locals
        emit_guard_branch gs locals base_ip c_res b_res

fn :: emit guard branch [RGuard] [String] Int ([RInstr], [String]) ([RInstr], [String]) => [RInstr]
      emit guard branch gs locals base_ip (c_code, _) (b_code, _) =
        next_guard_ip = base_ip + (rinstr_len c_code) + 1 + (rinstr_len b_code) + 1
        this_guard = c_code :: [BJumpIfFalse next_guard_ip] :: b_code :: [BReturn]
        this_guard :: (compile_guards gs locals next_guard_ip)

fn :: compile single case RFnCase Int     => [RInstr]
      compile single case (FnCase pats guards body) base_ip =
        locals = bind_pat_vars pats 0 []
        compile_case_inner pats guards body locals base_ip

fn :: compile case inner [RPattern] [RGuard] RExpr [String] Int => [RInstr]
      compile case inner pats [] body locals base_ip =
        b_res = compile_rexpr body locals
        finish_case_with_body pats base_ip b_res
      compile case inner pats guards _ locals base_ip =
        p_pre = emit_pat_checks pats 0 0
        g_code = compile_guards guards locals (base_ip + (rinstr_len p_pre))
        fail_ip = base_ip + (rinstr_len p_pre) + (rinstr_len g_code)
        p_checks = emit_pat_checks pats 0 fail_ip
        p_checks :: g_code

fn :: finish case with body [RPattern] Int ([RInstr], [String]) => [RInstr]
      finish case with body pats base_ip (b_code, _) =
        p_pre = emit_pat_checks pats 0 0
        fail_ip = base_ip + (rinstr_len p_pre) + (rinstr_len b_code) + 1
        p_checks = emit_pat_checks pats 0 fail_ip
        p_checks :: b_code :: [BReturn]

fn :: compile cases seq [RFnCase] Int     => [RInstr]
      compile cases seq []        _       =  []
      compile cases seq (c:cs)    base_ip =
        c_code = compile_single_case c base_ip
        next_ip = base_ip + (rinstr_len c_code)
        c_code :: (compile_cases_seq cs next_ip)

fn :: compile rfndef RFnDef => RCompiledFn
      compile rfndef (FnDef name params _ cases) =
        arity = list_str_len params
        code = compile_cases_seq cases 0
        CompiledFn name arity code

fn :: compile rfndef list [RFnDef] => [RCompiledFn]
      compile rfndef list []       =  []
      compile rfndef list (f:fs)   =  [compile_rfndef f] :: (compile_rfndef_list fs)

fn :: compile rprogram RProgram        => RCompiledProg
      compile rprogram (Program fns _) =
        CompiledProg (compile_rfndef_list fns)

-- ── Pre-Codegen Normalization (Variadic Packing & Tuple-Chain Unpacking) ──

type RCgSig = CgSig String Int Bool

fn :: str ends with dots String => Bool
      str ends with dots s      =
        len = str_len s
        len > 3 AND (str_slice s (len - 3) len) == "..."

fn :: params has variadic [String] => Bool
      params has variadic []       =  False
      params has variadic (p:[])   =  str_ends_with_dots p
      params has variadic (_:ps)   =  params_has_variadic ps

fn :: infer fndef arity [String] [RFnCase] => Int
      infer fndef arity params   ((FnCase ((PatSeqBind _):[]) _ _):_) = list_str_len params
      infer fndef arity _        ((FnCase pats _ _):_) = pat_list_len pats
      infer fndef arity params   []        =  list_str_len params

fn :: build cg sigs acc [RFnDef] [RCgSig] => [RCgSig]
      build cg sigs acc []       acc      =  acc
      build cg sigs acc ((FnDef name params _ cases):fs) acc =
        build_cg_sigs_acc fs (acc :: [CgSig name (infer_fndef_arity params cases) (params_has_variadic params)])

fn :: build cg sigs [RFnDef] => [RCgSig]
      build cg sigs fns      =  build_cg_sigs_acc fns []

fn :: lookup var cg sig [RCgSig] String => Bool Int Bool
      lookup var cg sig []       _      =  (False, 0, False)
      lookup var cg sig ((CgSig name arity is_var):rest) target
        | name == target AND arity < 0 = (False, 0, False)
        | name == target = (True, arity, is_var)
        | otherwise = lookup_var_cg_sig rest target

fn :: lookup cg sig [RCgSig] String => Bool Int Bool
      lookup cg sig []       _      =  (False, 0, False)
      lookup cg sig ((CgSig name arity is_var):rest) target
        | arity >= 0 AND name == target = (True, arity, is_var)
        | otherwise = lookup_cg_sig rest target

fn :: bind pat cg sigs RPattern [RCgSig] => [RCgSig]
      bind pat cg sigs (PatVar v) sigs = [CgSig v (0 - 2) False] :: sigs
      bind pat cg sigs (PatSeqBind v) sigs = [CgSig v (0 - 2) False] :: sigs
      bind pat cg sigs (PatCons h t) sigs = bind_pat_cg_sigs t (bind_pat_cg_sigs h sigs)
      bind pat cg sigs (PatTuple ps) sigs = bind_pat_list_cg_sigs ps sigs
      bind pat cg sigs (PatCtor _ ps) sigs = bind_pat_list_cg_sigs ps sigs
      bind pat cg sigs _ sigs = sigs

fn :: bind pat list cg sigs [RPattern] [RCgSig] => [RCgSig]
      bind pat list cg sigs [] sigs = sigs
      bind pat list cg sigs (p:ps) sigs = bind_pat_list_cg_sigs ps (bind_pat_cg_sigs p sigs)

fn :: bind where cg sigs [RWhereBind] [RCgSig] => [RCgSig]
      bind where cg sigs [] sigs = sigs
      bind where cg sigs ((WhereBind _ v _):wbs) sigs
        | v != "" = bind_where_cg_sigs wbs ([CgSig v (0 - 2) False] :: sigs)
        | otherwise = bind_where_cg_sigs wbs sigs

fn :: prep expr RExpr              [RCgSig] => RExpr
      prep expr (ENot inner)       sigs     =  ENot (prep_expr inner sigs)
      prep expr (EOut inner)       sigs     =  EOut (prep_expr inner sigs)
      prep expr (EBin bop l r)     sigs     =  EBin bop (prep_expr l sigs) (prep_expr r sigs)
      prep expr (ECall fname args) sigs     =
        p_args = prep_expr_list args sigs
        prep_call fname p_args (lookup_cg_sig sigs fname)
      prep expr (EEcho args)       sigs     =  EEcho (prep_expr_list args sigs)
      prep expr (EStrInterp parts) sigs     =  EStrInterp (prep_expr_list parts sigs)
      prep expr (EList elems)      sigs     =  EList (prep_expr_list elems sigs)
      prep expr (ETuple elems)     sigs     =  ETuple (prep_expr_list elems sigs)
      prep expr (ETensor elems)    sigs     =  ETensor (prep_expr_list elems sigs)
      prep expr (EEinsum es subs)  sigs     =  EEinsum (prep_expr_list es sigs) subs
      prep expr (EHadamard bop l s1 r s2) sigs = EHadamard bop (prep_expr l sigs) s1 (prep_expr r sigs) s2
      prep expr (EIndex base idxs) sigs     =  EIndex (prep_expr base sigs) (prep_expr_list idxs sigs)
      prep expr (EIndexAssign t idxs v) sigs = EIndexAssign t (prep_expr_list idxs sigs) (prep_expr v sigs)
      prep expr (ESeqSelect b m)   sigs     =  ESeqSelect (prep_expr b sigs) m
      prep expr (EBlock stmts)     sigs     =  EBlock (prep_stmt_list stmts sigs)
      prep expr (EGuard guards)    sigs     =  EGuard (prep_guard_list guards sigs)
      prep expr (EWhere body binds) sigs    =
        sigs1 = bind_where_cg_sigs binds sigs
        EWhere (prep_expr body sigs1) (prep_where_list binds sigs1)
      prep expr (EParPipe branches) sigs    =  EParPipe (prep_expr_list branches sigs)
      prep expr (EWithCtx c v b)   sigs     =  EWithCtx c (prep_expr v sigs) (prep_expr b sigs)
      prep expr (EWithRegion q b)  sigs     =  EWithRegion q (prep_expr b sigs)
      prep expr (EVar v)           sigs     =  prep_var v (lookup_var_cg_sig sigs v)
      prep expr e                  _        =  e

fn :: prep var String (Bool, Int, Bool) => RExpr
      prep var v      (True, 0, False)  =  ECall v []
      prep var v      _                 =  EVar v

fn :: prep call String [RExpr]         (Bool, Int, Bool) => RExpr
      prep call fname  args            (True, arity, True)
        | arity <= 1 = ECall fname [EList args]
        | otherwise = ECall fname ((take_exprs args (arity - 1)) :: [EList (drop_exprs args (arity - 1))])
      prep call fname  (single_arg:[]) (True, 2, False)
        | NOT (str_starts_with fname "__rg_lambda_") =
          ECall "__unpack2__" [EVar fname, single_arg]
      prep call fname  args            _                 =  ECall fname args

fn :: prep expr list [RExpr] [RCgSig] => [RExpr]
      prep expr list []      _        =  []
      prep expr list (e:es)  sigs     =  [prep_expr e sigs] :: (prep_expr_list es sigs)

fn :: prep stmt list [RStmt]            [RCgSig] => [RStmt]
      prep stmt list []                 _        =  []
      prep stmt list ((StmtLet v e):ss) sigs     =
        [StmtLet v (prep_expr e sigs)] :: (prep_stmt_list ss ([CgSig v (0 - 2) False] :: sigs))
      prep stmt list ((StmtMut v e):ss) sigs     =
        [StmtMut v (prep_expr e sigs)] :: (prep_stmt_list ss ([CgSig v (0 - 2) False] :: sigs))
      prep stmt list ((StmtExpr e):ss)  sigs     =  [StmtExpr (prep_expr e sigs)] :: (prep_stmt_list ss sigs)
      prep stmt list ((StmtIndexAssign t idxs e):ss) sigs = [StmtIndexAssign t (prep_expr_list idxs sigs) (prep_expr e sigs)] :: (prep_stmt_list ss sigs)

fn :: prep where list [RWhereBind] [RCgSig] => [RWhereBind]
      prep where list []           _        =  []
      prep where list ((WhereBind e v idxs):wbs) sigs = [WhereBind (prep_expr e sigs) v idxs] :: (prep_where_list wbs sigs)

fn :: prep guard list [RGuard] [RCgSig] => [RGuard]
      prep guard list []       _        =  []
      prep guard list ((GuardBranch c b):gs) sigs = [GuardBranch (prep_expr c sigs) (prep_expr b sigs)] :: (prep_guard_list gs sigs)

fn :: prep case list [RFnCase] [RCgSig] => [RFnCase]
      prep case list []        _        =  []
      prep case list ((FnCase pats guards body):cs) sigs =
        case_sigs = bind_pat_list_cg_sigs pats sigs
        [FnCase pats (prep_guard_list guards case_sigs) (prep_expr body case_sigs)] :: (prep_case_list cs sigs)

fn :: prep fndef list acc [RFnDef] [RCgSig] [RFnDef] => [RFnDef]
      prep fndef list acc []       _        acc      =  acc
      prep fndef list acc ((FnDef name params ret_ty cases):fs) sigs acc =
        prep_fndef_list_acc fs sigs (acc :: [FnDef name params ret_ty (prep_case_list cases sigs)])

fn :: prep fndef list [RFnDef] [RCgSig] => [RFnDef]
      prep fndef list fns      sigs     =  prep_fndef_list_acc fns sigs []

-- ── Pure-Ridgun AST Inlining & Tuple Escape Elimination ──────

type RInlineExprEntry = InlineExprEntry String [String] RExpr

type RInlineTupleEntry = InlineTupleEntry String [String] [RStmt] [RExpr]

fn :: all pat vars [RPattern]      => Bool
      all pat vars []              =  True
      all pat vars ((PatVar _):ps) =  all pat vars ps
      all pat vars _               =  False

fn :: extract pat var names [RPattern]      => [String]
      extract pat var names []              =  []
      extract pat var names ((PatVar v):ps) =  [v] :: (extract pat var names ps)
      extract pat var names (_:ps)          =  extract pat var names ps

fn :: is pure arith binop RBinOp => Bool
      is pure arith binop OpAdd  =  True
      is pure arith binop OpSub  =  True
      is pure arith binop OpMul  =  True
      is pure arith binop OpDiv  =  True
      is pure arith binop OpMod  =  True
      is pure arith binop OpAnd  =  True
      is pure arith binop OpOr   =  True
      is pure arith binop OpXor  =  True
      is pure arith binop OpShl  =  True
      is pure arith binop OpShr  =  True
      is pure arith binop OpRotr =  True
      is pure arith binop OpRotl =  True
      is pure arith binop OpEq   =  True
      is pure arith binop OpNeq  =  True
      is pure arith binop OpLt   =  True
      is pure arith binop OpGt   =  True
      is pure arith binop OpLtEq =  True
      is pure arith binop OpGtEq =  True
      is pure arith binop _      =  False

fn :: is pure arith expr RExpr          => Bool
      is pure arith expr (EVar v)       =  NOT (is_upper_ident v)
      is pure arith expr (EInt _)       =  True
      is pure arith expr (EBool _)      =  True
      is pure arith expr (ENot a)       =  is pure arith expr a
      is pure arith expr (EBin bop a b) =  (is pure arith binop bop) AND (is pure arith expr a) AND (is pure arith expr b)
      is pure arith expr _              =  False

fn :: is compound arith expr RExpr          => Bool
      is compound arith expr (ENot a)       =  is pure arith expr a
      is compound arith expr (EBin bop a b) =  (is pure arith binop bop) AND (is pure arith expr a) AND (is pure arith expr b)
      is compound arith expr _              =  False

fn :: is simple inline arg RExpr    => Bool
      is simple inline arg (EVar _) =  True
      is simple inline arg (EInt _) =  True
      is simple inline arg _        =  False

fn :: all simple inline args [RExpr] => Bool
      all simple inline args []      =  True
      all simple inline args (e:es)  =  (is simple inline arg e) AND (all simple inline args es)

fn :: collect inline expr fns [RFnDef] => [RInlineExprEntry]
      collect inline expr fns []       =  []
      collect inline expr fns ((FnDef name _ _ ((FnCase pats [] body):[])):fs)
        | (NOT (str_starts_with name "__rg_lambda_")) AND pats != [] AND (all pat vars pats) AND (is compound arith expr body) =
          [InlineExprEntry name (extract pat var names pats) body] :: (collect inline expr fns fs)
      collect inline expr fns (_:fs)   =  collect inline expr fns fs

fn :: lookup inline expr [RInlineExprEntry] String Int => Bool [String] RExpr
      lookup inline expr [] _ _ = (False, [], EUnit)
      lookup inline expr ((InlineExprEntry name pnames body):rest) target arity
        | name == target AND (list_str_len pnames) == arity = (True, pnames, body)
        | otherwise = lookup inline expr rest target arity

fn :: subst param var String [String] [RExpr] => RExpr
      subst param var v [] _ = EVar v
      subst param var v _ [] = EVar v
      subst param var v (p:ps) (a:as)
        | v == p    = a
        | otherwise = subst param var v ps as

fn :: subst arith expr RExpr [String] [RExpr] => RExpr
      subst arith expr (EVar v) pnames args = subst param var v pnames args
      subst arith expr (ENot a) pnames args = ENot (subst arith expr a pnames args)
      subst arith expr (EBin bop a b) pnames args = EBin bop (subst arith expr a pnames args) (subst arith expr b pnames args)
      subst arith expr e _ _ = e

fn :: inline leaf call String [RExpr] (Bool, [String], RExpr) => RExpr
      inline leaf call _ args (True, pnames, body) = subst arith expr body pnames args
      inline leaf call fname args _ = ECall fname args

fn :: inline leaf call check String [RExpr] [RInlineExprEntry] => RExpr
      inline leaf call check fname args1 tbl
        | all simple inline args args1 =
          inline leaf call fname args1 (lookup inline expr tbl fname (rexpr_list_len args1))
        | otherwise = ECall fname args1

fn :: inline leaf expr RExpr              [RInlineExprEntry] => RExpr
      inline leaf expr (ENot a)           tbl                =  ENot (inline leaf expr a tbl)
      inline leaf expr (EBin bop a b)     tbl                =  EBin bop (inline leaf expr a tbl) (inline leaf expr b tbl)
      inline leaf expr (EList es)         tbl                =  EList (inline leaf expr list es tbl)
      inline leaf expr (ETuple es)        tbl                =  ETuple (inline leaf expr list es tbl)
      inline leaf expr (ETensor es)       tbl                =  ETensor (inline leaf expr list es tbl)
      inline leaf expr (ECall fname args) tbl                =
        inline leaf call check fname (inline leaf expr list args tbl) tbl
      inline leaf expr (EEcho es)         tbl                =  EEcho (inline leaf expr list es tbl)
      inline leaf expr (EIndex b is)      tbl                =  EIndex (inline leaf expr b tbl) (inline leaf expr list is tbl)
      inline leaf expr (EIndexAssign t is v) tbl             =  EIndexAssign t (inline leaf expr list is tbl) (inline leaf expr v tbl)
      inline leaf expr (EBlock stmts)     tbl                =  EBlock (inline leaf stmt list stmts tbl)
      inline leaf expr (EGuard guards)    tbl                =  EGuard (inline leaf guard list guards tbl)
      inline leaf expr (EWhere b wbs)     tbl                =  EWhere (inline leaf expr b tbl) (inline leaf where list wbs tbl)
      inline leaf expr (EParPipe es)      tbl                =  EParPipe (inline leaf expr list es tbl)
      inline leaf expr (EWithCtx c v b)   tbl                =  EWithCtx c (inline leaf expr v tbl) (inline leaf expr b tbl)
      inline leaf expr (EWithRegion q b)  tbl                =  EWithRegion q (inline leaf expr b tbl)
      inline leaf expr e                  _                  =  e

fn :: inline leaf expr list [RExpr] [RInlineExprEntry] => [RExpr]
      inline leaf expr list [] _ = []
      inline leaf expr list (e:es) tbl = [inline leaf expr e tbl] :: (inline leaf expr list es tbl)

fn :: inline leaf stmt list [RStmt] [RInlineExprEntry] => [RStmt]
      inline leaf stmt list [] _ = []
      inline leaf stmt list ((StmtLet v e):ss) tbl = [StmtLet v (inline leaf expr e tbl)] :: (inline leaf stmt list ss tbl)
      inline leaf stmt list ((StmtMut v e):ss) tbl = [StmtMut v (inline leaf expr e tbl)] :: (inline leaf stmt list ss tbl)
      inline leaf stmt list ((StmtExpr e):ss) tbl = [StmtExpr (inline leaf expr e tbl)] :: (inline leaf stmt list ss tbl)
      inline leaf stmt list ((StmtIndexAssign t is e):ss) tbl = [StmtIndexAssign t (inline leaf expr list is tbl) (inline leaf expr e tbl)] :: (inline leaf stmt list ss tbl)

fn :: inline leaf where list [RWhereBind] [RInlineExprEntry] => [RWhereBind]
      inline leaf where list [] _ = []
      inline leaf where list ((WhereBind e v is):wbs) tbl = [WhereBind (inline leaf expr e tbl) v is] :: (inline leaf where list wbs tbl)

fn :: inline leaf guard list [RGuard] [RInlineExprEntry] => [RGuard]
      inline leaf guard list [] _ = []
      inline leaf guard list ((GuardBranch c b):gs) tbl = [GuardBranch (inline leaf expr c tbl) (inline leaf expr b tbl)] :: (inline leaf guard list gs tbl)

fn :: inline leaf case list [RFnCase] [RInlineExprEntry] => [RFnCase]
      inline leaf case list [] _ = []
      inline leaf case list ((FnCase p gs b):cs) tbl = [FnCase p (inline leaf guard list gs tbl) (inline leaf expr b tbl)] :: (inline leaf case list cs tbl)

fn :: inline leaf fndef list [RFnDef] [RInlineExprEntry] => [RFnDef]
      inline leaf fndef list [] _ = []
      inline leaf fndef list ((FnDef n p r cs):fs) tbl = [FnDef n p r (inline leaf case list cs tbl)] :: (inline leaf fndef list fs tbl)

fn :: is pure inline stmt RStmt         => Bool
      is pure inline stmt (StmtLet v e) =  v != "_" AND (NOT (str_starts_with v ":")) AND (is pure arith expr e)
      is pure inline stmt (StmtMut v e) =  v != "_" AND (NOT (str_starts_with v ":")) AND (is pure arith expr e)
      is pure inline stmt _             =  False

fn :: all pure arith exprs [RExpr] => Bool
      all pure arith exprs []      =  True
      all pure arith exprs (e:es)  =  (is pure arith expr e) AND (all pure arith exprs es)

fn :: split tuple return stmts [RStmt] [RStmt] => Bool [RStmt] [RExpr]
      split tuple return stmts ((StmtExpr (ETuple ret_es)):[]) acc
        | ret_es != [] AND (all pure arith exprs ret_es) = (True, acc, ret_es)
      split tuple return stmts (s:ss) acc
        | is pure inline stmt s = split tuple return stmts ss (acc :: [s])
      split tuple return stmts _ _ = (False, [], [])

fn :: extract tuple return body RExpr           => Bool [RStmt] [RExpr]
      extract tuple return body (ETuple ret_es)
        | ret_es != [] AND (all pure arith exprs ret_es) = (True, [], ret_es)
      extract tuple return body (EBlock stmts)  =  split tuple return stmts stmts []
      extract tuple return body _               =  (False, [], [])

fn :: append inline tuple if match String [String] (Bool, [RStmt], [RExpr]) [RInlineTupleEntry] => [RInlineTupleEntry]
      append inline tuple if match name pnames (True, init_stmts, ret_es) rest =
        [InlineTupleEntry name pnames init_stmts ret_es] :: rest
      append inline tuple if match _ _ _ rest = rest

fn :: collect inline tuple fns [RFnDef] => [RInlineTupleEntry]
      collect inline tuple fns []       =  []
      collect inline tuple fns ((FnDef name _ _ ((FnCase pats [] body):[])):fs)
        | pats != [] AND (all pat vars pats) =
          append inline tuple if match name (extract pat var names pats) (extract tuple return body body) (collect inline tuple fns fs)
      collect inline tuple fns (_:fs)   =  collect inline tuple fns fs

fn :: lookup inline tuple [RInlineTupleEntry] String Int => Bool [String] [RStmt] [RExpr]
      lookup inline tuple [] _ _ = (False, [], [], [])
      lookup inline tuple ((InlineTupleEntry name pnames init_stmts ret_es):rest) target arity
        | name == target AND (list_str_len pnames) == arity = (True, pnames, init_stmts, ret_es)
        | otherwise = lookup inline tuple rest target arity

fn :: match tup unpack stmts [RStmt] String Int Int [RStmt] => Bool [RStmt] [RStmt]
      match tup unpack stmts rest _ idx count acc
        | idx >= count = (True, acc, rest)
      match tup unpack stmts ((StmtMut v (EIndex (EVar tv) ((EInt i):[]))):rest) tmp_name idx count acc
        | tv == tmp_name AND i == idx =
          match tup unpack stmts rest tmp_name (idx + 1) count (acc :: [StmtMut v EUnit])
      match tup unpack stmts ((StmtIndexAssign tk is (EIndex (EVar tv) ((EInt i):[]))):rest) tmp_name idx count acc
        | tv == tmp_name AND i == idx =
          match tup unpack stmts rest tmp_name (idx + 1) count (acc :: [StmtIndexAssign tk is EUnit])
      match tup unpack stmts _ _ _ _ _ = (False, [], [])

fn :: collect inline local vars [RStmt] [String] => [String]
      collect inline local vars [] acc = acc
      collect inline local vars ((StmtLet v _):ss) acc = collect inline local vars ss (add_unique_str v acc)
      collect inline local vars ((StmtMut v _):ss) acc = collect inline local vars ss (add_unique_str v acc)
      collect inline local vars (_:ss) acc = collect inline local vars ss acc

fn :: rename inline expr RExpr [String] String => RExpr
      rename inline expr (EVar v) local_vars prefix
        | str_in_list v local_vars = EVar (prefix + v)
        | otherwise = EVar v
      rename inline expr (ENot a) local_vars prefix =
        ENot (rename inline expr a local_vars prefix)
      rename inline expr (EBin bop a b) local_vars prefix =
        EBin bop (rename inline expr a local_vars prefix) (rename inline expr b local_vars prefix)
      rename inline expr e _ _ = e

fn :: build inline param binds [String] [RExpr] String => [RStmt]
      build inline param binds [] _ _ = []
      build inline param binds _ [] _ = []
      build inline param binds (p:ps) (a:as) prefix =
        [StmtMut (prefix + p) a] :: (build inline param binds ps as prefix)

fn :: rename inline stmts [RStmt] [String] String => [RStmt]
      rename inline stmts [] _ _ = []
      rename inline stmts ((StmtLet v e):ss) local_vars prefix =
        [StmtMut (prefix + v) (rename inline expr e local_vars prefix)] :: (rename inline stmts ss local_vars prefix)
      rename inline stmts ((StmtMut v e):ss) local_vars prefix =
        [StmtMut (prefix + v) (rename inline expr e local_vars prefix)] :: (rename inline stmts ss local_vars prefix)
      rename inline stmts (_:ss) local_vars prefix =
        rename inline stmts ss local_vars prefix

fn :: build inline unpack assigns [RStmt] [RExpr] [String] String => [RStmt]
      build inline unpack assigns [] _ _ _ = []
      build inline unpack assigns _ [] _ _ = []
      build inline unpack assigns ((StmtMut v _):us) (ret_e:rs) local_vars prefix =
        [StmtMut v (rename inline expr ret_e local_vars prefix)] :: (build inline unpack assigns us rs local_vars prefix)
      build inline unpack assigns ((StmtIndexAssign tk is _):us) (ret_e:rs) local_vars prefix =
        [StmtIndexAssign tk is (rename inline expr ret_e local_vars prefix)] :: (build inline unpack assigns us rs local_vars prefix)
      build inline unpack assigns (_:us) (_:rs) local_vars prefix =
        build inline unpack assigns us rs local_vars prefix

fn :: try expand inline tuple String String [RExpr] [RStmt] (Bool, [String], [RStmt], [RExpr]) [RInlineTupleEntry] => [RStmt]
      try expand inline tuple tmp_name fname args rest (True, pnames, init_stmts, ret_es) tbl =
        finish expand inline tuple tmp_name fname args rest pnames init_stmts ret_es (match tup unpack stmts rest tmp_name 0 (rexpr_list_len ret_es) []) tbl
      try expand inline tuple tmp_name fname args rest _ tbl =
        [StmtMut tmp_name (ECall fname args)] :: (inline tuple stmt list rest tbl)

fn :: finish expand inline tuple String String [RExpr] [RStmt] [String] [RStmt] [RExpr] (Bool, [RStmt], [RStmt]) [RInlineTupleEntry] => [RStmt]
      finish expand inline tuple _ fname args _ pnames init_stmts ret_es (True, unpack_stmts, after_unpack) tbl =
        prefix = ":inl-" + fname + ":"
        local_vars = collect inline local vars init_stmts pnames
        bind_stmts = build inline param binds pnames args prefix
        body_stmts = rename inline stmts init_stmts local_vars prefix
        assign_stmts = build inline unpack assigns unpack_stmts ret_es local_vars prefix
        bind_stmts :: body_stmts :: assign_stmts :: (inline tuple stmt list after_unpack tbl)
      finish expand inline tuple tmp_name fname args rest _ _ _ _ tbl =
        [StmtMut tmp_name (ECall fname args)] :: (inline tuple stmt list rest tbl)

fn :: inline tuple expr RExpr             [RInlineTupleEntry] => RExpr
      inline tuple expr (EBlock stmts)    tbl                 =  EBlock (inline tuple stmt list stmts tbl)
      inline tuple expr (EGuard guards)   tbl                 =  EGuard (inline tuple guard list guards tbl)
      inline tuple expr (EWhere b wbs)    tbl                 =  EWhere (inline tuple expr b tbl) wbs
      inline tuple expr (EWithCtx c v b)  tbl                 =  EWithCtx c (inline tuple expr v tbl) (inline tuple expr b tbl)
      inline tuple expr (EWithRegion q b) tbl                 =  EWithRegion q (inline tuple expr b tbl)
      inline tuple expr e                 _                   =  e

fn :: inline tuple stmt list [RStmt] [RInlineTupleEntry] => [RStmt]
      inline tuple stmt list [] _ = []
      inline tuple stmt list ((StmtMut tmp_name (ECall fname args)):rest) tbl
        | (str_starts_with tmp_name ":tup-") OR (str_starts_with tmp_name ":idx-tup-") =
          try expand inline tuple tmp_name fname args rest (lookup inline tuple tbl fname (rexpr_list_len args)) tbl
      inline tuple stmt list ((StmtLet v e):ss) tbl =
        [StmtLet v (inline tuple expr e tbl)] :: (inline tuple stmt list ss tbl)
      inline tuple stmt list ((StmtMut v e):ss) tbl =
        [StmtMut v (inline tuple expr e tbl)] :: (inline tuple stmt list ss tbl)
      inline tuple stmt list ((StmtExpr e):ss) tbl =
        [StmtExpr (inline tuple expr e tbl)] :: (inline tuple stmt list ss tbl)
      inline tuple stmt list (s:ss) tbl =
        [s] :: (inline tuple stmt list ss tbl)

fn :: inline tuple guard list [RGuard] [RInlineTupleEntry] => [RGuard]
      inline tuple guard list [] _ = []
      inline tuple guard list ((GuardBranch c b):gs) tbl =
        [GuardBranch c (inline tuple expr b tbl)] :: (inline tuple guard list gs tbl)

fn :: inline tuple case list [RFnCase] [RInlineTupleEntry] => [RFnCase]
      inline tuple case list [] _ = []
      inline tuple case list ((FnCase p gs b):cs) tbl =
        [FnCase p (inline tuple guard list gs tbl) (inline tuple expr b tbl)] :: (inline tuple case list cs tbl)

fn :: inline tuple fndef list [RFnDef] [RInlineTupleEntry] => [RFnDef]
      inline tuple fndef list [] _ = []
      inline tuple fndef list ((FnDef n p r cs):fs) tbl =
        [FnDef n p r (inline tuple case list cs tbl)] :: (inline tuple fndef list fs tbl)

fn :: opt fndef list [RFnDef] => [RFnDef]
      opt fndef list fns      =
        expr_tbl = collect inline expr fns fns
        fns1 = inline leaf fndef list fns expr_tbl
        tup_tbl = collect inline tuple fns fns1
        inline tuple fndef list fns1 tup_tbl

-- ── Pure-Ridgun Native IR Lowering (RProgram => RNativeProg) ──
-- @implements FR-COMP-002
-- @implements FR-COMP-004

type RStrEntry = StrEntry String Int Int

type RStrPool = StrPool String [RStrEntry]

type RFnEntry = FnEntry String Int Int

type RFieldEntry = FieldEntry String Int

type RNativeEnv = NativeEnv String Int [String] [RStrEntry] [RFnEntry] [RFieldEntry]

type RNativeCode = NativeCode [RNativeInstr] Int Int

fn :: nc instrs RNativeCode => [RNativeInstr]
      nc instrs (NativeCode instrs _ _) = instrs

fn :: nc lbl RNativeCode => Int
      nc lbl (NativeCode _ lbl _) = lbl

fn :: nc max sp RNativeCode => Int
      nc max sp (NativeCode _ _ msp) = msp

fn :: nc set lbl RNativeCode Int     => RNativeCode
      nc set lbl (NativeCode instrs _ msp) new_lbl = NativeCode instrs new_lbl msp

fn :: nc emit RNativeCode RNativeInstr Int     => RNativeCode
      nc emit (NativeCode instrs lbl msp) ins used_sp =
        NativeCode (instrs :: [ins]) lbl (max_int msp used_sp)

fn :: nc emit list RNativeCode [RNativeInstr] Int => RNativeCode
      nc emit list (NativeCode instrs lbl msp) more used_sp =
        NativeCode (instrs :: more) lbl (max_int msp used_sp)

-- ── String Pool (.rodata) Collection & Interning ─────────────

fn :: join comma [String] => String
      join comma []       =  ""
      join comma (s:[])   =  s
      join comma (s:ss)   =  s + "," + (join_comma ss)

fn :: add ctor str String [String] => [String]
      add ctor str s acc
        | is_upper_ident s = add_unique_str (ident_base_name s) (add_unique_str s acc)
        | otherwise = add_unique_str s acc

fn :: collect pat strs RPattern         [String] => [String]
      collect pat strs (PatReal r)      acc      =  add_unique_str r acc
      collect pat strs (PatStr s)       acc      =  add_unique_str s acc
      collect pat strs (PatCons h t)    acc      =  collect_pat_strs t (collect_pat_strs h acc)
      collect pat strs (PatTuple ps)    acc      =  collect_pat_list_strs ps acc
      collect pat strs (PatCtor c args) acc      =  collect_pat_list_strs args (add_ctor_str c acc)
      collect pat strs _                acc      =  acc

fn :: collect pat list strs [RPattern] [String] => [String]
      collect pat list strs [] acc = acc
      collect pat list strs (p:ps) acc = collect_pat_list_strs ps (collect_pat_strs p acc)

fn :: collect expr strs RExpr              [String] => [String]
      collect expr strs (EReal r)          acc      =  add_unique_str r acc
      collect expr strs (EStr s)           acc      =  add_unique_str s acc
      collect expr strs (EVar v)           acc      =  add_ctor_str v acc
      collect expr strs (ENot inner)       acc      =  collect_expr_strs inner acc
      collect expr strs (EOut inner)       acc      =  collect_expr_strs inner acc
      collect expr strs (EBin _ l r)       acc      =  collect_expr_strs r (collect_expr_strs l acc)
      collect expr strs (ECall fname args) acc      =  collect_expr_list_strs args (add_ctor_str fname acc)
      collect expr strs (EEcho args)       acc      =  collect_expr_list_strs args acc
      collect expr strs (EStrInterp parts) acc      =  collect_expr_list_strs parts acc
      collect expr strs (EList elems)      acc      =  collect_expr_list_strs elems acc
      collect expr strs (ETuple elems)     acc      =  collect_expr_list_strs elems acc
      collect expr strs (ETensor elems)    acc      =  collect_expr_list_strs elems acc
      collect expr strs (EEinsum es subs)  acc      =  collect_expr_list_strs es (add_unique_str (join_comma subs) acc)
      collect expr strs (EHadamard _ l s1 r s2) acc =  collect_expr_strs r (collect_expr_strs l (add_unique_str (s1 + "," + s2) acc))
      collect expr strs (EIndex base idxs) acc      =  collect_expr_list_strs idxs (collect_expr_strs base acc)
      collect expr strs (EIndexAssign _ idxs v) acc =  collect_expr_strs v (collect_expr_list_strs idxs acc)
      collect expr strs (ESeqSelect b m)   acc      =  collect_expr_strs b (add_unique_str m acc)
      collect expr strs (EBlock stmts)     acc      =  collect_stmt_list_strs stmts acc
      collect expr strs (EGuard guards)    acc      =  collect_guard_list_strs guards acc
      collect expr strs (EWhere body binds) acc     =  collect_where_list_strs binds (collect_expr_strs body acc)
      collect expr strs (EParPipe branches) acc     =  collect_expr_list_strs branches acc
      collect expr strs (EWithCtx c v b)   acc      =  collect_expr_strs b (collect_expr_strs v (add_unique_str c acc))
      collect expr strs (EWithRegion _ b)  acc      =  collect_expr_strs b acc
      collect expr strs _                  acc      =  acc

fn :: collect expr list strs [RExpr] [String] => [String]
      collect expr list strs [] acc = acc
      collect expr list strs (e:es) acc = collect_expr_list_strs es (collect_expr_strs e acc)

fn :: collect stmt list strs [RStmt] [String] => [String]
      collect stmt list strs [] acc = acc
      collect stmt list strs ((StmtLet _ e):ss) acc = collect_stmt_list_strs ss (collect_expr_strs e acc)
      collect stmt list strs ((StmtMut _ e):ss) acc = collect_stmt_list_strs ss (collect_expr_strs e acc)
      collect stmt list strs ((StmtExpr e):ss) acc = collect_stmt_list_strs ss (collect_expr_strs e acc)
      collect stmt list strs ((StmtIndexAssign _ idxs e):ss) acc =
        collect_stmt_list_strs ss (collect_expr_strs e (collect_expr_list_strs idxs acc))

fn :: collect where list strs [RWhereBind] [String] => [String]
      collect where list strs [] acc = acc
      collect where list strs ((WhereBind e _ _):wbs) acc =
        collect_where_list_strs wbs (collect_expr_strs e acc)

fn :: collect guard list strs [RGuard] [String] => [String]
      collect guard list strs [] acc = acc
      collect guard list strs ((GuardBranch c b):gs) acc =
        collect_guard_list_strs gs (collect_expr_strs b (collect_expr_strs c acc))

fn :: collect case list strs [RFnCase] [String] => [String]
      collect case list strs [] acc = acc
      collect case list strs ((FnCase pats guards body):cs) acc =
        a1 = collect_pat_list_strs pats acc
        a2 = collect_guard_list_strs guards a1
        collect_case_list_strs cs (collect_expr_strs body a2)

fn :: collect fndef list strs [RFnDef] [String] => [String]
      collect fndef list strs [] acc = acc
      collect fndef list strs ((FnDef name _ _ cases):fs) acc =
        collect_fndef_list_strs fs (collect_case_list_strs cases (add_unique_str name acc))

fn :: build str pool loop [String] Int String [RStrEntry] => RStrPool
      build str pool loop [] _ rodata entries = StrPool rodata entries
      build str pool loop (s:ss) cur_off rodata entries =
        slen = str_len s
        build_str_pool_loop ss (cur_off + slen) (rodata + s) (entries :: [StrEntry s cur_off slen])

fn :: build str pool [RFnDef] [String]   => RStrPool
      build str pool fns      extra_strs =
        base_strs = ["", "+", "-", "*", "/", "%", "Linux", "MacOS", "Windows", "X86_64", "Arm64", "Ok", "Some", "None", "__rg_par_eval__", "ki,k", "i,j", "i,i", "ij,ij"] :: extra_strs
        all_strs = collect_fndef_list_strs fns base_strs
        build_str_pool_loop all_strs 0 "" []

fn :: pool rodata RStrPool      => String
      pool rodata (StrPool s _) =  s

fn :: pool entries RStrPool        => [RStrEntry]
      pool entries (StrPool _ tbl) =  tbl

fn :: lookup str off [RStrEntry] String => Int
      lookup str off []          _      =  0
      lookup str off ((StrEntry k off _):rest) target
        | k == target = off
        | otherwise = lookup_str_off rest target

-- ── Function & Record Field Tables ───────────────────────────

fn :: has field entry [RFieldEntry] String => Bool
      has field entry []            _      =  False
      has field entry ((FieldEntry k _):rest) target
        | k == target = True
        | otherwise = has_field_entry rest target

fn :: add base field entry String Int [RFieldEntry] => [RFieldEntry]
      add base field entry fname idx acc
        | (str_contains fname ".") AND (NOT (has_field_entry acc (ident_base_name fname))) =
          acc :: [FieldEntry (ident_base_name fname) idx]
        | otherwise = acc

fn :: collect fields from list [RField] Int [RFieldEntry] => [RFieldEntry]
      collect fields from list [] _ acc = acc
      collect fields from list ((TypeField fname _):fs) idx acc
        | has_field_entry acc fname = collect_fields_from_list fs (idx + 1) (add_base_field_entry fname idx acc)
        | otherwise = collect_fields_from_list fs (idx + 1) (add_base_field_entry fname idx (acc :: [FieldEntry fname idx]))

fn :: collect typedef fields [RTypeDef] [RFieldEntry] => [RFieldEntry]
      collect typedef fields []         acc           =  acc
      collect typedef fields ((TypeDef _ _ fields):ts) acc =
        collect_typedef_fields ts (collect_fields_from_list fields 0 acc)

fn :: lookup field idx [RFieldEntry] String => Int
      lookup field idx []            _      =  0
      lookup field idx ((FieldEntry k idx):rest) target
        | k == target = idx
        | otherwise = lookup_field_idx rest target

fn :: collect field names [RFieldEntry] => [String]
      collect field names []            =  []
      collect field names ((FieldEntry k _):rest) = [k] :: (collect_field_names rest)

fn :: build field cg sigs [RFieldEntry] [String] => [RCgSig]
      build field cg sigs [] _ = []
      build field cg sigs ((FieldEntry fname _):rest) fn_names
        | str_in_list fname fn_names = build_field_cg_sigs rest fn_names
        | otherwise = [CgSig fname 1 False] :: (build_field_cg_sigs rest fn_names)

fn :: build fn table fndefs [RFnDef] Int [RFnEntry] => [RFnEntry]
      build fn table fndefs [] _ acc = acc
      build fn table fndefs ((FnDef name params _ cases):fs) next_fid acc =
        arity = infer_fndef_arity params cases
        build_fn_table_fndefs fs (next_fid + 1) (acc :: [FnEntry name next_fid arity])

fn :: build fn table fields [RFieldEntry] [String] Int [RFnEntry] => [RFnEntry]
      build fn table fields [] _ _ acc = acc
      build fn table fields ((FieldEntry fname _):rest) fn_names next_fid acc
        | str_in_list fname fn_names = build_fn_table_fields rest fn_names next_fid acc
        | otherwise = build_fn_table_fields rest fn_names (next_fid + 1) (acc :: [FnEntry fname next_fid 1])

fn :: lookup fn id [RFnEntry] String => Int
      lookup fn id []         _      =  0
      lookup fn id ((FnEntry k fid _):rest) target
        | k == target = fid
        | otherwise = lookup_fn_id rest target

fn :: lookup fn arity [RFnEntry] String => Int
      lookup fn arity []         _      =  -1
      lookup fn arity ((FnEntry k _ arity):rest) target
        | k == target = arity
        | otherwise = lookup_fn_arity rest target

fn :: expr has heavy ops RExpr             => Bool
      expr has heavy ops (ETensor _)       =  True
      expr has heavy ops (EEinsum _ _)     =  True
      expr has heavy ops (EHadamard _ _ _ _ _) = True
      expr has heavy ops (EBin OpMatMul _ _) = True
      expr has heavy ops (EBin _ l r)      =  (expr_has_heavy_ops l) OR (expr_has_heavy_ops r)
      expr has heavy ops (ENot inner)      =  expr_has_heavy_ops inner
      expr has heavy ops (EOut inner)      =  expr_has_heavy_ops inner
      expr has heavy ops (ECall "sys_sleep_ms" _) = True
      expr has heavy ops (ECall _ args)    =  expr_list_has_heavy_ops args
      expr has heavy ops (EList elems)     =  expr_list_has_heavy_ops elems
      expr has heavy ops (ETuple elems)    =  expr_list_has_heavy_ops elems
      expr has heavy ops (EBlock stmts)    =  stmt_list_has_heavy_ops stmts
      expr has heavy ops (EGuard guards)   =  guard_list_has_heavy_ops guards
      expr has heavy ops (EWhere body binds) = (expr_has_heavy_ops body) OR (where_list_has_heavy_ops binds)
      expr has heavy ops (EParPipe branches) = expr_list_has_heavy_ops branches
      expr has heavy ops (EWithCtx _ v b)  =  (expr_has_heavy_ops v) OR (expr_has_heavy_ops b)
      expr has heavy ops (EWithRegion _ b) =  expr_has_heavy_ops b
      expr has heavy ops _                 =  False

fn :: expr list has heavy ops [RExpr] => Bool
      expr list has heavy ops [] = False
      expr list has heavy ops (e:es)
        | expr_has_heavy_ops e = True
        | otherwise = expr_list_has_heavy_ops es

fn :: stmt list has heavy ops [RStmt] => Bool
      stmt list has heavy ops [] = False
      stmt list has heavy ops ((StmtLet _ e):ss)
        | expr_has_heavy_ops e = True
        | otherwise = stmt_list_has_heavy_ops ss
      stmt list has heavy ops ((StmtMut _ e):ss)
        | expr_has_heavy_ops e = True
        | otherwise = stmt_list_has_heavy_ops ss
      stmt list has heavy ops ((StmtExpr e):ss)
        | expr_has_heavy_ops e = True
        | otherwise = stmt_list_has_heavy_ops ss
      stmt list has heavy ops (_:ss) = stmt_list_has_heavy_ops ss

fn :: where list has heavy ops [RWhereBind] => Bool
      where list has heavy ops [] = False
      where list has heavy ops ((WhereBind e _ _):wbs)
        | expr_has_heavy_ops e = True
        | otherwise = where_list_has_heavy_ops wbs

fn :: guard list has heavy ops [RGuard] => Bool
      guard list has heavy ops [] = False
      guard list has heavy ops ((GuardBranch c b):gs)
        | (expr_has_heavy_ops c) OR (expr_has_heavy_ops b) = True
        | otherwise = guard_list_has_heavy_ops gs

fn :: cases have heavy ops [RFnCase] => Bool
      cases have heavy ops []        =  False
      cases have heavy ops ((FnCase _ gs b):cs)
        | (guard_list_has_heavy_ops gs) OR (expr_has_heavy_ops b) = True
        | otherwise = cases_have_heavy_ops cs

fn :: any str in list [String] [String] => Bool
      any str in list [] _ = False
      any str in list (x:xs) targets
        | str_in_list x targets = True
        | otherwise = any_str_in_list xs targets

fn :: collect direct heavy fns [RFnDef] => [String]
      collect direct heavy fns []       =  []
      collect direct heavy fns ((FnDef name _ _ cases):fs)
        | (count_case_calls name cases) > 0 OR (cases_have_heavy_ops cases) =
          [name] :: (collect_direct_heavy_fns fs)
        | otherwise = collect_direct_heavy_fns fs

fn :: collect caller heavy fns [RFnDef] [String] => [String]
      collect caller heavy fns [] heavy = heavy
      collect caller heavy fns ((FnDef name _ _ cases):fs) heavy
        | str_in_list name heavy = collect_caller_heavy_fns fs heavy
        | any_str_in_list (collect_refs_cases cases []) heavy =
      collect caller heavy fns fs (heavy :: [name])
        | otherwise = collect_caller_heavy_fns fs heavy

fn :: build heavy fn entries [String] [RFnEntry] => [RFnEntry]
      build heavy fn entries [] acc = acc
      build heavy fn entries (h:hs) acc =
        build_heavy_fn_entries hs (acc :: [FnEntry ("__heavy__" + h) 1 (0 - 1)])

fn :: attach heavy fn entries [RFnDef] [String] [RFnEntry] => [RFnEntry]
      attach heavy fn entries fns fn_names fn_tbl
        | (list_str_len fn_names) <= 200 =
          direct_heavy = collect_direct_heavy_fns fns
          all_heavy = collect_caller_heavy_fns fns direct_heavy
          build_heavy_fn_entries all_heavy fn_tbl
        | otherwise =
          direct_heavy = collect_direct_heavy_fns fns
          build_heavy_fn_entries direct_heavy fn_tbl

-- ── Local Variable Collection & RMM2 Liveness Helpers ────────

fn :: collect pat vars RPattern         [String] => [String]
      collect pat vars (PatVar v)       acc      =  add_unique_str v acc
      collect pat vars (PatSeqBind v)   acc      =  add_unique_str v acc
      collect pat vars (PatCons h t)    acc      =  collect_pat_vars t (collect_pat_vars h acc)
      collect pat vars (PatTuple ps)    acc      =  collect_pat_list_vars ps acc
      collect pat vars (PatCtor _ args) acc      =  collect_pat_list_vars args acc
      collect pat vars _                acc      =  acc

fn :: collect pat list vars [RPattern] [String] => [String]
      collect pat list vars [] acc = acc
      collect pat list vars (p:ps) acc = collect_pat_list_vars ps (collect_pat_vars p acc)

fn :: add bound var String [String] => [String]
      add bound var "_"    acc      =  acc
      add bound var v      acc      =  add_unique_str v acc

fn :: collect expr bound vars RExpr [String] => [String]
      collect expr bound vars (ENot inner) acc = collect_expr_bound_vars inner acc
      collect expr bound vars (EOut inner) acc = collect_expr_bound_vars inner acc
      collect expr bound vars (EBin _ l r) acc = collect_expr_bound_vars r (collect_expr_bound_vars l acc)
      collect expr bound vars (ECall _ args) acc = collect_expr_list_bound_vars args acc
      collect expr bound vars (EEcho args) acc = collect_expr_list_bound_vars args acc
      collect expr bound vars (EStrInterp parts) acc = collect_expr_list_bound_vars parts acc
      collect expr bound vars (EList elems) acc = collect_expr_list_bound_vars elems acc
      collect expr bound vars (ETuple elems) acc = collect_expr_list_bound_vars elems acc
      collect expr bound vars (ETensor elems) acc = collect_expr_list_bound_vars elems acc
      collect expr bound vars (EEinsum es _) acc = collect_expr_list_bound_vars es acc
      collect expr bound vars (EHadamard _ l _ r _) acc = collect_expr_bound_vars r (collect_expr_bound_vars l acc)
      collect expr bound vars (EIndex base idxs) acc = collect_expr_list_bound_vars idxs (collect_expr_bound_vars base acc)
      collect expr bound vars (EIndexAssign t idxs v) acc = collect_expr_bound_vars v (collect_expr_list_bound_vars idxs (add_bound_var t acc))
      collect expr bound vars (ESeqSelect b _) acc = collect_expr_bound_vars b acc
      collect expr bound vars (EBlock stmts) acc = collect_stmt_list_bound_vars stmts acc
      collect expr bound vars (EGuard guards) acc = collect_guard_list_bound_vars guards acc
      collect expr bound vars (EWhere body binds) acc = collect_where_list_bound_vars binds (collect_expr_bound_vars body acc)
      collect expr bound vars (EParPipe branches) acc = collect_expr_list_bound_vars branches acc
      collect expr bound vars (EWithCtx _ v b) acc = collect_expr_bound_vars b (collect_expr_bound_vars v acc)
      collect expr bound vars (EWithRegion _ b) acc = collect_expr_bound_vars b acc
      collect expr bound vars _ acc = acc

fn :: collect expr list bound vars [RExpr] [String] => [String]
      collect expr list bound vars [] acc = acc
      collect expr list bound vars (e:es) acc = collect_expr_list_bound_vars es (collect_expr_bound_vars e acc)

fn :: collect stmt list bound vars [RStmt] [String] => [String]
      collect stmt list bound vars [] acc = acc
      collect stmt list bound vars ((StmtLet v e):ss) acc =
        collect_stmt_list_bound_vars ss (add_bound_var v (collect_expr_bound_vars e acc))
      collect stmt list bound vars ((StmtMut v e):ss) acc =
        collect_stmt_list_bound_vars ss (add_bound_var v (collect_expr_bound_vars e acc))
      collect stmt list bound vars ((StmtExpr e):ss) acc =
        collect_stmt_list_bound_vars ss (collect_expr_bound_vars e acc)
      collect stmt list bound vars ((StmtIndexAssign t idxs e):ss) acc =
        collect_stmt_list_bound_vars ss (collect_expr_bound_vars e (collect_expr_list_bound_vars idxs (add_bound_var t acc)))

fn :: collect where list bound vars [RWhereBind] [String] => [String]
      collect where list bound vars [] acc = acc
      collect where list bound vars ((WhereBind e v _):wbs) acc =
        collect_where_list_bound_vars wbs (add_bound_var v (collect_expr_bound_vars e acc))

fn :: collect guard list bound vars [RGuard] [String] => [String]
      collect guard list bound vars [] acc = acc
      collect guard list bound vars ((GuardBranch c b):gs) acc =
        collect_guard_list_bound_vars gs (collect_expr_bound_vars b (collect_expr_bound_vars c acc))

fn :: collect cases all locals [RFnCase] [String] => [String]
      collect cases all locals [] acc = acc
      collect cases all locals ((FnCase pats guards body):cs) acc =
        a1 = collect_pat_list_vars pats acc
        a2 = collect_guard_list_bound_vars guards a1
        collect_cases_all_locals cs (collect_expr_bound_vars body a2)

fn :: cmm expr vars RExpr              [String] => [String]
      cmm expr vars (EVar name)        acc      =  add_unique_str name acc
      cmm expr vars (ENot inner)       acc      =  cmm_expr_vars inner acc
      cmm expr vars (EOut inner)       acc      =  cmm_expr_vars inner acc
      cmm expr vars (EBin _ l r)       acc      =  cmm_expr_vars r (cmm_expr_vars l acc)
      cmm expr vars (ECall "__record_update__" (base_e:rest_args)) acc =
        cmm_expr_list_vars rest_args (cmm_expr_vars base_e acc)
      cmm expr vars (ECall "__unpack2__" (_:single_arg:[])) acc =
        cmm_expr_vars single_arg acc
      cmm expr vars (ECall fname args) acc      =  cmm_expr_list_vars args (add_unique_str fname acc)
      cmm expr vars (EEcho args)       acc      =  cmm_expr_list_vars args acc
      cmm expr vars (EStrInterp parts) acc      =  cmm_expr_list_vars parts acc
      cmm expr vars (EList elems)      acc      =  cmm_expr_list_vars elems acc
      cmm expr vars (ETuple elems)     acc      =  cmm_expr_list_vars elems acc
      cmm expr vars (ETensor elems)    acc      =  cmm_expr_list_vars elems acc
      cmm expr vars (EEinsum es _)     acc      =  cmm_expr_list_vars es acc
      cmm expr vars (EHadamard _ l _ r _) acc   =  cmm_expr_vars r (cmm_expr_vars l acc)
      cmm expr vars (EIndex base idxs) acc      =  cmm_expr_list_vars idxs (cmm_expr_vars base acc)
      cmm expr vars (EIndexAssign t idxs v) acc =  cmm_expr_vars v (cmm_expr_list_vars idxs (add_unique_str t acc))
      cmm expr vars (ESeqSelect b _)   acc      =  cmm_expr_vars b acc
      cmm expr vars (EBlock stmts)     acc      =  cmm_stmts_vars stmts acc
      cmm expr vars (EGuard guards)    acc      =  cmm_guards_vars guards acc
      cmm expr vars (EWhere body binds) acc     =  cmm_where_vars binds body acc
      cmm expr vars (EParPipe branches) acc     =  cmm_expr_list_vars branches acc
      cmm expr vars (EWithCtx _ v b)   acc      =  cmm_expr_vars b (cmm_expr_vars v acc)
      cmm expr vars (EWithRegion _ b)  acc      =  cmm_expr_vars b acc
      cmm expr vars _                  acc      =  acc

fn :: cmm guards vars [RGuard] [String] => [String]
      cmm guards vars []       acc      =  acc
      cmm guards vars ((GuardBranch c b):gs) acc =
        cmm_guards_vars gs (cmm_expr_vars b (cmm_expr_vars c acc))

fn :: cmm expr list vars [RExpr] [String] => [String]
      cmm expr list vars [] acc = acc
      cmm expr list vars (e:es) acc = cmm_expr_list_vars es (cmm_expr_vars e acc)

fn :: cmm stmts vars [RStmt]            [String] => [String]
      cmm stmts vars []                 acc      =  acc
      cmm stmts vars ((StmtLet _ e):ss) acc      =  cmm_stmts_vars ss (cmm_expr_vars e acc)
      cmm stmts vars ((StmtMut _ e):ss) acc      =  cmm_stmts_vars ss (cmm_expr_vars e acc)
      cmm stmts vars ((StmtExpr e):ss)  acc      =  cmm_stmts_vars ss (cmm_expr_vars e acc)
      cmm stmts vars ((StmtIndexAssign t idxs e):ss) acc =
        cmm_stmts_vars ss (cmm_expr_vars e (cmm_expr_list_vars idxs (add_unique_str t acc)))

fn :: cmm where vars [RWhereBind] RExpr [String] => [String]
      cmm where vars [] body acc = cmm_expr_vars body acc
      cmm where vars ((WhereBind e _ []):wbs) body acc =
        cmm_where_vars wbs body (cmm_expr_vars e acc)
      cmm where vars ((WhereBind e v _):wbs) body acc =
        cmm_where_vars wbs body (cmm_expr_vars e (add_unique_str v acc))

fn :: cmm filter in list [String] [String] => [String]
      cmm filter in list [] _ = []
      cmm filter in list (x:xs) allowed
        | x != "_" AND (str_in_list x allowed) = [x] :: (cmm_filter_in_list xs allowed)
        | otherwise = cmm_filter_in_list xs allowed

fn :: cmm filter not in list [String] [String] => [String]
      cmm filter not in list [] _ = []
      cmm filter not in list (x:xs) excluded
        | x != "_" AND (NOT (str_in_list x excluded)) = [x] :: (cmm_filter_not_in_list xs excluded)
        | otherwise = cmm_filter_not_in_list xs excluded

fn :: cmm remove str String [String] => [String]
      cmm remove str _      []       =  []
      cmm remove str target (x:xs)
        | x == target = cmm_remove_str target xs
        | otherwise = [x] :: (cmm_remove_str target xs)

-- ── Environment Accessors & Builtin ID Mapping ───────────────

fn :: env fn name RNativeEnv => String
      env fn name (NativeEnv fn_name _ _ _ _ _) = fn_name

fn :: env arity RNativeEnv => Int
      env arity (NativeEnv _ arity _ _ _ _) = arity

fn :: env str off RNativeEnv String => Int
      env str off (NativeEnv _ _ _ str_tbl _ _) s = lookup_str_off str_tbl s

fn :: env fn id RNativeEnv String => Int
      env fn id (NativeEnv _ _ _ _ fn_tbl _) fname = lookup_fn_id fn_tbl fname

fn :: env fn arity RNativeEnv String => Int
      env fn arity (NativeEnv _ _ _ _ fn_tbl _) fname = lookup_fn_arity fn_tbl fname

fn :: env fn is heavy RNativeEnv String => Bool
      env fn is heavy (NativeEnv _ _ _ _ fn_tbl _) fname =
        (lookup_fn_id fn_tbl ("__heavy__" + fname)) > 0

fn :: env field idx RNativeEnv String => Int
      env field idx (NativeEnv _ _ _ _ _ field_tbl) fname = lookup_field_idx field_tbl fname

fn :: env has field RNativeEnv String => Bool
      env has field (NativeEnv _ _ _ _ _ field_tbl) fname = has_field_entry field_tbl fname

fn :: env var slot RNativeEnv String => Int
      env var slot (NativeEnv _ arity all_locals _ _ _) name =
        idx = lookup_local all_locals name
        env_var_slot_idx arity idx

fn :: env var slot idx Int Int => Int
      env var slot idx arity idx
        | idx >= 0 = arity + idx
        | otherwise = 0

fn :: binop id RBinOp     => Int
      binop id OpAdd      =  0
      binop id OpSub      =  1
      binop id OpMul      =  2
      binop id OpDiv      =  3
      binop id OpMod      =  4
      binop id OpEq       =  5
      binop id OpNeq      =  6
      binop id OpGt       =  7
      binop id OpLt       =  8
      binop id OpGtEq     =  9
      binop id OpLtEq     =  10
      binop id OpAnd      =  11
      binop id OpOr       =  12
      binop id OpXor      =  13
      binop id OpConcat   =  14
      binop id OpFlatJoin =  15
      binop id OpMatMul   =  16
      binop id OpShl      =  17
      binop id OpShr      =  18
      binop id OpRotr     =  19
      binop id OpRotl     =  20

fn :: binop op tag RBinOp => String
      binop op tag OpAdd  =  "+"
      binop op tag OpSub  =  "-"
      binop op tag OpMul  =  "*"
      binop op tag OpDiv  =  "/"
      binop op tag OpMod  =  "%"
      binop op tag OpAnd  =  "and"
      binop op tag OpOr   =  "or"
      binop op tag OpXor  =  "xor"
      binop op tag OpShl  =  "shl"
      binop op tag OpShr  =  "shr"
      binop op tag OpRotr =  "rotr"
      binop op tag OpRotl =  "rotl"
      binop op tag _      =  "+"

fn :: builtin zero arg id String             => Int
      builtin zero arg id "cli_args"         =  0
      builtin zero arg id "new_mailbox"      =  1
      builtin zero arg id "mailbox"          =  1
      builtin zero arg id "new_channel"      =  1
      builtin zero arg id "channel"          =  1
      builtin zero arg id "sys_getcwd"       =  2
      builtin zero arg id "sys_getuid"       =  3
      builtin zero arg id "sys_getgid"       =  4
      builtin zero arg id "sys_getpid"       =  70
      builtin zero arg id "sys_time_ms"      =  71
      builtin zero arg id "sys_deadline_ms"  =  72
      builtin zero arg id "sys_remaining_ms" =  73
      builtin zero arg id "sys_pipe"         =  86
      builtin zero arg id "cmm_live_blocks"  =  5
      builtin zero arg id "cmm_cond_spared"  =  6
      builtin zero arg id "cmm_cond_freed"   =  7
      builtin zero arg id _                  =  -1

fn :: builtin call id String             => Int
      builtin call id "cli_args"         =  0
      builtin call id "new_mailbox"      =  1
      builtin call id "mailbox"          =  1
      builtin call id "new_channel"      =  1
      builtin call id "channel"          =  1
      builtin call id "sys_getcwd"       =  2
      builtin call id "sys_getuid"       =  3
      builtin call id "sys_getgid"       =  4
      builtin call id "cmm_live_blocks"  =  5
      builtin call id "cmm_cond_spared"  =  6
      builtin call id "cmm_cond_freed"   =  7
      builtin call id "str_len"          =  10
      builtin call id "char_from_code"   =  11
      builtin call id "int_to_str"       =  12
      builtin call id "str_to_int"       =  13
      builtin call id "read_file"        =  14
      builtin call id "load_rg_source"   =  15
      builtin call id "read_bytes"       =  16
      builtin call id "shell_exec"       =  17
      builtin call id "list_dir"         =  18
      builtin call id "file_lstat"       =  19
      builtin call id "sha256_file"      =  20
      builtin call id "sha256_str"       =  21
      builtin call id "sha256_raw"       =  36
      builtin call id "sha256_bytes"     =  36
      builtin call id "sys_chdir"        =  22
      builtin call id "sys_getenv"       =  23
      builtin call id "sys_exit"         =  24
      builtin call id "sys_username"     =  25
      builtin call id "sys_lookup_uid_gid" = 26
      builtin call id "sys_user_groups"  =  27
      builtin call id "sys_setresgid"    =  28
      builtin call id "sys_setgroups"    =  29
      builtin call id "sys_setresuid"    =  30
      builtin call id "sys_read_pass"    =  31
      builtin call id "receive_from"     =  32
      builtin call id "chan_recv"        =  32
      builtin call id "try_receive_from" =  33
      builtin call id "chan_try_recv"    =  33
      builtin call id "new_bounded_channel" = 35
      builtin call id "str_char_at"      =  40
      builtin call id "str_concat"       =  41
      builtin call id "str_starts_with"  =  42
      builtin call id "str_contains"     =  43
      builtin call id "write_bytes"      =  44
      builtin call id "write_file"       =  45
      builtin call id "sys_mkdir"        =  46
      builtin call id "sys_chmod"        =  47
      builtin call id "sys_setenv"       =  48
      builtin call id "cmm_same_ptr"     =  49
      builtin call id "send_through"     =  50
      builtin call id "chan_send"        =  50
      builtin call id "receive_from_timeout" = 51
      builtin call id "map"              =  53
      builtin call id "seq_map"          =  53
      builtin call id "||map"            =  54
      builtin call id "par_map"          =  54
      builtin call id "filter"           =  55
      builtin call id "seq_filter"       =  55
      builtin call id "||filter"         =  56
      builtin call id "par_filter"       =  56
      builtin call id "str_slice"        =  60
      builtin call id "fold"             =  61
      builtin call id "sys_exec"         =  62
      builtin call id "sys_execve"       =  63
      builtin call id "sys_getpid"       =  70
      builtin call id "sys_time_ms"      =  71
      builtin call id "sys_deadline_ms"  =  72
      builtin call id "sys_remaining_ms" =  73
      builtin call id "sys_sleep_ms"     =  74
      builtin call id "sys_open_mode"    =  75
      builtin call id "sys_open"         =  76
      builtin call id "sys_close"        =  77
      builtin call id "sys_read_fd"      =  78
      builtin call id "sys_write_fd"     =  79
      builtin call id "sys_poll"         =  80
      builtin call id "sys_terminate"    =  81
      builtin call id "sys_kill"         =  82
      builtin call id "sys_call"         =  83
      builtin call id "sys_pipe"         =  86
      builtin call id "sys_waitpid"      =  87
      builtin call id _                  =  -1

-- ── Expression & Statement Lowering to Native IR ─────────────

fn :: lower cmm drops RNativeEnv [String] Int RNativeCode => RNativeCode
      lower cmm drops _ [] _ st = st
      lower cmm drops env (x:xs) used_sp st =
        slot = env_var_slot env x
        st1 = nc_emit st (NCmmDropSlot slot) used_sp
        lower_cmm_drops env xs used_sp st1

fn :: lower unused let drop RNativeEnv String [String] Int RNativeCode => RNativeCode
      lower unused let drop env v live_after used_sp st
        | str_in_list v live_after = st
        | otherwise = nc_emit st (NCmmDropSlot (env_var_slot env v)) used_sp

fn :: lower let var store RNativeEnv String [String] Int RNativeCode => RNativeCode
      lower let var store env v bound_locals used_sp st
        | (lookup_local bound_locals v) >= 0 = nc_emit st (NRebindSlot (env_var_slot env v)) used_sp
        | otherwise = nc_emit st (NStoreSlot (env_var_slot env v)) used_sp

fn :: lower expr list to slots RNativeEnv [RExpr] [String] Int Int RNativeCode => RNativeCode
      lower expr list to slots _ [] _ _ _ st = st
      lower expr list to slots env (e:es) bound_locals sp idx st =
        cur_slot = sp + idx
        st1 = lower_expr env e bound_locals cur_slot st
        st2 = nc_emit st1 (NStoreSlot cur_slot) (cur_slot + 1)
        lower_expr_list_to_slots env es bound_locals sp (idx + 1) st2

fn :: lower int list to slots [Int] Int Int RNativeCode => RNativeCode
      lower int list to slots [] _ _ st = st
      lower int list to slots (n:ns) sp idx st =
        cur_slot = sp + idx
        st1 = nc_emit_list st [NLoadImmInt n, NStoreSlot cur_slot] (cur_slot + 1)
        lower_int_list_to_slots ns sp (idx + 1) st1

fn :: lower record updates RNativeEnv [RExpr] [String] Int RNativeCode => RNativeCode
      lower record updates env ((EStr fname):val_e:rest) bound_locals sp st =
        st1 = nc_emit st (NStoreSlot sp) (sp + 1)
        st2 = lower_expr env val_e bound_locals (sp + 1) st1
        fidx = env_field_idx env fname
        st3 = nc_emit st2 (NAdtSet sp fidx) (sp + 1)
        lower_record_updates env rest bound_locals sp st3
      lower record updates _ _ _ _ st = st

fn :: lower var expr RNativeEnv String [String] Int RNativeCode => RNativeCode
      lower var expr env name bound_locals sp st
        | (lookup_local bound_locals name) >= 0 =
          nc_emit st (NCloneSlot (env_var_slot env name)) sp
        | name == "sys_os" =
          nc_emit st (NLoadAdt0 (env_str_off env "Linux") 5) sp
        | name == "sys_arch" =
          nc_emit st (NLoadAdt0 (0 - 1) 0) sp
        | is_upper_ident name =
          c_tag = ident_base_name name
          off = env_str_off env c_tag
          nc_emit st (NLoadAdt0 off (str_len c_tag)) sp
        | (builtin_zero_arg_id name) >= 0 =
          nc_emit st (NCallBuiltin (builtin_zero_arg_id name) sp 0) (sp + 1)
        | (env_fn_arity env name) == 0 =
          nc_emit st (NCallFn (env_fn_id env name) sp 0) (sp + 1)
        | otherwise =
          off = env_str_off env name
          nc_emit st (NLoadStrLit off (str_len name)) sp

fn :: prim type tag id String       => Int
      prim type tag id "Int"        =  1
      prim type tag id "Byte"       =  1
      prim type tag id "U8"         =  1
      prim type tag id "U16"        =  1
      prim type tag id "U32"        =  1
      prim type tag id "U64"        =  1
      prim type tag id "I8"         =  1
      prim type tag id "I16"        =  1
      prim type tag id "I32"        =  1
      prim type tag id "I64"        =  1
      prim type tag id "Usize"      =  1
      prim type tag id "Bool"       =  2
      prim type tag id "String"     =  3
      prim type tag id "Char"       =  3
      prim type tag id "Real"       =  4
      prim type tag id "Float"      =  4
      prim type tag id "Tensor"     =  5
      prim type tag id "Tensor_GPU" =  5
      prim type tag id _            =  0

fn :: is tensor helper name String             => Bool
      is tensor helper name ":tensor-zeros:"   =  True
      is tensor helper name ":tensor-clone:"   =  True
      is tensor helper name ":tensor-row-slice:" = True
      is tensor helper name ":tensor-col-slice:" = True
      is tensor helper name ":tensor-set-row:" =  True
      is tensor helper name ":tensor-set-col:" =  True
      is tensor helper name ":tensor-map-rows:" = True
      is tensor helper name ":tensor-map-rows-in:" = True
      is tensor helper name ":tensor-map-cols:" = True
      is tensor helper name ":tensor-map-cols-in:" = True
      is tensor helper name ":tensor-map-elems:" = True
      is tensor helper name ":tensor-map-elems-in:" = True
      is tensor helper name _                  =  False

fn :: lower make repeated list RNativeEnv RExpr RExpr [String] Int RNativeCode => RNativeCode
      lower make repeated list env lenE fillE boundLocals sp st =
        st1 = lower expr env lenE boundLocals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env fillE boundLocals (sp + 1) st2
        st4 = nc emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        loopLbl = nc lbl st4
        doneLbl = loopLbl + 1
        st5 = nc set lbl st4 (loopLbl + 2)
        insInit = [NMakeList (sp + 2) 0, NStoreSlot (sp + 2), NLoadImmInt 0, NStoreSlot (sp + 3)]
        insLoop = [NLabel loopLbl, NCloneSlot (sp + 3), NStoreSlot (sp + 4), NCloneSlot sp, NBinOp 8 (sp + 4), NAsBool, NJumpIfZero doneLbl, NMoveSlot (sp + 2), NStoreSlot (sp + 4), NCloneSlot (sp + 1), NStoreSlot (sp + 5), NMakeList (sp + 5) 1, NBinOp 14 (sp + 4), NStoreSlot (sp + 2), NMoveSlot (sp + 3), NStoreSlot (sp + 4), NLoadImmInt 1, NBinOp 0 (sp + 4), NStoreSlot (sp + 3), NJump loopLbl]
        insDone = [NLabel doneLbl, NMoveSlot (sp + 2), NStoreSlot (sp + 4), NClearLocals sp (sp + 4), NMoveSlot (sp + 4)]
        nc emit list st5 (insInit :: insLoop :: insDone) (sp + 6)

fn :: lower make one dim tensor RNativeEnv RExpr RExpr [String] Int RNativeCode => RNativeCode
      lower make one dim tensor env lenE fillE boundLocals sp st =
        st1 = lower expr list to slots env [fillE, lenE] boundLocals sp 0 st
        nc emit st1 (NCallBuiltin 88 sp 2) (sp + 3)

fn :: lower make two dim tensor RNativeEnv RExpr RExpr RExpr [String] Int RNativeCode => RNativeCode
      lower make two dim tensor env d1 d2 fillE boundLocals sp st =
        st1 = lower expr list to slots env [fillE, d1, d2] boundLocals sp 0 st
        nc emit st1 (NCallBuiltin 88 sp 3) (sp + 4)

fn :: lower tensor clone RNativeEnv RExpr [String] Int RNativeCode => RNativeCode
      lower tensor clone env baseE boundLocals sp st =
        st1 = lower expr env baseE boundLocals sp st
        ins = [NStoreSlot sp, NCloneSlot sp, NStoreSlot (sp + 1), NLoadImmInt 12, NStoreSlot (sp + 2), NCallBuiltin 90 sp 3]
        nc emit list st1 ins (sp + 4)

fn :: tensor map call instr RNativeEnv RExpr [String] Int Int => RNativeInstr
      tensor map call instr env (EVar fname) boundLocals fnSlot argSlot
        | (lookup_local boundLocals fname) < 0 AND (env_fn_arity env fname) == 1 =
          NCallFn (env_fn_id env fname) argSlot 1
        | otherwise =
          NCallIndirect1 fnSlot argSlot
      tensor map call instr _ _ _ fnSlot argSlot =
        NCallIndirect1 fnSlot argSlot

fn :: lower tensor set row slots Int Int Int Int RNativeCode => RNativeCode
      lower tensor set row slots mSlot rowSlot vecSlot sp st =
        ins = [NCloneSlot mSlot, NStoreSlot sp, NCloneSlot rowSlot, NStoreSlot (sp + 1), NCloneSlot vecSlot, NStoreSlot (sp + 2), NCallBuiltin 93 sp 3, NDropVal]
        nc emit list st ins (sp + 4)

fn :: lower tensor set col slots Int Int Int Int RNativeCode => RNativeCode
      lower tensor set col slots mSlot colSlot vecSlot sp st =
        ins = [NCloneSlot mSlot, NStoreSlot sp, NCloneSlot colSlot, NStoreSlot (sp + 1), NCloneSlot vecSlot, NStoreSlot (sp + 2), NCallBuiltin 95 sp 3, NDropVal]
        nc emit list st ins (sp + 4)

fn :: lower tensor get col slots RNativeEnv Int Int Int RNativeCode => RNativeCode
      lower tensor get col slots _ mSlot colSlot sp st =
        ins = [NCloneSlot mSlot, NStoreSlot sp, NCloneSlot colSlot, NStoreSlot (sp + 1), NCallBuiltin 94 sp 2]
        nc emit list st ins (sp + 3)

fn :: store back mutated tensor RNativeEnv RExpr [String] Int Int RNativeCode => RNativeCode
      store back mutated tensor env (EVar tname) boundLocals srcSlot usedSp st
        | (lookup_local boundLocals tname) >= 0 =
          tslot = env_var_slot env tname
          nc emit list st [NCloneSlot srcSlot, NRebindSlot tslot] usedSp
      store back mutated tensor _ _ _ _ _ st = st

fn :: lower tensor helper RNativeEnv String [RExpr] [String] Int RNativeCode => RNativeCode
      lower tensor helper env ":tensor-zeros:" (fillE:d1:[]) boundLocals sp st =
        lower make one dim tensor env d1 fillE boundLocals sp st
      lower tensor helper env ":tensor-zeros:" (fillE:d1:d2:_) boundLocals sp st =
        lower make two dim tensor env d1 d2 fillE boundLocals sp st
      lower tensor helper env ":tensor-clone:" (baseE:_) boundLocals sp st =
        lower tensor clone env baseE boundLocals sp st
      lower tensor helper env ":tensor-row-slice:" (baseE:rowE:_) boundLocals sp st =
        st1 = lower expr env baseE boundLocals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env rowE boundLocals (sp + 1) st2
        st4 = nc emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        nc emit st4 (NCallBuiltin 92 sp 2) (sp + 3)
      lower tensor helper env ":tensor-col-slice:" (baseE:colE:_) boundLocals sp st =
        st1 = lower expr env baseE boundLocals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env colE boundLocals (sp + 1) st2
        st4 = nc emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        st5 = lower tensor get col slots env sp (sp + 1) (sp + 2) st4
        nc emit list st5 [NStoreSlot (sp + 2), NClearLocals sp (sp + 2), NMoveSlot (sp + 2)] (sp + 3)
      lower tensor helper env ":tensor-set-row:" (baseE:rowE:vecE:_) boundLocals sp st =
        st1 = lower expr env baseE boundLocals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env rowE boundLocals (sp + 1) st2
        st4 = nc emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        st5 = lower expr env vecE boundLocals (sp + 2) st4
        st6 = nc emit st5 (NStoreSlot (sp + 2)) (sp + 3)
        st7 = lower tensor set row slots sp (sp + 1) (sp + 2) (sp + 3) st6
        st8 = store back mutated tensor env baseE boundLocals sp (sp + 3) st7
        nc emit list st8 [NClearLocals sp (sp + 3), NLoadImmRaw 0] (sp + 3)
      lower tensor helper env ":tensor-set-col:" (baseE:colE:vecE:_) boundLocals sp st =
        st1 = lower expr env baseE boundLocals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env colE boundLocals (sp + 1) st2
        st4 = nc emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        st5 = lower expr env vecE boundLocals (sp + 2) st4
        st6 = nc emit st5 (NStoreSlot (sp + 2)) (sp + 3)
        st7 = lower tensor set col slots sp (sp + 1) (sp + 2) (sp + 3) st6
        st8 = store back mutated tensor env baseE boundLocals sp (sp + 3) st7
        nc emit list st8 [NClearLocals sp (sp + 3), NLoadImmRaw 0] (sp + 3)
      lower tensor helper env ":tensor-map-rows:" (fnE:baseE:_) boundLocals sp st =
        lower tensor helper env ":tensor-map-rows-in:" [fnE, ECall ":tensor-clone:" [baseE]] boundLocals sp st
      lower tensor helper env ":tensor-map-rows-in:" (fnE:baseE:_) boundLocals sp st =
        st1 = lower expr env fnE boundLocals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env baseE boundLocals (sp + 1) st2
        st4 = nc emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        loopLbl = nc lbl st4
        keepLbl = loopLbl + 1
        afterKeepLbl = loopLbl + 2
        doneLbl = loopLbl + 3
        st5 = nc set lbl st4 (loopLbl + 4)
        callIns = tensor map call instr env fnE boundLocals sp (sp + 5)
        insPre = [NAdtField (sp + 1) (0 - 10), NStoreSlot (sp + 2), NLoadImmInt 0, NStoreSlot (sp + 3), NLabel loopLbl, NCloneSlot (sp + 3), NStoreSlot (sp + 4), NCloneSlot (sp + 2), NBinOp 8 (sp + 4), NAsBool, NJumpIfZero doneLbl, NCloneSlot (sp + 1), NStoreSlot (sp + 4), NCloneSlot (sp + 3), NStoreSlot (sp + 5), NCallBuiltin 92 (sp + 4) 2, NStoreSlot (sp + 4), NCloneSlot (sp + 4), NStoreSlot (sp + 5), callIns, NStoreSlot (sp + 5), NMatchAdt (sp + 5) 0 0 (0 - 5), NJumpIfZero keepLbl, NMoveSlot (sp + 5), NRebindSlot (sp + 4), NJump afterKeepLbl, NLabel keepLbl, NCmmDropSlot (sp + 5), NLabel afterKeepLbl]
        st6 = nc emit list st5 insPre (sp + 6)
        st7 = lower tensor set row slots (sp + 1) (sp + 3) (sp + 4) (sp + 5) st6
        insLoopEnd = [NCmmDropSlot (sp + 4), NMoveSlot (sp + 3), NStoreSlot (sp + 5), NLoadImmInt 1, NBinOp 0 (sp + 5), NStoreSlot (sp + 3), NJump loopLbl, NLabel doneLbl]
        st8 = nc emit list st7 insLoopEnd (sp + 6)
        st9 = store back mutated tensor env baseE boundLocals (sp + 1) (sp + 6) st8
        insPost = [NMoveSlot (sp + 1), NStoreSlot (sp + 5), NClearLocals sp (sp + 5), NMoveSlot (sp + 5)]
        nc emit list st9 insPost (sp + 6)
      lower tensor helper env ":tensor-map-cols:" (fnE:baseE:_) boundLocals sp st =
        lower tensor helper env ":tensor-map-cols-in:" [fnE, ECall ":tensor-clone:" [baseE]] boundLocals sp st
      lower tensor helper env ":tensor-map-cols-in:" (fnE:baseE:_) boundLocals sp st =
        st1 = lower expr env fnE boundLocals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env baseE boundLocals (sp + 1) st2
        st4 = nc emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        loopLbl = nc lbl st4
        keepLbl = loopLbl + 1
        afterKeepLbl = loopLbl + 2
        doneLbl = loopLbl + 3
        st5 = nc set lbl st4 (loopLbl + 4)
        callIns = tensor map call instr env fnE boundLocals sp (sp + 5)
        insPre = [NAdtField (sp + 1) (0 - 11), NStoreSlot (sp + 2), NLoadImmInt 0, NStoreSlot (sp + 3), NLabel loopLbl, NCloneSlot (sp + 3), NStoreSlot (sp + 4), NCloneSlot (sp + 2), NBinOp 8 (sp + 4), NAsBool, NJumpIfZero doneLbl]
        st6 = nc emit list st5 insPre (sp + 5)
        st7 = lower tensor get col slots env (sp + 1) (sp + 3) (sp + 5) st6
        insCall = [NStoreSlot (sp + 4), NCloneSlot (sp + 4), NStoreSlot (sp + 5), callIns, NStoreSlot (sp + 5), NMatchAdt (sp + 5) 0 0 (0 - 5), NJumpIfZero keepLbl, NMoveSlot (sp + 5), NRebindSlot (sp + 4), NJump afterKeepLbl, NLabel keepLbl, NCmmDropSlot (sp + 5), NLabel afterKeepLbl]
        st8 = nc emit list st7 insCall (sp + 6)
        st9 = lower tensor set col slots (sp + 1) (sp + 3) (sp + 4) (sp + 5) st8
        insLoopEnd = [NCmmDropSlot (sp + 4), NMoveSlot (sp + 3), NStoreSlot (sp + 5), NLoadImmInt 1, NBinOp 0 (sp + 5), NStoreSlot (sp + 3), NJump loopLbl, NLabel doneLbl]
        st10 = nc emit list st9 insLoopEnd (sp + 6)
        st11 = store back mutated tensor env baseE boundLocals (sp + 1) (sp + 6) st10
        insPost = [NMoveSlot (sp + 1), NStoreSlot (sp + 5), NClearLocals sp (sp + 5), NMoveSlot (sp + 5)]
        nc emit list st11 insPost (sp + 6)
      lower tensor helper env ":tensor-map-elems:" (fnE:baseE:_) boundLocals sp st =
        lower tensor helper env ":tensor-map-elems-in:" [fnE, ECall ":tensor-clone:" [baseE]] boundLocals sp st
      lower tensor helper env ":tensor-map-elems-in:" (fnE:baseE:_) boundLocals sp st =
        st1 = lower expr env fnE boundLocals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env baseE boundLocals (sp + 1) st2
        st4 = nc emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        lbl2d = nc lbl st4
        lbl1dLoop = lbl2d + 1
        lbl2dOuter = lbl2d + 2
        lbl2dInner = lbl2d + 3
        lbl2dNextI = lbl2d + 4
        lblDone = lbl2d + 5
        st5 = nc set lbl st4 (lbl2d + 6)
        callIns1d = tensor map call instr env fnE boundLocals sp (sp + 5)
        callIns2d = tensor map call instr env fnE boundLocals sp (sp + 6)
        ins1d = [NAdtField (sp + 1) (0 - 1), NStoreSlot (sp + 2), NMatchInt (sp + 2) 1, NJumpIfZero lbl2d, NAdtField (sp + 1) (0 - 10), NStoreSlot (sp + 2), NLoadImmInt 0, NStoreSlot (sp + 3), NLabel lbl1dLoop, NCloneSlot (sp + 3), NStoreSlot (sp + 4), NCloneSlot (sp + 2), NBinOp 8 (sp + 4), NAsBool, NJumpIfZero lblDone, NCloneSlot (sp + 3), NStoreSlot (sp + 4), NIndex (sp + 1) (sp + 4) (0 - 1), NStoreSlot (sp + 5), callIns1d, NStoreSlot (sp + 5), NCloneSlot (sp + 3), NStoreSlot (sp + 4), NMoveSlot (sp + 5), NIndexSet (sp + 1) (sp + 4) 1, NStoreSlot (sp + 1), NMoveSlot (sp + 3), NStoreSlot (sp + 4), NLoadImmInt 1, NBinOp 0 (sp + 4), NStoreSlot (sp + 3), NJump lbl1dLoop]
        ins2d = [NLabel lbl2d, NAdtField (sp + 1) (0 - 10), NStoreSlot (sp + 2), NAdtField (sp + 1) (0 - 11), NStoreSlot (sp + 3), NLoadImmInt 0, NStoreSlot (sp + 4), NLabel lbl2dOuter, NCloneSlot (sp + 4), NStoreSlot (sp + 5), NCloneSlot (sp + 2), NBinOp 8 (sp + 5), NAsBool, NJumpIfZero lblDone, NLoadImmInt 0, NStoreSlot (sp + 5), NLabel lbl2dInner, NCloneSlot (sp + 5), NStoreSlot (sp + 6), NCloneSlot (sp + 3), NBinOp 8 (sp + 6), NAsBool, NJumpIfZero lbl2dNextI, NCloneSlot (sp + 4), NStoreSlot (sp + 6), NCloneSlot (sp + 5), NStoreSlot (sp + 7), NIndex (sp + 1) (sp + 6) (0 - 2), NStoreSlot (sp + 6), callIns2d, NStoreSlot (sp + 8), NCloneSlot (sp + 4), NStoreSlot (sp + 6), NCloneSlot (sp + 5), NStoreSlot (sp + 7), NMoveSlot (sp + 8), NIndexSet (sp + 1) (sp + 6) 2, NStoreSlot (sp + 1), NMoveSlot (sp + 5), NStoreSlot (sp + 6), NLoadImmInt 1, NBinOp 0 (sp + 6), NStoreSlot (sp + 5), NJump lbl2dInner, NLabel lbl2dNextI, NMoveSlot (sp + 4), NStoreSlot (sp + 6), NLoadImmInt 1, NBinOp 0 (sp + 6), NStoreSlot (sp + 4), NJump lbl2dOuter, NLabel lblDone]
        st6 = nc emit list st5 (ins1d :: ins2d) (sp + 9)
        st7 = store back mutated tensor env baseE boundLocals (sp + 1) (sp + 9) st6
        insDone = [NMoveSlot (sp + 1), NStoreSlot (sp + 6), NClearLocals sp (sp + 6), NMoveSlot (sp + 6)]
        nc emit list st7 insDone (sp + 9)
      lower tensor helper _ _ _ _ _ st = st

fn :: lower bitwise hadamard RNativeEnv RBinOp RExpr RExpr [String] Int RNativeCode => RNativeCode
      lower bitwise hadamard env bop leftE rightE boundLocals sp st =
        st1 = lower expr env leftE boundLocals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env rightE boundLocals (sp + 1) st2
        st4 = nc emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        opCode = binop id bop
        ins = [NLoadImmInt opCode, NStoreSlot (sp + 2), NCallBuiltin 90 sp 3]
        nc emit list st4 ins (sp + 4)

fn :: is agent call name String             => Bool
      is agent call name "agent"            =  True
      is agent call name "send_to"          =  True
      is agent call name "ask_to"           =  True
      is agent call name "receive_from"     =  True
      is agent call name "try_receive_from" =  True
      is agent call name "stop"             =  True
      is agent call name "agent_alive"      =  True
      is agent call name _                  =  False

fn :: agent fn mode RNativeEnv RExpr [String] => Int
      agent fn mode env (EVar fname) bound_locals
        | (lookup_local bound_locals fname) < 0 AND (env_fn_is_heavy env fname) = 3
        | (lookup_local bound_locals fname) < 0 AND (env_fn_arity env fname) == 2 = 4
        | otherwise = 1
      agent fn mode _ _ _ = 1

fn :: stateful agent mode RNativeEnv RExpr [String] => Int
      stateful agent mode env (EVar fname) bound_locals
        | (lookup_local bound_locals fname) < 0 AND (env_fn_is_heavy env fname) = 1
        | otherwise = 0
      stateful agent mode _ _ _ = 0

fn :: lower agent call RNativeEnv String [RExpr] [String] Int RNativeCode => RNativeCode
      lower agent call env "agent" (fn_e:[]) bound_locals sp st =
        ag_mode = agent_fn_mode env fn_e bound_locals
        st1 = lower_expr env fn_e bound_locals sp st
        ins = [NStoreSlot sp, NCallBuiltin 1 (sp + 1) 0, NStoreSlot (sp + 1), NCallBuiltin 1 (sp + 2) 0, NStoreSlot (sp + 2), NLoadImmInt ag_mode, NStoreSlot (sp + 3), NMakeList (sp + 4) 0, NStoreSlot (sp + 4), NMakeTuple (sp + 3) 2, NStoreSlot (sp + 3), NCloneSlot (sp + 1), NStoreSlot (sp + 4), NCallBuiltin 50 (sp + 3) 2, NDropVal, NMakeTuple sp 3]
        nc_emit_list st1 ins (sp + 5)
      lower agent call env "agent" (fn_e:init_e:[]) bound_locals sp st =
        st_flag = stateful_agent_mode env fn_e bound_locals
        st1 = lower_expr env fn_e bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_expr env init_e bound_locals (sp + 4) st2
        ins = [NStoreSlot (sp + 4), NLoadImmInt st_flag, NStoreSlot (sp + 5), NMakeTuple (sp + 4) 2, NStoreSlot (sp + 4), NCallBuiltin 1 (sp + 1) 0, NStoreSlot (sp + 1), NCallBuiltin 1 (sp + 2) 0, NStoreSlot (sp + 2), NLoadImmInt 2, NStoreSlot (sp + 3), NMakeTuple (sp + 3) 2, NStoreSlot (sp + 3), NCloneSlot (sp + 1), NStoreSlot (sp + 4), NCallBuiltin 50 (sp + 3) 2, NDropVal, NMakeTuple sp 3]
        nc_emit_list st3 ins (sp + 6)
      lower agent call env "send_to" (msg_e:ag_e:[]) bound_locals sp st =
        st1 = lower_expr env msg_e bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_expr env ag_e bound_locals (sp + 1) st2
        st4 = nc_emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        stopped_lbl = nc_lbl st4
        stateful_lbl = stopped_lbl + 1
        heavy_lbl = stopped_lbl + 2
        same_res_lbl = stopped_lbl + 3
        split_pair_lbl = stopped_lbl + 4
        store_state_lbl = stopped_lbl + 5
        done_lbl = stopped_lbl + 6
        stateless2_lbl = stopped_lbl + 7
        st_async_lbl = stopped_lbl + 8
        flush_prev_lbl = stopped_lbl + 9
        spawn_stateful_lbl = stopped_lbl + 10
        same_sync_lbl = stopped_lbl + 11
        split_sync_lbl = stopped_lbl + 12
        save_sync_lbl = stopped_lbl + 13
        st5 = nc_set_lbl st4 (stopped_lbl + 14)
        ins_unpack = [NTupleGet (sp + 1) 0, NStoreSlot (sp + 2), NTupleGet (sp + 1) 1, NStoreSlot (sp + 3), NTupleGet (sp + 1) 2, NStoreSlot (sp + 4), NCloneSlot (sp + 3), NStoreSlot (sp + 5), NCallBuiltin 32 (sp + 5) 1, NStoreSlot (sp + 5), NTupleGet (sp + 5) 0, NStoreSlot (sp + 6), NTupleGet (sp + 5) 1, NStoreSlot (sp + 7)]
        ins_stateless = [NMatchInt (sp + 6) 1, NJumpIfZero stateless2_lbl, NCloneSlot sp, NStoreSlot (sp + 8), NCallIndirect1 (sp + 2) (sp + 8), NStoreSlot (sp + 8), NCloneSlot (sp + 5), NStoreSlot (sp + 9), NCloneSlot (sp + 3), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NCloneSlot (sp + 8), NStoreSlot (sp + 9), NCloneSlot (sp + 4), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NJump done_lbl]
        ins_stateless2 = [NLabel stateless2_lbl, NMatchInt (sp + 6) 4, NJumpIfZero stateful_lbl, NTupleGet sp 0, NStoreSlot (sp + 8), NTupleGet sp 1, NStoreSlot (sp + 9), NCallIndirect2 (sp + 2) (sp + 8), NStoreSlot (sp + 8), NCloneSlot (sp + 5), NStoreSlot (sp + 9), NCloneSlot (sp + 3), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NCloneSlot (sp + 8), NStoreSlot (sp + 9), NCloneSlot (sp + 4), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NJump done_lbl]
        ins_stateful = [NLabel stateful_lbl, NMatchInt (sp + 6) 2, NJumpIfZero heavy_lbl, NTupleGet (sp + 7) 0, NStoreSlot (sp + 8), NTupleGet (sp + 7) 1, NStoreSlot (sp + 9), NMatchInt (sp + 9) 0, NJumpIfZero st_async_lbl, NCloneSlot (sp + 8), NStoreSlot (sp + 9), NCloneSlot sp, NStoreSlot (sp + 10), NCallIndirect2 (sp + 2) (sp + 9), NStoreSlot (sp + 10), NMatchTuple (sp + 10) 2, NJumpIfZero same_sync_lbl, NMatchTuple (sp + 8) 2, NJumpIfZero split_sync_lbl, NLabel same_sync_lbl, NCloneSlot (sp + 10), NStoreSlot (sp + 8), NCloneSlot (sp + 10), NStoreSlot (sp + 11), NJump save_sync_lbl, NLabel split_sync_lbl, NTupleGet (sp + 10) 0, NStoreSlot (sp + 8), NTupleGet (sp + 10) 1, NStoreSlot (sp + 11), NLabel save_sync_lbl, NCloneSlot (sp + 4), NStoreSlot (sp + 12), NCallBuiltin 50 (sp + 11) 2, NDropVal, NLoadImmInt 0, NStoreSlot (sp + 9), NMakeTuple (sp + 8) 2, NStoreSlot (sp + 9), NLoadImmInt 2, NStoreSlot (sp + 8), NMakeTuple (sp + 8) 2, NStoreSlot (sp + 8), NCloneSlot (sp + 3), NStoreSlot (sp + 9), NCallBuiltin 50 (sp + 8) 2, NDropVal, NJump done_lbl, NLabel st_async_lbl, NMatchInt (sp + 9) 1, NJumpIfZero flush_prev_lbl, NJump spawn_stateful_lbl, NLabel flush_prev_lbl, NCallBuiltin 59 (sp + 9) 1, NStoreSlot (sp + 10), NMatchTuple (sp + 10) 2, NJumpIfZero same_res_lbl, NMatchTuple (sp + 8) 2, NJumpIfZero split_pair_lbl, NLabel same_res_lbl, NCloneSlot (sp + 10), NStoreSlot (sp + 8), NCloneSlot (sp + 10), NStoreSlot (sp + 11), NJump store_state_lbl, NLabel split_pair_lbl, NTupleGet (sp + 10) 0, NStoreSlot (sp + 8), NTupleGet (sp + 10) 1, NStoreSlot (sp + 11), NLabel store_state_lbl, NCloneSlot (sp + 4), NStoreSlot (sp + 12), NCallBuiltin 50 (sp + 11) 2, NDropVal, NLabel spawn_stateful_lbl, NCloneSlot (sp + 8), NStoreSlot (sp + 10), NCloneSlot sp, NStoreSlot (sp + 11), NMakeTuple (sp + 10) 2, NStoreSlot (sp + 10), NCloneSlot (sp + 2), NStoreSlot (sp + 9), NCallBuiltin 57 (sp + 9) 2, NStoreSlot (sp + 9), NMakeTuple (sp + 8) 2, NStoreSlot (sp + 9), NLoadImmInt 2, NStoreSlot (sp + 8), NMakeTuple (sp + 8) 2, NStoreSlot (sp + 8), NCloneSlot (sp + 3), NStoreSlot (sp + 9), NCallBuiltin 50 (sp + 8) 2, NDropVal, NJump done_lbl]
        ins_heavy = [NLabel heavy_lbl, NMatchInt (sp + 6) 3, NJumpIfZero stopped_lbl, NCloneSlot (sp + 2), NStoreSlot (sp + 8), NCloneSlot sp, NStoreSlot (sp + 9), NCallBuiltin 57 (sp + 8) 2, NStoreSlot (sp + 9), NMoveSlot (sp + 7), NStoreSlot (sp + 8), NMakeList (sp + 9) 1, NBinOp 14 (sp + 8), NStoreSlot (sp + 9), NLoadImmInt 3, NStoreSlot (sp + 8), NMakeTuple (sp + 8) 2, NStoreSlot (sp + 9), NCloneSlot (sp + 3), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NJump done_lbl]
        ins_stopped = [NLabel stopped_lbl, NCloneSlot (sp + 5), NStoreSlot (sp + 9), NCloneSlot (sp + 3), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NLabel done_lbl, NClearLocals sp (sp + 13), NLoadImmRaw 0]
        nc_emit_list st5 (ins_unpack :: ins_stateless :: ins_stateless2 :: ins_stateful :: ins_heavy :: ins_stopped) (sp + 13)
      lower agent call env "ask_to" (msg_e:ag_e:[]) bound_locals sp st =
        st1 = lower_agent_call env "send_to" [msg_e, ag_e] bound_locals sp st
        st2 = nc_emit st1 NDropVal sp
        lower_agent_call env "receive_from" [ag_e] bound_locals sp st2
      lower agent call env "receive_from" (target_e:[]) bound_locals sp st =
        st1 = lower_expr env target_e bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        not_ag_lbl = nc_lbl st2
        no_job_lbl = not_ag_lbl + 1
        done_lbl = not_ag_lbl + 2
        check_st_lbl = not_ag_lbl + 3
        st_await_lbl = not_ag_lbl + 4
        st_has_job_lbl = not_ag_lbl + 5
        st_same_lbl = not_ag_lbl + 6
        st_split_lbl = not_ag_lbl + 7
        st_save_lbl = not_ag_lbl + 8
        st_has_job_lbl2 = not_ag_lbl + 9
        st3 = nc_set_lbl st2 (not_ag_lbl + 10)
        ok_off = env_str_off env "Ok"
        ins_check = [NMatchTuple sp 3, NJumpIfZero not_ag_lbl, NTupleGet sp 1, NStoreSlot (sp + 1), NTupleGet sp 2, NStoreSlot sp, NCloneSlot (sp + 1), NStoreSlot (sp + 2), NCallBuiltin 32 (sp + 2) 1, NStoreSlot (sp + 2), NTupleGet (sp + 2) 0, NStoreSlot (sp + 3), NTupleGet (sp + 2) 1, NStoreSlot (sp + 4), NMatchInt (sp + 3) 3, NJumpIfZero check_st_lbl, NMatchNonEmpty (sp + 4), NJumpIfZero no_job_lbl]
        ins_pop = [NListHead (sp + 4), NStoreSlot (sp + 5), NListTail (sp + 4), NStoreSlot (sp + 6), NLoadImmInt 3, NStoreSlot (sp + 7), NMoveSlot (sp + 6), NStoreSlot (sp + 8), NMakeTuple (sp + 7) 2, NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NClearLocals sp (sp + 5), NCallBuiltin 59 (sp + 5) 1, NJump done_lbl]
        ins_st = [NLabel check_st_lbl, NMatchInt (sp + 3) 2, NJumpIfZero no_job_lbl, NCloneSlot sp, NStoreSlot (sp + 5), NCallBuiltin 33 (sp + 5) 1, NStoreSlot (sp + 5), NMatchAdt (sp + 5) ok_off 2 1, NJumpIfZero st_await_lbl, NMoveSlot (sp + 2), NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NAdtField (sp + 5) 0, NStoreSlot (sp + 6), NClearLocals sp (sp + 6), NMoveSlot (sp + 6), NJump done_lbl, NLabel st_await_lbl, NTupleGet (sp + 4) 0, NStoreSlot (sp + 5), NTupleGet (sp + 4) 1, NStoreSlot (sp + 6), NMatchInt (sp + 6) 0, NJumpIfZero st_has_job_lbl, NJump no_job_lbl, NLabel st_has_job_lbl, NMatchInt (sp + 6) 1, NJumpIfZero st_has_job_lbl2, NJump no_job_lbl, NLabel st_has_job_lbl2, NCallBuiltin 59 (sp + 6) 1, NStoreSlot (sp + 7), NMatchTuple (sp + 7) 2, NJumpIfZero st_same_lbl, NMatchTuple (sp + 5) 2, NJumpIfZero st_split_lbl, NLabel st_same_lbl, NCloneSlot (sp + 7), NStoreSlot (sp + 8), NCloneSlot (sp + 7), NStoreSlot (sp + 9), NJump st_save_lbl, NLabel st_split_lbl, NTupleGet (sp + 7) 0, NStoreSlot (sp + 8), NTupleGet (sp + 7) 1, NStoreSlot (sp + 9), NLabel st_save_lbl, NLoadImmInt 1, NStoreSlot (sp + 10), NMoveSlot (sp + 8), NStoreSlot (sp + 11), NMoveSlot (sp + 10), NStoreSlot (sp + 12), NMakeTuple (sp + 11) 2, NStoreSlot (sp + 11), NLoadImmInt 2, NStoreSlot (sp + 10), NMakeTuple (sp + 10) 2, NStoreSlot (sp + 10), NCloneSlot (sp + 1), NStoreSlot (sp + 11), NCallBuiltin 50 (sp + 10) 2, NDropVal, NClearLocals sp (sp + 9), NMoveSlot (sp + 9), NJump done_lbl]
        ins_no_job = [NLabel no_job_lbl, NMoveSlot (sp + 2), NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NClearLocals (sp + 1) (sp + 13), NLabel not_ag_lbl, NCallBuiltin 32 sp 1, NLabel done_lbl]
        nc_emit_list st3 (ins_check :: ins_pop :: ins_st :: ins_no_job) (sp + 13)
      lower agent call env "try_receive_from" (target_e:[]) bound_locals sp st =
        st1 = lower_expr env target_e bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        not_ag_lbl = nc_lbl st2
        no_job_lbl = not_ag_lbl + 1
        not_ready_lbl = not_ag_lbl + 2
        chan_none_lbl = not_ag_lbl + 3
        done_lbl = not_ag_lbl + 4
        try_st_lbl = not_ag_lbl + 5
        try_st_poll_lbl = not_ag_lbl + 6
        try_st_has_job_lbl = not_ag_lbl + 7
        try_st_same_lbl = not_ag_lbl + 8
        try_st_split_lbl = not_ag_lbl + 9
        try_st_save_lbl = not_ag_lbl + 10
        try_st_has_job_lbl2 = not_ag_lbl + 11
        st3 = nc_set_lbl st2 (not_ag_lbl + 12)
        ok_off = env_str_off env "Ok"
        some_off = env_str_off env "Some"
        none_off = env_str_off env "None"
        ins_check = [NMatchTuple sp 3, NJumpIfZero not_ag_lbl, NTupleGet sp 1, NStoreSlot (sp + 1), NTupleGet sp 2, NStoreSlot sp, NCloneSlot (sp + 1), NStoreSlot (sp + 2), NCallBuiltin 32 (sp + 2) 1, NStoreSlot (sp + 2), NTupleGet (sp + 2) 0, NStoreSlot (sp + 3), NTupleGet (sp + 2) 1, NStoreSlot (sp + 4), NMatchInt (sp + 3) 3, NJumpIfZero try_st_lbl, NMatchNonEmpty (sp + 4), NJumpIfZero no_job_lbl, NListHead (sp + 4), NStoreSlot (sp + 5), NCloneSlot (sp + 5), NStoreSlot (sp + 6), NCallBuiltin 58 (sp + 6) 1, NAsBool, NJumpIfZero not_ready_lbl]
        ins_ready = [NListTail (sp + 4), NStoreSlot (sp + 6), NLoadImmInt 3, NStoreSlot (sp + 7), NMoveSlot (sp + 6), NStoreSlot (sp + 8), NMakeTuple (sp + 7) 2, NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NCallBuiltin 59 (sp + 5) 1, NStoreSlot (sp + 5), NMakeAdt some_off 4 (sp + 5) 1, NStoreSlot (sp + 5), NClearLocals sp (sp + 5), NMoveSlot (sp + 5), NJump done_lbl]
        ins_try_st = [NLabel try_st_lbl, NMatchInt (sp + 3) 2, NJumpIfZero no_job_lbl, NCloneSlot sp, NStoreSlot (sp + 5), NCallBuiltin 33 (sp + 5) 1, NStoreSlot (sp + 5), NMatchAdt (sp + 5) ok_off 2 1, NJumpIfZero try_st_poll_lbl, NMoveSlot (sp + 2), NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NAdtField (sp + 5) 0, NStoreSlot (sp + 6), NMakeAdt some_off 4 (sp + 6) 1, NStoreSlot (sp + 6), NClearLocals sp (sp + 6), NMoveSlot (sp + 6), NJump done_lbl, NLabel try_st_poll_lbl, NTupleGet (sp + 4) 0, NStoreSlot (sp + 5), NTupleGet (sp + 4) 1, NStoreSlot (sp + 6), NMatchInt (sp + 6) 0, NJumpIfZero try_st_has_job_lbl, NJump not_ready_lbl, NLabel try_st_has_job_lbl, NMatchInt (sp + 6) 1, NJumpIfZero try_st_has_job_lbl2, NJump not_ready_lbl, NLabel try_st_has_job_lbl2, NCloneSlot (sp + 6), NStoreSlot (sp + 7), NCallBuiltin 58 (sp + 7) 1, NAsBool, NJumpIfZero not_ready_lbl, NCallBuiltin 59 (sp + 6) 1, NStoreSlot (sp + 7), NMatchTuple (sp + 7) 2, NJumpIfZero try_st_same_lbl, NMatchTuple (sp + 5) 2, NJumpIfZero try_st_split_lbl, NLabel try_st_same_lbl, NCloneSlot (sp + 7), NStoreSlot (sp + 8), NCloneSlot (sp + 7), NStoreSlot (sp + 9), NJump try_st_save_lbl, NLabel try_st_split_lbl, NTupleGet (sp + 7) 0, NStoreSlot (sp + 8), NTupleGet (sp + 7) 1, NStoreSlot (sp + 9), NLabel try_st_save_lbl, NLoadImmInt 1, NStoreSlot (sp + 10), NMoveSlot (sp + 8), NStoreSlot (sp + 11), NMoveSlot (sp + 10), NStoreSlot (sp + 12), NMakeTuple (sp + 11) 2, NStoreSlot (sp + 11), NLoadImmInt 2, NStoreSlot (sp + 10), NMakeTuple (sp + 10) 2, NStoreSlot (sp + 10), NCloneSlot (sp + 1), NStoreSlot (sp + 11), NCallBuiltin 50 (sp + 10) 2, NDropVal, NMakeAdt some_off 4 (sp + 9) 1, NStoreSlot (sp + 9), NClearLocals sp (sp + 9), NMoveSlot (sp + 9), NJump done_lbl]
        ins_not_ready = [NLabel not_ready_lbl, NMoveSlot (sp + 2), NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NClearLocals sp (sp + 13), NLoadAdt0 none_off 4, NJump done_lbl]
        ins_chan = [NLabel no_job_lbl, NMoveSlot (sp + 2), NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NClearLocals (sp + 1) (sp + 13), NLabel not_ag_lbl, NCallBuiltin 33 sp 1, NStoreSlot sp, NMatchAdt sp ok_off 2 1, NJumpIfZero chan_none_lbl, NAdtField sp 0, NStoreSlot (sp + 1), NMakeAdt some_off 4 (sp + 1) 1, NStoreSlot (sp + 1), NClearLocals sp (sp + 1), NMoveSlot (sp + 1), NJump done_lbl, NLabel chan_none_lbl, NClearLocals sp (sp + 2), NLoadAdt0 none_off 4, NLabel done_lbl]
        nc_emit_list st3 (ins_check :: ins_ready :: ins_try_st :: ins_not_ready :: ins_chan) (sp + 13)
      lower agent call env "stop" (ag_e:[]) bound_locals sp st =
        st1 = lower_expr env ag_e bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        no_jobs_lbl = nc_lbl st2
        loop_lbl = no_jobs_lbl + 1
        st_stop_lbl = no_jobs_lbl + 2
        st_stop_await_lbl = no_jobs_lbl + 3
        st_stop_await_lbl2 = no_jobs_lbl + 4
        st3 = nc_set_lbl st2 (no_jobs_lbl + 5)
        ins_open = [NTupleGet sp 1, NStoreSlot (sp + 1), NCloneSlot (sp + 1), NStoreSlot (sp + 2), NCallBuiltin 32 (sp + 2) 1, NStoreSlot (sp + 2), NTupleGet (sp + 2) 0, NStoreSlot (sp + 3), NTupleGet (sp + 2) 1, NStoreSlot (sp + 4), NMatchInt (sp + 3) 3, NJumpIfZero st_stop_lbl]
        ins_loop = [NLabel loop_lbl, NMatchNonEmpty (sp + 4), NJumpIfZero no_jobs_lbl, NListHead (sp + 4), NStoreSlot (sp + 5), NListTail (sp + 4), NStoreSlot (sp + 4), NCallBuiltin 59 (sp + 5) 1, NDropVal, NJump loop_lbl]
        ins_st_stop = [NLabel st_stop_lbl, NMatchInt (sp + 3) 2, NJumpIfZero no_jobs_lbl, NTupleGet (sp + 4) 1, NStoreSlot (sp + 5), NMatchInt (sp + 5) 0, NJumpIfZero st_stop_await_lbl, NJump no_jobs_lbl, NLabel st_stop_await_lbl, NMatchInt (sp + 5) 1, NJumpIfZero st_stop_await_lbl2, NJump no_jobs_lbl, NLabel st_stop_await_lbl2, NCallBuiltin 59 (sp + 5) 1, NDropVal]
        ins_close = [NLabel no_jobs_lbl, NLoadImmInt 0, NStoreSlot (sp + 2), NLoadImmInt 0, NStoreSlot (sp + 3), NMakeTuple (sp + 2) 2, NStoreSlot (sp + 2), NCloneSlot (sp + 1), NStoreSlot (sp + 3), NCallBuiltin 50 (sp + 2) 2, NDropVal, NClearLocals sp (sp + 6), NLoadImmRaw 0]
        nc_emit_list st3 (ins_open :: ins_loop :: ins_st_stop :: ins_close) (sp + 6)
      lower agent call env "agent_alive" (ag_e:[]) bound_locals sp st =
        alive_lbl = nc_lbl st
        done_lbl = alive_lbl + 1
        st1 = nc_set_lbl st (alive_lbl + 2)
        st2 = lower_expr env ag_e bound_locals sp st1
        ins = [NStoreSlot sp, NTupleGet sp 1, NStoreSlot (sp + 1), NCloneSlot (sp + 1), NStoreSlot (sp + 2), NCallBuiltin 32 (sp + 2) 1, NStoreSlot (sp + 2), NTupleGet (sp + 2) 0, NStoreSlot (sp + 3), NCloneSlot (sp + 2), NStoreSlot (sp + 4), NCloneSlot (sp + 1), NStoreSlot (sp + 5), NCallBuiltin 50 (sp + 4) 2, NDropVal, NMatchInt (sp + 3) 0, NJumpIfZero alive_lbl, NClearLocals sp (sp + 6), NLoadImmRaw 2, NJump done_lbl, NLabel alive_lbl, NClearLocals sp (sp + 6), NLoadImmRaw 6, NLabel done_lbl]
        nc_emit_list st2 ins (sp + 6)
      lower agent call _ _ _ _ _ st = st

fn :: select par collection builtin RNativeEnv String [RExpr] [String] => Int
      select par collection builtin env fname ((EVar callee_fn):_:[]) bound_locals
        | (fname == "||map" OR fname == "par_map") AND (lookup_local bound_locals callee_fn) < 0 AND (env_fn_arity env callee_fn) > 0 AND (NOT (env_fn_is_heavy env callee_fn)) = 53
        | (fname == "||filter" OR fname == "par_filter") AND (lookup_local bound_locals callee_fn) < 0 AND (env_fn_arity env callee_fn) > 0 AND (NOT (env_fn_is_heavy env callee_fn)) = 55
      select par collection builtin _ fname _ _ = builtin_call_id fname

fn :: lower plain indirect call RNativeEnv Int [RExpr] [String] Int RNativeCode => RNativeCode
      lower plain indirect call _ fn_slot [] _ sp st =
        nc_emit st (NCloneSlot fn_slot) sp
      lower plain indirect call env fn_slot (a1:[]) bound_locals sp st =
        st1 = lower_expr env a1 bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        nc_emit st2 (NCallIndirect1 fn_slot sp) (sp + 1)
      lower plain indirect call env fn_slot (a1:a2:[]) bound_locals sp st =
        st1 = lower_expr_list_to_slots env [a1, a2] bound_locals sp 0 st
        nc_emit st1 (NCallIndirect2 fn_slot sp) (sp + 2)
      lower plain indirect call env fn_slot (a1:rest) bound_locals sp st =
        rem_count = rexpr_list_len rest
        st1 = lower_expr env a1 bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_expr_list_to_slots env rest bound_locals (sp + 1) 0 st2
        st4 = nc_emit_list st3 [NMakeTuple (sp + 1) rem_count, NStoreSlot (sp + 1)] (sp + rem_count + 2)
        nc_emit st4 (NCallIndirect2 fn_slot sp) (sp + rem_count + 2)

fn :: lower indirect call slots RNativeEnv Int [RExpr] [String] Int RNativeCode => RNativeCode
      lower indirect call slots _ fn_slot [] _ sp st =
        nc_emit st (NCloneSlot fn_slot) sp
      lower indirect call slots env fn_slot args bound_locals sp st =
        count = rexpr_list_len args
        plain_lbl = nc_lbl st
        done_lbl = plain_lbl + 1
        st0 = nc_set_lbl st (plain_lbl + 2)
        st1 = nc_emit_list st0 [NMatchTuple fn_slot 2, NJumpIfZero plain_lbl, NTupleGet fn_slot 0, NStoreSlot sp, NTupleGet fn_slot 1, NStoreSlot (sp + 1)] (sp + 2)
        st2 = lower_expr_list_to_slots env args bound_locals (sp + 2) 0 st1
        ins_clos = [NMakeList (sp + 2) count, NBinOp 14 (sp + 1), NStoreSlot (sp + 1), NListHead (sp + 1), NStoreSlot (sp + 2), NListTail (sp + 1), NStoreSlot (sp + 3), NMoveSlot (sp + 2), NStoreSlot (sp + 1), NMoveSlot (sp + 3), NStoreSlot (sp + 2), NCallIndirect2 sp (sp + 1), NStoreSlot (sp + 1), NClearLocals sp (sp + 1), NMoveSlot (sp + 1), NJump done_lbl, NLabel plain_lbl]
        st3 = nc_emit_list st2 ins_clos (sp + count + 4)
        st4 = lower plain indirect call env fn_slot args bound_locals sp st3
        nc_emit st4 (NLabel done_lbl) (sp + count + 4)

fn :: lower map or closure map RNativeEnv String [RExpr] [String] Int RNativeCode => RNativeCode
      lower map or closure map env fname (fn_e:list_e:[]) bound_locals sp st =
        bid = select_par_collection_builtin env fname [fn_e, list_e] bound_locals
        plain_lbl = nc_lbl st
        loop_lbl = plain_lbl + 1
        done_lbl = plain_lbl + 2
        after_lbl = plain_lbl + 3
        st0 = nc_set_lbl st (plain_lbl + 4)
        st1 = lower_expr_list_to_slots env [fn_e, list_e] bound_locals sp 0 st0
        ins_clos = [NMatchTuple sp 2, NJumpIfZero plain_lbl, NMakeList (sp + 2) 0, NStoreSlot (sp + 2), NLabel loop_lbl, NMatchNonEmpty (sp + 1), NJumpIfZero done_lbl, NTupleGet sp 0, NStoreSlot (sp + 3), NTupleGet sp 1, NStoreSlot (sp + 4), NListHead (sp + 1), NStoreSlot (sp + 5), NMakeList (sp + 5) 1, NBinOp 14 (sp + 4), NStoreSlot (sp + 4), NListHead (sp + 4), NStoreSlot (sp + 5), NListTail (sp + 4), NStoreSlot (sp + 6), NMoveSlot (sp + 5), NStoreSlot (sp + 4), NMoveSlot (sp + 6), NStoreSlot (sp + 5), NCallIndirect2 (sp + 3) (sp + 4), NStoreSlot (sp + 5), NMakeList (sp + 5) 1, NBinOp 14 (sp + 2), NStoreSlot (sp + 2), NListTail (sp + 1), NStoreSlot (sp + 1), NJump loop_lbl, NLabel done_lbl, NClearLocals sp (sp + 2), NClearLocals (sp + 3) (sp + 7), NMoveSlot (sp + 2), NJump after_lbl, NLabel plain_lbl, NCallBuiltin bid sp 2, NLabel after_lbl]
        nc_emit_list st1 ins_clos (sp + 7)
      lower map or closure map env fname args bound_locals sp st =
        count = rexpr_list_len args
        bid = select_par_collection_builtin env fname args bound_locals
        st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
        nc_emit st1 (NCallBuiltin bid sp count) (sp + count + 1)

fn :: lower filter or closure filter RNativeEnv String [RExpr] [String] Int RNativeCode => RNativeCode
      lower filter or closure filter env fname (fn_e:list_e:[]) bound_locals sp st =
        bid = select_par_collection_builtin env fname [fn_e, list_e] bound_locals
        plain_lbl = nc_lbl st
        loop_lbl = plain_lbl + 1
        skip_lbl = plain_lbl + 2
        done_lbl = plain_lbl + 3
        after_lbl = plain_lbl + 4
        st0 = nc_set_lbl st (plain_lbl + 5)
        st1 = lower_expr_list_to_slots env [fn_e, list_e] bound_locals sp 0 st0
        ins_clos = [NMatchTuple sp 2, NJumpIfZero plain_lbl, NMakeList (sp + 2) 0, NStoreSlot (sp + 2), NLabel loop_lbl, NMatchNonEmpty (sp + 1), NJumpIfZero done_lbl, NTupleGet sp 0, NStoreSlot (sp + 3), NTupleGet sp 1, NStoreSlot (sp + 4), NListHead (sp + 1), NStoreSlot (sp + 5), NMakeList (sp + 5) 1, NBinOp 14 (sp + 4), NStoreSlot (sp + 4), NListHead (sp + 4), NStoreSlot (sp + 5), NListTail (sp + 4), NStoreSlot (sp + 6), NMoveSlot (sp + 5), NStoreSlot (sp + 4), NMoveSlot (sp + 6), NStoreSlot (sp + 5), NCallIndirect2 (sp + 3) (sp + 4), NAsBool, NJumpIfZero skip_lbl, NListHead (sp + 1), NStoreSlot (sp + 5), NMakeList (sp + 5) 1, NBinOp 14 (sp + 2), NStoreSlot (sp + 2), NLabel skip_lbl, NListTail (sp + 1), NStoreSlot (sp + 1), NJump loop_lbl, NLabel done_lbl, NClearLocals sp (sp + 2), NClearLocals (sp + 3) (sp + 7), NMoveSlot (sp + 2), NJump after_lbl, NLabel plain_lbl, NCallBuiltin bid sp 2, NLabel after_lbl]
        nc_emit_list st1 ins_clos (sp + 7)
      lower filter or closure filter env fname args bound_locals sp st =
        count = rexpr_list_len args
        bid = select_par_collection_builtin env fname args bound_locals
        st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
        nc_emit st1 (NCallBuiltin bid sp count) (sp + count + 1)

fn :: lower fold or closure fold RNativeEnv [RExpr] [String] Int RNativeCode => RNativeCode
      lower fold or closure fold env (fn_e:init_e:list_e:[]) bound_locals sp st =
        plain_lbl = nc_lbl st
        loop_lbl = plain_lbl + 1
        done_lbl = plain_lbl + 2
        after_lbl = plain_lbl + 3
        st0 = nc_set_lbl st (plain_lbl + 4)
        st1 = lower_expr_list_to_slots env [fn_e, init_e, list_e] bound_locals sp 0 st0
        ins_clos = [NMatchTuple sp 2, NJumpIfZero plain_lbl, NLabel loop_lbl, NMatchNonEmpty (sp + 2), NJumpIfZero done_lbl, NTupleGet sp 0, NStoreSlot (sp + 3), NTupleGet sp 1, NStoreSlot (sp + 4), NMoveSlot (sp + 1), NStoreSlot (sp + 5), NListHead (sp + 2), NStoreSlot (sp + 6), NMakeList (sp + 5) 2, NBinOp 14 (sp + 4), NStoreSlot (sp + 4), NListHead (sp + 4), NStoreSlot (sp + 5), NListTail (sp + 4), NStoreSlot (sp + 6), NMoveSlot (sp + 5), NStoreSlot (sp + 4), NMoveSlot (sp + 6), NStoreSlot (sp + 5), NCallIndirect2 (sp + 3) (sp + 4), NStoreSlot (sp + 1), NListTail (sp + 2), NStoreSlot (sp + 2), NJump loop_lbl, NLabel done_lbl, NCmmDropSlot sp, NClearLocals (sp + 2) (sp + 7), NMoveSlot (sp + 1), NJump after_lbl, NLabel plain_lbl, NCallBuiltin 61 sp 3, NLabel after_lbl]
        nc_emit_list st1 ins_clos (sp + 7)
      lower fold or closure fold env args bound_locals sp st =
        count = rexpr_list_len args
        st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
        nc_emit st1 (NCallBuiltin 61 sp count) (sp + count + 1)

fn :: lower direct or partial call RNativeEnv String [RExpr] Int Int [String] Int RNativeCode => RNativeCode
      lower direct or partial call env fname args count fn_ar bound_locals sp st
        | count > 0 and fn_ar > count =
          off = env_str_off env fname
          slen = str_len fname
          st1 = nc_emit_list st [NLoadStrLit off slen, NStoreSlot sp] (sp + 1)
          st2 = lower_expr_list_to_slots env args bound_locals (sp + 1) 0 st1
          nc_emit_list st2 [NMakeList (sp + 1) count, NStoreSlot (sp + 1), NMakeTuple sp 2] (sp + count + 2)
        | otherwise =
          st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
          nc_emit st1 (NCallFn (env_fn_id env fname) sp count) (sp + count + 1)

fn :: lower call expr RNativeEnv String [RExpr] [String] Int RNativeCode => RNativeCode
      lower call expr env "__chain__" (fn_e:call_args) bound_locals sp st =
        st1 = lower_expr env fn_e bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        lower indirect call slots env sp call_args bound_locals (sp + 1) st2
      lower call expr env fname args bound_locals sp st
        | is_agent_call_name fname = lower_agent_call env fname args bound_locals sp st
        | is tensor helper name fname = lower tensor helper env fname args bound_locals sp st
        | (lookup_local bound_locals fname) >= 0 =
          lower indirect call slots env (env_var_slot env fname) args bound_locals sp st
      lower call expr env fname [] _ sp st
        | fname == "sys_os" =
          nc_emit st (NLoadAdt0 (env_str_off env "Linux") 5) sp
        | fname == "sys_arch" =
          nc_emit st (NLoadAdt0 (0 - 1) 0) sp
      lower call expr env fname (a1:[]) bound_locals sp st
        | (prim_type_tag_id fname) > 0 =
          lower_expr env a1 bound_locals sp st
      lower call expr env fname (rec_e:call_args) bound_locals sp st
        | (env has field env fname) and (env_fn_arity env fname) == 1 and (rexpr_list_len call_args) >= 1 =
          fidx = env_field_idx env fname
          st1 = lower_expr env rec_e bound_locals sp st
          st2 = nc_emit_list st1 [NStoreSlot sp, NAdtField sp fidx, NStoreSlot sp] (sp + 1)
          lower indirect call slots env sp call_args bound_locals (sp + 1) st2
      lower call expr env fname args bound_locals sp st
        | is_upper_ident fname =
          count = rexpr_list_len args
          c_tag = ident_base_name fname
          off = env_str_off env c_tag
          slen = str_len c_tag
          lower_adt_ctor_call env args bound_locals off slen count sp st
        | fname == "map" or fname == "||map" or fname == "seq_map" or fname == "par_map" =
          lower map or closure map env fname args bound_locals sp st
        | fname == "filter" or fname == "||filter" or fname == "seq_filter" or fname == "par_filter" =
          lower filter or closure filter env fname args bound_locals sp st
        | fname == "fold" =
          lower fold or closure fold env args bound_locals sp st
      lower call expr env "sha256_raw" ((EBin OpAdd a b):[]) bound_locals sp st
        | (lookup_local bound_locals "sha256_raw") < 0 =
          st1 = lower_expr_list_to_slots env [a, b] bound_locals sp 0 st
          nc_emit st1 (NCallBuiltin 89 sp 2) (sp + 3)
      lower call expr env "str_char_at" ((EVar s_var):idx_e:[]) bound_locals sp st
        | (lookup_local bound_locals "str_char_at") < 0 and (lookup_local bound_locals s_var) >= 0 =
          s_slot = env_var_slot env s_var
          st1 = lower_expr env idx_e bound_locals sp st
          nc_emit st1 (NCallBuiltin 91 s_slot 0) sp
      lower call expr env fname args bound_locals sp st
        | (builtin_call_id fname) >= 0 =
          count = rexpr_list_len args
          bid = select_par_collection_builtin env fname args bound_locals
          st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
          nc_emit st1 (NCallBuiltin bid sp count) (sp + count + 1)
        | otherwise =
          count = rexpr_list_len args
          fn_ar = env_fn_arity env fname
          lower direct or partial call env fname args count fn_ar bound_locals sp st

fn :: lower adt ctor call RNativeEnv [RExpr] [String] Int Int Int Int RNativeCode => RNativeCode
      lower adt ctor call _ [] _ off slen 0 sp st =
        nc_emit st (NLoadAdt0 off slen) sp
      lower adt ctor call env args bound_locals off slen count sp st =
        st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
        nc_emit st1 (NMakeAdt off slen sp count) (sp + count + 1)

fn :: lower expr RNativeEnv RExpr [String] Int RNativeCode => RNativeCode
      lower expr _ (EInt n) _ sp st =
        nc_emit st (NLoadImmInt n) sp
      lower expr env (EReal r) _ sp st =
        off = env_str_off env r
        nc_emit st (NLoadRealLit off (str_len r)) sp
      lower expr env (EStr s) _ sp st =
        off = env_str_off env s
        nc_emit st (NLoadStrLit off (str_len s)) sp
      lower expr env (EStrInterp parts) bound_locals sp st =
        count = rexpr_list_len parts
        st1 = lower_expr_list_to_slots env parts bound_locals sp 0 st
        nc_emit st1 (NStrInterp sp count) (sp + count + 1)
      lower expr _ (EBool True) _ sp st =
        nc_emit st (NLoadImmRaw 6) sp
      lower expr _ (EBool False) _ sp st =
        nc_emit st (NLoadImmRaw 2) sp
      lower expr _ EUnit _ sp st =
        nc_emit st (NLoadImmRaw 0) sp
      lower expr env (EVar name) bound_locals sp st =
        lower_var_expr env name bound_locals sp st
      lower expr env (ENot inner) bound_locals sp st =
        st1 = lower_expr env inner bound_locals sp st
        nc_emit st1 NNot sp
      lower expr env (EOut inner) bound_locals sp st =
        st1 = lower_expr env inner bound_locals sp st
        nc_emit st1 NOut sp
      lower expr env (EBin bop l r) bound_locals sp st =
        st1 = lower_expr env l bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_expr env r bound_locals (sp + 1) st2
        nc_emit st3 (NBinOp (binop_id bop) sp) (sp + 1)
      lower expr env (ECall "__record_update__" (base_e:rest_args)) bound_locals sp st =
        st1 = lower_expr env base_e bound_locals sp st
        lower_record_updates env rest_args bound_locals sp st1
      lower expr env (ECall "__unpack2__" ((EVar fn_target):single_arg:[])) bound_locals sp st =
        st1 = lower_expr env single_arg bound_locals sp st
        fid = env_fn_id env fn_target
        ins_list = [NStoreSlot sp, NTupleGet sp 0, NStoreSlot (sp + 1), NTupleGet sp 1, NStoreSlot (sp + 2), NClearLocals sp (sp + 1), NCallFn fid (sp + 1) 2]
        nc_emit_list st1 ins_list (sp + 3)
      lower expr env (ECall fname args) bound_locals sp st =
        lower_call_expr env fname args bound_locals sp st
      lower expr env (EEcho args) bound_locals sp st =
        count = rexpr_list_len args
        st1 = lower_expr_list_to_slots env args bound_locals sp 0 st
        nc_emit st1 (NEcho sp count) (sp + count + 1)
      lower expr env (EList elems) bound_locals sp st =
        count = rexpr_list_len elems
        st1 = lower_expr_list_to_slots env elems bound_locals sp 0 st
        nc_emit st1 (NMakeList sp count) (sp + count + 1)
      lower expr env (ETuple elems) bound_locals sp st =
        count = rexpr_list_len elems
        st1 = lower_expr_list_to_slots env elems bound_locals sp 0 st
        nc_emit st1 (NMakeTuple sp count) (sp + count + 1)
      lower expr env (ETensor elems) bound_locals sp st =
        count = rexpr_list_len elems
        st1 = lower_expr_list_to_slots env elems bound_locals sp 0 st
        nc_emit st1 (NMakeTensor sp count) (sp + count + 1)
      lower expr env (EEinsum es subs) bound_locals sp st =
        count = rexpr_list_len es
        spec = join_comma subs
        off = env_str_off env spec
        st1 = lower_expr_list_to_slots env es bound_locals sp 0 st
        nc_emit st1 (NEinsum sp count off (str_len spec)) (sp + count + 1)
      lower expr env (EHadamard bop l s1 r s2) bound_locals sp st
        | (bop == OpXor OR bop == OpAnd OR bop == OpOr) OR (s1 == s2 AND (bop == OpAdd OR bop == OpSub OR bop == OpMul)) =
          lower bitwise hadamard env bop l r bound_locals sp st
        | otherwise =
          subs = s1 + "," + s2
          off = env_str_off env subs
          st1 = lower_expr env l bound_locals sp st
          st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
          st3 = lower_expr env r bound_locals (sp + 1) st2
          nc_emit st3 (NHadamard (binop_id bop) sp off (str_len subs)) (sp + 1)
      lower expr env (EIndex (EVar v) ((EInt idx):[])) _ sp st
        | (str_starts_with v ":tup-") OR (str_starts_with v ":idx-tup-") =
          nc_emit st (NTupleGet (env_var_slot env v) idx) sp
      lower expr env (EIndex (EVar v) idxs) bound_locals sp st
        | (lookup_local bound_locals v) >= 0 AND ((rexpr_list_len idxs) == 1 OR (rexpr_list_len idxs) == 2) =
          count = rexpr_list_len idxs
          vslot = env_var_slot env v
          st1 = lower_expr_list_to_slots env idxs bound_locals sp 0 st
          nc_emit st1 (NIndex vslot sp (0 - count)) (sp + count + 1)
      lower expr env (EIndex base idxs) bound_locals sp st =
        count = rexpr_list_len idxs
        st1 = lower_expr env base bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_expr_list_to_slots env idxs bound_locals (sp + 1) 0 st2
        nc_emit st3 (NIndex sp (sp + 1) count) (sp + count + 2)
      lower expr env (EIndexAssign target idxs val_e) bound_locals sp st =
        count = rexpr_list_len idxs
        tslot = env_var_slot env target
        st1 = lower_expr_list_to_slots env idxs bound_locals sp 0 st
        st2 = lower_expr env val_e bound_locals (sp + count) st1
        nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot, NCloneSlot tslot] (sp + count + 1)
      lower expr env (ESeqSelect base mask) bound_locals sp st =
        off = env_str_off env mask
        st1 = lower_expr env base bound_locals sp st
        nc_emit st1 (NSeqSelect off (str_len mask)) sp
      lower expr env (EBlock stmts) bound_locals sp st =
        lower_stmts_cmm env stmts bound_locals [] sp st
      lower expr env (EGuard guards) bound_locals sp st =
        end_lbl = nc_lbl st
        st1 = nc_set_lbl st (end_lbl + 1)
        lower_expr_guards env guards bound_locals end_lbl sp st1
      lower expr env (EWhere body binds) bound_locals sp st =
        lower_where_cmm env binds body bound_locals [] sp st
      lower expr env (EParPipe branches) bound_locals sp st
        | (rexpr_list_len branches) >= 2 AND (all_exprs_par_eval env branches bound_locals) =
          count = rexpr_list_len branches
          par_off = env_str_off env "__rg_par_eval__"
          st1 = lower_par_eval_list env branches bound_locals sp 0 st
          st2 = nc_emit_list st1 [NMakeList sp count, NStoreSlot (sp + 1), NLoadStrLit par_off 15, NStoreSlot sp, NCallBuiltin 54 sp 2, NStoreSlot sp] (sp + count + 2)
          st3 = unpack_par_list_to_slots sp count 0 st2
          nc_emit_list st3 [NClearLocals sp (sp + 1), NMakeTuple (sp + 1) count] (sp + count + 2)
        | otherwise =
          count = rexpr_list_len branches
          st1 = lower_expr_list_to_slots env branches bound_locals sp 0 st
          nc_emit st1 (NMakeTuple sp count) (sp + count + 1)
      lower expr env (EWithCtx _ val_e body) bound_locals sp st =
        st1 = lower_expr env val_e bound_locals sp st
        st2 = nc_emit_list st1 [NStoreSlot sp, NCallBuiltin 84 sp 1] (sp + 1)
        st3 = lower_expr env body bound_locals sp st2
        nc_emit_list st3 [NStoreSlot sp, NCallBuiltin 85 sp 1] (sp + 1)
      lower expr env (EWithRegion quota body) bound_locals sp st =
        st1 = nc_emit st NEnterRegion sp
        st2 = lower_expr env body bound_locals sp st1
        nc_emit st2 (NExitRegion quota) sp

fn :: lower expr guards RNativeEnv [RGuard] [String] Int Int RNativeCode => RNativeCode
      lower expr guards _ [] _ end_lbl sp st =
        nc_emit_list st [NLoadImmRaw 0, NLabel end_lbl] sp
      lower expr guards env ((GuardBranch cond body):gs) bound_locals end_lbl sp st =
        next_lbl = nc_lbl st
        st1 = nc_set_lbl st (next_lbl + 1)
        st2 = lower_expr env cond bound_locals sp st1
        st3 = nc_emit_list st2 [NAsBool, NJumpIfZero next_lbl] sp
        st4 = lower_expr env body bound_locals sp st3
        st5 = nc_emit_list st4 [NJump end_lbl, NLabel next_lbl] sp
        lower_expr_guards env gs bound_locals end_lbl sp st5

fn :: lower final block expr RNativeEnv RExpr [String] [String] Int RNativeCode => RNativeCode
      lower final block expr env (EVar v) bound_locals _ sp st
        | (lookup_local bound_locals v) >= 0 =
          nc_emit st (NMoveSlot (env_var_slot env v)) sp
      lower final block expr env e bound_locals [] sp st =
        lower_expr env e bound_locals sp st
      lower final block expr env e bound_locals dead_vars sp st =
        st1 = lower_expr env e bound_locals sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_cmm_drops env dead_vars (sp + 1) st2
        nc_emit st3 (NMoveSlot sp) (sp + 1)

fn :: lower let binding stmt RNativeEnv String RExpr [String] [String] [RStmt] Int RNativeCode => RNativeCode
      lower let binding stmt env v e bound_locals scope_vars rest sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        st1 = lower_expr env e bound_locals sp st
        st2 = lower_let_var_store env v bound_locals sp st1
        st3 = lower_cmm_drops env dead_inputs sp st2
        st4 = lower_unused_let_drop env v live_after sp st3
        lower_stmts_cmm env rest (add_unique_str v bound_locals) (add_unique_str v scope_vars) sp st4

fn :: lower stmts cmm RNativeEnv [RStmt] [String] [String] Int RNativeCode => RNativeCode
      lower stmts cmm _ [] _ _ sp st =
        nc_emit st (NLoadImmRaw 0) sp
      lower stmts cmm env ((StmtExpr e):[]) bound_locals scope_vars sp st =
        used = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        lower_final_block_expr env e bound_locals used sp st
      lower stmts cmm env ((StmtIndexAssign t idxs e):[]) bound_locals scope_vars sp st =
        count = rexpr_list_len idxs
        tslot = env_var_slot env t
        st1 = lower_expr_list_to_slots env idxs bound_locals sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        st3 = nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        st4 = lower_cmm_drops env (cmm_remove_str t scope_vars) (sp + count + 1) st3
        nc_emit st4 (NCloneSlot tslot) (sp + count + 1)
      lower stmts cmm env ((StmtLet v e):[]) bound_locals scope_vars sp st
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
      lower stmts cmm env ((StmtMut v e):[]) bound_locals scope_vars sp st =
        lower_stmts_cmm env [StmtLet v e] bound_locals scope_vars sp st
      lower stmts cmm env ((StmtLet v e):rest) bound_locals scope_vars sp st
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
      lower stmts cmm env ((StmtMut v e):rest) bound_locals scope_vars sp st =
        lower_let_binding_stmt env v e bound_locals scope_vars rest sp st
      lower stmts cmm env ((StmtIndexAssign t idxs e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e (cmm_expr_list_vars idxs [])) scope_vars
        live_after = add_unique_str t (cmm_stmts_vars rest [])
        dead_now = cmm_filter_not_in_list used_in_e live_after
        count = rexpr_list_len idxs
        tslot = env_var_slot env t
        st1 = lower_expr_list_to_slots env idxs bound_locals sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        st3 = nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        st4 = lower_cmm_drops env dead_now (sp + count + 1) st3
        lower_stmts_cmm env rest bound_locals scope_vars sp st4
      lower stmts cmm env ((StmtExpr e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        dead_now = cmm_filter_not_in_list used_in_e live_after
        st1 = lower_expr env e bound_locals sp st
        st2 = nc_emit st1 NDropVal sp
        st3 = lower_cmm_drops env dead_now sp st2
        lower_stmts_cmm env rest bound_locals scope_vars sp st3

fn :: can par eval expr RNativeEnv RExpr [String] => Bool
      can par eval expr env (ECall fname args) bound_locals =
        arity = env_fn_arity env fname
        nargs = rexpr_list_len args
        (lookup_local bound_locals fname) < 0 AND (NOT (is_upper_ident fname)) AND (builtin_call_id fname) < 0 AND (NOT (is_agent_call_name fname)) AND fname != "sys_os" AND fname != "sys_arch" AND fname != "__record_update__" AND fname != "__unpack2__" AND arity >= 0 AND arity <= 3 AND nargs == arity AND (env_fn_is_heavy env fname)
      can par eval expr _ _ _ = False

fn :: all exprs par eval RNativeEnv [RExpr] [String] => Bool
      all exprs par eval _ [] _ = True
      all exprs par eval env (e:es) bound_locals
        | can_par_eval_expr env e bound_locals = all_exprs_par_eval env es bound_locals
        | otherwise = False

fn :: lower par eval arg RNativeEnv [RExpr] [String] Int RNativeCode => RNativeCode
      lower par eval arg _ [] _ slot st =
        nc_emit_list st [NLoadImmInt 0, NStoreSlot slot] (slot + 1)
      lower par eval arg env (a1:[]) bound_locals slot st =
        st1 = lower_expr env a1 bound_locals slot st
        nc_emit st1 (NStoreSlot slot) (slot + 1)
      lower par eval arg env args bound_locals slot st =
        count = rexpr_list_len args
        st1 = lower_expr_list_to_slots env args bound_locals slot 0 st
        nc_emit_list st1 [NMakeTuple slot count, NStoreSlot slot] (slot + count + 1)

fn :: lower par eval item RNativeEnv RExpr [String] Int RNativeCode => RNativeCode
      lower par eval item env (ECall fname args) bound_locals slot st =
        off = env_str_off env fname
        st1 = nc_emit_list st [NLoadStrLit off (str_len fname), NStoreSlot slot] (slot + 1)
        st2 = lower_par_eval_arg env args bound_locals (slot + 1) st1
        nc_emit_list st2 [NMakeTuple slot 2, NStoreSlot slot] (slot + 2)
      lower par eval item _ _ _ _ st = st

fn :: lower par eval list RNativeEnv [RExpr] [String] Int Int RNativeCode => RNativeCode
      lower par eval list _ [] _ _ _ st = st
      lower par eval list env (e:es) bound_locals sp idx st =
        st1 = lower_par_eval_item env e bound_locals (sp + idx) st
        lower_par_eval_list env es bound_locals sp (idx + 1) st1

fn :: unpack par list to slots Int Int Int RNativeCode => RNativeCode
      unpack par list to slots _ count idx st
        | idx >= count = st
      unpack par list to slots list_slot count idx st =
        dst = list_slot + 1 + idx
        st1 = nc_emit_list st [NListHead list_slot, NStoreSlot dst, NListTail list_slot, NStoreSlot list_slot] (dst + 1)
        unpack_par_list_to_slots list_slot count (idx + 1) st1

fn :: can par where pair RNativeEnv RExpr String RExpr String [String] => Bool
      can par where pair env e1 v1 e2 v2 bound_locals =
        v1 != "_" AND v2 != "_" AND v1 != v2 AND (can_par_eval_expr env e1 bound_locals) AND (can_par_eval_expr env e2 bound_locals) AND (NOT (str_in_list v1 (cmm_expr_vars e2 [])))

fn :: emit par where pair RNativeEnv RExpr String RExpr String [RWhereBind] RExpr [String] [String] Int RNativeCode => RNativeCode
      emit par where pair env e1 v1 e2 v2 wbs body bound_locals scope_vars sp st =
        used_in_pair = cmm_filter_in_list (cmm_expr_vars e2 (cmm_expr_vars e1 [])) scope_vars
        live_after = cmm_where_vars wbs body []
        live_with_vs = add_unique_str v1 (add_unique_str v2 live_after)
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v1 (cmm_remove_str v2 used_in_pair)) live_with_vs
        par_off = env_str_off env "__rg_par_eval__"
        st1 = lower_par_eval_list env [e1, e2] bound_locals sp 0 st
        st2 = nc_emit_list st1 [NMakeList sp 2, NStoreSlot (sp + 1), NLoadStrLit par_off 15, NStoreSlot sp, NCallBuiltin 54 sp 2, NStoreSlot sp, NListHead sp] (sp + 4)
        st3 = lower_let_var_store env v1 bound_locals (sp + 4) st2
        st4 = nc_emit_list st3 [NListTail sp, NStoreSlot sp, NListHead sp] (sp + 4)
        locals1 = add_unique_str v1 bound_locals
        st5 = lower_let_var_store env v2 locals1 (sp + 4) st4
        st6 = nc_emit st5 (NClearLocals sp (sp + 1)) (sp + 4)
        st7 = lower_cmm_drops env dead_inputs sp st6
        st8 = lower_unused_let_drop env v1 (add_unique_str v2 live_after) sp st7
        lower_unused_let_drop env v2 live_after sp st8

fn :: lower where cmm RNativeEnv [RWhereBind] RExpr [String] [String] Int RNativeCode => RNativeCode
      lower where cmm env [] body bound_locals scope_vars sp st =
        used = cmm_filter_in_list (cmm_expr_vars body []) scope_vars
        lower_final_block_expr env body bound_locals used sp st
      lower where cmm env ((WhereBind e1 v1 []):(WhereBind e2 v2 []):wbs) body bound_locals scope_vars sp st
        | can_par_where_pair env e1 v1 e2 v2 bound_locals =
          st1 = emit_par_where_pair env e1 v1 e2 v2 wbs body bound_locals scope_vars sp st
          locals2 = add_unique_str v2 (add_unique_str v1 bound_locals)
          scope2 = add_unique_str v2 (add_unique_str v1 scope_vars)
          lower_where_cmm env wbs body locals2 scope2 sp st1
      lower where cmm env ((WhereBind e v []):wbs) body bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_where_vars wbs body []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        st1 = lower_expr env e bound_locals sp st
        st2 = lower_let_var_store env v bound_locals sp st1
        st3 = lower_cmm_drops env dead_inputs sp st2
        st4 = lower_unused_let_drop env v live_after sp st3
        lower_where_cmm env wbs body (add_unique_str v bound_locals) (add_unique_str v scope_vars) sp st4
      lower where cmm env ((WhereBind e v idxs):wbs) body bound_locals scope_vars sp st =
        count = int_list_len idxs
        tslot = env_var_slot env v
        st1 = lower_int_list_to_slots idxs sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        st3 = nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        lower_where_cmm env wbs body bound_locals scope_vars sp st3

-- ── Tail-Call Optimization (TCO) & Tail Return Lowering ─────

fn :: expr has self tail call String RExpr => Bool
      expr has self tail call target (ECall fname _) = fname == target
      expr has self tail call target (EBlock stmts) = stmts_have_self_tail_call target stmts
      expr has self tail call target (EGuard guards) = guards_have_self_tail_call target guards
      expr has self tail call target (EWhere body _) = expr_has_self_tail_call target body
      expr has self tail call _ _ = False

fn :: stmts have self tail call String [RStmt] => Bool
      stmts have self tail call _ [] = False
      stmts have self tail call target ((StmtExpr e):[]) = expr_has_self_tail_call target e
      stmts have self tail call target (_:rest) = stmts_have_self_tail_call target rest

fn :: guards have self tail call String [RGuard] => Bool
      guards have self tail call _ [] = False
      guards have self tail call target ((GuardBranch _ body):gs)
        | expr_has_self_tail_call target body = True
        | otherwise = guards_have_self_tail_call target gs

fn :: can move param var String [String] [String] [String] => Bool
      can move param var v locals scope_vars later_vars =
        ((lookup_local locals v) >= 0) AND (NOT (str_in_list v scope_vars)) AND (NOT (str_in_list v later_vars))

fn :: lower tco arg expr RNativeEnv RExpr [RExpr] [String] [String] Int RNativeCode => RNativeCode
      lower tco arg expr env (EVar v) es bound_locals scope_vars sp st
        | can_move_param_var v bound_locals scope_vars (cmm_expr_list_vars es []) =
          nc_emit st (NMoveSlot (env_var_slot env v)) sp
      lower tco arg expr env (EBin OpConcat l r) es bound_locals scope_vars sp st =
        st1 = lower_tco_arg_expr env l ([r] :: es) bound_locals scope_vars sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_tco_arg_expr env r es bound_locals scope_vars (sp + 1) st2
        nc_emit st3 (NBinOp 14 sp) (sp + 1)
      lower tco arg expr env (ETuple elems) es bound_locals scope_vars sp st =
        count = rexpr_list_len elems
        st1 = lower_tco_arg_list_to_slots env elems es bound_locals scope_vars sp 0 st
        nc_emit st1 (NMakeTuple sp count) (sp + count + 1)
      lower tco arg expr env (ECall fname args) es bound_locals scope_vars sp st
        | (lookup_local bound_locals fname) < 0 AND (NOT (is_upper_ident fname)) AND (builtin_call_id fname) < 0 AND (NOT (is_agent_call_name fname)) AND (NOT (is tensor helper name fname)) AND fname != "sys_os" AND fname != "sys_arch" AND fname != "__record_update__" AND fname != "__unpack2__" AND fname != "__chain__" AND (rexpr_list_len args) == (env_fn_arity env fname) AND (NOT ((env has field env fname) AND (env_fn_arity env fname) == 1 AND (rexpr_list_len args) > 1)) =
          count = rexpr_list_len args
          st1 = lower_tco_arg_list_to_slots env args es bound_locals scope_vars sp 0 st
          nc_emit st1 (NCallFn (env_fn_id env fname) sp count) (sp + count + 1)
      lower tco arg expr env e _ bound_locals _ sp st =
        lower_expr env e bound_locals sp st

fn :: lower tco arg list to slots RNativeEnv [RExpr] [RExpr] [String] [String] Int Int RNativeCode => RNativeCode
      lower tco arg list to slots _ [] _ _ _ _ _ st = st
      lower tco arg list to slots env (e:es) after bound_locals scope_vars sp idx st =
        cur_slot = sp + idx
        st1 = lower_tco_arg_expr env e (es :: after) bound_locals scope_vars cur_slot st
        st2 = nc_emit st1 (NStoreSlot cur_slot) (cur_slot + 1)
        lower_tco_arg_list_to_slots env es after bound_locals scope_vars sp (idx + 1) st2

fn :: lower tail return RNativeEnv RExpr [String] Int RNativeCode => RNativeCode
      lower tail return env expr bound_locals sp st =
        lower_tail_return_cmm env expr bound_locals [] sp st

fn :: lower tail return cmm RNativeEnv RExpr [String] [String] Int RNativeCode => RNativeCode
      lower tail return cmm env (ECall fname args) bound_locals scope_vars sp st
        | fname == (env_fn_name env) AND (rexpr_list_len args) == (env_arity env) AND (lookup_local bound_locals fname) < 0 =
          arity = env_arity env
          st1 = lower_tco_arg_list_to_slots env args [] bound_locals scope_vars sp 0 st
          st2 = lower_cmm_drops env scope_vars (sp + arity + 1) st1
          nc_emit st2 (NTailCall sp arity) (sp + arity + 1)
      lower tail return cmm env (EBlock stmts) bound_locals scope_vars sp st =
        lower_tail_stmts_cmm env stmts bound_locals scope_vars sp st
      lower tail return cmm env (EGuard guards) bound_locals scope_vars sp st
        | guards_have_self_tail_call (env_fn_name env) guards =
          lower_tail_guards_cmm env guards bound_locals scope_vars sp st
      lower tail return cmm env (EWhere body binds) bound_locals scope_vars sp st =
        lower_tail_where_cmm env binds body bound_locals scope_vars sp st
      lower tail return cmm env (EVar v) bound_locals _ sp st
        | (lookup_local bound_locals v) >= 0 =
          nc_emit_list st [NMoveSlot (env_var_slot env v), NReturn] sp
      lower tail return cmm env expr bound_locals scope_vars sp st =
        used = cmm_filter_in_list (cmm_expr_vars expr []) scope_vars
        lower_tail_return_expr env expr bound_locals scope_vars used sp st

fn :: lower tail return expr RNativeEnv RExpr [String] [String] [String] Int RNativeCode => RNativeCode
      lower tail return expr env expr bound_locals scope_vars [] sp st =
        st1 = lower_tco_arg_expr env expr [] bound_locals scope_vars sp st
        nc_emit st1 NReturn sp
      lower tail return expr env expr bound_locals scope_vars used sp st =
        st1 = lower_tco_arg_expr env expr [] bound_locals scope_vars sp st
        st2 = nc_emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower_cmm_drops env used (sp + 1) st2
        nc_emit_list st3 [NMoveSlot sp, NReturn] (sp + 1)

fn :: lower tail guards cmm RNativeEnv [RGuard] [String] [String] Int RNativeCode => RNativeCode
      lower tail guards cmm env [] _ scope_vars sp st =
        st1 = lower_cmm_drops env scope_vars sp st
        nc_emit_list st1 [NLoadImmRaw 0, NReturn] sp
      lower tail guards cmm env ((GuardBranch cond body):gs) bound_locals scope_vars sp st =
        next_lbl = nc_lbl st
        st1 = nc_set_lbl st (next_lbl + 1)
        st2 = lower_expr env cond bound_locals sp st1
        st3 = nc_emit_list st2 [NAsBool, NJumpIfZero next_lbl] sp
        st4 = lower_tail_return_cmm env body bound_locals scope_vars sp st3
        st5 = nc_emit st4 (NLabel next_lbl) sp
        lower_tail_guards_cmm env gs bound_locals scope_vars sp st5

fn :: lower tail let stmt RNativeEnv String RExpr [String] [String] [RStmt] Int RNativeCode => RNativeCode
      lower tail let stmt env v e bound_locals scope_vars rest sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        st1 = lower_expr env e bound_locals sp st
        st2 = lower_let_var_store env v bound_locals sp st1
        st3 = lower_cmm_drops env dead_inputs sp st2
        st4 = lower_unused_let_drop env v live_after sp st3
        lower_tail_stmts_cmm env rest (add_unique_str v bound_locals) (add_unique_str v scope_vars) sp st4

fn :: lower tail stmts cmm RNativeEnv [RStmt] [String] [String] Int RNativeCode => RNativeCode
      lower tail stmts cmm _ [] _ _ sp st =
        nc_emit_list st [NLoadImmRaw 0, NReturn] sp
      lower tail stmts cmm env ((StmtExpr e):[]) bound_locals scope_vars sp st =
        lower_tail_return_cmm env e bound_locals scope_vars sp st
      lower tail stmts cmm env ((StmtLet v e):rest) bound_locals scope_vars sp st
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
      lower tail stmts cmm env ((StmtMut v e):rest) bound_locals scope_vars sp st =
        lower_tail_let_stmt env v e bound_locals scope_vars rest sp st
      lower tail stmts cmm env ((StmtIndexAssign t idxs e):[]) bound_locals scope_vars sp st =
        count = rexpr_list_len idxs
        tslot = env_var_slot env t
        st1 = lower_expr_list_to_slots env idxs bound_locals sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        st3 = nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        st4 = lower_cmm_drops env (cmm_remove_str t scope_vars) (sp + count + 1) st3
        nc_emit_list st4 [NMoveSlot tslot, NReturn] (sp + count + 1)
      lower tail stmts cmm env ((StmtIndexAssign t idxs e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e (cmm_expr_list_vars idxs [])) scope_vars
        live_after = add_unique_str t (cmm_stmts_vars rest [])
        dead_now = cmm_filter_not_in_list used_in_e live_after
        count = rexpr_list_len idxs
        tslot = env_var_slot env t
        st1 = lower_expr_list_to_slots env idxs bound_locals sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        st3 = nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        st4 = lower_cmm_drops env dead_now (sp + count + 1) st3
        lower_tail_stmts_cmm env rest bound_locals scope_vars sp st4
      lower tail stmts cmm env ((StmtExpr e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_stmts_vars rest []
        dead_now = cmm_filter_not_in_list used_in_e live_after
        st1 = lower_expr env e bound_locals sp st
        st2 = nc_emit st1 NDropVal sp
        st3 = lower_cmm_drops env dead_now sp st2
        lower_tail_stmts_cmm env rest bound_locals scope_vars sp st3

fn :: lower tail where cmm RNativeEnv [RWhereBind] RExpr [String] [String] Int RNativeCode => RNativeCode
      lower tail where cmm env [] body bound_locals scope_vars sp st =
        lower_tail_return_cmm env body bound_locals scope_vars sp st
      lower tail where cmm env ((WhereBind e1 v1 []):(WhereBind e2 v2 []):wbs) body bound_locals scope_vars sp st
        | can_par_where_pair env e1 v1 e2 v2 bound_locals =
          st1 = emit_par_where_pair env e1 v1 e2 v2 wbs body bound_locals scope_vars sp st
          locals2 = add_unique_str v2 (add_unique_str v1 bound_locals)
          scope2 = add_unique_str v2 (add_unique_str v1 scope_vars)
          lower_tail_where_cmm env wbs body locals2 scope2 sp st1
      lower tail where cmm env ((WhereBind e v []):wbs) body bound_locals scope_vars sp st =
        used_in_e = cmm_filter_in_list (cmm_expr_vars e []) scope_vars
        live_after = cmm_where_vars wbs body []
        live_with_v = add_unique_str v live_after
        dead_inputs = cmm_filter_not_in_list (cmm_remove_str v used_in_e) live_with_v
        st1 = lower_expr env e bound_locals sp st
        st2 = lower_let_var_store env v bound_locals sp st1
        st3 = lower_cmm_drops env dead_inputs sp st2
        st4 = lower_unused_let_drop env v live_after sp st3
        lower_tail_where_cmm env wbs body (add_unique_str v bound_locals) (add_unique_str v scope_vars) sp st4
      lower tail where cmm env ((WhereBind e v idxs):wbs) body bound_locals scope_vars sp st =
        count = int_list_len idxs
        tslot = env_var_slot env v
        st1 = lower_int_list_to_slots idxs sp 0 st
        st2 = lower_expr env e bound_locals (sp + count) st1
        st3 = nc_emit_list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        lower_tail_where_cmm env wbs body bound_locals scope_vars sp st3

-- ── Pattern Matching & Binding Lowering ──────────────────────

fn :: pat needs check RPattern       => Bool
      pat needs check PatWild        =  False
      pat needs check (PatVar _)     =  False
      pat needs check (PatSeqBind _) =  False
      pat needs check _              =  True

fn :: pat has vars RPattern         => Bool
      pat has vars (PatVar _)       =  True
      pat has vars (PatSeqBind _)   =  True
      pat has vars (PatCons h t)    =  (pat_has_vars h) OR (pat_has_vars t)
      pat has vars (PatTuple ps)    =  pat_list_has_vars ps
      pat has vars (PatCtor _ args) =  pat_list_has_vars args
      pat has vars _                =  False

fn :: pat list has vars [RPattern] => Bool
      pat list has vars []         =  False
      pat list has vars (p:ps)
        | pat_has_vars p = True
        | otherwise = pat_list_has_vars ps

fn :: lower pat cond RNativeEnv RPattern Int Int Int RNativeCode => RNativeCode
      lower pat cond _ PatWild _ _ _ st = st
      lower pat cond _ (PatVar _) _ _ _ st = st
      lower pat cond _ (PatSeqBind _) _ _ _ st = st
      lower pat cond _ (PatInt n) slot fail_lbl sp st =
        nc_emit_list st [NMatchInt slot n, NJumpIfZero fail_lbl] sp
      lower pat cond env (PatReal r) slot fail_lbl sp st =
        off = env_str_off env r
        nc_emit_list st [NMatchReal slot off (str_len r), NJumpIfZero fail_lbl] sp
      lower pat cond env (PatStr s) slot fail_lbl sp st =
        off = env_str_off env s
        nc_emit_list st [NMatchStr slot off (str_len s), NJumpIfZero fail_lbl] sp
      lower pat cond _ (PatBool True) slot fail_lbl sp st =
        nc_emit_list st [NMatchBool slot 1, NJumpIfZero fail_lbl] sp
      lower pat cond _ (PatBool False) slot fail_lbl sp st =
        nc_emit_list st [NMatchBool slot 0, NJumpIfZero fail_lbl] sp
      lower pat cond _ PatEmpty slot fail_lbl sp st =
        nc_emit_list st [NMatchEmpty slot, NJumpIfZero fail_lbl] sp
      lower pat cond env (PatCons h t) slot fail_lbl sp st =
        st1 = nc_emit_list st [NMatchNonEmpty slot, NJumpIfZero fail_lbl] sp
        st2 = lower_pat_cons_sub env h slot True fail_lbl sp st1
        lower_pat_cons_sub env t slot False fail_lbl sp st2
      lower pat cond env (PatTuple ps) slot fail_lbl sp st =
        arity = pat_list_len ps
        st1 = nc_emit_list st [NMatchTuple slot arity, NJumpIfZero fail_lbl] sp
        lower_tuple_pat_conds env ps slot 0 fail_lbl sp st1
      lower pat cond env (PatCtor ":tensor-pat:" (t_pat:rank_pat:dim_pats)) slot fail_lbl sp st =
        st1 = nc emit list st [NMatchAdt slot 0 0 (0 - 5), NJumpIfZero fail_lbl] sp
        st2 = lower pat cond env t_pat slot fail_lbl sp st1
        st3 = lower tensor dim cond env rank_pat slot (0 - 1) fail_lbl sp st2
        lower tensor dims cond list env dim_pats slot 0 fail_lbl sp st3
      lower pat cond env (PatCtor c (sub_p:[])) slot fail_lbl sp st
        | (prim_type_tag_id c) > 0 =
          st1 = nc_emit_list st [NMatchAdt slot 0 0 (0 - (prim_type_tag_id c)), NJumpIfZero fail_lbl] sp
          lower_pat_cond env sub_p slot fail_lbl sp st1
      lower pat cond env (PatCtor c args) slot fail_lbl sp st =
        arity = pat_list_len args
        c_tag = ident_base_name c
        off = env_str_off env c_tag
        st1 = nc_emit_list st [NMatchAdt slot off (str_len c_tag) arity, NJumpIfZero fail_lbl] sp
        lower_adt_pat_conds env args slot 0 fail_lbl sp st1

fn :: lower tensor dim cond RNativeEnv RPattern Int Int Int Int RNativeCode => RNativeCode
      lower tensor dim cond env p slot field_code fail_lbl sp st
        | not (pat needs check p) = st
        | otherwise =
          st1 = nc emit list st [NAdtField slot field_code, NStoreSlot sp] (sp + 1)
          st2 = lower pat cond env p sp fail_lbl (sp + 1) st1
          nc emit st2 (NClearLocals sp (sp + 1)) (sp + 1)

fn :: lower tensor dims cond list RNativeEnv [RPattern] Int Int Int Int RNativeCode => RNativeCode
      lower tensor dims cond list _ [] _ _ _ _ st = st
      lower tensor dims cond list env (p:ps) slot idx fail_lbl sp st =
        st1 = lower tensor dim cond env p slot ((0 - 10) - idx) fail_lbl sp st
        lower tensor dims cond list env ps slot (idx + 1) fail_lbl sp st1

fn :: lower pat cons sub RNativeEnv RPattern Int Bool Int Int RNativeCode => RNativeCode
      lower pat cons sub env sub_p slot is_head fail_lbl sp st
        | NOT (pat_needs_check sub_p) = st
        | is_head =
          st1 = nc_emit_list st [NListHead slot, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_cond env sub_p sp fail_lbl (sp + 1) st1
          nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
        | otherwise =
          st1 = nc_emit_list st [NListTail slot, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_cond env sub_p sp fail_lbl (sp + 1) st1
          nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)

fn :: lower tuple pat conds RNativeEnv [RPattern] Int Int Int Int RNativeCode => RNativeCode
      lower tuple pat conds _ [] _ _ _ _ st = st
      lower tuple pat conds env (p:ps) slot idx fail_lbl sp st
        | NOT (pat_needs_check p) = lower_tuple_pat_conds env ps slot (idx + 1) fail_lbl sp st
        | otherwise =
          st1 = nc_emit_list st [NTupleGet slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_cond env p sp fail_lbl (sp + 1) st1
          st3 = nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower_tuple_pat_conds env ps slot (idx + 1) fail_lbl sp st3

fn :: lower adt pat conds RNativeEnv [RPattern] Int Int Int Int RNativeCode => RNativeCode
      lower adt pat conds _ [] _ _ _ _ st = st
      lower adt pat conds env (p:ps) slot idx fail_lbl sp st
        | NOT (pat_needs_check p) = lower_adt_pat_conds env ps slot (idx + 1) fail_lbl sp st
        | otherwise =
          st1 = nc_emit_list st [NAdtField slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_cond env p sp fail_lbl (sp + 1) st1
          st3 = nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower_adt_pat_conds env ps slot (idx + 1) fail_lbl sp st3

fn :: lower pat list cond RNativeEnv [RPattern] Int Int Int RNativeCode => RNativeCode
      lower pat list cond _ [] _ _ _ st = st
      lower pat list cond env (p:ps) idx fail_lbl sp st =
        st1 = lower_pat_cond env p idx fail_lbl sp st
        lower_pat_list_cond env ps (idx + 1) fail_lbl sp st1

fn :: lower pat binds RNativeEnv RPattern Int Bool Int RNativeCode => RNativeCode
      lower pat binds env (PatVar v) slot True sp st =
        nc_emit_list st [NMoveSlot slot, NStoreSlot (env_var_slot env v)] sp
      lower pat binds env (PatVar v) slot False sp st =
        nc_emit_list st [NCloneSlot slot, NStoreSlot (env_var_slot env v)] sp
      lower pat binds env (PatSeqBind v) slot True sp st =
        nc_emit_list st [NMoveSlot slot, NStoreSlot (env_var_slot env v)] sp
      lower pat binds env (PatSeqBind v) slot False sp st =
        nc_emit_list st [NCloneSlot slot, NStoreSlot (env_var_slot env v)] sp
      lower pat binds env (PatCons h t) slot _ sp st =
        st1 = lower_pat_cons_bind env h slot True sp st
        lower_pat_cons_bind env t slot False sp st1
      lower pat binds env (PatTuple ps) slot _ sp st =
        lower_tuple_pat_binds env ps slot 0 sp st
      lower pat binds env (PatCtor ":tensor-pat:" (t_pat:rank_pat:dim_pats)) slot move_ok sp st =
        st1 = lower tensor dim bind env rank_pat slot (0 - 1) sp st
        st2 = lower tensor dims bind list env dim_pats slot 0 sp st1
        lower pat binds env t_pat slot move_ok sp st2
      lower pat binds env (PatCtor c (sub_p:[])) slot move_ok sp st
        | (prim_type_tag_id c) > 0 =
          lower_pat_binds env sub_p slot move_ok sp st
      lower pat binds env (PatCtor _ args) slot _ sp st =
        lower_adt_pat_binds env args slot 0 sp st
      lower pat binds _ _ _ _ _ st = st

fn :: lower tensor dim bind RNativeEnv RPattern Int Int Int RNativeCode => RNativeCode
      lower tensor dim bind env p slot field_code sp st
        | not (pat has vars p) = st
        | otherwise =
          st1 = nc emit list st [NAdtField slot field_code, NStoreSlot sp] (sp + 1)
          st2 = lower pat binds env p sp True (sp + 1) st1
          nc emit st2 (NClearLocals sp (sp + 1)) (sp + 1)

fn :: lower tensor dims bind list RNativeEnv [RPattern] Int Int Int RNativeCode => RNativeCode
      lower tensor dims bind list _ [] _ _ _ st = st
      lower tensor dims bind list env (p:ps) slot idx sp st =
        st1 = lower tensor dim bind env p slot ((0 - 10) - idx) sp st
        lower tensor dims bind list env ps slot (idx + 1) sp st1

fn :: lower pat cons bind RNativeEnv RPattern Int Bool Int RNativeCode => RNativeCode
      lower pat cons bind env sub_p slot is_head sp st
        | NOT (pat_has_vars sub_p) = st
        | is_head =
          st1 = nc_emit_list st [NListHead slot, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_binds env sub_p sp True (sp + 1) st1
          nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
        | otherwise =
          st1 = nc_emit_list st [NListTail slot, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_binds env sub_p sp True (sp + 1) st1
          nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)

fn :: lower tuple pat binds RNativeEnv [RPattern] Int Int Int RNativeCode => RNativeCode
      lower tuple pat binds _ [] _ _ _ st = st
      lower tuple pat binds env (p:ps) slot idx sp st
        | NOT (pat_has_vars p) = lower_tuple_pat_binds env ps slot (idx + 1) sp st
        | otherwise =
          st1 = nc_emit_list st [NTupleGet slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_binds env p sp True (sp + 1) st1
          st3 = nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower_tuple_pat_binds env ps slot (idx + 1) sp st3

fn :: lower adt pat binds RNativeEnv [RPattern] Int Int Int RNativeCode => RNativeCode
      lower adt pat binds _ [] _ _ _ st = st
      lower adt pat binds env (p:ps) slot idx sp st
        | NOT (pat_has_vars p) = lower_adt_pat_binds env ps slot (idx + 1) sp st
        | otherwise =
          st1 = nc_emit_list st [NAdtField slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower_pat_binds env p sp True (sp + 1) st1
          st3 = nc_emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower_adt_pat_binds env ps slot (idx + 1) sp st3

fn :: lower pat list binds RNativeEnv [RPattern] Int Int Bool Int RNativeCode => RNativeCode
      lower pat list binds _ [] _ _ _ _ st = st
      lower pat list binds env ((PatSeqBind v):[]) _ arity _ sp st =
        nc_emit_list st [NPackSeq arity, NStoreSlot (env_var_slot env v)] sp
      lower pat list binds env ((PatVar v):ps) idx arity True sp st =
        st1 = nc_emit_list st [NMoveSlot idx, NStoreSlot (env_var_slot env v)] sp
        lower_pat_list_binds env ps (idx + 1) arity True sp st1
      lower pat list binds env (p:ps) idx arity move_args sp st =
        st1 = lower_pat_binds env p idx False sp st
        lower_pat_list_binds env ps (idx + 1) arity move_args sp st1

fn :: guards have otherwise [RGuard] => Bool
      guards have otherwise []       =  False
      guards have otherwise ((GuardBranch (EBool True) _):_) = True
      guards have otherwise (_:gs)   =  guards_have_otherwise gs

fn :: lower case guards RNativeEnv [RGuard] [String] Int RNativeCode => RNativeCode
      lower case guards _ [] _ _ st = st
      lower case guards env ((GuardBranch cond body):gs) bound_locals sp st =
        next_lbl = nc_lbl st
        st1 = nc_set_lbl st (next_lbl + 1)
        st2 = lower_expr env cond bound_locals sp st1
        st3 = nc_emit_list st2 [NAsBool, NJumpIfZero next_lbl] sp
        st4 = lower_tail_return env body bound_locals sp st3
        st5 = nc_emit st4 (NLabel next_lbl) sp
        lower_case_guards env gs bound_locals sp st5

fn :: lower single case RNativeEnv RFnCase Bool Int RNativeCode => RNativeCode
      lower single case env (FnCase pats [] body) _ sp st =
        arity = env_arity env
        fail_lbl = nc_lbl st
        st1 = nc_set_lbl st (fail_lbl + 1)
        st2 = lower_pat_list_cond env pats 0 fail_lbl sp st1
        st3 = lower_pat_list_binds env pats 0 arity True sp st2
        bound_locals = collect_pat_list_vars pats []
        st4 = lower_tail_return env body bound_locals sp st3
        nc_emit_list st4 [NLabel fail_lbl, NClearLocals arity (nc_max_sp st4)] sp
      lower single case env (FnCase pats guards _) is_last sp st =
        arity = env_arity env
        fail_lbl = nc_lbl st
        st1 = nc_set_lbl st (fail_lbl + 1)
        st2 = lower_pat_list_cond env pats 0 fail_lbl sp st1
        move_args = is_last OR (guards_have_otherwise guards)
        st3 = lower_pat_list_binds env pats 0 arity move_args sp st2
        bound_locals = collect_pat_list_vars pats []
        st4 = lower_case_guards env guards bound_locals sp st3
        nc_emit_list st4 [NLabel fail_lbl, NClearLocals arity (nc_max_sp st4)] sp

fn :: lower cases list RNativeEnv [RFnCase] Int RNativeCode => RNativeCode
      lower cases list _ [] _ st = st
      lower cases list env (c:[]) sp st = lower_single_case env c True sp st
      lower cases list env (c:cs) sp st =
        st1 = lower_single_case env c False sp st
        lower_cases_list env cs sp st1

fn :: lower fndef RFnDef [RStrEntry] [RFnEntry] [RFieldEntry] => RNativeFn
      lower fndef (FnDef name params _ cases) str_tbl fn_tbl field_tbl =
        fid = lookup_fn_id fn_tbl name
        arity = infer_fndef_arity params cases
        all_locals = collect_cases_all_locals cases []
        base_sp = arity + (list_str_len all_locals)
        env = NativeEnv name arity all_locals str_tbl fn_tbl field_tbl
        init_st = NativeCode [] 1 (max_int (base_sp + 1) 2)
        st1 = lower_cases_list env cases base_sp init_st
        st2 = nc_emit_list st1 [NLoadImmRaw 0, NReturn] (base_sp + 1)
        NativeFn fid name arity (nc_max_sp st2) (nc_instrs st2)

fn :: lower fndef list [RFnDef] [RStrEntry] [RFnEntry] [RFieldEntry] => [RNativeFn]
      lower fndef list [] _ _ _ = []
      lower fndef list (f:fs) str_tbl fn_tbl field_tbl =
        [lower_fndef f str_tbl fn_tbl field_tbl] :: (lower_fndef_list fs str_tbl fn_tbl field_tbl)

fn :: lower field getter fns [RFieldEntry] [String] [RFnEntry] => [RNativeFn]
      lower field getter fns [] _ _ = []
      lower field getter fns ((FieldEntry fname idx):rest) fn_names fn_tbl
        | str_in_list fname fn_names = lower_field_getter_fns rest fn_names fn_tbl
        | otherwise =
          fid = lookup_fn_id fn_tbl fname
          [NativeFn fid fname 1 2 [NAdtField 0 idx, NReturn]] :: (lower_field_getter_fns rest fn_names fn_tbl)

-- ── Call-Graph Tree-Shaking & Dispatch Function Synthesis ────

fn :: collect refs expr RExpr              [String] => [String]
      collect refs expr (EVar name)        acc      =  add_unique_str name acc
      collect refs expr (ENot inner)       acc      =  collect_refs_expr inner acc
      collect refs expr (EOut inner)       acc      =  collect_refs_expr inner acc
      collect refs expr (EBin bop l r)     acc      =  collect_refs_expr r (collect_refs_expr l (add_unique_str (binop_op_tag bop) acc))
      collect refs expr (ECall fname args) acc      =  collect_refs_expr_list args (add_unique_str fname acc)
      collect refs expr (EEcho args)       acc      =  collect_refs_expr_list args acc
      collect refs expr (EStrInterp parts) acc      =  collect_refs_expr_list parts acc
      collect refs expr (EList elems)      acc      =  collect_refs_expr_list elems acc
      collect refs expr (ETuple elems)     acc      =  collect_refs_expr_list elems acc
      collect refs expr (ETensor elems)    acc      =  collect_refs_expr_list elems acc
      collect refs expr (EEinsum es _)     acc      =  collect_refs_expr_list es acc
      collect refs expr (EHadamard _ l _ r _) acc   =  collect_refs_expr r (collect_refs_expr l acc)
      collect refs expr (EIndex base idxs) acc      =  collect_refs_expr_list idxs (collect_refs_expr base acc)
      collect refs expr (EIndexAssign _ idxs v) acc =  collect_refs_expr v (collect_refs_expr_list idxs acc)
      collect refs expr (ESeqSelect b _)   acc      =  collect_refs_expr b acc
      collect refs expr (EBlock stmts)     acc      =  collect_refs_stmts stmts acc
      collect refs expr (EGuard guards)    acc      =  collect_refs_guards guards acc
      collect refs expr (EWhere body binds) acc     =  collect_refs_where binds (collect_refs_expr body acc)
      collect refs expr (EParPipe branches) acc     =  collect_refs_expr_list branches acc
      collect refs expr (EWithCtx _ v b)   acc      =  collect_refs_expr b (collect_refs_expr v acc)
      collect refs expr (EWithRegion _ b)  acc      =  collect_refs_expr b acc
      collect refs expr _                  acc      =  acc

fn :: collect refs expr list [RExpr] [String] => [String]
      collect refs expr list [] acc = acc
      collect refs expr list (e:es) acc = collect_refs_expr_list es (collect_refs_expr e acc)

fn :: collect refs stmts [RStmt]            [String] => [String]
      collect refs stmts []                 acc      =  acc
      collect refs stmts ((StmtLet _ e):ss) acc      =  collect_refs_stmts ss (collect_refs_expr e acc)
      collect refs stmts ((StmtMut _ e):ss) acc      =  collect_refs_stmts ss (collect_refs_expr e acc)
      collect refs stmts ((StmtExpr e):ss)  acc      =  collect_refs_stmts ss (collect_refs_expr e acc)
      collect refs stmts ((StmtIndexAssign _ idxs e):ss) acc =
        collect_refs_stmts ss (collect_refs_expr e (collect_refs_expr_list idxs acc))

fn :: collect refs where [RWhereBind] [String] => [String]
      collect refs where []           acc      =  acc
      collect refs where ((WhereBind e _ _):wbs) acc = collect_refs_where wbs (collect_refs_expr e acc)

fn :: collect refs guards [RGuard] [String] => [String]
      collect refs guards []       acc      =  acc
      collect refs guards ((GuardBranch c b):gs) acc =
        collect_refs_guards gs (collect_refs_expr b (collect_refs_expr c acc))

fn :: collect refs cases [RFnCase] [String] => [String]
      collect refs cases []        acc      =  acc
      collect refs cases ((FnCase _ guards body):cs) acc =
        collect_refs_cases cs (collect_refs_expr body (collect_refs_guards guards acc))

fn :: find fndef cases [RFnDef] String => [RFnCase]
      find fndef cases []       _      =  []
      find fndef cases ((FnDef name _ _ cases):fs) target
        | name == target = cases
        | otherwise = find_fndef_cases fs target

fn :: expand reachable worklist [String] [RFnDef] [String] => [String]
expand reachable worklist []       _        visited  =  visited
expand reachable worklist (w:ws)   all_fns  visited
| str_in_list w visited = expand_reachable_worklist ws all_fns visited
        | otherwise = expand_reachable_worklist (ws :: (collect_refs_cases (find_fndef_cases all_fns w) [])) all_fns (visited :: [w])

fn :: filter reachable fndefs [RFnDef] [String]  => [RFnDef]
      filter reachable fndefs []       _         =  []
      filter reachable fndefs ((FnDef name params ret cases):fs) reachable
        | str_in_list name reachable = [FnDef name params ret cases] :: (filter_reachable_fndefs fs reachable)
        | otherwise = filter_reachable_fndefs fs reachable

fn :: collect fn names [RFnDef] => [String]
      collect fn names []       =  []
      collect fn names ((FnDef name _ _ _):fs) = [name] :: (collect_fn_names fs)

fn :: find entry fn name [RFnDef] String => String
      find entry fn name [] fallback = fallback
      find entry fn name ((FnDef name params _ cases):fs) fallback
        | name == "main" = "main"
        | name == "demo_all" = "demo_all"
        | (infer_fndef_arity params cases) == 0 = find_entry_fn_name fs name
        | otherwise = find_entry_fn_name fs fallback

fn :: build spawn dispatch entry [RFnEntry] [RStrEntry] => [RNativeInstr]
      build spawn dispatch entry fn_tbl str_tbl =
        par_off = lookup_str_off str_tbl "__rg_par_eval__"
        par_hdr = [NMatchStr 0 par_off 15, NJumpIfZero 1, NTupleGet 1 0, NStoreSlot 2, NTupleGet 1 1, NStoreSlot 1, NMoveSlot 2, NStoreSlot 0, NLabel 1]
        build_spawn_dispatch_instrs fn_tbl str_tbl 2 par_hdr

fn :: build spawn dispatch instrs [RFnEntry] [RStrEntry] Int [RNativeInstr] => [RNativeInstr]
      build spawn dispatch instrs [] _ _ acc =
        acc :: [NLoadImmRaw 0, NReturn]
      build spawn dispatch instrs ((FnEntry name fid arity):rest) str_tbl lbl acc
        | arity == 0 =
          off = lookup_str_off str_tbl name
          arm = [NMatchStr 0 off (str_len name), NJumpIfZero lbl, NCallFn fid 2 0, NReturn, NLabel lbl]
          build_spawn_dispatch_instrs rest str_tbl (lbl + 1) (acc :: arm)
        | arity == 1 =
          off = lookup_str_off str_tbl name
          arm = [NMatchStr 0 off (str_len name), NJumpIfZero lbl, NMoveSlot 1, NStoreSlot 2, NCallFn fid 2 1, NReturn, NLabel lbl]
          build_spawn_dispatch_instrs rest str_tbl (lbl + 1) (acc :: arm)
        | arity == 2 =
          off = lookup_str_off str_tbl name
          arm = [NMatchStr 0 off (str_len name), NJumpIfZero lbl, NTupleGet 1 0, NStoreSlot 2, NTupleGet 1 1, NStoreSlot 3, NCallFn fid 2 2, NReturn, NLabel lbl]
          build_spawn_dispatch_instrs rest str_tbl (lbl + 1) (acc :: arm)
        | arity == 3 =
          off = lookup_str_off str_tbl name
          lbl2 = lbl + 1
          arm = [NMatchStr 0 off (str_len name), NJumpIfZero lbl2, NMatchTuple 1 2, NJumpIfZero lbl, NTupleGet 1 0, NStoreSlot 2, NTupleGet 1 1, NStoreSlot 5, NTupleGet 5 0, NStoreSlot 3, NTupleGet 5 1, NStoreSlot 4, NCallFn fid 2 3, NReturn, NLabel lbl, NTupleGet 1 0, NStoreSlot 2, NTupleGet 1 1, NStoreSlot 3, NTupleGet 1 2, NStoreSlot 4, NCallFn fid 2 3, NReturn, NLabel lbl2]
          build_spawn_dispatch_instrs rest str_tbl (lbl + 2) (acc :: arm)
        | otherwise =
          build_spawn_dispatch_instrs rest str_tbl lbl acc

fn :: highest entry arity [RFnEntry] => Int
      highest entry arity []         =  0
      highest entry arity ((FnEntry _ _ arity):rest) =
        max_int arity (highest entry arity rest)

fn :: build call2 unpack tuple Int Int => [RNativeInstr]
      build call2 unpack tuple idx count
        | idx >= count = []
        | otherwise =
          [NTupleGet 2 idx, NStoreSlot (4 + idx)] :: (build call2 unpack tuple (idx + 1) count)

fn :: build call2 unpack list Int Int => [RNativeInstr]
      build call2 unpack list idx count
        | idx >= count = []
        | otherwise =
          [NListHead 2, NStoreSlot (4 + idx), NListTail 2, NStoreSlot 2] :: (build call2 unpack list (idx + 1) count)

fn :: build call2 dispatch instrs [RFnEntry] [RStrEntry] Int [RNativeInstr] => [RNativeInstr]
      build call2 dispatch instrs [] _ _ acc =
        acc :: [NLoadImmRaw 0, NReturn]
      build call2 dispatch instrs ((FnEntry name fid arity):rest) str_tbl lbl acc
        | arity == 2 =
          off = lookup_str_off str_tbl name
          lbl_plain = lbl + 1
          lbl_next = lbl + 2
          arm = [NMatchStr 0 off (str_len name), NJumpIfZero lbl_next, NMoveSlot 1, NStoreSlot 3, NMatchNonEmpty 2, NJumpIfZero lbl_plain, NListHead 2, NStoreSlot 4, NJump lbl, NLabel lbl_plain, NMoveSlot 2, NStoreSlot 4, NLabel lbl, NCallFn fid 3 2, NReturn, NLabel lbl_next]
          build_call2_dispatch_instrs rest str_tbl (lbl + 3) (acc :: arm)
        | arity >= 3 =
          off = lookup_str_off str_tbl name
          lbl_tuple = lbl + 1
          lbl_next = lbl + 2
          unpack_list = build call2 unpack list 0 (arity - 1)
          unpack_tup = build call2 unpack tuple 0 (arity - 1)
          arm = [NMatchStr 0 off (str_len name), NJumpIfZero lbl_next, NMoveSlot 1, NStoreSlot 3, NMatchNonEmpty 2, NJumpIfZero lbl_tuple] :: unpack_list :: [NJump lbl, NLabel lbl_tuple] :: unpack_tup :: [NLabel lbl, NCallFn fid 3 arity, NReturn, NLabel lbl_next]
          build_call2_dispatch_instrs rest str_tbl (lbl + 3) (acc :: arm)
        | otherwise =
          build_call2_dispatch_instrs rest str_tbl lbl acc

fn :: is overloadable binop name String => Bool
      is overloadable binop name "+"    =  True
      is overloadable binop name "-"    =  True
      is overloadable binop name "*"    =  True
      is overloadable binop name "/"    =  True
      is overloadable binop name "%"    =  True
      is overloadable binop name _      =  False

fn :: build binop dispatch instrs [RFnEntry] [RStrEntry] Int [RNativeInstr] => [RNativeInstr]
      build binop dispatch instrs [] _ _ acc =
        acc :: [NLoadImmRaw 0, NReturn]
      build binop dispatch instrs ((FnEntry name fid arity):rest) str_tbl lbl acc
        | arity == 2 AND (is_overloadable_binop_name name) =
          off = lookup_str_off str_tbl name
          arm = [NMatchStr 0 off (str_len name), NJumpIfZero lbl, NMoveSlot 1, NStoreSlot 3, NMoveSlot 2, NStoreSlot 4, NCallFn fid 3 2, NReturn, NLabel lbl]
          build_binop_dispatch_instrs rest str_tbl (lbl + 1) (acc :: arm)
        | otherwise =
          build_binop_dispatch_instrs rest str_tbl lbl acc

fn :: lower program to native RProgram => RNativeProg
      lower program to native (Program raw_fns tys) =
        field_tbl = collect_typedef_fields tys []
        raw_fn_names = collect_fn_names raw_fns
        sigs = (build_cg_sigs raw_fns) :: (build_field_cg_sigs field_tbl raw_fn_names)
        all_fns = opt fndef list (prep_fndef_list raw_fns sigs)
        entry_name = find_entry_fn_name all_fns "main"
        reachable = expand_reachable_worklist [entry_name] all_fns []
        fns = filter_reachable_fndefs all_fns reachable
        fn_names = collect_fn_names fns
        str_pool = build_str_pool fns (collect_field_names field_tbl)
        rodata_str = pool_rodata str_pool
        str_tbl = pool_entries str_pool
        fn_tbl1 = build_fn_table_fndefs fns 5 []
        fn_tbl2 = build_fn_table_fields field_tbl fn_names (5 + (list_str_len fn_names)) fn_tbl1
        fn_tbl = attach_heavy_fn_entries fns fn_names fn_tbl2
        entry_fid = lookup_fn_id fn_tbl entry_name
        main_wrapper = NativeFn 1 "__rg_entry_main" 0 2 [NCallFn entry_fid 0 0, NReturn]
        spawn_disp = NativeFn 2 "__rg_dispatch_spawn" 2 6 (build_spawn_dispatch_entry fn_tbl str_tbl)
        call2_slots = max_int 7 (4 + (highest entry arity fn_tbl))
        call2_disp = NativeFn 3 "__rg_dispatch_call2" 3 call2_slots (build_call2_dispatch_instrs fn_tbl str_tbl 1 [])
        binop_disp = NativeFn 4 "__rg_dispatch_binop" 3 6 (build_binop_dispatch_instrs fn_tbl str_tbl 1 [])
        user_native_fns = lower_fndef_list fns str_tbl fn_tbl field_tbl
        field_native_fns = lower_field_getter_fns field_tbl fn_names fn_tbl
        all_native_fns = [main_wrapper, spawn_disp, call2_disp, binop_disp] :: user_native_fns :: field_native_fns
        NativeProg 1 2 3 4 all_native_fns rodata_str

fn :: build lib entry wrapper Int       => RNativeFn
      build lib entry wrapper 0         =  NativeFn 1 "__rg_entry_main" 0 2 [NLoadImmRaw 0, NReturn]
      build lib entry wrapper entry_fid =  NativeFn 1 "__rg_entry_main" 0 2 [NCallFn entry_fid 0 0, NReturn]

fn :: lower library to native RProgram => RNativeProg
      lower library to native (Program raw_fns tys) =
        field_tbl = collect_typedef_fields tys []
        raw_fn_names = collect_fn_names raw_fns
        sigs = (build_cg_sigs raw_fns) :: (build_field_cg_sigs field_tbl raw_fn_names)
        fns = opt fndef list (prep_fndef_list raw_fns sigs)
        fn_names = collect_fn_names fns
        str_pool = build_str_pool fns (collect_field_names field_tbl)
        rodata_str = pool_rodata str_pool
        str_tbl = pool_entries str_pool
        fn_tbl1 = build_fn_table_fndefs fns 5 []
        fn_tbl2 = build_fn_table_fields field_tbl fn_names (5 + (list_str_len fn_names)) fn_tbl1
        fn_tbl = attach_heavy_fn_entries fns fn_names fn_tbl2
        entry_fid = lookup_fn_id fn_tbl "main"
        main_wrapper = build_lib_entry_wrapper entry_fid
        spawn_disp = NativeFn 2 "__rg_dispatch_spawn" 2 6 (build_spawn_dispatch_entry fn_tbl str_tbl)
        call2_slots = max_int 7 (4 + (highest entry arity fn_tbl))
        call2_disp = NativeFn 3 "__rg_dispatch_call2" 3 call2_slots (build_call2_dispatch_instrs fn_tbl str_tbl 1 [])
        binop_disp = NativeFn 4 "__rg_dispatch_binop" 3 6 (build_binop_dispatch_instrs fn_tbl str_tbl 1 [])
        user_native_fns = lower_fndef_list fns str_tbl fn_tbl field_tbl
        field_native_fns = lower_field_getter_fns field_tbl fn_names fn_tbl
        all_native_fns = [main_wrapper, spawn_disp, call2_disp, binop_disp] :: user_native_fns :: field_native_fns
        NativeProg 1 2 3 4 all_native_fns rodata_str

-- ── Bytecode (.rgc), Library (.rglib / .so), & ELF64 Emission ─

fn :: join summaries [String] => String
      join summaries []       =  ""
      join summaries (s:ss)   =  "-- SUMMARY: {s}\n" + (join_summaries ss)

fn :: emit rgc payload RProgram String  => String
      emit rgc payload prog     raw_src =
        fn_count = count_fn_defs prog
        ty_count = count_type_defs prog
        summaries = join_summaries (analyze_rprogram prog)
        "RGC1\n-- SELF_HOSTED_COMPILER: ridgunc v0.9.8\n-- FUNCTIONS: {fn_count}\n-- TYPES: {ty_count}\n{summaries}{raw_src}"

fn :: emit rgc file String     String      => Int
      emit rgc file input_path output_path =
        raw_src = load_rg_with_libs input_path
        emit_rgc_file_loaded input_path output_path raw_src

fn :: emit rgc file loaded String String String => Int
      emit rgc file loaded input_path _ "" =
        _ = echo "[ridgunc compile] Error: empty or missing source file: {input_path}"
        -1
      emit rgc file loaded _ output_path raw_src =
        toks = tokenize_src raw_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        emit_rgc_after_check prog raw_src output_path errs

fn :: emit rgc after check RProgram String String [RTypeError] => Int
      emit rgc after check prog raw_src output_path []
        | ((count_fn_defs prog) == 0) AND ((count_type_defs prog) == 0) =
          _ = echo "[ridgunc compile] Error: no functions or types found in source"
          -1
        | otherwise =
          payload = emit_rgc_payload prog raw_src
          _ = write_file output_path payload
          count_fn_defs prog
      emit rgc after check _ _ _ errs =
        _ = echo (format_type_errors errs)
        0 - (type_err_count errs)

fn :: emit rglib payload RProgram String  => String
      emit rglib payload prog     raw_src =
        fn_count = count_fn_defs prog
        ty_count = count_type_defs prog
        summaries = join_summaries (analyze_rprogram prog)
        "-- RGLIB1\n-- SELF_HOSTED_COMPILER: ridgunc v0.9.8\n-- FUNCTIONS: {fn_count}\n-- TYPES: {ty_count}\n{summaries}{raw_src}"

fn :: emit rglib file String     String      => Int
      emit rglib file input_path output_path =
        own_src = load_rg_own_source input_path
        full_src = load_rg_with_libs input_path
        emit_rglib_file_loaded input_path output_path own_src full_src

fn :: emit rglib file loaded String String String String => Int
      emit rglib file loaded input_path _ "" _ =
        _ = echo "[ridgunc build --lib] Error: empty or missing source file: {input_path}"
        1
      emit rglib file loaded _ output_path own_src full_src =
        full_prog = parse_tokens (tokenize_src full_src)
        errs = typecheck_program full_prog
        own_prog = parse_tokens (tokenize_src own_src)
        emit_rglib_after_check own_prog own_src output_path errs

fn :: emit rglib after check RProgram String String [RTypeError] => Int
      emit rglib after check prog raw_src output_path []
        | ((count_fn_defs prog) == 0) AND ((count_type_defs prog) == 0) =
          _ = echo "[ridgunc build --lib] Error: no functions or types found in source"
          1
        | otherwise =
          payload = emit_rglib_payload prog raw_src
          _ = write_file output_path payload
          0
      emit rglib after check _ _ _ errs =
        _ = echo (format_type_errors errs)
        1

fn :: emit elf for target RNativeProg String => [Int]
      emit elf for target nprog "arm64" = emit arm64 elf nprog
      emit elf for target nprog "arm64-linux" = emit arm64 elf nprog
      emit elf for target nprog "aarch64" = emit arm64 elf nprog
      emit elf for target nprog _ = emit x8664 elf nprog

fn :: emit so elf for target RNativeProg String => [Int]
      emit so elf for target nprog "arm64" = emit arm64 so elf nprog
      emit so elf for target nprog "arm64-linux" = emit arm64 so elf nprog
      emit so elf for target nprog "aarch64" = emit arm64 so elf nprog
      emit so elf for target nprog _ = emit x8664 so elf nprog

fn :: build native target for arch RNativeProg String String => Int
      build native target for arch nprog output_bin "arm64" =
        write elf64 executable output_bin (emit arm64 elf nprog)
      build native target for arch nprog output_bin "arm64-linux" =
        write elf64 executable output_bin (emit arm64 elf nprog)
      build native target for arch nprog output_bin "aarch64" =
        write elf64 executable output_bin (emit arm64 elf nprog)
      build native target for arch nprog output_bin _ =
        build llvm x8664 executable nprog output_bin

fn :: build native so for arch RNativeProg String String => Int
      build native so for arch nprog output_so "arm64" =
        write elf64 executable output_so (emit arm64 so elf nprog)
      build native so for arch nprog output_so "arm64-linux" =
        write elf64 executable output_so (emit arm64 so elf nprog)
      build native so for arch nprog output_so "aarch64" =
        write elf64 executable output_so (emit arm64 so elf nprog)
      build native so for arch nprog output_so _ =
        build llvm x8664 so library nprog output_so

fn :: build native target executable String String String => Int
      build native target executable input_path output_bin target_arch =
        raw_src = load_rg_with_libs input_path
        build native target loaded input_path output_bin target_arch raw_src

fn :: build native target loaded String String String String => Int
      build native target loaded input_path _ _ "" =
        _ = echo "[ridgunc build] Error: empty or missing source file: {input_path}"
        1
      build native target loaded _ output_bin target_arch raw_src =
        toks = tokenize_src raw_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        build native target after check prog output_bin target_arch errs

fn :: build native target after check RProgram String String [RTypeError] => Int
      build native target after check prog output_bin target_arch []
        | (count_fn_defs prog) == 0 =
          _ = echo "[ridgunc build] Error: no functions found in source"
          1
        | otherwise =
          nprog = lower_program_to_native prog
          build native target for arch nprog output_bin target_arch
      build native target after check _ _ _ errs =
        _ = echo (format_type_errors errs)
        1

fn :: build native target so library String String String => Int
      build native target so library input_path output_so target_arch =
        raw_src = load_rg_with_libs input_path
        build native so loaded input_path output_so target_arch raw_src

fn :: build native so loaded String String String String => Int
      build native so loaded input_path _ _ "" =
        _ = echo "[ridgunc build --so] Error: empty or missing source file: {input_path}"
        1
      build native so loaded _ output_so target_arch raw_src =
        toks = tokenize_src raw_src
        prog = parse_tokens toks
        errs = typecheck_program prog
        build native so after check prog output_so target_arch errs

fn :: build native so after check RProgram String String [RTypeError] => Int
      build native so after check prog output_so target_arch []
        | ((count_fn_defs prog) == 0) AND ((count_type_defs prog) == 0) =
          _ = echo "[ridgunc build --so] Error: no functions or types found in source"
          1
        | otherwise =
          nprog = lower_library_to_native prog
          build native so for arch nprog output_so target_arch
      build native so after check _ _ _ errs =
        _ = echo (format_type_errors errs)
        1

fn :: build native so library String String => Int
      build native so library input_path output_so =
        build native target so library input_path output_so "x86_64-linux"

fn :: build native executable String     String     => Int
      build native executable input_path output_bin =
        build native target executable input_path output_bin "x86_64-linux"

fn :: build native fast executable String String => Int
      build native fast executable input_path output_bin =
        build native target executable input_path output_bin "x86_64-linux"
