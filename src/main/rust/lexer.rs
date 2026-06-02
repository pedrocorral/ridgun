/// Ridgun Lexer — Tokenizes .rg source files

/// Source location for error reporting
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Span {
    pub start_char: usize,
    pub end_char: usize,
    pub start_line: usize,
    pub start_col: usize,
}

impl Span {
    pub fn new(start_char: usize, end_char: usize, start_line: usize, start_col: usize) -> Self {
        Span { start_char, end_char, start_line, start_col }
    }

    pub fn len(&self) -> usize {
        self.end_char - self.start_char
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Token {
    // Keywords
    Fn,
    Op,
    Type,
    Import,
    True,
    False,
    Otherwise,
    Where,

    // Punctuation
    ColonColon,
    FatArrow,
    Arrow,
    Equals,
    EqualEqual,
    Plus,
    Minus,
    Star,
    Slash,
    Greater,
    GreaterEq,
    Less,
    LessEq,
    At,
    LParen,
    RParen,
    LBracket,
    RBracket,
    LBrace,
    RBrace,
    Pipe,
    DoublePipe,
    Colon,
    Comma,

    // Literals
    IntLit(i64),
    StringLit(String),
    RawStringLit(String),

    // Identifiers
    Ident(String),

    // Structure
    Newline,
    Eof,
}

pub struct Lexer {
    chars: Vec<char>,
    pos: usize,
    line: usize,
    col: usize,
}

impl Lexer {
    pub fn new(input: &str) -> Self {
        Lexer {
            chars: input.chars().collect(),
            pos: 0,
            line: 1,
            col: 0,
        }
    }

    pub fn tokenize(&mut self) -> (Vec<Token>, Vec<Span>) {
        let mut tokens = Vec::new();
        let mut spans = Vec::new();
        let mut last_was_newline = true;

        loop {
            let start_pos = self.pos;
            let start_line = self.line;
            let start_col = self.col;
            let token = self.next_token();
            let end_pos = self.pos;

            match token {
                Token::Eof => {
                    let span = Span::new(start_pos, end_pos, start_line, start_col);
                    tokens.push(Token::Eof);
                    spans.push(span);
                    break;
                }
                Token::Newline => {
                    if !last_was_newline {
                        let span = Span::new(start_pos, end_pos, start_line, start_col);
                        tokens.push(Token::Newline);
                        spans.push(span);
                        last_was_newline = true;
                    }
                }
                token => {
                    let span = Span::new(start_pos, end_pos, start_line, start_col);
                    tokens.push(token);
                    spans.push(span);
                    last_was_newline = false;
                }
            }
        }

        (tokens, spans)
    }

    fn peek(&self) -> Option<char> {
        self.chars.get(self.pos).copied()
    }

    fn advance(&mut self) -> Option<char> {
        let ch = self.chars.get(self.pos).copied();
        self.pos += 1;
        if let Some('\n') = ch {
            self.line += 1;
            self.col = 0;
        } else {
            self.col += 1;
        }
        ch
    }

    fn skip_spaces(&mut self) {
        while let Some(ch) = self.peek() {
            if ch == ' ' || ch == '\t' || ch == '\r' {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn next_token(&mut self) -> Token {
        self.skip_spaces();

        match self.peek() {
            None => Token::Eof,
            Some('\n') => {
                self.advance();
                Token::Newline
            }
            Some('-') => {
                self.advance();
                if self.peek() == Some('-') {
                    // Comment — skip to end of line
                    self.advance();
                    while let Some(ch) = self.peek() {
                        if ch == '\n' {
                            break;
                        }
                        self.advance();
                    }
                    if self.peek() == Some('\n') {
                        self.advance();
                    }
                    Token::Newline
                } else if self.peek() == Some('>') {
                    self.advance();
                    Token::Arrow
                } else {
                    Token::Minus
                }
            }
            Some(':') => {
                self.advance();
                if self.peek() == Some(':') {
                    self.advance();
                    Token::ColonColon
                } else {
                    Token::Colon
                }
            }
            Some('=') => {
                self.advance();
                if self.peek() == Some('>') {
                    self.advance();
                    Token::FatArrow
                } else if self.peek() == Some('=') {
                    self.advance();
                    Token::EqualEqual
                } else {
                    Token::Equals
                }
            }
            Some('>') => {
                self.advance();
                if self.peek() == Some('=') {
                    self.advance();
                    Token::GreaterEq
                } else {
                    Token::Greater
                }
            }
            Some('<') => {
                self.advance();
                if self.peek() == Some('=') {
                    self.advance();
                    Token::LessEq
                } else {
                    Token::Less
                }
            }
            Some('|') => {
                self.advance();
                if self.peek() == Some('|') {
                    self.advance();
                    Token::DoublePipe
                } else {
                    Token::Pipe
                }
            }
            Some('+') => { self.advance(); Token::Plus }
            Some('*') => { self.advance(); Token::Star }
            Some('/') => { self.advance(); Token::Slash }
            Some('@') => { self.advance(); Token::At }
            Some('{') => { self.advance(); Token::LBrace }
            Some('}') => { self.advance(); Token::RBrace }
            Some('(') => { self.advance(); Token::LParen }
            Some(')') => { self.advance(); Token::RParen }
            Some('[') => { self.advance(); Token::LBracket }
            Some(']') => { self.advance(); Token::RBracket }
            Some(',') => { self.advance(); Token::Comma }
            Some('"') => self.read_string(),
            Some('\'') => self.read_raw_string(),
            Some(ch) if ch.is_ascii_digit() => self.read_number(),
            Some(ch) if ch.is_alphabetic() || ch == '_' => self.read_ident(),
            Some(ch) => panic!("Unexpected character: '{}'", ch),
        }
    }

    fn read_number(&mut self) -> Token {
        let mut s = String::new();
        while let Some(ch) = self.peek() {
            if ch.is_ascii_digit() {
                s.push(ch);
                self.advance();
            } else {
                break;
            }
        }
        Token::IntLit(s.parse().unwrap())
    }

    fn read_ident(&mut self) -> Token {
        let mut s = String::new();
        while let Some(ch) = self.peek() {
            if ch.is_alphanumeric() || ch == '_' {
                s.push(ch);
                self.advance();
            } else {
                break;
            }
        }
        match s.as_str() {
            "fn" => Token::Fn,
            "op" => Token::Op,
            "type" => Token::Type,
            "import" => Token::Import,
            "True" => Token::True,
            "False" => Token::False,
            "otherwise" => Token::Otherwise,
            "where" => Token::Where,
            _ => Token::Ident(s),
        }
    }

    /// Read a double-quoted string: "..." with {expr} interpolation
    /// {{ produces a literal { in the output
    fn read_string(&mut self) -> Token {
        self.advance(); // consume opening "
        let mut s = String::new();
        loop {
            match self.peek() {
                None => panic!("Unterminated string literal"),
                Some('"') => {
                    self.advance();
                    break;
                }
                Some('{') => {
                    self.advance();
                    if self.peek() == Some('{') {
                        // {{ => literal {
                        self.advance();
                        s.push('{');
                    } else {
                        // {expr} — include braces in the string for later processing
                        s.push('{');
                        while let Some(ch) = self.peek() {
                            if ch == '}' {
                                s.push('}');
                                self.advance();
                                break;
                            }
                            s.push(ch);
                            self.advance();
                        }
                    }
                }
                Some('}') => {
                    self.advance();
                    if self.peek() == Some('}') {
                        // }} => literal }
                        self.advance();
                        s.push('}');
                    } else {
                        s.push('}');
                    }
                }
                Some('\\') => {
                    self.advance();
                    match self.peek() {
                        Some('n') => { self.advance(); s.push('\n'); }
                        Some('t') => { self.advance(); s.push('\t'); }
                        Some('"') => { self.advance(); s.push('"'); }
                        Some('\\') => { self.advance(); s.push('\\'); }
                        Some(ch) => { s.push('\\'); s.push(ch); self.advance(); }
                        None => panic!("Unterminated escape in string"),
                    }
                }
                Some(ch) => {
                    s.push(ch);
                    self.advance();
                }
            }
        }
        Token::StringLit(s)
    }

    /// Read a single-quoted raw string: '...' — no interpolation
    fn read_raw_string(&mut self) -> Token {
        self.advance(); // consume opening '
        let mut s = String::new();
        loop {
            match self.peek() {
                None => panic!("Unterminated raw string literal"),
                Some('\'') => {
                    self.advance();
                    break;
                }
                Some(ch) => {
                    s.push(ch);
                    self.advance();
                }
            }
        }
        Token::RawStringLit(s)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fn_decl() {
        let (tokens, _spans) = Lexer::new("fn :: sum Int Int => Int").tokenize();
        assert_eq!(tokens, vec![
            Token::Fn, Token::ColonColon,
            Token::Ident("sum".into()), Token::Ident("Int".into()),
            Token::Ident("Int".into()), Token::FatArrow,
            Token::Ident("Int".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_fn_def() {
        let (tokens, _spans) = Lexer::new("sum a b = a + b").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("sum".into()), Token::Ident("a".into()),
            Token::Ident("b".into()), Token::Equals,
            Token::Ident("a".into()), Token::Plus,
            Token::Ident("b".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_pattern_match() {
        let (tokens, _spans) = Lexer::new("factorial 0 = 1").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("factorial".into()), Token::IntLit(0),
            Token::Equals, Token::IntLit(1), Token::Eof,
        ]);
    }

    #[test]
    fn test_comment_skipped() {
        let (tokens, _spans) = Lexer::new("-- comment\nsum a b = a + b").tokenize();
        assert_eq!(tokens[0], Token::Ident("sum".into()));
    }

    #[test]
    fn test_recursive_expr() {
        let (tokens, _spans) = Lexer::new("factorial n = n * factorial (n - 1)").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("factorial".into()), Token::Ident("n".into()),
            Token::Equals, Token::Ident("n".into()), Token::Star,
            Token::Ident("factorial".into()), Token::LParen,
            Token::Ident("n".into()), Token::Minus, Token::IntLit(1),
            Token::RParen, Token::Eof,
        ]);
    }

    #[test]
    fn test_list_literal() {
        let (tokens, _spans) = Lexer::new("[1, 2, 3]").tokenize();
        assert_eq!(tokens, vec![
            Token::LBracket, Token::IntLit(1), Token::Comma,
            Token::IntLit(2), Token::Comma, Token::IntLit(3),
            Token::RBracket, Token::Eof,
        ]);
    }

    #[test]
    fn test_list_type() {
        let (tokens, _spans) = Lexer::new("[Int]").tokenize();
        assert_eq!(tokens, vec![
            Token::LBracket, Token::Ident("Int".into()),
            Token::RBracket, Token::Eof,
        ]);
    }

    #[test]
    fn test_cons_pattern() {
        let (tokens, _spans) = Lexer::new("(x:xs)").tokenize();
        assert_eq!(tokens, vec![
            Token::LParen, Token::Ident("x".into()),
            Token::Colon, Token::Ident("xs".into()),
            Token::RParen, Token::Eof,
        ]);
    }

    #[test]
    fn test_concat() {
        let (tokens, _spans) = Lexer::new("a :: b").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("a".into()), Token::ColonColon,
            Token::Ident("b".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_arrow() {
        let (tokens, _spans) = Lexer::new("Int Int switch -> Int Int").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("Int".into()), Token::Ident("Int".into()),
            Token::Ident("switch".into()), Token::Arrow,
            Token::Ident("Int".into()), Token::Ident("Int".into()),
            Token::Eof,
        ]);
    }

    #[test]
    fn test_seq_selector_paren() {
        let (tokens, _spans) = Lexer::new("s(+_)").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("s".into()),
            Token::LParen, Token::Plus, Token::Ident("_".into()),
            Token::RParen, Token::Eof,
        ]);
    }

    #[test]
    fn test_seq_bind_paren() {
        let (tokens, _spans) = Lexer::new("(s)").tokenize();
        assert_eq!(tokens, vec![
            Token::LParen, Token::Ident("s".into()),
            Token::RParen, Token::Eof,
        ]);
    }

    #[test]
    fn test_at_operator() {
        let (tokens, _spans) = Lexer::new("A @ B").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("A".into()), Token::At,
            Token::Ident("B".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_string_literal() {
        let (tokens, _spans) = Lexer::new("\"hello world\"").tokenize();
        assert_eq!(tokens, vec![
            Token::StringLit("hello world".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_string_interpolation() {
        let (tokens, _spans) = Lexer::new("\"result: {my_func x}\"").tokenize();
        assert_eq!(tokens, vec![
            Token::StringLit("result: {my_func x}".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_string_escaped_braces() {
        let (tokens, _spans) = Lexer::new("\"{{not code}}\"").tokenize();
        assert_eq!(tokens, vec![
            Token::StringLit("{not code}".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_raw_string() {
        let (tokens, _spans) = Lexer::new("'hello {world}'").tokenize();
        assert_eq!(tokens, vec![
            Token::RawStringLit("hello {world}".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_raw_string_no_interpolation() {
        let (tokens, _spans) = Lexer::new("'{this is just chars}'").tokenize();
        assert_eq!(tokens, vec![
            Token::RawStringLit("{this is just chars}".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_bool_literals() {
        let (tokens, _spans) = Lexer::new("True False").tokenize();
        assert_eq!(tokens, vec![
            Token::True, Token::False, Token::Eof,
        ]);
    }

    #[test]
    fn test_comparison_operators() {
        let (tokens, _spans) = Lexer::new("a == b > c < d >= e <= f").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("a".into()), Token::EqualEqual, Token::Ident("b".into()),
            Token::Greater, Token::Ident("c".into()),
            Token::Less, Token::Ident("d".into()),
            Token::GreaterEq, Token::Ident("e".into()),
            Token::LessEq, Token::Ident("f".into()),
            Token::Eof,
        ]);
    }

    #[test]
    fn test_op_keyword() {
        let (tokens, _spans) = Lexer::new("op :: add Int to Int => Int").tokenize();
        assert_eq!(tokens[0], Token::Op);
    }

    #[test]
    fn test_import_keyword() {
        let (tokens, _spans) = Lexer::new("import test").tokenize();
        assert_eq!(tokens, vec![
            Token::Import, Token::Ident("test".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_guard_pipe() {
        let (tokens, _spans) = Lexer::new("| a == b = True\n| otherwise = False").tokenize();
        assert_eq!(tokens[0], Token::Pipe);
        assert_eq!(tokens[2], Token::EqualEqual);
        assert_eq!(tokens[4], Token::Equals);
        assert_eq!(tokens[5], Token::True);
    }

    #[test]
    fn test_double_pipe() {
        let (tokens, _spans) = Lexer::new("|| run a").tokenize();
        assert_eq!(tokens[0], Token::DoublePipe);
    }
}
