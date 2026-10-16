/// Ridgun VM — Stack machine with Lexical Region Memory, DAG Latches, Typed Channels,
/// and Deterministic (`--seed`) Green-Thread Scheduling.

use std::collections::HashMap;
use std::fmt;
use crate::channel::{Channel, RecvStatus, SendStatus};
use crate::compiler::{CompiledProgram, Instruction};
use crate::mailbox::Mailbox;
use crate::region::Region;
use crate::scheduler::Scheduler;

// ── Value type ─────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Int(i64),
    Real(f64),
    Char(char),
    Str(String),
    Bool(bool),
    Unit,
    List(Vec<Value>),
    Tuple(Vec<Value>),
    Adt(String, Vec<Value>),
    Tensor(Vec<usize>, Vec<f64>),
    MailboxRef(usize),
    ThreadRef(usize),
    ChannelRef(usize),
}

impl fmt::Display for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Value::Int(n) => write!(f, "{}", n),
            Value::Real(r) => {
                if r.fract() == 0.0 {
                    write!(f, "{:.1}", r)
                } else {
                    write!(f, "{}", r)
                }
            }
            Value::Char(c) => write!(f, "{}", c),
            Value::Str(s) => write!(f, "{}", s),
            Value::Bool(b) => write!(f, "{}", if *b { "True" } else { "False" }),
            Value::Unit => write!(f, "()"),
            Value::List(items) => {
                let strs: Vec<String> = items.iter().map(|v| format!("{}", v)).collect();
                write!(f, "[{}]", strs.join(", "))
            }
            Value::Tuple(items) => {
                let strs: Vec<String> = items.iter().map(|v| format!("{}", v)).collect();
                write!(f, "({})", strs.join(", "))
            }
            Value::Adt(ctor, fields) => {
                if fields.is_empty() {
                    write!(f, "{}", ctor)
                } else {
                    let strs: Vec<String> = fields.iter().map(|v| format!("{}", v)).collect();
                    write!(f, "({} {})", ctor, strs.join(" "))
                }
            }
            Value::Tensor(shape, data) => {
                write!(f, "Tensor(shape={:?}, data={:?})", shape, data)
            }
            Value::MailboxRef(id) => write!(f, "Mailbox({})", id),
            Value::ThreadRef(id) => write!(f, "PID{}", id),
            Value::ChannelRef(id) => write!(f, "Channel({})", id),
        }
    }
}

impl Value {
    pub fn as_int(&self) -> i64 {
        match self {
            Value::Int(n) => *n,
            Value::Real(r) => *r as i64,
            other => panic!("Expected Int, got {:?}", other),
        }
    }

    pub fn as_real(&self) -> f64 {
        match self {
            Value::Real(r) => *r,
            Value::Int(n) => *n as f64,
            other => panic!("Expected Real or Int, got {:?}", other),
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
    pub region_watermark: (usize, usize),
}

// ── Thread state ───────────────────────────────────────────

#[derive(Clone)]
struct ThreadState {
    stack: Vec<Value>,
    call_stack: Vec<CallFrame>,
    mailbox_id: usize,
    blocked: bool,
    region: Region,
    latches: Vec<usize>,
    context_env: HashMap<String, Vec<Value>>,
    pending_stage_tasks: Vec<(usize, Option<usize>)>,
    region_limit_stack: Vec<(usize, bool)>,
    timeout_ticks: usize,
}

impl ThreadState {
    fn new(tid: usize, mailbox_id: usize) -> Self {
        ThreadState {
            stack: Vec::new(),
            call_stack: Vec::new(),
            mailbox_id,
            blocked: false,
            region: Region::new(tid, None),
            latches: Vec::new(),
            context_env: HashMap::new(),
            pending_stage_tasks: Vec::new(),
            region_limit_stack: Vec::new(),
            timeout_ticks: 0,
        }
    }

    fn is_done(&self) -> bool {
        self.call_stack.is_empty()
    }

    fn record_alloc(&mut self, val: Value) {
        if self.region.alloc_value(val).is_err() {
            if let Some((_, ref mut oom)) = self.region_limit_stack.last_mut() {
                *oom = true;
            }
        }
    }
}

// ── VM ─────────────────────────────────────────────────────

pub struct VM {
    program: CompiledProgram,
    threads: Vec<ThreadState>,
    scheduler: Scheduler,
    mailboxes: Vec<Mailbox>,
    channels: Vec<Channel>,
    shared_globals: HashMap<String, Value>,
    thread_to_sched: HashMap<usize, usize>,
    next_thread_id: usize,
    main_result: Option<Value>,
    completed_latches: usize,
}

impl VM {
    pub fn new(program: CompiledProgram) -> Self {
        VM {
            program,
            threads: Vec::new(),
            scheduler: Scheduler::new(),
            mailboxes: Vec::new(),
            channels: Vec::new(),
            shared_globals: HashMap::new(),
            thread_to_sched: HashMap::new(),
            next_thread_id: 0,
            main_result: None,
            completed_latches: 0,
        }
    }

    /// Create a VM in deterministic simulation mode (`--seed <u64>`, Section 9).
    pub fn with_seed(program: CompiledProgram, seed: u64) -> Self {
        let mut vm = Self::new(program);
        vm.scheduler = Scheduler::with_seed(seed);
        vm
    }

    /// Total number of `where` / `||` DAG countdown latches completed.
    pub fn completed_latches(&self) -> usize {
        self.completed_latches
    }

    /// Return the used region bytes of the main thread (0 after top-level return reset).
    pub fn main_region_used_bytes(&self) -> usize {
        self.threads.first().map(|t| t.region.used_bytes()).unwrap_or(0)
    }

    pub fn call(&mut self, name: &str, args: &[Value]) -> Value {
        let func = self
            .program
            .functions
            .get(name)
            .unwrap_or_else(|| panic!("Undefined function: {}", name));
        if !func.is_variadic {
            assert_eq!(
                args.len(),
                func.arity,
                "Function '{}' expects {} args, got {}",
                name,
                func.arity,
                args.len()
            );
        }

        let entry_tid = self.spawn_thread_with_context(name.to_string(), args.to_vec(), HashMap::new());
        self.run(entry_tid)
    }

    pub fn call_ints(&mut self, name: &str, args: &[i64]) -> Value {
        let val_args: Vec<Value> = args.iter().map(|n| Value::Int(*n)).collect();
        self.call(name, &val_args)
    }

    fn spawn_thread_with_context(
        &mut self,
        function: String,
        locals: Vec<Value>,
        inherited_ctx: HashMap<String, Vec<Value>>,
    ) -> usize {
        let mailbox_id = self.mailboxes.len();
        self.mailboxes.push(Mailbox::new());

        let vm_tid = self.next_thread_id;
        self.next_thread_id += 1;

        let sched_tid = self.scheduler.spawn();
        self.thread_to_sched.insert(vm_tid, sched_tid);

        let mut state = ThreadState::new(vm_tid, mailbox_id);
        state.context_env = inherited_ctx;
        let wm = state.region.watermark();
        state.call_stack.push(CallFrame {
            function,
            ip: 0,
            locals,
            region_watermark: wm,
        });
        self.threads.push(state);

        vm_tid
    }

    fn run(&mut self, entry_tid: usize) -> Value {
        loop {
            let mut made_progress = false;

            while let Some((sched_tid, _)) = self.scheduler.next_thread() {
                let vm_tid = sched_tid;
                if vm_tid >= self.threads.len()
                    || self.threads[vm_tid].blocked
                    || self.threads[vm_tid].is_done()
                {
                    self.scheduler.kill(sched_tid);
                    continue;
                }

                loop {
                    self.step(vm_tid);
                    made_progress = true;

                    if self.threads[vm_tid].is_done() {
                        if vm_tid == entry_tid && self.main_result.is_none() {
                            self.main_result = self.threads[vm_tid].stack.last().cloned();
                        }
                        self.scheduler.kill(sched_tid);
                        break;
                    }
                    if self.threads[vm_tid].blocked {
                        self.scheduler.block_thread(sched_tid);
                        break;
                    }
                    if self.scheduler.tick_reduction() {
                        self.scheduler.yield_thread();
                        break;
                    }
                }
            }

            if self.unblock_waiting_threads() {
                made_progress = true;
            }

            if !made_progress {
                break;
            }
        }

        self.main_result.take().unwrap_or(Value::Unit)
    }

    fn unblock_waiting_threads(&mut self) -> bool {
        let mut any_unblocked = false;
        for vm_tid in 0..self.threads.len() {
            if !self.threads[vm_tid].blocked {
                continue;
            }
            let mailbox_id = self.threads[vm_tid].mailbox_id;
            let mut should_unblock = !self.mailboxes[mailbox_id].is_empty();
            if !should_unblock && !self.threads[vm_tid].pending_stage_tasks.is_empty() {
                let all_children_done = self.threads[vm_tid]
                    .pending_stage_tasks
                    .iter()
                    .all(|(child_tid, _)| *child_tid < self.threads.len() && self.threads[*child_tid].is_done());
                if all_children_done {
                    should_unblock = true;
                }
            }
            if !should_unblock && self.threads[vm_tid].timeout_ticks > 0 {
                self.threads[vm_tid].timeout_ticks -= 1;
                if self.threads[vm_tid].timeout_ticks == 0 {
                    should_unblock = true;
                }
            }
            if !should_unblock {
                if let Some(Value::ThreadRef(target_tid)) = self.threads[vm_tid].stack.last() {
                    if *target_tid < self.threads.len() && self.threads[*target_tid].is_done() {
                        should_unblock = true;
                    }
                }
            }
            if should_unblock {
                self.threads[vm_tid].blocked = false;
                self.scheduler.unblock(vm_tid);
                any_unblocked = true;
            }
        }
        any_unblocked
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
            let popped = state.call_stack.pop().unwrap();
            let _ = state.region.reset_to(popped.region_watermark, vm_tid);
            return true;
        }

        let instr = code[ip].clone();
        frame.ip += 1;

        self.execute(vm_tid, &instr);
        true
    }

    fn execute(&mut self, vm_tid: usize, instr: &Instruction) {
        if self.try_execute_concurrency(vm_tid, instr) {
            return;
        }
        if self.try_execute_collection(vm_tid, instr) {
            return;
        }
        self.execute_core(vm_tid, instr);
    }

    fn dispatch_binary_op(&mut self, vm_tid: usize, sym: &str) {
        let state = &mut self.threads[vm_tid];
        let b = state.stack.pop().expect("Stack underflow");
        let a = state.stack.pop().expect("Stack underflow");

        if matches!((&a, &b), (Value::Adt(..), Value::Adt(..))) {
            if self.program.functions.contains_key(sym) {
                let wm = state.region.watermark();
                state.call_stack.push(CallFrame {
                    function: sym.to_string(),
                    ip: 0,
                    locals: vec![a, b],
                    region_watermark: wm,
                });
                return;
            }
        }

        if let (Value::Tensor(s1, d1), Value::Tensor(_, d2)) = (&a, &b) {
            let out: Vec<f64> = d1
                .iter()
                .zip(d2.iter())
                .map(|(&x, &y)| match sym {
                    "+" => x + y,
                    "-" => x - y,
                    "*" => x * y,
                    "/" => x / y,
                    "%" => x % y,
                    _ => x,
                })
                .collect();
            let t = Value::Tensor(s1.clone(), out);
            state.record_alloc(t.clone());
            state.stack.push(t);
            return;
        }

        if matches!(a, Value::Real(_)) || matches!(b, Value::Real(_)) {
            let x = a.as_real();
            let y = b.as_real();
            let r = match sym {
                "+" => x + y,
                "-" => x - y,
                "*" => x * y,
                "/" => x / y,
                "%" => x % y,
                _ => 0.0,
            };
            state.stack.push(Value::Real(r));
        } else {
            let x = a.as_int();
            let y = b.as_int();
            let n = match sym {
                "+" => x + y,
                "-" => x - y,
                "*" => x * y,
                "/" => x / y,
                "%" => x % y,
                _ => 0,
            };
            state.stack.push(Value::Int(n));
        }
    }

    fn execute_core(&mut self, vm_tid: usize, instr: &Instruction) {
        match instr {
            Instruction::Add => {
                self.dispatch_binary_op(vm_tid, "+");
                return;
            }
            Instruction::Sub => {
                self.dispatch_binary_op(vm_tid, "-");
                return;
            }
            Instruction::Mul => {
                self.dispatch_binary_op(vm_tid, "*");
                return;
            }
            Instruction::Div => {
                self.dispatch_binary_op(vm_tid, "/");
                return;
            }
            Instruction::Mod => {
                self.dispatch_binary_op(vm_tid, "%");
                return;
            }
            Instruction::LoadShared(var_name) => {
                let default_val = self.threads[vm_tid].stack.pop().expect("Stack underflow");
                let val = self
                    .shared_globals
                    .entry(var_name.clone())
                    .or_insert(default_val)
                    .clone();
                self.threads[vm_tid].stack.push(val);
                return;
            }
            Instruction::AtomicStore(var_name) => {
                let new_val = self.threads[vm_tid].stack.pop().expect("Stack underflow");
                self.shared_globals.insert(var_name.clone(), new_val);
                self.threads[vm_tid].stack.push(Value::Unit);
                return;
            }
            _ => {}
        }

        let state = &mut self.threads[vm_tid];
        match instr {
            Instruction::PushInt(n) => state.stack.push(Value::Int(*n)),
            Instruction::PushReal(r) => state.stack.push(Value::Real(*r)),
            Instruction::PushString(s) => {
                let val = Value::Str(s.clone());
                state.record_alloc(val.clone());
                state.stack.push(val);
            }
            Instruction::StrInterp(count) => {
                let start = state.stack.len() - *count;
                let joined: String = state.stack[start..].iter().map(|v| format!("{}", v)).collect();
                state.stack.truncate(start);
                let val = Value::Str(joined);
                state.record_alloc(val.clone());
                state.stack.push(val);
            }
            Instruction::Out => {
                if let Some(top) = state.stack.pop() {
                    println!("{}", top);
                }
                state.stack.push(Value::Unit);
            }
            Instruction::PushBool(b) => state.stack.push(Value::Bool(*b)),
            Instruction::PushUnit => state.stack.push(Value::Unit),
            Instruction::PushContext(ctx_name) => {
                let val = state.stack.pop().expect("Stack underflow");
                state.context_env.entry(ctx_name.clone()).or_default().push(val);
            }
            Instruction::PopContext(ctx_name) => {
                if let Some(stack) = state.context_env.get_mut(ctx_name) {
                    stack.pop();
                }
            }
            Instruction::LoadContext(ctx_name) => {
                let default_val = state.stack.pop().expect("Stack underflow");
                let val = state
                    .context_env
                    .get(ctx_name)
                    .and_then(|s| s.last().cloned())
                    .unwrap_or(default_val);
                state.stack.push(val);
            }
            Instruction::EnterRegionLimit(limit) => {
                let prev = state.region.quota_bytes();
                let used = state.region.used_bytes();
                state.region.set_quota(used + *limit);
                state.region_limit_stack.push((prev, false));
            }
            Instruction::ExitRegionLimit => {
                let body_val = state.stack.pop().unwrap_or(Value::Unit);
                let (prev_limit, oom) = state.region_limit_stack.pop().unwrap_or((65536, false));
                state.region.set_quota(prev_limit);
                if oom {
                    state.stack.push(Value::Adt(
                        "Err".to_string(),
                        vec![Value::Adt("OutOfMemory".to_string(), Vec::new())],
                    ));
                } else {
                    state.stack.push(Value::Adt("Ok".to_string(), vec![body_val]));
                }
            }
            Instruction::LoadLocal(idx) => {
                let val = state
                    .call_stack
                    .last()
                    .unwrap()
                    .locals
                    .get(*idx)
                    .cloned()
                    .unwrap_or(Value::Int(0));
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
            Instruction::CmpEq => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Bool(a == b));
            }
            Instruction::CmpNeq => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                state.stack.push(Value::Bool(a != b));
            }
            Instruction::CmpGt => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                let res = if matches!(a, Value::Real(_)) || matches!(b, Value::Real(_)) {
                    a.as_real() > b.as_real()
                } else {
                    a.as_int() > b.as_int()
                };
                state.stack.push(Value::Bool(res));
            }
            Instruction::CmpLt => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                let res = if matches!(a, Value::Real(_)) || matches!(b, Value::Real(_)) {
                    a.as_real() < b.as_real()
                } else {
                    a.as_int() < b.as_int()
                };
                state.stack.push(Value::Bool(res));
            }
            Instruction::CmpGtEq => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                let res = if matches!(a, Value::Real(_)) || matches!(b, Value::Real(_)) {
                    a.as_real() >= b.as_real()
                } else {
                    a.as_int() >= b.as_int()
                };
                state.stack.push(Value::Bool(res));
            }
            Instruction::CmpLtEq => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                let res = if matches!(a, Value::Real(_)) || matches!(b, Value::Real(_)) {
                    a.as_real() <= b.as_real()
                } else {
                    a.as_int() <= b.as_int()
                };
                state.stack.push(Value::Bool(res));
            }
            Instruction::And => {
                let b = state.stack.pop().expect("Stack underflow").as_bool();
                let a = state.stack.pop().expect("Stack underflow").as_bool();
                state.stack.push(Value::Bool(a && b));
            }
            Instruction::Or => {
                let b = state.stack.pop().expect("Stack underflow").as_bool();
                let a = state.stack.pop().expect("Stack underflow").as_bool();
                state.stack.push(Value::Bool(a || b));
            }
            Instruction::Xor => {
                let b = state.stack.pop().expect("Stack underflow").as_bool();
                let a = state.stack.pop().expect("Stack underflow").as_bool();
                state.stack.push(Value::Bool(a ^ b));
            }
            Instruction::Not => {
                let a = state.stack.pop().expect("Stack underflow").as_bool();
                state.stack.push(Value::Bool(!a));
            }
            Instruction::Echo(argc) => {
                let start = state.stack.len() - *argc;
                let parts: Vec<String> = state.stack[start..].iter().map(|v| format!("{}", v)).collect();
                state.stack.truncate(start);
                println!("{}", parts.join(" "));
                state.stack.push(Value::Unit);
            }
            Instruction::Call(name, argc) => {
                let mut args = vec![Value::Unit; *argc];
                for i in (0..*argc).rev() {
                    args[i] = state.stack.pop().expect("Stack underflow");
                }
                let func = self
                    .program
                    .functions
                    .get(name)
                    .unwrap_or_else(|| panic!("Undefined function: {}", name));

                if func.is_variadic && func.arity > 0 {
                    let fixed = func.arity - 1;
                    let rest = if args.len() > fixed {
                        args.split_off(fixed)
                    } else {
                        Vec::new()
                    };
                    if rest.len() == 1 && matches!(rest[0], Value::List(_)) {
                        args.push(rest.into_iter().next().unwrap());
                    } else {
                        args.push(Value::List(rest));
                    }
                } else if args.len() == 1 && func.arity > 1 {
                    match &args[0] {
                        Value::Tuple(elems) | Value::List(elems) if elems.len() == func.arity => {
                            args = elems.clone();
                        }
                        _ => {}
                    }
                }

                assert_eq!(args.len(), func.arity, "Arity mismatch in call to '{}'", name);

                let is_tail_self_call = if let Some(caller) = state.call_stack.last() {
                    caller.function == *name
                        && self
                            .program
                            .functions
                            .get(&caller.function)
                            .and_then(|cf| cf.code.get(caller.ip))
                            .map(|next_op| matches!(next_op, Instruction::Return))
                            .unwrap_or(false)
                } else {
                    false
                };

                if is_tail_self_call {
                    let wm = state.call_stack.last().unwrap().region_watermark;
                    let _ = state.region.reset_to(wm, vm_tid);
                    let caller = state.call_stack.last_mut().unwrap();
                    caller.ip = 0;
                    caller.locals = args;
                } else {
                    let wm = state.region.watermark();
                    state.call_stack.push(CallFrame {
                        function: name.clone(),
                        ip: 0,
                        locals: args,
                        region_watermark: wm,
                    });
                }
            }
            Instruction::Return => {
                if let Some(popped) = state.call_stack.pop() {
                    let _ = state.region.reset_to(popped.region_watermark, vm_tid);
                }
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
            _ => {}
        }
    }

    fn try_execute_collection(&mut self, vm_tid: usize, instr: &Instruction) -> bool {
        let state = &mut self.threads[vm_tid];
        match instr {
            Instruction::PushListEmpty => {
                state.stack.push(Value::List(Vec::new()));
            }
            Instruction::PushListConcat(n) => {
                let mut result = Vec::new();
                let start = state.stack.len() - *n;
                for i in start..state.stack.len() {
                    match &state.stack[i] {
                        Value::List(items) => result.extend(items.iter().cloned()),
                        val => result.push(val.clone()),
                    }
                }
                state.stack.truncate(start);
                let val = Value::List(result);
                state.record_alloc(val.clone());
                state.stack.push(val);
            }
            Instruction::SeqFlatJoin => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                let mut items = Vec::new();
                for v in [a, b] {
                    match v {
                        Value::Tuple(elems) | Value::List(elems) => items.extend(elems),
                        single => items.push(single),
                    }
                }
                let val = Value::Tuple(items);
                state.record_alloc(val.clone());
                state.stack.push(val);
            }
            Instruction::PackSeq(start_slot, end_slot) => {
                let locals = &state.call_stack.last().unwrap().locals;
                if let Some(first @ (Value::List(_) | Value::Tuple(_))) = locals.get(*start_slot) {
                    if *end_slot <= *start_slot + 1 {
                        state.stack.push(first.clone());
                        return true;
                    }
                }
                let mut items = Vec::new();
                for s in *start_slot..(*end_slot).min(locals.len()) {
                    items.push(locals[s].clone());
                }
                state.stack.push(Value::List(items));
            }
            Instruction::SeqSelectMask(mask) => {
                let seq = state.stack.pop().expect("Stack underflow");
                let items = match seq {
                    Value::List(v) | Value::Tuple(v) => v,
                    other => vec![other],
                };
                let selected: Vec<Value> = mask
                    .iter()
                    .enumerate()
                    .filter(|(_, &keep)| keep)
                    .filter_map(|(idx, _)| items.get(idx).cloned())
                    .collect();
                if selected.len() == 1 {
                    state.stack.push(selected.into_iter().next().unwrap());
                } else {
                    state.stack.push(Value::Tuple(selected));
                }
            }
            Instruction::SeqSelectIndices(indices) => {
                let seq = state.stack.pop().expect("Stack underflow");
                let items = match seq {
                    Value::List(v) | Value::Tuple(v) => v,
                    other => vec![other],
                };
                let selected: Vec<Value> = indices
                    .iter()
                    .filter_map(|&idx| items.get(idx).cloned())
                    .collect();
                if selected.len() == 1 {
                    state.stack.push(selected.into_iter().next().unwrap());
                } else {
                    state.stack.push(Value::Tuple(selected));
                }
            }
            Instruction::JumpIfEmpty(target) => {
                let val = state.stack.pop().expect("Stack underflow");
                let is_empty = match val {
                    Value::List(ref items) => items.is_empty(),
                    _ => true,
                };
                if is_empty {
                    state.call_stack.last_mut().unwrap().ip = *target;
                }
            }
            Instruction::JumpIfNotEmpty(target) => {
                let val = state.stack.pop().expect("Stack underflow");
                let is_empty = match val {
                    Value::List(ref items) => items.is_empty(),
                    _ => false,
                };
                if !is_empty {
                    state.call_stack.last_mut().unwrap().ip = *target;
                }
            }
            Instruction::ListHead => {
                let val = state.stack.pop().expect("Stack underflow");
                match val {
                    Value::List(items) => state.stack.push(items.into_iter().next().unwrap_or(Value::Unit)),
                    other => state.stack.push(other),
                }
            }
            Instruction::ListTail => {
                let val = state.stack.pop().expect("Stack underflow");
                match val {
                    Value::List(mut items) => {
                        if !items.is_empty() {
                            items.remove(0);
                        }
                        state.stack.push(Value::List(items));
                    }
                    _ => state.stack.push(Value::List(Vec::new())),
                }
            }
            Instruction::MakeTuple(n) => {
                let start = state.stack.len() - *n;
                let elems = state.stack.split_off(start);
                let val = Value::Tuple(elems);
                state.record_alloc(val.clone());
                state.stack.push(val);
            }
            Instruction::TupleGet(idx) => {
                let tup = state.stack.pop().expect("Stack underflow");
                match tup {
                    Value::Tuple(items) | Value::List(items) => {
                        state.stack.push(items.get(*idx).cloned().unwrap_or(Value::Unit));
                    }
                    other => state.stack.push(other),
                }
            }
            Instruction::MakeAdt(ctor, arity) => {
                let start = state.stack.len() - *arity;
                let fields = state.stack.split_off(start);
                let val = Value::Adt(ctor.clone(), fields);
                state.record_alloc(val.clone());
                state.stack.push(val);
            }
            Instruction::JumpIfNotAdt(expected_ctor, target) => {
                let val = state.stack.pop().expect("Stack underflow");
                let matched = match val {
                    Value::Adt(ref ctor, _) => ctor == expected_ctor,
                    _ => false,
                };
                if !matched {
                    state.call_stack.last_mut().unwrap().ip = *target;
                }
            }
            Instruction::AdtField(idx) => {
                let val = state.stack.pop().expect("Stack underflow");
                match val {
                    Value::Adt(_, fields) => {
                        state.stack.push(fields.get(*idx).cloned().unwrap_or(Value::Unit));
                    }
                    _ => state.stack.push(Value::Unit),
                }
            }
            Instruction::MakeTensor(n) => {
                let start = state.stack.len() - *n;
                let elems = state.stack.split_off(start);
                let tensor = build_tensor_value(&elems);
                state.record_alloc(tensor.clone());
                state.stack.push(tensor);
            }
            Instruction::TensorGet(ndim) => {
                let mut indices = vec![0usize; *ndim];
                for i in (0..*ndim).rev() {
                    indices[i] = state.stack.pop().expect("Stack underflow").as_int() as usize;
                }
                let tensor = state.stack.pop().expect("Stack underflow");
                state.stack.push(read_tensor_index(&tensor, &indices));
            }
            Instruction::TensorSet(ndim) => {
                let new_val = state.stack.pop().expect("Stack underflow");
                let mut indices = vec![0usize; *ndim];
                for i in (0..*ndim).rev() {
                    indices[i] = state.stack.pop().expect("Stack underflow").as_int() as usize;
                }
                let mut tensor = state.stack.pop().expect("Stack underflow");
                write_tensor_index(&mut tensor, &indices, new_val);
                state.stack.push(tensor);
            }
            Instruction::TensorMatMul => {
                let b = state.stack.pop().expect("Stack underflow");
                let a = state.stack.pop().expect("Stack underflow");
                let res = compute_einsum(&[a, b], &["ij".to_string(), "jk".to_string()]);
                state.record_alloc(res.clone());
                state.stack.push(res);
            }
            Instruction::TensorEinsum(subs) => {
                let k = subs.len();
                let start = state.stack.len() - k;
                let tensors = state.stack.split_off(start);
                let res = compute_einsum(&tensors, subs);
                state.record_alloc(res.clone());
                state.stack.push(res);
            }
            Instruction::TensorHadamard(op, s1, s2) => {
                let right = state.stack.pop().expect("Stack underflow");
                let left = state.stack.pop().expect("Stack underflow");
                let res = compute_hadamard(*op, &left, s1, &right, s2);
                state.record_alloc(res.clone());
                state.stack.push(res);
            }
            Instruction::SeqSelectHead => {
                let list = state.stack.pop().expect("Stack underflow");
                match list {
                    Value::List(items) | Value::Tuple(items) => {
                        state.stack.push(items.into_iter().next().unwrap_or(Value::Unit));
                    }
                    other => state.stack.push(other),
                }
            }
            Instruction::SeqSelectRange(start, end) => {
                let list = state.stack.pop().expect("Stack underflow");
                match list {
                    Value::List(items) | Value::Tuple(items) => {
                        let selected: Vec<Value> = items
                            .into_iter()
                            .enumerate()
                            .filter(|(i, _)| *i >= *start && *i <= *end)
                            .map(|(_, v)| v)
                            .collect();
                        state.stack.push(Value::List(selected));
                    }
                    other => state.stack.push(other),
                }
            }
            _ => return false,
        }
        true
    }

    fn try_execute_concurrency(&mut self, vm_tid: usize, instr: &Instruction) -> bool {
        match instr {
            Instruction::LatchInit(count) => {
                self.threads[vm_tid].latches.push(*count);
                true
            }
            Instruction::LatchArrive => {
                if let Some(counter) = self.threads[vm_tid].latches.last_mut() {
                    *counter = counter.saturating_sub(1);
                    if *counter == 0 {
                        self.threads[vm_tid].latches.pop();
                        self.completed_latches += 1;
                    }
                }
                true
            }
            Instruction::SpawnTask(helper_name, parent_slots, target_slot) => {
                let args: Vec<Value> = {
                    let locals = &self.threads[vm_tid].call_stack.last().unwrap().locals;
                    parent_slots
                        .iter()
                        .map(|&s| locals.get(s).cloned().unwrap_or(Value::Unit))
                        .collect()
                };
                let inherited_ctx = self.threads[vm_tid].context_env.clone();
                let child_tid = self.spawn_thread_with_context(helper_name.clone(), args, inherited_ctx);
                self.threads[vm_tid].pending_stage_tasks.push((child_tid, *target_slot));
                true
            }
            Instruction::WaitStageTasks => {
                let all_done = self.threads[vm_tid]
                    .pending_stage_tasks
                    .iter()
                    .all(|(child_tid, _)| self.threads[*child_tid].is_done());
                if !all_done {
                    self.threads[vm_tid].call_stack.last_mut().unwrap().ip -= 1;
                    self.threads[vm_tid].blocked = true;
                } else {
                    let tasks = std::mem::take(&mut self.threads[vm_tid].pending_stage_tasks);
                    for (child_tid, target_slot) in tasks {
                        let val = self.threads[child_tid]
                            .stack
                            .last()
                            .cloned()
                            .unwrap_or(Value::Unit);
                        if let Some(slot) = target_slot {
                            let locals = &mut self.threads[vm_tid].call_stack.last_mut().unwrap().locals;
                            while locals.len() <= slot {
                                locals.push(Value::Unit);
                            }
                            locals[slot] = val;
                        } else {
                            self.threads[vm_tid].stack.push(val);
                        }
                    }
                    self.completed_latches += 1;
                }
                true
            }
            Instruction::MailboxNew => {
                let id = self.mailboxes.len();
                self.mailboxes.push(Mailbox::new());
                self.threads[vm_tid].stack.push(Value::MailboxRef(id));
                true
            }
            Instruction::ChanNew => {
                let id = self.channels.len();
                self.channels.push(Channel::unbounded(id));
                self.threads[vm_tid].stack.push(Value::ChannelRef(id));
                true
            }
            Instruction::ChanNewBounded => {
                let cap = self.threads[vm_tid].stack.pop().expect("Stack underflow").as_int() as usize;
                let id = self.channels.len();
                self.channels.push(Channel::bounded(id, cap));
                self.threads[vm_tid].stack.push(Value::ChannelRef(id));
                true
            }
            Instruction::ChanSend => {
                let ch_val = self.threads[vm_tid].stack.pop().expect("Stack underflow");
                let msg = self.threads[vm_tid].stack.pop().expect("Stack underflow");
                if let Value::ChannelRef(cid) = ch_val {
                    let status = self.channels[cid].send(vm_tid, msg);
                    if let Some(waiting_rx) = self.channels[cid].pop_waiting_receiver() {
                        self.threads[waiting_rx].blocked = false;
                        self.scheduler.unblock(waiting_rx);
                    }
                    if status == SendStatus::WouldBlock {
                        self.threads[vm_tid].blocked = true;
                    }
                }
                self.threads[vm_tid].stack.push(Value::Unit);
                true
            }
            Instruction::ChanRecv => {
                let ch_val = self.threads[vm_tid].stack.pop().expect("Stack underflow");
                if let Value::ChannelRef(cid) = ch_val {
                    let (status, unblocked_tx) = self.channels[cid].recv(vm_tid);
                    if let Some(tx_tid) = unblocked_tx {
                        self.threads[tx_tid].blocked = false;
                        self.scheduler.unblock(tx_tid);
                    }
                    match status {
                        RecvStatus::Received(val) => self.threads[vm_tid].stack.push(val),
                        RecvStatus::Empty => {
                            self.threads[vm_tid].stack.push(Value::ChannelRef(cid));
                            self.threads[vm_tid].call_stack.last_mut().unwrap().ip -= 1;
                            self.threads[vm_tid].blocked = true;
                        }
                        RecvStatus::Closed => self.threads[vm_tid].stack.push(Value::Unit),
                    }
                }
                true
            }
            Instruction::ChanTryRecv => {
                let ch_val = self.threads[vm_tid].stack.pop().expect("Stack underflow");
                if let Value::ChannelRef(cid) = ch_val {
                    let (opt_val, unblocked_tx) = self.channels[cid].try_recv();
                    if let Some(tx_tid) = unblocked_tx {
                        self.threads[tx_tid].blocked = false;
                        self.scheduler.unblock(tx_tid);
                    }
                    match opt_val {
                        Some(val) => self.threads[vm_tid].stack.push(Value::Adt("Some".into(), vec![val])),
                        None => self.threads[vm_tid].stack.push(Value::Adt("None".into(), vec![])),
                    }
                }
                true
            }
            Instruction::ChanRecvTimeout => {
                let timeout_ms = self.threads[vm_tid].stack.pop().expect("Stack underflow").as_int();
                let ch_val = self.threads[vm_tid].stack.pop().expect("Stack underflow");
                if let Value::ChannelRef(cid) = ch_val {
                    let (opt_val, unblocked_tx) = self.channels[cid].try_recv();
                    if let Some(tx_tid) = unblocked_tx {
                        self.threads[tx_tid].blocked = false;
                        self.scheduler.unblock(tx_tid);
                    }
                    match opt_val {
                        Some(val) => {
                            self.threads[vm_tid].timeout_ticks = 0;
                            self.threads[vm_tid].stack.push(Value::Adt("Some".into(), vec![val]));
                        }
                        None => {
                            if timeout_ms > 0 && self.threads[vm_tid].timeout_ticks == 0 {
                                self.threads[vm_tid].timeout_ticks = 1;
                                self.threads[vm_tid].stack.push(Value::ChannelRef(cid));
                                self.threads[vm_tid].stack.push(Value::Int(0));
                                self.threads[vm_tid].call_stack.last_mut().unwrap().ip -= 1;
                                self.threads[vm_tid].blocked = true;
                            } else {
                                self.threads[vm_tid].timeout_ticks = 0;
                                self.threads[vm_tid].stack.push(Value::Adt("None".into(), vec![]));
                            }
                        }
                    }
                }
                true
            }
            Instruction::Spawn => {
                let thread_ref = Value::ThreadRef(self.next_thread_id);
                self.threads[vm_tid].stack.push(thread_ref);
                true
            }
            Instruction::SpawnFunc(func_name, argc) => {
                let mut args = vec![Value::Unit; *argc];
                for i in (0..*argc).rev() {
                    args[i] = self.threads[vm_tid].stack.pop().expect("Stack underflow");
                }
                let inherited_ctx = self.threads[vm_tid].context_env.clone();
                let child_tid = self.spawn_thread_with_context(func_name.clone(), args, inherited_ctx);
                self.threads[vm_tid].stack.push(Value::ThreadRef(child_tid));
                true
            }
            Instruction::Join => {
                let thread_ref = self.threads[vm_tid].stack.pop().expect("Stack underflow on Join");
                let target_tid = match thread_ref {
                    Value::ThreadRef(id) => id,
                    Value::Int(id) => id as usize,
                    _ => {
                        self.threads[vm_tid].stack.push(Value::Unit);
                        return true;
                    }
                };
                if target_tid < self.threads.len() {
                    if self.threads[target_tid].is_done() {
                        let val = self.threads[target_tid].stack.last().cloned().unwrap_or(Value::Unit);
                        self.threads[vm_tid].stack.push(val);
                    } else {
                        self.threads[vm_tid].stack.push(Value::ThreadRef(target_tid));
                        self.threads[vm_tid].call_stack.last_mut().unwrap().ip -= 1;
                        self.threads[vm_tid].blocked = true;
                    }
                } else {
                    self.threads[vm_tid].stack.push(Value::Unit);
                }
                true
            }
            Instruction::Send(_) => {
                let mailbox_id = self.threads[vm_tid].mailbox_id;
                let mailbox_val = self.threads[vm_tid].stack.pop().expect("Stack underflow on Send");
                let value = self.threads[vm_tid].stack.pop().expect("Stack underflow on Send");
                let target_mailbox = match mailbox_val {
                    Value::MailboxRef(id) => id,
                    Value::ThreadRef(_) => mailbox_id,
                    _ => {
                        self.threads[vm_tid].stack.push(Value::Bool(false));
                        return true;
                    }
                };
                if target_mailbox < self.mailboxes.len() {
                    self.mailboxes[target_mailbox].send(value);
                    self.threads[vm_tid].stack.push(Value::Bool(true));
                } else {
                    self.threads[vm_tid].stack.push(Value::Bool(false));
                }
                true
            }
            Instruction::Recv(_) => {
                let mailbox_id = self.threads[vm_tid].mailbox_id;
                let mailbox_val = self.threads[vm_tid].stack.pop().expect("Stack underflow on Recv");
                let target_mailbox = match mailbox_val {
                    Value::MailboxRef(id) => id,
                    Value::ThreadRef(_) => mailbox_id,
                    _ => {
                        self.threads[vm_tid].stack.push(Value::Unit);
                        return true;
                    }
                };
                if target_mailbox < self.mailboxes.len() {
                    if let Some(msg) = self.mailboxes[target_mailbox].recv() {
                        self.threads[vm_tid].stack.push(msg);
                    } else {
                        self.threads[vm_tid].stack.push(mailbox_val);
                        self.threads[vm_tid].call_stack.last_mut().unwrap().ip -= 1;
                        self.threads[vm_tid].blocked = true;
                    }
                } else {
                    self.threads[vm_tid].stack.push(Value::Unit);
                }
                true
            }
            _ => false,
        }
    }
}

fn flatten_tensor_elems(elems: &[Value], shape: &mut Vec<usize>, flat: &mut Vec<f64>, record_shape: bool) {
    if record_shape {
        shape.push(elems.len());
    }
    for (i, v) in elems.iter().enumerate() {
        match v {
            Value::List(sub) | Value::Tuple(sub) => {
                flatten_tensor_elems(sub, shape, flat, record_shape && i == 0);
            }
            scalar => flat.push(scalar.as_real()),
        }
    }
}

fn build_tensor_value(elems: &[Value]) -> Value {
    let mut shape = Vec::new();
    let mut flat = Vec::new();
    flatten_tensor_elems(elems, &mut shape, &mut flat, true);
    Value::Tensor(shape, flat)
}

fn compute_strides(shape: &[usize]) -> Vec<usize> {
    let mut strides = vec![1usize; shape.len()];
    for i in (0..shape.len().saturating_sub(1)).rev() {
        strides[i] = strides[i + 1] * shape[i + 1];
    }
    strides
}

fn read_tensor_index(tensor: &Value, indices: &[usize]) -> Value {
    match tensor {
        Value::Tensor(shape, data) => {
            let strides = compute_strides(shape);
            if indices.len() >= shape.len() {
                let offset: usize = indices
                    .iter()
                    .zip(strides.iter())
                    .map(|(&idx, &st)| idx * st)
                    .sum();
                let val = data.get(offset).copied().unwrap_or(0.0);
                if val.fract() == 0.0 {
                    Value::Int(val as i64)
                } else {
                    Value::Real(val)
                }
            } else {
                let prefix_offset: usize = indices
                    .iter()
                    .zip(strides.iter())
                    .map(|(&idx, &st)| idx * st)
                    .sum();
                let sub_shape = shape[indices.len()..].to_vec();
                let slice_len: usize = sub_shape.iter().product();
                let slice = data[prefix_offset..(prefix_offset + slice_len)].to_vec();
                Value::Tensor(sub_shape, slice)
            }
        }
        Value::List(items) | Value::Tuple(items) => items.get(indices[0]).cloned().unwrap_or(Value::Unit),
        _ => Value::Unit,
    }
}

fn write_tensor_index(tensor: &mut Value, indices: &[usize], new_val: Value) {
    if let Value::Tensor(shape, data) = tensor {
        let strides = compute_strides(shape);
        let offset: usize = indices
            .iter()
            .zip(strides.iter())
            .map(|(&idx, &st)| idx * st)
            .sum();
        if indices.len() >= shape.len() {
            if offset < data.len() {
                data[offset] = new_val.as_real();
            }
        } else {
            match new_val {
                Value::Tensor(_, sub_data) => {
                    for (k, &v) in sub_data.iter().enumerate() {
                        if offset + k < data.len() {
                            data[offset + k] = v;
                        }
                    }
                }
                scalar => {
                    if offset < data.len() {
                        data[offset] = scalar.as_real();
                    }
                }
            }
        }
    }
}

fn compute_einsum(tensors: &[Value], subs: &[String]) -> Value {
    let mut index_order: Vec<char> = Vec::new();
    let mut index_counts: HashMap<char, usize> = HashMap::new();
    let mut index_dims: HashMap<char, usize> = HashMap::new();

    for (tensor, sub) in tensors.iter().zip(subs.iter()) {
        if let Value::Tensor(shape, _) = tensor {
            for (ch, &dim) in sub.chars().zip(shape.iter()) {
                if !index_order.contains(&ch) {
                    index_order.push(ch);
                }
                *index_counts.entry(ch).or_insert(0) += 1;
                index_dims.insert(ch, dim);
            }
        }
    }

    let free_indices: Vec<char> = index_order
        .iter()
        .copied()
        .filter(|c| index_counts.get(c).copied().unwrap_or(0) == 1)
        .collect();

    let out_shape: Vec<usize> = if free_indices.is_empty() {
        vec![1]
    } else {
        free_indices.iter().map(|c| index_dims[c]).collect()
    };
    let out_strides = compute_strides(&out_shape);
    let out_len: usize = out_shape.iter().product();
    let mut out_data = vec![0.0f64; out_len];

    let all_dims: Vec<usize> = index_order.iter().map(|c| index_dims[c]).collect();
    let total_iters: usize = all_dims.iter().product::<usize>().max(1);
    let all_strides = compute_strides(&all_dims);

    let tensor_strides: Vec<Vec<usize>> = tensors
        .iter()
        .map(|t| match t {
            Value::Tensor(sh, _) => compute_strides(sh),
            _ => Vec::new(),
        })
        .collect();

    for flat_iter in 0..total_iters {
        let mut coord_map: HashMap<char, usize> = HashMap::new();
        for (idx_pos, &ch) in index_order.iter().enumerate() {
            let c_val = (flat_iter / all_strides[idx_pos]) % all_dims[idx_pos];
            coord_map.insert(ch, c_val);
        }

        let mut prod = 1.0f64;
        for (t_idx, (tensor, sub)) in tensors.iter().zip(subs.iter()).enumerate() {
            if let Value::Tensor(_, data) = tensor {
                let st = &tensor_strides[t_idx];
                let offset: usize = sub
                    .chars()
                    .enumerate()
                    .map(|(d, ch)| coord_map[&ch] * st[d])
                    .sum();
                prod *= data.get(offset).copied().unwrap_or(0.0);
            }
        }

        let out_offset: usize = if free_indices.is_empty() {
            0
        } else {
            free_indices
                .iter()
                .enumerate()
                .map(|(d, ch)| coord_map[ch] * out_strides[d])
                .sum()
        };
        if out_offset < out_data.len() {
            out_data[out_offset] += prod;
        }
    }

    Value::Tensor(out_shape, out_data)
}

fn compute_hadamard(
    op: crate::parser::BinOp,
    left: &Value,
    s1: &str,
    right: &Value,
    s2: &str,
) -> Value {
    if let (Value::Tensor(sh1, d1), Value::Tensor(sh2, d2)) = (left, right) {
        let st1 = compute_strides(sh1);
        let st2 = compute_strides(sh2);
        let s1_chars: Vec<char> = s1.chars().collect();
        let mut out = vec![0.0f64; d1.len()];

        for flat_idx in 0..d1.len() {
            let mut coord_map = HashMap::new();
            for (d, &ch) in s1_chars.iter().enumerate() {
                let c_val = (flat_idx / st1[d]) % sh1[d];
                coord_map.insert(ch, c_val);
            }
            let r_offset: usize = s2
                .chars()
                .enumerate()
                .map(|(d, ch)| coord_map.get(&ch).copied().unwrap_or(0) * st2[d])
                .sum();
            let lv = d1[flat_idx];
            let rv = d2.get(r_offset).copied().unwrap_or(0.0);
            out[flat_idx] = match op {
                crate::parser::BinOp::Add => lv + rv,
                crate::parser::BinOp::Sub => lv - rv,
                crate::parser::BinOp::Mul => lv * rv,
                crate::parser::BinOp::Div => lv / rv,
                _ => lv,
            };
        }
        return Value::Tensor(sh1.clone(), out);
    }
    Value::Unit
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
        let src2 = "fn :: test => Bool\ntest = True == True";
        let result = run(src2, "test", &[]);
        assert_eq!(result, Value::Bool(true));
    }
}
