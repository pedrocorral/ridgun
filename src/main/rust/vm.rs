/// Ridgun VM — Stack machine with concurrent execution support

use std::collections::HashMap;
use std::fmt;
use crate::compiler::{CompiledProgram, Instruction};
use crate::scheduler::Scheduler;
use crate::mailbox::Mailbox;

// ── Value type ─────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Int(i64),
    Str(String),
    Bool(bool),
    Unit,
    List(Vec<Value>),
    MailboxRef(usize),
    ThreadRef(usize),
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
            Value::MailboxRef(id) => write!(f, "Mailbox({})", id),
            Value::ThreadRef(id) => write!(f, "PID{}", id),
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

// ── Call frame ─────────────────────────────────────────────

#[derive(Clone)]
pub struct CallFrame {
    pub function: String,
    pub ip: usize,
    pub locals: Vec<Value>,
}

// ── Thread state ───────────────────────────────────────────

#[derive(Clone)]
struct ThreadState {
    stack: Vec<Value>,
    call_stack: Vec<CallFrame>,
    mailbox_id: usize,
    blocked: bool,
}

impl ThreadState {
    fn new(mailbox_id: usize) -> Self {
        ThreadState {
            stack: Vec::new(),
            call_stack: Vec::new(),
            mailbox_id,
            blocked: false,
        }
    }

    fn is_done(&self) -> bool {
        self.call_stack.is_empty()
    }
}

// ── VM ─────────────────────────────────────────────────────

pub struct VM {
    program: CompiledProgram,
    threads: Vec<ThreadState>,
    scheduler: Scheduler,
    mailboxes: Vec<Mailbox>,
    thread_to_sched: HashMap<usize, usize>, // VM thread ID -> scheduler thread ID
    next_thread_id: usize,
    main_result: Option<Value>,
}

impl VM {
    pub fn new(program: CompiledProgram) -> Self {
        VM {
            program,
            threads: Vec::new(),
            scheduler: Scheduler::new(),
            mailboxes: Vec::new(),
            thread_to_sched: HashMap::new(),
            next_thread_id: 0,
            main_result: None,
        }
    }

    pub fn call(&mut self, name: &str, args: &[Value]) -> Value {
        let arity = self.program.functions.get(name)
            .unwrap_or_else(|| panic!("Undefined function: {}", name))
            .arity;

        assert_eq!(args.len(), arity,
            "Function '{}' expects {} args, got {}", name, arity, args.len());

        self.spawn_thread(name.to_string(), args.to_vec());
        self.run()
    }

    pub fn call_ints(&mut self, name: &str, args: &[i64]) -> Value {
        let val_args: Vec<Value> = args.iter().map(|n| Value::Int(*n)).collect();
        self.call(name, &val_args)
    }

    fn spawn_thread(&mut self, function: String, locals: Vec<Value>) -> usize {
        let mailbox_id = self.mailboxes.len();
        self.mailboxes.push(Mailbox::new());

        let vm_tid = self.next_thread_id;
        self.next_thread_id += 1;

        let sched_tid = self.scheduler.spawn();
        self.thread_to_sched.insert(vm_tid, sched_tid);

        let mut state = ThreadState::new(mailbox_id);
        state.call_stack.push(CallFrame {
            function,
            ip: 0,
            locals,
        });
        self.threads.push(state);

        vm_tid
    }

    fn run(&mut self) -> Value {
        loop {
            // Process all runnable threads
            let mut made_progress = false;
            
            for vm_tid in 0..self.threads.len() {
                if self.threads[vm_tid].blocked {
                    continue;
                }
                
                if self.threads[vm_tid].is_done() {
                    continue;
                }

                let result = self.step(vm_tid);
                made_progress = true;

                if result {
                    // Thread completed
                    if self.threads[vm_tid].is_done() {
                        // Check if this is main thread
                        if self.threads[vm_tid].call_stack.is_empty() && self.main_result.is_none() {
                            self.main_result = self.threads[vm_tid].stack.last().cloned();
                        }
                    }
                }
            }

            // Process blocked threads waiting for messages
            self.unblock_waiting_threads();

            if !made_progress {
                break;
            }
        }

        self.main_result.take().unwrap_or(Value::Unit)
    }

    fn unblock_waiting_threads(&mut self) {
        for vm_tid in 0..self.threads.len() {
            if !self.threads[vm_tid].blocked {
                continue;
            }

            let mailbox_id = self.threads[vm_tid].mailbox_id;
            if !self.mailboxes[mailbox_id].is_empty() {
                self.threads[vm_tid].blocked = false;
            }
        }
    }

    fn step(&mut self, vm_tid: usize) -> bool {
        let state = &mut self.threads[vm_tid];
        
        if state.is_done() {
            return true;
        }

        let frame = match state.call_stack.last_mut() {
            Some(frame) => frame,
            None => return true,
        };

        let func_name = frame.function.clone();
        let ip = frame.ip;

        let code = match self.program.functions.get(&func_name) {
            Some(func) => &func.code,
            None => {
                eprintln!("Undefined function: {}", func_name);
                return true;
            }
        };

        if ip >= code.len() {
            state.call_stack.pop();
            return true;
        }

        let instr = code[ip].clone();
        frame.ip += 1;

        self.execute(vm_tid, &instr);
        true
    }

    fn execute(&mut self, vm_tid: usize, instr: &Instruction) {
        // Handle Join specially - it needs to read from other threads
        if matches!(instr, Instruction::Join) {
            let mut result_opt: Option<Value> = None;
            let mut target_blocked = false;
            
            {
                let state = &mut self.threads[vm_tid];
                let thread_ref = state.stack.pop().expect("Stack underflow on Join");
                let target_tid = match thread_ref {
                    Value::ThreadRef(id) => id,
                    Value::Int(id) => id as usize,
                    _ => {
                        state.stack.push(Value::Unit);
                        return;
                    }
                };
                
                // Check if target is done
                if target_tid < self.threads.len() {
                    if self.threads[target_tid].is_done() {
                        result_opt = self.threads[target_tid].stack.last().cloned();
                    } else {
                        target_blocked = true;
                    }
                }
            }
            
            // Now apply the result
            let state = &mut self.threads[vm_tid];
            match result_opt {
                Some(val) => state.stack.push(val),
                None if target_blocked => state.blocked = true,
                None => state.stack.push(Value::Unit),
            }
            return;
        }
        
        // For all other instructions, normal execution
        let state = &mut self.threads[vm_tid];
        let mailbox_id = state.mailbox_id;

        match instr {
            Instruction::PushInt(n) => {
                state.stack.push(Value::Int(*n));
            }

            Instruction::PushString(s) => {
                state.stack.push(Value::Str(s.clone()));
            }

            Instruction::PushBool(b) => {
                state.stack.push(Value::Bool(*b));
            }

            Instruction::PushUnit => {
                state.stack.push(Value::Unit);
            }

            Instruction::LoadLocal(idx) => {
                let val = state.call_stack.last_mut().unwrap().locals[*idx].clone();
                state.stack.push(val);
            }

            Instruction::StoreLocal(idx) => {
                let val = state.stack.pop().expect("Stack underflow");
                let locals = &mut state.call_stack.last_mut().unwrap().locals;
                while locals.len() <= *idx {
                    locals.push(Value::Unit);
                }
                locals[*idx] = val;
            }

            Instruction::Pop => {
                state.stack.pop();
            }

            Instruction::Add => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Int(a.as_int() + b.as_int()));
            }

            Instruction::Sub => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Int(a.as_int() - b.as_int()));
            }

            Instruction::Mul => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Int(a.as_int() * b.as_int()));
            }

            Instruction::Div => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Int(a.as_int() / b.as_int()));
            }

            Instruction::CmpEq => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Bool(a == b));
            }

            Instruction::CmpGt => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Bool(a.as_int() > b.as_int()));
            }

            Instruction::CmpLt => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Bool(a.as_int() < b.as_int()));
            }

            Instruction::CmpGtEq => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Bool(a.as_int() >= b.as_int()));
            }

            Instruction::CmpLtEq => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Bool(a.as_int() <= b.as_int()));
            }

            Instruction::PushListEmpty => {
                state.stack.push(Value::List(Vec::new()));
            }

            Instruction::PushListConcat(n) => {
                let mut result = Vec::new();
                let start = state.stack.len() - *n;
                for i in (start..state.stack.len()).rev() {
                    match &state.stack[i] {
                        Value::List(items) => {
                            for item in items.iter().rev() {
                                result.insert(0, item.clone());
                            }
                        }
                        val => result.insert(0, val.clone()),
                    }
                }
                state.stack.truncate(start);
                state.stack.push(Value::List(result));
            }

            Instruction::SeqSelectHead => {
                let list = state.stack.pop().expect("Stack underflow");
                match list {
                    Value::List(items) => {
                        if let Some(first) = items.into_iter().next() {
                            state.stack.push(first);
                        } else {
                            state.stack.push(Value::Unit);
                        }
                    }
                    other => state.stack.push(other),
                }
            }

            Instruction::SeqSelectRange(start, end) => {
                let list = state.stack.pop().expect("Stack underflow");
                match list {
                    Value::List(items) => {
                        let selected: Vec<Value> = items.into_iter()
                            .enumerate()
                            .filter(|(i, _)| *i >= *start && *i <= *end)
                            .map(|(_, v)| v)
                            .collect();
                        state.stack.push(Value::List(selected));
                    }
                    other => state.stack.push(other),
                }
            }

            Instruction::Echo(argc) => {
                let mut parts: Vec<String> = Vec::new();
                let start = state.stack.len() - *argc;
                for i in start..state.stack.len() {
                    parts.push(format!("{}", state.stack[i]));
                }
                state.stack.truncate(start);
                println!("{}", parts.join(" "));
                state.stack.push(Value::Unit);
            }

            Instruction::Call(name, argc) => {
                let mut args = vec![Value::Unit; *argc];
                for i in (0..*argc).rev() {
                    args[i] = state.stack.pop().expect("Stack underflow");
                }

                let arity = self.program.functions.get(name)
                    .unwrap_or_else(|| panic!("Undefined function: {}", name))
                    .arity;
                assert_eq!(args.len(), arity);

                state.call_stack.push(CallFrame {
                    function: name.clone(),
                    ip: 0,
                    locals: args,
                });
            }

            Instruction::Return => {
                state.call_stack.pop();
            }

            Instruction::JumpIfNeq(target) => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                if a != b {
                    state.call_stack.last_mut().unwrap().ip = *target;
                }
            }

            Instruction::JumpIfFalse(target) => {
                let val = state.stack.pop().expect("Stack underflow");
                if !val.as_bool() {
                    state.call_stack.last_mut().unwrap().ip = *target;
                }
            }

            Instruction::Jump(target) => {
                state.call_stack.last_mut().unwrap().ip = *target;
            }

            // ── Concurrency Primitives ─────────────────────

            Instruction::Spawn => {
                // Spawn creates a new thread reference
                let thread_ref = Value::ThreadRef(self.next_thread_id);
                state.stack.push(thread_ref);
            }

            Instruction::Send(_) => {
                // Handle Send specially - it accesses mailboxes
                let (target_mailbox, value_opt) = {
                    let mailbox_val = state.stack.pop().expect("Stack underflow on Send");
                    let value = state.stack.pop().expect("Stack underflow on Send");
                    let target_mailbox = match mailbox_val {
                        Value::MailboxRef(id) => id,
                        Value::ThreadRef(_) => mailbox_id,
                        _ => {
                            eprintln!("Send: invalid mailbox reference");
                            state.stack.push(Value::Bool(false));
                            return;
                        }
                    };
                    (target_mailbox, Some(value))
                };

                let result = {
                    if target_mailbox < self.mailboxes.len() {
                        self.mailboxes[target_mailbox].send(value_opt.unwrap());
                        Value::Bool(true)
                    } else {
                        Value::Bool(false)
                    }
                };
                
                let state = &mut self.threads[vm_tid];
                state.stack.push(result);
            }

            Instruction::Recv(_) => {
                // Handle Recv specially - it accesses mailboxes
                let target_mailbox = {
                    let mailbox_val = state.stack.pop().expect("Stack underflow on Recv");
                    match mailbox_val {
                        Value::MailboxRef(id) => id,
                        Value::ThreadRef(_) => mailbox_id,
                        _ => {
                            state.stack.push(Value::Unit);
                            return;
                        }
                    }
                };

                let (msg_opt, should_block) = {
                    if target_mailbox < self.mailboxes.len() {
                        if self.mailboxes[target_mailbox].is_empty() {
                            (None, true)
                        } else {
                            (self.mailboxes[target_mailbox].recv(), false)
                        }
                    } else {
                        (None, false)
                    }
                };

                let state = &mut self.threads[vm_tid];
                match (msg_opt, should_block) {
                    (Some(msg), _) => state.stack.push(msg),
                    (None, true) => state.blocked = true,
                    (None, false) => state.stack.push(Value::Unit),
                }
            }

            Instruction::Join => {
                // Join handled specially above - this should never be reached
                state.stack.push(Value::Unit);
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

    #[test]
    fn test_list_operations() {
        let src = "fn :: mklist => [Int]\nmklist = [1, 2, 3]";
        let result = run(src, "mklist", &[]);
        assert_eq!(result, Value::List(vec![
            Value::Int(1),
            Value::Int(2),
            Value::Int(3),
        ]));
    }

    #[test]
    fn test_echo_output() {
        let src = "fn :: greet => ()\ngreet = echo \"hello\" \"world\"";
        let result = run(src, "greet", &[]);
        assert_eq!(result, Value::Unit);
    }

    #[test]
    fn test_comparison() {
        let src = "fn :: test => Bool\ntest = 5 > 3 && 2 < 4";
        // Note: && needs to be tested - use Cmp operators
        let src2 = "fn :: test => Bool\ntest = True == True";
        let result = run(src2, "test", &[]);
        assert_eq!(result, Value::Bool(true));
    }
}
