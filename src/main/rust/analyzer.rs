//! Static Analyzer for Ridgun v2.0 Next-Gen Architecture.
//! Implements Sections 3, 4, 5.3, 6, 11.2, and 13.1 of `docs/etc/next_gen_architecture.md`:
//! - Bottom-up interprocedural mutation effect inference (`ReadOnly` vs `Mutates`)
//! - `where`-block Producer-Consumer DAG builder and cycle detection
//! - Automatic Freeze on Parallel Share & `ParallelMutationConflictError`
//! - Disjoint Slice Mutation verification (`m[0]` vs `m[1]`)
//! - Affine Move verification on channel sends (`UseAfterChannelSendError`)
//! - 4-Tier AST Execution Strategy classification

use std::collections::{HashMap, HashSet};
use crate::parser::{Expr, FnDef, Pattern, Program, Statement, WhereBinding};

/// Per-parameter mutation behavior inferred bottom-up (Section 4.2 & 13.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParamEffect {
    ReadOnly,
    Mutates,
}

/// Estimated execution weight for AST tiering (Section 6.2 & 13.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum CostTier {
    Trivial,          // Tier 1: Inline sequentially
    HeavyCPU,         // Tier 2: Direct OS pthread dispatch
    DynamicRecursive, // Tier 3: Lazy work-stealing deque entry
}

/// Execution strategy selected by the compiler for each branch in `where` or `||` (Section 6.3 & 13.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BranchExecStrategy {
    InlineSequential,
    KernelWorkerJob,
    LazyStealableTask,
    FullGreenThread,
}

/// Static analysis metadata attached to every Function/Operator definition (Section 13.1).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FnStaticSummary {
    pub param_effects: Vec<ParamEffect>,
    pub can_yield: bool,
    pub cost_tier: CostTier,
    pub supports_rvp: bool,
}

/// Compile-time errors raised by the v2.0 Static Analyzer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AnalysisError {
    CyclicWhereDependencyError { function: String, variable: String },
    ParallelMutationConflictError { function: String, variable: String },
    UseAfterChannelSendError { function: String, variable: String },
}

/// Producer-Consumer Directed Acyclic Graph for a `where` block (Section 3.2).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WhereDag {
    pub num_nodes: usize,
    pub edges: Vec< Vec<usize> >,
    pub in_degree: Vec<usize>,
    pub topological_order: Vec<usize>,
    pub stages: Vec< Vec<usize> >,
}

impl WhereDag {
    /// Return true if statement `a` and statement `b` can execute concurrently ($s_a \parallel s_b$).
    pub fn are_concurrent(&self, a: usize, b: usize) -> bool {
        if a == b {
            return false;
        }
        !self.is_reachable(a, b) && !self.is_reachable(b, a)
    }

    fn is_reachable(&self, src: usize, dst: usize) -> bool {
        let mut visited = vec![false; self.num_nodes];
        let mut stack = vec![src];
        while let Some(curr) = stack.pop() {
            if curr == dst {
                return true;
            }
            if !visited[curr] {
                visited[curr] = true;
                for &next in &self.edges[curr] {
                    stack.push(next);
                }
            }
        }
        false
    }
}

/// Select the 4-tier execution strategy from `(can_yield, cost_tier)` (Section 6.3).
pub fn select_exec_strategy(can_yield: bool, cost: CostTier) -> BranchExecStrategy {
    if can_yield {
        BranchExecStrategy::FullGreenThread
    } else {
        match cost {
            CostTier::Trivial => BranchExecStrategy::InlineSequential,
            CostTier::HeavyCPU => BranchExecStrategy::KernelWorkerJob,
            CostTier::DynamicRecursive => BranchExecStrategy::LazyStealableTask,
        }
    }
}

/// Run the full v2.0 static analysis pass on a parsed `Program`.
pub fn analyze_program(
    program: &Program,
) -> Result<HashMap<String, FnStaticSummary>, Vec<AnalysisError>> {
    let summaries = infer_all_summaries(program);
    let mut errors = Vec::new();
    for fndef in &program.functions {
        check_function_safety(fndef, &summaries, &mut errors);
    }
    if errors.is_empty() {
        Ok(summaries)
    } else {
        Err(errors)
    }
}

/// Infer `FnStaticSummary` for all functions using a bottom-up fixpoint pass.
pub fn infer_all_summaries(program: &Program) -> HashMap<String, FnStaticSummary> {
    let mut summaries = HashMap::new();
    for fndef in &program.functions {
        let arity = fndef.decl.param_types.len();
        summaries.insert(
            fndef.name.clone(),
            FnStaticSummary {
                param_effects: vec![ParamEffect::ReadOnly; arity],
                can_yield: false,
                cost_tier: CostTier::Trivial,
                supports_rvp: true,
            },
        );
    }
    for _ in 0..=program.functions.len() {
        let mut changed = false;
        for fndef in &program.functions {
            let updated = compute_fn_summary(fndef, &summaries);
            if summaries.get(&fndef.name) != Some(&updated) {
                summaries.insert(fndef.name.clone(), updated);
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    summaries
}

fn compute_fn_summary(
    fndef: &FnDef,
    summaries: &HashMap<String, FnStaticSummary>,
) -> FnStaticSummary {
    let arity = fndef.decl.param_types.len();
    let mut effects = vec![ParamEffect::ReadOnly; arity];
    let mut can_yield = false;
    let mut cost_tier = CostTier::Trivial;

    for case in &fndef.cases {
        let param_names = extract_case_param_names(&case.patterns);
        let mut mutated_vars = HashSet::new();
        collect_expr_effects(&case.body, &fndef.name, summaries, &mut mutated_vars, &mut can_yield, &mut cost_tier);
        for (_, gbody) in &case.guards {
            collect_expr_effects(gbody, &fndef.name, summaries, &mut mutated_vars, &mut can_yield, &mut cost_tier);
        }
        for (idx, maybe_name) in param_names.iter().enumerate() {
            if let Some(name) = maybe_name {
                if idx < effects.len() && mutated_vars.contains(name) {
                    effects[idx] = ParamEffect::Mutates;
                }
            }
        }
    }
    FnStaticSummary {
        param_effects: effects,
        can_yield,
        cost_tier,
        supports_rvp: true,
    }
}

fn extract_case_param_names(patterns: &[Pattern]) -> Vec<Option<String>> {
    patterns
        .iter()
        .map(|pat| match pat {
            Pattern::Var(name) | Pattern::SeqBind(name) => Some(name.clone()),
            _ => None,
        })
        .collect()
}

/// Classify an arbitrary expression into one of the 4 execution strategies (Section 6.3).
pub fn classify_expr_strategy(
    expr: &Expr,
    current_fn: &str,
    summaries: &HashMap<String, FnStaticSummary>,
) -> BranchExecStrategy {
    let mut mutated = HashSet::new();
    let mut can_yield = false;
    let mut cost_tier = CostTier::Trivial;
    collect_expr_effects(expr, current_fn, summaries, &mut mutated, &mut can_yield, &mut cost_tier);
    select_exec_strategy(can_yield, cost_tier)
}

fn collect_expr_effects(
    expr: &Expr,
    current_fn: &str,
    summaries: &HashMap<String, FnStaticSummary>,
    mutated: &mut HashSet<String>,
    can_yield: &mut bool,
    cost_tier: &mut CostTier,
) {
    match expr {
        Expr::Call(callee, args) => {
            classify_call_effects(callee, args, current_fn, summaries, mutated, can_yield, cost_tier);
            for arg in args {
                collect_expr_effects(arg, current_fn, summaries, mutated, can_yield, cost_tier);
            }
        }
        Expr::IndexAssign(target, indices, val) => {
            mutated.insert(target.clone());
            for idx in indices {
                collect_expr_effects(idx, current_fn, summaries, mutated, can_yield, cost_tier);
            }
            collect_expr_effects(val, current_fn, summaries, mutated, can_yield, cost_tier);
        }
        Expr::Where(body, bindings) => {
            collect_expr_effects(body, current_fn, summaries, mutated, can_yield, cost_tier);
            for b in bindings {
                if let Some((ref target, _)) = b.index_target {
                    mutated.insert(target.clone());
                }
                collect_expr_effects(&b.expr, current_fn, summaries, mutated, can_yield, cost_tier);
            }
        }
        Expr::ParPipe(branches) => {
            for br in branches {
                collect_expr_effects(br, current_fn, summaries, mutated, can_yield, cost_tier);
            }
        }
        Expr::BinOp(_, left, right) | Expr::Hadamard(_, left, _, right, _) => {
            if matches!(expr, Expr::Hadamard(..)) {
                *cost_tier = (*cost_tier).max(CostTier::HeavyCPU);
            }
            collect_expr_effects(left, current_fn, summaries, mutated, can_yield, cost_tier);
            collect_expr_effects(right, current_fn, summaries, mutated, can_yield, cost_tier);
        }
        Expr::Einsum(terms) => {
            *cost_tier = (*cost_tier).max(CostTier::HeavyCPU);
            for (e, _) in terms {
                collect_expr_effects(e, current_fn, summaries, mutated, can_yield, cost_tier);
            }
        }
        Expr::Not(inner)
        | Expr::Out(inner)
        | Expr::WithRegionLimit(_, inner)
        | Expr::AtomicUpdate(_, inner)
        | Expr::LoadContext(_, inner)
        | Expr::LoadShared(_, inner) => {
            collect_expr_effects(inner, current_fn, summaries, mutated, can_yield, cost_tier);
        }
        Expr::WithContext(_, val, body) => {
            collect_expr_effects(val, current_fn, summaries, mutated, can_yield, cost_tier);
            collect_expr_effects(body, current_fn, summaries, mutated, can_yield, cost_tier);
        }
        Expr::Block(stmts) => {
            for stmt in stmts {
                match stmt {
                    Statement::Let(_, e) | Statement::Expr(e) => {
                        collect_expr_effects(e, current_fn, summaries, mutated, can_yield, cost_tier);
                    }
                }
            }
        }
        Expr::ListLit(elems) | Expr::TupleLit(elems) | Expr::Echo(elems) | Expr::StringInterp(elems) => {
            for e in elems {
                collect_expr_effects(e, current_fn, summaries, mutated, can_yield, cost_tier);
            }
        }
        Expr::TensorLit(elems) => {
            *cost_tier = (*cost_tier).max(CostTier::HeavyCPU);
            for e in elems {
                collect_expr_effects(e, current_fn, summaries, mutated, can_yield, cost_tier);
            }
        }
        _ => {}
    }
}

fn classify_call_effects(
    callee: &str,
    args: &[Expr],
    current_fn: &str,
    summaries: &HashMap<String, FnStaticSummary>,
    mutated: &mut HashSet<String>,
    can_yield: &mut bool,
    cost_tier: &mut CostTier,
) {
    if callee == current_fn {
        *cost_tier = (*cost_tier).max(CostTier::DynamicRecursive);
    }
    if matches!(callee, "recv" | "receive_from" | "receive_from_timeout" | "send_through" | "join") {
        *can_yield = true;
    }
    if let Some(summary) = summaries.get(callee) {
        if summary.can_yield {
            *can_yield = true;
        }
        *cost_tier = (*cost_tier).max(summary.cost_tier);
        for (idx, effect) in summary.param_effects.iter().enumerate() {
            if *effect == ParamEffect::Mutates {
                if let Some(Expr::Var(arg_var)) = args.get(idx) {
                    mutated.insert(arg_var.clone());
                }
            }
        }
    }
}

/// Build the static Producer-Consumer DAG for a `where` block (Section 3.2).
pub fn build_where_dag(
    fn_name: &str,
    bindings: &[WhereBinding],
) -> Result<WhereDag, AnalysisError> {
    let n = bindings.len();
    let mut producer_of: HashMap<String, usize> = HashMap::new();
    for (idx, b) in bindings.iter().enumerate() {
        if !b.target_var.is_empty() && b.index_target.is_none() {
            if producer_of.insert(b.target_var.clone(), idx).is_some() {
                return Err(AnalysisError::CyclicWhereDependencyError {
                    function: fn_name.to_string(),
                    variable: b.target_var.clone(),
                });
            }
        }
    }
    let mut edges = vec![Vec::new(); n];
    let mut in_degree = vec![0usize; n];
    for (j, b) in bindings.iter().enumerate() {
        let mut free_vars = HashSet::new();
        collect_free_vars(&b.expr, &mut free_vars);
        for var in free_vars {
            if let Some(&i) = producer_of.get(&var) {
                if i == j {
                    return Err(AnalysisError::CyclicWhereDependencyError {
                        function: fn_name.to_string(),
                        variable: var,
                    });
                }
                edges[i].push(j);
                in_degree[j] += 1;
            }
        }
    }
    compute_dag_stages(fn_name, n, edges, in_degree)
}

fn compute_dag_stages(
    fn_name: &str,
    n: usize,
    edges: Vec<Vec<usize>>,
    in_degree: Vec<usize>,
) -> Result<WhereDag, AnalysisError> {
    let mut rem_deg = in_degree.clone();
    let mut current_stage: Vec<usize> = (0..n).filter(|&i| rem_deg[i] == 0).collect();
    let mut stages = Vec::new();
    let mut topo = Vec::with_capacity(n);

    while !current_stage.is_empty() {
        current_stage.sort_unstable();
        let mut next_stage = Vec::new();
        for &u in &current_stage {
            topo.push(u);
            for &v in &edges[u] {
                rem_deg[v] -= 1;
                if rem_deg[v] == 0 {
                    next_stage.push(v);
                }
            }
        }
        stages.push(current_stage);
        current_stage = next_stage;
    }
    if topo.len() != n {
        return Err(AnalysisError::CyclicWhereDependencyError {
            function: fn_name.to_string(),
            variable: "cycle".to_string(),
        });
    }
    Ok(WhereDag { num_nodes: n, edges, in_degree, topological_order: topo, stages })
}

fn check_function_safety(
    fndef: &FnDef,
    summaries: &HashMap<String, FnStaticSummary>,
    errors: &mut Vec<AnalysisError>,
) {
    let mut mutable_params = HashSet::new();
    for (idx, pty) in fndef.decl.param_types.iter().enumerate() {
        if pty.starts_with("Tensor") {
            for case in &fndef.cases {
                if let Some(Pattern::Var(name)) = case.patterns.get(idx) {
                    mutable_params.insert(name.clone());
                }
            }
        }
    }
    for case in &fndef.cases {
        let mut moved = HashSet::new();
        check_expr_safety(&case.body, &fndef.name, &mutable_params, summaries, &mut moved, errors);
    }
}

fn check_expr_safety(
    expr: &Expr,
    fn_name: &str,
    mutable_vars: &HashSet<String>,
    summaries: &HashMap<String, FnStaticSummary>,
    moved: &mut HashSet<String>,
    errors: &mut Vec<AnalysisError>,
) {
    match expr {
        Expr::Var(name) => {
            if moved.contains(name) {
                errors.push(AnalysisError::UseAfterChannelSendError {
                    function: fn_name.to_string(),
                    variable: name.clone(),
                });
            }
        }
        Expr::Call(callee, args) => {
            for arg in args {
                check_expr_safety(arg, fn_name, mutable_vars, summaries, moved, errors);
            }
            if matches!(callee.as_str(), "send" | "send_through" | "chan_send") {
                if let Some(Expr::Var(sent_var)) = args.first() {
                    if mutable_vars.contains(sent_var) {
                        moved.insert(sent_var.clone());
                    }
                }
            }
        }
        Expr::Where(body, bindings) => {
            check_where_block_safety(fn_name, body, bindings, mutable_vars, summaries, moved, errors);
        }
        Expr::Block(stmts) => {
            let mut local_mut = mutable_vars.clone();
            for stmt in stmts {
                match stmt {
                    Statement::Let(name, val_expr) => {
                        if matches!(val_expr, Expr::TensorLit(_)) {
                            local_mut.insert(name.clone());
                        }
                        check_expr_safety(val_expr, fn_name, &local_mut, summaries, moved, errors);
                    }
                    Statement::Expr(e) => {
                        check_expr_safety(e, fn_name, &local_mut, summaries, moved, errors);
                    }
                }
            }
        }
        Expr::BinOp(_, l, r) | Expr::Hadamard(_, l, _, r, _) => {
            check_expr_safety(l, fn_name, mutable_vars, summaries, moved, errors);
            check_expr_safety(r, fn_name, mutable_vars, summaries, moved, errors);
        }
        Expr::Einsum(terms) => {
            for (e, _) in terms {
                check_expr_safety(e, fn_name, mutable_vars, summaries, moved, errors);
            }
        }
        Expr::Not(inner)
        | Expr::Out(inner)
        | Expr::WithRegionLimit(_, inner)
        | Expr::AtomicUpdate(_, inner)
        | Expr::LoadContext(_, inner)
        | Expr::LoadShared(_, inner) => {
            check_expr_safety(inner, fn_name, mutable_vars, summaries, moved, errors);
        }
        Expr::WithContext(_, val, body) => {
            check_expr_safety(val, fn_name, mutable_vars, summaries, moved, errors);
            check_expr_safety(body, fn_name, mutable_vars, summaries, moved, errors);
        }
        Expr::StringInterp(parts) => {
            for p in parts {
                check_expr_safety(p, fn_name, mutable_vars, summaries, moved, errors);
            }
        }
        Expr::Index(base, indices) => {
            check_expr_safety(base, fn_name, mutable_vars, summaries, moved, errors);
            for idx in indices {
                check_expr_safety(idx, fn_name, mutable_vars, summaries, moved, errors);
            }
        }
        _ => {}
    }
}

fn check_where_block_safety(
    fn_name: &str,
    body: &Expr,
    bindings: &[WhereBinding],
    mutable_vars: &HashSet<String>,
    summaries: &HashMap<String, FnStaticSummary>,
    moved: &mut HashSet<String>,
    errors: &mut Vec<AnalysisError>,
) {
    let dag = match build_where_dag(fn_name, bindings) {
        Ok(d) => d,
        Err(e) => {
            errors.push(e);
            return;
        }
    };
    for i in 0..bindings.len() {
        for j in (i + 1)..bindings.len() {
            if dag.are_concurrent(i, j) {
                check_pair_conflict(fn_name, &bindings[i], &bindings[j], summaries, errors);
            }
        }
    }
    for b in bindings {
        check_expr_safety(&b.expr, fn_name, mutable_vars, summaries, moved, errors);
    }
    check_expr_safety(body, fn_name, mutable_vars, summaries, moved, errors);
}

fn check_pair_conflict(
    fn_name: &str,
    b1: &WhereBinding,
    b2: &WhereBinding,
    summaries: &HashMap<String, FnStaticSummary>,
    errors: &mut Vec<AnalysisError>,
) {
    let mut r1 = HashSet::new();
    let mut m1 = HashSet::new();
    let mut r2 = HashSet::new();
    let mut m2 = HashSet::new();
    collect_accesses(b1, summaries, &mut r1, &mut m1);
    collect_accesses(b2, summaries, &mut r2, &mut m2);

    for var in m1.union(&m2) {
        let used_in_1 = r1.contains(var) || m1.contains(var);
        let used_in_2 = r2.contains(var) || m2.contains(var);
        if used_in_1 && used_in_2 && !are_disjoint_slices(var, b1, b2) {
            errors.push(AnalysisError::ParallelMutationConflictError {
                function: fn_name.to_string(),
                variable: var.clone(),
            });
        }
    }
}

fn are_disjoint_slices(var: &str, b1: &WhereBinding, b2: &WhereBinding) -> bool {
    match (&b1.index_target, &b2.index_target) {
        (Some((t1, idx1)), Some((t2, idx2))) if t1 == var && t2 == var => {
            !idx1.is_empty() && !idx2.is_empty() && idx1[0] != idx2[0]
        }
        _ => false,
    }
}

fn collect_accesses(
    binding: &WhereBinding,
    summaries: &HashMap<String, FnStaticSummary>,
    reads: &mut HashSet<String>,
    mutates: &mut HashSet<String>,
) {
    collect_free_vars(&binding.expr, reads);
    if let Some((ref target, _)) = binding.index_target {
        mutates.insert(target.clone());
    }
    let mut dummy_yield = false;
    let mut dummy_cost = CostTier::Trivial;
    collect_expr_effects(&binding.expr, "", summaries, mutates, &mut dummy_yield, &mut dummy_cost);
}

fn collect_free_vars(expr: &Expr, out: &mut HashSet<String>) {
    match expr {
        Expr::Var(name) => {
            out.insert(name.clone());
        }
        Expr::Call(_, args)
        | Expr::ListLit(args)
        | Expr::TupleLit(args)
        | Expr::Echo(args)
        | Expr::TensorLit(args)
        | Expr::StringInterp(args) => {
            for a in args {
                collect_free_vars(a, out);
            }
        }
        Expr::BinOp(_, l, r) | Expr::Hadamard(_, l, _, r, _) => {
            collect_free_vars(l, out);
            collect_free_vars(r, out);
        }
        Expr::Einsum(terms) => {
            for (e, _) in terms {
                collect_free_vars(e, out);
            }
        }
        Expr::Not(inner)
        | Expr::Out(inner)
        | Expr::WithRegionLimit(_, inner)
        | Expr::AtomicUpdate(_, inner)
        | Expr::LoadContext(_, inner)
        | Expr::LoadShared(_, inner) => {
            collect_free_vars(inner, out);
        }
        Expr::WithContext(_, val, body) => {
            collect_free_vars(val, out);
            collect_free_vars(body, out);
        }
        Expr::Index(base, indices) => {
            collect_free_vars(base, out);
            for i in indices {
                collect_free_vars(i, out);
            }
        }
        Expr::IndexAssign(target, indices, val) => {
            out.insert(target.clone());
            for i in indices {
                collect_free_vars(i, out);
            }
            collect_free_vars(val, out);
        }
        Expr::SeqSelect(inner, _) => collect_free_vars(inner, out),
        _ => {}
    }
}
