/// Ridgun Type Checker — validates AST node types against function signatures

use std::collections::HashMap;
use crate::parser::{Expr, Statement, BinOp, Pattern, FnCase, FnDef, Program};

// ── Type System ──

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Type {
    Int,
    String,
    Bool,
    Unit,
    List(Box<Type>),
    Fun(Vec<Type>, Box<Type>),
    // Type variables for generics/inference
    TypeVar(String),
    // Product types (tuples/structs)
    Tuple(Vec<Type>),
}

impl std::fmt::Display for Type {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Type::Int => write!(f, "Int"),
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
    match s {
        "Int" => Type::Int,
        "String" => Type::String,
        "Bool" => Type::Bool,
        "Unit" => Type::Unit,
        "()" => Type::Unit,
        other => {
            // Check for generic type variable (starts with lowercase)
            if other.chars().next().map(|c| c.is_ascii_lowercase()).unwrap_or(false) {
                Type::TypeVar(other.to_string())
            }
            // Check for list type [T]
            else if let Some(inner) = other.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
                Type::List(Box::new(parse_type_string(inner)))
            }
            // Check for tuple type (T1, T2, ...)
            else if other.starts_with('(') && other.ends_with(')') {
                let inner = &other[1..other.len()-1];
                let types: Vec<Type> = inner.split(',')
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .map(parse_type_string)
                    .collect();
                Type::Tuple(types)
            }
            else {
                Type::TypeVar(other.to_string())
            }
        }
    }
}

// ── Type Unification (for type inference) ──

/// Try to unify two types. Returns Ok(true) if unification succeeds, Ok(false) if incompatible, Err if unification would create cycle.
fn unify(t1: &Type, t2: &Type) -> bool {
    match (t1, t2) {
        // Same concrete types
        (Type::Int, Type::Int) |
        (Type::String, Type::String) |
        (Type::Bool, Type::Bool) |
        (Type::Unit, Type::Unit) => true,
        
        // Type variables can unify with any type
        (Type::TypeVar(_), _) | (_, Type::TypeVar(_)) => true,
        
        // List unification
        (Type::List(inner1), Type::List(inner2)) => unify(inner1, inner2),
        
        // Tuple unification
        (Type::Tuple(elems1), Type::Tuple(elems2)) => {
            elems1.len() == elems2.len() && 
            elems1.iter().zip(elems2.iter()).all(|(a, b)| unify(a, b))
        }
        
        // Function unification
        (Type::Fun(params1, ret1), Type::Fun(params2, ret2)) => {
            params1.len() == params2.len() &&
            params1.iter().zip(params2.iter()).all(|(a, b)| unify(a, b)) &&
            unify(ret1, ret2)
        }
        
        _ => false
    }
}

/// Check if two types are compatible (with type variables as wildcards)
pub fn types_compatible(t1: &Type, t2: &Type) -> bool {
    unify(t1, t2)
}

// ── Type Checker ──

pub fn typecheck(program: &Program) -> Result<(), Vec<TypeError>> {
    let mut errors: Vec<TypeError> = Vec::new();
    let mut env = TypeEnv::new();

    for func in &program.functions {
        let param_types: Vec<Type> = func.decl.param_types.iter()
            .map(|s| parse_type_string(s)).collect();
        let return_type = parse_type_string(&func.decl.return_type);
        let sig = Type::Fun(param_types.clone(), Box::new(return_type));
        env.insert_function(func.name.clone(), sig);
    }

    for func in &program.functions {
        check_function(func, &mut env, &mut errors);
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
    let param_types: Vec<Type> = func.decl.param_types.iter()
        .map(|s| parse_type_string(s)).collect();

    for (case_idx, case) in func.cases.iter().enumerate() {
        let has_seq_bind = case.patterns.iter().any(|p| matches!(p, Pattern::SeqBind(_)));
        if case.patterns.len() != decl_param_count && !has_seq_bind {
            errors.push(TypeError {
                function: func.name.clone(),
                message: format!(
                    "case #{} has {} pattern(s), expected {}",
                    case_idx, case.patterns.len(), decl_param_count
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
            // SeqBind binds to Int (sequence handle); skip param type binding
            bind_pattern(pattern, &Type::Int, env);
        } else {
            let expected = if has_seq_bind {
                Type::Int
            } else {
                param_types.get(pat_idx).cloned().unwrap_or(Type::Int)
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
        if body_ty != *return_type {
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
        if body_ty != *return_type {
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
        Pattern::Wildcard | Pattern::Lit(_) | Pattern::NegLit(_) => {}
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
        // Advanced patterns
        Pattern::Tuple(pats) => {
            if let Type::Tuple(types) = expected_type {
                for (i, pat) in pats.iter().enumerate() {
                    let ptype = types.get(i).unwrap_or(&Type::Int);
                    bind_pattern(pat, ptype, env);
                }
            }
        }
        Pattern::Constructor(_, args) => {
            // For constructor patterns, bind variables in arguments
            for arg in args {
                bind_pattern(arg, &Type::Int, env);
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
        Expr::StringLit(_) => Type::String,
        Expr::BoolLit(_) => Type::Bool,
        Expr::Unit => Type::Unit,
        Expr::Var(name) => {
            if let Some(ty) = env.lookup_local(name) {
                ty.clone()
            } else if let Some(ty) = env.lookup_function(name) {
                ty.clone()
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
            check_binop(op, &left_ty, &right_ty, func_name, errors)
        }
        Expr::Call(name, args) => {
            let arg_types: Vec<Type> = args.iter()
                .map(|a| check_expr(a, func_name, env, errors)).collect();

            if let Some(fun_ty) = env.lookup_function(name) {
                if let Type::Fun(param_tys, ret_ty) = fun_ty {
                    if arg_types.len() != param_tys.len() {
                        errors.push(TypeError {
                            function: func_name.to_string(),
                            message: format!(
                                "function '{}' called with {} argument(s), expected {}",
                                name, arg_types.len(), param_tys.len()
                            ),
                        });
                    } else {
                        for (i, (arg, param)) in arg_types.iter().zip(param_tys.iter()).enumerate() {
                            if arg != param {
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
                    if ty != elem_ty {
                        errors.push(TypeError {
                            function: func_name.to_string(),
                            message: format!(
                                "list elements have mixed types: {} and {}",
                                elem_ty, elem_ty
                            ),
                        });
                    }
                }
                Type::List(Box::new(elem_ty))
            }
        }
        Expr::ListEmpty => Type::List(Box::new(Type::Int)),
        Expr::SeqSelect(base, _) => {
            let _ = check_expr(base, func_name, env, errors);
            Type::Int
        }
        Expr::Block(stmts) => {
            env.push_scope();
            let mut result_ty = Type::Unit;
            for stmt in stmts {
                match stmt {
                    Statement::Let(name, value) => {
                        let ty = check_expr(value, func_name, env, errors);
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
    func_name: &str,
    errors: &mut Vec<TypeError>,
) -> Type {
    match op {
        BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::Div => {
            if left != &Type::Int || right != &Type::Int {
                errors.push(TypeError {
                    function: func_name.to_string(),
                    message: format!(
                        "arithmetic operator {:?} requires Int operands, got {} and {}",
                        op, left, right
                    ),
                });
            }
            Type::Int
        }
        BinOp::Eq => {
            if left != right {
                errors.push(TypeError {
                    function: func_name.to_string(),
                    message: format!(
                        "equality comparison requires same types, got {} and {}",
                        left, right
                    ),
                });
            }
            Type::Bool
        }
        BinOp::Gt | BinOp::Lt | BinOp::GtEq | BinOp::LtEq => {
            if left != &Type::Int || right != &Type::Int {
                errors.push(TypeError {
                    function: func_name.to_string(),
                    message: format!(
                        "comparison operator {:?} requires Int operands, got {} and {}",
                        op, left, right
                    ),
                });
            }
            Type::Bool
        }
        BinOp::Concat => {
            match (left, right) {
                (Type::List(l_elem), Type::List(r_elem)) => {
                    if l_elem != r_elem {
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
            }
        }
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
