/// Ridgun Compiler — AST to bytecode with ADT, Tuple, Tensor, Channel, and where-DAG lowering.

use std::collections::{HashMap, HashSet};
use crate::analyzer::{build_where_dag, infer_all_summaries, FnStaticSummary};
use crate::parser::{BinOp, Expr, FnDef, Pattern, Program, Statement, TypeDef, WhereBinding};

// ── Instruction set ────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum Instruction {
    PushInt(i64),
    PushReal(f64),
    PushString(String),
    StrInterp(usize),
    Out,
    PushBool(bool),
    PushUnit,
    PushListEmpty,
    PushListConcat(usize),
    LoadLocal(usize),
    StoreLocal(usize),
    Pop,
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    CmpEq,
    CmpNeq,
    CmpGt,
    CmpLt,
    CmpGtEq,
    CmpLtEq,
    And,
    Or,
    Xor,
    Not,
    PackSeq(usize, usize),
    SeqSelectHead,
    SeqSelectRange(usize, usize),
    SeqSelectMask(Vec<bool>),
    SeqSelectIndices(Vec<usize>),
    SeqFlatJoin,
    Echo(usize),
    Call(String, usize),
    Return,
    JumpIfNeq(usize),
    JumpIfFalse(usize),
    Jump(usize),
    JumpIfEmpty(usize),
    JumpIfNotEmpty(usize),
    ListHead,
    ListTail,
    MakeTuple(usize),
    TupleGet(usize),
    MakeAdt(String, usize),
    JumpIfNotAdt(String, usize),
    AdtField(usize),
    MakeTensor(usize),
    TensorGet(usize),
    TensorSet(usize),
    TensorMatMul,
    TensorEinsum(Vec<String>),
    TensorHadamard(BinOp, String, String),
    PushContext(String),
    PopContext(String),
    LoadContext(String),
    LoadShared(String),
    AtomicStore(String),
    EnterRegionLimit(usize),
    ExitRegionLimit,
    LatchInit(usize),
    LatchArrive,
    SpawnTask(String, Vec<usize>, Option<usize>),
    WaitStageTasks,
    MailboxNew,
    ChanNew,
    ChanNewBounded,
    ChanSend,
    ChanRecv,
    ChanTryRecv,
    ChanRecvTimeout,
    Spawn,
    SpawnFunc(String, usize),
    Send(usize),
    Recv(usize),
    Join,
}

// ── Compiled output ────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct CompiledFunction {
    pub name: String,
    pub arity: usize,
    pub is_variadic: bool,
    pub code: Vec<Instruction>,
}

#[derive(Debug, Clone)]
pub struct CompiledProgram {
    pub functions: HashMap<String, CompiledFunction>,
    pub summaries: HashMap<String, FnStaticSummary>,
}

// ── Compile ────────────────────────────────────────────────

/// Compile a parsed `Program` into a `CompiledProgram`.
pub fn compile(program: &Program) -> CompiledProgram {
    let mut functions = HashMap::new();
    let mut nullary_ctors = HashSet::new();

    for tdef in &program.types {
        synthesize_type_helpers(tdef, &mut functions, &mut nullary_ctors);
    }

    let summaries = infer_all_summaries(program);
    let mut helper_functions = Vec::new();

    for fndef in &program.functions {
        let cf = compile_function_with_ctors(fndef, &nullary_ctors, &mut helper_functions);
        functions.insert(cf.name.clone(), cf);
    }

    for hf in helper_functions {
        functions.insert(hf.name.clone(), hf);
    }

    CompiledProgram { functions, summaries }
}

fn synthesize_type_helpers(
    tdef: &TypeDef,
    functions: &mut HashMap<String, CompiledFunction>,
    nullary_ctors: &mut HashSet<String>,
) {
    for (ctor, args) in &tdef.variants {
        if args.is_empty() {
            nullary_ctors.insert(ctor.clone());
        } else {
            let arity = args.len();
            let mut code: Vec<Instruction> = (0..arity).map(Instruction::LoadLocal).collect();
            code.push(Instruction::MakeAdt(ctor.clone(), arity));
            code.push(Instruction::Return);
            functions.insert(
                ctor.clone(),
                CompiledFunction { name: ctor.clone(), arity, is_variadic: false, code },
            );
        }
    }
    if !tdef.fields.is_empty() {
        let arity = tdef.fields.len();
        let mut ctor_code: Vec<Instruction> = (0..arity).map(Instruction::LoadLocal).collect();
        ctor_code.push(Instruction::MakeAdt(tdef.name.clone(), arity));
        ctor_code.push(Instruction::Return);
        functions.insert(
            tdef.name.clone(),
            CompiledFunction { name: tdef.name.clone(), arity, is_variadic: false, code: ctor_code },
        );
        for (idx, (fname, _)) in tdef.fields.iter().enumerate() {
            let code = vec![
                Instruction::LoadLocal(0),
                Instruction::AdtField(idx),
                Instruction::Return,
            ];
            functions.insert(
                fname.clone(),
                CompiledFunction { name: fname.clone(), arity: 1, is_variadic: false, code },
            );
        }
    }
}

fn compile_function_with_ctors(
    fndef: &FnDef,
    nullary_ctors: &HashSet<String>,
    helpers: &mut Vec<CompiledFunction>,
) -> CompiledFunction {
    let arity = fndef.decl.param_types.len();
    let is_variadic = fndef
        .decl
        .param_types
        .last()
        .map(|s| s.ends_with("..."))
        .unwrap_or(false);
    let mut code = Vec::new();

    for case in &fndef.cases {
        let mut locals: HashMap<String, usize> = HashMap::new();
        let mut jump_patches: Vec<usize> = Vec::new();
        let mut next_local = arity;

        for (arg_idx, pat) in case.patterns.iter().enumerate() {
            emit_pattern_match(
                pat,
                arg_idx,
                arity,
                nullary_ctors,
                &mut locals,
                &mut next_local,
                &mut jump_patches,
                &mut code,
            );
        }

        if case.guards.is_empty() {
            compile_expr(
                &case.body,
                &fndef.name,
                nullary_ctors,
                &mut locals,
                &mut next_local,
                &mut code,
                helpers,
            );
            code.push(Instruction::Return);
        } else {
            for (condition, body) in &case.guards {
                compile_expr(
                    condition,
                    &fndef.name,
                    nullary_ctors,
                    &mut locals,
                    &mut next_local,
                    &mut code,
                    helpers,
                );
                let false_patch = code.len();
                code.push(Instruction::JumpIfFalse(0));

                compile_expr(
                    body,
                    &fndef.name,
                    nullary_ctors,
                    &mut locals,
                    &mut next_local,
                    &mut code,
                    helpers,
                );
                code.push(Instruction::Return);

                let here = code.len();
                code[false_patch] = Instruction::JumpIfFalse(here);
            }
        }

        let next_case_ip = code.len();
        patch_case_jumps(&mut code, &jump_patches, next_case_ip);
    }

    CompiledFunction {
        name: fndef.name.clone(),
        arity,
        is_variadic,
        code,
    }
}

fn patch_case_jumps(code: &mut [Instruction], patches: &[usize], target: usize) {
    for &patch in patches {
        match &mut code[patch] {
            Instruction::JumpIfNeq(ref mut t)
            | Instruction::JumpIfEmpty(ref mut t)
            | Instruction::JumpIfNotEmpty(ref mut t)
            | Instruction::JumpIfNotAdt(_, ref mut t) => *t = target,
            _ => {}
        }
    }
}

fn emit_pattern_match(
    pat: &Pattern,
    slot: usize,
    arity: usize,
    nullary_ctors: &HashSet<String>,
    locals: &mut HashMap<String, usize>,
    next_local: &mut usize,
    jump_patches: &mut Vec<usize>,
    code: &mut Vec<Instruction>,
) {
    match pat {
        Pattern::Lit(value) | Pattern::NegLit(value) => {
            code.push(Instruction::LoadLocal(slot));
            code.push(Instruction::PushInt(*value));
            jump_patches.push(code.len());
            code.push(Instruction::JumpIfNeq(0));
        }
        Pattern::RealLit(value) => {
            code.push(Instruction::LoadLocal(slot));
            code.push(Instruction::PushReal(*value));
            jump_patches.push(code.len());
            code.push(Instruction::JumpIfNeq(0));
        }
        Pattern::StrLit(s) => {
            code.push(Instruction::LoadLocal(slot));
            code.push(Instruction::PushString(s.clone()));
            jump_patches.push(code.len());
            code.push(Instruction::JumpIfNeq(0));
        }
        Pattern::Var(name) if name == "True" => {
            code.push(Instruction::LoadLocal(slot));
            code.push(Instruction::PushBool(true));
            jump_patches.push(code.len());
            code.push(Instruction::JumpIfNeq(0));
        }
        Pattern::Var(name) if name == "False" => {
            code.push(Instruction::LoadLocal(slot));
            code.push(Instruction::PushBool(false));
            jump_patches.push(code.len());
            code.push(Instruction::JumpIfNeq(0));
        }
        Pattern::Var(name) if nullary_ctors.contains(name) => {
            code.push(Instruction::LoadLocal(slot));
            jump_patches.push(code.len());
            code.push(Instruction::JumpIfNotAdt(name.clone(), 0));
        }
        Pattern::Var(name) => {
            if let Some((base, _)) = crate::parser::Parser::extract_subscript_pub(name) {
                locals.insert(base, slot);
            }
            locals.insert(name.clone(), slot);
        }
        Pattern::SeqBind(name) => {
            let seq_slot = *next_local;
            *next_local += 1;
            code.push(Instruction::PackSeq(slot, arity.max(slot + 1)));
            code.push(Instruction::StoreLocal(seq_slot));
            locals.insert(name.clone(), seq_slot);
        }
        Pattern::Wildcard => {}
        Pattern::ListEmpty => {
            code.push(Instruction::LoadLocal(slot));
            jump_patches.push(code.len());
            code.push(Instruction::JumpIfNotEmpty(0));
        }
        Pattern::ListCons(head, tail) => {
            code.push(Instruction::LoadLocal(slot));
            jump_patches.push(code.len());
            code.push(Instruction::JumpIfEmpty(0));

            let head_slot = *next_local;
            *next_local += 1;
            code.push(Instruction::LoadLocal(slot));
            code.push(Instruction::ListHead);
            code.push(Instruction::StoreLocal(head_slot));
            emit_pattern_match(head, head_slot, arity, nullary_ctors, locals, next_local, jump_patches, code);

            let tail_slot = *next_local;
            *next_local += 1;
            code.push(Instruction::LoadLocal(slot));
            code.push(Instruction::ListTail);
            code.push(Instruction::StoreLocal(tail_slot));
            emit_pattern_match(tail, tail_slot, arity, nullary_ctors, locals, next_local, jump_patches, code);
        }
        Pattern::Tuple(sub_pats) => {
            for (idx, sub_pat) in sub_pats.iter().enumerate() {
                let elem_slot = *next_local;
                *next_local += 1;
                code.push(Instruction::LoadLocal(slot));
                code.push(Instruction::TupleGet(idx));
                code.push(Instruction::StoreLocal(elem_slot));
                emit_pattern_match(sub_pat, elem_slot, arity, nullary_ctors, locals, next_local, jump_patches, code);
            }
        }
        Pattern::Constructor(ctor_name, sub_pats) => {
            code.push(Instruction::LoadLocal(slot));
            jump_patches.push(code.len());
            code.push(Instruction::JumpIfNotAdt(ctor_name.clone(), 0));
            for (idx, sub_pat) in sub_pats.iter().enumerate() {
                let field_slot = *next_local;
                *next_local += 1;
                code.push(Instruction::LoadLocal(slot));
                code.push(Instruction::AdtField(idx));
                code.push(Instruction::StoreLocal(field_slot));
                emit_pattern_match(sub_pat, field_slot, arity, nullary_ctors, locals, next_local, jump_patches, code);
            }
        }
        Pattern::Record(_) => {}
    }
}

fn compile_expr(
    expr: &Expr,
    fn_name: &str,
    nullary_ctors: &HashSet<String>,
    locals: &mut HashMap<String, usize>,
    next_local: &mut usize,
    code: &mut Vec<Instruction>,
    helpers: &mut Vec<CompiledFunction>,
) {
    match expr {
        Expr::IntLit(n) => code.push(Instruction::PushInt(*n)),
        Expr::RealLit(r) => code.push(Instruction::PushReal(*r)),
        Expr::StringLit(s) => code.push(Instruction::PushString(s.clone())),
        Expr::StringInterp(parts) => {
            for p in parts {
                compile_expr(p, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::StrInterp(parts.len()));
        }
        Expr::Out(inner) => {
            compile_expr(inner, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::Out);
        }
        Expr::Not(inner) => {
            compile_expr(inner, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::Not);
        }
        Expr::BoolLit(b) => code.push(Instruction::PushBool(*b)),
        Expr::Unit => code.push(Instruction::PushUnit),
        Expr::WithContext(ctx_name, val_expr, body) => {
            compile_expr(val_expr, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::PushContext(ctx_name.clone()));
            compile_expr(body, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::PopContext(ctx_name.clone()));
        }
        Expr::WithRegionLimit(limit, body) => {
            code.push(Instruction::EnterRegionLimit(*limit as usize));
            compile_expr(body, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::ExitRegionLimit);
        }
        Expr::AtomicUpdate(var_name, val_expr) => {
            compile_expr(val_expr, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::AtomicStore(var_name.clone()));
        }
        Expr::LoadContext(ctx_name, default_expr) => {
            compile_expr(default_expr, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::LoadContext(ctx_name.clone()));
        }
        Expr::LoadShared(var_name, init_expr) => {
            compile_expr(init_expr, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::LoadShared(var_name.clone()));
        }
        Expr::Einsum(terms) => {
            let mut subs = Vec::with_capacity(terms.len());
            for (e, sub) in terms {
                compile_expr(e, fn_name, nullary_ctors, locals, next_local, code, helpers);
                subs.push(sub.clone());
            }
            code.push(Instruction::TensorEinsum(subs));
        }
        Expr::Hadamard(op, left, s1, right, s2) => {
            compile_expr(left, fn_name, nullary_ctors, locals, next_local, code, helpers);
            compile_expr(right, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::TensorHadamard(*op, s1.clone(), s2.clone()));
        }
        Expr::Var(name) => {
            if let Some(&idx) = locals.get(name) {
                code.push(Instruction::LoadLocal(idx));
            } else if let Some((base, _)) = crate::parser::Parser::extract_subscript_pub(name) {
                if let Some(&idx) = locals.get(&base) {
                    code.push(Instruction::LoadLocal(idx));
                } else {
                    panic!("Undefined variable: {}", name);
                }
            } else if nullary_ctors.contains(name) {
                code.push(Instruction::MakeAdt(name.clone(), 0));
            } else if name == "new_mailbox" || name == "mailbox" {
                code.push(Instruction::MailboxNew);
            } else if name == "new_channel" || name == "channel" {
                code.push(Instruction::ChanNew);
            } else if name == "cli_args" {
                code.push(Instruction::Call("cli_args".to_string(), 0));
            } else {
                panic!("Undefined variable: {}", name);
            }
        }
        Expr::BinOp(op, left, right) => {
            compile_expr(left, fn_name, nullary_ctors, locals, next_local, code, helpers);
            compile_expr(right, fn_name, nullary_ctors, locals, next_local, code, helpers);
            match op {
                BinOp::Add => code.push(Instruction::Add),
                BinOp::Sub => code.push(Instruction::Sub),
                BinOp::Mul => code.push(Instruction::Mul),
                BinOp::Div => code.push(Instruction::Div),
                BinOp::Mod => code.push(Instruction::Mod),
                BinOp::Eq => code.push(Instruction::CmpEq),
                BinOp::Neq => code.push(Instruction::CmpNeq),
                BinOp::Gt => code.push(Instruction::CmpGt),
                BinOp::Lt => code.push(Instruction::CmpLt),
                BinOp::GtEq => code.push(Instruction::CmpGtEq),
                BinOp::LtEq => code.push(Instruction::CmpLtEq),
                BinOp::And => code.push(Instruction::And),
                BinOp::Or => code.push(Instruction::Or),
                BinOp::Xor => code.push(Instruction::Xor),
                BinOp::Concat => code.push(Instruction::PushListConcat(2)),
                BinOp::FlatJoin => code.push(Instruction::SeqFlatJoin),
                BinOp::MatMul => code.push(Instruction::TensorMatMul),
            }
        }
        Expr::Call(name, args) => {
            compile_call_expr(name, args, fn_name, nullary_ctors, locals, next_local, code, helpers);
        }
        Expr::Echo(args) => {
            for arg in args {
                compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::Echo(args.len()));
        }
        Expr::ListLit(elems) => {
            for elem in elems {
                compile_expr(elem, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::PushListConcat(elems.len()));
        }
        Expr::ListEmpty => code.push(Instruction::PushListEmpty),
        Expr::TupleLit(elems) => {
            for elem in elems {
                compile_expr(elem, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::MakeTuple(elems.len()));
        }
        Expr::TensorLit(elems) => {
            for elem in elems {
                compile_expr(elem, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::MakeTensor(elems.len()));
        }
        Expr::Index(base, indices) => {
            compile_expr(base, fn_name, nullary_ctors, locals, next_local, code, helpers);
            for idx in indices {
                compile_expr(idx, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::TensorGet(indices.len()));
        }
        Expr::IndexAssign(target, indices, val) => {
            let slot = *locals.get(target).unwrap_or_else(|| panic!("Undefined tensor: {}", target));
            code.push(Instruction::LoadLocal(slot));
            for idx in indices {
                compile_expr(idx, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            compile_expr(val, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::TensorSet(indices.len()));
            code.push(Instruction::StoreLocal(slot));
            code.push(Instruction::LoadLocal(slot));
        }
        Expr::Where(body, bindings) => {
            compile_where_expr(body, bindings, fn_name, nullary_ctors, locals, next_local, code, helpers);
        }
        Expr::ParPipe(branches) => {
            compile_par_pipe(branches, fn_name, nullary_ctors, locals, next_local, code, helpers);
        }
        Expr::SeqSelect(seq_expr, mask) => {
            compile_expr(seq_expr, fn_name, nullary_ctors, locals, next_local, code, helpers);
            if mask.contains('+') || mask.contains('_') {
                let bool_mask: Vec<bool> = mask
                    .chars()
                    .filter(|&c| c == '+' || c == '_')
                    .map(|c| c == '+')
                    .collect();
                code.push(Instruction::SeqSelectMask(bool_mask));
            } else {
                let indices: Vec<usize> = mask
                    .split_whitespace()
                    .filter_map(|p| p.parse::<usize>().ok())
                    .collect();
                code.push(Instruction::SeqSelectIndices(indices));
            }
        }
        Expr::Block(stmts) => {
            for (i, stmt) in stmts.iter().enumerate() {
                match stmt {
                    Statement::Let(name, val_expr) => {
                        compile_expr(val_expr, fn_name, nullary_ctors, locals, next_local, code, helpers);
                        let slot = *next_local;
                        *next_local += 1;
                        if let Some((base, _)) = crate::parser::Parser::extract_subscript_pub(name) {
                            locals.insert(base, slot);
                        }
                        locals.insert(name.clone(), slot);
                        code.push(Instruction::StoreLocal(slot));
                    }
                    Statement::Expr(e) => {
                        compile_expr(e, fn_name, nullary_ctors, locals, next_local, code, helpers);
                        if i < stmts.len() - 1 {
                            code.push(Instruction::Pop);
                        }
                    }
                }
            }
        }
    }
}

fn compile_call_expr(
    name: &str,
    args: &[Expr],
    fn_name: &str,
    nullary_ctors: &HashSet<String>,
    locals: &mut HashMap<String, usize>,
    next_local: &mut usize,
    code: &mut Vec<Instruction>,
    helpers: &mut Vec<CompiledFunction>,
) {
    match name {
        "spawn" => {
            if let Some(Expr::StringLit(target_fn)) = args.first() {
                for arg in args.iter().skip(1) {
                    compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
                }
                code.push(Instruction::SpawnFunc(target_fn.clone(), args.len().saturating_sub(1)));
            } else {
                code.push(Instruction::Spawn);
            }
        }
        "join" => {
            for arg in args {
                compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::Join);
        }
        "send" => {
            for arg in args {
                compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::Send(0));
        }
        "recv" => {
            for arg in args {
                compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::Recv(0));
        }
        "new_bounded_channel" => {
            for arg in args {
                compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::ChanNewBounded);
        }
        "send_through" | "chan_send" => {
            for arg in args {
                compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::ChanSend);
        }
        "receive_from" | "chan_recv" => {
            for arg in args {
                compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::ChanRecv);
        }
        "try_receive_from" | "chan_try_recv" => {
            for arg in args {
                compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::ChanTryRecv);
        }
        "receive_from_timeout" => {
            for arg in args {
                compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::ChanRecvTimeout);
        }
        _ => {
            for arg in args {
                compile_expr(arg, fn_name, nullary_ctors, locals, next_local, code, helpers);
            }
            code.push(Instruction::Call(name.to_string(), args.len()));
        }
    }
}

fn synthesize_branch_helper(
    branch_expr: &Expr,
    parent_fn: &str,
    nullary_ctors: &HashSet<String>,
    parent_locals: &HashMap<String, usize>,
    helpers: &mut Vec<CompiledFunction>,
) -> (String, Vec<usize>) {
    let helper_id = helpers.len();
    let helper_name = format!("__par_{}_{}", parent_fn, helper_id);
    let mut ordered_vars: Vec<(String, usize)> = parent_locals
        .iter()
        .map(|(k, &v)| (k.clone(), v))
        .collect();
    ordered_vars.sort_by_key(|(_, slot)| *slot);

    let mut child_locals = HashMap::new();
    let mut parent_slots = Vec::new();
    for (new_idx, (var_name, orig_slot)) in ordered_vars.into_iter().enumerate() {
        child_locals.insert(var_name, new_idx);
        parent_slots.push(orig_slot);
    }
    let arity = parent_slots.len();
    let mut next_local = arity;
    let mut child_code = Vec::new();
    compile_expr(
        branch_expr,
        &helper_name,
        nullary_ctors,
        &mut child_locals,
        &mut next_local,
        &mut child_code,
        helpers,
    );
    child_code.push(Instruction::Return);
    helpers.push(CompiledFunction {
        name: helper_name.clone(),
        arity,
        is_variadic: false,
        code: child_code,
    });
    (helper_name, parent_slots)
}

fn compile_par_pipe(
    branches: &[Expr],
    fn_name: &str,
    nullary_ctors: &HashSet<String>,
    locals: &mut HashMap<String, usize>,
    next_local: &mut usize,
    code: &mut Vec<Instruction>,
    helpers: &mut Vec<CompiledFunction>,
) {
    if branches.len() > 1 {
        let mut temp_slots = Vec::with_capacity(branches.len());
        for br in branches {
            let slot = *next_local;
            *next_local += 1;
            temp_slots.push(slot);
            let (helper_name, parent_slots) =
                synthesize_branch_helper(br, fn_name, nullary_ctors, locals, helpers);
            code.push(Instruction::SpawnTask(helper_name, parent_slots, Some(slot)));
        }
        code.push(Instruction::WaitStageTasks);
        for slot in temp_slots {
            code.push(Instruction::LoadLocal(slot));
        }
        code.push(Instruction::MakeTuple(branches.len()));
    } else {
        code.push(Instruction::LatchInit(branches.len()));
        for br in branches {
            compile_expr(br, fn_name, nullary_ctors, locals, next_local, code, helpers);
            code.push(Instruction::LatchArrive);
        }
        code.push(Instruction::MakeTuple(branches.len()));
    }
}

fn compile_where_expr(
    body: &Expr,
    bindings: &[WhereBinding],
    fn_name: &str,
    nullary_ctors: &HashSet<String>,
    locals: &mut HashMap<String, usize>,
    next_local: &mut usize,
    code: &mut Vec<Instruction>,
    helpers: &mut Vec<CompiledFunction>,
) {
    let dag = build_where_dag(fn_name, bindings).unwrap_or_else(|e| panic!("Where DAG error: {:?}", e));
    for stage in &dag.stages {
        let all_pure_vars = stage.len() > 1 && stage.iter().all(|&idx| bindings[idx].index_target.is_none());
        if all_pure_vars {
            let mut stage_new_locals = Vec::new();
            for &idx in stage {
                let b = &bindings[idx];
                let slot = *next_local;
                *next_local += 1;
                let (helper_name, parent_slots) =
                    synthesize_branch_helper(&b.expr, fn_name, nullary_ctors, locals, helpers);
                code.push(Instruction::SpawnTask(helper_name, parent_slots, Some(slot)));
                stage_new_locals.push((b.target_var.clone(), slot));
            }
            code.push(Instruction::WaitStageTasks);
            for (var_name, slot) in stage_new_locals {
                locals.insert(var_name, slot);
            }
        } else {
            code.push(Instruction::LatchInit(stage.len()));
            for &idx in stage {
                let b = &bindings[idx];
                if let Some((ref target_tensor, ref indices)) = b.index_target {
                    let slot = *locals
                        .get(target_tensor)
                        .unwrap_or_else(|| panic!("Undefined tensor: {}", target_tensor));
                    code.push(Instruction::LoadLocal(slot));
                    for &i_val in indices {
                        code.push(Instruction::PushInt(i_val));
                    }
                    compile_expr(&b.expr, fn_name, nullary_ctors, locals, next_local, code, helpers);
                    code.push(Instruction::TensorSet(indices.len()));
                    code.push(Instruction::StoreLocal(slot));
                    code.push(Instruction::LatchArrive);
                } else {
                    compile_expr(&b.expr, fn_name, nullary_ctors, locals, next_local, code, helpers);
                    let slot = *next_local;
                    *next_local += 1;
                    locals.insert(b.target_var.clone(), slot);
                    code.push(Instruction::StoreLocal(slot));
                    code.push(Instruction::LatchArrive);
                }
            }
        }
    }
    compile_expr(body, fn_name, nullary_ctors, locals, next_local, code, helpers);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lexer::Lexer;
    use crate::parser::Parser;

    fn compile_src(src: &str) -> CompiledProgram {
        let (tokens, spans) = Lexer::new(src).tokenize();
        let program = Parser::new(tokens, spans).parse();
        compile(&program)
    }

    #[test]
    fn test_sum_bytecode() {
        let cp = compile_src("fn :: sum int int => int\nsum a b = a + b");
        let f = &cp.functions["sum"];
        assert_eq!(f.arity, 2);
        assert_eq!(f.code, vec![
            Instruction::LoadLocal(0),
            Instruction::LoadLocal(1),
            Instruction::Add,
            Instruction::Return,
        ]);
    }

    #[test]
    fn test_factorial_bytecode() {
        let cp = compile_src(
            "fn :: factorial int => int\nfactorial 0 = 1\nfactorial n = n * factorial (n - 1)"
        );
        let f = &cp.functions["factorial"];
        assert_eq!(f.arity, 1);
        assert_eq!(f.code[0], Instruction::LoadLocal(0));
        assert_eq!(f.code[1], Instruction::PushInt(0));
        assert!(matches!(f.code[2], Instruction::JumpIfNeq(_)));
        assert_eq!(f.code[3], Instruction::PushInt(1));
        assert_eq!(f.code[4], Instruction::Return);
    }

    #[test]
    fn test_echo_bytecode() {
        let cp = compile_src("fn :: greet => ()\ngreet = echo \"hello\" \"world\"");
        let f = &cp.functions["greet"];
        assert_eq!(f.code[0], Instruction::PushString("hello".into()));
        assert_eq!(f.code[1], Instruction::PushString("world".into()));
        assert_eq!(f.code[2], Instruction::Echo(2));
    }

    #[test]
    fn test_bool_bytecode() {
        let cp = compile_src("fn :: t => Int\nt = True == False");
        let f = &cp.functions["t"];
        assert_eq!(f.code[0], Instruction::PushBool(true));
        assert_eq!(f.code[1], Instruction::PushBool(false));
        assert_eq!(f.code[2], Instruction::CmpEq);
    }
}
