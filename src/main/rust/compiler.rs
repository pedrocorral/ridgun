/// Ridgun Compiler — AST to bytecode

use std::collections::HashMap;
use crate::parser::{Program, FnDef, Expr, Pattern, BinOp, Statement};

// ── Instruction set ────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum Instruction {
    PushInt(i64),
    PushString(String),
    PushBool(bool),
    PushUnit,
    LoadLocal(usize),
    StoreLocal(usize),
    Pop,
    Add,
    Sub,
    Mul,
    Div,
    CmpEq,
    CmpGt,
    CmpLt,
    CmpGtEq,
    CmpLtEq,
    Echo(usize),        // argument count
    Call(String, usize), // function name, arg count
    Return,
    JumpIfNeq(usize),   // target instruction index
    JumpIfFalse(usize),
    Jump(usize),
}

// ── Compiled output ────────────────────────────────────────

#[derive(Debug)]
pub struct CompiledFunction {
    pub name: String,
    pub arity: usize,
    pub code: Vec<Instruction>,
}

#[derive(Debug)]
pub struct CompiledProgram {
    pub functions: HashMap<String, CompiledFunction>,
}

// ── Compile ────────────────────────────────────────────────

pub fn compile(program: &Program) -> CompiledProgram {
    let mut functions = HashMap::new();

    for fndef in &program.functions {
        let cf = compile_function(fndef);
        functions.insert(cf.name.clone(), cf);
    }

    CompiledProgram { functions }
}

fn compile_function(fndef: &FnDef) -> CompiledFunction {
    let arity = fndef.decl.param_types.len();
    let mut code = Vec::new();

    for case in &fndef.cases {
        // Build local variable map from patterns
        let mut locals: HashMap<String, usize> = HashMap::new();
        let mut jump_patches: Vec<usize> = Vec::new();

        for (arg_idx, pat) in case.patterns.iter().enumerate() {
            match pat {
                Pattern::Lit(value) => {
                    code.push(Instruction::LoadLocal(arg_idx));
                    code.push(Instruction::PushInt(*value));
                    let patch = code.len();
                    code.push(Instruction::JumpIfNeq(0)); // placeholder
                    jump_patches.push(patch);
                }
                Pattern::Var(name) => {
                    locals.insert(name.clone(), arg_idx);
                }
                Pattern::ListEmpty | Pattern::ListCons(_, _) => {
                    todo!("List pattern compilation")
                }
                Pattern::Wildcard => {
                    // Wildcard matches anything — no constraints to emit
                }
                Pattern::SeqBind(name) => {
                    locals.insert(name.clone(), arg_idx);
                }
            }
        }

        if case.guards.is_empty() {
            // No guards — simple body
            compile_expr(&case.body, &locals, &mut code);
            code.push(Instruction::Return);
        } else {
            // Guarded case: | condition = body
            let guard_end_patches: Vec<usize> = Vec::new();
            for (condition, body) in &case.guards {
                compile_expr(condition, &locals, &mut code);
                let false_patch = code.len();
                code.push(Instruction::JumpIfFalse(0)); // placeholder: skip to next guard

                compile_expr(body, &locals, &mut code);
                code.push(Instruction::Return);

                // Patch the JumpIfFalse to point here (past this guard's body)
                let here = code.len();
                code[false_patch] = Instruction::JumpIfFalse(here);
            }
            // If no guard matched, fall through to next case
            for patch in guard_end_patches {
                code[patch] = Instruction::Jump(code.len());
            }
        }

        // Patch pattern-matching jumps to point past this case
        let next = code.len();
        for patch in jump_patches {
            code[patch] = Instruction::JumpIfNeq(next);
        }
    }

    CompiledFunction { name: fndef.name.clone(), arity, code }
}

fn compile_expr(
    expr: &Expr,
    locals: &HashMap<String, usize>,
    code: &mut Vec<Instruction>,
) {
    match expr {
        Expr::IntLit(n) => {
            code.push(Instruction::PushInt(*n));
        }
        Expr::StringLit(s) => {
            code.push(Instruction::PushString(s.clone()));
        }
        Expr::BoolLit(b) => {
            code.push(Instruction::PushBool(*b));
        }
        Expr::Unit => {
            code.push(Instruction::PushUnit);
        }
        Expr::Var(name) => {
            let &idx = locals.get(name)
                .unwrap_or_else(|| panic!("Undefined variable: {}", name));
            code.push(Instruction::LoadLocal(idx));
        }
        Expr::BinOp(op, left, right) => {
            compile_expr(left, locals, code);
            compile_expr(right, locals, code);
            match op {
                BinOp::Add => code.push(Instruction::Add),
                BinOp::Sub => code.push(Instruction::Sub),
                BinOp::Mul => code.push(Instruction::Mul),
                BinOp::Div => code.push(Instruction::Div),
                BinOp::Eq => code.push(Instruction::CmpEq),
                BinOp::Gt => code.push(Instruction::CmpGt),
                BinOp::Lt => code.push(Instruction::CmpLt),
                BinOp::GtEq => code.push(Instruction::CmpGtEq),
                BinOp::LtEq => code.push(Instruction::CmpLtEq),
                BinOp::Concat => todo!("List concatenation compilation"),
            }
        }
        Expr::Call(name, args) => {
            for arg in args {
                compile_expr(arg, locals, code);
            }
            code.push(Instruction::Call(name.clone(), args.len()));
        }
        Expr::Echo(args) => {
            for arg in args {
                compile_expr(arg, locals, code);
            }
            code.push(Instruction::Echo(args.len()));
        }
        Expr::ListLit(_) | Expr::ListEmpty => {
            todo!("List expression compilation")
        }
        Expr::SeqSelect(_, _) => {
            todo!("Seq selector compilation")
        }
        Expr::Block(stmts) => {
            // Compile block: let bindings create new locals, last expr = return value
            let mut block_locals = locals.clone();
            let mut next_local = locals.values().copied().max().map(|n| n + 1).unwrap_or(0);

            for (i, stmt) in stmts.iter().enumerate() {
                match stmt {
                    Statement::Let(name, expr) => {
                        compile_expr(expr, &block_locals, code);
                        // Store result in a new local
                        block_locals.insert(name.clone(), next_local);
                        // We need StoreLocal instruction — for now, use the local index
                        code.push(Instruction::StoreLocal(next_local));
                        next_local += 1;
                    }
                    Statement::Expr(expr) => {
                        compile_expr(expr, &block_locals, code);
                        // If not the last statement, pop the value
                        if i < stmts.len() - 1 {
                            code.push(Instruction::Pop);
                        }
                        // Last expression's value stays on the stack
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lexer::Lexer;
    use crate::parser::Parser;

    fn compile_src(src: &str) -> CompiledProgram {
        let tokens = Lexer::new(src).tokenize();
        let program = Parser::new(tokens).parse();
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
        // Case 0: LOAD 0, PUSH 0, JUMP_IF_NEQ, PUSH 1, RETURN
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
