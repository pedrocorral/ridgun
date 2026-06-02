/// Ridgun VM — Stack machine executing bytecoded programs

use std::fmt;
use crate::compiler::{CompiledProgram, Instruction};

// ── Value type ────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Int(i64),
    Str(String),
    Bool(bool),
    Unit,
    List(Vec<Value>),
}

impl fmt::Display for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Value::Int(n) => write!(f, "{}", n),
            Value::Str(s) => write!(f, "{}", s),
            Value::Bool(b) => write!(f, "{}", if *b { "True" } else { "False" }),
            Value::Unit => write!(f, "()"),
            Value::List(items) => {
                let strs: Vec<String> = items.iter().map(|v| format!("{}", v)).collect();
                write!(f, "[{}]", strs.join(", "))
            }
        }
    }
}

impl Value {
    pub fn as_int(&self) -> i64 {
        match self {
            Value::Int(n) => *n,
            other => panic!("Expected Int, got {:?}", other),
        }
    }

    pub fn as_bool(&self) -> bool {
        match self {
            Value::Bool(b) => *b,
            other => panic!("Expected Bool, got {:?}", other),
        }
    }
}

// ── Call frame ────────────────────────────────────────────

pub struct CallFrame {
    pub function: String,
    pub ip: usize,
    pub locals: Vec<Value>,
}

// ── VM ────────────────────────────────────────────────────

pub struct VM {
    stack: Vec<Value>,
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
    pub fn call(&mut self, name: &str, args: &[Value]) -> Value {
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

    /// Convenience: call with i64 args (backward compat)
    pub fn call_ints(&mut self, name: &str, args: &[i64]) -> Value {
        let val_args: Vec<Value> = args.iter().map(|n| Value::Int(*n)).collect();
        self.call(name, &val_args)
    }

    fn run(&mut self) -> Value {
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
                    self.stack.push(Value::Int(n));
                }

                Instruction::PushString(s) => {
                    self.stack.push(Value::Str(s));
                }

                Instruction::PushBool(b) => {
                    self.stack.push(Value::Bool(b));
                }

                Instruction::PushUnit => {
                    self.stack.push(Value::Unit);
                }

                Instruction::LoadLocal(idx) => {
                    let val = self.call_stack.last().unwrap().locals[idx].clone();
                    self.stack.push(val);
                }

                Instruction::StoreLocal(idx) => {
                    let val = self.stack.pop().expect("Stack underflow on StoreLocal");
                    let locals = &mut self.call_stack.last_mut().unwrap().locals;
                    // Grow locals vector if needed
                    while locals.len() <= idx {
                        locals.push(Value::Unit);
                    }
                    locals[idx] = val;
                }

                Instruction::Pop => {
                    self.stack.pop().expect("Stack underflow on Pop");
                }

                Instruction::Add => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(Value::Int(a.as_int() + b.as_int()));
                }

                Instruction::Sub => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(Value::Int(a.as_int() - b.as_int()));
                }

                Instruction::Mul => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(Value::Int(a.as_int() * b.as_int()));
                }

                Instruction::Div => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(Value::Int(a.as_int() / b.as_int()));
                }

                Instruction::CmpEq => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(Value::Bool(a == b));
                }

                Instruction::CmpGt => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(Value::Bool(a.as_int() > b.as_int()));
                }

                Instruction::CmpLt => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(Value::Bool(a.as_int() < b.as_int()));
                }

                Instruction::CmpGtEq => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(Value::Bool(a.as_int() >= b.as_int()));
                }

                Instruction::CmpLtEq => {
                    let b = self.stack.pop().expect("Stack underflow");
                    let a = self.stack.pop().expect("Stack underflow");
                    self.stack.push(Value::Bool(a.as_int() <= b.as_int()));
                }

                Instruction::PushListEmpty => {
                    self.stack.push(Value::List(Vec::new()));
                }

                Instruction::PushListConcat(n) => {
                    let mut result = Vec::new();
                    let start = self.stack.len() - n;
                    for i in (start..self.stack.len()).rev() {
                        match self.stack[i].clone() {
                            Value::List(items) => {
                                result.splice(0..0, items);
                            }
                            val => result.insert(0, val),
                        }
                    }
                    self.stack.truncate(start);
                    self.stack.push(Value::List(result));
                }

                Instruction::SeqSelectHead => {
                    let list = self.stack.pop().expect("Stack underflow");
                    match list {
                        Value::List(items) => {
                            if let Some(first) = items.into_iter().next() {
                                self.stack.push(first);
                            } else {
                                self.stack.push(Value::Unit);
                            }
                        }
                        other => self.stack.push(other),
                    }
                }

                Instruction::SeqSelectRange(start, end) => {
                    let list = self.stack.pop().expect("Stack underflow");
                    match list {
                        Value::List(items) => {
                            if start <= items.len() {
                                let selected: Vec<Value> = items.into_iter()
                                    .enumerate()
                                    .filter(|(i, _)| *i >= start && *i <= end)
                                    .map(|(_, v)| v)
                                    .collect();
                                self.stack.push(Value::List(selected));
                            } else {
                                self.stack.push(Value::Unit);
                            }
                        }
                        other => self.stack.push(other),
                    }
                }

                Instruction::Echo(argc) => {
                    let mut parts: Vec<String> = Vec::new();
                    // Collect args from stack (they're pushed left-to-right)
                    let start = self.stack.len() - argc;
                    for i in start..self.stack.len() {
                        parts.push(format!("{}", self.stack[i]));
                    }
                    self.stack.truncate(start);
                    println!("{}", parts.join(" "));
                    self.stack.push(Value::Unit);
                }

                Instruction::Call(name, argc) => {
                    let mut args = vec![Value::Unit; argc];
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

                Instruction::JumpIfFalse(target) => {
                    let val = self.stack.pop().expect("Stack underflow");
                    if !val.as_bool() {
                        self.call_stack.last_mut().unwrap().ip = target;
                    }
                }

                Instruction::Jump(target) => {
                    self.call_stack.last_mut().unwrap().ip = target;
                }

                Instruction::Spawn => {
                    self.stack.push(Value::Int(0));
                }

                Instruction::Send(_mailbox_id) => {
                    let _val = self.stack.pop().expect("Stack underflow on Send");
                    self.stack.push(Value::Bool(true));
                }

                Instruction::Recv(_mailbox_id) => {
                    self.stack.push(Value::Unit);
                }

                Instruction::Join => {
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

    fn run(src: &str, func: &str, args: &[i64]) -> Value {
        let (tokens, spans) = Lexer::new(src).tokenize();
        let program = Parser::new(tokens, spans).parse();
        let compiled = compiler::compile(&program);
        VM::new(compiled).call_ints(func, args)
    }

    #[test]
    fn test_sum() {
        let result = run(
            "fn :: sum Int Int => Int\nsum a b = a + b",
            "sum", &[3, 4],
        );
        assert_eq!(result, Value::Int(7));
    }

    #[test]
    fn test_factorial() {
        let src = "fn :: factorial Int => Int\n\
                   factorial 0 = 1\n\
                   factorial n = n * factorial (n - 1)";
        assert_eq!(run(src, "factorial", &[0]), Value::Int(1));
        assert_eq!(run(src, "factorial", &[1]), Value::Int(1));
        assert_eq!(run(src, "factorial", &[5]), Value::Int(120));
        assert_eq!(run(src, "factorial", &[10]), Value::Int(3628800));
    }

    #[test]
    fn test_fib() {
        let src = "fn :: fib Int => Int\n\
                   fib 0 = 0\n\
                   fib 1 = 1\n\
                   fib n = fib (n - 1) + fib (n - 2)";
        assert_eq!(run(src, "fib", &[0]), Value::Int(0));
        assert_eq!(run(src, "fib", &[1]), Value::Int(1));
        assert_eq!(run(src, "fib", &[5]), Value::Int(5));
        assert_eq!(run(src, "fib", &[10]), Value::Int(55));
    }
}
