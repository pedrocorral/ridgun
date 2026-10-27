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
        | otherwise = str in list target xs

fn :: add unique str String [String] => [String]
      add unique str s      xs
        | str in list s xs = xs
        | otherwise = xs :: [s]

fn :: union strs [String] [String] => [String]
      union strs []       ys       =  ys
      union strs (x:xs)   ys       =  union strs xs (add unique str x ys)

fn :: int in list Int    [Int]  => Bool
      int in list _      []     =  False
      int in list target (x:xs)
        | x == target = True
        | otherwise = int in list target xs

fn :: int list len [Int]  => Int
      int list len []     =  0
      int list len (_:xs) =  1 + (int list len xs)

fn :: where list len [RWhereBind] => Int
      where list len []           =  0
      where list len (_:xs)       =  1 + (where list len xs)

-- ── Cost Tier & 4-Tier Strategy Selection ───────────────────

fn :: cost rank RCostTier    => Int
      cost rank TierTrivial  =  0
      cost rank TierHeavyCPU =  1
      cost rank TierDynamicRecursive = 2

fn :: max cost tier RCostTier RCostTier => RCostTier
      max cost tier a         b
        | (cost rank a) >= (cost rank b) = a
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
        | otherwise = lookup fn summary rest name

fn :: is yielding builtin String => Bool
      is yielding builtin callee =
        callee == "recv" OR callee == "receive_from" OR callee == "try_receive_from" OR callee == "receive_from_timeout" OR callee == "send_to" OR callee == "ask_to" OR callee == "send_through" OR callee == "agent" OR callee == "stop"

fn :: param effect at [RParamEffect] Int => RParamEffect
      param effect at []             _   =  EffReadOnly
      param effect at (e:_)          0   =  e
      param effect at (_:es)         idx =  param effect at es (idx - 1)

fn :: collect mutated call args [RExpr] [RParamEffect] Int [String] => [String]
      collect mutated call args [] _ _ acc = acc
      collect mutated call args ((EVar v):args) effs idx acc
        | (param effect at effs idx) == EffMutates = collect mutated call args args effs (idx + 1) (add unique str v acc)
        | otherwise = collect mutated call args args effs (idx + 1) acc
      collect mutated call args (_:args) effs idx acc =
        collect mutated call args args effs (idx + 1) acc

-- ── Expression Effect & Self-Call Collection ────────────────

fn :: count expr self calls String RExpr => Int
      count expr self calls fn_name (ENot inner) = count expr self calls fn_name inner
      count expr self calls fn_name (EOut inner) = count expr self calls fn_name inner
      count expr self calls fn_name (EBin _ l r) = (count expr self calls fn_name l) + (count expr self calls fn_name r)
      count expr self calls fn_name (ECall callee args)
        | callee == fn_name = 1 + (count expr list calls fn_name args)
        | otherwise = count expr list calls fn_name args
      count expr self calls fn_name (EEcho args) = count expr list calls fn_name args
      count expr self calls fn_name (EStrInterp args) = count expr list calls fn_name args
      count expr self calls fn_name (EList elems) = count expr list calls fn_name elems
      count expr self calls fn_name (ETuple elems) = count expr list calls fn_name elems
      count expr self calls fn_name (ETensor elems) = count expr list calls fn_name elems
      count expr self calls fn_name (EEinsum es _) = count expr list calls fn_name es
      count expr self calls fn_name (EHadamard _ l _ r _) = (count expr self calls fn_name l) + (count expr self calls fn_name r)
      count expr self calls fn_name (EIndex b idxs) = (count expr self calls fn_name b) + (count expr list calls fn_name idxs)
      count expr self calls fn_name (EIndexAssign _ idxs v) = (count expr list calls fn_name idxs) + (count expr self calls fn_name v)
      count expr self calls fn_name (ESeqSelect b _) = count expr self calls fn_name b
      count expr self calls fn_name (EBlock stmts) = count stmt list calls fn_name stmts
      count expr self calls fn_name (EGuard guards) = count guard calls fn_name guards
      count expr self calls fn_name (EWhere body binds) = (count expr self calls fn_name body) + (count where calls fn_name binds)
      count expr self calls fn_name (EParPipe branches) = count expr list calls fn_name branches
      count expr self calls fn_name (EWithCtx _ v b) = (count expr self calls fn_name v) + (count expr self calls fn_name b)
      count expr self calls fn_name (EWithRegion _ b) = count expr self calls fn_name b
      count expr self calls _ _ = 0

fn :: count expr list calls String [RExpr] => Int
      count expr list calls _ [] = 0
      count expr list calls fn_name (e:es) = (count expr self calls fn_name e) + (count expr list calls fn_name es)

fn :: count stmt list calls String [RStmt] => Int
      count stmt list calls _ [] = 0
      count stmt list calls fn_name ((StmtLet _ e):ss) = (count expr self calls fn_name e) + (count stmt list calls fn_name ss)
      count stmt list calls fn_name ((StmtMut _ e):ss) = (count expr self calls fn_name e) + (count stmt list calls fn_name ss)
      count stmt list calls fn_name ((StmtExpr e):ss) = (count expr self calls fn_name e) + (count stmt list calls fn_name ss)
      count stmt list calls fn_name ((StmtIndexAssign _ idxs e):ss) = (count expr list calls fn_name idxs) + (count expr self calls fn_name e) + (count stmt list calls fn_name ss)

fn :: count where calls String  [RWhereBind] => Int
      count where calls _       []           =  0
      count where calls fn_name ((WhereBind e _ _):wbs) = (count expr self calls fn_name e) + (count where calls fn_name wbs)

fn :: count guard calls String  [RGuard] => Int
      count guard calls _       []       =  0
      count guard calls fn_name ((GuardBranch c b):gs) = (count expr self calls fn_name c) + (count expr self calls fn_name b) + (count guard calls fn_name gs)

fn :: count case calls String  [RFnCase] => Int
      count case calls _       []        =  0
      count case calls fn_name ((FnCase _ gs b):cs) =
        c_here = (count guard calls fn_name gs) + (count expr self calls fn_name b)
        c_rest = count case calls fn_name cs
        max int c_here c_rest

fn :: max int Int Int => Int
      max int a   b
        | a >= b = a
        | otherwise = b

fn :: collect expr effects RExpr String [RFnSummary] [String] Bool RCostTier => [String] Bool RCostTier
      collect expr effects (ECall callee args) cur_fn summaries muts yld cost =
        after_call = apply callee summary callee args cur_fn (lookup fn summary summaries callee) muts yld cost
        collect expr list effects tuple args cur_fn summaries after_call
      collect expr effects (EIndexAssign target idxs val) cur_fn summaries muts yld cost =
        muts1 = add unique str target muts
        r_idxs = collect expr list effects idxs cur_fn summaries muts1 yld cost
        collect expr effects tuple val cur_fn summaries r_idxs
      collect expr effects (EWhere body binds) cur_fn summaries muts yld cost =
        r_body = collect expr effects body cur_fn summaries muts yld cost
        collect where effects tuple binds cur_fn summaries r_body
      collect expr effects (EParPipe branches) cur_fn summaries muts yld cost =
        collect expr list effects branches cur_fn summaries muts yld cost
      collect expr effects (EBin _ l r) cur_fn summaries muts yld cost =
        r1 = collect expr effects l cur_fn summaries muts yld cost
        collect expr effects tuple r cur_fn summaries r1
      collect expr effects (EHadamard _ l _ r _) cur_fn summaries muts yld cost =
        r1 = collect expr effects l cur_fn summaries muts yld (max cost tier cost TierHeavyCPU)
        collect expr effects tuple r cur_fn summaries r1
      collect expr effects (EEinsum es _) cur_fn summaries muts yld cost =
        collect expr list effects es cur_fn summaries muts yld (max cost tier cost TierHeavyCPU)
      collect expr effects (ETensor elems) cur_fn summaries muts yld cost =
        collect expr list effects elems cur_fn summaries muts yld (max cost tier cost TierHeavyCPU)
      collect expr effects (ENot inner) cur_fn summaries muts yld cost =
        collect expr effects inner cur_fn summaries muts yld cost
      collect expr effects (EOut inner) cur_fn summaries muts yld cost =
        collect expr effects inner cur_fn summaries muts yld cost
      collect expr effects (EWithRegion _ inner) cur_fn summaries muts yld cost =
        collect expr effects inner cur_fn summaries muts yld cost
      collect expr effects (EWithCtx _ v b) cur_fn summaries muts yld cost =
        r1 = collect expr effects v cur_fn summaries muts yld cost
        collect expr effects tuple b cur_fn summaries r1
      collect expr effects (EBlock stmts) cur_fn summaries muts yld cost =
        collect stmt list effects stmts cur_fn summaries muts yld cost
      collect expr effects (EGuard guards) cur_fn summaries muts yld cost =
        collect guards effects guards cur_fn summaries muts yld cost
      collect expr effects (EList elems) cur_fn summaries muts yld cost =
        collect expr list effects elems cur_fn summaries muts yld cost
      collect expr effects (ETuple elems) cur_fn summaries muts yld cost =
        collect expr list effects elems cur_fn summaries muts yld cost
      collect expr effects (EEcho elems) cur_fn summaries muts yld cost =
        collect expr list effects elems cur_fn summaries muts yld cost
      collect expr effects (EStrInterp elems) cur_fn summaries muts yld cost =
        collect expr list effects elems cur_fn summaries muts yld cost
      collect expr effects (EIndex b idxs) cur_fn summaries muts yld cost =
        r1 = collect expr effects b cur_fn summaries muts yld cost
        collect expr list effects tuple idxs cur_fn summaries r1
      collect expr effects _ _ _ muts yld cost = (muts, yld, cost)

fn :: collect expr effects tuple RExpr String [RFnSummary] ([String], Bool, RCostTier) => [String] Bool RCostTier
      collect expr effects tuple e cur_fn summaries (muts, yld, cost) =
        collect expr effects e cur_fn summaries muts yld cost

fn :: collect expr list effects [RExpr] String [RFnSummary] [String] Bool RCostTier => [String] Bool RCostTier
      collect expr list effects [] _ _ muts yld cost = (muts, yld, cost)
      collect expr list effects (e:es) cur_fn summaries muts yld cost =
        r1 = collect expr effects e cur_fn summaries muts yld cost
        collect expr list effects tuple es cur_fn summaries r1

fn :: collect expr list effects tuple [RExpr] String [RFnSummary] ([String], Bool, RCostTier) => [String] Bool RCostTier
      collect expr list effects tuple es cur_fn summaries (muts, yld, cost) =
        collect expr list effects es cur_fn summaries muts yld cost

fn :: collect stmt list effects [RStmt] String [RFnSummary] [String] Bool RCostTier => [String] Bool RCostTier
      collect stmt list effects [] _ _ muts yld cost = (muts, yld, cost)
      collect stmt list effects ((StmtLet _ e):ss) cur_fn summaries muts yld cost =
        r1 = collect expr effects e cur_fn summaries muts yld cost
        collect stmt list effects tuple ss cur_fn summaries r1
      collect stmt list effects ((StmtMut _ e):ss) cur_fn summaries muts yld cost =
        r1 = collect expr effects e cur_fn summaries muts yld cost
        collect stmt list effects tuple ss cur_fn summaries r1
      collect stmt list effects ((StmtExpr e):ss) cur_fn summaries muts yld cost =
        r1 = collect expr effects e cur_fn summaries muts yld cost
        collect stmt list effects tuple ss cur_fn summaries r1
      collect stmt list effects ((StmtIndexAssign target idxs e):ss) cur_fn summaries muts yld cost =
        muts1 = add unique str target muts
        r_idxs = collect expr list effects idxs cur_fn summaries muts1 yld cost
        r_val = collect expr effects tuple e cur_fn summaries r_idxs
        collect stmt list effects tuple ss cur_fn summaries r_val

fn :: collect stmt list effects tuple [RStmt] String [RFnSummary] ([String], Bool, RCostTier) => [String] Bool RCostTier
      collect stmt list effects tuple ss cur_fn summaries (muts, yld, cost) =
        collect stmt list effects ss cur_fn summaries muts yld cost

fn :: collect where effects [RWhereBind] String [RFnSummary] [String] Bool RCostTier => [String] Bool RCostTier
      collect where effects [] _ _ muts yld cost = (muts, yld, cost)
      collect where effects ((WhereBind e target idxs):wbs) cur_fn summaries muts yld cost
        | (int list len idxs) > 0 = collect where effects tuple wbs cur_fn summaries (collect expr effects e cur_fn summaries (add unique str target muts) yld cost)
        | otherwise = collect where effects tuple wbs cur_fn summaries (collect expr effects e cur_fn summaries muts yld cost)

fn :: collect where effects tuple [RWhereBind] String [RFnSummary] ([String], Bool, RCostTier) => [String] Bool RCostTier
      collect where effects tuple wbs cur_fn summaries (muts, yld, cost) =
        collect where effects wbs cur_fn summaries muts yld cost

fn :: apply callee summary String [RExpr] String (Bool, RFnSummary) [String] Bool RCostTier => [String] Bool RCostTier
      apply callee summary callee args cur_fn (found, (FnSummary _ effs s_yld s_cost _)) muts yld cost =
        yld1 = yld OR (is yielding builtin callee) OR (found AND s_yld)
        cost1 = compute call cost callee cur_fn found s_cost cost
        muts1 = collect mutated call args args effs 0 muts
        (muts1, yld1, cost1)

fn :: compute call cost String String Bool RCostTier RCostTier => RCostTier
      compute call cost callee cur_fn _ _ cost
        | callee == cur_fn = max cost tier cost TierDynamicRecursive
      compute call cost _ _ True s_cost cost = max cost tier cost s_cost
      compute call cost _ _ False _ cost = cost

-- ── Classify Arbitrary Expression Strategy ──────────────────

fn :: classify expr strategy RExpr String [RFnSummary] => RExecStrategy
      classify expr strategy expr cur_fn summaries =
        finish expr strategy (collect expr effects expr cur_fn summaries [] False TierTrivial)

fn :: finish expr strategy ([String], Bool, RCostTier) => RExecStrategy
      finish expr strategy (_, yld, cost)              =  select exec strategy yld cost

-- ── Per-Function Static Summary Inference ───────────────────

fn :: init readonly effects [String] => [RParamEffect]
      init readonly effects []       =  []
      init readonly effects (_:ps)   =  [EffReadOnly] :: (init readonly effects ps)

fn :: update param effects [RPattern] [RParamEffect] [String] => [RParamEffect]
      update param effects [] effs _ = effs
      update param effects _ [] _ = []
      update param effects ((PatVar v):ps) (e:es) muts
        | str in list v muts = [EffMutates] :: (update param effects ps es muts)
        | otherwise = [e] :: (update param effects ps es muts)
      update param effects (_:ps) (e:es) muts =
        [e] :: (update param effects ps es muts)

fn :: collect guards effects [RGuard] String [RFnSummary] [String] Bool RCostTier => [String] Bool RCostTier
      collect guards effects [] _ _ muts yld cost = (muts, yld, cost)
      collect guards effects ((GuardBranch c b):gs) fn_name summaries muts yld cost =
        r1 = collect expr effects c fn_name summaries muts yld cost
        r2 = collect expr effects tuple b fn_name summaries r1
        collect guards effects tuple gs fn_name summaries r2

fn :: collect guards effects tuple [RGuard] String [RFnSummary] ([String], Bool, RCostTier) => [String] Bool RCostTier
      collect guards effects tuple gs fn_name summaries (muts, yld, cost) =
        collect guards effects gs fn_name summaries muts yld cost

fn :: collect cases summary [RFnCase] String [RFnSummary] [RParamEffect] Bool RCostTier => [RParamEffect] Bool RCostTier
      collect cases summary [] _ _ effs yld cost = (effs, yld, cost)
      collect cases summary ((FnCase pats guards body):cs) fn_name summaries effs yld cost =
        r_body = collect expr effects body fn_name summaries [] yld cost
        r_all = collect guards effects tuple guards fn_name summaries r_body
        collect cases step pats cs fn_name summaries effs r_all

fn :: collect cases step [RPattern] [RFnCase] String [RFnSummary] [RParamEffect] ([String], Bool, RCostTier) => [RParamEffect] Bool RCostTier
      collect cases step pats cs fn_name summaries effs (case_muts, yld1, cost1) =
        effs1 = update param effects pats effs case_muts
        collect cases summary cs fn_name summaries effs1 yld1 cost1

fn :: adjust recursive cost Int        RCostTier => RCostTier
      adjust recursive cost self_calls cost
        | self_calls == 1 = max cost tier cost TierHeavyCPU
        | self_calls > 1 = TierDynamicRecursive
        | otherwise = cost

fn :: compute one fn summary RFnDef [RFnSummary] => RFnSummary
      compute one fn summary (FnDef name params _ cases) summaries =
        init_effs = init readonly effects params
        self_calls = count case calls name cases
        res = collect cases summary cases name summaries init_effs False TierTrivial
        finish fn summary name self_calls res

fn :: finish fn summary String Int ([RParamEffect], Bool, RCostTier) => RFnSummary
      finish fn summary name self_calls (effs, yld, raw_cost) =
        final_cost = adjust recursive cost self_calls raw_cost
        strat = select exec strategy yld final_cost
        FnSummary name effs yld final_cost strat

fn :: has mut effect [RParamEffect]      => Bool
      has mut effect []                  =  False
      has mut effect (EffMutates:_)      =  True
      has mut effect (_:es)              =  has mut effect es

fn :: is nontrivial summary RFnSummary                             => Bool
      is nontrivial summary (FnSummary _ effs False TierTrivial _) =  has mut effect effs
      is nontrivial summary _                                      =  True

fn :: add nontrivial summary RFnSummary [RFnSummary] => [RFnSummary]
      add nontrivial summary s          summaries
        | is nontrivial summary s = summaries :: [s]
        | otherwise = summaries

fn :: filter nontrivial summaries acc [RFnSummary] [RFnSummary] => [RFnSummary]
      filter nontrivial summaries acc []           acc          =  acc
      filter nontrivial summaries acc (s:ss)       acc
        | is nontrivial summary s = filter nontrivial summaries acc ss (acc :: [s])
        | otherwise = filter nontrivial summaries acc ss acc

fn :: filter nontrivial summaries [RFnSummary] => [RFnSummary]
      filter nontrivial summaries ss           =  filter nontrivial summaries acc ss []

fn :: compute summaries pass acc [RFnDef] [RFnSummary] [RFnSummary] => [RFnSummary]
      compute summaries pass acc []       _            acc          =  acc
      compute summaries pass acc (f:fs)   cur_summaries acc         =
        s = compute one fn summary f cur_summaries
        compute summaries pass acc fs (add nontrivial summary s cur_summaries) (acc :: [s])

fn :: compute summaries pass [RFnDef] [RFnSummary]  => [RFnSummary]
      compute summaries pass fns      cur_summaries =
        compute summaries pass acc fns cur_summaries []

fn :: infer all summaries RProgram        => [RFnSummary]
      infer all summaries (Program fns _) =
        pass1 = filter nontrivial summaries (compute summaries pass fns [])
        compute summaries pass fns pass1

-- ── Free Variable Extraction & Where-Block DAG / Cycle Check ──

fn :: collect free vars RExpr              [String] => [String]
      collect free vars (EVar v)           acc      =  add unique str v acc
      collect free vars (ENot inner)       acc      =  collect free vars inner acc
      collect free vars (EOut inner)       acc      =  collect free vars inner acc
      collect free vars (EBin _ l r)       acc      =  collect free vars r (collect free vars l acc)
      collect free vars (EHadamard _ l _ r _) acc   =  collect free vars r (collect free vars l acc)
      collect free vars (EEinsum es _)     acc      =  collect free vars list es acc
      collect free vars (ECall _ args)     acc      =  collect free vars list args acc
      collect free vars (EEcho args)       acc      =  collect free vars list args acc
      collect free vars (EStrInterp args)  acc      =  collect free vars list args acc
      collect free vars (EList args)       acc      =  collect free vars list args acc
      collect free vars (ETuple args)      acc      =  collect free vars list args acc
      collect free vars (ETensor args)     acc      =  collect free vars list args acc
      collect free vars (EIndex b idxs)    acc      =  collect free vars list idxs (collect free vars b acc)
      collect free vars (EIndexAssign t idxs v) acc =  collect free vars v (collect free vars list idxs (add unique str t acc))
      collect free vars (ESeqSelect b _)   acc      =  collect free vars b acc
      collect free vars (EWithCtx _ v b)   acc      =  collect free vars b (collect free vars v acc)
      collect free vars (EWithRegion _ b)  acc      =  collect free vars b acc
      collect free vars _                  acc      =  acc

fn :: collect free vars list [RExpr] [String] => [String]
      collect free vars list [] acc = acc
      collect free vars list (e:es) acc = collect free vars list es (collect free vars e acc)

type RProducerEntry = ProducerEntry String Int

fn :: lookup producer [RProducerEntry] String => Int
      lookup producer []               _      =  -1
      lookup producer ((ProducerEntry k idx):rest) target
        | k == target = idx
        | otherwise = lookup producer rest target

fn :: collect producers [RWhereBind] Int [RProducerEntry] String => [RProducerEntry] [RAnalysisError]
      collect producers [] _ acc _ = (acc, [])
      collect producers ((WhereBind _ target idxs):wbs) idx acc fn_name
        | (int list len idxs) > 0 OR target == "" = collect producers wbs (idx + 1) acc fn_name
        | (lookup producer acc target) >= 0 = add prod err (ErrWhereCycle fn_name target) (collect producers wbs (idx + 1) acc fn_name)
        | otherwise = collect producers wbs (idx + 1) (acc :: [ProducerEntry target idx]) fn_name

fn :: add prod err RAnalysisError ([RProducerEntry], [RAnalysisError]) => [RProducerEntry] [RAnalysisError]
      add prod err err (prods, errs) = (prods, [err] :: errs)

type RDagEdge = DagEdge Int Int

fn :: build where edges [RWhereBind] Int [RProducerEntry] String => [RDagEdge] [RAnalysisError]
      build where edges [] _ _ _ = ([], [])
      build where edges ((WhereBind expr _ _):wbs) j prods fn_name =
        fvars = collect free vars expr []
        e_here = edges for vars fvars j prods fn_name
        e_rest = build where edges wbs (j + 1) prods fn_name
        merge edges and errs e_here e_rest

fn :: edges for vars [String] Int [RProducerEntry] String => [RDagEdge] [RAnalysisError]
      edges for vars [] _ _ _ = ([], [])
      edges for vars (v:vs) j prods fn_name =
        i = lookup producer prods v
        edges for one var v vs j i prods fn_name

fn :: edges for one var String [String] Int Int [RProducerEntry] String => [RDagEdge] [RAnalysisError]
      edges for one var v vs j i prods fn_name
        | i < 0 = edges for vars vs j prods fn_name
        | i == j = merge edges and errs ([], [ErrWhereCycle fn_name v]) (edges for vars vs j prods fn_name)
        | otherwise = merge edges and errs ([DagEdge i j], []) (edges for vars vs j prods fn_name)

fn :: merge edges and errs ([RDagEdge], [RAnalysisError]) ([RDagEdge], [RAnalysisError]) => [RDagEdge] [RAnalysisError]
      merge edges and errs (e1, err1) (e2, err2) = (e1 :: e2, err1 :: err2)

fn :: dag neighbors Int [RDagEdge] => [Int]
      dag neighbors _   []         =  []
      dag neighbors u   ((DagEdge src dst):es)
        | src == u = [dst] :: (dag neighbors u es)
        | otherwise = dag neighbors u es

fn :: dag reachable dfs [Int] Int [RDagEdge] [Int] => Bool
      dag reachable dfs [] _ _ _ = False
      dag reachable dfs (curr:stack) dst edges visited
        | curr == dst = True
        | int in list curr visited = dag reachable dfs stack dst edges visited
        | otherwise = dag reachable dfs ((dag neighbors curr edges) :: stack) dst edges (visited :: [curr])

fn :: has dag cycle Int Int [RDagEdge] => Bool
      has dag cycle idx n edges
        | idx >= n = False
        | dag reachable dfs (dag neighbors idx edges) idx edges [] = True
        | otherwise = has dag cycle (idx + 1) n edges

fn :: are where nodes concurrent Int Int [RDagEdge] => Bool
      are where nodes concurrent a b edges
        | a == b = False
        | dag reachable dfs [a] b edges [] = False
        | dag reachable dfs [b] a edges [] = False
        | otherwise = True

-- ── Disjoint Slice & Parallel Mutation Conflict Check ────────

fn :: are disjoint slices String RWhereBind RWhereBind => Bool
      are disjoint slices var (WhereBind _ t1 (i1:_)) (WhereBind _ t2 (i2:_))
        | t1 == var AND t2 == var AND i1 != i2 = True
      are disjoint slices _ _ _ = False

fn :: collect bind accesses RWhereBind [RFnSummary] => [String] [String]
      collect bind accesses (WhereBind expr target idxs) summaries =
        reads = collect free vars expr []
        init_muts = init target mut target idxs
        eff_res = collect expr effects expr "" summaries init_muts False TierTrivial
        extract reads and muts reads eff_res

fn :: init target mut String [Int] => [String]
      init target mut target (_:_) =  [target]
      init target mut _      []    =  []

fn :: extract reads and muts [String] ([String], Bool, RCostTier) => [String] [String]
      extract reads and muts reads (muts, _, _) = (reads, muts)

fn :: check vars conflict [String] String RWhereBind RWhereBind [String] [String] [String] [String] => [RAnalysisError]
      check vars conflict [] _ _ _ _ _ _ _ = []
      check vars conflict (v:vs) fn_name b1 b2 r1 m1 r2 m2
        | ((str in list v r1) OR (str in list v m1)) AND ((str in list v r2) OR (str in list v m2)) AND (NOT (are disjoint slices v b1 b2)) = [ErrParallelMutation fn_name v] :: (check vars conflict vs fn_name b1 b2 r1 m1 r2 m2)
        | otherwise = check vars conflict vs fn_name b1 b2 r1 m1 r2 m2

fn :: check pair conflict String RWhereBind RWhereBind [RFnSummary] => [RAnalysisError]
      check pair conflict fn_name b1 b2 summaries =
        acc1 = collect bind accesses b1 summaries
        acc2 = collect bind accesses b2 summaries
        check pair accesses fn_name b1 b2 acc1 acc2

fn :: check pair accesses String RWhereBind RWhereBind ([String], [String]) ([String], [String]) => [RAnalysisError]
      check pair accesses fn_name b1 b2 (r1, m1) (r2, m2) =
        all_muts = union strs m1 m2
        check vars conflict all_muts fn_name b1 b2 r1 m1 r2 m2

fn :: where bind at [RWhereBind] Int => RWhereBind
      where bind at (b:_)        0   =  b
      where bind at (_:bs)       idx =  where bind at bs (idx - 1)
      where bind at []           _   =  WhereBind EUnit "" []

fn :: check where pairs j String [RWhereBind] Int Int Int [RDagEdge] [RFnSummary] => [RAnalysisError]
      check where pairs j fn_name binds i j n edges summaries
        | j >= n = []
        | are where nodes concurrent i j edges = (check pair conflict fn_name (where bind at binds i) (where bind at binds j) summaries) :: (check where pairs j fn_name binds i (j + 1) n edges summaries)
        | otherwise = check where pairs j fn_name binds i (j + 1) n edges summaries

fn :: check where pairs i String [RWhereBind] Int Int [RDagEdge] [RFnSummary] => [RAnalysisError]
      check where pairs i fn_name binds i n edges summaries
        | i >= n = []
        | otherwise = (check where pairs j fn_name binds i (i + 1) n edges summaries) :: (check where pairs i fn_name binds (i + 1) n edges summaries)

fn :: check where block safety String RExpr [RWhereBind] [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check where block safety fn_name body binds mut_vars summaries moved =
        n = where list len binds
        prod_res = collect producers binds 0 [] fn_name
        check where dag step fn_name body binds n mut_vars summaries moved prod_res

fn :: check where dag step String RExpr [RWhereBind] Int [String] [RFnSummary] [String] ([RProducerEntry], [RAnalysisError]) => [String] [RAnalysisError]
      check where dag step _ _ _ _ _ _ moved (_, (err:errs)) = (moved, [err] :: errs)
      check where dag step fn_name body binds n mut_vars summaries moved (prods, []) =
        edge_res = build where edges binds 0 prods fn_name
        check where edges step fn_name body binds n mut_vars summaries moved edge_res

fn :: check where edges step String RExpr [RWhereBind] Int [String] [RFnSummary] [String] ([RDagEdge], [RAnalysisError]) => [String] [RAnalysisError]
      check where edges step _ _ _ _ _ _ moved (_, (err:errs)) = (moved, [err] :: errs)
      check where edges step fn_name body binds n mut_vars summaries moved (edges, [])
        | has dag cycle 0 n edges = (moved, [ErrWhereCycle fn_name "cycle"])
        | otherwise = finish where safety body fn_name mut_vars summaries (check where pairs i fn_name binds 0 n edges summaries) (check where binds exprs binds fn_name mut_vars summaries moved)

fn :: check where binds exprs [RWhereBind] String [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check where binds exprs [] _ _ _ moved = (moved, [])
      check where binds exprs ((WhereBind e _ _):wbs) fn_name mut_vars summaries moved =
        r1 = check expr safety e fn_name mut_vars summaries moved
        check where binds cont wbs fn_name mut_vars summaries r1

fn :: check where binds cont [RWhereBind] String [String] [RFnSummary] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      check where binds cont wbs fn_name mut_vars summaries (moved1, errs1) =
        r2 = check where binds exprs wbs fn_name mut_vars summaries moved1
        merge moved errs errs1 r2

fn :: finish where safety RExpr String [String] [RFnSummary] [RAnalysisError] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      finish where safety body fn_name mut_vars summaries pair_errs (moved1, bind_errs) =
        r_body = check expr safety body fn_name mut_vars summaries moved1
        merge moved errs (pair_errs :: bind_errs) r_body

fn :: merge moved errs [RAnalysisError] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      merge moved errs errs1 (moved2, errs2) = (moved2, errs1 :: errs2)

-- ── Affine Channel Ownership & Safety Verification ──────────

fn :: is channel send call String => Bool
      is channel send call callee =
        callee == "send" OR callee == "send_to" OR callee == "send_through" OR callee == "chan_send"

fn :: mark sent expr vars RExpr [String] => [String]
      mark sent expr vars (EVar sent_var) moved = add unique str sent_var moved
      mark sent expr vars (ETuple es) moved = mark sent expr list vars es moved
      mark sent expr vars _ moved = moved

fn :: mark sent expr list vars [RExpr] [String] => [String]
      mark sent expr list vars [] moved = moved
      mark sent expr list vars (e:es) moved =
        mark sent expr list vars es (mark sent expr vars e moved)

fn :: mark channel sent String [RExpr] [String] [String] => [String]
      mark channel sent "chan_send" (_:msg_e:_) _ moved =
        mark sent expr vars msg_e moved
      mark channel sent callee (msg_e:_) _ moved
        | is channel send call callee = mark sent expr vars msg_e moved
      mark channel sent _ _ _ moved = moved

fn :: check expr safety RExpr String [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check expr safety (EVar name) fn_name _ _ moved
        | str in list name moved = (moved, [ErrUseAfterSend fn_name name])
        | otherwise = (moved, [])
      check expr safety (ECall callee args) fn_name mut_vars summaries moved =
        r_args = check expr list safety args fn_name mut_vars summaries moved
        finish call safety callee args mut_vars r_args
      check expr safety (EEcho args) fn_name mut_vars summaries moved =
        check expr list safety args fn_name mut_vars summaries moved
      check expr safety (EList elems) fn_name mut_vars summaries moved =
        check expr list safety elems fn_name mut_vars summaries moved
      check expr safety (ETuple elems) fn_name mut_vars summaries moved =
        check expr list safety elems fn_name mut_vars summaries moved
      check expr safety (ETensor elems) fn_name mut_vars summaries moved =
        check expr list safety elems fn_name mut_vars summaries moved
      check expr safety (ESeqSelect base _) fn_name mut_vars summaries moved =
        check expr safety base fn_name mut_vars summaries moved
      check expr safety (EParPipe branches) fn_name mut_vars summaries moved =
        check expr list safety branches fn_name mut_vars summaries moved
      check expr safety (EIndexAssign t idxs val_e) fn_name mut_vars summaries moved =
        r0 = check expr safety (EVar t) fn_name mut_vars summaries moved
        r1 = check expr list safety tuple idxs fn_name mut_vars summaries r0
        check expr safety tuple val_e fn_name mut_vars summaries r1
      check expr safety (EWhere body binds) fn_name mut_vars summaries moved =
        check where block safety fn_name body binds mut_vars summaries moved
      check expr safety (EBlock stmts) fn_name mut_vars summaries moved =
        check stmt list safety stmts fn_name mut_vars summaries moved
      check expr safety (EGuard guards) fn_name mut_vars summaries moved =
        check guards safety guards fn_name mut_vars summaries moved
      check expr safety (EBin _ l r) fn_name mut_vars summaries moved =
        r1 = check expr safety l fn_name mut_vars summaries moved
        check expr safety tuple r fn_name mut_vars summaries r1
      check expr safety (EHadamard _ l _ r _) fn_name mut_vars summaries moved =
        r1 = check expr safety l fn_name mut_vars summaries moved
        check expr safety tuple r fn_name mut_vars summaries r1
      check expr safety (EEinsum es _) fn_name mut_vars summaries moved =
        check expr list safety es fn_name mut_vars summaries moved
      check expr safety (ENot inner) fn_name mut_vars summaries moved =
        check expr safety inner fn_name mut_vars summaries moved
      check expr safety (EOut inner) fn_name mut_vars summaries moved =
        check expr safety inner fn_name mut_vars summaries moved
      check expr safety (EWithRegion _ inner) fn_name mut_vars summaries moved =
        check expr safety inner fn_name mut_vars summaries moved
      check expr safety (EWithCtx _ v b) fn_name mut_vars summaries moved =
        r1 = check expr safety v fn_name mut_vars summaries moved
        check expr safety tuple b fn_name mut_vars summaries r1
      check expr safety (EStrInterp parts) fn_name mut_vars summaries moved =
        check expr list safety parts fn_name mut_vars summaries moved
      check expr safety (EIndex base idxs) fn_name mut_vars summaries moved =
        r1 = check expr safety base fn_name mut_vars summaries moved
        check expr list safety tuple idxs fn_name mut_vars summaries r1
      check expr safety _ _ _ _ moved = (moved, [])

fn :: finish call safety String [RExpr] [String] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      finish call safety callee args mut_vars (moved1, errs) =
        (mark channel sent callee args mut_vars moved1, errs)

fn :: check expr safety tuple RExpr String [String] [RFnSummary] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      check expr safety tuple e fn_name mut_vars summaries (moved, errs) =
        merge moved errs errs (check expr safety e fn_name mut_vars summaries moved)

fn :: check expr list safety [RExpr] String [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check expr list safety [] _ _ _ moved = (moved, [])
      check expr list safety (e:es) fn_name mut_vars summaries moved =
        r1 = check expr safety e fn_name mut_vars summaries moved
        check expr list safety tuple es fn_name mut_vars summaries r1

fn :: check expr list safety tuple [RExpr] String [String] [RFnSummary] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      check expr list safety tuple es fn_name mut_vars summaries (moved, errs) =
        merge moved errs errs (check expr list safety es fn_name mut_vars summaries moved)

fn :: is tensor expr RExpr       => Bool
      is tensor expr (ETensor _) =  True
      is tensor expr _           =  False

fn :: check guards safety [RGuard] String [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check guards safety [] _ _ _ moved = (moved, [])
      check guards safety ((GuardBranch c b):gs) fn_name mut_vars summaries moved =
        r1 = check expr safety c fn_name mut_vars summaries moved
        r2 = check expr safety tuple b fn_name mut_vars summaries r1
        check guards safety branch gs fn_name mut_vars summaries moved r2

fn :: check guards safety branch [RGuard] String [String] [RFnSummary] [String] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      check guards safety branch gs fn_name mut_vars summaries orig_moved (_, errs1) =
        merge moved errs errs1 (check guards safety gs fn_name mut_vars summaries orig_moved)

fn :: check stmt list safety [RStmt] String [String] [RFnSummary] [String] => [String] [RAnalysisError]
      check stmt list safety [] _ _ _ moved = (moved, [])
      check stmt list safety ((StmtLet v val_e):ss) fn_name mut_vars summaries moved
        | is tensor expr val_e = check stmt list safety tuple ss fn_name (add unique str v mut_vars) summaries (check expr safety val_e fn_name (add unique str v mut_vars) summaries moved)
        | otherwise = check stmt list safety tuple ss fn_name mut_vars summaries (check expr safety val_e fn_name mut_vars summaries moved)
      check stmt list safety ((StmtMut v val_e):ss) fn_name mut_vars summaries moved =
        check stmt list safety tuple ss fn_name (add unique str v mut_vars) summaries (check expr safety val_e fn_name (add unique str v mut_vars) summaries moved)
      check stmt list safety ((StmtExpr e):ss) fn_name mut_vars summaries moved =
        r1 = check expr safety e fn_name mut_vars summaries moved
        check stmt list safety tuple ss fn_name mut_vars summaries r1
      check stmt list safety ((StmtIndexAssign t idxs e):ss) fn_name mut_vars summaries moved =
        r0 = check expr safety (EVar t) fn_name mut_vars summaries moved
        r1 = check expr list safety tuple idxs fn_name mut_vars summaries r0
        r2 = check expr safety tuple e fn_name mut_vars summaries r1
        check stmt list safety tuple ss fn_name mut_vars summaries r2

fn :: check stmt list safety tuple [RStmt] String [String] [RFnSummary] ([String], [RAnalysisError]) => [String] [RAnalysisError]
      check stmt list safety tuple ss fn_name mut_vars summaries (moved, errs) =
        merge moved errs errs (check stmt list safety ss fn_name mut_vars summaries moved)

fn :: collect mutable params [String]   [RPattern]        => [String]
      collect mutable params []         _                 =  []
      collect mutable params _          []                =  []
      collect mutable params (pty:ptys) ((PatVar v):pats)
        | str starts with pty "Tensor" = add unique str v (collect mutable params ptys pats)
        | otherwise = collect mutable params ptys pats
      collect mutable params (_:ptys)   (_:pats)          =  collect mutable params ptys pats

fn :: check cases safety [RFnCase] String [String] [RFnSummary] => [RAnalysisError]
      check cases safety [] _ _ _ = []
      check cases safety ((FnCase pats guards body):cs) fn_name param_types summaries =
        mut_params = collect mutable params param_types pats
        res_g = check guards safety guards fn_name mut_params summaries []
        res_b = check expr safety body fn_name mut_params summaries []
        extract analysis errs res_g (extract analysis errs res_b (check cases safety cs fn_name param_types summaries))

fn :: extract analysis errs ([String], [RAnalysisError]) [RAnalysisError] => [RAnalysisError]
      extract analysis errs (_, errs) more = errs :: more

fn :: check all fns safety acc [RFnDef] [RFnSummary] [RAnalysisError] => [RAnalysisError]
      check all fns safety acc [] _ acc = acc
      check all fns safety acc ((FnDef name param_types _ cases):fs) summaries acc =
        check all fns safety acc fs summaries (acc :: (check cases safety cases name param_types summaries))

fn :: check all fns safety [RFnDef] [RFnSummary] => [RAnalysisError]
      check all fns safety fns summaries =
        check all fns safety acc fns summaries []

fn :: analyze program errors RProgram => [RAnalysisError]
      analyze program errors prog     =
        summaries = filter nontrivial summaries (infer all summaries prog)
        check program with summaries prog summaries

fn :: check program with summaries RProgram [RFnSummary] => [RAnalysisError]
      check program with summaries (Program fns _) summaries =
        check all fns safety fns summaries

fn :: format summaries acc [RFnSummary] [String] => [String]
      format summaries acc [] acc = acc
      format summaries acc ((FnSummary name _ _ _ strat):ss) acc =
        format summaries acc ss (acc :: [name + ":" + (strategy to str strat)])

fn :: format summaries [RFnSummary] => [String]
      format summaries ss           =  format summaries acc ss []

fn :: analyze rprogram RProgram => [String]
      analyze rprogram prog     =  format summaries (infer all summaries prog)

fn :: analysis err count [RAnalysisError] => Int
      analysis err count []               =  0
      analysis err count (_:xs)           =  1 + (analysis err count xs)

fn :: verify rprogram RProgram => Bool
      verify rprogram prog     =  (analysis err count (analyze program errors prog)) == 0
