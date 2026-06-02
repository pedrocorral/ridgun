/// Ridgun Compiler Error — formatted error reporting with source spans

use std::fmt;
use crate::lexer::Span;

pub struct CompilerError {
    pub span: Span,
    pub message: String,
}

impl CompilerError {
    pub fn new(span: Span, message: &str) -> Self {
        CompilerError { span, message: message.to_string() }
    }
}

impl fmt::Display for CompilerError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "error at {}:{}: {}",
            self.span.start_line, self.span.start_col, self.message)
    }
}

pub fn print_error(error: &CompilerError) {
    eprintln!("{}", error);
}

pub fn print_errors(errors: &[CompilerError]) -> usize {
    for e in errors {
        print_error(e);
    }
    errors.len()
}
