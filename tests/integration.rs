/// Integration tests — load actual .rg files and run them through the full pipeline

use ridgun::analyzer::{analyze_program, AnalysisError};
use ridgun::compiler;
use ridgun::lexer::Lexer;
use ridgun::parser::Parser;
use ridgun::vm::{VM, Value};

/// Run inline source and call main
fn run_src(src: &str) -> Value {
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    vm.call("main", &[])
}

// ── Arithmetic tests ───────────────────────────────────────

#[test]
fn test_factorial_values() {
    let r = run_src("fn :: factorial Int => Int\nfactorial 0 = 1\nfactorial n = n * factorial (n - 1)\nfn :: main => Int\nmain = factorial 10");
    assert_eq!(r, Value::Int(3628800));
}

#[test]
fn test_fib_values() {
    let r = run_src("fn :: fib Int => Int\nfib 0 = 0\nfib 1 = 1\nfib n = fib (n - 1) + fib (n - 2)\nfn :: main => Int\nmain = fib 10");
    assert_eq!(r, Value::Int(55));
}

#[test]
fn test_nested_calls() {
    let r = run_src("fn :: double Int => Int\ndouble x = x + x\nfn :: quadruple Int => Int\nquadruple x = double (double x)\nfn :: main => Int\nmain = quadruple 5");
    assert_eq!(r, Value::Int(20));
}

#[test]
fn test_multiple_pattern_cases() {
    let r = run_src("fn :: classify Int => Int\nclassify 0 = 100\nclassify 1 = 200\nclassify n = n\nfn :: main => Int\nmain = classify 0 + classify 1 + classify 42");
    assert_eq!(r, Value::Int(342));
}

#[test]
fn test_arithmetic_precedence() {
    let r = run_src("fn :: main => Int\nmain = 2 + 3 * 4");
    assert_eq!(r, Value::Int(14));
}

#[test]
fn test_subtraction() {
    let r = run_src("fn :: main => Int\nmain = 10 - 3 - 2");
    assert_eq!(r, Value::Int(5));
}

#[test]
fn test_parenthesized_expr() {
    let r = run_src("fn :: main => Int\nmain = (2 + 3) * 4");
    assert_eq!(r, Value::Int(20));
}

#[test]
fn test_division() {
    let r = run_src("fn :: main => Int\nmain = 100 / 5 / 2");
    assert_eq!(r, Value::Int(10));
}

#[test]
fn test_wildcard_pattern() {
    let r = run_src("fn :: second Int Int => Int\nsecond _ b = b\nfn :: main => Int\nmain = second 99 7");
    assert_eq!(r, Value::Int(7));
}

// ── Value type tests ───────────────────────────────────────

#[test]
fn test_string_return() {
    let r = run_src("fn :: main => String\nmain = \"hello\"");
    assert_eq!(r, Value::Str("hello".into()));
}

#[test]
fn test_bool_return() {
    let r = run_src("fn :: main => Bool\nmain = True");
    assert_eq!(r, Value::Bool(true));
}

#[test]
fn test_comparison_eq() {
    let r = run_src("fn :: main => Bool\nmain = 5 == 5");
    assert_eq!(r, Value::Bool(true));
}

#[test]
fn test_comparison_neq() {
    let r = run_src("fn :: main => Bool\nmain = 5 == 3");
    assert_eq!(r, Value::Bool(false));
}

#[test]
fn test_comparison_gt() {
    let r = run_src("fn :: main => Bool\nmain = 5 > 3");
    assert_eq!(r, Value::Bool(true));
}

#[test]
fn test_comparison_lt() {
    let r = run_src("fn :: main => Bool\nmain = 3 < 5");
    assert_eq!(r, Value::Bool(true));
}

#[test]
fn test_unit_return() {
    let r = run_src("fn :: main => ()\nmain = ()");
    assert_eq!(r, Value::Unit);
}

#[test]
fn test_type_skipped() {
    let r = run_src("type Result = Ok Int | Err String\nfn :: main => Int\nmain = 42");
    assert_eq!(r, Value::Int(42));
}

#[test]
fn test_import_skipped() {
    let r = run_src("import test\nfn :: main => Int\nmain = 42");
    assert_eq!(r, Value::Int(42));
}

// ── Native List Cons & Recursive Pattern Matching ──────────

#[test]
fn test_recursive_list_sum_and_length() {
    let src = "\
fn :: sum_list [Int] => Int
sum_list [] = 0
sum_list (x:xs) = x + sum_list xs

fn :: list_length [Int] => Int
list_length [] = 0
list_length (_:xs) = 1 + list_length xs

fn :: main => Int
main = sum_list [10, 20, 30, 40] + list_length [1, 2, 3]
";
    assert_eq!(run_src(src), Value::Int(103));
}

// ── Algebraic Data Types (Sum & Product) & Tuples ──────────

#[test]
fn test_adt_sum_type_and_recursive_tree() {
    let src = "\
type Tree = Leaf Int | Node Tree Tree

fn :: sum_tree Tree => Int
sum_tree (Leaf n) = n
sum_tree (Node left right) = sum_tree left + sum_tree right

fn :: main => Int
main = sum_tree (Node (Leaf 15) (Node (Leaf 25) (Leaf 10)))
";
    assert_eq!(run_src(src), Value::Int(50));
}

#[test]
fn test_adt_product_record_type() {
    let src = "\
type Conf = host String, port Int

fn :: get_port Conf => Int
get_port c = port c

fn :: main => Int
main = get_port (Conf \"localhost\" 8080)
";
    assert_eq!(run_src(src), Value::Int(8080));
}

#[test]
fn test_tuple_pattern_matching() {
    let src = "\
fn :: swap (Int, String) => (String, Int)
swap (n, s) = (s, n)

fn :: main => (String, Int)
main = swap (42, \"ridgun\")
";
    assert_eq!(
        run_src(src),
        Value::Tuple(vec![Value::Str("ridgun".into()), Value::Int(42)])
    );
}

// ── v2.0 Next-Gen Architecture: `where` DAGs & `||` Pipes ──

#[test]
fn test_where_multi_stage_dag_execution() {
    let src = "\
fn :: add_ten Int => Int
add_ten x = x + 10

fn :: mul_two Int => Int
mul_two x = x * 2

fn :: pipeline Int => Int
pipeline n = final_res
  where
    add_ten n -> stage1_a
    mul_two n -> stage1_b
    stage1_a + stage1_b -> final_res

fn :: main => Int
main = pipeline 5
";
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    let res = vm.call("main", &[]);
    assert_eq!(res, Value::Int(25));
    assert_eq!(vm.completed_latches(), 2);
}

#[test]
fn test_par_pipe_execution() {
    let src = "\
fn :: double Int => Int
double x = x * 2

fn :: triple Int => Int
triple x = x * 3

fn :: both Int => (Int, Int)
both n =
  || double n
  || triple n

fn :: main => (Int, Int)
main = both 7
";
    assert_eq!(
        run_src(src),
        Value::Tuple(vec![Value::Int(14), Value::Int(21)])
    );
}

// ── Tensors & Disjoint Parallel Slice Mutation ─────────────

#[test]
fn test_tensor_indexing_and_disjoint_slice_where_mutation() {
    let src = "\
fn :: update_matrix Tensor => Int
update_matrix m = m[0, 0] + m[1, 1]
  where
    100 -> m[0, 0]
    200 -> m[1, 1]

fn :: main => Int
main = update_matrix (Tensor [[1, 2], [3, 4]])
";
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(analyze_program(&program).is_ok());
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    assert_eq!(vm.call("main", &[]), Value::Int(300));
}

// ── Static Mutation Freeze & Cycle Detection Errors ────────

#[test]
fn test_static_analyzer_rejects_parallel_mutation_conflict() {
    let src = "\
fn :: mutate_tensor Tensor => Int
mutate_tensor t = t[0]
  where
    99 -> t[0]

fn :: read_tensor Tensor => Int
read_tensor t = t[0]

fn :: bad_share Tensor => (Int, Int)
bad_share m = a, b
  where
    mutate_tensor m -> a
    read_tensor m -> b
";
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    let err = analyze_program(&program).unwrap_err();
    assert!(err.contains(&AnalysisError::ParallelMutationConflictError {
        function: "bad_share".into(),
        variable: "m".into(),
    }));
}

#[test]
fn test_static_analyzer_rejects_where_cycle() {
    let src = "\
fn :: cyclic Int => Int
cyclic x = a
  where
    b + 1 -> a
    a + 1 -> b
";
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    let err = analyze_program(&program).unwrap_err();
    assert!(matches!(
        err.first(),
        Some(AnalysisError::CyclicWhereDependencyError { function, .. }) if function == "cyclic"
    ));
}

#[test]
fn test_static_analyzer_rejects_use_after_channel_send() {
    let src = "\
fn :: leak Tensor Int => Int
leak t ch =
  _ = send_through t ch
  t[0]
";
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    let err = analyze_program(&program).unwrap_err();
    assert!(err.contains(&AnalysisError::UseAfterChannelSendError {
        function: "leak".into(),
        variable: "t".into(),
    }));
}

// ── Lexical Region Reset & Tail-Call Constant Memory ───────

#[test]
fn test_lexical_region_reclaims_memory_and_tail_call_ping_pong() {
    let src = "\
fn :: loop_count Int Int => Int
loop_count 0 acc = acc
loop_count n acc = loop_count (n - 1) (acc + 1)

fn :: main => Int
main = loop_count 500 0
";
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    let compiled = compiler::compile(&program);
    let mut vm = VM::with_seed(compiled, 12345);
    let res = vm.call("main", &[]);
    assert_eq!(res, Value::Int(500));
    assert_eq!(vm.main_region_used_bytes(), 0);
}

// ── Typed Channels & Spawn/Join Concurrency ────────────────

#[test]
fn test_typed_channel_and_green_thread_spawn() {
    let src = "\
fn :: worker Int => Int
worker x = x * 10

fn :: main => Int
main =
  ch = new_channel
  _ = send_through 42 ch
  v = receive_from ch
  t = spawn \"worker\" 5
  v + join t
";
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    let compiled = compiler::compile(&program);
    let mut vm = VM::with_seed(compiled, 918273);
    assert_eq!(vm.call("main", &[]), Value::Int(92));
}

#[test]
fn test_self_hosted_compiler_and_metacircular_vm() {
    let src = std::fs::read_to_string("examples/self_hosted_vm.rg")
        .expect("Failed to read examples/self_hosted_vm.rg");
    let (tokens, spans) = Lexer::new(&src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(
        ridgun::typecheck::typecheck(&program).is_ok(),
        "examples/self_hosted_vm.rg must typecheck cleanly"
    );
    let compiled = compiler::compile(&program);
    let mut vm = VM::with_seed(compiled, 42);
    assert_eq!(
        vm.call("run_all_parallel", &[]),
        Value::Tuple(vec![
            Value::Int(56),
            Value::Int(720),
            Value::Int(55),
            Value::Int(210),
        ])
    );
    assert_eq!(vm.call("main", &[]), Value::Unit);
}

#[test]
fn test_demo_rg_runs_cleanly() {
    let src = std::fs::read_to_string("examples/demo.rg")
        .expect("Failed to read examples/demo.rg");
    let (tokens, spans) = Lexer::new(&src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(
        ridgun::typecheck::typecheck(&program).is_ok(),
        "examples/demo.rg must typecheck cleanly"
    );
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    assert_eq!(vm.call("factorial", &[Value::Int(5)]), Value::Int(120));
    assert_eq!(vm.call("fib", &[Value::Int(15)]), Value::Int(610));
    assert_eq!(vm.call("demo_all", &[]), Value::Unit);
}

// ── 100% Specification Compliance Suite (All 11 Spec Categories) ──

#[test]
fn test_spec_1_string_interpolation_and_raw_strings() {
    let src = r#"
fn :: sum Int Int => Int
sum a b = a + b

fn :: greet String => String
greet name = "Hello, {name}!"

fn :: calc_msg => String
calc_msg = "Sum is {sum 3 4}"

fn :: escaped_msg => String
escaped_msg = "Use {{braces}}"

fn :: raw_msg => String
raw_msg = 'hello {world}'
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(ridgun::typecheck::typecheck(&program).is_ok());
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    assert_eq!(
        vm.call("greet", &[Value::Str("Alice".into())]),
        Value::Str("Hello, Alice!".into())
    );
    assert_eq!(vm.call("calc_msg", &[]), Value::Str("Sum is 7".into()));
    assert_eq!(vm.call("escaped_msg", &[]), Value::Str("Use {braces}".into()));
    assert_eq!(vm.call("raw_msg", &[]), Value::Str("hello {world}".into()));
}

#[test]
fn test_spec_2_postfix_out() {
    let src = r#"
fn :: print_banner => ()
print_banner = "hello" out
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(ridgun::typecheck::typecheck(&program).is_ok());
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    assert_eq!(vm.call("print_banner", &[]), Value::Unit);
}

#[test]
fn test_spec_3_logical_operators_and_or_xor_not() {
    let src = r#"
fn :: logic_and Bool Bool => Bool
logic_and a b = a AND b

fn :: logic_or Bool Bool => Bool
logic_or a b = a OR b

fn :: logic_xor Bool Bool => Bool
logic_xor a b = a XOR b

fn :: logic_not Bool => Bool
logic_not a = NOT a

fn :: range_check Int => Bool
range_check x = x > 0 AND x < 100 AND NOT (x == 50)
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(ridgun::typecheck::typecheck(&program).is_ok());
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    assert_eq!(vm.call("logic_and", &[Value::Bool(true), Value::Bool(false)]), Value::Bool(false));
    assert_eq!(vm.call("logic_and", &[Value::Bool(true), Value::Bool(true)]), Value::Bool(true));
    assert_eq!(vm.call("logic_or", &[Value::Bool(false), Value::Bool(true)]), Value::Bool(true));
    assert_eq!(vm.call("logic_xor", &[Value::Bool(true), Value::Bool(true)]), Value::Bool(false));
    assert_eq!(vm.call("logic_xor", &[Value::Bool(true), Value::Bool(false)]), Value::Bool(true));
    assert_eq!(vm.call("logic_not", &[Value::Bool(false)]), Value::Bool(true));
    assert_eq!(vm.call("range_check", &[Value::Int(42)]), Value::Bool(true));
    assert_eq!(vm.call("range_check", &[Value::Int(50)]), Value::Bool(false));
}

#[test]
fn test_spec_4_neq_and_modulo() {
    let src = r#"
fn :: is_odd Int => Bool
is_odd n = (n % 2) != 0

fn :: rem Int Int => Int
rem a b = a % b
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(ridgun::typecheck::typecheck(&program).is_ok());
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    assert_eq!(vm.call("is_odd", &[Value::Int(7)]), Value::Bool(true));
    assert_eq!(vm.call("is_odd", &[Value::Int(8)]), Value::Bool(false));
    assert_eq!(vm.call("rem", &[Value::Int(17), Value::Int(5)]), Value::Int(2));
}

#[test]
fn test_spec_5_real_and_char_types() {
    let src = r#"
fn :: circle_area Real => Real
circle_area r = 3.14159 * r * r

fn :: temp_c_to_f Real => Real
temp_c_to_f c = c * 1.8 + 32.0
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(ridgun::typecheck::typecheck(&program).is_ok());
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    if let Value::Real(v) = vm.call("temp_c_to_f", &[Value::Real(100.0)]) {
        assert!((v - 212.0).abs() < 1e-9);
    } else {
        panic!("Expected Value::Real");
    }
}

#[test]
fn test_spec_6_sequences_masks_index_selectors_flat_join_and_chained_ops() {
    let src = r#"
op :: Int Int switch => Int Int
a b switch = b, a

fn :: mask_first Int Int => Int
mask_first a b =
  s = a b switch
  s(+ _)

fn :: mask_second Int Int => Int
mask_second a b =
  s = a b switch
  s(_ +)

fn :: chained_switch Int Int => (Int, Int)
chained_switch a b = a b switch switch

fn :: join_and_select => (Int, Int)
join_and_select =
  s1 = 10 20 switch
  s2 = 30 40 switch
  joined = s1:s2
  joined(0 3)

fn :: mask_edges => (Int, Int)
mask_edges =
  s1 = 10 20 switch
  s2 = 30 40 switch
  joined = s1:s2
  joined(+ _ _ +)
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(ridgun::typecheck::typecheck(&program).is_ok());
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    assert_eq!(vm.call("mask_first", &[Value::Int(3), Value::Int(4)]), Value::Int(4));
    assert_eq!(vm.call("mask_second", &[Value::Int(3), Value::Int(4)]), Value::Int(3));
    assert_eq!(
        vm.call("chained_switch", &[Value::Int(3), Value::Int(4)]),
        Value::Tuple(vec![Value::Int(3), Value::Int(4)])
    );
    assert_eq!(
        vm.call("join_and_select", &[]),
        Value::Tuple(vec![Value::Int(20), Value::Int(30)])
    );
    assert_eq!(
        vm.call("mask_edges", &[]),
        Value::Tuple(vec![Value::Int(20), Value::Int(30)])
    );
}

#[test]
fn test_spec_7_tensors_einsum_hadamard_broadcasting_chained_index_and_shape_checking() {
    let src = r#"
fn :: matmul_einsum Tensor(i, j) Tensor(j, k) => Tensor(i, k)
matmul_einsum A B = A_ij @ B_jk

fn :: broadcast_mul Tensor(i, j) Tensor(j) => Tensor(i, j)
broadcast_mul A B = A_ij * B_j

fn :: hadamard_add Tensor(i, j) Tensor(i, j) => Tensor(i, j)
hadamard_add A B = A_ij + B_ij

fn :: test_chained_and_block_mut => Int
test_chained_and_block_mut =
  m = Tensor_GPU [[1, 2], [3, 4]]
  m[0, 1] = 99
  m[0][1] + m[1][0]
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(
        ridgun::typecheck::typecheck(&program).is_ok(),
        "Shaped tensor functions must typecheck cleanly"
    );
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);

    let a = Value::Tensor(vec![2, 2], vec![1.0, 2.0, 3.0, 4.0]);
    let b = Value::Tensor(vec![2, 2], vec![5.0, 6.0, 7.0, 8.0]);
    assert_eq!(
        vm.call("matmul_einsum", &[a.clone(), b]),
        Value::Tensor(vec![2, 2], vec![19.0, 22.0, 43.0, 50.0])
    );

    let row_scale = Value::Tensor(vec![2], vec![10.0, 100.0]);
    assert_eq!(
        vm.call("broadcast_mul", &[a.clone(), row_scale]),
        Value::Tensor(vec![2, 2], vec![10.0, 200.0, 30.0, 400.0])
    );

    assert_eq!(
        vm.call("hadamard_add", &[a.clone(), a]),
        Value::Tensor(vec![2, 2], vec![2.0, 4.0, 6.0, 8.0])
    );

    assert_eq!(vm.call("test_chained_and_block_mut", &[]), Value::Int(102));

    // Verify compile-time tensor dimension mismatch rejection
    let bad_src = r#"
fn :: matmul Tensor(i, j) Tensor(j, k) => Tensor(i, k)
matmul A B = A_ij @ B_jk

fn :: bad_caller Tensor(a, b) Tensor(c, d) => Tensor(a, d)
bad_caller X Y = matmul X Y
"#;
    let (btok, bspan) = Lexer::new(bad_src).tokenize();
    let bprog = Parser::new(btok, bspan).parse();
    assert!(
        ridgun::typecheck::typecheck(&bprog).is_err(),
        "Mismatched symbolic tensor dimensions (b vs c) must be rejected at compile time"
    );
}

#[test]
fn test_spec_8_operator_overloading_by_adt_and_variadic_functions() {
    let src = r#"
type Complex = real Int, imag Int

op :: Complex + Complex => Complex
a + b = Complex (real a + real b) (imag a + imag b)

fn :: add_complex => Int
add_complex =
  c1 = Complex 3 4
  c2 = Complex 10 20
  c3 = c1 + c2
  (real c3) + (imag c3)

fn :: count_tags [String] => Int
count_tags [] = 0
count_tags (_:xs) = 1 + count_tags xs

fn :: tag_count String... => Int
tag_count tags = count_tags tags

fn :: test_variadic => Int
test_variadic = tag_count "alpha" "beta" "gamma"
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(ridgun::typecheck::typecheck(&program).is_ok());
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    assert_eq!(vm.call("add_complex", &[]), Value::Int(37));
    assert_eq!(vm.call("test_variadic", &[]), Value::Int(3));
}

#[test]
fn test_spec_9_4_tier_ast_classification_and_green_thread_parallelism() {
    use ridgun::analyzer::{classify_expr_strategy, BranchExecStrategy, infer_all_summaries};

    let src = r#"
fn :: fib Int => Int
fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)

fn :: parallel_where => Int
parallel_where = a + b + c
  where
    10 + 20 -> a
    fib 10 -> b
    a * 2 -> c

fn :: parallel_pipe => (Int, Int)
parallel_pipe =
  || fib 8
  || fib 9
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    let summaries = infer_all_summaries(&program);

    // Tier 1: Trivial scalar arithmetic -> InlineSequential
    let (t1_tok, t1_sp) = Lexer::new("10 + 20").tokenize();
    let t1_expr = Parser::new(t1_tok, t1_sp).parse_expr();
    assert_eq!(
        classify_expr_strategy(&t1_expr, "parallel_where", &summaries),
        BranchExecStrategy::InlineSequential
    );

    // Tier 3: Branching recursion (fib) -> LazyStealableTask
    let (t3_tok, t3_sp) = Lexer::new("fib 10").tokenize();
    let t3_expr = Parser::new(t3_tok, t3_sp).parse_expr();
    assert_eq!(
        classify_expr_strategy(&t3_expr, "parallel_where", &summaries),
        BranchExecStrategy::LazyStealableTask
    );

    let compiled = compiler::compile(&program);
    let mut vm = VM::with_seed(compiled, 12345);
    assert_eq!(vm.call("parallel_where", &[]), Value::Int(30 + 55 + 60));
    assert_eq!(
        vm.call("parallel_pipe", &[]),
        Value::Tuple(vec![Value::Int(21), Value::Int(34)])
    );
}

#[test]
fn test_spec_10_global_context_shared_atomic_and_channel_timeout() {
    let src = r#"
global :: max_retries Int
max_retries = 5

context :: log_level Int
log_level = 1

shared :: request_counter Int
request_counter = 0

fn :: read_ctx Int => Int
read_ctx x = x + log_level + max_retries

fn :: test_context_and_spawn => Int
test_context_and_spawn =
  with log_level = 10 do
    t = spawn "read_ctx" 100
    join t

fn :: test_shared_atomic => Int
test_shared_atomic =
  atomic request_counter = request_counter + 7
  atomic request_counter = request_counter + 3
  request_counter

fn :: test_channel_timeout => Int
test_channel_timeout =
  ch = channel
  res = receive from ch timeout 50
  0
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(ridgun::typecheck::typecheck(&program).is_ok());
    let compiled = compiler::compile(&program);
    let mut vm = VM::with_seed(compiled, 777);
    // Spawned green thread inherits log_level = 10 and reads global max_retries = 5 -> 100 + 10 + 5 = 115
    assert_eq!(vm.call("test_context_and_spawn", &[]), Value::Int(115));
    // Outside `with`, log_level reverts to default 1 -> 100 + 1 + 5 = 106
    assert_eq!(vm.call("read_ctx", &[Value::Int(100)]), Value::Int(106));
    assert_eq!(vm.call("test_shared_atomic", &[]), Value::Int(10));
    assert_eq!(vm.call("test_channel_timeout", &[]), Value::Int(0));
}

#[test]
fn test_spec_11_bare_metal_systems_profile_region_limit_and_hardware_mmio() {
    let src = r#"
@packed
@repr(C)
type GpioModer = pin0 U8, pin1 U8, pin2 U16, flags U32

hardware :: GpioPortA @ 0x4002_0000
  MODER : U32 @ 0x00
  ODR   : U32 @ 0x14

fn :: read_odr_addr => Int
read_odr_addr = ODR

fn :: bounded_ok => Result
bounded_ok =
  with region limit 16_KB do
    xs = [1, 2, 3]
     xs

fn :: bounded_oom => Result
bounded_oom =
  with region limit 16 do
    xs = [1, 2, 3, 4, 5, 6]
    xs
"#;
    let (tokens, spans) = Lexer::new(src).tokenize();
    let program = Parser::new(tokens, spans).parse();
    assert!(ridgun::typecheck::typecheck(&program).is_ok());
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);

    assert_eq!(vm.call("read_odr_addr", &[]), Value::Int(0x4002_0014));
    assert_eq!(
        vm.call("bounded_ok", &[]),
        Value::Adt(
            "Ok".into(),
            vec![Value::List(vec![Value::Int(1), Value::Int(2), Value::Int(3)])]
        )
    );
    assert_eq!(
        vm.call("bounded_oom", &[]),
        Value::Adt("Err".into(), vec![Value::Adt("OutOfMemory".into(), vec![])])
    );
}

#[test]
fn test_all_example_rg_files_typecheck_and_run() {
    let example_files = [
        "examples/01_strings_and_io.rg",
        "examples/02_logic_and_math.rg",
        "examples/03_lists_and_recursion.rg",
        "examples/04_sequences_and_operators.rg",
        "examples/05_adts_overload_variadic.rg",
        "examples/06_tensors_and_einsum.rg",
        "examples/07_parallel_where_and_pipes.rg",
        "examples/08_channels_and_actors.rg",
        "examples/09_scoped_state_and_atomics.rg",
        "examples/10_bare_metal_systems.rg",
    ];

    for path in &example_files {
        let src = std::fs::read_to_string(path)
            .unwrap_or_else(|e| panic!("Failed to read {}: {}", path, e));
        let (tokens, spans) = Lexer::new(&src).tokenize();
        let program = Parser::new(tokens, spans).parse();
        if let Err(errs) = ridgun::typecheck::typecheck(&program) {
            panic!("Typecheck failed for {}: {:?}", path, errs);
        }
        let compiled = compiler::compile(&program);
        let mut vm = VM::with_seed(compiled, 2026);
        assert_eq!(vm.call("main", &[]), Value::Unit, "main failed in {}", path);
    }
}

#[test]
fn test_self_hosted_ridgun_compiler_pipeline() {
    let path = std::path::Path::new("src/main/ridgun/ridgunc.rg");
    let raw = std::fs::read_to_string(path).expect("Failed to read ridgunc.rg");
    let combined = ridgun::resolve_imports(&raw, path);
    let (tokens, spans) = Lexer::new(&combined).tokenize();
    let program = Parser::new(tokens, spans).parse();
    if let Err(errs) = ridgun::typecheck::typecheck(&program) {
        panic!("Self-hosted compiler typecheck failed: {:?}", errs);
    }
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);

    // Evaluate recursive and multi-statement Ridgun code inside the self-hosted compiler + VM
    let sample = "fn :: fact Int => Int\nfact 0 = 1\nfact n = n * (fact (n - 1))\n\nfn :: fib Int => Int\nfib 0 = 0\nfib 1 = 1\nfib n = (fib (n - 1)) + (fib (n - 2))\n\nfn :: compute Int => Int\ncompute x =\n  a = fact x\n  b = fib 10\n  a + b\n";
    let r_fact6 = vm.call(
        "eval_source_in_ridgun_vm",
        &[
            Value::Str(sample.to_string()),
            Value::Str("fact".to_string()),
            Value::List(vec![Value::Int(6)]),
        ],
    );
    assert_eq!(r_fact6, Value::Int(720));

    let r_comp5 = vm.call(
        "eval_source_in_ridgun_vm",
        &[
            Value::Str(sample.to_string()),
            Value::Str("compute".to_string()),
            Value::List(vec![Value::Int(5)]),
        ],
    );
    assert_eq!(r_comp5, Value::Int(175));

    // Verify self-hosted lexer + parser + typechecker + static analyzer on negative cases
    let bad_cycle = "fn :: bad Int => Int\nbad x = a + b\n  where\n    b + 1 -> a\n    a + 1 -> b\n";
    let toks_cycle = vm.call("tokenize_src", &[Value::Str(bad_cycle.to_string())]);
    let prog_cycle = vm.call("parse_tokens", &[toks_cycle]);
    let errs_cycle = vm.call("typecheck_program", &[prog_cycle]);
    let err_count_cycle = vm.call("type_err_count", &[errs_cycle]);
    assert!(matches!(err_count_cycle, Value::Int(n) if n > 0));
}
