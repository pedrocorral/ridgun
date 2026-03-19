use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process;

use ridgun::lexer::Lexer;
use ridgun::parser::Parser;
use ridgun::compiler;
use ridgun::vm::VM;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: ridgun [run] <file.rg>");
        eprintln!("");
        eprintln!("Subcommands:");
        eprintln!("  run      Execute a Ridgun program (default)");
        eprintln!("  check    Type-check without running (planned)");
        eprintln!("  compile  Emit bytecode .rgc file (planned)");
        eprintln!("  fmt      Format source code (planned)");
        eprintln!("  repl     Interactive REPL (planned)");
        eprintln!("  test     Run tests with formatted output (planned)");
        process::exit(1);
    }

    let filename = if args[1] == "run" {
        if args.len() < 3 {
            eprintln!("Usage: ridgun run <file.rg>");
            process::exit(1);
        }
        &args[2]
    } else if args[1].ends_with(".rg") {
        &args[1]
    } else {
        eprintln!("Unknown subcommand: {}", args[1]);
        eprintln!("Usage: ridgun [run] <file.rg>");
        process::exit(1);
    };

    // Read source
    let source = fs::read_to_string(filename).unwrap_or_else(|e| {
        eprintln!("Error reading '{}': {}", filename, e);
        process::exit(1);
    });

    // Resolve imports
    let file_path = Path::new(filename).canonicalize().unwrap_or_else(|_| PathBuf::from(filename));
    let combined = resolve_imports(&source, &file_path);

    // Lex → Parse → Compile → Run
    let tokens = Lexer::new(&combined).tokenize();
    let program = Parser::new(tokens).parse();

    let main_returns_unit = program.functions.iter()
        .find(|f| f.name == "main")
        .map(|f| f.decl.return_type == "()")
        .unwrap_or(false);

    let compiled = compiler::compile(&program);
    let mut vm = VM::new(compiled);
    let result = vm.call("main", &[]);

    if !main_returns_unit {
        println!("{}", result);
    }
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
