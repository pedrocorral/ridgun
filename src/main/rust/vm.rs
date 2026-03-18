/// Ridgun VM — Stack machine executing bytecoded programs

use crate::compiler::{CompiledProgram, Instruction};

// ── Call frame ─────────────────────────────────────────────

struct CallFrame {
    function: String,
    ip: usize,
    locals: Vec<i64>,
}

// ── VM ─────────────────────────────────────────────────────

pub struct VM {
    stack: Vec<i64>,
    call_stack: Vec<CallFrame>,
    program: CompiledProgram,
}

impl VM {
    pub fn new(program: CompiledProgram) -> Self {
        VM {
            stack: Vec::new(),
            call_stack: Vec::new(),
            program,
        }
    }

    /// Call a function by name with the given arguments, returns the result.
    pub fn call(&mut self, name: &str, args: &[i64]) -> i64 {
        let arity = self.program.functions.get(name)
            .unwrap_or_else(|| panic!("Undefined function: {}", name))
            .arity;

        assert_eq!(args.len(), arity,
            "Function '{}' expects {} args, got {}", name, arity, args.len());

        self.call_stack.push(CallFrame {
            function: name.to_string(),
            ip: 0,
            locals: args.to_vec(),
        });

        self.run()
    }

    fn run(&mut self) -> i64 {
        loop {
            let frame = self.call_stack.last()
                .expect("Call stack empty");
            let func_name = frame.function.clone();
            let ip = frame.ip;

            // Borrow the function code
            let code = &self.program.functions[&func_name].code;

            if ip >= code.len() {
                panic!("IP out of bounds in '{}' (ip={}, len={})",
                    func_name, ip, code.len());
            }

            let instr = code[ip].clone();
            self.call_stack.last_mut().unwrap().ip += 1;

            match instr {
                Instruction::PushInt(n) => {
                    self.stack.push(n);
                }

                Instruction::LoadLocal(idx) => {
                    let val = self.call_stack.last().unwrap().locals[idx];
                    self.stack.push(val);
                }

                Instruction::Add => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(a + b);
                }

                Instruction::Sub => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(a - b);
                }

                Instruction::Mul => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(a * b);
                }

                Instruction::Call(name, argc) => {
                    let mut args = vec![0i64; argc];
                    for i in (0..argc).rev() {
                        args[i] = self.stack.pop().expect("Stack underflow");
                    }

                    let arity = self.program.functions.get(&name)
                        .unwrap_or_else(|| panic!("Undefined function: {}", name))
                        .arity;
                    assert_eq!(args.len(), arity);

                    self.call_stack.push(CallFrame {
                        function: name,
                        ip: 0,
                        locals: args,
                    });
                }

                Instruction::Return => {
                    self.call_stack.pop();
                    if self.call_stack.is_empty() {
                        return self.stack.pop().expect("Stack empty on final return");
                    }
                    // Return value stays on the stack for the caller
                }

                Instruction::JumpIfNeq(target) => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    if a != b {
                        self.call_stack.last_mut().unwrap().ip = target;
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
    use crate::compiler;

    fn run(src: &str, func: &str, args: &[i64]) -> i64 {
        let tokens = Lexer::new(src).tokenize();
        let program = Parser::new(tokens).parse();
        let compiled = compiler::compile(&program);
        VM::new(compiled).call(func, args)
    }

    #[test]
    fn test_sum() {
        let result = run(
            "fn :: sum Int Int => Int\nsum a b = a + b",
            "sum", &[3, 4],
        );
        assert_eq!(result, 7);
    }

    #[test]
    fn test_factorial() {
        let src = "fn :: factorial Int => Int\n\
                   factorial 0 = 1\n\
                   factorial n = n * factorial (n - 1)";
        assert_eq!(run(src, "factorial", &[0]), 1);
        assert_eq!(run(src, "factorial", &[1]), 1);
        assert_eq!(run(src, "factorial", &[5]), 120);
        assert_eq!(run(src, "factorial", &[10]), 3628800);
    }

    #[test]
    fn test_fib() {
        let src = "fn :: fib Int => Int\n\
                   fib 0 = 0\n\
                   fib 1 = 1\n\
                   fib n = fib (n - 1) + fib (n - 2)";
        assert_eq!(run(src, "fib", &[0]), 0);
        assert_eq!(run(src, "fib", &[1]), 1);
        assert_eq!(run(src, "fib", &[5]), 5);
        assert_eq!(run(src, "fib", &[10]), 55);
    }
}
