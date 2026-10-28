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
      list str len (_:xs)   =  1 + (list str len xs)

fn :: pat list len [RPattern] => Int
      pat list len []         =  0
      pat list len (_:xs)     =  1 + (pat list len xs)

fn :: find local idx [String] String Int => Int
      find local idx [] _ _ = -1
      find local idx (x:xs) target idx
        | x == target = idx
        | otherwise = find local idx xs target (idx + 1)

fn :: lookup local [String] String => Int
      lookup local locals   name   =  find local idx locals name 0

fn :: ensure local [String] String => [String] Int
      ensure local locals   name   =
        existing = lookup local locals name
        ensure local branch locals name existing

fn :: ensure local branch [String] String Int => [String] Int
      ensure local branch locals name existing
        | existing >= 0 = (locals, existing)
        | otherwise = (locals :: [name], list str len locals)

fn :: rinstr len [RInstr] => Int
      rinstr len []       =  0
      rinstr len (_:xs)   =  1 + (rinstr len xs)

-- ── Pattern Binding & Match Emission (Bytecode) ─────────────

fn :: bind pat vars [RPattern] Int [String] => [String]
      bind pat vars [] _ locals = locals
      bind pat vars ((PatVar v):ps) idx locals =
        bind pat vars ps (idx + 1) (locals :: [v])
      bind pat vars ((PatSeqBind v):ps) idx locals =
        bind pat vars ps (idx + 1) (locals :: [v])
      bind pat vars (_:ps) idx locals =
        bind pat vars ps (idx + 1) (locals :: ['_arg_' + (int to str idx)])

fn :: emit pat checks [RPattern] Int Int => [RInstr]
      emit pat checks [] _ _ = []
      emit pat checks ((PatInt n):ps) slot fail_ip =
        [BLoadLocal slot, BPushInt n, BJumpIfNeq fail_ip] :: (emit pat checks ps (slot + 1) fail_ip)
      emit pat checks ((PatReal r):ps) slot fail_ip =
        [BLoadLocal slot, BPushReal r, BJumpIfNeq fail_ip] :: (emit pat checks ps (slot + 1) fail_ip)
      emit pat checks ((PatStr s):ps) slot fail_ip =
        [BLoadLocal slot, BPushStr s, BJumpIfNeq fail_ip] :: (emit pat checks ps (slot + 1) fail_ip)
      emit pat checks ((PatBool b):ps) slot fail_ip =
        [BLoadLocal slot, BPushBool b, BJumpIfNeq fail_ip] :: (emit pat checks ps (slot + 1) fail_ip)
      emit pat checks (PatEmpty:ps) slot fail_ip =
        [BLoadLocal slot, BJumpIfNotEmpty fail_ip] :: (emit pat checks ps (slot + 1) fail_ip)
      emit pat checks (_:ps) slot fail_ip =
        emit pat checks ps (slot + 1) fail_ip

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
        p_res = compile rexpr list parts locals
        append instr (BStrInterp (rexpr list len parts)) p_res
      compile rexpr (EBool b)          locals   =  ([BPushBool b], locals)
      compile rexpr EUnit              locals   =  ([BPushUnit], locals)
      compile rexpr (EVar name)        locals   =
        idx = lookup local locals name
        compile var lookup name idx locals
      compile rexpr (ENot inner)       locals   =
        r1 = compile rexpr inner locals
        append instr BNot r1
      compile rexpr (EOut inner)       locals   =
        r1 = compile rexpr inner locals
        append instr BOut r1
      compile rexpr (EBin bop l r)     locals   =
        r1 = compile rexpr l locals
        compile bin rhs bop r r1
      compile rexpr (ECall fname args) locals   =
        args_res = compile rexpr list args locals
        append instr (BCall fname (rexpr list len args)) args_res
      compile rexpr (EEcho args)       locals   =
        args_res = compile rexpr list args locals
        append instr (BEcho (rexpr list len args)) args_res
      compile rexpr (EList elems)      locals   =
        elems_res = compile rexpr list elems locals
        append instr (BListConcat (rexpr list len elems)) elems_res
      compile rexpr (ETuple elems)     locals   =
        elems_res = compile rexpr list elems locals
        append instr (BMakeTuple (rexpr list len elems)) elems_res
      compile rexpr (ETensor elems)    locals   =
        elems_res = compile rexpr list elems locals
        append instr (BMakeTensor (rexpr list len elems)) elems_res
      compile rexpr (EEinsum es subs)  locals   =
        es_res = compile rexpr list es locals
        append instr (BTensorEinsum subs) es_res
      compile rexpr (EHadamard bop l s1 r s2) locals =
        r1 = compile rexpr l locals
        r2 = compile rexpr after r r1
        append instr (BTensorHadamard bop s1 s2) r2
      compile rexpr (EIndex base idxs) locals   =
        b_res = compile rexpr base locals
        i_res = compile rexpr list after idxs b_res
        append instr (BTensorGet (rexpr list len idxs)) i_res
      compile rexpr (EIndexAssign target idxs val_e) locals =
        slot_res = ensure local locals target
        compile index assign bc slot_res idxs val_e
      compile rexpr (ESeqSelect base mask) locals =
        b_res = compile rexpr base locals
        append instr (BSeqSelectMask mask) b_res
      compile rexpr (EBlock stmts)     locals   =
        compile rblock stmts locals
      compile rexpr (EGuard guards)    locals   =
        compile rguard expr guards locals
      compile rexpr (EWhere body binds) locals  =
        w_res = compile where list binds locals
        compile where body body w_res
      compile rexpr (EParPipe branches) locals  =
        b_res = compile rexpr list branches locals
        append instr (BMakeTuple (rexpr list len branches)) b_res
      compile rexpr (EWithCtx ctx_name val_e body) locals =
        v_res = compile rexpr val_e locals
        v_push = append instr (BPushCtx ctx_name) v_res
        b_res = compile rexpr after body v_push
        append instr (BPopCtx ctx_name) b_res
      compile rexpr (EWithRegion quota body) locals =
        b_res = compile rexpr body locals
        wrap region bc quota b_res

fn :: compile rexpr after RExpr ([RInstr], [String]) => [RInstr] [String]
      compile rexpr after e     (c1, locals1)        =
        r2 = compile rexpr e locals1
        merge code pair c1 r2

fn :: compile rexpr list after [RExpr] ([RInstr], [String]) => [RInstr] [String]
      compile rexpr list after es (c1, locals1) =
        r2 = compile rexpr list es locals1
        merge code pair c1 r2

fn :: compile index assign bc ([String], Int) [RExpr] RExpr => [RInstr] [String]
      compile index assign bc (locals1, slot) idxs val_e =
        i_res = compile rexpr list idxs locals1
        v_res = compile rexpr after val_e i_res
        finish index assign bc slot (rexpr list len idxs) v_res

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
        r_res = compile rexpr r locals1
        merge bin code (compile binop bop) l_code r_res

fn :: merge bin code RInstr [RInstr] ([RInstr], [String]) => [RInstr] [String]
      merge bin code ins l_code (r_code, locals2) =
        (l_code :: r_code :: [ins], locals2)

fn :: rexpr list len [RExpr] => Int
      rexpr list len []      =  0
      rexpr list len (_:xs)  =  1 + (rexpr list len xs)

fn :: compile rexpr list [RExpr] [String] => [RInstr] [String]
      compile rexpr list []      locals   =  ([], locals)
      compile rexpr list (e:es)  locals   =
        r1 = compile rexpr e locals
        compile rexpr list cont es r1

fn :: compile rexpr list cont [RExpr] ([RInstr], [String]) => [RInstr] [String]
      compile rexpr list cont es (c1, locals1) =
        r2 = compile rexpr list es locals1
        merge code pair c1 r2

fn :: merge code pair [RInstr] ([RInstr], [String]) => [RInstr] [String]
      merge code pair c1       (c2, locals2)        =  (c1 :: c2, locals2)

fn :: compile rguard expr [RGuard] [String] => [RInstr] [String]
      compile rguard expr []       locals   =  ([BPushUnit], locals)
      compile rguard expr ((GuardBranch _ body):[]) locals =
        compile rexpr body locals
      compile rguard expr ((GuardBranch _ body):_) locals =
        compile rexpr body locals

fn :: compile rblock [RStmt]           [String] => [RInstr] [String]
      compile rblock []                locals   =  ([BPushUnit], locals)
      compile rblock ((StmtExpr e):[]) locals   =  compile rexpr e locals
      compile rblock ((StmtLet v e):rest) locals =
        e_res = compile rexpr e locals
        compile rblock after let v rest e_res
      compile rblock ((StmtMut v e):rest) locals =
        e_res = compile rexpr e locals
        compile rblock after let v rest e_res
      compile rblock ((StmtIndexAssign t idxs e):rest) locals =
        e_res = compile rexpr (EIndexAssign t idxs e) locals
        compile rblock after expr rest e_res
      compile rblock ((StmtExpr e):rest) locals =
        e_res = compile rexpr e locals
        compile rblock after expr rest e_res

fn :: compile rblock after let String [RStmt] ([RInstr], [String]) => [RInstr] [String]
      compile rblock after let v rest (e_code, locals1) =
        slot_res = ensure local locals1 v
        compile rblock store let rest e_code slot_res

fn :: compile rblock store let [RStmt] [RInstr] ([String], Int) => [RInstr] [String]
      compile rblock store let [] e_code (locals2, slot) =
        (e_code :: [BStoreLocal slot, BLoadLocal slot], locals2)
      compile rblock store let rest e_code (locals2, slot) =
        r_more = compile rblock rest locals2
        merge code pair (e_code :: [BStoreLocal slot]) r_more

fn :: compile rblock after expr [RStmt] ([RInstr], [String]) => [RInstr] [String]
      compile rblock after expr [] (e_code, locals1) = (e_code, locals1)
      compile rblock after expr rest (e_code, locals1) =
        r_more = compile rblock rest locals1
        merge code pair (e_code :: [BPop]) r_more

fn :: compile where list [RWhereBind] [String] => [RInstr] [String]
      compile where list []           locals   =  ([], locals)
      compile where list ((WhereBind e v _):wbs) locals =
        e_res = compile rexpr e locals
        compile where list step v wbs e_res

fn :: compile where list step String [RWhereBind] ([RInstr], [String]) => [RInstr] [String]
      compile where list step v wbs (e_code, locals1) =
        slot_res = ensure local locals1 v
        compile where store wbs e_code slot_res

fn :: compile where store [RWhereBind] [RInstr] ([String], Int) => [RInstr] [String]
      compile where store wbs e_code (locals2, slot) =
        more = compile where list wbs locals2
        merge code pair (e_code :: [BStoreLocal slot]) more

fn :: compile where body RExpr ([RInstr], [String]) => [RInstr] [String]
      compile where body body  (w_code, locals1)    =
        b_res = compile rexpr body locals1
        merge code pair w_code b_res

-- ── Function & Case Lowering (Bytecode) ─────────────────────

fn :: compile guards [RGuard] [String] Int     => [RInstr]
      compile guards []       _        _       =  []
      compile guards ((GuardBranch cond body):gs) locals base_ip =
        c_res = compile rexpr cond locals
        b_res = compile rexpr body locals
        emit guard branch gs locals base_ip c_res b_res

fn :: emit guard branch [RGuard] [String] Int ([RInstr], [String]) ([RInstr], [String]) => [RInstr]
      emit guard branch gs locals base_ip (c_code, _) (b_code, _) =
        next_guard_ip = base_ip + (rinstr len c_code) + 1 + (rinstr len b_code) + 1
        this_guard = c_code :: [BJumpIfFalse next_guard_ip] :: b_code :: [BReturn]
        this_guard :: (compile guards gs locals next_guard_ip)

fn :: compile single case RFnCase Int     => [RInstr]
      compile single case (FnCase pats guards body) base_ip =
        locals = bind pat vars pats 0 []
        compile case inner pats guards body locals base_ip

fn :: compile case inner [RPattern] [RGuard] RExpr [String] Int => [RInstr]
      compile case inner pats [] body locals base_ip =
        b_res = compile rexpr body locals
        finish case with body pats base_ip b_res
      compile case inner pats guards _ locals base_ip =
        p_pre = emit pat checks pats 0 0
        g_code = compile guards guards locals (base_ip + (rinstr len p_pre))
        fail_ip = base_ip + (rinstr len p_pre) + (rinstr len g_code)
        p_checks = emit pat checks pats 0 fail_ip
        p_checks :: g_code

fn :: finish case with body [RPattern] Int ([RInstr], [String]) => [RInstr]
      finish case with body pats base_ip (b_code, _) =
        p_pre = emit pat checks pats 0 0
        fail_ip = base_ip + (rinstr len p_pre) + (rinstr len b_code) + 1
        p_checks = emit pat checks pats 0 fail_ip
        p_checks :: b_code :: [BReturn]

fn :: compile cases seq [RFnCase] Int     => [RInstr]
      compile cases seq []        _       =  []
      compile cases seq (c:cs)    base_ip =
        c_code = compile single case c base_ip
        next_ip = base_ip + (rinstr len c_code)
        c_code :: (compile cases seq cs next_ip)

fn :: compile rfndef RFnDef => RCompiledFn
      compile rfndef (FnDef name params _ cases) =
        arity = list str len params
        code = compile cases seq cases 0
        CompiledFn name arity code

fn :: compile rfndef list [RFnDef] => [RCompiledFn]
      compile rfndef list []       =  []
      compile rfndef list (f:fs)   =  [compile rfndef f] :: (compile rfndef list fs)

fn :: compile rprogram RProgram        => RCompiledProg
      compile rprogram (Program fns _) =
        CompiledProg (compile rfndef list fns)

-- ── Pre-Codegen Normalization (Variadic Packing & Tuple-Chain Unpacking) ──

type RCgSig = CgSig String Int Bool

fn :: str ends with dots String => Bool
      str ends with dots s      =
        len = str len s
        len > 3 and (str slice s (len - 3) len) == "..."

fn :: params has variadic [String] => Bool
      params has variadic []       =  False
      params has variadic (p:[])   =  str ends with dots p
      params has variadic (_:ps)   =  params has variadic ps

fn :: infer fndef arity [String] [RFnCase] => Int
      infer fndef arity params   ((FnCase ((PatSeqBind _):[]) _ _):_) = list str len params
      infer fndef arity _        ((FnCase pats _ _):_) = pat list len pats
      infer fndef arity params   []        =  list str len params

fn :: build cg sigs acc [RFnDef] [RCgSig] => [RCgSig]
      build cg sigs acc []       acc      =  acc
      build cg sigs acc ((FnDef name params _ cases):fs) acc =
        build cg sigs acc fs (acc :: [CgSig name (infer fndef arity params cases) (params has variadic params)])

fn :: build cg sigs [RFnDef] => [RCgSig]
      build cg sigs fns      =  build cg sigs acc fns []

fn :: lookup var cg sig [RCgSig] String => Bool Int Bool
      lookup var cg sig []       _      =  (False, 0, False)
      lookup var cg sig ((CgSig name arity is_var):rest) target
        | name == target and arity < 0 = (False, 0, False)
        | name == target = (True, arity, is_var)
        | otherwise = lookup var cg sig rest target

fn :: lookup cg sig [RCgSig] String => Bool Int Bool
      lookup cg sig []       _      =  (False, 0, False)
      lookup cg sig ((CgSig name arity is_var):rest) target
        | arity >= 0 and name == target = (True, arity, is_var)
        | otherwise = lookup cg sig rest target

fn :: bind pat cg sigs RPattern [RCgSig] => [RCgSig]
      bind pat cg sigs (PatVar v) sigs = [CgSig v (0 - 2) False] :: sigs
      bind pat cg sigs (PatSeqBind v) sigs = [CgSig v (0 - 2) False] :: sigs
      bind pat cg sigs (PatCons h t) sigs = bind pat cg sigs t (bind pat cg sigs h sigs)
      bind pat cg sigs (PatTuple ps) sigs = bind pat list cg sigs ps sigs
      bind pat cg sigs (PatCtor _ ps) sigs = bind pat list cg sigs ps sigs
      bind pat cg sigs _ sigs = sigs

fn :: bind pat list cg sigs [RPattern] [RCgSig] => [RCgSig]
      bind pat list cg sigs [] sigs = sigs
      bind pat list cg sigs (p:ps) sigs = bind pat list cg sigs ps (bind pat cg sigs p sigs)

fn :: bind where cg sigs [RWhereBind] [RCgSig] => [RCgSig]
      bind where cg sigs [] sigs = sigs
      bind where cg sigs ((WhereBind _ v _):wbs) sigs
        | v != "" = bind where cg sigs wbs ([CgSig v (0 - 2) False] :: sigs)
        | otherwise = bind where cg sigs wbs sigs

fn :: prep expr RExpr              [RCgSig] => RExpr
      prep expr (ENot inner)       sigs     =  ENot (prep expr inner sigs)
      prep expr (EOut inner)       sigs     =  EOut (prep expr inner sigs)
      prep expr (EBin bop l r)     sigs     =  EBin bop (prep expr l sigs) (prep expr r sigs)
      prep expr (ECall fname args) sigs     =
        p_args = prep expr list args sigs
        prep call fname p_args (lookup cg sig sigs fname)
      prep expr (EEcho args)       sigs     =  EEcho (prep expr list args sigs)
      prep expr (EStrInterp parts) sigs     =  EStrInterp (prep expr list parts sigs)
      prep expr (EList elems)      sigs     =  EList (prep expr list elems sigs)
      prep expr (ETuple elems)     sigs     =  ETuple (prep expr list elems sigs)
      prep expr (ETensor elems)    sigs     =  ETensor (prep expr list elems sigs)
      prep expr (EEinsum es subs)  sigs     =  EEinsum (prep expr list es sigs) subs
      prep expr (EHadamard bop l s1 r s2) sigs = EHadamard bop (prep expr l sigs) s1 (prep expr r sigs) s2
      prep expr (EIndex base idxs) sigs     =  EIndex (prep expr base sigs) (prep expr list idxs sigs)
      prep expr (EIndexAssign t idxs v) sigs = EIndexAssign t (prep expr list idxs sigs) (prep expr v sigs)
      prep expr (ESeqSelect b m)   sigs     =  ESeqSelect (prep expr b sigs) m
      prep expr (EBlock stmts)     sigs     =  EBlock (prep stmt list stmts sigs)
      prep expr (EGuard guards)    sigs     =  EGuard (prep guard list guards sigs)
      prep expr (EWhere body binds) sigs    =
        sigs1 = bind where cg sigs binds sigs
        EWhere (prep expr body sigs1) (prep where list binds sigs1)
      prep expr (EParPipe branches) sigs    =  EParPipe (prep expr list branches sigs)
      prep expr (EWithCtx c v b)   sigs     =  EWithCtx c (prep expr v sigs) (prep expr b sigs)
      prep expr (EWithRegion q b)  sigs     =  EWithRegion q (prep expr b sigs)
      prep expr (EVar v)           sigs     =  prep var v (lookup var cg sig sigs v)
      prep expr e                  _        =  e

fn :: prep var String (Bool, Int, Bool) => RExpr
      prep var v      (True, 0, False)  =  ECall v []
      prep var v      _                 =  EVar v

fn :: is tuple unpack arg RExpr              => Bool
      is tuple unpack arg (ESeqSelect _ _)   =  True
      is tuple unpack arg (ETuple _)         =  True
      is tuple unpack arg (EParPipe _)       =  True
      is tuple unpack arg _                  =  False

fn :: prep call String [RExpr]         (Bool, Int, Bool) => RExpr
      prep call fname  args            (True, arity, True)
        | arity <= 1 = ECall fname [EList args]
        | otherwise = ECall fname ((take exprs args (arity - 1)) :: [EList (drop exprs args (arity - 1))])
      prep call fname  (single_arg:[]) (True, 2, False)
        | not (str starts with fname "__rg_lambda_") =
          ECall "__unpack2__" [EVar fname, single_arg]
      prep call fname  (single_arg:[]) (True, arity, False)
        | arity > 2 and (is tuple unpack arg single_arg) and (not (str starts with fname "__rg_lambda_")) =
          ECall "__unpack2__" [EVar fname, single_arg]
      prep call fname  args            _                 =  ECall fname args

fn :: prep expr list [RExpr] [RCgSig] => [RExpr]
      prep expr list []      _        =  []
      prep expr list (e:es)  sigs     =  [prep expr e sigs] :: (prep expr list es sigs)

fn :: prep stmt list [RStmt]            [RCgSig] => [RStmt]
      prep stmt list []                 _        =  []
      prep stmt list ((StmtLet v e):ss) sigs     =
        [StmtLet v (prep expr e sigs)] :: (prep stmt list ss ([CgSig v (0 - 2) False] :: sigs))
      prep stmt list ((StmtMut v e):ss) sigs     =
        [StmtMut v (prep expr e sigs)] :: (prep stmt list ss ([CgSig v (0 - 2) False] :: sigs))
      prep stmt list ((StmtExpr e):ss)  sigs     =  [StmtExpr (prep expr e sigs)] :: (prep stmt list ss sigs)
      prep stmt list ((StmtIndexAssign t idxs e):ss) sigs = [StmtIndexAssign t (prep expr list idxs sigs) (prep expr e sigs)] :: (prep stmt list ss sigs)

fn :: prep where list [RWhereBind] [RCgSig] => [RWhereBind]
      prep where list []           _        =  []
      prep where list ((WhereBind e v idxs):wbs) sigs = [WhereBind (prep expr e sigs) v idxs] :: (prep where list wbs sigs)

fn :: prep guard list [RGuard] [RCgSig] => [RGuard]
      prep guard list []       _        =  []
      prep guard list ((GuardBranch c b):gs) sigs = [GuardBranch (prep expr c sigs) (prep expr b sigs)] :: (prep guard list gs sigs)

fn :: prep case list [RFnCase] [RCgSig] => [RFnCase]
      prep case list []        _        =  []
      prep case list ((FnCase pats guards body):cs) sigs =
        case_sigs = bind pat list cg sigs pats sigs
        [FnCase pats (prep guard list guards case_sigs) (prep expr body case_sigs)] :: (prep case list cs sigs)

fn :: prep fndef list acc [RFnDef] [RCgSig] [RFnDef] => [RFnDef]
      prep fndef list acc []       _        acc      =  acc
      prep fndef list acc ((FnDef name params ret_ty cases):fs) sigs acc =
        prep fndef list acc fs sigs (acc :: [FnDef name params ret_ty (prep case list cases sigs)])

fn :: prep fndef list [RFnDef] [RCgSig] => [RFnDef]
      prep fndef list fns      sigs     =  prep fndef list acc fns sigs []

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
      is pure arith expr (EVar v)       =  not (is upper ident v)
      is pure arith expr (EInt _)       =  True
      is pure arith expr (EBool _)      =  True
      is pure arith expr (ENot a)       =  is pure arith expr a
      is pure arith expr (EBin bop a b) =  (is pure arith binop bop) and (is pure arith expr a) and (is pure arith expr b)
      is pure arith expr _              =  False

fn :: is compound arith expr RExpr          => Bool
      is compound arith expr (ENot a)       =  is pure arith expr a
      is compound arith expr (EBin bop a b) =  (is pure arith binop bop) and (is pure arith expr a) and (is pure arith expr b)
      is compound arith expr _              =  False

fn :: is simple inline arg RExpr    => Bool
      is simple inline arg (EVar _) =  True
      is simple inline arg (EInt _) =  True
      is simple inline arg _        =  False

fn :: all simple inline args [RExpr] => Bool
      all simple inline args []      =  True
      all simple inline args (e:es)  =  (is simple inline arg e) and (all simple inline args es)

fn :: collect inline expr fns [RFnDef] => [RInlineExprEntry]
      collect inline expr fns []       =  []
      collect inline expr fns ((FnDef name _ _ ((FnCase pats [] body):[])):fs)
        | (not (str starts with name "__rg_lambda_")) and pats != [] and (all pat vars pats) and (is compound arith expr body) =
          [InlineExprEntry name (extract pat var names pats) body] :: (collect inline expr fns fs)
      collect inline expr fns (_:fs)   =  collect inline expr fns fs

fn :: lookup inline expr [RInlineExprEntry] String Int => Bool [String] RExpr
      lookup inline expr [] _ _ = (False, [], EUnit)
      lookup inline expr ((InlineExprEntry name pnames body):rest) target arity
        | name == target and (list str len pnames) == arity = (True, pnames, body)
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
          inline leaf call fname args1 (lookup inline expr tbl fname (rexpr list len args1))
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
      is pure inline stmt (StmtLet v e) =  v != "_" and (not (str starts with v ":")) and (is pure arith expr e)
      is pure inline stmt (StmtMut v e) =  v != "_" and (not (str starts with v ":")) and (is pure arith expr e)
      is pure inline stmt _             =  False

fn :: all pure arith exprs [RExpr] => Bool
      all pure arith exprs []      =  True
      all pure arith exprs (e:es)  =  (is pure arith expr e) and (all pure arith exprs es)

fn :: split tuple return stmts [RStmt] [RStmt] => Bool [RStmt] [RExpr]
      split tuple return stmts ((StmtExpr (ETuple ret_es)):[]) acc
        | ret_es != [] and (all pure arith exprs ret_es) = (True, acc, ret_es)
      split tuple return stmts (s:ss) acc
        | is pure inline stmt s = split tuple return stmts ss (acc :: [s])
      split tuple return stmts _ _ = (False, [], [])

fn :: extract tuple return body RExpr           => Bool [RStmt] [RExpr]
      extract tuple return body (ETuple ret_es)
        | ret_es != [] and (all pure arith exprs ret_es) = (True, [], ret_es)
      extract tuple return body (EBlock stmts)  =  split tuple return stmts stmts []
      extract tuple return body _               =  (False, [], [])

fn :: append inline tuple if match String [String] (Bool, [RStmt], [RExpr]) [RInlineTupleEntry] => [RInlineTupleEntry]
      append inline tuple if match name pnames (True, init_stmts, ret_es) rest =
        [InlineTupleEntry name pnames init_stmts ret_es] :: rest
      append inline tuple if match _ _ _ rest = rest

fn :: collect inline tuple fns [RFnDef] => [RInlineTupleEntry]
      collect inline tuple fns []       =  []
      collect inline tuple fns ((FnDef name _ _ ((FnCase pats [] body):[])):fs)
        | pats != [] and (all pat vars pats) =
          append inline tuple if match name (extract pat var names pats) (extract tuple return body body) (collect inline tuple fns fs)
      collect inline tuple fns (_:fs)   =  collect inline tuple fns fs

fn :: lookup inline tuple [RInlineTupleEntry] String Int => Bool [String] [RStmt] [RExpr]
      lookup inline tuple [] _ _ = (False, [], [], [])
      lookup inline tuple ((InlineTupleEntry name pnames init_stmts ret_es):rest) target arity
        | name == target and (list str len pnames) == arity = (True, pnames, init_stmts, ret_es)
        | otherwise = lookup inline tuple rest target arity

fn :: match tup unpack stmts [RStmt] String Int Int [RStmt] => Bool [RStmt] [RStmt]
      match tup unpack stmts rest _ idx count acc
        | idx >= count = (True, acc, rest)
      match tup unpack stmts ((StmtMut v (EIndex (EVar tv) ((EInt i):[]))):rest) tmp_name idx count acc
        | tv == tmp_name and i == idx =
          match tup unpack stmts rest tmp_name (idx + 1) count (acc :: [StmtMut v EUnit])
      match tup unpack stmts ((StmtIndexAssign tk is (EIndex (EVar tv) ((EInt i):[]))):rest) tmp_name idx count acc
        | tv == tmp_name and i == idx =
          match tup unpack stmts rest tmp_name (idx + 1) count (acc :: [StmtIndexAssign tk is EUnit])
      match tup unpack stmts _ _ _ _ _ = (False, [], [])

fn :: collect inline local vars [RStmt] [String] => [String]
      collect inline local vars [] acc = acc
      collect inline local vars ((StmtLet v _):ss) acc = collect inline local vars ss (add unique str v acc)
      collect inline local vars ((StmtMut v _):ss) acc = collect inline local vars ss (add unique str v acc)
      collect inline local vars (_:ss) acc = collect inline local vars ss acc

fn :: rename inline expr RExpr [String] String => RExpr
      rename inline expr (EVar v) local_vars prefix
        | str in list v local_vars = EVar (prefix + v)
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
        finish expand inline tuple tmp_name fname args rest pnames init_stmts ret_es (match tup unpack stmts rest tmp_name 0 (rexpr list len ret_es) []) tbl
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
        | (str starts with tmp_name ":tup-") or (str starts with tmp_name ":idx-tup-") =
          try expand inline tuple tmp_name fname args rest (lookup inline tuple tbl fname (rexpr list len args)) tbl
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
        NativeCode (instrs :: [ins]) lbl (max int msp used_sp)

fn :: nc emit list RNativeCode [RNativeInstr] Int => RNativeCode
      nc emit list (NativeCode instrs lbl msp) more used_sp =
        NativeCode (instrs :: more) lbl (max int msp used_sp)

-- ── String Pool (.rodata) Collection & Interning ─────────────

fn :: join comma [String] => String
      join comma []       =  ""
      join comma (s:[])   =  s
      join comma (s:ss)   =  s + "," + (join comma ss)

fn :: add ctor str String [String] => [String]
      add ctor str s acc
        | is upper ident s = add unique str (ident base name s) (add unique str s acc)
        | otherwise = add unique str s acc

fn :: collect pat strs RPattern         [String] => [String]
      collect pat strs (PatReal r)      acc      =  add unique str r acc
      collect pat strs (PatStr s)       acc      =  add unique str s acc
      collect pat strs (PatCons h t)    acc      =  collect pat strs t (collect pat strs h acc)
      collect pat strs (PatTuple ps)    acc      =  collect pat list strs ps acc
      collect pat strs (PatCtor c args) acc      =  collect pat list strs args (add ctor str c acc)
      collect pat strs _                acc      =  acc

fn :: collect pat list strs [RPattern] [String] => [String]
      collect pat list strs [] acc = acc
      collect pat list strs (p:ps) acc = collect pat list strs ps (collect pat strs p acc)

fn :: collect expr strs RExpr              [String] => [String]
      collect expr strs (EReal r)          acc      =  add unique str r acc
      collect expr strs (EStr s)           acc      =  add unique str s acc
      collect expr strs (EVar v)           acc      =  add ctor str v acc
      collect expr strs (ENot inner)       acc      =  collect expr strs inner acc
      collect expr strs (EOut inner)       acc      =  collect expr strs inner acc
      collect expr strs (EBin _ l r)       acc      =  collect expr strs r (collect expr strs l acc)
      collect expr strs (ECall fname args) acc      =  collect expr list strs args (add ctor str fname acc)
      collect expr strs (EEcho args)       acc      =  collect expr list strs args acc
      collect expr strs (EStrInterp parts) acc      =  collect expr list strs parts acc
      collect expr strs (EList elems)      acc      =  collect expr list strs elems acc
      collect expr strs (ETuple elems)     acc      =  collect expr list strs elems acc
      collect expr strs (ETensor elems)    acc      =  collect expr list strs elems acc
      collect expr strs (EEinsum es subs)  acc      =  collect expr list strs es (add unique str (join comma subs) acc)
      collect expr strs (EHadamard _ l s1 r s2) acc =  collect expr strs r (collect expr strs l (add unique str (s1 + "," + s2) acc))
      collect expr strs (EIndex base idxs) acc      =  collect expr list strs idxs (collect expr strs base acc)
      collect expr strs (EIndexAssign _ idxs v) acc =  collect expr strs v (collect expr list strs idxs acc)
      collect expr strs (ESeqSelect b m)   acc      =  collect expr strs b (add unique str m acc)
      collect expr strs (EBlock stmts)     acc      =  collect stmt list strs stmts acc
      collect expr strs (EGuard guards)    acc      =  collect guard list strs guards acc
      collect expr strs (EWhere body binds) acc     =  collect where list strs binds (collect expr strs body acc)
      collect expr strs (EParPipe branches) acc     =  collect expr list strs branches acc
      collect expr strs (EWithCtx c v b)   acc      =  collect expr strs b (collect expr strs v (add unique str c acc))
      collect expr strs (EWithRegion _ b)  acc      =  collect expr strs b acc
      collect expr strs _                  acc      =  acc

fn :: collect expr list strs [RExpr] [String] => [String]
      collect expr list strs [] acc = acc
      collect expr list strs (e:es) acc = collect expr list strs es (collect expr strs e acc)

fn :: collect stmt list strs [RStmt] [String] => [String]
      collect stmt list strs [] acc = acc
      collect stmt list strs ((StmtLet _ e):ss) acc = collect stmt list strs ss (collect expr strs e acc)
      collect stmt list strs ((StmtMut _ e):ss) acc = collect stmt list strs ss (collect expr strs e acc)
      collect stmt list strs ((StmtExpr e):ss) acc = collect stmt list strs ss (collect expr strs e acc)
      collect stmt list strs ((StmtIndexAssign _ idxs e):ss) acc =
        collect stmt list strs ss (collect expr strs e (collect expr list strs idxs acc))

fn :: collect where list strs [RWhereBind] [String] => [String]
      collect where list strs [] acc = acc
      collect where list strs ((WhereBind e _ _):wbs) acc =
        collect where list strs wbs (collect expr strs e acc)

fn :: collect guard list strs [RGuard] [String] => [String]
      collect guard list strs [] acc = acc
      collect guard list strs ((GuardBranch c b):gs) acc =
        collect guard list strs gs (collect expr strs b (collect expr strs c acc))

fn :: collect case list strs [RFnCase] [String] => [String]
      collect case list strs [] acc = acc
      collect case list strs ((FnCase pats guards body):cs) acc =
        a1 = collect pat list strs pats acc
        a2 = collect guard list strs guards a1
        collect case list strs cs (collect expr strs body a2)

fn :: collect fndef list strs [RFnDef] [String] => [String]
      collect fndef list strs [] acc = acc
      collect fndef list strs ((FnDef name _ _ cases):fs) acc =
        collect fndef list strs fs (collect case list strs cases (add unique str name acc))

fn :: build str pool loop [String] Int String [RStrEntry] => RStrPool
      build str pool loop [] _ rodata entries = StrPool rodata entries
      build str pool loop (s:ss) cur_off rodata entries =
        slen = str len s
        build str pool loop ss (cur_off + slen) (rodata + s) (entries :: [StrEntry s cur_off slen])

fn :: build str pool [RFnDef] [String]   => RStrPool
      build str pool fns      extra_strs =
        base_strs = ["", "+", "-", "*", "/", "%", "Linux", "MacOS", "Windows", "X86_64", "Arm64", "Ok", "Some", "None", "__rg_par_eval__", "ki,k", "i,j", "i,i", "ij,ij"] :: extra_strs
        all_strs = collect fndef list strs fns base_strs
        build str pool loop all_strs 0 "" []

fn :: pool rodata RStrPool      => String
      pool rodata (StrPool s _) =  s

fn :: pool entries RStrPool        => [RStrEntry]
      pool entries (StrPool _ tbl) =  tbl

fn :: lookup str off [RStrEntry] String => Int
      lookup str off []          _      =  0
      lookup str off ((StrEntry k off _):rest) target
        | k == target = off
        | otherwise = lookup str off rest target

-- ── Function & Record Field Tables ───────────────────────────

fn :: has field entry [RFieldEntry] String => Bool
      has field entry []            _      =  False
      has field entry ((FieldEntry k _):rest) target
        | k == target = True
        | otherwise = has field entry rest target

fn :: add base field entry String Int [RFieldEntry] => [RFieldEntry]
      add base field entry fname idx acc
        | (str contains fname ".") and (not (has field entry acc (ident base name fname))) =
          acc :: [FieldEntry (ident base name fname) idx]
        | otherwise = acc

fn :: collect fields from list [RField] Int [RFieldEntry] => [RFieldEntry]
      collect fields from list [] _ acc = acc
      collect fields from list ((TypeField fname _):fs) idx acc
        | has field entry acc fname = collect fields from list fs (idx + 1) (add base field entry fname idx acc)
        | otherwise = collect fields from list fs (idx + 1) (add base field entry fname idx (acc :: [FieldEntry fname idx]))

fn :: collect typedef fields [RTypeDef] [RFieldEntry] => [RFieldEntry]
      collect typedef fields []         acc           =  acc
      collect typedef fields ((TypeDef _ _ fields):ts) acc =
        collect typedef fields ts (collect fields from list fields 0 acc)

fn :: lookup field idx [RFieldEntry] String => Int
      lookup field idx []            _      =  0
      lookup field idx ((FieldEntry k idx):rest) target
        | k == target = idx
        | otherwise = lookup field idx rest target

fn :: collect field names [RFieldEntry] => [String]
      collect field names []            =  []
      collect field names ((FieldEntry k _):rest) = [k] :: (collect field names rest)

fn :: build field cg sigs [RFieldEntry] [String] => [RCgSig]
      build field cg sigs [] _ = []
      build field cg sigs ((FieldEntry fname _):rest) fn_names
        | str in list fname fn_names = build field cg sigs rest fn_names
        | otherwise = [CgSig fname 1 False] :: (build field cg sigs rest fn_names)

fn :: build fn table fndefs [RFnDef] Int [RFnEntry] => [RFnEntry]
      build fn table fndefs [] _ acc = acc
      build fn table fndefs ((FnDef name params _ cases):fs) next_fid acc =
        arity = infer fndef arity params cases
        build fn table fndefs fs (next_fid + 1) (acc :: [FnEntry name next_fid arity])

fn :: build fn table fields [RFieldEntry] [String] Int [RFnEntry] => [RFnEntry]
      build fn table fields [] _ _ acc = acc
      build fn table fields ((FieldEntry fname _):rest) fn_names next_fid acc
        | str in list fname fn_names = build fn table fields rest fn_names next_fid acc
        | otherwise = build fn table fields rest fn_names (next_fid + 1) (acc :: [FnEntry fname next_fid 1])

fn :: lookup fn id [RFnEntry] String => Int
      lookup fn id []         _      =  0
      lookup fn id ((FnEntry k fid _):rest) target
        | k == target = fid
        | otherwise = lookup fn id rest target

fn :: lookup fn arity [RFnEntry] String => Int
      lookup fn arity []         _      =  -1
      lookup fn arity ((FnEntry k _ arity):rest) target
        | k == target = arity
        | otherwise = lookup fn arity rest target

fn :: is heavy call name String               => Bool
      is heavy call name "sys_sleep_ms"       =  True
      is heavy call name "poll_fd_ms"         =  True
      is heavy call name "wait_fd"            =  True
      is heavy call name "sys_poll"           =  True
      is heavy call name "sys_read"           =  True
      is heavy call name "sys_read_fd"        =  True
      is heavy call name "sys_write"          =  True
      is heavy call name "sys_write_fd"       =  True
      is heavy call name "sys_syscall6"       =  True
      is heavy call name "sys_call"           =  True
      is heavy call name "sys_waitpid"        =  True
      is heavy call name "sys_pipe"           =  True
      is heavy call name "shell_exec"         =  True
      is heavy call name "shell_capture"      =  True
      is heavy call name "posix_read"         =  True
      is heavy call name "posix_write"        =  True
      is heavy call name "posix_pipe"         =  True
      is heavy call name "socket_accept"      =  True
      is heavy call name "socket_recv"        =  True
      is heavy call name "socket_send"        =  True
      is heavy call name "socket_connect"     =  True
      is heavy call name "send_to"            =  True
      is heavy call name "receive_from"       =  True
      is heavy call name "try_receive_from"   =  True
      is heavy call name "ask_to"             =  True
      is heavy call name "ask"                =  True
      is heavy call name _                    =  False

fn :: expr has heavy ops RExpr             => Bool
      expr has heavy ops (ETensor _)       =  True
      expr has heavy ops (EEinsum _ _)     =  True
      expr has heavy ops (EHadamard _ _ _ _ _) = True
      expr has heavy ops (EBin OpMatMul _ _) = True
      expr has heavy ops (EBin _ l r)      =  (expr has heavy ops l) or (expr has heavy ops r)
      expr has heavy ops (ENot inner)      =  expr has heavy ops inner
      expr has heavy ops (EOut inner)      =  expr has heavy ops inner
      expr has heavy ops (ECall fname args)
        | is heavy call name fname = True
        | otherwise = expr list has heavy ops args
      expr has heavy ops (EList elems)     =  expr list has heavy ops elems
      expr has heavy ops (ETuple elems)    =  expr list has heavy ops elems
      expr has heavy ops (EBlock stmts)    =  stmt list has heavy ops stmts
      expr has heavy ops (EGuard guards)   =  guard list has heavy ops guards
      expr has heavy ops (EWhere body binds) = (expr has heavy ops body) or (where list has heavy ops binds)
      expr has heavy ops (EParPipe branches) = expr list has heavy ops branches
      expr has heavy ops (EWithCtx "__rg_timeout_ms__" _ _) = True
      expr has heavy ops (EWithCtx _ v b)  =  (expr has heavy ops v) or (expr has heavy ops b)
      expr has heavy ops (EWithRegion _ b) =  expr has heavy ops b
      expr has heavy ops _                 =  False

fn :: expr list has heavy ops [RExpr] => Bool
      expr list has heavy ops [] = False
      expr list has heavy ops (e:es)
        | expr has heavy ops e = True
        | otherwise = expr list has heavy ops es

fn :: stmt list has heavy ops [RStmt] => Bool
      stmt list has heavy ops [] = False
      stmt list has heavy ops ((StmtLet _ e):ss)
        | expr has heavy ops e = True
        | otherwise = stmt list has heavy ops ss
      stmt list has heavy ops ((StmtMut _ e):ss)
        | expr has heavy ops e = True
        | otherwise = stmt list has heavy ops ss
      stmt list has heavy ops ((StmtExpr e):ss)
        | expr has heavy ops e = True
        | otherwise = stmt list has heavy ops ss
      stmt list has heavy ops (_:ss) = stmt list has heavy ops ss

fn :: where list has heavy ops [RWhereBind] => Bool
      where list has heavy ops [] = False
      where list has heavy ops ((WhereBind e _ _):wbs)
        | expr has heavy ops e = True
        | otherwise = where list has heavy ops wbs

fn :: guard list has heavy ops [RGuard] => Bool
      guard list has heavy ops [] = False
      guard list has heavy ops ((GuardBranch c b):gs)
        | (expr has heavy ops c) or (expr has heavy ops b) = True
        | otherwise = guard list has heavy ops gs

fn :: cases have heavy ops [RFnCase] => Bool
      cases have heavy ops []        =  False
      cases have heavy ops ((FnCase _ gs b):cs)
        | (guard list has heavy ops gs) or (expr has heavy ops b) = True
        | otherwise = cases have heavy ops cs

fn :: any str in list [String] [String] => Bool
      any str in list [] _ = False
      any str in list (x:xs) targets
        | str in list x targets = True
        | otherwise = any str in list xs targets

fn :: collect direct heavy fns [RFnDef] => [String]
      collect direct heavy fns []       =  []
      collect direct heavy fns ((FnDef name _ _ cases):fs)
        | ((builtin call id name) < 0 and (count case calls name cases) > 0) or (cases have heavy ops cases) =
          [name] :: (collect direct heavy fns fs)
        | otherwise = collect direct heavy fns fs

fn :: build non heavy ref pairs [RFnDef] [String] => [(String, [String])]
      build non heavy ref pairs [] _ = []
      build non heavy ref pairs ((FnDef name _ _ cases):fs) direct_heavy
        | str in list name direct_heavy = build non heavy ref pairs fs direct_heavy
        | otherwise = [(name, collect refs cases cases [])] :: (build non heavy ref pairs fs direct_heavy)

fn :: expand heavy pass [(String, [String])] [String] [(String, [String])] Bool => [String] [(String, [String])] Bool
      expand heavy pass [] heavy rem changed = (heavy, rem, changed)
      expand heavy pass ((name, refs):rest) heavy rem changed
        | any str in list refs heavy =
          expand heavy pass rest (heavy :: [name]) rem True
        | otherwise =
          expand heavy pass rest heavy (rem :: [(name, refs)]) changed

fn :: expand heavy fixpoint [(String, [String])] [String] Int => [String]
      expand heavy fixpoint _ heavy 0 = heavy
      expand heavy fixpoint [] heavy _ = heavy
      expand heavy fixpoint pairs heavy rounds =
        expand heavy step (expand heavy pass pairs heavy [] False) rounds

fn :: expand heavy step ([String], [(String, [String])], Bool) Int => [String]
      expand heavy step (heavy1, _, False) _ = heavy1
      expand heavy step (heavy1, rem1, True) rounds =
        expand heavy fixpoint rem1 heavy1 (rounds - 1)

fn :: build heavy fn entries [String] [RFnEntry] => [RFnEntry]
      build heavy fn entries [] acc = acc
      build heavy fn entries (h:hs) acc =
        build heavy fn entries hs (acc :: [FnEntry ("__heavy__" + h) 1 (0 - 1)])

fn :: attach heavy fn entries [RFnDef] [String] [RFnEntry] => [RFnEntry]
      attach heavy fn entries fns _ fn_tbl =
        direct_heavy = collect direct heavy fns fns
        ref_pairs = build non heavy ref pairs fns direct_heavy
        all_heavy = expand heavy fixpoint ref_pairs direct_heavy 8
        build heavy fn entries all_heavy fn_tbl

-- ── Local Variable Collection & RMM2 Liveness Helpers ────────

fn :: collect pat vars RPattern         [String] => [String]
      collect pat vars (PatVar v)       acc      =  add unique str v acc
      collect pat vars (PatSeqBind v)   acc      =  add unique str v acc
      collect pat vars (PatCons h t)    acc      =  collect pat vars t (collect pat vars h acc)
      collect pat vars (PatTuple ps)    acc      =  collect pat list vars ps acc
      collect pat vars (PatCtor _ args) acc      =  collect pat list vars args acc
      collect pat vars _                acc      =  acc

fn :: collect pat list vars [RPattern] [String] => [String]
      collect pat list vars [] acc = acc
      collect pat list vars (p:ps) acc = collect pat list vars ps (collect pat vars p acc)

fn :: add bound var String [String] => [String]
      add bound var "_"    acc      =  acc
      add bound var v      acc      =  add unique str v acc

fn :: collect expr bound vars RExpr [String] => [String]
      collect expr bound vars (ENot inner) acc = collect expr bound vars inner acc
      collect expr bound vars (EOut inner) acc = collect expr bound vars inner acc
      collect expr bound vars (EBin _ l r) acc = collect expr bound vars r (collect expr bound vars l acc)
      collect expr bound vars (ECall _ args) acc = collect expr list bound vars args acc
      collect expr bound vars (EEcho args) acc = collect expr list bound vars args acc
      collect expr bound vars (EStrInterp parts) acc = collect expr list bound vars parts acc
      collect expr bound vars (EList elems) acc = collect expr list bound vars elems acc
      collect expr bound vars (ETuple elems) acc = collect expr list bound vars elems acc
      collect expr bound vars (ETensor elems) acc = collect expr list bound vars elems acc
      collect expr bound vars (EEinsum es _) acc = collect expr list bound vars es acc
      collect expr bound vars (EHadamard _ l _ r _) acc = collect expr bound vars r (collect expr bound vars l acc)
      collect expr bound vars (EIndex base idxs) acc = collect expr list bound vars idxs (collect expr bound vars base acc)
      collect expr bound vars (EIndexAssign t idxs v) acc = collect expr bound vars v (collect expr list bound vars idxs (add bound var t acc))
      collect expr bound vars (ESeqSelect b _) acc = collect expr bound vars b acc
      collect expr bound vars (EBlock stmts) acc = collect stmt list bound vars stmts acc
      collect expr bound vars (EGuard guards) acc = collect guard list bound vars guards acc
      collect expr bound vars (EWhere body binds) acc = collect where list bound vars binds (collect expr bound vars body acc)
      collect expr bound vars (EParPipe branches) acc = collect expr list bound vars branches acc
      collect expr bound vars (EWithCtx _ v b) acc = collect expr bound vars b (collect expr bound vars v acc)
      collect expr bound vars (EWithRegion _ b) acc = collect expr bound vars b acc
      collect expr bound vars _ acc = acc

fn :: collect expr list bound vars [RExpr] [String] => [String]
      collect expr list bound vars [] acc = acc
      collect expr list bound vars (e:es) acc = collect expr list bound vars es (collect expr bound vars e acc)

fn :: collect stmt list bound vars [RStmt] [String] => [String]
      collect stmt list bound vars [] acc = acc
      collect stmt list bound vars ((StmtLet v e):ss) acc =
        collect stmt list bound vars ss (add bound var v (collect expr bound vars e acc))
      collect stmt list bound vars ((StmtMut v e):ss) acc =
        collect stmt list bound vars ss (add bound var v (collect expr bound vars e acc))
      collect stmt list bound vars ((StmtExpr e):ss) acc =
        collect stmt list bound vars ss (collect expr bound vars e acc)
      collect stmt list bound vars ((StmtIndexAssign t idxs e):ss) acc =
        collect stmt list bound vars ss (collect expr bound vars e (collect expr list bound vars idxs (add bound var t acc)))

fn :: collect where list bound vars [RWhereBind] [String] => [String]
      collect where list bound vars [] acc = acc
      collect where list bound vars ((WhereBind e v _):wbs) acc =
        collect where list bound vars wbs (add bound var v (collect expr bound vars e acc))

fn :: collect guard list bound vars [RGuard] [String] => [String]
      collect guard list bound vars [] acc = acc
      collect guard list bound vars ((GuardBranch c b):gs) acc =
        collect guard list bound vars gs (collect expr bound vars b (collect expr bound vars c acc))

fn :: collect cases all locals [RFnCase] [String] => [String]
      collect cases all locals [] acc = acc
      collect cases all locals ((FnCase pats guards body):cs) acc =
        a1 = collect pat list vars pats acc
        a2 = collect guard list bound vars guards a1
        collect cases all locals cs (collect expr bound vars body a2)

fn :: cmm expr vars RExpr              [String] => [String]
      cmm expr vars (EVar name)        acc      =  add unique str name acc
      cmm expr vars (ENot inner)       acc      =  cmm expr vars inner acc
      cmm expr vars (EOut inner)       acc      =  cmm expr vars inner acc
      cmm expr vars (EBin _ l r)       acc      =  cmm expr vars r (cmm expr vars l acc)
      cmm expr vars (ECall "__record_update__" (base_e:rest_args)) acc =
        cmm expr list vars rest_args (cmm expr vars base_e acc)
      cmm expr vars (ECall "__unpack2__" (_:single_arg:[])) acc =
        cmm expr vars single_arg acc
      cmm expr vars (ECall fname args) acc      =  cmm expr list vars args (add unique str fname acc)
      cmm expr vars (EEcho args)       acc      =  cmm expr list vars args acc
      cmm expr vars (EStrInterp parts) acc      =  cmm expr list vars parts acc
      cmm expr vars (EList elems)      acc      =  cmm expr list vars elems acc
      cmm expr vars (ETuple elems)     acc      =  cmm expr list vars elems acc
      cmm expr vars (ETensor elems)    acc      =  cmm expr list vars elems acc
      cmm expr vars (EEinsum es _)     acc      =  cmm expr list vars es acc
      cmm expr vars (EHadamard _ l _ r _) acc   =  cmm expr vars r (cmm expr vars l acc)
      cmm expr vars (EIndex base idxs) acc      =  cmm expr list vars idxs (cmm expr vars base acc)
      cmm expr vars (EIndexAssign t idxs v) acc =  cmm expr vars v (cmm expr list vars idxs (add unique str t acc))
      cmm expr vars (ESeqSelect b _)   acc      =  cmm expr vars b acc
      cmm expr vars (EBlock stmts)     acc      =  cmm stmts vars stmts acc
      cmm expr vars (EGuard guards)    acc      =  cmm guards vars guards acc
      cmm expr vars (EWhere body binds) acc     =  cmm where vars binds body acc
      cmm expr vars (EParPipe branches) acc     =  cmm expr list vars branches acc
      cmm expr vars (EWithCtx _ v b)   acc      =  cmm expr vars b (cmm expr vars v acc)
      cmm expr vars (EWithRegion _ b)  acc      =  cmm expr vars b acc
      cmm expr vars _                  acc      =  acc

fn :: cmm guards vars [RGuard] [String] => [String]
      cmm guards vars []       acc      =  acc
      cmm guards vars ((GuardBranch c b):gs) acc =
        cmm guards vars gs (cmm expr vars b (cmm expr vars c acc))

fn :: cmm expr list vars [RExpr] [String] => [String]
      cmm expr list vars [] acc = acc
      cmm expr list vars (e:es) acc = cmm expr list vars es (cmm expr vars e acc)

fn :: cmm stmts vars [RStmt]            [String] => [String]
      cmm stmts vars []                 acc      =  acc
      cmm stmts vars ((StmtLet _ e):ss) acc      =  cmm stmts vars ss (cmm expr vars e acc)
      cmm stmts vars ((StmtMut _ e):ss) acc      =  cmm stmts vars ss (cmm expr vars e acc)
      cmm stmts vars ((StmtExpr e):ss)  acc      =  cmm stmts vars ss (cmm expr vars e acc)
      cmm stmts vars ((StmtIndexAssign t idxs e):ss) acc =
        cmm stmts vars ss (cmm expr vars e (cmm expr list vars idxs (add unique str t acc)))

fn :: cmm where vars [RWhereBind] RExpr [String] => [String]
      cmm where vars [] body acc = cmm expr vars body acc
      cmm where vars ((WhereBind e _ []):wbs) body acc =
        cmm where vars wbs body (cmm expr vars e acc)
      cmm where vars ((WhereBind e v _):wbs) body acc =
        cmm where vars wbs body (cmm expr vars e (add unique str v acc))

fn :: cmm filter in list [String] [String] => [String]
      cmm filter in list [] _ = []
      cmm filter in list (x:xs) allowed
        | x != "_" and (str in list x allowed) = [x] :: (cmm filter in list xs allowed)
        | otherwise = cmm filter in list xs allowed

fn :: cmm filter not in list [String] [String] => [String]
      cmm filter not in list [] _ = []
      cmm filter not in list (x:xs) excluded
        | x != "_" and (not (str in list x excluded)) = [x] :: (cmm filter not in list xs excluded)
        | otherwise = cmm filter not in list xs excluded

fn :: cmm remove str String [String] => [String]
      cmm remove str _      []       =  []
      cmm remove str target (x:xs)
        | x == target = cmm remove str target xs
        | otherwise = [x] :: (cmm remove str target xs)

-- ── Environment Accessors & Builtin ID Mapping ───────────────

fn :: env fn name RNativeEnv => String
      env fn name (NativeEnv fn_name _ _ _ _ _) = fn_name

fn :: env arity RNativeEnv => Int
      env arity (NativeEnv _ arity _ _ _ _) = arity

fn :: env str off RNativeEnv String => Int
      env str off (NativeEnv _ _ _ str_tbl _ _) s = lookup str off str_tbl s

fn :: env fn id RNativeEnv String => Int
      env fn id (NativeEnv _ _ _ _ fn_tbl _) fname = lookup fn id fn_tbl fname

fn :: env fn arity RNativeEnv String => Int
      env fn arity (NativeEnv _ _ _ _ fn_tbl _) fname = lookup fn arity fn_tbl fname

fn :: env fn is heavy RNativeEnv String => Bool
      env fn is heavy (NativeEnv _ _ _ _ fn_tbl _) fname =
        (lookup fn id fn_tbl ("__heavy__" + fname)) > 0

fn :: env field idx RNativeEnv String => Int
      env field idx (NativeEnv _ _ _ _ _ field_tbl) fname = lookup field idx field_tbl fname

fn :: env has field RNativeEnv String => Bool
      env has field (NativeEnv _ _ _ _ _ field_tbl) fname = has field entry field_tbl fname

fn :: env var slot RNativeEnv String => Int
      env var slot (NativeEnv _ arity all_locals _ _ _) name =
        idx = lookup local all_locals name
        env var slot idx arity idx

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
        slot = env var slot env x
        st1 = nc emit st (NCmmDropSlot slot) used_sp
        lower cmm drops env xs used_sp st1

fn :: lower unused let drop RNativeEnv String [String] Int RNativeCode => RNativeCode
      lower unused let drop env v live_after used_sp st
        | str in list v live_after = st
        | otherwise = nc emit st (NCmmDropSlot (env var slot env v)) used_sp

fn :: lower let var store RNativeEnv String [String] Int RNativeCode => RNativeCode
      lower let var store env v bound_locals used_sp st
        | (lookup local bound_locals v) >= 0 = nc emit st (NRebindSlot (env var slot env v)) used_sp
        | otherwise = nc emit st (NStoreSlot (env var slot env v)) used_sp

fn :: lower expr list to slots RNativeEnv [RExpr] [String] Int Int RNativeCode => RNativeCode
      lower expr list to slots _ [] _ _ _ st = st
      lower expr list to slots env (e:es) bound_locals sp idx st =
        cur_slot = sp + idx
        st1 = lower expr env e bound_locals cur_slot st
        st2 = nc emit st1 (NStoreSlot cur_slot) (cur_slot + 1)
        lower expr list to slots env es bound_locals sp (idx + 1) st2

fn :: lower int list to slots [Int] Int Int RNativeCode => RNativeCode
      lower int list to slots [] _ _ st = st
      lower int list to slots (n:ns) sp idx st =
        cur_slot = sp + idx
        st1 = nc emit list st [NLoadImmInt n, NStoreSlot cur_slot] (cur_slot + 1)
        lower int list to slots ns sp (idx + 1) st1

fn :: lower record updates RNativeEnv [RExpr] [String] Int RNativeCode => RNativeCode
      lower record updates env ((EStr fname):val_e:rest) bound_locals sp st =
        st1 = nc emit st (NStoreSlot sp) (sp + 1)
        st2 = lower expr env val_e bound_locals (sp + 1) st1
        fidx = env field idx env fname
        st3 = nc emit st2 (NAdtSet sp fidx) (sp + 1)
        lower record updates env rest bound_locals sp st3
      lower record updates _ _ _ _ st = st

fn :: lower var expr RNativeEnv String [String] Int RNativeCode => RNativeCode
      lower var expr env name bound_locals sp st
        | (lookup local bound_locals name) >= 0 =
          nc emit st (NCloneSlot (env var slot env name)) sp
        | name == "sys_os" =
          nc emit st (NLoadAdt0 (env str off env "Linux") 5) sp
        | name == "sys_arch" =
          nc emit st (NLoadAdt0 (0 - 1) 0) sp
        | is upper ident name =
          c_tag = ident base name name
          off = env str off env c_tag
          nc emit st (NLoadAdt0 off (str len c_tag)) sp
        | (builtin zero arg id name) >= 0 =
          nc emit st (NCallBuiltin (builtin zero arg id name) sp 0) (sp + 1)
        | (env fn arity env name) == 0 =
          nc emit st (NCallFn (env fn id env name) sp 0) (sp + 1)
        | otherwise =
          off = env str off env name
          nc emit st (NLoadStrLit off (str len name)) sp

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
        | (lookup local boundLocals fname) < 0 and (env fn arity env fname) == 1 =
          NCallFn (env fn id env fname) argSlot 1
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
        | (lookup local boundLocals tname) >= 0 =
          tslot = env var slot env tname
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
        | (lookup local bound_locals fname) < 0 and (env fn is heavy env fname) = 3
        | (lookup local bound_locals fname) < 0 and (env fn arity env fname) == 2 = 4
        | otherwise = 1
      agent fn mode _ _ _ = 1

fn :: stateful agent mode RNativeEnv RExpr [String] => Int
      stateful agent mode env (EVar fname) bound_locals
        | (lookup local bound_locals fname) < 0 and (env fn is heavy env fname) = 1
        | otherwise = 0
      stateful agent mode _ _ _ = 0

fn :: lower agent call RNativeEnv String [RExpr] [String] Int RNativeCode => RNativeCode
      lower agent call env "agent" (fn_e:[]) bound_locals sp st =
        ag_mode = agent fn mode env fn_e bound_locals
        st1 = lower expr env fn_e bound_locals sp st
        ins = [NStoreSlot sp, NCallBuiltin 1 (sp + 1) 0, NStoreSlot (sp + 1), NCallBuiltin 1 (sp + 2) 0, NStoreSlot (sp + 2), NLoadImmInt ag_mode, NStoreSlot (sp + 3), NMakeList (sp + 4) 0, NStoreSlot (sp + 4), NMakeTuple (sp + 3) 2, NStoreSlot (sp + 3), NCloneSlot (sp + 1), NStoreSlot (sp + 4), NCallBuiltin 50 (sp + 3) 2, NDropVal, NMakeTuple sp 3]
        nc emit list st1 ins (sp + 5)
      lower agent call env "agent" (fn_e:init_e:[]) bound_locals sp st =
        st_flag = stateful agent mode env fn_e bound_locals
        st1 = lower expr env fn_e bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env init_e bound_locals (sp + 4) st2
        ins = [NStoreSlot (sp + 4), NLoadImmInt st_flag, NStoreSlot (sp + 5), NMakeTuple (sp + 4) 2, NStoreSlot (sp + 4), NCallBuiltin 1 (sp + 1) 0, NStoreSlot (sp + 1), NCallBuiltin 1 (sp + 2) 0, NStoreSlot (sp + 2), NLoadImmInt 2, NStoreSlot (sp + 3), NMakeTuple (sp + 3) 2, NStoreSlot (sp + 3), NCloneSlot (sp + 1), NStoreSlot (sp + 4), NCallBuiltin 50 (sp + 3) 2, NDropVal, NMakeTuple sp 3]
        nc emit list st3 ins (sp + 6)
      lower agent call env "send_to" (msg_e:ag_e:[]) bound_locals sp st =
        st1 = lower expr env msg_e bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env ag_e bound_locals (sp + 1) st2
        st4 = nc emit st3 (NStoreSlot (sp + 1)) (sp + 2)
        stopped_lbl = nc lbl st4
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
        st5 = nc set lbl st4 (stopped_lbl + 14)
        ins_unpack = [NTupleGet (sp + 1) 0, NStoreSlot (sp + 2), NTupleGet (sp + 1) 1, NStoreSlot (sp + 3), NTupleGet (sp + 1) 2, NStoreSlot (sp + 4), NCloneSlot (sp + 3), NStoreSlot (sp + 5), NCallBuiltin 32 (sp + 5) 1, NStoreSlot (sp + 5), NTupleGet (sp + 5) 0, NStoreSlot (sp + 6), NTupleGet (sp + 5) 1, NStoreSlot (sp + 7)]
        ins_stateless = [NMatchInt (sp + 6) 1, NJumpIfZero stateless2_lbl, NCloneSlot sp, NStoreSlot (sp + 8), NCallIndirect1 (sp + 2) (sp + 8), NStoreSlot (sp + 8), NCloneSlot (sp + 5), NStoreSlot (sp + 9), NCloneSlot (sp + 3), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NCloneSlot (sp + 8), NStoreSlot (sp + 9), NCloneSlot (sp + 4), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NJump done_lbl]
        ins_stateless2 = [NLabel stateless2_lbl, NMatchInt (sp + 6) 4, NJumpIfZero stateful_lbl, NTupleGet sp 0, NStoreSlot (sp + 8), NTupleGet sp 1, NStoreSlot (sp + 9), NCallIndirect2 (sp + 2) (sp + 8), NStoreSlot (sp + 8), NCloneSlot (sp + 5), NStoreSlot (sp + 9), NCloneSlot (sp + 3), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NCloneSlot (sp + 8), NStoreSlot (sp + 9), NCloneSlot (sp + 4), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NJump done_lbl]
        ins_stateful = [NLabel stateful_lbl, NMatchInt (sp + 6) 2, NJumpIfZero heavy_lbl, NTupleGet (sp + 7) 0, NStoreSlot (sp + 8), NTupleGet (sp + 7) 1, NStoreSlot (sp + 9), NMatchInt (sp + 9) 0, NJumpIfZero st_async_lbl, NCloneSlot (sp + 8), NStoreSlot (sp + 9), NCloneSlot sp, NStoreSlot (sp + 10), NCallIndirect2 (sp + 2) (sp + 9), NStoreSlot (sp + 10), NMatchTuple (sp + 10) 2, NJumpIfZero same_sync_lbl, NMatchTuple (sp + 8) 2, NJumpIfZero split_sync_lbl, NLabel same_sync_lbl, NCloneSlot (sp + 10), NStoreSlot (sp + 8), NCloneSlot (sp + 10), NStoreSlot (sp + 11), NJump save_sync_lbl, NLabel split_sync_lbl, NTupleGet (sp + 10) 0, NStoreSlot (sp + 8), NTupleGet (sp + 10) 1, NStoreSlot (sp + 11), NLabel save_sync_lbl, NCloneSlot (sp + 4), NStoreSlot (sp + 12), NCallBuiltin 50 (sp + 11) 2, NDropVal, NLoadImmInt 0, NStoreSlot (sp + 9), NMakeTuple (sp + 8) 2, NStoreSlot (sp + 9), NLoadImmInt 2, NStoreSlot (sp + 8), NMakeTuple (sp + 8) 2, NStoreSlot (sp + 8), NCloneSlot (sp + 3), NStoreSlot (sp + 9), NCallBuiltin 50 (sp + 8) 2, NDropVal, NJump done_lbl, NLabel st_async_lbl, NMatchInt (sp + 9) 1, NJumpIfZero flush_prev_lbl, NJump spawn_stateful_lbl, NLabel flush_prev_lbl, NCallBuiltin 59 (sp + 9) 1, NStoreSlot (sp + 10), NMatchTuple (sp + 10) 2, NJumpIfZero same_res_lbl, NMatchTuple (sp + 8) 2, NJumpIfZero split_pair_lbl, NLabel same_res_lbl, NCloneSlot (sp + 10), NStoreSlot (sp + 8), NCloneSlot (sp + 10), NStoreSlot (sp + 11), NJump store_state_lbl, NLabel split_pair_lbl, NTupleGet (sp + 10) 0, NStoreSlot (sp + 8), NTupleGet (sp + 10) 1, NStoreSlot (sp + 11), NLabel store_state_lbl, NCloneSlot (sp + 4), NStoreSlot (sp + 12), NCallBuiltin 50 (sp + 11) 2, NDropVal, NLabel spawn_stateful_lbl, NCloneSlot (sp + 8), NStoreSlot (sp + 10), NCloneSlot sp, NStoreSlot (sp + 11), NMakeTuple (sp + 10) 2, NStoreSlot (sp + 10), NCloneSlot (sp + 2), NStoreSlot (sp + 9), NCallBuiltin 57 (sp + 9) 2, NStoreSlot (sp + 9), NMakeTuple (sp + 8) 2, NStoreSlot (sp + 9), NLoadImmInt 2, NStoreSlot (sp + 8), NMakeTuple (sp + 8) 2, NStoreSlot (sp + 8), NCloneSlot (sp + 3), NStoreSlot (sp + 9), NCallBuiltin 50 (sp + 8) 2, NDropVal, NJump done_lbl]
        ins_heavy = [NLabel heavy_lbl, NMatchInt (sp + 6) 3, NJumpIfZero stopped_lbl, NCloneSlot (sp + 2), NStoreSlot (sp + 8), NCloneSlot sp, NStoreSlot (sp + 9), NCallBuiltin 57 (sp + 8) 2, NStoreSlot (sp + 9), NMoveSlot (sp + 7), NStoreSlot (sp + 8), NMakeList (sp + 9) 1, NBinOp 14 (sp + 8), NStoreSlot (sp + 9), NLoadImmInt 3, NStoreSlot (sp + 8), NMakeTuple (sp + 8) 2, NStoreSlot (sp + 9), NCloneSlot (sp + 3), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NJump done_lbl]
        ins_stopped = [NLabel stopped_lbl, NCloneSlot (sp + 5), NStoreSlot (sp + 9), NCloneSlot (sp + 3), NStoreSlot (sp + 10), NCallBuiltin 50 (sp + 9) 2, NDropVal, NLabel done_lbl, NClearLocals sp (sp + 13), NLoadImmRaw 0]
        nc emit list st5 (ins_unpack :: ins_stateless :: ins_stateless2 :: ins_stateful :: ins_heavy :: ins_stopped) (sp + 13)
      lower agent call env "ask_to" (msg_e:ag_e:[]) bound_locals sp st =
        st1 = lower agent call env "send_to" [msg_e, ag_e] bound_locals sp st
        st2 = nc emit st1 NDropVal sp
        lower agent call env "receive_from" [ag_e] bound_locals sp st2
      lower agent call env "receive_from" (target_e:[]) bound_locals sp st =
        st1 = lower expr env target_e bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        not_ag_lbl = nc lbl st2
        no_job_lbl = not_ag_lbl + 1
        done_lbl = not_ag_lbl + 2
        check_st_lbl = not_ag_lbl + 3
        st_await_lbl = not_ag_lbl + 4
        st_has_job_lbl = not_ag_lbl + 5
        st_same_lbl = not_ag_lbl + 6
        st_split_lbl = not_ag_lbl + 7
        st_save_lbl = not_ag_lbl + 8
        st_has_job_lbl2 = not_ag_lbl + 9
        st3 = nc set lbl st2 (not_ag_lbl + 10)
        ok_off = env str off env "Ok"
        ins_check = [NMatchTuple sp 3, NJumpIfZero not_ag_lbl, NTupleGet sp 1, NStoreSlot (sp + 1), NTupleGet sp 2, NStoreSlot sp, NCloneSlot (sp + 1), NStoreSlot (sp + 2), NCallBuiltin 32 (sp + 2) 1, NStoreSlot (sp + 2), NTupleGet (sp + 2) 0, NStoreSlot (sp + 3), NTupleGet (sp + 2) 1, NStoreSlot (sp + 4), NMatchInt (sp + 3) 3, NJumpIfZero check_st_lbl, NMatchNonEmpty (sp + 4), NJumpIfZero no_job_lbl]
        ins_pop = [NListHead (sp + 4), NStoreSlot (sp + 5), NListTail (sp + 4), NStoreSlot (sp + 6), NLoadImmInt 3, NStoreSlot (sp + 7), NMoveSlot (sp + 6), NStoreSlot (sp + 8), NMakeTuple (sp + 7) 2, NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NClearLocals sp (sp + 5), NCallBuiltin 59 (sp + 5) 1, NJump done_lbl]
        ins_st = [NLabel check_st_lbl, NMatchInt (sp + 3) 2, NJumpIfZero no_job_lbl, NCloneSlot sp, NStoreSlot (sp + 5), NCallBuiltin 33 (sp + 5) 1, NStoreSlot (sp + 5), NMatchAdt (sp + 5) ok_off 2 1, NJumpIfZero st_await_lbl, NMoveSlot (sp + 2), NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NAdtField (sp + 5) 0, NStoreSlot (sp + 6), NClearLocals sp (sp + 6), NMoveSlot (sp + 6), NJump done_lbl, NLabel st_await_lbl, NTupleGet (sp + 4) 0, NStoreSlot (sp + 5), NTupleGet (sp + 4) 1, NStoreSlot (sp + 6), NMatchInt (sp + 6) 0, NJumpIfZero st_has_job_lbl, NJump no_job_lbl, NLabel st_has_job_lbl, NMatchInt (sp + 6) 1, NJumpIfZero st_has_job_lbl2, NJump no_job_lbl, NLabel st_has_job_lbl2, NCallBuiltin 59 (sp + 6) 1, NStoreSlot (sp + 7), NMatchTuple (sp + 7) 2, NJumpIfZero st_same_lbl, NMatchTuple (sp + 5) 2, NJumpIfZero st_split_lbl, NLabel st_same_lbl, NCloneSlot (sp + 7), NStoreSlot (sp + 8), NCloneSlot (sp + 7), NStoreSlot (sp + 9), NJump st_save_lbl, NLabel st_split_lbl, NTupleGet (sp + 7) 0, NStoreSlot (sp + 8), NTupleGet (sp + 7) 1, NStoreSlot (sp + 9), NLabel st_save_lbl, NLoadImmInt 1, NStoreSlot (sp + 10), NMoveSlot (sp + 8), NStoreSlot (sp + 11), NMoveSlot (sp + 10), NStoreSlot (sp + 12), NMakeTuple (sp + 11) 2, NStoreSlot (sp + 11), NLoadImmInt 2, NStoreSlot (sp + 10), NMakeTuple (sp + 10) 2, NStoreSlot (sp + 10), NCloneSlot (sp + 1), NStoreSlot (sp + 11), NCallBuiltin 50 (sp + 10) 2, NDropVal, NClearLocals sp (sp + 9), NMoveSlot (sp + 9), NJump done_lbl]
        ins_no_job = [NLabel no_job_lbl, NMoveSlot (sp + 2), NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NClearLocals (sp + 1) (sp + 13), NLabel not_ag_lbl, NCallBuiltin 32 sp 1, NLabel done_lbl]
        nc emit list st3 (ins_check :: ins_pop :: ins_st :: ins_no_job) (sp + 13)
      lower agent call env "try_receive_from" (target_e:[]) bound_locals sp st =
        st1 = lower expr env target_e bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        not_ag_lbl = nc lbl st2
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
        st3 = nc set lbl st2 (not_ag_lbl + 12)
        ok_off = env str off env "Ok"
        some_off = env str off env "Some"
        none_off = env str off env "None"
        ins_check = [NMatchTuple sp 3, NJumpIfZero not_ag_lbl, NTupleGet sp 1, NStoreSlot (sp + 1), NTupleGet sp 2, NStoreSlot sp, NCloneSlot (sp + 1), NStoreSlot (sp + 2), NCallBuiltin 32 (sp + 2) 1, NStoreSlot (sp + 2), NTupleGet (sp + 2) 0, NStoreSlot (sp + 3), NTupleGet (sp + 2) 1, NStoreSlot (sp + 4), NMatchInt (sp + 3) 3, NJumpIfZero try_st_lbl, NMatchNonEmpty (sp + 4), NJumpIfZero no_job_lbl, NListHead (sp + 4), NStoreSlot (sp + 5), NCloneSlot (sp + 5), NStoreSlot (sp + 6), NCallBuiltin 58 (sp + 6) 1, NAsBool, NJumpIfZero not_ready_lbl]
        ins_ready = [NListTail (sp + 4), NStoreSlot (sp + 6), NLoadImmInt 3, NStoreSlot (sp + 7), NMoveSlot (sp + 6), NStoreSlot (sp + 8), NMakeTuple (sp + 7) 2, NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NCallBuiltin 59 (sp + 5) 1, NStoreSlot (sp + 5), NMakeAdt some_off 4 (sp + 5) 1, NStoreSlot (sp + 5), NClearLocals sp (sp + 5), NMoveSlot (sp + 5), NJump done_lbl]
        ins_try_st = [NLabel try_st_lbl, NMatchInt (sp + 3) 2, NJumpIfZero no_job_lbl, NCloneSlot sp, NStoreSlot (sp + 5), NCallBuiltin 33 (sp + 5) 1, NStoreSlot (sp + 5), NMatchAdt (sp + 5) ok_off 2 1, NJumpIfZero try_st_poll_lbl, NMoveSlot (sp + 2), NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NAdtField (sp + 5) 0, NStoreSlot (sp + 6), NMakeAdt some_off 4 (sp + 6) 1, NStoreSlot (sp + 6), NClearLocals sp (sp + 6), NMoveSlot (sp + 6), NJump done_lbl, NLabel try_st_poll_lbl, NTupleGet (sp + 4) 0, NStoreSlot (sp + 5), NTupleGet (sp + 4) 1, NStoreSlot (sp + 6), NMatchInt (sp + 6) 0, NJumpIfZero try_st_has_job_lbl, NJump not_ready_lbl, NLabel try_st_has_job_lbl, NMatchInt (sp + 6) 1, NJumpIfZero try_st_has_job_lbl2, NJump not_ready_lbl, NLabel try_st_has_job_lbl2, NCloneSlot (sp + 6), NStoreSlot (sp + 7), NCallBuiltin 58 (sp + 7) 1, NAsBool, NJumpIfZero not_ready_lbl, NCallBuiltin 59 (sp + 6) 1, NStoreSlot (sp + 7), NMatchTuple (sp + 7) 2, NJumpIfZero try_st_same_lbl, NMatchTuple (sp + 5) 2, NJumpIfZero try_st_split_lbl, NLabel try_st_same_lbl, NCloneSlot (sp + 7), NStoreSlot (sp + 8), NCloneSlot (sp + 7), NStoreSlot (sp + 9), NJump try_st_save_lbl, NLabel try_st_split_lbl, NTupleGet (sp + 7) 0, NStoreSlot (sp + 8), NTupleGet (sp + 7) 1, NStoreSlot (sp + 9), NLabel try_st_save_lbl, NLoadImmInt 1, NStoreSlot (sp + 10), NMoveSlot (sp + 8), NStoreSlot (sp + 11), NMoveSlot (sp + 10), NStoreSlot (sp + 12), NMakeTuple (sp + 11) 2, NStoreSlot (sp + 11), NLoadImmInt 2, NStoreSlot (sp + 10), NMakeTuple (sp + 10) 2, NStoreSlot (sp + 10), NCloneSlot (sp + 1), NStoreSlot (sp + 11), NCallBuiltin 50 (sp + 10) 2, NDropVal, NMakeAdt some_off 4 (sp + 9) 1, NStoreSlot (sp + 9), NClearLocals sp (sp + 9), NMoveSlot (sp + 9), NJump done_lbl]
        ins_not_ready = [NLabel not_ready_lbl, NMoveSlot (sp + 2), NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NClearLocals sp (sp + 13), NLoadAdt0 none_off 4, NJump done_lbl]
        ins_chan = [NLabel no_job_lbl, NMoveSlot (sp + 2), NStoreSlot (sp + 7), NCloneSlot (sp + 1), NStoreSlot (sp + 8), NCallBuiltin 50 (sp + 7) 2, NDropVal, NClearLocals (sp + 1) (sp + 13), NLabel not_ag_lbl, NCallBuiltin 33 sp 1, NStoreSlot sp, NMatchAdt sp ok_off 2 1, NJumpIfZero chan_none_lbl, NAdtField sp 0, NStoreSlot (sp + 1), NMakeAdt some_off 4 (sp + 1) 1, NStoreSlot (sp + 1), NClearLocals sp (sp + 1), NMoveSlot (sp + 1), NJump done_lbl, NLabel chan_none_lbl, NClearLocals sp (sp + 2), NLoadAdt0 none_off 4, NLabel done_lbl]
        nc emit list st3 (ins_check :: ins_ready :: ins_try_st :: ins_not_ready :: ins_chan) (sp + 13)
      lower agent call env "stop" (ag_e:[]) bound_locals sp st =
        st1 = lower expr env ag_e bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        no_jobs_lbl = nc lbl st2
        loop_lbl = no_jobs_lbl + 1
        st_stop_lbl = no_jobs_lbl + 2
        st_stop_await_lbl = no_jobs_lbl + 3
        st_stop_await_lbl2 = no_jobs_lbl + 4
        st3 = nc set lbl st2 (no_jobs_lbl + 5)
        ins_open = [NTupleGet sp 1, NStoreSlot (sp + 1), NCloneSlot (sp + 1), NStoreSlot (sp + 2), NCallBuiltin 32 (sp + 2) 1, NStoreSlot (sp + 2), NTupleGet (sp + 2) 0, NStoreSlot (sp + 3), NTupleGet (sp + 2) 1, NStoreSlot (sp + 4), NMatchInt (sp + 3) 3, NJumpIfZero st_stop_lbl]
        ins_loop = [NLabel loop_lbl, NMatchNonEmpty (sp + 4), NJumpIfZero no_jobs_lbl, NListHead (sp + 4), NStoreSlot (sp + 5), NListTail (sp + 4), NStoreSlot (sp + 4), NCallBuiltin 59 (sp + 5) 1, NDropVal, NJump loop_lbl]
        ins_st_stop = [NLabel st_stop_lbl, NMatchInt (sp + 3) 2, NJumpIfZero no_jobs_lbl, NTupleGet (sp + 4) 1, NStoreSlot (sp + 5), NMatchInt (sp + 5) 0, NJumpIfZero st_stop_await_lbl, NJump no_jobs_lbl, NLabel st_stop_await_lbl, NMatchInt (sp + 5) 1, NJumpIfZero st_stop_await_lbl2, NJump no_jobs_lbl, NLabel st_stop_await_lbl2, NCallBuiltin 59 (sp + 5) 1, NDropVal]
        ins_close = [NLabel no_jobs_lbl, NLoadImmInt 0, NStoreSlot (sp + 2), NLoadImmInt 0, NStoreSlot (sp + 3), NMakeTuple (sp + 2) 2, NStoreSlot (sp + 2), NCloneSlot (sp + 1), NStoreSlot (sp + 3), NCallBuiltin 50 (sp + 2) 2, NDropVal, NClearLocals sp (sp + 6), NLoadImmRaw 0]
        nc emit list st3 (ins_open :: ins_loop :: ins_st_stop :: ins_close) (sp + 6)
      lower agent call env "agent_alive" (ag_e:[]) bound_locals sp st =
        alive_lbl = nc lbl st
        done_lbl = alive_lbl + 1
        st1 = nc set lbl st (alive_lbl + 2)
        st2 = lower expr env ag_e bound_locals sp st1
        ins = [NStoreSlot sp, NTupleGet sp 1, NStoreSlot (sp + 1), NCloneSlot (sp + 1), NStoreSlot (sp + 2), NCallBuiltin 32 (sp + 2) 1, NStoreSlot (sp + 2), NTupleGet (sp + 2) 0, NStoreSlot (sp + 3), NCloneSlot (sp + 2), NStoreSlot (sp + 4), NCloneSlot (sp + 1), NStoreSlot (sp + 5), NCallBuiltin 50 (sp + 4) 2, NDropVal, NMatchInt (sp + 3) 0, NJumpIfZero alive_lbl, NClearLocals sp (sp + 6), NLoadImmRaw 2, NJump done_lbl, NLabel alive_lbl, NClearLocals sp (sp + 6), NLoadImmRaw 6, NLabel done_lbl]
        nc emit list st2 ins (sp + 6)
      lower agent call _ _ _ _ _ st = st

fn :: select par collection builtin RNativeEnv String [RExpr] [String] => Int
      select par collection builtin env fname ((EVar callee_fn):_:[]) bound_locals
        | (fname == "||map" or fname == "par_map") and (lookup local bound_locals callee_fn) < 0 and (env fn arity env callee_fn) > 0 and (not (env fn is heavy env callee_fn)) = 53
        | (fname == "||filter" or fname == "par_filter") and (lookup local bound_locals callee_fn) < 0 and (env fn arity env callee_fn) > 0 and (not (env fn is heavy env callee_fn)) = 55
      select par collection builtin _ fname _ _ = builtin call id fname

fn :: lower plain indirect call RNativeEnv Int [RExpr] [String] Int RNativeCode => RNativeCode
      lower plain indirect call _ fn_slot [] _ sp st =
        nc emit st (NCloneSlot fn_slot) sp
      lower plain indirect call env fn_slot (a1:[]) bound_locals sp st =
        st1 = lower expr env a1 bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        nc emit st2 (NCallIndirect1 fn_slot sp) (sp + 1)
      lower plain indirect call env fn_slot (a1:a2:[]) bound_locals sp st =
        st1 = lower expr list to slots env [a1, a2] bound_locals sp 0 st
        nc emit st1 (NCallIndirect2 fn_slot sp) (sp + 2)
      lower plain indirect call env fn_slot (a1:rest) bound_locals sp st =
        rem_count = rexpr list len rest
        st1 = lower expr env a1 bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr list to slots env rest bound_locals (sp + 1) 0 st2
        st4 = nc emit list st3 [NMakeTuple (sp + 1) rem_count, NStoreSlot (sp + 1)] (sp + rem_count + 2)
        nc emit st4 (NCallIndirect2 fn_slot sp) (sp + rem_count + 2)

fn :: lower indirect call slots RNativeEnv Int [RExpr] [String] Int RNativeCode => RNativeCode
      lower indirect call slots _ fn_slot [] _ sp st =
        nc emit st (NCloneSlot fn_slot) sp
      lower indirect call slots env fn_slot args bound_locals sp st =
        count = rexpr list len args
        plain_lbl = nc lbl st
        done_lbl = plain_lbl + 1
        st0 = nc set lbl st (plain_lbl + 2)
        st1 = nc emit list st0 [NMatchTuple fn_slot 2, NJumpIfZero plain_lbl, NTupleGet fn_slot 0, NStoreSlot sp, NTupleGet fn_slot 1, NStoreSlot (sp + 1)] (sp + 2)
        st2 = lower expr list to slots env args bound_locals (sp + 2) 0 st1
        ins_clos = [NMakeList (sp + 2) count, NBinOp 14 (sp + 1), NStoreSlot (sp + 1), NListHead (sp + 1), NStoreSlot (sp + 2), NListTail (sp + 1), NStoreSlot (sp + 3), NMoveSlot (sp + 2), NStoreSlot (sp + 1), NMoveSlot (sp + 3), NStoreSlot (sp + 2), NCallIndirect2 sp (sp + 1), NStoreSlot (sp + 1), NClearLocals sp (sp + 1), NMoveSlot (sp + 1), NJump done_lbl, NLabel plain_lbl]
        st3 = nc emit list st2 ins_clos (sp + count + 4)
        st4 = lower plain indirect call env fn_slot args bound_locals sp st3
        nc emit st4 (NLabel done_lbl) (sp + count + 4)

fn :: lower map or closure map RNativeEnv String [RExpr] [String] Int RNativeCode => RNativeCode
      lower map or closure map env fname ((EVar target_fn):list_e:[]) bound_locals sp st
        | (lookup local bound_locals target_fn) < 0 and (env fn arity env target_fn) == 1 and (select par collection builtin env fname [EVar target_fn, list_e] bound_locals) == 53 =
          fid = env fn id env target_fn
          loop_lbl = nc lbl st
          done_lbl = loop_lbl + 1
          st0 = nc set lbl st (loop_lbl + 2)
          st1 = lower expr env list_e bound_locals sp st0
          ins = [NStoreSlot sp, NMakeList (sp + 1) 0, NStoreSlot (sp + 1), NLabel loop_lbl, NMatchNonEmpty sp, NJumpIfZero done_lbl, NListHead sp, NStoreSlot (sp + 2), NCallFn fid (sp + 2) 1, NStoreSlot (sp + 2), NMakeList (sp + 2) 1, NBinOp 14 (sp + 1), NStoreSlot (sp + 1), NListTail sp, NStoreSlot sp, NJump loop_lbl, NLabel done_lbl, NClearLocals sp (sp + 1), NClearLocals (sp + 2) (sp + 3), NMoveSlot (sp + 1)]
          nc emit list st1 ins (sp + 3)
      lower map or closure map env fname (fn_e:list_e:[]) bound_locals sp st =
        bid = select par collection builtin env fname [fn_e, list_e] bound_locals
        plain_lbl = nc lbl st
        loop_lbl = plain_lbl + 1
        done_lbl = plain_lbl + 2
        after_lbl = plain_lbl + 3
        st0 = nc set lbl st (plain_lbl + 4)
        st1 = lower expr list to slots env [fn_e, list_e] bound_locals sp 0 st0
        ins_clos = [NMatchTuple sp 2, NJumpIfZero plain_lbl, NMakeList (sp + 2) 0, NStoreSlot (sp + 2), NLabel loop_lbl, NMatchNonEmpty (sp + 1), NJumpIfZero done_lbl, NTupleGet sp 0, NStoreSlot (sp + 3), NTupleGet sp 1, NStoreSlot (sp + 4), NListHead (sp + 1), NStoreSlot (sp + 5), NMakeList (sp + 5) 1, NBinOp 14 (sp + 4), NStoreSlot (sp + 4), NListHead (sp + 4), NStoreSlot (sp + 5), NListTail (sp + 4), NStoreSlot (sp + 6), NMoveSlot (sp + 5), NStoreSlot (sp + 4), NMoveSlot (sp + 6), NStoreSlot (sp + 5), NCallIndirect2 (sp + 3) (sp + 4), NStoreSlot (sp + 5), NMakeList (sp + 5) 1, NBinOp 14 (sp + 2), NStoreSlot (sp + 2), NListTail (sp + 1), NStoreSlot (sp + 1), NJump loop_lbl, NLabel done_lbl, NClearLocals sp (sp + 2), NClearLocals (sp + 3) (sp + 7), NMoveSlot (sp + 2), NJump after_lbl, NLabel plain_lbl, NCallBuiltin bid sp 2, NLabel after_lbl]
        nc emit list st1 ins_clos (sp + 7)
      lower map or closure map env fname args bound_locals sp st =
        count = rexpr list len args
        bid = select par collection builtin env fname args bound_locals
        st1 = lower expr list to slots env args bound_locals sp 0 st
        nc emit st1 (NCallBuiltin bid sp count) (sp + count + 1)

fn :: lower filter or closure filter RNativeEnv String [RExpr] [String] Int RNativeCode => RNativeCode
      lower filter or closure filter env fname ((EVar target_fn):list_e:[]) bound_locals sp st
        | (lookup local bound_locals target_fn) < 0 and (env fn arity env target_fn) == 1 and (select par collection builtin env fname [EVar target_fn, list_e] bound_locals) == 55 =
          fid = env fn id env target_fn
          loop_lbl = nc lbl st
          skip_lbl = loop_lbl + 1
          done_lbl = loop_lbl + 2
          st0 = nc set lbl st (loop_lbl + 3)
          st1 = lower expr env list_e bound_locals sp st0
          ins = [NStoreSlot sp, NMakeList (sp + 1) 0, NStoreSlot (sp + 1), NLabel loop_lbl, NMatchNonEmpty sp, NJumpIfZero done_lbl, NListHead sp, NStoreSlot (sp + 2), NCallFn fid (sp + 2) 1, NAsBool, NJumpIfZero skip_lbl, NListHead sp, NStoreSlot (sp + 2), NMakeList (sp + 2) 1, NBinOp 14 (sp + 1), NStoreSlot (sp + 1), NLabel skip_lbl, NListTail sp, NStoreSlot sp, NJump loop_lbl, NLabel done_lbl, NClearLocals sp (sp + 1), NClearLocals (sp + 2) (sp + 3), NMoveSlot (sp + 1)]
          nc emit list st1 ins (sp + 3)
      lower filter or closure filter env fname (fn_e:list_e:[]) bound_locals sp st =
        bid = select par collection builtin env fname [fn_e, list_e] bound_locals
        plain_lbl = nc lbl st
        loop_lbl = plain_lbl + 1
        skip_lbl = plain_lbl + 2
        done_lbl = plain_lbl + 3
        after_lbl = plain_lbl + 4
        st0 = nc set lbl st (plain_lbl + 5)
        st1 = lower expr list to slots env [fn_e, list_e] bound_locals sp 0 st0
        ins_clos = [NMatchTuple sp 2, NJumpIfZero plain_lbl, NMakeList (sp + 2) 0, NStoreSlot (sp + 2), NLabel loop_lbl, NMatchNonEmpty (sp + 1), NJumpIfZero done_lbl, NTupleGet sp 0, NStoreSlot (sp + 3), NTupleGet sp 1, NStoreSlot (sp + 4), NListHead (sp + 1), NStoreSlot (sp + 5), NMakeList (sp + 5) 1, NBinOp 14 (sp + 4), NStoreSlot (sp + 4), NListHead (sp + 4), NStoreSlot (sp + 5), NListTail (sp + 4), NStoreSlot (sp + 6), NMoveSlot (sp + 5), NStoreSlot (sp + 4), NMoveSlot (sp + 6), NStoreSlot (sp + 5), NCallIndirect2 (sp + 3) (sp + 4), NAsBool, NJumpIfZero skip_lbl, NListHead (sp + 1), NStoreSlot (sp + 5), NMakeList (sp + 5) 1, NBinOp 14 (sp + 2), NStoreSlot (sp + 2), NLabel skip_lbl, NListTail (sp + 1), NStoreSlot (sp + 1), NJump loop_lbl, NLabel done_lbl, NClearLocals sp (sp + 2), NClearLocals (sp + 3) (sp + 7), NMoveSlot (sp + 2), NJump after_lbl, NLabel plain_lbl, NCallBuiltin bid sp 2, NLabel after_lbl]
        nc emit list st1 ins_clos (sp + 7)
      lower filter or closure filter env fname args bound_locals sp st =
        count = rexpr list len args
        bid = select par collection builtin env fname args bound_locals
        st1 = lower expr list to slots env args bound_locals sp 0 st
        nc emit st1 (NCallBuiltin bid sp count) (sp + count + 1)

fn :: lower fold or closure fold RNativeEnv [RExpr] [String] Int RNativeCode => RNativeCode
      lower fold or closure fold env ((EVar target_fn):init_e:list_e:[]) bound_locals sp st
        | (lookup local bound_locals target_fn) < 0 and (env fn arity env target_fn) == 2 =
          fid = env fn id env target_fn
          loop_lbl = nc lbl st
          done_lbl = loop_lbl + 1
          st0 = nc set lbl st (loop_lbl + 2)
          st1 = lower expr list to slots env [init_e, list_e] bound_locals sp 0 st0
          ins = [NLabel loop_lbl, NMatchNonEmpty (sp + 1), NJumpIfZero done_lbl, NMoveSlot sp, NStoreSlot (sp + 2), NListHead (sp + 1), NStoreSlot (sp + 3), NCallFn fid (sp + 2) 2, NStoreSlot sp, NListTail (sp + 1), NStoreSlot (sp + 1), NJump loop_lbl, NLabel done_lbl, NClearLocals (sp + 1) (sp + 4), NMoveSlot sp]
          nc emit list st1 ins (sp + 4)
      lower fold or closure fold env (fn_e:init_e:list_e:[]) bound_locals sp st =
        plain_lbl = nc lbl st
        loop_lbl = plain_lbl + 1
        done_lbl = plain_lbl + 2
        after_lbl = plain_lbl + 3
        st0 = nc set lbl st (plain_lbl + 4)
        st1 = lower expr list to slots env [fn_e, init_e, list_e] bound_locals sp 0 st0
        ins_clos = [NMatchTuple sp 2, NJumpIfZero plain_lbl, NLabel loop_lbl, NMatchNonEmpty (sp + 2), NJumpIfZero done_lbl, NTupleGet sp 0, NStoreSlot (sp + 3), NTupleGet sp 1, NStoreSlot (sp + 4), NMoveSlot (sp + 1), NStoreSlot (sp + 5), NListHead (sp + 2), NStoreSlot (sp + 6), NMakeList (sp + 5) 2, NBinOp 14 (sp + 4), NStoreSlot (sp + 4), NListHead (sp + 4), NStoreSlot (sp + 5), NListTail (sp + 4), NStoreSlot (sp + 6), NMoveSlot (sp + 5), NStoreSlot (sp + 4), NMoveSlot (sp + 6), NStoreSlot (sp + 5), NCallIndirect2 (sp + 3) (sp + 4), NStoreSlot (sp + 1), NListTail (sp + 2), NStoreSlot (sp + 2), NJump loop_lbl, NLabel done_lbl, NCmmDropSlot sp, NClearLocals (sp + 2) (sp + 7), NMoveSlot (sp + 1), NJump after_lbl, NLabel plain_lbl, NCallBuiltin 61 sp 3, NLabel after_lbl]
        nc emit list st1 ins_clos (sp + 7)
      lower fold or closure fold env args bound_locals sp st =
        count = rexpr list len args
        st1 = lower expr list to slots env args bound_locals sp 0 st
        nc emit st1 (NCallBuiltin 61 sp count) (sp + count + 1)

fn :: lower direct or partial call RNativeEnv String [RExpr] Int Int [String] Int RNativeCode => RNativeCode
      lower direct or partial call env fname args count fn_ar bound_locals sp st
        | count > 0 and fn_ar > count =
          off = env str off env fname
          slen = str len fname
          st1 = nc emit list st [NLoadStrLit off slen, NStoreSlot sp] (sp + 1)
          st2 = lower expr list to slots env args bound_locals (sp + 1) 0 st1
          nc emit list st2 [NMakeList (sp + 1) count, NStoreSlot (sp + 1), NMakeTuple sp 2] (sp + count + 2)
        | count == fn_ar =
          st1 = lower expr list to slots env args bound_locals sp 0 st
          nc emit st1 (NCallFn (env fn id env fname) sp count) (sp + count + 1)
        | otherwise =
          st1 = lower expr list to slots env args bound_locals sp 0 st
          nc emit st1 (NCallFn (env fn id env fname) sp (0 - 1)) (sp + count + 1)

fn :: lower call expr RNativeEnv String [RExpr] [String] Int RNativeCode => RNativeCode
      lower call expr env "__chain__" (fn_e:call_args) bound_locals sp st =
        st1 = lower expr env fn_e bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        lower indirect call slots env sp call_args bound_locals (sp + 1) st2
      lower call expr env fname args bound_locals sp st
        | is agent call name fname = lower agent call env fname args bound_locals sp st
        | is tensor helper name fname = lower tensor helper env fname args bound_locals sp st
        | (lookup local bound_locals fname) >= 0 =
          lower indirect call slots env (env var slot env fname) args bound_locals sp st
      lower call expr env fname [] _ sp st
        | fname == "sys_os" =
          nc emit st (NLoadAdt0 (env str off env "Linux") 5) sp
        | fname == "sys_arch" =
          nc emit st (NLoadAdt0 (0 - 1) 0) sp
      lower call expr env fname (a1:[]) bound_locals sp st
        | (prim type tag id fname) > 0 =
          lower expr env a1 bound_locals sp st
      lower call expr env fname (rec_e:call_args) bound_locals sp st
        | (env has field env fname) and (env fn arity env fname) == 1 and (rexpr list len call_args) >= 1 =
          fidx = env field idx env fname
          st1 = lower expr env rec_e bound_locals sp st
          st2 = nc emit list st1 [NStoreSlot sp, NAdtField sp fidx, NStoreSlot sp] (sp + 1)
          lower indirect call slots env sp call_args bound_locals (sp + 1) st2
      lower call expr env fname args bound_locals sp st
        | is upper ident fname =
          count = rexpr list len args
          c_tag = ident base name fname
          off = env str off env c_tag
          slen = str len c_tag
          lower adt ctor call env args bound_locals off slen count sp st
        | fname == "map" or fname == "||map" or fname == "seq_map" or fname == "par_map" =
          lower map or closure map env fname args bound_locals sp st
        | fname == "filter" or fname == "||filter" or fname == "seq_filter" or fname == "par_filter" =
          lower filter or closure filter env fname args bound_locals sp st
        | fname == "fold" =
          lower fold or closure fold env args bound_locals sp st
      lower call expr env "sha256_raw" ((EBin OpAdd a b):[]) bound_locals sp st
        | (lookup local bound_locals "sha256_raw") < 0 =
          st1 = lower expr list to slots env [a, b] bound_locals sp 0 st
          nc emit st1 (NCallBuiltin 89 sp 2) (sp + 3)
      lower call expr env "str_char_at" ((EVar s_var):idx_e:[]) bound_locals sp st
        | (lookup local bound_locals "str_char_at") < 0 and (lookup local bound_locals s_var) >= 0 =
          s_slot = env var slot env s_var
          st1 = lower expr env idx_e bound_locals sp st
          nc emit st1 (NCallBuiltin 91 s_slot 0) sp
      lower call expr env fname args bound_locals sp st
        | (builtin call id fname) >= 0 and ((std builtin arity fname) <= 0 or (rexpr list len args) >= (std builtin arity fname)) =
          count = rexpr list len args
          bid = select par collection builtin env fname args bound_locals
          st1 = lower expr list to slots env args bound_locals sp 0 st
          nc emit st1 (NCallBuiltin bid sp count) (sp + count + 1)
        | otherwise =
          count = rexpr list len args
          fn_ar = env fn arity env fname
          lower direct or partial call env fname args count fn_ar bound_locals sp st

fn :: build tuple unpack instrs Int Int Int => [RNativeInstr]
      build tuple unpack instrs tup_slot count idx
        | idx >= count = []
        | otherwise =
          [NTupleGet tup_slot idx, NStoreSlot (tup_slot + 1 + idx)] :: (build tuple unpack instrs tup_slot count (idx + 1))

fn :: lower adt ctor call RNativeEnv [RExpr] [String] Int Int Int Int RNativeCode => RNativeCode
      lower adt ctor call _ [] _ off slen 0 sp st =
        nc emit st (NLoadAdt0 off slen) sp
      lower adt ctor call env args bound_locals off slen count sp st =
        st1 = lower expr list to slots env args bound_locals sp 0 st
        nc emit st1 (NMakeAdt off slen sp count) (sp + count + 1)

fn :: lower expr RNativeEnv RExpr [String] Int RNativeCode => RNativeCode
      lower expr _ (EInt n) _ sp st =
        nc emit st (NLoadImmInt n) sp
      lower expr env (EReal r) _ sp st =
        off = env str off env r
        nc emit st (NLoadRealLit off (str len r)) sp
      lower expr env (EStr s) _ sp st =
        off = env str off env s
        nc emit st (NLoadStrLit off (str len s)) sp
      lower expr env (EStrInterp parts) bound_locals sp st =
        count = rexpr list len parts
        st1 = lower expr list to slots env parts bound_locals sp 0 st
        nc emit st1 (NStrInterp sp count) (sp + count + 1)
      lower expr _ (EBool True) _ sp st =
        nc emit st (NLoadImmRaw 6) sp
      lower expr _ (EBool False) _ sp st =
        nc emit st (NLoadImmRaw 2) sp
      lower expr _ EUnit _ sp st =
        nc emit st (NLoadImmRaw 0) sp
      lower expr env (EVar name) bound_locals sp st =
        lower var expr env name bound_locals sp st
      lower expr env (ENot inner) bound_locals sp st =
        st1 = lower expr env inner bound_locals sp st
        nc emit st1 NNot sp
      lower expr env (EOut inner) bound_locals sp st =
        st1 = lower expr env inner bound_locals sp st
        nc emit st1 NOut sp
      lower expr env (EBin bop l r) bound_locals sp st =
        st1 = lower expr env l bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr env r bound_locals (sp + 1) st2
        nc emit st3 (NBinOp (binop id bop) sp) (sp + 1)
      lower expr env (ECall "__record_update__" (base_e:rest_args)) bound_locals sp st =
        st1 = lower expr env base_e bound_locals sp st
        lower record updates env rest_args bound_locals sp st1
      lower expr env (ECall "__unpack2__" ((EVar fn_target):single_arg:[])) bound_locals sp st =
        st1 = lower expr env single_arg bound_locals sp st
        fid = env fn id env fn_target
        arity = max int (env fn arity env fn_target) 2
        unpack_ins = build tuple unpack instrs sp arity 0
        ins_list = [NStoreSlot sp] :: unpack_ins :: [NClearLocals sp (sp + 1), NCallFn fid (sp + 1) arity]
        nc emit list st1 ins_list (sp + arity + 1)
      lower expr env (ECall fname args) bound_locals sp st =
        lower call expr env fname args bound_locals sp st
      lower expr env (EEcho args) bound_locals sp st =
        count = rexpr list len args
        st1 = lower expr list to slots env args bound_locals sp 0 st
        nc emit st1 (NEcho sp count) (sp + count + 1)
      lower expr env (EList elems) bound_locals sp st =
        count = rexpr list len elems
        st1 = lower expr list to slots env elems bound_locals sp 0 st
        nc emit st1 (NMakeList sp count) (sp + count + 1)
      lower expr env (ETuple elems) bound_locals sp st =
        count = rexpr list len elems
        st1 = lower expr list to slots env elems bound_locals sp 0 st
        nc emit st1 (NMakeTuple sp count) (sp + count + 1)
      lower expr env (ETensor elems) bound_locals sp st =
        count = rexpr list len elems
        st1 = lower expr list to slots env elems bound_locals sp 0 st
        nc emit st1 (NMakeTensor sp count) (sp + count + 1)
      lower expr env (EEinsum es subs) bound_locals sp st =
        count = rexpr list len es
        spec = join comma subs
        off = env str off env spec
        st1 = lower expr list to slots env es bound_locals sp 0 st
        nc emit st1 (NEinsum sp count off (str len spec)) (sp + count + 1)
      lower expr env (EHadamard bop l s1 r s2) bound_locals sp st
        | (bop == OpXor or bop == OpAnd or bop == OpOr) or (s1 == s2 and (bop == OpAdd or bop == OpSub or bop == OpMul)) =
          lower bitwise hadamard env bop l r bound_locals sp st
        | otherwise =
          subs = s1 + "," + s2
          off = env str off env subs
          st1 = lower expr env l bound_locals sp st
          st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
          st3 = lower expr env r bound_locals (sp + 1) st2
          nc emit st3 (NHadamard (binop id bop) sp off (str len subs)) (sp + 1)
      lower expr env (EIndex (EVar v) ((EInt idx):[])) _ sp st
        | (str starts with v ":tup-") or (str starts with v ":idx-tup-") =
          nc emit st (NTupleGet (env var slot env v) idx) sp
      lower expr env (EIndex (EVar v) idxs) bound_locals sp st
        | (lookup local bound_locals v) >= 0 and ((rexpr list len idxs) == 1 or (rexpr list len idxs) == 2) =
          count = rexpr list len idxs
          vslot = env var slot env v
          st1 = lower expr list to slots env idxs bound_locals sp 0 st
          nc emit st1 (NIndex vslot sp (0 - count)) (sp + count + 1)
      lower expr env (EIndex base idxs) bound_locals sp st =
        count = rexpr list len idxs
        st1 = lower expr env base bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower expr list to slots env idxs bound_locals (sp + 1) 0 st2
        nc emit st3 (NIndex sp (sp + 1) count) (sp + count + 2)
      lower expr env (EIndexAssign target idxs val_e) bound_locals sp st =
        count = rexpr list len idxs
        tslot = env var slot env target
        st1 = lower expr list to slots env idxs bound_locals sp 0 st
        st2 = lower expr env val_e bound_locals (sp + count) st1
        nc emit list st2 [NIndexSet tslot sp count, NStoreSlot tslot, NCloneSlot tslot] (sp + count + 1)
      lower expr env (ESeqSelect base mask) bound_locals sp st =
        off = env str off env mask
        st1 = lower expr env base bound_locals sp st
        nc emit st1 (NSeqSelect off (str len mask)) sp
      lower expr env (EBlock stmts) bound_locals sp st =
        lower stmts cmm env stmts bound_locals [] sp st
      lower expr env (EGuard guards) bound_locals sp st =
        end_lbl = nc lbl st
        st1 = nc set lbl st (end_lbl + 1)
        lower expr guards env guards bound_locals end_lbl sp st1
      lower expr env (EWhere body binds) bound_locals sp st =
        lower where cmm env binds body bound_locals [] sp st
      lower expr env (EParPipe branches) bound_locals sp st
        | (rexpr list len branches) >= 2 and (all exprs par eval env branches bound_locals) =
          count = rexpr list len branches
          par_off = env str off env "__rg_par_eval__"
          st1 = lower par eval list env branches bound_locals sp 0 st
          st2 = nc emit list st1 [NMakeList sp count, NStoreSlot (sp + 1), NLoadStrLit par_off 15, NStoreSlot sp, NCallBuiltin 54 sp 2, NStoreSlot sp] (sp + count + 2)
          st3 = unpack par list to slots sp count 0 st2
          nc emit list st3 [NClearLocals sp (sp + 1), NMakeTuple (sp + 1) count] (sp + count + 2)
        | otherwise =
          count = rexpr list len branches
          st1 = lower expr list to slots env branches bound_locals sp 0 st
          nc emit st1 (NMakeTuple sp count) (sp + count + 1)
      lower expr env (EWithCtx _ val_e body) bound_locals sp st =
        st1 = lower expr env val_e bound_locals sp st
        st2 = nc emit list st1 [NStoreSlot sp, NCallBuiltin 84 sp 1] (sp + 1)
        st3 = lower expr env body bound_locals sp st2
        nc emit list st3 [NStoreSlot sp, NCallBuiltin 85 sp 1] (sp + 1)
      lower expr env (EWithRegion quota body) bound_locals sp st =
        st1 = nc emit st NEnterRegion sp
        st2 = lower expr env body bound_locals sp st1
        nc emit st2 (NExitRegion quota) sp

fn :: lower expr guards RNativeEnv [RGuard] [String] Int Int RNativeCode => RNativeCode
      lower expr guards _ [] _ end_lbl sp st =
        nc emit list st [NLoadImmRaw 0, NLabel end_lbl] sp
      lower expr guards env ((GuardBranch cond body):gs) bound_locals end_lbl sp st =
        next_lbl = nc lbl st
        st1 = nc set lbl st (next_lbl + 1)
        st2 = lower expr env cond bound_locals sp st1
        st3 = nc emit list st2 [NAsBool, NJumpIfZero next_lbl] sp
        st4 = lower expr env body bound_locals sp st3
        st5 = nc emit list st4 [NJump end_lbl, NLabel next_lbl] sp
        lower expr guards env gs bound_locals end_lbl sp st5

fn :: lower final block expr RNativeEnv RExpr [String] [String] Int RNativeCode => RNativeCode
      lower final block expr env (EVar v) bound_locals _ sp st
        | (lookup local bound_locals v) >= 0 =
          nc emit st (NMoveSlot (env var slot env v)) sp
      lower final block expr env e bound_locals [] sp st =
        lower expr env e bound_locals sp st
      lower final block expr env e bound_locals dead_vars sp st =
        st1 = lower expr env e bound_locals sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower cmm drops env dead_vars (sp + 1) st2
        nc emit st3 (NMoveSlot sp) (sp + 1)

fn :: lower let binding stmt RNativeEnv String RExpr [String] [String] [RStmt] Int RNativeCode => RNativeCode
      lower let binding stmt env v e bound_locals scope_vars rest sp st =
        used_in_e = cmm filter in list (cmm expr vars e []) scope_vars
        live_after = cmm stmts vars rest []
        live_with_v = add unique str v live_after
        dead_inputs = cmm filter not in list (cmm remove str v used_in_e) live_with_v
        st1 = lower expr env e bound_locals sp st
        st2 = lower let var store env v bound_locals sp st1
        st3 = lower cmm drops env dead_inputs sp st2
        st4 = lower unused let drop env v live_after sp st3
        lower stmts cmm env rest (add unique str v bound_locals) (add unique str v scope_vars) sp st4

fn :: lower stmts cmm RNativeEnv [RStmt] [String] [String] Int RNativeCode => RNativeCode
      lower stmts cmm _ [] _ _ sp st =
        nc emit st (NLoadImmRaw 0) sp
      lower stmts cmm env ((StmtExpr e):[]) bound_locals scope_vars sp st =
        used = cmm filter in list (cmm expr vars e []) scope_vars
        lower final block expr env e bound_locals used sp st
      lower stmts cmm env ((StmtIndexAssign t idxs e):[]) bound_locals scope_vars sp st =
        count = rexpr list len idxs
        tslot = env var slot env t
        st1 = lower expr list to slots env idxs bound_locals sp 0 st
        st2 = lower expr env e bound_locals (sp + count) st1
        st3 = nc emit list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        st4 = lower cmm drops env (cmm remove str t scope_vars) (sp + count + 1) st3
        nc emit st4 (NCloneSlot tslot) (sp + count + 1)
      lower stmts cmm env ((StmtLet v e):[]) bound_locals scope_vars sp st
        | v == "_" =
          used = cmm filter in list (cmm expr vars e []) scope_vars
          st1 = lower expr env e bound_locals sp st
          st2 = nc emit st1 NDropVal sp
          st3 = lower cmm drops env used sp st2
          nc emit st3 (NLoadImmRaw 0) sp
        | otherwise =
          used = cmm remove str v (cmm filter in list (cmm expr vars e []) scope_vars)
          st1 = lower expr env e bound_locals sp st
          st2 = lower let var store env v bound_locals sp st1
          st3 = lower cmm drops env used sp st2
          nc emit st3 (NMoveSlot (env var slot env v)) sp
      lower stmts cmm env ((StmtMut v e):[]) bound_locals scope_vars sp st =
        lower stmts cmm env [StmtLet v e] bound_locals scope_vars sp st
      lower stmts cmm env ((StmtLet v e):rest) bound_locals scope_vars sp st
        | v == "_" =
          used_in_e = cmm filter in list (cmm expr vars e []) scope_vars
          live_after = cmm stmts vars rest []
          dead_now = cmm filter not in list used_in_e live_after
          st1 = lower expr env e bound_locals sp st
          st2 = nc emit st1 NDropVal sp
          st3 = lower cmm drops env dead_now sp st2
          lower stmts cmm env rest bound_locals scope_vars sp st3
        | otherwise =
          lower let binding stmt env v e bound_locals scope_vars rest sp st
      lower stmts cmm env ((StmtMut v e):rest) bound_locals scope_vars sp st =
        lower let binding stmt env v e bound_locals scope_vars rest sp st
      lower stmts cmm env ((StmtIndexAssign t idxs e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm filter in list (cmm expr vars e (cmm expr list vars idxs [])) scope_vars
        live_after = add unique str t (cmm stmts vars rest [])
        dead_now = cmm filter not in list used_in_e live_after
        count = rexpr list len idxs
        tslot = env var slot env t
        st1 = lower expr list to slots env idxs bound_locals sp 0 st
        st2 = lower expr env e bound_locals (sp + count) st1
        st3 = nc emit list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        st4 = lower cmm drops env dead_now (sp + count + 1) st3
        lower stmts cmm env rest bound_locals scope_vars sp st4
      lower stmts cmm env ((StmtExpr e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm filter in list (cmm expr vars e []) scope_vars
        live_after = cmm stmts vars rest []
        dead_now = cmm filter not in list used_in_e live_after
        st1 = lower expr env e bound_locals sp st
        st2 = nc emit st1 NDropVal sp
        st3 = lower cmm drops env dead_now sp st2
        lower stmts cmm env rest bound_locals scope_vars sp st3

fn :: can par eval expr RNativeEnv RExpr [String] => Bool
      can par eval expr env (ECall fname args) bound_locals =
        arity = env fn arity env fname
        nargs = rexpr list len args
        (lookup local bound_locals fname) < 0 and (not (is upper ident fname)) and (builtin call id fname) < 0 and (not (is agent call name fname)) and fname != "sys_os" and fname != "sys_arch" and fname != "__record_update__" and fname != "__unpack2__" and arity >= 0 and arity <= 3 and nargs == arity and (env fn is heavy env fname)
      can par eval expr _ _ _ = False

fn :: all exprs par eval RNativeEnv [RExpr] [String] => Bool
      all exprs par eval _ [] _ = True
      all exprs par eval env (e:es) bound_locals
        | can par eval expr env e bound_locals = all exprs par eval env es bound_locals
        | otherwise = False

fn :: lower par eval arg RNativeEnv [RExpr] [String] Int RNativeCode => RNativeCode
      lower par eval arg _ [] _ slot st =
        nc emit list st [NLoadImmInt 0, NStoreSlot slot] (slot + 1)
      lower par eval arg env (a1:[]) bound_locals slot st =
        st1 = lower expr env a1 bound_locals slot st
        nc emit st1 (NStoreSlot slot) (slot + 1)
      lower par eval arg env args bound_locals slot st =
        count = rexpr list len args
        st1 = lower expr list to slots env args bound_locals slot 0 st
        nc emit list st1 [NMakeTuple slot count, NStoreSlot slot] (slot + count + 1)

fn :: lower par eval item RNativeEnv RExpr [String] Int RNativeCode => RNativeCode
      lower par eval item env (ECall fname args) bound_locals slot st =
        off = env str off env fname
        st1 = nc emit list st [NLoadStrLit off (str len fname), NStoreSlot slot] (slot + 1)
        st2 = lower par eval arg env args bound_locals (slot + 1) st1
        nc emit list st2 [NMakeTuple slot 2, NStoreSlot slot] (slot + 2)
      lower par eval item _ _ _ _ st = st

fn :: lower par eval list RNativeEnv [RExpr] [String] Int Int RNativeCode => RNativeCode
      lower par eval list _ [] _ _ _ st = st
      lower par eval list env (e:es) bound_locals sp idx st =
        st1 = lower par eval item env e bound_locals (sp + idx) st
        lower par eval list env es bound_locals sp (idx + 1) st1

fn :: unpack par list to slots Int Int Int RNativeCode => RNativeCode
      unpack par list to slots _ count idx st
        | idx >= count = st
      unpack par list to slots list_slot count idx st =
        dst = list_slot + 1 + idx
        st1 = nc emit list st [NListHead list_slot, NStoreSlot dst, NListTail list_slot, NStoreSlot list_slot] (dst + 1)
        unpack par list to slots list_slot count (idx + 1) st1

fn :: can par where pair RNativeEnv RExpr String RExpr String [String] => Bool
      can par where pair env e1 v1 e2 v2 bound_locals =
        v1 != "_" and v2 != "_" and v1 != v2 and (can par eval expr env e1 bound_locals) and (can par eval expr env e2 bound_locals) and (not (str in list v1 (cmm expr vars e2 [])))

fn :: emit par where pair RNativeEnv RExpr String RExpr String [RWhereBind] RExpr [String] [String] Int RNativeCode => RNativeCode
      emit par where pair env e1 v1 e2 v2 wbs body bound_locals scope_vars sp st =
        used_in_pair = cmm filter in list (cmm expr vars e2 (cmm expr vars e1 [])) scope_vars
        live_after = cmm where vars wbs body []
        live_with_vs = add unique str v1 (add unique str v2 live_after)
        dead_inputs = cmm filter not in list (cmm remove str v1 (cmm remove str v2 used_in_pair)) live_with_vs
        par_off = env str off env "__rg_par_eval__"
        st1 = lower par eval list env [e1, e2] bound_locals sp 0 st
        st2 = nc emit list st1 [NMakeList sp 2, NStoreSlot (sp + 1), NLoadStrLit par_off 15, NStoreSlot sp, NCallBuiltin 54 sp 2, NStoreSlot sp, NListHead sp] (sp + 4)
        st3 = lower let var store env v1 bound_locals (sp + 4) st2
        st4 = nc emit list st3 [NListTail sp, NStoreSlot sp, NListHead sp] (sp + 4)
        locals1 = add unique str v1 bound_locals
        st5 = lower let var store env v2 locals1 (sp + 4) st4
        st6 = nc emit st5 (NClearLocals sp (sp + 1)) (sp + 4)
        st7 = lower cmm drops env dead_inputs sp st6
        st8 = lower unused let drop env v1 (add unique str v2 live_after) sp st7
        lower unused let drop env v2 live_after sp st8

fn :: lower where cmm RNativeEnv [RWhereBind] RExpr [String] [String] Int RNativeCode => RNativeCode
      lower where cmm env [] body bound_locals scope_vars sp st =
        used = cmm filter in list (cmm expr vars body []) scope_vars
        lower final block expr env body bound_locals used sp st
      lower where cmm env ((WhereBind e1 v1 []):(WhereBind e2 v2 []):wbs) body bound_locals scope_vars sp st
        | can par where pair env e1 v1 e2 v2 bound_locals =
          st1 = emit par where pair env e1 v1 e2 v2 wbs body bound_locals scope_vars sp st
          locals2 = add unique str v2 (add unique str v1 bound_locals)
          scope2 = add unique str v2 (add unique str v1 scope_vars)
          lower where cmm env wbs body locals2 scope2 sp st1
      lower where cmm env ((WhereBind e v []):wbs) body bound_locals scope_vars sp st =
        used_in_e = cmm filter in list (cmm expr vars e []) scope_vars
        live_after = cmm where vars wbs body []
        live_with_v = add unique str v live_after
        dead_inputs = cmm filter not in list (cmm remove str v used_in_e) live_with_v
        st1 = lower expr env e bound_locals sp st
        st2 = lower let var store env v bound_locals sp st1
        st3 = lower cmm drops env dead_inputs sp st2
        st4 = lower unused let drop env v live_after sp st3
        lower where cmm env wbs body (add unique str v bound_locals) (add unique str v scope_vars) sp st4
      lower where cmm env ((WhereBind e v idxs):wbs) body bound_locals scope_vars sp st =
        count = int list len idxs
        tslot = env var slot env v
        st1 = lower int list to slots idxs sp 0 st
        st2 = lower expr env e bound_locals (sp + count) st1
        st3 = nc emit list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        lower where cmm env wbs body bound_locals scope_vars sp st3

-- ── Tail-Call Optimization (TCO) & Tail Return Lowering ─────

fn :: expr has self tail call String RExpr => Bool
      expr has self tail call target (ECall fname _) = fname == target
      expr has self tail call target (EBlock stmts) = stmts have self tail call target stmts
      expr has self tail call target (EGuard guards) = guards have self tail call target guards
      expr has self tail call target (EWhere body _) = expr has self tail call target body
      expr has self tail call _ _ = False

fn :: stmts have self tail call String [RStmt] => Bool
      stmts have self tail call _ [] = False
      stmts have self tail call target ((StmtExpr e):[]) = expr has self tail call target e
      stmts have self tail call target (_:rest) = stmts have self tail call target rest

fn :: guards have self tail call String [RGuard] => Bool
      guards have self tail call _ [] = False
      guards have self tail call target ((GuardBranch _ body):gs)
        | expr has self tail call target body = True
        | otherwise = guards have self tail call target gs

fn :: can move param var String [String] [String] [String] => Bool
      can move param var v locals scope_vars later_vars =
        ((lookup local locals v) >= 0) and (not (str in list v scope_vars)) and (not (str in list v later_vars))

fn :: lower tco arg expr RNativeEnv RExpr [RExpr] [String] [String] Int RNativeCode => RNativeCode
      lower tco arg expr env (EVar v) es bound_locals scope_vars sp st
        | can move param var v bound_locals scope_vars (cmm expr list vars es []) =
          nc emit st (NMoveSlot (env var slot env v)) sp
      lower tco arg expr env (EBin OpConcat l r) es bound_locals scope_vars sp st =
        st1 = lower tco arg expr env l ([r] :: es) bound_locals scope_vars sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower tco arg expr env r es bound_locals scope_vars (sp + 1) st2
        nc emit st3 (NBinOp 14 sp) (sp + 1)
      lower tco arg expr env (ETuple elems) es bound_locals scope_vars sp st =
        count = rexpr list len elems
        st1 = lower tco arg list to slots env elems es bound_locals scope_vars sp 0 st
        nc emit st1 (NMakeTuple sp count) (sp + count + 1)
      lower tco arg expr env (ECall fname args) es bound_locals scope_vars sp st
        | (lookup local bound_locals fname) < 0 and (not (is upper ident fname)) and (builtin call id fname) < 0 and (not (is agent call name fname)) and (not (is tensor helper name fname)) and fname != "sys_os" and fname != "sys_arch" and fname != "__record_update__" and fname != "__unpack2__" and fname != "__chain__" and (rexpr list len args) == (env fn arity env fname) and (not ((env has field env fname) and (env fn arity env fname) == 1 and (rexpr list len args) > 1)) =
          count = rexpr list len args
          st1 = lower tco arg list to slots env args es bound_locals scope_vars sp 0 st
          nc emit st1 (NCallFn (env fn id env fname) sp count) (sp + count + 1)
      lower tco arg expr env e _ bound_locals _ sp st =
        lower expr env e bound_locals sp st

fn :: lower tco arg list to slots RNativeEnv [RExpr] [RExpr] [String] [String] Int Int RNativeCode => RNativeCode
      lower tco arg list to slots _ [] _ _ _ _ _ st = st
      lower tco arg list to slots env (e:es) after bound_locals scope_vars sp idx st =
        cur_slot = sp + idx
        st1 = lower tco arg expr env e (es :: after) bound_locals scope_vars cur_slot st
        st2 = nc emit st1 (NStoreSlot cur_slot) (cur_slot + 1)
        lower tco arg list to slots env es after bound_locals scope_vars sp (idx + 1) st2

fn :: lower tail return RNativeEnv RExpr [String] Int RNativeCode => RNativeCode
      lower tail return env expr bound_locals sp st =
        lower tail return cmm env expr bound_locals [] sp st

fn :: lower tail return cmm RNativeEnv RExpr [String] [String] Int RNativeCode => RNativeCode
      lower tail return cmm env (ECall fname args) bound_locals scope_vars sp st
        | (builtin call id fname) < 0 and fname == (env fn name env) and (rexpr list len args) == (env arity env) and (lookup local bound_locals fname) < 0 =
          arity = env arity env
          st1 = lower tco arg list to slots env args [] bound_locals scope_vars sp 0 st
          st2 = lower cmm drops env scope_vars (sp + arity + 1) st1
          nc emit st2 (NTailCall sp arity) (sp + arity + 1)
      lower tail return cmm env (EBlock stmts) bound_locals scope_vars sp st =
        lower tail stmts cmm env stmts bound_locals scope_vars sp st
      lower tail return cmm env (EGuard guards) bound_locals scope_vars sp st
        | guards have self tail call (env fn name env) guards =
          lower tail guards cmm env guards bound_locals scope_vars sp st
      lower tail return cmm env (EWhere body binds) bound_locals scope_vars sp st =
        lower tail where cmm env binds body bound_locals scope_vars sp st
      lower tail return cmm env (EVar v) bound_locals _ sp st
        | (lookup local bound_locals v) >= 0 =
          nc emit list st [NMoveSlot (env var slot env v), NReturn] sp
      lower tail return cmm env expr bound_locals scope_vars sp st =
        used = cmm filter in list (cmm expr vars expr []) scope_vars
        lower tail return expr env expr bound_locals scope_vars used sp st

fn :: lower tail return expr RNativeEnv RExpr [String] [String] [String] Int RNativeCode => RNativeCode
      lower tail return expr env expr bound_locals scope_vars [] sp st =
        st1 = lower tco arg expr env expr [] bound_locals scope_vars sp st
        nc emit st1 NReturn sp
      lower tail return expr env expr bound_locals scope_vars used sp st =
        st1 = lower tco arg expr env expr [] bound_locals scope_vars sp st
        st2 = nc emit st1 (NStoreSlot sp) (sp + 1)
        st3 = lower cmm drops env used (sp + 1) st2
        nc emit list st3 [NMoveSlot sp, NReturn] (sp + 1)

fn :: lower tail guards cmm RNativeEnv [RGuard] [String] [String] Int RNativeCode => RNativeCode
      lower tail guards cmm env [] _ scope_vars sp st =
        st1 = lower cmm drops env scope_vars sp st
        nc emit list st1 [NLoadImmRaw 0, NReturn] sp
      lower tail guards cmm env ((GuardBranch cond body):gs) bound_locals scope_vars sp st =
        next_lbl = nc lbl st
        st1 = nc set lbl st (next_lbl + 1)
        st2 = lower expr env cond bound_locals sp st1
        st3 = nc emit list st2 [NAsBool, NJumpIfZero next_lbl] sp
        st4 = lower tail return cmm env body bound_locals scope_vars sp st3
        st5 = nc emit st4 (NLabel next_lbl) sp
        lower tail guards cmm env gs bound_locals scope_vars sp st5

fn :: lower tail let stmt RNativeEnv String RExpr [String] [String] [RStmt] Int RNativeCode => RNativeCode
      lower tail let stmt env v e bound_locals scope_vars rest sp st =
        used_in_e = cmm filter in list (cmm expr vars e []) scope_vars
        live_after = cmm stmts vars rest []
        live_with_v = add unique str v live_after
        dead_inputs = cmm filter not in list (cmm remove str v used_in_e) live_with_v
        st1 = lower expr env e bound_locals sp st
        st2 = lower let var store env v bound_locals sp st1
        st3 = lower cmm drops env dead_inputs sp st2
        st4 = lower unused let drop env v live_after sp st3
        lower tail stmts cmm env rest (add unique str v bound_locals) (add unique str v scope_vars) sp st4

fn :: lower tail stmts cmm RNativeEnv [RStmt] [String] [String] Int RNativeCode => RNativeCode
      lower tail stmts cmm _ [] _ _ sp st =
        nc emit list st [NLoadImmRaw 0, NReturn] sp
      lower tail stmts cmm env ((StmtExpr e):[]) bound_locals scope_vars sp st =
        lower tail return cmm env e bound_locals scope_vars sp st
      lower tail stmts cmm env ((StmtLet v e):rest) bound_locals scope_vars sp st
        | v == "_" =
          used_in_e = cmm filter in list (cmm expr vars e []) scope_vars
          live_after = cmm stmts vars rest []
          dead_now = cmm filter not in list used_in_e live_after
          st1 = lower expr env e bound_locals sp st
          st2 = nc emit st1 NDropVal sp
          st3 = lower cmm drops env dead_now sp st2
          lower tail stmts cmm env rest bound_locals scope_vars sp st3
        | otherwise =
          lower tail let stmt env v e bound_locals scope_vars rest sp st
      lower tail stmts cmm env ((StmtMut v e):rest) bound_locals scope_vars sp st =
        lower tail let stmt env v e bound_locals scope_vars rest sp st
      lower tail stmts cmm env ((StmtIndexAssign t idxs e):[]) bound_locals scope_vars sp st =
        count = rexpr list len idxs
        tslot = env var slot env t
        st1 = lower expr list to slots env idxs bound_locals sp 0 st
        st2 = lower expr env e bound_locals (sp + count) st1
        st3 = nc emit list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        st4 = lower cmm drops env (cmm remove str t scope_vars) (sp + count + 1) st3
        nc emit list st4 [NMoveSlot tslot, NReturn] (sp + count + 1)
      lower tail stmts cmm env ((StmtIndexAssign t idxs e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm filter in list (cmm expr vars e (cmm expr list vars idxs [])) scope_vars
        live_after = add unique str t (cmm stmts vars rest [])
        dead_now = cmm filter not in list used_in_e live_after
        count = rexpr list len idxs
        tslot = env var slot env t
        st1 = lower expr list to slots env idxs bound_locals sp 0 st
        st2 = lower expr env e bound_locals (sp + count) st1
        st3 = nc emit list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        st4 = lower cmm drops env dead_now (sp + count + 1) st3
        lower tail stmts cmm env rest bound_locals scope_vars sp st4
      lower tail stmts cmm env ((StmtExpr e):rest) bound_locals scope_vars sp st =
        used_in_e = cmm filter in list (cmm expr vars e []) scope_vars
        live_after = cmm stmts vars rest []
        dead_now = cmm filter not in list used_in_e live_after
        st1 = lower expr env e bound_locals sp st
        st2 = nc emit st1 NDropVal sp
        st3 = lower cmm drops env dead_now sp st2
        lower tail stmts cmm env rest bound_locals scope_vars sp st3

fn :: lower tail where cmm RNativeEnv [RWhereBind] RExpr [String] [String] Int RNativeCode => RNativeCode
      lower tail where cmm env [] body bound_locals scope_vars sp st =
        lower tail return cmm env body bound_locals scope_vars sp st
      lower tail where cmm env ((WhereBind e1 v1 []):(WhereBind e2 v2 []):wbs) body bound_locals scope_vars sp st
        | can par where pair env e1 v1 e2 v2 bound_locals =
          st1 = emit par where pair env e1 v1 e2 v2 wbs body bound_locals scope_vars sp st
          locals2 = add unique str v2 (add unique str v1 bound_locals)
          scope2 = add unique str v2 (add unique str v1 scope_vars)
          lower tail where cmm env wbs body locals2 scope2 sp st1
      lower tail where cmm env ((WhereBind e v []):wbs) body bound_locals scope_vars sp st =
        used_in_e = cmm filter in list (cmm expr vars e []) scope_vars
        live_after = cmm where vars wbs body []
        live_with_v = add unique str v live_after
        dead_inputs = cmm filter not in list (cmm remove str v used_in_e) live_with_v
        st1 = lower expr env e bound_locals sp st
        st2 = lower let var store env v bound_locals sp st1
        st3 = lower cmm drops env dead_inputs sp st2
        st4 = lower unused let drop env v live_after sp st3
        lower tail where cmm env wbs body (add unique str v bound_locals) (add unique str v scope_vars) sp st4
      lower tail where cmm env ((WhereBind e v idxs):wbs) body bound_locals scope_vars sp st =
        count = int list len idxs
        tslot = env var slot env v
        st1 = lower int list to slots idxs sp 0 st
        st2 = lower expr env e bound_locals (sp + count) st1
        st3 = nc emit list st2 [NIndexSet tslot sp count, NStoreSlot tslot] (sp + count + 1)
        lower tail where cmm env wbs body bound_locals scope_vars sp st3

-- ── Pattern Matching & Binding Lowering ──────────────────────

fn :: pat needs check RPattern       => Bool
      pat needs check PatWild        =  False
      pat needs check (PatVar _)     =  False
      pat needs check (PatSeqBind _) =  False
      pat needs check _              =  True

fn :: pat has vars RPattern         => Bool
      pat has vars (PatVar _)       =  True
      pat has vars (PatSeqBind _)   =  True
      pat has vars (PatCons h t)    =  (pat has vars h) or (pat has vars t)
      pat has vars (PatTuple ps)    =  pat list has vars ps
      pat has vars (PatCtor _ args) =  pat list has vars args
      pat has vars _                =  False

fn :: pat list has vars [RPattern] => Bool
      pat list has vars []         =  False
      pat list has vars (p:ps)
        | pat has vars p = True
        | otherwise = pat list has vars ps

fn :: lower pat cond RNativeEnv RPattern Int Int Int RNativeCode => RNativeCode
      lower pat cond _ PatWild _ _ _ st = st
      lower pat cond _ (PatVar _) _ _ _ st = st
      lower pat cond _ (PatSeqBind _) _ _ _ st = st
      lower pat cond _ (PatInt n) slot fail_lbl sp st =
        nc emit list st [NMatchInt slot n, NJumpIfZero fail_lbl] sp
      lower pat cond env (PatReal r) slot fail_lbl sp st =
        off = env str off env r
        nc emit list st [NMatchReal slot off (str len r), NJumpIfZero fail_lbl] sp
      lower pat cond env (PatStr s) slot fail_lbl sp st =
        off = env str off env s
        nc emit list st [NMatchStr slot off (str len s), NJumpIfZero fail_lbl] sp
      lower pat cond _ (PatBool True) slot fail_lbl sp st =
        nc emit list st [NMatchBool slot 1, NJumpIfZero fail_lbl] sp
      lower pat cond _ (PatBool False) slot fail_lbl sp st =
        nc emit list st [NMatchBool slot 0, NJumpIfZero fail_lbl] sp
      lower pat cond _ PatEmpty slot fail_lbl sp st =
        nc emit list st [NMatchEmpty slot, NJumpIfZero fail_lbl] sp
      lower pat cond env (PatCons h t) slot fail_lbl sp st =
        st1 = nc emit list st [NMatchNonEmpty slot, NJumpIfZero fail_lbl] sp
        st2 = lower pat cons sub env h slot True fail_lbl sp st1
        lower pat cons sub env t slot False fail_lbl sp st2
      lower pat cond env (PatTuple ps) slot fail_lbl sp st =
        arity = pat list len ps
        st1 = nc emit list st [NMatchTuple slot arity, NJumpIfZero fail_lbl] sp
        lower tuple pat conds env ps slot 0 fail_lbl sp st1
      lower pat cond env (PatCtor ":tensor-pat:" (t_pat:rank_pat:dim_pats)) slot fail_lbl sp st =
        st1 = nc emit list st [NMatchAdt slot 0 0 (0 - 5), NJumpIfZero fail_lbl] sp
        st2 = lower pat cond env t_pat slot fail_lbl sp st1
        st3 = lower tensor dim cond env rank_pat slot (0 - 1) fail_lbl sp st2
        lower tensor dims cond list env dim_pats slot 0 fail_lbl sp st3
      lower pat cond env (PatCtor c (sub_p:[])) slot fail_lbl sp st
        | (prim type tag id c) > 0 =
          st1 = nc emit list st [NMatchAdt slot 0 0 (0 - (prim type tag id c)), NJumpIfZero fail_lbl] sp
          lower pat cond env sub_p slot fail_lbl sp st1
      lower pat cond env (PatCtor c args) slot fail_lbl sp st =
        arity = pat list len args
        c_tag = ident base name c
        off = env str off env c_tag
        st1 = nc emit list st [NMatchAdt slot off (str len c_tag) arity, NJumpIfZero fail_lbl] sp
        lower adt pat conds env args slot 0 fail_lbl sp st1

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
        | not (pat needs check sub_p) = st
        | is_head =
          st1 = nc emit list st [NListHead slot, NStoreSlot sp] (sp + 1)
          st2 = lower pat cond env sub_p sp fail_lbl (sp + 1) st1
          nc emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
        | otherwise =
          st1 = nc emit list st [NListTail slot, NStoreSlot sp] (sp + 1)
          st2 = lower pat cond env sub_p sp fail_lbl (sp + 1) st1
          nc emit st2 (NClearLocals sp (sp + 1)) (sp + 1)

fn :: lower tuple pat conds RNativeEnv [RPattern] Int Int Int Int RNativeCode => RNativeCode
      lower tuple pat conds _ [] _ _ _ _ st = st
      lower tuple pat conds env (p:ps) slot idx fail_lbl sp st
        | not (pat needs check p) = lower tuple pat conds env ps slot (idx + 1) fail_lbl sp st
        | otherwise =
          st1 = nc emit list st [NTupleGet slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower pat cond env p sp fail_lbl (sp + 1) st1
          st3 = nc emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower tuple pat conds env ps slot (idx + 1) fail_lbl sp st3

fn :: lower adt pat conds RNativeEnv [RPattern] Int Int Int Int RNativeCode => RNativeCode
      lower adt pat conds _ [] _ _ _ _ st = st
      lower adt pat conds env (p:ps) slot idx fail_lbl sp st
        | not (pat needs check p) = lower adt pat conds env ps slot (idx + 1) fail_lbl sp st
        | otherwise =
          st1 = nc emit list st [NAdtField slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower pat cond env p sp fail_lbl (sp + 1) st1
          st3 = nc emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower adt pat conds env ps slot (idx + 1) fail_lbl sp st3

fn :: lower pat list cond RNativeEnv [RPattern] Int Int Int RNativeCode => RNativeCode
      lower pat list cond _ [] _ _ _ st = st
      lower pat list cond env (p:ps) idx fail_lbl sp st =
        st1 = lower pat cond env p idx fail_lbl sp st
        lower pat list cond env ps (idx + 1) fail_lbl sp st1

fn :: lower pat binds RNativeEnv RPattern Int Bool Int RNativeCode => RNativeCode
      lower pat binds env (PatVar v) slot True sp st =
        nc emit list st [NMoveSlot slot, NStoreSlot (env var slot env v)] sp
      lower pat binds env (PatVar v) slot False sp st =
        nc emit list st [NCloneSlot slot, NStoreSlot (env var slot env v)] sp
      lower pat binds env (PatSeqBind v) slot True sp st =
        nc emit list st [NMoveSlot slot, NStoreSlot (env var slot env v)] sp
      lower pat binds env (PatSeqBind v) slot False sp st =
        nc emit list st [NCloneSlot slot, NStoreSlot (env var slot env v)] sp
      lower pat binds env (PatCons h t) slot _ sp st =
        st1 = lower pat cons bind env h slot True sp st
        lower pat cons bind env t slot False sp st1
      lower pat binds env (PatTuple ps) slot _ sp st =
        lower tuple pat binds env ps slot 0 sp st
      lower pat binds env (PatCtor ":tensor-pat:" (t_pat:rank_pat:dim_pats)) slot move_ok sp st =
        st1 = lower tensor dim bind env rank_pat slot (0 - 1) sp st
        st2 = lower tensor dims bind list env dim_pats slot 0 sp st1
        lower pat binds env t_pat slot move_ok sp st2
      lower pat binds env (PatCtor c (sub_p:[])) slot move_ok sp st
        | (prim type tag id c) > 0 =
          lower pat binds env sub_p slot move_ok sp st
      lower pat binds env (PatCtor _ args) slot _ sp st =
        lower adt pat binds env args slot 0 sp st
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
        | not (pat has vars sub_p) = st
        | is_head =
          st1 = nc emit list st [NListHead slot, NStoreSlot sp] (sp + 1)
          st2 = lower pat binds env sub_p sp True (sp + 1) st1
          nc emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
        | otherwise =
          st1 = nc emit list st [NListTail slot, NStoreSlot sp] (sp + 1)
          st2 = lower pat binds env sub_p sp True (sp + 1) st1
          nc emit st2 (NClearLocals sp (sp + 1)) (sp + 1)

fn :: lower tuple pat binds RNativeEnv [RPattern] Int Int Int RNativeCode => RNativeCode
      lower tuple pat binds _ [] _ _ _ st = st
      lower tuple pat binds env (p:ps) slot idx sp st
        | not (pat has vars p) = lower tuple pat binds env ps slot (idx + 1) sp st
        | otherwise =
          st1 = nc emit list st [NTupleGet slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower pat binds env p sp True (sp + 1) st1
          st3 = nc emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower tuple pat binds env ps slot (idx + 1) sp st3

fn :: lower adt pat binds RNativeEnv [RPattern] Int Int Int RNativeCode => RNativeCode
      lower adt pat binds _ [] _ _ _ st = st
      lower adt pat binds env (p:ps) slot idx sp st
        | not (pat has vars p) = lower adt pat binds env ps slot (idx + 1) sp st
        | otherwise =
          st1 = nc emit list st [NAdtField slot idx, NStoreSlot sp] (sp + 1)
          st2 = lower pat binds env p sp True (sp + 1) st1
          st3 = nc emit st2 (NClearLocals sp (sp + 1)) (sp + 1)
          lower adt pat binds env ps slot (idx + 1) sp st3

fn :: lower pat list binds RNativeEnv [RPattern] Int Int Bool Int RNativeCode => RNativeCode
      lower pat list binds _ [] _ _ _ _ st = st
      lower pat list binds env ((PatSeqBind v):[]) _ arity _ sp st =
        nc emit list st [NPackSeq arity, NStoreSlot (env var slot env v)] sp
      lower pat list binds env ((PatVar v):ps) idx arity True sp st =
        st1 = nc emit list st [NMoveSlot idx, NStoreSlot (env var slot env v)] sp
        lower pat list binds env ps (idx + 1) arity True sp st1
      lower pat list binds env (p:ps) idx arity move_args sp st =
        st1 = lower pat binds env p idx False sp st
        lower pat list binds env ps (idx + 1) arity move_args sp st1

fn :: guards have otherwise [RGuard] => Bool
      guards have otherwise []       =  False
      guards have otherwise ((GuardBranch (EBool True) _):_) = True
      guards have otherwise (_:gs)   =  guards have otherwise gs

fn :: lower case guards RNativeEnv [RGuard] [String] Int RNativeCode => RNativeCode
      lower case guards _ [] _ _ st = st
      lower case guards env ((GuardBranch cond body):gs) bound_locals sp st =
        next_lbl = nc lbl st
        st1 = nc set lbl st (next_lbl + 1)
        st2 = lower expr env cond bound_locals sp st1
        st3 = nc emit list st2 [NAsBool, NJumpIfZero next_lbl] sp
        st4 = lower tail return env body bound_locals sp st3
        st5 = nc emit st4 (NLabel next_lbl) sp
        lower case guards env gs bound_locals sp st5

fn :: lower single case RNativeEnv RFnCase Bool Int RNativeCode => RNativeCode
      lower single case env (FnCase pats [] body) _ sp st =
        arity = env arity env
        fail_lbl = nc lbl st
        bound_locals = collect pat list vars pats []
        st -> nc set lbl (fail_lbl + 1)
          -> lower pat list cond env pats 0 fail_lbl sp _
          -> lower pat list binds env pats 0 arity True sp _
          -> lower tail return env body bound_locals sp _
          -> st4
        st4 -> nc emit list [NLabel fail_lbl, NClearLocals arity (nc max sp st4)] sp
      lower single case env (FnCase pats guards _) is_last sp st =
        arity = env arity env
        fail_lbl = nc lbl st
        move_args = is_last or (guards have otherwise guards)
        bound_locals = collect pat list vars pats []
        st -> nc set lbl (fail_lbl + 1)
          -> lower pat list cond env pats 0 fail_lbl sp _
          -> lower pat list binds env pats 0 arity move_args sp _
          -> lower case guards env guards bound_locals sp _
          -> st4
        st4 -> nc emit list [NLabel fail_lbl, NClearLocals arity (nc max sp st4)] sp

fn :: lower cases list RNativeEnv [RFnCase] Int RNativeCode => RNativeCode
      lower cases list _ [] _ st = st
      lower cases list env (c:[]) sp st = lower single case env c True sp st
      lower cases list env (c:cs) sp st =
        st1 = lower single case env c False sp st
        lower cases list env cs sp st1

fn :: wrap unit return stmts String [RStmt] => [RStmt]
      wrap unit return stmts _ [] = [StmtExpr EUnit]
      wrap unit return stmts _ ((StmtExpr EUnit):[]) = [StmtExpr EUnit]
      wrap unit return stmts name ((StmtExpr e):[])
        | expr has self tail call name e = [StmtExpr (wrap unit return expr name e)]
        | otherwise = [StmtExpr e, StmtExpr EUnit]
      wrap unit return stmts _ (last_s:[]) = [last_s, StmtExpr EUnit]
      wrap unit return stmts name (s:rest) = [s] :: (wrap unit return stmts name rest)

fn :: wrap unit return guards String [RGuard] => [RGuard]
      wrap unit return guards _ [] = []
      wrap unit return guards name ((GuardBranch c b):gs) =
        [GuardBranch c (wrap unit return expr name b)] :: (wrap unit return guards name gs)

fn :: wrap unit return expr String RExpr => RExpr
      wrap unit return expr _ EUnit = EUnit
      wrap unit return expr name (EBlock stmts) =
        EBlock (wrap unit return stmts name stmts)
      wrap unit return expr name (EGuard guards) =
        EGuard (wrap unit return guards name guards)
      wrap unit return expr name (EWhere body binds) =
        EWhere (wrap unit return expr name body) binds
      wrap unit return expr name e
        | expr has self tail call name e = e
        | otherwise = EBlock [StmtExpr e, StmtExpr EUnit]

fn :: wrap unit return cases String [RFnCase] => [RFnCase]
      wrap unit return cases _ [] = []
      wrap unit return cases name ((FnCase pats [] body):cs) =
        [FnCase pats [] (wrap unit return expr name body)] :: (wrap unit return cases name cs)
      wrap unit return cases name ((FnCase pats guards body):cs) =
        [FnCase pats (wrap unit return guards name guards) body] :: (wrap unit return cases name cs)

fn :: maybe wrap unit cases String String [RFnCase] => [RFnCase]
      maybe wrap unit cases name ret cases
        | ret == "()" or ret == "Unit" = wrap unit return cases name cases
        | otherwise = cases

fn :: lower fndef RFnDef [RStrEntry] [RFnEntry] [RFieldEntry] => RNativeFn
      lower fndef (FnDef name params ret raw_cases) str_tbl fn_tbl field_tbl =
        cases = maybe wrap unit cases name ret raw_cases
        fid = lookup fn id fn_tbl name
        arity = infer fndef arity params cases
        all_locals = collect cases all locals cases []
        base_sp = arity + (list str len all_locals)
        env = NativeEnv name arity all_locals str_tbl fn_tbl field_tbl
        init_st = NativeCode [] 1 (max int (base_sp + 1) 2)
        st1 = lower cases list env cases base_sp init_st
        st2 = nc emit list st1 [NLoadImmRaw 0, NReturn] (base_sp + 1)
        NativeFn fid name arity (nc max sp st2) (nc instrs st2)

fn :: lower fndef list [RFnDef] [RStrEntry] [RFnEntry] [RFieldEntry] => [RNativeFn]
      lower fndef list [] _ _ _ = []
      lower fndef list (f:fs) str_tbl fn_tbl field_tbl =
        [lower fndef f str_tbl fn_tbl field_tbl] :: (lower fndef list fs str_tbl fn_tbl field_tbl)

fn :: lower field getter fns [RFieldEntry] [String] [RFnEntry] => [RNativeFn]
      lower field getter fns [] _ _ = []
      lower field getter fns ((FieldEntry fname idx):rest) fn_names fn_tbl
        | str in list fname fn_names = lower field getter fns rest fn_names fn_tbl
        | otherwise =
          fid = lookup fn id fn_tbl fname
          [NativeFn fid fname 1 2 [NAdtField 0 idx, NReturn]] :: (lower field getter fns rest fn_names fn_tbl)

-- ── Call-Graph Tree-Shaking & Dispatch Function Synthesis ────

fn :: collect refs expr RExpr              [String] => [String]
      collect refs expr (EVar name)        acc      =  add unique str name acc
      collect refs expr (ENot inner)       acc      =  collect refs expr inner acc
      collect refs expr (EOut inner)       acc      =  collect refs expr inner acc
      collect refs expr (EBin bop l r)     acc      =  acc -> add unique str (binop op tag bop) _ -> collect refs expr l _ -> collect refs expr r _
      collect refs expr (ECall fname args) acc      =  acc -> add unique str fname _ -> collect refs expr list args _
      collect refs expr (EEcho args)       acc      =  collect refs expr list args acc
      collect refs expr (EStrInterp parts) acc      =  collect refs expr list parts acc
      collect refs expr (EList elems)      acc      =  collect refs expr list elems acc
      collect refs expr (ETuple elems)     acc      =  collect refs expr list elems acc
      collect refs expr (ETensor elems)    acc      =  collect refs expr list elems acc
      collect refs expr (EEinsum es _)     acc      =  collect refs expr list es acc
      collect refs expr (EHadamard _ l _ r _) acc   =  acc -> collect refs expr l _ -> collect refs expr r _
      collect refs expr (EIndex base idxs) acc      =  acc -> collect refs expr base _ -> collect refs expr list idxs _
      collect refs expr (EIndexAssign _ idxs v) acc =  acc -> collect refs expr list idxs _ -> collect refs expr v _
      collect refs expr (ESeqSelect b _)   acc      =  collect refs expr b acc
      collect refs expr (EBlock stmts)     acc      =  collect refs stmts stmts acc
      collect refs expr (EGuard guards)    acc      =  collect refs guards guards acc
      collect refs expr (EWhere body binds) acc     =  acc -> collect refs expr body _ -> collect refs where binds _
      collect refs expr (EParPipe branches) acc     =  collect refs expr list branches acc
      collect refs expr (EWithCtx _ v b)   acc      =  acc -> collect refs expr v _ -> collect refs expr b _
      collect refs expr (EWithRegion _ b)  acc      =  collect refs expr b acc
      collect refs expr _                  acc      =  acc

fn :: collect refs expr list [RExpr] [String] => [String]
      collect refs expr list [] acc = acc
      collect refs expr list (e:es) acc = acc -> collect refs expr e _ -> collect refs expr list es _

fn :: collect refs stmts [RStmt]            [String] => [String]
      collect refs stmts []                 acc      =  acc
      collect refs stmts ((StmtLet _ e):ss) acc      =  acc -> collect refs expr e _ -> collect refs stmts ss _
      collect refs stmts ((StmtMut _ e):ss) acc      =  acc -> collect refs expr e _ -> collect refs stmts ss _
      collect refs stmts ((StmtExpr e):ss)  acc      =  acc -> collect refs expr e _ -> collect refs stmts ss _
      collect refs stmts ((StmtIndexAssign _ idxs e):ss) acc =
        acc -> collect refs expr list idxs _ -> collect refs expr e _ -> collect refs stmts ss _

fn :: collect refs where [RWhereBind] [String] => [String]
      collect refs where []           acc      =  acc
      collect refs where ((WhereBind e _ _):wbs) acc = acc -> collect refs expr e _ -> collect refs where wbs _

fn :: collect refs guards [RGuard] [String] => [String]
      collect refs guards []       acc      =  acc
      collect refs guards ((GuardBranch c b):gs) acc =
        acc -> collect refs expr c _ -> collect refs expr b _ -> collect refs guards gs _

fn :: collect refs cases [RFnCase] [String] => [String]
      collect refs cases []        acc      =  acc
      collect refs cases ((FnCase _ guards body):cs) acc =
        acc -> collect refs guards guards _ -> collect refs expr body _ -> collect refs cases cs _

fn :: find fndef cases [RFnDef] String => [RFnCase]
      find fndef cases []       _      =  []
      find fndef cases ((FnDef name _ _ cases):fs) target
        | name == target = cases
        | otherwise = find fndef cases fs target

fn :: expand reachable worklist [String] [RFnDef] [String] => [String]
expand reachable worklist []       _        visited  =  visited
expand reachable worklist (w:ws)   all_fns  visited
| str in list w visited = expand reachable worklist ws all_fns visited
        | otherwise = expand reachable worklist (ws :: (collect refs cases (find fndef cases all_fns w) [])) all_fns (visited :: [w])

fn :: filter reachable fndefs [RFnDef] [String]  => [RFnDef]
      filter reachable fndefs []       _         =  []
      filter reachable fndefs ((FnDef name params ret cases):fs) reachable
        | str in list name reachable = [FnDef name params ret cases] :: (filter reachable fndefs fs reachable)
        | otherwise = filter reachable fndefs fs reachable

fn :: collect fn names [RFnDef] => [String]
      collect fn names []       =  []
      collect fn names ((FnDef name _ _ _):fs) = [name] :: (collect fn names fs)

fn :: find entry fn name [RFnDef] String => String
      find entry fn name [] fallback = fallback
      find entry fn name ((FnDef name params _ cases):fs) fallback
        | name == "main" = "main"
        | name == "demo_all" = "demo_all"
        | (infer fndef arity params cases) == 0 = find entry fn name fs name
        | otherwise = find entry fn name fs fallback

fn :: build spawn dispatch entry [RFnEntry] [RStrEntry] => [RNativeInstr]
      build spawn dispatch entry fn_tbl str_tbl =
        par_off = lookup str off str_tbl "__rg_par_eval__"
        par_hdr = [NMatchStr 0 par_off 15, NJumpIfZero 1, NTupleGet 1 0, NStoreSlot 2, NTupleGet 1 1, NStoreSlot 1, NMoveSlot 2, NStoreSlot 0, NLabel 1]
        build spawn dispatch instrs fn_tbl str_tbl 2 par_hdr

fn :: build spawn dispatch instrs [RFnEntry] [RStrEntry] Int [RNativeInstr] => [RNativeInstr]
      build spawn dispatch instrs [] _ _ acc =
        acc :: [NLoadImmRaw 0, NReturn]
      build spawn dispatch instrs ((FnEntry name fid arity):rest) str_tbl lbl acc
        | arity == 0 =
          off = lookup str off str_tbl name
          arm = [NMatchStr 0 off (str len name), NJumpIfZero lbl, NCallFn fid 2 0, NReturn, NLabel lbl]
          build spawn dispatch instrs rest str_tbl (lbl + 1) (acc :: arm)
        | arity == 1 =
          off = lookup str off str_tbl name
          arm = [NMatchStr 0 off (str len name), NJumpIfZero lbl, NMoveSlot 1, NStoreSlot 2, NCallFn fid 2 1, NReturn, NLabel lbl]
          build spawn dispatch instrs rest str_tbl (lbl + 1) (acc :: arm)
        | arity == 2 =
          off = lookup str off str_tbl name
          arm = [NMatchStr 0 off (str len name), NJumpIfZero lbl, NTupleGet 1 0, NStoreSlot 2, NTupleGet 1 1, NStoreSlot 3, NCallFn fid 2 2, NReturn, NLabel lbl]
          build spawn dispatch instrs rest str_tbl (lbl + 1) (acc :: arm)
        | arity == 3 =
          off = lookup str off str_tbl name
          lbl2 = lbl + 1
          arm = [NMatchStr 0 off (str len name), NJumpIfZero lbl2, NMatchTuple 1 2, NJumpIfZero lbl, NTupleGet 1 0, NStoreSlot 2, NTupleGet 1 1, NStoreSlot 5, NTupleGet 5 0, NStoreSlot 3, NTupleGet 5 1, NStoreSlot 4, NCallFn fid 2 3, NReturn, NLabel lbl, NTupleGet 1 0, NStoreSlot 2, NTupleGet 1 1, NStoreSlot 3, NTupleGet 1 2, NStoreSlot 4, NCallFn fid 2 3, NReturn, NLabel lbl2]
          build spawn dispatch instrs rest str_tbl (lbl + 2) (acc :: arm)
        | otherwise =
          build spawn dispatch instrs rest str_tbl lbl acc

fn :: highest entry arity [RFnEntry] => Int
      highest entry arity []         =  0
      highest entry arity ((FnEntry _ _ arity):rest) =
        max int arity (highest entry arity rest)

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
          off = lookup str off str_tbl name
          lbl_plain = lbl + 1
          lbl_next = lbl + 2
          arm = [NMatchStr 0 off (str len name), NJumpIfZero lbl_next, NMoveSlot 1, NStoreSlot 3, NMatchNonEmpty 2, NJumpIfZero lbl_plain, NListHead 2, NStoreSlot 4, NJump lbl, NLabel lbl_plain, NMoveSlot 2, NStoreSlot 4, NLabel lbl, NCallFn fid 3 2, NReturn, NLabel lbl_next]
          build call2 dispatch instrs rest str_tbl (lbl + 3) (acc :: arm)
        | arity >= 3 =
          off = lookup str off str_tbl name
          lbl_tuple = lbl + 1
          lbl_next = lbl + 2
          unpack_list = build call2 unpack list 0 (arity - 1)
          unpack_tup = build call2 unpack tuple 0 (arity - 1)
          arm = [NMatchStr 0 off (str len name), NJumpIfZero lbl_next, NMoveSlot 1, NStoreSlot 3, NMatchNonEmpty 2, NJumpIfZero lbl_tuple] :: unpack_list :: [NJump lbl, NLabel lbl_tuple] :: unpack_tup :: [NLabel lbl, NCallFn fid 3 arity, NReturn, NLabel lbl_next]
          build call2 dispatch instrs rest str_tbl (lbl + 3) (acc :: arm)
        | otherwise =
          build call2 dispatch instrs rest str_tbl lbl acc

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
        | arity == 2 and (is overloadable binop name name) =
          off = lookup str off str_tbl name
          arm = [NMatchStr 0 off (str len name), NJumpIfZero lbl, NMoveSlot 1, NStoreSlot 3, NMoveSlot 2, NStoreSlot 4, NCallFn fid 3 2, NReturn, NLabel lbl]
          build binop dispatch instrs rest str_tbl (lbl + 1) (acc :: arm)
        | otherwise =
          build binop dispatch instrs rest str_tbl lbl acc

fn :: is wrapable builtin fn String => Bool
      is wrapable builtin fn name =
        bid = builtin call id name
        ar = std builtin arity name
        bid >= 10 and bid != 53 and bid != 54 and bid != 55 and bid != 56 and bid != 61 and ar >= 1 and ar <= 3

fn :: make builtin wrapper fndef String Int => RFnDef
      make builtin wrapper fndef name 1 =
        FnDef name ["A"] "B" [FnCase [PatVar "__p0"] [] (ECall name [EVar "__p0"])]
      make builtin wrapper fndef name 2 =
        FnDef name ["A", "B"] "C" [FnCase [PatVar "__p0", PatVar "__p1"] [] (ECall name [EVar "__p0", EVar "__p1"])]
      make builtin wrapper fndef name _ =
        FnDef name ["A", "B", "C"] "D" [FnCase [PatVar "__p0", PatVar "__p1", PatVar "__p2"] [] (ECall name [EVar "__p0", EVar "__p1", EVar "__p2"])]

fn :: collect builtin val expr RExpr [String] => [String]
      collect builtin val expr (EVar name) acc
        | is wrapable builtin fn name = add unique str name acc
        | otherwise = acc
      collect builtin val expr (ENot inner) acc = collect builtin val expr inner acc
      collect builtin val expr (EOut inner) acc = collect builtin val expr inner acc
      collect builtin val expr (EBin _ l r) acc = collect builtin val expr r (collect builtin val expr l acc)
      collect builtin val expr (ECall fname args) acc
        | (is wrapable builtin fn fname) and (rexpr list len args) > 0 and (rexpr list len args) < (std builtin arity fname) =
          collect builtin val expr list args (add unique str fname acc)
        | otherwise = collect builtin val expr list args acc
      collect builtin val expr (EEcho args) acc = collect builtin val expr list args acc
      collect builtin val expr (EStrInterp parts) acc = collect builtin val expr list parts acc
      collect builtin val expr (EList elems) acc = collect builtin val expr list elems acc
      collect builtin val expr (ETuple elems) acc = collect builtin val expr list elems acc
      collect builtin val expr (ETensor elems) acc = collect builtin val expr list elems acc
      collect builtin val expr (EEinsum es _) acc = collect builtin val expr list es acc
      collect builtin val expr (EHadamard _ l _ r _) acc = collect builtin val expr r (collect builtin val expr l acc)
      collect builtin val expr (EIndex base idxs) acc = collect builtin val expr list idxs (collect builtin val expr base acc)
      collect builtin val expr (EIndexAssign _ idxs v) acc = collect builtin val expr v (collect builtin val expr list idxs acc)
      collect builtin val expr (ESeqSelect b _) acc = collect builtin val expr b acc
      collect builtin val expr (EBlock stmts) acc = collect builtin val stmts stmts acc
      collect builtin val expr (EGuard guards) acc = collect builtin val guards guards acc
      collect builtin val expr (EWhere body binds) acc = collect builtin val where binds (collect builtin val expr body acc)
      collect builtin val expr (EParPipe branches) acc = collect builtin val expr list branches acc
      collect builtin val expr (EWithCtx _ v b) acc = collect builtin val expr b (collect builtin val expr v acc)
      collect builtin val expr (EWithRegion _ b) acc = collect builtin val expr b acc
      collect builtin val expr _ acc = acc

fn :: collect builtin val expr list [RExpr] [String] => [String]
      collect builtin val expr list [] acc = acc
      collect builtin val expr list (e:es) acc = collect builtin val expr list es (collect builtin val expr e acc)

fn :: collect builtin val stmts [RStmt] [String] => [String]
      collect builtin val stmts [] acc = acc
      collect builtin val stmts ((StmtLet _ e):ss) acc = collect builtin val stmts ss (collect builtin val expr e acc)
      collect builtin val stmts ((StmtMut _ e):ss) acc = collect builtin val stmts ss (collect builtin val expr e acc)
      collect builtin val stmts ((StmtExpr e):ss) acc = collect builtin val stmts ss (collect builtin val expr e acc)
      collect builtin val stmts ((StmtIndexAssign _ idxs e):ss) acc =
        collect builtin val stmts ss (collect builtin val expr e (collect builtin val expr list idxs acc))

fn :: collect builtin val where [RWhereBind] [String] => [String]
      collect builtin val where [] acc = acc
      collect builtin val where ((WhereBind e _ _):wbs) acc = collect builtin val where wbs (collect builtin val expr e acc)

fn :: collect builtin val guards [RGuard] [String] => [String]
      collect builtin val guards [] acc = acc
      collect builtin val guards ((GuardBranch c b):gs) acc =
        collect builtin val guards gs (collect builtin val expr b (collect builtin val expr c acc))

fn :: collect builtin val cases [RFnCase] [String] => [String]
      collect builtin val cases [] acc = acc
      collect builtin val cases ((FnCase _ gs b):cs) acc =
        collect builtin val cases cs (collect builtin val expr b (collect builtin val guards gs acc))

fn :: collect builtin val fndefs [RFnDef] [String] => [String]
      collect builtin val fndefs [] acc = acc
      collect builtin val fndefs ((FnDef _ _ _ cases):fs) acc =
        collect builtin val fndefs fs (collect builtin val cases cases acc)

fn :: build builtin wrapper fndefs [String] [String] => [RFnDef]
      build builtin wrapper fndefs [] _ = []
      build builtin wrapper fndefs (b:bs) existing
        | str in list b existing = build builtin wrapper fndefs bs existing
        | otherwise = [make builtin wrapper fndef b (std builtin arity b)] :: (build builtin wrapper fndefs bs existing)

fn :: lower program to native RProgram => RNativeProg
      lower program to native (Program raw_fns tys) =
        field_tbl = collect typedef fields tys []
        raw_fn_names = collect fn names raw_fns
        b_wrappers = build builtin wrapper fndefs (collect builtin val fndefs raw_fns []) raw_fn_names
        sigs = (build cg sigs raw_fns) :: (build field cg sigs field_tbl raw_fn_names)
        all_fns = (opt fndef list (prep fndef list raw_fns sigs)) :: b_wrappers
        entry_name = find entry fn name all_fns "main"
        reachable = expand reachable worklist [entry_name] all_fns []
        fns = filter reachable fndefs all_fns reachable
        fn_names = collect fn names fns
        str_pool = build str pool fns (collect field names field_tbl)
        rodata_str = pool rodata str_pool
        str_tbl = pool entries str_pool
        fn_tbl1 = build fn table fndefs fns 5 []
        fn_tbl2 = build fn table fields field_tbl fn_names (5 + (list str len fn_names)) fn_tbl1
        fn_tbl = attach heavy fn entries fns fn_names fn_tbl2
        entry_fid = lookup fn id fn_tbl entry_name
        main_wrapper = NativeFn 1 "__rg_entry_main" 0 2 [NCallFn entry_fid 0 (0 - 1), NReturn]
        spawn_disp = NativeFn 2 "__rg_dispatch_spawn" 2 6 (build spawn dispatch entry fn_tbl str_tbl)
        call2_slots = max int 7 (4 + (highest entry arity fn_tbl))
        call2_disp = NativeFn 3 "__rg_dispatch_call2" 3 call2_slots (build call2 dispatch instrs fn_tbl str_tbl 1 [])
        binop_disp = NativeFn 4 "__rg_dispatch_binop" 3 6 (build binop dispatch instrs fn_tbl str_tbl 1 [])
        user_native_fns = lower fndef list fns str_tbl fn_tbl field_tbl
        field_native_fns = lower field getter fns field_tbl fn_names fn_tbl
        all_native_fns = [main_wrapper, spawn_disp, call2_disp, binop_disp] :: user_native_fns :: field_native_fns
        NativeProg 1 2 3 4 all_native_fns rodata_str

fn :: build lib entry wrapper Int       => RNativeFn
      build lib entry wrapper 0         =  NativeFn 1 "__rg_entry_main" 0 2 [NLoadImmRaw 0, NReturn]
      build lib entry wrapper entry_fid =  NativeFn 1 "__rg_entry_main" 0 2 [NCallFn entry_fid 0 (0 - 1), NReturn]

fn :: lower library to native RProgram => RNativeProg
      lower library to native (Program raw_fns tys) =
        field_tbl = collect typedef fields tys []
        raw_fn_names = collect fn names raw_fns
        b_wrappers = build builtin wrapper fndefs (collect builtin val fndefs raw_fns []) raw_fn_names
        sigs = (build cg sigs raw_fns) :: (build field cg sigs field_tbl raw_fn_names)
        fns = (opt fndef list (prep fndef list raw_fns sigs)) :: b_wrappers
        fn_names = collect fn names fns
        str_pool = build str pool fns (collect field names field_tbl)
        rodata_str = pool rodata str_pool
        str_tbl = pool entries str_pool
        fn_tbl1 = build fn table fndefs fns 5 []
        fn_tbl2 = build fn table fields field_tbl fn_names (5 + (list str len fn_names)) fn_tbl1
        fn_tbl = attach heavy fn entries fns fn_names fn_tbl2
        entry_fid = lookup fn id fn_tbl "main"
        main_wrapper = build lib entry wrapper entry_fid
        spawn_disp = NativeFn 2 "__rg_dispatch_spawn" 2 6 (build spawn dispatch entry fn_tbl str_tbl)
        call2_slots = max int 7 (4 + (highest entry arity fn_tbl))
        call2_disp = NativeFn 3 "__rg_dispatch_call2" 3 call2_slots (build call2 dispatch instrs fn_tbl str_tbl 1 [])
        binop_disp = NativeFn 4 "__rg_dispatch_binop" 3 6 (build binop dispatch instrs fn_tbl str_tbl 1 [])
        user_native_fns = lower fndef list fns str_tbl fn_tbl field_tbl
        field_native_fns = lower field getter fns field_tbl fn_names fn_tbl
        all_native_fns = [main_wrapper, spawn_disp, call2_disp, binop_disp] :: user_native_fns :: field_native_fns
        NativeProg 1 2 3 4 all_native_fns rodata_str

-- ── Bytecode (.rgc), Library (.rglib / .so), & ELF64 Emission ─

fn :: join summaries [String] => String
      join summaries []       =  ""
      join summaries (s:ss)   =  "-- SUMMARY: {s}\n" + (join summaries ss)

fn :: emit rgc payload RProgram String  => String
      emit rgc payload prog     raw_src =
        prog -> count fn defs -> fn_count
        prog -> count type defs -> ty_count
        prog -> analyze rprogram -> join summaries -> summaries
        "RGC1\n-- SELF_HOSTED_COMPILER: ridgunc v0.9.8\n-- FUNCTIONS: {fn_count}\n-- TYPES: {ty_count}\n{summaries}{raw_src}"

fn :: emit rgc file String     String      => Int
      emit rgc file input_path output_path =
        input_path -> load rg with libs -> emit rgc file loaded input_path output_path _

fn :: emit rgc file loaded String String String => Int
      emit rgc file loaded input_path _ "" =
        echo "[ridgunc compile] Error: empty or missing source file: {input_path}"
        -1
      emit rgc file loaded _ output_path raw_src =
        raw_src -> tokenize src -> parse tokens -> prog
        prog -> typecheck program -> errs
        emit rgc after check prog raw_src output_path errs

fn :: emit rgc after check RProgram String String [RTypeError] => Int
      emit rgc after check prog raw_src output_path []
        | ((count fn defs prog) == 0) and ((count type defs prog) == 0) =
          echo "[ridgunc compile] Error: no functions or types found in source"
          -1
        | otherwise =
          prog -> emit rgc payload raw_src -> write file output_path _
          count fn defs prog
      emit rgc after check _ _ _ errs =
        echo (format type errors errs)
        0 - (type err count errs)

fn :: emit rglib payload RProgram String  => String
      emit rglib payload prog     raw_src =
        prog -> count fn defs -> fn_count
        prog -> count type defs -> ty_count
        prog -> analyze rprogram -> join summaries -> summaries
        "-- RGLIB1\n-- SELF_HOSTED_COMPILER: ridgunc v0.9.8\n-- FUNCTIONS: {fn_count}\n-- TYPES: {ty_count}\n{summaries}{raw_src}"

fn :: emit rglib file String     String      => Int
      emit rglib file input_path output_path =
        input_path -> load rg own source -> own_src
        input_path -> load rg with libs -> full_src
        emit rglib file loaded input_path output_path own_src full_src

fn :: emit rglib file loaded String String String String => Int
      emit rglib file loaded input_path _ "" _ =
        echo "[ridgunc build --lib] Error: empty or missing source file: {input_path}"
        1
      emit rglib file loaded _ output_path own_src full_src =
        full_src -> tokenize src -> parse tokens -> typecheck program -> errs
        own_src -> tokenize src -> parse tokens -> own_prog
        emit rglib after check own_prog own_src output_path errs

fn :: emit rglib after check RProgram String String [RTypeError] => Int
      emit rglib after check prog raw_src output_path []
        | ((count fn defs prog) == 0) and ((count type defs prog) == 0) =
          echo "[ridgunc build --lib] Error: no functions or types found in source"
          1
        | otherwise =
          prog -> emit rglib payload raw_src -> write file output_path _
          0
      emit rglib after check _ _ _ errs =
        echo (format type errors errs)
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
        nprog -> emit arm64 elf -> write elf64 executable output_bin _
      build native target for arch nprog output_bin "arm64-linux" =
        nprog -> emit arm64 elf -> write elf64 executable output_bin _
      build native target for arch nprog output_bin "aarch64" =
        nprog -> emit arm64 elf -> write elf64 executable output_bin _
      build native target for arch nprog output_bin _ =
        build llvm x8664 executable nprog output_bin

fn :: build native so for arch RNativeProg String String => Int
      build native so for arch nprog output_so "arm64" =
        nprog -> emit arm64 so elf -> write elf64 executable output_so _
      build native so for arch nprog output_so "arm64-linux" =
        nprog -> emit arm64 so elf -> write elf64 executable output_so _
      build native so for arch nprog output_so "aarch64" =
        nprog -> emit arm64 so elf -> write elf64 executable output_so _
      build native so for arch nprog output_so _ =
        build llvm x8664 so library nprog output_so

fn :: build native target executable String String String => Int
      build native target executable input_path output_bin target_arch =
        input_path -> load rg with libs -> build native target loaded input_path output_bin target_arch _

fn :: build native target loaded String String String String => Int
      build native target loaded input_path _ _ "" =
        echo "[ridgunc build] Error: empty or missing source file: {input_path}"
        1
      build native target loaded _ output_bin target_arch raw_src =
        raw_src -> tokenize src -> parse tokens -> prog
        prog -> typecheck program -> errs
        build native target after check prog output_bin target_arch errs

fn :: build native target after check RProgram String String [RTypeError] => Int
      build native target after check prog output_bin target_arch []
        | (count fn defs prog) == 0 =
          echo "[ridgunc build] Error: no functions found in source"
          1
        | otherwise =
          prog -> lower program to native -> build native target for arch output_bin target_arch
      build native target after check _ _ _ errs =
        echo (format type errors errs)
        1

fn :: build native target so library String String String => Int
      build native target so library input_path output_so target_arch =
        input_path -> load rg with libs -> build native so loaded input_path output_so target_arch _

fn :: build native so loaded String String String String => Int
      build native so loaded input_path _ _ "" =
        echo "[ridgunc build --so] Error: empty or missing source file: {input_path}"
        1
      build native so loaded _ output_so target_arch raw_src =
        raw_src -> tokenize src -> parse tokens -> prog
        prog -> typecheck program -> errs
        build native so after check prog output_so target_arch errs

fn :: build native so after check RProgram String String [RTypeError] => Int
      build native so after check prog output_so target_arch []
        | ((count fn defs prog) == 0) and ((count type defs prog) == 0) =
          echo "[ridgunc build --so] Error: no functions or types found in source"
          1
        | otherwise =
          prog -> lower library to native -> build native so for arch output_so target_arch
      build native so after check _ _ _ errs =
        echo (format type errors errs)
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
