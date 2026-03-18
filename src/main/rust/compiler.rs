/// Ridgun Compiler — AST to bytecode

use std::collections::HashMap;
use crate::parser::{Program, FnDef, Expr, Pattern, BinOp};

// ── Instruction set ────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum Instruction {
    PushInt(i64),
    LoadLocal(usize),
    Add,
    Sub,
    Mul,
    Call(String, usize),    // function name, arg count
    Return,
    JumpIfNeq(usize),      // target instruction index
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

        // Compile body
        compile_expr(&case.body, &locals, &mut code);
        code.push(Instruction::Return);

        // Patch jumps to point past this case
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
                BinOp::Concat => todo!("List concatenation compilation"),
            }
        }
        Expr::Call(name, args) => {
            for arg in args {
                compile_expr(arg, locals, code);
            }
            code.push(Instruction::Call(name.clone(), args.len()));
        }
        Expr::ListLit(_) | Expr::ListEmpty => {
            todo!("List expression compilation")
        }
        Expr::SeqSelect(_, _) => {
            todo!("Seq selector compilation")
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
}
