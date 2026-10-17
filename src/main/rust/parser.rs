/// Ridgun Parser — Recursive descent parser producing an AST

use std::collections::HashMap;
use crate::lexer::{Token, Span};

// ── AST Types ──────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub struct WhereBinding {
    pub expr: Expr,
    pub target_var: String,
    pub index_target: Option<(String, Vec<i64>)>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TypeDef {
    pub name: String,
    pub variants: Vec<(String, Vec<String>)>,
    pub fields: Vec<(String, String)>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    IntLit(i64),
    RealLit(f64),
    StringLit(String),
    StringInterp(Vec<Expr>),
    BoolLit(bool),
    Unit,
    Var(String),
    BinOp(BinOp, Box<Expr>, Box<Expr>),
    Not(Box<Expr>),
    Out(Box<Expr>),
    Call(String, Vec<Expr>),
    Echo(Vec<Expr>),
    ListLit(Vec<Expr>),
    ListEmpty,
    TupleLit(Vec<Expr>),
    TensorLit(Vec<Expr>),
    Einsum(Vec<(Expr, String)>),
    Hadamard(BinOp, Box<Expr>, String, Box<Expr>, String),
    Index(Box<Expr>, Vec<Expr>),
    IndexAssign(String, Vec<Expr>, Box<Expr>),
    Where(Box<Expr>, Vec<WhereBinding>),
    ParPipe(Vec<Expr>),
    SeqSelect(Box<Expr>, String),
    WithContext(String, Box<Expr>, Box<Expr>),
    WithRegionLimit(i64, Box<Expr>),
    AtomicUpdate(String, Box<Expr>),
    LoadContext(String, Box<Expr>),
    LoadShared(String, Box<Expr>),
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
    Mod,
    Eq,
    Neq,
    Gt,
    Lt,
    GtEq,
    LtEq,
    Concat,
    FlatJoin,
    And,
    Or,
    Xor,
    MatMul,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Pattern {
    Lit(i64),
    RealLit(f64),
    StrLit(String),
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
    pub types: Vec<TypeDef>,
}

// ── Intermediate parse items ───────────────────────────────

#[derive(Debug)]
enum Item {
    Decl(FnDecl, Span),
    Def(String, FnCase),
    TypeDecl(TypeDef),
    Skip, // for items the parser sees but doesn't compile yet (import)
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
            Token::Global => self.parse_scoped_global_decl(0),
            Token::Context => self.parse_scoped_global_decl(1),
            Token::Shared => self.parse_scoped_global_decl(2),
            Token::Hardware => self.parse_hardware_decl(),
            Token::At => {
                while matches!(self.peek(), Token::At) {
                    self.skip_to_newline();
                    self.skip_newlines();
                }
                if matches!(self.peek(), Token::Type) {
                    vec![self.parse_type_decl()]
                } else {
                    vec![Item::Skip]
                }
            }
            Token::Op => self.parse_op_decl(),
            Token::Type => vec![self.parse_type_decl()],
            Token::Import => {
                self.skip_to_newline();
                vec![Item::Skip]
            }
            Token::Ident(_) => vec![self.parse_fn_case()],
            other => panic!("Expected 'fn', 'op', 'type', 'import' or identifier, got {:?}", other),
        }
    }

    fn parse_scoped_global_decl(&mut self, kind: u8) -> Vec<Item> {
        let span_start = self.current_span();
        self.advance(); // consume global / context / shared
        self.expect(&Token::ColonColon);
        let name = match self.advance() {
            Token::Ident(s) => s,
            other => panic!("Expected identifier after global/context/shared ::, got {:?}", other),
        };
        if matches!(self.peek(), Token::FatArrow | Token::Arrow | Token::Colon) {
            self.advance();
        }
        let return_type = self.parse_return_type();
        let span_end = self.current_span();
        let span = Span::new(span_start.start_char, span_end.end_char, span_start.start_line, span_start.start_col);
        let mut items = vec![Item::Decl(FnDecl {
            name: name.clone(),
            param_types: Vec::new(),
            return_type,
        }, span)];

        self.skip_newlines();
        if let Token::Ident(s) = self.peek() {
            if s == &name {
                self.advance();
                self.expect(&Token::Equals);
                let init_expr = self.parse_expr();
                let body = match kind {
                    1 => Expr::LoadContext(name.clone(), Box::new(init_expr)),
                    2 => Expr::LoadShared(name.clone(), Box::new(init_expr)),
                    _ => init_expr,
                };
                items.push(Item::Def(name, FnCase {
                    span: Span::new(0, 0, 0, 0),
                    patterns: Vec::new(),
                    body,
                    guards: Vec::new(),
                }));
            }
        }
        items
    }

    fn parse_hardware_decl(&mut self) -> Vec<Item> {
        let span = self.current_span();
        self.expect(&Token::Hardware);
        self.expect(&Token::ColonColon);
        let hw_name = match self.advance() {
            Token::Ident(s) => s,
            other => panic!("Expected hardware block name, got {:?}", other),
        };
        self.expect(&Token::At);
        let base_addr = match self.advance() {
            Token::IntLit(n) => n,
            other => panic!("Expected base address after @, got {:?}", other),
        };
        let mut items = vec![
            Item::Decl(FnDecl { name: hw_name.clone(), param_types: Vec::new(), return_type: "Int".into() }, span),
            Item::Def(hw_name, FnCase { span, patterns: Vec::new(), body: Expr::IntLit(base_addr), guards: Vec::new() }),
        ];
        loop {
            let saved = self.pos;
            self.skip_newlines();
            if let Token::Ident(reg_name) = self.peek().clone() {
                if matches!(self.tokens.get(self.pos + 1), Some(Token::Colon)) {
                    self.advance(); // reg_name
                    self.advance(); // :
                    let _reg_ty = self.parse_return_type();
                    self.expect(&Token::At);
                    let offset = match self.advance() {
                        Token::IntLit(n) => n,
                        other => panic!("Expected register offset, got {:?}", other),
                    };
                    items.push(Item::Decl(FnDecl { name: reg_name.clone(), param_types: Vec::new(), return_type: "Int".into() }, span));
                    items.push(Item::Def(reg_name, FnCase { span, patterns: Vec::new(), body: Expr::IntLit(base_addr + offset), guards: Vec::new() }));
                    continue;
                }
            }
            self.pos = saved;
            break;
        }
        items
    }

    fn parse_type_decl(&mut self) -> Item {
        self.expect(&Token::Type);
        let name = match self.advance() {
            Token::Ident(s) => s,
            other => panic!("Expected type name, got {:?}", other),
        };
        while !matches!(self.peek(), Token::Equals | Token::Newline | Token::Eof) {
            self.advance();
        }
        if !matches!(self.peek(), Token::Equals) {
            return Item::TypeDecl(TypeDef { name, variants: Vec::new(), fields: Vec::new() });
        }
        self.advance(); // consume =

        let is_sum = match self.peek() {
            Token::Ident(s) => s.chars().next().map(|c| c.is_uppercase()).unwrap_or(false),
            _ => false,
        };
        if is_sum {
            let mut variants = Vec::new();
            while !matches!(self.peek(), Token::Newline | Token::Eof) {
                if matches!(self.peek(), Token::Pipe) {
                    self.advance();
                }
                if let Token::Ident(ctor) = self.advance() {
                    let mut args = Vec::new();
                    while !matches!(self.peek(), Token::Pipe | Token::Newline | Token::Eof) {
                        args.push(self.parse_return_type());
                    }
                    variants.push((ctor, args));
                } else {
                    break;
                }
            }
            Item::TypeDecl(TypeDef { name, variants, fields: Vec::new() })
        } else {
            let mut fields = Vec::new();
            while !matches!(self.peek(), Token::Newline | Token::Eof) {
                if matches!(self.peek(), Token::Comma) {
                    self.advance();
                }
                if let Token::Ident(fname) = self.advance() {
                    if matches!(self.peek(), Token::Colon) {
                        self.advance();
                    }
                    let ftype = self.parse_return_type();
                    fields.push((fname, ftype));
                } else {
                    break;
                }
            }
            Item::TypeDecl(TypeDef { name, variants: Vec::new(), fields })
        }
    }

    /// Parse `op :: word Type word Type ... => ReturnType` plus definitions
    fn parse_op_decl(&mut self) -> Vec<Item> {
        let span_start = self.current_span();
        self.expect(&Token::Op);
        self.expect(&Token::ColonColon);

        let mut words: Vec<String> = Vec::new();
        let mut param_types: Vec<String> = Vec::new();
        let mut template: Vec<bool> = Vec::new();

        while !matches!(self.peek(), Token::FatArrow | Token::Arrow | Token::Newline | Token::Eof) {
            match self.peek() {
                Token::Ident(s) => {
                    let s = s.clone();
                    self.advance();
                    if s.chars().next().map(|c| c.is_uppercase()).unwrap_or(false) {
                        param_types.push(s);
                        template.push(true);
                    } else {
                        words.push(s);
                        template.push(false);
                    }
                }
                Token::With => {
                    self.advance();
                    words.push("with".to_string());
                    template.push(false);
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
                Token::Plus | Token::Minus | Token::Star | Token::Slash | Token::Percent => {
                    let sym = match self.advance() {
                        Token::Plus => "+",
                        Token::Minus => "-",
                        Token::Star => "*",
                        Token::Slash => "/",
                        Token::Percent => "%",
                        _ => unreachable!(),
                    };
                    words.push(sym.to_string());
                    template.push(false);
                }
                _ => {
                    self.advance();
                }
            }
        }

        if matches!(self.peek(), Token::FatArrow | Token::Arrow) {
            self.advance();
        }

        let mut ret_types = vec![self.parse_return_type()];
        while matches!(self.peek(), Token::Ident(_)) {
            let s = if let Token::Ident(s) = self.peek() { s.clone() } else { break };
            if s.chars().next().map(|c| c.is_uppercase()).unwrap_or(false) {
                ret_types.push(self.parse_return_type());
            } else {
                break;
            }
        }
        let return_type = if ret_types.len() > 1 {
            format!("({})", ret_types.join(", "))
        } else {
            ret_types.remove(0)
        };

        let mangled_name = words.join("_");
        let span_end = self.current_span();
        let span = Span::new(span_start.start_char, span_end.end_char, span_start.start_line, span_start.start_col);
        let mut items = vec![Item::Decl(FnDecl {
            name: mangled_name.clone(),
            param_types,
            return_type,
        }, span)];

        self.skip_newlines();
        while !self.at_eof() {
            if let Some(case) = self.try_parse_op_case(&words, &template) {
                items.push(Item::Def(mangled_name.clone(), case));
                self.skip_newlines();
            } else {
                break;
            }
        }

        items
    }

    fn try_parse_op_case(&mut self, keywords: &[String], template: &[bool]) -> Option<FnCase> {
        if matches!(self.peek(), Token::Fn | Token::Op | Token::Type | Token::Import | Token::Global | Token::Context | Token::Shared | Token::Hardware | Token::At | Token::Eof) {
            return None;
        }
        let saved = self.pos;
        let mut patterns = Vec::new();
        let mut keyword_idx = 0;

        for &is_type in template {
            if is_type {
                let pat = match self.peek() {
                    Token::Ident(_) | Token::IntLit(_) | Token::RealLit(_) | Token::True | Token::False | Token::LParen | Token::LBracket | Token::Minus => {
                        self.parse_pattern()
                    }
                    _ => {
                        self.pos = saved;
                        return None;
                    }
                };
                patterns.push(pat);
            } else {
                let matched = match self.advance() {
                    Token::Ident(s) => keyword_idx < keywords.len() && s == keywords[keyword_idx],
                    Token::With => keyword_idx < keywords.len() && keywords[keyword_idx] == "with",
                    Token::Plus => keyword_idx < keywords.len() && keywords[keyword_idx] == "+",
                    Token::Minus => keyword_idx < keywords.len() && keywords[keyword_idx] == "-",
                    Token::Star => keyword_idx < keywords.len() && keywords[keyword_idx] == "*",
                    Token::Slash => keyword_idx < keywords.len() && keywords[keyword_idx] == "/",
                    Token::Percent => keyword_idx < keywords.len() && keywords[keyword_idx] == "%",
                    _ => false,
                };
                if !matched {
                    self.pos = saved;
                    return None;
                }
                keyword_idx += 1;
            }
        }

        if matches!(self.peek(), Token::Newline) {
            let after_pats = self.pos;
            self.advance();
            if matches!(self.peek(), Token::Pipe) {
                let guards = self.parse_guards();
                return Some(FnCase {
                    span: Span::new(0, 0, 0, 0),
                    patterns,
                    body: Expr::Unit,
                    guards,
                });
            }
            self.pos = after_pats;
        }

        if !matches!(self.peek(), Token::Equals) {
            self.pos = saved;
            return None;
        }
        self.advance(); // consume =
        let body = self.parse_case_body();
        Some(FnCase { span: Span::new(0, 0, 0, 0), patterns, body, guards: Vec::new() })
    }

    /// Parse return type: Int, [Int], (), (Int, String), Tensor(b, i), String..., etc.
    fn parse_return_type(&mut self) -> String {
        let base_ty = match self.peek() {
            Token::LBracket => {
                self.advance();
                let inner = self.parse_return_type();
                self.expect(&Token::RBracket);
                format!("[{}]", inner)
            }
            Token::LParen => {
                self.advance();
                if matches!(self.peek(), Token::RParen) {
                    self.advance();
                    "()".to_string()
                } else {
                    let mut elems = vec![self.parse_return_type()];
                    while matches!(self.peek(), Token::Comma) {
                        self.advance();
                        elems.push(self.parse_return_type());
                    }
                    self.expect(&Token::RParen);
                    format!("({})", elems.join(", "))
                }
            }
            _ => match self.advance() {
                Token::Ident(s) => {
                    let prev_end = self.spans.get(self.pos.saturating_sub(1)).map(|sp| sp.end_char).unwrap_or(0);
                    let next_start = self.current_span().start_char;
                    if (s == "Tensor" || s == "Tensor_GPU") && matches!(self.peek(), Token::LParen) && prev_end == next_start {
                        self.advance(); // consume (
                        let mut dims = Vec::new();
                        while !matches!(self.peek(), Token::RParen | Token::Newline | Token::Eof) {
                            if matches!(self.peek(), Token::Comma) {
                                self.advance();
                            }
                            match self.advance() {
                                Token::Ident(d) => dims.push(d),
                                Token::IntLit(n) => dims.push(n.to_string()),
                                _ => break,
                            }
                        }
                        self.expect(&Token::RParen);
                        format!("Tensor({})", dims.join(","))
                    } else {
                        s
                    }
                }
                other => panic!("Expected return type, got {:?}", other),
            },
        };
        if matches!(self.peek(), Token::Ellipsis) {
            self.advance();
            format!("{}...", base_ty)
        } else {
            base_ty
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
            param_types.push(self.parse_return_type());
        }

        match self.peek() {
            Token::FatArrow | Token::Arrow => { self.advance(); }
            other => panic!("Expected => or ->, got {:?}", other),
        }

        let mut ret_types = vec![self.parse_return_type()];
        while matches!(self.peek(), Token::Ident(_)) {
            let s = if let Token::Ident(s) = self.peek() { s.clone() } else { break };
            if s.chars().next().map(|c| c.is_uppercase()).unwrap_or(false) {
                ret_types.push(self.parse_return_type());
            } else {
                break;
            }
        }
        let return_type = if ret_types.len() > 1 {
            format!("({})", ret_types.join(", "))
        } else {
            ret_types.remove(0)
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
        let body = self.parse_case_body();
        Item::Def(name, FnCase { span: Span::new(0, 0, 0, 0), patterns, body, guards: Vec::new() })
    }

    fn parse_case_body(&mut self) -> Expr {
        if matches!(self.peek(), Token::Newline) {
            let saved = self.pos;
            self.advance();
            self.skip_newlines();
            if matches!(self.peek(), Token::DoublePipe) {
                return self.parse_par_pipe();
            }
            self.pos = saved;
            self.advance();
            return self.parse_block();
        }
        if matches!(self.peek(), Token::DoublePipe) {
            return self.parse_par_pipe();
        }
        let mut body = self.parse_expr();
        if matches!(self.peek(), Token::Comma) {
            let mut elems = vec![body];
            while matches!(self.peek(), Token::Comma) {
                self.advance();
                elems.push(self.parse_expr());
            }
            body = Expr::TupleLit(elems);
        }
        let saved = self.pos;
        self.skip_newlines();
        if matches!(self.peek(), Token::Where) {
            self.advance();
            let bindings = self.parse_where_bindings();
            Expr::Where(Box::new(body), bindings)
        } else {
            self.pos = saved;
            body
        }
    }

    fn parse_par_pipe(&mut self) -> Expr {
        let mut branches = Vec::new();
        while matches!(self.peek(), Token::DoublePipe) {
            self.advance();
            branches.push(self.parse_expr());
            let saved = self.pos;
            self.skip_newlines();
            if !matches!(self.peek(), Token::DoublePipe) {
                self.pos = saved;
                break;
            }
        }
        Expr::ParPipe(branches)
    }

    fn parse_where_bindings(&mut self) -> Vec<WhereBinding> {
        let mut bindings = Vec::new();
        loop {
            let saved = self.pos;
            self.skip_newlines();
            if !self.line_has_arrow() {
                self.pos = saved;
                break;
            }
            let expr = self.parse_expr();
            self.expect(&Token::Arrow);
            let target_name = match self.advance() {
                Token::Ident(s) => s,
                other => panic!("Expected target variable after ->, got {:?}", other),
            };
            let index_target = if matches!(self.peek(), Token::LBracket) {
                self.advance();
                let mut indices = Vec::new();
                while !matches!(self.peek(), Token::RBracket | Token::Newline | Token::Eof) {
                    if matches!(self.peek(), Token::Comma) {
                        self.advance();
                    }
                    if let Token::IntLit(n) = self.advance() {
                        indices.push(n);
                    }
                }
                self.expect(&Token::RBracket);
                Some((target_name.clone(), indices))
            } else {
                None
            };
            bindings.push(WhereBinding { expr, target_var: target_name, index_target });
        }
        bindings
    }

    fn line_has_arrow(&self) -> bool {
        let mut i = self.pos;
        while i < self.tokens.len() {
            match self.tokens[i] {
                Token::Arrow => return true,
                Token::Newline | Token::Eof | Token::Fn | Token::Op | Token::Type => return false,
                _ => i += 1,
            }
        }
        false
    }

    /// Parse an indented block of statements.
    /// Each line is either `name = expr` (let binding) or `expr` (expression).
    /// The last expression is the return value.
    fn parse_block(&mut self) -> Expr {
        let mut stmts = Vec::new();

        while !self.at_eof() {
            self.skip_newlines();

            if matches!(
                self.peek(),
                Token::Fn | Token::Op | Token::Type | Token::Import
                | Token::Global | Token::Context | Token::Shared | Token::Hardware | Token::At | Token::Eof
            ) {
                break;
            }

            if matches!(self.peek(), Token::Atomic) {
                self.advance();
                let var_name = match self.advance() {
                    Token::Ident(s) => s,
                    other => panic!("Expected shared variable name after 'atomic', got {:?}", other),
                };
                self.expect(&Token::Equals);
                let val_expr = self.parse_expr();
                stmts.push(Statement::Expr(Expr::AtomicUpdate(var_name, Box::new(val_expr))));
                continue;
            }

            // Try to detect if this is a let binding: [let] ident = expr, or index assignment: ident[...] = expr
            if let Token::Ident(_) = self.peek() {
                let saved = self.pos;
                let first_ident = if let Token::Ident(s) = self.advance() { s } else { unreachable!() };
                if first_ident == "let" {
                    if let Token::Ident(_) = self.peek() {
                        let var_name = if let Token::Ident(s) = self.advance() { s } else { unreachable!() };
                        if matches!(self.peek(), Token::Equals) {
                            self.advance();
                            let expr = self.parse_expr();
                            stmts.push(Statement::Let(var_name, expr));
                            continue;
                        }
                    }
                    self.pos = saved;
                } else if matches!(self.peek(), Token::Equals) {
                    self.advance(); // consume =
                    let expr = self.parse_expr();
                    stmts.push(Statement::Let(first_ident, expr));
                    continue;
                } else if matches!(self.peek(), Token::LBracket) && self.line_has_equals_or_guard() {
                    let mut indices = Vec::new();
                    while matches!(self.peek(), Token::LBracket) {
                        self.advance();
                        indices.push(self.parse_expr());
                        while matches!(self.peek(), Token::Comma) {
                            self.advance();
                            indices.push(self.parse_expr());
                        }
                        self.expect(&Token::RBracket);
                    }
                    if matches!(self.peek(), Token::Equals) {
                        self.advance();
                        let rhs = self.parse_expr();
                        stmts.push(Statement::Expr(Expr::IndexAssign(first_ident, indices, Box::new(rhs))));
                        continue;
                    }
                    self.pos = saved;
                } else if self.line_has_equals_or_guard() && !matches!(self.peek(), Token::LBracket) {
                    // This line is a new function case definition (e.g., `fn_name pat1 = ...`), end the block
                    self.pos = saved;
                    break;
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

    fn line_has_equals_or_guard(&self) -> bool {
        let mut i = self.pos;
        while i < self.tokens.len() {
            match self.tokens[i] {
                Token::Equals => return true,
                Token::Newline => {
                    return matches!(self.tokens.get(i + 1), Some(Token::Pipe));
                }
                Token::Eof | Token::Fn | Token::Op | Token::Type | Token::Global | Token::Context | Token::Shared | Token::Hardware => return false,
                _ => i += 1,
            }
        }
        false
    }

    /// Parse a single pattern
    fn parse_pattern(&mut self) -> Pattern {
        match self.peek() {
            Token::Minus => {
                self.advance();
                match self.peek() {
                    Token::IntLit(n) => {
                        let value = *n;
                        self.advance();
                        Pattern::NegLit(-value)
                    }
                    Token::RealLit(r) => {
                        let value = *r;
                        self.advance();
                        Pattern::RealLit(-value)
                    }
                    _ => Pattern::Var("-".to_string()),
                }
            }
            Token::IntLit(n) => {
                let value = *n;
                self.advance();
                Pattern::Lit(value)
            }
            Token::RealLit(r) => {
                let value = *r;
                self.advance();
                Pattern::RealLit(value)
            }
            Token::StringLit(_) | Token::RawStringLit(_) => {
                let s = match self.advance() {
                    Token::StringLit(s) | Token::RawStringLit(s) => s,
                    _ => unreachable!(),
                };
                Pattern::StrLit(s)
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
                self.advance();
                if matches!(self.peek(), Token::RBracket) {
                    self.advance();
                    Pattern::ListEmpty
                } else {
                    panic!("List patterns use (x:xs) syntax, not [x | rest]")
                }
            }
            Token::LParen => {
                self.advance();
                let first_pat = self.parse_pattern();

                if matches!(self.peek(), Token::Colon) {
                    let mut cons_pats = vec![first_pat];
                    while matches!(self.peek(), Token::Colon) {
                        self.advance();
                        cons_pats.push(self.parse_pattern());
                    }
                    self.expect(&Token::RParen);
                    let mut acc = cons_pats.pop().unwrap();
                    while let Some(head) = cons_pats.pop() {
                        acc = Pattern::ListCons(Box::new(head), Box::new(acc));
                    }
                    acc
                } else if matches!(self.peek(), Token::Comma) {
                    let mut tuple_pats = vec![first_pat];
                    while matches!(self.peek(), Token::Comma) {
                        self.advance();
                        tuple_pats.push(self.parse_pattern());
                    }
                    self.expect(&Token::RParen);
                    Pattern::Tuple(tuple_pats)
                } else if matches!(self.peek(), Token::RParen) {
                    self.advance();
                    match first_pat {
                        Pattern::Var(name) => Pattern::SeqBind(name),
                        other => other,
                    }
                } else {
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

    pub fn parse_expr(&mut self) -> Expr {
        if matches!(self.peek(), Token::Atomic) {
            self.advance();
            let var_name = match self.advance() {
                Token::Ident(s) => s,
                other => panic!("Expected shared variable name after 'atomic', got {:?}", other),
            };
            self.expect(&Token::Equals);
            let val_expr = self.parse_expr();
            return Expr::AtomicUpdate(var_name, Box::new(val_expr));
        }
        if matches!(self.peek(), Token::With) && self.is_with_block_start() {
            return self.parse_with_expr();
        }
        self.parse_logic_expr()
    }

    fn is_with_block_start(&self) -> bool {
        match self.tokens.get(self.pos + 1) {
            Some(Token::Ident(s)) if s == "region" => true,
            Some(Token::Ident(_)) => matches!(self.tokens.get(self.pos + 2), Some(Token::Equals)),
            _ => false,
        }
    }

    fn parse_with_expr(&mut self) -> Expr {
        self.expect(&Token::With);
        if let Token::Ident(s) = self.peek().clone() {
            if s == "region" {
                self.advance(); // region
                if let Token::Ident(lim_kw) = self.peek() {
                    if lim_kw == "limit" {
                        self.advance();
                    }
                }
                let quota = match self.advance() {
                    Token::IntLit(n) => n,
                    other => panic!("Expected integer byte limit after 'with region limit', got {:?}", other),
                };
                if matches!(self.peek(), Token::Do) {
                    self.advance();
                }
                let body = self.parse_case_body();
                return Expr::WithRegionLimit(quota, Box::new(body));
            }
        }
        let ctx_name = match self.advance() {
            Token::Ident(s) => s,
            other => panic!("Expected context variable name after 'with', got {:?}", other),
        };
        self.expect(&Token::Equals);
        let val_expr = self.parse_logic_expr();
        self.skip_newlines();
        if matches!(self.peek(), Token::Do) {
            self.advance();
        }
        let body = self.parse_case_body();
        Expr::WithContext(ctx_name, Box::new(val_expr), Box::new(body))
    }

    fn parse_logic_expr(&mut self) -> Expr {
        let mut left = self.parse_not_expr();
        while matches!(self.peek(), Token::And | Token::Or | Token::Xor) {
            let op = match self.advance() {
                Token::And => BinOp::And,
                Token::Or => BinOp::Or,
                Token::Xor => BinOp::Xor,
                _ => unreachable!(),
            };
            let right = self.parse_not_expr();
            left = Expr::BinOp(op, Box::new(left), Box::new(right));
        }
        left
    }

    fn parse_not_expr(&mut self) -> Expr {
        if matches!(self.peek(), Token::Not) {
            self.advance();
            let inner = self.parse_not_expr();
            Expr::Not(Box::new(inner))
        } else {
            self.parse_cmp_expr()
        }
    }

    fn parse_cmp_expr(&mut self) -> Expr {
        let left = self.parse_add_expr();
        match self.peek() {
            Token::EqualEqual | Token::NotEqual | Token::Greater | Token::Less
            | Token::GreaterEq | Token::LessEq => {
                let op = match self.advance() {
                    Token::EqualEqual => BinOp::Eq,
                    Token::NotEqual => BinOp::Neq,
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
        while matches!(self.peek(), Token::Plus | Token::Minus | Token::ColonColon | Token::Colon) {
            let op = match self.advance() {
                Token::Plus => BinOp::Add,
                Token::Minus => BinOp::Sub,
                Token::ColonColon => BinOp::Concat,
                Token::Colon => BinOp::FlatJoin,
                _ => unreachable!(),
            };
            let right = self.parse_mul_expr();
            if matches!(op, BinOp::Add | BinOp::Sub) {
                if let (Some((b1, s1)), Some((b2, s2))) = (Self::extract_subscript(&left), Self::extract_subscript(&right)) {
                    left = Expr::Hadamard(op, Box::new(Expr::Var(b1)), s1, Box::new(Expr::Var(b2)), s2);
                    continue;
                }
            }
            left = Expr::BinOp(op, Box::new(left), Box::new(right));
        }
        left
    }

    fn parse_mul_expr(&mut self) -> Expr {
        let mut left = self.parse_app_expr();
        while matches!(self.peek(), Token::Star | Token::Slash | Token::Percent | Token::At) {
            let tok = self.advance();
            let right = self.parse_app_expr();
            if tok == Token::At {
                match (&mut left, Self::extract_subscript(&right)) {
                    (Expr::Einsum(ref mut terms), Some((b2, s2))) => {
                        terms.push((Expr::Var(b2), s2));
                    }
                    (_, Some((b2, s2))) => {
                        if let Some((b1, s1)) = Self::extract_subscript(&left) {
                            left = Expr::Einsum(vec![(Expr::Var(b1), s1), (Expr::Var(b2), s2)]);
                        } else {
                            left = Expr::Einsum(vec![(left, String::new()), (Expr::Var(b2), s2)]);
                        }
                    }
                    _ => {
                        left = Expr::BinOp(BinOp::MatMul, Box::new(left), Box::new(right));
                    }
                }
                continue;
            }
            let op = match tok {
                Token::Star => BinOp::Mul,
                Token::Slash => BinOp::Div,
                Token::Percent => BinOp::Mod,
                _ => unreachable!(),
            };
            if matches!(op, BinOp::Mul | BinOp::Div) {
                if let (Some((b1, s1)), Some((b2, s2))) = (Self::extract_subscript(&left), Self::extract_subscript(&right)) {
                    left = Expr::Hadamard(op, Box::new(Expr::Var(b1)), s1, Box::new(Expr::Var(b2)), s2);
                    continue;
                }
            }
            left = Expr::BinOp(op, Box::new(left), Box::new(right));
        }
        left
    }

    pub fn extract_subscript_pub(ident: &str) -> Option<(String, String)> {
        if let Some(pos) = ident.find('_') {
            let prefix = &ident[..pos];
            let suffix = &ident[pos + 1..];
            if !prefix.is_empty()
                && !suffix.is_empty()
                && prefix.chars().next().map(|c| c.is_ascii_uppercase()).unwrap_or(false)
                && suffix.chars().all(|c| c.is_ascii_lowercase())
            {
                return Some((prefix.to_string(), suffix.to_string()));
            }
        }
        None
    }

    fn extract_subscript(expr: &Expr) -> Option<(String, String)> {
        if let Expr::Var(ident) = expr {
            return Self::extract_subscript_pub(ident);
        }
        None
    }

    fn parse_app_expr(&mut self) -> Expr {
        let first = self.parse_atom();

        if let Expr::Var(_) = &first {
            if matches!(self.peek(), Token::LParen) && self.try_parse_seq_selector(&first) {
                return self.parse_seq_selector(first);
            }
        }

        if let Expr::Var(ref name) = first {
            if name == "echo" {
                let mut args = Vec::new();
                while self.is_atom_start() {
                    args.push(self.parse_atom());
                }
                return Expr::Echo(args);
            }
        }

        if self.is_atom_start() {
            let mut args = Vec::new();
            while self.is_atom_start() {
                args.push(self.parse_atom());
            }
            if args.len() == 1 && args[0] == Expr::Var("out".to_string()) {
                return Expr::Out(Box::new(first));
            }
            match first {
                Expr::Var(func_name) => Expr::Call(func_name, args),
                other => {
                    let mut all = vec![other];
                    all.extend(args);
                    Expr::Call("__chain__".to_string(), all)
                }
            }
        } else {
            first
        }
    }

    fn is_atom_start(&self) -> bool {
        matches!(
            self.peek(),
            Token::IntLit(_)
                | Token::RealLit(_)
                | Token::Ident(_)
                | Token::With
                | Token::LParen
                | Token::LBracket
                | Token::StringLit(_)
                | Token::RawStringLit(_)
                | Token::True
                | Token::False
        )
    }

    /// Check if the next `(...)` is a seq selector mask (contains only +/_ tokens or indices)
    fn try_parse_seq_selector(&self, _expr: &Expr) -> bool {
        if self.pos + 1 < self.tokens.len() {
            match &self.tokens[self.pos + 1] {
                Token::Plus => true,
                Token::Ident(s) if s.chars().all(|c| c == '_') => true,
                Token::IntLit(_) => {
                    if self.pos + 2 < self.tokens.len() {
                        matches!(&self.tokens[self.pos + 2], Token::IntLit(_) | Token::RParen)
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
                    mask.push_str(&s);
                }
                Token::IntLit(n) => {
                    if !mask.is_empty() {
                        mask.push(' ');
                    }
                    mask.push_str(&n.to_string());
                }
                other => panic!("Unexpected token in seq selector: {:?}", other),
            }
        }
        self.advance(); // consume RParen
        Expr::SeqSelect(Box::new(expr), mask)
    }

    fn parse_atom(&mut self) -> Expr {
        let tok_span = self.current_span();
        let mut base = match self.peek().clone() {
            Token::IntLit(_) => {
                if let Token::IntLit(n) = self.advance() {
                    Expr::IntLit(n)
                } else {
                    unreachable!()
                }
            }
            Token::RealLit(_) => {
                if let Token::RealLit(r) = self.advance() {
                    Expr::RealLit(r)
                } else {
                    unreachable!()
                }
            }
            Token::StringLit(_) => {
                if let Token::StringLit(s) = self.advance() {
                    let escaped_count = s
                        .chars()
                        .filter(|&c| c == '\n' || c == '\t' || c == '"' || c == '\\')
                        .count();
                    if tok_span.len() == s.chars().count() + escaped_count + 2
                        && s.contains('{')
                        && s.contains('}')
                    {
                        Self::parse_interpolated_parts(&s)
                    } else {
                        Expr::StringLit(s)
                    }
                } else {
                    unreachable!()
                }
            }
            Token::RawStringLit(_) => {
                if let Token::RawStringLit(s) = self.advance() {
                    Expr::StringLit(s)
                } else {
                    unreachable!()
                }
            }
            Token::True => {
                self.advance();
                Expr::BoolLit(true)
            }
            Token::False => {
                self.advance();
                Expr::BoolLit(false)
            }
            Token::With => {
                self.advance();
                Expr::Var("with".to_string())
            }
            Token::Ident(_) => {
                if let Token::Ident(s) = self.advance() {
                    if (s == "Tensor" || s == "Tensor_GPU") && matches!(self.peek(), Token::LBracket) {
                        if let Expr::ListLit(elems) = self.parse_atom() {
                            Expr::TensorLit(elems)
                        } else {
                            Expr::TensorLit(Vec::new())
                        }
                    } else {
                        Expr::Var(s)
                    }
                } else {
                    unreachable!()
                }
            }
            Token::LParen => {
                self.advance();
                if matches!(self.peek(), Token::RParen) {
                    self.advance();
                    Expr::Unit
                } else {
                    let expr = self.parse_expr();
                    if matches!(self.peek(), Token::Comma) {
                        let mut elems = vec![expr];
                        while matches!(self.peek(), Token::Comma) {
                            self.advance();
                            elems.push(self.parse_expr());
                        }
                        self.expect(&Token::RParen);
                        Expr::TupleLit(elems)
                    } else {
                        self.expect(&Token::RParen);
                        expr
                    }
                }
            }
            Token::LBracket => {
                self.advance();
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
            Token::Minus => {
                self.advance();
                match self.peek() {
                    Token::IntLit(_) => {
                        if let Token::IntLit(n) = self.advance() {
                            Expr::IntLit(-n)
                        } else {
                            unreachable!()
                        }
                    }
                    Token::RealLit(_) => {
                        if let Token::RealLit(r) = self.advance() {
                            Expr::RealLit(-r)
                        } else {
                            unreachable!()
                        }
                    }
                    _ => {
                        let inner = self.parse_atom();
                        Expr::BinOp(BinOp::Sub, Box::new(Expr::IntLit(0)), Box::new(inner))
                    }
                }
            }
            other => panic!("Expected atom, got {:?}", other),
        };
        let mut all_indices = Vec::new();
        loop {
            let prev_end = self.spans.get(self.pos.saturating_sub(1)).map(|s| s.end_char).unwrap_or(0);
            let next_start = self.current_span().start_char;
            if matches!(base, Expr::Var(_)) && matches!(self.peek(), Token::LBracket) && prev_end == next_start {
                self.advance();
                all_indices.push(self.parse_expr());
                while matches!(self.peek(), Token::Comma) {
                    self.advance();
                    all_indices.push(self.parse_expr());
                }
                self.expect(&Token::RBracket);
            } else {
                break;
            }
        }
        if !all_indices.is_empty() {
            base = Expr::Index(Box::new(base), all_indices);
        }
        base
    }

    fn parse_interpolated_parts(s: &str) -> Expr {
        let mut parts = Vec::new();
        let mut literal = String::new();
        let mut chars = s.chars().peekable();
        while let Some(ch) = chars.next() {
            if ch == '{' {
                if !literal.is_empty() {
                    parts.push(Expr::StringLit(std::mem::take(&mut literal)));
                }
                let mut code_str = String::new();
                for c in chars.by_ref() {
                    if c == '}' {
                        break;
                    }
                    code_str.push(c);
                }
                let (tokens, spans) = crate::lexer::Lexer::new(&code_str).tokenize();
                let sub_expr = Parser::new(tokens, spans).parse_expr();
                parts.push(sub_expr);
            } else {
                literal.push(ch);
            }
        }
        if !literal.is_empty() {
            parts.push(Expr::StringLit(literal));
        }
        Expr::StringInterp(parts)
    }

    // ── Group items into FnDefs ────────────────────────────

    fn build_program(&self, items: Vec<Item>) -> Program {
        let mut decls: HashMap<String, (FnDecl, Span)> = HashMap::new();
        let mut defs: HashMap<String, Vec<FnCase>> = HashMap::new();
        let mut order: Vec<String> = Vec::new();
        let mut types: Vec<TypeDef> = Vec::new();

        for item in items {
            match item {
                Item::Decl(d, span) => {
                    if !decls.contains_key(&d.name) {
                        order.push(d.name.clone());
                    }
                    decls.insert(d.name.clone(), (d, span));
                }
                Item::Def(name, case) => {
                    defs.entry(name).or_default().push(case);
                }
                Item::TypeDecl(td) => {
                    types.push(td);
                }
                Item::Skip => {}
            }
        }

        let mut arities: HashMap<String, usize> = decls
            .iter()
            .map(|(k, (d, _))| (k.clone(), d.param_types.len()))
            .collect();
        arities.entry("send_through".to_string()).or_insert(2);
        arities.entry("receive_from".to_string()).or_insert(1);
        arities.entry("try_receive_from".to_string()).or_insert(1);
        arities.entry("receive_from_timeout".to_string()).or_insert(2);

        let functions = order
            .into_iter()
            .filter_map(|name| {
                let (decl, span) = decls.remove(&name)?;
                let mut cases = defs.remove(&name).unwrap_or_default();
                for case in &mut cases {
                    Self::normalize_echo_expr(&mut case.body, &arities);
                    for (cond, body) in &mut case.guards {
                        Self::normalize_echo_expr(cond, &arities);
                        Self::normalize_echo_expr(body, &arities);
                    }
                }
                Some(FnDef { span, name, decl, cases })
            })
            .collect();

        Program { functions, types }
    }

    fn normalize_echo_expr(expr: &mut Expr, arities: &HashMap<String, usize>) {
        match expr {
            Expr::Echo(args) => {
                for a in args.iter_mut() {
                    Self::normalize_echo_expr(a, arities);
                }
                let mut folded = Vec::with_capacity(args.len());
                let mut i = 0;
                while i < args.len() {
                    if let Expr::Var(fn_name) = &args[i] {
                        if let Some(&arity) = arities.get(fn_name) {
                            if arity > 0 && i + arity < args.len() {
                                let call_args = args[i + 1..=i + arity].to_vec();
                                folded.push(Expr::Call(fn_name.clone(), call_args));
                                i += 1 + arity;
                                continue;
                            }
                        }
                    }
                    folded.push(args[i].clone());
                    i += 1;
                }
                *args = folded;
            }
            Expr::StringInterp(parts) => {
                for p in parts.iter_mut() {
                    Self::normalize_echo_expr(p, arities);
                }
            }
            Expr::Out(inner) | Expr::Not(inner) => {
                Self::normalize_echo_expr(inner, arities);
            }
            Expr::WithContext(_, val, body) => {
                Self::normalize_echo_expr(val, arities);
                Self::normalize_echo_expr(body, arities);
            }
            Expr::WithRegionLimit(_, body)
            | Expr::AtomicUpdate(_, body)
            | Expr::LoadContext(_, body)
            | Expr::LoadShared(_, body) => {
                Self::normalize_echo_expr(body, arities);
            }
            Expr::Einsum(terms) => {
                for (e, _) in terms.iter_mut() {
                    Self::normalize_echo_expr(e, arities);
                }
            }
            Expr::Hadamard(_, l, _, r, _) => {
                Self::normalize_echo_expr(l, arities);
                Self::normalize_echo_expr(r, arities);
            }
            Expr::Call(fn_name, args) => {
                if !arities.contains_key(fn_name) {
                    if fn_name != "__chain__" {
                        let mut candidate_words = vec![fn_name.clone()];
                        let mut operand_args = Vec::new();
                        for arg in args.iter() {
                            if let Expr::Var(w) = arg {
                                let test_prefix = format!("{}_{}", candidate_words.join("_"), w);
                                let matches_op = arities.keys().any(|k| {
                                    k == &test_prefix || k.starts_with(&format!("{}_", test_prefix))
                                });
                                if matches_op {
                                    candidate_words.push(w.clone());
                                    continue;
                                }
                            }
                            operand_args.push(arg.clone());
                        }
                        let mangled = candidate_words.join("_");
                        if arities.contains_key(&mangled) {
                            *fn_name = mangled;
                            *args = operand_args;
                        }
                    }
                    if !arities.contains_key(fn_name) {
                        let mut spine = Vec::new();
                        if fn_name != "__chain__" {
                            spine.push(Expr::Var(fn_name.clone()));
                        }
                        spine.extend(args.iter().cloned());
                        let mut stack: Vec<Expr> = Vec::new();
                        for item in spine {
                            if let Expr::Var(ref w) = item {
                                if arities.contains_key(w) && !stack.is_empty() {
                                    let call_args = std::mem::take(&mut stack);
                                    stack.push(Expr::Call(w.clone(), call_args));
                                    continue;
                                }
                            }
                            stack.push(item);
                        }
                        if stack.len() == 1 {
                            if let Some(Expr::Call(new_fn, new_args)) = stack.pop() {
                                *fn_name = new_fn;
                                *args = new_args;
                            }
                        }
                    }
                }
                for a in args.iter_mut() {
                    Self::normalize_echo_expr(a, arities);
                }
            }
            Expr::BinOp(_, l, r) => {
                Self::normalize_echo_expr(l, arities);
                Self::normalize_echo_expr(r, arities);
            }
            Expr::ListLit(elems) | Expr::TupleLit(elems) | Expr::TensorLit(elems) => {
                for e in elems.iter_mut() {
                    Self::normalize_echo_expr(e, arities);
                }
            }
            Expr::Index(base, indices) => {
                Self::normalize_echo_expr(base, arities);
                for idx in indices.iter_mut() {
                    Self::normalize_echo_expr(idx, arities);
                }
            }
            Expr::IndexAssign(_, indices, val) => {
                for idx in indices.iter_mut() {
                    Self::normalize_echo_expr(idx, arities);
                }
                Self::normalize_echo_expr(val, arities);
            }
            Expr::Block(stmts) => {
                for stmt in stmts {
                    match stmt {
                        Statement::Let(_, e) | Statement::Expr(e) => {
                            Self::normalize_echo_expr(e, arities);
                        }
                    }
                }
            }
            Expr::Where(body, bindings) => {
                Self::normalize_echo_expr(body, arities);
                for b in bindings {
                    Self::normalize_echo_expr(&mut b.expr, arities);
                }
            }
            Expr::ParPipe(branches) => {
                for b in branches {
                    Self::normalize_echo_expr(b, arities);
                }
            }
            Expr::Var(fn_name) => {
                if arities.get(fn_name) == Some(&0) {
                    *expr = Expr::Call(fn_name.clone(), Vec::new());
                }
            }
            _ => {}
        }
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
