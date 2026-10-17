-- ============================================================
-- src/main/ridgun/parser.rg
-- Self-Hosted Recursive-Descent Parser ([RToken] => RProgram)
-- Full Ridgun v0.9.0 Spec: fn, op, type (sum & record), global,
-- context, shared, hardware, @packed/@repr, tensors, einsum,
-- hadamard, sequences/masks, where-DAG, || pipes, string interp.
-- ============================================================
import ast
import lexer

-- ── Token Stream Helpers ────────────────────────────────────

fn :: tok_head [RToken] => RToken
tok_head (t:_) = t
tok_head [] = TokEof

fn :: tok_tail [RToken] => [RToken]
tok_tail (_:ts) = ts
tok_tail [] = []

fn :: skip_newlines [RToken] => [RToken]
skip_newlines (TokNewline:ts) = skip_newlines ts
skip_newlines ts = ts

fn :: skip_to_newline [RToken] => [RToken]
skip_to_newline [] = []
skip_to_newline (TokEof:_) = [TokEof]
skip_to_newline (TokNewline:ts) = ts
skip_to_newline (_:ts) = skip_to_newline ts

fn :: is_top_keyword RToken => Bool
is_top_keyword TokFn = True
is_top_keyword TokOp = True
is_top_keyword TokType = True
is_top_keyword TokImport = True
is_top_keyword TokGlobal = True
is_top_keyword TokContext = True
is_top_keyword TokShared = True
is_top_keyword TokHardware = True
is_top_keyword TokAt = True
is_top_keyword TokEof = True
is_top_keyword _ = False

fn :: is_upper_ident String => Bool
is_upper_ident s =
  c = str_char_at s 0
  c >= 65 AND c <= 90

fn :: is_lower_ident String => Bool
is_lower_ident s =
  c = str_char_at s 0
  (c >= 97 AND c <= 122) OR c == 95

-- ── Subscript Extraction (A_ij -> ("A", "ij")) ──────────────

fn :: find_underscore String Int Int => Int
find_underscore s pos len
  | pos >= len = -1
  | (str_char_at s pos) == 95 = pos
  | otherwise = find_underscore s (pos + 1) len

fn :: all_lower_ascii String Int Int => Bool
all_lower_ascii s pos len
  | pos >= len = True
  | (str_char_at s pos) >= 97 AND (str_char_at s pos) <= 122 = all_lower_ascii s (pos + 1) len
  | otherwise = False

fn :: is_subscript_ident String => Bool
is_subscript_ident s =
  u_idx = find_underscore s 0 (str_len s)
  check_subscript_parts s u_idx (str_len s)

fn :: check_subscript_parts String Int Int => Bool
check_subscript_parts s u_idx len
  | u_idx <= 0 OR (u_idx + 1) >= len = False
  | NOT (is_upper_ident s) = False
  | otherwise = all_lower_ascii s (u_idx + 1) len

fn :: split_subscript String => (String, String)
split_subscript s =
  u_idx = find_underscore s 0 (str_len s)
  (str_slice s 0 u_idx, str_slice s (u_idx + 1) (str_len s))

-- ── Type String Parsing ─────────────────────────────────────

fn :: check_variadic_suffix (String, [RToken]) => (String, [RToken])
check_variadic_suffix (base_ty, (TokEllipsis:rest)) = (base_ty + "...", rest)
check_variadic_suffix res = res

fn :: parse_tensor_dims [RToken] => (String, [RToken])
parse_tensor_dims (TokRParen:rest) = ("", rest)
parse_tensor_dims (TokNewline:rest) = ("", rest)
parse_tensor_dims (TokEof:rest) = ("", rest)
parse_tensor_dims [] = ("", [])
parse_tensor_dims (TokComma:rest) = parse_tensor_dims rest
parse_tensor_dims ((TokIdent d):rest) =
  more = parse_tensor_dims rest
  join_tensor_dim d more
parse_tensor_dims ((TokInt n):rest) =
  more = parse_tensor_dims rest
  join_tensor_dim (int_to_str n) more
parse_tensor_dims (_:rest) = parse_tensor_dims rest

fn :: join_tensor_dim String (String, [RToken]) => (String, [RToken])
join_tensor_dim d ("", rest) = (d, rest)
join_tensor_dim d (more, rest) = (d + "," + more, rest)

fn :: finish_tensor_type (String, [RToken]) => (String, [RToken])
finish_tensor_type (dims, rest) = ("Tensor(" + dims + ")", rest)

fn :: parse_type_tok [RToken] => (String, [RToken])
parse_type_tok (TokLBracket:rest) =
  p = parse_type_tok rest
  check_variadic_suffix (parse_type_list_close p)
parse_type_tok (TokLParen:rest) =
  check_variadic_suffix (parse_type_paren rest)
parse_type_tok ((TokIdent s):TokLParen:rest)
  | s == "Tensor" OR s == "Tensor_GPU" = check_variadic_suffix (finish_tensor_type (parse_tensor_dims rest))
  | otherwise = check_variadic_suffix (s, [TokLParen] :: rest)
parse_type_tok ((TokIdent s):rest) =
  check_variadic_suffix (s, rest)
parse_type_tok (_:rest) = ("Int", rest)
parse_type_tok [] = ("()", [])

fn :: parse_type_list_close (String, [RToken]) => (String, [RToken])
parse_type_list_close (inner, (TokRBracket:rest)) = ("[" + inner + "]", rest)
parse_type_list_close (inner, rest) = ("[" + inner + "]", rest)

fn :: parse_type_paren [RToken] => (String, [RToken])
parse_type_paren (TokRParen:rest) = ("()", rest)
parse_type_paren ts =
  p1 = parse_type_tok ts
  parse_type_tuple_rest p1

fn :: parse_type_tuple_rest (String, [RToken]) => (String, [RToken])
parse_type_tuple_rest (acc, (TokComma:rest)) =
  p2 = parse_type_tok rest
  merge_type_tuple acc p2
parse_type_tuple_rest (acc, (TokRParen:rest)) = ("(" + acc + ")", rest)
parse_type_tuple_rest (acc, rest) = ("(" + acc + ")", rest)

fn :: merge_type_tuple String (String, [RToken]) => (String, [RToken])
merge_type_tuple acc (next_ty, rest) =
  parse_type_tuple_rest (acc + ", " + next_ty, rest)

fn :: parse_return_types [RToken] => (String, [RToken])
parse_return_types ts =
  p1 = parse_type_tok ts
  parse_return_types_more p1

fn :: parse_return_types_more (String, [RToken]) => (String, [RToken])
parse_return_types_more (first_ty, ((TokIdent s):rest))
  | is_upper_ident s = combine_return_types first_ty (parse_type_tok ([TokIdent s] :: rest))
  | otherwise = (first_ty, [TokIdent s] :: rest)
parse_return_types_more res = res

fn :: combine_return_types String (String, [RToken]) => (String, [RToken])
combine_return_types t1 (t2, rest) = ("(" + t1 + ", " + t2 + ")", rest)

fn :: parse_param_types [RToken] => ([String], [RToken])
parse_param_types (TokFatArrow:rest) = ([], [TokFatArrow] :: rest)
parse_param_types (TokArrow:rest) = ([], [TokArrow] :: rest)
parse_param_types (TokNewline:rest) = ([], [TokNewline] :: rest)
parse_param_types (TokEof:rest) = ([], [TokEof] :: rest)
parse_param_types [] = ([], [])
parse_param_types ts =
  p1 = parse_type_tok ts
  parse_param_types_cont p1

fn :: parse_param_types_cont (String, [RToken]) => ([String], [RToken])
parse_param_types_cont (ty, rest) =
  p_more = parse_param_types rest
  prepend_str ty p_more

fn :: prepend_str String ([String], [RToken]) => ([String], [RToken])
prepend_str s (xs, rest) = ([s] :: xs, rest)

-- ── Pattern Parsing ─────────────────────────────────────────

fn :: parse_pattern [RToken] => (RPattern, [RToken])
parse_pattern ((TokInt n):rest) = (PatInt n, rest)
parse_pattern (TokMinus:(TokInt n):rest) = (PatInt (0 - n), rest)
parse_pattern ((TokReal r):rest) = (PatReal r, rest)
parse_pattern (TokMinus:(TokReal r):rest) = (PatReal ("-" + r), rest)
parse_pattern ((TokStr s):rest) = (PatStr s, rest)
parse_pattern ((TokRawStr s):rest) = (PatStr s, rest)
parse_pattern (TokTrue:rest) = (PatBool True, rest)
parse_pattern (TokFalse:rest) = (PatBool False, rest)
parse_pattern (TokLBracket:TokRBracket:rest) = (PatEmpty, rest)
parse_pattern (TokLParen:TokRParen:rest) = (PatWild, rest)
parse_pattern ((TokIdent s):rest)
  | s == "_" = (PatWild, rest)
  | (is_upper_ident s) AND (str_len s) > 1 = (PatCtor s [], rest)
  | otherwise = (PatVar s, rest)
parse_pattern (TokLParen:rest) =
  p1 = parse_pattern rest
  parse_paren_pattern p1
parse_pattern (_:rest) = (PatWild, rest)
parse_pattern [] = (PatWild, [])

fn :: parse_paren_pattern (RPattern, [RToken]) => (RPattern, [RToken])
parse_paren_pattern (first_p, (TokColon:rest)) =
  p2 = parse_cons_tail rest
  finish_cons_pat first_p p2
parse_paren_pattern (first_p, (TokComma:rest)) =
  p_list = parse_tuple_pats rest
  finish_tuple_pat first_p p_list
parse_paren_pattern ((PatVar v), (TokRParen:rest)) = (PatSeqBind v, rest)
parse_paren_pattern (first_p, (TokRParen:rest)) = (first_p, rest)
parse_paren_pattern ((PatCtor ctor []), rest) =
  p_args = parse_ctor_subpats rest
  finish_ctor_pat ctor p_args
parse_paren_pattern ((PatVar ctor), rest) =
  p_args = parse_ctor_subpats rest
  finish_ctor_pat ctor p_args
parse_paren_pattern (first_p, rest) = (first_p, rest)

fn :: parse_cons_tail [RToken] => (RPattern, [RToken])
parse_cons_tail ts =
  p1 = parse_pattern ts
  parse_cons_tail_cont p1

fn :: parse_cons_tail_cont (RPattern, [RToken]) => (RPattern, [RToken])
parse_cons_tail_cont (p, (TokColon:rest)) =
  more = parse_cons_tail rest
  finish_cons_pat p more
parse_cons_tail_cont (p, (TokRParen:rest)) = (p, rest)
parse_cons_tail_cont (p, rest) = (p, rest)

fn :: finish_cons_pat RPattern (RPattern, [RToken]) => (RPattern, [RToken])
finish_cons_pat h (t, rest) = (PatCons h t, rest)

fn :: parse_tuple_pats [RToken] => ([RPattern], [RToken])
parse_tuple_pats ts =
  p1 = parse_pattern ts
  parse_tuple_pats_cont p1

fn :: parse_tuple_pats_cont (RPattern, [RToken]) => ([RPattern], [RToken])
parse_tuple_pats_cont (p, (TokComma:rest)) =
  more = parse_tuple_pats rest
  prepend_pat p more
parse_tuple_pats_cont (p, (TokRParen:rest)) = ([p], rest)
parse_tuple_pats_cont (p, rest) = ([p], rest)

fn :: finish_tuple_pat RPattern ([RPattern], [RToken]) => (RPattern, [RToken])
finish_tuple_pat p1 (ps, rest) = (PatTuple ([p1] :: ps), rest)

fn :: parse_ctor_subpats [RToken] => ([RPattern], [RToken])
parse_ctor_subpats (TokRParen:rest) = ([], rest)
parse_ctor_subpats (TokNewline:rest) = ([], rest)
parse_ctor_subpats (TokEof:rest) = ([], rest)
parse_ctor_subpats [] = ([], [])
parse_ctor_subpats ts =
  p1 = parse_pattern ts
  parse_ctor_subpats_tail p1

fn :: parse_ctor_subpats_tail (RPattern, [RToken]) => ([RPattern], [RToken])
parse_ctor_subpats_tail (p, rest) =
  tail_res = parse_ctor_subpats rest
  prepend_pat p tail_res

fn :: finish_ctor_pat String ([RPattern], [RToken]) => (RPattern, [RToken])
finish_ctor_pat ctor (args, rest) = (PatCtor ctor args, rest)

fn :: prepend_pat RPattern ([RPattern], [RToken]) => ([RPattern], [RToken])
prepend_pat p (ps, rest) = ([p] :: ps, rest)

fn :: parse_case_patterns [RToken] => ([RPattern], [RToken])
parse_case_patterns (TokEquals:rest) = ([], [TokEquals] :: rest)
parse_case_patterns (TokNewline:rest) = ([], [TokNewline] :: rest)
parse_case_patterns (TokEof:rest) = ([], [TokEof] :: rest)
parse_case_patterns [] = ([], [])
parse_case_patterns ts =
  p1 = parse_pattern ts
  parse_case_patterns_cont p1

fn :: parse_case_patterns_cont (RPattern, [RToken]) => ([RPattern], [RToken])
parse_case_patterns_cont (p, rest) =
  more = parse_case_patterns rest
  prepend_pat p more

-- ── String Interpolation & Escaped Braces Parsing ───────────

fn :: find_matching_rbrace String Int Int => Int
find_matching_rbrace s pos len
  | pos >= len = -1
  | (str_char_at s pos) == 125 = pos
  | (str_char_at s pos) == 10 OR (str_char_at s pos) == 59 OR (str_char_at s pos) == 34 = -1
  | otherwise = find_matching_rbrace s (pos + 1) len

fn :: has_interp_brace String Int Int => Bool
has_interp_brace s pos len
  | pos >= len = False
  | (str_char_at s pos) == 123 AND (str_char_at s (pos + 1)) == 123 = has_interp_brace s (pos + 2) len
  | (str_char_at s pos) == 125 AND (str_char_at s (pos + 1)) == 125 = has_interp_brace s (pos + 2) len
  | (str_char_at s pos) == 123 AND (find_matching_rbrace s (pos + 1) len) > (pos + 1) = True
  | otherwise = has_interp_brace s (pos + 1) len

fn :: unescape_double_braces String Int Int String => String
unescape_double_braces s pos len acc
  | pos >= len = acc
  | (str_char_at s pos) == 123 AND (str_char_at s (pos + 1)) == 123 = unescape_double_braces s (pos + 2) len (acc + (char_from_code 123))
  | (str_char_at s pos) == 125 AND (str_char_at s (pos + 1)) == 125 = unescape_double_braces s (pos + 2) len (acc + (char_from_code 125))
  | otherwise = unescape_double_braces s (pos + 1) len (acc + (str_slice s pos (pos + 1)))

fn :: flush_lit_part String [RExpr] => [RExpr]
flush_lit_part "" parts = parts
flush_lit_part lit parts = parts :: [EStr lit]

fn :: parse_interp_code String => RExpr
parse_interp_code code_str =
  toks = tokenize_src code_str
  extract_expr_fst (parse_expr toks)

fn :: extract_expr_fst (RExpr, [RToken]) => RExpr
extract_expr_fst (e, _) = e

fn :: split_interp_loop String Int Int String [RExpr] => [RExpr]
split_interp_loop s pos len cur_lit parts
  | pos >= len = flush_lit_part cur_lit parts
  | (str_char_at s pos) == 123 AND (str_char_at s (pos + 1)) == 123 = split_interp_loop s (pos + 2) len (cur_lit + (char_from_code 123)) parts
  | (str_char_at s pos) == 125 AND (str_char_at s (pos + 1)) == 125 = split_interp_loop s (pos + 2) len (cur_lit + (char_from_code 125)) parts
  | (str_char_at s pos) == 123 = split_interp_at_brace s pos len cur_lit parts (find_matching_rbrace s (pos + 1) len)
  | otherwise = split_interp_loop s (pos + 1) len (cur_lit + (str_slice s pos (pos + 1))) parts

fn :: split_interp_at_brace String Int Int String [RExpr] Int => [RExpr]
split_interp_at_brace s pos len cur_lit parts rbrace_idx
  | rbrace_idx <= (pos + 1) = split_interp_loop s (pos + 1) len (cur_lit + (char_from_code 123)) parts
  | otherwise = split_interp_loop s (rbrace_idx + 1) len "" ((flush_lit_part cur_lit parts) :: [parse_interp_code (str_slice s (pos + 1) rbrace_idx)])

fn :: build_str_expr String => RExpr
build_str_expr s
  | NOT ((str_contains s (char_from_code 123)) OR (str_contains s (char_from_code 125))) = EStr s
  | has_interp_brace s 0 (str_len s) = EStrInterp (split_interp_loop s 0 (str_len s) "" [])
  | otherwise = EStr (unescape_double_braces s 0 (str_len s) "")

-- ── Expression Parsing (Precedence Climbing) ────────────────

fn :: is_atom_tok RToken => Bool
is_atom_tok (TokInt _) = True
is_atom_tok (TokReal _) = True
is_atom_tok (TokStr _) = True
is_atom_tok (TokRawStr _) = True
is_atom_tok TokTrue = True
is_atom_tok TokFalse = True
is_atom_tok (TokIdent _) = True
is_atom_tok TokWith = True
is_atom_tok TokLParen = True
is_atom_tok TokLBracket = True
is_atom_tok _ = False

fn :: is_with_block_start [RToken] => Bool
is_with_block_start (TokWith:(TokIdent s):_)
  | s == "region" = True
is_with_block_start (TokWith:(TokIdent _):TokEquals:_) = True
is_with_block_start _ = False

fn :: parse_expr [RToken] => (RExpr, [RToken])
parse_expr (TokAtomic:(TokIdent var_name):TokEquals:rest) =
  v_res = parse_expr rest
  wrap_atomic_update var_name v_res
parse_expr ts
  | is_with_block_start ts = parse_with_expr ts
  | otherwise = parse_logic_expr ts

fn :: wrap_atomic_update String (RExpr, [RToken]) => (RExpr, [RToken])
wrap_atomic_update var_name (val_e, rest) = (EAtomicUpdate var_name val_e, rest)

fn :: skip_do_token [RToken] => [RToken]
skip_do_token (TokDo:rest) = rest
skip_do_token ts = ts

fn :: parse_with_expr [RToken] => (RExpr, [RToken])
parse_with_expr (TokWith:(TokIdent r_kw):(TokIdent l_kw):(TokInt quota):rest)
  | r_kw == "region" AND l_kw == "limit" = wrap_with_region quota (parse_case_body (skip_do_token rest))
parse_with_expr (TokWith:(TokIdent ctx_name):TokEquals:rest) =
  v_res = parse_logic_expr rest
  parse_with_ctx_body ctx_name v_res
parse_with_expr (_:rest) = parse_logic_expr rest
parse_with_expr [] = (EUnit, [])

fn :: wrap_with_region Int (RExpr, [RToken]) => (RExpr, [RToken])
wrap_with_region quota (body, rest) = (EWithRegion quota body, rest)

fn :: parse_with_ctx_body String (RExpr, [RToken]) => (RExpr, [RToken])
parse_with_ctx_body ctx_name (val_e, rest) =
  clean = skip_do_token (skip_newlines rest)
  b_res = parse_case_body clean
  wrap_with_ctx ctx_name val_e b_res

fn :: wrap_with_ctx String RExpr (RExpr, [RToken]) => (RExpr, [RToken])
wrap_with_ctx ctx_name val_e (body, rest) = (EWithCtx ctx_name val_e body, rest)

fn :: parse_logic_expr [RToken] => (RExpr, [RToken])
parse_logic_expr ts =
  p1 = parse_not_expr ts
  parse_logic_loop p1

fn :: parse_logic_loop (RExpr, [RToken]) => (RExpr, [RToken])
parse_logic_loop (left, (TokAnd:rest)) =
  r = parse_not_expr rest
  parse_logic_combine OpAnd left r
parse_logic_loop (left, (TokOr:rest)) =
  r = parse_not_expr rest
  parse_logic_combine OpOr left r
parse_logic_loop (left, (TokXor:rest)) =
  r = parse_not_expr rest
  parse_logic_combine OpXor left r
parse_logic_loop res = res

fn :: parse_logic_combine RBinOp RExpr (RExpr, [RToken]) => (RExpr, [RToken])
parse_logic_combine bop left (right, rest) =
  parse_logic_loop (EBin bop left right, rest)

fn :: parse_not_expr [RToken] => (RExpr, [RToken])
parse_not_expr (TokNot:rest) =
  inner = parse_not_expr rest
  wrap_not inner
parse_not_expr ts = parse_cmp_expr ts

fn :: wrap_not (RExpr, [RToken]) => (RExpr, [RToken])
wrap_not (e, rest) = (ENot e, rest)

fn :: parse_cmp_expr [RToken] => (RExpr, [RToken])
parse_cmp_expr ts =
  p1 = parse_add_expr ts
  parse_cmp_tail p1

fn :: parse_cmp_tail (RExpr, [RToken]) => (RExpr, [RToken])
parse_cmp_tail (left, (TokEqEq:rest)) = combine_bin OpEq left (parse_add_expr rest)
parse_cmp_tail (left, (TokNeq:rest)) = combine_bin OpNeq left (parse_add_expr rest)
parse_cmp_tail (left, (TokGt:rest)) = combine_bin OpGt left (parse_add_expr rest)
parse_cmp_tail (left, (TokLt:rest)) = combine_bin OpLt left (parse_add_expr rest)
parse_cmp_tail (left, (TokGtEq:rest)) = combine_bin OpGtEq left (parse_add_expr rest)
parse_cmp_tail (left, (TokLtEq:rest)) = combine_bin OpLtEq left (parse_add_expr rest)
parse_cmp_tail res = res

fn :: combine_bin RBinOp RExpr (RExpr, [RToken]) => (RExpr, [RToken])
combine_bin bop left (right, rest) = (EBin bop left right, rest)

fn :: make_add_or_hadamard RBinOp RExpr RExpr => RExpr
make_add_or_hadamard bop (EVar v1) (EVar v2)
  | (bop == OpAdd OR bop == OpSub OR bop == OpMul OR bop == OpDiv) AND (is_subscript_ident v1) AND (is_subscript_ident v2) = build_hadamard_node bop (split_subscript v1) (split_subscript v2)
make_add_or_hadamard bop left right = EBin bop left right

fn :: build_hadamard_node RBinOp (String, String) (String, String) => RExpr
build_hadamard_node bop (b1, s1) (b2, s2) =
  EHadamard bop (EVar b1) s1 (EVar b2) s2

fn :: make_matmul_or_einsum RExpr RExpr => RExpr
make_matmul_or_einsum (EEinsum es subs) (EVar v2)
  | is_subscript_ident v2 = append_einsum_term es subs (split_subscript v2)
make_matmul_or_einsum (EVar v1) (EVar v2)
  | (is_subscript_ident v1) AND (is_subscript_ident v2) = build_einsum_pair (split_subscript v1) (split_subscript v2)
make_matmul_or_einsum left right = EBin OpMatMul left right

fn :: append_einsum_term [RExpr] [String] (String, String) => RExpr
append_einsum_term es subs (b2, s2) =
  EEinsum (es :: [EVar b2]) (subs :: [s2])

fn :: build_einsum_pair (String, String) (String, String) => RExpr
build_einsum_pair (b1, s1) (b2, s2) =
  EEinsum [EVar b1, EVar b2] [s1, s2]

fn :: parse_add_expr [RToken] => (RExpr, [RToken])
parse_add_expr ts =
  p1 = parse_mul_expr ts
  parse_add_loop p1

fn :: parse_add_loop (RExpr, [RToken]) => (RExpr, [RToken])
parse_add_loop (left, (TokPlus:rest)) =
  r = parse_mul_expr (skip_newlines rest)
  parse_add_combine OpAdd left r
parse_add_loop (left, (TokMinus:rest)) =
  r = parse_mul_expr (skip_newlines rest)
  parse_add_combine OpSub left r
parse_add_loop (left, (TokColonColon:rest)) =
  r = parse_mul_expr (skip_newlines rest)
  parse_add_combine OpConcat left r
parse_add_loop (left, (TokColon:rest)) =
  r = parse_mul_expr (skip_newlines rest)
  parse_add_combine OpFlatJoin left r
parse_add_loop res = res

fn :: parse_add_combine RBinOp RExpr (RExpr, [RToken]) => (RExpr, [RToken])
parse_add_combine bop left (right, rest) =
  parse_add_loop (make_add_or_hadamard bop left right, rest)

fn :: parse_mul_expr [RToken] => (RExpr, [RToken])
parse_mul_expr ts =
  p1 = parse_app_expr ts
  parse_mul_loop p1

fn :: parse_mul_loop (RExpr, [RToken]) => (RExpr, [RToken])
parse_mul_loop (left, (TokStar:rest)) =
  r = parse_app_expr rest
  parse_mul_combine OpMul left r
parse_mul_loop (left, (TokSlash:rest)) =
  r = parse_app_expr rest
  parse_mul_combine OpDiv left r
parse_mul_loop (left, (TokPercent:rest)) =
  r = parse_app_expr rest
  parse_mul_combine OpMod left r
parse_mul_loop (left, (TokAt:rest)) =
  r = parse_app_expr rest
  parse_matmul_combine left r
parse_mul_loop res = res

fn :: parse_mul_combine RBinOp RExpr (RExpr, [RToken]) => (RExpr, [RToken])
parse_mul_combine bop left (right, rest) =
  parse_mul_loop (make_add_or_hadamard bop left right, rest)

fn :: parse_matmul_combine RExpr (RExpr, [RToken]) => (RExpr, [RToken])
parse_matmul_combine left (right, rest) =
  parse_mul_loop (make_matmul_or_einsum left right, rest)

-- ── Sequence Mask / Selector Detection: s(+ _) or s(0 3) ───

fn :: is_seq_mask_tokens [RToken] => Bool
is_seq_mask_tokens (TokLParen:TokPlus:_) = True
is_seq_mask_tokens (TokLParen:(TokIdent s):TokPlus:_)
  | s == "_" OR s == "__" OR s == "___" = True
is_seq_mask_tokens (TokLParen:(TokIdent s):(TokIdent _):_)
  | s == "_" OR s == "__" OR s == "___" = True
is_seq_mask_tokens (TokLParen:(TokIdent s):TokRParen:_)
  | s == "_" OR s == "__" OR s == "___" = True
is_seq_mask_tokens (TokLParen:(TokInt _):(TokInt _):_) = True
is_seq_mask_tokens _ = False

fn :: scan_seq_mask [RToken] String => (String, [RToken])
scan_seq_mask (TokRParen:rest) acc = (acc, rest)
scan_seq_mask (TokPlus:rest) acc = scan_seq_mask rest (acc + "+")
scan_seq_mask ((TokIdent s):rest) acc = scan_seq_mask rest (acc + s)
scan_seq_mask ((TokInt n):rest) "" = scan_seq_mask rest (int_to_str n)
scan_seq_mask ((TokInt n):rest) acc = scan_seq_mask rest (acc + " " + (int_to_str n))
scan_seq_mask (_:rest) acc = (acc, rest)
scan_seq_mask [] acc = (acc, [])

fn :: finish_seq_select RExpr (String, [RToken]) => (RExpr, [RToken])
finish_seq_select base (mask, rest) = (ESeqSelect base mask, rest)

-- ── Application & Postfix (`out`, `s(+ _)`, calls) ──────────

fn :: parse_app_expr [RToken] => (RExpr, [RToken])
parse_app_expr ts =
  p1 = parse_atom ts
  parse_app_tail p1

fn :: parse_app_tail (RExpr, [RToken]) => (RExpr, [RToken])
parse_app_tail ((EVar name), (TokLParen:rest))
  | is_seq_mask_tokens ([TokLParen] :: rest) = finish_seq_select (EVar name) (scan_seq_mask rest "")
parse_app_tail ((EVar name), rest)
  | name == "echo" = finish_echo_call (parse_atom_list rest)
  | is_atom_tok (tok_head rest) = finish_fn_or_out_call (EVar name) name (parse_atom_list rest)
  | otherwise = (EVar name, rest)
parse_app_tail (first_e, rest)
  | is_atom_tok (tok_head rest) = finish_chain_or_out first_e (parse_atom_list rest)
  | otherwise = (first_e, rest)

fn :: finish_fn_or_out_call RExpr String ([RExpr], [RToken]) => (RExpr, [RToken])
finish_fn_or_out_call first_e _ (((EVar w):[]), rest)
  | w == "out" = (EOut first_e, rest)
finish_fn_or_out_call _ name (args, rest) = (ECall name args, rest)

fn :: finish_chain_or_out RExpr ([RExpr], [RToken]) => (RExpr, [RToken])
finish_chain_or_out first_e (((EVar w):[]), rest)
  | w == "out" = (EOut first_e, rest)
finish_chain_or_out first_e (args, rest) = (ECall "__chain__" ([first_e] :: args), rest)

fn :: parse_atom_list [RToken] => ([RExpr], [RToken])
parse_atom_list ts
  | is_atom_tok (tok_head ts) = parse_atom_list_cont (parse_atom ts)
  | otherwise = ([], ts)

fn :: parse_atom_list_cont (RExpr, [RToken]) => ([RExpr], [RToken])
parse_atom_list_cont (e, rest) =
  more = parse_atom_list rest
  prepend_expr e more

fn :: prepend_expr RExpr ([RExpr], [RToken]) => ([RExpr], [RToken])
prepend_expr e (es, rest) = ([e] :: es, rest)

fn :: finish_echo_call ([RExpr], [RToken]) => (RExpr, [RToken])
finish_echo_call (args, rest) = (EEcho args, rest)

-- ── Atom & Postfix Indexing (`m[0, 1]`, `m[0][1]`) ──────────

fn :: parse_atom [RToken] => (RExpr, [RToken])
parse_atom ts =
  base_res = parse_atom_base ts
  parse_postfix_index base_res

fn :: parse_atom_base [RToken] => (RExpr, [RToken])
parse_atom_base ((TokInt n):rest) = (EInt n, rest)
parse_atom_base ((TokReal r):rest) = (EReal r, rest)
parse_atom_base ((TokStr s):rest) = (build_str_expr s, rest)
parse_atom_base ((TokRawStr s):rest) = (EStr s, rest)
parse_atom_base (TokTrue:rest) = (EBool True, rest)
parse_atom_base (TokFalse:rest) = (EBool False, rest)
parse_atom_base (TokWith:rest) = (EVar "with", rest)
parse_atom_base ((TokIdent s):TokLBracket:rest)
  | s == "Tensor" OR s == "Tensor_GPU" = finish_tensor_lit (parse_comma_exprs rest)
parse_atom_base ((TokIdent s):TokIdxLBracket:rest)
  | s == "Tensor" OR s == "Tensor_GPU" = finish_tensor_lit (parse_comma_exprs rest)
parse_atom_base ((TokIdent s):rest) = (EVar s, rest)
parse_atom_base (TokMinus:(TokInt n):rest) = (EInt (0 - n), rest)
parse_atom_base (TokMinus:(TokReal r):rest) = (EReal ("-" + r), rest)
parse_atom_base (TokLParen:TokRParen:rest) = (EUnit, rest)
parse_atom_base (TokLParen:rest) =
  p1 = parse_expr rest
  parse_paren_expr p1
parse_atom_base (TokLBracket:TokRBracket:rest) = (EList [], rest)
parse_atom_base (TokLBracket:rest) =
  elems_res = parse_comma_exprs rest
  finish_list_lit elems_res
parse_atom_base (_:rest) = (EUnit, rest)
parse_atom_base [] = (EUnit, [])

fn :: finish_tensor_lit ([RExpr], [RToken]) => (RExpr, [RToken])
finish_tensor_lit (elems, rest) = (ETensor elems, rest)

fn :: parse_postfix_index (RExpr, [RToken]) => (RExpr, [RToken])
parse_postfix_index ((EVar v), (TokIdxLBracket:rest)) =
  idx_res = collect_bracket_indices ([TokIdxLBracket] :: rest) []
  finish_index_expr (EVar v) idx_res
parse_postfix_index res = res

fn :: collect_bracket_indices [RToken] [RExpr] => ([RExpr], [RToken])
collect_bracket_indices (TokIdxLBracket:rest) acc =
  one_bracket = parse_comma_exprs rest
  collect_bracket_more acc one_bracket
collect_bracket_indices ts acc = (acc, ts)

fn :: collect_bracket_more [RExpr] ([RExpr], [RToken]) => ([RExpr], [RToken])
collect_bracket_more acc (idxs, rest) =
  collect_bracket_indices rest (acc :: idxs)

fn :: finish_index_expr RExpr ([RExpr], [RToken]) => (RExpr, [RToken])
finish_index_expr base ([], rest) = (base, rest)
finish_index_expr base (idxs, rest) = (EIndex base idxs, rest)

fn :: parse_paren_expr (RExpr, [RToken]) => (RExpr, [RToken])
parse_paren_expr (first_e, (TokComma:rest)) =
  more = parse_comma_exprs rest
  finish_tuple_lit first_e more
parse_paren_expr (first_e, (TokRParen:rest)) = (first_e, rest)
parse_paren_expr (first_e, rest) = (first_e, rest)

fn :: parse_comma_exprs [RToken] => ([RExpr], [RToken])
parse_comma_exprs ts =
  p1 = parse_expr ts
  parse_comma_exprs_cont p1

fn :: parse_comma_exprs_cont (RExpr, [RToken]) => ([RExpr], [RToken])
parse_comma_exprs_cont (e, (TokComma:rest)) =
  more = parse_comma_exprs rest
  prepend_expr e more
parse_comma_exprs_cont (e, (TokRParen:rest)) = ([e], rest)
parse_comma_exprs_cont (e, (TokRBracket:rest)) = ([e], rest)
parse_comma_exprs_cont (e, rest) = ([e], rest)

fn :: finish_list_lit ([RExpr], [RToken]) => (RExpr, [RToken])
finish_list_lit (elems, rest) = (EList elems, rest)

fn :: finish_tuple_lit RExpr ([RExpr], [RToken]) => (RExpr, [RToken])
finish_tuple_lit e1 (es, rest) = (ETuple ([e1] :: es), rest)

-- ── Guards, ParPipes, Blocks & Where Clauses ────────────────

fn :: parse_guards [RToken] => ([RGuard], [RToken])
parse_guards (TokPipe:TokOtherwise:TokEquals:rest) =
  b = parse_expr rest
  parse_guards_cont (EBool True) b
parse_guards (TokPipe:rest) =
  c = parse_expr rest
  parse_guard_after_cond c
parse_guards ts = ([], ts)

fn :: parse_guard_after_cond (RExpr, [RToken]) => ([RGuard], [RToken])
parse_guard_after_cond (cond, (TokEquals:rest)) =
  b = parse_expr rest
  parse_guards_cont cond b
parse_guard_after_cond (cond, rest) =
  b = parse_expr rest
  parse_guards_cont cond b

fn :: parse_guards_cont RExpr (RExpr, [RToken]) => ([RGuard], [RToken])
parse_guards_cont cond (body, rest) =
  trimmed = skip_newlines rest
  more = parse_guards trimmed
  prepend_guard (GuardBranch cond body) more

fn :: prepend_guard RGuard ([RGuard], [RToken]) => ([RGuard], [RToken])
prepend_guard g (gs, rest) = ([g] :: gs, rest)

fn :: line_has_equals [RToken] => Bool
line_has_equals [] = False
line_has_equals (TokEof:_) = False
line_has_equals (TokNewline:TokPipe:_) = True
line_has_equals (TokNewline:_) = False
line_has_equals (TokEquals:_) = True
line_has_equals (_:ts) = line_has_equals ts

fn :: line_has_arrow [RToken] => Bool
line_has_arrow [] = False
line_has_arrow (TokEof:_) = False
line_has_arrow (TokNewline:_) = False
line_has_arrow (TokArrow:_) = True
line_has_arrow (_:ts) = line_has_arrow ts

fn :: parse_int_indices [RToken] => ([Int], [RToken])
parse_int_indices (TokRBracket:rest) = ([], rest)
parse_int_indices (TokComma:rest) = parse_int_indices rest
parse_int_indices ((TokInt n):rest) =
  more = parse_int_indices rest
  prepend_int n more
parse_int_indices (_:rest) = ([], rest)
parse_int_indices [] = ([], [])

fn :: prepend_int Int ([Int], [RToken]) => ([Int], [RToken])
prepend_int n (ns, rest) = ([n] :: ns, rest)

fn :: parse_where_binds [RToken] => ([RWhereBind], [RToken])
parse_where_binds ts =
  clean = skip_newlines ts
  parse_where_binds_step clean

fn :: parse_where_binds_step [RToken] => ([RWhereBind], [RToken])
parse_where_binds_step ts
  | line_has_arrow ts = parse_where_bind_target (parse_expr ts)
  | otherwise = ([], ts)

fn :: parse_where_bind_target (RExpr, [RToken]) => ([RWhereBind], [RToken])
parse_where_bind_target (e, (TokArrow:(TokIdent v):TokIdxLBracket:rest)) =
  idx_res = parse_int_indices rest
  parse_where_bind_indexed e v idx_res
parse_where_bind_target (e, (TokArrow:(TokIdent v):rest)) =
  more = parse_where_binds rest
  prepend_where (WhereBind e v []) more
parse_where_bind_target (_, rest) = ([], rest)

fn :: parse_where_bind_indexed RExpr String ([Int], [RToken]) => ([RWhereBind], [RToken])
parse_where_bind_indexed e v (idxs, rest) =
  more = parse_where_binds rest
  prepend_where (WhereBind e v idxs) more

fn :: prepend_where RWhereBind ([RWhereBind], [RToken]) => ([RWhereBind], [RToken])
prepend_where wb (wbs, rest) = ([wb] :: wbs, rest)

fn :: check_trailing_comma_and_where (RExpr, [RToken]) => (RExpr, [RToken])
check_trailing_comma_and_where (first_e, (TokComma:rest)) =
  more = parse_comma_exprs rest
  check_trailing_where (finish_tuple_lit first_e more)
check_trailing_comma_and_where res = check_trailing_where res

fn :: check_trailing_where (RExpr, [RToken]) => (RExpr, [RToken])
check_trailing_where (body, rest) =
  clean = skip_newlines rest
  check_trailing_where_tok body rest clean

fn :: check_trailing_where_tok RExpr [RToken] [RToken] => (RExpr, [RToken])
check_trailing_where_tok body _ (TokWhere:after_w) =
  w_res = parse_where_binds after_w
  finish_where_expr body w_res
check_trailing_where_tok body orig_rest _ = (body, orig_rest)

fn :: finish_where_expr RExpr ([RWhereBind], [RToken]) => (RExpr, [RToken])
finish_where_expr body (binds, rest) = (EWhere body binds, rest)

fn :: parse_par_pipe_branches [RToken] => ([RExpr], [RToken])
parse_par_pipe_branches (TokDoublePipe:rest) =
  e_res = parse_expr rest
  parse_par_pipe_more e_res
parse_par_pipe_branches ts = ([], ts)

fn :: parse_par_pipe_more (RExpr, [RToken]) => ([RExpr], [RToken])
parse_par_pipe_more (e, rest) =
  clean = skip_newlines rest
  parse_par_pipe_check e rest clean

fn :: parse_par_pipe_check RExpr [RToken] [RToken] => ([RExpr], [RToken])
parse_par_pipe_check e _ (TokDoublePipe:more_ts) =
  more = parse_par_pipe_branches ([TokDoublePipe] :: more_ts)
  prepend_expr e more
parse_par_pipe_check e orig_rest _ = ([e], orig_rest)

fn :: finish_par_pipe ([RExpr], [RToken]) => (RExpr, [RToken])
finish_par_pipe (branches, rest) = (EParPipe branches, rest)

fn :: parse_block_line_ident String [RToken] => ([RStmt], [RToken])
parse_block_line_ident name (TokEquals:rest) =
  e_res = parse_expr rest
  finish_let_stmt name e_res
parse_block_line_ident name (TokIdxLBracket:rest)
  | line_has_equals rest = parse_block_idx_assign name ([TokIdxLBracket] :: rest) (collect_bracket_indices ([TokIdxLBracket] :: rest) [])
parse_block_line_ident name rest
  | line_has_equals rest = ([], [TokIdent name] :: rest)
  | otherwise = finish_expr_stmt (parse_expr ([TokIdent name] :: rest))

fn :: parse_block_idx_assign String [RToken] ([RExpr], [RToken]) => ([RStmt], [RToken])
parse_block_idx_assign name _ (idxs, (TokEquals:rest)) =
  val_res = parse_expr rest
  finish_idx_assign_stmt name idxs val_res
parse_block_idx_assign name orig_rest _ =
  finish_expr_stmt (parse_expr ([TokIdent name] :: orig_rest))

fn :: finish_idx_assign_stmt String [RExpr] (RExpr, [RToken]) => ([RStmt], [RToken])
finish_idx_assign_stmt name idxs (val_e, rest) =
  more = parse_block_stmts_safe rest
  prepend_stmt (StmtIndexAssign name idxs val_e) more

fn :: finish_let_stmt String (RExpr, [RToken]) => ([RStmt], [RToken])
finish_let_stmt v (e, rest) =
  more = parse_block_stmts_safe rest
  prepend_stmt (StmtLet v e) more

fn :: finish_expr_stmt (RExpr, [RToken]) => ([RStmt], [RToken])
finish_expr_stmt (e, rest) =
  more = parse_block_stmts_safe rest
  prepend_stmt (StmtExpr e) more

fn :: parse_block_stmts_safe [RToken] => ([RStmt], [RToken])
parse_block_stmts_safe ts =
  clean = skip_newlines ts
  parse_block_safe_dispatch clean

fn :: parse_block_safe_dispatch [RToken] => ([RStmt], [RToken])
parse_block_safe_dispatch [] = ([], [])
parse_block_safe_dispatch (TokAtomic:(TokIdent var_name):TokEquals:rest) =
  e_res = parse_expr rest
  finish_atomic_stmt var_name e_res
parse_block_safe_dispatch ((TokIdent name):rest) = parse_block_line_ident name rest
parse_block_safe_dispatch ts
  | is_top_keyword (tok_head ts) = ([], ts)
  | otherwise = finish_expr_stmt (parse_expr ts)

fn :: finish_atomic_stmt String (RExpr, [RToken]) => ([RStmt], [RToken])
finish_atomic_stmt var_name (val_e, rest) =
  more = parse_block_stmts_safe rest
  prepend_stmt (StmtAtomic var_name val_e) more

fn :: prepend_stmt RStmt ([RStmt], [RToken]) => ([RStmt], [RToken])
prepend_stmt s (ss, rest) = ([s] :: ss, rest)

fn :: parse_case_body [RToken] => (RExpr, [RToken])
parse_case_body (TokNewline:rest) =
  clean = skip_newlines rest
  parse_case_body_newline rest clean
parse_case_body (TokDoublePipe:rest) =
  finish_par_pipe (parse_par_pipe_branches ([TokDoublePipe] :: rest))
parse_case_body ts =
  e_res = parse_expr ts
  check_trailing_comma_and_where e_res

fn :: parse_case_body_newline [RToken] [RToken] => (RExpr, [RToken])
parse_case_body_newline _ (TokDoublePipe:rest) =
  finish_par_pipe (parse_par_pipe_branches ([TokDoublePipe] :: rest))
parse_case_body_newline orig_rest _ =
  stmts_res = parse_block_stmts_safe orig_rest
  finish_block_body stmts_res

fn :: finish_block_body ([RStmt], [RToken]) => (RExpr, [RToken])
finish_block_body (stmts, rest) = (EBlock stmts, rest)

-- ── Top-Level Function, Operator, Scoped Global, Hardware & Type Decls ──

fn :: parse_fn_case_for String [RToken] => (RFnCase, [RToken])
parse_fn_case_for _ (_:rest) =
  pats_res = parse_case_patterns rest
  parse_fn_case_after_pats pats_res
parse_fn_case_for _ [] = (FnCase [] [] EUnit, [])

fn :: parse_fn_case_after_pats ([RPattern], [RToken]) => (RFnCase, [RToken])
parse_fn_case_after_pats (pats, (TokNewline:TokPipe:rest)) =
  g_res = parse_guards ([TokPipe] :: rest)
  finish_guarded_case pats g_res
parse_fn_case_after_pats (pats, (TokEquals:rest)) =
  b_res = parse_case_body rest
  finish_body_case pats b_res
parse_fn_case_after_pats (pats, rest) = (FnCase pats [] EUnit, rest)

fn :: finish_guarded_case [RPattern] ([RGuard], [RToken]) => (RFnCase, [RToken])
finish_guarded_case pats (guards, rest) = (FnCase pats guards EUnit, rest)

fn :: finish_body_case [RPattern] (RExpr, [RToken]) => (RFnCase, [RToken])
finish_body_case pats (body, rest) = (FnCase pats [] body, rest)

fn :: parse_fn_cases String [RToken] => ([RFnCase], [RToken])
parse_fn_cases fn_name ts =
  clean = skip_newlines ts
  parse_fn_cases_check fn_name clean

fn :: parse_fn_cases_check String [RToken] => ([RFnCase], [RToken])
parse_fn_cases_check fn_name ((TokIdent s):rest)
  | s == fn_name = parse_fn_cases_cont fn_name (parse_fn_case_for fn_name ([TokIdent s] :: rest))
  | otherwise = ([], [TokIdent s] :: rest)
parse_fn_cases_check _ ts = ([], ts)

fn :: parse_fn_cases_cont String (RFnCase, [RToken]) => ([RFnCase], [RToken])
parse_fn_cases_cont fn_name (c, rest) =
  more = parse_fn_cases fn_name rest
  prepend_case c more

fn :: prepend_case RFnCase ([RFnCase], [RToken]) => ([RFnCase], [RToken])
prepend_case c (cs, rest) = ([c] :: cs, rest)

fn :: parse_fn_decl [RToken] => (RFnDef, [RToken])
parse_fn_decl (TokFn:TokColonColon:(TokIdent name):rest) =
  pt_res = parse_param_types rest
  parse_fn_decl_ret name pt_res
parse_fn_decl (_:rest) = (FnDef "unknown" [] "()" [], rest)
parse_fn_decl [] = (FnDef "unknown" [] "()" [], [])

fn :: parse_fn_decl_ret String ([String], [RToken]) => (RFnDef, [RToken])
parse_fn_decl_ret name (params, (TokFatArrow:rest)) =
  rt_res = parse_return_types rest
  parse_fn_decl_cases name params rt_res
parse_fn_decl_ret name (params, (TokArrow:rest)) =
  rt_res = parse_return_types rest
  parse_fn_decl_cases name params rt_res
parse_fn_decl_ret name (params, rest) =
  parse_fn_decl_cases name params ("()", rest)

fn :: parse_fn_decl_cases String [String] (String, [RToken]) => (RFnDef, [RToken])
parse_fn_decl_cases name params (ret_ty, rest) =
  cs_res = parse_fn_cases name rest
  finish_fn_def name params ret_ty cs_res

fn :: finish_fn_def String [String] String ([RFnCase], [RToken]) => (RFnDef, [RToken])
finish_fn_def name params ret_ty (cases, rest) =
  (FnDef name params ret_ty cases, rest)

-- ── Custom Operators (`op :: ...`) ──────────────────────────

fn :: join_words_underscore [String] => String
join_words_underscore [] = "op"
join_words_underscore (w:[]) = w
join_words_underscore (w:ws) = w + "_" + (join_words_underscore ws)

fn :: scan_op_header [RToken] [String] [String] [Bool] => ([String], [String], [Bool], [RToken])
scan_op_header (TokFatArrow:rest) words params tmpl = (words, params, tmpl, rest)
scan_op_header (TokArrow:rest) words params tmpl = (words, params, tmpl, rest)
scan_op_header (TokNewline:rest) words params tmpl = (words, params, tmpl, [TokNewline] :: rest)
scan_op_header (TokEof:rest) words params tmpl = (words, params, tmpl, [TokEof] :: rest)
scan_op_header [] words params tmpl = (words, params, tmpl, [])
scan_op_header ((TokIdent s):rest) words params tmpl
  | is_upper_ident s = scan_op_header rest words (params :: [s]) (tmpl :: [True])
  | otherwise = scan_op_header rest (words :: [s]) params (tmpl :: [False])
scan_op_header (TokWith:rest) words params tmpl =
  scan_op_header rest (words :: ["with"]) params (tmpl :: [False])
scan_op_header (TokPlus:rest) words params tmpl =
  scan_op_header rest (words :: ["+"]) params (tmpl :: [False])
scan_op_header (TokMinus:rest) words params tmpl =
  scan_op_header rest (words :: ["-"]) params (tmpl :: [False])
scan_op_header (TokStar:rest) words params tmpl =
  scan_op_header rest (words :: ["*"]) params (tmpl :: [False])
scan_op_header (TokSlash:rest) words params tmpl =
  scan_op_header rest (words :: ["/"]) params (tmpl :: [False])
scan_op_header (TokPercent:rest) words params tmpl =
  scan_op_header rest (words :: ["%"]) params (tmpl :: [False])
scan_op_header (TokLParen:TokRParen:rest) words params tmpl =
  scan_op_header rest words (params :: ["()"]) (tmpl :: [True])
scan_op_header (TokLBracket:(TokIdent inner):TokRBracket:rest) words params tmpl =
  scan_op_header rest words (params :: ["[" + inner + "]"]) (tmpl :: [True])
scan_op_header (_:rest) words params tmpl =
  scan_op_header rest words params tmpl

fn :: match_op_keyword RToken String => Bool
match_op_keyword (TokIdent s) kw = s == kw
match_op_keyword TokWith kw = kw == "with"
match_op_keyword TokPlus kw = kw == "+"
match_op_keyword TokMinus kw = kw == "-"
match_op_keyword TokStar kw = kw == "*"
match_op_keyword TokSlash kw = kw == "/"
match_op_keyword TokPercent kw = kw == "%"
match_op_keyword _ _ = False

fn :: try_parse_op_template [Bool] [String] [RToken] [RPattern] => (Bool, [RPattern], [RToken])
try_parse_op_template [] _ ts pats = (True, pats, ts)
try_parse_op_template (True:t_rest) kws ts pats
  | is_top_keyword (tok_head ts) = (False, [], ts)
  | otherwise = try_parse_op_pat t_rest kws pats (parse_pattern ts)
try_parse_op_template (False:t_rest) (kw:kw_rest) (tok:ts_rest) pats
  | match_op_keyword tok kw = try_parse_op_template t_rest kw_rest ts_rest pats
  | otherwise = (False, [], [tok] :: ts_rest)
try_parse_op_template _ _ ts _ = (False, [], ts)

fn :: try_parse_op_pat [Bool] [String] [RPattern] (RPattern, [RToken]) => (Bool, [RPattern], [RToken])
try_parse_op_pat t_rest kws pats (pat, rest) =
  try_parse_op_template t_rest kws rest (pats :: [pat])

fn :: parse_op_cases [Bool] [String] [RToken] => ([RFnCase], [RToken])
parse_op_cases tmpl kws ts =
  clean = skip_newlines ts
  parse_op_cases_step tmpl kws clean (try_parse_op_template tmpl kws clean [])

fn :: parse_op_cases_step [Bool] [String] [RToken] (Bool, [RPattern], [RToken]) => ([RFnCase], [RToken])
parse_op_cases_step _ _ orig_ts (False, _, _) = ([], orig_ts)
parse_op_cases_step tmpl kws _ (True, pats, after_pats) =
  c_res = parse_fn_case_after_pats (pats, after_pats)
  parse_op_cases_cont tmpl kws c_res

fn :: parse_op_cases_cont [Bool] [String] (RFnCase, [RToken]) => ([RFnCase], [RToken])
parse_op_cases_cont tmpl kws (c, rest) =
  more = parse_op_cases tmpl kws rest
  prepend_case c more

fn :: parse_op_decl [RToken] => (RFnDef, [RToken])
parse_op_decl (TokOp:TokColonColon:rest) =
  hdr = scan_op_header rest [] [] []
  finish_op_header hdr
parse_op_decl (_:rest) = (FnDef "unknown" [] "()" [], rest)
parse_op_decl [] = (FnDef "unknown" [] "()" [], [])

fn :: finish_op_header ([String], [String], [Bool], [RToken]) => (RFnDef, [RToken])
finish_op_header (words, params, tmpl, rest) =
  mangled = join_words_underscore words
  rt_res = parse_return_types rest
  finish_op_decl mangled words params tmpl rt_res

fn :: finish_op_decl String [String] [String] [Bool] (String, [RToken]) => (RFnDef, [RToken])
finish_op_decl mangled words params tmpl (ret_ty, rest) =
  cs_res = parse_op_cases tmpl words rest
  finish_fn_def mangled params ret_ty cs_res

-- ── Scoped Globals (`global ::`, `context ::`, `shared ::`) ─

fn :: wrap_scoped_init Int String RExpr => RExpr
wrap_scoped_init 1 name init_e = ELoadContext name init_e
wrap_scoped_init 2 name init_e = ELoadShared name init_e
wrap_scoped_init _ _ init_e = init_e

fn :: strip_optional_arrow [RToken] => [RToken]
strip_optional_arrow (TokFatArrow:rest) = rest
strip_optional_arrow (TokArrow:rest) = rest
strip_optional_arrow (TokColon:rest) = rest
strip_optional_arrow ts = ts

fn :: parse_scoped_global Int [RToken] => (RFnDef, [RToken])
parse_scoped_global kind (_:TokColonColon:(TokIdent name):rest) =
  rt_res = parse_return_types (strip_optional_arrow rest)
  parse_scoped_global_init kind name rt_res
parse_scoped_global _ (_:rest) = (FnDef "unknown" [] "Int" [], skip_to_newline rest)
parse_scoped_global _ [] = (FnDef "unknown" [] "Int" [], [])

fn :: parse_scoped_global_init Int String (String, [RToken]) => (RFnDef, [RToken])
parse_scoped_global_init kind name (ret_ty, rest) =
  clean = skip_newlines rest
  parse_scoped_global_body kind name ret_ty clean

fn :: parse_scoped_global_body Int String String [RToken] => (RFnDef, [RToken])
parse_scoped_global_body kind name ret_ty ((TokIdent s):TokEquals:rest)
  | s == name = finish_scoped_global kind name ret_ty (parse_expr rest)
parse_scoped_global_body _ name ret_ty ts =
  (FnDef name [] ret_ty [FnCase [] [] (EInt 0)], ts)

fn :: finish_scoped_global Int String String (RExpr, [RToken]) => (RFnDef, [RToken])
finish_scoped_global kind name ret_ty (init_e, rest) =
  body = wrap_scoped_init kind name init_e
  (FnDef name [] ret_ty [FnCase [] [] body], rest)

-- ── Hardware MMIO Blocks (`hardware :: Name @ 0x...`) ───────

fn :: parse_hw_registers Int [RToken] => ([RFnDef], [RToken])
parse_hw_registers base_addr ts =
  clean = skip_newlines ts
  parse_hw_reg_step base_addr ts clean

fn :: parse_hw_reg_step Int [RToken] [RToken] => ([RFnDef], [RToken])
parse_hw_reg_step base_addr _ ((TokIdent reg_name):TokColon:rest) =
  ty_res = parse_type_tok rest
  parse_hw_reg_offset base_addr reg_name ty_res
parse_hw_reg_step _ orig_ts _ = ([], orig_ts)

fn :: parse_hw_reg_offset Int String (String, [RToken]) => ([RFnDef], [RToken])
parse_hw_reg_offset base_addr reg_name (_, (TokAt:(TokInt offset):rest)) =
  reg_fn = FnDef reg_name [] "Int" [FnCase [] [] (EInt (base_addr + offset))]
  more = parse_hw_registers base_addr rest
  prepend_fndef reg_fn more
parse_hw_reg_offset base_addr _ (_, rest) =
  parse_hw_registers base_addr (skip_to_newline rest)

fn :: prepend_fndef RFnDef ([RFnDef], [RToken]) => ([RFnDef], [RToken])
prepend_fndef f (fs, rest) = ([f] :: fs, rest)

fn :: parse_hardware_decl [RToken] => ([RFnDef], [RToken])
parse_hardware_decl (TokHardware:TokColonColon:(TokIdent hw_name):TokAt:(TokInt base_addr):rest) =
  hw_fn = FnDef hw_name [] "Int" [FnCase [] [] (EInt base_addr)]
  regs_res = parse_hw_registers base_addr rest
  prepend_fndef hw_fn regs_res
parse_hardware_decl (_:rest) = ([], skip_to_newline rest)
parse_hardware_decl [] = ([], [])

-- ── Type Declarations (Sum Variants & Product Record Fields) ─

fn :: parse_variants [RToken] => ([RVariant], [RToken])
parse_variants (TokNewline:rest) = ([], rest)
parse_variants (TokEof:rest) = ([], [TokEof] :: rest)
parse_variants [] = ([], [])
parse_variants (TokPipe:rest) = parse_variants rest
parse_variants ((TokIdent ctor):rest) =
  args_res = parse_variant_args rest
  parse_variants_cont ctor args_res
parse_variants (_:rest) = ([], skip_to_newline rest)

fn :: parse_variant_args [RToken] => ([String], [RToken])
parse_variant_args (TokPipe:rest) = ([], [TokPipe] :: rest)
parse_variant_args (TokNewline:rest) = ([], [TokNewline] :: rest)
parse_variant_args (TokEof:rest) = ([], [TokEof] :: rest)
parse_variant_args [] = ([], [])
parse_variant_args ts =
  t1 = parse_type_tok ts
  parse_variant_args_cont t1

fn :: parse_variant_args_cont (String, [RToken]) => ([String], [RToken])
parse_variant_args_cont (ty, rest) =
  more = parse_variant_args rest
  prepend_str ty more

fn :: parse_variants_cont String ([String], [RToken]) => ([RVariant], [RToken])
parse_variants_cont ctor (args, rest) =
  more = parse_variants rest
  prepend_variant (TypeVariant ctor args) more

fn :: prepend_variant RVariant ([RVariant], [RToken]) => ([RVariant], [RToken])
prepend_variant v (vs, rest) = ([v] :: vs, rest)

fn :: strip_optional_colon [RToken] => [RToken]
strip_optional_colon (TokColon:rest) = rest
strip_optional_colon ts = ts

fn :: parse_record_fields [RToken] => ([RField], [RToken])
parse_record_fields (TokNewline:rest) = ([], rest)
parse_record_fields (TokEof:rest) = ([], [TokEof] :: rest)
parse_record_fields [] = ([], [])
parse_record_fields (TokComma:rest) = parse_record_fields rest
parse_record_fields ((TokIdent fname):rest) =
  ty_res = parse_type_tok (strip_optional_colon rest)
  parse_record_fields_cont fname ty_res
parse_record_fields (_:rest) = ([], skip_to_newline rest)

fn :: parse_record_fields_cont String (String, [RToken]) => ([RField], [RToken])
parse_record_fields_cont fname (fty, rest) =
  more = parse_record_fields rest
  prepend_field (TypeField fname fty) more

fn :: prepend_field RField ([RField], [RToken]) => ([RField], [RToken])
prepend_field f (fs, rest) = ([f] :: fs, rest)

fn :: parse_type_decl [RToken] => (RTypeDef, [RToken])
parse_type_decl (TokType:(TokIdent name):TokEquals:((TokIdent first_w):rest))
  | is_upper_ident first_w = finish_sum_type name (parse_variants ([TokIdent first_w] :: rest))
  | otherwise = finish_record_type name (parse_record_fields ([TokIdent first_w] :: rest))
parse_type_decl (_:rest) = (TypeDef "Unknown" [] [], skip_to_newline rest)
parse_type_decl [] = (TypeDef "Unknown" [] [], [])

fn :: finish_sum_type String ([RVariant], [RToken]) => (RTypeDef, [RToken])
finish_sum_type name (vars, rest) = (TypeDef name vars [], rest)

fn :: finish_record_type String ([RField], [RToken]) => (RTypeDef, [RToken])
finish_record_type name (flds, rest) = (TypeDef name [] flds, rest)

-- ── Post-Parse Normalization (echo folding, mixfix, postfix ops) ──

type RArityEntry = ArityEntry String Int

fn :: lookup_arity [RArityEntry] String => Int
lookup_arity [] _ = -1
lookup_arity ((ArityEntry k v):rest) target
  | k == target = v
  | otherwise = lookup_arity rest target

fn :: has_arity_prefix [RArityEntry] String => Bool
has_arity_prefix [] _ = False
has_arity_prefix ((ArityEntry k _):rest) pref
  | k == pref OR (str_starts_with k (pref + "_")) = True
  | otherwise = has_arity_prefix rest pref

fn :: collect_fn_arities [RFnDef] => [RArityEntry]
collect_fn_arities [] = [ArityEntry "send_through" 2, ArityEntry "receive_from" 1, ArityEntry "try_receive_from" 1, ArityEntry "receive_from_timeout" 2]
collect_fn_arities ((FnDef name params _ _):fs) =
  [ArityEntry name (str_list_count params)] :: (collect_fn_arities fs)

fn :: str_list_count [String] => Int
str_list_count [] = 0
str_list_count (_:xs) = 1 + (str_list_count xs)

fn :: take_exprs [RExpr] Int => [RExpr]
take_exprs _ 0 = []
take_exprs [] _ = []
take_exprs (x:xs) n = [x] :: (take_exprs xs (n - 1))

fn :: drop_exprs [RExpr] Int => [RExpr]
drop_exprs xs 0 = xs
drop_exprs [] _ = []
drop_exprs (_:xs) n = drop_exprs xs (n - 1)

fn :: fold_echo_args [RExpr] [RArityEntry] => [RExpr]
fold_echo_args [] _ = []
fold_echo_args ((EVar fn_name):rest) arities =
  ar = lookup_arity arities fn_name
  fold_echo_var fn_name ar rest arities
fold_echo_args (e:rest) arities =
  [norm_expr e arities] :: (fold_echo_args rest arities)

fn :: fold_echo_var String Int [RExpr] [RArityEntry] => [RExpr]
fold_echo_var fn_name ar rest arities
  | ar > 0 AND (expr_list_count rest) >= ar = [ECall fn_name (norm_expr_list (take_exprs rest ar) arities)] :: (fold_echo_args (drop_exprs rest ar) arities)
  | ar == 0 = [ECall fn_name []] :: (fold_echo_args rest arities)
  | otherwise = [EVar fn_name] :: (fold_echo_args rest arities)

fn :: expr_list_count [RExpr] => Int
expr_list_count [] = 0
expr_list_count (_:xs) = 1 + (expr_list_count xs)

fn :: extract_mixfix_call String [RExpr] [RArityEntry] [RExpr] => (String, [RExpr])
extract_mixfix_call cur_name [] _ operands = (cur_name, operands)
extract_mixfix_call cur_name ((EVar w):rest) arities operands
  | has_arity_prefix arities (cur_name + "_" + w) = extract_mixfix_call (cur_name + "_" + w) rest arities operands
  | otherwise = extract_mixfix_call cur_name rest arities (operands :: [EVar w])
extract_mixfix_call cur_name (arg:rest) arities operands =
  extract_mixfix_call cur_name rest arities (operands :: [arg])

fn :: reduce_postfix_spine [RExpr] [RArityEntry] [RExpr] => [RExpr]
reduce_postfix_spine [] _ stack = stack
reduce_postfix_spine ((EVar w):rest) arities stack
  | (lookup_arity arities w) > 0 AND (expr_list_count stack) > 0 = reduce_postfix_spine rest arities [ECall w stack]
  | otherwise = reduce_postfix_spine rest arities (stack :: [EVar w])
reduce_postfix_spine (item:rest) arities stack =
  reduce_postfix_spine rest arities (stack :: [item])

fn :: norm_call String [RExpr] [RArityEntry] => RExpr
norm_call fn_name args arities
  | (lookup_arity arities fn_name) >= 0 = ECall fn_name (norm_expr_list args arities)
  | fn_name == "__chain__" = finish_postfix_stack fn_name args arities (reduce_postfix_spine (norm_expr_list args arities) arities [])
  | otherwise = norm_call_mixfix fn_name args arities (extract_mixfix_call fn_name args arities [])

fn :: norm_call_mixfix String [RExpr] [RArityEntry] (String, [RExpr]) => RExpr
norm_call_mixfix orig_name orig_args arities (mangled, operands)
  | (lookup_arity arities mangled) >= 0 = ECall mangled (norm_expr_list operands arities)
  | otherwise = finish_postfix_stack orig_name orig_args arities (reduce_postfix_spine ([EVar orig_name] :: (norm_expr_list orig_args arities)) arities [])

fn :: finish_postfix_stack String [RExpr] [RArityEntry] [RExpr] => RExpr
finish_postfix_stack _ _ _ ((ECall f a):[]) = ECall f a
finish_postfix_stack orig_name orig_args arities _ = ECall orig_name (norm_expr_list orig_args arities)

fn :: norm_expr RExpr [RArityEntry] => RExpr
norm_expr (EVar name) arities
  | (lookup_arity arities name) == 0 = ECall name []
  | otherwise = EVar name
norm_expr (ENot inner) arities = ENot (norm_expr inner arities)
norm_expr (EOut inner) arities = EOut (norm_expr inner arities)
norm_expr (EBin bop l r) arities = EBin bop (norm_expr l arities) (norm_expr r arities)
norm_expr (ECall fn_name args) arities = norm_call fn_name args arities
norm_expr (EEcho args) arities = EEcho (fold_echo_args args arities)
norm_expr (EStrInterp parts) arities = EStrInterp (norm_expr_list parts arities)
norm_expr (EList elems) arities = EList (norm_expr_list elems arities)
norm_expr (ETuple elems) arities = ETuple (norm_expr_list elems arities)
norm_expr (ETensor elems) arities = ETensor (norm_expr_list elems arities)
norm_expr (EEinsum es subs) arities = EEinsum (norm_expr_list es arities) subs
norm_expr (EHadamard bop l s1 r s2) arities = EHadamard bop (norm_expr l arities) s1 (norm_expr r arities) s2
norm_expr (EIndex base idxs) arities = EIndex (norm_expr base arities) (norm_expr_list idxs arities)
norm_expr (EIndexAssign t idxs v) arities = EIndexAssign t (norm_expr_list idxs arities) (norm_expr v arities)
norm_expr (ESeqSelect b m) arities = ESeqSelect (norm_expr b arities) m
norm_expr (EBlock stmts) arities = EBlock (norm_stmt_list stmts arities)
norm_expr (EWhere body binds) arities = EWhere (norm_expr body arities) (norm_where_list binds arities)
norm_expr (EParPipe branches) arities = EParPipe (norm_expr_list branches arities)
norm_expr (EWithCtx c v b) arities = EWithCtx c (norm_expr v arities) (norm_expr b arities)
norm_expr (EWithRegion q b) arities = EWithRegion q (norm_expr b arities)
norm_expr (EAtomicUpdate v e) arities = EAtomicUpdate v (norm_expr e arities)
norm_expr (ELoadContext c e) arities = ELoadContext c (norm_expr e arities)
norm_expr (ELoadShared v e) arities = ELoadShared v (norm_expr e arities)
norm_expr e _ = e

fn :: norm_expr_list [RExpr] [RArityEntry] => [RExpr]
norm_expr_list [] _ = []
norm_expr_list (e:es) arities = [norm_expr e arities] :: (norm_expr_list es arities)

fn :: norm_stmt_list [RStmt] [RArityEntry] => [RStmt]
norm_stmt_list [] _ = []
norm_stmt_list ((StmtLet v e):ss) arities = [StmtLet v (norm_expr e arities)] :: (norm_stmt_list ss arities)
norm_stmt_list ((StmtExpr e):ss) arities = [StmtExpr (norm_expr e arities)] :: (norm_stmt_list ss arities)
norm_stmt_list ((StmtAtomic v e):ss) arities = [StmtAtomic v (norm_expr e arities)] :: (norm_stmt_list ss arities)
norm_stmt_list ((StmtIndexAssign t idxs e):ss) arities = [StmtIndexAssign t (norm_expr_list idxs arities) (norm_expr e arities)] :: (norm_stmt_list ss arities)

fn :: norm_where_list [RWhereBind] [RArityEntry] => [RWhereBind]
norm_where_list [] _ = []
norm_where_list ((WhereBind e v idxs):wbs) arities = [WhereBind (norm_expr e arities) v idxs] :: (norm_where_list wbs arities)

fn :: norm_guard_list [RGuard] [RArityEntry] => [RGuard]
norm_guard_list [] _ = []
norm_guard_list ((GuardBranch c b):gs) arities = [GuardBranch (norm_expr c arities) (norm_expr b arities)] :: (norm_guard_list gs arities)

fn :: norm_case_list [RFnCase] [RArityEntry] => [RFnCase]
norm_case_list [] _ = []
norm_case_list ((FnCase pats guards body):cs) arities =
  [FnCase pats (norm_guard_list guards arities) (norm_expr body arities)] :: (norm_case_list cs arities)

fn :: norm_fndef_list [RFnDef] [RArityEntry] => [RFnDef]
norm_fndef_list [] _ = []
norm_fndef_list ((FnDef name params ret_ty cases):fs) arities =
  [FnDef name params ret_ty (norm_case_list cases arities)] :: (norm_fndef_list fs arities)

fn :: normalize_program RProgram => RProgram
normalize_program (Program fns tys) =
  arities = collect_fn_arities fns
  Program (norm_fndef_list fns arities) tys

-- ── Top-Level Program Loop ──────────────────────────────────

fn :: parse_items [RToken] [RFnDef] [RTypeDef] => RProgram
parse_items [] fns tys = normalize_program (Program fns tys)
parse_items (TokEof:_) fns tys = normalize_program (Program fns tys)
parse_items (TokNewline:rest) fns tys = parse_items rest fns tys
parse_items (TokAt:rest) fns tys = parse_items (skip_to_newline rest) fns tys
parse_items (TokImport:rest) fns tys = parse_items (skip_to_newline rest) fns tys
parse_items (TokFn:rest) fns tys =
  f_res = parse_fn_decl ([TokFn] :: rest)
  parse_items_after_fn f_res fns tys
parse_items (TokOp:rest) fns tys =
  o_res = parse_op_decl ([TokOp] :: rest)
  parse_items_after_fn o_res fns tys
parse_items (TokGlobal:rest) fns tys =
  g_res = parse_scoped_global 0 ([TokGlobal] :: rest)
  parse_items_after_fn g_res fns tys
parse_items (TokContext:rest) fns tys =
  c_res = parse_scoped_global 1 ([TokContext] :: rest)
  parse_items_after_fn c_res fns tys
parse_items (TokShared:rest) fns tys =
  s_res = parse_scoped_global 2 ([TokShared] :: rest)
  parse_items_after_fn s_res fns tys
parse_items (TokHardware:rest) fns tys =
  hw_res = parse_hardware_decl ([TokHardware] :: rest)
  parse_items_after_fndefs hw_res fns tys
parse_items (TokType:rest) fns tys =
  t_res = parse_type_decl ([TokType] :: rest)
  parse_items_after_type t_res fns tys
parse_items (_:rest) fns tys =
  parse_items (skip_to_newline rest) fns tys

fn :: parse_items_after_fn (RFnDef, [RToken]) [RFnDef] [RTypeDef] => RProgram
parse_items_after_fn (fdef, rest) fns tys =
  parse_items rest (fns :: [fdef]) tys

fn :: parse_items_after_fndefs ([RFnDef], [RToken]) [RFnDef] [RTypeDef] => RProgram
parse_items_after_fndefs (new_fns, rest) fns tys =
  parse_items rest (fns :: new_fns) tys

fn :: parse_items_after_type (RTypeDef, [RToken]) [RFnDef] [RTypeDef] => RProgram
parse_items_after_type (tdef, rest) fns tys =
  parse_items rest fns (tys :: [tdef])

fn :: parse_tokens [RToken] => RProgram
parse_tokens toks = parse_items toks [] []

fn :: count_fndef_list [RFnDef] => Int
count_fndef_list [] = 0
count_fndef_list (_:xs) = 1 + (count_fndef_list xs)

fn :: count_fn_defs RProgram => Int
count_fn_defs (Program fns _) = count_fndef_list fns

fn :: count_type_defs RProgram => Int
count_type_defs (Program _ tys) = count_typedef_list tys

fn :: count_typedef_list [RTypeDef] => Int
count_typedef_list [] = 0
count_typedef_list (_:xs) = 1 + (count_typedef_list xs)
