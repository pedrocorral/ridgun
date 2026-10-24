-- ============================================================
-- src/main/ridgun/analyzer.rg
-- Self-Hosted Ridgun v0.9.0 Static Analyzer
-- Implements:
-- 1. Bottom-up interprocedural mutation effect inference (EffReadOnly / EffMutates)
-- 2. 4-Tier AST Execution Strategy classification (InlineSequential,
--    KernelWorkerJob, LazyStealableTask, FullGreenThread)
-- 3. where-block Producer-Consumer DAG builder & cycle detection (ErrWhereCycle)
-- 4. Automatic Freeze on Parallel Share & Disjoint Slice Verification (ErrParallelMutation)
-- 5. Affine Move verification on channel sends (ErrUseAfterSend)
-- ============================================================
import ast
import lexer
import parser

-- ── Basic List & Set Helpers ────────────────────────────────

fn :: str in list String [String] => Bool
      str in list _      []       =  False
      str in list target (x:xs)
        | x == target = True
        | otherwise = str_in_list target xs

fn :: add unique str String [String] => [String]
      add unique str s      xs
        | str_in_list s xs = xs
        | otherwise = xs :: [s]

fn :: union strs [String] [String] => [String]
      union strs []       ys       =  ys
      union strs (x:xs)   ys       =  union_strs xs (add_unique_str x ys)

fn :: int in list Int    [Int]  => Bool
      int in list _      []     =  False
      int in list target (x:xs)
        | x == target = True
        | otherwise = int_in_list target xs

fn :: int list len [Int]  => Int
      int list len []     =  0
      int list len (_:xs) =  1 + (int_list_len xs)

fn :: where list len [RWhereBind] => Int
      where list len []           =  0
      where list len (_:xs)       =  1 + (where_list_len xs)

-- ── Cost Tier & 4-Tier Strategy Selection ───────────────────

fn :: cost rank RCostTier    => Int
      cost rank TierTrivial  =  0
      cost rank TierHeavyCPU =  1
      cost rank TierDynamicRecursive = 2

fn :: max cost tier RCostTier RCostTier => RCostTier
      max cost tier a         b
        | (cost_rank a) >= (cost_rank b) = a
        | otherwise = b

fn :: select exec strategy Bool  RCostTier    => RExecStrategy
      select exec strategy True  _            =  StratFullGreenThread
      select exec strategy False TierTrivial  =  StratInlineSequential
      select exec strategy False TierHeavyCPU =  StratKernelWorkerJob
      select exec strategy False TierDynamicRecursive = StratLazyStealableTask

fn :: strategy to str RExecStrategy => String
      strategy to str StratInlineSequential = "InlineSequential"
      strategy to str StratKernelWorkerJob = "KernelWorkerJob"
      strategy to str StratLazyStealableTask = "LazyStealableTask"
      strategy to str StratFullGreenThread = "FullGreenThread"

-- ── Summary Table Lookup & Update ───────────────────────────

fn :: lookup fn summary [RFnSummary] String => Bool RFnSummary
      lookup fn summary []           name   =
        (False, FnSummary name [] False TierTrivial StratInlineSequential)
      lookup fn summary ((FnSummary sname effs yld cost strat):rest) name
        | sname == name = (True, FnSummary sname effs yld cost strat)
        | otherwise = lookup_fn_summary rest name

fn :: is yielding builtin String => Bool
      is yielding builtin callee =
        callee == "recv" OR callee == "receive_from" OR callee == "try_receive_from" OR callee == "receive_from_timeout" OR callee == "send_to" OR callee == "ask_to" OR callee == "send_through" OR callee == "agent" OR callee == "stop"

fn :: param effect at [RParamEffect] Int => RParamEffect
      param effect at []             _   =  EffReadOnly
      param effect at (e:_)          0   =  e
      param effect at (_:es)         idx =  param_effect_at es (idx - 1)

fn :: collect mutated call args [RExpr] [RParamEffect] Int [String] => [String]
      collect mutated call args [] _ _ acc = acc
      collect mutated call args ((EVar v):args) effs idx acc
        | (param_effect_at effs idx) == EffMutates = collect_mutated_call_args args effs (idx + 1) (add_unique_str v acc)
        | otherwise = collect_mutated_call_args args effs (idx + 1) acc
      collect mutated call args (_:args) effs idx acc =
        collect_mutated_call_args args effs (idx + 1) acc

-- ── Expression Effect & Self-Call Collection ────────────────

fn :: count expr self calls String RExpr => Int
      count expr self calls fn_name (ENot inner) = count_expr_self_calls fn_name inner
      count expr self calls fn_name (EOut inner) = count_expr_self_calls fn_name inner
      count expr self calls fn_name (EBin _ l r) = (count_expr_self_calls fn_name l) + (count_expr_self_calls fn_name r)
      count expr self calls fn_name (ECall callee args)
        | callee == fn_name = 1 + (count_expr_list_calls fn_name args)
        | otherwise = count_expr_list_calls fn_name args
      count expr self calls fn_name (EEcho args) = count_expr_list_calls fn_name args
      count expr self calls fn_name (EStrInterp args) = count_expr_list_calls fn_name args
      count expr self calls fn_name (EList elems) = count_expr_list_calls fn_name elems
      count expr self calls fn_name (ETuple elems) = count_expr_list_calls fn_name elems
      count expr self calls fn_name (ETensor elems) = count_expr_list_calls fn_name elems
      count expr self calls fn_name (EEinsum es _) = count_expr_list_calls fn_name es
      count expr self calls fn_name (EHadamard _ l _ r _) = (count_expr_self_calls fn_name l) + (count_expr_self_calls fn_name r)
      count expr self calls fn_name (EIndex b idxs) = (count_expr_self_calls fn_name b) + (count_expr_list_calls fn_name idxs)
      count expr self calls fn_name (EIndexAssign _ idxs v) = (count_expr_list_calls fn_name idxs) + (count_expr_self_calls fn_name v)
      count expr self calls fn_name (ESeqSelect b _) = count_expr_self_calls fn_name b
      count expr self calls fn_name (EBlock stmts) = count_stmt_list_calls fn_name stmts
      count expr self calls fn_name (EGuard guards) = count_guard_calls fn_name guards
      count expr self calls fn_name (EWhere body binds) = (count_expr_self_calls fn_name body) + (count_where_calls fn_name binds)
      count expr self calls fn_name (EParPipe branches) = count_expr_list_calls fn_name branches
      count expr self calls fn_name (EWithCtx _ v b) = (count_expr_self_calls fn_name v) + (count_expr_self_calls fn_name b)
      count expr self calls fn_name (EWithRegion _ b) = count_expr_self_calls fn_name b
      count expr self calls _ _ = 0

fn :: count expr list calls String [RExpr] => Int
      count expr list calls _ [] = 0
      count expr list calls fn_name (e:es) = (count_expr_self_calls fn_name e) + (count_expr_list_calls fn_name es)

fn :: count stmt list calls String [RStmt] => Int
      count stmt list calls _ [] = 0
      count stmt list calls fn_name ((StmtLet _ e):ss) = (count_expr_self_calls fn_name e) + (count_stmt_list_calls fn_name ss)
      count stmt list calls fn_name ((StmtMut _ e):ss) = (count_expr_self_calls fn_name e) + (count_stmt_list_calls fn_name ss)
      count stmt list calls fn_name ((StmtExpr e):ss) = (count_expr_self_calls fn_name e) + (count_stmt_list_calls fn_name ss)
      count stmt list calls fn_name ((StmtIndexAssign _ idxs e):ss) = (count_expr_list_calls fn_name idxs) + (count_expr_self_calls fn_name e) + (count_stmt_list_calls fn_name ss)

fn :: count where calls String  [RWhereBind] => Int
      count where calls _       []           =  0
      count where calls fn_name ((WhereBind e _ _):wbs) = (count_expr_self_calls fn_name e) + (count_where_calls fn_name wbs)

fn :: count guard calls String  [RGuard] => Int
      count guard calls _       []       =  0
      count guard calls fn_name ((GuardBranch c b):gs) = (count_expr_self_calls fn_name c) + (count_expr_self_calls fn_name b) + (count_guard_calls fn_name gs)

fn :: count case calls String  [RFnCase] => Int
      count case calls _       []        =  0
      count case calls fn_name ((FnCase _ gs b):cs) =
        c_here = (count_guard_calls fn_name gs) + (count_expr_self_calls fn_name b)
        c_rest = count_case_calls fn_name cs
        max_int c_here c_rest

fn :: max int Int Int => Int
      max int a   b
        | a >= b = a
        | otherwise = b

fn :: collect expr effects RExpr String [RFnSummary] [String] Bool RCostTier => [String] Bool RCostTier
      collect expr effects (ECall callee args) cur_fn summaries muts yld cost =
        after_call = apply_callee_summary callee args cur_fn (lookup_fn_summary summaries callee) muts yld cost
        collect_expr_list_effects_tuple args cur_fn summaries after_call
      collect expr effects (EIndexAssign target idxs val) cur_fn summaries muts yld cost =
        muts1 = add_unique_str target muts
        r_idxs = collect_expr_list_effects idxs cur_fn summaries muts1 yld cost
        collect_expr_effects_tuple val cur_fn summaries r_idxs
      collect expr effects (EWhere body binds) cur_fn summaries muts yld cost =
        r_body = collect_expr_effects body cur_fn summaries muts yld cost
        collect_where_effects_tuple binds cur_fn summaries r_body
      collect expr effects (EParPipe branches) cur_fn summaries muts yld cost =
        collect_expr_list_effects branches cur_fn summaries muts yld cost
      collect expr effects (EBin _ l r) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects l cur_fn summaries muts yld cost
        collect_expr_effects_tuple r cur_fn summaries r1
      collect expr effects (EHadamard _ l _ r _) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects l cur_fn summaries muts yld (max_cost_tier cost TierHeavyCPU)
        collect_expr_effects_tuple r cur_fn summaries r1
      collect expr effects (EEinsum es _) cur_fn summaries muts yld cost =
        collect_expr_list_effects es cur_fn summaries muts yld (max_cost_tier cost TierHeavyCPU)
      collect expr effects (ETensor elems) cur_fn summaries muts yld cost =
        collect_expr_list_effects elems cur_fn summaries muts yld (max_cost_tier cost TierHeavyCPU)
      collect expr effects (ENot inner) cur_fn summaries muts yld cost =
        collect_expr_effects inner cur_fn summaries muts yld cost
      collect expr effects (EOut inner) cur_fn summaries muts yld cost =
        collect_expr_effects inner cur_fn summaries muts yld cost
      collect expr effects (EWithRegion _ inner) cur_fn summaries muts yld cost =
        collect_expr_effects inner cur_fn summaries muts yld cost
      collect expr effects (EWithCtx _ v b) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects v cur_fn summaries muts yld cost
        collect_expr_effects_tuple b cur_fn summaries r1
      collect expr effects (EBlock stmts) cur_fn summaries muts yld cost =
        collect_stmt_list_effects stmts cur_fn summaries muts yld cost
      collect expr effects (EGuard guards) cur_fn summaries muts yld cost =
        collect_guards_effects guards cur_fn summaries muts yld cost
      collect expr effects (EList elems) cur_fn summaries muts yld cost =
        collect_expr_list_effects elems cur_fn summaries muts yld cost
      collect expr effects (ETuple elems) cur_fn summaries muts yld cost =
        collect_expr_list_effects elems cur_fn summaries muts yld cost
      collect expr effects (EEcho elems) cur_fn summaries muts yld cost =
        collect_expr_list_effects elems cur_fn summaries muts yld cost
      collect expr effects (EStrInterp elems) cur_fn summaries muts yld cost =
        collect_expr_list_effects elems cur_fn summaries muts yld cost
      collect expr effects (EIndex b idxs) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects b cur_fn summaries muts yld cost
        collect_expr_list_effects_tuple idxs cur_fn summaries r1
      collect expr effects _ _ _ muts yld cost = (muts, yld, cost)

fn :: collect expr effects tuple RExpr String [RFnSummary] ([String], Bool, RCostTier) => [String] Bool RCostTier
      collect expr effects tuple e cur_fn summaries (muts, yld, cost) =
        collect_expr_effects e cur_fn summaries muts yld cost

fn :: collect expr list effects [RExpr] String [RFnSummary] [String] Bool RCostTier => [String] Bool RCostTier
      collect expr list effects [] _ _ muts yld cost = (muts, yld, cost)
      collect expr list effects (e:es) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects e cur_fn summaries muts yld cost
        collect_expr_list_effects_tuple es cur_fn summaries r1

fn :: collect expr list effects tuple [RExpr] String [RFnSummary] ([String], Bool, RCostTier) => [String] Bool RCostTier
      collect expr list effects tuple es cur_fn summaries (muts, yld, cost) =
        collect_expr_list_effects es cur_fn summaries muts yld cost

fn :: collect stmt list effects [RStmt] String [RFnSummary] [String] Bool RCostTier => [String] Bool RCostTier
      collect stmt list effects [] _ _ muts yld cost = (muts, yld, cost)
      collect stmt list effects ((StmtLet _ e):ss) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects e cur_fn summaries muts yld cost
        collect_stmt_list_effects_tuple ss cur_fn summaries r1
      collect stmt list effects ((StmtMut _ e):ss) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects e cur_fn summaries muts yld cost
        collect_stmt_list_effects_tuple ss cur_fn summaries r1
      collect stmt list effects ((StmtExpr e):ss) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects e cur_fn summaries muts yld cost
        collect_stmt_list_effects_tuple ss cur_fn summaries r1
      collect stmt list effects ((StmtIndexAssign target idxs e):ss) cur_fn summaries muts yld cost =
        muts1 = add_unique_str target muts
        r_idxs = collect_expr_list_effects idxs cur_fn summaries muts1 yld cost
        r_val = collect_expr_effects_tuple e cur_fn summaries r_idxs
        collect_stmt_list_effects_tuple ss cur_fn summaries r_val

fn :: collect stmt list effects tuple [RStmt] String [RFnSummary] ([String], Bool, RCostTier) => [String] Bool RCostTier
      collect stmt list effects tuple ss cur_fn summaries (muts, yld, cost) =
        collect_stmt_list_effects ss cur_fn summaries muts yld cost

fn :: collect where effects [RWhereBind] String [RFnSummary] [String] Bool RCostTier => [String] Bool RCostTier
      collect where effects [] _ _ muts yld cost = (muts, yld, cost)
      collect where effects ((WhereBind e target idxs):wbs) cur_fn summaries muts yld cost
        | (int_list_len idxs) > 0 = collect_where_effects_tuple wbs cur_fn summaries (collect_expr_effects e cur_fn summaries (add_unique_str target muts) yld cost)
        | otherwise = collect_where_effects_tuple wbs cur_fn summaries (collect_expr_effects e cur_fn summaries muts yld cost)

fn :: collect where effects tuple [RWhereBind] String [RFnSummary] ([String], Bool, RCostTier) => [String] Bool RCostTier
      collect where effects tuple wbs cur_fn summaries (muts, yld, cost) =
        collect_where_effects wbs cur_fn summaries muts yld cost

fn :: apply callee summary String [RExpr] String (Bool, RFnSummary) [String] Bool RCostTier => [String] Bool RCostTier
      apply callee summary callee args cur_fn (found, (FnSummary _ effs s_yld s_cost _)) muts yld cost =
        yld1 = yld OR (is_yielding_builtin callee) OR (found AND s_yld)
        cost1 = compute_call_cost callee cur_fn found s_cost cost
        muts1 = collect_mutated_call_args args effs 0 muts
        (muts1, yld1, cost1)

fn :: compute call cost String String Bool RCostTier RCostTier => RCostTier
      compute call cost callee cur_fn _ _ cost
        | callee == cur_fn = max_cost_tier cost TierDynamicRecursive
      compute call cost _ _ True s_cost cost = max_cost_tier cost s_cost
      compute call cost _ _ False _ cost = cost

-- ── Classify Arbitrary Expression Strategy ──────────────────

fn :: classify expr strategy RExpr String [RFnSummary] => RExecStrategy
      classify expr strategy expr cur_fn summaries =
        finish_expr_strategy (collect_expr_effects expr cur_fn summaries [] False TierTrivial)

fn :: finish expr strategy ([String], Bool, RCostTier) => RExecStrategy
      finish expr strategy (_, yld, cost)              =  select_exec_strategy yld cost

-- ── Per-Function Static Summary Inference ───────────────────

fn :: init readonly effects [String] => [RParamEffect]
      init readonly effects []       =  []
      init readonly effects (_:ps)   =  [EffReadOnly] :: (init_readonly_effects ps)

fn :: update param effects [RPattern] [RParamEffect] [String] => [RParamEffect]
      update param effects [] effs _ = effs
      update param effects _ [] _ = []
      update param effects ((PatVar v):ps) (e:es) muts
        | str_in_list v muts = [EffMutates] :: (update_param_effects ps es muts)
        | otherwise = [e] :: (update_param_effects ps es muts)
      update param effects (_:ps) (e:es) muts =
        [e] :: (update_param_effects ps es muts)

fn :: collect guards effects [RGuard] String [RFnSummary] [String] Bool RCostTier => [String] Bool RCostTier
      collect guards effects [] _ _ muts yld cost = (muts, yld, cost)
      collect guards effects ((GuardBranch c b):gs) fn_name summaries muts yld cost =
        r1 = collect_expr_effects c fn_name summaries muts yld cost
        r2 = collect_expr_effects_tuple b fn_name summaries r1
        collect_guards_effects_tuple gs fn_name summaries r2

fn :: collect guards effects tuple [RGuard] String [RFnSummary] ([String], Bool, RCostTier) => [String] Bool RCostTier
      collect guards effects tuple gs fn_name summaries (muts, yld, cost) =
        collect_guards_effects gs fn_name summaries muts yld cost

fn :: collect cases summary [RFnCase] String [RFnSummary] [RParamEffect] Bool RCostTier => [RParamEffect] Bool RCostTier
      collect cases summary [] _ _ effs yld cost = (effs, yld, cost)
      collect cases summary ((FnCase pats guards body):cs) fn_name summaries effs yld cost =
        r_body = collect_expr_effects body fn_name summaries [] yld cost
        r_all = collect_guards_effects_tuple guards fn_name summaries r_body
        collect_cases_step pats cs fn_name summaries effs r_all

fn :: collect cases step [RPattern] [RFnCase] String [RFnSummary] [RParamEffect] ([String], Bool, RCostTier) => [RParamEffect] Bool RCostTier
      collect cases step pats cs fn_name summaries effs (case_muts, yld1, cost1) =
        effs1 = update_param_effects pats effs case_muts
        collect_cases_summary cs fn_name summaries effs1 yld1 cost1

fn :: adjust recursive cost Int        RCostTier => RCostTier
      adjust recursive cost self_calls cost
        | self_calls == 1 = max_cost_tier cost TierHeavyCPU
        | self_calls > 1 = TierDynamicRecursive
        | otherwise = cost

fn :: compute one fn summary RFnDef [RFnSummary] => RFnSummary
      compute one fn summary (FnDef name params _ cases) summaries =
        init_effs = init_readonly_effects params
        self_calls = count_case_calls name cases
        res = collect_cases_summary cases name summaries init_effs False TierTrivial
        finish_fn_summary name self_calls res

fn :: finish fn summary String Int ([RParamEffect], Bool, RCostTier) => RFnSummary
      finish fn summary name self_calls (effs, yld, raw_cost) =
        final_cost = adjust_recursive_cost self_calls raw_cost
        strat = select_exec_strategy yld final_cost
        FnSummary name effs yld final_cost strat

fn :: has mut effect [RParamEffect]      => Bool
      has mut effect []                  =  False
      has mut effect (EffMutates:_)      =  True
      has mut effect (_:es)              =  has_mut_effect es

fn :: is nontrivial summary RFnSummary                             => Bool
      is nontrivial summary (FnSummary _ effs False TierTrivial _) =  has_mut_effect effs
      is nontrivial summary _                                      =  True

fn :: add nontrivial summary RFnSummary [RFnSummary] => [RFnSummary]
      add nontrivial summary s          summaries
        | is_nontrivial_summary s = summaries :: [s]
        | otherwise = summaries

fn :: filter nontrivial summaries acc [RFnSummary] [RFnSummary] => [RFnSummary]
      filter nontrivial summaries acc []           acc          =  acc
      filter nontrivial summaries acc (s:ss)       acc
        | is_nontrivial_summary s = filter_nontrivial_summaries_acc ss (acc :: [s])
        | otherwise = filter_nontrivial_summaries_acc ss acc

fn :: filter nontrivial summaries [RFnSummary] => [RFnSummary]
      filter nontrivial summaries ss           =  filter_nontrivial_summaries_acc ss []

fn :: compute summaries pass acc [RFnDef] [RFnSummary] [RFnSummary] => [RFnSummary]
      compute summaries pass acc []       _            acc          =  acc
      compute summaries pass acc (f:fs)   cur_summaries acc         =
        s = compute_one_fn_summary f cur_summaries
        compute_summaries_pass_acc fs (add_nontrivial_summary s cur_summaries) (acc :: [s])

fn :: compute summaries pass [RFnDef] [RFnSummary]  => [RFnSummary]
      compute summaries pass fns      cur_summaries =
        compute_summaries_pass_acc fns cur_summaries []

fn :: infer all summaries RProgram        => [RFnSummary]
      infer all summaries (Program fns _) =
        pass1 = filter_nontrivial_summaries (compute_summaries_pass fns [])
        compute_summaries_pass fns pass1

-- ── Free Variable Extraction & Where-Block DAG / Cycle Check ──

fn :: collect free vars RExpr              [String] => [String]
      collect free vars (EVar v)           acc      =  add_unique_str v acc
      collect free vars (ENot inner)       acc      =  collect_free_vars inner acc
      collect free vars (EOut inner)       acc      =  collect_free_vars inner acc
      collect free vars (EBin _ l r)       acc      =  collect_free_vars r (collect_free_vars l acc)
      collect free vars (EHadamard _ l _ r _) acc   =  collect_free_vars r (collect_free_vars l acc)
      collect free vars (EEinsum es _)     acc      =  collect_free_vars_list es acc
      collect free vars (ECall _ args)     acc      =  collect_free_vars_list args acc
      collect free vars (EEcho args)       acc      =  collect_free_vars_list args acc
      collect free vars (EStrInterp args)  acc      =  collect_free_vars_list args acc
      collect free vars (EList args)       acc      =  collect_free_vars_list args acc
      collect free vars (ETuple args)      acc      =  collect_free_vars_list args acc
      collect free vars (ETensor args)     acc      =  collect_free_vars_list args acc
      collect free vars (EIndex b idxs)    acc      =  collect_free_vars_list idxs (collect_free_vars b acc)
      collect free vars (EIndexAssign t idxs v) acc =  collect_free_vars v (collect_free_vars_list idxs (add_unique_str t acc))
      collect free vars (ESeqSelect b _)   acc      =  collect_free_vars b acc
      collect free vars (EWithCtx _ v b)   acc      =  collect_free_vars b (collect_free_vars v acc)
      collect free vars (EWithRegion _ b)  acc      =  collect_free_vars b acc
      collect free vars _                  acc      =  acc

fn :: collect free vars list [RExpr] [String] => [String]
      collect free vars list [] acc = acc
      collect free vars list (e:es) acc = collect_free_vars_list es (collect_free_vars e acc)

type RProducerEntry = ProducerEntry String Int

fn :: lookup producer [RProducerEntry] String => Int
      lookup producer []               _      =  -1
      lookup producer ((ProducerEntry k idx):rest) target
        | k == target = idx
        | otherwise = lookup_producer rest target

fn :: collect producers [RWhereBind] Int [RProducerEntry] String => [RProducerEntry] [RAnalysisError]
      collect producers [] _ acc _ = (acc, [])
      collect producers ((WhereBind _ target idxs):wbs) idx acc fn_name
        | (int_list_len idxs) > 0 OR target == "" = collect_producers wbs (idx + 1) acc fn_name
        | (lookup_producer acc target) >= 0 = add_prod_err (ErrWhereCycle fn_name target) (collect_producers wbs (idx + 1) acc fn_name)
        | otherwise = collect_producers wbs (idx + 1) (acc :: [ProducerEntry target idx]) fn_name

fn :: add prod err RAnalysisError ([RProducerEntry], [RAnalysisError]) => [RProducerEntry] [RAnalysisError]
      add prod err err (prods, errs) = (prods, [err] :: errs)

type RDagEdge = DagEdge Int Int

fn :: build where edges [RWhereBind] Int [RProducerEntry] String => [RDagEdge] [RAnalysisError]
      build where edges [] _ _ _ = ([], [])
      build where edges ((WhereBind expr _ _):wbs) j prods fn_name =
        fvars = collect_free_vars expr []
        e_here = edges_for_vars fvars j prods fn_name
        e_rest = build_where_edges wbs (j + 1) prods fn_name
        merge_edges_and_errs e_here e_rest

fn :: edges for vars [String] Int [RProducerEntry] String => [RDagEdge] [RAnalysisError]
      edges for vars [] _ _ _ = ([], [])
      edges for vars (v:vs) j prods fn_name =
        i = lookup_producer prods v
        edges_for_one_var v vs j i prods fn_name

fn :: edges for one var String [String] Int Int [RProducerEntry] String => [RDagEdge] [RAnalysisError]
      edges for one var v vs j i prods fn_name
        | i < 0 = edges_for_vars vs j prods fn_name
        | i == j = merge_edges_and_errs ([], [ErrWhereCycle fn_name v]) (edges_for_vars vs j prods fn_name)
        | otherwise = merge_edges_and_errs ([DagEdge i j], []) (edges_for_vars vs j prods fn_name)

fn :: merge edges and errs ([RDagEdge], [RAnalysisError]) ([RDagEdge], [RAnalysisError]) => [RDagEdge] [RAnalysisError]
      merge edges and errs (e1, err1) (e2, err2) = (e1 :: e2, err1 :: err2)

fn :: dag neighbors Int [RDagEdge] => [Int]
      dag neighbors _   []         =  []
      dag neighbors u   ((DagEdge src dst):es)
        | src == u = [dst] :: (dag_neighbors u es)
        | otherwise = dag_neighbors u es

fn :: dag reachable dfs [Int] Int [RDagEdge] [Int] => Bool
      dag reachable dfs [] _ _ _ = False
      dag reachable dfs (curr:stack) dst edges visited
        | curr == dst = True
        | int_in_list curr visited = dag_reachable_dfs stack dst edges visited
        | otherwise = dag_reachable_dfs ((dag_neighbors curr edges) :: stack) dst edges (visited :: [curr])

fn :: has dag cycle Int Int [RDagEdge] => Bool
      has dag cycle idx n edges
        | idx >= n = False
        | dag_reachable_dfs (dag_neighbors idx edges) idx edges [] = True
        | otherwise = has_dag_cycle (idx + 1) n edges

fn :: are where nodes concurrent Int Int [RDagEdge] => Bool
      are where nodes concurrent a b edges
        | a == b = False
        | dag_reachable_dfs [a] b edges [] = False
        | dag_reachable_dfs [b] a edges [] = False
        | otherwise = True

-- ── Disjoint Slice & Parallel Mutation Conflict Check ────────

fn :: are disjoint slices String RWhereBind RWhereBind => Bool
      are disjoint slices var (WhereBind _ t1 (i1:_)) (WhereBind _ t2 (i2:_))
        | t1 == var AND t2 == var AND i1 != i2 = True
      are disjoint slices _ _ _ = False

fn :: collect bind accesses RWhereBind [RFnSummary] => [String] [String]
      collect bind accesses (WhereBind expr target idxs) summaries =
        reads = collect_free_vars expr []
        init_muts = init_target_mut target idxs
        eff_res = collect_expr_effects expr "" summaries init_muts False TierTrivial
        extract_reads_and_muts reads eff_res

fn :: init target mut String [Int] => [String]
      init target mut target (_:_) =  [target]
      init target mut _      []    =  []

fn :: extract reads and muts [String] ([String], Bool, RCostTier) => [String] [String]
      extract reads and muts reads (muts, _, _) = (reads, muts)

fn :: check vars conflict [String] String RWhereBind RWhereBind [String] [String] [String] [String] => [RAnalysisError]
      check vars conflict [] _ _ _ _ _ _ _ = []
      check vars conflict (v:vs) fn_name b1 b2 r1 m1 r2 m2
        | ((str_in_list v r1) OR (str_in_list v m1)) AND ((str_in_list v r2) OR (str_in_list v m2)) AND (NOT (are_disjoint_slices v b1 b2)) = [ErrParallelMutation fn_name v] :: (check_vars_conflict vs fn_name b1 b2 r1 m1 r2 m2)
        | otherwise = check_vars_conflict vs fn_name b1 b2 r1 m1 r2 m2

fn :: check pair conflict String RWhereBind RWhereBind [RFnSummary] => [RAnalysisError]
      check pair conflict fn_name b1 b2 summaries =
        acc1 = collect_bind_accesses b1 summaries
        acc2 = collect_bind_accesses b2 summaries
        check_pair_accesses fn_name b1 b2 acc1 acc2

fn :: check pair accesses String RWhereBind RWhereBind ([String], [String]) ([String], [String]) => [RAnalysisError]
      check pair accesses fn_name b1 b2 (r1, m1) (r2, m2) =
        all_muts = union_strs m1 m2
        check_vars_conflict all_muts fn_name b1 b2 r1 m1 r2 m2

fn :: where bind at [RWhereBind] Int => RWhereBind
      where bind at (b:_)        0   =  b
      where bind at (_:bs)       idx =  where_bind_at bs (idx - 1)
      where bind at []           _   =  WhereBind EUnit "" []

fn :: check where pairs j String [RWhereBind] Int Int Int [RDagEdge] [RFnSummary] => [RAnalysisError]
      check where pairs j fn_name binds i j n edges summaries
        | j >= n = []
        | are_where_nodes_concurrent i j edges = (check_pair_conflict fn_name (where_bind_at binds i) (where_bind_at binds j) summaries) :: (check_where_pairs_j fn_name binds i (j + 1) n edges summaries)
        | otherwise = check_where_pairs_j fn_name binds i (j + 1) n edges summaries

fn :: check where pairs i String [RWhereBind] Int Int [RDagEdge] [RFnSummary] => [RAnalysisError]
      check where pairs i fn_name binds i n edges summaries
        | i >= n = []
        | otherwise = (check_where_pairs_j fn_name binds i (i + 1) n edges summaries) :: (check_where_pairs_i fn_name binds (i + 1) n edges summaries)

fn :: check where block safety String RExpr [RWhereBind] [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check where block safety fn_name body binds mut_vars summaries moved =
        n = where_list_len binds
        prod_res = collect_producers binds 0 [] fn_name
        check_where_dag_step fn_name body binds n mut_vars summaries moved prod_res

fn :: check where dag step String RExpr [RWhereBind] Int [String] [RFnSummary] [String] ([RProducerEntry], [RAnalysisError]) => [String] [RAnalysisError]
      check where dag step _ _ _ _ _ _ moved (_, (err:errs)) = (moved, [err] :: errs)
      check where dag step fn_name body binds n mut_vars summaries moved (prods, []) =
        edge_res = build_where_edges binds 0 prods fn_name
        check_where_edges_step fn_name body binds n mut_vars summaries moved edge_res

fn :: check where edges step String RExpr [RWhereBind] Int [String] [RFnSummary] [String] ([RDagEdge], [RAnalysisError]) => [String] [RAnalysisError]
      check where edges step _ _ _ _ _ _ moved (_, (err:errs)) = (moved, [err] :: errs)
      check where edges step fn_name body binds n mut_vars summaries moved (edges, [])
        | has_dag_cycle 0 n edges = (moved, [ErrWhereCycle fn_name "cycle"])
        | otherwise = finish_where_safety body fn_name mut_vars summaries (check_where_pairs_i fn_name binds 0 n edges summaries) (check_where_binds_exprs binds fn_name mut_vars summaries moved)

fn :: check where binds exprs [RWhereBind] String [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check where binds exprs [] _ _ _ moved = (moved, [])
      check where binds exprs ((WhereBind e _ _):wbs) fn_name mut_vars summaries moved =
        r1 = check_expr_safety e fn_name mut_vars summaries moved
        check_where_binds_cont wbs fn_name mut_vars summaries r1

fn :: check where binds cont [RWhereBind] String [String] [RFnSummary] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      check where binds cont wbs fn_name mut_vars summaries (moved1, errs1) =
        r2 = check_where_binds_exprs wbs fn_name mut_vars summaries moved1
        merge_moved_errs errs1 r2

fn :: finish where safety RExpr String [String] [RFnSummary] [RAnalysisError] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      finish where safety body fn_name mut_vars summaries pair_errs (moved1, bind_errs) =
        r_body = check_expr_safety body fn_name mut_vars summaries moved1
        merge_moved_errs (pair_errs :: bind_errs) r_body

fn :: merge moved errs [RAnalysisError] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      merge moved errs errs1 (moved2, errs2) = (moved2, errs1 :: errs2)

-- ── Affine Channel Ownership & Safety Verification ──────────

fn :: is channel send call String => Bool
      is channel send call callee =
        callee == "send" OR callee == "send_to" OR callee == "send_through" OR callee == "chan_send"

fn :: mark channel sent String [RExpr] [String] [String] => [String]
      mark channel sent callee ((EVar sent_var):_) mut_vars moved
        | (is_channel_send_call callee) AND (str_in_list sent_var mut_vars) = add_unique_str sent_var moved
      mark channel sent _ _ _ moved = moved

fn :: check expr safety RExpr String [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check expr safety (EVar name) fn_name _ _ moved
        | str_in_list name moved = (moved, [ErrUseAfterSend fn_name name])
        | otherwise = (moved, [])
      check expr safety (ECall callee args) fn_name mut_vars summaries moved =
        r_args = check_expr_list_safety args fn_name mut_vars summaries moved
        finish_call_safety callee args mut_vars r_args
      check expr safety (EWhere body binds) fn_name mut_vars summaries moved =
        check_where_block_safety fn_name body binds mut_vars summaries moved
      check expr safety (EBlock stmts) fn_name mut_vars summaries moved =
        check_stmt_list_safety stmts fn_name mut_vars summaries moved
      check expr safety (EGuard guards) fn_name mut_vars summaries moved =
        check_guards_safety guards fn_name mut_vars summaries moved
      check expr safety (EBin _ l r) fn_name mut_vars summaries moved =
        r1 = check_expr_safety l fn_name mut_vars summaries moved
        check_expr_safety_tuple r fn_name mut_vars summaries r1
      check expr safety (EHadamard _ l _ r _) fn_name mut_vars summaries moved =
        r1 = check_expr_safety l fn_name mut_vars summaries moved
        check_expr_safety_tuple r fn_name mut_vars summaries r1
      check expr safety (EEinsum es _) fn_name mut_vars summaries moved =
        check_expr_list_safety es fn_name mut_vars summaries moved
      check expr safety (ENot inner) fn_name mut_vars summaries moved =
        check_expr_safety inner fn_name mut_vars summaries moved
      check expr safety (EOut inner) fn_name mut_vars summaries moved =
        check_expr_safety inner fn_name mut_vars summaries moved
      check expr safety (EWithRegion _ inner) fn_name mut_vars summaries moved =
        check_expr_safety inner fn_name mut_vars summaries moved
      check expr safety (EWithCtx _ v b) fn_name mut_vars summaries moved =
        r1 = check_expr_safety v fn_name mut_vars summaries moved
        check_expr_safety_tuple b fn_name mut_vars summaries r1
      check expr safety (EStrInterp parts) fn_name mut_vars summaries moved =
        check_expr_list_safety parts fn_name mut_vars summaries moved
      check expr safety (EIndex base idxs) fn_name mut_vars summaries moved =
        r1 = check_expr_safety base fn_name mut_vars summaries moved
        check_expr_list_safety_tuple idxs fn_name mut_vars summaries r1
      check expr safety _ _ _ _ moved = (moved, [])

fn :: finish call safety String [RExpr] [String] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      finish call safety callee args mut_vars (moved1, errs) =
        (mark_channel_sent callee args mut_vars moved1, errs)

fn :: check expr safety tuple RExpr String [String] [RFnSummary] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      check expr safety tuple e fn_name mut_vars summaries (moved, errs) =
        merge_moved_errs errs (check_expr_safety e fn_name mut_vars summaries moved)

fn :: check expr list safety [RExpr] String [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check expr list safety [] _ _ _ moved = (moved, [])
      check expr list safety (e:es) fn_name mut_vars summaries moved =
        r1 = check_expr_safety e fn_name mut_vars summaries moved
        check_expr_list_safety_tuple es fn_name mut_vars summaries r1

fn :: check expr list safety tuple [RExpr] String [String] [RFnSummary] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      check expr list safety tuple es fn_name mut_vars summaries (moved, errs) =
        merge_moved_errs errs (check_expr_list_safety es fn_name mut_vars summaries moved)

fn :: is tensor expr RExpr       => Bool
      is tensor expr (ETensor _) =  True
      is tensor expr _           =  False

fn :: check guards safety [RGuard] String [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check guards safety [] _ _ _ moved = (moved, [])
      check guards safety ((GuardBranch c b):gs) fn_name mut_vars summaries moved =
        r1 = check_expr_safety c fn_name mut_vars summaries moved
        r2 = check_expr_safety_tuple b fn_name mut_vars summaries r1
        check_guards_safety_tuple gs fn_name mut_vars summaries r2

fn :: check guards safety tuple [RGuard] String [String] [RFnSummary] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      check guards safety tuple gs fn_name mut_vars summaries (moved, errs) =
        merge_moved_errs errs (check_guards_safety gs fn_name mut_vars summaries moved)

fn :: check stmt list safety [RStmt] String [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check stmt list safety [] _ _ _ moved = (moved, [])
      check stmt list safety ((StmtLet v val_e):ss) fn_name mut_vars summaries moved
        | is_tensor_expr val_e = check_stmt_list_safety_tuple ss fn_name (add_unique_str v mut_vars) summaries (check_expr_safety val_e fn_name (add_unique_str v mut_vars) summaries moved)
        | otherwise = check_stmt_list_safety_tuple ss fn_name mut_vars summaries (check_expr_safety val_e fn_name mut_vars summaries moved)
      check stmt list safety ((StmtMut v val_e):ss) fn_name mut_vars summaries moved =
        check_stmt_list_safety_tuple ss fn_name (add_unique_str v mut_vars) summaries (check_expr_safety val_e fn_name (add_unique_str v mut_vars) summaries moved)
      check stmt list safety ((StmtExpr e):ss) fn_name mut_vars summaries moved =
        r1 = check_expr_safety e fn_name mut_vars summaries moved
        check_stmt_list_safety_tuple ss fn_name mut_vars summaries r1
      check stmt list safety ((StmtIndexAssign _ idxs e):ss) fn_name mut_vars summaries moved =
        r1 = check_expr_list_safety idxs fn_name mut_vars summaries moved
        r2 = check_expr_safety_tuple e fn_name mut_vars summaries r1
        check_stmt_list_safety_tuple ss fn_name mut_vars summaries r2

fn :: check stmt list safety tuple [RStmt] String [String] [RFnSummary] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      check stmt list safety tuple ss fn_name mut_vars summaries (moved, errs) =
        merge_moved_errs errs (check_stmt_list_safety ss fn_name mut_vars summaries moved)

fn :: collect mutable params [String]   [RPattern]        => [String]
      collect mutable params []         _                 =  []
      collect mutable params _          []                =  []
      collect mutable params (pty:ptys) ((PatVar v):pats)
        | str_starts_with pty "Tensor" = add_unique_str v (collect_mutable_params ptys pats)
        | otherwise = collect_mutable_params ptys pats
      collect mutable params (_:ptys)   (_:pats)          =  collect_mutable_params ptys pats

fn :: check cases safety [RFnCase] String [String] [RFnSummary] => [RAnalysisError]
      check cases safety [] _ _ _ = []
      check cases safety ((FnCase pats _ body):cs) fn_name param_types summaries =
        mut_params = collect_mutable_params param_types pats
        res = check_expr_safety body fn_name mut_params summaries []
        extract_analysis_errs res (check_cases_safety cs fn_name param_types summaries)

fn :: extract analysis errs ([String], [RAnalysisError]) [RAnalysisError] => [RAnalysisError]
      extract analysis errs (_, errs) more = errs :: more

fn :: check all fns safety acc [RFnDef] [RFnSummary] [RAnalysisError] => [RAnalysisError]
      check all fns safety acc [] _ acc = acc
      check all fns safety acc ((FnDef name param_types _ cases):fs) summaries acc =
        check_all_fns_safety_acc fs summaries (acc :: (check_cases_safety cases name param_types summaries))

fn :: check all fns safety [RFnDef] [RFnSummary] => [RAnalysisError]
      check all fns safety fns summaries =
        check_all_fns_safety_acc fns summaries []

fn :: analyze program errors RProgram => [RAnalysisError]
      analyze program errors prog     =
        summaries = filter_nontrivial_summaries (infer_all_summaries prog)
        check_program_with_summaries prog summaries

fn :: check program with summaries RProgram [RFnSummary] => [RAnalysisError]
      check program with summaries (Program fns _) summaries =
        check_all_fns_safety fns summaries

fn :: format summaries acc [RFnSummary] [String] => [String]
      format summaries acc [] acc = acc
      format summaries acc ((FnSummary name _ _ _ strat):ss) acc =
        format_summaries_acc ss (acc :: [name + ":" + (strategy_to_str strat)])

fn :: format summaries [RFnSummary] => [String]
      format summaries ss           =  format_summaries_acc ss []

fn :: analyze rprogram RProgram => [String]
      analyze rprogram prog     =  format_summaries (infer_all_summaries prog)

fn :: analysis err count [RAnalysisError] => Int
      analysis err count []               =  0
      analysis err count (_:xs)           =  1 + (analysis_err_count xs)

fn :: verify rprogram RProgram => Bool
      verify rprogram prog     =  (analysis_err_count (analyze_program_errors prog)) == 0
