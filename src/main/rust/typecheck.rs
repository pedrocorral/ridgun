/// Ridgun Type Checker — validates AST node types against function signatures

use std::collections::HashMap;
use crate::parser::{Expr, Statement, BinOp, Pattern, FnCase, FnDef, Program};

// ── Type System ──

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Type {
    Int,
    Real,
    Char,
    String,
    Bool,
    Unit,
    List(Box<Type>),
    Fun(Vec<Type>, Box<Type>),
    TypeVar(String),
    Tuple(Vec<Type>),
    Tensor(Vec<String>),
    Variadic(Box<Type>),
}

impl std::fmt::Display for Type {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Type::Int => write!(f, "Int"),
            Type::Real => write!(f, "Real"),
            Type::Char => write!(f, "Char"),
            Type::String => write!(f, "String"),
            Type::Bool => write!(f, "Bool"),
            Type::Unit => write!(f, "()"),
            Type::List(inner) => write!(f, "[{}]", inner),
            Type::Fun(params, ret) => {
                let ps: Vec<String> = params.iter().map(|t| t.to_string()).collect();
                write!(f, "({} => {})", ps.join(", "), ret)
            }
            Type::TypeVar(name) => write!(f, "{}", name),
            Type::Tuple(types) => {
                let ts: Vec<String> = types.iter().map(|t| t.to_string()).collect();
                write!(f, "({})", ts.join(", "))
            }
            Type::Tensor(dims) => {
                if dims.is_empty() {
                    write!(f, "Tensor")
                } else {
                    write!(f, "Tensor({})", dims.join(", "))
                }
            }
            Type::Variadic(inner) => write!(f, "{}...", inner),
        }
    }
}

// ── Type Errors ──

#[derive(Debug, Clone, PartialEq)]
pub struct TypeError {
    pub function: String,
    pub message: String,
}

impl std::fmt::Display for TypeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "type error in function '{}': {}", self.function, self.message)
    }
}

// ── Type Environment ──

pub struct TypeEnv {
    scopes: Vec<HashMap<String, Type>>,
    functions: HashMap<String, Type>,
}

impl TypeEnv {
    fn new() -> Self {
        TypeEnv {
            scopes: vec![HashMap::new()],
            functions: HashMap::new(),
        }
    }

    fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }

    fn pop_scope(&mut self) {
        self.scopes.pop();
    }

    fn insert_local(&mut self, name: String, ty: Type) {
        self.scopes.last_mut().expect("no active scope").insert(name, ty);
    }

    fn lookup_local(&self, name: &str) -> Option<&Type> {
        self.scopes.iter().rev().find_map(|s| s.get(name))
    }

    fn insert_function(&mut self, name: String, ty: Type) {
        self.functions.insert(name, ty);
    }

    fn lookup_function(&self, name: &str) -> Option<&Type> {
        self.functions.get(name)
    }
}

// ── Type String Parser ──

fn parse_type_string(s: &str) -> Type {
    if let Some(base) = s.strip_suffix("...") {
        return Type::Variadic(Box::new(parse_type_string(base)));
    }
    match s {
        "Int" | "U8" | "U16" | "U32" | "U64" | "I8" | "I16" | "I32" | "I64" | "Usize" => Type::Int,
        "Real" => Type::Real,
        "Char" => Type::Char,
        "String" => Type::String,
        "Bool" => Type::Bool,
        "Unit" | "()" => Type::Unit,
        "Tensor" | "Tensor_GPU" => Type::Tensor(Vec::new()),
        other => {
            if let Some(inner) = other.strip_prefix("Tensor(").and_then(|s| s.strip_suffix(')')) {
                let dims: Vec<String> = inner
                    .split(',')
                    .map(|d| d.trim().to_string())
                    .filter(|d| !d.is_empty())
                    .collect();
                Type::Tensor(dims)
            } else if other.chars().next().map(|c| c.is_ascii_lowercase()).unwrap_or(false) {
                Type::TypeVar(other.to_string())
            } else if let Some(inner) = other.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
                Type::List(Box::new(parse_type_string(inner)))
            } else if other.starts_with('(') && other.ends_with(')') {
                let inner = &other[1..other.len() - 1];
                let types: Vec<Type> = inner
                    .split(',')
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .map(parse_type_string)
                    .collect();
                Type::Tuple(types)
            } else {
                Type::TypeVar(other.to_string())
            }
        }
    }
}

// ── Type Unification (for type inference) ──

fn unify(t1: &Type, t2: &Type) -> bool {
    match (t1, t2) {
        (Type::Int, Type::Int)
        | (Type::Real, Type::Real)
        | (Type::Char, Type::Char)
        | (Type::Char, Type::String)
        | (Type::String, Type::Char)
        | (Type::String, Type::String)
        | (Type::Bool, Type::Bool)
        | (Type::Unit, Type::Unit) => true,

        (Type::Tensor(d1), Type::Tensor(d2)) => {
            if d1.is_empty() || d2.is_empty() {
                true
            } else {
                d1.len() == d2.len()
                    && d1.iter().zip(d2.iter()).all(|(a, b)| {
                        a == b
                            || a.chars().next().map(|c| c.is_ascii_lowercase()).unwrap_or(false)
                            || b.chars().next().map(|c| c.is_ascii_lowercase()).unwrap_or(false)
                    })
            }
        }

        (Type::Variadic(inner), other) | (other, Type::Variadic(inner)) => {
            unify(inner, other) || unify(&Type::List(inner.clone()), other)
        }

        (Type::TypeVar(_), _) | (_, Type::TypeVar(_)) => true,

        (Type::List(inner1), Type::List(inner2)) => unify(inner1, inner2),

        (Type::Tuple(elems1), Type::Tuple(elems2)) => {
            elems1.len() == elems2.len()
                && elems1.iter().zip(elems2.iter()).all(|(a, b)| unify(a, b))
        }

        (Type::Fun(params1, ret1), Type::Fun(params2, ret2)) => {
            params1.len() == params2.len()
                && params1.iter().zip(params2.iter()).all(|(a, b)| unify(a, b))
                && unify(ret1, ret2)
        }

        _ => false,
    }
}

pub fn types_compatible(t1: &Type, t2: &Type) -> bool {
    unify(t1, t2)
}

// ── Type Checker ──

pub fn typecheck(program: &Program) -> Result<(), Vec<TypeError>> {
    let mut errors: Vec<TypeError> = Vec::new();
    let mut env = TypeEnv::new();
    env.insert_function("spawn".to_string(), Type::Fun(vec![Type::String], Box::new(Type::Int)));
    env.insert_function("join".to_string(), Type::Fun(vec![Type::Int], Box::new(Type::Int)));
    env.insert_local("new_mailbox".to_string(), Type::Int);
    env.insert_local("mailbox".to_string(), Type::Int);
    env.insert_local("new_channel".to_string(), Type::Int);
    env.insert_local("channel".to_string(), Type::Int);
    env.insert_function("new_bounded_channel".to_string(), Type::Fun(vec![Type::Int], Box::new(Type::Int)));
    env.insert_function(
        "send_through".to_string(),
        Type::Fun(vec![Type::TypeVar("a".into()), Type::Int], Box::new(Type::Unit)),
    );
    env.insert_function(
        "chan_send".to_string(),
        Type::Fun(vec![Type::TypeVar("a".into()), Type::Int], Box::new(Type::Unit)),
    );
    env.insert_function(
        "receive_from".to_string(),
        Type::Fun(vec![Type::Int], Box::new(Type::TypeVar("a".into()))),
    );
    env.insert_function(
        "chan_recv".to_string(),
        Type::Fun(vec![Type::Int], Box::new(Type::TypeVar("a".into()))),
    );
    env.insert_function(
        "try_receive_from".to_string(),
        Type::Fun(vec![Type::Int], Box::new(Type::TypeVar("Option".into()))),
    );
    env.insert_function(
        "chan_try_recv".to_string(),
        Type::Fun(vec![Type::Int], Box::new(Type::TypeVar("Option".into()))),
    );
    env.insert_function(
        "receive_from_timeout".to_string(),
        Type::Fun(vec![Type::Int, Type::Int], Box::new(Type::TypeVar("Option".into()))),
    );
    env.insert_function("str_len".to_string(), Type::Fun(vec![Type::String], Box::new(Type::Int)));
    env.insert_function("str_char_at".to_string(), Type::Fun(vec![Type::String, Type::Int], Box::new(Type::Int)));
    env.insert_function("str_slice".to_string(), Type::Fun(vec![Type::String, Type::Int, Type::Int], Box::new(Type::String)));
    env.insert_function("char_from_code".to_string(), Type::Fun(vec![Type::Int], Box::new(Type::String)));
    env.insert_function("str_concat".to_string(), Type::Fun(vec![Type::String, Type::String], Box::new(Type::String)));
    env.insert_function("int_to_str".to_string(), Type::Fun(vec![Type::Int], Box::new(Type::String)));
    env.insert_function("str_to_int".to_string(), Type::Fun(vec![Type::String], Box::new(Type::Int)));
    env.insert_function("str_starts_with".to_string(), Type::Fun(vec![Type::String, Type::String], Box::new(Type::Bool)));
    env.insert_function("str_contains".to_string(), Type::Fun(vec![Type::String, Type::String], Box::new(Type::Bool)));
    env.insert_function("read_file".to_string(), Type::Fun(vec![Type::String], Box::new(Type::String)));
    env.insert_function("write_file".to_string(), Type::Fun(vec![Type::String, Type::String], Box::new(Type::Unit)));
    env.insert_function("shell_exec".to_string(), Type::Fun(vec![Type::String], Box::new(Type::Int)));
    env.insert_local("cli_args".to_string(), Type::List(Box::new(Type::String)));

    for tdef in &program.types {
        let adt_ty = parse_type_string(&tdef.name);
        for (ctor, arg_strs) in &tdef.variants {
            let arg_tys: Vec<Type> = arg_strs.iter().map(|s| parse_type_string(s)).collect();
            if arg_tys.is_empty() {
                env.insert_local(ctor.clone(), adt_ty.clone());
            } else {
                env.insert_function(ctor.clone(), Type::Fun(arg_tys, Box::new(adt_ty.clone())));
            }
        }
        if !tdef.fields.is_empty() {
            let mut ctor_args = Vec::new();
            for (fname, ftype_str) in &tdef.fields {
                let fty = parse_type_string(ftype_str);
                ctor_args.push(fty.clone());
                env.insert_function(fname.clone(), Type::Fun(vec![adt_ty.clone()], Box::new(fty)));
            }
            env.insert_function(tdef.name.clone(), Type::Fun(ctor_args, Box::new(adt_ty)));
        }
    }

    for func in &program.functions {
        let param_types: Vec<Type> = func
            .decl
            .param_types
            .iter()
            .map(|s| parse_type_string(s))
            .collect();
        let return_type = parse_type_string(&func.decl.return_type);
        let sig = Type::Fun(param_types.clone(), Box::new(return_type));
        env.insert_function(func.name.clone(), sig);
    }

    for func in &program.functions {
        check_function(func, &mut env, &mut errors);
    }

    if let Err(analysis_errs) = crate::analyzer::analyze_program(program) {
        for aerr in analysis_errs {
            let (fn_name, msg) = match aerr {
                crate::analyzer::AnalysisError::CyclicWhereDependencyError { function, variable } => {
                    (function, format!("CyclicWhereDependencyError on '{}'", variable))
                }
                crate::analyzer::AnalysisError::ParallelMutationConflictError { function, variable } => {
                    (function, format!("ParallelMutationConflictError on '{}'", variable))
                }
                crate::analyzer::AnalysisError::UseAfterChannelSendError { function, variable } => {
                    (function, format!("UseAfterChannelSendError on '{}'", variable))
                }
            };
            errors.push(TypeError { function: fn_name, message: msg });
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

fn check_function(func: &FnDef, env: &mut TypeEnv, errors: &mut Vec<TypeError>) {
    let decl_param_count = func.decl.param_types.len();
    let return_type = parse_type_string(&func.decl.return_type);
    let param_types: Vec<Type> = func
        .decl
        .param_types
        .iter()
        .map(|s| parse_type_string(s))
        .collect();

    for (case_idx, case) in func.cases.iter().enumerate() {
        let has_seq_bind = case.patterns.iter().any(|p| matches!(p, Pattern::SeqBind(_)));
        if case.patterns.len() != decl_param_count && !has_seq_bind {
            errors.push(TypeError {
                function: func.name.clone(),
                message: format!(
                    "case #{} has {} pattern(s), expected {}",
                    case_idx,
                    case.patterns.len(),
                    decl_param_count
                ),
            });
            continue;
        }
        check_case(func, case, &param_types, &return_type, env, errors);
    }
}

fn check_case(
    func: &FnDef,
    case: &FnCase,
    param_types: &[Type],
    return_type: &Type,
    env: &mut TypeEnv,
    errors: &mut Vec<TypeError>,
) {
    env.push_scope();

    let has_seq_bind = case.patterns.iter().any(|p| matches!(p, Pattern::SeqBind(_)));

    for (pat_idx, pattern) in case.patterns.iter().enumerate() {
        if matches!(pattern, Pattern::SeqBind(_)) {
            bind_pattern(pattern, &Type::Int, env);
        } else {
            let expected = if has_seq_bind {
                Type::Int
            } else {
                match param_types.get(pat_idx).cloned().unwrap_or(Type::Int) {
                    Type::Variadic(inner) => Type::List(inner),
                    other => other,
                }
            };
            bind_pattern(pattern, &expected, env);
        }
    }

    for (guard_idx, (condition, body)) in case.guards.iter().enumerate() {
        let cond_ty = check_expr(condition, func.name.as_str(), env, errors);
        if cond_ty != Type::Bool {
            errors.push(TypeError {
                function: func.name.clone(),
                message: format!(
                    "guard #{} condition has type {}, expected Bool",
                    guard_idx, cond_ty
                ),
            });
        }
        let body_ty = check_expr(body, func.name.as_str(), env, errors);
        let is_empty_list_compat = matches!((&body_ty, return_type), (Type::List(b), Type::List(_)) if b.as_ref() == &Type::TypeVar("_empty".to_string()));
        if !types_compatible(&body_ty, return_type) && !is_empty_list_compat {
            errors.push(TypeError {
                function: func.name.clone(),
                message: format!(
                    "guard #{} body has type {}, expected {}",
                    guard_idx, body_ty, return_type
                ),
            });
        }
    }

    if case.guards.is_empty() {
        let body_ty = check_expr(&case.body, func.name.as_str(), env, errors);
        let is_empty_list_compat = matches!((&body_ty, return_type), (Type::List(b), Type::List(_)) if b.as_ref() == &Type::TypeVar("_empty".to_string()));
        if !types_compatible(&body_ty, return_type) && !is_empty_list_compat {
            errors.push(TypeError {
                function: func.name.clone(),
                message: format!("body has type {}, expected {}", body_ty, return_type),
            });
        }
    }

    env.pop_scope();
}

fn bind_pattern(pattern: &Pattern, expected_type: &Type, env: &mut TypeEnv) {
    match pattern {
        Pattern::Wildcard
        | Pattern::Lit(_)
        | Pattern::NegLit(_)
        | Pattern::RealLit(_)
        | Pattern::StrLit(_) => {}
        Pattern::Var(name) => {
            env.insert_local(name.clone(), expected_type.clone());
        }
        Pattern::ListEmpty => {}
        Pattern::ListCons(head, tail) => {
            if let Type::List(elem_type) = expected_type {
                bind_pattern(head, elem_type, env);
                bind_pattern(tail, expected_type, env);
            }
        }
        Pattern::SeqBind(name) => {
            env.insert_local(name.clone(), Type::Int);
        }
        Pattern::Tuple(pats) => {
            if let Type::Tuple(types) = expected_type {
                for (i, pat) in pats.iter().enumerate() {
                    let ptype = types.get(i).unwrap_or(&Type::Int);
                    bind_pattern(pat, ptype, env);
                }
            }
        }
        Pattern::Constructor(ctor_name, args) => {
            let param_tys = env
                .lookup_function(ctor_name)
                .and_then(|t| match t {
                    Type::Fun(params, _) => Some(params.clone()),
                    _ => None,
                })
                .unwrap_or_default();
            for (i, arg) in args.iter().enumerate() {
                let pty = param_tys.get(i).unwrap_or(&Type::Int);
                bind_pattern(arg, pty, env);
            }
        }
        Pattern::Record(fields) => {
            for (_, pat) in fields {
                bind_pattern(pat, expected_type, env);
            }
        }
    }
}

fn check_expr(expr: &Expr, func_name: &str, env: &mut TypeEnv, errors: &mut Vec<TypeError>) -> Type {
    match expr {
        Expr::IntLit(_) => Type::Int,
        Expr::RealLit(_) => Type::Real,
        Expr::StringLit(_) => Type::String,
        Expr::StringInterp(parts) => {
            for p in parts {
                let _ = check_expr(p, func_name, env, errors);
            }
            Type::String
        }
        Expr::BoolLit(_) => Type::Bool,
        Expr::Unit => Type::Unit,
        Expr::Not(inner) => {
            let inner_ty = check_expr(inner, func_name, env, errors);
            if !types_compatible(&inner_ty, &Type::Bool) {
                errors.push(TypeError {
                    function: func_name.to_string(),
                    message: format!("NOT requires Bool operand, got {}", inner_ty),
                });
            }
            Type::Bool
        }
        Expr::Out(inner) => {
            let _ = check_expr(inner, func_name, env, errors);
            Type::TypeVar("_out".to_string())
        }
        Expr::WithContext(ctx_name, val_expr, body) => {
            let val_ty = check_expr(val_expr, func_name, env, errors);
            env.push_scope();
            env.insert_local(ctx_name.clone(), val_ty);
            let body_ty = check_expr(body, func_name, env, errors);
            env.pop_scope();
            body_ty
        }
        Expr::WithRegionLimit(_, body) => {
            let _ = check_expr(body, func_name, env, errors);
            Type::TypeVar("Result".to_string())
        }
        Expr::AtomicUpdate(_, val_expr) => {
            let _ = check_expr(val_expr, func_name, env, errors);
            Type::Unit
        }
        Expr::LoadContext(_, default_expr) | Expr::LoadShared(_, default_expr) => {
            check_expr(default_expr, func_name, env, errors)
        }
        Expr::Einsum(terms) => {
            let mut shapes: Vec<(String, Vec<String>)> = Vec::new();
            for (e, sub) in terms {
                let ty = check_expr(e, func_name, env, errors);
                if let Type::Tensor(dims) = ty {
                    shapes.push((sub.clone(), dims));
                }
            }
            let mut dim_env: HashMap<char, String> = HashMap::new();
            for (sub, dims) in &shapes {
                if !dims.is_empty() && dims.len() == sub.chars().count() {
                    for (ch, dim_name) in sub.chars().zip(dims.iter()) {
                        if let Some(prev) = dim_env.get(&ch) {
                            if prev != dim_name {
                                errors.push(TypeError {
                                    function: func_name.to_string(),
                                    message: format!(
                                        "tensor einsum dimension mismatch for index '{}': {} vs {}",
                                        ch, prev, dim_name
                                    ),
                                });
                            }
                        } else {
                            dim_env.insert(ch, dim_name.clone());
                        }
                    }
                }
            }
            Type::Tensor(Vec::new())
        }
        Expr::Hadamard(_, left, _, right, _) => {
            let l_ty = check_expr(left, func_name, env, errors);
            let _ = check_expr(right, func_name, env, errors);
            match l_ty {
                Type::Tensor(_) => l_ty,
                _ => Type::Tensor(Vec::new()),
            }
        }
        Expr::Var(name) => {
            if let Some(ty) = env.lookup_local(name) {
                ty.clone()
            } else if let Some(ty) = env.lookup_function(name) {
                match ty {
                    Type::Fun(params, ret) if params.is_empty() => ret.as_ref().clone(),
                    other => other.clone(),
                }
            } else if let Some((base, _)) = crate::parser::Parser::extract_subscript_pub(name) {
                if let Some(ty) = env.lookup_local(&base) {
                    ty.clone()
                } else {
                    Type::Tensor(Vec::new())
                }
            } else {
                errors.push(TypeError {
                    function: func_name.to_string(),
                    message: format!("undefined variable '{}'", name),
                });
                Type::Int
            }
        }
        Expr::BinOp(op, left, right) => {
            let left_ty = check_expr(left, func_name, env, errors);
            let right_ty = check_expr(right, func_name, env, errors);
            check_binop(op, &left_ty, &right_ty, env, func_name, errors)
        }
        Expr::Call(name, args) => {
            let arg_types: Vec<Type> = args
                .iter()
                .map(|a| check_expr(a, func_name, env, errors))
                .collect();

            if name == "spawn" {
                return Type::Int;
            }

            if let Some(fun_ty) = env.lookup_function(name).cloned() {
                if let Type::Fun(param_tys, ret_ty) = fun_ty {
                    let is_variadic = matches!(param_tys.last(), Some(Type::Variadic(_)));
                    let is_tuple_chain = arg_types.len() == 1
                        && param_tys.len() > 1
                        && matches!(&arg_types[0], Type::Tuple(elems) if elems.len() == param_tys.len());

                    if is_variadic {
                        let fixed = param_tys.len().saturating_sub(1);
                        let var_ty = match param_tys.last().unwrap() {
                            Type::Variadic(inner) => inner.as_ref(),
                            _ => unreachable!(),
                        };
                        if arg_types.len() < fixed {
                            errors.push(TypeError {
                                function: func_name.to_string(),
                                message: format!(
                                    "function '{}' called with {} argument(s), expected at least {}",
                                    name,
                                    arg_types.len(),
                                    fixed
                                ),
                            });
                        } else {
                            for i in 0..fixed {
                                if !types_compatible(&arg_types[i], &param_tys[i]) {
                                    errors.push(TypeError {
                                        function: func_name.to_string(),
                                        message: format!(
                                            "function '{}' arg #{} has type {}, expected {}",
                                            name, i, arg_types[i], param_tys[i]
                                        ),
                                    });
                                }
                            }
                            for i in fixed..arg_types.len() {
                                if !types_compatible(&arg_types[i], var_ty)
                                    && !types_compatible(&arg_types[i], &Type::List(Box::new(var_ty.clone())))
                                {
                                    errors.push(TypeError {
                                        function: func_name.to_string(),
                                        message: format!(
                                            "function '{}' variadic arg #{} has type {}, expected {}",
                                            name, i, arg_types[i], var_ty
                                        ),
                                    });
                                }
                            }
                        }
                    } else if is_tuple_chain {
                        if let Type::Tuple(elems) = &arg_types[0] {
                            for (i, (arg, param)) in elems.iter().zip(param_tys.iter()).enumerate() {
                                if !types_compatible(arg, param) {
                                    errors.push(TypeError {
                                        function: func_name.to_string(),
                                        message: format!(
                                            "function '{}' arg #{} has type {}, expected {}",
                                            name, i, arg, param
                                        ),
                                    });
                                }
                            }
                        }
                    } else if arg_types.len() != param_tys.len() {
                        errors.push(TypeError {
                            function: func_name.to_string(),
                            message: format!(
                                "function '{}' called with {} argument(s), expected {}",
                                name,
                                arg_types.len(),
                                param_tys.len()
                            ),
                        });
                    } else {
                        let mut call_dim_env: HashMap<String, String> = HashMap::new();
                        for (i, (arg, param)) in arg_types.iter().zip(param_tys.iter()).enumerate() {
                            if !types_compatible(arg, param) {
                                errors.push(TypeError {
                                    function: func_name.to_string(),
                                    message: format!(
                                        "function '{}' arg #{} has type {}, expected {}",
                                        name, i, arg, param
                                    ),
                                });
                            } else if let (Type::Tensor(adims), Type::Tensor(pdims)) = (arg, param) {
                                if !adims.is_empty() && adims.len() == pdims.len() {
                                    for (ad, pd) in adims.iter().zip(pdims.iter()) {
                                        if let Some(bound) = call_dim_env.get(pd) {
                                            if bound != ad {
                                                errors.push(TypeError {
                                                    function: func_name.to_string(),
                                                    message: format!(
                                                        "tensor dimension mismatch in call to '{}': symbolic dim '{}' bound to both '{}' and '{}'",
                                                        name, pd, bound, ad
                                                    ),
                                                });
                                            }
                                        } else {
                                            call_dim_env.insert(pd.clone(), ad.clone());
                                        }
                                    }
                                }
                            }
                        }
                    }
                    ret_ty.as_ref().clone()
                } else {
                    errors.push(TypeError {
                        function: func_name.to_string(),
                        message: format!("'{}' is not a function", name),
                    });
                    Type::Int
                }
            } else {
                errors.push(TypeError {
                    function: func_name.to_string(),
                    message: format!("undefined function '{}'", name),
                });
                Type::Int
            }
        }
        Expr::Echo(_) => Type::Unit,
        Expr::ListLit(elems) => {
            if elems.is_empty() {
                Type::List(Box::new(Type::Int))
            } else {
                let elem_ty = check_expr(&elems[0], func_name, env, errors);
                for elem in elems.iter().skip(1) {
                    let ty = check_expr(elem, func_name, env, errors);
                    if !types_compatible(&ty, &elem_ty) {
                        errors.push(TypeError {
                            function: func_name.to_string(),
                            message: format!(
                                "list elements have mixed types: {} and {}",
                                elem_ty, ty
                            ),
                        });
                    }
                }
                Type::List(Box::new(elem_ty))
            }
        }
        Expr::ListEmpty => Type::List(Box::new(Type::TypeVar("_empty".to_string()))),
        Expr::TupleLit(elems) => {
            let tys: Vec<Type> = elems.iter().map(|e| check_expr(e, func_name, env, errors)).collect();
            Type::Tuple(tys)
        }
        Expr::TensorLit(elems) => {
            for e in elems {
                let _ = check_expr(e, func_name, env, errors);
            }
            Type::Tensor(Vec::new())
        }
        Expr::Index(base, indices) => {
            let _ = check_expr(base, func_name, env, errors);
            for i in indices {
                let _ = check_expr(i, func_name, env, errors);
            }
            Type::Int
        }
        Expr::IndexAssign(_, indices, val) => {
            for i in indices {
                let _ = check_expr(i, func_name, env, errors);
            }
            let _ = check_expr(val, func_name, env, errors);
            Type::Unit
        }
        Expr::Where(body, bindings) => {
            env.push_scope();
            for b in bindings {
                let bty = check_expr(&b.expr, func_name, env, errors);
                if b.index_target.is_none() {
                    env.insert_local(b.target_var.clone(), bty);
                }
            }
            let rty = check_expr(body, func_name, env, errors);
            env.pop_scope();
            rty
        }
        Expr::ParPipe(branches) => {
            let tys: Vec<Type> = branches.iter().map(|b| check_expr(b, func_name, env, errors)).collect();
            Type::Tuple(tys)
        }
        Expr::SeqSelect(base, mask) => {
            let _ = check_expr(base, func_name, env, errors);
            let plus_count = mask.chars().filter(|&c| c == '+').count();
            let idx_count = if plus_count == 0 {
                mask.split_whitespace().count()
            } else {
                plus_count
            };
            if idx_count > 1 {
                Type::TypeVar("_seq".to_string())
            } else {
                Type::Int
            }
        }
        Expr::Block(stmts) => {
            env.push_scope();
            let mut result_ty = Type::Unit;
            for stmt in stmts {
                match stmt {
                    Statement::Let(name, value) => {
                        let ty = check_expr(value, func_name, env, errors);
                        if let Some((base, _)) = crate::parser::Parser::extract_subscript_pub(name) {
                            env.insert_local(base, ty.clone());
                        }
                        env.insert_local(name.clone(), ty);
                    }
                    Statement::Expr(e) => {
                        result_ty = check_expr(e, func_name, env, errors);
                    }
                }
            }
            env.pop_scope();
            result_ty
        }
    }
}

fn check_binop(
    op: &BinOp,
    left: &Type,
    right: &Type,
    env: &TypeEnv,
    func_name: &str,
    errors: &mut Vec<TypeError>,
) -> Type {
    match op {
        BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::Div | BinOp::Mod => {
            let is_poly = |t: &Type| matches!(t, Type::TypeVar(s) if s.chars().next().map(|c| c.is_ascii_lowercase()).unwrap_or(false));
            if (left == &Type::Int || is_poly(left)) && (right == &Type::Int || is_poly(right)) {
                return Type::Int;
            }
            if (left == &Type::Real || is_poly(left)) && (right == &Type::Real || is_poly(right)) {
                return Type::Real;
            }
            if *op == BinOp::Add && (left == &Type::String || is_poly(left)) && (right == &Type::String || is_poly(right)) {
                return Type::String;
            }
            if let (Type::Tensor(d1), Type::Tensor(_)) = (left, right) {
                return Type::Tensor(d1.clone());
            }
            let sym = match op {
                BinOp::Add => "+",
                BinOp::Sub => "-",
                BinOp::Mul => "*",
                BinOp::Div => "/",
                BinOp::Mod => "%",
                _ => "",
            };
            if let Some(Type::Fun(params, ret)) = env.lookup_function(sym) {
                if params.len() == 2 && types_compatible(left, &params[0]) && types_compatible(right, &params[1]) {
                    return ret.as_ref().clone();
                }
            }
            errors.push(TypeError {
                function: func_name.to_string(),
                message: format!(
                    "arithmetic operator {:?} requires numeric or overloaded operands, got {} and {}",
                    op, left, right
                ),
            });
            Type::Int
        }
        BinOp::MatMul => {
            if let (Type::Tensor(d1), Type::Tensor(d2)) = (left, right) {
                if d1.len() == 2 && d2.len() == 2 && d1[1] != d2[0] {
                    errors.push(TypeError {
                        function: func_name.to_string(),
                        message: format!(
                            "tensor contraction dimension mismatch: {} vs {}",
                            d1[1], d2[0]
                        ),
                    });
                }
                if d1.len() == 2 && d2.len() == 2 {
                    return Type::Tensor(vec![d1[0].clone(), d2[1].clone()]);
                }
            }
            Type::Tensor(Vec::new())
        }
        BinOp::Eq | BinOp::Neq => {
            if !types_compatible(left, right) {
                errors.push(TypeError {
                    function: func_name.to_string(),
                    message: format!(
                        "equality comparison requires compatible types, got {} and {}",
                        left, right
                    ),
                });
            }
            Type::Bool
        }
        BinOp::Gt | BinOp::Lt | BinOp::GtEq | BinOp::LtEq => {
            let valid = (left == &Type::Int && right == &Type::Int)
                || (left == &Type::Real && right == &Type::Real)
                || (left == &Type::Char && right == &Type::Char);
            if !valid {
                errors.push(TypeError {
                    function: func_name.to_string(),
                    message: format!(
                        "comparison operator {:?} requires numeric operands, got {} and {}",
                        op, left, right
                    ),
                });
            }
            Type::Bool
        }
        BinOp::And | BinOp::Or | BinOp::Xor => {
            if left != &Type::Bool || right != &Type::Bool {
                errors.push(TypeError {
                    function: func_name.to_string(),
                    message: format!(
                        "logical operator {:?} requires Bool operands, got {} and {}",
                        op, left, right
                    ),
                });
            }
            Type::Bool
        }
        BinOp::FlatJoin => Type::TypeVar("_seq".to_string()),
        BinOp::Concat => match (left, right) {
            (Type::List(l_elem), Type::List(r_elem)) => {
                if l_elem.as_ref() == &Type::TypeVar("_empty".to_string()) {
                    return Type::List(r_elem.clone());
                }
                if r_elem.as_ref() == &Type::TypeVar("_empty".to_string()) {
                    return Type::List(l_elem.clone());
                }
                if !types_compatible(l_elem, r_elem) {
                    errors.push(TypeError {
                        function: func_name.to_string(),
                        message: format!(
                            "concatenation requires same list element types, got [{}] and [{}]",
                            l_elem, r_elem
                        ),
                    });
                }
                Type::List(l_elem.clone())
            }
            _ => {
                errors.push(TypeError {
                    function: func_name.to_string(),
                    message: format!(
                        "concatenation (::) requires list operands, got {} and {}",
                        left, right
                    ),
                });
                Type::List(Box::new(Type::Int))
            }
        },
    }
}

pub fn typecheck_with_diagnostics(program: &Program) -> Vec<TypeError> {
    match typecheck(program) {
        Ok(()) => Vec::new(),
        Err(errors) => errors,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lexer::Lexer;
    use crate::parser::Parser;

    fn parse_and_check(src: &str) -> Result<(), Vec<TypeError>> {
        let (tokens, spans) = Lexer::new(src).tokenize();
        let program = Parser::new(tokens, spans).parse();
        typecheck(&program)
    }

    #[test]
    fn test_valid_int_addition() {
        assert!(parse_and_check(
            "fn :: add Int Int => Int\nadd a b = a + b"
        ).is_ok());
    }

    #[test]
    fn test_invalid_param_count() {
        let result = parse_and_check(
            "fn :: add Int Int => Int\nadd a = a"
        );
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert_eq!(errors.len(), 1);
    }

    #[test]
    fn test_integer_comparison() {
        assert!(parse_and_check(
            "fn :: cmp Int Int => Bool\ncmp a b = a > b"
        ).is_ok());
    }

    #[test]
    fn test_comparison_wrong_return_type() {
        let result = parse_and_check(
            "fn :: cmp Int Int => Int\ncmp a b = a > b"
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_valid_echo() {
        assert!(parse_and_check(
            "fn :: greet => ()\ngreet = echo \"hello\""
        ).is_ok());
    }

    #[test]
    fn test_echo_wrong_return() {
        let result = parse_and_check(
            "fn :: greet => Int\ngreet = echo \"hello\""
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_list_concat() {
        assert!(parse_and_check(
            "fn :: concat_lists [Int] [Int] => [Int]\nconcat_lists a b = a :: b"
        ).is_ok());
    }

    #[test]
    fn test_non_list_concat() {
        let result = parse_and_check(
            "fn :: bad Int Int => [Int]\nbad a b = a :: b"
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_valid_recursive() {
        assert!(parse_and_check(
            "fn :: fact Int => Int\nfact 0 = 1\nfact n = n * fact (n - 1)"
        ).is_ok());
    }

    #[test]
    fn test_guard_must_be_bool() {
        let result = parse_and_check(
            "fn :: guarded Int => Int\nguarded n\n  | n = 1\n  | otherwise = 2"
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_valid_guard() {
        assert!(parse_and_check(
            "fn :: guarded Int => Int\nguarded n\n  | n > 0 = 1\n  | otherwise = 2"
        ).is_ok());
    }

    #[test]
    fn test_wrong_call_arity() {
        let result = parse_and_check(
            "fn :: add Int Int => Int\nadd a b = a + b\nfn :: main => Int\nmain = add 1"
        );
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors.iter().any(|e| e.message.contains("called with")));
    }

    #[test]
    fn test_undefined_variable() {
        let result = parse_and_check(
            "fn :: main => Int\nmain = x"
        );
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors.iter().any(|e| e.message.contains("undefined variable")));
    }

    #[test]
    fn test_valid_let_binding() {
        assert!(parse_and_check(
            "fn :: main => Int\nmain =\n  x = 1\n  y = 2\n  x + y"
        ).is_ok());
    }

    #[test]
    fn test_list_literal() {
        assert!(parse_and_check(
            "fn :: make_list => [Int]\nmake_list = [1, 2, 3]"
        ).is_ok());
    }

    #[test]
    fn test_empty_program() {
        let (tokens, spans) = Lexer::new("").tokenize();
        let program = Parser::new(tokens, spans).parse();
        assert!(typecheck(&program).is_ok());
    }

    #[test]
    fn test_unit_return() {
        assert!(parse_and_check(
            "fn :: noop => ()\nnoop = ()"
        ).is_ok());
    }

    #[test]
    fn test_mixed_arithmetic_types() {
        let result = parse_and_check(
            "fn :: bad Int String => Int\nbad a b = a + b"
        );
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors.iter().any(|e| e.message.contains("arithmetic")));
    }

    #[test]
    fn test_wrong_call_arg_type() {
        let result = parse_and_check(
            "fn :: add Int Int => Int\nadd a b = a + b\nfn :: main => Int\nmain = add \"hello\" 1"
        );
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors.iter().any(|e| e.message.contains("arg")));
    }

    #[test]
    fn test_undefined_function_call() {
        let result = parse_and_check(
            "fn :: main => Int\nmain = nonexistent 1"
        );
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors.iter().any(|e| e.message.contains("undefined function")));
    }

    #[test]
    fn test_fibonacci() {
        assert!(parse_and_check(
            "fn :: fib Int => Int\nfib 0 = 0\nfib 1 = 1\nfib n = fib (n - 1) + fib (n - 2)"
        ).is_ok());
    }

    #[test]
    fn test_list_sum() {
        assert!(parse_and_check(
            "fn :: sum_list [Int] => Int\nsum_list [] = 0\nsum_list (x:rest) = x + sum_list rest"
        ).is_ok());
    }

    // ── New tests for Generics and Type Inference ──

    #[test]
    fn test_generic_type_var_parsing() {
        // Type variables starting with lowercase should be parsed as TypeVar
        let int_ty = parse_type_string("Int");
        assert_eq!(int_ty, Type::Int);

        let typevar = parse_type_string("a");
        assert_eq!(typevar, Type::TypeVar("a".to_string()));

        let list_of_typevar = parse_type_string("[a]");
        assert_eq!(list_of_typevar, Type::List(Box::new(Type::TypeVar("a".to_string()))));
    }

    #[test]
    fn test_unification_basic() {
        // Concrete types unify with themselves
        assert!(unify(&Type::Int, &Type::Int));
        assert!(unify(&Type::String, &Type::String));
        assert!(unify(&Type::Bool, &Type::Bool));

        // Different concrete types don't unify
        assert!(!unify(&Type::Int, &Type::String));
        assert!(!unify(&Type::Bool, &Type::Int));
    }

    #[test]
    fn test_unification_with_type_vars() {
        // Type variables unify with anything
        assert!(unify(&Type::TypeVar("a".to_string()), &Type::Int));
        assert!(unify(&Type::TypeVar("a".to_string()), &Type::String));
        assert!(unify(&Type::TypeVar("a".to_string()), &Type::Bool));
        assert!(unify(&Type::Int, &Type::TypeVar("a".to_string())));
    }

    #[test]
    fn test_unification_lists() {
        // Lists unify if their elements unify
        assert!(unify(&Type::List(Box::new(Type::Int)), &Type::List(Box::new(Type::Int))));
        assert!(unify(&Type::List(Box::new(Type::TypeVar("a".to_string()))), &Type::List(Box::new(Type::Int))));
        
        // Different element types don't unify (without type vars)
        assert!(!unify(&Type::List(Box::new(Type::Int)), &Type::List(Box::new(Type::String))));
    }

    #[test]
    fn test_unification_tuples() {
        // Tuple type support
        let t1 = Type::Tuple(vec![Type::Int, Type::String]);
        let t2 = Type::Tuple(vec![Type::Int, Type::String]);
        assert!(unify(&t1, &t2));

        let t3 = Type::Tuple(vec![Type::Int, Type::Bool]);
        assert!(!unify(&t1, &t3));

        // Different arity tuples don't unify
        let t4 = Type::Tuple(vec![Type::Int]);
        assert!(!unify(&t1, &t4));
    }

    #[test]
    fn test_unification_functions() {
        let f1 = Type::Fun(vec![Type::Int, Type::String], Box::new(Type::Bool));
        let f2 = Type::Fun(vec![Type::Int, Type::String], Box::new(Type::Bool));
        assert!(unify(&f1, &f2));

        // Different function types
        let f3 = Type::Fun(vec![Type::Int], Box::new(Type::Bool));
        assert!(!unify(&f1, &f3));
    }

    #[test]
    fn test_tuple_syntax_parsing() {
        let tuple = parse_type_string("(Int, String)");
        assert_eq!(tuple, Type::Tuple(vec![Type::Int, Type::String]));

        let triple = parse_type_string("(Int, String, Bool)");
        assert_eq!(triple, Type::Tuple(vec![Type::Int, Type::String, Type::Bool]));

        let unit = parse_type_string("()");
        assert_eq!(unit, Type::Unit);
    }
}
