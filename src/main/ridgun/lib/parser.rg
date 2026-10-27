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
-- @implements FR-COMP-014
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
      skip newlines (TokNewline:ts) =  skip newlines ts
      skip newlines ts              =  ts

fn :: skip to newline [RToken]        => [RToken]
      skip to newline []              =  []
      skip to newline (TokEof:_)      =  [TokEof]
      skip to newline (TokNewline:ts) =  ts
      skip to newline (_:ts)          =  skip to newline ts

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
        | is upper ident p = has type params then eq rest
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
        | (is upper ident name) AND (has type params then eq rest) = True
      is top decl start ((TokIdent "expand"):TokType:(TokIdent name):rest)
        | (is upper ident name) AND (has type params then eq rest) = True
      is top decl start (TokType:_)     =  False
      is top decl start ts              =  is top keyword (tok head ts)

fn :: last dot idx String Int Int Int => Int
      last dot idx s pos len last_d
        | pos >= len = last_d
        | (str char at s pos) == 46 = last dot idx s (pos + 1) len pos
        | otherwise = last dot idx s (pos + 1) len last_d

fn :: first dot idx String Int Int => Int
      first dot idx s pos len
        | pos >= len = 0 - 1
        | (str char at s pos) == 46 = pos
        | otherwise = first dot idx s (pos + 1) len

fn :: ident base start String => Int
      ident base start s =
        d = last dot idx s 0 (str len s) (0 - 1)
        d + 1

fn :: ident base slice String Int => String
      ident base slice s d
        | d < 0 = s
        | otherwise = str slice s (d + 1) (str len s)

fn :: ident base name String => String
      ident base name s =
        d = last dot idx s 0 (str len s) (0 - 1)
        ident base slice s d

fn :: ident mod prefix slice String Int => String
      ident mod prefix slice _ d
        | d <= 0 = ""
      ident mod prefix slice s d = str slice s 0 d

fn :: ident mod prefix String => String
      ident mod prefix s =
        d = last dot idx s 0 (str len s) (0 - 1)
        ident mod prefix slice s d

fn :: ident first prefix String => String
      ident first prefix s =
        d = first dot idx s 0 (str len s)
        ident mod prefix slice s d

fn :: ident after first dot String => String
      ident after first dot s =
        d = first dot idx s 0 (str len s)
        ident base slice s d

fn :: encode literal underscores loop String Int Int String => String
      encode literal underscores loop s pos len acc
        | pos >= len = acc
        | (str char at s pos) == 95 = encode literal underscores loop s (pos + 1) len (acc + "__U__")
        | otherwise = encode literal underscores loop s (pos + 1) len (acc + (str slice s pos (pos + 1)))

fn :: encode literal underscores String => String
      encode literal underscores s
        | not (str contains s "_") = s
        | (str starts with s "__") or (str starts with s ":") = s
        | otherwise = encode literal underscores loop s 0 (str len s) ""

fn :: decode literal underscores loop String Int Int String => String
      decode literal underscores loop s pos len acc
        | pos >= len = acc
        | (pos + 5) <= len and (str slice s pos (pos + 5)) == "__U__" = decode literal underscores loop s (pos + 5) len (acc + "_")
        | otherwise = decode literal underscores loop s (pos + 1) len (acc + (str slice s pos (pos + 1)))

fn :: decode literal underscores String => String
      decode literal underscores s
        | not (str contains s "__U__") = s
        | otherwise = decode literal underscores loop s 0 (str len s) ""

fn :: is upper ident String => Bool
      is upper ident s      =
        c = str char at s (ident base start s)
        c >= 65 AND c <= 90

fn :: is lower ident String => Bool
      is lower ident s      =
        c = str char at s (ident base start s)
        (c >= 97 AND c <= 122) OR c == 95 OR (str starts with s "||")

-- ── Subscript Extraction (A_ij -> ("A", "ij")) ──────────────

fn :: find underscore String Int Int => Int
      find underscore s      pos len
        | pos >= len = -1
        | (str char at s pos) == 95 = pos
        | otherwise = find underscore s (pos + 1) len

fn :: all lower ascii String Int Int => Bool
      all lower ascii s pos len
        | pos >= len = True
        | (str char at s pos) >= 97 AND (str char at s pos) <= 122 = all lower ascii s (pos + 1) len
        | otherwise = False

fn :: all einstein idx chars String Int Int => Bool
      all einstein idx chars s pos len
        | pos >= len = True
        | (str char at s pos) >= 105 and (str char at s pos) <= 108 = all einstein idx chars s (pos + 1) len
        | otherwise = False

fn :: is trailing underscore ident String => Bool
      is trailing underscore ident s      =
        len = str len s
        len > 1 and (str char at s (len - 1)) == 95

fn :: is subscript ident String => Bool
      is subscript ident s
        | str contains s "." = False
        | otherwise =
          u_idx = find underscore s 0 (str len s)
          check subscript parts s u_idx (str len s)

fn :: check subscript parts String Int Int => Bool
      check subscript parts s u_idx len
        | u_idx <= 0 or (u_idx + 1) >= len = False
        | (find underscore s (u_idx + 1) len) >= 0 = False
        | is upper ident s = all lower ascii s (u_idx + 1) len
        | (len - (u_idx + 1)) >= 2 and (len - (u_idx + 1)) <= 4 and (str slice s (u_idx + 1) len) != "kill" = all einstein idx chars s (u_idx + 1) len
        | otherwise = False

fn :: split subscript String => String String
      split subscript s      =
        u_idx = find underscore s 0 (str len s)
        (str slice s 0 u_idx, str slice s (u_idx + 1) (str len s))

-- ── Type String Parsing ─────────────────────────────────────

fn :: check variadic suffix (String, [RToken]) => String [RToken]
      check variadic suffix (base_ty, (TokEllipsis:rest)) = (base_ty + "...", rest)
      check variadic suffix res                =  res

fn :: parse tensor dims [RToken]          => String [RToken]
      parse tensor dims (TokRParen:rest)  =  ("", rest)
      parse tensor dims (TokNewline:rest) =  ("", rest)
      parse tensor dims (TokEof:rest)     =  ("", rest)
      parse tensor dims []                =  ("", [])
      parse tensor dims (TokComma:rest)   =  parse tensor dims rest
      parse tensor dims ((TokIdent d):rest) =
        more = parse tensor dims rest
        join tensor dim d more
      parse tensor dims ((TokInt n):rest) =
        more = parse tensor dims rest
        join tensor dim (int to str n) more
      parse tensor dims (_:rest)          =  parse tensor dims rest

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
        join tensor dim d more
      parse tensor bracket tail ((TokInt n):rest)  =
        more = parse tensor bracket tail rest
        join tensor dim (int to str n) more
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
        p = parse type tok rest
        check variadic suffix (parse type list rest p False)
      parse type tok (TokLParen:rest)   =
        check variadic suffix (parse type paren rest)
      parse type tok ((TokIdent s):TokLParen:rest)
        | s == "Tensor" or s == "Tensor_GPU" = check variadic suffix (finish tensor type (parse tensor dims rest))
        | otherwise = check variadic suffix (s, [TokLParen] :: rest)
      parse type tok ((TokIdent s):TokIdxLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = check variadic suffix (finish tensor type (parse tensor bracket dims rest))
      parse type tok ((TokIdent s):TokLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = check variadic suffix (finish tensor type (parse tensor bracket dims rest))
      parse type tok ((TokIdent s):rest) =
        check variadic suffix (s, rest)
      parse type tok (_:rest)           =  ("Int", rest)
      parse type tok []                 =  ("()", [])

fn :: parse type list rest (String, [RToken]) Bool => String [RToken]
      parse type list rest (acc, (TokComma:rest)) _ =
        p2 = parse type tok rest
        merge type list acc p2
      parse type list rest (acc, ((TokIdent s):rest)) is_tup
        | is upper ident s = merge type list acc (parse type tok ([TokIdent s] :: rest))
        | otherwise = finish type list acc ([TokIdent s] :: rest) is_tup
      parse type list rest (acc, (TokLBracket:rest)) _ =
        p2 = parse type tok ([TokLBracket] :: rest)
        merge type list acc p2
      parse type list rest (acc, (TokLParen:rest)) _ =
        p2 = parse type tok ([TokLParen] :: rest)
        merge type list acc p2
      parse type list rest (acc, (TokRBracket:rest)) is_tup = finish type list acc rest is_tup
      parse type list rest (acc, rest) is_tup = finish type list acc rest is_tup

fn :: merge type list String (String, [RToken]) => String [RToken]
      merge type list acc    (next_ty, rest)    =
        parse type list rest (acc + ", " + next_ty, rest) True

fn :: finish type list String [RToken] Bool => String [RToken]
      finish type list acc rest True = ("[(" + acc + ")]", rest)
      finish type list acc rest False = ("[" + acc + "]", rest)

fn :: parse type paren [RToken]         => String [RToken]
      parse type paren (TokRParen:rest) =  ("()", rest)
      parse type paren (TokLParen:TokRParen:TokFatArrow:rest) =
        merge type fn "__err_unit_fn_type__" (parse type tok rest)
      parse type paren (TokFatArrow:rest) =
        merge type fn "()" (parse type tok rest)
      parse type paren ((TokIdent s):rest)
        | (is lower ident s) AND (is paren lambda ([TokIdent s] :: rest) False) =
          ("__err_lower_fn_type__", skip to rparen rest 0)
      parse type paren ts               =
        p1 = parse type tok ts
        parse type tuple rest p1

fn :: skip to rparen [RToken] Int => [RToken]
      skip to rparen [] _ = []
      skip to rparen (TokEof:rest) _ = [TokEof] :: rest
      skip to rparen (TokNewline:rest) 0 = [TokNewline] :: rest
      skip to rparen (TokLParen:rest) d = skip to rparen rest (d + 1)
      skip to rparen (TokRParen:rest) 0 = rest
      skip to rparen (TokRParen:rest) d = skip to rparen rest (d - 1)
      skip to rparen (_:rest) d = skip to rparen rest d

fn :: parse type tuple rest (String, [RToken]) => String [RToken]
      parse type tuple rest (acc, (TokComma:rest)) =
        p2 = parse type tok rest
        merge type tuple acc p2
      parse type tuple rest (acc, (TokFatArrow:rest)) =
        p_ret = parse type tok rest
        merge type fn acc p_ret
      parse type tuple rest (acc, (TokArrow:rest)) =
        p_ret = parse type tok rest
        merge type fn acc p_ret
      parse type tuple rest (acc, ((TokIdent s):rest))
        | is upper ident s = merge type tuple acc (parse type tok ([TokIdent s] :: rest))
      parse type tuple rest (acc, (TokLBracket:rest)) =
        p2 = parse type tok ([TokLBracket] :: rest)
        merge type tuple acc p2
      parse type tuple rest (acc, (TokLParen:rest)) =
        p2 = parse type tok ([TokLParen] :: rest)
        merge type tuple acc p2
      parse type tuple rest (acc, (TokRParen:rest)) = ("(" + acc + ")", rest)
      parse type tuple rest (acc, rest)        =  ("(" + acc + ")", rest)

fn :: merge type fn String (String, [RToken]) => String [RToken]
      merge type fn acc    (ret_ty, (TokRParen:rest)) = ("(" + acc + " => " + ret_ty + ")", rest)
      merge type fn acc    (ret_ty, rest)     =  ("(" + acc + " => " + ret_ty + ")", rest)

fn :: merge type tuple String (String, [RToken]) => String [RToken]
      merge type tuple acc    (next_ty, rest)    =
        parse type tuple rest (acc + ", " + next_ty, rest)

fn :: parse return types [RToken] => String [RToken]
      parse return types ts       =
        p1 = parse type tok ts
        parse return types more p1 False

fn :: parse return types more (String, [RToken]) Bool => String [RToken]
      parse return types more (acc, (TokComma:rest)) _ =
        p2 = parse type tok rest
        merge return types acc p2
      parse return types more (acc, ((TokIdent s):rest)) is_tup
        | is upper ident s = merge return types acc (parse type tok ([TokIdent s] :: rest))
        | otherwise = finish return types acc ([TokIdent s] :: rest) is_tup
      parse return types more (acc, (TokLBracket:rest)) _ =
        p2 = parse type tok ([TokLBracket] :: rest)
        merge return types acc p2
      parse return types more (acc, (TokLParen:rest)) _ =
        p2 = parse type tok ([TokLParen] :: rest)
        merge return types acc p2
      parse return types more (acc, rest) is_tup = finish return types acc rest is_tup

fn :: merge return types String (String, [RToken]) => String [RToken]
      merge return types acc    (next_ty, rest)    =
        parse return types more (acc + ", " + next_ty, rest) True

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
        p1 = parse type tok ts
        parse param types cont p1

fn :: parse param types cont (String, [RToken]) => [String] [RToken]
      parse param types cont (ty, rest)         =
        p_more = parse param types rest
        prepend str ty p_more

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
        prepend pat (PatInt n) more
      parse tensor pat dims (TokStar:(TokIdent v):rest)
        | v == "_" = prepend pat PatWild (parse tensor pat dims rest)
        | otherwise = prepend pat (PatVar v) (parse tensor pat dims rest)
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
        finish tensor pat with inner rank_pat dim_pats (parse pattern ts)

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
        parse tensor pat after elem (parse type tok ts) has_paren

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
        | is subscript ident s = (PatVar (extract fst str (split subscript s)), rest)
        | (is upper ident s) and (str len s) > 1 = (PatCtor s [], rest)
        | otherwise = (PatVar s, rest)
      parse pattern (TokLParen:rest)   =
        p1 = parse pattern rest
        parse paren pattern p1
      parse pattern (_:rest)           =  (PatWild, rest)
      parse pattern []                 =  (PatWild, [])

fn :: parse paren pattern (RPattern, [RToken]) => RPattern [RToken]
      parse paren pattern (first_p, (TokColon:rest)) =
        p2 = parse cons tail rest
        finish cons pat first_p p2
      parse paren pattern (first_p, (TokComma:rest)) =
        p_list = parse tuple pats rest
        finish tuple pat first_p p_list
      parse paren pattern ((PatVar v), (TokRParen:rest)) = (PatSeqBind v, rest)
      parse paren pattern (first_p, (TokRParen:rest)) = (first_p, rest)
      parse paren pattern ((PatCtor ctor []), rest) =
        p_args = parse ctor subpats rest
        finish ctor pat ctor p_args
      parse paren pattern ((PatVar ctor), rest) =
        p_args = parse ctor subpats rest
        finish ctor pat ctor p_args
      parse paren pattern (first_p, rest)      =  (first_p, rest)

fn :: parse cons tail [RToken] => RPattern [RToken]
      parse cons tail ts       =
        p1 = parse pattern ts
        parse cons tail cont p1

fn :: parse cons tail cont (RPattern, [RToken]) => RPattern [RToken]
      parse cons tail cont (p, (TokColon:rest)) =
        more = parse cons tail rest
        finish cons pat p more
      parse cons tail cont (p, (TokRParen:rest)) = (p, rest)
      parse cons tail cont (p, rest)            =  (p, rest)

fn :: finish cons pat RPattern (RPattern, [RToken]) => RPattern [RToken]
      finish cons pat h        (t, rest)            =  (PatCons h t, rest)

fn :: parse tuple pats [RToken] => [RPattern] [RToken]
      parse tuple pats ts       =
        p1 = parse pattern ts
        parse tuple pats cont p1

fn :: parse tuple pats cont (RPattern, [RToken]) => [RPattern] [RToken]
      parse tuple pats cont (p, (TokComma:rest)) =
        more = parse tuple pats rest
        prepend pat p more
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
        p1 = parse pattern ts
        parse ctor subpats tail p1

fn :: parse ctor subpats tail (RPattern, [RToken]) => [RPattern] [RToken]
      parse ctor subpats tail (p, rest)            =
        tail_res = parse ctor subpats rest
        prepend pat p tail_res

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
        p1 = parse pattern ts
        parse case patterns cont p1

fn :: parse case patterns cont (RPattern, [RToken]) => [RPattern] [RToken]
      parse case patterns cont (p, rest)            =
        more = parse case patterns rest
        prepend pat p more

-- ── String Interpolation & Escaped Braces Parsing ───────────

fn :: find matching rbrace String Int Int => Int
      find matching rbrace s pos len
        | pos >= len = -1
        | (str char at s pos) == 125 = pos
        | (str char at s pos) == 10 OR (str char at s pos) == 59 OR (str char at s pos) == 34 = -1
        | otherwise = find matching rbrace s (pos + 1) len

fn :: has interp brace String Int Int => Bool
      has interp brace s pos len
        | pos >= len = False
        | (str char at s pos) == 123 AND (str char at s (pos + 1)) == 123 = has interp brace s (pos + 2) len
        | (str char at s pos) == 125 AND (str char at s (pos + 1)) == 125 = has interp brace s (pos + 2) len
        | (str char at s pos) == 123 AND (find matching rbrace s (pos + 1) len) > (pos + 1) = True
        | otherwise = has interp brace s (pos + 1) len

fn :: unescape double braces String Int Int String => String
      unescape double braces s pos len acc
        | pos >= len = acc
        | (str char at s pos) == 123 AND (str char at s (pos + 1)) == 123 = unescape double braces s (pos + 2) len (acc + (char from code 123))
        | (str char at s pos) == 125 AND (str char at s (pos + 1)) == 125 = unescape double braces s (pos + 2) len (acc + (char from code 125))
        | otherwise = unescape double braces s (pos + 1) len (acc + (str slice s pos (pos + 1)))

fn :: flush lit part String [RExpr] => [RExpr]
      flush lit part ""     parts   =  parts
      flush lit part lit    parts   =  parts :: [EStr lit]

fn :: parse interp code String   => RExpr
      parse interp code code_str =
        toks = tokenize src code_str
        extract expr fst (parse expr toks)

fn :: extract expr fst (RExpr, [RToken]) => RExpr
      extract expr fst (e, _)            =  e

fn :: split interp loop String Int Int String [RExpr] => [RExpr]
      split interp loop s pos len cur_lit parts
        | pos >= len = flush lit part cur_lit parts
        | (str char at s pos) == 123 AND (str char at s (pos + 1)) == 123 = split interp loop s (pos + 2) len (cur_lit + (char from code 123)) parts
        | (str char at s pos) == 125 AND (str char at s (pos + 1)) == 125 = split interp loop s (pos + 2) len (cur_lit + (char from code 125)) parts
        | (str char at s pos) == 123 = split interp at brace s pos len cur_lit parts (find matching rbrace s (pos + 1) len)
        | otherwise = split interp loop s (pos + 1) len (cur_lit + (str slice s pos (pos + 1))) parts

fn :: split interp at brace String Int Int String [RExpr] Int => [RExpr]
      split interp at brace s pos len cur_lit parts rbrace_idx
        | rbrace_idx <= (pos + 1) = split interp loop s (pos + 1) len (cur_lit + (char from code 123)) parts
        | otherwise = split interp loop s (rbrace_idx + 1) len "" ((flush lit part cur_lit parts) :: [parse interp code (str slice s (pos + 1) rbrace_idx)])

fn :: build str expr String => RExpr
      build str expr s
        | NOT ((str contains s (char from code 123)) OR (str contains s (char from code 125))) = EStr s
        | has interp brace s 0 (str len s) = EStrInterp (split interp loop s 0 (str len s) "" [])
        | otherwise = EStr (unescape double braces s 0 (str len s) "")

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

fn :: is arrow tok [RToken]     => Bool
      is arrow tok (TokArrow:_) =  True
      is arrow tok _            =  False

fn :: parse expr [RToken] => RExpr [RToken]
      parse expr ts
        | is with block start ts = parse with expr ts
        | otherwise = parse pipe chain (parse logic expr ts)

fn :: parse pipe chain (RExpr, [RToken]) => RExpr [RToken]
      parse pipe chain (left_e, (TokArrow:(TokIdent v):TokIdxLBracket:rest)) =
        (left_e, [TokArrow, TokIdent v, TokIdxLBracket] :: rest)
      parse pipe chain (left_e, (TokArrow:TokLParen:TokRParen:rest)) =
        parse pipe chain (ECall "__pipe__" [left_e, EUnit], rest)
      parse pipe chain (left_e, (TokArrow:TokLParen:rest))
        | is seq mask tokens ([TokLParen] :: rest) =
          parse pipe chain (finish seq select left_e (scan seq mask rest ""))
      parse pipe chain (left_e, (TokArrow:rest)) =
        parse pipe stage left_e (parse logic expr (skip newlines rest))
      parse pipe chain (left_e, (TokNewline:rest))
        | is arrow tok (skip newlines rest) =
          parse pipe chain (left_e, skip newlines rest)
      parse pipe chain res = res

fn :: parse pipe stage RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse pipe stage left_e (rhs_e, rest) =
        parse pipe chain (ECall "__pipe__" [left_e, rhs_e], rest)

fn :: skip opt dtok [RToken]     => [RToken]
      skip opt dtok (TokDo:rest) =  rest
      skip opt dtok ts           =  ts

fn :: parse with region after Int [RToken] => RExpr [RToken]
      parse with region after quota (TokComma:(TokIdent t_kw):rest)
        | t_kw == "timeout" =
          d_res = parse logic expr rest
          wrap with region quota (parse with ctx body "__rg_timeout_ms__" d_res)
      parse with region after quota rest =
        wrap with region quota (parse case body (skip opt dtok (skip newlines rest)))

fn :: parse with timeout after (RExpr, [RToken]) => RExpr [RToken]
      parse with timeout after (dur_e, (TokComma:(TokIdent r_kw):(TokIdent l_kw):(TokInt quota):rest))
        | r_kw == "region" AND l_kw == "limit" =
          b_res = parse case body (skip opt dtok (skip newlines rest))
          wrap with ctx "__rg_timeout_ms__" dur_e (wrap with region quota b_res)
      parse with timeout after (dur_e, (TokComma:(TokIdent r_kw):(TokInt quota):rest))
        | r_kw == "region" =
          b_res = parse case body (skip opt dtok (skip newlines rest))
          wrap with ctx "__rg_timeout_ms__" dur_e (wrap with region quota b_res)
      parse with timeout after d_res             =
        parse with ctx body "__rg_timeout_ms__" d_res

fn :: parse with expr [RToken] => RExpr [RToken]
      parse with expr (TokWith:(TokIdent r_kw):(TokIdent l_kw):(TokInt quota):rest)
        | r_kw == "region" AND l_kw == "limit" = parse with region after quota rest
      parse with expr (TokWith:(TokIdent r_kw):(TokInt quota):rest)
        | r_kw == "region" = parse with region after quota rest
      parse with expr (TokWith:(TokIdent t_kw):rest)
        | t_kw == "timeout" = parse with timeout after (parse logic expr rest)
      parse with expr (_:rest) =  parse logic expr rest
      parse with expr []       =  (EUnit, [])

fn :: wrap with region Int   (RExpr, [RToken]) => RExpr [RToken]
      wrap with region quota (body, rest)      =
        dot_res = strip optional pipe dot rest
        finish with region quota body dot_res

fn :: finish with region Int RExpr (Bool, [RToken]) => RExpr [RToken]
      finish with region quota body (_, after_dot) = (EWithRegion quota body, after_dot)

fn :: parse with ctx body String (RExpr, [RToken]) => RExpr [RToken]
      parse with ctx body ctx_name (val_e, rest) =
        clean = skip opt dtok (skip newlines rest)
        b_res = parse case body clean
        wrap with ctx ctx_name val_e b_res

fn :: wrap with ctx String RExpr (RExpr, [RToken]) => RExpr [RToken]
      wrap with ctx ctx_name val_e (body, rest) =
        dot_res = strip optional pipe dot rest
        finish with ctx ctx_name val_e body dot_res

fn :: finish with ctx String RExpr RExpr (Bool, [RToken]) => RExpr [RToken]
      finish with ctx ctx_name val_e body (_, after_dot) = (EWithCtx ctx_name val_e body, after_dot)

fn :: parse logic expr [RToken] => RExpr [RToken]
      parse logic expr ts       =
        p1 = parse not expr ts
        parse logic loop p1

fn :: parse logic loop (RExpr, [RToken]) => RExpr [RToken]
      parse logic loop (left, (TokAnd:rest)) =
        r = parse not expr rest
        parse logic combine OpAnd left r
      parse logic loop (left, (TokOr:rest)) =
        r = parse not expr rest
        parse logic combine OpOr left r
      parse logic loop (left, (TokXor:rest)) =
        r = parse not expr rest
        parse logic combine OpXor left r
      parse logic loop res               =  res

fn :: parse logic combine RBinOp RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse logic combine bop left (right, rest) =
        parse logic loop (make add or hadamard bop left right, rest)

fn :: parse not expr [RToken]      => RExpr [RToken]
      parse not expr (TokNot:rest) =
        inner = parse not expr rest
        wrap not inner
      parse not expr ts            =  parse cmp expr ts

fn :: wrap not (RExpr, [RToken]) => RExpr [RToken]
      wrap not (e, rest)         =  (ENot e, rest)

fn :: parse cmp expr [RToken] => RExpr [RToken]
      parse cmp expr ts       =
        p1 = parse add expr ts
        parse cmp tail p1

fn :: parse cmp tail (RExpr, [RToken]) => RExpr [RToken]
      parse cmp tail (left, (TokEqEq:rest)) = combine bin OpEq left (parse add expr rest)
      parse cmp tail (left, (TokNeq:rest)) = combine bin OpNeq left (parse add expr rest)
      parse cmp tail (left, (TokGt:rest)) = combine bin OpGt left (parse add expr rest)
      parse cmp tail (left, (TokLt:rest)) = combine bin OpLt left (parse add expr rest)
      parse cmp tail (left, (TokGtEq:rest)) = combine bin OpGtEq left (parse add expr rest)
      parse cmp tail (left, (TokLtEq:rest)) = combine bin OpLtEq left (parse add expr rest)
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
        | (is hadamard bop bop) and (is subscript ident v1) and (is subscript ident v2) = build hadamard node bop (split subscript v1) (split subscript v2)
      make add or hadamard bop (EHadamard b1 l1 s1 r1 s2) (EVar v2)
        | (is hadamard bop bop) and (is subscript ident v2) = build hadamard chain r bop (EHadamard b1 l1 s1 r1 s2) s1 (split subscript v2)
      make add or hadamard bop (EVar v1) (EHadamard b2 l2 s2 r2 s3)
        | (is hadamard bop bop) and (is subscript ident v1) = build hadamard chain l bop (split subscript v1) (EHadamard b2 l2 s2 r2 s3) s2
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
        | is subscript ident v2 = append einsum term es subs (split subscript v2)
      make matmul or einsum (EVar v1) (EVar v2)
        | (is subscript ident v1) AND (is subscript ident v2) = build einsum pair (split subscript v1) (split subscript v2)
      make matmul or einsum left right = EBin OpMatMul left right

fn :: append einsum term [RExpr] [String] (String, String) => RExpr
      append einsum term es subs (b2, s2) =
        EEinsum (es :: [EVar b2]) (subs :: [s2])

fn :: build einsum pair (String, String) (String, String) => RExpr
      build einsum pair (b1, s1)         (b2, s2)         =
        EEinsum [EVar b1, EVar b2] [s1, s2]

fn :: parse add expr [RToken] => RExpr [RToken]
      parse add expr ts       =
        p1 = parse mul expr ts
        parse add loop p1

fn :: parse add loop (RExpr, [RToken]) => RExpr [RToken]
      parse add loop (left, (TokPlus:rest)) =
        r = parse mul expr (skip newlines rest)
        parse add combine OpAdd left r
      parse add loop (left, (TokMinus:rest)) =
        r = parse mul expr (skip newlines rest)
        parse add combine OpSub left r
      parse add loop (left, (TokColonColon:rest)) =
        r = parse mul expr (skip newlines rest)
        parse add combine OpConcat left r
      parse add loop (left, (TokColon:rest)) =
        r = parse add expr (skip newlines rest)
        parse colon combine left r
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
        parse add loop (make add or hadamard bop left right, rest)

fn :: parse mul expr [RToken] => RExpr [RToken]
      parse mul expr ts       =
        p1 = parse app expr ts
        parse mul loop p1

fn :: parse mul loop (RExpr, [RToken]) => RExpr [RToken]
      parse mul loop (left, (TokStar:rest)) =
        r = parse app expr rest
        parse mul combine OpMul left r
      parse mul loop (left, (TokSlash:rest)) =
        r = parse app expr rest
        parse mul combine OpDiv left r
      parse mul loop (left, (TokPercent:rest)) =
        r = parse app expr rest
        parse mul combine OpMod left r
      parse mul loop (left, (TokAt:rest)) =
        r = parse app expr rest
        parse matmul combine left r
      parse mul loop (left, ((TokIdent "shl"):rest)) =
        r = parse app expr rest
        parse mul combine OpShl left r
      parse mul loop (left, ((TokIdent "shr"):rest)) =
        r = parse app expr rest
        parse mul combine OpShr left r
      parse mul loop (left, ((TokIdent "rotr"):rest)) =
        r = parse app expr rest
        parse mul combine OpRotr left r
      parse mul loop (left, ((TokIdent "rotl"):rest)) =
        r = parse app expr rest
        parse mul combine OpRotl left r
      parse mul loop res               =  res

fn :: parse mul combine RBinOp RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse mul combine bop left (right, rest) =
        parse mul loop (make add or hadamard bop left right, rest)

fn :: parse matmul combine RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse matmul combine left  (right, rest)     =
        parse mul loop (make matmul or einsum left right, rest)

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
      scan seq mask (TokPlus:TokEllipsis:rest) acc = scan seq mask rest (acc + " +")
      scan seq mask (TokPlus:rest)    acc    =  scan seq mask rest (acc + "+")
      scan seq mask (TokEllipsis:rest) acc   =  scan seq mask rest (acc + " +")
      scan seq mask ((TokIdent s):rest) acc  =  scan seq mask rest (acc + s)
      scan seq mask ((TokInt n):rest) ""     =  scan seq mask rest (int to str n)
      scan seq mask ((TokInt n):rest) acc    =  scan seq mask rest (acc + " " + (int to str n))
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
        f_res = extract field name ts
        parse record update val f_res acc

fn :: parse record update val (String, [RToken]) [RExpr] => [RExpr] [RToken]
      parse record update val ("", ts) acc = (acc, ts)
      parse record update val (fname, rest) acc =
        v_res = parse logic expr rest
        parse record update more fname v_res acc

fn :: parse record update more String (RExpr, [RToken]) [RExpr] => [RExpr] [RToken]
      parse record update more fname (val_e, (TokComma:rest)) acc
        | has next record field ([TokComma] :: rest) = parse record update pairs rest (acc :: [EStr fname, val_e])
        | otherwise = (acc :: [EStr fname, val_e], [TokComma] :: rest)
      parse record update more fname (val_e, rest) acc =
        (acc :: [EStr fname, val_e], rest)

fn :: parse record update RExpr [RToken]       => RExpr [RToken]
      parse record update base  (TokWith:rest) =
        p_res = parse record update pairs rest []
        finish record update base p_res
      parse record update base  ts             =  (base, ts)

fn :: finish record update RExpr ([RExpr], [RToken]) => RExpr [RToken]
      finish record update base  (pairs, rest)       =
        check record update tail (ECall "__record_update__" ([base] :: pairs), rest)

fn :: check record update tail (RExpr, [RToken]) => RExpr [RToken]
      check record update tail (base_e, rest)
        | is record update start rest = parse record update base_e rest
        | otherwise = (base_e, rest)

fn :: parse app expr [RToken] => RExpr [RToken]
      parse app expr ts       =
        p1 = parse atom ts
        parse app tail p1

fn :: parse app tail (RExpr, [RToken]) => RExpr [RToken]
      parse app tail ((EVar name), (TokLParen:rest))
        | is seq mask tokens ([TokLParen] :: rest) = finish seq select (EVar name) (scan seq mask rest "")
      parse app tail ((EVar name), rest)
        | is record update start rest = parse record update (EVar name) rest
        | name == "echo" = finish echo call (parse atom list rest)
        | is atom tok (tok head rest) = check record update tail (finish fn or out call (EVar name) name (parse atom list rest))
        | otherwise = (EVar name, rest)
      parse app tail (first_e, rest)
        | is record update start rest = parse record update first_e rest
        | is atom tok (tok head rest) = check record update tail (finish chain or out first_e (parse atom list rest))
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
        | is record update start ts = ([], ts)
        | is atom tok (tok head ts) = parse atom list cont (parse atom ts)
        | otherwise = ([], ts)

fn :: parse atom list cont (RExpr, [RToken]) => [RExpr] [RToken]
      parse atom list cont (e, rest)         =
        more = parse atom list rest
        prepend expr e more

fn :: prepend expr RExpr ([RExpr], [RToken]) => [RExpr] [RToken]
      prepend expr e     (es, rest)          =  ([e] :: es, rest)

fn :: finish echo call ([RExpr], [RToken]) => RExpr [RToken]
      finish echo call (args, rest)        =  (EEcho args, rest)

-- ── Atom & Postfix Indexing (`m[0, 1]`, `m[0][1]`) ──────────

fn :: parse atom [RToken] => RExpr [RToken]
      parse atom ts       =
        base_res = parse atom base ts
        parse postfix index base_res

fn :: parse atom base [RToken]           => RExpr [RToken]
      parse atom base ((TokInt n):rest)  =  (EInt n, rest)
      parse atom base ((TokReal r):rest) =  (EReal r, rest)
      parse atom base ((TokStr s):rest)  =  (build str expr s, rest)
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
        | (s == "Tensor" or s == "Tensor_GPU") and (is upper ident elem_ty) = finish tensor alloc elem_ty (parse tensor alloc dims ([TokStar] :: after_star))
      parse atom base ((TokIdent s):TokIdxLBracket:(TokIdent elem_ty):TokStar:after_star)
        | (s == "Tensor" or s == "Tensor_GPU") and (is upper ident elem_ty) = finish tensor alloc elem_ty (parse tensor alloc dims ([TokStar] :: after_star))
      parse atom base ((TokIdent s):TokLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = finish tensor lit (parse comma exprs rest)
      parse atom base ((TokIdent s):TokIdxLBracket:rest)
        | s == "Tensor" or s == "Tensor_GPU" = finish tensor lit (parse comma exprs rest)
      parse atom base ((TokIdent s):rest) = (EVar s, rest)
      parse atom base (TokMinus:(TokInt n):rest) = (EInt (0 - n), rest)
      parse atom base (TokMinus:(TokReal r):rest) = (EReal ("-" + r), rest)
      parse atom base (TokLParen:TokRParen:rest) = (EUnit, rest)
      parse atom base (TokLParen:TokLParen:TokRParen:TokFatArrow:rest) =
        (ECall "__syntax_error__" [EStr "zero-parameter lambda uses '(=> expr)', not '(() => expr)'"], skip to rparen rest 0)
      parse atom base (TokLParen:TokRParen:TokFatArrow:rest) =
        (ECall "__syntax_error__" [EStr "zero-parameter lambda uses '(=> expr)', not '(() => expr)'"], skip to newline rest)
      parse atom base (TokLParen:TokFatArrow:rest) =
        parse lambda paren (parse lambda body [] rest)
      parse atom base (TokLParen:rest)
        | is paren lambda rest False = parse lambda paren (parse lambda expr rest [])
        | is paren type arrow rest False =
          (ECall "__syntax_error__" [EStr "type signature '(Type => Type)' cannot be used as an expression; lambda parameters must start with a lowercase letter"], skip to rparen rest 0)
        | otherwise =
          p1 = parse expr rest
          parse paren expr p1
      parse atom base (TokLBracket:TokRBracket:rest) = (EList [], rest)
      parse atom base (TokLBracket:rest) =
        elems_res = parse comma exprs rest
        finish list lit elems_res
      parse atom base (_:rest)           =  (EUnit, rest)
      parse atom base []                 =  (EUnit, [])

fn :: is lambda param ident String => Bool
      is lambda param ident "_" = True
      is lambda param ident s = (is lower ident s) AND (NOT (str contains s "."))

fn :: scan lambda tuple params [RToken] [String] => Bool [String] [RToken]
      scan lambda tuple params (TokRParen:rest) acc = ((str list count acc) >= 2, acc, rest)
      scan lambda tuple params (TokComma:rest) acc = scan lambda tuple params rest acc
      scan lambda tuple params ((TokIdent p):rest) acc
        | is lambda param ident p = scan lambda tuple params rest (acc :: [p])
      scan lambda tuple params (TokType:rest) acc = scan lambda tuple params rest (acc :: ["type"])
      scan lambda tuple params (TokWith:rest) acc = scan lambda tuple params rest (acc :: ["with"])
      scan lambda tuple params ts _ = (False, [], ts)

fn :: is paren lambda [RToken] Bool => Bool
      is paren lambda (TokFatArrow:_) has_p = has_p
      is paren lambda ((TokIdent p):rest) _
        | is lambda param ident p = is paren lambda rest True
      is paren lambda (TokType:rest) _ = is paren lambda rest True
      is paren lambda (TokWith:rest) _ = is paren lambda rest True
      is paren lambda (TokLParen:rest) _ =
        is paren lambda tuple (scan lambda tuple params rest [])
      is paren lambda _ _ = False

fn :: is paren lambda tuple (Bool, [String], [RToken]) => Bool
      is paren lambda tuple (True, _, after_tup) = is paren lambda after_tup True
      is paren lambda tuple (False, _, _) = False

fn :: is paren type arrow [RToken] Bool => Bool
      is paren type arrow (TokFatArrow:_) has_t = has_t
      is paren type arrow ((TokIdent s):rest) _
        | is upper ident s = is paren type arrow rest True
      is paren type arrow (TokComma:rest) has_t = is paren type arrow rest has_t
      is paren type arrow _ _ = False

fn :: join raw comma strs [String] => String
      join raw comma strs [] = ""
      join raw comma strs (s:[]) = s
      join raw comma strs (s:ss) = s + "," + (join raw comma strs ss)

fn :: parse lambda expr [RToken] [RExpr] => RExpr [RToken]
      parse lambda expr (TokFatArrow:rest) params =
        parse lambda body params rest
      parse lambda expr ((TokIdent p):rest) params =
        parse lambda expr rest (params :: [EStr p])
      parse lambda expr (TokType:rest) params =
        parse lambda expr rest (params :: [EStr "type"])
      parse lambda expr (TokWith:rest) params =
        parse lambda expr rest (params :: [EStr "with"])
      parse lambda expr (TokLParen:rest) params =
        parse lambda tup step params (scan lambda tuple params rest [])
      parse lambda expr ts params =
        parse lambda body params ts

fn :: parse lambda tup step [RExpr] (Bool, [String], [RToken]) => RExpr [RToken]
      parse lambda tup step params (True, tup_vars, after_tup) =
        parse lambda expr after_tup (params :: [EStr ("(" + (join raw comma strs tup_vars) + ")")])
      parse lambda tup step params (False, _, after_tup) =
        parse lambda body params after_tup

fn :: parse lambda body [RExpr] [RToken] => RExpr [RToken]
      parse lambda body params (TokNewline:rest) =
        finish lambda expr params (parse case body ([TokNewline] :: rest))
      parse lambda body params ts =
        finish lambda expr params (parse expr ts)

fn :: parse lambda paren (RExpr, [RToken]) => RExpr [RToken]
      parse lambda paren (e, rest) =
        clean = skip newlines rest
        finish lambda paren e rest clean

fn :: finish lambda paren RExpr [RToken] [RToken] => RExpr [RToken]
      finish lambda paren e _ (TokRParen:after_rp) = (e, after_rp)
      finish lambda paren e orig_rest _ = parse paren expr (e, orig_rest)

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
        d_res = parse atom rest
        parse tensor alloc dims cont d_res
      parse tensor alloc dims ts                 =
        d_res = parse atom ts
        parse tensor alloc dims cont d_res

fn :: parse tensor alloc dims cont (RExpr, [RToken]) => [RExpr] [RToken]
      parse tensor alloc dims cont (d_e, rest) =
        more = parse tensor alloc dims rest
        prepend expr d_e more

fn :: finish tensor alloc String  ([RExpr], [RToken]) => RExpr [RToken]
      finish tensor alloc elem_ty (dims, rest)        =
        (ECall ":tensor-zeros:" ([tensor zero fill elem_ty] :: dims), rest)

fn :: finish tensor lit ([RExpr], [RToken]) => RExpr [RToken]
      finish tensor lit (elems, rest)       =  (ETensor elems, rest)

fn :: parse postfix index (RExpr, [RToken]) => RExpr [RToken]
      parse postfix index ((EVar v), (TokIdxLBracket:rest)) =
        idx_res = collect bracket indices ([TokIdxLBracket] :: rest) []
        finish index expr (EVar v) idx_res
      parse postfix index ((EVar v), (TokLParen:rest))
        | is trailing underscore ident v =
          base_e = EVar (str slice v 0 ((str len v) - 1))
          check chained subscript (parse subscript paren base_e rest)
      parse postfix index res               =  check chained subscript res

fn :: check chained subscript (RExpr, [RToken]) => RExpr [RToken]
      check chained subscript (base_e, ((TokIdent "_"):TokLParen:rest)) =
        check chained subscript (parse subscript paren base_e rest)
      check chained subscript res               =  res

fn :: parse subscript paren RExpr  [RToken]           => RExpr [RToken]
      parse subscript paren base_e (TokComma:after_c) =
        c_res = parse expr after_c
        finish col slice expr base_e c_res
      parse subscript paren base_e ts                 =
        i1_res = parse expr ts
        parse subscript after first base_e i1_res

fn :: finish col slice expr RExpr (RExpr, [RToken]) => RExpr [RToken]
      finish col slice expr base_e (col_e, rest) =
        (ECall ":tensor-col-slice:" [base_e, col_e], strip rparen rest)

fn :: parse subscript after first RExpr (RExpr, [RToken]) => RExpr [RToken]
      parse subscript after first base_e (idx1, (TokComma:TokRParen:rest)) =
        (ECall ":tensor-row-slice:" [base_e, idx1], rest)
      parse subscript after first base_e (idx1, (TokComma:more_ts)) =
        more_res = parse comma exprs more_ts
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
        one_bracket = parse comma exprs rest
        collect bracket more acc one_bracket
      collect bracket indices ts       acc     =  (acc, ts)

fn :: collect bracket more [RExpr] ([RExpr], [RToken]) => [RExpr] [RToken]
      collect bracket more acc     (idxs, rest)        =
        collect bracket indices rest (acc :: idxs)

fn :: finish index expr RExpr ([RExpr], [RToken]) => RExpr [RToken]
      finish index expr base  ([], rest)          =  (base, rest)
      finish index expr base  (idxs, rest)        =  (EIndex base idxs, rest)

fn :: parse paren expr (RExpr, [RToken]) => RExpr [RToken]
      parse paren expr (first_e, (TokComma:rest)) =
        more = parse comma exprs rest
        finish tuple lit first_e more
      parse paren expr (first_e, (TokRParen:rest)) = (first_e, rest)
      parse paren expr (first_e, rest)   =  (first_e, rest)

fn :: parse comma exprs [RToken] => [RExpr] [RToken]
      parse comma exprs ts       =
        p1 = parse expr ts
        parse comma exprs cont p1

fn :: parse comma exprs cont (RExpr, [RToken]) => [RExpr] [RToken]
      parse comma exprs cont (e, (TokComma:rest)) =
        more = parse comma exprs rest
        prepend expr e more
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
      strip optional pipe dot (TokNewline:rest) =  strip pipe dot after nl rest (skip newlines rest)
      strip optional pipe dot ts                =  (False, ts)

fn :: strip pipe dot after nl [RToken] [RToken] => Bool [RToken]
      strip pipe dot after nl _ (TokPipeDot:rest) = (True, rest)
      strip pipe dot after nl orig_ts _ = (False, orig_ts)

fn :: finish otherwise guard (RExpr, [RToken]) => [RGuard] [RToken]
      finish otherwise guard (body, rest)      =
        dot_res = strip optional pipe dot rest
        finish otherwise after dot body dot_res

fn :: finish otherwise after dot RExpr (Bool, [RToken]) => [RGuard] [RToken]
      finish otherwise after dot body (_, after_dot) =
        ([GuardBranch (EBool True) body], after_dot)

fn :: split guard cond [RToken] Int [RToken] => [RToken] [RToken]
      split guard cond [] _ acc = (acc, [])
      split guard cond (TokEquals:rest) 0 acc = (acc, [TokEquals] :: rest)
      split guard cond (TokNewline:rest) 0 acc = (acc, [TokNewline] :: rest)
      split guard cond (TokEof:rest) 0 acc = (acc, [TokEof] :: rest)
      split guard cond (TokLParen:rest) depth acc =
        split guard cond rest (depth + 1) (acc :: [TokLParen])
      split guard cond (TokLBracket:rest) depth acc =
        split guard cond rest (depth + 1) (acc :: [TokLBracket])
      split guard cond (TokRParen:rest) depth acc
        | depth > 0 = split guard cond rest (depth - 1) (acc :: [TokRParen])
        | otherwise = split guard cond rest 0 (acc :: [TokRParen])
      split guard cond (TokRBracket:rest) depth acc
        | depth > 0 = split guard cond rest (depth - 1) (acc :: [TokRBracket])
        | otherwise = split guard cond rest 0 (acc :: [TokRBracket])
      split guard cond (t:rest) depth acc =
        split guard cond rest depth (acc :: [t])

fn :: parse guard cond split ([RToken], [RToken]) => RExpr [RToken]
      parse guard cond split (cond_toks, after_cond) =
        c = parse expr cond_toks
        finish guard cond split c after_cond

fn :: finish guard cond split (RExpr, [RToken]) [RToken] => RExpr [RToken]
      finish guard cond split (cond_e, _) after_cond = (cond_e, after_cond)

fn :: parse guards [RToken]       => [RGuard] [RToken]
      parse guards (TokPipe:TokOtherwise:TokEquals:rest) =
        b = parse case body rest
        finish otherwise guard b
      parse guards (TokPipe:rest) =
        c = parse guard cond split (split guard cond rest 0 [])
        parse guard after cond c
      parse guards ts             =  ([], ts)

fn :: parse guard after cond (RExpr, [RToken]) => [RGuard] [RToken]
      parse guard after cond (cond, (TokEquals:rest)) =
        b = parse case body rest
        parse guards cont cond b
      parse guard after cond (cond, rest)      =
        b = parse case body rest
        parse guards cont cond b

fn :: parse guards cont RExpr (RExpr, [RToken]) => [RGuard] [RToken]
      parse guards cont cond  (body, rest)      =
        dot_res = strip optional pipe dot rest
        parse guards after dot cond body dot_res

fn :: parse guards after dot RExpr RExpr (Bool, [RToken]) => [RGuard] [RToken]
      parse guards after dot cond body (True, after_dot) =
        ([GuardBranch cond body], after_dot)
      parse guards after dot cond body (False, rest) =
        trimmed = skip newlines rest
        more = parse guards trimmed
        prepend guard (GuardBranch cond body) more

fn :: prepend guard RGuard ([RGuard], [RToken]) => [RGuard] [RToken]
      prepend guard g      (gs, rest)           =  ([g] :: gs, rest)

fn :: finish guard expr ([RGuard], [RToken]) => RExpr [RToken]
      finish guard expr (guards, rest)       =  (EGuard guards, rest)

fn :: line has equals [RToken] => Bool
      line has equals ts = line has equals depth ts 0

fn :: line has equals depth [RToken] Int => Bool
      line has equals depth [] _ = False
      line has equals depth (TokEof:_) _ = False
      line has equals depth (TokNewline:_) _ = False
      line has equals depth (TokLParen:ts) d = line has equals depth ts (d + 1)
      line has equals depth (TokLBracket:ts) d = line has equals depth ts (d + 1)
      line has equals depth (TokIdxLBracket:ts) d = line has equals depth ts (d + 1)
      line has equals depth (TokRParen:ts) d
        | d > 0 = line has equals depth ts (d - 1)
        | otherwise = line has equals depth ts 0
      line has equals depth (TokRBracket:ts) d
        | d > 0 = line has equals depth ts (d - 1)
        | otherwise = line has equals depth ts 0
      line has equals depth (TokWith:ts) 0
        | is record update start ([TokWith] :: ts) = False
        | otherwise = line has equals depth ts 0
      line has equals depth (TokEquals:_) 0 = True
      line has equals depth (_:ts) d = line has equals depth ts d

fn :: is echo expr RExpr            => Bool
      is echo expr (EEcho _)        =  True
      is echo expr (ECall "__pipe__" (_:(EVar _):[])) = True
      is echo expr (ECall "send" _) =  True
      is echo expr (ECall "send_to" _) = True
      is echo expr (ECall "send_through" _) = True
      is echo expr (ECall "stop" _) =  True
      is echo expr (ECall "write_file" _) = True
      is echo expr (ECall "write_bytes" _) = True
      is echo expr (ECall "shell_exec" _) = True
      is echo expr (ECall "sys_mkdir" _) = True
      is echo expr (ECall "sys_close" _) = True
      is echo expr (ECall "log" _) = True
      is echo expr (ECall "print" _) = True
      is echo expr (ECall "verify" _) = True
      is echo expr (ECall "ensure" _) = True
      is echo expr (ECall "report" _) = True
      is echo expr _                =  False

fn :: is stmt only starter String     => Bool
      is stmt only starter "echo"     =  True
      is stmt only starter "send"     =  True
      is stmt only starter "ask"      =  True
      is stmt only starter "stop"     =  True
      is stmt only starter "sys_exit" =  True
      is stmt only starter _          =  False

fn :: line followed by pipe [RToken]       => Bool
      line followed by pipe []             =  False
      line followed by pipe (TokEof:_)     =  False
      line followed by pipe (TokNewline:TokPipe:TokOtherwise:_) = False
      line followed by pipe (TokNewline:TokPipe:_) = True
      line followed by pipe (TokNewline:_) =  False
      line followed by pipe (TokEquals:_)  =  False
      line followed by pipe (TokArrow:_)   =  False
      line followed by pipe (TokFatArrow:_) = False
      line followed by pipe (_:ts)         =  line followed by pipe ts

fn :: next line has guard [RToken] => Bool
      next line has guard ts       =
        clean = skip newlines ts
        next line has guard clean clean

fn :: next line has guard clean [RToken] => Bool
      next line has guard clean ((TokIdent s):rest)
        | (is stmt only starter s) OR (str contains s "_") = False
        | otherwise = line followed by pipe rest
      next line has guard clean _ = False

fn :: line has arrow [RToken]       => Bool
      line has arrow []             =  False
      line has arrow (TokEof:_)     =  False
      line has arrow (TokNewline:_) =  False
      line has arrow (TokArrow:_)   =  True
      line has arrow (_:ts)         =  line has arrow ts

fn :: line has fat arrow [RToken] => Bool
      line has fat arrow ts = line has fat arrow depth ts 0

fn :: line has fat arrow depth [RToken] Int => Bool
      line has fat arrow depth [] _ = False
      line has fat arrow depth (TokEof:_) _ = False
      line has fat arrow depth (TokNewline:_) _ = False
      line has fat arrow depth (TokLParen:ts) d = line has fat arrow depth ts (d + 1)
      line has fat arrow depth (TokLBracket:ts) d = line has fat arrow depth ts (d + 1)
      line has fat arrow depth (TokIdxLBracket:ts) d = line has fat arrow depth ts (d + 1)
      line has fat arrow depth (TokRParen:ts) d
        | d > 0 = line has fat arrow depth ts (d - 1)
        | otherwise = line has fat arrow depth ts 0
      line has fat arrow depth (TokRBracket:ts) d
        | d > 0 = line has fat arrow depth ts (d - 1)
        | otherwise = line has fat arrow depth ts 0
      line has fat arrow depth (TokFatArrow:_) 0 = True
      line has fat arrow depth (_:ts) d = line has fat arrow depth ts d

fn :: parse int indices [RToken]           => [Int] [RToken]
      parse int indices (TokRBracket:rest) =  ([], rest)
      parse int indices (TokComma:rest)    =  parse int indices rest
      parse int indices ((TokInt n):rest)  =
        more = parse int indices rest
        prepend int n more
      parse int indices (_:rest)           =  ([], rest)
      parse int indices []                 =  ([], [])

fn :: prepend int Int ([Int], [RToken]) => [Int] [RToken]
      prepend int n   (ns, rest)        =  ([n] :: ns, rest)

fn :: strip optional dpipe dot [RToken]          => Bool [RToken]
      strip optional dpipe dot (TokDoublePipeDot:rest) = (True, rest)
      strip optional dpipe dot (TokNewline:rest) =  strip dpipe dot after nl rest (skip newlines rest)
      strip optional dpipe dot ts                =  (False, ts)

fn :: strip dpipe dot after nl [RToken] [RToken] => Bool [RToken]
      strip dpipe dot after nl _ (TokDoublePipeDot:rest) = (True, rest)
      strip dpipe dot after nl orig_ts _ = (False, orig_ts)

fn :: parse pipe where binds [RToken] => [RWhereBind] [RToken]
      parse pipe where binds ts       =
        clean = skip newlines ts
        parse pipe where step ts clean

fn :: parse pipe where step [RToken] [RToken] => [RWhereBind] [RToken]
      parse pipe where step _ (TokDoublePipe:rest)
        | line has arrow rest = parse pipe where target (parse expr rest)
      parse pipe where step orig_ts _ = ([], orig_ts)

fn :: parse pipe where target (RExpr, [RToken]) => [RWhereBind] [RToken]
      parse pipe where target (e, (TokArrow:(TokIdent v):TokIdxLBracket:rest)) =
        idx_res = parse int indices rest
        parse pipe where indexed e v idx_res
      parse pipe where target (e, (TokArrow:(TokIdent v):rest)) =
        dot_res = strip optional dpipe dot rest
        parse pipe where after dot (WhereBind e v []) dot_res
      parse pipe where target ((ECall "__pipe__" (inner_e:(EVar v):[])), rest) =
        dot_res = strip optional dpipe dot rest
        parse pipe where after dot (WhereBind inner_e v []) dot_res
      parse pipe where target ((ECall "__pipe__" (inner_e:EUnit:[])), rest) =
        dot_res = strip optional dpipe dot rest
        parse pipe where after dot (WhereBind inner_e "_" []) dot_res
      parse pipe where target (_, rest)         =  ([], rest)

fn :: parse pipe where indexed RExpr String ([Int], [RToken]) => [RWhereBind] [RToken]
      parse pipe where indexed e v (idxs, rest) =
        dot_res = strip optional dpipe dot rest
        parse pipe where after dot (WhereBind e v idxs) dot_res

fn :: parse pipe where after dot RWhereBind (Bool, [RToken]) => [RWhereBind] [RToken]
      parse pipe where after dot wb (True, after_dot) = ([wb], after_dot)
      parse pipe where after dot wb (False, rest) =
        more = parse pipe where binds rest
        prepend where wb more

fn :: prepend where RWhereBind ([RWhereBind], [RToken]) => [RWhereBind] [RToken]
      prepend where wb         (wbs, rest)              =  ([wb] :: wbs, rest)

fn :: check trailing comma and where (RExpr, [RToken]) => RExpr [RToken]
      check trailing comma and where (first_e, (TokComma:rest)) =
        more = parse comma exprs rest
        check trailing where (finish tuple lit first_e more)
      check trailing comma and where res = check trailing where res

fn :: check trailing where (RExpr, [RToken]) => RExpr [RToken]
      check trailing where (body, rest)      =
        clean = skip newlines rest
        check trailing where tok body rest clean

fn :: check trailing where tok RExpr [RToken] [RToken] => RExpr [RToken]
      check trailing where tok body _ (TokDoublePipe:after_dp)
        | line has arrow after_dp = finish where expr body (parse pipe where binds ([TokDoublePipe] :: after_dp))
      check trailing where tok body orig_rest _ = (body, orig_rest)

fn :: finish where expr RExpr ([RWhereBind], [RToken]) => RExpr [RToken]
      finish where expr body  (binds, rest)            =  (EWhere body binds, rest)

fn :: parse par pipe branches [RToken] => [RExpr] [RToken]
      parse par pipe branches (TokDoublePipe:rest) =
        e_res = parse expr rest
        parse par pipe more e_res
      parse par pipe branches ts       =  ([], ts)

fn :: parse par pipe more (RExpr, [RToken]) => [RExpr] [RToken]
      parse par pipe more (e, rest)         =
        dot_res = strip optional dpipe dot rest
        parse par pipe after dot e dot_res

fn :: parse par pipe after dot RExpr (Bool, [RToken]) => [RExpr] [RToken]
      parse par pipe after dot e (True, after_dot) = ([e], after_dot)
      parse par pipe after dot e (False, rest) =
        clean = skip newlines rest
        parse par pipe check e rest clean

fn :: parse par pipe check RExpr [RToken] [RToken] => [RExpr] [RToken]
      parse par pipe check e _ (TokDoublePipe:more_ts) =
        more = parse par pipe branches ([TokDoublePipe] :: more_ts)
        prepend expr e more
      parse par pipe check e orig_rest _ = ([e], orig_rest)

fn :: finish par pipe ([RExpr], [RToken]) => RExpr [RToken]
      finish par pipe (branches, rest)    =  (EParPipe branches, rest)

fn :: parse case body dpipe [RToken] => RExpr [RToken]
      parse case body dpipe (TokDoublePipe:rest)
        | line has arrow rest = finish dpipe where block (parse pipe where binds ([TokDoublePipe] :: rest))
        | otherwise = finish par pipe (parse par pipe branches ([TokDoublePipe] :: rest))
      parse case body dpipe ts       =  finish par pipe (parse par pipe branches ts)

fn :: finish dpipe where block ([RWhereBind], [RToken]) => RExpr [RToken]
      finish dpipe where block (binds, rest)            =
        stmts_res = parse block stmts safe rest
        wrap dpipe where stmts binds stmts_res

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
        | is lambda param ident p = has unparenthesized fat arrow rest
      has unparenthesized fat arrow _ = False

fn :: parse let rhs [RToken]          => RExpr [RToken]
      parse let rhs (TokNewline:rest) =
        clean = skip newlines rest
        parse let rhs newline rest clean
      parse let rhs (TokPipe:rest)    =
        finish guard expr (parse guards ([TokPipe] :: rest))
      parse let rhs (TokDoublePipe:rest) =
        finish par pipe (parse par pipe branches ([TokDoublePipe] :: rest))
      parse let rhs ts
        | has unparenthesized fat arrow ts =
          (ECall "__syntax_error__" [EStr "lambda expression must be enclosed in parentheses: '(x => expr)'"], skip to newline ts)
        | otherwise =
          check trailing comma and where (parse expr ts)

fn :: parse let rhs newline [RToken] [RToken] => RExpr [RToken]
      parse let rhs newline _ (TokPipe:rest) =
        finish guard expr (parse guards ([TokPipe] :: rest))
      parse let rhs newline _ (TokDoublePipe:rest) =
        finish par pipe (parse par pipe branches ([TokDoublePipe] :: rest))
      parse let rhs newline orig_rest _ =
        check trailing comma and where (parse expr orig_rest)

fn :: wrap subscript let rhs (RExpr, [RToken]) => RExpr [RToken]
      wrap subscript let rhs ((EVar rhs_v), rest)
        | is subscript ident rhs_v = (ECall ":tensor-clone:" [EVar (extract fst str (split subscript rhs_v))], rest)
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
        more_res = parse block stmts safe after_rhs
        finish tup destructure more tmp_name vars rhs_e more_res

fn :: finish tup destructure more String [String] RExpr ([RStmt], [RToken]) => [RStmt] [RToken]
      finish tup destructure more tmp_name vars rhs_e (more_stmts, rest) =
        ([StmtMut tmp_name rhs_e] :: (build tup unpack stmts vars tmp_name 0 more_stmts), rest)

fn :: parse tuple destructure stmt String (Bool, [String], [RToken]) [RToken] => [RStmt] [RToken]
      parse tuple destructure stmt first_v (True, vars, after_eq) _ =
        finish tup destructure first_v vars (parse let rhs after_eq)
      parse tuple destructure stmt first_v (False, _, _) orig_rest =
        finish expr stmt (parse expr ([TokIdent first_v, TokComma] :: orig_rest))

fn :: collect multi subscript lhs [RToken] [RExpr] => Bool [RExpr] [RToken]
      collect multi subscript lhs ((TokIdent vk):TokLParen:rest) acc
        | is trailing underscore ident vk =
          tk = str slice vk 0 ((str len vk) - 1)
          collect multi subscript one tk acc (parse comma exprs rest)
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
        more_res = parse block stmts safe after_rhs
        finish multi idx assign more tmp_name targets rhs_e more_res

fn :: finish multi idx assign more String [RExpr] RExpr ([RStmt], [RToken]) => [RStmt] [RToken]
      finish multi idx assign more tmp_name targets rhs_e (more_stmts, rest) =
        ([StmtMut tmp_name rhs_e] :: (build multi idx assign stmts targets tmp_name 0 more_stmts), rest)

fn :: parse subscript col assign String String [RToken] (RExpr, [RToken]) => [RStmt] [RToken]
      parse subscript col assign t_name _ _ (col_e, (TokRParen:TokEquals:after_eq)) =
        val_res = parse let rhs after_eq
        finish slice set stmt ":tensor-set-col:" t_name col_e val_res
      parse subscript col assign _ raw_name orig_rest _ =
        finish expr stmt (parse expr ([TokIdent raw_name, TokLParen] :: orig_rest))

fn :: finish slice set stmt String String RExpr (RExpr, [RToken]) => [RStmt] [RToken]
      finish slice set stmt helper t_name idx_e (val_e, after_rhs) =
        more = parse block stmts safe after_rhs
        prepend stmt (StmtExpr (ECall helper [EVar t_name, idx_e, val_e])) more

fn :: parse subscript assign after first String String [RToken] (RExpr, [RToken]) => [RStmt] [RToken]
      parse subscript assign after first t_name _ _ (idx1, (TokComma:TokRParen:TokEquals:after_eq)) =
        val_res = parse let rhs after_eq
        finish slice set stmt ":tensor-set-row:" t_name idx1 val_res
      parse subscript assign after first t_name raw_name orig_rest (idx1, (TokComma:more_ts)) =
        more_res = parse comma exprs more_ts
        parse subscript assign after idxs t_name raw_name orig_rest idx1 more_res
      parse subscript assign after first t_name _ _ (idx1, (TokRParen:TokEquals:after_eq)) =
        val_res = parse let rhs after_eq
        finish idx assign stmt t_name [idx1] val_res
      parse subscript assign after first t_name raw_name orig_rest (idx1, (TokRParen:TokComma:more_lhs)) =
        multi_res = collect multi subscript lhs more_lhs [EIndexAssign t_name [idx1] EUnit]
        finish multi subscript lhs t_name raw_name orig_rest multi_res
      parse subscript assign after first _ raw_name orig_rest _ =
        finish expr stmt (parse expr ([TokIdent raw_name, TokLParen] :: orig_rest))

fn :: parse subscript assign after idxs String String [RToken] RExpr ([RExpr], [RToken]) => [RStmt] [RToken]
      parse subscript assign after idxs t_name _ _ idx1 (more_idxs, (TokEquals:after_eq)) =
        val_res = parse let rhs after_eq
        finish idx assign stmt t_name ([idx1] :: more_idxs) val_res
      parse subscript assign after idxs t_name raw_name orig_rest idx1 (more_idxs, (TokComma:more_lhs)) =
        multi_res = collect multi subscript lhs more_lhs [EIndexAssign t_name ([idx1] :: more_idxs) EUnit]
        finish multi subscript lhs t_name raw_name orig_rest multi_res
      parse subscript assign after idxs _ raw_name orig_rest _ _ =
        finish expr stmt (parse expr ([TokIdent raw_name, TokLParen] :: orig_rest))

fn :: finish multi subscript lhs String String [RToken] (Bool, [RExpr], [RToken]) => [RStmt] [RToken]
      finish multi subscript lhs t_name _ _ (True, targets, after_eq) =
        finish multi idx assign t_name targets (parse let rhs after_eq)
      finish multi subscript lhs _ raw_name orig_rest (False, _, _) =
        finish expr stmt (parse expr ([TokIdent raw_name, TokLParen] :: orig_rest))

fn :: parse subscript assign stmt String String [RToken] => [RStmt] [RToken]
      parse subscript assign stmt t_name raw_name (TokComma:after_c) =
        parse subscript col assign t_name raw_name ([TokComma] :: after_c) (parse expr after_c)
      parse subscript assign stmt t_name raw_name ts =
        parse subscript assign after first t_name raw_name ts (parse expr ts)

fn :: parse block line ident String [RToken] => [RStmt] [RToken]
      parse block line ident name (TokEquals:rest)
        | is subscript ident name =
          e_res = wrap subscript let rhs (parse let rhs rest)
          finish mut stmt (extract fst str (split subscript name)) e_res
        | otherwise =
          e_res = parse let rhs rest
          finish let stmt name e_res
      parse block line ident name (TokComma:rest)
        | line has equals rest = parse tuple destructure stmt name (collect ident lhs list rest [name]) rest
      parse block line ident name (TokLParen:rest)
        | (is trailing underscore ident name) and (line has equals rest) =
          parse subscript assign stmt (str slice name 0 ((str len name) - 1)) name rest
      parse block line ident name (TokIdxLBracket:rest)
        | line has equals rest = parse block idx assign name ([TokIdxLBracket] :: rest) (collect bracket indices ([TokIdxLBracket] :: rest) [])
      parse block line ident name rest
        | (line has equals rest) OR (line has fat arrow rest) = ([], [TokIdent name] :: rest)
        | otherwise = finish expr stmt (parse expr ([TokIdent name] :: rest))

fn :: parse block idx assign String [RToken] ([RExpr], [RToken]) => [RStmt] [RToken]
      parse block idx assign name _ (idxs, (TokEquals:rest)) =
        val_res = parse expr rest
        finish idx assign stmt name idxs val_res
      parse block idx assign name orig_rest _ =
        finish expr stmt (parse expr ([TokIdent name] :: orig_rest))

fn :: finish idx assign stmt String [RExpr] (RExpr, [RToken]) => [RStmt] [RToken]
      finish idx assign stmt name idxs (val_e, rest) =
        more = parse block stmts safe rest
        prepend stmt (StmtIndexAssign name idxs val_e) more

fn :: finish let stmt String (RExpr, [RToken]) => [RStmt] [RToken]
      finish let stmt v      (e, rest)         =
        more = parse block stmts safe rest
        prepend stmt (StmtLet v e) more

fn :: finish mut stmt String (RExpr, [RToken]) => [RStmt] [RToken]
      finish mut stmt v      (e, rest)         =
        more = parse block stmts safe rest
        prepend stmt (StmtMut v e) more

fn :: finish dpipe stmt (RExpr, [RToken]) => [RStmt] [RToken]
      finish dpipe stmt (e, rest)         =  ([StmtExpr e], rest)

fn :: finish expr stmt (RExpr, [RToken]) => [RStmt] [RToken]
      finish expr stmt (e, rest)
        | (NOT (is echo expr e)) AND (next line has guard rest) = ([StmtExpr e], rest)
        | otherwise = prepend stmt (StmtExpr e) (parse block stmts safe rest)

fn :: parse block stmts safe [RToken] => [RStmt] [RToken]
      parse block stmts safe ts       =
        clean = skip newlines ts
        parse block safe dispatch clean

fn :: parse block safe dispatch [RToken]          => [RStmt] [RToken]
      parse block safe dispatch []                =  ([], [])
      parse block safe dispatch (TokRParen:rest)  =  ([], [TokRParen] :: rest)
      parse block safe dispatch (TokPipe:rest)    =  ([], [TokPipe] :: rest)
      parse block safe dispatch (TokPipeDot:rest) =  ([], [TokPipeDot] :: rest)
      parse block safe dispatch (TokDoublePipeDot:rest) = ([], [TokDoublePipeDot] :: rest)
      parse block safe dispatch (TokDoublePipe:rest)
        | line has arrow rest = finish dpipe stmt (parse case body dpipe ([TokDoublePipe] :: rest))
      parse block safe dispatch (TokMut:(TokIdent name):TokEquals:rest) =
        e_res = parse let rhs rest
        finish mut stmt name e_res
      parse block safe dispatch ((TokIdent name):rest)
        | is top decl start ([TokIdent name] :: rest) = ([], [TokIdent name] :: rest)
        | otherwise = parse block line ident name rest
      parse block safe dispatch (TokFn:rest)
        | is top decl start ([TokFn] :: rest) = ([], [TokFn] :: rest)
        | otherwise = parse block line ident "fn" rest
      parse block safe dispatch (TokOp:rest)
        | is top decl start ([TokOp] :: rest) = ([], [TokOp] :: rest)
        | otherwise = parse block line ident "op" rest
      parse block safe dispatch (TokType:rest)
        | is top decl start ([TokType] :: rest) = ([], [TokType] :: rest)
        | otherwise = parse block line ident "type" rest
      parse block safe dispatch (TokWith:rest)
        | is with block start ([TokWith] :: rest) = finish expr stmt (parse expr ([TokWith] :: rest))
        | otherwise = parse block line ident "with" rest
      parse block safe dispatch ts
        | (is top decl start ts) OR (line has fat arrow ts) = ([], ts)
        | otherwise = finish expr stmt (parse expr ts)

fn :: prepend stmt RStmt ([RStmt], [RToken]) => [RStmt] [RToken]
      prepend stmt s     (ss, rest)          =  ([s] :: ss, rest)

fn :: parse case body [RToken]          => RExpr [RToken]
      parse case body (TokNewline:rest) =
        clean = skip newlines rest
        parse case body newline rest clean
      parse case body (TokPipe:rest)    =
        finish guard expr (parse guards ([TokPipe] :: rest))
      parse case body (TokDoublePipe:rest) =
        parse case body dpipe ([TokDoublePipe] :: rest)
      parse case body ts                =
        e_res = parse expr ts
        check trailing comma and where e_res

fn :: parse case body newline [RToken] [RToken] => RExpr [RToken]
      parse case body newline _ (TokPipe:rest) =
        finish guard expr (parse guards ([TokPipe] :: rest))
      parse case body newline _ (TokDoublePipe:rest) =
        parse case body dpipe ([TokDoublePipe] :: rest)
      parse case body newline orig_rest _ =
        stmts_res = parse block stmts safe orig_rest
        finish block body stmts_res

fn :: finish block body ([RStmt], [RToken]) => RExpr [RToken]
      finish block body (stmts, rest)       =  (EBlock stmts, rest)

-- ── Top-Level Function, Operator, Scoped Global, Hardware & Type Decls ──

fn :: parse fn case for String [RToken] => RFnCase [RToken]
      parse fn case for _ (_:rest) =
        pats_res = parse case patterns rest
        parse fn case after pats pats_res
      parse fn case for _ [] = (FnCase [] [] EUnit, [])

fn :: parse fn case after pats ([RPattern], [RToken]) => RFnCase [RToken]
      parse fn case after pats (pats, (TokNewline:TokPipe:rest)) =
        g_res = parse guards ([TokPipe] :: rest)
        finish guarded case pats g_res
      parse fn case after pats (pats, (TokEquals:rest)) =
        parse fn case after eq pats rest (skip newlines rest)
      parse fn case after pats (pats, rest) = (FnCase pats [] EUnit, rest)

fn :: parse fn case after eq [RPattern] [RToken] [RToken] => RFnCase [RToken]
      parse fn case after eq pats _ (TokPipe:rest) =
        g_res = parse guards ([TokPipe] :: rest)
        finish guarded case pats g_res
      parse fn case after eq pats orig_rest _ =
        b_res = parse case body orig_rest
        finish body case pats b_res

fn :: finish guarded case [RPattern] ([RGuard], [RToken]) => RFnCase [RToken]
      finish guarded case pats       (guards, rest)       =  (FnCase pats guards EUnit, rest)

fn :: finish body case [RPattern] (RExpr, [RToken]) => RFnCase [RToken]
      finish body case pats       (body, rest)      =  (FnCase pats [] body, rest)

fn :: parse fn cases String  [RToken] => [RFnCase] [RToken]
      parse fn cases fn_name ts       =
        clean = skip newlines ts
        parse fn cases check fn_name clean

fn :: parse fn cases check String [RToken] => [RFnCase] [RToken]
      parse fn cases check fn_name ((TokIdent s):rest)
        | (encode literal underscores s) == fn_name = parse fn cases cont fn_name (parse fn case for fn_name ([TokIdent (encode literal underscores s)] :: rest))
        | otherwise = ([], [TokIdent s] :: rest)
      parse fn cases check "fn" (TokFn:rest)
        | NOT (is top decl start ([TokFn] :: rest)) =
          parse fn cases cont "fn" (parse fn case for "fn" ([TokIdent "fn"] :: rest))
      parse fn cases check "op" (TokOp:rest)
        | NOT (is top decl start ([TokOp] :: rest)) =
          parse fn cases cont "op" (parse fn case for "op" ([TokIdent "op"] :: rest))
      parse fn cases check "type" (TokType:rest) =
        parse fn cases cont "type" (parse fn case for "type" ([TokIdent "type"] :: rest))
      parse fn cases check "with" (TokWith:rest) =
        parse fn cases cont "with" (parse fn case for "with" ([TokIdent "with"] :: rest))
      parse fn cases check _ ts = ([], ts)

fn :: parse fn cases cont String (RFnCase, [RToken]) => [RFnCase] [RToken]
      parse fn cases cont fn_name (c, rest) =
        more = parse fn cases fn_name rest
        prepend case c more

fn :: prepend case RFnCase ([RFnCase], [RToken]) => [RFnCase] [RToken]
      prepend case c       (cs, rest)            =  ([c] :: cs, rest)

fn :: parse fn decl [RToken] => RFnDef [RToken]
      parse fn decl (TokFn:TokColonColon:rest) =
        parse bare decl rest
      parse fn decl (_:rest) =  (FnDef "unknown" [] "()" [], rest)
      parse fn decl []       =  (FnDef "unknown" [] "()" [], [])

fn :: parse fn decl ret String ([String], [RToken]) => RFnDef [RToken]
      parse fn decl ret name (params, (TokFatArrow:rest)) =
        rt_res = parse return types rest
        parse fn decl cases name params rt_res
      parse fn decl ret name (params, (TokArrow:rest)) =
        rt_res = parse return types rest
        parse fn decl cases name params rt_res
      parse fn decl ret name (params, rest) =
        parse fn decl cases name params ("()", rest)

fn :: parse fn decl cases String [String] (String, [RToken]) => RFnDef [RToken]
      parse fn decl cases name params (ret_ty, rest) =
        cs_res = parse fn cases name rest
        finish fn def name params ret_ty cs_res

fn :: finish fn def String [String] String ([RFnCase], [RToken]) => RFnDef [RToken]
      finish fn def name params ret_ty (cases, rest) =
        (FnDef name params ret_ty cases, rest)

-- ── Custom Operators (`op :: ...`) ──────────────────────────

fn :: join words underscore [String] => String
      join words underscore []       =  "op"
      join words underscore (w:[])   =  w
      join words underscore (w:ws)   =  w + "_" + (join words underscore ws)

fn :: scan op header [RToken] [String] [String] [Bool] => [String] [String] [Bool] [RToken]
      scan op header (TokFatArrow:rest) words params tmpl = (words, params, tmpl, rest)
      scan op header (TokArrow:rest) words params tmpl = (words, params, tmpl, rest)
      scan op header (TokNewline:rest) words params tmpl = (words, params, tmpl, [TokNewline] :: rest)
      scan op header (TokEof:rest) words params tmpl = (words, params, tmpl, [TokEof] :: rest)
      scan op header [] words params tmpl = (words, params, tmpl, [])
      scan op header ((TokIdent s):rest) words params tmpl
        | is upper ident s = scan op type slot words params tmpl (parse type tok ([TokIdent s] :: rest))
        | otherwise = scan op header rest (words :: [encode literal underscores s]) params (tmpl :: [False])
      scan op header (TokFn:rest) words params tmpl =
        scan op header rest (words :: ["fn"]) params (tmpl :: [False])
      scan op header (TokOp:rest) words params tmpl =
        scan op header rest (words :: ["op"]) params (tmpl :: [False])
      scan op header (TokImport:rest) words params tmpl =
        scan op header rest (words :: ["import"]) params (tmpl :: [False])
      scan op header (TokDo:rest) words params tmpl =
        scan op header rest (words :: ["do"]) params (tmpl :: [False])
      scan op header (TokHardware:rest) words params tmpl =
        scan op header rest (words :: ["hardware"]) params (tmpl :: [False])
      scan op header (TokOtherwise:rest) words params tmpl =
        scan op header rest (words :: ["otherwise"]) params (tmpl :: [False])
      scan op header (TokMut:rest) words params tmpl =
        scan op header rest (words :: ["mut"]) params (tmpl :: [False])
      scan op header (TokType:rest) words params tmpl =
        scan op header rest (words :: ["type"]) params (tmpl :: [False])
      scan op header (TokWith:rest) words params tmpl =
        scan op header rest (words :: ["with"]) params (tmpl :: [False])
      scan op header (TokAnd:rest) words params tmpl =
        scan op header rest (words :: ["and"]) params (tmpl :: [False])
      scan op header (TokOr:rest) words params tmpl =
        scan op header rest (words :: ["or"]) params (tmpl :: [False])
      scan op header (TokXor:rest) words params tmpl =
        scan op header rest (words :: ["xor"]) params (tmpl :: [False])
      scan op header (TokNot:rest) words params tmpl =
        scan op header rest (words :: ["not"]) params (tmpl :: [False])
      scan op header (TokPlus:rest) words params tmpl =
        scan op header rest (words :: ["+"]) params (tmpl :: [False])
      scan op header (TokMinus:rest) words params tmpl =
        scan op header rest (words :: ["-"]) params (tmpl :: [False])
      scan op header (TokStar:rest) words params tmpl =
        scan op header rest (words :: ["*"]) params (tmpl :: [False])
      scan op header (TokSlash:rest) words params tmpl =
        scan op header rest (words :: ["/"]) params (tmpl :: [False])
      scan op header (TokPercent:rest) words params tmpl =
        scan op header rest (words :: ["%"]) params (tmpl :: [False])
      scan op header (TokLParen:rest) words params tmpl =
        scan op type slot words params tmpl (parse type tok ([TokLParen] :: rest))
      scan op header (TokLBracket:rest) words params tmpl =
        scan op type slot words params tmpl (parse type tok ([TokLBracket] :: rest))
      scan op header (_:rest) words params tmpl =
        scan op header rest words params tmpl

fn :: scan op type slot [String] [String] [Bool] (String, [RToken]) => [String] [String] [Bool] [RToken]
      scan op type slot words params tmpl (ty_str, rest) =
        scan op header rest words (params :: [ty_str]) (tmpl :: [True])

fn :: match op keyword RToken       String => Bool
      match op keyword (TokIdent s) kw     =  (encode literal underscores s) == kw
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
        | (pat list count pats) > 0 AND (tok head ts_rest) != TokColonColon AND (match op keyword tok kw) =
          try parse op template (skip true slots t_rest) kw_rest ts_rest pats
      try parse op template (True:t_rest) kws ts pats
        | is top decl start ts = (False, [], ts)
        | otherwise = try parse op pat t_rest kws pats (parse pattern ts)
      try parse op template (False:t_rest) (kw:kw_rest) (tok:ts_rest) pats
        | (tok head ts_rest) != TokColonColon AND (match op keyword tok kw) = try parse op template t_rest kw_rest ts_rest pats
        | otherwise = (False, [], [tok] :: ts_rest)
      try parse op template _ _ ts _ = (False, [], ts)

fn :: skip true slots [Bool]        => [Bool]
      skip true slots (True:t_rest) =  skip true slots t_rest
      skip true slots other         =  other

fn :: try parse op pat [Bool] [String] [RPattern] (RPattern, [RToken]) => Bool [RPattern] [RToken]
      try parse op pat t_rest kws pats ((PatSeqBind v), rest) =
        try parse op template (skip true slots t_rest) kws rest (pats :: [PatSeqBind v])
      try parse op pat t_rest kws pats (pat, rest) =
        try parse op template t_rest kws rest (pats :: [pat])

fn :: parse op cases [Bool] [String] [RToken] => [RFnCase] [RToken]
      parse op cases tmpl kws ts =
        clean = skip newlines ts
        parse op cases step tmpl kws clean (try parse op template tmpl kws clean [])

fn :: parse op cases step [Bool] [String] [RToken] (Bool, [RPattern], [RToken]) => [RFnCase] [RToken]
      parse op cases step _ _ orig_ts (False, _, _) = ([], orig_ts)
      parse op cases step tmpl kws _ (True, pats, after_pats) =
        c_res = parse fn case after pats (pats, after_pats)
        parse op cases cont tmpl kws c_res

fn :: parse op cases cont [Bool] [String] (RFnCase, [RToken]) => [RFnCase] [RToken]
      parse op cases cont tmpl kws (c, rest) =
        more = parse op cases tmpl kws rest
        prepend case c more

fn :: parse op decl [RToken] => RFnDef [RToken]
      parse op decl (TokOp:TokColonColon:rest) =
        hdr = scan op header rest [] [] []
        finish op header hdr
      parse op decl ts       =
        hdr = scan op header ts [] [] []
        finish op header hdr

fn :: is prefix fn tmpl [Bool] [String] => Bool
      is prefix fn tmpl (False:_) (w:[]) = is lower ident w
      is prefix fn tmpl _ _ = False

fn :: parse bare decl [RToken] => RFnDef [RToken]
      parse bare decl ts       =
        hdr = scan op header ts [] [] []
        dispatch bare decl ts hdr

fn :: dispatch bare decl [RToken] ([String], [String], [Bool], [RToken]) => RFnDef [RToken]
      dispatch bare decl ((TokIdent name):rest) (words, _, tmpl, _)
        | is prefix fn tmpl tmpl words = parse fn decl ret (encode literal underscores name) (parse param types rest)
      dispatch bare decl (TokFn:rest) (words, _, tmpl, _)
        | is prefix fn tmpl tmpl words = parse fn decl ret "fn" (parse param types rest)
      dispatch bare decl (TokOp:rest) (words, _, tmpl, _)
        | is prefix fn tmpl tmpl words = parse fn decl ret "op" (parse param types rest)
      dispatch bare decl (TokType:rest) (words, _, tmpl, _)
        | is prefix fn tmpl tmpl words = parse fn decl ret "type" (parse param types rest)
      dispatch bare decl (TokWith:rest) (words, _, tmpl, _)
        | is prefix fn tmpl tmpl words = parse fn decl ret "with" (parse param types rest)
      dispatch bare decl _ hdr =
        finish op header hdr

fn :: finish op header ([String], [String], [Bool], [RToken]) => RFnDef [RToken]
      finish op header (words, params, tmpl, rest)            =
        mangled = join words underscore words
        rt_res = parse return types rest
        finish op decl mangled words params tmpl rt_res

fn :: finish op decl String [String] [String] [Bool] (String, [RToken]) => RFnDef [RToken]
      finish op decl mangled words params tmpl (ret_ty, rest) =
        cs_res = parse op cases tmpl words rest
        finish fn def mangled params ret_ty cs_res

-- ── Hardware MMIO Blocks (`hardware :: Name @ 0x...`) ───────

fn :: parse hw registers Int       [RToken] => [RFnDef] [RToken]
      parse hw registers base_addr ts       =
        clean = skip newlines ts
        parse hw reg step base_addr ts clean

fn :: parse hw reg step Int [RToken] [RToken] => [RFnDef] [RToken]
      parse hw reg step base_addr _ ((TokIdent reg_name):TokColon:rest) =
        ty_res = parse type tok rest
        parse hw reg offset base_addr reg_name ty_res
      parse hw reg step _ orig_ts _ = ([], orig_ts)

fn :: parse hw reg offset Int String (String, [RToken]) => [RFnDef] [RToken]
      parse hw reg offset base_addr reg_name (_, (TokAt:(TokInt offset):rest)) =
        reg_fn = FnDef reg_name [] "Int" [FnCase [] [] (EInt (base_addr + offset))]
        more = parse hw registers base_addr rest
        prepend fndef reg_fn more
      parse hw reg offset base_addr _ (_, rest) =
        parse hw registers base_addr (skip to newline rest)

fn :: prepend fndef RFnDef ([RFnDef], [RToken]) => [RFnDef] [RToken]
      prepend fndef f      (fs, rest)           =  ([f] :: fs, rest)

fn :: parse hardware decl [RToken] => [RFnDef] [RToken]
      parse hardware decl (TokHardware:TokColonColon:(TokIdent hw_name):TokAt:(TokInt base_addr):rest) =
        hw_fn = FnDef hw_name [] "Int" [FnCase [] [] (EInt base_addr)]
        regs_res = parse hw registers base_addr rest
        prepend fndef hw_fn regs_res
      parse hardware decl (_:rest) =  ([], skip to newline rest)
      parse hardware decl []       =  ([], [])

-- ── Type Declarations (Sum Variants & Product Record Fields) ─

fn :: parse variants [RToken]          => [RVariant] [RToken]
      parse variants (TokNewline:rest) =  ([], rest)
      parse variants (TokEof:rest)     =  ([], [TokEof] :: rest)
      parse variants []                =  ([], [])
      parse variants (TokPipe:rest)    =  parse variants rest
      parse variants ((TokIdent ctor):rest) =
        args_res = parse variant args rest
        parse variants cont ctor args_res
      parse variants (_:rest)          =  ([], skip to newline rest)

fn :: parse variant args [RToken]          => [String] [RToken]
      parse variant args (TokPipe:rest)    =  ([], [TokPipe] :: rest)
      parse variant args (TokNewline:rest) =  ([], [TokNewline] :: rest)
      parse variant args (TokEof:rest)     =  ([], [TokEof] :: rest)
      parse variant args []                =  ([], [])
      parse variant args ts                =
        t1 = parse type tok ts
        parse variant args cont t1

fn :: parse variant args cont (String, [RToken]) => [String] [RToken]
      parse variant args cont (ty, rest)         =
        more = parse variant args rest
        prepend str ty more

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
        | is prim type ctor ctor = [ctor]
        | otherwise = []
      norm variant args _      args     =  args

fn :: parse variants cont String ([String], [RToken]) => [RVariant] [RToken]
      parse variants cont ctor   (args, rest)         =
        more = parse variants rest
        prepend variant (TypeVariant ctor (norm variant args ctor args)) more

fn :: prepend variant RVariant ([RVariant], [RToken]) => [RVariant] [RToken]
      prepend variant v        (vs, rest)             =  ([v] :: vs, rest)

fn :: strip optional colon [RToken]        => [RToken]
      strip optional colon (TokColon:rest) =  rest
      strip optional colon ts              =  ts

fn :: parse field type more (String, [RToken]) Bool => String [RToken]
      parse field type more (acc, ((TokIdent s):rest)) is_app
        | (is upper ident s) AND (tok head rest) != TokColon =
          t2 = parse type tok ([TokIdent s] :: rest)
          parse field type step acc t2
        | otherwise = finish return types acc ([TokIdent s] :: rest) is_app
      parse field type more (acc, (TokLBracket:rest)) _ =
        t2 = parse type tok ([TokLBracket] :: rest)
        parse field type step acc t2
      parse field type more (acc, (TokLParen:rest)) _ =
        t2 = parse type tok ([TokLParen] :: rest)
        parse field type step acc t2
      parse field type more (acc, rest) is_app = finish return types acc rest is_app

fn :: parse field type step String (String, [RToken]) => String [RToken]
      parse field type step acc (next_ty, rest) =
        parse field type more (acc + ", " + next_ty, rest) True

fn :: parse field type tok [RToken] => String [RToken]
      parse field type tok ts =
        parse field type more (parse type tok ts) False

fn :: parse record fields [RToken]          => [RField] [RToken]
      parse record fields (TokNewline:(TokIdent fname):TokColon:rest) =
        ty_res = parse field type tok rest
        parse record fields cont fname ty_res
      parse record fields (TokNewline:TokType:TokColon:rest) =
        ty_res = parse field type tok rest
        parse record fields cont "type" ty_res
      parse record fields (TokNewline:TokWith:TokColon:rest) =
        ty_res = parse field type tok rest
        parse record fields cont "with" ty_res
      parse record fields (TokNewline:rest) =  ([], rest)
      parse record fields (TokEof:rest)     =  ([], [TokEof] :: rest)
      parse record fields []                =  ([], [])
      parse record fields (TokComma:rest)   =  parse record fields rest
      parse record fields ((TokIdent fname):rest) =
        ty_res = parse field type tok (strip optional colon rest)
        parse record fields cont fname ty_res
      parse record fields (TokType:rest)    =
        ty_res = parse field type tok (strip optional colon rest)
        parse record fields cont "type" ty_res
      parse record fields (TokWith:rest)    =
        ty_res = parse field type tok (strip optional colon rest)
        parse record fields cont "with" ty_res
      parse record fields (_:rest)          =  ([], skip to newline rest)

fn :: parse record fields cont String (String, [RToken]) => [RField] [RToken]
      parse record fields cont fname (fty, rest) =
        more = parse record fields rest
        prepend field (TypeField fname fty) more

fn :: prepend field RField ([RField], [RToken]) => [RField] [RToken]
      prepend field f      (fs, rest)           =  ([f] :: fs, rest)

fn :: collect type decl params [RToken] [String] => [String] [RToken]
      collect type decl params (TokEquals:rest) acc = (acc, [TokEquals] :: rest)
      collect type decl params ((TokIdent p):rest) acc
        | is upper ident p = collect type decl params rest (acc :: [p])
      collect type decl params ts acc = (acc, ts)

fn :: subst one tparam str String String String => String
      subst one tparam str ty_s tp letter
        | ty_s == tp = letter
        | ty_s == ("[" + tp + "]") = "[" + letter + "]"
        | otherwise = ty_s

fn :: subst tparams in str String [String] Int => String
      subst tparams in str ty_s [] _ = ty_s
      subst tparams in str ty_s (tp:tps) idx
        | (str len tp) == 1 = subst tparams in str ty_s tps (idx + 1)
        | otherwise = subst tparams in str (subst one tparam str ty_s tp (char from code (65 + idx))) tps (idx + 1)

fn :: subst tparams in strs [String] [String] => [String]
      subst tparams in strs [] _ = []
      subst tparams in strs (s:ss) tps = [subst tparams in str s tps 0] :: (subst tparams in strs ss tps)

fn :: subst tparams in variants [RVariant] [String] => [RVariant]
      subst tparams in variants [] _ = []
      subst tparams in variants ((TypeVariant c args):vs) tps =
        [TypeVariant c (subst tparams in strs args tps)] :: (subst tparams in variants vs tps)

fn :: subst tparams in fields [RField] [String] => [RField]
      subst tparams in fields [] _ = []
      subst tparams in fields ((TypeField fnm fty):fs) tps =
        [TypeField fnm (subst tparams in str fty tps 0)] :: (subst tparams in fields fs tps)

fn :: apply tparams to tdef [String] (RTypeDef, [RToken]) => RTypeDef [RToken]
      apply tparams to tdef [] res = res
      apply tparams to tdef tps ((TypeDef nm vs fs), rest) =
        (TypeDef nm (subst tparams in variants vs tps) (subst tparams in fields fs tps), rest)

fn :: parse type decl after params String ([String], [RToken]) => RTypeDef [RToken]
      parse type decl after params name (tps, (TokEquals:TokNewline:rest)) =
        parse type decl after params name (tps, [TokEquals] :: (skip newlines rest))
      parse type decl after params name (tps, (TokEquals:(TokIdent first_w):rest))
        | is upper ident first_w = apply tparams to tdef tps (finish sum type name (parse variants ([TokIdent first_w] :: rest)))
        | otherwise = apply tparams to tdef tps (finish record type name (parse record fields ([TokIdent first_w] :: rest)))
      parse type decl after params name (tps, (TokEquals:TokType:rest)) =
        apply tparams to tdef tps (finish record type name (parse record fields ([TokType] :: rest)))
      parse type decl after params name (tps, (TokEquals:TokWith:rest)) =
        apply tparams to tdef tps (finish record type name (parse record fields ([TokWith] :: rest)))
      parse type decl after params _ (_, rest) = (TypeDef "Unknown" [] [], skip to newline rest)

fn :: parse type decl [RToken] => RTypeDef [RToken]
      parse type decl (TokType:(TokIdent name):rest) =
        parse type decl after params name (collect type decl params rest [])
      parse type decl (_:rest) =  (TypeDef "Unknown" [] [], skip to newline rest)
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
        | k == target and v == 0 = 0
        | k == target = -1
        | otherwise = lookup var arity rest target

fn :: lookup arity [RArityEntry] String => Int
      lookup arity []            _      =  -1
      lookup arity ((ArityEntry k v):rest) target
        | v >= 0 AND k == target = v
        | otherwise = lookup arity rest target

fn :: has arity prefix loop [RArityEntry] String Int => Bool
      has arity prefix loop [] _ _ = False
      has arity prefix loop ((ArityEntry k v):rest) pref plen
        | v >= 0 AND (str starts with k pref) AND ((str len k) == plen OR (str char at k plen) == 95) = True
        | otherwise = has arity prefix loop rest pref plen

fn :: has arity prefix [RArityEntry] String => Bool
      has arity prefix arities       pref   =
        has arity prefix loop arities pref (str len pref)

fn :: filter arity prefix loop [RArityEntry] String Int => [RArityEntry]
      filter arity prefix loop [] _ _ = []
      filter arity prefix loop ((ArityEntry k v):rest) pref plen
        | v >= 0 AND (str starts with k pref) AND ((str len k) == plen OR (str char at k plen) == 95) = [ArityEntry k v] :: (filter arity prefix loop rest pref plen)
        | otherwise = filter arity prefix loop rest pref plen

fn :: has variadic param [String] => Bool
      has variadic param []       =  False
      has variadic param (p:ps)
        | str contains p "..." = True
        | otherwise = has variadic param ps

fn :: fn def arity [String] => Int
fn def arity params
| has variadic param params = 999
        | otherwise = str list count params

fn :: arity matches Int Int    => Bool
      arity matches 999 actual =  actual >= 1
      arity matches ar  actual =  ar >= 0 AND ar == actual

fn :: builtin arity entries => [RArityEntry]
      builtin arity entries =
        [ArityEntry "assert_equals" 2, ArityEntry "assert_true" 1, ArityEntry "send_to" 2, ArityEntry "ask_to" 2, ArityEntry "send_through" 2, ArityEntry "receive_from" 1, ArityEntry "try_receive_from" 1, ArityEntry "receive_from_timeout" 2, ArityEntry "stop" 1, ArityEntry "agent_alive" 1, ArityEntry "new_mailbox" 0, ArityEntry "new_channel" 0, ArityEntry "new_bounded_channel" 1, ArityEntry "chan_send" 2, ArityEntry "chan_recv" 1, ArityEntry "chan_try_recv" 1, ArityEntry "str_len" 1, ArityEntry "str_char_at" 2, ArityEntry "str_slice" 3, ArityEntry "str_contains" 2, ArityEntry "str_starts_with" 2, ArityEntry "str_concat" 2, ArityEntry "int_to_str" 1, ArityEntry "str_to_int" 1, ArityEntry "char_from_code" 1, ArityEntry "trim_str" 1, ArityEntry "read_file" 1, ArityEntry "load_rg_source" 1, ArityEntry "read_bytes" 1, ArityEntry "write_bytes" 2, ArityEntry "write_file" 2, ArityEntry "shell_exec" 1, ArityEntry "list_str_len" 1, ArityEntry "list_dir" 1, ArityEntry "file_lstat" 1, ArityEntry "sha256_file" 1, ArityEntry "sha256_str" 1, ArityEntry "sha256_raw" 1, ArityEntry "sha256_bytes" 1, ArityEntry "sys_os" 0, ArityEntry "sys_arch" 0, ArityEntry "sys_mkdir" 2, ArityEntry "sys_chmod" 2, ArityEntry "sys_exec" 3, ArityEntry "sys_chdir" 1, ArityEntry "sys_getcwd" 0, ArityEntry "sys_getenv" 1, ArityEntry "sys_setenv" 2, ArityEntry "sys_exit" 1, ArityEntry "sys_getuid" 0, ArityEntry "sys_getgid" 0, ArityEntry "sys_getpid" 0, ArityEntry "sys_time_ms" 0, ArityEntry "sys_deadline_ms" 0, ArityEntry "sys_remaining_ms" 0, ArityEntry "sys_sleep_ms" 1, ArityEntry "sys_open_mode" 2, ArityEntry "sys_open" 3, ArityEntry "sys_close" 1, ArityEntry "sys_read_fd" 2, ArityEntry "sys_write_fd" 2, ArityEntry "sys_poll" 3, ArityEntry "sys_terminate" 2, ArityEntry "sys_kill" 2, ArityEntry "sys_call" 7, ArityEntry "sys_pipe" 0, ArityEntry "sys_waitpid" 2, ArityEntry "sys_username" 1, ArityEntry "sys_user_groups" 1, ArityEntry "sys_lookup_uid_gid" 1, ArityEntry "sys_setresgid" 1, ArityEntry "sys_setgroups" 1, ArityEntry "sys_setresuid" 1, ArityEntry "sys_execve" 3, ArityEntry "sys_read_pass" 1, ArityEntry "cli_args" 0, ArityEntry "cmm_live_blocks" 0, ArityEntry "cmm_cond_spared" 0, ArityEntry "cmm_cond_freed" 0, ArityEntry "cmm_same_ptr" 2, ArityEntry "seq_map" 2, ArityEntry "par_map" 2, ArityEntry "seq_filter" 2, ArityEntry "par_filter" 2]

fn :: collect fn arities acc [RFnDef] [RArityEntry] => [RArityEntry]
      collect fn arities acc []       acc           =  acc :: (builtin arity entries)
      collect fn arities acc ((FnDef name params _ _):fs) acc =
        collect fn arities acc fs (acc :: [ArityEntry name (fn def arity params)])

fn :: collect fn arities [RFnDef] => [RArityEntry]
      collect fn arities fns      =  collect fn arities acc fns []

fn :: field list count [RField] => Int
      field list count []       =  0
      field list count (_:fs)   =  1 + (field list count fs)

fn :: collect variant arities String [RVariant] => [RArityEntry]
      collect variant arities _         []         =  []
      collect variant arities tdef_name ((TypeVariant _ []):vs) =
        collect variant arities tdef_name vs
      collect variant arities tdef_name ((TypeVariant ctor args):vs) =
        n = str list count args
        [ArityEntry ctor n, ArityEntry (tdef_name + "." + ctor) n] :: (collect variant arities tdef_name vs)

fn :: collect field arities [RField] => [RArityEntry]
      collect field arities []       =  []
      collect field arities ((TypeField fname _):fs)
        | str contains fname "." = [ArityEntry fname 1, ArityEntry (ident base name fname) 1] :: (collect field arities fs)
        | otherwise = [ArityEntry fname 1] :: (collect field arities fs)

fn :: collect type arities [RTypeDef] => [RArityEntry]
      collect type arities []         =  []
      collect type arities ((TypeDef name vars []):ts) =
        (collect variant arities name vars) :: (collect type arities ts)
      collect type arities ((TypeDef name vars fields):ts) =
        [ArityEntry name (field list count fields)] :: (collect variant arities name vars) :: (collect field arities fields) :: (collect type arities ts)

fn :: str list count [String] => Int
      str list count []       =  0
      str list count (_:xs)   =  1 + (str list count xs)

fn :: take exprs [RExpr] Int => [RExpr]
      take exprs _       0   =  []
      take exprs []      _   =  []
      take exprs (x:xs)  n   =  [x] :: (take exprs xs (n - 1))

fn :: drop exprs [RExpr] Int => [RExpr]
      drop exprs xs      0   =  xs
      drop exprs []      _   =  []
      drop exprs (_:xs)  n   =  drop exprs xs (n - 1)

fn :: fold echo args [RExpr]  [RArityEntry] => [RExpr]
      fold echo args []       _             =  []
      fold echo args ((EVar fn_name):rest) arities =
        ar = lookup arity arities fn_name
        fold echo var fn_name ar rest arities
      fold echo args (e:rest) arities       =
        [norm expr e arities] :: (fold echo args rest arities)

fn :: fold echo var String Int [RExpr] [RArityEntry] => [RExpr]
      fold echo var fn_name ar rest arities
        | ar > 0 AND (expr list count rest) >= ar = [ECall fn_name (norm expr list (take exprs rest ar) arities)] :: (fold echo args (drop exprs rest ar) arities)
        | ar == 0 = [ECall fn_name []] :: (fold echo args rest arities)
        | otherwise = [EVar fn_name] :: (fold echo args rest arities)

fn :: expr list count [RExpr] => Int
      expr list count []      =  0
      expr list count (_:xs)  =  1 + (expr list count xs)

fn :: join op word String String => String
      join op word ""     w      =  w
      join op word cur    w      =  cur + "_" + w

fn :: can complete op [RArityEntry] String [RExpr] => Bool
      can complete op arities cand [] = (lookup arity arities cand) >= 0
      can complete op arities cand ((EVar w):rest)
        | (lookup arity arities cand) >= 0 = True
        | has arity prefix arities (join op word cand w) = can complete op arities (join op word cand w) rest
        | otherwise = can complete op arities cand rest
      can complete op arities cand (_:rest)
        | (lookup arity arities cand) >= 0 = True
        | otherwise = can complete op arities cand rest

fn :: extract mixfix start String [RExpr] [RArityEntry] [RArityEntry] [RExpr] => String [RExpr]
      extract mixfix start w rest arities w_cands operands
        | (NOT (str starts with w "__lambda_")) AND (NOT ((is std builtin w) AND (expr list count operands) > 0)) AND (has arity prefix w_cands w) AND (can complete op w_cands w rest) = extract mixfix call w rest w_cands operands
        | otherwise = extract mixfix call "" rest arities (operands :: [EVar w])

fn :: extract mixfix call String [RExpr] [RArityEntry] [RExpr] => String [RExpr]
      extract mixfix call cur_name [] _ operands = (cur_name, operands)
      extract mixfix call "" ((EVar w):rest) arities operands =
        w_cands = filter arity prefix loop arities w (str len w)
        extract mixfix start w rest arities w_cands operands
      extract mixfix call cur_name ((EVar w):rest) arities operands
        | (NOT ((is std builtin cur_name) AND (expr list count operands) > 0)) AND (has arity prefix arities (join op word cur_name w)) AND (can complete op arities (join op word cur_name w) rest) = extract mixfix call (join op word cur_name w) rest arities operands
        | otherwise = extract mixfix call cur_name rest arities (operands :: [EVar w])
      extract mixfix call cur_name (arg:rest) arities operands =
        extract mixfix call cur_name rest arities (operands :: [arg])

fn :: reduce postfix spine [RExpr] [RArityEntry] [RExpr] => [RExpr]
      reduce postfix spine [] _ stack = stack
      reduce postfix spine ((EVar w):rest) arities stack
        | (lookup arity arities w) > 0 AND (expr list count stack) > 0 = reduce postfix spine rest arities [ECall w stack]
        | otherwise = reduce postfix spine rest arities (stack :: [EVar w])
      reduce postfix spine (item:rest) arities stack =
        reduce postfix spine rest arities (stack :: [item])

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
      std builtin arity "str_len"  =  1
      std builtin arity "str_char_at" = 2
      std builtin arity "str_slice" = 3
      std builtin arity "str_contains" = 2
      std builtin arity "str_starts_with" = 2
      std builtin arity "str_concat" = 2
      std builtin arity "int_to_str" = 1
      std builtin arity "str_to_int" = 1
      std builtin arity "char_from_code" = 1
      std builtin arity "trim_str" = 1
      std builtin arity "read_file" = 1
      std builtin arity "load_rg_source" = 1
      std builtin arity "read_bytes" = 1
      std builtin arity "write_bytes" = 2
      std builtin arity "write_file" = 2
      std builtin arity "shell_exec" = 1
      std builtin arity "list_str_len" = 1
      std builtin arity "list_dir" = 1
      std builtin arity "file_lstat" = 1
      std builtin arity "sha256_file" = 1
      std builtin arity "sha256_str" = 1
      std builtin arity "sha256_raw" = 1
      std builtin arity "sha256_bytes" = 1
      std builtin arity "sys_mkdir" = 2
      std builtin arity "sys_chmod" = 2
      std builtin arity "sys_exec" = 3
      std builtin arity "sys_chdir" = 1
      std builtin arity "sys_getenv" = 1
      std builtin arity "sys_setenv" = 2
      std builtin arity "sys_exit" = 1
      std builtin arity "sys_sleep_ms" = 1
      std builtin arity "sys_open_mode" = 2
      std builtin arity "sys_open" = 3
      std builtin arity "sys_close" = 1
      std builtin arity "sys_read_fd" = 2
      std builtin arity "sys_write_fd" = 2
      std builtin arity "sys_poll" = 3
      std builtin arity "sys_terminate" = 2
      std builtin arity "sys_kill" = 2
      std builtin arity "sys_call" = 7
      std builtin arity "sys_waitpid" = 2
      std builtin arity "sys_username" = 1
      std builtin arity "sys_lookup_uid_gid" = 1
      std builtin arity "sys_user_groups" = 1
      std builtin arity "sys_setresgid" = 1
      std builtin arity "sys_setgroups" = 1
      std builtin arity "sys_setresuid" = 1
      std builtin arity "sys_execve" = 3
      std builtin arity "sys_read_pass" = 1
      std builtin arity "new_bounded_channel" = 1
      std builtin arity "chan_send" = 2
      std builtin arity "chan_recv" = 1
      std builtin arity "chan_try_recv" = 1
      std builtin arity "send_through" = 2
      std builtin arity "receive_from" = 1
      std builtin arity "try_receive_from" = 1
      std builtin arity "receive_from_timeout" = 2
      std builtin arity "cmm_same_ptr" = 2
      std builtin arity "seq_map" = 2
      std builtin arity "par_map" = 2
      std builtin arity "seq_filter" = 2
      std builtin arity "par_filter" = 2
      std builtin arity _          =  -1

fn :: collapse fn ref args [RExpr] [RArityEntry] => [RExpr]
      collapse fn ref args [] _ = []
      collapse fn ref args ((EVar w1):(EVar w2):(EVar w3):(EVar w4):rest) arities
        | (lookup arity arities (w1 + "_" + w2 + "_" + w3 + "_" + w4)) >= 0 = [EVar (w1 + "_" + w2 + "_" + w3 + "_" + w4)] :: (collapse fn ref args rest arities)
      collapse fn ref args ((EVar w1):(EVar w2):(EVar w3):rest) arities
        | (lookup arity arities (w1 + "_" + w2 + "_" + w3)) >= 0 = [EVar (w1 + "_" + w2 + "_" + w3)] :: (collapse fn ref args rest arities)
      collapse fn ref args ((EVar w1):(EVar w2):rest) arities
        | (lookup arity arities (w1 + "_" + w2)) >= 0 = [EVar (w1 + "_" + w2)] :: (collapse fn ref args rest arities)
      collapse fn ref args (e:rest) arities =
        [e] :: (collapse fn ref args rest arities)

fn :: maybe collapse args [RExpr] Int [RArityEntry] => [RExpr]
      maybe collapse args args expected_ar arities
        | expected_ar >= 0 and (expr list count args) <= expected_ar = args
        | otherwise = collapse fn ref args args arities

fn :: has longer arity prefix [RArityEntry] String [RExpr] => Bool
      has longer arity prefix arities fn_name ((EVar w):rest)
        | (is upper ident fn_name) OR (is upper ident w) = False
        | otherwise = (has arity prefix arities (fn_name + "_" + w)) and (can complete op arities (fn_name + "_" + w) rest)
      has longer arity prefix _ _ _ = False

fn :: split send to args [RExpr] [RExpr] => Bool [RExpr] RExpr
      split send to args ((EVar "to"):target:[]) acc = (True, acc, target)
      split send to args (x:xs) acc = split send to args xs (acc :: [x])
      split send to args [] _ = (False, [], EUnit)

fn :: pack send to msg [RExpr]     => RExpr
      pack send to msg (single:[]) =  single
      pack send to msg msgs        =  ETuple msgs

fn :: finish send to norm String [RExpr] [RArityEntry] (Bool, [RExpr], RExpr) => RExpr
      finish send to norm _ _ arities (True, msg_atoms, target) =
        normed_msgs = norm expr list (collapse fn ref args msg_atoms arities) arities
        ECall "send_to" [pack send to msg normed_msgs, norm expr target arities]
      finish send to norm fn_name args arities (False, _, _) =
        norm call mixfix fn_name args arities (extract mixfix call "" ([EVar fn_name] :: args) arities [])

fn :: finish ask prefix [RExpr]            [RArityEntry] => RExpr
      finish ask prefix (target:msg_atoms) arities
        | (expr list count msg_atoms) > 0 =
          normed_msgs = norm expr list (collapse fn ref args msg_atoms arities) arities
          ECall "ask_to" [pack send to msg normed_msgs, norm expr target arities]
      finish ask prefix args               arities       =
        ECall "ask" (norm expr list args arities)

fn :: finish ask norm String [RExpr] [RArityEntry] (Bool, [RExpr], RExpr) => RExpr
      finish ask norm _ _ arities (True, msg_atoms, target) =
        normed_msgs = norm expr list (collapse fn ref args msg_atoms arities) arities
        ECall "ask_to" [pack send to msg normed_msgs, norm expr target arities]
      finish ask norm fn_name args arities (False, _, _)
        | (not (has longer arity prefix arities fn_name args)) and (lookup arity arities fn_name) < 0 =
          finish ask prefix args arities
        | otherwise =
          norm call mixfix fn_name args arities (extract mixfix call "" ([EVar fn_name] :: args) arities [])

fn :: norm map in target RExpr RExpr [RArityEntry] => RExpr
      norm map in target fn_e (ECall ":tensor-row-slice:" (base_e:_)) arities =
        ECall ":tensor-map-rows-in:" [fn_e, norm expr base_e arities]
      norm map in target fn_e (ECall ":tensor-col-slice:" (base_e:_)) arities =
        ECall ":tensor-map-cols-in:" [fn_e, norm expr base_e arities]
      norm map in target fn_e (EVar v) _
        | is subscript ident v = ECall ":tensor-map-elems-in:" [fn_e, EVar (extract fst str (split subscript v))]
      norm map in target fn_e target_e arities =
        ECall ":tensor-map-elems-in:" [fn_e, norm expr target_e arities]

fn :: norm map pure target String RExpr RExpr [RArityEntry] => RExpr
      norm map pure target _ fn_e (ECall ":tensor-row-slice:" (base_e:_)) arities =
        ECall ":tensor-map-rows:" [fn_e, norm expr base_e arities]
      norm map pure target _ fn_e (ECall ":tensor-col-slice:" (base_e:_)) arities =
        ECall ":tensor-map-cols:" [fn_e, norm expr base_e arities]
      norm map pure target _ fn_e (EVar v) _
        | is subscript ident v = ECall ":tensor-map-elems:" [fn_e, EVar (extract fst str (split subscript v))]
      norm map pure target fn_name fn_e target_e arities =
        ECall fn_name [fn_e, norm expr target_e arities]

fn :: norm map call String [RExpr] [RArityEntry] => RExpr
      norm map call _ (fn_arg:(EVar "in"):target_arg:[]) arities =
        norm map in target (norm expr fn_arg arities) target_arg arities
      norm map call fn_name (fn_arg:target_arg:[]) arities =
        norm map pure target fn_name (norm expr fn_arg arities) target_arg arities
      norm map call fn_name args arities =
        ECall fn_name (norm expr list args arities)

fn :: is fn arg RExpr [RArityEntry] => Bool
      is fn arg (ECall fn_name _) _ =
        (fn_name == "__lambda__") OR (str starts with fn_name "__lambda_")
      is fn arg (EVar v) arities =
        ((lookup arity arities v) > 0) OR (str starts with v "__lambda_")
      is fn arg _ _ = False

fn :: norm fold call [RExpr] [RArityEntry] => RExpr
      norm fold call (a1:a2:target_e:[]) arities
        | is fn arg a1 arities = ECall "fold" [norm expr a1 arities, norm expr a2 arities, norm expr target_e arities]
        | is fn arg a2 arities = ECall "fold" [norm expr a2 arities, norm expr a1 arities, norm expr target_e arities]
        | otherwise = ECall "fold" [norm expr a1 arities, norm expr a2 arities, norm expr target_e arities]
      norm fold call args arities =
        ECall "fold" (norm expr list args arities)

fn :: take one fn ref [RExpr] [RArityEntry] => RExpr [RExpr]
      take one fn ref ((EVar w1):(EVar w2):(EVar w3):(EVar w4):rest) arities
        | (lookup arity arities (w1 + "_" + w2 + "_" + w3 + "_" + w4)) >= 0 = (EVar (w1 + "_" + w2 + "_" + w3 + "_" + w4), rest)
      take one fn ref ((EVar w1):(EVar w2):(EVar w3):rest) arities
        | (lookup arity arities (w1 + "_" + w2 + "_" + w3)) >= 0 = (EVar (w1 + "_" + w2 + "_" + w3), rest)
      take one fn ref ((EVar w1):(EVar w2):rest) arities
        | (lookup arity arities (w1 + "_" + w2)) >= 0 = (EVar (w1 + "_" + w2), rest)
      take one fn ref (e:rest) _ = (e, rest)
      take one fn ref [] _ = (EUnit, [])

fn :: consume op words String [RExpr] [RArityEntry] => String [RExpr]
      consume op words cur ((EVar w):rest) arities
        | (NOT (str starts with w "__lambda_")) AND (has arity prefix arities (cur + "_" + w)) AND (can complete op arities (cur + "_" + w) rest) =
          consume op words (cur + "_" + w) rest arities
      consume op words cur rest _ = (cur, rest)

fn :: is infix comb word String => Bool
      is infix comb word "map"      = True
      is infix comb word "||map"    = True
      is infix comb word "filter"   = True
      is infix comb word "||filter" = True
      is infix comb word "fold"     = True
      is infix comb word "send"     = True
      is infix comb word "ask"      = True
      is infix comb word _          = False

fn :: is infix comb start [RExpr] => Bool
      is infix comb start ((EVar w):_) = is infix comb word w
      is infix comb start _            = False

fn :: has placeholder arg [RExpr] => Bool
      has placeholder arg [] = False
      has placeholder arg ((EVar "_"):_) = True
      has placeholder arg (_:xs) = has placeholder arg xs

fn :: replace placeholder arg [RExpr] RExpr => [RExpr]
      replace placeholder arg [] _ = []
      replace placeholder arg ((EVar "_"):xs) rep = [rep] :: (replace placeholder arg xs rep)
      replace placeholder arg (x:xs) rep = [x] :: (replace placeholder arg xs rep)

fn :: norm pipe ask RExpr [RExpr] [RArityEntry] (Bool, [RExpr], RExpr) => RExpr
      norm pipe ask _ _ arities (True, msg_atoms, target) =
        finish ask norm "ask" [] arities (True, msg_atoms, target)
      norm pipe ask left_e args arities (False, _, _) =
        norm call "ask" (args :: [left_e]) arities

fn :: reduce infix map step RExpr String (RExpr, [RExpr]) [RArityEntry] => Bool RExpr
      reduce infix map step _ _ (EUnit, []) _ = (False, EUnit)
      reduce infix map step acc w (fn_arg, rem) arities =
        acc1 = norm map call w [fn_arg, acc] arities
        reduce infix steps acc1 rem arities

fn :: reduce infix filter step RExpr String (RExpr, [RExpr]) [RArityEntry] => Bool RExpr
      reduce infix filter step _ _ (EUnit, []) _ = (False, EUnit)
      reduce infix filter step acc w (fn_arg, rem) arities =
        acc1 = ECall w [norm expr fn_arg arities, acc]
        reduce infix steps acc1 rem arities

fn :: reduce infix fold step RExpr (RExpr, [RExpr]) [RArityEntry] => Bool RExpr
      reduce infix fold step _ (EUnit, []) _ = (False, EUnit)
      reduce infix fold step acc (a1, rem1) arities =
        reduce infix fold step2 acc a1 (take one fn ref rem1 arities) arities

fn :: reduce infix fold step2 RExpr RExpr (RExpr, [RExpr]) [RArityEntry] => Bool RExpr
      reduce infix fold step2 _ _ (EUnit, []) _ = (False, EUnit)
      reduce infix fold step2 acc a1 (a2, rem2) arities =
        acc1 = norm fold call [a1, a2, acc] arities
        reduce infix steps acc1 rem2 arities

fn :: reduce infix op take RExpr String [RExpr] Int [RArityEntry] => Bool RExpr
      reduce infix op take acc mangled c_after need arities
        | (expr list count c_after) >= need =
          stage_args = norm expr list (take exprs c_after need) arities
          rem = drop exprs c_after need
          reduce infix steps (ECall mangled ([acc] :: stage_args)) rem arities
        | otherwise = (False, EUnit)

fn :: reduce infix mixfix check String Int [RExpr] [RArityEntry] => Bool RExpr
      reduce infix mixfix check mangled ar c_ops arities
        | arity matches ar (expr list count c_ops) = (True, ECall mangled (norm expr list c_ops arities))
        | otherwise = (False, EUnit)

fn :: reduce infix mixfix RExpr (String, [RExpr]) [RArityEntry] => Bool RExpr
      reduce infix mixfix _ (mangled, ops) arities =
        ar = lookup arity arities mangled
        c_ops = maybe collapse args ops ar arities
        reduce infix mixfix check mangled ar c_ops arities

fn :: reduce infix op dispatch RExpr String [RExpr] [RArityEntry] String [RExpr] Int [RArityEntry] => Bool RExpr
      reduce infix op dispatch acc _ _ _ mangled [] ar _
        | ar >= 1 = (True, ECall mangled [acc])
      reduce infix op dispatch acc _ _ w_cands mangled after_words ar arities
        | ar >= 1 AND (NOT (has longer arity prefix w_cands mangled after_words)) =
          c_after = maybe collapse args after_words (ar - 1) arities
          reduce infix op take acc mangled c_after (ar - 1) arities
      reduce infix op dispatch acc w orig_rest w_cands _ _ _ arities =
        reduce infix mixfix acc (extract mixfix call w orig_rest w_cands [acc]) arities

fn :: reduce infix op step RExpr String [RExpr] [RArityEntry] (String, [RExpr]) [RArityEntry] => Bool RExpr
      reduce infix op step acc w orig_rest w_cands (mangled, after_words) arities =
        ar = lookup arity w_cands mangled
        reduce infix op dispatch acc w orig_rest w_cands mangled after_words ar arities

fn :: has any arity entry [RArityEntry] => Bool
      has any arity entry [] = False
      has any arity entry (_:_) = True

fn :: reduce infix try op RExpr String [RExpr] [RArityEntry] [RArityEntry] => Bool RExpr
      reduce infix try op acc w rest w_cands arities
        | has any arity entry w_cands =
          reduce infix op step acc w rest w_cands (consume op words w rest w_cands) arities
        | is std builtin w =
          (True, ECall w ([acc] :: (norm expr list (collapse fn ref args rest arities) arities)))
        | otherwise = (False, EUnit)

fn :: reduce infix steps RExpr [RExpr] [RArityEntry] => Bool RExpr
      reduce infix steps acc [] _ = (True, acc)
      reduce infix steps acc ((EVar w):rest) arities
        | w == "map" OR w == "||map" =
          reduce infix map step acc w (take one fn ref rest arities) arities
        | w == "filter" OR w == "||filter" =
          reduce infix filter step acc w (take one fn ref rest arities) arities
        | w == "fold" =
          reduce infix fold step acc (take one fn ref rest arities) arities
        | w == "send" =
          (True, finish send to norm "send" ([acc] :: rest) arities (split send to args ([acc] :: rest) []))
        | w == "ask" =
          (True, norm pipe ask acc rest arities (split send to args ([acc] :: rest) []))
        | NOT (str starts with w "__lambda_") =
          reduce infix try op acc w rest (filter arity prefix loop arities w (str len w)) arities
        | otherwise = (False, EUnit)
      reduce infix steps _ _ _ = (False, EUnit)

fn :: finish pipe step RExpr String [RExpr] [RArityEntry] (Bool, RExpr) => RExpr
      finish pipe step _ _ _ _ (True, res_e) = res_e
      finish pipe step l_norm fn_name args arities (False, _) =
        norm call fn_name ([l_norm] :: args) arities

fn :: norm pipe step RExpr RExpr [RArityEntry] => RExpr
      norm pipe step left_e EUnit arities =
        EBlock [StmtExpr (norm expr left_e arities), StmtExpr EUnit]
      norm pipe step left_e (EVar "echo") arities =
        EEcho [norm expr left_e arities]
      norm pipe step left_e (EEcho args) arities
        | has placeholder arg args =
          EEcho (fold echo args (collapse fn ref args (replace placeholder arg args left_e) arities) arities)
        | otherwise =
          EEcho (fold echo args (collapse fn ref args (args :: [left_e]) arities) arities)
      norm pipe step left_e (EVar fn_name) arities
        | is upper ident fn_name = ECall fn_name [norm expr left_e arities]
        | ((lookup arity arities fn_name) >= 1) OR (is std builtin fn_name) OR ((lookup arity arities fn_name) == (0 - 2)) =
          ECall fn_name [norm expr left_e arities]
        | otherwise =
          EBlock [StmtLet fn_name (norm expr left_e arities)]
      norm pipe step left_e (ECall fn_name args) arities
        | has placeholder arg args =
          norm call fn_name (replace placeholder arg args left_e) arities
        | is upper ident fn_name =
          ECall fn_name ([norm expr left_e arities] :: (norm expr list args arities))
        | otherwise =
          l_norm = norm expr left_e arities
          finish pipe step l_norm fn_name args arities (reduce infix steps l_norm ([EVar fn_name] :: args) arities)
      norm pipe step left_e rhs_e arities =
        ECall "__chain__" [norm expr rhs_e arities, norm expr left_e arities]

fn :: norm pipe args [RExpr] [RArityEntry] => RExpr
      norm pipe args (left_e:rhs_e:[]) arities = norm pipe step left_e rhs_e arities
      norm pipe args args arities = ECall "__pipe__" (norm expr list args arities)

fn :: norm call with cands String [RExpr] [RArityEntry] [RArityEntry] Int => RExpr
      norm call with cands fn_name args arities cands ar
        | ar >= 0 and (not (has longer arity prefix cands fn_name args)) = ECall fn_name (norm expr list (maybe collapse args args ar arities) arities)
        | (not (is std builtin fn_name)) and (has arity prefix cands fn_name) and (can complete op cands fn_name args) = norm call mixfix fn_name args arities (extract mixfix call fn_name args cands [])
        | is infix comb start args = norm call infix or mixfix fn_name args arities (reduce infix steps (norm expr (EVar fn_name) arities) args arities)
        | otherwise = norm call mixfix fn_name args arities (extract mixfix call "" ([EVar fn_name] :: args) arities [])

fn :: norm call infix or mixfix String [RExpr] [RArityEntry] (Bool, RExpr) => RExpr
      norm call infix or mixfix _ _ _ (True, res_e) = res_e
      norm call infix or mixfix fn_name args arities (False, _) =
        norm call mixfix fn_name args arities (extract mixfix call "" ([EVar fn_name] :: args) arities [])

fn :: norm call snake or cands String [RExpr] [RArityEntry] Int => RExpr
      norm call snake or cands fn_name args arities ar
        | ar >= 0 = ECall fn_name (norm expr list (maybe collapse args args ar arities) arities)
        | otherwise =
          cands = filter arity prefix loop arities fn_name (str len fn_name)
          norm call with cands fn_name args arities cands (lookup arity cands fn_name)

fn :: norm call fast or cands String [RExpr] [RArityEntry] => RExpr
      norm call fast or cands fn_name args arities
        | is upper ident fn_name =
          ECall fn_name (norm expr list (maybe collapse args args (lookup arity arities fn_name) arities) arities)
        | str contains fn_name "_" =
          norm call snake or cands fn_name args arities (lookup arity arities fn_name)
        | otherwise =
          cands = filter arity prefix loop arities fn_name (str len fn_name)
          norm call with cands fn_name args arities cands (lookup arity cands fn_name)

fn :: norm call chain start [RExpr] [RArityEntry] => RExpr
      norm call chain start (first_e:rest) arities
        | is infix comb start rest =
          norm call chain infix (first_e:rest) arities (reduce infix steps (norm expr first_e arities) rest arities)
      norm call chain start args arities =
        norm call chain args arities (extract mixfix call "" args arities [])

fn :: norm call chain infix [RExpr] [RArityEntry] (Bool, RExpr) => RExpr
      norm call chain infix _ _ (True, res_e) = res_e
      norm call chain infix args arities (False, _) =
        norm call chain args arities (extract mixfix call "" args arities [])

fn :: norm call String  [RExpr] [RArityEntry] => RExpr
      norm call fn_name args    arities
        | fn_name == "__lambda__" = ECall "__lambda__" args
        | fn_name == "__pipe__" = norm pipe args args arities
        | fn_name == "agent" and (not (has longer arity prefix arities "agent" args)) = ECall "agent" (norm expr list (collapse fn ref args args arities) arities)
        | fn_name == "send" = finish send to norm fn_name args arities (split send to args args [])
        | fn_name == "ask" = finish ask norm fn_name args arities (split send to args args [])
        | (fn_name == "map" or fn_name == "||map") and (not (has longer arity prefix arities fn_name args)) = norm map call fn_name (collapse fn ref args args arities) arities
        | fn_name == "fold" and (not (has longer arity prefix arities "fold" args)) = norm fold call (collapse fn ref args args arities) arities
        | (is std builtin fn_name) and ((str contains fn_name "_") or (not (has longer arity prefix arities fn_name args))) = ECall fn_name (norm expr list (maybe collapse args args (std builtin arity fn_name) arities) arities)
        | fn_name == "__chain__" = norm call chain start args arities
        | otherwise = norm call fast or cands fn_name args arities

fn :: norm call chain [RExpr] [RArityEntry] (String, [RExpr]) => RExpr
      norm call chain orig_args arities (mangled, operands) =
        ar = lookup arity arities mangled
        c_ops = maybe collapse args operands ar arities
        norm call chain step orig_args arities mangled ar c_ops

fn :: norm call chain step [RExpr] [RArityEntry] String Int [RExpr] => RExpr
      norm call chain step orig_args arities mangled ar c_ops
        | arity matches ar (expr list count c_ops) = ECall mangled (norm expr list c_ops arities)
        | ar > 0 and (expr list count c_ops) == 0 = EVar mangled
        | otherwise = norm call chain try infix orig_args arities mangled ar c_ops

fn :: norm call chain try infix [RExpr] [RArityEntry] String Int [RExpr] => RExpr
      norm call chain try infix (first_e:rest) arities mangled ar c_ops =
        norm call chain after infix (first_e:rest) arities mangled ar c_ops (reduce infix steps (norm expr first_e arities) rest arities)
      norm call chain try infix orig_args arities mangled ar c_ops =
        norm call chain fallback (norm expr list orig_args arities) arities mangled ar c_ops

fn :: norm call chain after infix [RExpr] [RArityEntry] String Int [RExpr] (Bool, RExpr) => RExpr
      norm call chain after infix _ _ _ _ _ (True, res_e) = res_e
      norm call chain after infix orig_args arities mangled ar c_ops (False, _) =
        norm call chain fallback (norm expr list orig_args arities) arities mangled ar c_ops

fn :: norm call chain fallback [RExpr] [RArityEntry] String Int [RExpr] => RExpr
      norm call chain fallback normed arities mangled ar c_ops =
        finish postfix or partial "__chain__" normed (reduce postfix spine normed arities []) mangled ar c_ops arities

fn :: norm call mixfix String [RExpr] [RArityEntry] (String, [RExpr]) => RExpr
      norm call mixfix orig_name orig_args arities (mangled, operands) =
        ar = lookup arity arities mangled
        c_ops = maybe collapse args operands ar arities
        norm call mixfix step orig_name orig_args arities mangled ar c_ops

fn :: norm call mixfix step String [RExpr] [RArityEntry] String Int [RExpr] => RExpr
      norm call mixfix step orig_name orig_args arities mangled ar c_ops
        | arity matches ar (expr list count c_ops) = ECall mangled (norm expr list c_ops arities)
        | ar > 0 and (expr list count c_ops) == 0 = EVar mangled
        | otherwise = norm call mixfix after infix orig_name orig_args arities mangled ar c_ops (reduce infix steps (norm expr (EVar orig_name) arities) orig_args arities)

fn :: norm call mixfix after infix String [RExpr] [RArityEntry] String Int [RExpr] (Bool, RExpr) => RExpr
      norm call mixfix after infix _ _ _ _ _ _ (True, res_e) = res_e
      norm call mixfix after infix orig_name orig_args arities mangled ar c_ops (False, _) =
        norm call mixfix fallback orig_name (norm expr list orig_args arities) arities mangled ar c_ops

fn :: norm call mixfix fallback String [RExpr] [RArityEntry] String Int [RExpr] => RExpr
      norm call mixfix fallback orig_name normed arities mangled ar c_ops =
        finish postfix or partial orig_name normed (reduce postfix spine ([EVar orig_name] :: normed) arities []) mangled ar c_ops arities

fn :: finish postfix or partial String [RExpr] [RExpr] String Int [RExpr] [RArityEntry] => RExpr
      finish postfix or partial _ _ ((ECall f a):[]) _ _ _ _ = ECall f a
      finish postfix or partial _ _ _ mangled ar c_ops arities
        | ar > 1 and (expr list count c_ops) > 0 and (expr list count c_ops) < ar =
          ECall mangled (norm expr list c_ops arities)
      finish postfix or partial orig_name normed_args _ _ _ _ _ =
        ECall orig_name normed_args

fn :: flatten mixfix rhs RExpr [RArityEntry] => [RExpr]
      flatten mixfix rhs (ECall "__chain__" args) _ = args
      flatten mixfix rhs (ECall r_name r_args) arities
        | ((lookup arity arities r_name) < 0 and (not (is std builtin r_name))) or (has longer arity prefix arities r_name r_args) = [EVar r_name] :: r_args
      flatten mixfix rhs other _             =  [other]

fn :: can absorb mixfix conj String [RExpr] String RExpr [RArityEntry] => Bool
      can absorb mixfix conj fn_name args conj_word r arities =
        full_args = [EVar fn_name] :: args :: [EVar conj_word] :: (flatten mixfix rhs r arities)
        full_res = extract mixfix call "" full_args arities []
        can absorb mixfix verify conj_word arities full_res

fn :: can absorb mixfix verify String [RArityEntry] (String, [RExpr]) => Bool
      can absorb mixfix verify conj_word arities (full_mangled, full_ops) =
        ar = lookup arity arities full_mangled
        c_ops = maybe collapse args full_ops ar arities
        (str contains full_mangled ("_" + conj_word)) and (arity matches ar (expr list count c_ops))

fn :: norm expr RExpr              [RArityEntry] => RExpr
      norm expr (EVar name)        arities
        | is upper ident name = EVar name
        | (lookup var arity arities name) == 0 = ECall name []
        | is subscript ident name = EVar (extract fst str (split subscript name))
        | otherwise = EVar name
      norm expr (ENot inner)       arities       =  ENot (norm expr inner arities)
      norm expr (EOut (EVar name)) arities
        | (lookup arity arities (name + "_out")) == 0 = ECall (name + "_out") []
      norm expr (EOut inner)       arities       =  EOut (norm expr inner arities)
      norm expr (EBin OpAnd (EVar fn_name) r) arities
        | (lookup arity arities fn_name) < 0 AND (can absorb mixfix conj fn_name [] "and" r arities) = norm call fn_name ([EVar "and"] :: (flatten mixfix rhs r arities)) arities
      norm expr (EBin OpAnd (ECall fn_name args) r) arities
        | (lookup arity arities fn_name) < 0 AND (can absorb mixfix conj fn_name args "and" r arities) = norm call fn_name (args :: [EVar "and"] :: (flatten mixfix rhs r arities)) arities
      norm expr (EBin OpOr (EVar fn_name) r) arities
        | (lookup arity arities fn_name) < 0 AND (can absorb mixfix conj fn_name [] "or" r arities) = norm call fn_name ([EVar "or"] :: (flatten mixfix rhs r arities)) arities
      norm expr (EBin OpOr (ECall fn_name args) r) arities
        | (lookup arity arities fn_name) < 0 AND (can absorb mixfix conj fn_name args "or" r arities) = norm call fn_name (args :: [EVar "or"] :: (flatten mixfix rhs r arities)) arities
      norm expr (EBin bop l r)     arities       =  EBin bop (norm expr l arities) (norm expr r arities)
      norm expr (ECall fn_name args) arities     =  norm call fn_name args arities
      norm expr (EEcho args)       arities       =  EEcho (fold echo args (collapse fn ref args args arities) arities)
      norm expr (EStrInterp parts) arities       =  EStrInterp (norm expr list parts arities)
      norm expr (EList elems)      arities       =  EList (norm expr list elems arities)
      norm expr (ETuple elems)     arities       =  ETuple (norm expr list elems arities)
      norm expr (ETensor elems)    arities       =  ETensor (norm expr list elems arities)
      norm expr (EEinsum es subs)  arities       =  EEinsum (norm expr list es arities) subs
      norm expr (EHadamard bop l s1 r s2) arities = EHadamard bop (norm expr l arities) s1 (norm expr r arities) s2
      norm expr (EIndex base idxs) arities       =  EIndex (norm expr base arities) (norm expr list idxs arities)
      norm expr (EIndexAssign t idxs v) arities  =  EIndexAssign t (norm expr list idxs arities) (norm expr v arities)
      norm expr (ESeqSelect b m)   arities       =  ESeqSelect (norm expr b arities) m
      norm expr (EBlock stmts)     arities       =  EBlock (norm stmt list stmts arities)
      norm expr (EGuard guards)    arities       =  EGuard (norm guard list guards arities)
      norm expr (EWhere body binds) arities      =  EWhere (norm expr body arities) (norm where list binds arities)
      norm expr (EParPipe branches) arities      =  EParPipe (norm expr list branches arities)
      norm expr (EWithCtx c v b)   arities       =  EWithCtx c (norm expr v arities) (norm expr b arities)
      norm expr (EWithRegion q b)  arities       =  EWithRegion q (norm expr b arities)
      norm expr e                  _             =  e

fn :: norm expr list [RExpr] [RArityEntry] => [RExpr]
      norm expr list []      _             =  []
      norm expr list (e:es)  arities       =  [norm expr e arities] :: (norm expr list es arities)

fn :: bind pat local arities RPattern [RArityEntry] => [RArityEntry]
      bind pat local arities (PatVar v) arities = [ArityEntry v (0 - 2)] :: arities
      bind pat local arities (PatSeqBind v) arities = [ArityEntry v (0 - 2)] :: arities
      bind pat local arities (PatCons h t) arities = bind pat local arities t (bind pat local arities h arities)
      bind pat local arities (PatTuple ps) arities = bind pat list local arities ps arities
      bind pat local arities (PatCtor _ ps) arities = bind pat list local arities ps arities
      bind pat local arities _ arities = arities

fn :: bind pat list local arities [RPattern] [RArityEntry] => [RArityEntry]
      bind pat list local arities [] arities = arities
      bind pat list local arities (p:ps) arities = bind pat list local arities ps (bind pat local arities p arities)

fn :: bind where local arities [RWhereBind] [RArityEntry] => [RArityEntry]
      bind where local arities [] arities = arities
      bind where local arities ((WhereBind _ v _):wbs) arities
        | v != "" = bind where local arities wbs ([ArityEntry v (0 - 2)] :: arities)
        | otherwise = bind where local arities wbs arities

fn :: is pipe var target String [RArityEntry] => Bool
      is pipe var target v arities =
        (v != "echo") AND (NOT (is upper ident v)) AND (NOT (is std builtin v)) AND ((lookup arity arities v) <= 0)

fn :: norm stmt list [RStmt]            [RArityEntry] => [RStmt]
      norm stmt list []                 _             =  []
      norm stmt list ((StmtLet v e):ss) arities       =
        [StmtLet v (norm expr e arities)] :: (norm stmt list ss ([ArityEntry v (0 - 2)] :: arities))
      norm stmt list ((StmtMut v e):ss) arities       =
        [StmtMut v (norm expr e arities)] :: (norm stmt list ss ([ArityEntry v (0 - 2)] :: arities))
      norm stmt list ((StmtExpr (ECall "__pipe__" (left_e:(EVar v):[]))):ss) arities
        | is pipe var target v arities =
          norm pipe var stmt left_e v ss arities
      norm stmt list ((StmtExpr e):ss)  arities       =  [StmtExpr (norm expr e arities)] :: (norm stmt list ss arities)
      norm stmt list ((StmtIndexAssign t idxs e):ss) arities = [StmtIndexAssign t (norm expr list idxs arities) (norm expr e arities)] :: (norm stmt list ss arities)

fn :: extract fst expr (RExpr, [RToken]) => RExpr
      extract fst expr (e, _)            =  e

fn :: norm pipe var stmt RExpr String [RStmt] [RArityEntry] => [RStmt]
      norm pipe var stmt left_e v ss arities
        | is subscript ident v =
          base_v = extract fst str (split subscript v)
          sub_e = extract fst expr (wrap subscript let rhs (left_e, []))
          [StmtMut base_v (norm expr sub_e arities)] :: (norm stmt list ss ([ArityEntry base_v (0 - 2), ArityEntry v (0 - 2)] :: arities))
        | otherwise =
          [StmtLet v (norm expr left_e arities)] :: (norm stmt list ss ([ArityEntry v (0 - 2)] :: arities))

fn :: norm where list [RWhereBind] [RArityEntry] => [RWhereBind]
      norm where list []           _             =  []
      norm where list ((WhereBind e v idxs):wbs) arities = [WhereBind (norm expr e arities) v idxs] :: (norm where list wbs arities)

fn :: norm guard list [RGuard] [RArityEntry] => [RGuard]
      norm guard list []       _             =  []
      norm guard list ((GuardBranch c b):gs) arities = [GuardBranch (norm expr c arities) (norm expr b arities)] :: (norm guard list gs arities)

fn :: norm case body RExpr [RArityEntry] => RExpr
      norm case body (EWhere body binds) arities =
        ar1 = bind where local arities binds arities
        EWhere (norm expr body ar1) (norm where list binds ar1)
      norm case body body arities = norm expr body arities

fn :: filter arities for wset [RArityEntry] [String] => [RArityEntry]
      filter arities for wset [] _ = []
      filter arities for wset ((ArityEntry k v):rest) wset
        | ident words all in (ident base name k) wset = [ArityEntry k v] :: (filter arities for wset rest wset)
        | otherwise = filter arities for wset rest wset

fn :: norm case list [RFnCase] [RArityEntry] => [RFnCase]
      norm case list []        _             =  []
      norm case list ((FnCase pats guards body):cs) arities =
        wset = collect expr ident words body (collect guard list ident words guards [])
        filtered_arities = filter arities for wset arities wset
        case_arities = bind pat list local arities pats filtered_arities
        [FnCase pats (norm guard list guards case_arities) (norm case body body case_arities)] :: (norm case list cs arities)

fn :: norm fndef list acc [RFnDef] [RArityEntry] [RFnDef] => [RFnDef]
      norm fndef list acc []       _             acc      =  acc
      norm fndef list acc ((FnDef name params ret_ty cases):fs) arities acc =
        norm fndef list acc fs arities (acc :: [FnDef name params ret_ty (norm case list cases arities)])

fn :: norm fndef list [RFnDef] [RArityEntry] => [RFnDef]
      norm fndef list fns      arities       =  norm fndef list acc fns arities []

fn :: extract lambda params [RExpr] => [String] RExpr
      extract lambda params (body_e:[]) = ([], body_e)
      extract lambda params ((EStr p):rest) =
        prepend str expr p (extract lambda params rest)
      extract lambda params (_:rest) = extract lambda params rest
      extract lambda params [] = ([], EUnit)

fn :: prepend str expr String ([String], RExpr) => [String] RExpr
      prepend str expr s (xs, e) = ([s] :: xs, e)

fn :: collect expr free locals RExpr [String] [String] [String] => [String]
      collect expr free locals (EVar v) outer_locals shadowed acc
        | (str in seen list v outer_locals) AND (NOT (str in seen list v shadowed)) AND (NOT (str in seen list v acc)) = acc :: [v]
        | otherwise = acc
      collect expr free locals (ENot e) outer_locals shadowed acc =
        collect expr free locals e outer_locals shadowed acc
      collect expr free locals (EOut e) outer_locals shadowed acc =
        collect expr free locals e outer_locals shadowed acc
      collect expr free locals (EBin _ l r) outer_locals shadowed acc =
        collect expr free locals r outer_locals shadowed (collect expr free locals l outer_locals shadowed acc)
      collect expr free locals (ECall "__lambda__" args) outer_locals shadowed acc =
        collect lambda free locals (extract lambda params args) outer_locals shadowed acc
      collect expr free locals (ECall fn_name args) outer_locals shadowed acc =
        acc1 = collect expr free locals (EVar fn_name) outer_locals shadowed acc
        collect expr list free locals args outer_locals shadowed acc1
      collect expr free locals (EEcho args) outer_locals shadowed acc =
        collect expr list free locals args outer_locals shadowed acc
      collect expr free locals (EStrInterp parts) outer_locals shadowed acc =
        collect expr list free locals parts outer_locals shadowed acc
      collect expr free locals (EList elems) outer_locals shadowed acc =
        collect expr list free locals elems outer_locals shadowed acc
      collect expr free locals (ETuple elems) outer_locals shadowed acc =
        collect expr list free locals elems outer_locals shadowed acc
      collect expr free locals (ETensor elems) outer_locals shadowed acc =
        collect expr list free locals elems outer_locals shadowed acc
      collect expr free locals (EEinsum es _) outer_locals shadowed acc =
        collect expr list free locals es outer_locals shadowed acc
      collect expr free locals (EHadamard _ l _ r _) outer_locals shadowed acc =
        collect expr free locals r outer_locals shadowed (collect expr free locals l outer_locals shadowed acc)
      collect expr free locals (EIndex b idxs) outer_locals shadowed acc =
        collect expr list free locals idxs outer_locals shadowed (collect expr free locals b outer_locals shadowed acc)
      collect expr free locals (EIndexAssign t idxs v) outer_locals shadowed acc =
        a1 = collect expr free locals (EVar t) outer_locals shadowed acc
        a2 = collect expr list free locals idxs outer_locals shadowed a1
        collect expr free locals v outer_locals shadowed a2
      collect expr free locals (ESeqSelect b _) outer_locals shadowed acc =
        collect expr free locals b outer_locals shadowed acc
      collect expr free locals (EBlock stmts) outer_locals shadowed acc =
        collect stmt list free locals stmts outer_locals shadowed acc
      collect expr free locals (EGuard gs) outer_locals shadowed acc =
        collect guard list free locals gs outer_locals shadowed acc
      collect expr free locals (EWhere b wbs) outer_locals shadowed acc =
        sh1 = collect where bound vars wbs shadowed
        a1 = collect where list free locals wbs outer_locals sh1 acc
        collect expr free locals b outer_locals sh1 a1
      collect expr free locals (EParPipe bs) outer_locals shadowed acc =
        collect expr list free locals bs outer_locals shadowed acc
      collect expr free locals (EWithCtx c v b) outer_locals shadowed acc =
        a1 = collect expr free locals v outer_locals shadowed acc
        collect expr free locals b outer_locals ([c] :: shadowed) a1
      collect expr free locals (EWithRegion _ b) outer_locals shadowed acc =
        collect expr free locals b outer_locals shadowed acc
      collect expr free locals _ _ _ acc = acc

fn :: split raw comma loop String Int Int Int [String] => [String]
      split raw comma loop s start pos len acc
        | pos >= len = acc :: [str slice s start len]
        | (str char at s pos) == 44 = split raw comma loop s (pos + 1) (pos + 1) len (acc :: [str slice s start pos])
        | otherwise = split raw comma loop s start (pos + 1) len acc

fn :: split raw comma strs String => [String]
      split raw comma strs "" = []
      split raw comma strs s = split raw comma loop s 0 0 (str len s) []

fn :: expand lambda param names [String] => [String]
      expand lambda param names [] = []
      expand lambda param names (p:ps)
        | str starts with p "(" = (split raw comma strs (str slice p 1 ((str len p) - 1))) :: (expand lambda param names ps)
        | otherwise = [p] :: (expand lambda param names ps)

fn :: collect lambda free locals ([String], RExpr) [String] [String] [String] => [String]
      collect lambda free locals (lparams, lbody) outer_locals shadowed acc =
        collect expr free locals lbody outer_locals ((expand lambda param names lparams) :: shadowed) acc

fn :: collect expr list free locals [RExpr] [String] [String] [String] => [String]
      collect expr list free locals [] _ _ acc = acc
      collect expr list free locals (e:es) outer_locals shadowed acc =
        collect expr list free locals es outer_locals shadowed (collect expr free locals e outer_locals shadowed acc)

fn :: collect stmt list free locals [RStmt] [String] [String] [String] => [String]
      collect stmt list free locals [] _ _ acc = acc
      collect stmt list free locals ((StmtLet v e):ss) outer_locals shadowed acc =
        a1 = collect expr free locals e outer_locals shadowed acc
        collect stmt list free locals ss outer_locals ([v] :: shadowed) a1
      collect stmt list free locals ((StmtMut v e):ss) outer_locals shadowed acc =
        a1 = collect expr free locals e outer_locals shadowed acc
        collect stmt list free locals ss outer_locals ([v] :: shadowed) a1
      collect stmt list free locals ((StmtExpr e):ss) outer_locals shadowed acc =
        a1 = collect expr free locals e outer_locals shadowed acc
        collect stmt list free locals ss outer_locals shadowed a1
      collect stmt list free locals ((StmtIndexAssign t idxs e):ss) outer_locals shadowed acc =
        a1 = collect expr free locals (EIndexAssign t idxs e) outer_locals shadowed acc
        collect stmt list free locals ss outer_locals shadowed a1

fn :: collect guard list free locals [RGuard] [String] [String] [String] => [String]
      collect guard list free locals [] _ _ acc = acc
      collect guard list free locals ((GuardBranch c b):gs) outer_locals shadowed acc =
        a1 = collect expr free locals c outer_locals shadowed acc
        a2 = collect expr free locals b outer_locals shadowed a1
        collect guard list free locals gs outer_locals shadowed a2

fn :: collect where list free locals [RWhereBind] [String] [String] [String] => [String]
      collect where list free locals [] _ _ acc = acc
      collect where list free locals ((WhereBind e _ _):wbs) outer_locals shadowed acc =
        collect where list free locals wbs outer_locals shadowed (collect expr free locals e outer_locals shadowed acc)

fn :: make poly type vars Int Int => [String]
      make poly type vars idx count
        | idx >= count = []
        | otherwise = [char from code (65 + (idx % 26))] :: (make poly type vars (idx + 1) count)

fn :: make lambda param ty vars [String] Int => [String] Int
      make lambda param ty vars [] idx = ([], idx)
      make lambda param ty vars (p:ps) idx
        | str starts with p "(" =
          tvs = split raw comma strs (str slice p 1 ((str len p) - 1))
          k = str list count tvs
          tup_ty = "(" + (join comma ty strs (make poly type vars idx (idx + k))) + ")"
          prepend ty var idx tup_ty (make lambda param ty vars ps (idx + k))
        | otherwise =
          v = char from code (65 + (idx % 26))
          prepend ty var idx v (make lambda param ty vars ps (idx + 1))

fn :: prepend ty var idx String ([String], Int) => [String] Int
      prepend ty var idx s (xs, next_idx) = ([s] :: xs, next_idx)

fn :: var to pat String => RPattern
      var to pat "_" = PatWild
      var to pat v
        | str starts with v "(" = PatTuple (vars to pat list (split raw comma strs (str slice v 1 ((str len v) - 1))))
        | otherwise = PatVar v

fn :: vars to pat list [String] => [RPattern]
      vars to pat list [] = []
      vars to pat list (v:vs) = [var to pat v] :: (vars to pat list vs)

fn :: vars to expr list [String] => [RExpr]
      vars to expr list [] = []
      vars to expr list (v:vs) = [EVar v] :: (vars to expr list vs)

fn :: build lambda call expr String [String] => RExpr
      build lambda call expr lname [] = EVar lname
      build lambda call expr lname caps = ECall lname (vars to expr list caps)

fn :: ensure non empty lambda params [String] => [String]
      ensure non empty lambda params [] = ["_"]
      ensure non empty lambda params ps = ps

fn :: lift lambda node ([String], RExpr) [String] Int [RFnDef] => RExpr Int [RFnDef]
      lift lambda node (lparams, lbody) locals cnt lifted =
        bound_names = expand lambda param names lparams
        lifted_body = lift expr lambdas lbody (locals :: bound_names) (cnt + 1) lifted
        finish lift lambda lparams locals cnt lifted_body

fn :: finish lift lambda [String] [String] Int (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift lambda lparams locals my_id (body1, cnt1, lifted1) =
        bound_names = expand lambda param names lparams
        caps = collect expr free locals body1 locals bound_names []
        eff_params = ensure non empty lambda params lparams
        all_params = caps :: eff_params
        lname = "__rg_lambda_" + (int to str my_id)
        finish lift lambda fn lname caps all_params body1 cnt1 lifted1 (make lambda param ty vars all_params 0)

fn :: finish lift lambda fn String [String] [String] RExpr Int [RFnDef] ([String], Int) => RExpr Int [RFnDef]
      finish lift lambda fn lname caps all_params body1 cnt1 lifted1 (ty_vars, next_idx) =
        ret_var = char from code (65 + (next_idx % 26))
        lfn = FnDef lname ty_vars ret_var [FnCase (vars to pat list all_params) [] body1]
        (build lambda call expr lname caps, cnt1, lifted1 :: [lfn])

fn :: lift expr lambdas RExpr [String] Int [RFnDef] => RExpr Int [RFnDef]
      lift expr lambdas (ECall "__lambda__" args) locals cnt lifted =
        lift lambda node (extract lambda params args) locals cnt lifted
      lift expr lambdas (ENot inner) locals cnt lifted =
        wrap lift not (lift expr lambdas inner locals cnt lifted)
      lift expr lambdas (EOut inner) locals cnt lifted =
        wrap lift out (lift expr lambdas inner locals cnt lifted)
      lift expr lambdas (EBin bop l r) locals cnt lifted =
        lift bin lambdas bop (lift expr lambdas l locals cnt lifted) r locals
      lift expr lambdas (ECall fn_name args) locals cnt lifted =
        wrap lift call fn_name (lift expr list lambdas args locals cnt lifted)
      lift expr lambdas (EEcho args) locals cnt lifted =
        wrap lift echo (lift expr list lambdas args locals cnt lifted)
      lift expr lambdas (EStrInterp parts) locals cnt lifted =
        wrap lift interp (lift expr list lambdas parts locals cnt lifted)
      lift expr lambdas (EList elems) locals cnt lifted =
        wrap lift list (lift expr list lambdas elems locals cnt lifted)
      lift expr lambdas (ETuple elems) locals cnt lifted =
        wrap lift tuple (lift expr list lambdas elems locals cnt lifted)
      lift expr lambdas (ETensor elems) locals cnt lifted =
        wrap lift tensor (lift expr list lambdas elems locals cnt lifted)
      lift expr lambdas (EIndex b idxs) locals cnt lifted =
        lift index lambdas (lift expr lambdas b locals cnt lifted) idxs locals
      lift expr lambdas (EIndexAssign t idxs v) locals cnt lifted =
        lift idx assign lambdas t (lift expr list lambdas idxs locals cnt lifted) v locals
      lift expr lambdas (ESeqSelect b m) locals cnt lifted =
        wrap lift seq m (lift expr lambdas b locals cnt lifted)
      lift expr lambdas (EBlock stmts) locals cnt lifted =
        wrap lift block (lift stmt list lambdas stmts locals cnt lifted)
      lift expr lambdas (EGuard gs) locals cnt lifted =
        wrap lift guard (lift guard list lambdas gs locals cnt lifted)
      lift expr lambdas (EWhere b wbs) locals cnt lifted =
        locs1 = collect where bound vars wbs locals
        lift where lambdas (lift expr lambdas b locs1 cnt lifted) wbs locs1
      lift expr lambdas (EParPipe bs) locals cnt lifted =
        wrap lift parpipe (lift expr list lambdas bs locals cnt lifted)
      lift expr lambdas (EWithCtx c v b) locals cnt lifted =
        lift with ctx lambdas c (lift expr lambdas v locals cnt lifted) b ([c] :: locals)
      lift expr lambdas (EWithRegion q b) locals cnt lifted =
        wrap lift region q (lift expr lambdas b locals cnt lifted)
      lift expr lambdas e _ cnt lifted = (e, cnt, lifted)

fn :: wrap lift not (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift not (e1, c1, l1) = (ENot e1, c1, l1)

fn :: wrap lift out (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      wrap lift out (e1, c1, l1) = (EOut e1, c1, l1)

fn :: lift bin lambdas RBinOp (RExpr, Int, [RFnDef]) RExpr [String] => RExpr Int [RFnDef]
      lift bin lambdas bop (l1, c1, lf1) r locals =
        finish lift bin bop l1 (lift expr lambdas r locals c1 lf1)

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
        finish lift index b1 (lift expr list lambdas idxs locals c1 l1)

fn :: finish lift index RExpr ([RExpr], Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift index b1 (idxs1, c2, l2) = (EIndex b1 idxs1, c2, l2)

fn :: lift idx assign lambdas String ([RExpr], Int, [RFnDef]) RExpr [String] => RExpr Int [RFnDef]
      lift idx assign lambdas t (idxs1, c1, l1) v locals =
        finish lift idx assign t idxs1 (lift expr lambdas v locals c1 l1)

fn :: finish lift idx assign String [RExpr] (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift idx assign t idxs1 (v1, c2, l2) = (EIndexAssign t idxs1 v1, c2, l2)

fn :: lift with ctx lambdas String (RExpr, Int, [RFnDef]) RExpr [String] => RExpr Int [RFnDef]
      lift with ctx lambdas c (v1, c1, l1) b locals =
        finish lift with ctx c v1 (lift expr lambdas b locals c1 l1)

fn :: finish lift with ctx String RExpr (RExpr, Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift with ctx c v1 (b1, c2, l2) = (EWithCtx c v1 b1, c2, l2)

fn :: lift where lambdas (RExpr, Int, [RFnDef]) [RWhereBind] [String] => RExpr Int [RFnDef]
      lift where lambdas (b1, c1, l1) wbs locals =
        finish lift where b1 (lift where list lambdas wbs locals c1 l1)

fn :: finish lift where RExpr ([RWhereBind], Int, [RFnDef]) => RExpr Int [RFnDef]
      finish lift where b1 (wbs1, c2, l2) = (EWhere b1 wbs1, c2, l2)

fn :: lift expr list lambdas [RExpr] [String] Int [RFnDef] => [RExpr] Int [RFnDef]
      lift expr list lambdas [] _ cnt lifted = ([], cnt, lifted)
      lift expr list lambdas (e:es) locals cnt lifted =
        lift expr list step (lift expr lambdas e locals cnt lifted) es locals

fn :: lift expr list step (RExpr, Int, [RFnDef]) [RExpr] [String] => [RExpr] Int [RFnDef]
      lift expr list step (e1, c1, l1) es locals =
        finish lift expr list e1 (lift expr list lambdas es locals c1 l1)

fn :: finish lift expr list RExpr ([RExpr], Int, [RFnDef]) => [RExpr] Int [RFnDef]
      finish lift expr list e1 (es1, c2, l2) = ([e1] :: es1, c2, l2)

fn :: lift stmt list lambdas [RStmt] [String] Int [RFnDef] => [RStmt] Int [RFnDef]
      lift stmt list lambdas [] _ cnt lifted = ([], cnt, lifted)
      lift stmt list lambdas ((StmtLet v e):ss) locals cnt lifted =
        lift stmt let step v (lift expr lambdas e locals cnt lifted) ss (locals :: [v])
      lift stmt list lambdas ((StmtMut v e):ss) locals cnt lifted =
        lift stmt mut step v (lift expr lambdas e locals cnt lifted) ss (locals :: [v])
      lift stmt list lambdas ((StmtExpr (ECall "__pipe__" (left_e:(EVar v):[]))):ss) locals cnt lifted =
        lift stmt pipe var step v (lift expr lambdas left_e locals cnt lifted) ss (locals :: [v])
      lift stmt list lambdas ((StmtExpr e):ss) locals cnt lifted =
        lift stmt expr step (lift expr lambdas e locals cnt lifted) ss locals
      lift stmt list lambdas ((StmtIndexAssign t idxs e):ss) locals cnt lifted =
        lift stmt idx step (lift idx assign lambdas t (lift expr list lambdas idxs locals cnt lifted) e locals) ss locals

fn :: lift stmt pipe var step String (RExpr, Int, [RFnDef]) [RStmt] [String] => [RStmt] Int [RFnDef]
      lift stmt pipe var step v (e1, c1, l1) ss locals =
        finish lift stmt (StmtExpr (ECall "__pipe__" [e1, EVar v])) (lift stmt list lambdas ss locals c1 l1)

fn :: lift stmt let step String (RExpr, Int, [RFnDef]) [RStmt] [String] => [RStmt] Int [RFnDef]
      lift stmt let step v (e1, c1, l1) ss locals =
        finish lift stmt (StmtLet v e1) (lift stmt list lambdas ss locals c1 l1)

fn :: lift stmt mut step String (RExpr, Int, [RFnDef]) [RStmt] [String] => [RStmt] Int [RFnDef]
      lift stmt mut step v (e1, c1, l1) ss locals =
        finish lift stmt (StmtMut v e1) (lift stmt list lambdas ss locals c1 l1)

fn :: lift stmt expr step (RExpr, Int, [RFnDef]) [RStmt] [String] => [RStmt] Int [RFnDef]
      lift stmt expr step (e1, c1, l1) ss locals =
        finish lift stmt (StmtExpr e1) (lift stmt list lambdas ss locals c1 l1)

fn :: lift stmt idx step (RExpr, Int, [RFnDef]) [RStmt] [String] => [RStmt] Int [RFnDef]
      lift stmt idx step ((EIndexAssign t idxs1 e1), c1, l1) ss locals =
        finish lift stmt (StmtIndexAssign t idxs1 e1) (lift stmt list lambdas ss locals c1 l1)
      lift stmt idx step (e1, c1, l1) ss locals =
        finish lift stmt (StmtExpr e1) (lift stmt list lambdas ss locals c1 l1)

fn :: finish lift stmt RStmt ([RStmt], Int, [RFnDef]) => [RStmt] Int [RFnDef]
      finish lift stmt s1 (ss1, c2, l2) = ([s1] :: ss1, c2, l2)

fn :: lift guard list lambdas [RGuard] [String] Int [RFnDef] => [RGuard] Int [RFnDef]
      lift guard list lambdas [] _ cnt lifted = ([], cnt, lifted)
      lift guard list lambdas ((GuardBranch c b):gs) locals cnt lifted =
        lift guard step (lift expr lambdas c locals cnt lifted) b gs locals

fn :: lift guard step (RExpr, Int, [RFnDef]) RExpr [RGuard] [String] => [RGuard] Int [RFnDef]
      lift guard step (c1, cnt1, l1) b gs locals =
        lift guard step2 c1 (lift expr lambdas b locals cnt1 l1) gs locals

fn :: lift guard step2 RExpr (RExpr, Int, [RFnDef]) [RGuard] [String] => [RGuard] Int [RFnDef]
      lift guard step2 c1 (b1, cnt2, l2) gs locals =
        finish lift guard (GuardBranch c1 b1) (lift guard list lambdas gs locals cnt2 l2)

fn :: finish lift guard RGuard ([RGuard], Int, [RFnDef]) => [RGuard] Int [RFnDef]
      finish lift guard g1 (gs1, c3, l3) = ([g1] :: gs1, c3, l3)

fn :: lift where list lambdas [RWhereBind] [String] Int [RFnDef] => [RWhereBind] Int [RFnDef]
      lift where list lambdas [] _ cnt lifted = ([], cnt, lifted)
      lift where list lambdas ((WhereBind e v idxs):wbs) locals cnt lifted =
        lift where step v idxs (lift expr lambdas e locals cnt lifted) wbs locals

fn :: lift where step String [Int] (RExpr, Int, [RFnDef]) [RWhereBind] [String] => [RWhereBind] Int [RFnDef]
      lift where step v idxs (e1, c1, l1) wbs locals =
        finish lift where bind (WhereBind e1 v idxs) (lift where list lambdas wbs locals c1 l1)

fn :: finish lift where bind RWhereBind ([RWhereBind], Int, [RFnDef]) => [RWhereBind] Int [RFnDef]
      finish lift where bind wb1 (wbs1, c2, l2) = ([wb1] :: wbs1, c2, l2)

fn :: lift case list lambdas [RFnCase] Int [RFnDef] => [RFnCase] Int [RFnDef]
      lift case list lambdas [] cnt lifted = ([], cnt, lifted)
      lift case list lambdas ((FnCase pats gs body):cs) cnt lifted =
        locals = collect pat list bound vars pats []
        lift case step pats (lift guard list lambdas gs locals cnt lifted) body locals cs

fn :: lift case step [RPattern] ([RGuard], Int, [RFnDef]) RExpr [String] [RFnCase] => [RFnCase] Int [RFnDef]
      lift case step pats (gs1, c1, l1) body locals cs =
        lift case step2 pats gs1 (lift expr lambdas body locals c1 l1) cs

fn :: lift case step2 [RPattern] [RGuard] (RExpr, Int, [RFnDef]) [RFnCase] => [RFnCase] Int [RFnDef]
      lift case step2 pats gs1 (body1, c2, l2) cs =
        finish lift case (FnCase pats gs1 body1) (lift case list lambdas cs c2 l2)

fn :: finish lift case RFnCase ([RFnCase], Int, [RFnDef]) => [RFnCase] Int [RFnDef]
      finish lift case fc1 (cs1, c3, l3) = ([fc1] :: cs1, c3, l3)

fn :: lift fndef list lambdas [RFnDef] Int [RFnDef] [RFnDef] => [RFnDef]
      lift fndef list lambdas [] _ lifted acc = acc :: lifted
      lift fndef list lambdas ((FnDef name params ret_ty cases):fs) cnt lifted acc =
        lift fndef step name params ret_ty (lift case list lambdas cases cnt lifted) fs acc

fn :: lift fndef step String [String] String ([RFnCase], Int, [RFnDef]) [RFnDef] [RFnDef] => [RFnDef]
      lift fndef step name params ret_ty (cs1, c1, l1) fs acc =
        lift fndef list lambdas fs c1 l1 (acc :: [FnDef name params ret_ty cs1])

fn :: strip ty brackets String => String
      strip ty brackets s
        | (str len s) >= 2 AND (str starts with s "[") = strip ty brackets (str slice s 1 ((str len s) - 1))
        | otherwise = s

fn :: collect poly vars in str String [String] => [String]
      collect poly vars in str s acc =
        b = strip ty brackets s
        collect poly var base b acc

fn :: collect poly var base String [String] => [String]
      collect poly var base b acc
        | (str len b) == 1 AND (is upper ident b) AND (NOT (str in seen list b acc)) = acc :: [b]
        | otherwise = acc

fn :: collect poly vars in strs [String] [String] => [String]
      collect poly vars in strs [] acc = acc
      collect poly vars in strs (s:ss) acc =
        collect poly vars in strs ss (collect poly vars in str s acc)

fn :: collect poly vars in variants [RVariant] [String] => [String]
      collect poly vars in variants [] acc = acc
      collect poly vars in variants ((TypeVariant _ args):vs) acc =
        collect poly vars in variants vs (collect poly vars in strs args acc)

fn :: collect poly vars in fields [RField] [String] => [String]
      collect poly vars in fields [] acc = acc
      collect poly vars in fields ((TypeField _ fty):fs) acc =
        collect poly vars in fields fs (collect poly vars in str fty acc)

fn :: collect poly type arities [RTypeDef] => [RArityEntry]
      collect poly type arities [] = [ArityEntry "Option" 1]
      collect poly type arities ((TypeDef name vars fields):ts) =
        pvars = collect poly vars in fields fields (collect poly vars in variants vars [])
        n = str list count pvars
        prepend poly arity name n (collect poly type arities ts)

fn :: prepend poly arity String Int [RArityEntry] => [RArityEntry]
      prepend poly arity _ 0 rest = rest
      prepend poly arity name n rest
        | str contains name "." = [ArityEntry name n, ArityEntry (ident base name name) n] :: rest
        | otherwise = [ArityEntry name n] :: rest

fn :: take ty strs [String] Int => [String]
      take ty strs _ 0 = []
      take ty strs [] _ = []
      take ty strs (x:xs) n = [x] :: (take ty strs xs (n - 1))

fn :: drop ty strs [String] Int => [String]
      drop ty strs xs 0 = xs
      drop ty strs [] _ = []
      drop ty strs (_:xs) n = drop ty strs xs (n - 1)

fn :: join comma ty strs [String] => String
      join comma ty strs [] = ""
      join comma ty strs (s:[]) = s
      join comma ty strs (s:ss) = s + ", " + (join comma ty strs ss)

fn :: collapse poly param list [String] Int [RArityEntry] => [String]
      collapse poly param list [] _ _ = []
      collapse poly param list (p:ps) target_arity poly_arities
        | (1 + (str list count ps)) <= target_arity = [p] :: ps
        | otherwise =
          k = lookup arity poly_arities p
          collapse poly param step p ps k target_arity poly_arities

fn :: collapse poly param step String [String] Int Int [RArityEntry] => [String]
      collapse poly param step p ps k target_arity poly_arities
        | k > 0 AND (str list count ps) >= k =
          app_s = "(" + p + ", " + (join comma ty strs (take ty strs ps k)) + ")"
          [app_s] :: (collapse poly param list (drop ty strs ps k) (target_arity - 1) poly_arities)
        | otherwise =
          [p] :: (collapse poly param list ps (target_arity - 1) poly_arities)

fn :: first case pat arity [RFnCase] => Int
      first case pat arity ((FnCase pats _ _):_) = pat list count pats
      first case pat arity [] = 0

fn :: collapse fndef poly params [RFnDef] [RArityEntry] [RFnDef] => [RFnDef]
      collapse fndef poly params [] _ acc = acc
      collapse fndef poly params ((FnDef name params ret_ty cases):fs) poly_arities acc =
        pat_ar = first case pat arity cases
        params1 = collapse poly param list params pat_ar poly_arities
        collapse fndef poly params fs poly_arities (acc :: [FnDef name params1 ret_ty cases])

fn :: filter zero arities [RArityEntry] => [RArityEntry]
      filter zero arities [] = []
      filter zero arities ((ArityEntry k 0):rest) = [ArityEntry k 0] :: (filter zero arities rest)
      filter zero arities (_:rest) = filter zero arities rest

fn :: filter nonzero arities [RArityEntry] => [RArityEntry]
      filter nonzero arities [] = []
      filter nonzero arities ((ArityEntry _ 0):rest) = filter nonzero arities rest
      filter nonzero arities (e:rest) = [e] :: (filter nonzero arities rest)

fn :: normalize program RProgram          => RProgram
      normalize program (Program fns tys) =
        poly_arities = collect poly type arities tys
        fns0 = collapse fndef poly params fns poly_arities []
        fns1 = lift fndef list lambdas fns0 0 [] []
        raw_arities = (collect fn arities fns1) :: (collect type arities tys)
        arities = (filter zero arities raw_arities) :: (filter nonzero arities raw_arities)
        Program (norm fndef list fns1 arities) tys

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
        content = read file p
        try read candidate step content ps

fn :: try read candidate step String [String] => String
      try read candidate step "" ps = try read candidate paths ps
      try read candidate step content _ = content

fn :: rglib dir of String Int Int Int => String
      rglib dir of fpath pos len last_slash
        | pos >= len AND last_slash < 0 = "."
        | pos >= len = str slice fpath 0 last_slash
        | (str char at fpath pos) == 47 = rglib dir of fpath (pos + 1) len pos
        | otherwise = rglib dir of fpath (pos + 1) len last_slash

fn :: strip quotes len String Int => String
      strip quotes len s      n
        | n >= 2 AND ((str char at s 0) == 34 OR (str char at s 0) == 39) = str slice s 1 (n - 1)
        | otherwise = s

fn :: strip quotes String => String
      strip quotes s      =  strip quotes len s (str len s)

fn :: dots to slashes loop String Int Int String => String
      dots to slashes loop s pos len acc
        | pos >= len = acc
        | (str char at s pos) == 46 = dots to slashes loop s (pos + 1) len (acc + "/")
        | otherwise = dots to slashes loop s (pos + 1) len (acc + (str slice s pos (pos + 1)))

fn :: norm spec path String => String
      norm spec path spec
        | (str contains spec ".rglib") OR (str contains spec ".rg") = spec
        | str contains spec "." = dots to slashes loop spec 0 (str len spec) ""
        | otherwise = spec

fn :: read local rg module raw String String => String
      read local rg module raw pdir spec =
        try read candidate paths [pdir + "/" + spec + ".rg", pdir + "/" + spec + "/lib.rg", pdir + "/" + spec + "/mod.rg", pdir + "/../" + spec + ".rg", pdir + "/../../" + spec + ".rg", pdir + "/../../../" + spec + ".rg", pdir + "/../lib/" + spec + ".rg", pdir + "/../../main/ridgun/lib/" + spec + ".rg", pdir + "/../../main/ridgun/" + spec + ".rg", "src/main/ridgun/lib/" + spec + ".rg", "src/main/ridgun/" + spec + ".rg", "src/main/ridgun/" + spec + "/lib.rg", spec + ".rg"]

fn :: read local rg module String String => String
      read local rg module pdir spec =
        r1 = read local rg module raw pdir spec
        read local rg fallback pdir (norm spec path spec) r1

fn :: read local rg fallback String String String => String
      read local rg fallback pdir nspec "" = read local rg module raw pdir nspec
      read local rg fallback _ _ content = content

fn :: has local rg module String String => Bool
      has local rg module pdir spec =
        (read local rg module pdir spec) != ""

fn :: dep subdir paths String [String] String => [String]
      dep subdir paths _ [] _ = []
      dep subdir paths deps_base (d:ds) spec
        | str contains spec ".rglib" =
          [deps_base + "/" + d + "/target/bundles/" + spec, deps_base + "/" + d + "/target/" + spec, deps_base + "/" + d + "/" + spec] :: (dep subdir paths deps_base ds spec)
        | otherwise =
          [deps_base + "/" + d + "/target/bundles/" + spec + ".rglib", deps_base + "/" + d + "/target/" + spec + ".rglib", deps_base + "/" + d + "/" + spec + ".rglib", deps_base + "/" + d + "/src/main/ridgun/lib/" + spec + ".rg", deps_base + "/" + d + "/src/main/ridgun/" + spec + ".rg", deps_base + "/" + d + "/src/main/ridgun/" + spec + "/lib.rg"] :: (dep subdir paths deps_base ds spec)

fn :: all deps base paths [String] String => [String]
      all deps base paths [] _ = []
      all deps base paths (base:bs) spec
        | str contains spec ".rglib" =
          [base + "/" + spec] :: (dep subdir paths base (list dir base) spec) :: (all deps base paths bs spec)
        | otherwise =
          [base + "/" + spec + ".rglib", base + "/" + spec + ".rg"] :: (dep subdir paths base (list dir base) spec) :: (all deps base paths bs spec)

fn :: resolve rglib bundle raw String String => String
      resolve rglib bundle raw pdir spec
        | is core compiler mod spec = ""
        | str contains spec ".rglib" =
          dep_paths = all deps base paths [".stable/deps", pdir + "/.stable/deps", pdir + "/../.stable/deps", pdir + "/../../.stable/deps", pdir + "/../../../.stable/deps", pdir + "/../../../../.stable/deps"] spec
          try read candidate paths ([spec, pdir + "/" + spec, "target/bundles/" + spec, "build/" + spec, "target/" + spec, "dist/" + spec, "lib/" + spec] :: dep_paths)
        | otherwise =
          dep_paths = all deps base paths [".stable/deps", pdir + "/.stable/deps", pdir + "/../.stable/deps", pdir + "/../../.stable/deps", pdir + "/../../../.stable/deps", pdir + "/../../../../.stable/deps"] spec
          try read candidate paths (dep_paths :: ["target/bundles/" + spec + ".rglib", "build/" + spec + ".rglib", pdir + "/" + spec + ".rglib", pdir + "/lib/" + spec + ".rglib", spec + ".rglib", "target/" + spec + ".rglib", "dist/" + spec + ".rglib", "lib/" + spec + ".rglib", "src/main/ridgun/lib/" + spec + ".rglib"])

fn :: resolve rglib bundle fallback String String String => String
      resolve rglib bundle fallback pdir nspec "" = resolve rglib bundle raw pdir nspec
      resolve rglib bundle fallback _ _ content = content

fn :: resolve rglib bundle String String => String
      resolve rglib bundle pdir spec =
        r1 = resolve rglib bundle raw pdir spec
        resolve rglib bundle fallback pdir (norm spec path spec) r1

fn :: resolve rglib clean String String => String
      resolve rglib clean pdir   spec
        | is core compiler mod spec = ""
        | str contains spec ".rglib" = resolve rglib bundle pdir spec
        | has local rg module pdir spec = ""
        | otherwise = resolve rglib bundle pdir spec

fn :: rglib trim lead String Int Int => String
      rglib trim lead s pos len
        | pos >= len = ""
        | (str char at s pos) == 32 OR (str char at s pos) == 9 OR (str char at s pos) == 13 = rglib trim lead s (pos + 1) len
        | otherwise = str slice s pos len

fn :: rglib trim trail String Int     => String
      rglib trim trail s      end_pos
        | end_pos <= 0 = ""
        | (str char at s (end_pos - 1)) == 32 OR (str char at s (end_pos - 1)) == 9 OR (str char at s (end_pos - 1)) == 13 = rglib trim trail s (end_pos - 1)
        | otherwise = str slice s 0 end_pos

fn :: rglib trim String => String
      rglib trim s      =
        s1 = rglib trim lead s 0 (str len s)
        rglib trim trail s1 (str len s1)

fn :: strip inline comment loop String Int Int => String
      strip inline comment loop s pos len
        | pos >= len = s
        | (pos + 1) < len AND (str char at s pos) == 45 AND (str char at s (pos + 1)) == 45 = str slice s 0 pos
        | otherwise = strip inline comment loop s (pos + 1) len

fn :: find import as kw String Int Int => Int
      find import as kw s pos len
        | (pos + 4) > len = 0 - 1
        | (str slice s pos (pos + 4)) == " as " = pos
        | otherwise = find import as kw s (pos + 1) len

fn :: split import as idx String Int => String String
      split import as idx trimmed idx
        | idx < 0 = (strip quotes (rglib trim trimmed), "")
        | otherwise =
          spec_part = strip quotes (rglib trim (str slice trimmed 0 idx))
          alias_part = strip quotes (rglib trim (str slice trimmed (idx + 4) (str len trimmed)))
          (spec_part, alias_part)

fn :: parse import spec line String => String String
      parse import spec line raw_spec =
        no_comment = rglib trim (strip inline comment loop raw_spec 0 (str len raw_spec))
        idx = find import as kw no_comment 0 (str len no_comment)
        split import as idx no_comment idx

fn :: last slash idx String Int Int Int => Int
      last slash idx s pos len last_s
        | pos >= len = last_s
        | (str char at s pos) == 47 = last slash idx s (pos + 1) len pos
        | otherwise = last slash idx s (pos + 1) len last_s

fn :: strip mod ext String => String
      strip mod ext s
        | (str len s) > 6 AND (str slice s ((str len s) - 6) (str len s)) == ".rglib" = str slice s 0 ((str len s) - 6)
        | (str len s) > 3 AND (str slice s ((str len s) - 3) (str len s)) == ".rg" = str slice s 0 ((str len s) - 3)
        | otherwise = s

fn :: mod name after slash String Int => String
      mod name after slash s sl
        | sl < 0 = s
        | otherwise = str slice s (sl + 1) (str len s)

fn :: mod name of spec String => String
      mod name of spec spec =
        s1 = strip mod ext spec
        s2 = norm spec path s1
        sl = last slash idx s2 0 (str len s2) (0 - 1)
        mod name after slash s2 sl

fn :: mod alias marker String String => String
      mod alias marker "" _ = ""
      mod alias marker alias mname = "\n@__rg_mod_alias__ " + alias + " " + mname + "\n"

fn :: resolve rglib for spec String String => String
      resolve rglib for spec pdir raw_spec =
        spec_pair = parse import spec line raw_spec
        resolve rglib clean pdir (extract fst str spec_pair)

fn :: strip rgc magic String => String
      strip rgc magic s
        | str starts with s "RGC1" = "-- " + s
        | otherwise = s

fn :: append rglib resolved String String String => String
      append rglib resolved acc    _     ""      =  acc
      append rglib resolved acc    mname lib_src
        | is core compiler mod mname = acc + (strip rgc magic lib_src) + "\n"
        | otherwise = acc + "\n@__rg_mod_enter__ " + mname + "\n" + (strip rgc magic lib_src) + "\n@__rg_mod_exit__\n"

fn :: str in seen list String [String] => Bool
      str in seen list _ [] = False
      str in seen list target (s:ss)
        | s == target = True
        | otherwise = str in seen list target ss

fn :: append rglib from pair String (String, String) String [String] => String [String]
      append rglib from pair pdir (clean_spec, alias) acc seen =
        mname = mod name of spec clean_spec
        r1 = append rglib if unseen pdir clean_spec acc seen
        append rglib with alias alias mname r1

fn :: append rglib with alias String String (String, [String]) => String [String]
      append rglib with alias alias mname (acc2, seen2) =
        (acc2 + (mod alias marker alias mname), seen2)

fn :: append rglib from line String String String [String] => String [String]
      append rglib from line pdir line acc seen
        | str starts with line "import " =
          raw_spec = str slice line 7 (str len line)
          append rglib from pair pdir (parse import spec line raw_spec) acc seen
        | otherwise = (acc, seen)

fn :: append rglib after deps String String (String, [String]) => String [String]
      append rglib after deps mname lib_src (acc2, seen2) =
        (append rglib resolved acc2 mname lib_src, seen2)

fn :: has same dir rglib String String => Bool
      has same dir rglib pdir spec
        | str contains spec ".rglib" = (read file (pdir + "/" + spec)) != ""
        | otherwise = (read file (pdir + "/" + spec + ".rglib")) != ""

fn :: append rglib resolved mod String String String String [String] => String [String]
      append rglib resolved mod _ clean_spec "" acc seen1 =
        (acc + "\nfn :: unresolved import => Int\n      unresolved import = __missing_import__ \"" + clean_spec + "\"\n", seen1)
      append rglib resolved mod pdir clean_spec lib_src acc seen1 =
        mname = mod name of spec clean_spec
        sub_pdir = child pdir for spec pdir clean_spec
        res_deps = scan rglib imports state sub_pdir lib_src 0 (str len lib_src) 0 acc seen1
        append rglib after deps mname lib_src res_deps

fn :: append rglib local or ext String String String String [String] => String [String]
      append rglib local or ext pdir clean_spec "" acc seen1 =
        lib_src = resolve rglib bundle pdir clean_spec
        append rglib resolved mod pdir clean_spec lib_src acc seen1
      append rglib local or ext pdir clean_spec local_rg acc seen1 =
        mname = mod name of spec clean_spec
        sub_pdir = child pdir for spec pdir clean_spec
        res_deps = scan rglib imports state sub_pdir local_rg 0 (str len local_rg) 0 acc seen1
        append rglib after deps mname local_rg res_deps

fn :: append rglib if unseen String String String [String] => String [String]
      append rglib if unseen pdir clean_spec acc seen
        | (is core compiler mod clean_spec) OR (str in seen list clean_spec seen) = (acc, seen)
        | has same dir rglib pdir clean_spec =
          seen1 = [clean_spec] :: seen
          append rglib resolved mod pdir clean_spec (resolve rglib bundle pdir clean_spec) acc seen1
        | otherwise =
          seen1 = [clean_spec] :: seen
          local_rg = read local rg module pdir clean_spec
          append rglib local or ext pdir clean_spec local_rg acc seen1

fn :: fst str seen (String, [String]) => String
      fst str seen (a, _)             =  a

fn :: skip line spaces String Int Int => Int
      skip line spaces s p end_p
        | p >= end_p = p
        | (str char at s p) == 32 OR (str char at s p) == 9 = skip line spaces s (p + 1) end_p
        | otherwise = p

fn :: line starts with import String Int Int => Bool
      line starts with import s start end_p =
        p = skip line spaces s start end_p
        (end_p - p) > 7 AND (str char at s p) == 105 AND (str char at s (p + 1)) == 109 AND (str char at s (p + 2)) == 112 AND (str char at s (p + 3)) == 111 AND (str char at s (p + 4)) == 114 AND (str char at s (p + 5)) == 116 AND (str char at s (p + 6)) == 32

fn :: line starts with module String Int Int => Bool
      line starts with module s start end_p =
        p = skip line spaces s start end_p
        (end_p - p) > 9 AND (str char at s p) == 109 AND (str char at s (p + 1)) == 111 AND (str char at s (p + 2)) == 100 AND (str char at s (p + 3)) == 117 AND (str char at s (p + 4)) == 108 AND (str char at s (p + 5)) == 101 AND (str char at s (p + 6)) == 32

fn :: extract line mod after String => String
      extract line mod after line
        | str starts with line "module ::" = rglib trim (str slice line 9 (str len line))
        | otherwise = ""

fn :: extract line module name String Int Int => String
      extract line module name s start end_p
        | NOT (line starts with module s start end_p) = ""
        | otherwise = extract line mod after (rglib trim (str slice s start end_p))

fn :: add inline mod seen String [String] => [String]
      add inline mod seen "" seen = seen
      add inline mod seen m  seen = [m] :: seen

fn :: scan rglib line String String Int Int String [String] => String [String]
      scan rglib line pdir s line_start end_p acc seen
        | line starts with import s line_start end_p =
          line = rglib trim (str slice s line_start end_p)
          append rglib from line pdir line acc seen
        | line starts with module s line_start end_p =
          (acc, add inline mod seen (extract line module name s line_start end_p) seen)
        | otherwise = (acc, seen)

fn :: scan rglib imports state String String Int Int Int String [String] => String [String]
      scan rglib imports state pdir s pos len line_start acc seen
        | pos >= len =
          scan rglib line pdir s line_start len acc seen
        | (str char at s pos) == 10 =
          res = scan rglib line pdir s line_start pos acc seen
          scan rglib imports cont pdir s (pos + 1) len res
        | otherwise =
          scan rglib imports state pdir s (pos + 1) len line_start acc seen

fn :: scan rglib imports cont String String Int Int (String, [String]) => String [String]
      scan rglib imports cont pdir s next_pos len (acc2, seen2) =
        scan rglib imports state pdir s next_pos len next_pos acc2 seen2

fn :: scan rglib imports String String Int Int Int String [String] => String
      scan rglib imports pdir s pos len line_start acc seen =
        fst str seen (scan rglib imports state pdir s pos len line_start acc seen)

fn :: format deferred import String String => String
      format deferred import clean_spec "" = "import \"" + clean_spec + "\"\n"
      format deferred import clean_spec alias = "import \"" + clean_spec + "\" as " + alias + "\n"

fn :: mod import marker String => String
      mod import marker "" = ""
      mod import marker mname = "\n@__rg_mod_import__ " + mname + "\n"

fn :: append own rg after local String String String (String, [String]) => String [String]
      append own rg after local clean_spec mname alias (acc2, seen2)
        | is core compiler mod clean_spec = (acc2 + "\n-- import " + clean_spec + "\n", seen2)
        | otherwise = (acc2 + "\n@__rg_mod_exit__\n" + (mod import marker mname) + (mod alias marker alias mname) + "-- import " + clean_spec + "\n", seen2)

fn :: child pdir for spec String String => String
      child pdir for spec pdir spec =
        s1 = strip mod ext spec
        s2 = norm spec path s1
        sl = last slash idx s2 0 (str len s2) (0 - 1)
        child pdir step pdir s2 sl

fn :: child pdir step String String Int => String
      child pdir step pdir _ sl
        | sl <= 0 = pdir
      child pdir step pdir s2 sl =
        pdir + "/" + (str slice s2 0 sl)

fn :: append own rg local String String String String String [String] => String [String]
      append own rg local _ clean_spec alias "" acc seen1 =
        (acc + (format deferred import clean_spec alias), seen1)
      append own rg local pdir clean_spec alias local_rg acc seen1
        | is core compiler mod clean_spec =
          sub_pdir = child pdir for spec pdir clean_spec
          res = scan own rg lines sub_pdir local_rg 0 (str len local_rg) 0 0 acc seen1
          append own rg after local clean_spec clean_spec alias res
        | otherwise =
          mname = mod name of spec clean_spec
          sub_pdir = child pdir for spec pdir clean_spec
          acc_enter = acc + "\n@__rg_mod_enter__ " + mname + "\n"
          res = scan own rg lines sub_pdir local_rg 0 (str len local_rg) 0 0 acc_enter seen1
          append own rg after local clean_spec mname alias res

fn :: append own rg import pair String String (String, String) String [String] => String [String]
      append own rg import pair pdir _ (clean_spec, alias) acc seen
        | str in seen list clean_spec seen =
          mname = mod name of spec clean_spec
          (acc + (mod import marker mname) + (mod alias marker alias mname), seen)
        | has same dir rglib pdir clean_spec = (acc + (format deferred import clean_spec alias), [clean_spec] :: seen)
        | otherwise =
          local_rg = read local rg module pdir clean_spec
          append own rg local pdir clean_spec alias local_rg acc ([clean_spec] :: seen)

fn :: scan own rg lines cont String String Int Int (String, [String]) => String [String]
      scan own rg lines cont pdir s next_pos len (acc2, seen2) =
        scan own rg lines pdir s next_pos len next_pos next_pos acc2 seen2

fn :: scan own rg lines String String Int Int Int Int String [String] => String [String]
      scan own rg lines pdir s pos len line_start chunk_start acc seen
        | pos >= len AND line_start >= len =
          (acc + (str slice s chunk_start len), seen)
        | pos >= len AND (line starts with import s line_start len) =
          before = acc + (str slice s chunk_start line_start)
          line = rglib trim (str slice s line_start len)
          raw_spec = str slice line 7 (str len line)
          append own rg import pair pdir s (parse import spec line raw_spec) before seen
        | pos >= len =
          (acc + (str slice s chunk_start len), seen)
        | (str char at s pos) == 10 AND (line starts with import s line_start pos) =
          before = acc + (str slice s chunk_start line_start)
          line = rglib trim (str slice s line_start pos)
          raw_spec = str slice line 7 (str len line)
          res = append own rg import pair pdir s (parse import spec line raw_spec) before seen
          scan own rg lines cont pdir s (pos + 1) len res
        | (str char at s pos) == 10 =
          seen_next = add inline mod seen (extract line module name s line_start pos) seen
          scan own rg lines pdir s (pos + 1) len (pos + 1) chunk_start acc seen_next
        | otherwise =
          scan own rg lines pdir s (pos + 1) len line_start chunk_start acc seen

fn :: load rg own source raw String String => String
      load rg own source raw _ "" = ""
      load rg own source raw input_path raw_file =
        pdir = rglib dir of input_path 0 (str len input_path) (0 - 1)
        root_spec = mod name of spec input_path
        fst str seen (scan own rg lines pdir raw_file 0 (str len raw_file) 0 0 "" [root_spec])

fn :: load rg own source String => String
      load rg own source input_path =
        raw_file = read file input_path
        load rg own source raw input_path raw_file

fn :: join lib and base String String => String
      join lib and base ""     base_src =  base_src
      join lib and base lib_pr base_src =  lib_pr + "\n@__rg_user_src__\n" + base_src

fn :: load rg with libs String     => String
      load rg with libs input_path =
        base_src = load rg own source input_path
        pdir = rglib dir of input_path 0 (str len input_path) (0 - 1)
        lib_prefix = scan rglib imports pdir base_src 0 (str len base_src) 0 "" []
        join lib and base lib_prefix base_src

-- ── Scoped Module Namespace Resolution ──────────────────────

type RScopedFn = ScopedFn String Bool RFnDef
type RScopedType = ScopedType String Bool RTypeDef
type RModAlias = ModAlias String String

fn :: strip enter colon String => String
      strip enter colon s
        | str starts with s ":" = str slice s 1 (str len s)
        | otherwise = s

fn :: cur mod of stack [String] => String
      cur mod of stack []       =  ""
      cur mod of stack (m:_)    =  strip enter colon m

fn :: mod key of String => String
      mod key of "" = "__app__"
      mod key of m  = strip enter colon m

fn :: pop mod stack [String] => [String]
      pop mod stack []       =  []
      pop mod stack (_:ms)   =  ms

fn :: set explicit mod String [String] => [String]
      set explicit mod "main" []     =  []
      set explicit mod "main" (_:ms) =  [""] :: ms
      set explicit mod "root" []     =  []
      set explicit mod "root" (_:ms) =  [""] :: ms
      set explicit mod ""     []     =  []
      set explicit mod ""     (_:ms) =  [""] :: ms
      set explicit mod mname  []     =  [mname]
      set explicit mod mname  (_:ms) =  [mname] :: ms

fn :: has alias pair [RModAlias] String String => Bool
      has alias pair [] _ _ = False
      has alias pair ((ModAlias k v):rest) tk tv
        | k == tk AND v == tv = True
        | otherwise = has alias pair rest tk tv

fn :: add alias unique String String [RModAlias] => [RModAlias]
      add alias unique tk tv aliases
        | has alias pair aliases tk tv = aliases
        | otherwise = aliases :: [ModAlias tk tv]

fn :: add mod import String String [RModAlias] => [RModAlias]
      add mod import _ "" aliases = aliases
      add mod import cur_mod target aliases
        | is core compiler mod target = aliases
        | otherwise =
          ikey = mod key of cur_mod
          tkey = strip enter colon target
          add mod import step ikey tkey aliases

fn :: add mod import step String String [RModAlias] => [RModAlias]
      add mod import step ikey tkey aliases
        | ikey == tkey = aliases
        | otherwise = add alias unique ("__imp__:" + ikey) tkey aliases

fn :: add mod rename String String [RModAlias] => [RModAlias]
      add mod rename m1 m2 aliases
        | m1 == "" OR m2 == "" OR m1 == m2 = aliases
        | otherwise =
          a1 = add alias unique ("__ren__:" + m1) m2 aliases
          add alias unique ("__ren__:" + m2) m1 a1

fn :: record enter rename [String] String [RModAlias] => [RModAlias]
      record enter rename [] _ aliases = aliases
      record enter rename (top_m:_) new_mod aliases
        | (str starts with top_m ":") AND (new_mod != "") =
          add mod rename (strip enter colon top_m) new_mod aliases
        | otherwise = aliases

fn :: has any str [String] => Bool
      has any str []    = False
      has any str (_:_) = True

fn :: record exit import Bool [String] String String [RModAlias] => [RModAlias]
      record exit import in_lib rest_stack parent_mod child_mod aliases
        | ((NOT in_lib) OR (has any str rest_stack)) AND (child_mod != "") =
          add mod import parent_mod child_mod aliases
        | otherwise = aliases

fn :: add scoped alias String String String [RModAlias] => [RModAlias]
      add scoped alias _ "" _ aliases = aliases
      add scoped alias cur_mod al target aliases =
        mk = mod key of cur_mod
        [ModAlias (mk + "." + al) target] :: (aliases :: [ModAlias al target])

fn :: parse import target toks [RToken] String => String
      parse import target toks [] last_spec = mod name of spec last_spec
      parse import target toks (TokEof:_) last_spec = mod name of spec last_spec
      parse import target toks (TokNewline:_) last_spec = mod name of spec last_spec
      parse import target toks ((TokIdent "as"):_) last_spec = mod name of spec last_spec
      parse import target toks ((TokIdent s):rest) _ = parse import target toks rest s
      parse import target toks ((TokStr s):rest) _ = parse import target toks rest s
      parse import target toks (_:rest) last_spec = parse import target toks rest last_spec

fn :: parse import alias tok [RToken] => String
      parse import alias tok [] = ""
      parse import alias tok (TokEof:_) = ""
      parse import alias tok (TokNewline:_) = ""
      parse import alias tok ((TokIdent "as"):(TokIdent al):_) = al
      parse import alias tok (_:rest) = parse import alias tok rest

fn :: parse inline import [RToken] String [RModAlias] => [RModAlias]
      parse inline import ts cur_mod aliases =
        target = parse import target toks ts ""
        al = parse import alias tok ts
        a1 = add mod import cur_mod target aliases
        add scoped alias cur_mod al target a1

fn :: lookup str map [RModAlias] String => String
      lookup str map [] _ = ""
      lookup str map ((ModAlias k v):rest) target
        | k == target = v
        | otherwise = lookup str map rest target

fn :: expand mod alias String String [RModAlias] => String
      expand mod alias s cur_mod aliases
        | NOT (str contains s ".") = s
        | otherwise =
          pfx = ident first prefix s
          rest = ident after first dot s
          mk = mod key of cur_mod
          scoped_t = lookup str map aliases (mk + "." + pfx)
          target = default if empty scoped_t (lookup str map aliases pfx)
          expand mod alias step s target rest

fn :: expand mod alias step String String String => String
      expand mod alias step s "" _ = s
      expand mod alias step _ target rest = target + "." + rest

fn :: is single variant alias RTypeDef [RScopedType] => Bool
      is single variant alias (TypeDef _ ((TypeVariant vname []):[]) []) s_tys =
        (str contains vname ".") OR (scoped types have name s_tys vname)
      is single variant alias _ _ = False

fn :: scoped types have name [RScopedType] String => Bool
      scoped types have name [] _ = False
      scoped types have name ((ScopedType _ _ (TypeDef tname _ _)):ts) target
        | tname == target = True
        | otherwise = scoped types have name ts target

fn :: has any scoped mod [RScopedFn] [RScopedType] [RModAlias] => Bool
      has any scoped mod _ _ (_:_) = True
      has any scoped mod ((ScopedFn m _ _):fs) tys aliases
        | m != "" = True
        | otherwise = has any scoped mod fs tys aliases
      has any scoped mod [] ((ScopedType m _ tdef):ts) aliases
        | m != "" OR (is single variant alias tdef ts) = True
        | otherwise = has any scoped mod [] ts aliases
      has any scoped mod [] [] [] = False

fn :: add unique seen String [String] => [String]
      add unique seen s seen
        | str in seen list s seen = seen
        | otherwise = [s] :: seen

fn :: add unique seen end String [String] => [String]
      add unique seen end s seen
        | str in seen list s seen = seen
        | otherwise = seen :: [s]

fn :: add all unique end [String] [String] => [String]
      add all unique end [] acc = acc
      add all unique end (x:xs) acc = add all unique end xs (add unique seen end x acc)

fn :: lookup all map vals [RModAlias] String [String] => [String]
      lookup all map vals [] _ acc = acc
      lookup all map vals ((ModAlias k v):rest) target_k acc
        | k == target_k = lookup all map vals rest target_k (add unique seen end v acc)
        | otherwise = lookup all map vals rest target_k acc

fn :: own mods of String [RModAlias] => [String]
      own mods of cur_mod aliases =
        mk = mod key of cur_mod
        lookup all map vals aliases ("__ren__:" + mk) [mk]

fn :: expand renames list [String] [RModAlias] [String] => [String]
      expand renames list [] _ acc = acc
      expand renames list (m:ms) aliases acc =
        rens = lookup all map vals aliases ("__ren__:" + m) [m]
        expand renames list ms aliases (add all unique end rens acc)

fn :: collect imps for mods [String] [RModAlias] [String] => [String]
      collect imps for mods [] _ acc = acc
      collect imps for mods (m:ms) aliases acc =
        imps = lookup all map vals aliases ("__imp__:" + m) []
        collect imps for mods ms aliases (add all unique end imps acc)

fn :: filter out mods [String] [String] => [String]
      filter out mods [] _ = []
      filter out mods (m:ms) excl
        | str in seen list m excl = filter out mods ms excl
        | otherwise = [m] :: (filter out mods ms excl)

fn :: direct imports of String [RModAlias] => [String]
      direct imports of cur_mod aliases =
        own = own mods of cur_mod aliases
        raw_imps = collect imps for mods own aliases []
        exp_imps = expand renames list raw_imps aliases []
        filter out mods exp_imps own

fn :: expand imp hop [String] [RModAlias] => [String]
      expand imp hop mods aliases =
        step1 = collect imps for mods mods aliases mods
        expand renames list step1 aliases []

fn :: trans imports of String [String] [RModAlias] => [String]
      trans imports of cur_mod direct_imps aliases =
        own = own mods of cur_mod aliases
        h1 = expand imp hop direct_imps aliases
        h2 = expand imp hop h1 aliases
        h3 = expand imp hop h2 aliases
        filter out mods h3 (own :: direct_imps)

fn :: lookup all mod keys [String] String [RModAlias] [String] => [String]
      lookup all mod keys [] _ _ acc = acc
      lookup all mod keys (m:ms) ident map acc =
        found = lookup str map map (m + "." + ident)
        lookup all mod keys step ms ident map acc found

fn :: lookup all mod keys step [String] String [RModAlias] [String] String => [String]
      lookup all mod keys step ms ident map acc "" =
        lookup all mod keys ms ident map acc
      lookup all mod keys step ms ident map acc found =
        lookup all mod keys ms ident map (add unique seen end found acc)

fn :: select tier hits [String] String => String
      select tier hits [] _ = ""
      select tier hits (h:[]) _ = h
      select tier hits (_:_:_) ident = "__ambiguous__." + ident

fn :: lookup in mod scope String String [RModAlias] [RModAlias] => String
      lookup in mod scope cur_mod ident aliases map =
        own = own mods of cur_mod aliases
        own_hits = lookup all mod keys own ident map []
        lookup in mod scope tier1 cur_mod ident aliases map own_hits

fn :: lookup in mod scope tier1 String String [RModAlias] [RModAlias] [String] => String
      lookup in mod scope tier1 _ _ _ _ (h:_) = h
      lookup in mod scope tier1 cur_mod ident aliases map [] =
        direct_imps = direct imports of cur_mod aliases
        direct_hits = lookup all mod keys direct_imps ident map []
        lookup in mod scope tier2 cur_mod ident direct_imps aliases map (select tier hits direct_hits ident)

fn :: lookup in mod scope tier2 String String [String] [RModAlias] [RModAlias] String => String
      lookup in mod scope tier2 cur_mod ident direct_imps aliases map "" =
        trans_imps = trans imports of cur_mod direct_imps aliases
        trans_hits = lookup all mod keys trans_imps ident map []
        select tier hits trans_hits ident
      lookup in mod scope tier2 _ _ _ _ _ hit = hit

fn :: key has base ident String String => Bool
      key has base ident k base =
        (str contains k ".") AND ((ident base name k) == base)

fn :: map has base ident [RModAlias] String => Bool
      map has base ident [] _ = False
      map has base ident ((ModAlias k _):rest) base
        | key has base ident k base = True
        | otherwise = map has base ident rest base

fn :: other scoped type has name [RScopedType] String String => Bool
      other scoped type has name [] _ _ = False
      other scoped type has name ((ScopedType m2 False (TypeDef tname2 _ _)):ts) m1 target
        | tname2 == target AND m2 != m1 = True
        | otherwise = other scoped type has name ts m1 target
      other scoped type has name (_:ts) m1 target =
        other scoped type has name ts m1 target

fn :: collect collided types [RScopedType] [RScopedType] [String] => [String]
      collect collided types [] _ acc = acc
      collect collided types ((ScopedType m True _):ts) all_ts acc =
        collect collided types ts all_ts acc
      collect collided types ((ScopedType m False (TypeDef tname _ _)):ts) all_ts acc
        | other scoped type has name all_ts m tname =
          collect collided types ts all_ts (add unique seen tname acc)
        | otherwise = collect collided types ts all_ts acc

fn :: fields have name [RField] String => Bool
      fields have name [] _ = False
      fields have name ((TypeField fname _):fs) target
        | fname == target = True
        | otherwise = fields have name fs target

fn :: other mod has field [RScopedType] String String => Bool
      other mod has field [] _ _ = False
      other mod has field ((ScopedType m2 _ (TypeDef _ _ fs)):ts) m1 target
        | m2 != m1 AND (fields have name fs target) = True
        | otherwise = other mod has field ts m1 target

fn :: collect fields collided from list [RField] String [RScopedType] [String] => [String]
      collect fields collided from list [] _ _ acc = acc
      collect fields collided from list ((TypeField fname _):fs) m all_ts acc
        | other mod has field all_ts m fname =
          collect fields collided from list fs m all_ts (add unique seen fname acc)
        | otherwise = collect fields collided from list fs m all_ts acc

fn :: collect collided fields [RScopedType] [RScopedType] [String] => [String]
      collect collided fields [] _ acc = acc
      collect collided fields ((ScopedType m _ (TypeDef _ _ fs)):ts) all_ts acc =
        acc1 = collect fields collided from list fs m all_ts acc
        collect collided fields ts all_ts acc1

fn :: other mod has fn [RScopedFn] String String => Bool
      other mod has fn [] _ _ = False
      other mod has fn ((ScopedFn m2 _ (FnDef fname2 _ _ _)):fs) m1 target
        | fname2 == target AND m2 != m1 = True
        | otherwise = other mod has fn fs m1 target

fn :: is special top fn String => Bool
      is special top fn "main" = True
      is special top fn "__syntax_error__" = True
      is special top fn "__unresolved_import__" = True
      is special top fn _ = False

fn :: collect collided fns [RScopedFn] [RScopedFn] [String] => [String]
      collect collided fns [] _ acc = acc
      collect collided fns ((ScopedFn m _ (FnDef fname _ _ _)):fs) _ acc
        | (NOT (is special top fn fname)) AND (NOT (str in seen list fname acc)) AND (other mod has fn fs m fname) =
          collect collided fns fs fs (add unique seen fname acc)
        | otherwise = collect collided fns fs fs acc

fn :: variants have ctor [RVariant] String => Bool
      variants have ctor [] _ = False
      variants have ctor ((TypeVariant c _):vs) target
        | c == target = True
        | otherwise = variants have ctor vs target

fn :: other mod has ctor [RScopedType] String String => Bool
      other mod has ctor [] _ _ = False
      other mod has ctor ((ScopedType _ True _):ts) m1 target = other mod has ctor ts m1 target
      other mod has ctor ((ScopedType m2 False (TypeDef _ vs _)):ts) m1 target
        | m2 != m1 AND (variants have ctor vs target) = True
        | otherwise = other mod has ctor ts m1 target

fn :: count ctor in mod [RScopedType] String String => Int
      count ctor in mod [] _ _ = 0
      count ctor in mod ((ScopedType _ True _):ts) m target = count ctor in mod ts m target
      count ctor in mod ((ScopedType m2 False (TypeDef _ vs _)):ts) m target
        | m2 == m AND (variants have ctor vs target) = 1 + (count ctor in mod ts m target)
        | otherwise = count ctor in mod ts m target

fn :: collect ctors collided from vars String [RVariant] [RScopedType] [String] => [String]
      collect ctors collided from vars _ [] _ acc = acc
      collect ctors collided from vars m ((TypeVariant c _):vs) all_ts acc
        | other mod has ctor all_ts m c =
          collect ctors collided from vars m vs all_ts (add unique seen c acc)
        | otherwise = collect ctors collided from vars m vs all_ts acc

fn :: collect collided ctors [RScopedType] [RScopedType] [String] => [String]
      collect collided ctors [] _ acc = acc
      collect collided ctors ((ScopedType _ True _):ts) all_ts acc = collect collided ctors ts all_ts acc
      collect collided ctors ((ScopedType m False (TypeDef _ vs _)):ts) all_ts acc =
        acc1 = collect ctors collided from vars m vs all_ts acc
        collect collided ctors ts all_ts acc1

fn :: canon scoped name String String [String] => String
      canon scoped name "" "main" _ = "main"
      canon scoped name _ "__syntax_error__" _ = "__syntax_error__"
      canon scoped name _ "__unresolved_import__" _ = "__unresolved_import__"
      canon scoped name m name collided
        | str in seen list name collided = (mod key of m) + "." + name
        | otherwise = name

fn :: build base type map [RScopedType] [RScopedType] [String] => [RModAlias]
      build base type map [] _ _ = []
      build base type map ((ScopedType m _ tdef):ts) all_ts collided_types
        | is single variant alias tdef all_ts = build base type map ts all_ts collided_types
      build base type map ((ScopedType m _ (TypeDef tname _ _)):ts) all_ts collided_types =
        canon_t = canon scoped name m tname collided_types
        mk = mod key of m
        [ModAlias (mk + "." + tname) canon_t] :: (build base type map ts all_ts collided_types)

fn :: resolve target type alias String String [RModAlias] [RModAlias] => String
      resolve target type alias m raw_target aliases base_tmap =
        t1 = expand mod alias raw_target m aliases
        resolve target type step m t1 aliases base_tmap

fn :: resolve target type step String String [RModAlias] [RModAlias] => String
      resolve target type step m t1 aliases base_tmap
        | str contains t1 "." =
          found = lookup str map base_tmap t1
          default if empty found t1
        | otherwise =
          found_s = lookup in mod scope m t1 aliases base_tmap
          default if empty found_s t1

fn :: default if empty String String => String
      default if empty "" fallback = fallback
      default if empty val _ = val

fn :: build alias type map [RScopedType] [RScopedType] [String] [RModAlias] [RModAlias] => [RModAlias]
      build alias type map [] _ _ _ acc = acc
      build alias type map ((ScopedType m _ (TypeDef tname ((TypeVariant raw_target []):[]) [])):ts) all_ts collided_types aliases acc
        | is single variant alias (TypeDef tname [TypeVariant raw_target []] []) all_ts =
          canon_target = resolve target type alias m raw_target aliases acc
          mk = mod key of m
          acc1 = [ModAlias (mk + "." + tname) canon_target] :: acc
          build alias type map ts all_ts collided_types aliases acc1
      build alias type map (_:ts) all_ts collided_types aliases acc =
        build alias type map ts all_ts collided_types aliases acc

fn :: build variant ctor entries String String String [RVariant] [RScopedType] [String] => [RModAlias]
      build variant ctor entries _ _ _ [] _ _ = []
      build variant ctor entries m tname canon_t ((TypeVariant c _):vs) all_ts collided_ctors =
        rest = build variant ctor entries m tname canon_t vs all_ts collided_ctors
        c_canon = canon variant ctor c canon_t collided_ctors
        e_base = [ModAlias (canon_t + "." + c) (canon_t + "." + c)]
        build variant mod entries m tname canon_t c c_canon (count ctor in mod all_ts m c) (e_base :: rest)

fn :: canon variant ctor String String [String] => String
      canon variant ctor c canon_t collided_ctors
        | str in seen list c collided_ctors = canon_t + "." + c
        | otherwise = c

fn :: build variant mod entries String String String String String Int [RModAlias] => [RModAlias]
      build variant mod entries m tname canon_t c c_canon mod_cnt acc =
        mk = mod key of m
        build variant mod step mk tname canon_t c c_canon mod_cnt acc

fn :: build variant mod step String String String String String Int [RModAlias] => [RModAlias]
      build variant mod step mk tname canon_t c c_canon 1 acc =
        [ModAlias (mk + "." + tname + "." + c) (canon_t + "." + c), ModAlias (mk + "." + c) c_canon] :: acc
      build variant mod step mk tname canon_t c _ _ acc =
        [ModAlias (mk + "." + tname + "." + c) (canon_t + "." + c), ModAlias (mk + "." + c) c] :: acc

fn :: build ctor map [RScopedType] [RScopedType] [String] [String] [RModAlias] => [RModAlias]
      build ctor map [] _ _ _ type_map = type_map
      build ctor map ((ScopedType _ _ tdef):ts) all_ts collided_types collided_ctors type_map
        | is single variant alias tdef all_ts = build ctor map ts all_ts collided_types collided_ctors type_map
      build ctor map ((ScopedType m _ (TypeDef tname vs _)):ts) all_ts collided_types collided_ctors type_map =
        canon_t = canon scoped name m tname collided_types
        v_entries = build variant ctor entries m tname canon_t vs all_ts collided_ctors
        v_entries :: (build ctor map ts all_ts collided_types collided_ctors type_map)

fn :: build field entries for mod String [RField] [String] => [RModAlias]
      build field entries for mod _ [] _ = []
      build field entries for mod m ((TypeField fname _):fs) collided_fields =
        canon_f = canon scoped name m fname collided_fields
        mk = mod key of m
        [ModAlias (mk + "." + fname) canon_f] :: (build field entries for mod m fs collided_fields)

fn :: build field map [RScopedType] [String] => [RModAlias]
      build field map [] _ = []
      build field map ((ScopedType m _ (TypeDef _ _ fs)):ts) collided_fields =
        (build field entries for mod m fs collided_fields) :: (build field map ts collided_fields)

fn :: build fn map [RScopedFn] [String] => [RModAlias]
      build fn map [] _ = []
      build fn map ((ScopedFn m _ (FnDef fname _ _ _)):fs) collided_fns =
        canon_fn = canon scoped name m fname collided_fns
        mk = mod key of m
        [ModAlias (mk + "." + fname) canon_fn] :: (build fn map fs collided_fns)

fn :: is type ident char Int => Bool
      is type ident char c =
        (c >= 65 AND c <= 90) OR (c >= 97 AND c <= 122) OR (c >= 48 AND c <= 57) OR c == 95 OR c == 46

fn :: scan type ident end String Int Int => Int
      scan type ident end s pos len
        | pos >= len = pos
        | is type ident char (str char at s pos) = scan type ident end s (pos + 1) len
        | otherwise = pos

fn :: is builtin or poly type String => Bool
      is builtin or poly type s
        | (str len s) == 1 = True
        | is prim type ctor s = True
        | s == "Unit" OR s == "Actor" OR s == "Agent" OR s == "Tensor" OR s == "Tensor_GPU" OR s == "Option" OR s == "Byte" OR s == "Ptr" OR s == "Channel" OR s == "Fd" OR s == "Socket" OR s == "Pid" OR s == "Any" OR s == "SysOs" OR s == "SysArch" = True
        | otherwise = False

fn :: resolve one type ident String String [RModAlias] [RModAlias] => String
      resolve one type ident tok cur_mod aliases type_map
        | NOT (is upper ident tok) = tok
        | otherwise =
          t1 = expand mod alias tok cur_mod aliases
          resolve one type step t1 cur_mod aliases type_map

fn :: resolve one type step String String [RModAlias] [RModAlias] => String
      resolve one type step t1 cur_mod aliases type_map
        | str contains t1 "." = default if empty (lookup str map type_map t1) t1
        | otherwise =
          in_scope = lookup in mod scope cur_mod t1 aliases type_map
          resolve one type fallback t1 type_map in_scope

fn :: resolve one type fallback String [RModAlias] String => String
      resolve one type fallback t1 type_map ""
        | is builtin or poly type t1 = t1
        | map has base ident type_map t1 = "__unimported__." + t1
        | otherwise = t1
      resolve one type fallback _ _ in_scope = in_scope

fn :: rewrite type str loop String Int Int String [RModAlias] [RModAlias] String => String
      rewrite type str loop s pos len cur_mod aliases type_map acc
        | pos >= len = acc
        | is type ident char (str char at s pos) =
          end_p = scan type ident end s pos len
          tok = str slice s pos end_p
          resolved = resolve one type ident tok cur_mod aliases type_map
          rewrite type str loop s end_p len cur_mod aliases type_map (acc + resolved)
        | otherwise =
          ch = str slice s pos (pos + 1)
          rewrite type str loop s (pos + 1) len cur_mod aliases type_map (acc + ch)

fn :: rewrite type str String String [RModAlias] [RModAlias] => String
      rewrite type str s cur_mod aliases type_map =
        rewrite type str loop s 0 (str len s) cur_mod aliases type_map ""

fn :: rewrite type str list [String] String [RModAlias] [RModAlias] => [String]
      rewrite type str list [] _ _ _ = []
      rewrite type str list (t:ts) cur_mod aliases type_map =
        [rewrite type str t cur_mod aliases type_map] :: (rewrite type str list ts cur_mod aliases type_map)

fn :: is builtin ctor ident String => Bool
      is builtin ctor ident c
        | is prim type ctor c = True
        | c == "True" OR c == "False" OR c == "Some" OR c == "None" OR c == "Linux" OR c == "MacOS" OR c == "Windows" OR c == "X86_64" OR c == "Arm64" = True
        | otherwise = False

fn :: resolve ctor ident String String [RModAlias] [RModAlias] => String
      resolve ctor ident c cur_mod aliases ctor_map =
        c1 = expand mod alias c cur_mod aliases
        resolve ctor ident step c1 cur_mod aliases ctor_map

fn :: resolve ctor ident step String String [RModAlias] [RModAlias] => String
      resolve ctor ident step c1 cur_mod aliases ctor_map
        | str contains c1 "." =
          in_scope = lookup in mod scope cur_mod c1 aliases ctor_map
          in_direct = lookup str map ctor_map c1
          resolve ctor dot fallback c1 in_scope in_direct
        | otherwise =
          in_scope = lookup in mod scope cur_mod c1 aliases ctor_map
          resolve ctor plain fallback c1 ctor_map in_scope

fn :: resolve ctor dot fallback String String String => String
      resolve ctor dot fallback c1 "" in_direct = default if empty in_direct c1
      resolve ctor dot fallback _ in_scope in_direct
        | str starts with in_scope "__ambiguous__." = default if empty in_direct in_scope
        | otherwise = in_scope

fn :: resolve ctor plain fallback String [RModAlias] String => String
      resolve ctor plain fallback c1 ctor_map ""
        | is builtin ctor ident c1 = c1
        | map has base ident ctor_map c1 = "__unimported__." + c1
        | otherwise = c1
      resolve ctor plain fallback _ _ in_scope = in_scope

fn :: rewrite pat RPattern String [RModAlias] [RModAlias] => RPattern
      rewrite pat (PatCons h t) cur_mod aliases ctor_map =
        PatCons (rewrite pat h cur_mod aliases ctor_map) (rewrite pat t cur_mod aliases ctor_map)
      rewrite pat (PatTuple ps) cur_mod aliases ctor_map =
        PatTuple (rewrite pat list ps cur_mod aliases ctor_map)
      rewrite pat (PatCtor c ps) cur_mod aliases ctor_map =
        PatCtor (resolve ctor ident c cur_mod aliases ctor_map) (rewrite pat list ps cur_mod aliases ctor_map)
      rewrite pat p _ _ _ = p

fn :: rewrite pat list [RPattern] String [RModAlias] [RModAlias] => [RPattern]
      rewrite pat list [] _ _ _ = []
      rewrite pat list (p:ps) cur_mod aliases ctor_map =
        [rewrite pat p cur_mod aliases ctor_map] :: (rewrite pat list ps cur_mod aliases ctor_map)

fn :: collect pat bound vars RPattern [String] => [String]
      collect pat bound vars (PatVar v) acc = [v] :: acc
      collect pat bound vars (PatSeqBind v) acc = [v] :: acc
      collect pat bound vars (PatCons h t) acc = collect pat bound vars t (collect pat bound vars h acc)
      collect pat bound vars (PatTuple ps) acc = collect pat list bound vars ps acc
      collect pat bound vars (PatCtor _ ps) acc = collect pat list bound vars ps acc
      collect pat bound vars _ acc = acc

fn :: collect pat list bound vars [RPattern] [String] => [String]
      collect pat list bound vars [] acc = acc
      collect pat list bound vars (p:ps) acc = collect pat list bound vars ps (collect pat bound vars p acc)

fn :: collect where bound vars [RWhereBind] [String] => [String]
      collect where bound vars [] acc = acc
      collect where bound vars ((WhereBind _ v _):wbs) acc
        | v != "" = collect where bound vars wbs ([v] :: acc)
        | otherwise = collect where bound vars wbs acc

fn :: lookup mod fn or field String String [RModAlias] [RModAlias] => String
      lookup mod fn or field m base fn_map field_map =
        key = m + "." + base
        in_fn = lookup str map fn_map key
        in_fld = lookup str map field_map key
        default if empty in_fn in_fld

fn :: lookup all mod fn or field [String] String [RModAlias] [RModAlias] [String] => [String]
      lookup all mod fn or field [] _ _ _ acc = acc
      lookup all mod fn or field (m:ms) base fn_map field_map acc =
        found = lookup mod fn or field m base fn_map field_map
        lookup all mod ff step ms base fn_map field_map acc found

fn :: lookup all mod ff step [String] String [RModAlias] [RModAlias] [String] String => [String]
      lookup all mod ff step ms base fn_map field_map acc "" =
        lookup all mod fn or field ms base fn_map field_map acc
      lookup all mod ff step ms base fn_map field_map acc found =
        lookup all mod fn or field ms base fn_map field_map (add unique seen end found acc)

fn :: lookup scoped fn or field String String [RModAlias] [RModAlias] [RModAlias] => String
      lookup scoped fn or field cur_mod base aliases fn_map field_map =
        own = own mods of cur_mod aliases
        own_hits = lookup all mod fn or field own base fn_map field_map []
        lookup scoped ff t1 cur_mod base aliases fn_map field_map own_hits

fn :: lookup scoped ff t1 String String [RModAlias] [RModAlias] [RModAlias] [String] => String
      lookup scoped ff t1 _ _ _ _ _ (h:_) = h
      lookup scoped ff t1 cur_mod base aliases fn_map field_map [] =
        direct_imps = direct imports of cur_mod aliases
        direct_hits = lookup all mod fn or field direct_imps base fn_map field_map []
        lookup scoped ff t2 cur_mod base direct_imps aliases fn_map field_map (select tier hits direct_hits base)

fn :: lookup scoped ff t2 String String [String] [RModAlias] [RModAlias] [RModAlias] String => String
      lookup scoped ff t2 cur_mod base direct_imps aliases fn_map field_map "" =
        trans_imps = trans imports of cur_mod direct_imps aliases
        trans_hits = lookup all mod fn or field trans_imps base fn_map field_map []
        lookup scoped ff t3 base (select tier hits trans_hits base)
      lookup scoped ff t2 _ _ _ _ _ _ hit = hit

fn :: lookup scoped ff t3 String String => String
      lookup scoped ff t3 base ""
        | (is std builtin base) OR ((lookup arity (builtin arity entries) base) >= 0) = base
        | otherwise = ""
      lookup scoped ff t3 _ hit = hit

fn :: ident has word part String String => Bool
      ident has word part full_name word =
        (full_name == word) OR (str starts with full_name (word + "_")) OR (str contains full_name ("_" + word + "_")) OR ((str len full_name) > (str len word) AND (str slice full_name ((str len full_name) - (str len word) - 1) (str len full_name)) == ("_" + word))

fn :: arity list has word part [RArityEntry] String => Bool
      arity list has word part [] _ = False
      arity list has word part ((ArityEntry k _):rest) word
        | ident has word part k word = True
        | otherwise = arity list has word part rest word

fn :: mod has word part in map String String [RModAlias] => Bool
      mod has word part in map _ _ [] = False
      mod has word part in map m word ((ModAlias k _):rest)
        | (str starts with k (m + ".")) AND (ident has word part (ident base name k) word) = True
        | otherwise = mod has word part in map m word rest

fn :: mods have word part [String] String [RModAlias] => Bool
      mods have word part [] _ _ = False
      mods have word part (m:ms) word fn_map
        | mod has word part in map m word fn_map = True
        | otherwise = mods have word part ms word fn_map

fn :: scope has word part String String [RModAlias] [RModAlias] => Bool
      scope has word part cur_mod word aliases fn_map =
        own = own mods of cur_mod aliases
        direct_imps = direct imports of cur_mod aliases
        trans_imps = trans imports of cur_mod direct_imps aliases
        all_vis = own :: direct_imps :: trans_imps
        (arity list has word part (builtin arity entries) word) OR (mods have word part all_vis word fn_map)

fn :: is mixfix reserved word String => Bool
      is mixfix reserved word "to" = True
      is mixfix reserved word "in" = True
      is mixfix reserved word "from" = True
      is mixfix reserved word "through" = True
      is mixfix reserved word "timeout" = True
      is mixfix reserved word "alive" = True
      is mixfix reserved word "out" = True
      is mixfix reserved word "and" = True
      is mixfix reserved word "or" = True
      is mixfix reserved word "xor" = True
      is mixfix reserved word "not" = True
      is mixfix reserved word "with" = True
      is mixfix reserved word "as" = True
      is mixfix reserved word "otherwise" = True
      is mixfix reserved word "agent" = True
      is mixfix reserved word "send" = True
      is mixfix reserved word "ask" = True
      is mixfix reserved word "receive" = True
      is mixfix reserved word "stop" = True
      is mixfix reserved word _ = False

fn :: collect unimported ff names [String] [RModAlias] [String] => [String]
      collect unimported ff names _ [] acc = acc
      collect unimported ff names vis_mods ((ModAlias k _):rest) acc =
        m = ident mod prefix k
        base = ident base name k
        collect unimp ff step vis_mods m base rest acc

fn :: collect unimp ff step [String] String String [RModAlias] [String] => [String]
      collect unimp ff step vis_mods m base rest acc
        | (m != "") AND (NOT (str in seen list m vis_mods)) =
          collect unimported ff names vis_mods rest (add unique seen base acc)
        | otherwise =
          collect unimported ff names vis_mods rest acc

fn :: compute mod special ff String [String] [String] [RModAlias] [RModAlias] [RModAlias] => [String]
      compute mod special ff cur_mod collided_fns collided_fields aliases fn_map field_map =
        own = own mods of cur_mod aliases
        direct_imps = direct imports of cur_mod aliases
        trans_imps = trans imports of cur_mod direct_imps aliases
        vis_mods = own :: direct_imps :: trans_imps
        unimp1 = collect unimported ff names vis_mods fn_map []
        unimp2 = collect unimported ff names vis_mods field_map unimp1
        collided_fns :: collided_fields :: unimp2

fn :: special has word or prefix String [String] => Bool
      special has word or prefix _ [] = False
      special has word or prefix w (s:ss)
        | s == w OR (str starts with s (w + "_")) = True
        | otherwise = special has word or prefix w ss

fn :: args touch special [RExpr] [String] => Bool
      args touch special ((EVar w):rest) special_ff
        | (is lower ident w) AND (NOT (str contains w ".")) =
          (str in seen list w special_ff) OR (args touch special rest special_ff)
      args touch special _ _ = False

fn :: resolve lower ident String String [String] [String] [RModAlias] [RModAlias] [RModAlias] => String
      resolve lower ident v cur_mod locals special_ff aliases fn_map field_map
        | str in seen list v locals = v
        | (NOT (str contains v ".")) AND (NOT (str in seen list v special_ff)) = v
        | otherwise =
          v1 = expand mod alias v cur_mod aliases
          resolve lower ident step v1 cur_mod aliases fn_map field_map

fn :: resolve lower ident step String String [RModAlias] [RModAlias] [RModAlias] => String
      resolve lower ident step v1 cur_mod aliases fn_map field_map
        | str contains v1 "." =
          in_fn = lookup str map fn_map v1
          in_fld = lookup str map field_map v1
          default if empty in_fn (default if empty in_fld v1)
        | otherwise =
          in_scope = lookup scoped fn or field cur_mod v1 aliases fn_map field_map
          resolve lower plain fallback v1 cur_mod aliases fn_map field_map in_scope

fn :: resolve lower plain fallback String String [RModAlias] [RModAlias] [RModAlias] String => String
      resolve lower plain fallback v1 cur_mod aliases fn_map field_map ""
        | is mixfix reserved word v1 = v1
        | ((map has base ident fn_map v1) OR (map has base ident field_map v1)) AND (NOT (scope has word part cur_mod v1 aliases fn_map)) = "__unimported__." + v1
        | otherwise = v1
      resolve lower plain fallback _ _ _ _ _ in_scope = in_scope

fn :: resolve field str String String [RModAlias] [RModAlias] => String
      resolve field str fname cur_mod aliases field_map =
        f1 = expand mod alias fname cur_mod aliases
        resolve field str step f1 cur_mod aliases field_map

fn :: resolve field str step String String [RModAlias] [RModAlias] => String
      resolve field str step f1 cur_mod aliases field_map
        | str contains f1 "." = default if empty (lookup str map field_map f1) f1
        | otherwise =
          in_scope = lookup in mod scope cur_mod f1 aliases field_map
          resolve field plain fallback f1 field_map in_scope

fn :: resolve field plain fallback String [RModAlias] String => String
      resolve field plain fallback f1 field_map ""
        | map has base ident field_map f1 = "__unimported__." + f1
        | otherwise = f1
      resolve field plain fallback _ _ in_scope = in_scope

fn :: try consume mod words String String [RExpr] [RExpr] [RModAlias] [RModAlias] => String [RExpr] [RExpr]
      try consume mod words m acc_base consumed ((EVar w):rest) fn_map field_map
        | (is lower ident w) AND (NOT (str contains w ".")) =
          cand = acc_base + "_" + w
          deeper = try consume mod words m cand (consumed :: [EVar w]) rest fn_map field_map
          select mod words m acc_base consumed ((EVar w):rest) fn_map field_map deeper
      try consume mod words m acc_base consumed args fn_map field_map =
        resolved = lookup mod fn or field m acc_base fn_map field_map
        (resolved, consumed, args)

fn :: select mod words String String [RExpr] [RExpr] [RModAlias] [RModAlias] (String, [RExpr], [RExpr]) => String [RExpr] [RExpr]
      select mod words m acc_base consumed orig_args fn_map field_map ("", _, _) =
        (lookup mod fn or field m acc_base fn_map field_map, consumed, orig_args)
      select mod words _ _ _ _ _ _ deeper_match = deeper_match

fn :: try consume scoped words String String [RExpr] [RExpr] [RModAlias] [RModAlias] [RModAlias] => String [RExpr] [RExpr]
      try consume scoped words cur_mod acc_base consumed ((EVar w):rest) aliases fn_map field_map
        | (is lower ident w) AND (NOT (str contains w ".")) =
          cand = acc_base + "_" + w
          deeper = try consume scoped words cur_mod cand (consumed :: [EVar w]) rest aliases fn_map field_map
          select scoped words cur_mod acc_base consumed ((EVar w):rest) aliases fn_map field_map deeper
      try consume scoped words cur_mod acc_base consumed args aliases fn_map field_map =
        resolved = lookup scoped fn or field cur_mod acc_base aliases fn_map field_map
        (resolved, consumed, args)

fn :: select scoped words String String [RExpr] [RExpr] [RModAlias] [RModAlias] [RModAlias] (String, [RExpr], [RExpr]) => String [RExpr] [RExpr]
      select scoped words cur_mod acc_base consumed orig_args aliases fn_map field_map ("", _, _) =
        (lookup scoped fn or field cur_mod acc_base aliases fn_map field_map, consumed, orig_args)
      select scoped words _ _ _ _ _ _ _ deeper_match = deeper_match

fn :: lookup any unimported ff String [RModAlias] [RModAlias] => String
      lookup any unimported ff base fn_map field_map
        | (map has base ident fn_map base) OR (map has base ident field_map base) = "__unimported__." + base
        | otherwise = ""

fn :: try consume unimported words String [RExpr] [RExpr] [RModAlias] [RModAlias] => String [RExpr] [RExpr]
      try consume unimported words acc_base consumed ((EVar w):rest) fn_map field_map
        | (is lower ident w) AND (NOT (str contains w ".")) =
          cand = acc_base + "_" + w
          deeper = try consume unimported words cand (consumed :: [EVar w]) rest fn_map field_map
          select unimported words acc_base consumed ((EVar w):rest) fn_map field_map deeper
      try consume unimported words acc_base consumed args fn_map field_map =
        (lookup any unimported ff acc_base fn_map field_map, consumed, args)

fn :: select unimported words String [RExpr] [RExpr] [RModAlias] [RModAlias] (String, [RExpr], [RExpr]) => String [RExpr] [RExpr]
      select unimported words acc_base consumed orig_args fn_map field_map ("", _, _) =
        (lookup any unimported ff acc_base fn_map field_map, consumed, orig_args)
      select unimported words _ _ _ _ _ deeper_match = deeper_match

fn :: rewrite rec update args [RExpr] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RExpr]
      rewrite rec update args [] _ _ _ _ _ _ _ = []
      rewrite rec update args ((EStr fname):val_e:rest) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        f_canon = resolve field str fname cur_mod aliases field_map
        val_r = rewrite expr val_e cur_mod locals special_ff aliases ctor_map fn_map field_map
        [EStr f_canon, val_r] :: (rewrite rec update args rest cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite rec update args (e:rest) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        [rewrite expr e cur_mod locals special_ff aliases ctor_map fn_map field_map] :: (rewrite rec update args rest cur_mod locals special_ff aliases ctor_map fn_map field_map)

fn :: collect lambda param strs [RExpr] [String] => [String]
      collect lambda param strs [] acc = acc
      collect lambda param strs (_:[]) acc = acc
      collect lambda param strs ((EStr p):rest) acc =
        collect lambda param strs rest ((expand lambda param names [p]) :: acc)
      collect lambda param strs (_:rest) acc =
        collect lambda param strs rest acc

fn :: rewrite lambda args [RExpr] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RExpr]
      rewrite lambda args [] _ _ _ _ _ _ _ = []
      rewrite lambda args (body_e:[]) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        [rewrite expr body_e cur_mod locals special_ff aliases ctor_map fn_map field_map]
      rewrite lambda args (p:rest) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        [p] :: (rewrite lambda args rest cur_mod locals special_ff aliases ctor_map fn_map field_map)

fn :: unpack rewritten infix call String [RExpr] RExpr => [RExpr]
      unpack rewritten infix call _ _ (ECall rw rrest) = [EVar rw] :: rrest
      unpack rewritten infix call orig_w orig_rest _ = [EVar orig_w] :: orig_rest

fn :: rewrite local call args [RExpr] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RExpr]
      rewrite local call args ((EVar w):rest) cur_mod locals special_ff aliases ctor_map fn_map field_map
        | (NOT (str in seen list w locals)) AND (NOT (is upper ident w)) AND (w != "with") AND (w != "and") AND (w != "or") =
          unpack rewritten infix call w rest (rewrite call expr w rest cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite local call args args cur_mod locals special_ff aliases ctor_map fn_map field_map =
        rewrite expr list args cur_mod locals special_ff aliases ctor_map fn_map field_map

fn :: rewrite call expr String [RExpr] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => RExpr
      rewrite call expr "__lambda__" args cur_mod locals special_ff aliases ctor_map fn_map field_map =
        locals1 = collect lambda param strs args locals
        ECall "__lambda__" (rewrite lambda args args cur_mod locals1 special_ff aliases ctor_map fn_map field_map)
      rewrite call expr "__record_update__" (base_e:rest) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        base_r = rewrite expr base_e cur_mod locals special_ff aliases ctor_map fn_map field_map
        ECall "__record_update__" ([base_r] :: (rewrite rec update args rest cur_mod locals special_ff aliases ctor_map fn_map field_map))
      rewrite call expr fn_name args cur_mod locals special_ff aliases ctor_map fn_map field_map
        | is upper ident fn_name =
          ECall (resolve ctor ident fn_name cur_mod aliases ctor_map) (rewrite expr list args cur_mod locals special_ff aliases ctor_map fn_map field_map)
        | str in seen list fn_name locals =
          ECall fn_name (rewrite local call args args cur_mod locals special_ff aliases ctor_map fn_map field_map)
        | otherwise =
          fn1 = expand mod alias fn_name cur_mod aliases
          rewrite call lower fn1 args cur_mod locals special_ff aliases ctor_map fn_map field_map

fn :: rewrite call lower String [RExpr] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => RExpr
      rewrite call lower fn1 orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map
        | str contains fn1 "." =
          m = ident mod prefix fn1
          base = ident base name fn1
          finish qual mod call fn1 orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map (try consume mod words m base [] orig_args fn_map field_map)
        | (NOT (special has word or prefix fn1 special_ff)) AND (NOT (args touch special orig_args special_ff)) =
          ECall fn1 (rewrite expr list orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map)
        | otherwise =
          finish scoped mod call fn1 orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map (try consume scoped words cur_mod fn1 [] orig_args aliases fn_map field_map)

fn :: finish qual mod call String [RExpr] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] (String, [RExpr], [RExpr]) => RExpr
      finish qual mod call fn1 orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map ("", _, _) =
        ECall fn1 (rewrite expr list orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map)
      finish qual mod call _ _ cur_mod locals special_ff aliases ctor_map fn_map field_map (resolved_fn, _, rem_args) =
        ECall resolved_fn (rewrite expr list rem_args cur_mod locals special_ff aliases ctor_map fn_map field_map)

fn :: finish scoped mod call String [RExpr] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] (String, [RExpr], [RExpr]) => RExpr
      finish scoped mod call fn1 orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map ("", _, _)
        | is mixfix reserved word fn1 =
          ECall fn1 (rewrite expr list orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map)
        | otherwise =
          finish unimp mod call fn1 orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map (try consume unimported words fn1 [] orig_args fn_map field_map)
      finish scoped mod call fn1 _ cur_mod locals special_ff aliases ctor_map fn_map field_map (resolved_fn, consumed_words, rem_args)
        | str contains resolved_fn "." =
          ECall resolved_fn (rewrite expr list rem_args cur_mod locals special_ff aliases ctor_map fn_map field_map)
        | otherwise =
          ECall fn1 (consumed_words :: (rewrite expr list rem_args cur_mod locals special_ff aliases ctor_map fn_map field_map))

fn :: finish unimp mod call String [RExpr] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] (String, [RExpr], [RExpr]) => RExpr
      finish unimp mod call fn1 orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map ("", _, _) =
        ECall fn1 (rewrite expr list orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map)
      finish unimp mod call fn1 orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map (unimp_fn, _, rem_args)
        | scope has word part cur_mod fn1 aliases fn_map =
          ECall fn1 (rewrite expr list orig_args cur_mod locals special_ff aliases ctor_map fn_map field_map)
        | otherwise =
          ECall unimp_fn (rewrite expr list rem_args cur_mod locals special_ff aliases ctor_map fn_map field_map)

fn :: rewrite expr RExpr String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => RExpr
      rewrite expr (EVar v) cur_mod locals special_ff aliases ctor_map fn_map field_map
        | is upper ident v = EVar (resolve ctor ident v cur_mod aliases ctor_map)
        | otherwise = EVar (resolve lower ident v cur_mod locals special_ff aliases fn_map field_map)
      rewrite expr (ENot inner) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        ENot (rewrite expr inner cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EOut inner) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EOut (rewrite expr inner cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EBin bop l r) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EBin bop (rewrite expr l cur_mod locals special_ff aliases ctor_map fn_map field_map) (rewrite expr r cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (ECall fn_name args) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        rewrite call expr fn_name args cur_mod locals special_ff aliases ctor_map fn_map field_map
      rewrite expr (EEcho args) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EEcho (rewrite expr list args cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EStrInterp parts) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EStrInterp (rewrite expr list parts cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EList elems) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EList (rewrite expr list elems cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (ETuple elems) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        ETuple (rewrite expr list elems cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (ETensor elems) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        ETensor (rewrite expr list elems cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EEinsum es subs) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EEinsum (rewrite expr list es cur_mod locals special_ff aliases ctor_map fn_map field_map) subs
      rewrite expr (EHadamard bop l s1 r s2) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EHadamard bop (rewrite expr l cur_mod locals special_ff aliases ctor_map fn_map field_map) s1 (rewrite expr r cur_mod locals special_ff aliases ctor_map fn_map field_map) s2
      rewrite expr (EIndex base idxs) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EIndex (rewrite expr base cur_mod locals special_ff aliases ctor_map fn_map field_map) (rewrite expr list idxs cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EIndexAssign t idxs v) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EIndexAssign t (rewrite expr list idxs cur_mod locals special_ff aliases ctor_map fn_map field_map) (rewrite expr v cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (ESeqSelect b m) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        ESeqSelect (rewrite expr b cur_mod locals special_ff aliases ctor_map fn_map field_map) m
      rewrite expr (EBlock stmts) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EBlock (rewrite stmt list stmts cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EGuard guards) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EGuard (rewrite guard list guards cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EWhere body binds) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        locals1 = collect where bound vars binds locals
        EWhere (rewrite expr body cur_mod locals1 special_ff aliases ctor_map fn_map field_map) (rewrite where list binds cur_mod locals1 special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EParPipe branches) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EParPipe (rewrite expr list branches cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EWithCtx c v b) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EWithCtx c (rewrite expr v cur_mod locals special_ff aliases ctor_map fn_map field_map) (rewrite expr b cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr (EWithRegion q b) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        EWithRegion q (rewrite expr b cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite expr e _ _ _ _ _ _ _ = e

fn :: rewrite expr list [RExpr] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RExpr]
      rewrite expr list [] _ _ _ _ _ _ _ = []
      rewrite expr list (e:es) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        [rewrite expr e cur_mod locals special_ff aliases ctor_map fn_map field_map] :: (rewrite expr list es cur_mod locals special_ff aliases ctor_map fn_map field_map)

fn :: is scoped pipe var target String String [String] [RModAlias] [RModAlias] [RModAlias] => Bool
      is scoped pipe var target cur_mod v locals aliases fn_map field_map
        | str in seen list v locals = True
        | (v == "echo") OR (is upper ident v) OR (str contains v ".") OR (is std builtin v) = False
        | otherwise = (lookup scoped fn or field cur_mod v aliases fn_map field_map) == ""

fn :: rewrite stmt list [RStmt] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RStmt]
      rewrite stmt list [] _ _ _ _ _ _ _ = []
      rewrite stmt list ((StmtLet v e):ss) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        e1 = rewrite expr e cur_mod locals special_ff aliases ctor_map fn_map field_map
        [StmtLet v e1] :: (rewrite stmt list ss cur_mod ([v] :: locals) special_ff aliases ctor_map fn_map field_map)
      rewrite stmt list ((StmtMut v e):ss) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        e1 = rewrite expr e cur_mod locals special_ff aliases ctor_map fn_map field_map
        [StmtMut v e1] :: (rewrite stmt list ss cur_mod ([v] :: locals) special_ff aliases ctor_map fn_map field_map)
      rewrite stmt list ((StmtExpr (ECall "__pipe__" (left_e:(EVar v):[]))):ss) cur_mod locals special_ff aliases ctor_map fn_map field_map
        | is scoped pipe var target cur_mod v locals aliases fn_map field_map =
          l1 = rewrite expr left_e cur_mod locals special_ff aliases ctor_map fn_map field_map
          [StmtExpr (ECall "__pipe__" [l1, EVar v])] :: (rewrite stmt list ss cur_mod ([v] :: locals) special_ff aliases ctor_map fn_map field_map)
      rewrite stmt list ((StmtExpr e):ss) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        [StmtExpr (rewrite expr e cur_mod locals special_ff aliases ctor_map fn_map field_map)] :: (rewrite stmt list ss cur_mod locals special_ff aliases ctor_map fn_map field_map)
      rewrite stmt list ((StmtIndexAssign t idxs e):ss) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        [StmtIndexAssign t (rewrite expr list idxs cur_mod locals special_ff aliases ctor_map fn_map field_map) (rewrite expr e cur_mod locals special_ff aliases ctor_map fn_map field_map)] :: (rewrite stmt list ss cur_mod locals special_ff aliases ctor_map fn_map field_map)

fn :: rewrite guard list [RGuard] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RGuard]
      rewrite guard list [] _ _ _ _ _ _ _ = []
      rewrite guard list ((GuardBranch c b):gs) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        [GuardBranch (rewrite expr c cur_mod locals special_ff aliases ctor_map fn_map field_map) (rewrite expr b cur_mod locals special_ff aliases ctor_map fn_map field_map)] :: (rewrite guard list gs cur_mod locals special_ff aliases ctor_map fn_map field_map)

fn :: rewrite where list [RWhereBind] String [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RWhereBind]
      rewrite where list [] _ _ _ _ _ _ _ = []
      rewrite where list ((WhereBind e v idxs):wbs) cur_mod locals special_ff aliases ctor_map fn_map field_map =
        [WhereBind (rewrite expr e cur_mod locals special_ff aliases ctor_map fn_map field_map) v idxs] :: (rewrite where list wbs cur_mod locals special_ff aliases ctor_map fn_map field_map)

fn :: rewrite fn cases [RFnCase] String [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] => [RFnCase]
      rewrite fn cases [] _ _ _ _ _ _ = []
      rewrite fn cases ((FnCase pats guards body):cs) cur_mod special_ff aliases ctor_map fn_map field_map =
        pats1 = rewrite pat list pats cur_mod aliases ctor_map
        locals = collect pat list bound vars pats1 []
        guards1 = rewrite guard list guards cur_mod locals special_ff aliases ctor_map fn_map field_map
        body1 = rewrite expr body cur_mod locals special_ff aliases ctor_map fn_map field_map
        [FnCase pats1 guards1 body1] :: (rewrite fn cases cs cur_mod special_ff aliases ctor_map fn_map field_map)

fn :: rewrite variants [RVariant] String [RModAlias] [RModAlias] => [RVariant]
      rewrite variants [] _ _ _ = []
      rewrite variants ((TypeVariant c args):vs) cur_mod aliases type_map =
        [TypeVariant c (rewrite type str list args cur_mod aliases type_map)] :: (rewrite variants vs cur_mod aliases type_map)

fn :: rewrite fields [RField] String [String] [RModAlias] [RModAlias] => [RField]
      rewrite fields [] _ _ _ _ = []
      rewrite fields ((TypeField fname fty):fs) cur_mod collided_fields aliases type_map =
        canon_f = canon scoped name cur_mod fname collided_fields
        [TypeField canon_f (rewrite type str fty cur_mod aliases type_map)] :: (rewrite fields fs cur_mod collided_fields aliases type_map)

fn :: rewrite and merge types [RScopedType] [RScopedType] [String] [String] [RModAlias] [RModAlias] [RTypeDef] => [RTypeDef]
      rewrite and merge types [] _ _ _ _ _ acc = acc
      rewrite and merge types ((ScopedType _ _ tdef):ts) all_ts collided_types collided_fields aliases type_map acc
        | is single variant alias tdef all_ts =
          rewrite and merge types ts all_ts collided_types collided_fields aliases type_map acc
      rewrite and merge types ((ScopedType m True (TypeDef tname vs fs)):ts) all_ts collided_types collided_fields aliases type_map acc =
        canon_t = resolve one type ident tname m aliases type_map
        vs1 = rewrite variants vs m aliases type_map
        fs1 = rewrite fields fs m collided_fields aliases type_map
        rewrite and merge types ts all_ts collided_types collided_fields aliases type_map (merge type def acc (TypeDef canon_t vs1 fs1))
      rewrite and merge types ((ScopedType m False (TypeDef tname vs fs)):ts) all_ts collided_types collided_fields aliases type_map acc =
        canon_t = canon scoped name m tname collided_types
        vs1 = rewrite variants vs m aliases type_map
        fs1 = rewrite fields fs m collided_fields aliases type_map
        rewrite and merge types ts all_ts collided_types collided_fields aliases type_map (merge type def acc (TypeDef canon_t vs1 fs1))

fn :: rewrite and merge fns cached [RScopedFn] String [String] [String] [String] [RModAlias] [RModAlias] [RModAlias] [RModAlias] [RModAlias] [RFnDef] => [RFnDef]
      rewrite and merge fns cached [] _ _ _ _ _ _ _ _ _ acc = acc
      rewrite and merge fns cached ((ScopedFn m in_lib (FnDef fname ps ret cs)):fs) cached_m cached_sp collided_fns collided_fields aliases type_map ctor_map fn_map field_map acc
        | m == cached_m =
          canon_fn = canon scoped name m fname collided_fns
          ps1 = rewrite type str list ps m aliases type_map
          ret1 = rewrite type str ret m aliases type_map
          cs1 = rewrite fn cases cs m cached_sp aliases ctor_map fn_map field_map
          acc1 = merge fn def scoped acc (FnDef canon_fn ps1 ret1 cs1) in_lib
          rewrite and merge fns cached fs cached_m cached_sp collided_fns collided_fields aliases type_map ctor_map fn_map field_map acc1
        | otherwise =
          sp1 = compute mod special ff m collided_fns collided_fields aliases fn_map field_map
          canon_fn = canon scoped name m fname collided_fns
          ps1 = rewrite type str list ps m aliases type_map
          ret1 = rewrite type str ret m aliases type_map
          cs1 = rewrite fn cases cs m sp1 aliases ctor_map fn_map field_map
          acc1 = merge fn def scoped acc (FnDef canon_fn ps1 ret1 cs1) in_lib
          rewrite and merge fns cached fs m sp1 collided_fns collided_fields aliases type_map ctor_map fn_map field_map acc1

fn :: add split ident words loop String Int Int Int [String] => [String]
      add split ident words loop s start pos len acc
        | pos >= len AND start >= len = acc
        | pos >= len = add unique seen (str slice s start len) acc
        | (str char at s pos) == 95 AND pos > start =
          acc1 = add unique seen (str slice s start pos) acc
          add split ident words loop s (pos + 1) (pos + 1) len acc1
        | (str char at s pos) == 95 =
          add split ident words loop s (pos + 1) (pos + 1) len acc
        | otherwise =
          add split ident words loop s start (pos + 1) len acc

fn :: add ident words String [String] => [String]
      add ident words "" acc = acc
      add ident words raw_s acc =
        s = ident base name raw_s
        add split ident words loop s 0 0 (str len s) acc

fn :: ident words all in loop String Int Int Int [String] => Bool
      ident words all in loop s start pos len words
        | pos >= len AND start >= len = True
        | pos >= len = str in seen list (str slice s start len) words
        | (str char at s pos) == 95 AND pos > start =
          (str in seen list (str slice s start pos) words) AND (ident words all in loop s (pos + 1) (pos + 1) len words)
        | (str char at s pos) == 95 =
          ident words all in loop s (pos + 1) (pos + 1) len words
        | otherwise =
          ident words all in loop s start (pos + 1) len words

fn :: ident words all in String [String] => Bool
      ident words all in "" _ = False
      ident words all in fname words =
        ident words all in loop fname 0 0 (str len fname) words

fn :: collect expr ident words RExpr [String] => [String]
      collect expr ident words (EVar v) acc = add ident words v acc
      collect expr ident words (ENot inner) acc = collect expr ident words inner (add unique seen "not" acc)
      collect expr ident words (EOut inner) acc = collect expr ident words inner (add unique seen "out" acc)
      collect expr ident words (EBin OpAnd l r) acc = collect expr ident words r (collect expr ident words l (add unique seen "and" acc))
      collect expr ident words (EBin OpOr l r) acc = collect expr ident words r (collect expr ident words l (add unique seen "or" acc))
      collect expr ident words (EBin OpXor l r) acc = collect expr ident words r (collect expr ident words l (add unique seen "xor" acc))
      collect expr ident words (EBin OpAdd l r) acc = collect expr ident words r (collect expr ident words l (add unique seen "+" acc))
      collect expr ident words (EBin OpSub l r) acc = collect expr ident words r (collect expr ident words l (add unique seen "-" acc))
      collect expr ident words (EBin OpMul l r) acc = collect expr ident words r (collect expr ident words l (add unique seen "*" acc))
      collect expr ident words (EBin OpDiv l r) acc = collect expr ident words r (collect expr ident words l (add unique seen "/" acc))
      collect expr ident words (EBin OpMod l r) acc = collect expr ident words r (collect expr ident words l (add unique seen "%" acc))
      collect expr ident words (EBin _ l r) acc = collect expr ident words r (collect expr ident words l acc)
      collect expr ident words (ECall fn_name args) acc =
        collect expr list ident words args (add ident words fn_name acc)
      collect expr ident words (EEcho args) acc = collect expr list ident words args acc
      collect expr ident words (EStrInterp parts) acc = collect expr list ident words parts acc
      collect expr ident words (EList elems) acc = collect expr list ident words elems acc
      collect expr ident words (ETuple elems) acc = collect expr list ident words elems acc
      collect expr ident words (ETensor elems) acc = collect expr list ident words elems acc
      collect expr ident words (EEinsum es _) acc = collect expr list ident words es acc
      collect expr ident words (EHadamard _ l _ r _) acc = collect expr ident words r (collect expr ident words l acc)
      collect expr ident words (EIndex b idxs) acc = collect expr list ident words idxs (collect expr ident words b acc)
      collect expr ident words (EIndexAssign t idxs v) acc = collect expr ident words v (collect expr list ident words idxs (add ident words t acc))
      collect expr ident words (ESeqSelect b _) acc = collect expr ident words b acc
      collect expr ident words (EBlock stmts) acc = collect stmt list ident words stmts acc
      collect expr ident words (EGuard gs) acc = collect guard list ident words gs acc
      collect expr ident words (EWhere b wbs) acc = collect where list ident words wbs (collect expr ident words b acc)
      collect expr ident words (EParPipe bs) acc = collect expr list ident words bs acc
      collect expr ident words (EWithCtx _ v b) acc = collect expr ident words b (collect expr ident words v acc)
      collect expr ident words (EWithRegion _ b) acc = collect expr ident words b acc
      collect expr ident words _ acc = acc

fn :: collect expr list ident words [RExpr] [String] => [String]
      collect expr list ident words [] acc = acc
      collect expr list ident words (e:es) acc = collect expr list ident words es (collect expr ident words e acc)

fn :: collect stmt list ident words [RStmt] [String] => [String]
      collect stmt list ident words [] acc = acc
      collect stmt list ident words ((StmtLet _ e):ss) acc = collect stmt list ident words ss (collect expr ident words e acc)
      collect stmt list ident words ((StmtMut _ e):ss) acc = collect stmt list ident words ss (collect expr ident words e acc)
      collect stmt list ident words ((StmtExpr e):ss) acc = collect stmt list ident words ss (collect expr ident words e acc)
      collect stmt list ident words ((StmtIndexAssign t idxs e):ss) acc = collect stmt list ident words ss (collect expr ident words (EIndexAssign t idxs e) acc)

fn :: collect guard list ident words [RGuard] [String] => [String]
      collect guard list ident words [] acc = acc
      collect guard list ident words ((GuardBranch c b):gs) acc = collect guard list ident words gs (collect expr ident words b (collect expr ident words c acc))

fn :: collect where list ident words [RWhereBind] [String] => [String]
      collect where list ident words [] acc = acc
      collect where list ident words ((WhereBind e _ _):wbs) acc = collect where list ident words wbs (collect expr ident words e acc)

fn :: collect cases word sets [RFnCase] [[String]] => [[String]]
      collect cases word sets [] acc = acc
      collect cases word sets ((FnCase _ gs body):cs) acc =
        wset = collect expr ident words body (collect guard list ident words gs [])
        collect cases word sets cs ([wset] :: acc)

fn :: any case has all words String [[String]] => Bool
      any case has all words _ [] = False
      any case has all words fname (wset:wsets)
        | ident words all in fname wset = True
        | otherwise = any case has all words fname wsets

fn :: has any word set [[String]] => Bool
      has any word set [] = False
      has any word set (_:_) = True

fn :: is root scoped fn RScopedFn => Bool
      is root scoped fn (ScopedFn _ False _) = True
      is root scoped fn (ScopedFn _ True (FnDef fname _ _ _)) =
        is special top fn fname

fn :: collect root word sets [RScopedFn] [[String]] => [[String]]
      collect root word sets [] acc = acc
      collect root word sets (sf:sfs) acc
        | is root scoped fn sf =
          collect root word sets step sf sfs acc
        | otherwise = collect root word sets sfs acc

fn :: collect root word sets step RScopedFn [RScopedFn] [[String]] => [[String]]
      collect root word sets step (ScopedFn _ _ (FnDef _ _ _ cs)) sfs acc =
        collect root word sets sfs (collect cases word sets cs acc)

fn :: collect all fname word sets [RScopedFn] String [[String]] => [[String]]
      collect all fname word sets [] _ acc = acc
      collect all fname word sets ((ScopedFn _ True (FnDef fn_k _ _ cs)):sfs) target acc
        | fn_k == target = collect all fname word sets sfs target (collect cases word sets cs acc)
        | otherwise = collect all fname word sets sfs target acc
      collect all fname word sets (_:sfs) target acc =
        collect all fname word sets sfs target acc

fn :: expand reachable words pass [RScopedFn] [RScopedFn] [[String]] [[String]] [String] => [[String]] [String]
      expand reachable words pass [] _ _ next_sets reached = (next_sets, reached)
      expand reachable words pass ((ScopedFn _ True (FnDef fname _ _ _)):sfs) all_sfs frontier next_sets reached =
        expand reach step fname sfs all_sfs frontier next_sets reached
      expand reachable words pass (_:sfs) all_sfs frontier next_sets reached =
        expand reachable words pass sfs all_sfs frontier next_sets reached

fn :: expand reach step String [RScopedFn] [RScopedFn] [[String]] [[String]] [String] => [[String]] [String]
      expand reach step fname sfs all_sfs frontier next_sets reached
        | (NOT (str in seen list fname reached)) AND (any case has all words fname frontier) =
          next_sets1 = collect all fname word sets all_sfs fname next_sets
          expand reachable words pass sfs all_sfs frontier next_sets1 ([fname] :: reached)
        | otherwise =
          expand reachable words pass sfs all_sfs frontier next_sets reached

fn :: expand reachable words fix [RScopedFn] ([[String]], [String]) => [String]
      expand reachable words fix sfs (frontier, reached)
        | NOT (has any word set frontier) = reached
        | otherwise =
          expand reachable words fix sfs (expand reachable words pass sfs sfs frontier [] reached)

fn :: filter reachable scoped fns [RScopedFn] [String] => [RScopedFn]
      filter reachable scoped fns [] _ = []
      filter reachable scoped fns (sf:sfs) reached
        | is root scoped fn sf = [sf] :: (filter reachable scoped fns sfs reached)
      filter reachable scoped fns ((ScopedFn m True (FnDef fname ps ret cs)):sfs) reached
        | str in seen list fname reached =
          [ScopedFn m True (FnDef fname ps ret cs)] :: (filter reachable scoped fns sfs reached)
        | otherwise = filter reachable scoped fns sfs reached

fn :: has any user fn [RScopedFn] => Bool
      has any user fn [] = False
      has any user fn ((ScopedFn _ False _):_) = True
      has any user fn (_:sfs) = has any user fn sfs

fn :: has any lib fn [RScopedFn] => Bool
      has any lib fn [] = False
      has any lib fn ((ScopedFn _ True _):_) = True
      has any lib fn (_:sfs) = has any lib fn sfs

fn :: prune unreachable lib fns [RScopedFn] => [RScopedFn]
      prune unreachable lib fns s_fns
        | (has any user fn s_fns) AND (has any lib fn s_fns) =
          init_sets = collect root word sets s_fns []
          reached = expand reachable words fix s_fns (init_sets, [])
          filter reachable scoped fns s_fns reached
        | otherwise = s_fns

fn :: merge plain scoped types [RScopedType] [RTypeDef] => [RTypeDef]
      merge plain scoped types [] acc = acc
      merge plain scoped types ((ScopedType _ _ tdef):ts) acc =
        merge plain scoped types ts (merge type def acc tdef)

fn :: merge plain scoped fns [RScopedFn] [RFnDef] => [RFnDef]
      merge plain scoped fns [] acc = acc
      merge plain scoped fns ((ScopedFn _ in_lib fdef):fs) acc =
        merge plain scoped fns fs (merge fn def scoped acc fdef in_lib)

fn :: is compiler builtin ident String => Bool
      is compiler builtin ident "assert_equals" = False
      is compiler builtin ident "assert_true"   = False
      is compiler builtin ident s =
        (is std builtin s) or ((lookup arity (builtin arity entries) s) >= 0)

fn :: collect field base names [RField] [String] => [String]
      collect field base names [] acc = acc
      collect field base names ((TypeField fname _):fs) acc =
        collect field base names fs (add unique seen (ident base name fname) acc)

fn :: collect typedef field names [RTypeDef] [String] => [String]
      collect typedef field names [] acc = acc
      collect typedef field names ((TypeDef _ _ fs):ts) acc =
        collect typedef field names ts (collect field base names fs acc)

fn :: collect scoped type field names [RScopedType] [String] => [String]
      collect scoped type field names [] acc = acc
      collect scoped type field names ((ScopedType _ _ (TypeDef _ _ fs)):ts) acc =
        collect scoped type field names ts (collect field base names fs acc)

fn :: collect fndef base names [RFnDef] [String] => [String]
      collect fndef base names [] acc = acc
      collect fndef base names ((FnDef fname _ _ _):fs) acc =
        collect fndef base names fs (add unique seen (ident base name fname) acc)

fn :: collect scoped fn base names [RScopedFn] [String] => [String]
      collect scoped fn base names [] acc = acc
      collect scoped fn base names ((ScopedFn _ _ (FnDef fname _ _ _)):fs) acc =
        collect scoped fn base names fs (add unique seen (ident base name fname) acc)

fn :: expr mentions var RExpr String => Bool
      expr mentions var (EVar w) target =
        w == target or ((is subscript ident w) and (extract fst str (split subscript w)) == target)
      expr mentions var (ENot inner) target = expr mentions var inner target
      expr mentions var (EOut inner) target = expr mentions var inner target
      expr mentions var (EBin _ l r) target = (expr mentions var l target) or (expr mentions var r target)
      expr mentions var (ECall fn_name args) target =
        fn_name == target or (expr list mentions var args target)
      expr mentions var (EEcho args) target = expr list mentions var args target
      expr mentions var (EStrInterp parts) target = expr list mentions var parts target
      expr mentions var (EList elems) target = expr list mentions var elems target
      expr mentions var (ETuple elems) target = expr list mentions var elems target
      expr mentions var (ETensor elems) target = expr list mentions var elems target
      expr mentions var (EEinsum es _) target = expr list mentions var es target
      expr mentions var (EHadamard _ l _ r _) target = (expr mentions var l target) or (expr mentions var r target)
      expr mentions var (EIndex base idxs) target = (expr mentions var base target) or (expr list mentions var idxs target)
      expr mentions var (EIndexAssign t idxs v) target =
        t == target or (expr list mentions var idxs target) or (expr mentions var v target)
      expr mentions var (ESeqSelect b _) target = expr mentions var b target
      expr mentions var (EBlock stmts) target = stmt list mentions var stmts target
      expr mentions var (EGuard gs) target = guard list mentions var gs target
      expr mentions var (EWhere b wbs) target = (expr mentions var b target) or (where list mentions var wbs target)
      expr mentions var (EParPipe bs) target = expr list mentions var bs target
      expr mentions var (EWithCtx _ v b) target = (expr mentions var v target) or (expr mentions var b target)
      expr mentions var (EWithRegion _ b) target = expr mentions var b target
      expr mentions var _ _ = False

fn :: expr list mentions var [RExpr] String => Bool
      expr list mentions var [] _ = False
      expr list mentions var (e:es) target
        | expr mentions var e target = True
        | otherwise = expr list mentions var es target

fn :: stmt list mentions var [RStmt] String => Bool
      stmt list mentions var [] _ = False
      stmt list mentions var ((StmtLet _ e):ss) target =
        (expr mentions var e target) or (stmt list mentions var ss target)
      stmt list mentions var ((StmtMut _ e):ss) target =
        (expr mentions var e target) or (stmt list mentions var ss target)
      stmt list mentions var ((StmtExpr e):ss) target =
        (expr mentions var e target) or (stmt list mentions var ss target)
      stmt list mentions var ((StmtIndexAssign t idxs e):ss) target =
        t == target or (expr list mentions var idxs target) or (expr mentions var e target) or (stmt list mentions var ss target)

fn :: guard list mentions var [RGuard] String => Bool
      guard list mentions var [] _ = False
      guard list mentions var ((GuardBranch c b):gs) target =
        (expr mentions var c target) or (expr mentions var b target) or (guard list mentions var gs target)

fn :: where list mentions var [RWhereBind] String => Bool
      where list mentions var [] _ = False
      where list mentions var ((WhereBind e _ _):wbs) target =
        (expr mentions var e target) or (where list mentions var wbs target)

fn :: should encode base underscores String String [String] [String] Bool => Bool
      should encode base underscores v base locals field_names encode_builtins
        | not (str contains base "_") = False
        | (str starts with base "__") or (str starts with base ":") = False
        | (str in seen list v locals) or (str in seen list base locals) = False
        | (is subscript ident v) and ((is upper ident v) or (str in seen list (extract fst str (split subscript v)) locals)) = False
        | str in seen list base field_names = False
        | (not encode_builtins) and (is compiler builtin ident base) = False
        | otherwise = True

fn :: should encode ident underscores String [String] [String] Bool => Bool
      should encode ident underscores v locals field_names encode_builtins
        | v == "_" or v == "__" or v == "___" = False
        | is upper ident v = False
        | (str starts with v "__") or (str starts with v ":") = False
        | otherwise =
          base = ident base name v
          should encode base underscores v base locals field_names encode_builtins

fn :: encode ident underscores String [String] [String] Bool => String
      encode ident underscores v locals field_names encode_builtins
        | not (should encode ident underscores v locals field_names encode_builtins) = v
        | str contains v "." =
          (ident mod prefix v) + "." + (encode literal underscores (ident base name v))
        | otherwise = encode literal underscores v

fn :: encode lambda args underscores [RExpr] [String] [String] [String] Bool => [RExpr]
      encode lambda args underscores [] _ _ _ _ = []
      encode lambda args underscores (body_e:[]) locals field_names fn_names encode_builtins =
        [encode expr underscores body_e locals field_names fn_names encode_builtins]
      encode lambda args underscores (p:rest) locals field_names fn_names encode_builtins =
        [p] :: (encode lambda args underscores rest locals field_names fn_names encode_builtins)

fn :: encode rec update args underscores [RExpr] [String] [String] [String] Bool => [RExpr]
      encode rec update args underscores [] _ _ _ _ = []
      encode rec update args underscores ((EStr fname):val_e:rest) locals field_names fn_names encode_builtins =
        val1 = encode expr underscores val_e locals field_names fn_names encode_builtins
        [EStr fname, val1] :: (encode rec update args underscores rest locals field_names fn_names encode_builtins)
      encode rec update args underscores (e:rest) locals field_names fn_names encode_builtins =
        [encode expr underscores e locals field_names fn_names encode_builtins] :: (encode rec update args underscores rest locals field_names fn_names encode_builtins)

fn :: is encode pipe var target String [RStmt] [String] [String] [String] => Bool
      is encode pipe var target v ss locals field_names fn_names
        | (v == "echo") or (is upper ident v) or (str contains v ".") or (is compiler builtin ident v) = False
        | str in seen list v locals = True
        | str in seen list v field_names = False
        | str in seen list (encode literal underscores v) fn_names = False
        | (is subscript ident v) and ((is upper ident v) or (str in seen list (extract fst str (split subscript v)) locals)) = True
        | otherwise = stmt list mentions var ss v

fn :: encode expr underscores RExpr [String] [String] [String] Bool => RExpr
      encode expr underscores (EVar v) locals field_names _ encode_builtins =
        EVar (encode ident underscores v locals field_names encode_builtins)
      encode expr underscores (ENot inner) locals field_names fn_names encode_builtins =
        ENot (encode expr underscores inner locals field_names fn_names encode_builtins)
      encode expr underscores (EOut inner) locals field_names fn_names encode_builtins =
        EOut (encode expr underscores inner locals field_names fn_names encode_builtins)
      encode expr underscores (EBin bop l r) locals field_names fn_names encode_builtins =
        EBin bop (encode expr underscores l locals field_names fn_names encode_builtins) (encode expr underscores r locals field_names fn_names encode_builtins)
      encode expr underscores (ECall "__lambda__" args) locals field_names fn_names encode_builtins =
        locals1 = collect lambda param strs args locals
        ECall "__lambda__" (encode lambda args underscores args locals1 field_names fn_names encode_builtins)
      encode expr underscores (ECall "__record_update__" (base_e:rest)) locals field_names fn_names encode_builtins =
        base1 = encode expr underscores base_e locals field_names fn_names encode_builtins
        ECall "__record_update__" ([base1] :: (encode rec update args underscores rest locals field_names fn_names encode_builtins))
      encode expr underscores (ECall fn_name args) locals field_names fn_names encode_builtins =
        ECall (encode ident underscores fn_name locals field_names encode_builtins) (encode expr list underscores args locals field_names fn_names encode_builtins)
      encode expr underscores (EEcho args) locals field_names fn_names encode_builtins =
        EEcho (encode expr list underscores args locals field_names fn_names encode_builtins)
      encode expr underscores (EStrInterp parts) locals field_names fn_names encode_builtins =
        EStrInterp (encode expr list underscores parts locals field_names fn_names encode_builtins)
      encode expr underscores (EList elems) locals field_names fn_names encode_builtins =
        EList (encode expr list underscores elems locals field_names fn_names encode_builtins)
      encode expr underscores (ETuple elems) locals field_names fn_names encode_builtins =
        ETuple (encode expr list underscores elems locals field_names fn_names encode_builtins)
      encode expr underscores (ETensor elems) locals field_names fn_names encode_builtins =
        ETensor (encode expr list underscores elems locals field_names fn_names encode_builtins)
      encode expr underscores (EEinsum es subs) locals field_names fn_names encode_builtins =
        EEinsum (encode expr list underscores es locals field_names fn_names encode_builtins) subs
      encode expr underscores (EHadamard bop l s1 r s2) locals field_names fn_names encode_builtins =
        EHadamard bop (encode expr underscores l locals field_names fn_names encode_builtins) s1 (encode expr underscores r locals field_names fn_names encode_builtins) s2
      encode expr underscores (EIndex base idxs) locals field_names fn_names encode_builtins =
        EIndex (encode expr underscores base locals field_names fn_names encode_builtins) (encode expr list underscores idxs locals field_names fn_names encode_builtins)
      encode expr underscores (EIndexAssign t idxs v) locals field_names fn_names encode_builtins =
        EIndexAssign t (encode expr list underscores idxs locals field_names fn_names encode_builtins) (encode expr underscores v locals field_names fn_names encode_builtins)
      encode expr underscores (ESeqSelect b m) locals field_names fn_names encode_builtins =
        ESeqSelect (encode expr underscores b locals field_names fn_names encode_builtins) m
      encode expr underscores (EBlock stmts) locals field_names fn_names encode_builtins =
        EBlock (encode stmt list underscores stmts locals field_names fn_names encode_builtins)
      encode expr underscores (EGuard guards) locals field_names fn_names encode_builtins =
        EGuard (encode guard list underscores guards locals field_names fn_names encode_builtins)
      encode expr underscores (EWhere body binds) locals field_names fn_names encode_builtins =
        locals1 = collect where bound vars binds locals
        EWhere (encode expr underscores body locals1 field_names fn_names encode_builtins) (encode where list underscores binds locals1 field_names fn_names encode_builtins)
      encode expr underscores (EParPipe branches) locals field_names fn_names encode_builtins =
        EParPipe (encode expr list underscores branches locals field_names fn_names encode_builtins)
      encode expr underscores (EWithCtx c v b) locals field_names fn_names encode_builtins =
        EWithCtx c (encode expr underscores v locals field_names fn_names encode_builtins) (encode expr underscores b ([c] :: locals) field_names fn_names encode_builtins)
      encode expr underscores (EWithRegion q b) locals field_names fn_names encode_builtins =
        EWithRegion q (encode expr underscores b locals field_names fn_names encode_builtins)
      encode expr underscores e _ _ _ _ = e

fn :: encode expr list underscores [RExpr] [String] [String] [String] Bool => [RExpr]
      encode expr list underscores [] _ _ _ _ = []
      encode expr list underscores (e:es) locals field_names fn_names encode_builtins =
        [encode expr underscores e locals field_names fn_names encode_builtins] :: (encode expr list underscores es locals field_names fn_names encode_builtins)

fn :: encode stmt list underscores [RStmt] [String] [String] [String] Bool => [RStmt]
      encode stmt list underscores [] _ _ _ _ = []
      encode stmt list underscores ((StmtLet v e):ss) locals field_names fn_names encode_builtins =
        e1 = encode expr underscores e locals field_names fn_names encode_builtins
        [StmtLet v e1] :: (encode stmt list underscores ss ([v] :: locals) field_names fn_names encode_builtins)
      encode stmt list underscores ((StmtMut v e):ss) locals field_names fn_names encode_builtins =
        e1 = encode expr underscores e locals field_names fn_names encode_builtins
        [StmtMut v e1] :: (encode stmt list underscores ss ([v] :: locals) field_names fn_names encode_builtins)
      encode stmt list underscores ((StmtExpr (ECall "__pipe__" (left_e:(EVar v):[]))):ss) locals field_names fn_names encode_builtins
        | is encode pipe var target v ss locals field_names fn_names =
          l1 = encode expr underscores left_e locals field_names fn_names encode_builtins
          [StmtExpr (ECall "__pipe__" [l1, EVar v])] :: (encode stmt list underscores ss ([v] :: locals) field_names fn_names encode_builtins)
      encode stmt list underscores ((StmtExpr e):ss) locals field_names fn_names encode_builtins =
        [StmtExpr (encode expr underscores e locals field_names fn_names encode_builtins)] :: (encode stmt list underscores ss locals field_names fn_names encode_builtins)
      encode stmt list underscores ((StmtIndexAssign t idxs e):ss) locals field_names fn_names encode_builtins =
        [StmtIndexAssign t (encode expr list underscores idxs locals field_names fn_names encode_builtins) (encode expr underscores e locals field_names fn_names encode_builtins)] :: (encode stmt list underscores ss locals field_names fn_names encode_builtins)

fn :: encode guard list underscores [RGuard] [String] [String] [String] Bool => [RGuard]
      encode guard list underscores [] _ _ _ _ = []
      encode guard list underscores ((GuardBranch c b):gs) locals field_names fn_names encode_builtins =
        [GuardBranch (encode expr underscores c locals field_names fn_names encode_builtins) (encode expr underscores b locals field_names fn_names encode_builtins)] :: (encode guard list underscores gs locals field_names fn_names encode_builtins)

fn :: encode where list underscores [RWhereBind] [String] [String] [String] Bool => [RWhereBind]
      encode where list underscores [] _ _ _ _ = []
      encode where list underscores ((WhereBind e v idxs):wbs) locals field_names fn_names encode_builtins =
        [WhereBind (encode expr underscores e locals field_names fn_names encode_builtins) v idxs] :: (encode where list underscores wbs locals field_names fn_names encode_builtins)

fn :: encode fn cases underscores [RFnCase] [String] [String] Bool => [RFnCase]
      encode fn cases underscores [] _ _ _ = []
      encode fn cases underscores ((FnCase pats guards body):cs) field_names fn_names encode_builtins =
        locals = collect pat list bound vars pats []
        guards1 = encode guard list underscores guards locals field_names fn_names encode_builtins
        body1 = encode expr underscores body locals field_names fn_names encode_builtins
        [FnCase pats guards1 body1] :: (encode fn cases underscores cs field_names fn_names encode_builtins)

fn :: encode fndef list underscores [RFnDef] [RTypeDef] Bool => [RFnDef]
      encode fndef list underscores fns tys encode_builtins =
        field_names = collect typedef field names tys []
        fn_names = collect fndef base names fns []
        encode fndef list underscores loop fns field_names fn_names encode_builtins

fn :: encode fndef list underscores loop [RFnDef] [String] [String] Bool => [RFnDef]
      encode fndef list underscores loop [] _ _ _ = []
      encode fndef list underscores loop ((FnDef fname ps ret cs):fs) field_names fn_names encode_builtins =
        [FnDef fname ps ret (encode fn cases underscores cs field_names fn_names encode_builtins)] :: (encode fndef list underscores loop fs field_names fn_names encode_builtins)

fn :: encode scoped fn list [RScopedFn] [String] [String] Bool => [RScopedFn]
      encode scoped fn list [] _ _ _ = []
      encode scoped fn list ((ScopedFn m in_lib (FnDef fname ps ret cs)):fs) field_names fn_names encode_builtins =
        [ScopedFn m in_lib (FnDef fname ps ret (encode fn cases underscores cs field_names fn_names encode_builtins))] :: (encode scoped fn list fs field_names fn_names encode_builtins)

fn :: encode all scoped fns [RScopedFn] [RScopedType] => [RScopedFn]
      encode all scoped fns raw_s_fns s_tys =
        field_names = collect scoped type field names s_tys []
        fn_names = collect scoped fn base names raw_s_fns []
        encode scoped fn list raw_s_fns field_names fn_names False

fn :: resolve scoped state [RScopedFn] [RScopedType] [RModAlias] => RProgram
      resolve scoped state raw_s_fns s_tys aliases =
        enc_s_fns = encode all scoped fns raw_s_fns s_tys
        resolve scoped state encoded enc_s_fns s_tys aliases

fn :: resolve scoped state encoded [RScopedFn] [RScopedType] [RModAlias] => RProgram
      resolve scoped state encoded raw_s_fns s_tys aliases
        | NOT (has any scoped mod raw_s_fns s_tys aliases) =
          Program (merge plain scoped fns raw_s_fns []) (merge plain scoped types s_tys [])
        | otherwise =
          s_fns = prune unreachable lib fns raw_s_fns
          collided_types = collect collided types s_tys s_tys []
          collided_fields = collect collided fields s_tys s_tys []
          collided_fns = collect collided fns s_fns s_fns []
          collided_ctors = collect collided ctors s_tys s_tys []
          base_tmap = build base type map s_tys s_tys collided_types
          type_map = build alias type map s_tys s_tys collided_types aliases base_tmap
          ctor_map = build ctor map s_tys s_tys collided_types collided_ctors type_map
          field_map = build field map s_tys collided_fields
          fn_map = build fn map s_fns collided_fns
          tys_out = rewrite and merge types s_tys s_tys collided_types collided_fields aliases type_map []
          fns_out = rewrite and merge fns cached s_fns "__none__" [] collided_fns collided_fields aliases type_map ctor_map fn_map field_map []
          Program fns_out tys_out

-- ── Top-Level Program Loop ──────────────────────────────────

fn :: tokens have user src marker [RToken] => Bool
      tokens have user src marker [] = False
      tokens have user src marker (TokAt:(TokIdent "__rg_user_src__"):_) = True
      tokens have user src marker (_:ts) = tokens have user src marker ts

fn :: line has colon colon [RToken]          => Bool
      line has colon colon []                =  False
      line has colon colon (TokEof:_)        =  False
      line has colon colon (TokNewline:_)    =  False
      line has colon colon (TokColonColon:_) =  True
      line has colon colon (_:ts)            =  line has colon colon ts

fn :: add scoped fndefs [RFnDef] String Bool [RScopedFn] => [RScopedFn]
      add scoped fndefs [] _ _ acc = acc
      add scoped fndefs (f:fs) cur_mod in_lib acc =
        add scoped fndefs fs cur_mod in_lib (acc :: [ScopedFn cur_mod in_lib f])

fn :: parse items after fn mod (RFnDef, [RToken]) [RScopedFn] [RScopedType] [RModAlias] [String] Bool => [RScopedFn] [RScopedType] [RModAlias]
      parse items after fn mod (fdef, rest) s_fns s_tys aliases mod_stack in_lib =
        cur_mod = cur mod of stack mod_stack
        parse items mod rest (s_fns :: [ScopedFn cur_mod in_lib fdef]) s_tys aliases mod_stack in_lib

fn :: parse items after fndefs mod ([RFnDef], [RToken]) [RScopedFn] [RScopedType] [RModAlias] [String] Bool => [RScopedFn] [RScopedType] [RModAlias]
      parse items after fndefs mod (new_fns, rest) s_fns s_tys aliases mod_stack in_lib =
        cur_mod = cur mod of stack mod_stack
        parse items mod rest (add scoped fndefs new_fns cur_mod in_lib s_fns) s_tys aliases mod_stack in_lib

fn :: parse items after type mod Bool (RTypeDef, [RToken]) [RScopedFn] [RScopedType] [RModAlias] [String] Bool => [RScopedFn] [RScopedType] [RModAlias]
      parse items after type mod is_exp (tdef, rest) s_fns s_tys aliases mod_stack in_lib =
        cur_mod = cur mod of stack mod_stack
        parse items mod rest s_fns (s_tys :: [ScopedType cur_mod is_exp tdef]) aliases mod_stack in_lib

fn :: parse items mod [RToken] [RScopedFn] [RScopedType] [RModAlias] [String] Bool => [RScopedFn] [RScopedType] [RModAlias]
      parse items mod []                 s_fns s_tys aliases _         _      =  (s_fns, s_tys, aliases)
      parse items mod (TokEof:_)         s_fns s_tys aliases _         _      =  (s_fns, s_tys, aliases)
      parse items mod (TokNewline:rest)  s_fns s_tys aliases mod_stack in_lib =  parse items mod rest s_fns s_tys aliases mod_stack in_lib
      parse items mod (TokAt:(TokIdent "__rg_user_src__"):rest) s_fns s_tys aliases _ _ =
        parse items mod (skip to newline rest) s_fns s_tys aliases [] False
      parse items mod (TokAt:(TokIdent "__rg_mod_enter__"):(TokIdent mname):rest) s_fns s_tys aliases mod_stack in_lib =
        parse items mod (skip to newline rest) s_fns s_tys aliases ([":" + mname] :: mod_stack) in_lib
      parse items mod (TokAt:(TokIdent "__rg_mod_exit__"):rest) s_fns s_tys aliases mod_stack in_lib =
        child_mod = cur mod of stack mod_stack
        rest_stack = pop mod stack mod_stack
        parent_mod = cur mod of stack rest_stack
        aliases1 = record exit import in_lib rest_stack parent_mod child_mod aliases
        parse items mod (skip to newline rest) s_fns s_tys aliases1 rest_stack in_lib
      parse items mod (TokAt:(TokIdent "__rg_mod_import__"):(TokIdent target):rest) s_fns s_tys aliases mod_stack in_lib =
        cur_mod = cur mod of stack mod_stack
        parse items mod (skip to newline rest) s_fns s_tys (add mod import cur_mod target aliases) mod_stack in_lib
      parse items mod (TokAt:(TokIdent "__rg_mod_alias__"):(TokIdent al):(TokIdent target):rest) s_fns s_tys aliases mod_stack in_lib =
        cur_mod = cur mod of stack mod_stack
        aliases1 = add scoped alias cur_mod al target (add mod import cur_mod target aliases)
        parse items mod (skip to newline rest) s_fns s_tys aliases1 mod_stack in_lib
      parse items mod (TokAt:rest)       s_fns s_tys aliases mod_stack in_lib =
        parse items mod (skip to newline rest) s_fns s_tys aliases mod_stack in_lib
      parse items mod ((TokIdent "RGC1"):rest) s_fns s_tys aliases mod_stack in_lib =
        parse items mod (skip to newline rest) s_fns s_tys aliases mod_stack in_lib
      parse items mod ((TokIdent "module"):TokColonColon:(TokIdent mname):rest) s_fns s_tys aliases mod_stack in_lib =
        new_stack = set explicit mod mname mod_stack
        new_mod = cur mod of stack new_stack
        aliases1 = record enter rename mod_stack new_mod aliases
        parse items mod (skip to newline rest) s_fns s_tys aliases1 new_stack in_lib
      parse items mod (TokImport:rest)   s_fns s_tys aliases mod_stack in_lib =
        cur_mod = cur mod of stack mod_stack
        parse items mod (skip to newline rest) s_fns s_tys (parse inline import rest cur_mod aliases) mod_stack in_lib
      parse items mod (TokFn:rest)       s_fns s_tys aliases mod_stack in_lib =
        f_res = parse fn decl ([TokFn] :: rest)
        parse items after fn mod f_res s_fns s_tys aliases mod_stack in_lib
      parse items mod (TokOp:rest)       s_fns s_tys aliases mod_stack in_lib =
        o_res = parse op decl ([TokOp] :: rest)
        parse items after fn mod o_res s_fns s_tys aliases mod_stack in_lib
      parse items mod (TokHardware:rest) s_fns s_tys aliases mod_stack in_lib =
        hw_res = parse hardware decl ([TokHardware] :: rest)
        parse items after fndefs mod hw_res s_fns s_tys aliases mod_stack in_lib
      parse items mod (TokType:(TokIdent name):rest) s_fns s_tys aliases mod_stack in_lib
        | (is upper ident name) AND (has type params then eq rest) =
          t_res = parse type decl ([TokType, TokIdent name] :: rest)
          parse items after type mod False t_res s_fns s_tys aliases mod_stack in_lib
      parse items mod ((TokIdent "expand"):TokType:(TokIdent name):rest) s_fns s_tys aliases mod_stack in_lib
        | (is upper ident name) AND (has type params then eq rest) =
          t_res = parse type decl ([TokType, TokIdent name] :: rest)
          parse items after type mod True t_res s_fns s_tys aliases mod_stack in_lib
      parse items mod ts                 s_fns s_tys aliases mod_stack in_lib
        | (NOT (line has colon colon ts)) AND (line has fat arrow ts) =
          parse items after fn mod (parse bare decl ts) s_fns s_tys aliases mod_stack in_lib
        | otherwise =
          err_fn = FnDef "__syntax_error__" [] "Int" [FnCase [] [] (ECall "__syntax_error__" [EStr "unknown or invalid top-level declaration"])]
          cur_mod = cur mod of stack mod_stack
          parse items mod (skip to newline (tok tail ts)) (s_fns :: [ScopedFn cur_mod in_lib err_fn]) s_tys aliases mod_stack in_lib

fn :: skip to user src marker [RToken] => [RToken]
      skip to user src marker [] = []
      skip to user src marker (TokAt:(TokIdent "__rg_user_src__"):rest) =
        skip to user src marker (skip to newline rest)
      skip to user src marker (_:rest) =
        skip to user src marker rest

fn :: user src tokens [RToken] => [RToken]
      user src tokens toks
        | tokens have user src marker toks = skip to user src marker toks
        | otherwise = toks

fn :: filter non lib scoped fns [RScopedFn] => [RFnDef]
      filter non lib scoped fns [] = []
      filter non lib scoped fns ((ScopedFn _ True _):fs) = filter non lib scoped fns fs
      filter non lib scoped fns ((ScopedFn _ False fdef):fs) = [fdef] :: (filter non lib scoped fns fs)

fn :: finish strict user fns ([RScopedFn], [RScopedType], [RModAlias]) => [RFnDef]
      finish strict user fns (raw_s_fns, s_tys, _) =
        field_names = collect scoped type field names s_tys []
        fn_names = collect scoped fn base names raw_s_fns []
        enc_s_fns = encode scoped fn list raw_s_fns field_names fn_names True
        filter non lib scoped fns enc_s_fns

fn :: parse strict user fns [RToken] => [RFnDef]
      parse strict user fns toks =
        finish strict user fns (parse items mod toks [] [] [] [] (tokens have user src marker toks))

fn :: finish parse items ([RScopedFn], [RScopedType], [RModAlias]) => RProgram
      finish parse items (s_fns, s_tys, aliases) =
        resolve scoped state s_fns s_tys aliases

fn :: parse items [RToken] [RFnDef] [RTypeDef] => RProgram
      parse items toks     _        _          =
        finish parse items (parse items mod toks [] [] [] [] (tokens have user src marker toks))

fn :: is catchall pat RPattern   => Bool
      is catchall pat PatWild    =  True
      is catchall pat (PatVar _) =  True
      is catchall pat _          =  False

fn :: all catchall pats [RPattern] => Bool
      all catchall pats []         =  True
      all catchall pats (p:ps)
        | is catchall pat p = all catchall pats ps
        | otherwise = False

fn :: is catchall case RFnCase            => Bool
      is catchall case (FnCase [] _ _)    =  False
      is catchall case (FnCase pats [] _) =  all catchall pats pats
      is catchall case (FnCase _ _ _)     =  False

fn :: filter specific cases [RFnCase] => [RFnCase]
      filter specific cases []        =  []
      filter specific cases (c:cs)
        | is catchall case c = filter specific cases cs
        | otherwise = [c] :: (filter specific cases cs)

fn :: filter catchall cases [RFnCase] => [RFnCase]
      filter catchall cases []        =  []
      filter catchall cases (c:cs)
        | is catchall case c = [c] :: (filter catchall cases cs)
        | otherwise = filter catchall cases cs

fn :: pat list adt ctor [RPattern] => String
      pat list adt ctor []         =  ""
      pat list adt ctor ((PatCtor ctor _):_) = ctor
      pat list adt ctor (_:ps)     =  pat list adt ctor ps

fn :: cases have adt ctor [RFnCase] String => Bool
      cases have adt ctor [] _ = False
      cases have adt ctor ((FnCase pats _ _):cs) target
        | (pat list adt ctor pats) == target = True
        | otherwise = cases have adt ctor cs target

fn :: filter new extension cases [RFnCase] [RFnCase] => [RFnCase]
      filter new extension cases _ [] = []
      filter new extension cases old_cs ((FnCase pats guards body):cs) =
        ctor = pat list adt ctor pats
        filter new extension step old_cs ctor (FnCase pats guards body) cs

fn :: filter new extension step [RFnCase] String RFnCase [RFnCase] => [RFnCase]
      filter new extension step old_cs ctor c cs
        | ctor != "" AND (NOT (cases have adt ctor old_cs ctor)) = [c] :: (filter new extension cases old_cs cs)
        | otherwise = filter new extension cases old_cs cs

fn :: merge fn cases [RFnCase] [RFnCase] => [RFnCase]
      merge fn cases old_cs    new_cs    =
        ext_cs = filter new extension cases old_cs new_cs
        (filter specific cases old_cs) :: (filter specific cases ext_cs) :: (filter catchall cases ext_cs) :: (filter catchall cases old_cs)

fn :: has variant ctor [RVariant] String => Bool
      has variant ctor []         _      =  False
      has variant ctor ((TypeVariant ctor _):vs) target
        | ctor == target = True
        | otherwise = has variant ctor vs target

fn :: filter new variants [RVariant] [RVariant] => [RVariant]
      filter new variants _          []         =  []
      filter new variants old_vs     ((TypeVariant ctor args):vs)
        | has variant ctor old_vs ctor = filter new variants old_vs vs
        | otherwise = [TypeVariant ctor args] :: (filter new variants old_vs vs)

fn :: has field name [RField] String => Bool
      has field name []       _      =  False
      has field name ((TypeField fname _):fs) target
        | fname == target = True
        | otherwise = has field name fs target

fn :: filter new fields [RField] [RField] => [RField]
      filter new fields _        []       =  []
      filter new fields old_fs   ((TypeField fname fty):fs)
        | has field name old_fs fname = filter new fields old_fs fs
        | otherwise = [TypeField fname fty] :: (filter new fields old_fs fs)

fn :: str list same [String] [String] => Bool
      str list same []       []       =  True
      str list same (a:as)   (b:bs)
        | a == b = str list same as bs
        | otherwise = False
      str list same _        _        =  False

fn :: has any fn case [RFnCase] => Bool
      has any fn case []        =  False
      has any fn case (_:_)     =  True

fn :: is adt ext fndef [String] String [RFnCase] [String] String [RFnCase] => Bool
      is adt ext fndef old_ps old_ret old_cs new_ps new_ret new_cs =
        (str list same old_ps new_ps) AND (old_ret == new_ret) AND (has any fn case (filter new extension cases old_cs new_cs))

fn :: has extensible fn def [RFnDef] RFnDef => Bool
      has extensible fn def [] _ = False
      has extensible fn def ((FnDef k old_ps old_ret old_cs):fs) (FnDef target new_ps new_ret new_cs)
        | k == target = is adt ext fndef old_ps old_ret old_cs new_ps new_ret new_cs
        | otherwise = has extensible fn def fs (FnDef target new_ps new_ret new_cs)

fn :: update fn def [RFnDef] RFnDef => [RFnDef]
      update fn def []       _      =  []
      update fn def ((FnDef k old_ps old_ret old_cs):fs) (FnDef target new_ps new_ret new_cs)
        | k == target = [FnDef k old_ps old_ret (merge fn cases old_cs new_cs)] :: (update fn def fs (FnDef target new_ps new_ret new_cs))
        | otherwise = [FnDef k old_ps old_ret old_cs] :: (update fn def fs (FnDef target new_ps new_ret new_cs))

fn :: cases have any adt ctor [RFnCase] => Bool
      cases have any adt ctor [] = False
      cases have any adt ctor ((FnCase pats _ _):cs)
        | (pat list adt ctor pats) != "" = True
        | otherwise = cases have any adt ctor cs

fn :: has fn def name [RFnDef] String => Bool
      has fn def name [] _ = False
      has fn def name ((FnDef k _ _ _):fs) target
        | k == target = True
        | otherwise = has fn def name fs target

fn :: merge fn def scoped [RFnDef] RFnDef Bool => [RFnDef]
      merge fn def scoped fns (FnDef name ps ret cs) in_lib
        | (cases have any adt ctor cs) AND (has extensible fn def fns (FnDef name ps ret cs)) = update fn def fns (FnDef name ps ret cs)
        | in_lib AND (name != "__unresolved_import__") AND (name != "__syntax_error__") AND (has fn def name fns name) = fns
        | otherwise = fns :: [FnDef name ps ret cs]

fn :: merge fn def [RFnDef] RFnDef => [RFnDef]
      merge fn def fns      fdef   =  merge fn def scoped fns fdef False

fn :: has type def [RTypeDef] String => Bool
      has type def []         _      =  False
      has type def ((TypeDef k _ _):ts) target
        | k == target = True
        | otherwise = has type def ts target

fn :: update type def [RTypeDef] RTypeDef => [RTypeDef]
      update type def []         _        =  []
      update type def ((TypeDef k old_vs old_fs):ts) (TypeDef target new_vs new_fs)
        | k == target = [TypeDef k (old_vs :: (filter new variants old_vs new_vs)) (old_fs :: (filter new fields old_fs new_fs))] :: (update type def ts (TypeDef target new_vs new_fs))
        | otherwise = [TypeDef k old_vs old_fs] :: (update type def ts (TypeDef target new_vs new_fs))

fn :: merge type def [RTypeDef] RTypeDef => [RTypeDef]
      merge type def tys        (TypeDef name vs fs)
        | has type def tys name = update type def tys (TypeDef name vs fs)
        | otherwise = tys :: [TypeDef name vs fs]

fn :: parse tokens [RToken] => RProgram
      parse tokens toks     =  normalize program (parse items toks [] [])

fn :: count fndef list [RFnDef] => Int
      count fndef list []       =  0
      count fndef list (_:xs)   =  1 + (count fndef list xs)

fn :: count fn defs RProgram        => Int
      count fn defs (Program fns _) =  count fndef list fns

fn :: count type defs RProgram        => Int
      count type defs (Program _ tys) =  count typedef list tys

fn :: count typedef list [RTypeDef] => Int
      count typedef list []         =  0
      count typedef list (_:xs)     =  1 + (count typedef list xs)
