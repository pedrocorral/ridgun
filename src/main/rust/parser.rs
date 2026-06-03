/// Ridgun Parser — Recursive descent parser producing an AST

use std::collections::HashMap;
use crate::lexer::{Token, Span};

// ── AST Types ──────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    IntLit(i64),
    StringLit(String),
    BoolLit(bool),
    Unit,
    Var(String),
    BinOp(BinOp, Box<Expr>, Box<Expr>),
    Call(String, Vec<Expr>),
    Echo(Vec<Expr>),
    ListLit(Vec<Expr>),
    ListEmpty,
    SeqSelect(Box<Expr>, String),
    Block(Vec<Statement>),
}

#[derive(Debug, Clone, PartialEq)]
pub enum Statement {
    Let(String, Expr),    // name = expr
    Expr(Expr),           // expression (last one = return value)
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Eq,
    Gt,
    Lt,
    GtEq,
    LtEq,
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
    // Advanced patterns
    Tuple(Vec<Pattern>),        // (p1, p2, ...) - nested tuple patterns
    Constructor(String, Vec<Pattern>), // TypeName(args...) - ADT constructor patterns
    Record(Vec<(String, Pattern)>), // { field: pattern, ... } - record patterns
    NegLit(i64),                // -5 literal patterns
}

#[derive(Debug, Clone)]
pub struct FnDecl {
    pub name: String,
    pub param_types: Vec<String>,
    pub return_type: String,
}

#[derive(Debug, Clone)]
pub struct FnCase {
    pub span: Span,
    pub patterns: Vec<Pattern>,
    pub body: Expr,
    pub guards: Vec<(Expr, Expr)>,  // (condition, body) pairs; empty = no guards
}

#[derive(Debug, Clone)]
pub struct FnDef {
    pub span: Span,
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
    Decl(FnDecl, Span),
    Def(String, FnCase),
    Skip, // for items the parser sees but doesn't compile yet (type, import, op)
}

// ── Parser ─────────────────────────────────────────────────

pub struct Parser {
    tokens: Vec<Token>,
    spans: Vec<Span>,
    pos: usize,
}

impl Parser {
    pub fn new(tokens: Vec<Token>, spans: Vec<Span>) -> Self {
        Parser { tokens, spans, pos: 0 }
    }

    /// Return the span for the token at the current position
    fn current_span(&self) -> Span {
        self.spans.get(self.pos).copied().unwrap_or(Span::new(0, 0, 0, 0))
    }

    pub fn parse(&mut self) -> Program {
        let mut items = Vec::new();
        self.skip_newlines();

        while !self.at_eof() {
            items.extend(self.parse_item());
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

    /// Skip to end of line (for things we can't compile yet)
    fn skip_to_newline(&mut self) {
        while !matches!(self.peek(), Token::Newline | Token::Eof) {
            self.advance();
        }
    }

    // ── Top-level items ────────────────────────────────────

    fn parse_item(&mut self) -> Vec<Item> {
        match self.peek() {
            Token::Fn => vec![self.parse_fn_decl()],
            Token::Op => self.parse_op_decl(),
            Token::Type => {
                // Skip type definitions for now
                self.skip_to_newline();
                vec![Item::Skip]
            }
            Token::Import => {
                // Skip import statements for now
                self.skip_to_newline();
                vec![Item::Skip]
            }
            Token::Ident(_) => vec![self.parse_fn_case()],
            other => panic!("Expected 'fn', 'op', 'type', 'import' or identifier, got {:?}", other),
        }
    }

    /// Parse `op :: word Type word Type ... => ReturnType` plus definitions
    fn parse_op_decl(&mut self) -> Vec<Item> {
        let span_start = self.current_span();
        self.expect(&Token::Op);
        self.expect(&Token::ColonColon);

        let mut words: Vec<String> = Vec::new();
        let mut param_types: Vec<String> = Vec::new();
        // Track the template: true = type position, false = keyword position
        let mut template: Vec<bool> = Vec::new();

        // Parse interleaved words and types until => or ->
        while !matches!(self.peek(), Token::FatArrow | Token::Arrow | Token::Newline | Token::Eof) {
            match self.peek() {
                Token::Ident(s) => {
                    let s = s.clone();
                    self.advance();
                    if s.chars().next().map(|c| c.is_uppercase()).unwrap_or(false) {
                        param_types.push(s);
                        template.push(true); // type position
                    } else {
                        words.push(s);
                        template.push(false); // keyword position
                    }
                }
                Token::LParen => {
                    self.advance();
                    self.expect(&Token::RParen);
                    param_types.push("()".to_string());
                    template.push(true);
                }
                Token::LBracket => {
                    self.advance();
                    let inner = match self.advance() {
                        Token::Ident(s) => s,
                        other => panic!("Expected type inside [...], got {:?}", other),
                    };
                    self.expect(&Token::RBracket);
                    param_types.push(format!("[{}]", inner));
                    template.push(true);
                }
                Token::Plus | Token::Minus | Token::Star | Token::Slash => {
                    let sym = match self.advance() {
                        Token::Plus => "+",
                        Token::Minus => "-",
                        Token::Star => "*",
                        Token::Slash => "/",
                        _ => unreachable!(),
                    };
                    words.push(sym.to_string());
                    template.push(false);
                }
                _ => {
                    self.advance(); // skip unknown tokens
                }
            }
        }

        // Consume => or ->
        if matches!(self.peek(), Token::FatArrow | Token::Arrow) {
            self.advance();
        }

        // Parse return type(s)
        let return_type = self.parse_return_type();

        // Skip additional return types on the same line
        while matches!(self.peek(), Token::Ident(_)) {
            let s = if let Token::Ident(s) = self.peek() { s.clone() } else { break };
            if s.chars().next().map(|c| c.is_uppercase()).unwrap_or(false) {
                self.advance();
            } else {
                break;
            }
        }

        let mangled_name = words.join("_");
        let span_end = self.current_span();
        let span = Span::new(span_start.start_char, span_end.end_char, span_start.start_line, span_start.start_col);
        let mut items = vec![Item::Decl(FnDecl {
            name: mangled_name.clone(),
            param_types,
            return_type,
        }, span)];

        // Now parse definition line(s) that follow
        self.skip_newlines();
        // Try to parse definition(s): they start with the first keyword word
        while !self.at_eof() {
            // Check if this line starts with the first keyword of the operator
            if let Token::Ident(s) = self.peek() {
                if !words.is_empty() && s == &words[0] {
                    let case = self.parse_op_case(&words, &template);
                    items.push(Item::Def(mangled_name.clone(), case));
                    self.skip_newlines();
                    continue;
                }
            }
            break;
        }

        items
    }

    /// Parse an operator definition line using the known template
    fn parse_op_case(&mut self, keywords: &[String], template: &[bool]) -> FnCase {
        let mut patterns = Vec::new();
        let mut keyword_idx = 0;

        for &is_type in template {
            if is_type {
                // This position is a pattern (variable or literal)
                let pat = match self.peek() {
                    Token::Ident(_) => {
                        if let Token::Ident(s) = self.advance() {
                            if s == "_" { Pattern::Wildcard } else { Pattern::Var(s) }
                        } else { unreachable!() }
                    }
                    Token::IntLit(_) => {
                        if let Token::IntLit(n) = self.advance() { Pattern::Lit(n) }
                        else { unreachable!() }
                    }
                    Token::True => { self.advance(); Pattern::Var("True".into()) }
                    Token::False => { self.advance(); Pattern::Var("False".into()) }
                    other => panic!("Expected pattern in op definition, got {:?}", other),
                };
                patterns.push(pat);
            } else {
                // This position is a keyword — consume and verify
                match self.advance() {
                    Token::Ident(s) => {
                        if keyword_idx < keywords.len() {
                            assert_eq!(&s, &keywords[keyword_idx],
                                "Expected keyword '{}', got '{}'", keywords[keyword_idx], s);
                        }
                    }
                    Token::Plus | Token::Minus | Token::Star | Token::Slash => {
                        // Symbolic keyword, just consume
                    }
                    other => panic!("Expected keyword in op def, got {:?}", other),
                }
                keyword_idx += 1;
            }
        }

        // Check for guards
        if matches!(self.peek(), Token::Newline) {
            let saved = self.pos;
            self.advance();
            if matches!(self.peek(), Token::Pipe) {
                let guards = self.parse_guards();
                return FnCase {
                    span: Span::new(0, 0, 0, 0),
                    patterns,
                    body: Expr::Unit,
                    guards,
                };
            } else {
                self.pos = saved;
            }
        }

        // No guards — parse = body
        self.expect(&Token::Equals);
        let body = self.parse_expr();
        FnCase { span: Span::new(0, 0, 0, 0), patterns, body, guards: Vec::new() }
    }

    /// Parse return type: Int, [Int], (), etc.
    fn parse_return_type(&mut self) -> String {
        match self.peek() {
            Token::LBracket => {
                self.advance();
                let inner = match self.advance() {
                    Token::Ident(s) => s,
                    other => panic!("Expected type in [...], got {:?}", other),
                };
                self.expect(&Token::RBracket);
                format!("[{}]", inner)
            }
            Token::LParen => {
                self.advance();
                self.expect(&Token::RParen);
                "()".to_string()
            }
            _ => match self.advance() {
                Token::Ident(s) => s,
                other => panic!("Expected return type, got {:?}", other),
            },
        }
    }

    fn parse_fn_decl(&mut self) -> Item {
        let span_start = self.current_span();
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
                    self.advance();
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
            Token::LParen => {
                self.advance();
                self.expect(&Token::RParen);
                "()".to_string()
            }
            _ => match self.advance() {
                Token::Ident(s) => s,
                other => panic!("Expected return type, got {:?}", other),
            },
        };

        let span_end = self.current_span();
        let span = Span::new(span_start.start_char, span_end.end_char, span_start.start_line, span_start.start_col);
        Item::Decl(FnDecl { name, param_types, return_type }, span)
    }

    fn parse_fn_case(&mut self) -> Item {
        let name = match self.advance() {
            Token::Ident(s) => s,
            other => panic!("Expected function name, got {:?}", other),
        };

        let mut patterns = Vec::new();
        while !matches!(self.peek(), Token::Equals | Token::Newline | Token::Eof) {
            let pat = self.parse_pattern();
            patterns.push(pat);
        }

        // Check for guards: | condition = body
        if matches!(self.peek(), Token::Newline) {
            // Peek past newline to see if there are guards
            let saved = self.pos;
            self.advance(); // consume newline
            if matches!(self.peek(), Token::Pipe) {
                // This is a guarded case
                let guards = self.parse_guards();
                return Item::Def(name, FnCase {
                    span: Span::new(0, 0, 0, 0),
                    patterns,
                    body: Expr::Unit, // placeholder, guards hold the real bodies
                    guards,
                });
            } else {
                // Not guards, restore position
                self.pos = saved;
            }
        }

        self.expect(&Token::Equals);

        // Check for multi-line body: = <newline> <indented block>
        if matches!(self.peek(), Token::Newline) {
            self.advance(); // consume newline
            let body = self.parse_block();
            Item::Def(name, FnCase { span: Span::new(0, 0, 0, 0), patterns, body, guards: Vec::new() })
        } else {
            let body = self.parse_expr();
            Item::Def(name, FnCase { span: Span::new(0, 0, 0, 0), patterns, body, guards: Vec::new() })
        }
    }

    /// Parse an indented block of statements.
    /// Each line is either `name = expr` (let binding) or `expr` (expression).
    /// The last expression is the return value.
    fn parse_block(&mut self) -> Expr {
        let mut stmts = Vec::new();

        while !self.at_eof() {
            self.skip_newlines();

            // If we've reached a top-level keyword or we're past the block, stop
            if matches!(self.peek(), Token::Fn | Token::Op | Token::Type | Token::Import | Token::Eof) {
                break;
            }

            // Try to detect if this is a let binding: ident = expr
            // Look ahead: if we see Ident then Equals, it's a let binding
            if let Token::Ident(_) = self.peek() {
                let saved = self.pos;
                let ident = if let Token::Ident(s) = self.advance() { s } else { unreachable!() };

                if matches!(self.peek(), Token::Equals) {
                    self.advance(); // consume =
                    let expr = self.parse_expr();
                    stmts.push(Statement::Let(ident, expr));
                    continue;
                } else {
                    // Not a let binding — restore and parse as expression
                    self.pos = saved;
                }
            }

            // Parse as expression statement
            let expr = self.parse_expr();
            stmts.push(Statement::Expr(expr));
        }

        if stmts.is_empty() {
            Expr::Unit
        } else {
            Expr::Block(stmts)
        }
    }

    /// Parse a single pattern
    fn parse_pattern(&mut self) -> Pattern {
        match self.peek() {
            // Negative literal: -5
            Token::Minus => {
                self.advance(); // consume -
                match self.peek() {
                    Token::IntLit(n) => {
                        let value = *n;
                        self.advance();
                        Pattern::NegLit(-value)
                    }
                    _ => {
                        // Not a negative number - treat minus as variable or error
                        Pattern::Var("-".to_string())
                    }
                }
            }
            Token::IntLit(n) => {
                let value = *n;
                self.advance();
                Pattern::Lit(value)
            }
            Token::True => {
                self.advance();
                Pattern::Var("True".to_string())
            }
            Token::False => {
                self.advance();
                Pattern::Var("False".to_string())
            }
            Token::Ident(_) => {
                let s = match self.advance() {
                    Token::Ident(s) => s,
                    _ => unreachable!(),
                };
                if s == "_" {
                    Pattern::Wildcard
                } else {
                    Pattern::Var(s)
                }
            }
            Token::LBracket => {
                self.advance(); // consume [
                if matches!(self.peek(), Token::RBracket) {
                    self.advance();
                    Pattern::ListEmpty
                } else {
                    // Simple list literal pattern - for now just error or treat as wildcard
                    panic!("List patterns use (x:xs) syntax, not [x | rest]")
                }
            }
            Token::LParen => {
                self.advance(); // consume (
                let first_pat = self.parse_pattern();
                
                if matches!(self.peek(), Token::Colon) {
                    // (x:xs) - list cons pattern
                    self.advance(); // consume :
                    let tail = self.parse_pattern();
                    self.expect(&Token::RParen);
                    Pattern::ListCons(Box::new(first_pat), Box::new(tail))
                } else if matches!(self.peek(), Token::Comma) {
                    // (p1, p2, ...) - tuple pattern
                    self.advance(); // consume ,
                    let mut tuple_pats = vec![first_pat];
                    while matches!(self.peek(), Token::Comma) {
                        self.advance(); // consume ,
                        tuple_pats.push(self.parse_pattern());
                    }
                    self.expect(&Token::RParen);
                    Pattern::Tuple(tuple_pats)
                } else if matches!(self.peek(), Token::RParen) {
                    // (p) - just parens or seq bind
                    self.advance();
                    match first_pat {
                        Pattern::Var(name) => Pattern::SeqBind(name),
                        other => other,
                    }
                } else {
                    // (Constructor arg1 arg2 ...) - constructor pattern
                    let mut args = vec![first_pat.clone()];
                    while !matches!(self.peek(), Token::RParen | Token::Newline | Token::Eof) {
                        if matches!(self.peek(), Token::Comma) {
                            self.advance();
                        }
                        if matches!(self.peek(), Token::RParen) {
                            break;
                        }
                        args.push(self.parse_pattern());
                    }
                    self.expect(&Token::RParen);
                    // Create a synthetic constructor name from the first argument if it's a Var
                    let ctor_name = match first_pat {
                        Pattern::Var(name) => name,
                        _ => "unknown".to_string(),
                    };
                    Pattern::Constructor(ctor_name, if args.len() > 1 { args[1..].to_vec() } else { vec![] })
                }
            }
            other => panic!("Expected pattern, got {:?}", other),
        }
    }

    /// Parse guard lines: | condition = body
    fn parse_guards(&mut self) -> Vec<(Expr, Expr)> {
        let mut guards = Vec::new();
        while matches!(self.peek(), Token::Pipe) {
            self.advance(); // consume |
            let condition = if matches!(self.peek(), Token::Otherwise) {
                self.advance(); // consume 'otherwise'
                Expr::BoolLit(true) // otherwise = always true
            } else {
                self.parse_expr()
            };
            self.expect(&Token::Equals);
            let body = self.parse_expr();
            guards.push((condition, body));
            self.skip_newlines();
        }
        guards
    }

    // ── Expression parsing (precedence climbing) ───────────
    //
    // expr      = cmp_expr
    // cmp_expr  = add_expr (('==' | '>' | '<' | '>=' | '<=') add_expr)?
    // add_expr  = mul_expr (('+' | '-' | '::') mul_expr)*
    // mul_expr  = app_expr (('*' | '/') app_expr)*
    // app_expr  = atom+  (if multiple, first ident = function call)
    // atom      = INT_LIT | STRING_LIT | BOOL_LIT | IDENT | '(' expr ')' | '[' ... ']'

    fn parse_expr(&mut self) -> Expr {
        self.parse_cmp_expr()
    }

    fn parse_cmp_expr(&mut self) -> Expr {
        let left = self.parse_add_expr();
        match self.peek() {
            Token::EqualEqual | Token::Greater | Token::Less
            | Token::GreaterEq | Token::LessEq => {
                let op = match self.advance() {
                    Token::EqualEqual => BinOp::Eq,
                    Token::Greater => BinOp::Gt,
                    Token::Less => BinOp::Lt,
                    Token::GreaterEq => BinOp::GtEq,
                    Token::LessEq => BinOp::LtEq,
                    _ => unreachable!(),
                };
                let right = self.parse_add_expr();
                Expr::BinOp(op, Box::new(left), Box::new(right))
            }
            _ => left,
        }
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
        while matches!(self.peek(), Token::Star | Token::Slash) {
            let op = match self.advance() {
                Token::Star => BinOp::Mul,
                Token::Slash => BinOp::Div,
                _ => unreachable!(),
            };
            let right = self.parse_app_expr();
            left = Expr::BinOp(op, Box::new(left), Box::new(right));
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

        // Check for echo
        if let Expr::Var(ref name) = first {
            if name == "echo" {
                // Parse all remaining atoms on this line as echo arguments
                let mut args = Vec::new();
                while self.is_atom_start() {
                    args.push(self.parse_atom());
                }
                return Expr::Echo(args);
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
        matches!(self.peek(),
            Token::IntLit(_) | Token::Ident(_) | Token::LParen | Token::LBracket
            | Token::StringLit(_) | Token::RawStringLit(_) | Token::True | Token::False)
    }

    /// Check if the next `(...)` is a seq selector mask (contains only +/_ tokens or indices)
    fn try_parse_seq_selector(&self, _expr: &Expr) -> bool {
        if self.pos + 1 < self.tokens.len() {
            match &self.tokens[self.pos + 1] {
                Token::Plus => true,
                Token::Ident(s) if s == "_" => true,
                Token::IntLit(_) => {
                    // Disambiguate: s(0 3) is a seq selector, but (0 - 3) is arithmetic.
                    // Check what follows the int: if it's another int or ), it's a selector.
                    if self.pos + 2 < self.tokens.len() {
                        matches!(&self.tokens[self.pos + 2],
                            Token::IntLit(_) | Token::RParen)
                    } else {
                        false
                    }
                }
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
            Token::StringLit(_) => {
                if let Token::StringLit(s) = self.advance() {
                    Expr::StringLit(s)
                } else { unreachable!() }
            }
            Token::RawStringLit(_) => {
                if let Token::RawStringLit(s) = self.advance() {
                    Expr::StringLit(s)
                } else { unreachable!() }
            }
            Token::True => {
                self.advance();
                Expr::BoolLit(true)
            }
            Token::False => {
                self.advance();
                Expr::BoolLit(false)
            }
            Token::Ident(_) => {
                if let Token::Ident(s) = self.advance() {
                    Expr::Var(s)
                } else { unreachable!() }
            }
            Token::LParen => {
                self.advance();
                if matches!(self.peek(), Token::RParen) {
                    // () — unit literal
                    self.advance();
                    Expr::Unit
                } else {
                    let expr = self.parse_expr();
                    self.expect(&Token::RParen);
                    expr
                }
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
                Item::Decl(d, _) => {
                    if !decls.contains_key(&d.name) {
                        order.push(d.name.clone());
                    }
                    decls.insert(d.name.clone(), d);
                }
                Item::Def(name, case) => {
                    defs.entry(name).or_default().push(case);
                }
                Item::Skip => {}
            }
        }

        let functions = order.into_iter()
            .filter_map(|name| {
                let decl = decls.remove(&name)?;
                let cases = defs.remove(&name).unwrap_or_default();
                Some(FnDef { span: Span::new(0, 0, 0, 0), name, decl, cases })
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
        let (tokens, spans) = Lexer::new(src).tokenize();
        Parser::new(tokens, spans).parse()
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

    #[test]
    fn test_string_expr() {
        let p = parse("fn :: greet => String\ngreet = \"hello world\"");
        assert_eq!(p.functions[0].cases[0].body, Expr::StringLit("hello world".into()));
    }

    #[test]
    fn test_bool_expr() {
        let p = parse("fn :: t => Bool\nt = True");
        assert_eq!(p.functions[0].cases[0].body, Expr::BoolLit(true));
    }

    #[test]
    fn test_comparison_expr() {
        let p = parse("fn :: cmp Int Int => Bool\ncmp a b = a == b");
        match &p.functions[0].cases[0].body {
            Expr::BinOp(BinOp::Eq, _, _) => {},
            other => panic!("Expected Eq BinOp, got {:?}", other),
        }
    }

    #[test]
    fn test_echo_expr() {
        let p = parse("fn :: greet => ()\ngreet = echo \"hello\" \"world\"");
        match &p.functions[0].cases[0].body {
            Expr::Echo(args) => {
                assert_eq!(args.len(), 2);
                assert_eq!(args[0], Expr::StringLit("hello".into()));
                assert_eq!(args[1], Expr::StringLit("world".into()));
            }
            other => panic!("Expected Echo, got {:?}", other),
        }
    }

    #[test]
    fn test_unit_literal() {
        let p = parse("fn :: noop => ()\nnoop = ()");
        assert_eq!(p.functions[0].cases[0].body, Expr::Unit);
    }

    #[test]
    fn test_type_skipped() {
        let p = parse("type Result = Ok Int | Err String\nfn :: f => Int\nf = 42");
        assert_eq!(p.functions.len(), 1);
        assert_eq!(p.functions[0].name, "f");
    }

    #[test]
    fn test_import_skipped() {
        let p = parse("import test\nfn :: f => Int\nf = 42");
        assert_eq!(p.functions.len(), 1);
        assert_eq!(p.functions[0].name, "f");
    }

    #[test]
    fn test_op_parsed() {
        let p = parse("op :: add Int to Int => Int\nadd a to b = a + b\nfn :: f => Int\nf = 42");
        // op is parsed as a function named "add_to", plus fn :: f
        assert_eq!(p.functions.len(), 2);
        assert_eq!(p.functions[0].name, "add_to");
        assert_eq!(p.functions[0].decl.param_types, vec!["Int".to_string(), "Int".to_string()]);
        assert_eq!(p.functions[0].cases.len(), 1);
        assert_eq!(p.functions[1].name, "f");
    }
}
