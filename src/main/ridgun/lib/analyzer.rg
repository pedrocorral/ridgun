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

fn :: str_in_list String [String] => Bool
      str_in_list _      []       =  False
      str_in_list target (x:xs)
        | x == target = True
        | otherwise = str_in_list target xs

fn :: add_unique_str String [String] => [String]
      add_unique_str s      xs
        | str_in_list s xs = xs
        | otherwise = xs :: [s]

fn :: union_strs [String] [String] => [String]
      union_strs []       ys       =  ys
      union_strs (x:xs)   ys       =  union_strs xs (add_unique_str x ys)

fn :: int_in_list Int    [Int]  => Bool
      int_in_list _      []     =  False
      int_in_list target (x:xs)
        | x == target = True
        | otherwise = int_in_list target xs

fn :: int_list_len [Int]  => Int
      int_list_len []     =  0
      int_list_len (_:xs) =  1 + (int_list_len xs)

fn :: where_list_len [RWhereBind] => Int
      where_list_len []           =  0
      where_list_len (_:xs)       =  1 + (where_list_len xs)

-- ── Cost Tier & 4-Tier Strategy Selection ───────────────────

fn :: cost_rank RCostTier    => Int
      cost_rank TierTrivial  =  0
      cost_rank TierHeavyCPU =  1
      cost_rank TierDynamicRecursive = 2

fn :: max_cost_tier RCostTier RCostTier => RCostTier
      max_cost_tier a         b
        | (cost_rank a) >= (cost_rank b) = a
        | otherwise = b

fn :: select_exec_strategy Bool  RCostTier    => RExecStrategy
      select_exec_strategy True  _            =  StratFullGreenThread
      select_exec_strategy False TierTrivial  =  StratInlineSequential
      select_exec_strategy False TierHeavyCPU =  StratKernelWorkerJob
      select_exec_strategy False TierDynamicRecursive = StratLazyStealableTask

fn :: strategy_to_str RExecStrategy => String
      strategy_to_str StratInlineSequential = "InlineSequential"
      strategy_to_str StratKernelWorkerJob = "KernelWorkerJob"
      strategy_to_str StratLazyStealableTask = "LazyStealableTask"
      strategy_to_str StratFullGreenThread = "FullGreenThread"

-- ── Summary Table Lookup & Update ───────────────────────────

fn :: lookup_fn_summary [RFnSummary] String => (Bool, RFnSummary)
      lookup_fn_summary []           name   =
        (False, FnSummary name [] False TierTrivial StratInlineSequential)
      lookup_fn_summary ((FnSummary sname effs yld cost strat):rest) name
        | sname == name = (True, FnSummary sname effs yld cost strat)
        | otherwise = lookup_fn_summary rest name

fn :: is_yielding_builtin String => Bool
      is_yielding_builtin callee =
        callee == "recv" OR callee == "receive_from" OR callee == "receive_from_timeout" OR callee == "send_through" OR callee == "join"

fn :: param_effect_at [RParamEffect] Int => RParamEffect
      param_effect_at []             _   =  EffReadOnly
      param_effect_at (e:_)          0   =  e
      param_effect_at (_:es)         idx =  param_effect_at es (idx - 1)

fn :: collect_mutated_call_args [RExpr] [RParamEffect] Int [String] => [String]
      collect_mutated_call_args [] _ _ acc = acc
      collect_mutated_call_args ((EVar v):args) effs idx acc
        | (param_effect_at effs idx) == EffMutates = collect_mutated_call_args args effs (idx + 1) (add_unique_str v acc)
        | otherwise = collect_mutated_call_args args effs (idx + 1) acc
      collect_mutated_call_args (_:args) effs idx acc =
        collect_mutated_call_args args effs (idx + 1) acc

-- ── Expression Effect & Self-Call Collection ────────────────

fn :: count_expr_self_calls String  RExpr              => Int
      count_expr_self_calls fn_name (ENot inner)       =  count_expr_self_calls fn_name inner
      count_expr_self_calls fn_name (EOut inner)       =  count_expr_self_calls fn_name inner
      count_expr_self_calls fn_name (EBin _ l r)       =  (count_expr_self_calls fn_name l) + (count_expr_self_calls fn_name r)
      count_expr_self_calls fn_name (ECall callee args)
        | callee == fn_name = 1 + (count_expr_list_calls fn_name args)
        | otherwise = count_expr_list_calls fn_name args
      count_expr_self_calls fn_name (EEcho args)       =  count_expr_list_calls fn_name args
      count_expr_self_calls fn_name (EStrInterp args)  =  count_expr_list_calls fn_name args
      count_expr_self_calls fn_name (EList elems)      =  count_expr_list_calls fn_name elems
      count_expr_self_calls fn_name (ETuple elems)     =  count_expr_list_calls fn_name elems
      count_expr_self_calls fn_name (ETensor elems)    =  count_expr_list_calls fn_name elems
      count_expr_self_calls fn_name (EEinsum es _)     =  count_expr_list_calls fn_name es
      count_expr_self_calls fn_name (EHadamard _ l _ r _) = (count_expr_self_calls fn_name l) + (count_expr_self_calls fn_name r)
      count_expr_self_calls fn_name (EIndex b idxs)    =  (count_expr_self_calls fn_name b) + (count_expr_list_calls fn_name idxs)
      count_expr_self_calls fn_name (EIndexAssign _ idxs v) = (count_expr_list_calls fn_name idxs) + (count_expr_self_calls fn_name v)
      count_expr_self_calls fn_name (ESeqSelect b _)   =  count_expr_self_calls fn_name b
      count_expr_self_calls fn_name (EBlock stmts)     =  count_stmt_list_calls fn_name stmts
      count_expr_self_calls fn_name (EGuard guards)    =  count_guard_calls fn_name guards
      count_expr_self_calls fn_name (EWhere body binds) = (count_expr_self_calls fn_name body) + (count_where_calls fn_name binds)
      count_expr_self_calls fn_name (EParPipe branches) = count_expr_list_calls fn_name branches
      count_expr_self_calls fn_name (EWithCtx _ v b)   =  (count_expr_self_calls fn_name v) + (count_expr_self_calls fn_name b)
      count_expr_self_calls fn_name (EWithRegion _ b)  =  count_expr_self_calls fn_name b
      count_expr_self_calls fn_name (EAtomicUpdate _ b) = count_expr_self_calls fn_name b
      count_expr_self_calls fn_name (ELoadContext _ b) =  count_expr_self_calls fn_name b
      count_expr_self_calls fn_name (ELoadShared _ b)  =  count_expr_self_calls fn_name b
      count_expr_self_calls _       _                  =  0

fn :: count_expr_list_calls String  [RExpr] => Int
      count_expr_list_calls _       []      =  0
      count_expr_list_calls fn_name (e:es)  =  (count_expr_self_calls fn_name e) + (count_expr_list_calls fn_name es)

fn :: count_stmt_list_calls String  [RStmt]            => Int
      count_stmt_list_calls _       []                 =  0
      count_stmt_list_calls fn_name ((StmtLet _ e):ss) =  (count_expr_self_calls fn_name e) + (count_stmt_list_calls fn_name ss)
      count_stmt_list_calls fn_name ((StmtMut _ e):ss) =  (count_expr_self_calls fn_name e) + (count_stmt_list_calls fn_name ss)
      count_stmt_list_calls fn_name ((StmtExpr e):ss)  =  (count_expr_self_calls fn_name e) + (count_stmt_list_calls fn_name ss)
      count_stmt_list_calls fn_name ((StmtAtomic _ e):ss) = (count_expr_self_calls fn_name e) + (count_stmt_list_calls fn_name ss)
      count_stmt_list_calls fn_name ((StmtIndexAssign _ idxs e):ss) = (count_expr_list_calls fn_name idxs) + (count_expr_self_calls fn_name e) + (count_stmt_list_calls fn_name ss)

fn :: count_where_calls String  [RWhereBind] => Int
      count_where_calls _       []           =  0
      count_where_calls fn_name ((WhereBind e _ _):wbs) = (count_expr_self_calls fn_name e) + (count_where_calls fn_name wbs)

fn :: count_guard_calls String  [RGuard] => Int
      count_guard_calls _       []       =  0
      count_guard_calls fn_name ((GuardBranch c b):gs) = (count_expr_self_calls fn_name c) + (count_expr_self_calls fn_name b) + (count_guard_calls fn_name gs)

fn :: count_case_calls String  [RFnCase] => Int
      count_case_calls _       []        =  0
      count_case_calls fn_name ((FnCase _ gs b):cs) =
        c_here = (count_guard_calls fn_name gs) + (count_expr_self_calls fn_name b)
        c_rest = count_case_calls fn_name cs
        max_int c_here c_rest

fn :: max_int Int Int => Int
      max_int a   b
        | a >= b = a
        | otherwise = b

fn :: collect_expr_effects RExpr String [RFnSummary] [String] Bool RCostTier => ([String], Bool, RCostTier)
      collect_expr_effects (ECall callee args) cur_fn summaries muts yld cost =
        after_call = apply_callee_summary callee args cur_fn (lookup_fn_summary summaries callee) muts yld cost
        collect_expr_list_effects_tuple args cur_fn summaries after_call
      collect_expr_effects (EIndexAssign target idxs val) cur_fn summaries muts yld cost =
        muts1 = add_unique_str target muts
        r_idxs = collect_expr_list_effects idxs cur_fn summaries muts1 yld cost
        collect_expr_effects_tuple val cur_fn summaries r_idxs
      collect_expr_effects (EWhere body binds) cur_fn summaries muts yld cost =
        r_body = collect_expr_effects body cur_fn summaries muts yld cost
        collect_where_effects_tuple binds cur_fn summaries r_body
      collect_expr_effects (EParPipe branches) cur_fn summaries muts yld cost =
        collect_expr_list_effects branches cur_fn summaries muts yld cost
      collect_expr_effects (EBin _ l r) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects l cur_fn summaries muts yld cost
        collect_expr_effects_tuple r cur_fn summaries r1
      collect_expr_effects (EHadamard _ l _ r _) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects l cur_fn summaries muts yld (max_cost_tier cost TierHeavyCPU)
        collect_expr_effects_tuple r cur_fn summaries r1
      collect_expr_effects (EEinsum es _) cur_fn summaries muts yld cost =
        collect_expr_list_effects es cur_fn summaries muts yld (max_cost_tier cost TierHeavyCPU)
      collect_expr_effects (ETensor elems) cur_fn summaries muts yld cost =
        collect_expr_list_effects elems cur_fn summaries muts yld (max_cost_tier cost TierHeavyCPU)
      collect_expr_effects (ENot inner) cur_fn summaries muts yld cost =
        collect_expr_effects inner cur_fn summaries muts yld cost
      collect_expr_effects (EOut inner) cur_fn summaries muts yld cost =
        collect_expr_effects inner cur_fn summaries muts yld cost
      collect_expr_effects (EWithRegion _ inner) cur_fn summaries muts yld cost =
        collect_expr_effects inner cur_fn summaries muts yld cost
      collect_expr_effects (EAtomicUpdate _ inner) cur_fn summaries muts yld cost =
        collect_expr_effects inner cur_fn summaries muts yld cost
      collect_expr_effects (ELoadContext _ inner) cur_fn summaries muts yld cost =
        collect_expr_effects inner cur_fn summaries muts yld cost
      collect_expr_effects (ELoadShared _ inner) cur_fn summaries muts yld cost =
        collect_expr_effects inner cur_fn summaries muts yld cost
      collect_expr_effects (EWithCtx _ v b) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects v cur_fn summaries muts yld cost
        collect_expr_effects_tuple b cur_fn summaries r1
      collect_expr_effects (EBlock stmts) cur_fn summaries muts yld cost =
        collect_stmt_list_effects stmts cur_fn summaries muts yld cost
      collect_expr_effects (EGuard guards) cur_fn summaries muts yld cost =
        collect_guards_effects guards cur_fn summaries muts yld cost
      collect_expr_effects (EList elems) cur_fn summaries muts yld cost =
        collect_expr_list_effects elems cur_fn summaries muts yld cost
      collect_expr_effects (ETuple elems) cur_fn summaries muts yld cost =
        collect_expr_list_effects elems cur_fn summaries muts yld cost
      collect_expr_effects (EEcho elems) cur_fn summaries muts yld cost =
        collect_expr_list_effects elems cur_fn summaries muts yld cost
      collect_expr_effects (EStrInterp elems) cur_fn summaries muts yld cost =
        collect_expr_list_effects elems cur_fn summaries muts yld cost
      collect_expr_effects (EIndex b idxs) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects b cur_fn summaries muts yld cost
        collect_expr_list_effects_tuple idxs cur_fn summaries r1
      collect_expr_effects _ _ _ muts yld cost = (muts, yld, cost)

fn :: collect_expr_effects_tuple RExpr String [RFnSummary] ([String], Bool, RCostTier) => ([String], Bool, RCostTier)
      collect_expr_effects_tuple e cur_fn summaries (muts, yld, cost) =
        collect_expr_effects e cur_fn summaries muts yld cost

fn :: collect_expr_list_effects [RExpr] String [RFnSummary] [String] Bool RCostTier => ([String], Bool, RCostTier)
      collect_expr_list_effects [] _ _ muts yld cost = (muts, yld, cost)
      collect_expr_list_effects (e:es) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects e cur_fn summaries muts yld cost
        collect_expr_list_effects_tuple es cur_fn summaries r1

fn :: collect_expr_list_effects_tuple [RExpr] String [RFnSummary] ([String], Bool, RCostTier) => ([String], Bool, RCostTier)
      collect_expr_list_effects_tuple es cur_fn summaries (muts, yld, cost) =
        collect_expr_list_effects es cur_fn summaries muts yld cost

fn :: collect_stmt_list_effects [RStmt] String [RFnSummary] [String] Bool RCostTier => ([String], Bool, RCostTier)
      collect_stmt_list_effects [] _ _ muts yld cost = (muts, yld, cost)
      collect_stmt_list_effects ((StmtLet _ e):ss) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects e cur_fn summaries muts yld cost
        collect_stmt_list_effects_tuple ss cur_fn summaries r1
      collect_stmt_list_effects ((StmtMut _ e):ss) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects e cur_fn summaries muts yld cost
        collect_stmt_list_effects_tuple ss cur_fn summaries r1
      collect_stmt_list_effects ((StmtExpr e):ss) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects e cur_fn summaries muts yld cost
        collect_stmt_list_effects_tuple ss cur_fn summaries r1
      collect_stmt_list_effects ((StmtAtomic _ e):ss) cur_fn summaries muts yld cost =
        r1 = collect_expr_effects e cur_fn summaries muts yld cost
        collect_stmt_list_effects_tuple ss cur_fn summaries r1
      collect_stmt_list_effects ((StmtIndexAssign target idxs e):ss) cur_fn summaries muts yld cost =
        muts1 = add_unique_str target muts
        r_idxs = collect_expr_list_effects idxs cur_fn summaries muts1 yld cost
        r_val = collect_expr_effects_tuple e cur_fn summaries r_idxs
        collect_stmt_list_effects_tuple ss cur_fn summaries r_val

fn :: collect_stmt_list_effects_tuple [RStmt] String [RFnSummary] ([String], Bool, RCostTier) => ([String], Bool, RCostTier)
      collect_stmt_list_effects_tuple ss cur_fn summaries (muts, yld, cost) =
        collect_stmt_list_effects ss cur_fn summaries muts yld cost

fn :: collect_where_effects [RWhereBind] String [RFnSummary] [String] Bool RCostTier => ([String], Bool, RCostTier)
      collect_where_effects [] _ _ muts yld cost = (muts, yld, cost)
      collect_where_effects ((WhereBind e target idxs):wbs) cur_fn summaries muts yld cost
        | (int_list_len idxs) > 0 = collect_where_effects_tuple wbs cur_fn summaries (collect_expr_effects e cur_fn summaries (add_unique_str target muts) yld cost)
        | otherwise = collect_where_effects_tuple wbs cur_fn summaries (collect_expr_effects e cur_fn summaries muts yld cost)

fn :: collect_where_effects_tuple [RWhereBind] String [RFnSummary] ([String], Bool, RCostTier) => ([String], Bool, RCostTier)
      collect_where_effects_tuple wbs cur_fn summaries (muts, yld, cost) =
        collect_where_effects wbs cur_fn summaries muts yld cost

fn :: apply_callee_summary String [RExpr] String (Bool, RFnSummary) [String] Bool RCostTier => ([String], Bool, RCostTier)
      apply_callee_summary callee args cur_fn (found, (FnSummary _ effs s_yld s_cost _)) muts yld cost =
        yld1 = yld OR (is_yielding_builtin callee) OR (found AND s_yld)
        cost1 = compute_call_cost callee cur_fn found s_cost cost
        muts1 = collect_mutated_call_args args effs 0 muts
        (muts1, yld1, cost1)

fn :: compute_call_cost String String Bool RCostTier RCostTier => RCostTier
      compute_call_cost callee cur_fn _ _ cost
        | callee == cur_fn = max_cost_tier cost TierDynamicRecursive
      compute_call_cost _ _ True s_cost cost = max_cost_tier cost s_cost
      compute_call_cost _ _ False _ cost = cost

-- ── Classify Arbitrary Expression Strategy ──────────────────

fn :: classify_expr_strategy RExpr String [RFnSummary] => RExecStrategy
      classify_expr_strategy expr  cur_fn summaries    =
        finish_expr_strategy (collect_expr_effects expr cur_fn summaries [] False TierTrivial)

fn :: finish_expr_strategy ([String], Bool, RCostTier) => RExecStrategy
      finish_expr_strategy (_, yld, cost)              =  select_exec_strategy yld cost

-- ── Per-Function Static Summary Inference ───────────────────

fn :: init_readonly_effects [String] => [RParamEffect]
      init_readonly_effects []       =  []
      init_readonly_effects (_:ps)   =  [EffReadOnly] :: (init_readonly_effects ps)

fn :: update_param_effects [RPattern] [RParamEffect] [String] => [RParamEffect]
      update_param_effects [] effs _ = effs
      update_param_effects _ [] _ = []
      update_param_effects ((PatVar v):ps) (e:es) muts
        | str_in_list v muts = [EffMutates] :: (update_param_effects ps es muts)
        | otherwise = [e] :: (update_param_effects ps es muts)
      update_param_effects (_:ps) (e:es) muts =
        [e] :: (update_param_effects ps es muts)

fn :: collect_guards_effects [RGuard] String [RFnSummary] [String] Bool RCostTier => ([String], Bool, RCostTier)
      collect_guards_effects [] _ _ muts yld cost = (muts, yld, cost)
      collect_guards_effects ((GuardBranch c b):gs) fn_name summaries muts yld cost =
        r1 = collect_expr_effects c fn_name summaries muts yld cost
        r2 = collect_expr_effects_tuple b fn_name summaries r1
        collect_guards_effects_tuple gs fn_name summaries r2

fn :: collect_guards_effects_tuple [RGuard] String [RFnSummary] ([String], Bool, RCostTier) => ([String], Bool, RCostTier)
      collect_guards_effects_tuple gs fn_name summaries (muts, yld, cost) =
        collect_guards_effects gs fn_name summaries muts yld cost

fn :: collect_cases_summary [RFnCase] String [RFnSummary] [RParamEffect] Bool RCostTier => ([RParamEffect], Bool, RCostTier)
      collect_cases_summary [] _ _ effs yld cost = (effs, yld, cost)
      collect_cases_summary ((FnCase pats guards body):cs) fn_name summaries effs yld cost =
        r_body = collect_expr_effects body fn_name summaries [] yld cost
        r_all = collect_guards_effects_tuple guards fn_name summaries r_body
        collect_cases_step pats cs fn_name summaries effs r_all

fn :: collect_cases_step [RPattern] [RFnCase] String [RFnSummary] [RParamEffect] ([String], Bool, RCostTier) => ([RParamEffect], Bool, RCostTier)
      collect_cases_step pats cs fn_name summaries effs (case_muts, yld1, cost1) =
        effs1 = update_param_effects pats effs case_muts
        collect_cases_summary cs fn_name summaries effs1 yld1 cost1

fn :: adjust_recursive_cost Int        RCostTier => RCostTier
      adjust_recursive_cost self_calls cost
        | self_calls == 1 = max_cost_tier cost TierHeavyCPU
        | self_calls > 1 = TierDynamicRecursive
        | otherwise = cost

fn :: compute_one_fn_summary RFnDef [RFnSummary] => RFnSummary
      compute_one_fn_summary (FnDef name params _ cases) summaries =
        init_effs = init_readonly_effects params
        self_calls = count_case_calls name cases
        res = collect_cases_summary cases name summaries init_effs False TierTrivial
        finish_fn_summary name self_calls res

fn :: finish_fn_summary String Int ([RParamEffect], Bool, RCostTier) => RFnSummary
      finish_fn_summary name self_calls (effs, yld, raw_cost) =
        final_cost = adjust_recursive_cost self_calls raw_cost
        strat = select_exec_strategy yld final_cost
        FnSummary name effs yld final_cost strat

fn :: compute_summaries_pass [RFnDef] [RFnSummary]  => [RFnSummary]
      compute_summaries_pass []       _             =  []
      compute_summaries_pass (f:fs)   cur_summaries =
        s = compute_one_fn_summary f cur_summaries
        [s] :: (compute_summaries_pass fs (cur_summaries :: [s]))

fn :: infer_all_summaries RProgram        => [RFnSummary]
      infer_all_summaries (Program fns _) =
        pass1 = compute_summaries_pass fns []
        compute_summaries_pass fns pass1

-- ── Free Variable Extraction & Where-Block DAG / Cycle Check ──

fn :: collect_free_vars RExpr              [String] => [String]
      collect_free_vars (EVar v)           acc      =  add_unique_str v acc
      collect_free_vars (ENot inner)       acc      =  collect_free_vars inner acc
      collect_free_vars (EOut inner)       acc      =  collect_free_vars inner acc
      collect_free_vars (EBin _ l r)       acc      =  collect_free_vars r (collect_free_vars l acc)
      collect_free_vars (EHadamard _ l _ r _) acc   =  collect_free_vars r (collect_free_vars l acc)
      collect_free_vars (EEinsum es _)     acc      =  collect_free_vars_list es acc
      collect_free_vars (ECall _ args)     acc      =  collect_free_vars_list args acc
      collect_free_vars (EEcho args)       acc      =  collect_free_vars_list args acc
      collect_free_vars (EStrInterp args)  acc      =  collect_free_vars_list args acc
      collect_free_vars (EList args)       acc      =  collect_free_vars_list args acc
      collect_free_vars (ETuple args)      acc      =  collect_free_vars_list args acc
      collect_free_vars (ETensor args)     acc      =  collect_free_vars_list args acc
      collect_free_vars (EIndex b idxs)    acc      =  collect_free_vars_list idxs (collect_free_vars b acc)
      collect_free_vars (EIndexAssign t idxs v) acc =  collect_free_vars v (collect_free_vars_list idxs (add_unique_str t acc))
      collect_free_vars (ESeqSelect b _)   acc      =  collect_free_vars b acc
      collect_free_vars (EWithCtx _ v b)   acc      =  collect_free_vars b (collect_free_vars v acc)
      collect_free_vars (EWithRegion _ b)  acc      =  collect_free_vars b acc
      collect_free_vars (EAtomicUpdate _ b) acc     =  collect_free_vars b acc
      collect_free_vars (ELoadContext _ b) acc      =  collect_free_vars b acc
      collect_free_vars (ELoadShared _ b)  acc      =  collect_free_vars b acc
      collect_free_vars _                  acc      =  acc

fn :: collect_free_vars_list [RExpr] [String] => [String]
      collect_free_vars_list []      acc      =  acc
      collect_free_vars_list (e:es)  acc      =  collect_free_vars_list es (collect_free_vars e acc)

type RProducerEntry = ProducerEntry String Int

fn :: lookup_producer [RProducerEntry] String => Int
      lookup_producer []               _      =  -1
      lookup_producer ((ProducerEntry k idx):rest) target
        | k == target = idx
        | otherwise = lookup_producer rest target

fn :: collect_producers [RWhereBind] Int [RProducerEntry] String => ([RProducerEntry], [RAnalysisError])
      collect_producers [] _ acc _ = (acc, [])
      collect_producers ((WhereBind _ target idxs):wbs) idx acc fn_name
        | (int_list_len idxs) > 0 OR target == "" = collect_producers wbs (idx + 1) acc fn_name
        | (lookup_producer acc target) >= 0 = add_prod_err (ErrWhereCycle fn_name target) (collect_producers wbs (idx + 1) acc fn_name)
        | otherwise = collect_producers wbs (idx + 1) (acc :: [ProducerEntry target idx]) fn_name

fn :: add_prod_err RAnalysisError ([RProducerEntry], [RAnalysisError]) => ([RProducerEntry], [RAnalysisError])
      add_prod_err err (prods, errs) = (prods, [err] :: errs)

type RDagEdge = DagEdge Int Int

fn :: build_where_edges [RWhereBind] Int [RProducerEntry] String => ([RDagEdge], [RAnalysisError])
      build_where_edges [] _ _ _ = ([], [])
      build_where_edges ((WhereBind expr _ _):wbs) j prods fn_name =
        fvars = collect_free_vars expr []
        e_here = edges_for_vars fvars j prods fn_name
        e_rest = build_where_edges wbs (j + 1) prods fn_name
        merge_edges_and_errs e_here e_rest

fn :: edges_for_vars [String] Int [RProducerEntry] String => ([RDagEdge], [RAnalysisError])
      edges_for_vars [] _ _ _ = ([], [])
      edges_for_vars (v:vs) j prods fn_name =
        i = lookup_producer prods v
        edges_for_one_var v vs j i prods fn_name

fn :: edges_for_one_var String [String] Int Int [RProducerEntry] String => ([RDagEdge], [RAnalysisError])
      edges_for_one_var v vs j i prods fn_name
        | i < 0 = edges_for_vars vs j prods fn_name
        | i == j = merge_edges_and_errs ([], [ErrWhereCycle fn_name v]) (edges_for_vars vs j prods fn_name)
        | otherwise = merge_edges_and_errs ([DagEdge i j], []) (edges_for_vars vs j prods fn_name)

fn :: merge_edges_and_errs ([RDagEdge], [RAnalysisError]) ([RDagEdge], [RAnalysisError]) => ([RDagEdge], [RAnalysisError])
      merge_edges_and_errs (e1, err1) (e2, err2) = (e1 :: e2, err1 :: err2)

fn :: dag_neighbors Int [RDagEdge] => [Int]
      dag_neighbors _   []         =  []
      dag_neighbors u   ((DagEdge src dst):es)
        | src == u = [dst] :: (dag_neighbors u es)
        | otherwise = dag_neighbors u es

fn :: dag_reachable_dfs [Int]        Int [RDagEdge] [Int]   => Bool
      dag_reachable_dfs []           _   _          _       =  False
      dag_reachable_dfs (curr:stack) dst edges      visited
        | curr == dst = True
        | int_in_list curr visited = dag_reachable_dfs stack dst edges visited
        | otherwise = dag_reachable_dfs ((dag_neighbors curr edges) :: stack) dst edges (visited :: [curr])

fn :: has_dag_cycle Int Int [RDagEdge] => Bool
      has_dag_cycle idx n   edges
        | idx >= n = False
        | dag_reachable_dfs (dag_neighbors idx edges) idx edges [] = True
        | otherwise = has_dag_cycle (idx + 1) n edges

fn :: are_where_nodes_concurrent Int Int [RDagEdge] => Bool
      are_where_nodes_concurrent a   b   edges
        | a == b = False
        | dag_reachable_dfs [a] b edges [] = False
        | dag_reachable_dfs [b] a edges [] = False
        | otherwise = True

-- ── Disjoint Slice & Parallel Mutation Conflict Check ────────

fn :: are_disjoint_slices String RWhereBind RWhereBind => Bool
      are_disjoint_slices var    (WhereBind _ t1 (i1:_)) (WhereBind _ t2 (i2:_))
        | t1 == var AND t2 == var AND i1 != i2 = True
      are_disjoint_slices _      _          _          =  False

fn :: collect_bind_accesses RWhereBind [RFnSummary] => ([String], [String])
      collect_bind_accesses (WhereBind expr target idxs) summaries =
        reads = collect_free_vars expr []
        init_muts = init_target_mut target idxs
        eff_res = collect_expr_effects expr "" summaries init_muts False TierTrivial
        extract_reads_and_muts reads eff_res

fn :: init_target_mut String [Int] => [String]
      init_target_mut target (_:_) =  [target]
      init_target_mut _      []    =  []

fn :: extract_reads_and_muts [String] ([String], Bool, RCostTier) => ([String], [String])
      extract_reads_and_muts reads (muts, _, _) = (reads, muts)

fn :: check_vars_conflict [String] String RWhereBind RWhereBind [String] [String] [String] [String] => [RAnalysisError]
      check_vars_conflict [] _ _ _ _ _ _ _ = []
      check_vars_conflict (v:vs) fn_name b1 b2 r1 m1 r2 m2
        | ((str_in_list v r1) OR (str_in_list v m1)) AND ((str_in_list v r2) OR (str_in_list v m2)) AND (NOT (are_disjoint_slices v b1 b2)) = [ErrParallelMutation fn_name v] :: (check_vars_conflict vs fn_name b1 b2 r1 m1 r2 m2)
        | otherwise = check_vars_conflict vs fn_name b1 b2 r1 m1 r2 m2

fn :: check_pair_conflict String RWhereBind RWhereBind [RFnSummary] => [RAnalysisError]
      check_pair_conflict fn_name b1 b2 summaries =
        acc1 = collect_bind_accesses b1 summaries
        acc2 = collect_bind_accesses b2 summaries
        check_pair_accesses fn_name b1 b2 acc1 acc2

fn :: check_pair_accesses String RWhereBind RWhereBind ([String], [String]) ([String], [String]) => [RAnalysisError]
      check_pair_accesses fn_name b1 b2 (r1, m1) (r2, m2) =
        all_muts = union_strs m1 m2
        check_vars_conflict all_muts fn_name b1 b2 r1 m1 r2 m2

fn :: where_bind_at [RWhereBind] Int => RWhereBind
      where_bind_at (b:_)        0   =  b
      where_bind_at (_:bs)       idx =  where_bind_at bs (idx - 1)
      where_bind_at []           _   =  WhereBind EUnit "" []

fn :: check_where_pairs_j String [RWhereBind] Int Int Int [RDagEdge] [RFnSummary] => [RAnalysisError]
      check_where_pairs_j fn_name binds i j n edges summaries
        | j >= n = []
        | are_where_nodes_concurrent i j edges = (check_pair_conflict fn_name (where_bind_at binds i) (where_bind_at binds j) summaries) :: (check_where_pairs_j fn_name binds i (j + 1) n edges summaries)
        | otherwise = check_where_pairs_j fn_name binds i (j + 1) n edges summaries

fn :: check_where_pairs_i String [RWhereBind] Int Int [RDagEdge] [RFnSummary] => [RAnalysisError]
      check_where_pairs_i fn_name binds i n edges summaries
        | i >= n = []
        | otherwise = (check_where_pairs_j fn_name binds i (i + 1) n edges summaries) :: (check_where_pairs_i fn_name binds (i + 1) n edges summaries)

fn :: check_where_block_safety String RExpr [RWhereBind] [String] [RFnSummary] [String] => ([String], [RAnalysisError])
      check_where_block_safety fn_name body binds mut_vars summaries moved =
        n = where_list_len binds
        prod_res = collect_producers binds 0 [] fn_name
        check_where_dag_step fn_name body binds n mut_vars summaries moved prod_res

fn :: check_where_dag_step String RExpr [RWhereBind] Int [String] [RFnSummary] [String] ([RProducerEntry], [RAnalysisError]) => ([String], [RAnalysisError])
      check_where_dag_step _ _ _ _ _ _ moved (_, (err:errs)) = (moved, [err] :: errs)
      check_where_dag_step fn_name body binds n mut_vars summaries moved (prods, []) =
        edge_res = build_where_edges binds 0 prods fn_name
        check_where_edges_step fn_name body binds n mut_vars summaries moved edge_res

fn :: check_where_edges_step String RExpr [RWhereBind] Int [String] [RFnSummary] [String] ([RDagEdge], [RAnalysisError]) => ([String], [RAnalysisError])
      check_where_edges_step _ _ _ _ _ _ moved (_, (err:errs)) = (moved, [err] :: errs)
      check_where_edges_step fn_name body binds n mut_vars summaries moved (edges, [])
        | has_dag_cycle 0 n edges = (moved, [ErrWhereCycle fn_name "cycle"])
        | otherwise = finish_where_safety body fn_name mut_vars summaries (check_where_pairs_i fn_name binds 0 n edges summaries) (check_where_binds_exprs binds fn_name mut_vars summaries moved)

fn :: check_where_binds_exprs [RWhereBind] String [String] [RFnSummary] [String] => ([String], [RAnalysisError])
      check_where_binds_exprs [] _ _ _ moved = (moved, [])
      check_where_binds_exprs ((WhereBind e _ _):wbs) fn_name mut_vars summaries moved =
        r1 = check_expr_safety e fn_name mut_vars summaries moved
        check_where_binds_cont wbs fn_name mut_vars summaries r1

fn :: check_where_binds_cont [RWhereBind] String [String] [RFnSummary] ([String], [RAnalysisError]) => ([String], [RAnalysisError])
      check_where_binds_cont wbs fn_name mut_vars summaries (moved1, errs1) =
        r2 = check_where_binds_exprs wbs fn_name mut_vars summaries moved1
        merge_moved_errs errs1 r2

fn :: finish_where_safety RExpr String [String] [RFnSummary] [RAnalysisError] ([String], [RAnalysisError]) => ([String], [RAnalysisError])
      finish_where_safety body fn_name mut_vars summaries pair_errs (moved1, bind_errs) =
        r_body = check_expr_safety body fn_name mut_vars summaries moved1
        merge_moved_errs (pair_errs :: bind_errs) r_body

fn :: merge_moved_errs [RAnalysisError] ([String], [RAnalysisError]) => ([String], [RAnalysisError])
      merge_moved_errs errs1 (moved2, errs2) = (moved2, errs1 :: errs2)

-- ── Affine Channel Ownership & Safety Verification ──────────

fn :: is_channel_send_call String => Bool
      is_channel_send_call callee =
        callee == "send" OR callee == "send_through" OR callee == "chan_send"

fn :: mark_channel_sent String [RExpr] [String] [String] => [String]
      mark_channel_sent callee ((EVar sent_var):_) mut_vars moved
        | (is_channel_send_call callee) AND (str_in_list sent_var mut_vars) = add_unique_str sent_var moved
      mark_channel_sent _      _       _        moved    =  moved

fn :: check_expr_safety RExpr String [String] [RFnSummary] [String] => ([String], [RAnalysisError])
      check_expr_safety (EVar name) fn_name _ _ moved
        | str_in_list name moved = (moved, [ErrUseAfterSend fn_name name])
        | otherwise = (moved, [])
      check_expr_safety (ECall callee args) fn_name mut_vars summaries moved =
        r_args = check_expr_list_safety args fn_name mut_vars summaries moved
        finish_call_safety callee args mut_vars r_args
      check_expr_safety (EWhere body binds) fn_name mut_vars summaries moved =
        check_where_block_safety fn_name body binds mut_vars summaries moved
      check_expr_safety (EBlock stmts) fn_name mut_vars summaries moved =
        check_stmt_list_safety stmts fn_name mut_vars summaries moved
      check_expr_safety (EGuard guards) fn_name mut_vars summaries moved =
        check_guards_safety guards fn_name mut_vars summaries moved
      check_expr_safety (EBin _ l r) fn_name mut_vars summaries moved =
        r1 = check_expr_safety l fn_name mut_vars summaries moved
        check_expr_safety_tuple r fn_name mut_vars summaries r1
      check_expr_safety (EHadamard _ l _ r _) fn_name mut_vars summaries moved =
        r1 = check_expr_safety l fn_name mut_vars summaries moved
        check_expr_safety_tuple r fn_name mut_vars summaries r1
      check_expr_safety (EEinsum es _) fn_name mut_vars summaries moved =
        check_expr_list_safety es fn_name mut_vars summaries moved
      check_expr_safety (ENot inner) fn_name mut_vars summaries moved =
        check_expr_safety inner fn_name mut_vars summaries moved
      check_expr_safety (EOut inner) fn_name mut_vars summaries moved =
        check_expr_safety inner fn_name mut_vars summaries moved
      check_expr_safety (EWithRegion _ inner) fn_name mut_vars summaries moved =
        check_expr_safety inner fn_name mut_vars summaries moved
      check_expr_safety (EAtomicUpdate _ inner) fn_name mut_vars summaries moved =
        check_expr_safety inner fn_name mut_vars summaries moved
      check_expr_safety (ELoadContext _ inner) fn_name mut_vars summaries moved =
        check_expr_safety inner fn_name mut_vars summaries moved
      check_expr_safety (ELoadShared _ inner) fn_name mut_vars summaries moved =
        check_expr_safety inner fn_name mut_vars summaries moved
      check_expr_safety (EWithCtx _ v b) fn_name mut_vars summaries moved =
        r1 = check_expr_safety v fn_name mut_vars summaries moved
        check_expr_safety_tuple b fn_name mut_vars summaries r1
      check_expr_safety (EStrInterp parts) fn_name mut_vars summaries moved =
        check_expr_list_safety parts fn_name mut_vars summaries moved
      check_expr_safety (EIndex base idxs) fn_name mut_vars summaries moved =
        r1 = check_expr_safety base fn_name mut_vars summaries moved
        check_expr_list_safety_tuple idxs fn_name mut_vars summaries r1
      check_expr_safety _ _ _ _ moved = (moved, [])

fn :: finish_call_safety String [RExpr] [String] ([String], [RAnalysisError]) => ([String], [RAnalysisError])
      finish_call_safety callee args mut_vars (moved1, errs) =
        (mark_channel_sent callee args mut_vars moved1, errs)

fn :: check_expr_safety_tuple RExpr String [String] [RFnSummary] ([String], [RAnalysisError]) => ([String], [RAnalysisError])
      check_expr_safety_tuple e fn_name mut_vars summaries (moved, errs) =
        merge_moved_errs errs (check_expr_safety e fn_name mut_vars summaries moved)

fn :: check_expr_list_safety [RExpr] String [String] [RFnSummary] [String] => ([String], [RAnalysisError])
      check_expr_list_safety [] _ _ _ moved = (moved, [])
      check_expr_list_safety (e:es) fn_name mut_vars summaries moved =
        r1 = check_expr_safety e fn_name mut_vars summaries moved
        check_expr_list_safety_tuple es fn_name mut_vars summaries r1

fn :: check_expr_list_safety_tuple [RExpr] String [String] [RFnSummary] ([String], [RAnalysisError]) => ([String], [RAnalysisError])
      check_expr_list_safety_tuple es fn_name mut_vars summaries (moved, errs) =
        merge_moved_errs errs (check_expr_list_safety es fn_name mut_vars summaries moved)

fn :: is_tensor_expr RExpr       => Bool
      is_tensor_expr (ETensor _) =  True
      is_tensor_expr _           =  False

fn :: check_guards_safety [RGuard] String [String] [RFnSummary] [String] => ([String], [RAnalysisError])
      check_guards_safety [] _ _ _ moved = (moved, [])
      check_guards_safety ((GuardBranch c b):gs) fn_name mut_vars summaries moved =
        r1 = check_expr_safety c fn_name mut_vars summaries moved
        r2 = check_expr_safety_tuple b fn_name mut_vars summaries r1
        check_guards_safety_tuple gs fn_name mut_vars summaries r2

fn :: check_guards_safety_tuple [RGuard] String [String] [RFnSummary] ([String], [RAnalysisError]) => ([String], [RAnalysisError])
      check_guards_safety_tuple gs fn_name mut_vars summaries (moved, errs) =
        merge_moved_errs errs (check_guards_safety gs fn_name mut_vars summaries moved)

fn :: check_stmt_list_safety [RStmt] String [String] [RFnSummary] [String] => ([String], [RAnalysisError])
      check_stmt_list_safety [] _ _ _ moved = (moved, [])
      check_stmt_list_safety ((StmtLet v val_e):ss) fn_name mut_vars summaries moved
        | is_tensor_expr val_e = check_stmt_list_safety_tuple ss fn_name (add_unique_str v mut_vars) summaries (check_expr_safety val_e fn_name (add_unique_str v mut_vars) summaries moved)
        | otherwise = check_stmt_list_safety_tuple ss fn_name mut_vars summaries (check_expr_safety val_e fn_name mut_vars summaries moved)
      check_stmt_list_safety ((StmtMut v val_e):ss) fn_name mut_vars summaries moved =
        check_stmt_list_safety_tuple ss fn_name (add_unique_str v mut_vars) summaries (check_expr_safety val_e fn_name (add_unique_str v mut_vars) summaries moved)
      check_stmt_list_safety ((StmtExpr e):ss) fn_name mut_vars summaries moved =
        r1 = check_expr_safety e fn_name mut_vars summaries moved
        check_stmt_list_safety_tuple ss fn_name mut_vars summaries r1
      check_stmt_list_safety ((StmtAtomic _ e):ss) fn_name mut_vars summaries moved =
        r1 = check_expr_safety e fn_name mut_vars summaries moved
        check_stmt_list_safety_tuple ss fn_name mut_vars summaries r1
      check_stmt_list_safety ((StmtIndexAssign _ idxs e):ss) fn_name mut_vars summaries moved =
        r1 = check_expr_list_safety idxs fn_name mut_vars summaries moved
        r2 = check_expr_safety_tuple e fn_name mut_vars summaries r1
        check_stmt_list_safety_tuple ss fn_name mut_vars summaries r2

fn :: check_stmt_list_safety_tuple [RStmt] String [String] [RFnSummary] ([String], [RAnalysisError]) => ([String], [RAnalysisError])
      check_stmt_list_safety_tuple ss fn_name mut_vars summaries (moved, errs) =
        merge_moved_errs errs (check_stmt_list_safety ss fn_name mut_vars summaries moved)

fn :: collect_mutable_params [String]   [RPattern]        => [String]
      collect_mutable_params []         _                 =  []
      collect_mutable_params _          []                =  []
      collect_mutable_params (pty:ptys) ((PatVar v):pats)
        | str_starts_with pty "Tensor" = add_unique_str v (collect_mutable_params ptys pats)
        | otherwise = collect_mutable_params ptys pats
      collect_mutable_params (_:ptys)   (_:pats)          =  collect_mutable_params ptys pats

fn :: check_cases_safety [RFnCase] String [String] [RFnSummary] => [RAnalysisError]
      check_cases_safety [] _ _ _ = []
      check_cases_safety ((FnCase pats _ body):cs) fn_name param_types summaries =
        mut_params = collect_mutable_params param_types pats
        res = check_expr_safety body fn_name mut_params summaries []
        extract_analysis_errs res (check_cases_safety cs fn_name param_types summaries)

fn :: extract_analysis_errs ([String], [RAnalysisError]) [RAnalysisError] => [RAnalysisError]
      extract_analysis_errs (_, errs) more = errs :: more

fn :: check_all_fns_safety [RFnDef] [RFnSummary] => [RAnalysisError]
      check_all_fns_safety []       _            =  []
      check_all_fns_safety ((FnDef name param_types _ cases):fs) summaries =
        (check_cases_safety cases name param_types summaries) :: (check_all_fns_safety fs summaries)

fn :: analyze_program_errors RProgram => [RAnalysisError]
      analyze_program_errors prog     =
        summaries = infer_all_summaries prog
        check_program_with_summaries prog summaries

fn :: check_program_with_summaries RProgram [RFnSummary] => [RAnalysisError]
      check_program_with_summaries (Program fns _) summaries =
        check_all_fns_safety fns summaries

fn :: format_summaries [RFnSummary] => [String]
      format_summaries []           =  []
      format_summaries ((FnSummary name _ _ _ strat):ss) =
        [name + ":" + (strategy_to_str strat)] :: (format_summaries ss)

fn :: analyze_rprogram RProgram => [String]
      analyze_rprogram prog     =  format_summaries (infer_all_summaries prog)

fn :: analysis_err_count [RAnalysisError] => Int
      analysis_err_count []               =  0
      analysis_err_count (_:xs)           =  1 + (analysis_err_count xs)

fn :: verify_rprogram RProgram => Bool
      verify_rprogram prog     =  (analysis_err_count (analyze_program_errors prog)) == 0
