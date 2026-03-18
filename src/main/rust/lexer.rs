/// Ridgun Lexer — Tokenizes .rg source files

#[derive(Debug, Clone, PartialEq)]
pub enum Token {
    Fn,
    ColonColon,
    FatArrow,
    Arrow,
    Equals,
    Plus,
    Minus,
    Star,
    LParen,
    RParen,
    LBracket,
    RBracket,
    Pipe,
    Colon,
    Comma,
    IntLit(i64),
    Ident(String),
    Newline,
    Eof,
}

pub struct Lexer {
    chars: Vec<char>,
    pos: usize,
}

impl Lexer {
    pub fn new(input: &str) -> Self {
        Lexer {
            chars: input.chars().collect(),
            pos: 0,
        }
    }

    pub fn tokenize(&mut self) -> Vec<Token> {
        let mut tokens = Vec::new();
        let mut last_was_newline = true;

        loop {
            match self.next_token() {
                Token::Eof => {
                    tokens.push(Token::Eof);
                    break;
                }
                Token::Newline => {
                    if !last_was_newline {
                        tokens.push(Token::Newline);
                        last_was_newline = true;
                    }
                }
                token => {
                    tokens.push(token);
                    last_was_newline = false;
                }
            }
        }

        tokens
    }

    fn peek(&self) -> Option<char> {
        self.chars.get(self.pos).copied()
    }

    fn advance(&mut self) -> Option<char> {
        let ch = self.chars.get(self.pos).copied();
        self.pos += 1;
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
                } else {
                    Token::Equals
                }
            }
            Some('+') => { self.advance(); Token::Plus }
            Some('*') => { self.advance(); Token::Star }
            Some('(') => { self.advance(); Token::LParen }
            Some(')') => { self.advance(); Token::RParen }
            Some('[') => { self.advance(); Token::LBracket }
            Some(']') => { self.advance(); Token::RBracket }
            Some('|') => { self.advance(); Token::Pipe }
            Some(',') => { self.advance(); Token::Comma }
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
            _ => Token::Ident(s),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fn_decl() {
        let tokens = Lexer::new("fn :: sum Int Int => Int").tokenize();
        assert_eq!(tokens, vec![
            Token::Fn, Token::ColonColon,
            Token::Ident("sum".into()), Token::Ident("Int".into()),
            Token::Ident("Int".into()), Token::FatArrow,
            Token::Ident("Int".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_fn_def() {
        let tokens = Lexer::new("sum a b = a + b").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("sum".into()), Token::Ident("a".into()),
            Token::Ident("b".into()), Token::Equals,
            Token::Ident("a".into()), Token::Plus,
            Token::Ident("b".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_pattern_match() {
        let tokens = Lexer::new("factorial 0 = 1").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("factorial".into()), Token::IntLit(0),
            Token::Equals, Token::IntLit(1), Token::Eof,
        ]);
    }

    #[test]
    fn test_comment_skipped() {
        let tokens = Lexer::new("-- comment\nsum a b = a + b").tokenize();
        assert_eq!(tokens[0], Token::Ident("sum".into()));
    }

    #[test]
    fn test_recursive_expr() {
        let tokens = Lexer::new("factorial n = n * factorial (n - 1)").tokenize();
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
        let tokens = Lexer::new("[1, 2, 3]").tokenize();
        assert_eq!(tokens, vec![
            Token::LBracket, Token::IntLit(1), Token::Comma,
            Token::IntLit(2), Token::Comma, Token::IntLit(3),
            Token::RBracket, Token::Eof,
        ]);
    }

    #[test]
    fn test_list_type() {
        let tokens = Lexer::new("[Int]").tokenize();
        assert_eq!(tokens, vec![
            Token::LBracket, Token::Ident("Int".into()),
            Token::RBracket, Token::Eof,
        ]);
    }

    #[test]
    fn test_cons_pattern() {
        let tokens = Lexer::new("(x:xs)").tokenize();
        assert_eq!(tokens, vec![
            Token::LParen, Token::Ident("x".into()),
            Token::Colon, Token::Ident("xs".into()),
            Token::RParen, Token::Eof,
        ]);
    }

    #[test]
    fn test_concat() {
        let tokens = Lexer::new("a :: b").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("a".into()), Token::ColonColon,
            Token::Ident("b".into()), Token::Eof,
        ]);
    }

    #[test]
    fn test_arrow() {
        let tokens = Lexer::new("Int Int switch -> Int Int").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("Int".into()), Token::Ident("Int".into()),
            Token::Ident("switch".into()), Token::Arrow,
            Token::Ident("Int".into()), Token::Ident("Int".into()),
            Token::Eof,
        ]);
    }

    #[test]
    fn test_seq_selector_paren() {
        let tokens = Lexer::new("s(+_)").tokenize();
        assert_eq!(tokens, vec![
            Token::Ident("s".into()),
            Token::LParen, Token::Plus, Token::Ident("_".into()),
            Token::RParen, Token::Eof,
        ]);
    }

    #[test]
    fn test_seq_bind_paren() {
        let tokens = Lexer::new("(s)").tokenize();
        assert_eq!(tokens, vec![
            Token::LParen, Token::Ident("s".into()),
            Token::RParen, Token::Eof,
        ]);
    }
}
