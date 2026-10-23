-- ============================================================
-- src/main/ridgun/typecheck.rg
-- Self-Hosted Ridgun v0.9.0 Type Checker
-- Validates:
-- - Function & Operator Signatures, Arities, and Return Types
-- - Sum ADTs, Product Record Constructors & Field Accessors
-- - Variadic Functions (T...) & Sequence Tuple Chaining
-- - Symbolic Tensor Shapes (Tensor(i, j)), Einsum Contractions,
--   and Compile-Time Call-Site Dimension Unification
-- - Integrates Static Analyzer Errors (Where Cycles, Parallel
--   Mutation Conflicts, Use-After-Channel-Send)
-- @implements FR-COMP-001
-- @implements FR-COMP-005
-- @implements FR-COMP-007
-- @implements FR-COMP-008
-- @implements FR-COMP-009
-- @implements FR-VM-001
-- @implements FR-VM-002
-- ============================================================
import ast
import lexer
import parser
import analyzer

-- ── String & Type Formatting Helpers ────────────────────────

fn :: trim_leading_spaces String Int Int => String
      trim_leading_spaces s      pos len
        | pos >= len = ""
        | (str_char_at s pos) == 32 = trim_leading_spaces s (pos + 1) len
        | otherwise = str_slice s pos len

fn :: trim_str String => String
      trim_str s      =  trim_leading_spaces s 0 (str_len s)

fn :: split_by_comma_loop String Int Int Int Int [String] => [String]
      split_by_comma_loop s start pos len depth acc
        | pos >= len = acc :: [trim_str (str_slice s start len)]
        | (str_char_at s pos) == 40 OR (str_char_at s pos) == 91 = split_by_comma_loop s start (pos + 1) len (depth + 1) acc
        | (str_char_at s pos) == 41 OR (str_char_at s pos) == 93 = split_by_comma_loop s start (pos + 1) len (depth - 1) acc
        | depth == 0 AND (str_char_at s pos) == 44 = split_by_comma_loop s (pos + 1) (pos + 1) len 0 (acc :: [trim_str (str_slice s start pos)])
        | otherwise = split_by_comma_loop s start (pos + 1) len depth acc

fn :: split_comma_strs String => [String]
      split_comma_strs ""     =  []
      split_comma_strs s      =  split_by_comma_loop s 0 0 (str_len s) 0 []

fn :: ends_with_ellipsis String => Bool
      ends_with_ellipsis s      =
        len = str_len s
        len > 3 AND (str_slice s (len - 3) len) == "..."

fn :: parse_type_list_strs [String] => [RType]
      parse_type_list_strs []       =  []
      parse_type_list_strs (s:ss)   =  [parse_type_str s] :: (parse_type_list_strs ss)

fn :: is_int_type_name String => Bool
      is_int_type_name s      =
        s == "Int" OR s == "U8" OR s == "U16" OR s == "U32" OR s == "U64" OR s == "I8" OR s == "I16" OR s == "I32" OR s == "I64" OR s == "Usize"

fn :: find_fat_arrow_idx String Int Int => Int
      find_fat_arrow_idx s      pos len
        | (pos + 4) > len = -1
        | (str_slice s pos (pos + 4)) == " => " = pos
        | otherwise = find_fat_arrow_idx s (pos + 1) len

fn :: parse_paren_type_inner String => RType
      parse_paren_type_inner inner  =
        arrow_idx = find_fat_arrow_idx inner 0 (str_len inner)
        parse_paren_type_split inner arrow_idx

fn :: finish_paren_tuple_type [String]    => RType
      finish_paren_tuple_type (single:[]) =  parse_type_str single
      finish_paren_tuple_type parts       =  TyTuple (parse_type_list_strs parts)

fn :: parse_paren_type_split String Int => RType
      parse_paren_type_split inner  -1  =  finish_paren_tuple_type (split_comma_strs inner)
      parse_paren_type_split inner  idx =
        lhs_s = str_slice inner 0 idx
        rhs_s = str_slice inner (idx + 4) (str_len inner)
        TyFun (parse_type_list_strs (split_comma_strs lhs_s)) (parse_type_str rhs_s)

fn :: parse_type_str String => RType
      parse_type_str s
        | ends_with_ellipsis s = TyVariadic (parse_type_str (str_slice s 0 ((str_len s) - 3)))
        | is_int_type_name s = TyInt
        | s == "Real" OR s == "Float" = TyReal
        | s == "Char" = TyChar
        | s == "String" = TyString
        | s == "Bool" = TyBool
        | s == "Unit" OR s == "()" = TyUnit
        | s == "Actor" = TyVar "Agent"
        | s == "Tensor" OR s == "Tensor_GPU" = TyTensor []
        | str_starts_with s "Tensor(" = TyTensor (split_comma_strs (str_slice s 7 ((str_len s) - 1)))
        | str_starts_with s "[" = TyList (parse_type_str (str_slice s 1 ((str_len s) - 1)))
        | str_starts_with s "(" = parse_paren_type_inner (str_slice s 1 ((str_len s) - 1))
        | otherwise = TyVar s

fn :: strip_pipe_suffix String Int Int => String
      strip_pipe_suffix s      pos len
        | pos >= len = s
        | (str_char_at s pos) == 124 = str_slice s 0 pos
        | otherwise = strip_pipe_suffix s (pos + 1) len

fn :: rtype_to_str RType              => String
      rtype_to_str TyInt              =  "Int"
      rtype_to_str TyReal             =  "Real"
      rtype_to_str TyChar             =  "Char"
      rtype_to_str TyString           =  "String"
      rtype_to_str TyBool             =  "Bool"
      rtype_to_str TyUnit             =  "()"
      rtype_to_str (TyList inner)     =  "[" + (rtype_to_str inner) + "]"
      rtype_to_str (TyTuple elems)    =  "(" + (rtype_list_to_str elems) + ")"
      rtype_to_str (TyTensor [])      =  "Tensor"
      rtype_to_str (TyTensor dims)    =  "Tensor(" + (join_comma_strs dims) + ")"
      rtype_to_str (TyVariadic inner) =  (rtype_to_str inner) + "..."
      rtype_to_str (TyFun params ret) =  "(" + (rtype_list_to_str params) + " => " + (rtype_to_str ret) + ")"
      rtype_to_str (TyVar name)
        | str_starts_with name "adt:" =
          raw = str_slice name 4 (str_len name)
          strip_pipe_suffix raw 0 (str_len raw)
        | otherwise = name

fn :: rtype_list_to_str [RType] => String
      rtype_list_to_str []      =  ""
      rtype_list_to_str (t:[])  =  rtype_to_str t
      rtype_list_to_str (t:ts)  =  (rtype_to_str t) + ", " + (rtype_list_to_str ts)

fn :: join_comma_strs [String] => String
      join_comma_strs []       =  ""
      join_comma_strs (s:[])   =  s
      join_comma_strs (s:ss)   =  s + ", " + (join_comma_strs ss)

-- ── Type Unification & Compatibility ────────────────────────

fn :: rtype_list_len [RType] => Int
      rtype_list_len []      =  0
      rtype_list_len (_:xs)  =  1 + (rtype_list_len xs)

fn :: dims_compatible [String] [String] => Bool
      dims_compatible []       []       =  True
      dims_compatible (a:as)   (b:bs)
        | a == b OR (is_lower_ident a) OR (is_lower_ident b) = dims_compatible as bs
        | otherwise = False
      dims_compatible _        _        =  False

fn :: tensor_dims_unify [String] [String] => Bool
      tensor_dims_unify []       _        =  True
      tensor_dims_unify _        []       =  True
      tensor_dims_unify d1       d2
        | (str_list_count d1) == (str_list_count d2) = dims_compatible d1 d2
        | otherwise = False

fn :: types_list_compatible [RType] [RType] => Bool
      types_list_compatible []      []      =  True
      types_list_compatible (a:as)  (b:bs)
        | types_compatible a b = types_list_compatible as bs
        | otherwise = False
      types_list_compatible _       _       =  False

fn :: is_poly_type_var String => Bool
      is_poly_type_var s
        | str_starts_with s "adt:" = False
        | s == "_empty" OR s == "_any" OR s == "Option" OR s == "_chan_or_agent" = True
        | (str_len s) == 1 = True
        | otherwise = False

fn :: adt_accepts_prim String RType    => Bool
      adt_accepts_prim a      TyInt    =  str_contains a "|prim:Int"
      adt_accepts_prim a      TyReal   =  str_contains a "|prim:Real"
      adt_accepts_prim a      TyString =  str_contains a "|prim:String"
      adt_accepts_prim a      TyChar   =  str_contains a "|prim:String"
      adt_accepts_prim a      TyBool   =  str_contains a "|prim:Bool"
      adt_accepts_prim _      _        =  False

fn :: types_compatible RType              RType              => Bool
      types_compatible TyInt              TyInt              =  True
      types_compatible TyReal             TyReal             =  True
      types_compatible TyChar             TyChar             =  True
      types_compatible TyChar             TyString           =  True
      types_compatible TyString           TyChar             =  True
      types_compatible TyString           TyString           =  True
      types_compatible TyBool             TyBool             =  True
      types_compatible TyUnit             TyUnit             =  True
      types_compatible (TyTensor d1)      (TyTensor d2)      =  tensor_dims_unify d1 d2
      types_compatible (TyVariadic inner) other              =
        (types_compatible inner other) OR (types_compatible (TyList inner) other)
      types_compatible other              (TyVariadic inner) =
        (types_compatible inner other) OR (types_compatible (TyList inner) other)
      types_compatible (TyVar a)          (TyVar b)
        | a == b OR ("adt:" + a) == b OR ("adt:" + b) == a = True
        | (is_poly_type_var a) OR (is_poly_type_var b) = True
        | (str_starts_with a "adt:") AND (str_starts_with b "adt:") AND ((str_contains a b) OR (str_contains b a) OR (str_contains a ("adt:" + (rtype_to_str (TyVar b)))) OR (str_contains b ("adt:" + (rtype_to_str (TyVar a))))) = True
        | otherwise = False
      types_compatible (TyVar "Agent")    (TyTuple ((TyVar "Agent"):_)) = True
      types_compatible (TyTuple ((TyVar "Agent"):_)) (TyVar "Agent") = True
      types_compatible (TyVar a)          other
        | is_poly_type_var a = True
        | (str_starts_with a "adt:") AND (adt_accepts_prim a other) = True
        | otherwise = False
      types_compatible other              (TyVar b)
        | is_poly_type_var b = True
        | (str_starts_with b "adt:") AND (adt_accepts_prim b other) = True
        | otherwise = False
      types_compatible (TyList a)         (TyList b)         =  types_compatible a b
      types_compatible (TyTuple as)       (TyTuple bs)
        | (rtype_list_len as) == (rtype_list_len bs) = types_list_compatible as bs
        | otherwise = False
      types_compatible (TyFun p1 r1)      (TyFun p2 r2)
        | (rtype_list_len p1) == (rtype_list_len p2) AND (types_list_compatible p1 p2) = types_compatible r1 r2
        | otherwise = False
      types_compatible _                  _                  =  False

-- ── Type Environment Lookup & Registration ──────────────────

fn :: embedded_variant_tag RVariant => String
      embedded_variant_tag (TypeVariant c (a:[]))
        | c != a = ""
        | is_int_type_name c = "|prim:Int"
        | c == "Real" OR c == "Float" = "|prim:Real"
        | c == "String" OR c == "Char" = "|prim:String"
        | c == "Bool" = "|prim:Bool"
        | otherwise = "|adt:" + c
      embedded_variant_tag _        =  ""

fn :: collect_embedded_tags [RVariant] => String
      collect_embedded_tags []         =  ""
      collect_embedded_tags (v:vs)     =  (embedded_variant_tag v) + (collect_embedded_tags vs)

fn :: collect_typedef_names [RTypeDef] => [String]
      collect_typedef_names []         =  []
      collect_typedef_names ((TypeDef name vars _):ts) =
        [(name + (collect_embedded_tags vars))] :: (collect_typedef_names ts)

fn :: lookup_declared_adt_entry [String] String => String
      lookup_declared_adt_entry []       _      =  ""
      lookup_declared_adt_entry (e:es)   target
        | e == target OR (str_starts_with e (target + "|")) = e
        | otherwise = lookup_declared_adt_entry es target

fn :: qualify_declared_adt [String] RType              => RType
      qualify_declared_adt tnames   (TyVar s)
        | (lookup_declared_adt_entry tnames s) != "" = TyVar ("adt:" + (lookup_declared_adt_entry tnames s))
        | otherwise = TyVar s
      qualify_declared_adt tnames   (TyList inner)     =  TyList (qualify_declared_adt tnames inner)
      qualify_declared_adt tnames   (TyTuple elems)    =  TyTuple (qualify_declared_adt_list tnames elems)
      qualify_declared_adt tnames   (TyVariadic inner) =  TyVariadic (qualify_declared_adt tnames inner)
      qualify_declared_adt tnames   (TyFun params ret) =  TyFun (qualify_declared_adt_list tnames params) (qualify_declared_adt tnames ret)
      qualify_declared_adt _        other              =  other

fn :: qualify_declared_adt_list [String] [RType] => [RType]
      qualify_declared_adt_list _        []      =  []
      qualify_declared_adt_list tnames   (t:ts)  =  [qualify_declared_adt tnames t] :: (qualify_declared_adt_list tnames ts)

fn :: lookup_type_bind [RTypeBind] String => (Bool, RType)
      lookup_type_bind []          _      =  (False, TyInt)
      lookup_type_bind ((TypeBind k ty):rest) target
        | k == target = (True, ty)
        | otherwise = lookup_type_bind rest target

fn :: put_type_bind [RTypeBind] String RType => [RTypeBind]
      put_type_bind env         k      ty    =  [TypeBind k ty] :: env

fn :: builtin_local_types => [RTypeBind]
      builtin_local_types =
        [TypeBind "new_mailbox" TyInt, TypeBind "mailbox" TyInt, TypeBind "new_channel" TyInt, TypeBind "channel" TyInt, TypeBind "cli_args" (TyList TyString), TypeBind "sys_os" (TyVar "adt:SysOs"), TypeBind "sys_arch" (TyVar "adt:SysArch"), TypeBind "sys_getcwd" TyString, TypeBind "sys_getuid" TyInt, TypeBind "sys_getgid" TyInt, TypeBind "sys_getpid" TyInt, TypeBind "sys_time_ms" TyInt, TypeBind "sys_deadline_ms" TyInt, TypeBind "sys_remaining_ms" TyInt, TypeBind "cmm_live_blocks" TyInt, TypeBind "cmm_cond_spared" TyInt, TypeBind "cmm_cond_freed" TyInt]

fn :: builtin_fn_types => [RTypeBind]
      builtin_fn_types =
        [TypeBind "cli_args" (TyFun [] (TyList TyString)), TypeBind "new_mailbox" (TyFun [] TyInt), TypeBind "new_channel" (TyFun [] TyInt), TypeBind "stop" (TyFun [TyVar "Agent"] TyUnit), TypeBind "agent_alive" (TyFun [TyVar "Agent"] TyBool), TypeBind "send_to" (TyFun [TyVar "A", TyVar "Agent"] TyUnit), TypeBind "ask_to" (TyFun [TyVar "A", TyVar "Agent"] (TyVar "B")), TypeBind "new_bounded_channel" (TyFun [TyInt] TyInt), TypeBind "send_through" (TyFun [TyVar "A", TyInt] TyUnit), TypeBind "chan_send" (TyFun [TyVar "A", TyInt] TyUnit), TypeBind "receive_from" (TyFun [TyVar "_chan_or_agent"] (TyVar "A")), TypeBind "chan_recv" (TyFun [TyInt] (TyVar "A")), TypeBind "try_receive_from" (TyFun [TyVar "_chan_or_agent"] (TyVar "Option")), TypeBind "chan_try_recv" (TyFun [TyInt] (TyVar "Option")), TypeBind "receive_from_timeout" (TyFun [TyInt, TyInt] (TyVar "Option")), TypeBind "str_len" (TyFun [TyString] TyInt), TypeBind "str_char_at" (TyFun [TyString, TyInt] TyInt), TypeBind "str_slice" (TyFun [TyString, TyInt, TyInt] TyString), TypeBind "char_from_code" (TyFun [TyInt] TyString), TypeBind "str_concat" (TyFun [TyString, TyString] TyString), TypeBind "int_to_str" (TyFun [TyInt] TyString), TypeBind "str_to_int" (TyFun [TyString] TyInt), TypeBind "str_starts_with" (TyFun [TyString, TyString] TyBool), TypeBind "str_contains" (TyFun [TyString, TyString] TyBool), TypeBind "read_file" (TyFun [TyString] TyString), TypeBind "load_rg_source" (TyFun [TyString] TyString), TypeBind "read_bytes" (TyFun [TyString] (TyList TyInt)), TypeBind "write_bytes" (TyFun [TyString, TyList TyInt] TyUnit), TypeBind "write_file" (TyFun [TyString, TyString] TyUnit), TypeBind "shell_exec" (TyFun [TyString] TyInt), TypeBind "map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "seq_map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "||map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "par_map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "seq_filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "||filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "par_filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "fold" (TyFun [TyFun [TyVar "B", TyVar "A"] (TyVar "B"), TyVar "B", TyList (TyVar "A")] (TyVar "B")), TypeBind "list_dir" (TyFun [TyString] (TyList TyString)), TypeBind "file_lstat" (TyFun [TyString] (TyTuple [TyBool, TyString, TyInt, TyInt, TyInt, TyString, TyString, TyInt, TyString])), TypeBind "sha256_file" (TyFun [TyString] TyString), TypeBind "sha256_str" (TyFun [TyString] TyString), TypeBind "sys_os" (TyFun [] (TyVar "adt:SysOs")), TypeBind "sys_arch" (TyFun [] (TyVar "adt:SysArch")), TypeBind "sys_mkdir" (TyFun [TyString, TyInt] TyInt), TypeBind "sys_chmod" (TyFun [TyString, TyInt] TyInt), TypeBind "sys_exec" (TyFun [TyString, TyList TyString, TyList TyString] TyInt), TypeBind "sys_chdir" (TyFun [TyString] TyInt), TypeBind "sys_getcwd" (TyFun [] TyString), TypeBind "sys_getenv" (TyFun [TyString] TyString), TypeBind "sys_setenv" (TyFun [TyString, TyString] TyInt), TypeBind "sys_exit" (TyFun [TyInt] TyUnit), TypeBind "sys_getuid" (TyFun [] TyInt), TypeBind "sys_getgid" (TyFun [] TyInt), TypeBind "sys_getpid" (TyFun [] TyInt), TypeBind "sys_time_ms" (TyFun [] TyInt), TypeBind "sys_deadline_ms" (TyFun [] TyInt), TypeBind "sys_remaining_ms" (TyFun [] TyInt), TypeBind "sys_sleep_ms" (TyFun [TyInt] TyUnit), TypeBind "sys_open_mode" (TyFun [TyString, TyString] TyInt), TypeBind "sys_open" (TyFun [TyString, TyInt, TyInt] TyInt), TypeBind "sys_close" (TyFun [TyInt] TyInt), TypeBind "sys_read_fd" (TyFun [TyInt, TyInt] TyString), TypeBind "sys_write_fd" (TyFun [TyInt, TyString] TyInt), TypeBind "sys_poll" (TyFun [TyInt, TyInt, TyInt] TyInt), TypeBind "sys_terminate" (TyFun [TyInt, TyBool] TyInt), TypeBind "sys_kill" (TyFun [TyInt, TyInt] TyInt), TypeBind "sys_call" (TyFun [TyInt, TyInt, TyInt, TyInt, TyInt, TyInt, TyInt] TyInt), TypeBind "sys_username" (TyFun [TyInt] TyString), TypeBind "sys_user_groups" (TyFun [TyString] (TyList TyString)), TypeBind "sys_lookup_uid_gid" (TyFun [TyString] (TyTuple [TyInt, TyInt])), TypeBind "sys_setresgid" (TyFun [TyInt] TyInt), TypeBind "sys_setgroups" (TyFun [TyList TyInt] TyInt), TypeBind "sys_setresuid" (TyFun [TyInt] TyInt), TypeBind "sys_execve" (TyFun [TyString, TyList TyString, TyList TyString] TyInt), TypeBind "sys_read_pass" (TyFun [TyString] TyString), TypeBind "cmm_live_blocks" (TyFun [] TyInt), TypeBind "cmm_cond_spared" (TyFun [] TyInt), TypeBind "cmm_cond_freed" (TyFun [] TyInt), TypeBind "cmm_same_ptr" (TyFun [TyVar "A", TyVar "A"] TyBool)]

fn :: join_adt_ret_ty RType     RType     => RType
      join_adt_ret_ty (TyVar a) (TyVar b)
        | (str_starts_with a "adt:") AND (str_starts_with b "adt:") AND (NOT (str_contains a b)) = TyVar (a + "|" + b)
        | otherwise = TyVar a
      join_adt_ret_ty a         _         =  a

fn :: put_ctor_local_bind [RTypeBind] String RType  => [RTypeBind]
      put_ctor_local_bind locals      ctor   adt_ty =
        prev = lookup_type_bind locals ctor
        put_ctor_local_step locals ctor adt_ty prev

fn :: put_ctor_local_step [RTypeBind] String RType (Bool, RType) => [RTypeBind]
      put_ctor_local_step locals ctor adt_ty (True, prev_ty) =
        put_type_bind locals ctor (join_adt_ret_ty prev_ty adt_ty)
      put_ctor_local_step locals ctor adt_ty (False, _) =
        put_type_bind locals ctor adt_ty

fn :: register_variants [String] [RVariant] RType [RTypeBind] [RTypeBind] => ([RTypeBind], [RTypeBind])
      register_variants _ [] _ locals fns = (locals, fns)
      register_variants tnames ((TypeVariant ctor []):vs) adt_ty locals fns =
        register_variants tnames vs adt_ty (put_ctor_local_bind locals ctor adt_ty) fns
      register_variants tnames ((TypeVariant ctor arg_strs):vs) adt_ty locals fns =
        arg_tys = qualify_declared_adt_list tnames (parse_type_list_strs arg_strs)
        register_variants tnames vs adt_ty locals (put_type_bind fns ctor (TyFun arg_tys adt_ty))

fn :: collect_field_types [String] [RField] => [RType]
      collect_field_types _        []       =  []
      collect_field_types tnames   ((TypeField _ fty_str):fs) =
        [qualify_declared_adt tnames (parse_type_str fty_str)] :: (collect_field_types tnames fs)

fn :: register_field_accessors [String] [RField] RType [RTypeBind] => [RTypeBind]
      register_field_accessors _ [] _ fns = fns
      register_field_accessors tnames ((TypeField fname fty_str):fs) adt_ty fns =
        fty = qualify_declared_adt tnames (parse_type_str fty_str)
        register_field_accessors tnames fs adt_ty (put_type_bind fns fname (TyFun [adt_ty] fty))

fn :: register_typedef [String] RTypeDef [RTypeBind] [RTypeBind] => ([RTypeBind], [RTypeBind])
      register_typedef tnames (TypeDef name vars []) locals fns =
        adt_ty = qualify_declared_adt tnames (parse_type_str name)
        register_variants tnames vars adt_ty locals fns
      register_typedef tnames (TypeDef name vars fields) locals fns =
        adt_ty = qualify_declared_adt tnames (parse_type_str name)
        v_res = register_variants tnames vars adt_ty locals fns
        register_record_helpers tnames name adt_ty fields v_res

fn :: register_record_helpers [String] String RType [RField] ([RTypeBind], [RTypeBind]) => ([RTypeBind], [RTypeBind])
      register_record_helpers tnames name adt_ty fields (locals, fns) =
        ctor_arg_tys = collect_field_types tnames fields
        fns1 = put_type_bind fns name (TyFun ctor_arg_tys adt_ty)
        fns2 = register_field_accessors tnames fields adt_ty fns1
        (locals, fns2)

fn :: register_typedef_list [String] [RTypeDef] [RTypeBind] [RTypeBind] => ([RTypeBind], [RTypeBind])
      register_typedef_list _ [] locals fns = (locals, fns)
      register_typedef_list tnames (t:ts) locals fns =
        r1 = register_typedef tnames t locals fns
        register_typedef_list_cont tnames ts r1

fn :: register_typedef_list_cont [String] [RTypeDef] ([RTypeBind], [RTypeBind]) => ([RTypeBind], [RTypeBind])
      register_typedef_list_cont tnames ts (locals1, fns1) =
        register_typedef_list tnames ts locals1 fns1

fn :: register_fndef_sigs [String] [RFnDef] [RTypeBind] => [RTypeBind]
      register_fndef_sigs _        []       fns         =  fns
      register_fndef_sigs tnames   ((FnDef name param_strs ret_str _):fs) fns =
        param_tys = qualify_declared_adt_list tnames (parse_type_list_strs param_strs)
        ret_ty = qualify_declared_adt tnames (parse_type_str ret_str)
        register_fndef_sigs tnames fs (put_type_bind fns name (TyFun param_tys ret_ty))

-- ── Pattern Variable Binding ────────────────────────────────

fn :: rtype_at [RType] Int => RType
      rtype_at (t:_)   0   =  t
      rtype_at (_:ts)  idx =  rtype_at ts (idx - 1)
      rtype_at []      _   =  TyInt

fn :: unwrap_variadic_param RType              => RType
      unwrap_variadic_param (TyVariadic inner) =  TyList inner
      unwrap_variadic_param other              =  other

fn :: has_seq_bind_pat [RPattern]         => Bool
      has_seq_bind_pat []                 =  False
      has_seq_bind_pat ((PatSeqBind _):_) =  True
      has_seq_bind_pat (_:ps)             =  has_seq_bind_pat ps

fn :: ctor_param_types [RTypeBind] String    => [RType]
      ctor_param_types fns         ctor_name =
        extract_fun_params (lookup_type_bind fns ctor_name)

fn :: extract_fun_params (Bool, RType) => [RType]
      extract_fun_params (True, (TyFun params _)) = params
      extract_fun_params _             =  []

fn :: pat_list_arity [RPattern] => Int
      pat_list_arity []         =  0
      pat_list_arity (_:xs)     =  1 + (pat_list_arity xs)

fn :: lookup_ctor_for_type [RTypeBind] String RType    Int   => (Bool, [RType])
      lookup_ctor_for_type []          _      _        _     =  (False, [])
      lookup_ctor_for_type ((TypeBind k (TyFun params ret_ty)):rest) target expected arity
        | k == target AND (rtype_list_len params) == arity AND (types_compatible ret_ty expected) = (True, params)
        | otherwise = lookup_ctor_for_type rest target expected arity
      lookup_ctor_for_type (_:rest)    target expected arity =
        lookup_ctor_for_type rest target expected arity

fn :: lookup_ctor_by_arity [RTypeBind] String Int   => (Bool, [RType])
      lookup_ctor_by_arity []          _      _     =  (False, [])
      lookup_ctor_by_arity ((TypeBind k (TyFun params _)):rest) target arity
        | k == target AND (rtype_list_len params) == arity = (True, params)
        | otherwise = lookup_ctor_by_arity rest target arity
      lookup_ctor_by_arity (_:rest)    target arity =
        lookup_ctor_by_arity rest target arity

fn :: ctor_param_types_for [RTypeBind] String    RType    Int   => [RType]
      ctor_param_types_for fns         ctor_name expected arity =
        by_ty = lookup_ctor_for_type fns ctor_name expected arity
        ctor_param_types_fallback fns ctor_name arity by_ty

fn :: ctor_param_types_fallback [RTypeBind] String Int (Bool, [RType]) => [RType]
      ctor_param_types_fallback _ _ _ (True, params) = params
      ctor_param_types_fallback fns ctor_name arity (False, _) =
        by_ar = lookup_ctor_by_arity fns ctor_name arity
        ctor_param_types_arity_fallback fns ctor_name by_ar

fn :: ctor_param_types_arity_fallback [RTypeBind] String (Bool, [RType]) => [RType]
      ctor_param_types_arity_fallback _ _ (True, params) = params
      ctor_param_types_arity_fallback fns ctor_name (False, _) =
        ctor_param_types fns ctor_name

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
      bind_pattern (PatCtor ctor_name args) expected locals fns =
        param_tys = ctor_param_types_for fns ctor_name expected (pat_list_arity args)
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
      lookup_dim_bind []         _      =  (False, "")
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
      sub_chars_to_strs s      pos len
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

fn :: is_poly_tyvar RType     => Bool
      is_poly_tyvar (TyVar s) =  is_lower_ident s
      is_poly_tyvar _         =  False

fn :: is_int_or_poly RType => Bool
      is_int_or_poly TyInt =  True
      is_int_or_poly t     =  is_poly_tyvar t

fn :: is_real_or_poly RType  => Bool
      is_real_or_poly TyReal =  True
      is_real_or_poly t      =  is_poly_tyvar t

fn :: is_str_or_poly RType    => Bool
      is_str_or_poly TyString =  True
      is_str_or_poly t        =  is_poly_tyvar t

fn :: binop_symbol RBinOp => String
      binop_symbol OpAdd  =  "+"
      binop_symbol OpSub  =  "-"
      binop_symbol OpMul  =  "*"
      binop_symbol OpDiv  =  "/"
      binop_symbol OpMod  =  "%"
      binop_symbol _      =  ""

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

fn :: check_matmul_binop RType RType String  => (RType, [RTypeError])
      check_matmul_binop (TyTensor (d1a:d1b:[])) (TyTensor (d2a:d2b:[])) fn_name
        | d1b != d2a = (TyTensor [d1a, d2b], [TypeError fn_name ("tensor contraction dimension mismatch: " + d1b + " vs " + d2a)])
        | otherwise = (TyTensor [d1a, d2b], [])
      check_matmul_binop _     _     _       =  (TyTensor [], [])

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

fn :: count_char_in_str String Int Int Int       => Int
      count_char_in_str s      pos len target_ch
        | pos >= len = 0
        | (str_char_at s pos) == target_ch = 1 + (count_char_in_str s (pos + 1) len target_ch)
        | otherwise = count_char_in_str s (pos + 1) len target_ch

fn :: seq_select_type String => RType
      seq_select_type mask   =
        plus_c = count_char_in_str mask 0 (str_len mask) 43
        space_c = count_char_in_str mask 0 (str_len mask) 32
        decide_seq_select_type plus_c space_c

fn :: decide_seq_select_type Int    Int     => RType
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
      extract_subscript_ty (True, ty)    =  (ty, [])
      extract_subscript_ty (False, _)    =  (TyTensor [], [])

fn :: is_last_variadic [RType] => Bool
      is_last_variadic []      =  False
      is_last_variadic ((TyVariadic _):[]) = True
      is_last_variadic (_:ts)  =  is_last_variadic ts

fn :: last_variadic_inner [RType] => RType
      last_variadic_inner ((TyVariadic inner):[]) = inner
      last_variadic_inner (_:ts)  =  last_variadic_inner ts
      last_variadic_inner []      =  TyInt

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
      take_rtypes _       0   =  []
      take_rtypes []      _   =  []
      take_rtypes (x:xs)  n   =  [x] :: (take_rtypes xs (n - 1))

fn :: drop_rtypes [RType] Int => [RType]
      drop_rtypes xs      0   =  xs
      drop_rtypes []      _   =  []
      drop_rtypes (_:xs)  n   =  drop_rtypes xs (n - 1)

fn :: is_single_poly_var String => Bool
      is_single_poly_var s
        | str_starts_with s "adt:" = False
        | otherwise = (str_len s) == 1

fn :: is_concrete_for_poly RType            => Bool
      is_concrete_for_poly (TyVar "_empty") =  False
      is_concrete_for_poly (TyVar "_any")   =  False
      is_concrete_for_poly _                =  True

fn :: bind_or_check_poly String RType String String [RTypeBind] => ([RTypeBind], [RTypeError])
      bind_or_check_poly v arg callee fn_name poly_env =
        bind_or_check_poly_step v arg callee fn_name poly_env (lookup_type_bind poly_env v)

fn :: bind_or_check_poly_step String RType String String [RTypeBind] (Bool, RType) => ([RTypeBind], [RTypeError])
      bind_or_check_poly_step v arg _ _ poly_env (False, _)
        | is_concrete_for_poly arg = ([TypeBind v arg] :: poly_env, [])
        | otherwise = (poly_env, [])
      bind_or_check_poly_step v arg callee fn_name poly_env (True, bound_ty)
        | types_compatible arg bound_ty = (poly_env, [])
        | otherwise = (poly_env, [TypeError fn_name ("function '" + callee + "' type variable " + v + " unified with incompatible types: " + (rtype_to_str bound_ty) + " and " + (rtype_to_str arg))])

fn :: collect_poly_binds RType RType String String [RTypeBind] => ([RTypeBind], [RTypeError])
      collect_poly_binds arg (TyVar v) callee fn_name poly_env
        | is_single_poly_var v = bind_or_check_poly v arg callee fn_name poly_env
        | otherwise = (poly_env, [])
      collect_poly_binds (TyList a_in) (TyList p_in) callee fn_name poly_env =
        collect_poly_binds a_in p_in callee fn_name poly_env
      collect_poly_binds (TyTuple a_es) (TyTuple p_es) callee fn_name poly_env =
        collect_poly_binds_list a_es p_es callee fn_name poly_env
      collect_poly_binds (TyFun a_ps a_r) (TyFun p_ps p_r) callee fn_name poly_env =
        collect_poly_binds_after (collect_poly_binds_list a_ps p_ps callee fn_name poly_env) a_r p_r callee fn_name
      collect_poly_binds _ _ _ _ poly_env = (poly_env, [])

fn :: collect_poly_binds_after ([RTypeBind], [RTypeError]) RType RType String String => ([RTypeBind], [RTypeError])
      collect_poly_binds_after (env1, errs1) a_r p_r callee fn_name =
        merge_poly_res errs1 (collect_poly_binds a_r p_r callee fn_name env1)

fn :: collect_poly_binds_list [RType] [RType] String String [RTypeBind] => ([RTypeBind], [RTypeError])
      collect_poly_binds_list [] _ _ _ poly_env = (poly_env, [])
      collect_poly_binds_list _ [] _ _ poly_env = (poly_env, [])
      collect_poly_binds_list (a:as) (p:ps) callee fn_name poly_env =
        collect_poly_binds_list_step (collect_poly_binds a p callee fn_name poly_env) as ps callee fn_name

fn :: collect_poly_binds_list_step ([RTypeBind], [RTypeError]) [RType] [RType] String String => ([RTypeBind], [RTypeError])
      collect_poly_binds_list_step (env1, errs1) as ps callee fn_name =
        merge_poly_res errs1 (collect_poly_binds_list as ps callee fn_name env1)

fn :: merge_poly_res [RTypeError] ([RTypeBind], [RTypeError]) => ([RTypeBind], [RTypeError])
      merge_poly_res errs1 (env2, errs2) = (env2, errs1 :: errs2)

fn :: subst_poly_type RType          [RTypeBind] => RType
      subst_poly_type (TyVar v)      poly_env
        | is_single_poly_var v = subst_poly_var v (lookup_type_bind poly_env v)
        | otherwise = TyVar v
      subst_poly_type (TyList inner) poly_env    =  TyList (subst_poly_type inner poly_env)
      subst_poly_type (TyTuple es)   poly_env    =  TyTuple (subst_poly_type_list es poly_env)
      subst_poly_type (TyFun ps r)   poly_env    =  TyFun (subst_poly_type_list ps poly_env) (subst_poly_type r poly_env)
      subst_poly_type ty             _           =  ty

fn :: subst_poly_var String (Bool, RType) => RType
      subst_poly_var _      (True, ty)    =  ty
      subst_poly_var v      (False, _)    =  TyVar v

fn :: subst_poly_type_list [RType] [RTypeBind] => [RType]
      subst_poly_type_list []      _           =  []
      subst_poly_type_list (t:ts)  poly_env    =  [subst_poly_type t poly_env] :: (subst_poly_type_list ts poly_env)

fn :: finish_poly_call RType [RTypeError] ([RTypeBind], [RTypeError]) => (RType, [RTypeError])
      finish_poly_call ret_ty fixed_errs (poly_env, poly_errs) =
        (subst_poly_type ret_ty poly_env, fixed_errs :: poly_errs)

fn :: check_call_sig String [RType] [RType] RType String => (RType, [RTypeError])
      check_call_sig callee arg_tys param_tys ret_ty fn_name
        | is_last_variadic param_tys = check_variadic_call callee arg_tys param_tys ret_ty fn_name
        | (rtype_list_len arg_tys) == 1 AND (rtype_list_len param_tys) > 1 = check_tuple_chain_call callee (rtype_at arg_tys 0) arg_tys param_tys ret_ty fn_name
        | (rtype_list_len arg_tys) != (rtype_list_len param_tys) = (ret_ty, [TypeError fn_name ("function '" + callee + "' called with " + (int_to_str (rtype_list_len arg_tys)) + " argument(s), expected " + (int_to_str (rtype_list_len param_tys)))])
        | otherwise = finish_poly_call ret_ty (check_fixed_args arg_tys param_tys callee fn_name 0 []) (collect_poly_binds_list arg_tys param_tys callee fn_name [])

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
        | (rtype_list_len elems) == (rtype_list_len param_tys) = finish_poly_call ret_ty (check_fixed_args elems param_tys callee fn_name 0 []) (collect_poly_binds_list elems param_tys callee fn_name [])
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

fn :: lookup_record_field_for_type [RTypeBind] String RType   => (Bool, RType)
      lookup_record_field_for_type []          _      _       =  (False, TyInt)
      lookup_record_field_for_type ((TypeBind k (TyFun (rec_ty:[]) fty)):rest) target base_ty
        | k == target AND (types_compatible base_ty rec_ty) = (True, TyFun [rec_ty] fty)
        | otherwise = lookup_record_field_for_type rest target base_ty
      lookup_record_field_for_type (_:rest)    target base_ty =
        lookup_record_field_for_type rest target base_ty

fn :: lookup_record_field_bind [RTypeBind] String RType   => (Bool, RType)
      lookup_record_field_bind fns         fname  base_ty =
        by_ty = lookup_record_field_for_type fns fname base_ty
        lookup_record_field_fallback fns fname by_ty

fn :: lookup_record_field_fallback [RTypeBind] String (Bool, RType) => (Bool, RType)
      lookup_record_field_fallback _ _ (True, ty) = (True, ty)
      lookup_record_field_fallback fns fname (False, _) = lookup_type_bind fns fname

fn :: check_record_update_fields (RType, [RTypeError]) [RExpr] String [RTypeBind] [RTypeBind] => (RType, [RTypeError])
      check_record_update_fields (base_ty, base_errs) [] _ _ _ = (base_ty, base_errs)
      check_record_update_fields (base_ty, base_errs) ((EStr fname):val_e:rest) fn_name locals fns =
        v_res = check_expr val_e fn_name locals fns
        f_errs = check_one_record_field base_ty fname v_res fn_name (lookup_record_field_bind fns fname base_ty)
        check_record_update_fields (base_ty, base_errs :: f_errs) rest fn_name locals fns
      check_record_update_fields (base_ty, base_errs) (_:rest) fn_name locals fns =
        check_record_update_fields (base_ty, base_errs) rest fn_name locals fns

fn :: check_one_record_field RType String (RType, [RTypeError]) String (Bool, RType) => [RTypeError]
      check_one_record_field base_ty fname (val_ty, val_errs) fn_name (True, (TyFun (rec_ty:[]) fty))
        | NOT (types_compatible base_ty rec_ty) = val_errs :: [TypeError fn_name ("record field '" + fname + "' belongs to " + (rtype_to_str rec_ty) + ", not " + (rtype_to_str base_ty))]
        | NOT (types_compatible val_ty fty) = val_errs :: [TypeError fn_name ("record field '" + fname + "' has type " + (rtype_to_str val_ty) + ", expected " + (rtype_to_str fty))]
        | otherwise = val_errs
      check_one_record_field _ fname (_, val_errs) fn_name _ =
        val_errs :: [TypeError fn_name ("unknown record field '" + fname + "'")]

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

fn :: check_list_elems_uniform RType    [RType] String  => [RTypeError]
      check_list_elems_uniform _        []      _       =  []
      check_list_elems_uniform first_ty (t:ts)  fn_name
        | types_compatible t first_ty = check_list_elems_uniform first_ty ts fn_name
        | otherwise = [TypeError fn_name ("list elements have mixed types: " + (rtype_to_str first_ty) + " and " + (rtype_to_str t))] :: (check_list_elems_uniform first_ty ts fn_name)

fn :: finish_list_type ([RType], [RTypeError]) String  => (RType, [RTypeError])
      finish_list_type ([], errs)              _       =  (TyList (TyVar "_empty"), errs)
      finish_list_type ((first_ty:rest_tys), errs) fn_name =
        elem_errs = check_list_elems_uniform first_ty rest_tys fn_name
        (TyList first_ty, errs :: elem_errs)

fn :: finish_tuple_type ([RType], [RTypeError]) => (RType, [RTypeError])
      finish_tuple_type (tys, errs)             =  (TyTuple tys, errs)

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
      check_expr (ECall "__record_update__" (base_e:rest_args)) fn_name locals fns =
        b_res = check_expr base_e fn_name locals fns
        check_record_update_fields b_res rest_args fn_name locals fns
      check_expr (ECall callee args) fn_name locals fns =
        args_res = check_expr_list args fn_name locals fns
        finish_call_check callee args_res fn_name locals fns
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
      check_expr (EGuard guards) fn_name locals fns =
        check_guard_expr guards fn_name locals fns
      check_expr (EBlock stmts) fn_name locals fns =
        check_block_stmts stmts TyUnit fn_name locals fns

fn :: snd_errs (RType, [RTypeError]) => [RTypeError]
      snd_errs (_, errs)             =  errs

fn :: snd_list_errs ([RType], [RTypeError]) => [RTypeError]
      snd_list_errs (_, errs)               =  errs

fn :: discard_tys_return RType  ([RType], [RTypeError]) => (RType, [RTypeError])
      discard_tys_return ret_ty (_, errs)               =  (ret_ty, errs)

fn :: check_not_inner (RType, [RTypeError]) String  => (RType, [RTypeError])
      check_not_inner (inner_ty, errs)      fn_name
        | types_compatible inner_ty TyBool = (TyBool, errs)
        | otherwise = (TyBool, errs :: [TypeError fn_name ("NOT requires Bool operand, got " + (rtype_to_str inner_ty))])

fn :: check_with_ctx_body String RExpr String [RTypeBind] [RTypeBind] (RType, [RTypeError]) => (RType, [RTypeError])
      check_with_ctx_body "__rg_timeout_ms__" body fn_name locals fns (val_ty, v_errs)
        | types_compatible val_ty TyInt =
          b_res = check_expr body fn_name locals fns
          prepend_type_errs v_errs b_res
        | otherwise =
          b_res = check_expr body fn_name locals fns
          prepend_type_errs (v_errs :: [TypeError fn_name ("with timeout requires Int duration, got " + (rtype_to_str val_ty))]) b_res
      check_with_ctx_body ctx_name body fn_name locals fns (val_ty, v_errs) =
        locals1 = put_type_bind locals ctx_name val_ty
        b_res = check_expr body fn_name locals1 fns
        prepend_type_errs v_errs b_res

fn :: finish_einsum_check ([RDimBind], [RTypeError]) => (RType, [RTypeError])
      finish_einsum_check (_, errs)                  =  (TyTensor [], errs)

fn :: finish_hadamard_check (RType, [RTypeError]) (RType, [RTypeError]) => (RType, [RTypeError])
      finish_hadamard_check ((TyTensor dims), l_errs) (_, r_errs) = (TyTensor dims, l_errs :: r_errs)
      finish_hadamard_check (_, l_errs) (_, r_errs) = (TyTensor [], l_errs :: r_errs)

fn :: finish_binop_check RBinOp (RType, [RTypeError]) (RType, [RTypeError]) [RTypeBind] String => (RType, [RTypeError])
      finish_binop_check bop (l_ty, l_errs) (r_ty, r_errs) fns fn_name =
        b_res = check_binop bop l_ty r_ty fns fn_name
        prepend_type_errs (l_errs :: r_errs) b_res

fn :: args_match_params [RType] [RType] => Bool
      args_match_params []      []      =  True
      args_match_params (a:as)  (p:ps)
        | types_compatible a p = args_match_params as ps
        | otherwise = False
      args_match_params _       _       =  False

fn :: collect_matching_sigs [RTypeBind] String [RType] => [RType]
      collect_matching_sigs []          _      _       =  []
      collect_matching_sigs ((TypeBind k (TyFun param_tys ret_ty)):rest) target arg_tys
        | k == target AND (rtype_list_len param_tys) == (rtype_list_len arg_tys) AND (args_match_params arg_tys param_tys) = [TyFun param_tys ret_ty] :: (collect_matching_sigs rest target arg_tys)
        | otherwise = collect_matching_sigs rest target arg_tys
      collect_matching_sigs (_:rest)    target arg_tys =
        collect_matching_sigs rest target arg_tys

fn :: merge_matching_sigs [RType] => (Bool, RType)
      merge_matching_sigs []      =  (False, TyInt)
      merge_matching_sigs (s:[])  =  (True, s)
      merge_matching_sigs ((TyFun p1 r1):(TyFun _ r2):rest) =
        merge_matching_sigs ([TyFun p1 (join_adt_ret_ty r1 r2)] :: rest)
      merge_matching_sigs (s:_)   =  (True, s)

fn :: resolve_callee_for_args String [RType] [RTypeBind] [RTypeBind] => (Bool, RType)
      resolve_callee_for_args callee arg_tys locals fns =
        matched = merge_matching_sigs (collect_matching_sigs fns callee arg_tys)
        resolve_callee_args_fallback callee locals fns matched

fn :: resolve_callee_args_fallback String [RTypeBind] [RTypeBind] (Bool, RType) => (Bool, RType)
      resolve_callee_args_fallback _ _ _ (True, ty) = (True, ty)
      resolve_callee_args_fallback callee locals fns (False, _) = resolve_callee_bind callee locals fns

fn :: resolve_callee_bind String [RTypeBind] [RTypeBind] => (Bool, RType)
      resolve_callee_bind callee locals      fns         =
        fn_b = lookup_type_bind fns callee
        resolve_callee_fallback callee locals fn_b

fn :: resolve_callee_fallback String [RTypeBind] (Bool, RType) => (Bool, RType)
      resolve_callee_fallback _      _           (True, ty)    =  (True, ty)
      resolve_callee_fallback callee locals      (False, _)    =  lookup_type_bind locals callee

fn :: pack_agent_msg_ty [RType]     => RType
      pack_agent_msg_ty []          =  TyUnit
      pack_agent_msg_ty (single:[]) =  single
      pack_agent_msg_ty tys         =  TyTuple tys

fn :: infer_stateful_agent_out RType RType  => RType
      infer_stateful_agent_out s_ty  (TyTuple (r1:r2:[]))
        | (types_compatible r1 s_ty) AND (NOT (types_compatible (TyTuple [r1, r2]) s_ty)) = r2
      infer_stateful_agent_out _     ret_ty =  ret_ty

fn :: check_agent_create [RType] [RTypeError] String  => (RType, [RTypeError])
      check_agent_create ((TyFun params ret_ty):[]) arg_errs _ =
        (TyTuple [TyVar "Agent", pack_agent_msg_ty params, ret_ty], arg_errs)
      check_agent_create ((TyFun (s_ty:msg_params) ret_ty):init_ty:[]) arg_errs fn_name
        | types_compatible init_ty s_ty =
          (TyTuple [TyVar "Agent", pack_agent_msg_ty msg_params, infer_stateful_agent_out s_ty ret_ty], arg_errs)
        | otherwise =
          err = TypeError fn_name ("agent initial state has type " + (rtype_to_str init_ty) + ", expected " + (rtype_to_str s_ty))
          (TyTuple [TyVar "Agent", pack_agent_msg_ty msg_params, infer_stateful_agent_out s_ty ret_ty], arg_errs :: [err])
      check_agent_create _       arg_errs     fn_name =
        (TyVar "Agent", arg_errs :: [TypeError fn_name "agent expects a function reference and optional initial state"])

fn :: check_agent_send [RType] [RTypeError] String  => (RType, [RTypeError])
      check_agent_send (msg_ty:(TyTuple ((TyVar "Agent"):in_ty:_)):[]) arg_errs fn_name
        | types_compatible msg_ty in_ty = (TyUnit, arg_errs)
        | otherwise =
          (TyUnit, arg_errs :: [TypeError fn_name ("agent message has type " + (rtype_to_str msg_ty) + ", expected " + (rtype_to_str in_ty))])
      check_agent_send (_:(TyVar "Agent"):[]) arg_errs _ = (TyUnit, arg_errs)
      check_agent_send _       arg_errs     _       =  (TyUnit, arg_errs)

fn :: specialize_hof_return String [RType] (RType, [RTypeError]) => (RType, [RTypeError])
      specialize_hof_return "map" ((TyFun _ f_ret):_) (_, errs) = (TyList f_ret, errs)
      specialize_hof_return "||map" ((TyFun _ f_ret):_) (_, errs) = (TyList f_ret, errs)
      specialize_hof_return "filter" (_:list_ty:_) (_, errs) = (list_ty, errs)
      specialize_hof_return "||filter" (_:list_ty:_) (_, errs) = (list_ty, errs)
      specialize_hof_return "fold" (_:init_ty:_) (_, errs) = (init_ty, errs)
      specialize_hof_return "receive_from" ((TyTuple ((TyVar "Agent"):_:out_ty:[])):_) (_, errs) = (out_ty, errs)
      specialize_hof_return _ _ res = res

fn :: check_agent_ask [RType] [RTypeError] String  => (RType, [RTypeError])
      check_agent_ask (msg_ty:(TyTuple ((TyVar "Agent"):in_ty:out_ty:[])):[]) arg_errs fn_name
        | types_compatible msg_ty in_ty = (out_ty, arg_errs)
        | otherwise =
          (out_ty, arg_errs :: [TypeError fn_name ("agent message has type " + (rtype_to_str msg_ty) + ", expected " + (rtype_to_str in_ty))])
      check_agent_ask (_:(TyVar "Agent"):[]) arg_errs _ = (TyVar "A", arg_errs)
      check_agent_ask _       arg_errs     _       =  (TyVar "A", arg_errs)

fn :: finish_call_check String ([RType], [RTypeError]) String [RTypeBind] [RTypeBind] => (RType, [RTypeError])
      finish_call_check "agent" (arg_tys, arg_errs) fn_name _ _ = check_agent_create arg_tys arg_errs fn_name
      finish_call_check "send_to" (arg_tys, arg_errs) fn_name _ _ = check_agent_send arg_tys arg_errs fn_name
      finish_call_check "ask_to" (arg_tys, arg_errs) fn_name _ _ = check_agent_ask arg_tys arg_errs fn_name
      finish_call_check callee (arg_tys, arg_errs) fn_name locals fns =
        base_res = check_call_target callee arg_tys arg_errs (resolve_callee_for_args callee arg_tys locals fns) fn_name
        specialize_hof_return callee arg_tys base_res

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
      bind_let_var name   ty    locals
        | is_subscript_ident name = bind_subscript_let (split_subscript name) name ty locals
        | otherwise = put_type_bind locals name ty

fn :: bind_subscript_let (String, String) String RType [RTypeBind] => [RTypeBind]
      bind_subscript_let (base, _) name ty locals =
        put_type_bind (put_type_bind locals base ty) name ty

fn :: check_guard_expr [RGuard] String [RTypeBind] [RTypeBind] => (RType, [RTypeError])
      check_guard_expr [] _ _ _ = (TyUnit, [])
      check_guard_expr ((GuardBranch cond body):gs) fn_name locals fns =
        c_res = check_expr cond fn_name locals fns
        b_res = check_expr body fn_name locals fns
        check_guard_expr_first c_res b_res gs fn_name locals fns

fn :: check_guard_expr_first (RType, [RTypeError]) (RType, [RTypeError]) [RGuard] String [RTypeBind] [RTypeBind] => (RType, [RTypeError])
      check_guard_expr_first (c_ty, c_errs) (b_ty, b_errs) gs fn_name locals fns =
        c_chk = check_guard_cond_ty c_ty fn_name 0
        rest_errs = check_case_guards gs fn_name b_ty 1 locals fns
        (b_ty, c_errs :: c_chk :: b_errs :: rest_errs)

fn :: check_block_stmts [RStmt] RType String [RTypeBind] [RTypeBind] => (RType, [RTypeError])
      check_block_stmts stmts last_ty fn_name locals fns =
        check_block_stmts_scoped stmts last_ty fn_name locals fns [] []

fn :: check_block_stmts_scoped [RStmt] RType String [RTypeBind] [RTypeBind] [String] [String] => (RType, [RTypeError])
      check_block_stmts_scoped [] last_ty _ _ _ _ _ = (last_ty, [])
      check_block_stmts_scoped ((StmtMut name val_e):ss) _ fn_name locals fns immuts muts =
        v_res = check_expr val_e fn_name locals fns
        check_block_after_mut name ss fn_name locals fns immuts muts v_res
      check_block_stmts_scoped ((StmtLet name val_e):ss) _ fn_name locals fns immuts muts =
        v_res = check_expr val_e fn_name locals fns
        check_block_after_let name ss fn_name locals fns immuts muts v_res
      check_block_stmts_scoped ((StmtExpr e):ss) _ fn_name locals fns immuts muts =
        e_res = check_expr e fn_name locals fns
        check_block_after_expr ss fn_name locals fns immuts muts e_res
      check_block_stmts_scoped ((StmtAtomic _ val_e):ss) _ fn_name locals fns immuts muts =
        v_res = check_expr val_e fn_name locals fns
        check_block_after_expr ss fn_name locals fns immuts muts (TyUnit, snd_errs v_res)
      check_block_stmts_scoped ((StmtIndexAssign _ idxs val_e):ss) _ fn_name locals fns immuts muts =
        i_res = check_expr_list idxs fn_name locals fns
        v_res = check_expr val_e fn_name locals fns
        check_block_after_expr ss fn_name locals fns immuts muts (TyUnit, (snd_list_errs i_res) :: (snd_errs v_res))

fn :: check_block_after_mut String [RStmt] String [RTypeBind] [RTypeBind] [String] [String] (RType, [RTypeError]) => (RType, [RTypeError])
      check_block_after_mut name ss fn_name locals fns immuts muts (v_ty, v_errs) =
        locals1 = bind_let_var name v_ty locals
        more = check_block_stmts_scoped ss v_ty fn_name locals1 fns immuts (add_unique_str name muts)
        prepend_type_errs v_errs more

fn :: check_immut_reassign String String  [String] [String] => [RTypeError]
      check_immut_reassign "_"    _       _        _        =  []
      check_immut_reassign name   fn_name immuts   muts
        | str_in_list name muts = []
        | str_in_list name immuts = [TypeError fn_name ("cannot reassign immutable variable '" + name + "'; declare it with 'mut " + name + " = ...' first")]
        | otherwise = []

fn :: check_block_after_let String [RStmt] String [RTypeBind] [RTypeBind] [String] [String] (RType, [RTypeError]) => (RType, [RTypeError])
      check_block_after_let name ss fn_name locals fns immuts muts (v_ty, v_errs) =
        mut_err = check_immut_reassign name fn_name immuts muts
        locals1 = bind_let_var name v_ty locals
        more = check_block_stmts_scoped ss v_ty fn_name locals1 fns (add_unique_str name immuts) muts
        prepend_type_errs (v_errs :: mut_err) more

fn :: check_block_after_expr [RStmt] String [RTypeBind] [RTypeBind] [String] [String] (RType, [RTypeError]) => (RType, [RTypeError])
      check_block_after_expr ss fn_name locals fns immuts muts (e_ty, e_errs) =
        more = check_block_stmts_scoped ss e_ty fn_name locals fns immuts muts
        prepend_type_errs e_errs more

-- ── Function & Case Type Checking ───────────────────────────

fn :: is_empty_list_return_compat RType RType      => Bool
      is_empty_list_return_compat (TyList (TyVar "_empty")) (TyList _) = True
      is_empty_list_return_compat _     _          =  False

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

fn :: check_guard_cond_ty RType  String  Int => [RTypeError]
      check_guard_cond_ty TyBool _       _   =  []
      check_guard_cond_ty c_ty   fn_name idx =
        [TypeError fn_name ("guard #" + (int_to_str idx) + " condition has type " + (rtype_to_str c_ty) + ", expected Bool")]

fn :: check_guard_body_ty RType RType  String  Int => [RTypeError]
      check_guard_body_ty b_ty  ret_ty fn_name idx
        | (types_compatible b_ty ret_ty) OR (is_empty_list_return_compat b_ty ret_ty) = []
        | otherwise = [TypeError fn_name ("guard #" + (int_to_str idx) + " body has type " + (rtype_to_str b_ty) + ", expected " + (rtype_to_str ret_ty))]

fn :: check_case_body_ty (RType, [RTypeError]) RType  String  => [RTypeError]
      check_case_body_ty (b_ty, b_errs)        ret_ty fn_name
        | (types_compatible b_ty ret_ty) OR (is_empty_list_return_compat b_ty ret_ty) = b_errs
        | otherwise = b_errs :: [TypeError fn_name ("body has type " + (rtype_to_str b_ty) + ", expected " + (rtype_to_str ret_ty))]

fn :: pat_count [RPattern] => Int
      pat_count []         =  0
      pat_count (_:xs)     =  1 + (pat_count xs)

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

fn :: check_all_functions [String] [RFnDef] [RTypeBind] [RTypeBind] => [RTypeError]
      check_all_functions _ [] _ _ = []
      check_all_functions tnames ((FnDef name param_strs ret_str cases):fs) locals fns =
        param_tys = qualify_declared_adt_list tnames (parse_type_list_strs param_strs)
        ret_ty = qualify_declared_adt tnames (parse_type_str ret_str)
        (check_fn_cases cases name param_tys ret_ty 0 locals fns) :: (check_all_functions tnames fs locals fns)

fn :: convert_analysis_errors [RAnalysisError] => [RTypeError]
      convert_analysis_errors []               =  []
      convert_analysis_errors ((ErrWhereCycle fn_name var):es) =
        [TypeError fn_name ("CyclicWhereDependencyError on '" + var + "'")] :: (convert_analysis_errors es)
      convert_analysis_errors ((ErrParallelMutation fn_name var):es) =
        [TypeError fn_name ("ParallelMutationConflictError on '" + var + "'")] :: (convert_analysis_errors es)
      convert_analysis_errors ((ErrUseAfterSend fn_name var):es) =
        [TypeError fn_name ("UseAfterChannelSendError on '" + var + "'")] :: (convert_analysis_errors es)

fn :: builtin_typedefs => [RTypeDef]
      builtin_typedefs =
        [TypeDef "SysOs" [TypeVariant "Linux" [], TypeVariant "MacOS" [], TypeVariant "Windows" []] [], TypeDef "SysArch" [TypeVariant "X86_64" [], TypeVariant "Arm64" []] []]

fn :: typecheck_program RProgram => [RTypeError]
      typecheck_program (Program fdefs tdefs) =
        all_tdefs = builtin_typedefs :: tdefs
        tnames = collect_typedef_names all_tdefs
        env_pair = register_typedef_list tnames all_tdefs builtin_local_types builtin_fn_types
        typecheck_with_typedef_env tnames (Program fdefs tdefs) fdefs env_pair

fn :: typecheck_with_typedef_env [String] RProgram [RFnDef] ([RTypeBind], [RTypeBind]) => [RTypeError]
      typecheck_with_typedef_env tnames prog fdefs (locals, fns0) =
        fns = register_fndef_sigs tnames fdefs fns0
        ty_errs = check_all_functions tnames fdefs locals fns
        an_errs = convert_analysis_errors (analyze_program_errors prog)
        ty_errs :: an_errs

fn :: type_err_count [RTypeError] => Int
      type_err_count []           =  0
      type_err_count (_:xs)       =  1 + (type_err_count xs)

fn :: format_type_errors [RTypeError] => [String]
      format_type_errors []           =  []
      format_type_errors ((TypeError fn_name msg):es) =
        ["type error in function '" + fn_name + "': " + msg] :: (format_type_errors es)
