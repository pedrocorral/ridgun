-- ============================================================
-- src/main/ridgun/parser.rg
-- Self-Hosted Recursive-Descent Parser ([RToken] => RProgram)
-- Full Ridgun v0.9.0 Spec: fn, op, type (sum & record), global,
-- context, shared, hardware, @packed/@repr, tensors, einsum,
-- hadamard, sequences/masks, where-DAG, || pipes, string interp.
-- @implements FR-COMP-001
-- @implements FR-COMP-005
-- @implements FR-COMP-006
-- @implements FR-COMP-007
-- @implements FR-COMP-008
-- @implements FR-COMP-009
-- @implements FR-COMP-010
-- @implements FR-COMP-012
-- @implements FR-COMP-013
-- ============================================================
import ast
import lexer

-- ── Token Stream Helpers ────────────────────────────────────

fn :: tok head [RToken] => RToken
      tok head (t:_)    =  t
      tok head []       =  TokEof

fn :: tok tail [RToken] => [RToken]
      tok tail (_:ts)   =  ts
      tok tail []       =  []

fn :: skip newlines [RToken]        => [RToken]
      skip newlines (TokNewline:ts) =  skip_newlines ts
      skip newlines ts              =  ts

fn :: skip to newline [RToken]        => [RToken]
      skip to newline []              =  []
      skip to newline (TokEof:_)      =  [TokEof]
      skip to newline (TokNewline:ts) =  ts
      skip to newline (_:ts)          =  skip_to_newline ts

fn :: is top keyword RToken      => Bool
      is top keyword TokFn       =  True
      is top keyword TokOp       =  True
      is top keyword TokType     =  True
      is top keyword TokImport   =  True
      is top keyword TokHardware =  True
      is top keyword TokAt       =  True
      is top keyword TokEof      =  True
      is top keyword _           =  False

fn :: has type params then eq [RToken] => Bool
      has type params then eq (TokEquals:_) = True
      has type params then eq ((TokIdent p):rest)
        | is_upper_ident p = has_type_params_then_eq rest
      has type params then eq _ = False

fn :: is top decl start [RToken]        => Bool
      is top decl start (TokFn:TokColonColon:_) = True
      is top decl start (TokFn:_)       =  False
      is top decl start (TokOp:TokColonColon:_) = True
      is top decl start (TokOp:_)       =  False
      is top decl start (TokHardware:TokColonColon:_) = True
      is top decl start (TokHardware:_) =  False
      is top decl start ((TokIdent "module"):TokColonColon:_) = True
      is top decl start (TokType:(TokIdent name):rest)
        | (is_upper_ident name) AND (has_type_params_then_eq rest) = True
      is top decl start ((TokIdent "expand"):TokType:(TokIdent name):rest)
        | (is_upper_ident name) AND (has_type_params_then_eq rest) = True
      is top decl start (TokType:_)     =  False
      is top decl start ts              =  is_top_keyword (tok_head ts)

fn :: last dot idx String Int Int Int => Int
      last dot idx s pos len last_d
        | pos >= len = last_d
        | (str_char_at s pos) == 46 = last_dot_idx s (pos + 1) len pos
        | otherwise = last_dot_idx s (pos + 1) len last_d

fn :: first dot idx String Int Int => Int
      first dot idx s pos len
        | pos >= len = 0 - 1
        | (str_char_at s pos) == 46 = pos
        | otherwise = first_dot_idx s (pos + 1) len

fn :: ident base start String => Int
      ident base start s =
        d = last_dot_idx s 0 (str_len s) (0 - 1)
        d + 1

fn :: ident base slice String Int => String
      ident base slice s d
        | d < 0 = s
        | otherwise = str_slice s (d + 1) (str_len s)

fn :: ident base name String => String
      ident base name s =
        d = last_dot_idx s 0 (str_len s) (0 - 1)
        ident_base_slice s d

fn :: ident mod prefix slice String Int => String
      ident mod prefix slice _ d
        | d <= 0 = ""
      ident mod prefix slice s d = str_slice s 0 d

fn :: ident mod prefix String => String
      ident mod prefix s =
        d = last_dot_idx s 0 (str_len s) (0 - 1)
        ident_mod_prefix_slice s d

fn :: ident first prefix String => String
      ident first prefix s =
        d = first_dot_idx s 0 (str_len s)
        ident_mod_prefix_slice s d

fn :: ident after first dot String => String
      ident after first dot s =
        d = first_dot_idx s 0 (str_len s)
        ident_base_slice s d

fn :: is upper ident String => Bool
      is upper ident s      =
        c = str_char_at s (ident_base_start s)
        c >= 65 AND c <= 90

fn :: is lower ident String => Bool
      is lower ident s      =
        c = str_char_at s (ident_base_start s)
        (c >= 97 AND c <= 122) OR c == 95 OR (str_starts_with s "||")

-- ── Subscript Extraction (A_ij -> ("A", "ij")) ──────────────

fn :: find underscore String Int Int => Int
      find underscore s      pos len
        | pos >= len = -1
        | (str_char_at s pos) == 95 = pos
        | otherwise = find_underscore s (pos + 1) len

fn :: all lower ascii String Int Int => Bool
      all lower ascii s pos len
        | pos >= len = True
        | (str_char_at s pos) >= 97 AND (str_char_at s pos) <= 122 = all_lower_ascii s (pos + 1) len
        | otherwise = False

fn :: all einstein idx chars String Int Int => Bool
      all einstein idx chars s pos len
        | pos >= len = True
        | (str_char_at s pos) >= 105 and (str_char_at s pos) <= 108 = all einstein idx chars s (pos + 1) len
        | otherwise = False

fn :: is trailing underscore ident String => Bool
      is trailing underscore ident s      =
        len = str_len s
        len > 1 and (str_char_at s (len - 1)) == 95

fn :: is subscript ident String => Bool
      is subscript ident s
        | str_contains s "." = False
        | otherwise =
          u_idx = find_underscore s 0 (str_len s)
          check_subscript_parts s u_idx (str_len s)

fn :: check subscript parts String Int Int => Bool
      check subscript parts s u_idx len
        | u_idx <= 0 or (u_idx + 1) >= len = False
        | (find_underscore s (u_idx + 1) len) >= 0 = False
        | is_upper_ident s = all_lower_ascii s (u_idx + 1) len
        | (len - (u_idx + 1)) >= 2 and (len - (u_idx + 1)) <= 4 and (str_slice s (u_idx + 1) len) != "kill" = all einstein idx chars s (u_idx + 1) len
        | otherwise = False

fn :: split subscript String => String String
      split subscript s      =
        u_idx = find_underscore s 0 (str_len s)
        (str_slice s 0 u_idx, str_slice s (u_idx + 1) (str_len s))

-- ── Type String Parsing ─────────────────────────────────────

fn :: check variadic suffix (String, [RToken]) => String [RToken]
      check variadic suffix (base_ty, (TokEllipsis:rest)) = (base_ty + "...", rest)
      check variadic suffix res                =  res

fn :: parse tensor dims [RToken]          => String [RToken]
      parse tensor dims (TokRParen:rest)  =  ("", rest)
      parse tensor dims (TokNewline:rest) =  ("", rest)
      parse tensor dims (TokEof:rest)     =  ("", rest)
      parse tensor dims []                =  ("", [])
      parse tensor dims (TokComma:rest)   =  parse_tensor_dims rest
      parse tensor dims ((TokIdent d):rest) =
        more = parse_tensor_dims rest
        join_tensor_dim d more
      parse tensor dims ((TokInt n):rest) =
        more = parse_tensor_dims rest
        join_tensor_dim (int_to_str n) more
      parse tensor dims (_:rest)          =  parse_tensor_dims rest

fn :: parse tensor bracket tail [RToken]           => String [RToken]
      parse tensor bracket tail (TokRBracket:rest) =  ("", rest)
      parse tensor bracket tail (TokNewline:rest)  =  ("", rest)
      parse tensor bracket tail (TokEof:rest)      =  ("", rest)
      parse tensor bracket tail []                 =  ("", [])
      parse tensor bracket tail ((TokIdent "^"):(TokInt _):TokRBracket:rest) = ("", rest)
      parse tensor bracket tail (TokStar:rest)     =  parse tensor bracket tail rest
      parse tensor bracket tail (TokComma:rest)    =  parse tensor bracket tail rest
      parse tensor bracket tail ((TokIdent d):rest) =
        more = parse tensor bracket tail rest
        join_tensor_dim d more
      parse tensor bracket tail ((TokInt n):rest)  =
        more = parse tensor bracket tail rest
        join_tensor_dim (int_to_str n) more
      parse tensor bracket tail (_:rest)           =  parse tensor bracket tail rest

fn :: parse tensor bracket dims [RToken] => String [RToken]
      parse tensor bracket dims ((TokIdent _):TokRBracket:rest) = ("", rest)
      parse tensor bracket dims ((TokIdent _):rest) = parse tensor bracket tail rest
      parse tensor bracket dims ts       =  parse tensor bracket tail ts

fn :: join tensor dim String (String, [RToken]) => String [RToken]
      join tensor dim d      ("", rest)         =  (d, rest)
      join tensor dim d      (more, rest)       =  (d + "," + more, rest)

fn :: finish tensor type (String, [RToken]) => String [RToken]
      finish tensor type ("", rest)         =  ("Tensor", rest)
      finish tensor type (dims, rest)       =  ("Tensor(" + dims + ")", rest)

fn :: parse type tok [RToken]           => String [RToken]
      parse type tok (TokLBracket:rest) =
        p = parse_type_tok rest
        check_variadic_suffix (parse_type_list_rest p False)
      parse type tok (TokLParen:rest)   =
        check_variadic_suffix (parse_type_paren rest)
      parse type tok ((TokIdent s):TokLParen:rest)
        | s == "Tensor" or s == "Tensor_GPU" = check_variadic_suffix (finish_tensor_type (parse_tensor_dims rest))
        | otherwise = check_variadic_suffix (s, [TokLParen] :: rest)
      parse type tok ((TokIdent s):TokIdxLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = check_variadic_suffix (finish_tensor_type (parse tensor bracket dims rest))
      parse type tok ((TokIdent s):TokLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = check_variadic_suffix (finish_tensor_type (parse tensor bracket dims rest))
      parse type tok ((TokIdent s):rest) =
        check_variadic_suffix (s, rest)
      parse type tok (_:rest)           =  ("Int", rest)
      parse type tok []                 =  ("()", [])

fn :: parse type list rest (String, [RToken]) Bool => String [RToken]
      parse type list rest (acc, (TokComma:rest)) _ =
        p2 = parse_type_tok rest
        merge_type_list acc p2
      parse type list rest (acc, ((TokIdent s):rest)) is_tup
        | is_upper_ident s = merge_type_list acc (parse_type_tok ([TokIdent s] :: rest))
        | otherwise = finish_type_list acc ([TokIdent s] :: rest) is_tup
      parse type list rest (acc, (TokLBracket:rest)) _ =
        p2 = parse_type_tok ([TokLBracket] :: rest)
        merge_type_list acc p2
      parse type list rest (acc, (TokLParen:rest)) _ =
        p2 = parse_type_tok ([TokLParen] :: rest)
        merge_type_list acc p2
      parse type list rest (acc, (TokRBracket:rest)) is_tup = finish_type_list acc rest is_tup
      parse type list rest (acc, rest) is_tup = finish_type_list acc rest is_tup

fn :: merge type list String (String, [RToken]) => String [RToken]
      merge type list acc    (next_ty, rest)    =
        parse_type_list_rest (acc + ", " + next_ty, rest) True

fn :: finish type list String [RToken] Bool => String [RToken]
      finish type list acc rest True = ("[(" + acc + ")]", rest)
      finish type list acc rest False = ("[" + acc + "]", rest)

fn :: parse type paren [RToken]         => String [RToken]
      parse type paren (TokRParen:rest) =  ("()", rest)
      parse type paren (TokLParen:TokRParen:TokFatArrow:rest) =
        merge_type_fn "__err_unit_fn_type__" (parse_type_tok rest)
      parse type paren (TokFatArrow:rest) =
        merge_type_fn "()" (parse_type_tok rest)
      parse type paren ((TokIdent s):rest)
        | (is_lower_ident s) AND (is_paren_lambda ([TokIdent s] :: rest) False) =
          ("__err_lower_fn_type__", skip_to_rparen rest 0)
      parse type paren ts               =
        p1 = parse_type_tok ts
        parse_type_tuple_rest p1

fn :: skip to rparen [RToken] Int => [RToken]
      skip to rparen [] _ = []
      skip to rparen (TokEof:rest) _ = [TokEof] :: rest
      skip to rparen (TokNewline:rest) 0 = [TokNewline] :: rest
      skip to rparen (TokLParen:rest) d = skip_to_rparen rest (d + 1)
      skip to rparen (TokRParen:rest) 0 = rest
      skip to rparen (TokRParen:rest) d = skip_to_rparen rest (d - 1)
      skip to rparen (_:rest) d = skip_to_rparen rest d

fn :: parse type tuple rest (String, [RToken]) => String [RToken]
      parse type tuple rest (acc, (TokComma:rest)) =
        p2 = parse_type_tok rest
        merge_type_tuple acc p2
      parse type tuple rest (acc, (TokFatArrow:rest)) =
        p_ret = parse_type_tok rest
        merge_type_fn acc p_ret
      parse type tuple rest (acc, (TokArrow:rest)) =
        p_ret = parse_type_tok rest
        merge_type_fn acc p_ret
      parse type tuple rest (acc, ((TokIdent s):rest))
        | is_upper_ident s = merge_type_tuple acc (parse_type_tok ([TokIdent s] :: rest))
      parse type tuple rest (acc, (TokLBracket:rest)) =
        p2 = parse_type_tok ([TokLBracket] :: rest)
        merge_type_tuple acc p2
      parse type tuple rest (acc, (TokLParen:rest)) =
        p2 = parse_type_tok ([TokLParen] :: rest)
        merge_type_tuple acc p2
      parse type tuple rest (acc, (TokRParen:rest)) = ("(" + acc + ")", rest)
      parse type tuple rest (acc, rest)        =  ("(" + acc + ")", rest)

fn :: merge type fn String (String, [RToken]) => String [RToken]
      merge type fn acc    (ret_ty, (TokRParen:rest)) = ("(" + acc + " => " + ret_ty + ")", rest)
      merge type fn acc    (ret_ty, rest)     =  ("(" + acc + " => " + ret_ty + ")", rest)

fn :: merge type tuple String (String, [RToken]) => String [RToken]
      merge type tuple acc    (next_ty, rest)    =
        parse_type_tuple_rest (acc + ", " + next_ty, rest)

fn :: parse return types [RToken] => String [RToken]
      parse return types ts       =
        p1 = parse_type_tok ts
        parse_return_types_more p1 False

fn :: parse return types more (String, [RToken]) Bool => String [RToken]
      parse return types more (acc, (TokComma:rest)) _ =
        p2 = parse_type_tok rest
        merge_return_types acc p2
      parse return types more (acc, ((TokIdent s):rest)) is_tup
        | is_upper_ident s = merge_return_types acc (parse_type_tok ([TokIdent s] :: rest))
        | otherwise = finish_return_types acc ([TokIdent s] :: rest) is_tup
      parse return types more (acc, (TokLBracket:rest)) _ =
        p2 = parse_type_tok ([TokLBracket] :: rest)
        merge_return_types acc p2
      parse return types more (acc, (TokLParen:rest)) _ =
        p2 = parse_type_tok ([TokLParen] :: rest)
        merge_return_types acc p2
      parse return types more (acc, rest) is_tup = finish_return_types acc rest is_tup

fn :: merge return types String (String, [RToken]) => String [RToken]
      merge return types acc    (next_ty, rest)    =
        parse_return_types_more (acc + ", " + next_ty, rest) True

fn :: finish return types String [RToken] Bool => String [RToken]
      finish return types acc rest True = ("(" + acc + ")", rest)
      finish return types acc rest False = (acc, rest)

fn :: parse param types [RToken]           => [String] [RToken]
      parse param types (TokFatArrow:rest) =  ([], [TokFatArrow] :: rest)
      parse param types (TokArrow:rest)    =  ([], [TokArrow] :: rest)
      parse param types (TokNewline:rest)  =  ([], [TokNewline] :: rest)
      parse param types (TokEof:rest)      =  ([], [TokEof] :: rest)
      parse param types []                 =  ([], [])
      parse param types ts                 =
        p1 = parse_type_tok ts
        parse_param_types_cont p1

fn :: parse param types cont (String, [RToken]) => [String] [RToken]
      parse param types cont (ty, rest)         =
        p_more = parse_param_types rest
        prepend_str ty p_more

fn :: prepend str String ([String], [RToken]) => [String] [RToken]
      prepend str s      (xs, rest)           =  ([s] :: xs, rest)

-- ── Pattern Parsing ─────────────────────────────────────────

fn :: extract fst str (String, String) => String
      extract fst str (a, _)           =  a

fn :: pat list count [RPattern] => Int
      pat list count []         =  0
      pat list count (_:ps)     =  1 + (pat list count ps)

fn :: parse tensor pat dims [RToken]           => [RPattern] [RToken]
      parse tensor pat dims (TokRBracket:rest) =  ([], rest)
      parse tensor pat dims (TokNewline:rest)  =  ([], rest)
      parse tensor pat dims (TokEof:rest)      =  ([], rest)
      parse tensor pat dims []                 =  ([], [])
      parse tensor pat dims (TokStar:(TokInt n):rest) =
        more = parse tensor pat dims rest
        prepend_pat (PatInt n) more
      parse tensor pat dims (TokStar:(TokIdent v):rest)
        | v == "_" = prepend_pat PatWild (parse tensor pat dims rest)
        | otherwise = prepend_pat (PatVar v) (parse tensor pat dims rest)
      parse tensor pat dims (_:rest)           =  parse tensor pat dims rest

fn :: strip rparen [RToken]         => [RToken]
      strip rparen (TokRParen:rest) =  rest
      strip rparen ts               =  ts

fn :: finish tensor pat with inner RPattern [RPattern] (RPattern, [RToken]) => RPattern [RToken]
      finish tensor pat with inner rank_pat dim_pats (t_pat, after_t) =
        (PatCtor ":tensor-pat:" ([t_pat, rank_pat] :: dim_pats), strip rparen after_t)

fn :: finish tensor pat target RPattern [RPattern] [RToken] => RPattern [RToken]
      finish tensor pat target rank_pat dim_pats (TokRParen:rest) =
        (PatCtor ":tensor-pat:" ([PatWild, rank_pat] :: dim_pats), rest)
      finish tensor pat target rank_pat dim_pats ts =
        finish tensor pat with inner rank_pat dim_pats (parse_pattern ts)

fn :: finish tensor pat dims ([RPattern], [RToken]) Bool => RPattern [RToken]
      finish tensor pat dims (dim_pats, after_rb) True =
        finish tensor pat target (PatInt (pat list count dim_pats)) dim_pats after_rb
      finish tensor pat dims (dim_pats, after_rb) False =
        (PatCtor ":tensor-pat:" ([PatWild, PatInt (pat list count dim_pats)] :: dim_pats), after_rb)

fn :: parse tensor pat after elem (String, [RToken]) Bool => RPattern [RToken]
      parse tensor pat after elem (_, (TokRBracket:after_rb)) True =
        finish tensor pat target PatWild [] after_rb
      parse tensor pat after elem (_, (TokRBracket:after_rb)) False =
        (PatCtor ":tensor-pat:" [PatWild, PatWild], after_rb)
      parse tensor pat after elem (_, ((TokIdent "^"):(TokInt k):TokRBracket:after_rb)) True =
        finish tensor pat target (PatInt k) [] after_rb
      parse tensor pat after elem (_, ((TokIdent "^"):(TokInt k):TokRBracket:after_rb)) False =
        (PatCtor ":tensor-pat:" [PatWild, PatInt k], after_rb)
      parse tensor pat after elem (_, ((TokIdent "^"):(TokIdent kv):TokRBracket:after_rb)) True
        | kv == "_" = finish tensor pat target PatWild [] after_rb
        | otherwise = finish tensor pat target (PatVar kv) [] after_rb
      parse tensor pat after elem (_, ((TokIdent "^"):(TokIdent kv):TokRBracket:after_rb)) False
        | kv == "_" = (PatCtor ":tensor-pat:" [PatWild, PatWild], after_rb)
        | otherwise = (PatCtor ":tensor-pat:" [PatWild, PatVar kv], after_rb)
      parse tensor pat after elem (_, (TokStar:after_star)) has_paren =
        finish tensor pat dims (parse tensor pat dims ([TokStar] :: after_star)) has_paren
      parse tensor pat after elem (_, rest) has_paren =
        finish tensor pat dims (parse tensor pat dims rest) has_paren

fn :: parse tensor pat [RToken] Bool      => RPattern [RToken]
      parse tensor pat ts       has_paren =
        parse tensor pat after elem (parse_type_tok ts) has_paren

fn :: parse pattern [RToken]           => RPattern [RToken]
      parse pattern ((TokInt n):rest)  =  (PatInt n, rest)
      parse pattern (TokMinus:(TokInt n):rest) = (PatInt (0 - n), rest)
      parse pattern ((TokReal r):rest) =  (PatReal r, rest)
      parse pattern (TokMinus:(TokReal r):rest) = (PatReal ("-" + r), rest)
      parse pattern ((TokStr s):rest)  =  (PatStr s, rest)
      parse pattern ((TokRawStr s):rest) = (PatStr s, rest)
      parse pattern (TokTrue:rest)     =  (PatBool True, rest)
      parse pattern (TokFalse:rest)    =  (PatBool False, rest)
      parse pattern (TokLBracket:TokRBracket:rest) = (PatEmpty, rest)
      parse pattern (TokLParen:TokRParen:rest) = (PatWild, rest)
      parse pattern (TokType:rest)     =  (PatVar "type", rest)
      parse pattern (TokWith:rest)     =  (PatVar "with", rest)
      parse pattern (TokLParen:(TokIdent s):TokIdxLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = parse tensor pat rest True
      parse pattern (TokLParen:(TokIdent s):TokLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = parse tensor pat rest True
      parse pattern ((TokIdent s):TokIdxLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = parse tensor pat rest False
      parse pattern ((TokIdent s):TokLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = parse tensor pat rest False
      parse pattern ((TokIdent s):rest)
        | s == "_" = (PatWild, rest)
        | is_subscript_ident s = (PatVar (extract fst str (split_subscript s)), rest)
        | (is_upper_ident s) and (str_len s) > 1 = (PatCtor s [], rest)
        | otherwise = (PatVar s, rest)
      parse pattern (TokLParen:rest)   =
        p1 = parse_pattern rest
        parse_paren_pattern p1
      parse pattern (_:rest)           =  (PatWild, rest)
      parse pattern []                 =  (PatWild, [])

fn :: parse paren pattern (RPattern, [RToken]) => RPattern [RToken]
      parse paren pattern (first_p, (TokColon:rest)) =
        p2 = parse_cons_tail rest
        finish_cons_pat first_p p2
      parse paren pattern (first_p, (TokComma:rest)) =
        p_list = parse_tuple_pats rest
        finish_tuple_pat first_p p_list
      parse paren pattern ((PatVar v), (TokRParen:rest)) = (PatSeqBind v, rest)
      parse paren pattern (first_p, (TokRParen:rest)) = (first_p, rest)
      parse paren pattern ((PatCtor ctor []), rest) =
        p_args = parse_ctor_subpats rest
        finish_ctor_pat ctor p_args
      parse paren pattern ((PatVar ctor), rest) =
        p_args = parse_ctor_subpats rest
        finish_ctor_pat ctor p_args
      parse paren pattern (first_p, rest)      =  (first_p, rest)

fn :: parse cons tail [RToken] => RPattern [RToken]
      parse cons tail ts       =
        p1 = parse_pattern ts
        parse_cons_tail_cont p1

fn :: parse cons tail cont (RPattern, [RToken]) => RPattern [RToken]
      parse cons tail cont (p, (TokColon:rest)) =
        more = parse_cons_tail rest
        finish_cons_pat p more
      parse cons tail cont (p, (TokRParen:rest)) = (p, rest)
      parse cons tail cont (p, rest)            =  (p, rest)

fn :: finish cons pat RPattern (RPattern, [RToken]) => RPattern [RToken]
      finish cons pat h        (t, rest)            =  (PatCons h t, rest)

fn :: parse tuple pats [RToken] => [RPattern] [RToken]
      parse tuple pats ts       =
        p1 = parse_pattern ts
        parse_tuple_pats_cont p1

fn :: parse tuple pats cont (RPattern, [RToken]) => [RPattern] [RToken]
      parse tuple pats cont (p, (TokComma:rest)) =
        more = parse_tuple_pats rest
        prepend_pat p more
      parse tuple pats cont (p, (TokRParen:rest)) = ([p], rest)
      parse tuple pats cont (p, rest)            =  ([p], rest)

fn :: finish tuple pat RPattern ([RPattern], [RToken]) => RPattern [RToken]
      finish tuple pat p1       (ps, rest)             =  (PatTuple ([p1] :: ps), rest)

fn :: parse ctor subpats [RToken]          => [RPattern] [RToken]
      parse ctor subpats (TokRParen:rest)  =  ([], rest)
      parse ctor subpats (TokNewline:rest) =  ([], rest)
      parse ctor subpats (TokEof:rest)     =  ([], rest)
      parse ctor subpats []                =  ([], [])
      parse ctor subpats ts                =
        p1 = parse_pattern ts
        parse_ctor_subpats_tail p1

fn :: parse ctor subpats tail (RPattern, [RToken]) => [RPattern] [RToken]
      parse ctor subpats tail (p, rest)            =
        tail_res = parse_ctor_subpats rest
        prepend_pat p tail_res

fn :: finish ctor pat String ([RPattern], [RToken]) => RPattern [RToken]
      finish ctor pat ctor   (args, rest)           =  (PatCtor ctor args, rest)

fn :: prepend pat RPattern ([RPattern], [RToken]) => [RPattern] [RToken]
      prepend pat p        (ps, rest)             =  ([p] :: ps, rest)

fn :: parse case patterns [RToken]          => [RPattern] [RToken]
      parse case patterns (TokEquals:rest)  =  ([], [TokEquals] :: rest)
      parse case patterns (TokNewline:rest) =  ([], [TokNewline] :: rest)
      parse case patterns (TokEof:rest)     =  ([], [TokEof] :: rest)
      parse case patterns []                =  ([], [])
      parse case patterns ts                =
        p1 = parse_pattern ts
        parse_case_patterns_cont p1

fn :: parse case patterns cont (RPattern, [RToken]) => [RPattern] [RToken]
      parse case patterns cont (p, rest)            =
        more = parse_case_patterns rest
        prepend_pat p more

-- ── String Interpolation & Escaped Braces Parsing ───────────

fn :: find matching rbrace String Int Int => Int
      find matching rbrace s pos len
        | pos >= len = -1
        | (str_char_at s pos) == 125 = pos
        | (str_char_at s pos) == 10 OR (str_char_at s pos) == 59 OR (str_char_at s pos) == 34 = -1
        | otherwise = find_matching_rbrace s (pos + 1) len

fn :: has interp brace String Int Int => Bool
      has interp brace s pos len
        | pos >= len = False
        | (str_char_at s pos) == 123 AND (str_char_at s (pos + 1)) == 123 = has_interp_brace s (pos + 2) len
        | (str_char_at s pos) == 125 AND (str_char_at s (pos + 1)) == 125 = has_interp_brace s (pos + 2) len
        | (str_char_at s pos) == 123 AND (find_matching_rbrace s (pos + 1) len) > (pos + 1) = True
        | otherwise = has_interp_brace s (pos + 1) len

fn :: unescape double braces String Int Int String => String
      unescape double braces s pos len acc
        | pos >= len = acc
        | (str_char_at s pos) == 123 AND (str_char_at s (pos + 1)) == 123 = unescape_double_braces s (pos + 2) len (acc + (char_from_code 123))
        | (str_char_at s pos) == 125 AND (str_char_at s (pos + 1)) == 125 = unescape_double_braces s (pos + 2) len (acc + (char_from_code 125))
        | otherwise = unescape_double_braces s (pos + 1) len (acc + (str_slice s pos (pos + 1)))

fn :: flush lit part String [RExpr] => [RExpr]
      flush lit part ""     parts   =  parts
      flush lit part lit    parts   =  parts :: [EStr lit]

fn :: parse interp code String   => RExpr
      parse interp code code_str =
        toks = tokenize_src code_str
        extract_expr_fst (parse_expr toks)

fn :: extract expr fst (RExpr, [RToken]) => RExpr
      extract expr fst (e, _)            =  e

fn :: split interp loop String Int Int String [RExpr] => [RExpr]
      split interp loop s pos len cur_lit parts
        | pos >= len = flush_lit_part cur_lit parts
        | (str_char_at s pos) == 123 AND (str_char_at s (pos + 1)) == 123 = split_interp_loop s (pos + 2) len (cur_lit + (char_from_code 123)) parts
        | (str_char_at s pos) == 125 AND (str_char_at s (pos + 1)) == 125 = split_interp_loop s (pos + 2) len (cur_lit + (char_from_code 125)) parts
        | (str_char_at s pos) == 123 = split_interp_at_brace s pos len cur_lit parts (find_matching_rbrace s (pos + 1) len)
        | otherwise = split_interp_loop s (pos + 1) len (cur_lit + (str_slice s pos (pos + 1))) parts

fn :: split interp at brace String Int Int String [RExpr] Int => [RExpr]
      split interp at brace s pos len cur_lit parts rbrace_idx
        | rbrace_idx <= (pos + 1) = split_interp_loop s (pos + 1) len (cur_lit + (char_from_code 123)) parts
        | otherwise = split_interp_loop s (rbrace_idx + 1) len "" ((flush_lit_part cur_lit parts) :: [parse_interp_code (str_slice s (pos + 1) rbrace_idx)])

fn :: build str expr String => RExpr
      build str expr s
        | NOT ((str_contains s (char_from_code 123)) OR (str_contains s (char_from_code 125))) = EStr s
        | has_interp_brace s 0 (str_len s) = EStrInterp (split_interp_loop s 0 (str_len s) "" [])
        | otherwise = EStr (unescape_double_braces s 0 (str_len s) "")

-- ── Expression Parsing (Precedence Climbing) ────────────────

fn :: is atom tok RToken        => Bool
      is atom tok (TokInt _)    =  True
      is atom tok (TokReal _)   =  True
      is atom tok (TokStr _)    =  True
      is atom tok (TokRawStr _) =  True
      is atom tok TokTrue       =  True
      is atom tok TokFalse      =  True
      is atom tok (TokIdent w)  =  w != "shl" AND w != "shr" AND w != "rotr" AND w != "rotl"
      is atom tok TokFn         =  True
      is atom tok TokOp         =  True
      is atom tok TokImport     =  True
      is atom tok TokHardware   =  True
      is atom tok TokOtherwise  =  True
      is atom tok TokMut        =  True
      is atom tok TokType       =  True
      is atom tok TokWith       =  True
      is atom tok TokNot        =  True
      is atom tok TokLParen     =  True
      is atom tok TokLBracket   =  True
      is atom tok _             =  False

fn :: is with block start [RToken] => Bool
      is with block start (TokWith:(TokIdent s):_)
        | s == "region" OR s == "timeout" = True
      is with block start _        =  False

fn :: parse expr [RToken] => RExpr [RToken]
      parse expr ts
        | is_with_block_start ts = parse_with_expr ts
        | otherwise = parse_logic_expr ts

fn :: skip do token [RToken]     => [RToken]
      skip do token (TokDo:rest) =  rest
      skip do token ts           =  ts

fn :: parse with region after Int [RToken] => RExpr [RToken]
      parse with region after quota (TokComma:(TokIdent t_kw):rest)
        | t_kw == "timeout" =
          d_res = parse_logic_expr rest
          wrap_with_region quota (parse_with_ctx_body "__rg_timeout_ms__" d_res)
      parse with region after quota rest =
        wrap_with_region quota (parse_case_body (skip_do_token (skip_newlines rest)))

fn :: parse with timeout after (RExpr, [RToken]) => RExpr [RToken]
      parse with timeout after (dur_e, (TokComma:(TokIdent r_kw):(TokIdent l_kw):(TokInt quota):rest))
        | r_kw == "region" AND l_kw == "limit" =
          b_res = parse_case_body (skip_do_token (skip_newlines rest))
          wrap_with_ctx "__rg_timeout_ms__" dur_e (wrap_with_region quota b_res)
      parse with timeout after (dur_e, (TokComma:(TokIdent r_kw):(TokInt quota):rest))
        | r_kw == "region" =
          b_res = parse_case_body (skip_do_token (skip_newlines rest))
          wrap_with_ctx "__rg_timeout_ms__" dur_e (wrap_with_region quota b_res)
      parse with timeout after d_res             =
        parse_with_ctx_body "__rg_timeout_ms__" d_res

fn :: parse with expr [RToken] => RExpr [RToken]
      parse with expr (TokWith:(TokIdent r_kw):(TokIdent l_kw):(TokInt quota):rest)
        | r_kw == "region" AND l_kw == "limit" = parse_with_region_after quota rest
      parse with expr (TokWith:(TokIdent r_kw):(TokInt quota):rest)
        | r_kw == "region" = parse_with_region_after quota rest
      parse with expr (TokWith:(TokIdent t_kw):rest)
        | t_kw == "timeout" = parse_with_timeout_after (parse_logic_expr rest)
      parse with expr (_:rest) =  parse_logic_expr rest
      parse with expr []       =  (EUnit, [])

fn :: wrap with region Int   (RExpr, [RToken]) => RExpr [RToken]
      wrap with region quota (body, rest)      =
        dot_res = strip_optional_pipe_dot rest
        finish_with_region quota body dot_res

fn :: finish with region Int RExpr (Bool, [RToken]) => RExpr [RToken]
      finish with region quota body (_, after_dot) = (EWithRegion quota body, after_dot)

fn :: parse with ctx body String (RExpr, [RToken]) => RExpr [RToken]
      parse with ctx body ctx_name (val_e, rest) =
        clean = skip_do_token (skip_newlines rest)
        b_res = parse_case_body clean
        wrap_with_ctx ctx_name val_e b_res

fn :: wrap with ctx String RExpr (RExpr, [RToken]) => RExpr [RToken]
      wrap with ctx ctx_name val_e (body, rest) =
        dot_res = strip_optional_pipe_dot rest
        finish_with_ctx ctx_name val_e body dot_res

fn :: finish with ctx String RExpr RExpr (Bool, [RToken]) => RExpr [RToken]
      finish with ctx ctx_name val_e body (_, after_dot) = (EWithCtx ctx_name val_e body, after_dot)

fn :: parse logic expr [RToken] => RExpr [RToken]
      parse logic expr ts       =
        p1 = parse_not_expr ts
        parse_logic_loop p1

fn :: parse logic loop (RExpr, [RToken]) => RExpr [RToken]
      parse logic loop (left, (TokAnd:rest)) =
        r = parse_not_expr rest
        parse_logic_combine OpAnd left r
      parse logic loop (left, (TokOr:rest)) =
        r = parse_not_expr rest
        parse_logic_combine OpOr left r
      parse logic loop (left, (TokXor:rest)) =
        r = parse_not_expr rest
        parse_logic_combine OpXor left r
      parse logic loop res               =  res

fn :: parse logic combine RBinOp RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse logic combine bop left (right, rest) =
        parse_logic_loop (make_add_or_hadamard bop left right, rest)

fn :: parse not expr [RToken]      => RExpr [RToken]
      parse not expr (TokNot:rest) =
        inner = parse_not_expr rest
        wrap_not inner
      parse not expr ts            =  parse_cmp_expr ts

fn :: wrap not (RExpr, [RToken]) => RExpr [RToken]
      wrap not (e, rest)         =  (ENot e, rest)

fn :: parse cmp expr [RToken] => RExpr [RToken]
      parse cmp expr ts       =
        p1 = parse_add_expr ts
        parse_cmp_tail p1

fn :: parse cmp tail (RExpr, [RToken]) => RExpr [RToken]
      parse cmp tail (left, (TokEqEq:rest)) = combine_bin OpEq left (parse_add_expr rest)
      parse cmp tail (left, (TokNeq:rest)) = combine_bin OpNeq left (parse_add_expr rest)
      parse cmp tail (left, (TokGt:rest)) = combine_bin OpGt left (parse_add_expr rest)
      parse cmp tail (left, (TokLt:rest)) = combine_bin OpLt left (parse_add_expr rest)
      parse cmp tail (left, (TokGtEq:rest)) = combine_bin OpGtEq left (parse_add_expr rest)
      parse cmp tail (left, (TokLtEq:rest)) = combine_bin OpLtEq left (parse_add_expr rest)
      parse cmp tail res               =  res

fn :: combine bin RBinOp RExpr (RExpr, [RToken]) => RExpr [RToken]
      combine bin bop    left  (right, rest)     =  (EBin bop left right, rest)

fn :: is hadamard bop RBinOp => Bool
      is hadamard bop OpAdd  =  True
      is hadamard bop OpSub  =  True
      is hadamard bop OpMul  =  True
      is hadamard bop OpDiv  =  True
      is hadamard bop OpAnd  =  True
      is hadamard bop OpOr   =  True
      is hadamard bop OpXor  =  True
      is hadamard bop _      =  False

fn :: make add or hadamard RBinOp RExpr RExpr => RExpr
      make add or hadamard bop (EVar v1) (EVar v2)
        | (is hadamard bop bop) and (is_subscript_ident v1) and (is_subscript_ident v2) = build_hadamard_node bop (split_subscript v1) (split_subscript v2)
      make add or hadamard bop (EHadamard b1 l1 s1 r1 s2) (EVar v2)
        | (is hadamard bop bop) and (is_subscript_ident v2) = build hadamard chain r bop (EHadamard b1 l1 s1 r1 s2) s1 (split_subscript v2)
      make add or hadamard bop (EVar v1) (EHadamard b2 l2 s2 r2 s3)
        | (is hadamard bop bop) and (is_subscript_ident v1) = build hadamard chain l bop (split_subscript v1) (EHadamard b2 l2 s2 r2 s3) s2
      make add or hadamard bop left right = EBin bop left right

fn :: build hadamard node RBinOp (String, String) (String, String) => RExpr
      build hadamard node bop (b1, s1) (b2, s2) =
        EHadamard bop (EVar b1) s1 (EVar b2) s2

fn :: build hadamard chain r RBinOp RExpr String (String, String) => RExpr
      build hadamard chain r bop left s1 (b2, s2) =
        EHadamard bop left s1 (EVar b2) s2

fn :: build hadamard chain l RBinOp (String, String) RExpr String => RExpr
      build hadamard chain l bop (b1, s1) right s2 =
        EHadamard bop (EVar b1) s1 right s2

fn :: make matmul or einsum RExpr RExpr => RExpr
      make matmul or einsum (EEinsum es subs) (EVar v2)
        | is_subscript_ident v2 = append_einsum_term es subs (split_subscript v2)
      make matmul or einsum (EVar v1) (EVar v2)
        | (is_subscript_ident v1) AND (is_subscript_ident v2) = build_einsum_pair (split_subscript v1) (split_subscript v2)
      make matmul or einsum left right = EBin OpMatMul left right

fn :: append einsum term [RExpr] [String] (String, String) => RExpr
      append einsum term es subs (b2, s2) =
        EEinsum (es :: [EVar b2]) (subs :: [s2])

fn :: build einsum pair (String, String) (String, String) => RExpr
      build einsum pair (b1, s1)         (b2, s2)         =
        EEinsum [EVar b1, EVar b2] [s1, s2]

fn :: parse add expr [RToken] => RExpr [RToken]
      parse add expr ts       =
        p1 = parse_mul_expr ts
        parse_add_loop p1

fn :: parse add loop (RExpr, [RToken]) => RExpr [RToken]
      parse add loop (left, (TokPlus:rest)) =
        r = parse_mul_expr (skip_newlines rest)
        parse_add_combine OpAdd left r
      parse add loop (left, (TokMinus:rest)) =
        r = parse_mul_expr (skip_newlines rest)
        parse_add_combine OpSub left r
      parse add loop (left, (TokColonColon:rest)) =
        r = parse_mul_expr (skip_newlines rest)
        parse_add_combine OpConcat left r
      parse add loop (left, (TokColon:rest)) =
        r = parse_add_expr (skip_newlines rest)
        parse_colon_combine left r
      parse add loop res               =  res

fn :: parse colon combine RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse colon combine left ((EList elems), rest) =
        (EList ([left] :: elems), rest)
      parse colon combine left ((EBin OpConcat (EList elems) tail_e), rest) =
        (EBin OpConcat (EList ([left] :: elems)) tail_e, rest)
      parse colon combine left (right, rest) =
        (EBin OpConcat (EList [left]) right, rest)

fn :: parse add combine RBinOp RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse add combine bop left (right, rest) =
        parse_add_loop (make_add_or_hadamard bop left right, rest)

fn :: parse mul expr [RToken] => RExpr [RToken]
      parse mul expr ts       =
        p1 = parse_app_expr ts
        parse_mul_loop p1

fn :: parse mul loop (RExpr, [RToken]) => RExpr [RToken]
      parse mul loop (left, (TokStar:rest)) =
        r = parse_app_expr rest
        parse_mul_combine OpMul left r
      parse mul loop (left, (TokSlash:rest)) =
        r = parse_app_expr rest
        parse_mul_combine OpDiv left r
      parse mul loop (left, (TokPercent:rest)) =
        r = parse_app_expr rest
        parse_mul_combine OpMod left r
      parse mul loop (left, (TokAt:rest)) =
        r = parse_app_expr rest
        parse_matmul_combine left r
      parse mul loop (left, ((TokIdent "shl"):rest)) =
        r = parse_app_expr rest
        parse_mul_combine OpShl left r
      parse mul loop (left, ((TokIdent "shr"):rest)) =
        r = parse_app_expr rest
        parse_mul_combine OpShr left r
      parse mul loop (left, ((TokIdent "rotr"):rest)) =
        r = parse_app_expr rest
        parse_mul_combine OpRotr left r
      parse mul loop (left, ((TokIdent "rotl"):rest)) =
        r = parse_app_expr rest
        parse_mul_combine OpRotl left r
      parse mul loop res               =  res

fn :: parse mul combine RBinOp RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse mul combine bop left (right, rest) =
        parse_mul_loop (make_add_or_hadamard bop left right, rest)

fn :: parse matmul combine RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse matmul combine left  (right, rest)     =
        parse_mul_loop (make_matmul_or_einsum left right, rest)

-- ── Sequence Mask / Selector Detection: s(+ _) or s(0 3) ───

fn :: is seq mask tokens [RToken] => Bool
      is seq mask tokens (TokLParen:TokPlus:_) = True
      is seq mask tokens (TokLParen:(TokIdent s):TokPlus:_)
        | s == "_" OR s == "__" OR s == "___" = True
      is seq mask tokens (TokLParen:(TokIdent s):(TokIdent _):_)
        | s == "_" OR s == "__" OR s == "___" = True
      is seq mask tokens (TokLParen:(TokIdent s):TokRParen:_)
        | s == "_" OR s == "__" OR s == "___" = True
      is seq mask tokens (TokLParen:(TokInt _):(TokInt _):_) = True
      is seq mask tokens _        =  False

fn :: scan seq mask [RToken]          String => String [RToken]
      scan seq mask (TokRParen:rest)  acc    =  (acc, rest)
      scan seq mask (TokPlus:rest)    acc    =  scan_seq_mask rest (acc + "+")
      scan seq mask ((TokIdent s):rest) acc  =  scan_seq_mask rest (acc + s)
      scan seq mask ((TokInt n):rest) ""     =  scan_seq_mask rest (int_to_str n)
      scan seq mask ((TokInt n):rest) acc    =  scan_seq_mask rest (acc + " " + (int_to_str n))
      scan seq mask (_:rest)          acc    =  (acc, rest)
      scan seq mask []                acc    =  (acc, [])

fn :: finish seq select RExpr (String, [RToken]) => RExpr [RToken]
      finish seq select base  (mask, rest)       =  (ESeqSelect base mask, rest)

-- ── Application & Postfix (`out`, `s(+ _)`, calls) ──────────

fn :: is record update start [RToken] => Bool
      is record update start (TokWith:(TokIdent _):TokEquals:_) = True
      is record update start (TokWith:TokType:TokEquals:_) = True
      is record update start (TokWith:TokWith:TokEquals:_) = True
      is record update start _        =  False

fn :: extract field name [RToken] => String [RToken]
      extract field name ((TokIdent f):TokEquals:rest) = (f, rest)
      extract field name (TokType:TokEquals:rest) = ("type", rest)
      extract field name (TokWith:TokEquals:rest) = ("with", rest)
      extract field name ts       =  ("", ts)

fn :: has next record field [RToken] => Bool
      has next record field (TokComma:(TokIdent _):TokEquals:_) = True
      has next record field (TokComma:TokType:TokEquals:_) = True
      has next record field (TokComma:TokWith:TokEquals:_) = True
      has next record field _        =  False

fn :: parse record update pairs [RToken] [RExpr] => [RExpr] [RToken]
      parse record update pairs ts acc =
        f_res = extract_field_name ts
        parse_record_update_val f_res acc

fn :: parse record update val (String, [RToken]) [RExpr] => [RExpr] [RToken]
      parse record update val ("", ts) acc = (acc, ts)
      parse record update val (fname, rest) acc =
        v_res = parse_logic_expr rest
        parse_record_update_more fname v_res acc

fn :: parse record update more String (RExpr, [RToken]) [RExpr] => [RExpr] [RToken]
      parse record update more fname (val_e, (TokComma:rest)) acc
        | has_next_record_field ([TokComma] :: rest) = parse_record_update_pairs rest (acc :: [EStr fname, val_e])
        | otherwise = (acc :: [EStr fname, val_e], [TokComma] :: rest)
      parse record update more fname (val_e, rest) acc =
        (acc :: [EStr fname, val_e], rest)

fn :: parse record update RExpr [RToken]       => RExpr [RToken]
      parse record update base  (TokWith:rest) =
        p_res = parse_record_update_pairs rest []
        finish_record_update base p_res
      parse record update base  ts             =  (base, ts)

fn :: finish record update RExpr ([RExpr], [RToken]) => RExpr [RToken]
      finish record update base  (pairs, rest)       =
        check_record_update_tail (ECall "__record_update__" ([base] :: pairs), rest)

fn :: check record update tail (RExpr, [RToken]) => RExpr [RToken]
      check record update tail (base_e, rest)
        | is_record_update_start rest = parse_record_update base_e rest
        | otherwise = (base_e, rest)

fn :: parse app expr [RToken] => RExpr [RToken]
      parse app expr ts       =
        p1 = parse_atom ts
        parse_app_tail p1

fn :: parse app tail (RExpr, [RToken]) => RExpr [RToken]
      parse app tail ((EVar name), (TokLParen:rest))
        | is_seq_mask_tokens ([TokLParen] :: rest) = finish_seq_select (EVar name) (scan_seq_mask rest "")
      parse app tail ((EVar name), rest)
        | is_record_update_start rest = parse_record_update (EVar name) rest
        | name == "echo" = finish_echo_call (parse_atom_list rest)
        | is_atom_tok (tok_head rest) = check_record_update_tail (finish_fn_or_out_call (EVar name) name (parse_atom_list rest))
        | otherwise = (EVar name, rest)
      parse app tail (first_e, rest)
        | is_record_update_start rest = parse_record_update first_e rest
        | is_atom_tok (tok_head rest) = check_record_update_tail (finish_chain_or_out first_e (parse_atom_list rest))
        | otherwise = (first_e, rest)

fn :: finish fn or out call RExpr String ([RExpr], [RToken]) => RExpr [RToken]
      finish fn or out call first_e _ (((EVar w):[]), rest)
        | w == "out" = (EOut first_e, rest)
      finish fn or out call _ name (args, rest) = (ECall name args, rest)

fn :: finish chain or out RExpr ([RExpr], [RToken]) => RExpr [RToken]
      finish chain or out first_e (((EVar w):[]), rest)
        | w == "out" = (EOut first_e, rest)
      finish chain or out first_e (args, rest) = (ECall "__chain__" ([first_e] :: args), rest)

fn :: parse atom list [RToken] => [RExpr] [RToken]
      parse atom list ts
        | is_record_update_start ts = ([], ts)
        | is_atom_tok (tok_head ts) = parse_atom_list_cont (parse_atom ts)
        | otherwise = ([], ts)

fn :: parse atom list cont (RExpr, [RToken]) => [RExpr] [RToken]
      parse atom list cont (e, rest)         =
        more = parse_atom_list rest
        prepend_expr e more

fn :: prepend expr RExpr ([RExpr], [RToken]) => [RExpr] [RToken]
      prepend expr e     (es, rest)          =  ([e] :: es, rest)

fn :: finish echo call ([RExpr], [RToken]) => RExpr [RToken]
      finish echo call (args, rest)        =  (EEcho args, rest)

-- ── Atom & Postfix Indexing (`m[0, 1]`, `m[0][1]`) ──────────

fn :: parse atom [RToken] => RExpr [RToken]
      parse atom ts       =
        base_res = parse_atom_base ts
        parse_postfix_index base_res

fn :: parse atom base [RToken]           => RExpr [RToken]
      parse atom base ((TokInt n):rest)  =  (EInt n, rest)
      parse atom base ((TokReal r):rest) =  (EReal r, rest)
      parse atom base ((TokStr s):rest)  =  (build_str_expr s, rest)
      parse atom base ((TokRawStr s):rest) = (EStr s, rest)
      parse atom base (TokTrue:rest)     =  (EBool True, rest)
      parse atom base (TokFalse:rest)    =  (EBool False, rest)
      parse atom base (TokFn:rest)       =  (EVar "fn", rest)
      parse atom base (TokOp:rest)       =  (EVar "op", rest)
      parse atom base (TokImport:rest)   =  (EVar "import", rest)
      parse atom base (TokHardware:rest) =  (EVar "hardware", rest)
      parse atom base (TokOtherwise:rest) = (EVar "otherwise", rest)
      parse atom base (TokMut:rest)      =  (EVar "mut", rest)
      parse atom base (TokType:rest)     =  (EVar "type", rest)
      parse atom base (TokWith:rest)     =  (EVar "with", rest)
      parse atom base (TokNot:rest)      =  (EVar "not", rest)
      parse atom base ((TokIdent s):TokLBracket:(TokIdent elem_ty):TokStar:after_star)
        | (s == "Tensor" or s == "Tensor_GPU") and (is_upper_ident elem_ty) = finish tensor alloc elem_ty (parse tensor alloc dims ([TokStar] :: after_star))
      parse atom base ((TokIdent s):TokIdxLBracket:(TokIdent elem_ty):TokStar:after_star)
        | (s == "Tensor" or s == "Tensor_GPU") and (is_upper_ident elem_ty) = finish tensor alloc elem_ty (parse tensor alloc dims ([TokStar] :: after_star))
      parse atom base ((TokIdent s):TokLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = finish_tensor_lit (parse_comma_exprs rest)
      parse atom base ((TokIdent s):TokIdxLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = finish_tensor_lit (parse_comma_exprs rest)
      parse atom base ((TokIdent s):rest) = (EVar s, rest)
      parse atom base (TokMinus:(TokInt n):rest) = (EInt (0 - n), rest)
      parse atom base (TokMinus:(TokReal r):rest) = (EReal ("-" + r), rest)
      parse atom base (TokLParen:TokRParen:rest) = (EUnit, rest)
      parse atom base (TokLParen:TokLParen:TokRParen:TokFatArrow:rest) =
        (ECall "__syntax_error__" [EStr "zero-parameter lambda uses '(=> expr)', not '(() => expr)'"], skip_to_rparen rest 0)
      parse atom base (TokLParen:TokRParen:TokFatArrow:rest) =
        (ECall "__syntax_error__" [EStr "zero-parameter lambda uses '(=> expr)', not '(() => expr)'"], skip_to_newline rest)
      parse atom base (TokLParen:TokFatArrow:rest) =
        parse_lambda_paren (parse_lambda_body [] rest)
      parse atom base (TokLParen:rest)
        | is_paren_lambda rest False = parse_lambda_paren (parse_lambda_expr rest [])
        | is_paren_type_arrow rest False =
          (ECall "__syntax_error__" [EStr "type signature '(Type => Type)' cannot be used as an expression; lambda parameters must start with a lowercase letter"], skip_to_rparen rest 0)
        | otherwise =
          p1 = parse_expr rest
          parse_paren_expr p1
      parse atom base (TokLBracket:TokRBracket:rest) = (EList [], rest)
      parse atom base (TokLBracket:rest) =
        elems_res = parse_comma_exprs rest
        finish_list_lit elems_res
      parse atom base (_:rest)           =  (EUnit, rest)
      parse atom base []                 =  (EUnit, [])

fn :: is lambda param ident String => Bool
      is lambda param ident "_" = True
      is lambda param ident s = (is_lower_ident s) AND (NOT (str_contains s "."))

fn :: scan lambda tuple params [RToken] [String] => Bool [String] [RToken]
      scan lambda tuple params (TokRParen:rest) acc = ((str_list_count acc) >= 2, acc, rest)
      scan lambda tuple params (TokComma:rest) acc = scan_lambda_tuple_params rest acc
      scan lambda tuple params ((TokIdent p):rest) acc
        | is_lambda_param_ident p = scan_lambda_tuple_params rest (acc :: [p])
      scan lambda tuple params (TokType:rest) acc = scan_lambda_tuple_params rest (acc :: ["type"])
      scan lambda tuple params (TokWith:rest) acc = scan_lambda_tuple_params rest (acc :: ["with"])
      scan lambda tuple params ts _ = (False, [], ts)

fn :: is paren lambda [RToken] Bool => Bool
      is paren lambda (TokFatArrow:_) has_p = has_p
      is paren lambda ((TokIdent p):rest) _
        | is_lambda_param_ident p = is_paren_lambda rest True
      is paren lambda (TokType:rest) _ = is_paren_lambda rest True
      is paren lambda (TokWith:rest) _ = is_paren_lambda rest True
      is paren lambda (TokLParen:rest) _ =
        is_paren_lambda_tuple (scan_lambda_tuple_params rest [])
      is paren lambda _ _ = False

fn :: is paren lambda tuple (Bool, [String], [RToken]) => Bool
      is paren lambda tuple (True, _, after_tup) = is_paren_lambda after_tup True
      is paren lambda tuple (False, _, _) = False

fn :: is paren type arrow [RToken] Bool => Bool
      is paren type arrow (TokFatArrow:_) has_t = has_t
      is paren type arrow ((TokIdent s):rest) _
        | is_upper_ident s = is_paren_type_arrow rest True
      is paren type arrow (TokComma:rest) has_t = is_paren_type_arrow rest has_t
      is paren type arrow _ _ = False

fn :: join raw comma strs [String] => String
      join raw comma strs [] = ""
      join raw comma strs (s:[]) = s
      join raw comma strs (s:ss) = s + "," + (join_raw_comma_strs ss)

fn :: parse lambda expr [RToken] [RExpr] => RExpr [RToken]
      parse lambda expr (TokFatArrow:rest) params =
        parse_lambda_body params rest
      parse lambda expr ((TokIdent p):rest) params =
        parse_lambda_expr rest (params :: [EStr p])
      parse lambda expr (TokType:rest) params =
        parse_lambda_expr rest (params :: [EStr "type"])
      parse lambda expr (TokWith:rest) params =
        parse_lambda_expr rest (params :: [EStr "with"])
      parse lambda expr (TokLParen:rest) params =
        parse_lambda_tup_step params (scan_lambda_tuple_params rest [])
      parse lambda expr ts params =
        parse_lambda_body params ts

fn :: parse lambda tup step [RExpr] (Bool, [String], [RToken]) => RExpr [RToken]
      parse lambda tup step params (True, tup_vars, after_tup) =
        parse_lambda_expr after_tup (params :: [EStr ("(" + (join_raw_comma_strs tup_vars) + ")")])
      parse lambda tup step params (False, _, after_tup) =
        parse_lambda_body params after_tup

fn :: parse lambda body [RExpr] [RToken] => RExpr [RToken]
      parse lambda body params (TokNewline:rest) =
        finish_lambda_expr params (parse_case_body ([TokNewline] :: rest))
      parse lambda body params ts =
        finish_lambda_expr params (parse_expr ts)

fn :: parse lambda paren (RExpr, [RToken]) => RExpr [RToken]
      parse lambda paren (e, rest) =
        clean = skip_newlines rest
        finish_lambda_paren e rest clean

fn :: finish lambda paren RExpr [RToken] [RToken] => RExpr [RToken]
      finish lambda paren e _ (TokRParen:after_rp) = (e, after_rp)
      finish lambda paren e orig_rest _ = parse_paren_expr (e, orig_rest)

fn :: finish lambda expr [RExpr] (RExpr, [RToken]) => RExpr [RToken]
      finish lambda expr params (body_e, rest) =
        (ECall "__lambda__" (params :: [body_e]), rest)

fn :: tensor zero fill String  => RExpr
      tensor zero fill _       =  EInt 0

fn :: parse tensor alloc dims [RToken]           => [RExpr] [RToken]
      parse tensor alloc dims (TokRBracket:rest) =  ([], rest)
      parse tensor alloc dims (TokNewline:rest)  =  ([], rest)
      parse tensor alloc dims (TokEof:rest)      =  ([], rest)
      parse tensor alloc dims []                 =  ([], [])
      parse tensor alloc dims (TokStar:rest)     =
        d_res = parse_atom rest
        parse tensor alloc dims cont d_res
      parse tensor alloc dims ts                 =
        d_res = parse_atom ts
        parse tensor alloc dims cont d_res

fn :: parse tensor alloc dims cont (RExpr, [RToken]) => [RExpr] [RToken]
      parse tensor alloc dims cont (d_e, rest) =
        more = parse tensor alloc dims rest
        prepend_expr d_e more

fn :: finish tensor alloc String  ([RExpr], [RToken]) => RExpr [RToken]
      finish tensor alloc elem_ty (dims, rest)        =
        (ECall ":tensor-zeros:" ([tensor zero fill elem_ty] :: dims), rest)

fn :: finish tensor lit ([RExpr], [RToken]) => RExpr [RToken]
      finish tensor lit (elems, rest)       =  (ETensor elems, rest)

fn :: parse postfix index (RExpr, [RToken]) => RExpr [RToken]
      parse postfix index ((EVar v), (TokIdxLBracket:rest)) =
        idx_res = collect_bracket_indices ([TokIdxLBracket] :: rest) []
        finish_index_expr (EVar v) idx_res
      parse postfix index ((EVar v), (TokLParen:rest))
        | is trailing underscore ident v =
          base_e = EVar (str_slice v 0 ((str_len v) - 1))
          check chained subscript (parse subscript paren base_e rest)
      parse postfix index res               =  check chained subscript res

fn :: check chained subscript (RExpr, [RToken]) => RExpr [RToken]
      check chained subscript (base_e, ((TokIdent "_"):TokLParen:rest)) =
        check chained subscript (parse subscript paren base_e rest)
      check chained subscript res               =  res

fn :: parse subscript paren RExpr  [RToken]           => RExpr [RToken]
      parse subscript paren base_e (TokComma:after_c) =
        c_res = parse_expr after_c
        finish col slice expr base_e c_res
      parse subscript paren base_e ts                 =
        i1_res = parse_expr ts
        parse subscript after first base_e i1_res

fn :: finish col slice expr RExpr (RExpr, [RToken]) => RExpr [RToken]
      finish col slice expr base_e (col_e, rest) =
        (ECall ":tensor-col-slice:" [base_e, col_e], strip rparen rest)

fn :: parse subscript after first RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse subscript after first base_e (idx1, (TokComma:TokRParen:rest)) =
        (ECall ":tensor-row-slice:" [base_e, idx1], rest)
      parse subscript after first base_e (idx1, (TokComma:more_ts)) =
        more_res = parse_comma_exprs more_ts
        finish multi subscript expr base_e idx1 more_res
      parse subscript after first base_e (idx1, (TokRParen:rest)) =
        (EIndex base_e [idx1], rest)
      parse subscript after first base_e (idx1, rest) =
        (EIndex base_e [idx1], rest)

fn :: finish multi subscript expr RExpr RExpr ([RExpr], [RToken]) => RExpr [RToken]
      finish multi subscript expr base_e idx1 (more_idxs, rest) =
        (EIndex base_e ([idx1] :: more_idxs), rest)

fn :: collect bracket indices [RToken] [RExpr] => [RExpr] [RToken]
      collect bracket indices (TokIdxLBracket:rest) acc =
        one_bracket = parse_comma_exprs rest
        collect_bracket_more acc one_bracket
      collect bracket indices ts       acc     =  (acc, ts)

fn :: collect bracket more [RExpr] ([RExpr], [RToken]) => [RExpr] [RToken]
      collect bracket more acc     (idxs, rest)        =
        collect_bracket_indices rest (acc :: idxs)

fn :: finish index expr RExpr ([RExpr], [RToken]) => RExpr [RToken]
      finish index expr base  ([], rest)          =  (base, rest)
      finish index expr base  (idxs, rest)        =  (EIndex base idxs, rest)

fn :: parse paren expr (RExpr, [RToken]) => RExpr [RToken]
      parse paren expr (first_e, (TokComma:rest)) =
        more = parse_comma_exprs rest
        finish_tuple_lit first_e more
      parse paren expr (first_e, (TokRParen:rest)) = (first_e, rest)
      parse paren expr (first_e, rest)   =  (first_e, rest)

fn :: parse comma exprs [RToken] => [RExpr] [RToken]
      parse comma exprs ts       =
        p1 = parse_expr ts
        parse_comma_exprs_cont p1

fn :: parse comma exprs cont (RExpr, [RToken]) => [RExpr] [RToken]
      parse comma exprs cont (e, (TokComma:rest)) =
        more = parse_comma_exprs rest
        prepend_expr e more
      parse comma exprs cont (e, (TokRParen:rest)) = ([e], rest)
      parse comma exprs cont (e, (TokRBracket:rest)) = ([e], rest)
      parse comma exprs cont (e, rest)         =  ([e], rest)

fn :: finish list lit ([RExpr], [RToken]) => RExpr [RToken]
      finish list lit (elems, rest)       =  (EList elems, rest)

fn :: finish tuple lit RExpr ([RExpr], [RToken]) => RExpr [RToken]
      finish tuple lit e1    (es, rest)          =  (ETuple ([e1] :: es), rest)

-- ── Guards, ParPipes, Blocks & Where Clauses ────────────────

fn :: strip optional pipe dot [RToken]          => Bool [RToken]
      strip optional pipe dot (TokPipeDot:rest) =  (True, rest)
      strip optional pipe dot (TokNewline:rest) =  strip_pipe_dot_after_nl rest (skip_newlines rest)
      strip optional pipe dot ts                =  (False, ts)

fn :: strip pipe dot after nl [RToken] [RToken] => Bool [RToken]
      strip pipe dot after nl _ (TokPipeDot:rest) = (True, rest)
      strip pipe dot after nl orig_ts _ = (False, orig_ts)

fn :: finish otherwise guard (RExpr, [RToken]) => [RGuard] [RToken]
      finish otherwise guard (body, rest)      =
        dot_res = strip_optional_pipe_dot rest
        finish_otherwise_after_dot body dot_res

fn :: finish otherwise after dot RExpr (Bool, [RToken]) => [RGuard] [RToken]
      finish otherwise after dot body (_, after_dot) =
        ([GuardBranch (EBool True) body], after_dot)

fn :: split guard cond [RToken] Int [RToken] => [RToken] [RToken]
      split guard cond [] _ acc = (acc, [])
      split guard cond (TokEquals:rest) 0 acc = (acc, [TokEquals] :: rest)
      split guard cond (TokNewline:rest) 0 acc = (acc, [TokNewline] :: rest)
      split guard cond (TokEof:rest) 0 acc = (acc, [TokEof] :: rest)
      split guard cond (TokLParen:rest) depth acc =
        split_guard_cond rest (depth + 1) (acc :: [TokLParen])
      split guard cond (TokLBracket:rest) depth acc =
        split_guard_cond rest (depth + 1) (acc :: [TokLBracket])
      split guard cond (TokRParen:rest) depth acc
        | depth > 0 = split_guard_cond rest (depth - 1) (acc :: [TokRParen])
        | otherwise = split_guard_cond rest 0 (acc :: [TokRParen])
      split guard cond (TokRBracket:rest) depth acc
        | depth > 0 = split_guard_cond rest (depth - 1) (acc :: [TokRBracket])
        | otherwise = split_guard_cond rest 0 (acc :: [TokRBracket])
      split guard cond (t:rest) depth acc =
        split_guard_cond rest depth (acc :: [t])

fn :: parse guard cond split ([RToken], [RToken]) => RExpr [RToken]
      parse guard cond split (cond_toks, after_cond) =
        c = parse_expr cond_toks
        finish_guard_cond_split c after_cond

fn :: finish guard cond split (RExpr, [RToken]) [RToken] => RExpr [RToken]
      finish guard cond split (cond_e, _) after_cond = (cond_e, after_cond)

fn :: parse guards [RToken]       => [RGuard] [RToken]
      parse guards (TokPipe:TokOtherwise:TokEquals:rest) =
        b = parse_case_body rest
        finish_otherwise_guard b
      parse guards (TokPipe:rest) =
        c = parse_guard_cond_split (split_guard_cond rest 0 [])
        parse_guard_after_cond c
      parse guards ts             =  ([], ts)

fn :: parse guard after cond (RExpr, [RToken]) => [RGuard] [RToken]
      parse guard after cond (cond, (TokEquals:rest)) =
        b = parse_case_body rest
        parse_guards_cont cond b
      parse guard after cond (cond, rest)      =
        b = parse_case_body rest
        parse_guards_cont cond b

fn :: parse guards cont RExpr (RExpr, [RToken]) => [RGuard] [RToken]
      parse guards cont cond  (body, rest)      =
        dot_res = strip_optional_pipe_dot rest
        parse_guards_after_dot cond body dot_res

fn :: parse guards after dot RExpr RExpr (Bool, [RToken]) => [RGuard] [RToken]
      parse guards after dot cond body (True, after_dot) =
        ([GuardBranch cond body], after_dot)
      parse guards after dot cond body (False, rest) =
        trimmed = skip_newlines rest
        more = parse_guards trimmed
        prepend_guard (GuardBranch cond body) more

fn :: prepend guard RGuard ([RGuard], [RToken]) => [RGuard] [RToken]
      prepend guard g      (gs, rest)           =  ([g] :: gs, rest)

fn :: finish guard expr ([RGuard], [RToken]) => RExpr [RToken]
      finish guard expr (guards, rest)       =  (EGuard guards, rest)

fn :: line has equals [RToken] => Bool
      line has equals ts = line_has_equals_depth ts 0

fn :: line has equals depth [RToken] Int => Bool
      line has equals depth [] _ = False
      line has equals depth (TokEof:_) _ = False
      line has equals depth (TokNewline:_) _ = False
      line has equals depth (TokLParen:ts) d = line_has_equals_depth ts (d + 1)
      line has equals depth (TokLBracket:ts) d = line_has_equals_depth ts (d + 1)
      line has equals depth (TokIdxLBracket:ts) d = line_has_equals_depth ts (d + 1)
      line has equals depth (TokRParen:ts) d
        | d > 0 = line_has_equals_depth ts (d - 1)
        | otherwise = line_has_equals_depth ts 0
      line has equals depth (TokRBracket:ts) d
        | d > 0 = line_has_equals_depth ts (d - 1)
        | otherwise = line_has_equals_depth ts 0
      line has equals depth (TokWith:ts) 0
        | is_record_update_start ([TokWith] :: ts) = False
        | otherwise = line_has_equals_depth ts 0
      line has equals depth (TokEquals:_) 0 = True
      line has equals depth (_:ts) d = line_has_equals_depth ts d

fn :: is echo expr RExpr            => Bool
      is echo expr (EEcho _)        =  True
      is echo expr (ECall "send" _) =  True
      is echo expr (ECall "send_to" _) = True
      is echo expr (ECall "send_through" _) = True
      is echo expr (ECall "stop" _) =  True
      is echo expr _                =  False

fn :: line followed by pipe [RToken]       => Bool
      line followed by pipe []             =  False
      line followed by pipe (TokEof:_)     =  False
      line followed by pipe (TokNewline:TokPipe:_) = True
      line followed by pipe (TokNewline:_) =  False
      line followed by pipe (TokEquals:_)  =  False
      line followed by pipe (_:ts)         =  line_followed_by_pipe ts

fn :: next line has guard [RToken] => Bool
      next line has guard ts       =
        clean = skip_newlines ts
        next_line_has_guard_clean clean

fn :: next line has guard clean [RToken] => Bool
      next line has guard clean (TokPipe:_) = False
      next line has guard clean ts = line_followed_by_pipe ts

fn :: line has arrow [RToken]       => Bool
      line has arrow []             =  False
      line has arrow (TokEof:_)     =  False
      line has arrow (TokNewline:_) =  False
      line has arrow (TokArrow:_)   =  True
      line has arrow (_:ts)         =  line_has_arrow ts

fn :: line has fat arrow [RToken] => Bool
      line has fat arrow ts = line_has_fat_arrow_depth ts 0

fn :: line has fat arrow depth [RToken] Int => Bool
      line has fat arrow depth [] _ = False
      line has fat arrow depth (TokEof:_) _ = False
      line has fat arrow depth (TokNewline:_) _ = False
      line has fat arrow depth (TokLParen:ts) d = line_has_fat_arrow_depth ts (d + 1)
      line has fat arrow depth (TokLBracket:ts) d = line_has_fat_arrow_depth ts (d + 1)
      line has fat arrow depth (TokIdxLBracket:ts) d = line_has_fat_arrow_depth ts (d + 1)
      line has fat arrow depth (TokRParen:ts) d
        | d > 0 = line_has_fat_arrow_depth ts (d - 1)
        | otherwise = line_has_fat_arrow_depth ts 0
      line has fat arrow depth (TokRBracket:ts) d
        | d > 0 = line_has_fat_arrow_depth ts (d - 1)
        | otherwise = line_has_fat_arrow_depth ts 0
      line has fat arrow depth (TokFatArrow:_) 0 = True
      line has fat arrow depth (_:ts) d = line_has_fat_arrow_depth ts d

fn :: parse int indices [RToken]           => [Int] [RToken]
      parse int indices (TokRBracket:rest) =  ([], rest)
      parse int indices (TokComma:rest)    =  parse_int_indices rest
      parse int indices ((TokInt n):rest)  =
        more = parse_int_indices rest
        prepend_int n more
      parse int indices (_:rest)           =  ([], rest)
      parse int indices []                 =  ([], [])

fn :: prepend int Int ([Int], [RToken]) => [Int] [RToken]
      prepend int n   (ns, rest)        =  ([n] :: ns, rest)

fn :: strip optional dpipe dot [RToken]          => Bool [RToken]
      strip optional dpipe dot (TokDoublePipeDot:rest) = (True, rest)
      strip optional dpipe dot (TokNewline:rest) =  strip_dpipe_dot_after_nl rest (skip_newlines rest)
      strip optional dpipe dot ts                =  (False, ts)

fn :: strip dpipe dot after nl [RToken] [RToken] => Bool [RToken]
      strip dpipe dot after nl _ (TokDoublePipeDot:rest) = (True, rest)
      strip dpipe dot after nl orig_ts _ = (False, orig_ts)

fn :: parse pipe where binds [RToken] => [RWhereBind] [RToken]
      parse pipe where binds ts       =
        clean = skip_newlines ts
        parse_pipe_where_step ts clean

fn :: parse pipe where step [RToken] [RToken] => [RWhereBind] [RToken]
      parse pipe where step _ (TokDoublePipe:rest)
        | line_has_arrow rest = parse_pipe_where_target (parse_expr rest)
      parse pipe where step orig_ts _ = ([], orig_ts)

fn :: parse pipe where target (RExpr, [RToken]) => [RWhereBind] [RToken]
      parse pipe where target (e, (TokArrow:(TokIdent v):TokIdxLBracket:rest)) =
        idx_res = parse_int_indices rest
        parse_pipe_where_indexed e v idx_res
      parse pipe where target (e, (TokArrow:(TokIdent v):rest)) =
        dot_res = strip_optional_dpipe_dot rest
        parse_pipe_where_after_dot (WhereBind e v []) dot_res
      parse pipe where target (_, rest)         =  ([], rest)

fn :: parse pipe where indexed RExpr String ([Int], [RToken]) => [RWhereBind] [RToken]
      parse pipe where indexed e v (idxs, rest) =
        dot_res = strip_optional_dpipe_dot rest
        parse_pipe_where_after_dot (WhereBind e v idxs) dot_res

fn :: parse pipe where after dot RWhereBind (Bool, [RToken]) => [RWhereBind] [RToken]
      parse pipe where after dot wb (True, after_dot) = ([wb], after_dot)
      parse pipe where after dot wb (False, rest) =
        more = parse_pipe_where_binds rest
        prepend_where wb more

fn :: prepend where RWhereBind ([RWhereBind], [RToken]) => [RWhereBind] [RToken]
      prepend where wb         (wbs, rest)              =  ([wb] :: wbs, rest)

fn :: check trailing comma and where (RExpr, [RToken]) => RExpr [RToken]
      check trailing comma and where (first_e, (TokComma:rest)) =
        more = parse_comma_exprs rest
        check_trailing_where (finish_tuple_lit first_e more)
      check trailing comma and where res = check_trailing_where res

fn :: check trailing where (RExpr, [RToken]) => RExpr [RToken]
      check trailing where (body, rest)      =
        clean = skip_newlines rest
        check_trailing_where_tok body rest clean

fn :: check trailing where tok RExpr [RToken] [RToken] => RExpr [RToken]
      check trailing where tok body _ (TokDoublePipe:after_dp)
        | line_has_arrow after_dp = finish_where_expr body (parse_pipe_where_binds ([TokDoublePipe] :: after_dp))
      check trailing where tok body orig_rest _ = (body, orig_rest)

fn :: finish where expr RExpr ([RWhereBind], [RToken]) => RExpr [RToken]
      finish where expr body  (binds, rest)            =  (EWhere body binds, rest)

fn :: parse par pipe branches [RToken] => [RExpr] [RToken]
      parse par pipe branches (TokDoublePipe:rest) =
        e_res = parse_expr rest
        parse_par_pipe_more e_res
      parse par pipe branches ts       =  ([], ts)

fn :: parse par pipe more (RExpr, [RToken]) => [RExpr] [RToken]
      parse par pipe more (e, rest)         =
        dot_res = strip_optional_dpipe_dot rest
        parse_par_pipe_after_dot e dot_res

fn :: parse par pipe after dot RExpr (Bool, [RToken]) => [RExpr] [RToken]
      parse par pipe after dot e (True, after_dot) = ([e], after_dot)
      parse par pipe after dot e (False, rest) =
        clean = skip_newlines rest
        parse_par_pipe_check e rest clean

fn :: parse par pipe check RExpr [RToken] [RToken] => [RExpr] [RToken]
      parse par pipe check e _ (TokDoublePipe:more_ts) =
        more = parse_par_pipe_branches ([TokDoublePipe] :: more_ts)
        prepend_expr e more
      parse par pipe check e orig_rest _ = ([e], orig_rest)

fn :: finish par pipe ([RExpr], [RToken]) => RExpr [RToken]
      finish par pipe (branches, rest)    =  (EParPipe branches, rest)

fn :: parse case body dpipe [RToken] => RExpr [RToken]
      parse case body dpipe (TokDoublePipe:rest)
        | line_has_arrow rest = finish_dpipe_where_block (parse_pipe_where_binds ([TokDoublePipe] :: rest))
        | otherwise = finish_par_pipe (parse_par_pipe_branches ([TokDoublePipe] :: rest))
      parse case body dpipe ts       =  finish_par_pipe (parse_par_pipe_branches ts)

fn :: finish dpipe where block ([RWhereBind], [RToken]) => RExpr [RToken]
      finish dpipe where block (binds, rest)            =
        stmts_res = parse_block_stmts_safe rest
        wrap_dpipe_where_stmts binds stmts_res

fn :: wrap dpipe where stmts [RWhereBind] ([RStmt], [RToken]) => RExpr [RToken]
      wrap dpipe where stmts binds (stmts, rest) =
        (EWhere (EBlock stmts) binds, rest)

fn :: has unparenthesized fat arrow [RToken] => Bool
      has unparenthesized fat arrow [] = False
      has unparenthesized fat arrow (TokNewline:_) = False
      has unparenthesized fat arrow (TokEof:_) = False
      has unparenthesized fat arrow (TokLParen:_) = False
      has unparenthesized fat arrow (TokFatArrow:_) = True
      has unparenthesized fat arrow ((TokIdent p):rest)
        | is_lambda_param_ident p = has_unparenthesized_fat_arrow rest
      has unparenthesized fat arrow _ = False

fn :: parse let rhs [RToken]          => RExpr [RToken]
      parse let rhs (TokNewline:rest) =
        clean = skip_newlines rest
        parse_let_rhs_newline rest clean
      parse let rhs (TokPipe:rest)    =
        finish_guard_expr (parse_guards ([TokPipe] :: rest))
      parse let rhs (TokDoublePipe:rest) =
        finish_par_pipe (parse_par_pipe_branches ([TokDoublePipe] :: rest))
      parse let rhs ts
        | has_unparenthesized_fat_arrow ts =
          (ECall "__syntax_error__" [EStr "lambda expression must be enclosed in parentheses: '(x => expr)'"], skip_to_newline ts)
        | otherwise =
          check_trailing_comma_and_where (parse_expr ts)

fn :: parse let rhs newline [RToken] [RToken] => RExpr [RToken]
      parse let rhs newline _ (TokPipe:rest) =
        finish_guard_expr (parse_guards ([TokPipe] :: rest))
      parse let rhs newline _ (TokDoublePipe:rest) =
        finish_par_pipe (parse_par_pipe_branches ([TokDoublePipe] :: rest))
      parse let rhs newline orig_rest _ =
        check_trailing_comma_and_where (parse_expr orig_rest)

fn :: wrap subscript let rhs (RExpr, [RToken]) => RExpr [RToken]
      wrap subscript let rhs ((EVar rhs_v), rest)
        | is_subscript_ident rhs_v = (ECall ":tensor-clone:" [EVar (extract fst str (split_subscript rhs_v))], rest)
      wrap subscript let rhs res               =  res

fn :: collect ident lhs list [RToken] [String] => Bool [String] [RToken]
      collect ident lhs list ((TokIdent v):TokComma:rest) acc =
        collect ident lhs list rest (acc :: [v])
      collect ident lhs list ((TokIdent v):TokEquals:rest) acc =
        (True, acc :: [v], rest)
      collect ident lhs list ts acc =
        (False, acc, ts)

fn :: build tup unpack stmts [String] String Int [RStmt] => [RStmt]
      build tup unpack stmts [] _ _ tail_stmts = tail_stmts
      build tup unpack stmts (v:vs) tmp_name idx tail_stmts =
        [StmtMut v (EIndex (EVar tmp_name) [EInt idx])] :: (build tup unpack stmts vs tmp_name (idx + 1) tail_stmts)

fn :: finish tup destructure String [String] (RExpr, [RToken]) => [RStmt] [RToken]
      finish tup destructure first_v vars (rhs_e, after_rhs) =
        tmp_name = ":tup-" + first_v + ":"
        more_res = parse_block_stmts_safe after_rhs
        finish tup destructure more tmp_name vars rhs_e more_res

fn :: finish tup destructure more String [String] RExpr ([RStmt], [RToken]) => [RStmt] [RToken]
      finish tup destructure more tmp_name vars rhs_e (more_stmts, rest) =
        ([StmtMut tmp_name rhs_e] :: (build tup unpack stmts vars tmp_name 0 more_stmts), rest)

fn :: parse tuple destructure stmt String (Bool, [String], [RToken]) [RToken] => [RStmt] [RToken]
      parse tuple destructure stmt first_v (True, vars, after_eq) _ =
        finish tup destructure first_v vars (parse_let_rhs after_eq)
      parse tuple destructure stmt first_v (False, _, _) orig_rest =
        finish_expr_stmt (parse_expr ([TokIdent first_v, TokComma] :: orig_rest))

fn :: collect multi subscript lhs [RToken] [RExpr] => Bool [RExpr] [RToken]
      collect multi subscript lhs ((TokIdent vk):TokLParen:rest) acc
        | is trailing underscore ident vk =
          tk = str_slice vk 0 ((str_len vk) - 1)
          collect multi subscript one tk acc (parse_comma_exprs rest)
      collect multi subscript lhs ts acc =
        (False, acc, ts)

fn :: collect multi subscript one String [RExpr] ([RExpr], [RToken]) => Bool [RExpr] [RToken]
      collect multi subscript one tk acc (idxs, (TokComma:rest)) =
        collect multi subscript lhs rest (acc :: [EIndexAssign tk idxs EUnit])
      collect multi subscript one tk acc (idxs, (TokEquals:rest)) =
        (True, acc :: [EIndexAssign tk idxs EUnit], rest)
      collect multi subscript one _ acc (_, rest) =
        (False, acc, rest)

fn :: build multi idx assign stmts [RExpr] String Int [RStmt] => [RStmt]
      build multi idx assign stmts [] _ _ tail_stmts = tail_stmts
      build multi idx assign stmts ((EIndexAssign tk idxs _):ts) tmp_name idx tail_stmts =
        [StmtIndexAssign tk idxs (EIndex (EVar tmp_name) [EInt idx])] :: (build multi idx assign stmts ts tmp_name (idx + 1) tail_stmts)
      build multi idx assign stmts (_:ts) tmp_name idx tail_stmts =
        build multi idx assign stmts ts tmp_name (idx + 1) tail_stmts

fn :: finish multi idx assign String [RExpr] (RExpr, [RToken]) => [RStmt] [RToken]
      finish multi idx assign t_name targets (rhs_e, after_rhs) =
        tmp_name = ":idx-tup-" + t_name + ":"
        more_res = parse_block_stmts_safe after_rhs
        finish multi idx assign more tmp_name targets rhs_e more_res

fn :: finish multi idx assign more String [RExpr] RExpr ([RStmt], [RToken]) => [RStmt] [RToken]
      finish multi idx assign more tmp_name targets rhs_e (more_stmts, rest) =
        ([StmtMut tmp_name rhs_e] :: (build multi idx assign stmts targets tmp_name 0 more_stmts), rest)

fn :: parse subscript col assign String String [RToken] (RExpr, [RToken]) => [RStmt] [RToken]
      parse subscript col assign t_name _ _ (col_e, (TokRParen:TokEquals:after_eq)) =
        val_res = parse_let_rhs after_eq
        finish slice set stmt ":tensor-set-col:" t_name col_e val_res
      parse subscript col assign _ raw_name orig_rest _ =
        finish_expr_stmt (parse_expr ([TokIdent raw_name, TokLParen] :: orig_rest))

fn :: finish slice set stmt String String RExpr (RExpr, [RToken]) => [RStmt] [RToken]
      finish slice set stmt helper t_name idx_e (val_e, after_rhs) =
        more = parse_block_stmts_safe after_rhs
        prepend_stmt (StmtExpr (ECall helper [EVar t_name, idx_e, val_e])) more

fn :: parse subscript assign after first String String [RToken] (RExpr, [RToken]) => [RStmt] [RToken]
      parse subscript assign after first t_name _ _ (idx1, (TokComma:TokRParen:TokEquals:after_eq)) =
        val_res = parse_let_rhs after_eq
        finish slice set stmt ":tensor-set-row:" t_name idx1 val_res
      parse subscript assign after first t_name raw_name orig_rest (idx1, (TokComma:more_ts)) =
        more_res = parse_comma_exprs more_ts
        parse subscript assign after idxs t_name raw_name orig_rest idx1 more_res
      parse subscript assign after first t_name _ _ (idx1, (TokRParen:TokEquals:after_eq)) =
        val_res = parse_let_rhs after_eq
        finish_idx_assign_stmt t_name [idx1] val_res
      parse subscript assign after first t_name raw_name orig_rest (idx1, (TokRParen:TokComma:more_lhs)) =
        multi_res = collect multi subscript lhs more_lhs [EIndexAssign t_name [idx1] EUnit]
        finish multi subscript lhs t_name raw_name orig_rest multi_res
      parse subscript assign after first _ raw_name orig_rest _ =
        finish_expr_stmt (parse_expr ([TokIdent raw_name, TokLParen] :: orig_rest))

fn :: parse subscript assign after idxs String String [RToken] RExpr ([RExpr], [RToken]) => [RStmt] [RToken]
      parse subscript assign after idxs t_name _ _ idx1 (more_idxs, (TokEquals:after_eq)) =
        val_res = parse_let_rhs after_eq
        finish_idx_assign_stmt t_name ([idx1] :: more_idxs) val_res
      parse subscript assign after idxs t_name raw_name orig_rest idx1 (more_idxs, (TokComma:more_lhs)) =
        multi_res = collect multi subscript lhs more_lhs [EIndexAssign t_name ([idx1] :: more_idxs) EUnit]
        finish multi subscript lhs t_name raw_name orig_rest multi_res
      parse subscript assign after idxs _ raw_name orig_rest _ _ =
        finish_expr_stmt (parse_expr ([TokIdent raw_name, TokLParen] :: orig_rest))

fn :: finish multi subscript lhs String String [RToken] (Bool, [RExpr], [RToken]) => [RStmt] [RToken]
      finish multi subscript lhs t_name _ _ (True, targets, after_eq) =
        finish multi idx assign t_name targets (parse_let_rhs after_eq)
      finish multi subscript lhs _ raw_name orig_rest (False, _, _) =
        finish_expr_stmt (parse_expr ([TokIdent raw_name, TokLParen] :: orig_rest))

fn :: parse subscript assign stmt String String [RToken] => [RStmt] [RToken]
      parse subscript assign stmt t_name raw_name (TokComma:after_c) =
        parse subscript col assign t_name raw_name ([TokComma] :: after_c) (parse_expr after_c)
      parse subscript assign stmt t_name raw_name ts =
        parse subscript assign after first t_name raw_name ts (parse_expr ts)

fn :: parse block line ident String [RToken] => [RStmt] [RToken]
      parse block line ident name (TokEquals:rest)
        | is_subscript_ident name =
          e_res = wrap subscript let rhs (parse_let_rhs rest)
          finish_mut_stmt (extract fst str (split_subscript name)) e_res
        | otherwise =
          e_res = parse_let_rhs rest
          finish_let_stmt name e_res
      parse block line ident name (TokComma:rest)
        | line_has_equals rest = parse tuple destructure stmt name (collect ident lhs list rest [name]) rest
      parse block line ident name (TokLParen:rest)
        | (is trailing underscore ident name) and (line_has_equals rest) =
          parse subscript assign stmt (str_slice name 0 ((str_len name) - 1)) name rest
      parse block line ident name (TokIdxLBracket:rest)
        | line_has_equals rest = parse_block_idx_assign name ([TokIdxLBracket] :: rest) (collect_bracket_indices ([TokIdxLBracket] :: rest) [])
      parse block line ident name rest
        | (line_has_equals rest) OR (line_has_fat_arrow rest) = ([], [TokIdent name] :: rest)
        | otherwise = finish_expr_stmt (parse_expr ([TokIdent name] :: rest))

fn :: parse block idx assign String [RToken] ([RExpr], [RToken]) => [RStmt] [RToken]
      parse block idx assign name _ (idxs, (TokEquals:rest)) =
        val_res = parse_expr rest
        finish_idx_assign_stmt name idxs val_res
      parse block idx assign name orig_rest _ =
        finish_expr_stmt (parse_expr ([TokIdent name] :: orig_rest))

fn :: finish idx assign stmt String [RExpr] (RExpr, [RToken]) => [RStmt] [RToken]
      finish idx assign stmt name idxs (val_e, rest) =
        more = parse_block_stmts_safe rest
        prepend_stmt (StmtIndexAssign name idxs val_e) more

fn :: finish let stmt String (RExpr, [RToken]) => [RStmt] [RToken]
      finish let stmt v      (e, rest)         =
        more = parse_block_stmts_safe rest
        prepend_stmt (StmtLet v e) more

fn :: finish mut stmt String (RExpr, [RToken]) => [RStmt] [RToken]
      finish mut stmt v      (e, rest)         =
        more = parse_block_stmts_safe rest
        prepend_stmt (StmtMut v e) more

fn :: finish dpipe stmt (RExpr, [RToken]) => [RStmt] [RToken]
      finish dpipe stmt (e, rest)         =  ([StmtExpr e], rest)

fn :: finish expr stmt (RExpr, [RToken]) => [RStmt] [RToken]
      finish expr stmt (e, rest)
        | (NOT (is_echo_expr e)) AND (next_line_has_guard rest) = ([StmtExpr e], rest)
        | otherwise = prepend_stmt (StmtExpr e) (parse_block_stmts_safe rest)

fn :: parse block stmts safe [RToken] => [RStmt] [RToken]
      parse block stmts safe ts       =
        clean = skip_newlines ts
        parse_block_safe_dispatch clean

fn :: parse block safe dispatch [RToken]          => [RStmt] [RToken]
      parse block safe dispatch []                =  ([], [])
      parse block safe dispatch (TokRParen:rest)  =  ([], [TokRParen] :: rest)
      parse block safe dispatch (TokPipe:rest)    =  ([], [TokPipe] :: rest)
      parse block safe dispatch (TokPipeDot:rest) =  ([], [TokPipeDot] :: rest)
      parse block safe dispatch (TokDoublePipeDot:rest) = ([], [TokDoublePipeDot] :: rest)
      parse block safe dispatch (TokDoublePipe:rest)
        | line_has_arrow rest = finish_dpipe_stmt (parse_case_body_dpipe ([TokDoublePipe] :: rest))
      parse block safe dispatch (TokMut:(TokIdent name):TokEquals:rest) =
        e_res = parse_let_rhs rest
        finish_mut_stmt name e_res
      parse block safe dispatch ((TokIdent name):rest)
        | is_top_decl_start ([TokIdent name] :: rest) = ([], [TokIdent name] :: rest)
        | otherwise = parse_block_line_ident name rest
      parse block safe dispatch (TokFn:rest)
        | is_top_decl_start ([TokFn] :: rest) = ([], [TokFn] :: rest)
        | otherwise = parse_block_line_ident "fn" rest
      parse block safe dispatch (TokOp:rest)
        | is_top_decl_start ([TokOp] :: rest) = ([], [TokOp] :: rest)
        | otherwise = parse_block_line_ident "op" rest
      parse block safe dispatch (TokType:rest)
        | is_top_decl_start ([TokType] :: rest) = ([], [TokType] :: rest)
        | otherwise = parse_block_line_ident "type" rest
      parse block safe dispatch (TokWith:rest)
        | is_with_block_start ([TokWith] :: rest) = finish_expr_stmt (parse_expr ([TokWith] :: rest))
        | otherwise = parse_block_line_ident "with" rest
      parse block safe dispatch ts
        | (is_top_decl_start ts) OR (line_has_fat_arrow ts) = ([], ts)
        | otherwise = finish_expr_stmt (parse_expr ts)

fn :: prepend stmt RStmt ([RStmt], [RToken]) => [RStmt] [RToken]
      prepend stmt s     (ss, rest)          =  ([s] :: ss, rest)

fn :: parse case body [RToken]          => RExpr [RToken]
      parse case body (TokNewline:rest) =
        clean = skip_newlines rest
        parse_case_body_newline rest clean
      parse case body (TokPipe:rest)    =
        finish_guard_expr (parse_guards ([TokPipe] :: rest))
      parse case body (TokDoublePipe:rest) =
        parse_case_body_dpipe ([TokDoublePipe] :: rest)
      parse case body ts                =
        e_res = parse_expr ts
        check_trailing_comma_and_where e_res

fn :: parse case body newline [RToken] [RToken] => RExpr [RToken]
      parse case body newline _ (TokPipe:rest) =
        finish_guard_expr (parse_guards ([TokPipe] :: rest))
      parse case body newline _ (TokDoublePipe:rest) =
        parse_case_body_dpipe ([TokDoublePipe] :: rest)
      parse case body newline orig_rest _ =
        stmts_res = parse_block_stmts_safe orig_rest
        finish_block_body stmts_res

fn :: finish block body ([RStmt], [RToken]) => RExpr [RToken]
      finish block body (stmts, rest)       =  (EBlock stmts, rest)

-- ── Top-Level Function, Operator, Scoped Global, Hardware & Type Decls ──

fn :: parse fn case for String [RToken] => RFnCase [RToken]
      parse fn case for _ (_:rest) =
        pats_res = parse_case_patterns rest
        parse_fn_case_after_pats pats_res
      parse fn case for _ [] = (FnCase [] [] EUnit, [])

fn :: parse fn case after pats ([RPattern], [RToken]) => RFnCase [RToken]
      parse fn case after pats (pats, (TokNewline:TokPipe:rest)) =
        g_res = parse_guards ([TokPipe] :: rest)
        finish_guarded_case pats g_res
      parse fn case after pats (pats, (TokEquals:rest)) =
        parse_fn_case_after_eq pats rest (skip_newlines rest)
      parse fn case after pats (pats, rest) = (FnCase pats [] EUnit, rest)

fn :: parse fn case after eq [RPattern] [RToken] [RToken] => RFnCase [RToken]
      parse fn case after eq pats _ (TokPipe:rest) =
        g_res = parse_guards ([TokPipe] :: rest)
        finish_guarded_case pats g_res
      parse fn case after eq pats orig_rest _ =
        b_res = parse_case_body orig_rest
        finish_body_case pats b_res

fn :: finish guarded case [RPattern] ([RGuard], [RToken]) => RFnCase [RToken]
      finish guarded case pats       (guards, rest)       =  (FnCase pats guards EUnit, rest)

fn :: finish body case [RPattern] (RExpr, [RToken]) => RFnCase [RToken]
      finish body case pats       (body, rest)      =  (FnCase pats [] body, rest)

fn :: parse fn cases String  [RToken] => [RFnCase] [RToken]
      parse fn cases fn_name ts       =
        clean = skip_newlines ts
        parse_fn_cases_check fn_name clean

fn :: parse fn cases check String [RToken] => [RFnCase] [RToken]
      parse fn cases check fn_name ((TokIdent s):rest)
        | s == fn_name = parse_fn_cases_cont fn_name (parse_fn_case_for fn_name ([TokIdent s] :: rest))
        | otherwise = ([], [TokIdent s] :: rest)
      parse fn cases check "fn" (TokFn:rest)
        | NOT (is_top_decl_start ([TokFn] :: rest)) =
          parse_fn_cases_cont "fn" (parse_fn_case_for "fn" ([TokIdent "fn"] :: rest))
      parse fn cases check "op" (TokOp:rest)
        | NOT (is_top_decl_start ([TokOp] :: rest)) =
          parse_fn_cases_cont "op" (parse_fn_case_for "op" ([TokIdent "op"] :: rest))
      parse fn cases check "type" (TokType:rest) =
        parse_fn_cases_cont "type" (parse_fn_case_for "type" ([TokIdent "type"] :: rest))
      parse fn cases check "with" (TokWith:rest) =
        parse_fn_cases_cont "with" (parse_fn_case_for "with" ([TokIdent "with"] :: rest))
      parse fn cases check _ ts = ([], ts)

fn :: parse fn cases cont String (RFnCase, [RToken]) => [RFnCase] [RToken]
      parse fn cases cont fn_name (c, rest) =
        more = parse_fn_cases fn_name rest
        prepend_case c more

fn :: prepend case RFnCase ([RFnCase], [RToken]) => [RFnCase] [RToken]
      prepend case c       (cs, rest)            =  ([c] :: cs, rest)

fn :: parse fn decl [RToken] => RFnDef [RToken]
      parse fn decl (TokFn:TokColonColon:rest) =
        parse_bare_decl rest
      parse fn decl (_:rest) =  (FnDef "unknown" [] "()" [], rest)
      parse fn decl []       =  (FnDef "unknown" [] "()" [], [])

fn :: parse fn decl ret String ([String], [RToken]) => RFnDef [RToken]
      parse fn decl ret name (params, (TokFatArrow:rest)) =
        rt_res = parse_return_types rest
        parse_fn_decl_cases name params rt_res
      parse fn decl ret name (params, (TokArrow:rest)) =
        rt_res = parse_return_types rest
        parse_fn_decl_cases name params rt_res
      parse fn decl ret name (params, rest) =
        parse_fn_decl_cases name params ("()", rest)

fn :: parse fn decl cases String [String] (String, [RToken]) => RFnDef [RToken]
      parse fn decl cases name params (ret_ty, rest) =
        cs_res = parse_fn_cases name rest
        finish_fn_def name params ret_ty cs_res

fn :: finish fn def String [String] String ([RFnCase], [RToken]) => RFnDef [RToken]
      finish fn def name params ret_ty (cases, rest) =
        (FnDef name params ret_ty cases, rest)

-- ── Custom Operators (`op :: ...`) ──────────────────────────

fn :: join words underscore [String] => String
      join words underscore []       =  "op"
      join words underscore (w:[])   =  w
      join words underscore (w:ws)   =  w + "_" + (join_words_underscore ws)

fn :: scan op header [RToken] [String] [String] [Bool] => [String] [String] [Bool] [RToken]
      scan op header (TokFatArrow:rest) words params tmpl = (words, params, tmpl, rest)
      scan op header (TokArrow:rest) words params tmpl = (words, params, tmpl, rest)
      scan op header (TokNewline:rest) words params tmpl = (words, params, tmpl, [TokNewline] :: rest)
      scan op header (TokEof:rest) words params tmpl = (words, params, tmpl, [TokEof] :: rest)
      scan op header [] words params tmpl = (words, params, tmpl, [])
      scan op header ((TokIdent s):rest) words params tmpl
        | is_upper_ident s = scan_op_type_slot words params tmpl (parse_type_tok ([TokIdent s] :: rest))
        | otherwise = scan_op_header rest (words :: [s]) params (tmpl :: [False])
      scan op header (TokFn:rest) words params tmpl =
        scan_op_header rest (words :: ["fn"]) params (tmpl :: [False])
      scan op header (TokOp:rest) words params tmpl =
        scan_op_header rest (words :: ["op"]) params (tmpl :: [False])
      scan op header (TokImport:rest) words params tmpl =
        scan_op_header rest (words :: ["import"]) params (tmpl :: [False])
      scan op header (TokDo:rest) words params tmpl =
        scan_op_header rest (words :: ["do"]) params (tmpl :: [False])
      scan op header (TokHardware:rest) words params tmpl =
        scan_op_header rest (words :: ["hardware"]) params (tmpl :: [False])
      scan op header (TokOtherwise:rest) words params tmpl =
        scan_op_header rest (words :: ["otherwise"]) params (tmpl :: [False])
      scan op header (TokMut:rest) words params tmpl =
        scan_op_header rest (words :: ["mut"]) params (tmpl :: [False])
      scan op header (TokType:rest) words params tmpl =
        scan_op_header rest (words :: ["type"]) params (tmpl :: [False])
      scan op header (TokWith:rest) words params tmpl =
        scan_op_header rest (words :: ["with"]) params (tmpl :: [False])
      scan op header (TokAnd:rest) words params tmpl =
        scan_op_header rest (words :: ["and"]) params (tmpl :: [False])
      scan op header (TokOr:rest) words params tmpl =
        scan_op_header rest (words :: ["or"]) params (tmpl :: [False])
      scan op header (TokXor:rest) words params tmpl =
        scan_op_header rest (words :: ["xor"]) params (tmpl :: [False])
      scan op header (TokNot:rest) words params tmpl =
        scan_op_header rest (words :: ["not"]) params (tmpl :: [False])
      scan op header (TokPlus:rest) words params tmpl =
        scan_op_header rest (words :: ["+"]) params (tmpl :: [False])
      scan op header (TokMinus:rest) words params tmpl =
        scan_op_header rest (words :: ["-"]) params (tmpl :: [False])
      scan op header (TokStar:rest) words params tmpl =
        scan_op_header rest (words :: ["*"]) params (tmpl :: [False])
      scan op header (TokSlash:rest) words params tmpl =
        scan_op_header rest (words :: ["/"]) params (tmpl :: [False])
      scan op header (TokPercent:rest) words params tmpl =
        scan_op_header rest (words :: ["%"]) params (tmpl :: [False])
      scan op header (TokLParen:rest) words params tmpl =
        scan_op_type_slot words params tmpl (parse_type_tok ([TokLParen] :: rest))
      scan op header (TokLBracket:rest) words params tmpl =
        scan_op_type_slot words params tmpl (parse_type_tok ([TokLBracket] :: rest))
      scan op header (_:rest) words params tmpl =
        scan_op_header rest words params tmpl

fn :: scan op type slot [String] [String] [Bool] (String, [RToken]) => [String] [String] [Bool] [RToken]
      scan op type slot words params tmpl (ty_str, rest) =
        scan_op_header rest words (params :: [ty_str]) (tmpl :: [True])

fn :: match op keyword RToken       String => Bool
      match op keyword (TokIdent s) kw     =  s == kw
      match op keyword TokFn        kw     =  kw == "fn"
      match op keyword TokOp        kw     =  kw == "op"
      match op keyword TokImport    kw     =  kw == "import"
      match op keyword TokDo        kw     =  kw == "do"
      match op keyword TokHardware  kw     =  kw == "hardware"
      match op keyword TokOtherwise kw     =  kw == "otherwise"
      match op keyword TokMut       kw     =  kw == "mut"
      match op keyword TokType      kw     =  kw == "type"
      match op keyword TokWith      kw     =  kw == "with"
      match op keyword TokAnd       kw     =  kw == "and"
      match op keyword TokOr        kw     =  kw == "or"
      match op keyword TokXor       kw     =  kw == "xor"
      match op keyword TokNot       kw     =  kw == "not"
      match op keyword TokPlus      kw     =  kw == "+"
      match op keyword TokMinus     kw     =  kw == "-"
      match op keyword TokStar      kw     =  kw == "*"
      match op keyword TokSlash     kw     =  kw == "/"
      match op keyword TokPercent   kw     =  kw == "%"
      match op keyword _            _      =  False

fn :: try parse op template [Bool] [String] [RToken] [RPattern] => Bool [RPattern] [RToken]
      try parse op template [] _ ts pats = (True, pats, ts)
      try parse op template (True:_) [] (TokEquals:rest) pats = (True, pats, [TokEquals] :: rest)
      try parse op template (True:_) [] (TokNewline:TokPipe:rest) pats = (True, pats, [TokNewline, TokPipe] :: rest)
      try parse op template (True:t_rest) (kw:kw_rest) (tok:ts_rest) pats
        | (pat_list_count pats) > 0 AND (tok_head ts_rest) != TokColonColon AND (match_op_keyword tok kw) =
          try_parse_op_template (skip_true_slots t_rest) kw_rest ts_rest pats
      try parse op template (True:t_rest) kws ts pats
        | is_top_decl_start ts = (False, [], ts)
        | otherwise = try_parse_op_pat t_rest kws pats (parse_pattern ts)
      try parse op template (False:t_rest) (kw:kw_rest) (tok:ts_rest) pats
        | (tok_head ts_rest) != TokColonColon AND (match_op_keyword tok kw) = try_parse_op_template t_rest kw_rest ts_rest pats
        | otherwise = (False, [], [tok] :: ts_rest)
      try parse op template _ _ ts _ = (False, [], ts)

fn :: skip true slots [Bool]        => [Bool]
      skip true slots (True:t_rest) =  skip_true_slots t_rest
      skip true slots other         =  other

fn :: try parse op pat [Bool] [String] [RPattern] (RPattern, [RToken]) => Bool [RPattern] [RToken]
      try parse op pat t_rest kws pats ((PatSeqBind v), rest) =
        try_parse_op_template (skip_true_slots t_rest) kws rest (pats :: [PatSeqBind v])
      try parse op pat t_rest kws pats (pat, rest) =
        try_parse_op_template t_rest kws rest (pats :: [pat])

fn :: parse op cases [Bool] [String] [RToken] => [RFnCase] [RToken]
      parse op cases tmpl kws ts =
        clean = skip_newlines ts
        parse_op_cases_step tmpl kws clean (try_parse_op_template tmpl kws clean [])

fn :: parse op cases step [Bool] [String] [RToken] (Bool, [RPattern], [RToken]) => [RFnCase] [RToken]
      parse op cases step _ _ orig_ts (False, _, _) = ([], orig_ts)
      parse op cases step tmpl kws _ (True, pats, after_pats) =
        c_res = parse_fn_case_after_pats (pats, after_pats)
        parse_op_cases_cont tmpl kws c_res

fn :: parse op cases cont [Bool] [String] (RFnCase, [RToken]) => [RFnCase] [RToken]
      parse op cases cont tmpl kws (c, rest) =
        more = parse_op_cases tmpl kws rest
        prepend_case c more

fn :: parse op decl [RToken] => RFnDef [RToken]
      parse op decl (TokOp:TokColonColon:rest) =
        hdr = scan_op_header rest [] [] []
        finish_op_header hdr
      parse op decl ts       =
        hdr = scan_op_header ts [] [] []
        finish_op_header hdr

fn :: is prefix fn tmpl [Bool] [String] => Bool
      is prefix fn tmpl (False:_) (w:[]) = is_lower_ident w
      is prefix fn tmpl _ _ = False

fn :: parse bare decl [RToken] => RFnDef [RToken]
      parse bare decl ts       =
        hdr = scan_op_header ts [] [] []
        dispatch_bare_decl ts hdr

fn :: dispatch bare decl [RToken] ([String], [String], [Bool], [RToken]) => RFnDef [RToken]
      dispatch bare decl ((TokIdent name):rest) (words, _, tmpl, _)
        | is_prefix_fn_tmpl tmpl words = parse_fn_decl_ret name (parse_param_types rest)
      dispatch bare decl (TokFn:rest) (words, _, tmpl, _)
        | is_prefix_fn_tmpl tmpl words = parse_fn_decl_ret "fn" (parse_param_types rest)
      dispatch bare decl (TokOp:rest) (words, _, tmpl, _)
        | is_prefix_fn_tmpl tmpl words = parse_fn_decl_ret "op" (parse_param_types rest)
      dispatch bare decl (TokType:rest) (words, _, tmpl, _)
        | is_prefix_fn_tmpl tmpl words = parse_fn_decl_ret "type" (parse_param_types rest)
      dispatch bare decl (TokWith:rest) (words, _, tmpl, _)
        | is_prefix_fn_tmpl tmpl words = parse_fn_decl_ret "with" (parse_param_types rest)
      dispatch bare decl _ hdr =
        finish_op_header hdr

fn :: finish op header ([String], [String], [Bool], [RToken]) => RFnDef [RToken]
      finish op header (words, params, tmpl, rest)            =
        mangled = join_words_underscore words
        rt_res = parse_return_types rest
        finish_op_decl mangled words params tmpl rt_res

fn :: finish op decl String [String] [String] [Bool] (String, [RToken]) => RFnDef [RToken]
      finish op decl mangled words params tmpl (ret_ty, rest) =
        cs_res = parse_op_cases tmpl words rest
        finish_fn_def mangled params ret_ty cs_res

-- ── Hardware MMIO Blocks (`hardware :: Name @ 0x...`) ───────

fn :: parse hw registers Int       [RToken] => [RFnDef] [RToken]
      parse hw registers base_addr ts       =
        clean = skip_newlines ts
        parse_hw_reg_step base_addr ts clean

fn :: parse hw reg step Int [RToken] [RToken] => [RFnDef] [RToken]
      parse hw reg step base_addr _ ((TokIdent reg_name):TokColon:rest) =
        ty_res = parse_type_tok rest
        parse_hw_reg_offset base_addr reg_name ty_res
      parse hw reg step _ orig_ts _ = ([], orig_ts)

fn :: parse hw reg offset Int String (String, [RToken]) => [RFnDef] [RToken]
      parse hw reg offset base_addr reg_name (_, (TokAt:(TokInt offset):rest)) =
        reg_fn = FnDef reg_name [] "Int" [FnCase [] [] (EInt (base_addr + offset))]
        more = parse_hw_registers base_addr rest
        prepend_fndef reg_fn more
      parse hw reg offset base_addr _ (_, rest) =
        parse_hw_registers base_addr (skip_to_newline rest)

fn :: prepend fndef RFnDef ([RFnDef], [RToken]) => [RFnDef] [RToken]
      prepend fndef f      (fs, rest)           =  ([f] :: fs, rest)

fn :: parse hardware decl [RToken] => [RFnDef] [RToken]
      parse hardware decl (TokHardware:TokColonColon:(TokIdent hw_name):TokAt:(TokInt base_addr):rest) =
        hw_fn = FnDef hw_name [] "Int" [FnCase [] [] (EInt base_addr)]
        regs_res = parse_hw_registers base_addr rest
        prepend_fndef hw_fn regs_res
      parse hardware decl (_:rest) =  ([], skip_to_newline rest)
      parse hardware decl []       =  ([], [])

-- ── Type Declarations (Sum Variants & Product Record Fields) ─

fn :: parse variants [RToken]          => [RVariant] [RToken]
      parse variants (TokNewline:rest) =  ([], rest)
      parse variants (TokEof:rest)     =  ([], [TokEof] :: rest)
      parse variants []                =  ([], [])
      parse variants (TokPipe:rest)    =  parse_variants rest
      parse variants ((TokIdent ctor):rest) =
        args_res = parse_variant_args rest
        parse_variants_cont ctor args_res
      parse variants (_:rest)          =  ([], skip_to_newline rest)

fn :: parse variant args [RToken]          => [String] [RToken]
      parse variant args (TokPipe:rest)    =  ([], [TokPipe] :: rest)
      parse variant args (TokNewline:rest) =  ([], [TokNewline] :: rest)
      parse variant args (TokEof:rest)     =  ([], [TokEof] :: rest)
      parse variant args []                =  ([], [])
      parse variant args ts                =
        t1 = parse_type_tok ts
        parse_variant_args_cont t1

fn :: parse variant args cont (String, [RToken]) => [String] [RToken]
      parse variant args cont (ty, rest)         =
        more = parse_variant_args rest
        prepend_str ty more

fn :: is prim type ctor String   => Bool
      is prim type ctor "Int"    =  True
      is prim type ctor "U8"     =  True
      is prim type ctor "U16"    =  True
      is prim type ctor "U32"    =  True
      is prim type ctor "U64"    =  True
      is prim type ctor "I8"     =  True
      is prim type ctor "I16"    =  True
      is prim type ctor "I32"    =  True
      is prim type ctor "I64"    =  True
      is prim type ctor "Usize"  =  True
      is prim type ctor "Real"   =  True
      is prim type ctor "Float"  =  True
      is prim type ctor "String" =  True
      is prim type ctor "Char"   =  True
      is prim type ctor "Bool"   =  True
      is prim type ctor _        =  False

fn :: norm variant args String [String] => [String]
      norm variant args ctor   []
        | is_prim_type_ctor ctor = [ctor]
        | otherwise = []
      norm variant args _      args     =  args

fn :: parse variants cont String ([String], [RToken]) => [RVariant] [RToken]
      parse variants cont ctor   (args, rest)         =
        more = parse_variants rest
        prepend_variant (TypeVariant ctor (norm_variant_args ctor args)) more

fn :: prepend variant RVariant ([RVariant], [RToken]) => [RVariant] [RToken]
      prepend variant v        (vs, rest)             =  ([v] :: vs, rest)

fn :: strip optional colon [RToken]        => [RToken]
      strip optional colon (TokColon:rest) =  rest
      strip optional colon ts              =  ts

fn :: parse field type more (String, [RToken]) Bool => String [RToken]
      parse field type more (acc, ((TokIdent s):rest)) is_app
        | (is_upper_ident s) AND (tok_head rest) != TokColon =
          t2 = parse_type_tok ([TokIdent s] :: rest)
          parse_field_type_step acc t2
        | otherwise = finish_return_types acc ([TokIdent s] :: rest) is_app
      parse field type more (acc, (TokLBracket:rest)) _ =
        t2 = parse_type_tok ([TokLBracket] :: rest)
        parse_field_type_step acc t2
      parse field type more (acc, (TokLParen:rest)) _ =
        t2 = parse_type_tok ([TokLParen] :: rest)
        parse_field_type_step acc t2
      parse field type more (acc, rest) is_app = finish_return_types acc rest is_app

fn :: parse field type step String (String, [RToken]) => String [RToken]
      parse field type step acc (next_ty, rest) =
        parse_field_type_more (acc + ", " + next_ty, rest) True

fn :: parse field type tok [RToken] => String [RToken]
      parse field type tok ts =
        parse_field_type_more (parse_type_tok ts) False

fn :: parse record fields [RToken]          => [RField] [RToken]
      parse record fields (TokNewline:(TokIdent fname):TokColon:rest) =
        ty_res = parse_field_type_tok rest
        parse_record_fields_cont fname ty_res
      parse record fields (TokNewline:TokType:TokColon:rest) =
        ty_res = parse_field_type_tok rest
        parse_record_fields_cont "type" ty_res
      parse record fields (TokNewline:TokWith:TokColon:rest) =
        ty_res = parse_field_type_tok rest
        parse_record_fields_cont "with" ty_res
      parse record fields (TokNewline:rest) =  ([], rest)
      parse record fields (TokEof:rest)     =  ([], [TokEof] :: rest)
      parse record fields []                =  ([], [])
      parse record fields (TokComma:rest)   =  parse_record_fields rest
      parse record fields ((TokIdent fname):rest) =
        ty_res = parse_field_type_tok (strip_optional_colon rest)
        parse_record_fields_cont fname ty_res
      parse record fields (TokType:rest)    =
        ty_res = parse_field_type_tok (strip_optional_colon rest)
        parse_record_fields_cont "type" ty_res
      parse record fields (TokWith:rest)    =
        ty_res = parse_field_type_tok (strip_optional_colon rest)
        parse_record_fields_cont "with" ty_res
      parse record fields (_:rest)          =  ([], skip_to_newline rest)

fn :: parse record fields cont String (String, [RToken]) => [RField] [RToken]
      parse record fields cont fname (fty, rest) =
        more = parse_record_fields rest
        prepend_field (TypeField fname fty) more

fn :: prepend field RField ([RField], [RToken]) => [RField] [RToken]
      prepend field f      (fs, rest)           =  ([f] :: fs, rest)

fn :: collect type decl params [RToken] [String] => [String] [RToken]
      collect type decl params (TokEquals:rest) acc = (acc, [TokEquals] :: rest)
      collect type decl params ((TokIdent p):rest) acc
        | is_upper_ident p = collect_type_decl_params rest (acc :: [p])
      collect type decl params ts acc = (acc, ts)

fn :: subst one tparam str String String String => String
      subst one tparam str ty_s tp letter
        | ty_s == tp = letter
        | ty_s == ("[" + tp + "]") = "[" + letter + "]"
        | otherwise = ty_s

fn :: subst tparams in str String [String] Int => String
      subst tparams in str ty_s [] _ = ty_s
      subst tparams in str ty_s (tp:tps) idx
        | (str_len tp) == 1 = subst_tparams_in_str ty_s tps (idx + 1)
        | otherwise = subst_tparams_in_str (subst_one_tparam_str ty_s tp (char_from_code (65 + idx))) tps (idx + 1)

fn :: subst tparams in strs [String] [String] => [String]
      subst tparams in strs [] _ = []
      subst tparams in strs (s:ss) tps = [subst_tparams_in_str s tps 0] :: (subst_tparams_in_strs ss tps)

fn :: subst tparams in variants [RVariant] [String] => [RVariant]
      subst tparams in variants [] _ = []
      subst tparams in variants ((TypeVariant c args):vs) tps =
        [TypeVariant c (subst_tparams_in_strs args tps)] :: (subst_tparams_in_variants vs tps)

fn :: subst tparams in fields [RField] [String] => [RField]
      subst tparams in fields [] _ = []
      subst tparams in fields ((TypeField fnm fty):fs) tps =
        [TypeField fnm (subst_tparams_in_str fty tps 0)] :: (subst_tparams_in_fields fs tps)

fn :: apply tparams to tdef [String] (RTypeDef, [RToken]) => RTypeDef [RToken]
      apply tparams to tdef [] res = res
      apply tparams to tdef tps ((TypeDef nm vs fs), rest) =
        (TypeDef nm (subst_tparams_in_variants vs tps) (subst_tparams_in_fields fs tps), rest)

fn :: parse type decl after params String ([String], [RToken]) => RTypeDef [RToken]
      parse type decl after params name (tps, (TokEquals:TokNewline:rest)) =
        parse_type_decl_after_params name (tps, [TokEquals] :: (skip_newlines rest))
      parse type decl after params name (tps, (TokEquals:(TokIdent first_w):rest))
        | is_upper_ident first_w = apply_tparams_to_tdef tps (finish_sum_type name (parse_variants ([TokIdent first_w] :: rest)))
        | otherwise = apply_tparams_to_tdef tps (finish_record_type name (parse_record_fields ([TokIdent first_w] :: rest)))
      parse type decl after params name (tps, (TokEquals:TokType:rest)) =
        apply_tparams_to_tdef tps (finish_record_type name (parse_record_fields ([TokType] :: rest)))
      parse type decl after params name (tps, (TokEquals:TokWith:rest)) =
        apply_tparams_to_tdef tps (finish_record_type name (parse_record_fields ([TokWith] :: rest)))
      parse type decl after params _ (_, rest) = (TypeDef "Unknown" [] [], skip_to_newline rest)

fn :: parse type decl [RToken] => RTypeDef [RToken]
      parse type decl (TokType:(TokIdent name):rest) =
        parse_type_decl_after_params name (collect_type_decl_params rest [])
      parse type decl (_:rest) =  (TypeDef "Unknown" [] [], skip_to_newline rest)
      parse type decl []       =  (TypeDef "Unknown" [] [], [])

fn :: finish sum type String ([RVariant], [RToken]) => RTypeDef [RToken]
      finish sum type name   (vars, rest)           =  (TypeDef name vars [], rest)

fn :: finish record type String ([RField], [RToken]) => RTypeDef [RToken]
      finish record type name   (flds, rest)         =  (TypeDef name [] flds, rest)

-- ── Post-Parse Normalization (echo folding, mixfix, postfix ops) ──

type RArityEntry = ArityEntry String Int

fn :: lookup var arity [RArityEntry] String => Int
      lookup var arity []            _      =  -1
      lookup var arity ((ArityEntry k v):rest) target
        | k == target AND v == -2 = -1
        | k == target = v
        | otherwise = lookup_var_arity rest target

fn :: lookup arity [RArityEntry] String => Int
      lookup arity []            _      =  -1
      lookup arity ((ArityEntry k v):rest) target
        | v >= 0 AND k == target = v
        | otherwise = lookup_arity rest target

fn :: has arity prefix loop [RArityEntry] String String => Bool
      has arity prefix loop [] _ _ = False
      has arity prefix loop ((ArityEntry k v):rest) pref pref_under
        | v >= 0 AND (k == pref OR (str_starts_with k pref_under)) = True
        | otherwise = has_arity_prefix_loop rest pref pref_under

fn :: has arity prefix [RArityEntry] String => Bool
      has arity prefix arities       pref   =
        has_arity_prefix_loop arities pref (pref + "_")

fn :: filter arity prefix [RArityEntry] String String => [RArityEntry]
      filter arity prefix [] _ _ = []
      filter arity prefix ((ArityEntry k v):rest) pref pref_under
        | v >= 0 AND (k == pref OR (str_starts_with k pref_under)) = [ArityEntry k v] :: (filter_arity_prefix rest pref pref_under)
        | otherwise = filter_arity_prefix rest pref pref_under

fn :: has variadic param [String] => Bool
      has variadic param []       =  False
      has variadic param (p:ps)
        | str_contains p "..." = True
        | otherwise = has_variadic_param ps

fn :: fn def arity [String] => Int
fn def arity params
| has_variadic_param params = 999
        | otherwise = str_list_count params

fn :: arity matches Int Int    => Bool
      arity matches 999 actual =  actual >= 1
      arity matches ar  actual =  ar >= 0 AND ar == actual

fn :: builtin arity entries => [RArityEntry]
      builtin arity entries =
        [ArityEntry "assert_equals" 2, ArityEntry "assert_true" 1, ArityEntry "send_to" 2, ArityEntry "ask_to" 2, ArityEntry "send_through" 2, ArityEntry "receive_from" 1, ArityEntry "try_receive_from" 1, ArityEntry "receive_from_timeout" 2, ArityEntry "stop" 1, ArityEntry "agent_alive" 1, ArityEntry "new_mailbox" 0, ArityEntry "new_channel" 0, ArityEntry "new_bounded_channel" 1, ArityEntry "chan_send" 2, ArityEntry "chan_recv" 1, ArityEntry "chan_try_recv" 1, ArityEntry "str_len" 1, ArityEntry "str_char_at" 2, ArityEntry "str_slice" 3, ArityEntry "str_contains" 2, ArityEntry "str_starts_with" 2, ArityEntry "str_concat" 2, ArityEntry "int_to_str" 1, ArityEntry "str_to_int" 1, ArityEntry "char_from_code" 1, ArityEntry "trim_str" 1, ArityEntry "read_file" 1, ArityEntry "load_rg_source" 1, ArityEntry "read_bytes" 1, ArityEntry "write_bytes" 2, ArityEntry "write_file" 2, ArityEntry "shell_exec" 1, ArityEntry "list_str_len" 1, ArityEntry "list_dir" 1, ArityEntry "file_lstat" 1, ArityEntry "sha256_file" 1, ArityEntry "sha256_str" 1, ArityEntry "sha256_raw" 1, ArityEntry "sha256_bytes" 1, ArityEntry "sys_os" 0, ArityEntry "sys_arch" 0, ArityEntry "sys_mkdir" 2, ArityEntry "sys_chmod" 2, ArityEntry "sys_exec" 3, ArityEntry "sys_chdir" 1, ArityEntry "sys_getcwd" 0, ArityEntry "sys_getenv" 1, ArityEntry "sys_setenv" 2, ArityEntry "sys_exit" 1, ArityEntry "sys_getuid" 0, ArityEntry "sys_getgid" 0, ArityEntry "sys_getpid" 0, ArityEntry "sys_time_ms" 0, ArityEntry "sys_deadline_ms" 0, ArityEntry "sys_remaining_ms" 0, ArityEntry "sys_sleep_ms" 1, ArityEntry "sys_open_mode" 2, ArityEntry "sys_open" 3, ArityEntry "sys_close" 1, ArityEntry "sys_read_fd" 2, ArityEntry "sys_write_fd" 2, ArityEntry "sys_poll" 3, ArityEntry "sys_terminate" 2, ArityEntry "sys_kill" 2, ArityEntry "sys_call" 7, ArityEntry "sys_pipe" 0, ArityEntry "sys_waitpid" 2, ArityEntry "sys_username" 1, ArityEntry "sys_user_groups" 1, ArityEntry "sys_lookup_uid_gid" 1, ArityEntry "sys_setresgid" 1, ArityEntry "sys_setgroups" 1, ArityEntry "sys_setresuid" 1, ArityEntry "sys_execve" 3, ArityEntry "sys_read_pass" 1, ArityEntry "cli_args" 0, ArityEntry "cmm_live_blocks" 0, ArityEntry "cmm_cond_spared" 0, ArityEntry "cmm_cond_freed" 0, ArityEntry "cmm_same_ptr" 2, ArityEntry "seq_map" 2, ArityEntry "par_map" 2, ArityEntry "seq_filter" 2, ArityEntry "par_filter" 2]

fn :: collect fn arities acc [RFnDef] [RArityEntry] => [RArityEntry]
      collect fn arities acc []       acc           =  acc :: builtin_arity_entries
      collect fn arities acc ((FnDef name params _ _):fs) acc =
        collect_fn_arities_acc fs (acc :: [ArityEntry name (fn_def_arity params)])

fn :: collect fn arities [RFnDef] => [RArityEntry]
      collect fn arities fns      =  collect_fn_arities_acc fns []

fn :: field list count [RField] => Int
      field list count []       =  0
      field list count (_:fs)   =  1 + (field_list_count fs)

fn :: collect variant arities String [RVariant] => [RArityEntry]
      collect variant arities _         []         =  []
      collect variant arities tdef_name ((TypeVariant _ []):vs) =
        collect_variant_arities tdef_name vs
      collect variant arities tdef_name ((TypeVariant ctor args):vs) =
        n = str_list_count args
        [ArityEntry ctor n, ArityEntry (tdef_name + "." + ctor) n] :: (collect_variant_arities tdef_name vs)

fn :: collect field arities [RField] => [RArityEntry]
      collect field arities []       =  []
      collect field arities ((TypeField fname _):fs)
        | str_contains fname "." = [ArityEntry fname 1, ArityEntry (ident_base_name fname) 1] :: (collect_field_arities fs)
        | otherwise = [ArityEntry fname 1] :: (collect_field_arities fs)

fn :: collect type arities [RTypeDef] => [RArityEntry]
      collect type arities []         =  []
      collect type arities ((TypeDef name vars []):ts) =
        (collect_variant_arities name vars) :: (collect_type_arities ts)
      collect type arities ((TypeDef name vars fields):ts) =
        [ArityEntry name (field_list_count fields)] :: (collect_variant_arities name vars) :: (collect_field_arities fields) :: (collect_type_arities ts)

fn :: str list count [String] => Int
      str list count []       =  0
      str list count (_:xs)   =  1 + (str_list_count xs)

fn :: take exprs [RExpr] Int => [RExpr]
      take exprs _       0   =  []
      take exprs []      _   =  []
      take exprs (x:xs)  n   =  [x] :: (take_exprs xs (n - 1))

fn :: drop exprs [RExpr] Int => [RExpr]
      drop exprs xs      0   =  xs
      drop exprs []      _   =  []
      drop exprs (_:xs)  n   =  drop_exprs xs (n - 1)

fn :: fold echo args [RExpr]  [RArityEntry] => [RExpr]
      fold echo args []       _             =  []
      fold echo args ((EVar fn_name):rest) arities =
        ar = lookup_arity arities fn_name
        fold_echo_var fn_name ar rest arities
      fold echo args (e:rest) arities       =
        [norm_expr e arities] :: (fold_echo_args rest arities)

fn :: fold echo var String Int [RExpr] [RArityEntry] => [RExpr]
      fold echo var fn_name ar rest arities
        | ar > 0 AND (expr_list_count rest) >= ar = [ECall fn_name (norm_expr_list (take_exprs rest ar) arities)] :: (fold_echo_args (drop_exprs rest ar) arities)
        | ar == 0 = [ECall fn_name []] :: (fold_echo_args rest arities)
        | otherwise = [EVar fn_name] :: (fold_echo_args rest arities)

fn :: expr list count [RExpr] => Int
      expr list count []      =  0
      expr list count (_:xs)  =  1 + (expr_list_count xs)

fn :: join op word String String => String
      join op word ""     w      =  w
      join op word cur    w      =  cur + "_" + w

fn :: can complete op [RArityEntry] String [RExpr] => Bool
      can complete op arities cand [] = (lookup_arity arities cand) >= 0
      can complete op arities cand ((EVar w):rest)
        | (lookup_arity arities cand) >= 0 = True
        | has_arity_prefix arities (join_op_word cand w) = can_complete_op arities (join_op_word cand w) rest
        | otherwise = can_complete_op arities cand rest
      can complete op arities cand (_:rest)
        | (lookup_arity arities cand) >= 0 = True
        | otherwise = can_complete_op arities cand rest

fn :: extract mixfix start String [RExpr] [RArityEntry] [RArityEntry] [RExpr] => String [RExpr]
      extract mixfix start w rest arities w_cands operands
        | (NOT ((is_std_builtin w) AND (expr_list_count operands) > 0)) AND (has_arity_prefix w_cands w) AND (can_complete_op w_cands w rest) = extract_mixfix_call w rest w_cands operands
        | otherwise = extract_mixfix_call "" rest arities (operands :: [EVar w])

fn :: extract mixfix call String [RExpr] [RArityEntry] [RExpr] => String [RExpr]
      extract mixfix call cur_name [] _ operands = (cur_name, operands)
      extract mixfix call "" ((EVar w):rest) arities operands =
        w_cands = filter_arity_prefix arities w (w + "_")
        extract_mixfix_start w rest arities w_cands operands
      extract mixfix call cur_name ((EVar w):rest) arities operands
        | (NOT ((is_std_builtin cur_name) AND (expr_list_count operands) > 0)) AND (has_arity_prefix arities (join_op_word cur_name w)) AND (can_complete_op arities (join_op_word cur_name w) rest) = extract_mixfix_call (join_op_word cur_name w) rest arities operands
        | otherwise = extract_mixfix_call cur_name rest arities (operands :: [EVar w])
      extract mixfix call cur_name (arg:rest) arities operands =
        extract_mixfix_call cur_name rest arities (operands :: [arg])

fn :: reduce postfix spine [RExpr] [RArityEntry] [RExpr] => [RExpr]
      reduce postfix spine [] _ stack = stack
      reduce postfix spine ((EVar w):rest) arities stack
        | (lookup_arity arities w) > 0 AND (expr_list_count stack) > 0 = reduce_postfix_spine rest arities [ECall w stack]
        | otherwise = reduce_postfix_spine rest arities (stack :: [EVar w])
      reduce postfix spine (item:rest) arities stack =
        reduce_postfix_spine rest arities (stack :: [item])

fn :: is std builtin String             => Bool
      is std builtin "str_len"          =  True
      is std builtin "str_char_at"      =  True
      is std builtin "str_slice"        =  True
      is std builtin "str_contains"     =  True
      is std builtin "str_starts_with"  =  True
      is std builtin "int_to_str"       =  True
      is std builtin "str_to_int"       =  True
      is std builtin "char_from_code"   =  True
      is std builtin "trim_str"         =  True
      is std builtin "read_file"        =  True
      is std builtin "load_rg_source"   =  True
      is std builtin "read_bytes"       =  True
      is std builtin "write_bytes"      =  True
      is std builtin "write_file"       =  True
      is std builtin "shell_exec"       =  True
      is std builtin "list_str_len"     =  True
      is std builtin "map"              =  True
      is std builtin "||map"            =  True
      is std builtin "filter"           =  True
      is std builtin "||filter"         =  True
      is std builtin "fold"             =  True
      is std builtin "list_dir"         =  True
      is std builtin "file_lstat"       =  True
      is std builtin "sha256_file"      =  True
      is std builtin "sha256_str"       =  True
      is std builtin "sha256_raw"       =  True
      is std builtin "sha256_bytes"     =  True
      is std builtin "sys_os"           =  True
      is std builtin "sys_arch"         =  True
      is std builtin "sys_mkdir"        =  True
      is std builtin "sys_chmod"        =  True
      is std builtin "sys_exec"         =  True
      is std builtin "sys_chdir"        =  True
      is std builtin "sys_getcwd"       =  True
      is std builtin "sys_getenv"       =  True
      is std builtin "sys_setenv"       =  True
      is std builtin "sys_exit"         =  True
      is std builtin "sys_getuid"       =  True
      is std builtin "sys_getgid"       =  True
      is std builtin "sys_getpid"       =  True
      is std builtin "sys_time_ms"      =  True
      is std builtin "sys_deadline_ms"  =  True
      is std builtin "sys_remaining_ms" =  True
      is std builtin "sys_sleep_ms"     =  True
      is std builtin "sys_open_mode"    =  True
      is std builtin "sys_open"         =  True
      is std builtin "sys_close"        =  True
      is std builtin "sys_read_fd"      =  True
      is std builtin "sys_write_fd"     =  True
      is std builtin "sys_poll"         =  True
      is std builtin "sys_terminate"    =  True
      is std builtin "sys_kill"         =  True
      is std builtin "sys_call"         =  True
      is std builtin "sys_pipe"         =  True
      is std builtin "sys_waitpid"      =  True
      is std builtin "sys_username"     =  True
      is std builtin "sys_user_groups"  =  True
      is std builtin "sys_lookup_uid_gid" = True
      is std builtin "sys_setresgid"    =  True
      is std builtin "sys_setgroups"    =  True
      is std builtin "sys_setresuid"    =  True
      is std builtin "sys_execve"       =  True
      is std builtin "sys_read_pass"    =  True
      is std builtin "__record_update__" = True
      is std builtin ":tensor-zeros:"   =  True
      is std builtin ":tensor-clone:"   =  True
      is std builtin ":tensor-row-slice:" = True
      is std builtin ":tensor-col-slice:" = True
      is std builtin ":tensor-set-row:" =  True
      is std builtin ":tensor-set-col:" =  True
      is std builtin ":tensor-map-rows:" = True
      is std builtin ":tensor-map-rows-in:" = True
      is std builtin ":tensor-map-cols:" = True
      is std builtin ":tensor-map-cols-in:" = True
      is std builtin ":tensor-map-elems:" = True
      is std builtin ":tensor-map-elems-in:" = True
      is std builtin _                  =  False

fn :: std builtin arity String     => Int
      std builtin arity "map"      =  2
      std builtin arity "||map"    =  2
      std builtin arity "filter"   =  2
      std builtin arity "||filter" =  2
      std builtin arity "fold"     =  3
      std builtin arity _          =  -1

fn :: collapse fn ref args [RExpr] [RArityEntry] => [RExpr]
      collapse fn ref args [] _ = []
      collapse fn ref args ((EVar w1):(EVar w2):(EVar w3):(EVar w4):rest) arities
        | (lookup_arity arities (w1 + "_" + w2 + "_" + w3 + "_" + w4)) >= 0 = [EVar (w1 + "_" + w2 + "_" + w3 + "_" + w4)] :: (collapse_fn_ref_args rest arities)
      collapse fn ref args ((EVar w1):(EVar w2):(EVar w3):rest) arities
        | (lookup_arity arities (w1 + "_" + w2 + "_" + w3)) >= 0 = [EVar (w1 + "_" + w2 + "_" + w3)] :: (collapse_fn_ref_args rest arities)
      collapse fn ref args ((EVar w1):(EVar w2):rest) arities
        | (lookup_arity arities (w1 + "_" + w2)) >= 0 = [EVar (w1 + "_" + w2)] :: (collapse_fn_ref_args rest arities)
      collapse fn ref args (e:rest) arities =
        [e] :: (collapse_fn_ref_args rest arities)

fn :: maybe collapse args [RExpr] Int [RArityEntry] => [RExpr]
      maybe collapse args args expected_ar arities
        | expected_ar >= 0 and (expr_list_count args) <= expected_ar = args
        | otherwise = collapse_fn_ref_args args arities

fn :: has longer arity prefix [RArityEntry] String [RExpr] => Bool
      has longer arity prefix arities fn_name ((EVar w):rest) =
        (has_arity_prefix arities (fn_name + "_" + w)) and (can_complete_op arities (fn_name + "_" + w) rest)
      has longer arity prefix _ _ _ = False

fn :: split send to args [RExpr] [RExpr] => Bool [RExpr] RExpr
      split send to args ((EVar "to"):target:[]) acc = (True, acc, target)
      split send to args (x:xs) acc = split_send_to_args xs (acc :: [x])
      split send to args [] _ = (False, [], EUnit)

fn :: pack send to msg [RExpr]     => RExpr
      pack send to msg (single:[]) =  single
      pack send to msg msgs        =  ETuple msgs

fn :: finish send to norm String [RExpr] [RArityEntry] (Bool, [RExpr], RExpr) => RExpr
      finish send to norm _ _ arities (True, msg_atoms, target) =
        normed_msgs = norm_expr_list (collapse_fn_ref_args msg_atoms arities) arities
        ECall "send_to" [pack_send_to_msg normed_msgs, norm_expr target arities]
      finish send to norm fn_name args arities (False, _, _) =
        norm_call_mixfix fn_name args arities (extract_mixfix_call "" ([EVar fn_name] :: args) arities [])

fn :: finish ask prefix [RExpr]            [RArityEntry] => RExpr
      finish ask prefix (target:msg_atoms) arities
        | (expr_list_count msg_atoms) > 0 =
          normed_msgs = norm_expr_list (collapse_fn_ref_args msg_atoms arities) arities
          ECall "ask_to" [pack_send_to_msg normed_msgs, norm_expr target arities]
      finish ask prefix args               arities       =
        ECall "ask" (norm_expr_list args arities)

fn :: finish ask norm String [RExpr] [RArityEntry] (Bool, [RExpr], RExpr) => RExpr
      finish ask norm _ _ arities (True, msg_atoms, target) =
        normed_msgs = norm_expr_list (collapse_fn_ref_args msg_atoms arities) arities
        ECall "ask_to" [pack_send_to_msg normed_msgs, norm_expr target arities]
      finish ask norm fn_name args arities (False, _, _)
        | (not (has_longer_arity_prefix arities fn_name args)) and (lookup_arity arities fn_name) < 0 =
          finish_ask_prefix args arities
        | otherwise =
          norm_call_mixfix fn_name args arities (extract_mixfix_call "" ([EVar fn_name] :: args) arities [])

fn :: norm map in target RExpr RExpr [RArityEntry] => RExpr
      norm map in target fn_e (ECall ":tensor-row-slice:" (base_e:_)) arities =
        ECall ":tensor-map-rows-in:" [fn_e, norm_expr base_e arities]
      norm map in target fn_e (ECall ":tensor-col-slice:" (base_e:_)) arities =
        ECall ":tensor-map-cols-in:" [fn_e, norm_expr base_e arities]
      norm map in target fn_e (EVar v) _
        | is_subscript_ident v = ECall ":tensor-map-elems-in:" [fn_e, EVar (extract fst str (split_subscript v))]
      norm map in target fn_e target_e arities =
        ECall ":tensor-map-elems-in:" [fn_e, norm_expr target_e arities]

fn :: norm map pure target String RExpr RExpr [RArityEntry] => RExpr
      norm map pure target _ fn_e (ECall ":tensor-row-slice:" (base_e:_)) arities =
        ECall ":tensor-map-rows:" [fn_e, norm_expr base_e arities]
      norm map pure target _ fn_e (ECall ":tensor-col-slice:" (base_e:_)) arities =
        ECall ":tensor-map-cols:" [fn_e, norm_expr base_e arities]
      norm map pure target _ fn_e (EVar v) _
        | is_subscript_ident v = ECall ":tensor-map-elems:" [fn_e, EVar (extract fst str (split_subscript v))]
      norm map pure target fn_name fn_e target_e arities =
        ECall fn_name [fn_e, norm_expr target_e arities]

fn :: norm map call String [RExpr] [RArityEntry] => RExpr
      norm map call _ (fn_arg:(EVar "in"):target_arg:[]) arities =
        norm map in target (norm_expr fn_arg arities) target_arg arities
      norm map call fn_name (fn_arg:target_arg:[]) arities =
        norm map pure target fn_name (norm_expr fn_arg arities) target_arg arities
      norm map call fn_name args arities =
        ECall fn_name (norm_expr_list args arities)

fn :: norm call with cands String [RExpr] [RArityEntry] [RArityEntry] Int => RExpr
      norm call with cands fn_name args arities cands ar
        | ar >= 0 and (not (has_longer_arity_prefix cands fn_name args)) = ECall fn_name (norm_expr_list (maybe_collapse_args args ar arities) arities)
        | (not (is_std_builtin fn_name)) and (has_arity_prefix cands fn_name) and (can_complete_op cands fn_name args) = norm_call_mixfix fn_name args arities (extract_mixfix_call fn_name args cands [])
        | otherwise = norm_call_mixfix fn_name args arities (extract_mixfix_call "" ([EVar fn_name] :: args) arities [])

fn :: norm call fast or cands String [RExpr] [RArityEntry] Int => RExpr
      norm call fast or cands fn_name args arities ar
        | ar >= 0 and (not (has_longer_arity_prefix arities fn_name args)) = ECall fn_name (norm_expr_list (maybe_collapse_args args ar arities) arities)
        | otherwise =
          cands = filter_arity_prefix arities fn_name (fn_name + "_")
          norm_call_with_cands fn_name args arities cands (lookup_arity cands fn_name)

fn :: norm call String  [RExpr] [RArityEntry] => RExpr
      norm call fn_name args    arities
        | fn_name == "__lambda__" = ECall "__lambda__" args
        | fn_name == "agent" and (not (has_longer_arity_prefix arities "agent" args)) = ECall "agent" (norm_expr_list (collapse_fn_ref_args args arities) arities)
        | fn_name == "send" = finish_send_to_norm fn_name args arities (split_send_to_args args [])
        | fn_name == "ask" = finish_ask_norm fn_name args arities (split_send_to_args args [])
        | (fn_name == "map" or fn_name == "||map") and (not (has_longer_arity_prefix arities fn_name args)) = norm map call fn_name (collapse_fn_ref_args args arities) arities
        | (is_std_builtin fn_name) and (not (has_longer_arity_prefix arities fn_name args)) = ECall fn_name (norm_expr_list (maybe_collapse_args args (std_builtin_arity fn_name) arities) arities)
        | fn_name == "__chain__" = norm_call_chain args arities (extract_mixfix_call "" args arities [])
        | otherwise = norm_call_fast_or_cands fn_name args arities (lookup_arity arities fn_name)

fn :: norm call chain [RExpr] [RArityEntry] (String, [RExpr]) => RExpr
      norm call chain orig_args arities (mangled, operands) =
        ar = lookup_arity arities mangled
        c_ops = maybe_collapse_args operands ar arities
        norm_call_chain_step orig_args arities mangled ar c_ops

fn :: norm call chain step [RExpr] [RArityEntry] String Int [RExpr] => RExpr
      norm call chain step orig_args arities mangled ar c_ops
        | arity_matches ar (expr_list_count c_ops) = ECall mangled (norm_expr_list c_ops arities)
        | ar > 0 and (expr_list_count c_ops) == 0 = EVar mangled
        | otherwise = norm_call_chain_fallback (norm_expr_list orig_args arities) arities mangled ar c_ops

fn :: norm call chain fallback [RExpr] [RArityEntry] String Int [RExpr] => RExpr
      norm call chain fallback normed arities mangled ar c_ops =
        finish_postfix_or_partial "__chain__" normed (reduce_postfix_spine normed arities []) mangled ar c_ops arities

fn :: norm call mixfix String [RExpr] [RArityEntry] (String, [RExpr]) => RExpr
      norm call mixfix orig_name orig_args arities (mangled, operands) =
        ar = lookup_arity arities mangled
        c_ops = maybe_collapse_args operands ar arities
        norm_call_mixfix_step orig_name orig_args arities mangled ar c_ops

fn :: norm call mixfix step String [RExpr] [RArityEntry] String Int [RExpr] => RExpr
      norm call mixfix step orig_name orig_args arities mangled ar c_ops
        | arity_matches ar (expr_list_count c_ops) = ECall mangled (norm_expr_list c_ops arities)
        | ar > 0 and (expr_list_count c_ops) == 0 = EVar mangled
        | otherwise = norm_call_mixfix_fallback orig_name (norm_expr_list orig_args arities) arities mangled ar c_ops

fn :: norm call mixfix fallback String [RExpr] [RArityEntry] String Int [RExpr] => RExpr
      norm call mixfix fallback orig_name normed arities mangled ar c_ops =
        finish_postfix_or_partial orig_name normed (reduce_postfix_spine ([EVar orig_name] :: normed) arities []) mangled ar c_ops arities

fn :: finish postfix or partial String [RExpr] [RExpr] String Int [RExpr] [RArityEntry] => RExpr
      finish postfix or partial _ _ ((ECall f a):[]) _ _ _ _ = ECall f a
      finish postfix or partial _ _ _ mangled ar c_ops arities
        | ar > 1 and (expr_list_count c_ops) > 0 and (expr_list_count c_ops) < ar =
          ECall mangled (norm_expr_list c_ops arities)
      finish postfix or partial orig_name normed_args _ _ _ _ _ =
        ECall orig_name normed_args

fn :: flatten mixfix rhs RExpr [RArityEntry] => [RExpr]
      flatten mixfix rhs (ECall "__chain__" args) _ = args
      flatten mixfix rhs (ECall r_name r_args) arities
        | ((lookup_arity arities r_name) < 0 and (not (is_std_builtin r_name))) or (has_longer_arity_prefix arities r_name r_args) = [EVar r_name] :: r_args
      flatten mixfix rhs other _             =  [other]

fn :: can absorb mixfix conj String [RExpr] String RExpr [RArityEntry] => Bool
      can absorb mixfix conj fn_name args conj_word r arities =
        full_args = [EVar fn_name] :: args :: [EVar conj_word] :: (flatten_mixfix_rhs r arities)
        full_res = extract_mixfix_call "" full_args arities []
        can_absorb_mixfix_verify conj_word arities full_res

fn :: can absorb mixfix verify String [RArityEntry] (String, [RExpr]) => Bool
      can absorb mixfix verify conj_word arities (full_mangled, full_ops) =
        ar = lookup_arity arities full_mangled
        c_ops = maybe_collapse_args full_ops ar arities
        (str_contains full_mangled ("_" + conj_word)) and (arity_matches ar (expr_list_count c_ops))

fn :: norm expr RExpr              [RArityEntry] => RExpr
      norm expr (EVar name)        arities
        | (lookup_var_arity arities name) == 0 = ECall name []
        | is_subscript_ident name = EVar (extract fst str (split_subscript name))
        | otherwise = EVar name
      norm expr (ENot inner)       arities       =  ENot (norm_expr inner arities)
      norm expr (EOut (EVar name)) arities
        | (lookup_arity arities (name + "_out")) == 0 = ECall (name + "_out") []
      norm expr (EOut inner)       arities       =  EOut (norm_expr inner arities)
      norm expr (EBin OpAnd (EVar fn_name) r) arities
        | (lookup_arity arities fn_name) < 0 AND (can_absorb_mixfix_conj fn_name [] "and" r arities) = norm_call fn_name ([EVar "and"] :: (flatten_mixfix_rhs r arities)) arities
      norm expr (EBin OpAnd (ECall fn_name args) r) arities
        | (lookup_arity arities fn_name) < 0 AND (can_absorb_mixfix_conj fn_name args "and" r arities) = norm_call fn_name (args :: [EVar "and"] :: (flatten_mixfix_rhs r arities)) arities
      norm expr (EBin OpOr (EVar fn_name) r) arities
        | (lookup_arity arities fn_name) < 0 AND (can_absorb_mixfix_conj fn_name [] "or" r arities) = norm_call fn_name ([EVar "or"] :: (flatten_mixfix_rhs r arities)) arities
      norm expr (EBin OpOr (ECall fn_name args) r) arities
        | (lookup_arity arities fn_name) < 0 AND (can_absorb_mixfix_conj fn_name args "or" r arities) = norm_call fn_name (args :: [EVar "or"] :: (flatten_mixfix_rhs r arities)) arities
      norm expr (EBin bop l r)     arities       =  EBin bop (norm_expr l arities) (norm_expr r arities)
      norm expr (ECall fn_name args) arities     =  norm_call fn_name args arities
      norm expr (EEcho args)       arities       =  EEcho (fold_echo_args (collapse_fn_ref_args args arities) arities)
      norm expr (EStrInterp parts) arities       =  EStrInterp (norm_expr_list parts arities)
      norm expr (EList elems)      arities       =  EList (norm_expr_list elems arities)
      norm expr (ETuple elems)     arities       =  ETuple (norm_expr_list elems arities)
      norm expr (ETensor elems)    arities       =  ETensor (norm_expr_list elems arities)
      norm expr (EEinsum es subs)  arities       =  EEinsum (norm_expr_list es arities) subs
      norm expr (EHadamard bop l s1 r s2) arities = EHadamard bop (norm_expr l arities) s1 (norm_expr r arities) s2
      norm expr (EIndex base idxs) arities       =  EIndex (norm_expr base arities) (norm_expr_list idxs arities)
      norm expr (EIndexAssign t idxs v) arities  =  EIndexAssign t (norm_expr_list idxs arities) (norm_expr v arities)
      norm expr (ESeqSelect b m)   arities       =  ESeqSelect (norm_expr b arities) m
      norm expr (EBlock stmts)     arities       =  EBlock (norm_stmt_list stmts arities)
      norm expr (EGuard guards)    arities       =  EGuard (norm_guard_list guards arities)
      norm expr (EWhere body binds) arities      =  EWhere (norm_expr body arities) (norm_where_list binds arities)
      norm expr (EParPipe branches) arities      =  EParPipe (norm_expr_list branches arities)
      norm expr (EWithCtx c v b)   arities       =  EWithCtx c (norm_expr v arities) (norm_expr b arities)
      norm expr (EWithRegion q b)  arities       =  EWithRegion q (norm_expr b arities)
      norm expr e                  _             =  e

fn :: norm expr list [RExpr] [RArityEntry] => [RExpr]
      norm expr list []      _             =  []
      norm expr list (e:es)  arities       =  [norm_expr e arities] :: (norm_expr_list es arities)

fn :: bind pat local arities RPattern [RArityEntry] => [RArityEntry]
      bind pat local arities (PatVar v) arities = [ArityEntry v (0 - 2)] :: arities
      bind pat local arities (PatSeqBind v) arities = [ArityEntry v (0 - 2)] :: arities
      bind pat local arities (PatCons h t) arities = bind_pat_local_arities t (bind_pat_local_arities h arities)
      bind pat local arities (PatTuple ps) arities = bind_pat_list_local_arities ps arities
      bind pat local arities (PatCtor _ ps) arities = bind_pat_list_local_arities ps arities
      bind pat local arities _ arities = arities

fn :: bind pat list local arities [RPattern] [RArityEntry] => [RArityEntry]
      bind pat list local arities [] arities = arities
      bind pat list local arities (p:ps) arities = bind_pat_list_local_arities ps (bind_pat_local_arities p arities)

fn :: bind where local arities [RWhereBind] [RArityEntry] => [RArityEntry]
      bind where local arities [] arities = arities
      bind where local arities ((WhereBind _ v _):wbs) arities
        | v != "" = bind_where_local_arities wbs ([ArityEntry v (0 - 2)] :: arities)
        | otherwise = bind_where_local_arities wbs arities

fn :: norm stmt list [RStmt]            [RArityEntry] => [RStmt]
      norm stmt list []                 _             =  []
      norm stmt list ((StmtLet v e):ss) arities       =
        [StmtLet v (norm_expr e arities)] :: (norm_stmt_list ss ([ArityEntry v (0 - 2)] :: arities))
      norm stmt list ((StmtMut v e):ss) arities       =
        [StmtMut v (norm_expr e arities)] :: (norm_stmt_list ss ([ArityEntry v (0 - 2)] :: arities))
      norm stmt list ((StmtExpr e):ss)  arities       =  [StmtExpr (norm_expr e arities)] :: (norm_stmt_list ss arities)
      norm stmt list ((StmtIndexAssign t idxs e):ss) arities = [StmtIndexAssign t (norm_expr_list idxs arities) (norm_expr e arities)] :: (norm_stmt_list ss arities)

fn :: norm where list [RWhereBind] [RArityEntry] => [RWhereBind]
      norm where list []           _             =  []
      norm where list ((WhereBind e v idxs):wbs) arities = [WhereBind (norm_expr e arities) v idxs] :: (norm_where_list wbs arities)

fn :: norm guard list [RGuard] [RArityEntry] => [RGuard]
      norm guard list []       _             =  []
      norm guard list ((GuardBranch c b):gs) arities = [GuardBranch (norm_expr c arities) (norm_expr b arities)] :: (norm_guard_list gs arities)

fn :: norm case body RExpr [RArityEntry] => RExpr
      norm case body (EWhere body binds) arities =
        ar1 = bind_where_local_arities binds arities
        EWhere (norm_expr body ar1) (norm_where_list binds ar1)
      norm case body body arities = norm_expr body arities

fn :: norm case list [RFnCase] [RArityEntry] => [RFnCase]
      norm case list []        _             =  []
      norm case list ((FnCase pats guards body):cs) arities =
        case_arities = bind_pat_list_local_arities pats arities
        [FnCase pats (norm_guard_list guards case_arities) (norm_case_body body case_arities)] :: (norm_case_list cs arities)

fn :: norm fndef list acc [RFnDef] [RArityEntry] [RFnDef] => [RFnDef]
      norm fndef list acc []       _             acc      =  acc
      norm fndef list acc ((FnDef name params ret_ty cases):fs) arities acc =
        norm_fndef_list_acc fs arities (acc :: [FnDef name params ret_ty (norm_case_list cases arities)])

fn :: norm fndef list [RFnDef] [RArityEntry] => [RFnDef]
      norm fndef list fns      arities       =  norm_fndef_list_acc fns arities []

fn :: extract lambda params [RExpr] => [String] RExpr
      extract lambda params (body_e:[]) = ([], body_e)
      extract lambda params ((EStr p):rest) =
        prepend_str_expr p (extract_lambda_params rest)
      extract lambda params (_:rest) = extract_lambda_params rest
      extract lambda params [] = ([], EUnit)

fn :: prepend str expr String ([String], RExpr) => [String] RExpr
      prepend str expr s (xs, e) = ([s] :: xs, e)

fn :: collect expr free locals RExpr [String] [String] [String] => [String]
      collect expr free locals (EVar v) outer_locals shadowed acc
        | (str_in_seen_list v outer_locals) AND (NOT (str_in_seen_list v shadowed)) AND (NOT (str_in_seen_list v acc)) = acc :: [v]
        | otherwise = acc
      collect expr free locals (ENot e) outer_locals shadowed acc =
        collect_expr_free_locals e outer_locals shadowed acc
      collect expr free locals (EOut e) outer_locals shadowed acc =
        collect_expr_free_locals e outer_locals shadowed acc
      collect expr free locals (EBin _ l r) outer_locals shadowed acc =
        collect_expr_free_locals r outer_locals shadowed (collect_expr_free_locals l outer_locals shadowed acc)
      collect expr free locals (ECall "__lambda__" args) outer_locals shadowed acc =
        collect_lambda_free_locals (extract_lambda_params args) outer_locals shadowed acc
      collect expr free locals (ECall fn_name args) outer_locals shadowed acc =
        acc1 = collect_expr_free_locals (EVar fn_name) outer_locals shadowed acc
        collect_expr_list_free_locals args outer_locals shadowed acc1
      collect expr free locals (EEcho args) outer_locals shadowed acc =
        collect_expr_list_free_locals args outer_locals shadowed acc
      collect expr free locals (EStrInterp parts) outer_locals shadowed acc =
        collect_expr_list_free_locals parts outer_locals shadowed acc
      collect expr free locals (EList elems) outer_locals shadowed acc =
        collect_expr_list_free_locals elems outer_locals shadowed acc
      collect expr free locals (ETuple elems) outer_locals shadowed acc =
        collect_expr_list_free_locals elems outer_locals shadowed acc
      collect expr free locals (ETensor elems) outer_locals shadowed acc =
        collect_expr_list_free_locals elems outer_locals shadowed acc
      collect expr free locals (EEinsum es _) outer_locals shadowed acc =
        collect_expr_list_free_locals es outer_locals shadowed acc
      collect expr free locals (EHadamard _ l _ r _) outer_locals shadowed acc =
        collect_expr_free_locals r outer_locals shadowed (collect_expr_free_locals l outer_locals shadowed acc)
      collect expr free locals (EIndex b idxs) outer_locals shadowed acc =
        collect_expr_list_free_locals idxs outer_locals shadowed (collect_expr_free_locals b outer_locals shadowed acc)
      collect expr free locals (EIndexAssign t idxs v) outer_locals shadowed acc =
        a1 = collect_expr_free_locals (EVar t) outer_locals shadowed acc
        a2 = collect_expr_list_free_locals idxs outer_locals shadowed a1
        collect_expr_free_locals v outer_locals shadowed a2
      collect expr free locals (ESeqSelect b _) outer_locals shadowed acc =
        collect_expr_free_locals b outer_locals shadowed acc
      collect expr free locals (EBlock stmts) outer_locals shadowed acc =
        collect_stmt_list_free_locals stmts outer_locals shadowed acc
      collect expr free locals (EGuard gs) outer_locals shadowed acc =
        collect_guard_list_free_locals gs outer_locals shadowed acc
      collect expr free locals (EWhere b wbs) outer_locals shadowed acc =
        sh1 = collect_where_bound_vars wbs shadowed
        a1 = collect_where_list_free_locals wbs outer_locals sh1 acc
        collect_expr_free_locals b outer_locals sh1 a1
      collect expr free locals (EParPipe bs) outer_locals shadowed acc =
        collect_expr_list_free_locals bs outer_locals shadowed acc
      collect expr free locals (EWithCtx c v b) outer_locals shadowed acc =
        a1 = collect_expr_free_locals v outer_locals shadowed acc
        collect_expr_free_locals b outer_locals ([c] :: shadowed) a1
      collect expr free locals (EWithRegion _ b) outer_locals shadowed acc =
        collect_expr_free_locals b outer_locals shadowed acc
      collect expr free locals _ _ _ acc = acc

fn :: split raw comma loop String Int Int Int [String] => [String]
      split raw comma loop s start pos len acc
        | pos >= len = acc :: [str_slice s start len]
        | (str_char_at s pos) == 44 = split_raw_comma_loop s (pos + 1) (pos + 1) len (acc :: [str_slice s start pos])
        | otherwise = split_raw_comma_loop s start (pos + 1) len acc

fn :: split raw comma strs String => [String]
      split raw comma strs "" = []
      split raw comma strs s = split_raw_comma_loop s 0 0 (str_len s) []

fn :: expand lambda param names [String] => [String]
      expand lambda param names [] = []
      expand lambda param names (p:ps)
        | str_starts_with p "(" = (split_raw_comma_strs (str_slice p 1 ((str_len p) - 1))) :: (expand_lambda_param_names ps)
        | otherwise = [p] :: (expand_lambda_param_names ps)

fn :: collect lambda free locals ([String], RExpr) [String] [String] [String] => [String]
      collect lambda free locals (lparams, lbody) outer_locals shadowed acc =
        collect_expr_free_locals lbody outer_locals ((expand_lambda_param_names lparams) :: shadowed) acc

fn :: collect expr list free locals [RExpr] [String] [String] [String] => [String]
      collect expr list free locals [] _ _ acc = acc
      collect expr list free locals (e:es) outer_locals shadowed acc =
        collect_expr_list_free_locals es outer_locals shadowed (collect_expr_free_locals e outer_locals shadowed acc)

fn :: collect stmt list free locals [RStmt] [String] [String] [String] => [String]
      collect stmt list free locals [] _ _ acc = acc
      collect stmt list free locals ((StmtLet v e):ss) outer_locals shadowed acc =
        a1 = collect_expr_free_locals e outer_locals shadowed acc
        collect_stmt_list_free_locals ss outer_locals ([v] :: shadowed) a1
      collect stmt list free locals ((StmtMut v e):ss) outer_locals shadowed acc =
        a1 = collect_expr_free_locals e outer_locals shadowed acc
        collect_stmt_list_free_locals ss outer_locals ([v] :: shadowed) a1
      collect stmt list free locals ((StmtExpr e):ss) outer_locals shadowed acc =
        a1 = collect_expr_free_locals e outer_locals shadowed acc
        collect_stmt_list_free_locals ss outer_locals shadowed a1
      collect stmt list free locals ((StmtIndexAssign t idxs e):ss) outer_locals shadowed acc =
        a1 = collect_expr_free_locals (EIndexAssign t idxs e) outer_locals shadowed acc
        collect_stmt_list_free_locals ss outer_locals shadowed a1

fn :: collect guard list free locals [RGuard] [String] [String] [String] => [String]
      collect guard list free locals [] _ _ acc = acc
      collect guard list free locals ((GuardBranch c b):gs) outer_locals shadowed acc =
        a1 = collect_expr_free_locals c outer_locals shadowed acc
        a2 = collect_expr_free_locals b outer_locals shadowed a1
        collect_guard_list_free_locals gs outer_locals shadowed a2

fn :: collect where list free locals [RWhereBind] [String] [String] [String] => [String]
      collect where list free locals [] _ _ acc = acc
      collect where list free locals ((WhereBind e _ _):wbs) outer_locals shadowed acc =
        collect_where_list_free_locals wbs outer_locals shadowed (collect_expr_free_locals e outer_locals shadowed acc)

fn :: make poly type vars Int Int => [String]
      make poly type vars idx count
        | idx >= count = []
        | otherwise = [char_from_code (65 + (idx % 26))] :: (make_poly_type_vars (idx + 1) count)

fn :: make lambda param ty vars [String] Int => [String] Int
      make lambda param ty vars [] idx = ([], idx)
      make lambda param ty vars (p:ps) idx
        | str_starts_with p "(" =
          tvs = split_raw_comma_strs (str_slice p 1 ((str_len p) - 1))
          k = str_list_count tvs
          tup_ty = "(" + (join_comma_ty_strs (make_poly_type_vars idx (idx + k))) + ")"
          prepend_ty_var_idx tup_ty (make_lambda_param_ty_vars ps (idx + k))
        | otherwise =
          v = char_from_code (65 + (idx % 26))
          prepend_ty_var_idx v (make_lambda_param_ty_vars ps (idx + 1))

fn :: prepend ty var idx String ([String], Int) => [String] Int
      prepend ty var idx s (xs, next_idx) = ([s] :: xs, next_idx)

fn :: var to pat String => RPattern
      var to pat "_" = PatWild
      var to pat v
        | str_starts_with v "(" = PatTuple (vars_to_pat_list (split_raw_comma_strs (str_slice v 1 ((str_len v) - 1))))
        | otherwise = PatVar v

fn :: vars to pat list [String] => [RPattern]
      vars to pat list [] = []
      vars to pat list (v:vs) = [var_to_pat v] :: (vars_to_pat_list vs)

fn :: vars to expr list [String] => [RExpr]
      vars to expr list [] = []
      vars to expr list (v:vs) = [EVar v] :: (vars_to_expr_list vs)

fn :: build lambda call expr String [String] => RExpr
      build lambda call expr lname [] = EVar lname
      build lambda call expr lname caps = ECall lname (vars_to_expr_list caps)

fn :: ensure non empty lambda params [String] => [String]
      ensure non empty lambda params [] = ["_"]
      ensure non empty lambda params ps = ps

fn :: lift lambda node ([String], RExpr) [String] Int [RFnDef] => RExpr Int [RFnDef]
      lift lambda node (lparams, lbody) locals cnt lifted =
        bound_names = expand_lambda_param_names lparams
        lifted_body = lift_expr_lambdas lbody (locals :: bound_names) (cnt + 1) lifted
        finish_lift_lambda lparams locals cnt lifted_body

fn :: finish lift lambda [String] [String] Int (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift lambda lparams locals my_id (body1, cnt1, lifted1) =
        bound_names = expand_lambda_param_names lparams
        caps = collect_expr_free_locals body1 locals bound_names []
        eff_params = ensure_non_empty_lambda_params lparams
        all_params = caps :: eff_params
        lname = "__rg_lambda_" + (int_to_str my_id)
        finish_lift_lambda_fn lname caps all_params body1 cnt1 lifted1 (make_lambda_param_ty_vars all_params 0)

fn :: finish lift lambda fn String [String] [String] RExpr Int [RFnDef] ([String], Int) => RExpr Int [RFnDef]
      finish lift lambda fn lname caps all_params body1 cnt1 lifted1 (ty_vars, next_idx) =
        ret_var = char_from_code (65 + (next_idx % 26))
        lfn = FnDef lname ty_vars ret_var [FnCase (vars_to_pat_list all_params) [] body1]
        (build_lambda_call_expr lname caps, cnt1, lifted1 :: [lfn])

fn :: lift expr lambdas RExpr [String] Int [RFnDef] => RExpr Int [RFnDef]
      lift expr lambdas (ECall "__lambda__" args) locals cnt lifted =
        lift_lambda_node (extract_lambda_params args) locals cnt lifted
      lift expr lambdas (ENot inner) locals cnt lifted =
        wrap_lift_not (lift_expr_lambdas inner locals cnt lifted)
      lift expr lambdas (EOut inner) locals cnt lifted =
        wrap_lift_out (lift_expr_lambdas inner locals cnt lifted)
      lift expr lambdas (EBin bop l r) locals cnt lifted =
        lift_bin_lambdas bop (lift_expr_lambdas l locals cnt lifted) r locals
      lift expr lambdas (ECall fn_name args) locals cnt lifted =
        wrap_lift_call fn_name (lift_expr_list_lambdas args locals cnt lifted)
      lift expr lambdas (EEcho args) locals cnt lifted =
        wrap_lift_echo (lift_expr_list_lambdas args locals cnt lifted)
      lift expr lambdas (EStrInterp parts) locals cnt lifted =
        wrap_lift_interp (lift_expr_list_lambdas parts locals cnt lifted)
      lift expr lambdas (EList elems) locals cnt lifted =
        wrap_lift_list (lift_expr_list_lambdas elems locals cnt lifted)
      lift expr lambdas (ETuple elems) locals cnt lifted =
        wrap_lift_tuple (lift_expr_list_lambdas elems locals cnt lifted)
      lift expr lambdas (ETensor elems) locals cnt lifted =
        wrap_lift_tensor (lift_expr_list_lambdas elems locals cnt lifted)
      lift expr lambdas (EIndex b idxs) locals cnt lifted =
        lift_index_lambdas (lift_expr_lambdas b locals cnt lifted) idxs locals
      lift expr lambdas (EIndexAssign t idxs v) locals cnt lifted =
        lift_idx_assign_lambdas t (lift_expr_list_lambdas idxs locals cnt lifted) v locals
      lift expr lambdas (ESeqSelect b m) locals cnt lifted =
        wrap_lift_seq m (lift_expr_lambdas b locals cnt lifted)
      lift expr lambdas (EBlock stmts) locals cnt lifted =
        wrap_lift_block (lift_stmt_list_lambdas stmts locals cnt lifted)
      lift expr lambdas (EGuard gs) locals cnt lifted =
        wrap_lift_guard (lift_guard_list_lambdas gs locals cnt lifted)
      lift expr lambdas (EWhere b wbs) locals cnt lifted =
        locs1 = collect_where_bound_vars wbs locals
        lift_where_lambdas (lift_expr_lambdas b locs1 cnt lifted) wbs locs1
      lift expr lambdas (EParPipe bs) locals cnt lifted =
        wrap_lift_parpipe (lift_expr_list_lambdas bs locals cnt lifted)
      lift expr lambdas (EWithCtx c v b) locals cnt lifted =
        lift_with_ctx_lambdas c (lift_expr_lambdas v locals cnt lifted) b ([c] :: locals)
      lift expr lambdas (EWithRegion q b) locals cnt lifted =
        wrap_lift_region q (lift_expr_lambdas b locals cnt lifted)
      lift expr lambdas e _ cnt lifted = (e, cnt, lifted)

fn :: wrap lift not (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift not (e1, c1, l1) = (ENot e1, c1, l1)

fn :: wrap lift out (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift out (e1, c1, l1) = (EOut e1, c1, l1)

fn :: lift bin lambdas RBinOp (RExpr, Int, [RFnDef]) RExpr [String] => RExpr Int [RFnDef]
      lift bin lambdas bop (l1, c1, lf1) r locals =
        finish_lift_bin bop l1 (lift_expr_lambdas r locals c1 lf1)

fn :: finish lift bin RBinOp RExpr (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift bin bop l1 (r1, c2, lf2) = (EBin bop l1 r1, c2, lf2)

fn :: wrap lift call String ([RExpr], Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift call fn_name (es1, c1, l1) = (ECall fn_name es1, c1, l1)

fn :: wrap lift echo ([RExpr], Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift echo (es1, c1, l1) = (EEcho es1, c1, l1)

fn :: wrap lift interp ([RExpr], Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift interp (es1, c1, l1) = (EStrInterp es1, c1, l1)

fn :: wrap lift list ([RExpr], Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift list (es1, c1, l1) = (EList es1, c1, l1)

fn :: wrap lift tuple ([RExpr], Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift tuple (es1, c1, l1) = (ETuple es1, c1, l1)

fn :: wrap lift tensor ([RExpr], Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift tensor (es1, c1, l1) = (ETensor es1, c1, l1)

fn :: wrap lift parpipe ([RExpr], Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift parpipe (es1, c1, l1) = (EParPipe es1, c1, l1)

fn :: wrap lift seq String (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift seq m (b1, c1, l1) = (ESeqSelect b1 m, c1, l1)

fn :: wrap lift block ([RStmt], Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift block (ss1, c1, l1) = (EBlock ss1, c1, l1)

fn :: wrap lift guard ([RGuard], Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift guard (gs1, c1, l1) = (EGuard gs1, c1, l1)

fn :: wrap lift region Int (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift region q (b1, c1, l1) = (EWithRegion q b1, c1, l1)

fn :: lift index lambdas (RExpr, Int, [RFnDef]) [RExpr] [String] => RExpr Int [RFnDef]
      lift index lambdas (b1, c1, l1) idxs locals =
        finish_lift_index b1 (lift_expr_list_lambdas idxs locals c1 l1)

fn :: finish lift index RExpr ([RExpr], Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift index b1 (idxs1, c2, l2) = (EIndex b1 idxs1, c2, l2)

fn :: lift idx assign lambdas String ([RExpr], Int, [RFnDef]) RExpr [String] => RExpr Int [RFnDef]
      lift idx assign lambdas t (idxs1, c1, l1) v locals =
        finish_lift_idx_assign t idxs1 (lift_expr_lambdas v locals c1 l1)

fn :: finish lift idx assign String [RExpr] (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift idx assign t idxs1 (v1, c2, l2) = (EIndexAssign t idxs1 v1, c2, l2)

fn :: lift with ctx lambdas String (RExpr, Int, [RFnDef]) RExpr [String] => RExpr Int [RFnDef]
      lift with ctx lambdas c (v1, c1, l1) b locals =
        finish_lift_with_ctx c v1 (lift_expr_lambdas b locals c1 l1)

fn :: finish lift with ctx String RExpr (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift with ctx c v1 (b1, c2, l2) = (EWithCtx c v1 b1, c2, l2)

fn :: lift where lambdas (RExpr, Int, [RFnDef]) [RWhereBind] [String] => RExpr Int [RFnDef]
      lift where lambdas (b1, c1, l1) wbs locals =
        finish_lift_where b1 (lift_where_list_lambdas wbs locals c1 l1)

fn :: finish lift where RExpr ([RWhereBind], Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift where b1 (wbs1, c2, l2) = (EWhere b1 wbs1, c2, l2)

fn :: lift expr list lambdas [RExpr] [String] Int [RFnDef] => [RExpr] Int [RFnDef]
      lift expr list lambdas [] _ cnt lifted = ([], cnt, lifted)
      lift expr list lambdas (e:es) locals cnt lifted =
        lift_expr_list_step (lift_expr_lambdas e locals cnt lifted) es locals

fn :: lift expr list step (RExpr, Int, [RFnDef]) [RExpr] [String] => [RExpr] Int [RFnDef]
      lift expr list step (e1, c1, l1) es locals =
        finish_lift_expr_list e1 (lift_expr_list_lambdas es locals c1 l1)

fn :: finish lift expr list RExpr ([RExpr], Int, [RFnDef]) => [RExpr] Int [RFnDef]
      finish lift expr list e1 (es1, c2, l2) = ([e1] :: es1, c2, l2)

fn :: lift stmt list lambdas [RStmt] [String] Int [RFnDef] => [RStmt] Int [RFnDef]
      lift stmt list lambdas [] _ cnt lifted = ([], cnt, lifted)
      lift stmt list lambdas ((StmtLet v e):ss) locals cnt lifted =
        lift_stmt_let_step v (lift_expr_lambdas e locals cnt lifted) ss (locals :: [v])
      lift stmt list lambdas ((StmtMut v e):ss) locals cnt lifted =
        lift_stmt_mut_step v (lift_expr_lambdas e locals cnt lifted) ss (locals :: [v])
      lift stmt list lambdas ((StmtExpr e):ss) locals cnt lifted =
        lift_stmt_expr_step (lift_expr_lambdas e locals cnt lifted) ss locals
      lift stmt list lambdas ((StmtIndexAssign t idxs e):ss) locals cnt lifted =
        lift_stmt_idx_step (lift_idx_assign_lambdas t (lift_expr_list_lambdas idxs locals cnt lifted) e locals) ss locals

fn :: lift stmt let step String (RExpr, Int, [RFnDef]) [RStmt] [String] => [RStmt] Int [RFnDef]
      lift stmt let step v (e1, c1, l1) ss locals =
        finish_lift_stmt (StmtLet v e1) (lift_stmt_list_lambdas ss locals c1 l1)

fn :: lift stmt mut step String (RExpr, Int, [RFnDef]) [RStmt] [String] => [RStmt] Int [RFnDef]
      lift stmt mut step v (e1, c1, l1) ss locals =
        finish_lift_stmt (StmtMut v e1) (lift_stmt_list_lambdas ss locals c1 l1)

fn :: lift stmt expr step (RExpr, Int, [RFnDef]) [RStmt] [String] => [RStmt] Int [RFnDef]
      lift stmt expr step (e1, c1, l1) ss locals =
        finish_lift_stmt (StmtExpr e1) (lift_stmt_list_lambdas ss locals c1 l1)

fn :: lift stmt idx step (RExpr, Int, [RFnDef]) [RStmt] [String] => [RStmt] Int [RFnDef]
      lift stmt idx step ((EIndexAssign t idxs1 e1), c1, l1) ss locals =
        finish_lift_stmt (StmtIndexAssign t idxs1 e1) (lift_stmt_list_lambdas ss locals c1 l1)
      lift stmt idx step (e1, c1, l1) ss locals =
        finish_lift_stmt (StmtExpr e1) (lift_stmt_list_lambdas ss locals c1 l1)

fn :: finish lift stmt RStmt ([RStmt], Int, [RFnDef]) => [RStmt] Int [RFnDef]
      finish lift stmt s1 (ss1, c2, l2) = ([s1] :: ss1, c2, l2)

fn :: lift guard list lambdas [RGuard] [String] Int [RFnDef] => [RGuard] Int [RFnDef]
      lift guard list lambdas [] _ cnt lifted = ([], cnt, lifted)
      lift guard list lambdas ((GuardBranch c b):gs) locals cnt lifted =
        lift_guard_step (lift_expr_lambdas c locals cnt lifted) b gs locals

fn :: lift guard step (RExpr, Int, [RFnDef]) RExpr [RGuard] [String] => [RGuard] Int [RFnDef]
      lift guard step (c1, cnt1, l1) b gs locals =
        lift_guard_step2 c1 (lift_expr_lambdas b locals cnt1 l1) gs locals

fn :: lift guard step2 RExpr (RExpr, Int, [RFnDef]) [RGuard] [String] => [RGuard] Int [RFnDef]
      lift guard step2 c1 (b1, cnt2, l2) gs locals =
        finish_lift_guard (GuardBranch c1 b1) (lift_guard_list_lambdas gs locals cnt2 l2)

fn :: finish lift guard RGuard ([RGuard], Int, [RFnDef]) => [RGuard] Int [RFnDef]
      finish lift guard g1 (gs1, c3, l3) = ([g1] :: gs1, c3, l3)

fn :: lift where list lambdas [RWhereBind] [String] Int [RFnDef] => [RWhereBind] Int [RFnDef]
      lift where list lambdas [] _ cnt lifted = ([], cnt, lifted)
      lift where list lambdas ((WhereBind e v idxs):wbs) locals cnt lifted =
        lift_where_step v idxs (lift_expr_lambdas e locals cnt lifted) wbs locals

fn :: lift where step String [Int] (RExpr, Int, [RFnDef]) [RWhereBind] [String] => [RWhereBind] Int [RFnDef]
      lift where step v idxs (e1, c1, l1) wbs locals =
        finish_lift_where_bind (WhereBind e1 v idxs) (lift_where_list_lambdas wbs locals c1 l1)

fn :: finish lift where bind RWhereBind ([RWhereBind], Int, [RFnDef]) => [RWhereBind] Int [RFnDef]
      finish lift where bind wb1 (wbs1, c2, l2) = ([wb1] :: wbs1, c2, l2)

fn :: lift case list lambdas [RFnCase] Int [RFnDef] => [RFnCase] Int [RFnDef]
      lift case list lambdas [] cnt lifted = ([], cnt, lifted)
      lift case list lambdas ((FnCase pats gs body):cs) cnt lifted =
        locals = collect_pat_list_bound_vars pats []
        lift_case_step pats (lift_guard_list_lambdas gs locals cnt lifted) body locals cs

fn :: lift case step [RPattern] ([RGuard], Int, [RFnDef]) RExpr [String] [RFnCase] => [RFnCase] Int [RFnDef]
      lift case step pats (gs1, c1, l1) body locals cs =
        lift_case_step2 pats gs1 (lift_expr_lambdas body locals c1 l1) cs

fn :: lift case step2 [RPattern] [RGuard] (RExpr, Int, [RFnDef]) [RFnCase] => [RFnCase] Int [RFnDef]
      lift case step2 pats gs1 (body1, c2, l2) cs =
        finish_lift_case (FnCase pats gs1 body1) (lift_case_list_lambdas cs c2 l2)

fn :: finish lift case RFnCase ([RFnCase], Int, [RFnDef]) => [RFnCase] Int [RFnDef]
      finish lift case fc1 (cs1, c3, l3) = ([fc1] :: cs1, c3, l3)

fn :: lift fndef list lambdas [RFnDef] Int [RFnDef] [RFnDef] => [RFnDef]
      lift fndef list lambdas [] _ lifted acc = acc :: lifted
      lift fndef list lambdas ((FnDef name params ret_ty cases):fs) cnt lifted acc =
        lift_fndef_step name params ret_ty (lift_case_list_lambdas cases cnt lifted) fs acc

fn :: lift fndef step String [String] String ([RFnCase], Int, [RFnDef]) [RFnDef] [RFnDef] => [RFnDef]
      lift fndef step name params ret_ty (cs1, c1, l1) fs acc =
        lift_fndef_list_lambdas fs c1 l1 (acc :: [FnDef name params ret_ty cs1])

fn :: strip ty brackets String => String
      strip ty brackets s
        | (str_len s) >= 2 AND (str_starts_with s "[") = strip_ty_brackets (str_slice s 1 ((str_len s) - 1))
        | otherwise = s

fn :: collect poly vars in str String [String] => [String]
      collect poly vars in str s acc =
        b = strip_ty_brackets s
        collect_poly_var_base b acc

fn :: collect poly var base String [String] => [String]
      collect poly var base b acc
        | (str_len b) == 1 AND (is_upper_ident b) AND (NOT (str_in_seen_list b acc)) = acc :: [b]
        | otherwise = acc

fn :: collect poly vars in strs [String] [String] => [String]
      collect poly vars in strs [] acc = acc
      collect poly vars in strs (s:ss) acc =
        collect_poly_vars_in_strs ss (collect_poly_vars_in_str s acc)

fn :: collect poly vars in variants [RVariant] [String] => [String]
      collect poly vars in variants [] acc = acc
      collect poly vars in variants ((TypeVariant _ args):vs) acc =
        collect_poly_vars_in_variants vs (collect_poly_vars_in_strs args acc)

fn :: collect poly vars in fields [RField] [String] => [String]
      collect poly vars in fields [] acc = acc
      collect poly vars in fields ((TypeField _ fty):fs) acc =
        collect_poly_vars_in_fields fs (collect_poly_vars_in_str fty acc)

fn :: collect poly type arities [RTypeDef] => [RArityEntry]
      collect poly type arities [] = [ArityEntry "Option" 1]
      collect poly type arities ((TypeDef name vars fields):ts) =
        pvars = collect_poly_vars_in_fields fields (collect_poly_vars_in_variants vars [])
        n = str_list_count pvars
        prepend_poly_arity name n (collect_poly_type_arities ts)

fn :: prepend poly arity String Int [RArityEntry] => [RArityEntry]
      prepend poly arity _ 0 rest = rest
      prepend poly arity name n rest
        | str_contains name "." = [ArityEntry name n, ArityEntry (ident_base_name name) n] :: rest
        | otherwise = [ArityEntry name n] :: rest

fn :: take ty strs [String] Int => [String]
      take ty strs _ 0 = []
      take ty strs [] _ = []
      take ty strs (x:xs) n = [x] :: (take_ty_strs xs (n - 1))

fn :: drop ty strs [String] Int => [String]
      drop ty strs xs 0 = xs
      drop ty strs [] _ = []
      drop ty strs (_:xs) n = drop_ty_strs xs (n - 1)

fn :: join comma ty strs [String] => String
      join comma ty strs [] = ""
      join comma ty strs (s:[]) = s
      join comma ty strs (s:ss) = s + ", " + (join_comma_ty_strs ss)

fn :: collapse poly param list [String] Int [RArityEntry] => [String]
      collapse poly param list [] _ _ = []
      collapse poly param list (p:ps) target_arity poly_arities
        | (1 + (str_list_count ps)) <= target_arity = [p] :: ps
        | otherwise =
          k = lookup_arity poly_arities p
          collapse_poly_param_step p ps k target_arity poly_arities

fn :: collapse poly param step String [String] Int Int [RArityEntry] => [String]
      collapse poly param step p ps k target_arity poly_arities
        | k > 0 AND (str_list_count ps) >= k =
          app_s = "(" + p + ", " + (join_comma_ty_strs (take_ty_strs ps k)) + ")"
          [app_s] :: (collapse_poly_param_list (drop_ty_strs ps k) (target_arity - 1) poly_arities)
        | otherwise =
          [p] :: (collapse_poly_param_list ps (target_arity - 1) poly_arities)

fn :: first case pat arity [RFnCase] => Int
      first case pat arity ((FnCase pats _ _):_) = pat_list_count pats
      first case pat arity [] = 0

fn :: collapse fndef poly params [RFnDef] [RArityEntry] [RFnDef] => [RFnDef]
      collapse fndef poly params [] _ acc = acc
      collapse fndef poly params ((FnDef name params ret_ty cases):fs) poly_arities acc =
        pat_ar = first_case_pat_arity cases
        params1 = collapse_poly_param_list params pat_ar poly_arities
        collapse_fndef_poly_params fs poly_arities (acc :: [FnDef name params1 ret_ty cases])

fn :: normalize program RProgram          => RProgram
      normalize program (Program fns tys) =
        poly_arities = collect_poly_type_arities tys
        fns0 = collapse_fndef_poly_params fns poly_arities []
        fns1 = lift_fndef_list_lambdas fns0 0 [] []
        arities = (collect_fn_arities fns1) :: (collect_type_arities tys)
        Program (norm_fndef_list fns1 arities) tys

-- ── Library & Module Import Resolution (`.rglib` / `.rg`) ────

fn :: is core compiler mod String      => Bool
      is core compiler mod "ast"       =  True
      is core compiler mod "lexer"     =  True
      is core compiler mod "parser"    =  True
      is core compiler mod "analyzer"  =  True
      is core compiler mod "typecheck" =  True
      is core compiler mod "compiler"  =  True
      is core compiler mod "vm"        =  True
      is core compiler mod "elf64"     =  True
      is core compiler mod "x86_64"    =  True
      is core compiler mod "arm64"     =  True
      is core compiler mod "llvm"      =  True
      is core compiler mod "formatter" =  True
      is core compiler mod _           =  False

fn :: try read candidate paths [String] => String
      try read candidate paths []       =  ""
      try read candidate paths (p:ps)   =
        content = read_file p
        try_read_candidate_step content ps

fn :: try read candidate step String [String] => String
      try read candidate step "" ps = try_read_candidate_paths ps
      try read candidate step content _ = content

fn :: rglib dir of String Int Int Int => String
      rglib dir of fpath pos len last_slash
        | pos >= len AND last_slash < 0 = "."
        | pos >= len = str_slice fpath 0 last_slash
        | (str_char_at fpath pos) == 47 = rglib_dir_of fpath (pos + 1) len pos
        | otherwise = rglib_dir_of fpath (pos + 1) len last_slash

fn :: strip quotes len String Int => String
      strip quotes len s      n
        | n >= 2 AND ((str_char_at s 0) == 34 OR (str_char_at s 0) == 39) = str_slice s 1 (n - 1)
        | otherwise = s

fn :: strip quotes String => String
      strip quotes s      =  strip_quotes_len s (str_len s)

fn :: dots to slashes loop String Int Int String => String
      dots to slashes loop s pos len acc
        | pos >= len = acc
        | (str_char_at s pos) == 46 = dots_to_slashes_loop s (pos + 1) len (acc + "/")
        | otherwise = dots_to_slashes_loop s (pos + 1) len (acc + (str_slice s pos (pos + 1)))

fn :: norm spec path String => String
      norm spec path spec
        | (str_contains spec ".rglib") OR (str_contains spec ".rg") = spec
        | str_contains spec "." = dots_to_slashes_loop spec 0 (str_len spec) ""
        | otherwise = spec

fn :: read local rg module raw String String => String
      read local rg module raw pdir spec =
        try_read_candidate_paths [pdir + "/" + spec + ".rg", pdir + "/" + spec + "/lib.rg", pdir + "/" + spec + "/mod.rg", pdir + "/../" + spec + ".rg", pdir + "/../lib/" + spec + ".rg", pdir + "/../../main/ridgun/lib/" + spec + ".rg", pdir + "/../../main/ridgun/" + spec + ".rg", "src/main/ridgun/lib/" + spec + ".rg", "src/main/ridgun/" + spec + ".rg", "src/main/ridgun/" + spec + "/lib.rg", spec + ".rg"]

fn :: read local rg module String String => String
      read local rg module pdir spec =
        r1 = read_local_rg_module_raw pdir spec
        read_local_rg_fallback pdir (norm_spec_path spec) r1

fn :: read local rg fallback String String String => String
      read local rg fallback pdir nspec "" = read_local_rg_module_raw pdir nspec
      read local rg fallback _ _ content = content

fn :: has local rg module String String => Bool
      has local rg module pdir spec =
        (read_local_rg_module pdir spec) != ""

fn :: dep subdir paths String [String] String => [String]
      dep subdir paths _ [] _ = []
      dep subdir paths deps_base (d:ds) spec
        | str_contains spec ".rglib" =
          [deps_base + "/" + d + "/target/bundles/" + spec, deps_base + "/" + d + "/target/" + spec, deps_base + "/" + d + "/" + spec] :: (dep_subdir_paths deps_base ds spec)
        | otherwise =
          [deps_base + "/" + d + "/target/bundles/" + spec + ".rglib", deps_base + "/" + d + "/target/" + spec + ".rglib", deps_base + "/" + d + "/" + spec + ".rglib", deps_base + "/" + d + "/src/main/ridgun/lib/" + spec + ".rg", deps_base + "/" + d + "/src/main/ridgun/" + spec + ".rg", deps_base + "/" + d + "/src/main/ridgun/" + spec + "/lib.rg"] :: (dep_subdir_paths deps_base ds spec)

fn :: all deps base paths [String] String => [String]
      all deps base paths [] _ = []
      all deps base paths (base:bs) spec
        | str_contains spec ".rglib" =
          [base + "/" + spec] :: (dep_subdir_paths base (list_dir base) spec) :: (all_deps_base_paths bs spec)
        | otherwise =
          [base + "/" + spec + ".rglib", base + "/" + spec + ".rg"] :: (dep_subdir_paths base (list_dir base) spec) :: (all_deps_base_paths bs spec)

fn :: resolve rglib bundle raw String String => String
      resolve rglib bundle raw pdir spec
        | is_core_compiler_mod spec = ""
        | str_contains spec ".rglib" =
          dep_paths = all_deps_base_paths [".stable/deps", pdir + "/.stable/deps", pdir + "/../.stable/deps", pdir + "/../../.stable/deps", pdir + "/../../../.stable/deps", pdir + "/../../../../.stable/deps"] spec
          try_read_candidate_paths ([spec, pdir + "/" + spec, "target/bundles/" + spec, "build/" + spec, "target/" + spec, "dist/" + spec, "lib/" + spec] :: dep_paths)
        | otherwise =
          dep_paths = all_deps_base_paths [".stable/deps", pdir + "/.stable/deps", pdir + "/../.stable/deps", pdir + "/../../.stable/deps", pdir + "/../../../.stable/deps", pdir + "/../../../../.stable/deps"] spec
          try_read_candidate_paths (dep_paths :: ["target/bundles/" + spec + ".rglib", "build/" + spec + ".rglib", pdir + "/" + spec + ".rglib", pdir + "/lib/" + spec + ".rglib", spec + ".rglib", "target/" + spec + ".rglib", "dist/" + spec + ".rglib", "lib/" + spec + ".rglib", "src/main/ridgun/lib/" + spec + ".rglib"])

fn :: resolve rglib bundle fallback String String String => String
      resolve rglib bundle fallback pdir nspec "" = resolve_rglib_bundle_raw pdir nspec
      resolve rglib bundle fallback _ _ content = content

fn :: resolve rglib bundle String String => String
      resolve rglib bundle pdir spec =
        r1 = resolve_rglib_bundle_raw pdir spec
        resolve_rglib_bundle_fallback pdir (norm_spec_path spec) r1

fn :: resolve rglib clean String String => String
      resolve rglib clean pdir   spec
        | is_core_compiler_mod spec = ""
        | str_contains spec ".rglib" = resolve_rglib_bundle pdir spec
        | has_local_rg_module pdir spec = ""
        | otherwise = resolve_rglib_bundle pdir spec

fn :: rglib trim lead String Int Int => String
      rglib trim lead s pos len
        | pos >= len = ""
        | (str_char_at s pos) == 32 OR (str_char_at s pos) == 9 OR (str_char_at s pos) == 13 = rglib_trim_lead s (pos + 1) len
        | otherwise = str_slice s pos len

fn :: rglib trim trail String Int     => String
      rglib trim trail s      end_pos
        | end_pos <= 0 = ""
        | (str_char_at s (end_pos - 1)) == 32 OR (str_char_at s (end_pos - 1)) == 9 OR (str_char_at s (end_pos - 1)) == 13 = rglib_trim_trail s (end_pos - 1)
        | otherwise = str_slice s 0 end_pos

fn :: rglib trim String => String
      rglib trim s      =
        s1 = rglib_trim_lead s 0 (str_len s)
        rglib_trim_trail s1 (str_len s1)

fn :: strip inline comment loop String Int Int => String
      strip inline comment loop s pos len
        | pos >= len = s
        | (pos + 1) < len AND (str_char_at s pos) == 45 AND (str_char_at s (pos + 1)) == 45 = str_slice s 0 pos
        | otherwise = strip_inline_comment_loop s (pos + 1) len

fn :: find import as kw String Int Int => Int
      find import as kw s pos len
        | (pos + 4) > len = 0 - 1
        | (str_slice s pos (pos + 4)) == " as " = pos
        | otherwise = find_import_as_kw s (pos + 1) len

fn :: split import as idx String Int => String String
      split import as idx trimmed idx
        | idx < 0 = (strip_quotes (rglib_trim trimmed), "")
        | otherwise =
          spec_part = strip_quotes (rglib_trim (str_slice trimmed 0 idx))
          alias_part = strip_quotes (rglib_trim (str_slice trimmed (idx + 4) (str_len trimmed)))
          (spec_part, alias_part)

fn :: parse import spec line String => String String
      parse import spec line raw_spec =
        no_comment = rglib_trim (strip_inline_comment_loop raw_spec 0 (str_len raw_spec))
        idx = find_import_as_kw no_comment 0 (str_len no_comment)
        split_import_as_idx no_comment idx

fn :: last slash idx String Int Int Int => Int
      last slash idx s pos len last_s
        | pos >= len = last_s
        | (str_char_at s pos) == 47 = last_slash_idx s (pos + 1) len pos
        | otherwise = last_slash_idx s (pos + 1) len last_s

fn :: strip mod ext String => String
      strip mod ext s
        | (str_len s) > 6 AND (str_slice s ((str_len s) - 6) (str_len s)) == ".rglib" = str_slice s 0 ((str_len s) - 6)
        | (str_len s) > 3 AND (str_slice s ((str_len s) - 3) (str_len s)) == ".rg" = str_slice s 0 ((str_len s) - 3)
        | otherwise = s

fn :: mod name after slash String Int => String
      mod name after slash s sl
        | sl < 0 = s
        | otherwise = str_slice s (sl + 1) (str_len s)

fn :: mod name of spec String => String
      mod name of spec spec =
        s1 = strip_mod_ext spec
        s2 = norm_spec_path s1
        sl = last_slash_idx s2 0 (str_len s2) (0 - 1)
        mod_name_after_slash s2 sl

fn :: mod alias marker String String => String
      mod alias marker "" _ = ""
      mod alias marker alias mname = "\n@__rg_mod_alias__ " + alias + " " + mname + "\n"

fn :: resolve rglib for spec String String => String
      resolve rglib for spec pdir raw_spec =
        spec_pair = parse_import_spec_line raw_spec
        resolve_rglib_clean pdir (extract_fst_str spec_pair)

fn :: strip rgc magic String => String
      strip rgc magic s
        | str_starts_with s "RGC1" = "-- " + s
        | otherwise = s

fn :: append rglib resolved String String String => String
      append rglib resolved acc    _     ""      =  acc
      append rglib resolved acc    mname lib_src
        | is_core_compiler_mod mname = acc + (strip_rgc_magic lib_src) + "\n"
        | otherwise = acc + "\n@__rg_mod_enter__ " + mname + "\n" + (strip_rgc_magic lib_src) + "\n@__rg_mod_exit__\n"

fn :: str in seen list String [String] => Bool
      str in seen list _ [] = False
      str in seen list target (s:ss)
        | s == target = True
        | otherwise = str_in_seen_list target ss

fn :: append rglib from pair String (String, String) String [String] => String [String]
      append rglib from pair pdir (clean_spec, alias) acc seen =
        mname = mod_name_of_spec clean_spec
        r1 = append_rglib_if_unseen pdir clean_spec acc seen
        append_rglib_with_alias alias mname r1

fn :: append rglib with alias String String (String, [String]) => String [String]
      append rglib with alias alias mname (acc2, seen2) =
        (acc2 + (mod_alias_marker alias mname), seen2)

fn :: append rglib from line String String String [String] => String [String]
      append rglib from line pdir line acc seen
        | str_starts_with line "import " =
          raw_spec = str_slice line 7 (str_len line)
          append_rglib_from_pair pdir (parse_import_spec_line raw_spec) acc seen
        | otherwise = (acc, seen)

fn :: append rglib after deps String String (String, [String]) => String [String]
      append rglib after deps mname lib_src (acc2, seen2) =
        (append_rglib_resolved acc2 mname lib_src, seen2)

fn :: has same dir rglib String String => Bool
      has same dir rglib pdir spec
        | str_contains spec ".rglib" = (read_file (pdir + "/" + spec)) != ""
        | otherwise = (read_file (pdir + "/" + spec + ".rglib")) != ""

fn :: append rglib resolved mod String String String String [String] => String [String]
      append rglib resolved mod _ clean_spec "" acc seen1 =
        (acc + "\nfn :: unresolved import => Int\n      unresolved import = __missing_import__ \"" + clean_spec + "\"\n", seen1)
      append rglib resolved mod pdir clean_spec lib_src acc seen1 =
        mname = mod_name_of_spec clean_spec
        sub_pdir = child_pdir_for_spec pdir clean_spec
        res_deps = scan_rglib_imports_state sub_pdir lib_src 0 (str_len lib_src) 0 acc seen1
        append_rglib_after_deps mname lib_src res_deps

fn :: append rglib local or ext String String String String [String] => String [String]
      append rglib local or ext pdir clean_spec "" acc seen1 =
        lib_src = resolve_rglib_bundle pdir clean_spec
        append_rglib_resolved_mod pdir clean_spec lib_src acc seen1
      append rglib local or ext pdir clean_spec local_rg acc seen1 =
        mname = mod_name_of_spec clean_spec
        sub_pdir = child_pdir_for_spec pdir clean_spec
        res_deps = scan_rglib_imports_state sub_pdir local_rg 0 (str_len local_rg) 0 acc seen1
        append_rglib_after_deps mname local_rg res_deps

fn :: append rglib if unseen String String String [String] => String [String]
      append rglib if unseen pdir clean_spec acc seen
        | (is_core_compiler_mod clean_spec) OR (str_in_seen_list clean_spec seen) = (acc, seen)
        | has_same_dir_rglib pdir clean_spec =
          seen1 = [clean_spec] :: seen
          append_rglib_resolved_mod pdir clean_spec (resolve_rglib_bundle pdir clean_spec) acc seen1
        | otherwise =
          seen1 = [clean_spec] :: seen
          local_rg = read_local_rg_module pdir clean_spec
          append_rglib_local_or_ext pdir clean_spec local_rg acc seen1

fn :: fst str seen (String, [String]) => String
      fst str seen (a, _)             =  a

fn :: skip line spaces String Int Int => Int
      skip line spaces s p end_p
        | p >= end_p = p
        | (str_char_at s p) == 32 OR (str_char_at s p) == 9 = skip_line_spaces s (p + 1) end_p
        | otherwise = p

fn :: line starts with import String Int Int => Bool
      line starts with import s start end_p =
        p = skip_line_spaces s start end_p
        (end_p - p) > 7 AND (str_char_at s p) == 105 AND (str_char_at s (p + 1)) == 109 AND (str_char_at s (p + 2)) == 112 AND (str_char_at s (p + 3)) == 111 AND (str_char_at s (p + 4)) == 114 AND (str_char_at s (p + 5)) == 116 AND (str_char_at s (p + 6)) == 32

fn :: scan rglib line String String Int Int String [String] => String [String]
      scan rglib line pdir s line_start end_p acc seen
        | line_starts_with_import s line_start end_p =
          line = rglib_trim (str_slice s line_start end_p)
          append_rglib_from_line pdir line acc seen
        | otherwise = (acc, seen)

fn :: scan rglib imports state String String Int Int Int String [String] => String [String]
      scan rglib imports state pdir s pos len line_start acc seen
        | pos >= len =
          scan_rglib_line pdir s line_start len acc seen
        | (str_char_at s pos) == 10 =
          res = scan_rglib_line pdir s line_start pos acc seen
          scan_rglib_imports_cont pdir s (pos + 1) len res
        | otherwise =
          scan_rglib_imports_state pdir s (pos + 1) len line_start acc seen

fn :: scan rglib imports cont String String Int Int (String, [String]) => String [String]
      scan rglib imports cont pdir s next_pos len (acc2, seen2) =
        scan_rglib_imports_state pdir s next_pos len next_pos acc2 seen2

fn :: scan rglib imports String String Int Int Int String [String] => String
      scan rglib imports pdir s pos len line_start acc seen =
        fst_str_seen (scan_rglib_imports_state pdir s pos len line_start acc seen)

fn :: format deferred import String String => String
      format deferred import clean_spec "" = "import \"" + clean_spec + "\"\n"
      format deferred import clean_spec alias = "import \"" + clean_spec + "\" as " + alias + "\n"

fn :: append own rg after local String String String (String, [String]) => String [String]
      append own rg after local clean_spec mname alias (acc2, seen2)
        | is_core_compiler_mod clean_spec = (acc2 + "\n-- import " + clean_spec + "\n", seen2)
        | otherwise = (acc2 + "\n@__rg_mod_exit__\n" + (mod_alias_marker alias mname) + "-- import " + clean_spec + "\n", seen2)

fn :: child pdir for spec String String => String
      child pdir for spec pdir spec =
        s1 = strip_mod_ext spec
        s2 = norm_spec_path s1
        sl = last_slash_idx s2 0 (str_len s2) (0 - 1)
        child_pdir_step pdir s2 sl

fn :: child pdir step String String Int => String
      child pdir step pdir _ sl
        | sl <= 0 = pdir
      child pdir step pdir s2 sl =
        pdir + "/" + (str_slice s2 0 sl)

fn :: append own rg local String String String String String [String] => String [String]
      append own rg local _ clean_spec alias "" acc seen1 =
        (acc + (format_deferred_import clean_spec alias), seen1)
      append own rg local pdir clean_spec alias local_rg acc seen1
        | is_core_compiler_mod clean_spec =
          sub_pdir = child_pdir_for_spec pdir clean_spec
          res = scan_own_rg_lines sub_pdir local_rg 0 (str_len local_rg) 0 0 acc seen1
          append_own_rg_after_local clean_spec clean_spec alias res
        | otherwise =
          mname = mod_name_of_spec clean_spec
          sub_pdir = child_pdir_for_spec pdir clean_spec
          acc_enter = acc + "\n@__rg_mod_enter__ " + mname + "\n"
          res = scan_own_rg_lines sub_pdir local_rg 0 (str_len local_rg) 0 0 acc_enter seen1
          append_own_rg_after_local clean_spec mname alias res

fn :: append own rg import pair String String (String, String) String [String] => String [String]
      append own rg import pair pdir s (clean_spec, alias) acc seen
        | (str_in_seen_list clean_spec seen) OR (str_contains s ("module :: " + clean_spec)) =
          (acc + (mod_alias_marker alias (mod_name_of_spec clean_spec)), seen)
        | has_same_dir_rglib pdir clean_spec = (acc + (format_deferred_import clean_spec alias), [clean_spec] :: seen)
        | otherwise =
          local_rg = read_local_rg_module pdir clean_spec
          append_own_rg_local pdir clean_spec alias local_rg acc ([clean_spec] :: seen)

fn :: scan own rg lines cont String String Int Int (String, [String]) => String [String]
      scan own rg lines cont pdir s next_pos len (acc2, seen2) =
        scan_own_rg_lines pdir s next_pos len next_pos next_pos acc2 seen2

fn :: scan own rg lines String String Int Int Int Int String [String] => String [String]
      scan own rg lines pdir s pos len line_start chunk_start acc seen
        | pos >= len AND line_start >= len =
          (acc + (str_slice s chunk_start len), seen)
        | pos >= len AND (line_starts_with_import s line_start len) =
          before = acc + (str_slice s chunk_start line_start)
          line = rglib_trim (str_slice s line_start len)
          raw_spec = str_slice line 7 (str_len line)
          append_own_rg_import_pair pdir s (parse_import_spec_line raw_spec) before seen
        | pos >= len =
          (acc + (str_slice s chunk_start len), seen)
        | (str_char_at s pos) == 10 AND (line_starts_with_import s line_start pos) =
          before = acc + (str_slice s chunk_start line_start)
          line = rglib_trim (str_slice s line_start pos)
          raw_spec = str_slice line 7 (str_len line)
          res = append_own_rg_import_pair pdir s (parse_import_spec_line raw_spec) before seen
          scan_own_rg_lines_cont pdir s (pos + 1) len res
        | (str_char_at s pos) == 10 =
          scan_own_rg_lines pdir s (pos + 1) len (pos + 1) chunk_start acc seen
        | otherwise =
          scan_own_rg_lines pdir s (pos + 1) len line_start chunk_start acc seen

fn :: load rg own source raw String String => String
      load rg own source raw _ "" = ""
      load rg own source raw input_path raw_file =
        pdir = rglib_dir_of input_path 0 (str_len input_path) (0 - 1)
        fst_str_seen (scan_own_rg_lines pdir raw_file 0 (str_len raw_file) 0 0 "" [])

fn :: load rg own source String => String
      load rg own source input_path =
        raw_file = read_file input_path
        load_rg_own_source_raw input_path raw_file

fn :: join lib and base String String => String
      join lib and base ""     base_src =  base_src
      join lib and base lib_pr base_src =  lib_pr + "\n@__rg_user_src__\n" + base_src

fn :: load rg with libs String     => String
      load rg with libs input_path =
        base_src = load_rg_own_source input_path
        pdir = rglib_dir_of input_path 0 (str_len input_path) (0 - 1)
        lib_prefix = scan_rglib_imports pdir base_src 0 (str_len base_src) 0 "" []
        join_lib_and_base lib_prefix base_src

-- ── Scoped Module Namespace Resolution ──────────────────────

type RScopedFn = ScopedFn String Bool RFnDef
type RScopedType = ScopedType String Bool RTypeDef
type RModAlias = ModAlias String String

fn :: cur mod of stack [String] => String
      cur mod of stack []       =  ""
      cur mod of stack (m:_)    =  m

fn :: pop mod stack [String] => [String]
      pop mod stack []       =  []
      pop mod stack (_:ms)   =  ms

fn :: set explicit mod String => [String]
      set explicit mod "main" =  []
      set explicit mod "root" =  []
      set explicit mod ""     =  []
      set explicit mod mname  =  [mname]

fn :: parse inline import alias [RToken] [RModAlias] => [RModAlias]
      parse inline import alias ((TokIdent spec):(TokIdent "as"):(TokIdent al):_) aliases =
        aliases :: [ModAlias al (mod_name_of_spec spec)]
      parse inline import alias ((TokStr spec):(TokIdent "as"):(TokIdent al):_) aliases =
        aliases :: [ModAlias al (mod_name_of_spec spec)]
      parse inline import alias _ aliases = aliases

fn :: lookup str map [RModAlias] String => String
      lookup str map [] _ = ""
      lookup str map ((ModAlias k v):rest) target
        | k == target = v
        | otherwise = lookup_str_map rest target

fn :: expand mod alias String [RModAlias] => String
      expand mod alias s aliases
        | NOT (str_contains s ".") = s
        | otherwise =
          pfx = ident_first_prefix s
          rest = ident_after_first_dot s
          target = lookup_str_map aliases pfx
          expand_mod_alias_step s target rest

fn :: expand mod alias step String String String => String
      expand mod alias step s "" _ = s
      expand mod alias step _ target rest = target + "." + rest

fn :: is single variant alias RTypeDef [RScopedType] => Bool
      is single variant alias (TypeDef _ ((TypeVariant vname []):[]) []) s_tys =
        (str_contains vname ".") OR (scoped_types_have_name s_tys vname)
      is single variant alias _ _ = False

fn :: scoped types have name [RScopedType] String => Bool
      scoped types have name [] _ = False
      scoped types have name ((ScopedType _ _ (TypeDef tname _ _)):ts) target
        | tname == target = True
        | otherwise = scoped_types_have_name ts target

fn :: has any scoped mod [RScopedFn] [RScopedType] [RModAlias] => Bool
      has any scoped mod _ _ (_:_) = True
      has any scoped mod ((ScopedFn m _ _):fs) tys aliases
        | m != "" = True
        | otherwise = has_any_scoped_mod fs tys aliases
      has any scoped mod [] ((ScopedType m _ tdef):ts) aliases
        | m != "" OR (is_single_variant_alias tdef ts) = True
        | otherwise = has_any_scoped_mod [] ts aliases
      has any scoped mod [] [] [] = False

fn :: add unique seen String [String] => [String]
      add unique seen s seen
        | str_in_seen_list s seen = seen
        | otherwise = [s] :: seen

fn :: other scoped type has name [RScopedType] String String => Bool
      other scoped type has name [] _ _ = False
      other scoped type has name ((ScopedType m2 False (TypeDef tname2 _ _)):ts) m1 target
        | tname2 == target AND m2 != m1 = True
        | otherwise = other_scoped_type_has_name ts m1 target
      other scoped type has name (_:ts) m1 target =
        other_scoped_type_has_name ts m1 target

fn :: collect collided types [RScopedType] [RScopedType] [String] => [String]
      collect collided types [] _ acc = acc
      collect collided types ((ScopedType m True _):ts) all_ts acc =
        collect_collided_types ts all_ts acc
      collect collided types ((ScopedType m False (TypeDef tname _ _)):ts) all_ts acc
        | other_scoped_type_has_name all_ts m tname =
          collect_collided_types ts all_ts (add_unique_seen tname acc)
        | otherwise = collect_collided_types ts all_ts acc

fn :: fields have name [RField] String => Bool
      fields have name [] _ = False
      fields have name ((TypeField fname _):fs) target
        | fname == target = True
        | otherwise = fields_have_name fs target

fn :: other mod has field [RScopedType] String String => Bool
      other mod has field [] _ _ = False
      other mod has field ((ScopedType m2 _ (TypeDef _ _ fs)):ts) m1 target
        | m2 != m1 AND (fields_have_name fs target) = True
        | otherwise = other_mod_has_field ts m1 target

fn :: collect fields collided from list [RField] String [RScopedType] [String] => [String]
      collect fields collided from list [] _ _ acc = acc
      collect fields collided from list ((TypeField fname _):fs) m all_ts acc
        | other_mod_has_field all_ts m fname =
          collect_fields_collided_from_list fs m all_ts (add_unique_seen fname acc)
        | otherwise = collect_fields_collided_from_list fs m all_ts acc

fn :: collect collided fields [RScopedType] [RScopedType] [String] => [String]
      collect collided fields [] _ acc = acc
      collect collided fields ((ScopedType m _ (TypeDef _ _ fs)):ts) all_ts acc =
        acc1 = collect_fields_collided_from_list fs m all_ts acc
        collect_collided_fields ts all_ts acc1

fn :: other mod has fn [RScopedFn] String String => Bool
      other mod has fn [] _ _ = False
      other mod has fn ((ScopedFn m2 _ (FnDef fname2 _ _ _)):fs) m1 target
        | fname2 == target AND m2 != m1 = True
        | otherwise = other_mod_has_fn fs m1 target

fn :: is special top fn String => Bool
      is special top fn "main" = True
      is special top fn "__syntax_error__" = True
      is special top fn "__unresolved_import__" = True
      is special top fn _ = False

fn :: collect collided fns [RScopedFn] [RScopedFn] [String] => [String]
      collect collided fns [] _ acc = acc
      collect collided fns ((ScopedFn m _ (FnDef fname _ _ _)):fs) all_fs acc
        | (NOT (is_special_top_fn fname)) AND (other_mod_has_fn all_fs m fname) =
          collect_collided_fns fs all_fs (add_unique_seen fname acc)
        | otherwise = collect_collided_fns fs all_fs acc

fn :: variants have ctor [RVariant] String => Bool
      variants have ctor [] _ = False
      variants have ctor ((TypeVariant c _):vs) target
        | c == target = True
        | otherwise = variants_have_ctor vs target

fn :: count ctor in types [RScopedType] String => Int
      count ctor in types [] _ = 0
      count ctor in types ((ScopedType _ True _):ts) target = count_ctor_in_types ts target
      count ctor in types ((ScopedType _ False (TypeDef _ vs _)):ts) target
        | variants_have_ctor vs target = 1 + (count_ctor_in_types ts target)
        | otherwise = count_ctor_in_types ts target

fn :: count ctor in mod [RScopedType] String String => Int
      count ctor in mod [] _ _ = 0
      count ctor in mod ((ScopedType _ True _):ts) m target = count_ctor_in_mod ts m target
      count ctor in mod ((ScopedType m2 False (TypeDef _ vs _)):ts) m target
        | m2 == m AND (variants_have_ctor vs target) = 1 + (count_ctor_in_mod ts m target)
        | otherwise = count_ctor_in_mod ts m target

fn :: collect ctors collided from vars [RVariant] [RScopedType] [String] => [String]
      collect ctors collided from vars [] _ acc = acc
      collect ctors collided from vars ((TypeVariant c _):vs) all_ts acc
        | (count_ctor_in_types all_ts c) > 1 =
          collect_ctors_collided_from_vars vs all_ts (add_unique_seen c acc)
        | otherwise = collect_ctors_collided_from_vars vs all_ts acc

fn :: collect collided ctors [RScopedType] [RScopedType] [String] => [String]
      collect collided ctors [] _ acc = acc
      collect collided ctors ((ScopedType _ True _):ts) all_ts acc = collect_collided_ctors ts all_ts acc
      collect collided ctors ((ScopedType _ False (TypeDef _ vs _)):ts) all_ts acc =
        acc1 = collect_ctors_collided_from_vars vs all_ts acc
        collect_collided_ctors ts all_ts acc1

fn :: canon scoped name String String [String] => String
      canon scoped name "" name _ = name
      canon scoped name m name collided
        | str_in_seen_list name collided = m + "." + name
        | otherwise = name

fn :: build base type map [RScopedType] [RScopedType] [String] => [RModAlias]
      build base type map [] _ _ = []
      build base type map ((ScopedType m _ tdef):ts) all_ts collided_types
        | is_single_variant_alias tdef all_ts = build_base_type_map ts all_ts collided_types
      build base type map ((ScopedType m _ (TypeDef tname _ _)):ts) all_ts collided_types =
        canon_t = canon_scoped_name m tname collided_types
        build_base_type_map_step m tname canon_t (build_base_type_map ts all_ts collided_types)

fn :: build base type map step String String String [RModAlias] => [RModAlias]
      build base type map step "" _ _ rest = rest
      build base type map step m tname canon_t rest = [ModAlias (m + "." + tname) canon_t] :: rest

fn :: resolve target type alias String String [RModAlias] [RModAlias] => String
      resolve target type alias m raw_target aliases base_tmap =
        t1 = expand_mod_alias raw_target aliases
        resolve_target_type_step m t1 base_tmap

fn :: resolve target type step String String [RModAlias] => String
      resolve target type step m t1 base_tmap
        | str_contains t1 "." =
          found = lookup_str_map base_tmap t1
          default_if_empty found t1
        | m != "" =
          found_m = lookup_str_map base_tmap (m + "." + t1)
          default_if_empty found_m t1
        | otherwise = t1

fn :: default if empty String String => String
      default if empty "" fallback = fallback
      default if empty val _ = val

fn :: build alias type map [RScopedType] [RScopedType] [String] [RModAlias] [RModAlias] => [RModAlias]
      build alias type map [] _ _ _ acc = acc
      build alias type map ((ScopedType m _ (TypeDef tname ((TypeVariant raw_target []):[]) [])):ts) all_ts collided_types aliases acc
        | is_single_variant_alias (TypeDef tname [TypeVariant raw_target []] []) all_ts =
          canon_target = resolve_target_type_alias m raw_target aliases acc
          acc1 = add_alias_type_entries m tname canon_target collided_types acc
          build_alias_type_map ts all_ts collided_types aliases acc1
      build alias type map (_:ts) all_ts collided_types aliases acc =
        build_alias_type_map ts all_ts collided_types aliases acc

fn :: add alias type entries String String String [String] [RModAlias] => [RModAlias]
      add alias type entries "" tname canon_target _ acc =
        [ModAlias tname canon_target] :: acc
      add alias type entries m tname canon_target collided_types acc
        | str_in_seen_list tname collided_types =
          [ModAlias (m + "." + tname) canon_target] :: acc
        | otherwise =
          [ModAlias (m + "." + tname) canon_target, ModAlias tname canon_target] :: acc

fn :: build variant ctor entries String String String [RVariant] [RScopedType] [String] => [RModAlias]
      build variant ctor entries _ _ _ [] _ _ = []
      build variant ctor entries m tname canon_t ((TypeVariant c _):vs) all_ts collided_ctors =
        rest = build_variant_ctor_entries m tname canon_t vs all_ts collided_ctors
        c_canon = canon_variant_ctor c canon_t collided_ctors
        e_base = [ModAlias (tname + "." + c) (canon_t + "." + c), ModAlias (canon_t + "." + c) (canon_t + "." + c)]
        build_variant_mod_entries m tname canon_t c c_canon (count_ctor_in_mod all_ts m c) (e_base :: rest)

fn :: canon variant ctor String String [String] => String
      canon variant ctor c canon_t collided_ctors
        | str_in_seen_list c collided_ctors = canon_t + "." + c
        | otherwise = c

fn :: build variant mod entries String String String String String Int [RModAlias] => [RModAlias]
      build variant mod entries "" _ _ _ _ _ acc = acc
      build variant mod entries m tname canon_t c c_canon mod_cnt acc
        | mod_cnt == 1 =
          [ModAlias (m + "." + tname + "." + c) (canon_t + "." + c), ModAlias (m + "." + c) c_canon] :: acc
        | otherwise =
          [ModAlias (m + "." + tname + "." + c) (canon_t + "." + c)] :: acc

fn :: build ctor map [RScopedType] [RScopedType] [String] [String] [RModAlias] => [RModAlias]
      build ctor map [] _ _ _ type_map = type_map
      build ctor map ((ScopedType _ _ tdef):ts) all_ts collided_types collided_ctors type_map
        | is_single_variant_alias tdef all_ts = build_ctor_map ts all_ts collided_types collided_ctors type_map
      build ctor map ((ScopedType m _ (TypeDef tname vs _)):ts) all_ts collided_types collided_ctors type_map =
        canon_t = canon_scoped_name m tname collided_types
        v_entries = build_variant_ctor_entries m tname canon_t vs all_ts collided_ctors
        v_entries :: (build_ctor_map ts all_ts collided_types collided_ctors type_map)

fn :: build field entries for mod String [RField] [String] => [RModAlias]
      build field entries for mod "" _ _ = []
      build field entries for mod _ [] _ = []
      build field entries for mod m ((TypeField fname _):fs) collided_fields =
        canon_f = canon_scoped_name m fname collided_fields
        [ModAlias (m + "." + fname) canon_f] :: (build_field_entries_for_mod m fs collided_fields)

fn :: build field map [RScopedType] [String] => [RModAlias]
      build field map [] _ = []
      build field map ((ScopedType m _ (TypeDef _ _ fs)):ts) collided_fields =
        (build_field_entries_for_mod m fs collided_fields) :: (build_field_map ts collided_fields)

fn :: build fn map [RScopedFn] [String] => [RModAlias]
      build fn map [] _ = []
      build fn map ((ScopedFn "" _ _):fs) collided_fns = build_fn_map fs collided_fns
      build fn map ((ScopedFn m _ (FnDef fname _ _ _)):fs) collided_fns =
        canon_fn = canon_scoped_name m fname collided_fns
        [ModAlias (m + "." + fname) canon_fn] :: (build_fn_map fs collided_fns)

fn :: is type ident char Int => Bool
      is type ident char c =
        (c >= 65 AND c <= 90) OR (c >= 97 AND c <= 122) OR (c >= 48 AND c <= 57) OR c == 95 OR c == 46

fn :: scan type ident end String Int Int => Int
      scan type ident end s pos len
        | pos >= len = pos
        | is_type_ident_char (str_char_at s pos) = scan_type_ident_end s (pos + 1) len
        | otherwise = pos

fn :: resolve one type ident String String [RModAlias] [RModAlias] => String
      resolve one type ident tok cur_mod aliases type_map
        | NOT (is_upper_ident tok) = tok
        | otherwise =
          t1 = expand_mod_alias tok aliases
          resolve_one_type_step t1 cur_mod type_map

fn :: resolve one type step String String [RModAlias] => String
      resolve one type step t1 cur_mod type_map
        | str_contains t1 "." = default_if_empty (lookup_str_map type_map t1) t1
        | cur_mod != "" =
          in_mod = lookup_str_map type_map (cur_mod + "." + t1)
          default_if_empty in_mod (default_if_empty (lookup_str_map type_map t1) t1)
        | otherwise = default_if_empty (lookup_str_map type_map t1) t1

fn :: rewrite type str loop String Int Int String [RModAlias] [RModAlias] String => String
      rewrite type str loop s pos len cur_mod aliases type_map acc
        | pos >= len = acc
        | is_type_ident_char (str_char_at s pos) =
          end_p = scan_type_ident_end s pos len
          tok = str_slice s pos end_p
          resolved = resolve_one_type_ident tok cur_mod aliases type_map
          rewrite_type_str_loop s end_p len cur_mod aliases type_map (acc + resolved)
        | otherwise =
          ch = str_slice s pos (pos + 1)
          rewrite_type_str_loop s (pos + 1) len cur_mod aliases type_map (acc + ch)

fn :: rewrite type str String String [RModAlias] [RModAlias] => String
      rewrite type str s cur_mod aliases type_map =
        rewrite_type_str_loop s 0 (str_len s) cur_mod aliases type_map ""

fn :: rewrite type str list [String] String [RModAlias] [RModAlias] => [String]
      rewrite type str list [] _ _ _ = []
      rewrite type str list (t:ts) cur_mod aliases type_map =
        [rewrite_type_str t cur_mod aliases type_map] :: (rewrite_type_str_list ts cur_mod aliases type_map)

fn :: resolve ctor ident String String [RModAlias] [RModAlias] => String
      resolve ctor ident c cur_mod aliases ctor_map =
        c1 = expand_mod_alias c aliases
        resolve_ctor_ident_step c1 cur_mod ctor_map

fn :: resolve ctor ident step String String [RModAlias] => String
      resolve ctor ident step c1 cur_mod ctor_map
        | str_contains c1 "." = default_if_empty (lookup_str_map ctor_map c1) c1
        | cur_mod != "" =
          in_mod = lookup_str_map ctor_map (cur_mod + "." + c1)
          default_if_empty in_mod (default_if_empty (lookup_str_map ctor_map c1) c1)
        | otherwise = default_if_empty (lookup_str_map ctor_map c1) c1

fn :: rewrite pat RPattern String [RModAlias] [RModAlias] => RPattern
      rewrite pat (PatCons h t) cur_mod aliases ctor_map =
        PatCons (rewrite_pat h cur_mod aliases ctor_map) (rewrite_pat t cur_mod aliases ctor_map)
      rewrite pat (PatTuple ps) cur_mod aliases ctor_map =
        PatTuple (rewrite_pat_list ps cur_mod aliases ctor_map)
      rewrite pat (PatCtor c ps) cur_mod aliases ctor_map =
        PatCtor (resolve_ctor_ident c cur_mod aliases ctor_map) (rewrite_pat_list ps cur_mod aliases ctor_map)
      rewrite pat p _ _ _ = p

fn :: rewrite pat list [RPattern] String [RModAlias] [RModAlias] => [RPattern]
      rewrite pat list [] _ _ _ = []
      rewrite pat list (p:ps) cur_mod aliases ctor_map =
        [rewrite_pat p cur_mod aliases ctor_map] :: (rewrite_pat_list ps cur_mod aliases ctor_map)

fn :: collect pat bound vars RPattern [String] => [String]
      collect pat bound vars (PatVar v) acc = [v] :: acc
      collect pat bound vars (PatSeqBind v) acc = [v] :: acc
      collect pat bound vars (PatCons h t) acc = collect_pat_bound_vars t (collect_pat_bound_vars h acc)
      collect pat bound vars (PatTuple ps) acc = collect_pat_list_bound_vars ps acc
      collect pat bound vars (PatCtor _ ps) acc = collect_pat_list_bound_vars ps acc
      collect pat bound vars _ acc = acc

fn :: collect pat list bound vars [RPattern] [String] => [String]
      collect pat list bound vars [] acc = acc
      collect pat list bound vars (p:ps) acc = collect_pat_list_bound_vars ps (collect_pat_bound_vars p acc)

fn :: collect where bound vars [RWhereBind] [String] => [String]
      collect where bound vars [] acc = acc
      collect where bound vars ((WhereBind _ v _):wbs) acc
        | v != "" = collect_where_bound_vars wbs ([v] :: acc)
        | otherwise = collect_where_bound_vars wbs acc

fn :: resolve lower ident String String [String] [RModAlias] [RModAlias] [RModAlias] => String
      resolve lower ident v cur_mod locals aliases fn_map field_map
        | str_in_seen_list v locals = v
        | otherwise =
          v1 = expand_mod_alias v aliases
          resolve_lower_ident_step v1 cur_mod fn_map field_map

fn :: resolve lower ident step String String [RModAlias] [RModAlias] => String
      resolve lower ident step v1 cur_mod fn_map field_map
        | str_contains v1 "." =
          in_fn = lookup_str_map fn_map v1
          in_fld = lookup_str_map field_map v1
          default_if_empty in_fn (default_if_empty in_fld v1)
        | cur_mod != "" =
          in_fn_m = lookup_str_map fn_map (cur_mod + "." + v1)
          in_fld_m = lookup_str_map field_map (cur_mod + "." + v1)
          default_if_empty in_fn_m (default_if_empty in_fld_m v1)
        | otherwise = v1

fn :: resolve field str String String [RModAlias] [RModAlias] => String
      resolve field str fname cur_mod aliases field_map =
        f1 = expand_mod_alias fname aliases
        resolve_field_str_step f1 cur_mod field_map

fn :: resolve field str step String String [RModAlias] => String
      resolve field str step f1 cur_mod field_map
        | str_contains f1 "." = default_if_empty (lookup_str_map field_map f1) f1
        | cur_mod != "" = default_if_empty (lookup_str_map field_map (cur_mod + "." + f1)) f1
        | otherwise = f1

fn :: lookup mod fn or field String String [RModAlias] [RModAlias] => String
      lookup mod fn or field m base fn_map field_map =
        key = m + "." + base
        in_fn = lookup_str_map fn_map key
        in_fld = lookup_str_map field_map key
        default_if_empty in_fn in_fld

fn :: try consume mod words String String [RExpr] [RModAlias] [RModAlias] => String [RExpr]
      try consume mod words m acc_base ((EVar w):rest) fn_map field_map
        | (is_lower_ident w) AND (NOT (str_contains w ".")) =
          cand = acc_base + "_" + w
          deeper = try_consume_mod_words m cand rest fn_map field_map
          select_mod_words m acc_base ((EVar w):rest) fn_map field_map deeper
      try consume mod words m acc_base args fn_map field_map =
        resolved = lookup_mod_fn_or_field m acc_base fn_map field_map
        (resolved, args)

fn :: select mod words String String [RExpr] [RModAlias] [RModAlias] (String, [RExpr]) => String [RExpr]
      select mod words m acc_base orig_args fn_map field_map ("", _) =
        (lookup_mod_fn_or_field m acc_base fn_map field_map, orig_args)
      select mod words _ _ _ _ _ deeper_match = deeper_match

fn :: rewrite rec update args [RExpr] String [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RExpr]
      rewrite rec update args [] _ _ _ _ _ _ = []
      rewrite rec update args ((EStr fname):val_e:rest) cur_mod locals aliases ctor_map fn_map field_map =
        f_canon = resolve_field_str fname cur_mod aliases field_map
        val_r = rewrite_expr val_e cur_mod locals aliases ctor_map fn_map field_map
        [EStr f_canon, val_r] :: (rewrite_rec_update_args rest cur_mod locals aliases ctor_map fn_map field_map)
      rewrite rec update args (e:rest) cur_mod locals aliases ctor_map fn_map field_map =
        [rewrite_expr e cur_mod locals aliases ctor_map fn_map field_map] :: (rewrite_rec_update_args rest cur_mod locals aliases ctor_map fn_map field_map)

fn :: collect lambda param strs [RExpr] [String] => [String]
      collect lambda param strs [] acc = acc
      collect lambda param strs (_:[]) acc = acc
      collect lambda param strs ((EStr p):rest) acc =
        collect_lambda_param_strs rest ((expand_lambda_param_names [p]) :: acc)
      collect lambda param strs (_:rest) acc =
        collect_lambda_param_strs rest acc

fn :: rewrite lambda args [RExpr] String [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RExpr]
      rewrite lambda args [] _ _ _ _ _ _ = []
      rewrite lambda args (body_e:[]) cur_mod locals aliases ctor_map fn_map field_map =
        [rewrite_expr body_e cur_mod locals aliases ctor_map fn_map field_map]
      rewrite lambda args (p:rest) cur_mod locals aliases ctor_map fn_map field_map =
        [p] :: (rewrite_lambda_args rest cur_mod locals aliases ctor_map fn_map field_map)

fn :: rewrite call expr String [RExpr] String [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => RExpr
      rewrite call expr "__lambda__" args cur_mod locals aliases ctor_map fn_map field_map =
        locals1 = collect_lambda_param_strs args locals
        ECall "__lambda__" (rewrite_lambda_args args cur_mod locals1 aliases ctor_map fn_map field_map)
      rewrite call expr "__record_update__" (base_e:rest) cur_mod locals aliases ctor_map fn_map field_map =
        base_r = rewrite_expr base_e cur_mod locals aliases ctor_map fn_map field_map
        ECall "__record_update__" ([base_r] :: (rewrite_rec_update_args rest cur_mod locals aliases ctor_map fn_map field_map))
      rewrite call expr fn_name args cur_mod locals aliases ctor_map fn_map field_map
        | is_upper_ident fn_name =
          ECall (resolve_ctor_ident fn_name cur_mod aliases ctor_map) (rewrite_expr_list args cur_mod locals aliases ctor_map fn_map field_map)
        | str_in_seen_list fn_name locals =
          ECall fn_name (rewrite_expr_list args cur_mod locals aliases ctor_map fn_map field_map)
        | otherwise =
          fn1 = expand_mod_alias fn_name aliases
          args_r = rewrite_expr_list args cur_mod locals aliases ctor_map fn_map field_map
          rewrite_call_lower fn1 args_r cur_mod fn_map field_map

fn :: rewrite call lower String [RExpr] String [RModAlias] [RModAlias] => RExpr
      rewrite call lower fn1 args_r cur_mod fn_map field_map
        | str_contains fn1 "." =
          m = ident_mod_prefix fn1
          base = ident_base_name fn1
          finish_mod_call True fn1 args_r (try_consume_mod_words m base args_r fn_map field_map)
        | cur_mod != "" =
          finish_mod_call False fn1 args_r (try_consume_mod_words cur_mod fn1 args_r fn_map field_map)
        | otherwise = ECall fn1 args_r

fn :: finish mod call Bool String [RExpr] (String, [RExpr]) => RExpr
      finish mod call _ fn1 args_r ("", _) = ECall fn1 args_r
      finish mod call True _ _ (resolved_fn, rem_args) = ECall resolved_fn rem_args
      finish mod call False fn1 args_r (resolved_fn, rem_args)
        | str_contains resolved_fn "." = ECall resolved_fn rem_args
        | otherwise = ECall fn1 args_r

fn :: rewrite expr RExpr String [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => RExpr
      rewrite expr (EVar v) cur_mod locals aliases ctor_map fn_map field_map
        | is_upper_ident v = EVar (resolve_ctor_ident v cur_mod aliases ctor_map)
        | otherwise = EVar (resolve_lower_ident v cur_mod locals aliases fn_map field_map)
      rewrite expr (ENot inner) cur_mod locals aliases ctor_map fn_map field_map =
        ENot (rewrite_expr inner cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (EOut inner) cur_mod locals aliases ctor_map fn_map field_map =
        EOut (rewrite_expr inner cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (EBin bop l r) cur_mod locals aliases ctor_map fn_map field_map =
        EBin bop (rewrite_expr l cur_mod locals aliases ctor_map fn_map field_map) (rewrite_expr r cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (ECall fn_name args) cur_mod locals aliases ctor_map fn_map field_map =
        rewrite_call_expr fn_name args cur_mod locals aliases ctor_map fn_map field_map
      rewrite expr (EEcho args) cur_mod locals aliases ctor_map fn_map field_map =
        EEcho (rewrite_expr_list args cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (EStrInterp parts) cur_mod locals aliases ctor_map fn_map field_map =
        EStrInterp (rewrite_expr_list parts cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (EList elems) cur_mod locals aliases ctor_map fn_map field_map =
        EList (rewrite_expr_list elems cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (ETuple elems) cur_mod locals aliases ctor_map fn_map field_map =
        ETuple (rewrite_expr_list elems cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (ETensor elems) cur_mod locals aliases ctor_map fn_map field_map =
        ETensor (rewrite_expr_list elems cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (EEinsum es subs) cur_mod locals aliases ctor_map fn_map field_map =
        EEinsum (rewrite_expr_list es cur_mod locals aliases ctor_map fn_map field_map) subs
      rewrite expr (EHadamard bop l s1 r s2) cur_mod locals aliases ctor_map fn_map field_map =
        EHadamard bop (rewrite_expr l cur_mod locals aliases ctor_map fn_map field_map) s1 (rewrite_expr r cur_mod locals aliases ctor_map fn_map field_map) s2
      rewrite expr (EIndex base idxs) cur_mod locals aliases ctor_map fn_map field_map =
        EIndex (rewrite_expr base cur_mod locals aliases ctor_map fn_map field_map) (rewrite_expr_list idxs cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (EIndexAssign t idxs v) cur_mod locals aliases ctor_map fn_map field_map =
        EIndexAssign t (rewrite_expr_list idxs cur_mod locals aliases ctor_map fn_map field_map) (rewrite_expr v cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (ESeqSelect b m) cur_mod locals aliases ctor_map fn_map field_map =
        ESeqSelect (rewrite_expr b cur_mod locals aliases ctor_map fn_map field_map) m
      rewrite expr (EBlock stmts) cur_mod locals aliases ctor_map fn_map field_map =
        EBlock (rewrite_stmt_list stmts cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (EGuard guards) cur_mod locals aliases ctor_map fn_map field_map =
        EGuard (rewrite_guard_list guards cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (EWhere body binds) cur_mod locals aliases ctor_map fn_map field_map =
        locals1 = collect_where_bound_vars binds locals
        EWhere (rewrite_expr body cur_mod locals1 aliases ctor_map fn_map field_map) (rewrite_where_list binds cur_mod locals1 aliases ctor_map fn_map field_map)
      rewrite expr (EParPipe branches) cur_mod locals aliases ctor_map fn_map field_map =
        EParPipe (rewrite_expr_list branches cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (EWithCtx c v b) cur_mod locals aliases ctor_map fn_map field_map =
        EWithCtx c (rewrite_expr v cur_mod locals aliases ctor_map fn_map field_map) (rewrite_expr b cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr (EWithRegion q b) cur_mod locals aliases ctor_map fn_map field_map =
        EWithRegion q (rewrite_expr b cur_mod locals aliases ctor_map fn_map field_map)
      rewrite expr e _ _ _ _ _ _ = e

fn :: rewrite expr list [RExpr] String [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RExpr]
      rewrite expr list [] _ _ _ _ _ _ = []
      rewrite expr list (e:es) cur_mod locals aliases ctor_map fn_map field_map =
        [rewrite_expr e cur_mod locals aliases ctor_map fn_map field_map] :: (rewrite_expr_list es cur_mod locals aliases ctor_map fn_map field_map)

fn :: rewrite stmt list [RStmt] String [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RStmt]
      rewrite stmt list [] _ _ _ _ _ _ = []
      rewrite stmt list ((StmtLet v e):ss) cur_mod locals aliases ctor_map fn_map field_map =
        e1 = rewrite_expr e cur_mod locals aliases ctor_map fn_map field_map
        [StmtLet v e1] :: (rewrite_stmt_list ss cur_mod ([v] :: locals) aliases ctor_map fn_map field_map)
      rewrite stmt list ((StmtMut v e):ss) cur_mod locals aliases ctor_map fn_map field_map =
        e1 = rewrite_expr e cur_mod locals aliases ctor_map fn_map field_map
        [StmtMut v e1] :: (rewrite_stmt_list ss cur_mod ([v] :: locals) aliases ctor_map fn_map field_map)
      rewrite stmt list ((StmtExpr e):ss) cur_mod locals aliases ctor_map fn_map field_map =
        [StmtExpr (rewrite_expr e cur_mod locals aliases ctor_map fn_map field_map)] :: (rewrite_stmt_list ss cur_mod locals aliases ctor_map fn_map field_map)
      rewrite stmt list ((StmtIndexAssign t idxs e):ss) cur_mod locals aliases ctor_map fn_map field_map =
        [StmtIndexAssign t (rewrite_expr_list idxs cur_mod locals aliases ctor_map fn_map field_map) (rewrite_expr e cur_mod locals aliases ctor_map fn_map field_map)] :: (rewrite_stmt_list ss cur_mod locals aliases ctor_map fn_map field_map)

fn :: rewrite guard list [RGuard] String [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RGuard]
      rewrite guard list [] _ _ _ _ _ _ = []
      rewrite guard list ((GuardBranch c b):gs) cur_mod locals aliases ctor_map fn_map field_map =
        [GuardBranch (rewrite_expr c cur_mod locals aliases ctor_map fn_map field_map) (rewrite_expr b cur_mod locals aliases ctor_map fn_map field_map)] :: (rewrite_guard_list gs cur_mod locals aliases ctor_map fn_map field_map)

fn :: rewrite where list [RWhereBind] String [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RWhereBind]
      rewrite where list [] _ _ _ _ _ _ = []
      rewrite where list ((WhereBind e v idxs):wbs) cur_mod locals aliases ctor_map fn_map field_map =
        [WhereBind (rewrite_expr e cur_mod locals aliases ctor_map fn_map field_map) v idxs] :: (rewrite_where_list wbs cur_mod locals aliases ctor_map fn_map field_map)

fn :: rewrite fn cases [RFnCase] String [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RFnCase]
      rewrite fn cases [] _ _ _ _ _ = []
      rewrite fn cases ((FnCase pats guards body):cs) cur_mod aliases ctor_map fn_map field_map =
        pats1 = rewrite_pat_list pats cur_mod aliases ctor_map
        locals = collect_pat_list_bound_vars pats1 []
        guards1 = rewrite_guard_list guards cur_mod locals aliases ctor_map fn_map field_map
        body1 = rewrite_expr body cur_mod locals aliases ctor_map fn_map field_map
        [FnCase pats1 guards1 body1] :: (rewrite_fn_cases cs cur_mod aliases ctor_map fn_map field_map)

fn :: rewrite variants [RVariant] String [RModAlias] [RModAlias] => [RVariant]
      rewrite variants [] _ _ _ = []
      rewrite variants ((TypeVariant c args):vs) cur_mod aliases type_map =
        [TypeVariant c (rewrite_type_str_list args cur_mod aliases type_map)] :: (rewrite_variants vs cur_mod aliases type_map)

fn :: rewrite fields [RField] String [String] [RModAlias] [RModAlias] => [RField]
      rewrite fields [] _ _ _ _ = []
      rewrite fields ((TypeField fname fty):fs) cur_mod collided_fields aliases type_map =
        canon_f = canon_scoped_name cur_mod fname collided_fields
        [TypeField canon_f (rewrite_type_str fty cur_mod aliases type_map)] :: (rewrite_fields fs cur_mod collided_fields aliases type_map)

fn :: rewrite and merge types [RScopedType] [RScopedType] [String] [String] [RModAlias] [RModAlias] [RTypeDef] => [RTypeDef]
      rewrite and merge types [] _ _ _ _ _ acc = acc
      rewrite and merge types ((ScopedType _ _ tdef):ts) all_ts collided_types collided_fields aliases type_map acc
        | is_single_variant_alias tdef all_ts =
          rewrite_and_merge_types ts all_ts collided_types collided_fields aliases type_map acc
      rewrite and merge types ((ScopedType m True (TypeDef tname vs fs)):ts) all_ts collided_types collided_fields aliases type_map acc =
        canon_t = resolve_one_type_ident tname m aliases type_map
        vs1 = rewrite_variants vs m aliases type_map
        fs1 = rewrite_fields fs m collided_fields aliases type_map
        rewrite_and_merge_types ts all_ts collided_types collided_fields aliases type_map (merge_type_def acc (TypeDef canon_t vs1 fs1))
      rewrite and merge types ((ScopedType m False (TypeDef tname vs fs)):ts) all_ts collided_types collided_fields aliases type_map acc =
        canon_t = canon_scoped_name m tname collided_types
        vs1 = rewrite_variants vs m aliases type_map
        fs1 = rewrite_fields fs m collided_fields aliases type_map
        rewrite_and_merge_types ts all_ts collided_types collided_fields aliases type_map (merge_type_def acc (TypeDef canon_t vs1 fs1))

fn :: rewrite and merge fns [RScopedFn] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] [RModAlias] [RFnDef] => [RFnDef]
      rewrite and merge fns [] _ _ _ _ _ _ acc = acc
      rewrite and merge fns ((ScopedFn m in_lib (FnDef fname ps ret cs)):fs) collided_fns aliases type_map ctor_map fn_map field_map acc =
        canon_fn = canon_scoped_name m fname collided_fns
        ps1 = rewrite_type_str_list ps m aliases type_map
        ret1 = rewrite_type_str ret m aliases type_map
        cs1 = rewrite_fn_cases cs m aliases ctor_map fn_map field_map
        acc1 = merge_fn_def_scoped acc (FnDef canon_fn ps1 ret1 cs1) in_lib
        rewrite_and_merge_fns fs collided_fns aliases type_map ctor_map fn_map field_map acc1

fn :: merge plain scoped types [RScopedType] [RTypeDef] => [RTypeDef]
      merge plain scoped types [] acc = acc
      merge plain scoped types ((ScopedType _ _ tdef):ts) acc =
        merge_plain_scoped_types ts (merge_type_def acc tdef)

fn :: merge plain scoped fns [RScopedFn] [RFnDef] => [RFnDef]
      merge plain scoped fns [] acc = acc
      merge plain scoped fns ((ScopedFn _ in_lib fdef):fs) acc =
        merge_plain_scoped_fns fs (merge_fn_def_scoped acc fdef in_lib)

fn :: resolve scoped state [RScopedFn] [RScopedType] [RModAlias] => RProgram
      resolve scoped state s_fns s_tys aliases
        | NOT (has_any_scoped_mod s_fns s_tys aliases) =
          Program (merge_plain_scoped_fns s_fns []) (merge_plain_scoped_types s_tys [])
        | otherwise =
          collided_types = collect_collided_types s_tys s_tys []
          collided_fields = collect_collided_fields s_tys s_tys []
          collided_fns = collect_collided_fns s_fns s_fns []
          collided_ctors = collect_collided_ctors s_tys s_tys []
          base_tmap = build_base_type_map s_tys s_tys collided_types
          type_map = build_alias_type_map s_tys s_tys collided_types aliases base_tmap
          ctor_map = build_ctor_map s_tys s_tys collided_types collided_ctors type_map
          field_map = build_field_map s_tys collided_fields
          fn_map = build_fn_map s_fns collided_fns
          tys_out = rewrite_and_merge_types s_tys s_tys collided_types collided_fields aliases type_map []
          fns_out = rewrite_and_merge_fns s_fns collided_fns aliases type_map ctor_map fn_map field_map []
          Program fns_out tys_out

-- ── Top-Level Program Loop ──────────────────────────────────

fn :: tokens have user src marker [RToken] => Bool
      tokens have user src marker [] = False
      tokens have user src marker (TokAt:(TokIdent "__rg_user_src__"):_) = True
      tokens have user src marker (_:ts) = tokens_have_user_src_marker ts

fn :: line has colon colon [RToken]          => Bool
      line has colon colon []                =  False
      line has colon colon (TokEof:_)        =  False
      line has colon colon (TokNewline:_)    =  False
      line has colon colon (TokColonColon:_) =  True
      line has colon colon (_:ts)            =  line_has_colon_colon ts

fn :: add scoped fndefs [RFnDef] String Bool [RScopedFn] => [RScopedFn]
      add scoped fndefs [] _ _ acc = acc
      add scoped fndefs (f:fs) cur_mod in_lib acc =
        add_scoped_fndefs fs cur_mod in_lib (acc :: [ScopedFn cur_mod in_lib f])

fn :: parse items after fn mod (RFnDef, [RToken]) [RScopedFn] [RScopedType] [RModAlias] [String] Bool => RProgram
      parse items after fn mod (fdef, rest) s_fns s_tys aliases mod_stack in_lib =
        cur_mod = cur_mod_of_stack mod_stack
        parse_items_mod rest (s_fns :: [ScopedFn cur_mod in_lib fdef]) s_tys aliases mod_stack in_lib

fn :: parse items after fndefs mod ([RFnDef], [RToken]) [RScopedFn] [RScopedType] [RModAlias] [String] Bool => RProgram
      parse items after fndefs mod (new_fns, rest) s_fns s_tys aliases mod_stack in_lib =
        cur_mod = cur_mod_of_stack mod_stack
        parse_items_mod rest (add_scoped_fndefs new_fns cur_mod in_lib s_fns) s_tys aliases mod_stack in_lib

fn :: parse items after type mod Bool (RTypeDef, [RToken]) [RScopedFn] [RScopedType] [RModAlias] [String] Bool => RProgram
      parse items after type mod is_exp (tdef, rest) s_fns s_tys aliases mod_stack in_lib =
        cur_mod = cur_mod_of_stack mod_stack
        parse_items_mod rest s_fns (s_tys :: [ScopedType cur_mod is_exp tdef]) aliases mod_stack in_lib

fn :: parse items mod [RToken] [RScopedFn] [RScopedType] [RModAlias] [String] Bool => RProgram
      parse items mod []                 s_fns s_tys aliases _         _      =  resolve_scoped_state s_fns s_tys aliases
      parse items mod (TokEof:_)         s_fns s_tys aliases _         _      =  resolve_scoped_state s_fns s_tys aliases
      parse items mod (TokNewline:rest)  s_fns s_tys aliases mod_stack in_lib =  parse_items_mod rest s_fns s_tys aliases mod_stack in_lib
      parse items mod (TokAt:(TokIdent "__rg_user_src__"):rest) s_fns s_tys aliases _ _ =
        parse_items_mod (skip_to_newline rest) s_fns s_tys aliases [] False
      parse items mod (TokAt:(TokIdent "__rg_mod_enter__"):(TokIdent mname):rest) s_fns s_tys aliases mod_stack in_lib =
        parse_items_mod (skip_to_newline rest) s_fns s_tys aliases ([mname] :: mod_stack) in_lib
      parse items mod (TokAt:(TokIdent "__rg_mod_exit__"):rest) s_fns s_tys aliases mod_stack in_lib =
        parse_items_mod (skip_to_newline rest) s_fns s_tys aliases (pop_mod_stack mod_stack) in_lib
      parse items mod (TokAt:(TokIdent "__rg_mod_alias__"):(TokIdent al):(TokIdent target):rest) s_fns s_tys aliases mod_stack in_lib =
        parse_items_mod (skip_to_newline rest) s_fns s_tys (aliases :: [ModAlias al target]) mod_stack in_lib
      parse items mod (TokAt:rest)       s_fns s_tys aliases mod_stack in_lib =
        parse_items_mod (skip_to_newline rest) s_fns s_tys aliases mod_stack in_lib
      parse items mod ((TokIdent "RGC1"):rest) s_fns s_tys aliases mod_stack in_lib =
        parse_items_mod (skip_to_newline rest) s_fns s_tys aliases mod_stack in_lib
      parse items mod ((TokIdent "module"):TokColonColon:(TokIdent mname):rest) s_fns s_tys aliases _ in_lib =
        parse_items_mod (skip_to_newline rest) s_fns s_tys aliases (set_explicit_mod mname) in_lib
      parse items mod (TokImport:rest)   s_fns s_tys aliases mod_stack in_lib =
        parse_items_mod (skip_to_newline rest) s_fns s_tys (parse_inline_import_alias rest aliases) mod_stack in_lib
      parse items mod (TokFn:rest)       s_fns s_tys aliases mod_stack in_lib =
        f_res = parse_fn_decl ([TokFn] :: rest)
        parse_items_after_fn_mod f_res s_fns s_tys aliases mod_stack in_lib
      parse items mod (TokOp:rest)       s_fns s_tys aliases mod_stack in_lib =
        o_res = parse_op_decl ([TokOp] :: rest)
        parse_items_after_fn_mod o_res s_fns s_tys aliases mod_stack in_lib
      parse items mod (TokHardware:rest) s_fns s_tys aliases mod_stack in_lib =
        hw_res = parse_hardware_decl ([TokHardware] :: rest)
        parse_items_after_fndefs_mod hw_res s_fns s_tys aliases mod_stack in_lib
      parse items mod (TokType:(TokIdent name):rest) s_fns s_tys aliases mod_stack in_lib
        | (is_upper_ident name) AND (has_type_params_then_eq rest) =
          t_res = parse_type_decl ([TokType, TokIdent name] :: rest)
          parse_items_after_type_mod False t_res s_fns s_tys aliases mod_stack in_lib
      parse items mod ((TokIdent "expand"):TokType:(TokIdent name):rest) s_fns s_tys aliases mod_stack in_lib
        | (is_upper_ident name) AND (has_type_params_then_eq rest) =
          t_res = parse_type_decl ([TokType, TokIdent name] :: rest)
          parse_items_after_type_mod True t_res s_fns s_tys aliases mod_stack in_lib
      parse items mod ts                 s_fns s_tys aliases mod_stack in_lib
        | (NOT (line_has_colon_colon ts)) AND (line_has_fat_arrow ts) =
          parse_items_after_fn_mod (parse_bare_decl ts) s_fns s_tys aliases mod_stack in_lib
        | otherwise =
          err_fn = FnDef "__syntax_error__" [] "Int" [FnCase [] [] (ECall "__syntax_error__" [EStr "unknown or invalid top-level declaration"])]
          cur_mod = cur_mod_of_stack mod_stack
          parse_items_mod (skip_to_newline (tok_tail ts)) (s_fns :: [ScopedFn cur_mod in_lib err_fn]) s_tys aliases mod_stack in_lib

fn :: parse items [RToken] [RFnDef] [RTypeDef] => RProgram
      parse items toks     _        _          =
        parse_items_mod toks [] [] [] [] (tokens_have_user_src_marker toks)

fn :: is catchall pat RPattern   => Bool
      is catchall pat PatWild    =  True
      is catchall pat (PatVar _) =  True
      is catchall pat _          =  False

fn :: all catchall pats [RPattern] => Bool
      all catchall pats []         =  True
      all catchall pats (p:ps)
        | is_catchall_pat p = all_catchall_pats ps
        | otherwise = False

fn :: is catchall case RFnCase            => Bool
      is catchall case (FnCase [] _ _)    =  False
      is catchall case (FnCase pats [] _) =  all_catchall_pats pats
      is catchall case (FnCase _ _ _)     =  False

fn :: filter specific cases [RFnCase] => [RFnCase]
      filter specific cases []        =  []
      filter specific cases (c:cs)
        | is_catchall_case c = filter_specific_cases cs
        | otherwise = [c] :: (filter_specific_cases cs)

fn :: filter catchall cases [RFnCase] => [RFnCase]
      filter catchall cases []        =  []
      filter catchall cases (c:cs)
        | is_catchall_case c = [c] :: (filter_catchall_cases cs)
        | otherwise = filter_catchall_cases cs

fn :: pat list adt ctor [RPattern] => String
      pat list adt ctor []         =  ""
      pat list adt ctor ((PatCtor ctor _):_) = ctor
      pat list adt ctor (_:ps)     =  pat_list_adt_ctor ps

fn :: cases have adt ctor [RFnCase] String => Bool
      cases have adt ctor [] _ = False
      cases have adt ctor ((FnCase pats _ _):cs) target
        | (pat_list_adt_ctor pats) == target = True
        | otherwise = cases_have_adt_ctor cs target

fn :: filter new extension cases [RFnCase] [RFnCase] => [RFnCase]
      filter new extension cases _ [] = []
      filter new extension cases old_cs ((FnCase pats guards body):cs) =
        ctor = pat_list_adt_ctor pats
        filter_new_extension_step old_cs ctor (FnCase pats guards body) cs

fn :: filter new extension step [RFnCase] String RFnCase [RFnCase] => [RFnCase]
      filter new extension step old_cs ctor c cs
        | ctor != "" AND (NOT (cases_have_adt_ctor old_cs ctor)) = [c] :: (filter_new_extension_cases old_cs cs)
        | otherwise = filter_new_extension_cases old_cs cs

fn :: merge fn cases [RFnCase] [RFnCase] => [RFnCase]
      merge fn cases old_cs    new_cs    =
        ext_cs = filter_new_extension_cases old_cs new_cs
        (filter_specific_cases old_cs) :: (filter_specific_cases ext_cs) :: (filter_catchall_cases ext_cs) :: (filter_catchall_cases old_cs)

fn :: has variant ctor [RVariant] String => Bool
      has variant ctor []         _      =  False
      has variant ctor ((TypeVariant ctor _):vs) target
        | ctor == target = True
        | otherwise = has_variant_ctor vs target

fn :: filter new variants [RVariant] [RVariant] => [RVariant]
      filter new variants _          []         =  []
      filter new variants old_vs     ((TypeVariant ctor args):vs)
        | has_variant_ctor old_vs ctor = filter_new_variants old_vs vs
        | otherwise = [TypeVariant ctor args] :: (filter_new_variants old_vs vs)

fn :: has field name [RField] String => Bool
      has field name []       _      =  False
      has field name ((TypeField fname _):fs) target
        | fname == target = True
        | otherwise = has_field_name fs target

fn :: filter new fields [RField] [RField] => [RField]
      filter new fields _        []       =  []
      filter new fields old_fs   ((TypeField fname fty):fs)
        | has_field_name old_fs fname = filter_new_fields old_fs fs
        | otherwise = [TypeField fname fty] :: (filter_new_fields old_fs fs)

fn :: str list same [String] [String] => Bool
      str list same []       []       =  True
      str list same (a:as)   (b:bs)
        | a == b = str_list_same as bs
        | otherwise = False
      str list same _        _        =  False

fn :: has any fn case [RFnCase] => Bool
      has any fn case []        =  False
      has any fn case (_:_)     =  True

fn :: is adt ext fndef [String] String [RFnCase] [String] String [RFnCase] => Bool
      is adt ext fndef old_ps old_ret old_cs new_ps new_ret new_cs =
        (str_list_same old_ps new_ps) AND (old_ret == new_ret) AND (has_any_fn_case (filter_new_extension_cases old_cs new_cs))

fn :: has extensible fn def [RFnDef] RFnDef => Bool
      has extensible fn def [] _ = False
      has extensible fn def ((FnDef k old_ps old_ret old_cs):fs) (FnDef target new_ps new_ret new_cs)
        | k == target = is_adt_ext_fndef old_ps old_ret old_cs new_ps new_ret new_cs
        | otherwise = has_extensible_fn_def fs (FnDef target new_ps new_ret new_cs)

fn :: update fn def [RFnDef] RFnDef => [RFnDef]
      update fn def []       _      =  []
      update fn def ((FnDef k old_ps old_ret old_cs):fs) (FnDef target new_ps new_ret new_cs)
        | k == target = [FnDef k old_ps old_ret (merge_fn_cases old_cs new_cs)] :: (update_fn_def fs (FnDef target new_ps new_ret new_cs))
        | otherwise = [FnDef k old_ps old_ret old_cs] :: (update_fn_def fs (FnDef target new_ps new_ret new_cs))

fn :: cases have any adt ctor [RFnCase] => Bool
      cases have any adt ctor [] = False
      cases have any adt ctor ((FnCase pats _ _):cs)
        | (pat_list_adt_ctor pats) != "" = True
        | otherwise = cases_have_any_adt_ctor cs

fn :: has fn def name [RFnDef] String => Bool
      has fn def name [] _ = False
      has fn def name ((FnDef k _ _ _):fs) target
        | k == target = True
        | otherwise = has_fn_def_name fs target

fn :: merge fn def scoped [RFnDef] RFnDef Bool => [RFnDef]
      merge fn def scoped fns (FnDef name ps ret cs) in_lib
        | (cases_have_any_adt_ctor cs) AND (has_extensible_fn_def fns (FnDef name ps ret cs)) = update_fn_def fns (FnDef name ps ret cs)
        | in_lib AND (name != "__unresolved_import__") AND (name != "__syntax_error__") AND (has_fn_def_name fns name) = fns
        | otherwise = fns :: [FnDef name ps ret cs]

fn :: merge fn def [RFnDef] RFnDef => [RFnDef]
      merge fn def fns      fdef   =  merge_fn_def_scoped fns fdef False

fn :: has type def [RTypeDef] String => Bool
      has type def []         _      =  False
      has type def ((TypeDef k _ _):ts) target
        | k == target = True
        | otherwise = has_type_def ts target

fn :: update type def [RTypeDef] RTypeDef => [RTypeDef]
      update type def []         _        =  []
      update type def ((TypeDef k old_vs old_fs):ts) (TypeDef target new_vs new_fs)
        | k == target = [TypeDef k (old_vs :: (filter_new_variants old_vs new_vs)) (old_fs :: (filter_new_fields old_fs new_fs))] :: (update_type_def ts (TypeDef target new_vs new_fs))
        | otherwise = [TypeDef k old_vs old_fs] :: (update_type_def ts (TypeDef target new_vs new_fs))

fn :: merge type def [RTypeDef] RTypeDef => [RTypeDef]
      merge type def tys        (TypeDef name vs fs)
        | has_type_def tys name = update_type_def tys (TypeDef name vs fs)
        | otherwise = tys :: [TypeDef name vs fs]

fn :: parse tokens [RToken] => RProgram
      parse tokens toks     =  normalize_program (parse_items toks [] [])

fn :: count fndef list [RFnDef] => Int
      count fndef list []       =  0
      count fndef list (_:xs)   =  1 + (count_fndef_list xs)

fn :: count fn defs RProgram        => Int
      count fn defs (Program fns _) =  count_fndef_list fns

fn :: count type defs RProgram        => Int
      count type defs (Program _ tys) =  count_typedef_list tys

fn :: count typedef list [RTypeDef] => Int
      count typedef list []         =  0
      count typedef list (_:xs)     =  1 + (count_typedef_list xs)
