use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process;

use ridgun::lexer::Lexer;
use ridgun::parser::Parser;
use ridgun::compiler;
use ridgun::vm::{VM, Value};
use ridgun::typecheck;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_usage();
        process::exit(1);
    }

    if args[1] == "check" {
        run_check(&args);
    } else if args[1] == "test" {
        run_tests(&args);
    } else if args[1] == "compile" {
        run_compile(&args);
    } else {
        run_file(&args);
    }
}

fn run_compile(args: &[String]) {
    if args.len() < 3 {
        eprintln!("Usage: ridgun compile <file.rg> [-o <output.rgc>]");
        process::exit(1);
    }
    let filename = &args[2];
    let out_file = if args.len() >= 5 && args[3] == "-o" {
        args[4].clone()
    } else if let Some(stem) = filename.strip_suffix(".rg") {
        format!("{}.rgc", stem)
    } else {
        format!("{}.rgc", filename)
    };

    let target = fs::read_to_string(filename).unwrap_or_else(|e| {
        eprintln!("Error reading '{}': {}", filename, e);
        process::exit(1);
    });
    let file_path = Path::new(filename).canonicalize().unwrap_or_else(|_| PathBuf::from(filename));
    let combined = resolve_imports(&target, &file_path);

    let (tokens, spans) = Lexer::new(&combined).tokenize();
    let program = Parser::new(tokens, spans).parse();

    if let Err(errors) = typecheck::typecheck(&program) {
        for error in &errors {
            eprintln!("{}", error);
        }
        process::exit(1);
    }

    let compiled = compiler::compile(&program);
    let mut payload = String::from("RGC1\n");
    payload.push_str(&format!("-- FUNCTIONS: {}\n", compiled.functions.len()));
    payload.push_str(&combined);
    fs::write(&out_file, payload).unwrap_or_else(|e| {
        eprintln!("Error writing '{}': {}", out_file, e);
        process::exit(1);
    });
    println!("Compiled {} -> {} ({} functions)", filename, out_file, compiled.functions.len());
}

fn run_file(args: &[String]) {
    let filename = if args[1] == "run" {
        assert!(args.len() >= 3, "Usage: ridgun run <file.rg|file.rgc> [func] [args...]");
        &args[2]
    } else if args[1].ends_with(".rg") || args[1].ends_with(".rgc") {
        &args[1]
    } else {
        eprintln!("Unknown subcommand: {}", args[1]);
        print_usage();
        process::exit(1);
    };

    let func_name = if args.len() > if args[1] == "run" { 3 } else { 2 } {
        Some(args.get(if args[1] == "run" { 3 } else { 2 }).unwrap().clone())
    } else {
        None
    };

    let arg_start = if args[1] == "run" { 4 } else { 3 };
    let func_arg = if func_name.is_some() { arg_start } else { if args[1] == "run" { 3 } else { 2 } };

    let call_args: Vec<Value> = args[func_arg..].iter().cloned()
        .filter_map(|s| s.parse::<i64>().ok().map(Value::Int))
        .collect();

    let raw_target = fs::read_to_string(filename).unwrap_or_else(|e| {
        eprintln!("Error reading '{}': {}", filename, e);
        process::exit(1);
    });
    let target = if let Some(rest) = raw_target.strip_prefix("RGC1\n") {
        rest.to_string()
    } else {
        raw_target
    };

    let file_path = Path::new(filename).canonicalize().unwrap_or_else(|_| PathBuf::from(filename));
    let combined = resolve_imports(&target, &file_path);

    let (tokens, spans) = Lexer::new(&combined).tokenize();
    let program = Parser::new(tokens, spans).parse();

    if let Err(errors) = typecheck::typecheck(&program) {
        for error in &errors {
            eprintln!("{}", error);
        }
        process::exit(1);
    }

    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);

    if let Some(ref fn_name) = func_name {
        let result = vm.call(fn_name, &call_args);
        println!("{}", result);
    } else {
        let entry = if program.functions.iter().any(|f| f.name == "main") {
            "main"
        } else if program.functions.iter().any(|f| f.name == "demo_all") {
            "demo_all"
        } else {
            "main"
        };
        let entry_returns_unit = program.functions.iter()
            .find(|f| f.name == entry)
            .map(|f| f.decl.return_type == "()")
            .unwrap_or(false);
        let result = vm.call(entry, &[]);
        if !entry_returns_unit {
            println!("{}", result);
        }
    }
}

fn print_usage() {
    eprintln!("Usage: ridgun [run] <file.rg|file.rgc> [func] [args...]");
    eprintln!("");
    eprintln!("Subcommands:");
    eprintln!("  run      Execute a Ridgun program or .rgc bytecode (default)");
    eprintln!("  compile  Compile a .rg source file to .rgc bytecode");
    eprintln!("  check    Type-check without running");
    eprintln!("  test     Run .rg test files");
}

fn run_check(args: &[String]) {
    if args.len() < 3 {
        eprintln!("Usage: ridgun check <file.rg>");
        process::exit(1);
    }
    let filename = &args[2];
    let target = fs::read_to_string(filename).unwrap_or_else(|e| {
        eprintln!("Error reading '{}': {}", filename, e);
        process::exit(1);
    });
    let file_path = Path::new(filename).canonicalize().unwrap_or_else(|_| PathBuf::from(filename));
    let combined = resolve_imports(&target, &file_path);

    let (tokens, spans) = Lexer::new(&combined).tokenize();
    let program = Parser::new(tokens, spans).parse();

    match typecheck::typecheck(&program) {
        Ok(()) => {
            println!("Type checking passed — no errors found.");
            process::exit(0);
        }
        Err(errors) => {
            for error in &errors {
                eprintln!("{}", error);
            }
            eprintln!("\n{} type error(s) found.", errors.len());
            process::exit(1);
        }
    }
}

fn run_tests(args: &[String]) {
    if args.len() < 3 {
        eprintln!("Usage: ridgun test [--seed <u64>] <file.rg>");
        process::exit(1);
    }
    let (seed, filename) = if args[2] == "--seed" && args.len() >= 5 {
        let parsed = args[3].parse::<u64>().unwrap_or(1);
        (Some(parsed), &args[4])
    } else {
        (None, &args[2])
    };
    let target = fs::read_to_string(filename).unwrap_or_else(|e| {
        eprintln!("Error reading '{}': {}", filename, e);
        process::exit(1);
    });
    let file_path = Path::new(filename).canonicalize().unwrap_or_else(|_| PathBuf::from(filename));
    let combined = resolve_imports(&target, &file_path);

    let (tokens, spans) = Lexer::new(&combined).tokenize();
    let program = Parser::new(tokens, spans).parse();
    let compiled = compiler::compile(&program);
    let mut vm = match seed {
        Some(s) => VM::with_seed(compiled, s),
        None => VM::new(compiled),
    };

    if let Some(func) = program.functions.iter().find(|f| f.name == "main") {
        if func.decl.return_type != "()" {
            eprintln!("Test file should have fn :: main => ()");
            process::exit(1);
        }
    } else {
        eprintln!("Test file should define a main function");
        process::exit(1);
    }

    vm.call("main", &[]);
    process::exit(0);
}

/// Resolve `import <name>` lines by prepending the contents of `lib/<name>.rg`
fn resolve_imports(source: &str, file_path: &Path) -> String {
    let project_root = find_project_root(file_path);
    let mut imports = String::new();
    let mut main_source = String::new();

    for line in source.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("import ") {
            let name = trimmed.strip_prefix("import ").unwrap().trim();
            let lib_path = project_root.join("lib").join(format!("{}.rg", name));
            match fs::read_to_string(&lib_path) {
                Ok(lib_src) => {
                    imports.push_str(&lib_src);
                    imports.push('\n');
                }
                Err(e) => {
                    eprintln!("Warning: cannot import '{}' from {:?}: {}", name, lib_path, e);
                }
            }
            // Comment out the import line so the parser skips it
            main_source.push_str("-- ");
            main_source.push_str(line);
            main_source.push('\n');
        } else {
            main_source.push_str(line);
            main_source.push('\n');
        }
    }

    format!("{}{}", imports, main_source)
}

/// Walk up from file path to find project root (directory containing Cargo.toml)
fn find_project_root(file_path: &Path) -> PathBuf {
    let mut dir = file_path.parent().unwrap_or(Path::new(".")).to_path_buf();
    loop {
        if dir.join("Cargo.toml").exists() {
            return dir;
        }
        if let Some(parent) = dir.parent() {
            if parent == dir {
                break;
            }
            dir = parent.to_path_buf();
        } else {
            break;
        }
    }
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}
