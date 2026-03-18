/// Ridgun Parser — Recursive descent parser producing an AST

use std::collections::HashMap;
use crate::lexer::Token;

// ── AST Types ──────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    IntLit(i64),
    Var(String),
    BinOp(BinOp, Box<Expr>, Box<Expr>),
    Call(String, Vec<Expr>),
    ListLit(Vec<Expr>),
    ListEmpty,
    SeqSelect(Box<Expr>, String),
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Concat,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Pattern {
    Lit(i64),
    Var(String),
    Wildcard,
    ListEmpty,
    ListCons(Box<Pattern>, Box<Pattern>),
    SeqBind(String),
}

#[derive(Debug, Clone)]
pub struct FnDecl {
    pub name: String,
    pub param_types: Vec<String>,
    pub return_type: String,
}

#[derive(Debug, Clone)]
pub struct FnCase {
    pub patterns: Vec<Pattern>,
    pub body: Expr,
}

#[derive(Debug, Clone)]
pub struct FnDef {
    pub name: String,
    pub decl: FnDecl,
    pub cases: Vec<FnCase>,
}

#[derive(Debug)]
pub struct Program {
    pub functions: Vec<FnDef>,
}

// ── Intermediate parse items ───────────────────────────────

#[derive(Debug)]
enum Item {
    Decl(FnDecl),
    Def(String, FnCase),
}

// ── Parser ─────────────────────────────────────────────────

pub struct Parser {
    tokens: Vec<Token>,
    pos: usize,
}

impl Parser {
    pub fn new(tokens: Vec<Token>) -> Self {
        Parser { tokens, pos: 0 }
    }

    pub fn parse(&mut self) -> Program {
        let mut items = Vec::new();
        self.skip_newlines();

        while !self.at_eof() {
            items.push(self.parse_item());
            self.skip_newlines();
        }

        self.build_program(items)
    }

    fn peek(&self) -> &Token {
        self.tokens.get(self.pos).unwrap_or(&Token::Eof)
    }

    fn advance(&mut self) -> Token {
        let tok = self.tokens.get(self.pos).cloned().unwrap_or(Token::Eof);
        self.pos += 1;
        tok
    }

    fn expect(&mut self, expected: &Token) {
        let got = self.advance();
        assert_eq!(&got, expected, "Expected {:?}, got {:?}", expected, got);
    }

    fn at_eof(&self) -> bool {
        matches!(self.peek(), Token::Eof)
    }

    fn skip_newlines(&mut self) {
        while matches!(self.peek(), Token::Newline) {
            self.advance();
        }
    }

    // ── Top-level items ────────────────────────────────────

    fn parse_item(&mut self) -> Item {
        match self.peek() {
            Token::Fn => self.parse_fn_decl(),
            Token::Ident(_) => self.parse_fn_case(),
            other => panic!("Expected 'fn' or identifier, got {:?}", other),
        }
    }

    fn parse_fn_decl(&mut self) -> Item {
        self.expect(&Token::Fn);
        self.expect(&Token::ColonColon);

        let name = match self.advance() {
            Token::Ident(s) => s,
            other => panic!("Expected function name, got {:?}", other),
        };

        let mut param_types = Vec::new();
        while !matches!(self.peek(), Token::FatArrow | Token::Arrow) {
            match self.peek() {
                Token::LBracket => {
                    // [type] list type syntax
                    self.advance(); // consume [
                    let inner = match self.advance() {
                        Token::Ident(s) => s,
                        other => panic!("Expected type inside [...], got {:?}", other),
                    };
                    self.expect(&Token::RBracket);
                    param_types.push(format!("[{}]", inner));
                }
                _ => {
                    match self.advance() {
                        Token::Ident(s) => param_types.push(s),
                        other => panic!("Expected type, got {:?}", other),
                    }
                }
            }
        }

        // Accept both => and -> for return type separator
        match self.peek() {
            Token::FatArrow | Token::Arrow => { self.advance(); }
            other => panic!("Expected => or ->, got {:?}", other),
        }

        let return_type = match self.peek() {
            Token::LBracket => {
                self.advance();
                let inner = match self.advance() {
                    Token::Ident(s) => s,
                    other => panic!("Expected type inside [...], got {:?}", other),
                };
                self.expect(&Token::RBracket);
                format!("[{}]", inner)
            }
            _ => match self.advance() {
                Token::Ident(s) => s,
                other => panic!("Expected return type, got {:?}", other),
            },
        };

        Item::Decl(FnDecl { name, param_types, return_type })
    }

    fn parse_fn_case(&mut self) -> Item {
        let name = match self.advance() {
            Token::Ident(s) => s,
            other => panic!("Expected function name, got {:?}", other),
        };

        let mut patterns = Vec::new();
        while !matches!(self.peek(), Token::Equals) {
            let pat = match self.peek() {
                Token::IntLit(_) => {
                    if let Token::IntLit(n) = self.advance() {
                        Pattern::Lit(n)
                    } else { unreachable!() }
                }
                Token::Ident(_) => {
                    if let Token::Ident(s) = self.advance() {
                        if s == "_" {
                            Pattern::Wildcard
                        } else {
                            Pattern::Var(s)
                        }
                    } else { unreachable!() }
                }
                Token::LBracket => {
                    self.advance(); // consume [
                    if matches!(self.peek(), Token::RBracket) {
                        // [] — empty list pattern
                        self.advance();
                        Pattern::ListEmpty
                    } else {
                        panic!("List patterns use (x:xs) syntax, not [x | rest]")
                    }
                }
                Token::LParen => {
                    self.advance(); // consume (
                    // (x:xs) — cons pattern
                    let head = match self.advance() {
                        Token::Ident(s) if s == "_" => Pattern::Wildcard,
                        Token::Ident(s) => Pattern::Var(s),
                        Token::IntLit(n) => Pattern::Lit(n),
                        other => panic!("Expected pattern in cons, got {:?}", other),
                    };
                    if matches!(self.peek(), Token::Colon) {
                        self.advance(); // consume :
                        let tail = match self.advance() {
                            Token::Ident(s) if s == "_" => Pattern::Wildcard,
                            Token::Ident(s) => Pattern::Var(s),
                            other => panic!("Expected tail pattern, got {:?}", other),
                        };
                        self.expect(&Token::RParen);
                        Pattern::ListCons(Box::new(head), Box::new(tail))
                    } else if matches!(self.peek(), Token::RParen) {
                        // (s) — single ident in parens = seq bind
                        self.advance();
                        match head {
                            Pattern::Var(name) => Pattern::SeqBind(name),
                            other => other, // (0) etc — just the pattern
                        }
                    } else {
                        // Not a cons — it's a constructor pattern like (Ok n)
                        // For now, just return the head pattern
                        self.expect(&Token::RParen);
                        head
                    }
                }
                other => panic!("Expected pattern, got {:?}", other),
            };
            patterns.push(pat);
        }

        self.expect(&Token::Equals);
        let body = self.parse_expr();

        Item::Def(name, FnCase { patterns, body })
    }

    // ── Expression parsing (precedence climbing) ───────────
    //
    // expr      = add_expr
    // add_expr  = mul_expr (('+' | '-') mul_expr)*
    // mul_expr  = app_expr ('*' app_expr)*
    // app_expr  = atom+  (if multiple, first ident = function call)
    // atom      = INT_LIT | IDENT | '(' expr ')'

    fn parse_expr(&mut self) -> Expr {
        self.parse_add_expr()
    }

    fn parse_add_expr(&mut self) -> Expr {
        let mut left = self.parse_mul_expr();
        while matches!(self.peek(), Token::Plus | Token::Minus | Token::ColonColon) {
            let op = match self.advance() {
                Token::Plus => BinOp::Add,
                Token::Minus => BinOp::Sub,
                Token::ColonColon => BinOp::Concat,
                _ => unreachable!(),
            };
            let right = self.parse_mul_expr();
            left = Expr::BinOp(op, Box::new(left), Box::new(right));
        }
        left
    }

    fn parse_mul_expr(&mut self) -> Expr {
        let mut left = self.parse_app_expr();
        while matches!(self.peek(), Token::Star) {
            self.advance();
            let right = self.parse_app_expr();
            left = Expr::BinOp(BinOp::Mul, Box::new(left), Box::new(right));
        }
        left
    }

    fn parse_app_expr(&mut self) -> Expr {
        let first = self.parse_atom();

        // Check for seq selector postfix: s(+_) or s(0 3)
        if let Expr::Var(_) = &first {
            if matches!(self.peek(), Token::LParen) {
                // Peek ahead to see if this is a mask selector
                if self.try_parse_seq_selector(&first) {
                    return self.parse_seq_selector(first);
                }
            }
        }

        // If there are more atoms and the first is an ident, it's a function call
        if self.is_atom_start() {
            let func_name = match &first {
                Expr::Var(name) => name.clone(),
                other => panic!("Expected function name, got {:?}", other),
            };
            let mut args = Vec::new();
            while self.is_atom_start() {
                args.push(self.parse_atom());
            }
            Expr::Call(func_name, args)
        } else {
            first
        }
    }

    fn is_atom_start(&self) -> bool {
        matches!(self.peek(), Token::IntLit(_) | Token::Ident(_) | Token::LParen | Token::LBracket)
    }

    /// Check if the next `(...)` is a seq selector mask (contains only +/_ tokens or indices)
    fn try_parse_seq_selector(&self, _expr: &Expr) -> bool {
        if self.pos + 1 < self.tokens.len() {
            match &self.tokens[self.pos + 1] {
                Token::Plus => true,
                Token::Ident(s) if s == "_" => true,
                Token::IntLit(_) => true,
                _ => false,
            }
        } else {
            false
        }
    }

    /// Parse s(+_) or s(+___) style seq selector
    fn parse_seq_selector(&mut self, expr: Expr) -> Expr {
        self.advance(); // consume LParen
        let mut mask = String::new();
        while !matches!(self.peek(), Token::RParen) {
            match self.advance() {
                Token::Plus => mask.push('+'),
                Token::Ident(s) if s.chars().all(|c| c == '_') => {
                    // Multiple underscores lexed as a single ident: "___" -> "___"
                    mask.push_str(&s);
                }
                Token::IntLit(n) => {
                    if !mask.is_empty() { mask.push(' '); }
                    mask.push_str(&n.to_string());
                }
                other => panic!("Unexpected token in seq selector: {:?}", other),
            }
        }
        self.advance(); // consume RParen
        Expr::SeqSelect(Box::new(expr), mask)
    }

    fn parse_atom(&mut self) -> Expr {
        match self.peek().clone() {
            Token::IntLit(_) => {
                if let Token::IntLit(n) = self.advance() {
                    Expr::IntLit(n)
                } else { unreachable!() }
            }
            Token::Ident(_) => {
                if let Token::Ident(s) = self.advance() {
                    Expr::Var(s)
                } else { unreachable!() }
            }
            Token::LParen => {
                self.advance();
                let expr = self.parse_expr();
                self.expect(&Token::RParen);
                expr
            }
            Token::LBracket => {
                self.advance(); // consume [
                if matches!(self.peek(), Token::RBracket) {
                    self.advance();
                    Expr::ListEmpty
                } else {
                    let mut elems = vec![self.parse_expr()];
                    while matches!(self.peek(), Token::Comma) {
                        self.advance();
                        elems.push(self.parse_expr());
                    }
                    self.expect(&Token::RBracket);
                    Expr::ListLit(elems)
                }
            }
            other => panic!("Expected atom, got {:?}", other),
        }
    }



    // ── Group items into FnDefs ────────────────────────────

    fn build_program(&self, items: Vec<Item>) -> Program {
        let mut decls: HashMap<String, FnDecl> = HashMap::new();
        let mut defs: HashMap<String, Vec<FnCase>> = HashMap::new();
        let mut order: Vec<String> = Vec::new();

        for item in items {
            match item {
                Item::Decl(d) => {
                    if !decls.contains_key(&d.name) {
                        order.push(d.name.clone());
                    }
                    decls.insert(d.name.clone(), d);
                }
                Item::Def(name, case) => {
                    defs.entry(name).or_default().push(case);
                }
            }
        }

        let functions = order.into_iter()
            .filter_map(|name| {
                let decl = decls.remove(&name)?;
                let cases = defs.remove(&name).unwrap_or_default();
                Some(FnDef { name, decl, cases })
            })
            .collect();

        Program { functions }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lexer::Lexer;

    fn parse(src: &str) -> Program {
        let tokens = Lexer::new(src).tokenize();
        Parser::new(tokens).parse()
    }

    #[test]
    fn test_simple_function() {
        let p = parse("fn :: sum Int Int => Int\nsum a b = a + b");
        assert_eq!(p.functions.len(), 1);
        assert_eq!(p.functions[0].name, "sum");
        assert_eq!(p.functions[0].cases.len(), 1);
    }

    #[test]
    fn test_pattern_matching() {
        let p = parse("fn :: factorial Int => Int\nfactorial 0 = 1\nfactorial n = n * factorial (n - 1)");
        assert_eq!(p.functions[0].cases.len(), 2);
        assert_eq!(p.functions[0].cases[0].patterns, vec![Pattern::Lit(0)]);
        assert_eq!(p.functions[0].cases[1].patterns, vec![Pattern::Var("n".into())]);
    }

    #[test]
    fn test_fib() {
        let p = parse("fn :: fib Int => Int\nfib 0 = 0\nfib 1 = 1\nfib n = fib (n - 1) + fib (n - 2)");
        assert_eq!(p.functions[0].cases.len(), 3);
    }

    #[test]
    fn test_list_type_signature() {
        let p = parse("fn :: sum_list [Int] => Int\nsum_list xs = 0");
        assert_eq!(p.functions[0].decl.param_types, vec!["[Int]".to_string()]);
        assert_eq!(p.functions[0].decl.return_type, "Int");
    }

    #[test]
    fn test_list_return_type() {
        let p = parse("fn :: reverse [Int] => [Int]\nreverse xs = xs");
        assert_eq!(p.functions[0].decl.return_type, "[Int]");
    }

    #[test]
    fn test_empty_list_pattern() {
        let p = parse("fn :: sum_list [Int] => Int\nsum_list [] = 0");
        assert_eq!(p.functions[0].cases[0].patterns, vec![Pattern::ListEmpty]);
    }

    #[test]
    fn test_cons_pattern() {
        let p = parse("fn :: sum_list [Int] => Int\nsum_list [] = 0\nsum_list (x:rest) = x");
        assert_eq!(p.functions[0].cases.len(), 2);
        assert_eq!(p.functions[0].cases[1].patterns, vec![
            Pattern::ListCons(
                Box::new(Pattern::Var("x".into())),
                Box::new(Pattern::Var("rest".into())),
            )
        ]);
    }

    #[test]
    fn test_wildcard_cons_pattern() {
        let p = parse("fn :: list_length [Int] => Int\nlist_length [] = 0\nlist_length (_:xs) = 1");
        assert_eq!(p.functions[0].cases[1].patterns, vec![
            Pattern::ListCons(
                Box::new(Pattern::Wildcard),
                Box::new(Pattern::Var("xs".into())),
            )
        ]);
    }

    #[test]
    fn test_list_literal_expr() {
        let p = parse("fn :: f => Int\nf = [1, 2, 3]");
        match &p.functions[0].cases[0].body {
            Expr::ListLit(elems) => assert_eq!(elems.len(), 3),
            other => panic!("Expected ListLit, got {:?}", other),
        }
    }

    #[test]
    fn test_empty_list_expr() {
        let p = parse("fn :: f => Int\nf = []");
        assert_eq!(p.functions[0].cases[0].body, Expr::ListEmpty);
    }

    #[test]
    fn test_concat_operator() {
        let p = parse("fn :: f [Int] [Int] => [Int]\nf a b = a :: b");
        match &p.functions[0].cases[0].body {
            Expr::BinOp(BinOp::Concat, _, _) => {},
            other => panic!("Expected Concat BinOp, got {:?}", other),
        }
    }

    #[test]
    fn test_seq_selector() {
        let p = parse("fn :: first_of_seq Int Int => Int\nfirst_of_seq (s) = s(+ _)");
        assert_eq!(p.functions[0].cases[0].patterns, vec![Pattern::SeqBind("s".into())]);
        match &p.functions[0].cases[0].body {
            Expr::SeqSelect(expr, mask) => {
                assert_eq!(**expr, Expr::Var("s".into()));
                assert_eq!(mask, "+_");
            }
            other => panic!("Expected SeqSelect, got {:?}", other),
        }
    }

    #[test]
    fn test_seq_selector_multi() {
        let p = parse("fn :: endpoints Int Int Int Int => Int\nendpoints (s) = s(+ _ _ _)");
        assert_eq!(p.functions[0].cases[0].patterns, vec![Pattern::SeqBind("s".into())]);
        match &p.functions[0].cases[0].body {
            Expr::SeqSelect(_, mask) => assert_eq!(mask, "+___"),
            other => panic!("Expected SeqSelect, got {:?}", other),
        }
    }

    #[test]
    fn test_seq_index_selector() {
        let p = parse("fn :: extreme_points Int Int Int Int => Int\nextreme_points (s) = s(0 3)");
        match &p.functions[0].cases[0].body {
            Expr::SeqSelect(_, mask) => assert_eq!(mask, "0 3"),
            other => panic!("Expected SeqSelect, got {:?}", other),
        }
    }
}
