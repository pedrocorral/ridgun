pub mod lexer;
pub mod parser;
pub mod compiler;
pub mod vm;
pub mod typecheck;
pub mod greenthread;
pub mod scheduler;
pub mod mailbox;
pub mod region;
pub mod channel;
pub mod analyzer;

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

/// Recursively resolve `import <name>` directives from the current directory, `src/main/ridgun/`, or `lib/`.
pub fn resolve_imports(source: &str, file_path: &Path) -> String {
    let mut visited = HashSet::new();
    if let Ok(canon) = file_path.canonicalize() {
        visited.insert(canon);
    }
    resolve_imports_inner(source, file_path, &mut visited)
}

fn resolve_imports_inner(source: &str, file_path: &Path, visited: &mut HashSet<PathBuf>) -> String {
    let project_root = find_project_root(file_path);
    let parent_dir = file_path.parent().unwrap_or(Path::new("."));
    let mut imports = String::new();
    let mut main_source = String::new();

    for line in source.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("import ") {
            let name = rest.trim();
            let candidates = [
                parent_dir.join(format!("{}.rg", name)),
                project_root.join("src/main/ridgun").join(format!("{}.rg", name)),
                project_root.join("lib").join(format!("{}.rg", name)),
            ];
            if let Some(found_path) = candidates.iter().find(|p| p.exists()) {
                let canon = found_path.canonicalize().unwrap_or_else(|_| found_path.clone());
                if visited.insert(canon.clone()) {
                    if let Ok(lib_src) = fs::read_to_string(&canon) {
                        let resolved_sub = resolve_imports_inner(&lib_src, &canon, visited);
                        imports.push_str(&resolved_sub);
                        imports.push('\n');
                    }
                }
            }
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

pub fn find_project_root(file_path: &Path) -> PathBuf {
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
    PathBuf::from(".")
}

