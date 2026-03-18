use std::env;
use std::fs;
use std::process;

use ridgun::lexer::Lexer;
use ridgun::parser::Parser;
use ridgun::compiler;
use ridgun::vm::VM;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 4 || args[1] != "run" {
        eprintln!("Usage: ridgun run <file.rg> <function> [args...]");
        eprintln!("Example: ridgun run sample.rg factorial 5");
        process::exit(1);
    }

    let filename = &args[2];
    let func_name = &args[3];
    let func_args: Vec<i64> = args[4..].iter()
        .map(|a| a.parse::<i64>().unwrap_or_else(|_| {
            eprintln!("Invalid argument: {}", a);
            process::exit(1);
        }))
        .collect();

    // Read source
    let source = fs::read_to_string(filename).unwrap_or_else(|e| {
        eprintln!("Error reading '{}': {}", filename, e);
        process::exit(1);
    });

    // Lex → Parse → Compile → Run
    let tokens = Lexer::new(&source).tokenize();
    let program = Parser::new(tokens).parse();
    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    let result = vm.call(func_name, &func_args);

    println!("{}", result);
}
