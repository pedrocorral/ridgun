-- ============================================================
-- src/main/ridgun/typecheck.rg
-- Self-Hosted Ridgun v2.0 Type Checker
-- Validates:
-- - Function & Operator Signatures, Arities, and Return Types
-- - Sum ADTs, Product Record Constructors & Field Accessors
-- - Variadic Functions (T...) & Sequence Tuple Chaining
-- - Symbolic Tensor Shapes (Tensor(i, j)), Einsum Contractions,
--   and Compile-Time Call-Site Dimension Unification
-- - Integrates Static Analyzer Errors (Where Cycles, Parallel
--   Mutation Conflicts, Use-After-Channel-Send)
-- ============================================================
import ast
import lexer
import parser
import analyzer

-- ── String & Type Formatting Helpers ────────────────────────

fn :: trim_leading_spaces String Int Int => String
trim_leading_spaces s pos len
  | pos >= len = ""
  | (str_char_at s pos) == 32 = trim_leading_spaces s (pos + 1) len
  | otherwise = str_slice s pos len

fn :: trim_str String => String
trim_str s = trim_leading_spaces s 0 (str_len s)

fn :: split_by_comma_loop String Int Int Int [String] => [String]
split_by_comma_loop s start pos len acc
  | pos >= len = acc :: [trim_str (str_slice s start len)]
  | (str_char_at s pos) == 44 = split_by_comma_loop s (pos + 1) (pos + 1) len (acc :: [trim_str (str_slice s start pos)])
  | otherwise = split_by_comma_loop s start (pos + 1) len acc

fn :: split_comma_strs String => [String]
split_comma_strs "" = []
split_comma_strs s = split_by_comma_loop s 0 0 (str_len s) []

fn :: ends_with_ellipsis String => Bool
ends_with_ellipsis s =
  len = str_len s
  len > 3 AND (str_slice s (len - 3) len) == "..."

fn :: parse_type_list_strs [String] => [RType]
parse_type_list_strs [] = []
parse_type_list_strs (s:ss) = [parse_type_str s] :: (parse_type_list_strs ss)

fn :: is_int_type_name String => Bool
is_int_type_name s =
  s == "Int" OR s == "U8" OR s == "U16" OR s == "U32" OR s == "U64" OR s == "I8" OR s == "I16" OR s == "I32" OR s == "I64" OR s == "Usize"

fn :: parse_type_str String => RType
parse_type_str s
  | ends_with_ellipsis s = TyVariadic (parse_type_str (str_slice s 0 ((str_len s) - 3)))
  | is_int_type_name s = TyInt
  | s == "Real" = TyReal
  | s == "Char" = TyChar
  | s == "String" = TyString
  | s == "Bool" = TyBool
  | s == "Unit" OR s == "()" = TyUnit
  | s == "Tensor" OR s == "Tensor_GPU" = TyTensor []
  | str_starts_with s "Tensor(" = TyTensor (split_comma_strs (str_slice s 7 ((str_len s) - 1)))
  | str_starts_with s "[" = TyList (parse_type_str (str_slice s 1 ((str_len s) - 1)))
  | str_starts_with s "(" = TyTuple (parse_type_list_strs (split_comma_strs (str_slice s 1 ((str_len s) - 1))))
  | otherwise = TyVar s

fn :: rtype_to_str RType => String
rtype_to_str TyInt = "Int"
rtype_to_str TyReal = "Real"
rtype_to_str TyChar = "Char"
rtype_to_str TyString = "String"
rtype_to_str TyBool = "Bool"
rtype_to_str TyUnit = "()"
rtype_to_str (TyList inner) = "[" + (rtype_to_str inner) + "]"
rtype_to_str (TyTuple elems) = "(" + (rtype_list_to_str elems) + ")"
rtype_to_str (TyTensor []) = "Tensor"
rtype_to_str (TyTensor dims) = "Tensor(" + (join_comma_strs dims) + ")"
rtype_to_str (TyVariadic inner) = (rtype_to_str inner) + "..."
rtype_to_str (TyFun params ret) = "(" + (rtype_list_to_str params) + " => " + (rtype_to_str ret) + ")"
rtype_to_str (TyVar name) = name

fn :: rtype_list_to_str [RType] => String
rtype_list_to_str [] = ""
rtype_list_to_str (t:[]) = rtype_to_str t
rtype_list_to_str (t:ts) = (rtype_to_str t) + ", " + (rtype_list_to_str ts)

fn :: join_comma_strs [String] => String
join_comma_strs [] = ""
join_comma_strs (s:[]) = s
join_comma_strs (s:ss) = s + ", " + (join_comma_strs ss)

-- ── Type Unification & Compatibility ────────────────────────

fn :: rtype_list_len [RType] => Int
rtype_list_len [] = 0
rtype_list_len (_:xs) = 1 + (rtype_list_len xs)

fn :: dims_compatible [String] [String] => Bool
dims_compatible [] [] = True
dims_compatible (a:as) (b:bs)
  | a == b OR (is_lower_ident a) OR (is_lower_ident b) = dims_compatible as bs
  | otherwise = False
dims_compatible _ _ = False

fn :: tensor_dims_unify [String] [String] => Bool
tensor_dims_unify [] _ = True
tensor_dims_unify _ [] = True
tensor_dims_unify d1 d2
  | (str_list_count d1) == (str_list_count d2) = dims_compatible d1 d2
  | otherwise = False

fn :: types_list_compatible [RType] [RType] => Bool
types_list_compatible [] [] = True
types_list_compatible (a:as) (b:bs)
  | types_compatible a b = types_list_compatible as bs
  | otherwise = False
types_list_compatible _ _ = False

fn :: types_compatible RType RType => Bool
types_compatible TyInt TyInt = True
types_compatible TyReal TyReal = True
types_compatible TyChar TyChar = True
types_compatible TyChar TyString = True
types_compatible TyString TyChar = True
types_compatible TyString TyString = True
types_compatible TyBool TyBool = True
types_compatible TyUnit TyUnit = True
types_compatible (TyTensor d1) (TyTensor d2) = tensor_dims_unify d1 d2
types_compatible (TyVariadic inner) other =
  (types_compatible inner other) OR (types_compatible (TyList inner) other)
types_compatible other (TyVariadic inner) =
  (types_compatible inner other) OR (types_compatible (TyList inner) other)
types_compatible (TyVar _) _ = True
types_compatible _ (TyVar _) = True
types_compatible (TyList a) (TyList b) = types_compatible a b
types_compatible (TyTuple as) (TyTuple bs)
  | (rtype_list_len as) == (rtype_list_len bs) = types_list_compatible as bs
  | otherwise = False
types_compatible (TyFun p1 r1) (TyFun p2 r2)
  | (rtype_list_len p1) == (rtype_list_len p2) AND (types_list_compatible p1 p2) = types_compatible r1 r2
  | otherwise = False
types_compatible _ _ = False

-- ── Type Environment Lookup & Registration ──────────────────

fn :: lookup_type_bind [RTypeBind] String => (Bool, RType)
lookup_type_bind [] _ = (False, TyInt)
lookup_type_bind ((TypeBind k ty):rest) target
  | k == target = (True, ty)
  | otherwise = lookup_type_bind rest target

fn :: put_type_bind [RTypeBind] String RType => [RTypeBind]
put_type_bind env k ty = [TypeBind k ty] :: env

fn :: builtin_local_types => [RTypeBind]
builtin_local_types =
  [TypeBind "new_mailbox" TyInt, TypeBind "mailbox" TyInt, TypeBind "new_channel" TyInt, TypeBind "channel" TyInt, TypeBind "cli_args" (TyList TyString)]

fn :: builtin_fn_types => [RTypeBind]
builtin_fn_types =
  [TypeBind "spawn" (TyFun [TyString] TyInt), TypeBind "join" (TyFun [TyInt] TyInt), TypeBind "new_bounded_channel" (TyFun [TyInt] TyInt), TypeBind "send_through" (TyFun [TyVar "a", TyInt] TyUnit), TypeBind "chan_send" (TyFun [TyVar "a", TyInt] TyUnit), TypeBind "receive_from" (TyFun [TyInt] (TyVar "a")), TypeBind "chan_recv" (TyFun [TyInt] (TyVar "a")), TypeBind "try_receive_from" (TyFun [TyInt] (TyVar "Option")), TypeBind "chan_try_recv" (TyFun [TyInt] (TyVar "Option")), TypeBind "receive_from_timeout" (TyFun [TyInt, TyInt] (TyVar "Option")), TypeBind "str_len" (TyFun [TyString] TyInt), TypeBind "str_char_at" (TyFun [TyString, TyInt] TyInt), TypeBind "str_slice" (TyFun [TyString, TyInt, TyInt] TyString), TypeBind "char_from_code" (TyFun [TyInt] TyString), TypeBind "str_concat" (TyFun [TyString, TyString] TyString), TypeBind "int_to_str" (TyFun [TyInt] TyString), TypeBind "str_to_int" (TyFun [TyString] TyInt), TypeBind "str_starts_with" (TyFun [TyString, TyString] TyBool), TypeBind "str_contains" (TyFun [TyString, TyString] TyBool), TypeBind "read_file" (TyFun [TyString] TyString), TypeBind "write_file" (TyFun [TyString, TyString] TyUnit), TypeBind "shell_exec" (TyFun [TyString] TyInt)]

fn :: register_variants [RVariant] RType [RTypeBind] [RTypeBind] => ([RTypeBind], [RTypeBind])
register_variants [] _ locals fns = (locals, fns)
register_variants ((TypeVariant ctor []):vs) adt_ty locals fns =
  register_variants vs adt_ty (put_type_bind locals ctor adt_ty) fns
register_variants ((TypeVariant ctor arg_strs):vs) adt_ty locals fns =
  arg_tys = parse_type_list_strs arg_strs
  register_variants vs adt_ty locals (put_type_bind fns ctor (TyFun arg_tys adt_ty))

fn :: collect_field_types [RField] => [RType]
collect_field_types [] = []
collect_field_types ((TypeField _ fty_str):fs) =
  [parse_type_str fty_str] :: (collect_field_types fs)

fn :: register_field_accessors [RField] RType [RTypeBind] => [RTypeBind]
register_field_accessors [] _ fns = fns
register_field_accessors ((TypeField fname fty_str):fs) adt_ty fns =
  fty = parse_type_str fty_str
  register_field_accessors fs adt_ty (put_type_bind fns fname (TyFun [adt_ty] fty))

fn :: register_typedef RTypeDef [RTypeBind] [RTypeBind] => ([RTypeBind], [RTypeBind])
register_typedef (TypeDef name vars []) locals fns =
  adt_ty = parse_type_str name
  register_variants vars adt_ty locals fns
register_typedef (TypeDef name vars fields) locals fns =
  adt_ty = parse_type_str name
  v_res = register_variants vars adt_ty locals fns
  register_record_helpers name adt_ty fields v_res

fn :: register_record_helpers String RType [RField] ([RTypeBind], [RTypeBind]) => ([RTypeBind], [RTypeBind])
register_record_helpers name adt_ty fields (locals, fns) =
  ctor_arg_tys = collect_field_types fields
  fns1 = put_type_bind fns name (TyFun ctor_arg_tys adt_ty)
  fns2 = register_field_accessors fields adt_ty fns1
  (locals, fns2)

fn :: register_typedef_list [RTypeDef] [RTypeBind] [RTypeBind] => ([RTypeBind], [RTypeBind])
register_typedef_list [] locals fns = (locals, fns)
register_typedef_list (t:ts) locals fns =
  r1 = register_typedef t locals fns
  register_typedef_list_cont ts r1

fn :: register_typedef_list_cont [RTypeDef] ([RTypeBind], [RTypeBind]) => ([RTypeBind], [RTypeBind])
register_typedef_list_cont ts (locals1, fns1) =
  register_typedef_list ts locals1 fns1

fn :: register_fndef_sigs [RFnDef] [RTypeBind] => [RTypeBind]
register_fndef_sigs [] fns = fns
register_fndef_sigs ((FnDef name param_strs ret_str _):fs) fns =
  param_tys = parse_type_list_strs param_strs
  ret_ty = parse_type_str ret_str
  register_fndef_sigs fs (put_type_bind fns name (TyFun param_tys ret_ty))

-- ── Pattern Variable Binding ────────────────────────────────

fn :: rtype_at [RType] Int => RType
rtype_at (t:_) 0 = t
rtype_at (_:ts) idx = rtype_at ts (idx - 1)
rtype_at [] _ = TyInt

fn :: unwrap_variadic_param RType => RType
unwrap_variadic_param (TyVariadic inner) = TyList inner
unwrap_variadic_param other = other

fn :: has_seq_bind_pat [RPattern] => Bool
has_seq_bind_pat [] = False
has_seq_bind_pat ((PatSeqBind _):_) = True
has_seq_bind_pat (_:ps) = has_seq_bind_pat ps

fn :: ctor_param_types [RTypeBind] String => [RType]
ctor_param_types fns ctor_name =
  extract_fun_params (lookup_type_bind fns ctor_name)

fn :: extract_fun_params (Bool, RType) => [RType]
extract_fun_params (True, (TyFun params _)) = params
extract_fun_params _ = []

fn :: bind_pattern RPattern RType [RTypeBind] [RTypeBind] => [RTypeBind]
bind_pattern (PatVar v) expected locals _ =
  put_type_bind locals v expected
bind_pattern (PatSeqBind v) _ locals _ =
  put_type_bind locals v TyInt
bind_pattern (PatCons h t) (TyList elem_ty) locals fns =
  locals1 = bind_pattern h elem_ty locals fns
  bind_pattern t (TyList elem_ty) locals1 fns
bind_pattern (PatTuple pats) (TyTuple tys) locals fns =
  bind_tuple_pats pats tys 0 locals fns
bind_pattern (PatCtor ctor_name args) _ locals fns =
  param_tys = ctor_param_types fns ctor_name
  bind_tuple_pats args param_tys 0 locals fns
bind_pattern _ _ locals _ = locals

fn :: bind_tuple_pats [RPattern] [RType] Int [RTypeBind] [RTypeBind] => [RTypeBind]
bind_tuple_pats [] _ _ locals _ = locals
bind_tuple_pats (p:ps) tys idx locals fns =
  pty = rtype_at tys idx
  locals1 = bind_pattern p pty locals fns
  bind_tuple_pats ps tys (idx + 1) locals1 fns

fn :: bind_case_patterns [RPattern] [RType] Bool Int [RTypeBind] [RTypeBind] => [RTypeBind]
bind_case_patterns [] _ _ _ locals _ = locals
bind_case_patterns (p:ps) param_tys True idx locals fns =
  locals1 = bind_pattern p TyInt locals fns
  bind_case_patterns ps param_tys True (idx + 1) locals1 fns
bind_case_patterns (p:ps) param_tys False idx locals fns =
  expected = unwrap_variadic_param (rtype_at param_tys idx)
  locals1 = bind_pattern p expected locals fns
  bind_case_patterns ps param_tys False (idx + 1) locals1 fns

-- ── Symbolic Tensor Dimension Unification (Einsum & Calls) ──

fn :: lookup_dim_bind [RDimBind] String => (Bool, String)
lookup_dim_bind [] _ = (False, "")
lookup_dim_bind ((DimBind k v):rest) target
  | k == target = (True, v)
  | otherwise = lookup_dim_bind rest target

fn :: bind_or_check_dims [String] [String] String String [RDimBind] => ([RDimBind], [RTypeError])
bind_or_check_dims [] _ _ _ dim_env = (dim_env, [])
bind_or_check_dims _ [] _ _ dim_env = (dim_env, [])
bind_or_check_dims (ad:ads) (pd:pds) callee fn_name dim_env =
  step_res = check_single_dim ad pd callee fn_name (lookup_dim_bind dim_env pd) dim_env
  bind_or_check_dims_cont ads pds callee fn_name step_res

fn :: check_single_dim String String String String (Bool, String) [RDimBind] => ([RDimBind], [RTypeError])
check_single_dim ad pd callee fn_name (True, bound) dim_env
  | bound != ad = (dim_env, [TypeError fn_name ("tensor dimension mismatch in call to '" + callee + "': symbolic dim '" + pd + "' bound to both '" + bound + "' and '" + ad + "'")])
  | otherwise = (dim_env, [])
check_single_dim ad pd _ _ (False, _) dim_env =
  ([DimBind pd ad] :: dim_env, [])

fn :: bind_or_check_dims_cont [String] [String] String String ([RDimBind], [RTypeError]) => ([RDimBind], [RTypeError])
bind_or_check_dims_cont ads pds callee fn_name (dim_env1, errs1) =
  more = bind_or_check_dims ads pds callee fn_name dim_env1
  merge_dim_errs errs1 more

fn :: merge_dim_errs [RTypeError] ([RDimBind], [RTypeError]) => ([RDimBind], [RTypeError])
merge_dim_errs errs1 (dim_env2, errs2) = (dim_env2, errs1 :: errs2)

fn :: sub_chars_to_strs String Int Int => [String]
sub_chars_to_strs s pos len
  | pos >= len = []
  | otherwise = [str_slice s pos (pos + 1)] :: (sub_chars_to_strs s (pos + 1) len)

fn :: check_einsum_terms [RExpr] [String] String [RTypeBind] [RTypeBind] [RDimBind] => ([RDimBind], [RTypeError])
check_einsum_terms [] _ _ _ _ dim_env = (dim_env, [])
check_einsum_terms _ [] _ _ _ dim_env = (dim_env, [])
check_einsum_terms (e:es) (sub:subs) fn_name locals fns dim_env =
  e_res = check_expr e fn_name locals fns
  step = check_einsum_one e_res sub fn_name dim_env
  check_einsum_cont es subs fn_name locals fns step

fn :: check_einsum_one (RType, [RTypeError]) String String [RDimBind] => ([RDimBind], [RTypeError])
check_einsum_one ((TyTensor dims), errs1) sub fn_name dim_env
  | (str_list_count dims) > 0 AND (str_list_count dims) == (str_len sub) = merge_dim_errs errs1 (bind_or_check_dims dims (sub_chars_to_strs sub 0 (str_len sub)) "einsum" fn_name dim_env)
  | otherwise = (dim_env, errs1)
check_einsum_one (_, errs1) _ _ dim_env = (dim_env, errs1)

fn :: check_einsum_cont [RExpr] [String] String [RTypeBind] [RTypeBind] ([RDimBind], [RTypeError]) => ([RDimBind], [RTypeError])
check_einsum_cont es subs fn_name locals fns (dim_env1, errs1) =
  more = check_einsum_terms es subs fn_name locals fns dim_env1
  merge_dim_errs errs1 more

-- ── Binary Operator Type Checking ───────────────────────────

fn :: is_poly_tyvar RType => Bool
is_poly_tyvar (TyVar s) = is_lower_ident s
is_poly_tyvar _ = False

fn :: is_int_or_poly RType => Bool
is_int_or_poly TyInt = True
is_int_or_poly t = is_poly_tyvar t

fn :: is_real_or_poly RType => Bool
is_real_or_poly TyReal = True
is_real_or_poly t = is_poly_tyvar t

fn :: is_str_or_poly RType => Bool
is_str_or_poly TyString = True
is_str_or_poly t = is_poly_tyvar t

fn :: binop_symbol RBinOp => String
binop_symbol OpAdd = "+"
binop_symbol OpSub = "-"
binop_symbol OpMul = "*"
binop_symbol OpDiv = "/"
binop_symbol OpMod = "%"
binop_symbol _ = ""

fn :: check_overloaded_arith RBinOp RType RType [RTypeBind] String => (RType, [RTypeError])
check_overloaded_arith bop l_ty r_ty fns fn_name =
  sym = binop_symbol bop
  check_overload_lookup sym l_ty r_ty (lookup_type_bind fns sym) fn_name

fn :: check_overload_lookup String RType RType (Bool, RType) String => (RType, [RTypeError])
check_overload_lookup _ l_ty r_ty (True, (TyFun (p1:p2:[]) ret_ty)) _
  | (types_compatible l_ty p1) AND (types_compatible r_ty p2) = (ret_ty, [])
check_overload_lookup sym l_ty r_ty _ fn_name =
  (TyInt, [TypeError fn_name ("arithmetic operator " + sym + " requires numeric or overloaded operands, got " + (rtype_to_str l_ty) + " and " + (rtype_to_str r_ty))])

fn :: check_arith_binop RBinOp RType RType [RTypeBind] String => (RType, [RTypeError])
check_arith_binop _ (TyTensor d1) (TyTensor _) _ _ = (TyTensor d1, [])
check_arith_binop bop l_ty r_ty fns fn_name
  | (is_int_or_poly l_ty) AND (is_int_or_poly r_ty) = (TyInt, [])
  | (is_real_or_poly l_ty) AND (is_real_or_poly r_ty) = (TyReal, [])
  | bop == OpAdd AND (is_str_or_poly l_ty) AND (is_str_or_poly r_ty) = (TyString, [])
  | otherwise = check_overloaded_arith bop l_ty r_ty fns fn_name

fn :: check_matmul_binop RType RType String => (RType, [RTypeError])
check_matmul_binop (TyTensor (d1a:d1b:[])) (TyTensor (d2a:d2b:[])) fn_name
  | d1b != d2a = (TyTensor [d1a, d2b], [TypeError fn_name ("tensor contraction dimension mismatch: " + d1b + " vs " + d2a)])
  | otherwise = (TyTensor [d1a, d2b], [])
check_matmul_binop _ _ _ = (TyTensor [], [])

fn :: check_concat_binop RType RType String => (RType, [RTypeError])
check_concat_binop (TyList (TyVar "_empty")) (TyList r_elem) _ = (TyList r_elem, [])
check_concat_binop (TyList l_elem) (TyList (TyVar "_empty")) _ = (TyList l_elem, [])
check_concat_binop (TyList l_elem) (TyList r_elem) fn_name
  | types_compatible l_elem r_elem = (TyList l_elem, [])
  | otherwise = (TyList l_elem, [TypeError fn_name ("concatenation requires same list element types, got [" + (rtype_to_str l_elem) + "] and [" + (rtype_to_str r_elem) + "]")])
check_concat_binop l_ty r_ty fn_name =
  (TyList TyInt, [TypeError fn_name ("concatenation (::) requires list operands, got " + (rtype_to_str l_ty) + " and " + (rtype_to_str r_ty))])

fn :: check_binop RBinOp RType RType [RTypeBind] String => (RType, [RTypeError])
check_binop OpAdd l r fns fn_name = check_arith_binop OpAdd l r fns fn_name
check_binop OpSub l r fns fn_name = check_arith_binop OpSub l r fns fn_name
check_binop OpMul l r fns fn_name = check_arith_binop OpMul l r fns fn_name
check_binop OpDiv l r fns fn_name = check_arith_binop OpDiv l r fns fn_name
check_binop OpMod l r fns fn_name = check_arith_binop OpMod l r fns fn_name
check_binop OpMatMul l r _ fn_name = check_matmul_binop l r fn_name
check_binop OpFlatJoin _ _ _ _ = (TyVar "_seq", [])
check_binop OpConcat l r _ fn_name = check_concat_binop l r fn_name
check_binop OpEq l r _ fn_name
  | types_compatible l r = (TyBool, [])
  | otherwise = (TyBool, [TypeError fn_name ("equality comparison requires compatible types, got " + (rtype_to_str l) + " and " + (rtype_to_str r))])
check_binop OpNeq l r _ fn_name
  | types_compatible l r = (TyBool, [])
  | otherwise = (TyBool, [TypeError fn_name ("equality comparison requires compatible types, got " + (rtype_to_str l) + " and " + (rtype_to_str r))])
check_binop OpAnd l r _ fn_name
  | (types_compatible l TyBool) AND (types_compatible r TyBool) = (TyBool, [])
  | otherwise = (TyBool, [TypeError fn_name "logical operator requires Bool operands"])
check_binop OpOr l r _ fn_name
  | (types_compatible l TyBool) AND (types_compatible r TyBool) = (TyBool, [])
  | otherwise = (TyBool, [TypeError fn_name "logical operator requires Bool operands"])
check_binop OpXor l r _ fn_name
  | (types_compatible l TyBool) AND (types_compatible r TyBool) = (TyBool, [])
  | otherwise = (TyBool, [TypeError fn_name "logical operator requires Bool operands"])
check_binop _ l r _ fn_name
  | (types_compatible l TyInt AND types_compatible r TyInt) OR (types_compatible l TyReal AND types_compatible r TyReal) OR (types_compatible l TyChar AND types_compatible r TyChar) = (TyBool, [])
  | otherwise = (TyBool, [TypeError fn_name ("comparison operator requires numeric operands, got " + (rtype_to_str l) + " and " + (rtype_to_str r))])

-- ── Expression & Call Type Checking ─────────────────────────

fn :: count_char_in_str String Int Int Int => Int
count_char_in_str s pos len target_ch
  | pos >= len = 0
  | (str_char_at s pos) == target_ch = 1 + (count_char_in_str s (pos + 1) len target_ch)
  | otherwise = count_char_in_str s (pos + 1) len target_ch

fn :: seq_select_type String => RType
seq_select_type mask =
  plus_c = count_char_in_str mask 0 (str_len mask) 43
  space_c = count_char_in_str mask 0 (str_len mask) 32
  decide_seq_select_type plus_c space_c

fn :: decide_seq_select_type Int Int => RType
decide_seq_select_type plus_c space_c
  | plus_c > 1 = TyVar "_seq"
  | plus_c == 0 AND space_c >= 1 = TyVar "_seq"
  | otherwise = TyInt

fn :: lookup_var_type String String [RTypeBind] [RTypeBind] => (RType, [RTypeError])
lookup_var_type name fn_name locals fns =
  loc_res = lookup_type_bind locals name
  lookup_var_step1 name fn_name loc_res locals fns

fn :: lookup_var_step1 String String (Bool, RType) [RTypeBind] [RTypeBind] => (RType, [RTypeError])
lookup_var_step1 _ _ (True, ty) _ _ = (ty, [])
lookup_var_step1 name fn_name (False, _) locals fns =
  fn_res = lookup_type_bind fns name
  lookup_var_step2 name fn_name fn_res locals

fn :: lookup_var_step2 String String (Bool, RType) [RTypeBind] => (RType, [RTypeError])
lookup_var_step2 _ _ (True, (TyFun [] ret_ty)) _ = (ret_ty, [])
lookup_var_step2 _ _ (True, other_ty) _ = (other_ty, [])
lookup_var_step2 name fn_name (False, _) locals
  | is_subscript_ident name = lookup_subscript_base (split_subscript name) locals
  | otherwise = (TyInt, [TypeError fn_name ("undefined variable '" + name + "'")])

fn :: lookup_subscript_base (String, String) [RTypeBind] => (RType, [RTypeError])
lookup_subscript_base (base, _) locals =
  extract_subscript_ty (lookup_type_bind locals base)

fn :: extract_subscript_ty (Bool, RType) => (RType, [RTypeError])
extract_subscript_ty (True, ty) = (ty, [])
extract_subscript_ty (False, _) = (TyTensor [], [])

fn :: is_last_variadic [RType] => Bool
is_last_variadic [] = False
is_last_variadic ((TyVariadic _):[]) = True
is_last_variadic (_:ts) = is_last_variadic ts

fn :: last_variadic_inner [RType] => RType
last_variadic_inner ((TyVariadic inner):[]) = inner
last_variadic_inner (_:ts) = last_variadic_inner ts
last_variadic_inner [] = TyInt

fn :: check_fixed_args [RType] [RType] String String Int [RDimBind] => [RTypeError]
check_fixed_args [] _ _ _ _ _ = []
check_fixed_args _ [] _ _ _ _ = []
check_fixed_args (arg:args) (param:params) callee fn_name idx dim_env
  | NOT (types_compatible arg param) = [TypeError fn_name ("function '" + callee + "' arg #" + (int_to_str idx) + " has type " + (rtype_to_str arg) + ", expected " + (rtype_to_str param))] :: (check_fixed_args args params callee fn_name (idx + 1) dim_env)
  | otherwise = check_arg_tensor_dims arg param args params callee fn_name idx dim_env

fn :: check_arg_tensor_dims RType RType [RType] [RType] String String Int [RDimBind] => [RTypeError]
check_arg_tensor_dims (TyTensor adims) (TyTensor pdims) args params callee fn_name idx dim_env
  | (str_list_count adims) > 0 AND (str_list_count adims) == (str_list_count pdims) = check_arg_tensor_dims_step (bind_or_check_dims adims pdims callee fn_name dim_env) args params callee fn_name idx
check_arg_tensor_dims _ _ args params callee fn_name idx dim_env =
  check_fixed_args args params callee fn_name (idx + 1) dim_env

fn :: check_arg_tensor_dims_step ([RDimBind], [RTypeError]) [RType] [RType] String String Int => [RTypeError]
check_arg_tensor_dims_step (dim_env1, dim_errs) args params callee fn_name idx =
  dim_errs :: (check_fixed_args args params callee fn_name (idx + 1) dim_env1)

fn :: check_variadic_args [RType] RType String String Int => [RTypeError]
check_variadic_args [] _ _ _ _ = []
check_variadic_args (arg:args) var_ty callee fn_name idx
  | (types_compatible arg var_ty) OR (types_compatible arg (TyList var_ty)) = check_variadic_args args var_ty callee fn_name (idx + 1)
  | otherwise = [TypeError fn_name ("function '" + callee + "' variadic arg #" + (int_to_str idx) + " has type " + (rtype_to_str arg) + ", expected " + (rtype_to_str var_ty))] :: (check_variadic_args args var_ty callee fn_name (idx + 1))

fn :: take_rtypes [RType] Int => [RType]
take_rtypes _ 0 = []
take_rtypes [] _ = []
take_rtypes (x:xs) n = [x] :: (take_rtypes xs (n - 1))

fn :: drop_rtypes [RType] Int => [RType]
drop_rtypes xs 0 = xs
drop_rtypes [] _ = []
drop_rtypes (_:xs) n = drop_rtypes xs (n - 1)

fn :: check_call_sig String [RType] [RType] RType String => (RType, [RTypeError])
check_call_sig callee arg_tys param_tys ret_ty fn_name
  | is_last_variadic param_tys = check_variadic_call callee arg_tys param_tys ret_ty fn_name
  | (rtype_list_len arg_tys) == 1 AND (rtype_list_len param_tys) > 1 = check_tuple_chain_call callee (rtype_at arg_tys 0) arg_tys param_tys ret_ty fn_name
  | (rtype_list_len arg_tys) != (rtype_list_len param_tys) = (ret_ty, [TypeError fn_name ("function '" + callee + "' called with " + (int_to_str (rtype_list_len arg_tys)) + " argument(s), expected " + (int_to_str (rtype_list_len param_tys)))])
  | otherwise = (ret_ty, check_fixed_args arg_tys param_tys callee fn_name 0 [])

fn :: check_variadic_call String [RType] [RType] RType String => (RType, [RTypeError])
check_variadic_call callee arg_tys param_tys ret_ty fn_name =
  fixed = (rtype_list_len param_tys) - 1
  var_ty = last_variadic_inner param_tys
  check_variadic_call_counts callee arg_tys param_tys ret_ty fn_name fixed var_ty

fn :: check_variadic_call_counts String [RType] [RType] RType String Int RType => (RType, [RTypeError])
check_variadic_call_counts callee arg_tys param_tys ret_ty fn_name fixed var_ty
  | (rtype_list_len arg_tys) < fixed = (ret_ty, [TypeError fn_name ("function '" + callee + "' called with " + (int_to_str (rtype_list_len arg_tys)) + " argument(s), expected at least " + (int_to_str fixed))])
  | otherwise = (ret_ty, (check_fixed_args (take_rtypes arg_tys fixed) (take_rtypes param_tys fixed) callee fn_name 0 []) :: (check_variadic_args (drop_rtypes arg_tys fixed) var_ty callee fn_name fixed))

fn :: check_tuple_chain_call String RType [RType] [RType] RType String => (RType, [RTypeError])
check_tuple_chain_call callee (TyTuple elems) _ param_tys ret_ty fn_name
  | (rtype_list_len elems) == (rtype_list_len param_tys) = (ret_ty, check_fixed_args elems param_tys callee fn_name 0 [])
check_tuple_chain_call _ (TyVar "_seq") _ _ ret_ty _ = (ret_ty, [])
check_tuple_chain_call callee _ arg_tys param_tys ret_ty fn_name =
  (ret_ty, [TypeError fn_name ("function '" + callee + "' called with " + (int_to_str (rtype_list_len arg_tys)) + " argument(s), expected " + (int_to_str (rtype_list_len param_tys)))])

fn :: check_call_target String [RType] [RTypeError] (Bool, RType) String => (RType, [RTypeError])
check_call_target callee arg_tys arg_errs (True, (TyFun param_tys ret_ty)) fn_name =
  sig_res = check_call_sig callee arg_tys param_tys ret_ty fn_name
  prepend_type_errs arg_errs sig_res
check_call_target callee _ arg_errs (True, _) fn_name =
  (TyInt, arg_errs :: [TypeError fn_name ("'" + callee + "' is not a function")])
check_call_target callee _ arg_errs (False, _) fn_name =
  (TyInt, arg_errs :: [TypeError fn_name ("undefined function '" + callee + "'")])

fn :: prepend_type_errs [RTypeError] (RType, [RTypeError]) => (RType, [RTypeError])
prepend_type_errs errs1 (ty, errs2) = (ty, errs1 :: errs2)

fn :: check_expr_list [RExpr] String [RTypeBind] [RTypeBind] => ([RType], [RTypeError])
check_expr_list [] _ _ _ = ([], [])
check_expr_list (e:es) fn_name locals fns =
  r1 = check_expr e fn_name locals fns
  check_expr_list_cont es fn_name locals fns r1

fn :: check_expr_list_cont [RExpr] String [RTypeBind] [RTypeBind] (RType, [RTypeError]) => ([RType], [RTypeError])
check_expr_list_cont es fn_name locals fns (ty1, errs1) =
  r2 = check_expr_list es fn_name locals fns
  merge_ty_list ty1 errs1 r2

fn :: merge_ty_list RType [RTypeError] ([RType], [RTypeError]) => ([RType], [RTypeError])
merge_ty_list ty1 errs1 (tys, errs2) = ([ty1] :: tys, errs1 :: errs2)

fn :: check_list_elems_uniform RType [RType] String => [RTypeError]
check_list_elems_uniform _ [] _ = []
check_list_elems_uniform first_ty (t:ts) fn_name
  | types_compatible t first_ty = check_list_elems_uniform first_ty ts fn_name
  | otherwise = [TypeError fn_name ("list elements have mixed types: " + (rtype_to_str first_ty) + " and " + (rtype_to_str t))] :: (check_list_elems_uniform first_ty ts fn_name)

fn :: finish_list_type ([RType], [RTypeError]) String => (RType, [RTypeError])
finish_list_type ([], errs) _ = (TyList (TyVar "_empty"), errs)
finish_list_type ((first_ty:rest_tys), errs) fn_name =
  elem_errs = check_list_elems_uniform first_ty rest_tys fn_name
  (TyList first_ty, errs :: elem_errs)

fn :: finish_tuple_type ([RType], [RTypeError]) => (RType, [RTypeError])
finish_tuple_type (tys, errs) = (TyTuple tys, errs)

fn :: check_expr RExpr String [RTypeBind] [RTypeBind] => (RType, [RTypeError])
check_expr (EInt _) _ _ _ = (TyInt, [])
check_expr (EReal _) _ _ _ = (TyReal, [])
check_expr (EStr _) _ _ _ = (TyString, [])
check_expr (EStrInterp parts) fn_name locals fns =
  p_res = check_expr_list parts fn_name locals fns
  discard_tys_return TyString p_res
check_expr (EBool _) _ _ _ = (TyBool, [])
check_expr EUnit _ _ _ = (TyUnit, [])
check_expr (ENot inner) fn_name locals fns =
  check_not_inner (check_expr inner fn_name locals fns) fn_name
check_expr (EOut inner) fn_name locals fns =
  r1 = check_expr inner fn_name locals fns
  prepend_type_errs (snd_errs r1) (TyVar "_out", [])
check_expr (EWithCtx ctx_name val_e body) fn_name locals fns =
  v_res = check_expr val_e fn_name locals fns
  check_with_ctx_body ctx_name body fn_name locals fns v_res
check_expr (EWithRegion _ body) fn_name locals fns =
  b_res = check_expr body fn_name locals fns
  prepend_type_errs (snd_errs b_res) (TyVar "Result", [])
check_expr (EAtomicUpdate _ val_e) fn_name locals fns =
  v_res = check_expr val_e fn_name locals fns
  prepend_type_errs (snd_errs v_res) (TyUnit, [])
check_expr (ELoadContext _ def_e) fn_name locals fns =
  check_expr def_e fn_name locals fns
check_expr (ELoadShared _ def_e) fn_name locals fns =
  check_expr def_e fn_name locals fns
check_expr (EEinsum es subs) fn_name locals fns =
  e_res = check_einsum_terms es subs fn_name locals fns []
  finish_einsum_check e_res
check_expr (EHadamard _ l _ r _) fn_name locals fns =
  l_res = check_expr l fn_name locals fns
  r_res = check_expr r fn_name locals fns
  finish_hadamard_check l_res r_res
check_expr (EVar name) fn_name locals fns =
  lookup_var_type name fn_name locals fns
check_expr (EBin bop l r) fn_name locals fns =
  l_res = check_expr l fn_name locals fns
  r_res = check_expr r fn_name locals fns
  finish_binop_check bop l_res r_res fns fn_name
check_expr (ECall callee args) fn_name locals fns =
  args_res = check_expr_list args fn_name locals fns
  finish_call_check callee args_res fn_name fns
check_expr (EEcho args) fn_name locals fns =
  args_res = check_expr_list args fn_name locals fns
  discard_tys_return TyUnit args_res
check_expr (EList []) _ _ _ = (TyList (TyVar "_empty"), [])
check_expr (EList elems) fn_name locals fns =
  finish_list_type (check_expr_list elems fn_name locals fns) fn_name
check_expr (ETuple elems) fn_name locals fns =
  finish_tuple_type (check_expr_list elems fn_name locals fns)
check_expr (ETensor elems) fn_name locals fns =
  args_res = check_expr_list elems fn_name locals fns
  discard_tys_return (TyTensor []) args_res
check_expr (EIndex base idxs) fn_name locals fns =
  b_res = check_expr base fn_name locals fns
  i_res = check_expr_list idxs fn_name locals fns
  (TyInt, (snd_errs b_res) :: (snd_list_errs i_res))
check_expr (EIndexAssign _ idxs val_e) fn_name locals fns =
  i_res = check_expr_list idxs fn_name locals fns
  v_res = check_expr val_e fn_name locals fns
  (TyUnit, (snd_list_errs i_res) :: (snd_errs v_res))
check_expr (ESeqSelect base mask) fn_name locals fns =
  b_res = check_expr base fn_name locals fns
  (seq_select_type mask, snd_errs b_res)
check_expr (EWhere body binds) fn_name locals fns =
  check_where_expr body binds fn_name locals fns
check_expr (EParPipe branches) fn_name locals fns =
  finish_tuple_type (check_expr_list branches fn_name locals fns)
check_expr (EBlock stmts) fn_name locals fns =
  check_block_stmts stmts TyUnit fn_name locals fns

fn :: snd_errs (RType, [RTypeError]) => [RTypeError]
snd_errs (_, errs) = errs

fn :: snd_list_errs ([RType], [RTypeError]) => [RTypeError]
snd_list_errs (_, errs) = errs

fn :: discard_tys_return RType ([RType], [RTypeError]) => (RType, [RTypeError])
discard_tys_return ret_ty (_, errs) = (ret_ty, errs)

fn :: check_not_inner (RType, [RTypeError]) String => (RType, [RTypeError])
check_not_inner (inner_ty, errs) fn_name
  | types_compatible inner_ty TyBool = (TyBool, errs)
  | otherwise = (TyBool, errs :: [TypeError fn_name ("NOT requires Bool operand, got " + (rtype_to_str inner_ty))])

fn :: check_with_ctx_body String RExpr String [RTypeBind] [RTypeBind] (RType, [RTypeError]) => (RType, [RTypeError])
check_with_ctx_body ctx_name body fn_name locals fns (val_ty, v_errs) =
  locals1 = put_type_bind locals ctx_name val_ty
  b_res = check_expr body fn_name locals1 fns
  prepend_type_errs v_errs b_res

fn :: finish_einsum_check ([RDimBind], [RTypeError]) => (RType, [RTypeError])
finish_einsum_check (_, errs) = (TyTensor [], errs)

fn :: finish_hadamard_check (RType, [RTypeError]) (RType, [RTypeError]) => (RType, [RTypeError])
finish_hadamard_check ((TyTensor dims), l_errs) (_, r_errs) = (TyTensor dims, l_errs :: r_errs)
finish_hadamard_check (_, l_errs) (_, r_errs) = (TyTensor [], l_errs :: r_errs)

fn :: finish_binop_check RBinOp (RType, [RTypeError]) (RType, [RTypeError]) [RTypeBind] String => (RType, [RTypeError])
finish_binop_check bop (l_ty, l_errs) (r_ty, r_errs) fns fn_name =
  b_res = check_binop bop l_ty r_ty fns fn_name
  prepend_type_errs (l_errs :: r_errs) b_res

fn :: finish_call_check String ([RType], [RTypeError]) String [RTypeBind] => (RType, [RTypeError])
finish_call_check "spawn" (_, arg_errs) _ _ = (TyInt, arg_errs)
finish_call_check callee (arg_tys, arg_errs) fn_name fns =
  check_call_target callee arg_tys arg_errs (lookup_type_bind fns callee) fn_name

fn :: check_where_binds [RWhereBind] String [RTypeBind] [RTypeBind] => ([RTypeBind], [RTypeError])
check_where_binds [] _ locals _ = (locals, [])
check_where_binds ((WhereBind e target idxs):wbs) fn_name locals fns =
  e_res = check_expr e fn_name locals fns
  check_where_binds_step target idxs wbs fn_name locals fns e_res

fn :: check_where_binds_step String [Int] [RWhereBind] String [RTypeBind] [RTypeBind] (RType, [RTypeError]) => ([RTypeBind], [RTypeError])
check_where_binds_step target [] wbs fn_name locals fns (bty, errs1) =
  locals1 = put_type_bind locals target bty
  more = check_where_binds wbs fn_name locals1 fns
  merge_env_errs errs1 more
check_where_binds_step _ _ wbs fn_name locals fns (_, errs1) =
  more = check_where_binds wbs fn_name locals fns
  merge_env_errs errs1 more

fn :: merge_env_errs [RTypeError] ([RTypeBind], [RTypeError]) => ([RTypeBind], [RTypeError])
merge_env_errs errs1 (env2, errs2) = (env2, errs1 :: errs2)

fn :: check_where_expr RExpr [RWhereBind] String [RTypeBind] [RTypeBind] => (RType, [RTypeError])
check_where_expr body binds fn_name locals fns =
  w_res = check_where_binds binds fn_name locals fns
  check_where_body body fn_name fns w_res

fn :: check_where_body RExpr String [RTypeBind] ([RTypeBind], [RTypeError]) => (RType, [RTypeError])
check_where_body body fn_name fns (locals1, w_errs) =
  b_res = check_expr body fn_name locals1 fns
  prepend_type_errs w_errs b_res

fn :: bind_let_var String RType [RTypeBind] => [RTypeBind]
bind_let_var name ty locals
  | is_subscript_ident name = bind_subscript_let (split_subscript name) name ty locals
  | otherwise = put_type_bind locals name ty

fn :: bind_subscript_let (String, String) String RType [RTypeBind] => [RTypeBind]
bind_subscript_let (base, _) name ty locals =
  put_type_bind (put_type_bind locals base ty) name ty

fn :: check_block_stmts [RStmt] RType String [RTypeBind] [RTypeBind] => (RType, [RTypeError])
check_block_stmts [] last_ty _ _ _ = (last_ty, [])
check_block_stmts ((StmtLet name val_e):ss) _ fn_name locals fns =
  v_res = check_expr val_e fn_name locals fns
  check_block_after_let name ss fn_name locals fns v_res
check_block_stmts ((StmtExpr e):ss) _ fn_name locals fns =
  e_res = check_expr e fn_name locals fns
  check_block_after_expr ss fn_name locals fns e_res
check_block_stmts ((StmtAtomic _ val_e):ss) _ fn_name locals fns =
  v_res = check_expr val_e fn_name locals fns
  check_block_after_expr ss fn_name locals fns (TyUnit, snd_errs v_res)
check_block_stmts ((StmtIndexAssign _ idxs val_e):ss) _ fn_name locals fns =
  i_res = check_expr_list idxs fn_name locals fns
  v_res = check_expr val_e fn_name locals fns
  check_block_after_expr ss fn_name locals fns (TyUnit, (snd_list_errs i_res) :: (snd_errs v_res))

fn :: check_block_after_let String [RStmt] String [RTypeBind] [RTypeBind] (RType, [RTypeError]) => (RType, [RTypeError])
check_block_after_let name ss fn_name locals fns (v_ty, v_errs) =
  locals1 = bind_let_var name v_ty locals
  more = check_block_stmts ss v_ty fn_name locals1 fns
  prepend_type_errs v_errs more

fn :: check_block_after_expr [RStmt] String [RTypeBind] [RTypeBind] (RType, [RTypeError]) => (RType, [RTypeError])
check_block_after_expr ss fn_name locals fns (e_ty, e_errs) =
  more = check_block_stmts ss e_ty fn_name locals fns
  prepend_type_errs e_errs more

-- ── Function & Case Type Checking ───────────────────────────

fn :: is_empty_list_return_compat RType RType => Bool
is_empty_list_return_compat (TyList (TyVar "_empty")) (TyList _) = True
is_empty_list_return_compat _ _ = False

fn :: check_case_guards [RGuard] String RType Int [RTypeBind] [RTypeBind] => [RTypeError]
check_case_guards [] _ _ _ _ _ = []
check_case_guards ((GuardBranch cond body):gs) fn_name ret_ty idx locals fns =
  c_res = check_expr cond fn_name locals fns
  b_res = check_expr body fn_name locals fns
  (check_guard_pair c_res b_res fn_name ret_ty idx) :: (check_case_guards gs fn_name ret_ty (idx + 1) locals fns)

fn :: check_guard_pair (RType, [RTypeError]) (RType, [RTypeError]) String RType Int => [RTypeError]
check_guard_pair (c_ty, c_errs) (b_ty, b_errs) fn_name ret_ty idx =
  c_chk = check_guard_cond_ty c_ty fn_name idx
  b_chk = check_guard_body_ty b_ty ret_ty fn_name idx
  c_errs :: c_chk :: b_errs :: b_chk

fn :: check_guard_cond_ty RType String Int => [RTypeError]
check_guard_cond_ty TyBool _ _ = []
check_guard_cond_ty c_ty fn_name idx =
  [TypeError fn_name ("guard #" + (int_to_str idx) + " condition has type " + (rtype_to_str c_ty) + ", expected Bool")]

fn :: check_guard_body_ty RType RType String Int => [RTypeError]
check_guard_body_ty b_ty ret_ty fn_name idx
  | (types_compatible b_ty ret_ty) OR (is_empty_list_return_compat b_ty ret_ty) = []
  | otherwise = [TypeError fn_name ("guard #" + (int_to_str idx) + " body has type " + (rtype_to_str b_ty) + ", expected " + (rtype_to_str ret_ty))]

fn :: check_case_body_ty (RType, [RTypeError]) RType String => [RTypeError]
check_case_body_ty (b_ty, b_errs) ret_ty fn_name
  | (types_compatible b_ty ret_ty) OR (is_empty_list_return_compat b_ty ret_ty) = b_errs
  | otherwise = b_errs :: [TypeError fn_name ("body has type " + (rtype_to_str b_ty) + ", expected " + (rtype_to_str ret_ty))]

fn :: pat_count [RPattern] => Int
pat_count [] = 0
pat_count (_:xs) = 1 + (pat_count xs)

fn :: check_one_case RFnCase String [RType] RType Int [RTypeBind] [RTypeBind] => [RTypeError]
check_one_case (FnCase pats guards body) fn_name param_tys ret_ty case_idx locals fns
  | (pat_count pats) != (rtype_list_len param_tys) AND (NOT (has_seq_bind_pat pats)) = [TypeError fn_name ("case #" + (int_to_str case_idx) + " has " + (int_to_str (pat_count pats)) + " pattern(s), expected " + (int_to_str (rtype_list_len param_tys)))]
  | otherwise = check_case_guards_or_body guards body fn_name ret_ty (bind_case_patterns pats param_tys (has_seq_bind_pat pats) 0 locals fns) fns

fn :: check_case_guards_or_body [RGuard] RExpr String RType [RTypeBind] [RTypeBind] => [RTypeError]
check_case_guards_or_body [] body fn_name ret_ty locals fns =
  check_case_body_ty (check_expr body fn_name locals fns) ret_ty fn_name
check_case_guards_or_body guards _ fn_name ret_ty locals fns =
  check_case_guards guards fn_name ret_ty 0 locals fns

fn :: check_fn_cases [RFnCase] String [RType] RType Int [RTypeBind] [RTypeBind] => [RTypeError]
check_fn_cases [] _ _ _ _ _ _ = []
check_fn_cases (c:cs) fn_name param_tys ret_ty idx locals fns =
  (check_one_case c fn_name param_tys ret_ty idx locals fns) :: (check_fn_cases cs fn_name param_tys ret_ty (idx + 1) locals fns)

fn :: check_all_functions [RFnDef] [RTypeBind] [RTypeBind] => [RTypeError]
check_all_functions [] _ _ = []
check_all_functions ((FnDef name param_strs ret_str cases):fs) locals fns =
  param_tys = parse_type_list_strs param_strs
  ret_ty = parse_type_str ret_str
  (check_fn_cases cases name param_tys ret_ty 0 locals fns) :: (check_all_functions fs locals fns)

fn :: convert_analysis_errors [RAnalysisError] => [RTypeError]
convert_analysis_errors [] = []
convert_analysis_errors ((ErrWhereCycle fn_name var):es) =
  [TypeError fn_name ("CyclicWhereDependencyError on '" + var + "'")] :: (convert_analysis_errors es)
convert_analysis_errors ((ErrParallelMutation fn_name var):es) =
  [TypeError fn_name ("ParallelMutationConflictError on '" + var + "'")] :: (convert_analysis_errors es)
convert_analysis_errors ((ErrUseAfterSend fn_name var):es) =
  [TypeError fn_name ("UseAfterChannelSendError on '" + var + "'")] :: (convert_analysis_errors es)

fn :: typecheck_program RProgram => [RTypeError]
typecheck_program (Program fdefs tdefs) =
  env_pair = register_typedef_list tdefs builtin_local_types builtin_fn_types
  typecheck_with_typedef_env (Program fdefs tdefs) fdefs env_pair

fn :: typecheck_with_typedef_env RProgram [RFnDef] ([RTypeBind], [RTypeBind]) => [RTypeError]
typecheck_with_typedef_env prog fdefs (locals, fns0) =
  fns = register_fndef_sigs fdefs fns0
  ty_errs = check_all_functions fdefs locals fns
  an_errs = convert_analysis_errors (analyze_program_errors prog)
  ty_errs :: an_errs

fn :: type_err_count [RTypeError] => Int
type_err_count [] = 0
type_err_count (_:xs) = 1 + (type_err_count xs)

fn :: format_type_errors [RTypeError] => [String]
format_type_errors [] = []
format_type_errors ((TypeError fn_name msg):es) =
  ["type error in function '" + fn_name + "': " + msg] :: (format_type_errors es)
