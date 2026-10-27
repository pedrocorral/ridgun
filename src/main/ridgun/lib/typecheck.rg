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
-- @implements FR-COMP-010
-- @implements FR-COMP-012
-- @implements FR-COMP-013
-- @implements FR-VM-001
-- @implements FR-VM-002
-- ============================================================
import ast
import lexer
import parser
import analyzer

-- ── String & Type Formatting Helpers ────────────────────────

fn :: trim leading spaces String Int Int => String
      trim leading spaces s pos len
        | pos >= len = ""
        | (str char at s pos) == 32 = trim leading spaces s (pos + 1) len
        | otherwise = str slice s pos len

fn :: trim str String => String
      trim str s      =  trim leading spaces s 0 (str len s)

fn :: split by comma loop String Int Int Int Int [String] => [String]
      split by comma loop s start pos len depth acc
        | pos >= len = acc :: [trim str (str slice s start len)]
        | (str char at s pos) == 40 OR (str char at s pos) == 91 = split by comma loop s start (pos + 1) len (depth + 1) acc
        | (str char at s pos) == 41 OR (str char at s pos) == 93 = split by comma loop s start (pos + 1) len (depth - 1) acc
        | depth == 0 AND (str char at s pos) == 44 = split by comma loop s (pos + 1) (pos + 1) len 0 (acc :: [trim str (str slice s start pos)])
        | otherwise = split by comma loop s start (pos + 1) len depth acc

fn :: split comma strs String => [String]
      split comma strs ""     =  []
      split comma strs s      =  split by comma loop s 0 0 (str len s) 0 []

fn :: ends with ellipsis String => Bool
      ends with ellipsis s      =
        len = str len s
        len > 3 AND (str slice s (len - 3) len) == "..."

fn :: parse type list strs [String] => [RType]
      parse type list strs []       =  []
      parse type list strs (s:ss)   =  [parse type str s] :: (parse type list strs ss)

fn :: is int type name String => Bool
      is int type name s      =
        s == "Int" OR s == "Byte" OR s == "U8" OR s == "U16" OR s == "U32" OR s == "U64" OR s == "I8" OR s == "I16" OR s == "I32" OR s == "I64" OR s == "Usize"

fn :: find fat arrow idx String Int Int => Int
      find fat arrow idx s pos len
        | (pos + 4) > len = -1
        | (str slice s pos (pos + 4)) == " => " = pos
        | otherwise = find fat arrow idx s (pos + 1) len

fn :: parse paren type inner String => RType
      parse paren type inner inner  =
        arrow_idx = find fat arrow idx inner 0 (str len inner)
        parse paren type split inner arrow_idx

fn :: finish paren tuple type [String]              => RType
      finish paren tuple type (single:[])           =  parse type str single
      finish paren tuple type ("Option":inner_s:[]) =  make option type (parse type str inner_s)
      finish paren tuple type parts                 =  TyTuple (parse type list strs parts)

fn :: parse paren type split String Int => RType
      parse paren type split inner -1 = finish paren tuple type (split comma strs inner)
      parse paren type split inner idx =
        lhs_s = str slice inner 0 idx
        rhs_s = str slice inner (idx + 4) (str len inner)
        TyFun (parse type list strs (split comma strs lhs_s)) (parse type str rhs_s)

fn :: parse type str String => RType
      parse type str s
        | ends with ellipsis s = TyVariadic (parse type str (str slice s 0 ((str len s) - 3)))
        | is int type name s = TyInt
        | s == "Real" OR s == "Float" = TyReal
        | s == "Char" = TyChar
        | s == "String" = TyString
        | s == "Bool" = TyBool
        | s == "Unit" OR s == "()" = TyUnit
        | s == "Actor" = TyVar "Agent"
        | s == "Tensor" OR s == "Tensor_GPU" = TyTensor []
        | str starts with s "Tensor(" = TyTensor (split comma strs (str slice s 7 ((str len s) - 1)))
        | str starts with s "[" = TyList (parse type str (str slice s 1 ((str len s) - 1)))
        | str starts with s "(" = parse paren type inner (str slice s 1 ((str len s) - 1))
        | otherwise = TyVar s

fn :: strip pipe suffix String Int Int => String
      strip pipe suffix s pos len
        | pos >= len = s
        | (str char at s pos) == 124 = str slice s 0 pos
        | otherwise = strip pipe suffix s (pos + 1) len

fn :: rtype to str RType              => String
      rtype to str TyInt              =  "Int"
      rtype to str TyReal             =  "Real"
      rtype to str TyChar             =  "Char"
      rtype to str TyString           =  "String"
      rtype to str TyBool             =  "Bool"
      rtype to str TyUnit             =  "()"
      rtype to str (TyList inner)     =  "[" + (rtype to str inner) + "]"
      rtype to str (TyTuple elems)    =  "(" + (rtype list to str elems) + ")"
      rtype to str (TyTensor [])      =  "Tensor"
      rtype to str (TyTensor dims)    =  "Tensor(" + (join comma strs dims) + ")"
      rtype to str (TyVariadic inner) =  (rtype to str inner) + "..."
      rtype to str (TyFun (TyUnit:[]) ret) = "(=> " + (rtype to str ret) + ")"
      rtype to str (TyFun [] ret)     =  "(=> " + (rtype to str ret) + ")"
      rtype to str (TyFun params ret) =  "(" + (rtype list to str params) + " => " + (rtype to str ret) + ")"
      rtype to str (TyVar name)
        | str starts with name "Option " =
          "Option " + (rtype to str (parse option inner ty (str slice name 7 (str len name))))
        | str starts with name "adt:" =
          raw = str slice name 4 (str len name)
          strip pipe suffix raw 0 (str len raw)
        | otherwise = name

fn :: rtype list to str [RType] => String
      rtype list to str []      =  ""
      rtype list to str (t:[])  =  rtype to str t
      rtype list to str (t:ts)  =  (rtype to str t) + ", " + (rtype list to str ts)

fn :: join comma strs [String] => String
      join comma strs []       =  ""
      join comma strs (s:[])   =  s
      join comma strs (s:ss)   =  s + ", " + (join comma strs ss)

-- ── Type Unification & Compatibility ────────────────────────

fn :: rtype list len [RType] => Int
      rtype list len []      =  0
      rtype list len (_:xs)  =  1 + (rtype list len xs)

fn :: dims compatible [String] [String] => Bool
      dims compatible []       []       =  True
      dims compatible (a:as)   (b:bs)
        | a == b OR a == "_" OR b == "_" OR (is lower ident a) OR (is lower ident b) = dims compatible as bs
        | otherwise = False
      dims compatible _        _        =  False

fn :: tensor dims unify [String] [String] => Bool
      tensor dims unify []       _        =  True
      tensor dims unify _        []       =  True
      tensor dims unify d1       d2
        | (str list count d1) == (str list count d2) = dims compatible d1 d2
        | otherwise = False

fn :: types list compatible [RType] [RType] => Bool
      types list compatible []      []      =  True
      types list compatible (a:as)  (b:bs)
        | types compatible a b = types list compatible as bs
        | otherwise = False
      types list compatible _       _       =  False

fn :: is poly type var String => Bool
      is poly type var s
        | s == "adt:Option" = True
        | str starts with s "adt:" = False
        | s == "_empty" OR s == "_any" OR s == "Option" OR s == "_chan_or_agent" = True
        | (str len s) == 1 = True
        | otherwise = False

fn :: parse option inner ty String => RType
      parse option inner ty s
        | str starts with s "adt:" = TyVar s
        | otherwise = parse type str s

fn :: make option type RType     => RType
      make option type (TyVar s) =  TyVar ("Option " + s)
      make option type other     =  TyVar ("Option " + (rtype to str other))

fn :: adt accepts prim String RType    => Bool
      adt accepts prim a      TyInt    =  str contains a "|prim:Int"
      adt accepts prim a      TyReal   =  str contains a "|prim:Real"
      adt accepts prim a      TyString =  str contains a "|prim:String"
      adt accepts prim a      TyChar   =  str contains a "|prim:String"
      adt accepts prim a      TyBool   =  str contains a "|prim:Bool"
      adt accepts prim _      _        =  False

fn :: types compatible RType              RType              => Bool
      types compatible TyInt              TyInt              =  True
      types compatible TyReal             TyReal             =  True
      types compatible TyChar             TyChar             =  True
      types compatible TyChar             TyString           =  True
      types compatible TyString           TyChar             =  True
      types compatible TyString           TyString           =  True
      types compatible TyBool             TyBool             =  True
      types compatible TyUnit             TyUnit             =  True
      types compatible (TyTensor d1)      (TyTensor d2)      =  tensor dims unify d1 d2
      types compatible (TyVariadic inner) other              =
        (types compatible inner other) OR (types compatible (TyList inner) other)
      types compatible other              (TyVariadic inner) =
        (types compatible inner other) OR (types compatible (TyList inner) other)
      types compatible (TyVar a)          (TyVar b)
        | a == b OR ("adt:" + a) == b OR ("adt:" + b) == a = True
        | (is poly type var a) OR (is poly type var b) = True
        | (str starts with a "Option ") AND (str starts with b "Option ") = types compatible (parse option inner ty (str slice a 7 (str len a))) (parse option inner ty (str slice b 7 (str len b)))
        | (str starts with a "Option ") AND (str starts with b "adt:Option") = True
        | (str starts with a "adt:Option") AND (str starts with b "Option ") = True
        | (str starts with a "adt:") AND (str starts with b "adt:") AND ((str contains a b) OR (str contains b a) OR (str contains a ("adt:" + (rtype to str (TyVar b)))) OR (str contains b ("adt:" + (rtype to str (TyVar a))))) = True
        | otherwise = False
      types compatible (TyVar "Agent")    (TyTuple ((TyVar "Agent"):_)) = True
      types compatible (TyTuple ((TyVar "Agent"):_)) (TyVar "Agent") = True
      types compatible (TyVar a)          other
        | is poly type var a = True
        | (str starts with a "adt:") AND (adt accepts prim a other) = True
        | otherwise = False
      types compatible other              (TyVar b)
        | is poly type var b = True
        | (str starts with b "adt:") AND (adt accepts prim b other) = True
        | otherwise = False
      types compatible (TyList a)         (TyList b)         =  types compatible a b
      types compatible (TyTuple as)       (TyTuple bs)
        | (rtype list len as) == (rtype list len bs) = types list compatible as bs
        | otherwise = False
      types compatible (TyFun p1 r1)      (TyFun p2 r2)
        | (rtype list len p1) == (rtype list len p2) AND (types list compatible p1 p2) = types compatible r1 r2
        | otherwise = False
      types compatible _                  _                  =  False

-- ── Type Environment Lookup & Registration ──────────────────

fn :: embedded variant tag RVariant => String
      embedded variant tag (TypeVariant c (a:[]))
        | c != a = ""
        | is int type name c = "|prim:Int"
        | c == "Real" OR c == "Float" = "|prim:Real"
        | c == "String" OR c == "Char" = "|prim:String"
        | c == "Bool" = "|prim:Bool"
        | otherwise = "|adt:" + c
      embedded variant tag _        =  ""

fn :: collect embedded tags [RVariant] => String
      collect embedded tags []         =  ""
      collect embedded tags (v:vs)     =  (embedded variant tag v) + (collect embedded tags vs)

fn :: poly tag for tdef [RVariant] [RField] => String
      poly tag for tdef vars fields
        | (str list count (collect poly vars in fields fields (collect poly vars in variants vars []))) > 0 = "|poly"
        | otherwise = ""

fn :: collect typedef names [RTypeDef] => [String]
      collect typedef names []         =  []
      collect typedef names ((TypeDef name vars fields):ts) =
        [(name + (collect embedded tags vars) + (poly tag for tdef vars fields))] :: (collect typedef names ts)

fn :: lookup declared adt entry [String] String => String
      lookup declared adt entry [] _ = ""
      lookup declared adt entry (e:es) target
        | e == target OR (str starts with e (target + "|")) = e
        | otherwise = lookup declared adt entry es target

fn :: qualify declared adt [String] RType              => RType
      qualify declared adt tnames   (TyVar s)
        | str starts with s "Option " = make option type (qualify declared adt tnames (parse type str (str slice s 7 (str len s))))
        | (lookup declared adt entry tnames s) != "" = TyVar ("adt:" + (lookup declared adt entry tnames s))
        | otherwise = TyVar s
      qualify declared adt tnames   (TyList inner)     =  TyList (qualify declared adt tnames inner)
      qualify declared adt tnames   (TyTuple ((TyVar head_s):rest))
        | str contains (lookup declared adt entry tnames head_s) "|poly" = TyVar ("adt:" + (lookup declared adt entry tnames head_s))
        | otherwise = TyTuple (qualify declared adt list tnames ([TyVar head_s] :: rest))
      qualify declared adt tnames   (TyTuple elems)    =  TyTuple (qualify declared adt list tnames elems)
      qualify declared adt tnames   (TyVariadic inner) =  TyVariadic (qualify declared adt tnames inner)
      qualify declared adt tnames   (TyFun params ret) =  TyFun (qualify declared adt list tnames params) (qualify declared adt tnames ret)
      qualify declared adt _        other              =  other

fn :: qualify declared adt list [String] [RType] => [RType]
      qualify declared adt list _ [] = []
      qualify declared adt list tnames (t:ts) = [qualify declared adt tnames t] :: (qualify declared adt list tnames ts)

fn :: lookup type bind [RTypeBind] String => Bool RType
      lookup type bind []          _      =  (False, TyInt)
      lookup type bind ((TypeBind k ty):rest) target
        | k == target = (True, ty)
        | otherwise = lookup type bind rest target

fn :: put type bind [RTypeBind] String RType => [RTypeBind]
      put type bind env k ty = [TypeBind k ty] :: env

fn :: builtin local types => [RTypeBind]
      builtin local types =
        [TypeBind "new_mailbox" TyInt, TypeBind "mailbox" TyInt, TypeBind "new_channel" TyInt, TypeBind "channel" TyInt, TypeBind "cli_args" (TyList TyString), TypeBind "sys_os" (TyVar "adt:SysOs"), TypeBind "sys_arch" (TyVar "adt:SysArch"), TypeBind "sys_getcwd" TyString, TypeBind "sys_getuid" TyInt, TypeBind "sys_getgid" TyInt, TypeBind "sys_getpid" TyInt, TypeBind "sys_pipe" (TyTuple [TyInt, TyInt]), TypeBind "sys_time_ms" TyInt, TypeBind "sys_deadline_ms" TyInt, TypeBind "sys_remaining_ms" TyInt, TypeBind "cmm_live_blocks" TyInt, TypeBind "cmm_cond_spared" TyInt, TypeBind "cmm_cond_freed" TyInt]

fn :: builtin fn types => [RTypeBind]
      builtin fn types =
        [TypeBind "cli_args" (TyFun [] (TyList TyString)), TypeBind "new_mailbox" (TyFun [] TyInt), TypeBind "new_channel" (TyFun [] TyInt), TypeBind "stop" (TyFun [TyVar "Agent"] TyUnit), TypeBind "agent_alive" (TyFun [TyVar "Agent"] TyBool), TypeBind "send_to" (TyFun [TyVar "A", TyVar "Agent"] TyUnit), TypeBind "ask_to" (TyFun [TyVar "A", TyVar "Agent"] (TyVar "B")), TypeBind "new_bounded_channel" (TyFun [TyInt] TyInt), TypeBind "send_through" (TyFun [TyVar "A", TyInt] TyUnit), TypeBind "chan_send" (TyFun [TyVar "A", TyInt] TyUnit), TypeBind "receive_from" (TyFun [TyVar "_chan_or_agent"] (TyVar "A")), TypeBind "chan_recv" (TyFun [TyInt] (TyVar "A")), TypeBind "try_receive_from" (TyFun [TyVar "_chan_or_agent"] (TyVar "Option")), TypeBind "chan_try_recv" (TyFun [TyInt] (TyVar "Option")), TypeBind "receive_from_timeout" (TyFun [TyInt, TyInt] (TyVar "Option")), TypeBind "str_len" (TyFun [TyString] TyInt), TypeBind "str_char_at" (TyFun [TyString, TyInt] TyInt), TypeBind "str_slice" (TyFun [TyString, TyInt, TyInt] TyString), TypeBind "char_from_code" (TyFun [TyInt] TyString), TypeBind "str_concat" (TyFun [TyString, TyString] TyString), TypeBind "int_to_str" (TyFun [TyInt] TyString), TypeBind "str_to_int" (TyFun [TyString] TyInt), TypeBind "str_starts_with" (TyFun [TyString, TyString] TyBool), TypeBind "str_contains" (TyFun [TyString, TyString] TyBool), TypeBind "read_file" (TyFun [TyString] TyString), TypeBind "load_rg_source" (TyFun [TyString] TyString), TypeBind "read_bytes" (TyFun [TyString] (TyList TyInt)), TypeBind "write_bytes" (TyFun [TyString, TyList TyInt] TyUnit), TypeBind "write_file" (TyFun [TyString, TyString] TyUnit), TypeBind "shell_exec" (TyFun [TyString] TyInt), TypeBind "map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "seq_map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "||map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "par_map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "seq_filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "||filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "par_filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "fold" (TyFun [TyFun [TyVar "B", TyVar "A"] (TyVar "B"), TyVar "B", TyList (TyVar "A")] (TyVar "B")), TypeBind "list_dir" (TyFun [TyString] (TyList TyString)), TypeBind "file_lstat" (TyFun [TyString] (TyTuple [TyBool, TyString, TyInt, TyInt, TyInt, TyString, TyString, TyInt, TyString])), TypeBind "sha256_file" (TyFun [TyString] TyString), TypeBind "sha256_str" (TyFun [TyString] TyString), TypeBind "sha256_raw" (TyFun [TyString] TyString), TypeBind "sha256_bytes" (TyFun [TyString] TyString), TypeBind "sys_os" (TyFun [] (TyVar "adt:SysOs")), TypeBind "sys_arch" (TyFun [] (TyVar "adt:SysArch")), TypeBind "sys_mkdir" (TyFun [TyString, TyInt] TyInt), TypeBind "sys_chmod" (TyFun [TyString, TyInt] TyInt), TypeBind "sys_exec" (TyFun [TyString, TyList TyString, TyList TyString] TyInt), TypeBind "sys_chdir" (TyFun [TyString] TyInt), TypeBind "sys_getcwd" (TyFun [] TyString), TypeBind "sys_getenv" (TyFun [TyString] TyString), TypeBind "sys_setenv" (TyFun [TyString, TyString] TyInt), TypeBind "sys_exit" (TyFun [TyInt] TyUnit), TypeBind "sys_getuid" (TyFun [] TyInt), TypeBind "sys_getgid" (TyFun [] TyInt), TypeBind "sys_getpid" (TyFun [] TyInt), TypeBind "sys_time_ms" (TyFun [] TyInt), TypeBind "sys_deadline_ms" (TyFun [] TyInt), TypeBind "sys_remaining_ms" (TyFun [] TyInt), TypeBind "sys_sleep_ms" (TyFun [TyInt] TyUnit), TypeBind "sys_open_mode" (TyFun [TyString, TyString] TyInt), TypeBind "sys_open" (TyFun [TyString, TyInt, TyInt] TyInt), TypeBind "sys_close" (TyFun [TyInt] TyInt), TypeBind "sys_read_fd" (TyFun [TyInt, TyInt] TyString), TypeBind "sys_write_fd" (TyFun [TyInt, TyString] TyInt), TypeBind "sys_poll" (TyFun [TyInt, TyInt, TyInt] TyInt), TypeBind "sys_terminate" (TyFun [TyInt, TyBool] TyInt), TypeBind "sys_kill" (TyFun [TyInt, TyInt] TyInt), TypeBind "sys_call" (TyFun [TyInt, TyInt, TyInt, TyInt, TyInt, TyInt, TyInt] TyInt), TypeBind "sys_pipe" (TyFun [] (TyTuple [TyInt, TyInt])), TypeBind "sys_waitpid" (TyFun [TyInt, TyInt] (TyTuple [TyInt, TyInt])), TypeBind "sys_username" (TyFun [TyInt] TyString), TypeBind "sys_user_groups" (TyFun [TyString] (TyList TyString)), TypeBind "sys_lookup_uid_gid" (TyFun [TyString] (TyTuple [TyInt, TyInt])), TypeBind "sys_setresgid" (TyFun [TyInt] TyInt), TypeBind "sys_setgroups" (TyFun [TyList TyInt] TyInt), TypeBind "sys_setresuid" (TyFun [TyInt] TyInt), TypeBind "sys_execve" (TyFun [TyString, TyList TyString, TyList TyString] TyInt), TypeBind "sys_read_pass" (TyFun [TyString] TyString), TypeBind "cmm_live_blocks" (TyFun [] TyInt), TypeBind "cmm_cond_spared" (TyFun [] TyInt), TypeBind "cmm_cond_freed" (TyFun [] TyInt), TypeBind "cmm_same_ptr" (TyFun [TyVar "A", TyVar "A"] TyBool)]

fn :: join adt ret ty RType RType => RType
      join adt ret ty (TyVar a) (TyVar b)
        | (str starts with a "adt:") AND (str starts with b "adt:") AND (NOT (str contains a b)) = TyVar (a + "|" + b)
        | otherwise = TyVar a
      join adt ret ty a _ = a

fn :: put ctor local bind [RTypeBind] String RType => [RTypeBind]
      put ctor local bind locals ctor adt_ty =
        prev = lookup type bind locals ctor
        put ctor local step locals ctor adt_ty prev

fn :: put ctor local step [RTypeBind] String RType (Bool, RType) => [RTypeBind]
      put ctor local step locals ctor adt_ty (True, prev_ty) =
        put type bind locals ctor (join adt ret ty prev_ty adt_ty)
      put ctor local step locals ctor adt_ty (False, _) =
        put type bind locals ctor adt_ty

fn :: register variants [String] String [RVariant] RType [RTypeBind] [RTypeBind] => [RTypeBind] [RTypeBind]
      register variants _ _ [] _ locals fns = (locals, fns)
      register variants tnames tdef_name ((TypeVariant ctor []):vs) adt_ty locals fns =
        locals1 = put ctor local bind locals ctor adt_ty
        locals2 = put ctor local bind locals1 (tdef_name + "." + ctor) adt_ty
        register variants tnames tdef_name vs adt_ty locals2 fns
      register variants tnames tdef_name ((TypeVariant ctor arg_strs):vs) adt_ty locals fns =
        arg_tys = qualify declared adt list tnames (parse type list strs arg_strs)
        fns1 = put type bind fns ctor (TyFun arg_tys adt_ty)
        fns2 = put type bind fns1 (tdef_name + "." + ctor) (TyFun arg_tys adt_ty)
        register variants tnames tdef_name vs adt_ty locals fns2

fn :: collect field types [String] [RField] => [RType]
      collect field types _        []       =  []
      collect field types tnames   ((TypeField _ fty_str):fs) =
        [qualify declared adt tnames (parse type str fty_str)] :: (collect field types tnames fs)

fn :: register field accessors [String] [RField] RType [RTypeBind] => [RTypeBind]
      register field accessors _ [] _ fns = fns
      register field accessors tnames ((TypeField fname fty_str):fs) adt_ty fns =
        fty = qualify declared adt tnames (parse type str fty_str)
        fns1 = put type bind fns fname (TyFun [adt_ty] fty)
        fns2 = put base field bind fname adt_ty fty fns1
        register field accessors tnames fs adt_ty fns2

fn :: put base field bind String RType RType [RTypeBind] => [RTypeBind]
      put base field bind fname adt_ty fty fns
        | str contains fname "." = put type bind fns (ident base name fname) (TyFun [adt_ty] fty)
        | otherwise = fns

fn :: register typedef [String] RTypeDef [RTypeBind] [RTypeBind] => [RTypeBind] [RTypeBind]
      register typedef tnames (TypeDef name vars []) locals fns =
        adt_ty = qualify declared adt tnames (parse type str name)
        register variants tnames name vars adt_ty locals fns
      register typedef tnames (TypeDef name vars fields) locals fns =
        adt_ty = qualify declared adt tnames (parse type str name)
        v_res = register variants tnames name vars adt_ty locals fns
        register record helpers tnames name adt_ty fields v_res

fn :: register record helpers [String] String RType [RField] ([RTypeBind], [RTypeBind]) => [RTypeBind] [RTypeBind]
      register record helpers tnames name adt_ty fields (locals, fns) =
        ctor_arg_tys = collect field types tnames fields
        fns1 = put type bind fns name (TyFun ctor_arg_tys adt_ty)
        fns2 = register field accessors tnames fields adt_ty fns1
        (locals, fns2)

fn :: register typedef list [String] [RTypeDef] [RTypeBind] [RTypeBind] => [RTypeBind] [RTypeBind]
      register typedef list _ [] locals fns = (locals, fns)
      register typedef list tnames (t:ts) locals fns =
        r1 = register typedef tnames t locals fns
        register typedef list cont tnames ts r1

fn :: register typedef list cont [String] [RTypeDef] ([RTypeBind], [RTypeBind]) => [RTypeBind] [RTypeBind]
      register typedef list cont tnames ts (locals1, fns1) =
        register typedef list tnames ts locals1 fns1

fn :: register fndef sigs acc [String] [RFnDef] [RTypeBind] => [RTypeBind]
      register fndef sigs acc _ [] acc = acc
      register fndef sigs acc tnames ((FnDef name param_strs ret_str _):fs) acc =
        param_tys = qualify declared adt list tnames (parse type list strs param_strs)
        ret_ty = qualify declared adt tnames (parse type str ret_str)
        register fndef sigs acc tnames fs (acc :: [TypeBind name (TyFun param_tys ret_ty)])

fn :: register fndef sigs [String] [RFnDef] [RTypeBind] => [RTypeBind]
      register fndef sigs tnames fdefs fns0 =
        (register fndef sigs acc tnames fdefs []) :: fns0

-- ── Pattern Variable Binding ────────────────────────────────

fn :: rtype at [RType] Int => RType
      rtype at (t:_)   0   =  t
      rtype at (_:ts)  idx =  rtype at ts (idx - 1)
      rtype at []      _   =  TyInt

fn :: unwrap variadic param RType              => RType
      unwrap variadic param (TyVariadic inner) =  TyList inner
      unwrap variadic param other              =  other

fn :: has seq bind pat [RPattern]         => Bool
      has seq bind pat []                 =  False
      has seq bind pat ((PatSeqBind _):_) =  True
      has seq bind pat (_:ps)             =  has seq bind pat ps

fn :: ctor param types [RTypeBind] String    => [RType]
      ctor param types fns         ctor_name =
        extract fun params (lookup type bind fns ctor_name)

fn :: extract fun params (Bool, RType) => [RType]
      extract fun params (True, (TyFun params _)) = params
      extract fun params _             =  []

fn :: pat list arity [RPattern] => Int
      pat list arity []         =  0
      pat list arity (_:xs)     =  1 + (pat list arity xs)

fn :: lookup ctor for type [RTypeBind] String RType Int => Bool [RType]
      lookup ctor for type [] _ _ _ = (False, [])
      lookup ctor for type ((TypeBind k (TyFun params ret_ty)):rest) target expected arity
        | k == target AND (rtype list len params) == arity AND (types compatible ret_ty expected) = (True, params)
        | otherwise = lookup ctor for type rest target expected arity
      lookup ctor for type (_:rest) target expected arity =
        lookup ctor for type rest target expected arity

fn :: lookup ctor by arity [RTypeBind] String Int => Bool [RType]
      lookup ctor by arity [] _ _ = (False, [])
      lookup ctor by arity ((TypeBind k (TyFun params _)):rest) target arity
        | k == target AND (rtype list len params) == arity = (True, params)
        | otherwise = lookup ctor by arity rest target arity
      lookup ctor by arity (_:rest) target arity =
        lookup ctor by arity rest target arity

fn :: ctor param types for [RTypeBind] String RType Int => [RType]
      ctor param types for fns ctor_name expected arity =
        by_ty = lookup ctor for type fns ctor_name expected arity
        ctor param types fallback fns ctor_name arity by_ty

fn :: ctor param types fallback [RTypeBind] String Int (Bool, [RType]) => [RType]
      ctor param types fallback _ _ _ (True, params) = params
      ctor param types fallback fns ctor_name arity (False, _) =
        by_ar = lookup ctor by arity fns ctor_name arity
        ctor param types arity fallback fns ctor_name by_ar

fn :: ctor param types arity fallback [RTypeBind] String (Bool, [RType]) => [RType]
      ctor param types arity fallback _ _ (True, params) = params
      ctor param types arity fallback fns ctor_name (False, _) =
        ctor param types fns ctor_name

fn :: tensor pat expected RType        => RType
      tensor pat expected (TyTensor d) =  TyTensor d
      tensor pat expected _            =  TyTensor []

fn :: bind int pats [RPattern] [RTypeBind] [RTypeBind] => [RTypeBind]
      bind int pats [] locals _ = locals
      bind int pats (p:ps) locals fns =
        locals1 = bind pattern p TyInt locals fns
        bind int pats ps locals1 fns

fn :: bind pattern RPattern RType [RTypeBind] [RTypeBind] => [RTypeBind]
      bind pattern (PatVar v) expected locals _ =
        put type bind locals v expected
      bind pattern (PatSeqBind v) _ locals _ =
        put type bind locals v TyInt
      bind pattern (PatCons h t) (TyList elem_ty) locals fns =
        locals1 = bind pattern h elem_ty locals fns
        bind pattern t (TyList elem_ty) locals1 fns
      bind pattern (PatTuple pats) (TyTuple tys) locals fns =
        bind tuple pats pats tys 0 locals fns
      bind pattern (PatCtor ":tensor-pat:" (t_pat:dim_pats)) expected locals fns =
        locals1 = bind pattern t_pat (tensor pat expected expected) locals fns
        bind int pats dim_pats locals1 fns
      bind pattern (PatCtor "Some" (sub_p:[])) (TyVar opt_s) locals fns
        | str starts with opt_s "Option " =
          bind pattern sub_p (parse option inner ty (str slice opt_s 7 (str len opt_s))) locals fns
      bind pattern (PatCtor ctor_name args) expected locals fns =
        param_tys = ctor param types for fns ctor_name expected (pat list arity args)
        bind tuple pats args param_tys 0 locals fns
      bind pattern _ _ locals _ = locals

fn :: bind tuple pats [RPattern] [RType] Int [RTypeBind] [RTypeBind] => [RTypeBind]
      bind tuple pats [] _ _ locals _ = locals
      bind tuple pats (p:ps) tys idx locals fns =
        pty = rtype at tys idx
        locals1 = bind pattern p pty locals fns
        bind tuple pats ps tys (idx + 1) locals1 fns

fn :: bind case patterns [RPattern] [RType] Bool Int [RTypeBind] [RTypeBind] => [RTypeBind]
      bind case patterns [] _ _ _ locals _ = locals
      bind case patterns ((PatSeqBind v):[]) param_tys True _ locals _ =
        put type bind locals v (TyTuple param_tys)
      bind case patterns (p:ps) param_tys True idx locals fns =
        locals1 = bind pattern p TyInt locals fns
        bind case patterns ps param_tys True (idx + 1) locals1 fns
      bind case patterns (p:ps) param_tys False idx locals fns =
        expected = unwrap variadic param (rtype at param_tys idx)
        locals1 = bind pattern p expected locals fns
        bind case patterns ps param_tys False (idx + 1) locals1 fns

-- ── Symbolic Tensor Dimension Unification (Einsum & Calls) ──

fn :: lookup dim bind [RDimBind] String => Bool String
      lookup dim bind []         _      =  (False, "")
      lookup dim bind ((DimBind k v):rest) target
        | k == target = (True, v)
        | otherwise = lookup dim bind rest target

fn :: bind or check dims [String] [String] String String [RDimBind] => [RDimBind] [RTypeError]
      bind or check dims [] _ _ _ dim_env = (dim_env, [])
      bind or check dims _ [] _ _ dim_env = (dim_env, [])
      bind or check dims (ad:ads) (pd:pds) callee fn_name dim_env =
        step_res = check single dim ad pd callee fn_name (lookup dim bind dim_env pd) dim_env
        bind or check dims cont ads pds callee fn_name step_res

fn :: check single dim String String String String (Bool, String) [RDimBind] => [RDimBind] [RTypeError]
      check single dim ad pd callee fn_name (True, bound) dim_env
        | pd == "_" OR ad == "_" = (dim_env, [])
        | bound != ad = (dim_env, [TypeError fn_name ("tensor dimension mismatch in call to '" + callee + "': symbolic dim '" + pd + "' bound to both '" + bound + "' and '" + ad + "'")])
        | otherwise = (dim_env, [])
      check single dim ad pd _ _ (False, _) dim_env
        | pd == "_" OR ad == "_" = (dim_env, [])
        | otherwise = ([DimBind pd ad] :: dim_env, [])

fn :: bind or check dims cont [String] [String] String String ([RDimBind], [RTypeError]) => [RDimBind] [RTypeError]
      bind or check dims cont ads pds callee fn_name (dim_env1, errs1) =
        more = bind or check dims ads pds callee fn_name dim_env1
        merge dim errs errs1 more

fn :: merge dim errs [RTypeError] ([RDimBind], [RTypeError]) => [RDimBind] [RTypeError]
      merge dim errs errs1 (dim_env2, errs2) = (dim_env2, errs1 :: errs2)

fn :: sub chars to strs String Int Int => [String]
      sub chars to strs s pos len
        | pos >= len = []
        | otherwise = [str slice s pos (pos + 1)] :: (sub chars to strs s (pos + 1) len)

fn :: check einsum terms [RExpr] [String] String [RTypeBind] [RTypeBind] [RDimBind] => [RDimBind] [RTypeError]
      check einsum terms [] _ _ _ _ dim_env = (dim_env, [])
      check einsum terms _ [] _ _ _ dim_env = (dim_env, [])
      check einsum terms (e:es) (sub:subs) fn_name locals fns dim_env =
        e_res = check expr e fn_name locals fns
        step = check einsum one e_res sub fn_name dim_env
        check einsum cont es subs fn_name locals fns step

fn :: check einsum one (RType, [RTypeError]) String String [RDimBind] => [RDimBind] [RTypeError]
      check einsum one ((TyTensor dims), errs1) sub fn_name dim_env
        | (str list count dims) > 0 AND (str list count dims) == (str len sub) = merge dim errs errs1 (bind or check dims dims (sub chars to strs sub 0 (str len sub)) "einsum" fn_name dim_env)
        | otherwise = (dim_env, errs1)
      check einsum one (_, errs1) _ _ dim_env = (dim_env, errs1)

fn :: check einsum cont [RExpr] [String] String [RTypeBind] [RTypeBind] ([RDimBind], [RTypeError]) => [RDimBind] [RTypeError]
      check einsum cont es subs fn_name locals fns (dim_env1, errs1) =
        more = check einsum terms es subs fn_name locals fns dim_env1
        merge dim errs errs1 more

-- ── Binary Operator Type Checking ───────────────────────────

fn :: is poly tyvar RType     => Bool
      is poly tyvar (TyVar s) =  (is lower ident s) OR (is poly type var s)
      is poly tyvar _         =  False

fn :: is int or poly RType => Bool
      is int or poly TyInt =  True
      is int or poly t     =  is poly tyvar t

fn :: is real or poly RType  => Bool
      is real or poly TyReal =  True
      is real or poly t      =  is poly tyvar t

fn :: is str or poly RType    => Bool
      is str or poly TyString =  True
      is str or poly t        =  is poly tyvar t

fn :: binop symbol RBinOp => String
      binop symbol OpAdd  =  "+"
      binop symbol OpSub  =  "-"
      binop symbol OpMul  =  "*"
      binop symbol OpDiv  =  "/"
      binop symbol OpMod  =  "%"
      binop symbol OpAnd  =  "and"
      binop symbol OpOr   =  "or"
      binop symbol OpXor  =  "xor"
      binop symbol OpShl  =  "shl"
      binop symbol OpShr  =  "shr"
      binop symbol OpRotr =  "rotr"
      binop symbol OpRotl =  "rotl"
      binop symbol _      =  ""

fn :: check overloaded arith RBinOp RType RType [RTypeBind] String => RType [RTypeError]
      check overloaded arith bop l_ty r_ty fns fn_name =
        sym = binop symbol bop
        check overload lookup sym l_ty r_ty (lookup type bind fns sym) fn_name

fn :: check overload lookup String RType RType (Bool, RType) String => RType [RTypeError]
      check overload lookup _ l_ty r_ty (True, (TyFun (p1:p2:[]) ret_ty)) _
        | (types compatible l_ty p1) AND (types compatible r_ty p2) = (ret_ty, [])
      check overload lookup sym l_ty r_ty _ fn_name =
        (TyInt, [TypeError fn_name ("arithmetic operator " + sym + " requires numeric or overloaded operands, got " + (rtype to str l_ty) + " and " + (rtype to str r_ty))])

fn :: check arith binop RBinOp RType RType [RTypeBind] String => RType [RTypeError]
      check arith binop _ (TyTensor d1) (TyTensor _) _ _ = (TyTensor d1, [])
      check arith binop bop l_ty r_ty fns fn_name
        | (is int or poly l_ty) AND (is int or poly r_ty) = (TyInt, [])
        | (is real or poly l_ty) AND (is real or poly r_ty) = (TyReal, [])
        | bop == OpAdd AND (is str or poly l_ty) AND (is str or poly r_ty) = (TyString, [])
        | otherwise = check overloaded arith bop l_ty r_ty fns fn_name

fn :: check matmul binop RType RType String => RType [RTypeError]
      check matmul binop (TyTensor (d1a:d1b:[])) (TyTensor (d2a:d2b:[])) fn_name
        | d1b != d2a = (TyTensor [d1a, d2b], [TypeError fn_name ("tensor contraction dimension mismatch: " + d1b + " vs " + d2a)])
        | otherwise = (TyTensor [d1a, d2b], [])
      check matmul binop _ _ _ = (TyTensor [], [])

fn :: check concat binop RType RType String => RType [RTypeError]
      check concat binop (TyList (TyVar "_empty")) (TyList r_elem) _ = (TyList r_elem, [])
      check concat binop (TyList l_elem) (TyList (TyVar "_empty")) _ = (TyList l_elem, [])
      check concat binop (TyList l_elem) (TyList r_elem) fn_name
        | types compatible l_elem r_elem = (TyList l_elem, [])
        | otherwise = (TyList l_elem, [TypeError fn_name ("concatenation requires same list element types, got [" + (rtype to str l_elem) + "] and [" + (rtype to str r_elem) + "]")])
      check concat binop l_ty r_ty fn_name =
        (TyList TyInt, [TypeError fn_name ("concatenation (::) requires list operands, got " + (rtype to str l_ty) + " and " + (rtype to str r_ty))])

fn :: check binop RBinOp RType RType [RTypeBind] String => RType [RTypeError]
      check binop OpAdd l r fns fn_name = check arith binop OpAdd l r fns fn_name
      check binop OpSub l r fns fn_name = check arith binop OpSub l r fns fn_name
      check binop OpMul l r fns fn_name = check arith binop OpMul l r fns fn_name
      check binop OpDiv l r fns fn_name = check arith binop OpDiv l r fns fn_name
      check binop OpMod l r fns fn_name = check arith binop OpMod l r fns fn_name
      check binop OpShl l r fns fn_name = check arith binop OpShl l r fns fn_name
      check binop OpShr l r fns fn_name = check arith binop OpShr l r fns fn_name
      check binop OpRotr l r fns fn_name = check arith binop OpRotr l r fns fn_name
      check binop OpRotl l r fns fn_name = check arith binop OpRotl l r fns fn_name
      check binop OpMatMul l r _ fn_name = check matmul binop l r fn_name
      check binop OpFlatJoin l (TyList (TyVar "_empty")) _ _ = (TyList l, [])
      check binop OpFlatJoin l (TyList r_elem) _ fn_name
        | types compatible l r_elem = (TyList r_elem, [])
        | otherwise = (TyList r_elem, [TypeError fn_name ("cons (:) requires element type compatible with list, got " + (rtype to str l) + " and [" + (rtype to str r_elem) + "]")])
      check binop OpFlatJoin l _ _ _ = (TyList l, [])
      check binop OpConcat l r _ fn_name = check concat binop l r fn_name
      check binop OpEq l r _ fn_name
        | types compatible l r = (TyBool, [])
        | otherwise = (TyBool, [TypeError fn_name ("equality comparison requires compatible types, got " + (rtype to str l) + " and " + (rtype to str r))])
      check binop OpNeq l r _ fn_name
        | types compatible l r = (TyBool, [])
        | otherwise = (TyBool, [TypeError fn_name ("equality comparison requires compatible types, got " + (rtype to str l) + " and " + (rtype to str r))])
      check binop OpAnd l r fns fn_name
        | (types compatible l TyBool) AND (types compatible r TyBool) = (TyBool, [])
        | (is int or poly l) AND (is int or poly r) = (TyInt, [])
        | (types compatible l (TyTensor [])) AND (types compatible r (TyTensor [])) = (l, [])
        | otherwise = check overloaded arith OpAnd l r fns fn_name
      check binop OpOr l r fns fn_name
        | (types compatible l TyBool) AND (types compatible r TyBool) = (TyBool, [])
        | (is int or poly l) AND (is int or poly r) = (TyInt, [])
        | (types compatible l (TyTensor [])) AND (types compatible r (TyTensor [])) = (l, [])
        | otherwise = check overloaded arith OpOr l r fns fn_name
      check binop OpXor l r fns fn_name
        | (types compatible l TyBool) AND (types compatible r TyBool) = (TyBool, [])
        | (is int or poly l) AND (is int or poly r) = (TyInt, [])
        | (types compatible l (TyTensor [])) AND (types compatible r (TyTensor [])) = (l, [])
        | otherwise = check overloaded arith OpXor l r fns fn_name
      check binop _ l r _ fn_name
        | (types compatible l TyInt AND types compatible r TyInt) OR (types compatible l TyReal AND types compatible r TyReal) OR (types compatible l TyChar AND types compatible r TyChar) = (TyBool, [])
        | otherwise = (TyBool, [TypeError fn_name ("comparison operator requires numeric operands, got " + (rtype to str l) + " and " + (rtype to str r))])

-- ── Expression & Call Type Checking ─────────────────────────

fn :: count char in str String Int Int Int => Int
      count char in str s pos len target_ch
        | pos >= len = 0
        | (str char at s pos) == target_ch = 1 + (count char in str s (pos + 1) len target_ch)
        | otherwise = count char in str s (pos + 1) len target_ch

fn :: seq select type String => RType
      seq select type mask   =
        plus_c = count char in str mask 0 (str len mask) 43
        space_c = count char in str mask 0 (str len mask) 32
        decide seq select type plus_c space_c

fn :: decide seq select type Int Int => RType
      decide seq select type plus_c space_c
        | plus_c > 1 = TyVar "_seq"
        | plus_c == 0 AND space_c >= 1 = TyVar "_seq"
        | otherwise = TyInt

fn :: select positional mask tys [RType] String Int Int => [RType]
      select positional mask tys elem_tys mask pos limit
        | pos >= limit = []
        | (str char at mask pos) == 43 =
          [rtype at elem_tys pos] :: (select positional mask tys elem_tys mask (pos + 1) limit)
        | otherwise =
          select positional mask tys elem_tys mask (pos + 1) limit

fn :: select tail tys [RType] Int Int => [RType]
      select tail tys elem_tys pos tup_len
        | pos >= tup_len = []
        | otherwise =
          [rtype at elem_tys pos] :: (select tail tys elem_tys (pos + 1) tup_len)

fn :: wrap selected mask tys [RType] => RType
      wrap selected mask tys [] = TyUnit
      wrap selected mask tys (single_ty:[]) = single_ty
      wrap selected mask tys multi_tys = TyTuple multi_tys

fn :: check one index mask [RType] Int Int String => RType [RTypeError]
      check one index mask elem_tys idx tup_len fn_name
        | idx < 0 OR idx >= tup_len =
          (TyInt, [TypeError fn_name ("sequence mask index " + (int to str idx) + " is out of range for tuple of length " + (int to str tup_len))])
        | otherwise =
          (rtype at elem_tys idx, [])

fn :: scan index mask tys [RType] String Int Int Int Int String [RType] [RTypeError] => RType [RTypeError]
      scan index mask tys elem_tys mask start pos len tup_len fn_name acc_tys acc_errs
        | pos >= len AND start >= len =
          (wrap selected mask tys acc_tys, acc_errs)
        | pos >= len =
          idx = str to int (str slice mask start len)
          one_res = check one index mask elem_tys idx tup_len fn_name
          (wrap selected mask tys (acc_tys :: [fst ty one_res]), acc_errs :: (snd errs one_res))
        | (str char at mask pos) == 32 AND pos > start =
          idx = str to int (str slice mask start pos)
          one_res = check one index mask elem_tys idx tup_len fn_name
          scan index mask tys elem_tys mask (pos + 1) (pos + 1) len tup_len fn_name (acc_tys :: [fst ty one_res]) (acc_errs :: (snd errs one_res))
        | (str char at mask pos) == 32 =
          scan index mask tys elem_tys mask (pos + 1) (pos + 1) len tup_len fn_name acc_tys acc_errs
        | otherwise =
          scan index mask tys elem_tys mask start (pos + 1) len tup_len fn_name acc_tys acc_errs

fn :: check tuple spread mask [RType] String Int Int [RTypeError] String => RType [RTypeError]
      check tuple spread mask elem_tys mask prefix_len tup_len b_errs fn_name
        | prefix_len > tup_len =
          (TyVar "_seq", b_errs :: [TypeError fn_name ("sequence spread mask has " + (int to str prefix_len) + " leading position(s), expected at most " + (int to str tup_len) + " for tuple of type " + (rtype to str (TyTuple elem_tys)))])
        | otherwise =
          sel_tys = (select positional mask tys elem_tys mask 0 prefix_len) :: (select tail tys elem_tys prefix_len tup_len)
          (wrap selected mask tys sel_tys, b_errs)

fn :: check tuple pos mask [RType] String Int Int [RTypeError] String => RType [RTypeError]
      check tuple pos mask elem_tys mask mask_len tup_len b_errs fn_name
        | mask_len != tup_len =
          (TyVar "_seq", b_errs :: [TypeError fn_name ("sequence mask has " + (int to str mask_len) + " position(s), expected " + (int to str tup_len) + " for tuple of type " + (rtype to str (TyTuple elem_tys)))])
        | otherwise =
          sel_tys = select positional mask tys elem_tys mask 0 mask_len
          (wrap selected mask tys sel_tys, b_errs)

fn :: check tuple seq mask [RType] String [RTypeError] String => RType [RTypeError]
      check tuple seq mask elem_tys mask b_errs fn_name
        | (str len mask) >= 2 AND (str slice mask ((str len mask) - 2) (str len mask)) == " +" =
          check tuple spread mask elem_tys mask ((str len mask) - 2) (rtype list len elem_tys) b_errs fn_name
        | NOT (str contains mask " ") =
          check tuple pos mask elem_tys mask (str len mask) (rtype list len elem_tys) b_errs fn_name
        | otherwise =
          scan index mask tys elem_tys mask 0 0 (str len mask) (rtype list len elem_tys) fn_name [] b_errs

fn :: check seq select (RType, [RTypeError]) String String => RType [RTypeError]
      check seq select ((TyTuple elem_tys), b_errs) mask fn_name =
        check tuple seq mask elem_tys mask b_errs fn_name
      check seq select ((TyVar _), b_errs) mask _ =
        (seq select type mask, b_errs)
      check seq select (other_ty, b_errs) _ fn_name =
        (TyVar "_seq", b_errs :: [TypeError fn_name ("sequence mask requires a tuple, got " + (rtype to str other_ty))])

fn :: lookup var type String String [RTypeBind] [RTypeBind] => RType [RTypeError]
      lookup var type name fn_name locals fns =
        loc_res = lookup type bind locals name
        lookup var step1 name fn_name loc_res locals fns

fn :: lookup var step1 String String (Bool, RType) [RTypeBind] [RTypeBind] => RType [RTypeError]
      lookup var step1 _ _ (True, ty) _ _ = (ty, [])
      lookup var step1 name fn_name (False, _) locals fns =
        fn_res = lookup type bind fns name
        lookup var step2 name fn_name fn_res locals

fn :: lookup var step2 String String (Bool, RType) [RTypeBind] => RType [RTypeError]
      lookup var step2 _ _ (True, (TyFun [] ret_ty)) _ = (ret_ty, [])
      lookup var step2 _ _ (True, other_ty) _ = (other_ty, [])
      lookup var step2 name fn_name (False, _) locals
        | is subscript ident name = lookup subscript base (split subscript name) locals
        | otherwise = (TyInt, [TypeError fn_name ("undefined variable '" + name + "'")])

fn :: lookup subscript base (String, String) [RTypeBind] => RType [RTypeError]
      lookup subscript base (base, _)        locals      =
        extract subscript ty (lookup type bind locals base)

fn :: extract subscript ty (Bool, RType) => RType [RTypeError]
      extract subscript ty (True, ty)    =  (ty, [])
      extract subscript ty (False, _)    =  (TyTensor [], [])

fn :: is last variadic [RType] => Bool
      is last variadic []      =  False
      is last variadic ((TyVariadic _):[]) = True
      is last variadic (_:ts)  =  is last variadic ts

fn :: last variadic inner [RType] => RType
      last variadic inner ((TyVariadic inner):[]) = inner
      last variadic inner (_:ts)  =  last variadic inner ts
      last variadic inner []      =  TyInt

fn :: lambda tuple arity hint RType RType => String
      lambda tuple arity hint (TyFun p1 _) (TyFun p2 _)
        | (rtype list len p1) > 1 AND (rtype list len p2) == 1 =
          "; note: '(a b => ...)' has multiple parameters — use '((a b) => ...)' to destructure a tuple"
        | (rtype list len p1) == 1 AND (rtype list len p2) > 1 =
          "; note: '((a b) => ...)' takes 1 tuple parameter — use '(a b => ...)' for multiple parameters"
        | otherwise = ""
      lambda tuple arity hint _ _ = ""

fn :: check fixed args [RType] [RType] String String Int [RDimBind] => [RTypeError]
      check fixed args [] _ _ _ _ _ = []
      check fixed args _ [] _ _ _ _ = []
      check fixed args (arg:args) (param:params) callee fn_name idx dim_env
        | NOT (types compatible arg param) = [TypeError fn_name ("function '" + callee + "' arg #" + (int to str idx) + " has type " + (rtype to str arg) + ", expected " + (rtype to str param) + (lambda tuple arity hint arg param))] :: (check fixed args args params callee fn_name (idx + 1) dim_env)
        | otherwise = check arg tensor dims arg param args params callee fn_name idx dim_env

fn :: check arg tensor dims RType RType [RType] [RType] String String Int [RDimBind] => [RTypeError]
      check arg tensor dims (TyTensor adims) (TyTensor pdims) args params callee fn_name idx dim_env
        | (str list count adims) > 0 AND (str list count adims) == (str list count pdims) = check arg tensor dims step (bind or check dims adims pdims callee fn_name dim_env) args params callee fn_name idx
      check arg tensor dims _ _ args params callee fn_name idx dim_env =
        check fixed args args params callee fn_name (idx + 1) dim_env

fn :: check arg tensor dims step ([RDimBind], [RTypeError]) [RType] [RType] String String Int => [RTypeError]
      check arg tensor dims step (dim_env1, dim_errs) args params callee fn_name idx =
        dim_errs :: (check fixed args args params callee fn_name (idx + 1) dim_env1)

fn :: check variadic args [RType] RType String String Int => [RTypeError]
      check variadic args [] _ _ _ _ = []
      check variadic args (arg:args) var_ty callee fn_name idx
        | (types compatible arg var_ty) OR (types compatible arg (TyList var_ty)) = check variadic args args var_ty callee fn_name (idx + 1)
        | otherwise = [TypeError fn_name ("function '" + callee + "' variadic arg #" + (int to str idx) + " has type " + (rtype to str arg) + ", expected " + (rtype to str var_ty))] :: (check variadic args args var_ty callee fn_name (idx + 1))

fn :: take rtypes [RType] Int => [RType]
      take rtypes _       0   =  []
      take rtypes []      _   =  []
      take rtypes (x:xs)  n   =  [x] :: (take rtypes xs (n - 1))

fn :: drop rtypes [RType] Int => [RType]
      drop rtypes xs      0   =  xs
      drop rtypes []      _   =  []
      drop rtypes (_:xs)  n   =  drop rtypes xs (n - 1)

fn :: is single poly var String => Bool
      is single poly var s
        | str starts with s "adt:" = False
        | otherwise = (str len s) == 1

fn :: is concrete for poly RType            => Bool
      is concrete for poly (TyVar "_empty") =  False
      is concrete for poly (TyVar "_any")   =  False
      is concrete for poly _                =  True

fn :: bind or check poly String RType String String [RTypeBind] => [RTypeBind] [RTypeError]
      bind or check poly v arg callee fn_name poly_env =
        bind or check poly step v arg callee fn_name poly_env (lookup type bind poly_env v)

fn :: bind or check poly step String RType String String [RTypeBind] (Bool, RType) => [RTypeBind] [RTypeError]
      bind or check poly step v arg _ _ poly_env (False, _)
        | is concrete for poly arg = ([TypeBind v arg] :: poly_env, [])
        | otherwise = (poly_env, [])
      bind or check poly step v arg callee fn_name poly_env (True, bound_ty)
        | types compatible arg bound_ty = (poly_env, [])
        | otherwise = (poly_env, [TypeError fn_name ("function '" + callee + "' type variable " + v + " unified with incompatible types: " + (rtype to str bound_ty) + " and " + (rtype to str arg))])

fn :: collect poly binds RType RType String String [RTypeBind] => [RTypeBind] [RTypeError]
      collect poly binds arg (TyVar v) callee fn_name poly_env
        | is single poly var v = bind or check poly v arg callee fn_name poly_env
        | otherwise = (poly_env, [])
      collect poly binds (TyList a_in) (TyList p_in) callee fn_name poly_env =
        collect poly binds a_in p_in callee fn_name poly_env
      collect poly binds (TyTuple a_es) (TyTuple p_es) callee fn_name poly_env =
        collect poly binds list a_es p_es callee fn_name poly_env
      collect poly binds (TyFun a_ps a_r) (TyFun p_ps p_r) callee fn_name poly_env =
        collect poly binds after (collect poly binds list a_ps p_ps callee fn_name poly_env) a_r p_r callee fn_name
      collect poly binds _ _ _ _ poly_env = (poly_env, [])

fn :: collect poly binds after ([RTypeBind], [RTypeError]) RType RType String String => [RTypeBind] [RTypeError]
      collect poly binds after (env1, errs1) a_r p_r callee fn_name =
        merge poly res errs1 (collect poly binds a_r p_r callee fn_name env1)

fn :: collect poly binds list [RType] [RType] String String [RTypeBind] => [RTypeBind] [RTypeError]
      collect poly binds list [] _ _ _ poly_env = (poly_env, [])
      collect poly binds list _ [] _ _ poly_env = (poly_env, [])
      collect poly binds list (a:as) (p:ps) callee fn_name poly_env =
        collect poly binds list step (collect poly binds a p callee fn_name poly_env) as ps callee fn_name

fn :: collect poly binds list step ([RTypeBind], [RTypeError]) [RType] [RType] String String => [RTypeBind] [RTypeError]
      collect poly binds list step (env1, errs1) as ps callee fn_name =
        merge poly res errs1 (collect poly binds list as ps callee fn_name env1)

fn :: merge poly res [RTypeError] ([RTypeBind], [RTypeError]) => [RTypeBind] [RTypeError]
      merge poly res errs1 (env2, errs2) = (env2, errs1 :: errs2)

fn :: subst poly type RType          [RTypeBind] => RType
      subst poly type (TyVar v)      poly_env
        | is single poly var v = subst poly var v (lookup type bind poly_env v)
        | otherwise = TyVar v
      subst poly type (TyList inner) poly_env    =  TyList (subst poly type inner poly_env)
      subst poly type (TyTuple es)   poly_env    =  TyTuple (subst poly type list es poly_env)
      subst poly type (TyFun ps r)   poly_env    =  TyFun (subst poly type list ps poly_env) (subst poly type r poly_env)
      subst poly type ty             _           =  ty

fn :: subst poly var String (Bool, RType) => RType
      subst poly var _      (True, ty)    =  ty
      subst poly var v      (False, _)    =  TyVar v

fn :: subst poly type list [RType] [RTypeBind] => [RType]
      subst poly type list [] _ = []
      subst poly type list (t:ts) poly_env = [subst poly type t poly_env] :: (subst poly type list ts poly_env)

fn :: finish poly call RType [RTypeError] ([RTypeBind], [RTypeError]) => RType [RTypeError]
      finish poly call ret_ty fixed_errs (poly_env, poly_errs) =
        (subst poly type ret_ty poly_env, fixed_errs :: poly_errs)

fn :: check call sig String [RType] [RType] RType String => RType [RTypeError]
      check call sig callee (first_arg:rest_args) (rec_param:[]) (TyFun inner_params inner_ret) fn_name
        | (rtype list len rest_args) >= 1 AND (types compatible first_arg rec_param) =
          check call sig callee rest_args inner_params inner_ret fn_name
      check call sig callee arg_tys param_tys ret_ty fn_name
        | is last variadic param_tys = check variadic call callee arg_tys param_tys ret_ty fn_name
        | (rtype list len arg_tys) == 1 AND (rtype list len param_tys) > 1 = check tuple chain call callee (rtype at arg_tys 0) arg_tys param_tys ret_ty fn_name
        | (rtype list len arg_tys) > 1 AND (rtype list len arg_tys) < (rtype list len param_tys) =
          k = rtype list len arg_tys
          taken_params = take rtypes param_tys k
          rem_params = drop rtypes param_tys k
          finish poly call (TyFun rem_params ret_ty) (check fixed args arg_tys taken_params callee fn_name 0 []) (collect poly binds list arg_tys taken_params callee fn_name [])
        | (rtype list len arg_tys) != (rtype list len param_tys) = (ret_ty, [TypeError fn_name ("function '" + callee + "' called with " + (int to str (rtype list len arg_tys)) + " argument(s), expected " + (int to str (rtype list len param_tys)))])
        | otherwise = finish poly call ret_ty (check fixed args arg_tys param_tys callee fn_name 0 []) (collect poly binds list arg_tys param_tys callee fn_name [])

fn :: check variadic call String [RType] [RType] RType String => RType [RTypeError]
      check variadic call callee arg_tys param_tys ret_ty fn_name =
        fixed = (rtype list len param_tys) - 1
        var_ty = last variadic inner param_tys
        check variadic call counts callee arg_tys param_tys ret_ty fn_name fixed var_ty

fn :: check variadic call counts String [RType] [RType] RType String Int RType => RType [RTypeError]
      check variadic call counts callee arg_tys param_tys ret_ty fn_name fixed var_ty
        | (rtype list len arg_tys) < fixed = (ret_ty, [TypeError fn_name ("function '" + callee + "' called with " + (int to str (rtype list len arg_tys)) + " argument(s), expected at least " + (int to str fixed))])
        | otherwise = (ret_ty, (check fixed args (take rtypes arg_tys fixed) (take rtypes param_tys fixed) callee fn_name 0 []) :: (check variadic args (drop rtypes arg_tys fixed) var_ty callee fn_name fixed))

fn :: check tuple chain call String RType [RType] [RType] RType String => RType [RTypeError]
      check tuple chain call callee (TyTuple elems) _ param_tys ret_ty fn_name
        | (rtype list len elems) == (rtype list len param_tys) = finish poly call ret_ty (check fixed args elems param_tys callee fn_name 0 []) (collect poly binds list elems param_tys callee fn_name [])
      check tuple chain call _ (TyVar "_seq") _ _ ret_ty _ = (ret_ty, [])
      check tuple chain call callee first_arg arg_tys param_tys ret_ty fn_name
        | types compatible first_arg (rtype at param_tys 0) =
          taken_params = take rtypes param_tys 1
          rem_params = drop rtypes param_tys 1
          finish poly call (TyFun rem_params ret_ty) (check fixed args arg_tys taken_params callee fn_name 0 []) (collect poly binds list arg_tys taken_params callee fn_name [])
        | otherwise =
          (ret_ty, [TypeError fn_name ("function '" + callee + "' called with " + (int to str (rtype list len arg_tys)) + " argument(s), expected " + (int to str (rtype list len param_tys)))])

fn :: check call target String [RType] [RTypeError] (Bool, RType) String => RType [RTypeError]
      check call target callee arg_tys arg_errs (True, (TyFun param_tys ret_ty)) fn_name =
        sig_res = check call sig callee arg_tys param_tys ret_ty fn_name
        prepend type errs arg_errs sig_res
      check call target callee _ arg_errs (True, _) fn_name =
        (TyInt, arg_errs :: [TypeError fn_name ("'" + callee + "' is not a function")])
      check call target callee _ arg_errs (False, _) fn_name =
        (TyInt, arg_errs :: [TypeError fn_name ("undefined function '" + callee + "'")])

fn :: prepend type errs [RTypeError] (RType, [RTypeError]) => RType [RTypeError]
      prepend type errs errs1        (ty, errs2)           =  (ty, errs1 :: errs2)

fn :: lookup record field for type [RTypeBind] String RType => Bool RType
      lookup record field for type [] _ _ = (False, TyInt)
      lookup record field for type ((TypeBind k (TyFun (rec_ty:[]) fty)):rest) target base_ty
        | k == target AND (types compatible base_ty rec_ty) = (True, TyFun [rec_ty] fty)
        | otherwise = lookup record field for type rest target base_ty
      lookup record field for type (_:rest) target base_ty =
        lookup record field for type rest target base_ty

fn :: lookup record field bind [RTypeBind] String RType => Bool RType
      lookup record field bind fns fname base_ty =
        by_ty = lookup record field for type fns fname base_ty
        lookup record field fallback fns fname by_ty

fn :: lookup record field fallback [RTypeBind] String (Bool, RType) => Bool RType
      lookup record field fallback _ _ (True, ty) = (True, ty)
      lookup record field fallback fns fname (False, _) = lookup type bind fns fname

fn :: check record update fields (RType, [RTypeError]) [RExpr] String [RTypeBind] [RTypeBind] => RType [RTypeError]
      check record update fields (base_ty, base_errs) [] _ _ _ = (base_ty, base_errs)
      check record update fields (base_ty, base_errs) ((EStr fname):val_e:rest) fn_name locals fns =
        v_res = check expr val_e fn_name locals fns
        f_errs = check one record field base_ty fname v_res fn_name (lookup record field bind fns fname base_ty)
        check record update fields (base_ty, base_errs :: f_errs) rest fn_name locals fns
      check record update fields (base_ty, base_errs) (_:rest) fn_name locals fns =
        check record update fields (base_ty, base_errs) rest fn_name locals fns

fn :: check one record field RType String (RType, [RTypeError]) String (Bool, RType) => [RTypeError]
      check one record field base_ty fname (val_ty, val_errs) fn_name (True, (TyFun (rec_ty:[]) fty))
        | NOT (types compatible base_ty rec_ty) = val_errs :: [TypeError fn_name ("record field '" + fname + "' belongs to " + (rtype to str rec_ty) + ", not " + (rtype to str base_ty))]
        | NOT (types compatible val_ty fty) = val_errs :: [TypeError fn_name ("record field '" + fname + "' has type " + (rtype to str val_ty) + ", expected " + (rtype to str fty))]
        | otherwise = val_errs
      check one record field _ fname (_, val_errs) fn_name _ =
        val_errs :: [TypeError fn_name ("unknown record field '" + fname + "'")]

fn :: check expr list [RExpr] String [RTypeBind] [RTypeBind] => [RType] [RTypeError]
      check expr list [] _ _ _ = ([], [])
      check expr list (e:es) fn_name locals fns =
        r1 = check expr e fn_name locals fns
        check expr list cont es fn_name locals fns r1

fn :: check expr list cont [RExpr] String [RTypeBind] [RTypeBind] (RType, [RTypeError]) => [RType] [RTypeError]
      check expr list cont es fn_name locals fns (ty1, errs1) =
        r2 = check expr list es fn_name locals fns
        merge ty list ty1 errs1 r2

fn :: merge ty list RType [RTypeError] ([RType], [RTypeError]) => [RType] [RTypeError]
      merge ty list ty1 errs1 (tys, errs2) = ([ty1] :: tys, errs1 :: errs2)

fn :: check list elems uniform RType [RType] String => [RTypeError]
      check list elems uniform _ [] _ = []
      check list elems uniform first_ty (t:ts) fn_name
        | types compatible t first_ty = check list elems uniform first_ty ts fn_name
        | otherwise = [TypeError fn_name ("list elements have mixed types: " + (rtype to str first_ty) + " and " + (rtype to str t))] :: (check list elems uniform first_ty ts fn_name)

fn :: finish list type ([RType], [RTypeError]) String  => RType [RTypeError]
      finish list type ([], errs)              _       =  (TyList (TyVar "_empty"), errs)
      finish list type ((first_ty:rest_tys), errs) fn_name =
        elem_errs = check list elems uniform first_ty rest_tys fn_name
        (TyList first_ty, errs :: elem_errs)

fn :: finish tuple type ([RType], [RTypeError]) => RType [RTypeError]
      finish tuple type (tys, errs)             =  (TyTuple tys, errs)

fn :: check expr RExpr String [RTypeBind] [RTypeBind] => RType [RTypeError]
      check expr (EInt _) _ _ _ = (TyInt, [])
      check expr (EReal _) _ _ _ = (TyReal, [])
      check expr (EStr _) _ _ _ = (TyString, [])
      check expr (EStrInterp parts) fn_name locals fns =
        p_res = check expr list parts fn_name locals fns
        discard tys return TyString p_res
      check expr (EBool _) _ _ _ = (TyBool, [])
      check expr EUnit _ _ _ = (TyUnit, [])
      check expr (ENot inner) fn_name locals fns =
        check not inner (check expr inner fn_name locals fns) fn_name
      check expr (EOut inner) fn_name locals fns =
        r1 = check expr inner fn_name locals fns
        prepend type errs (snd errs r1) (TyVar "_out", [])
      check expr (EWithCtx ctx_name val_e body) fn_name locals fns =
        v_res = check expr val_e fn_name locals fns
        check with ctx body ctx_name body fn_name locals fns v_res
      check expr (EWithRegion _ body) fn_name locals fns =
        b_res = check expr body fn_name locals fns
        prepend type errs (snd errs b_res) (TyVar "Result", [])
      check expr (EEinsum es subs) fn_name locals fns =
        e_res = check einsum terms es subs fn_name locals fns []
        finish einsum check e_res
      check expr (EHadamard _ l _ r _) fn_name locals fns =
        l_res = check expr l fn_name locals fns
        r_res = check expr r fn_name locals fns
        finish hadamard check l_res r_res
      check expr (EVar name) fn_name locals fns =
        lookup var type name fn_name locals fns
      check expr (EBin bop l r) fn_name locals fns =
        l_res = check expr l fn_name locals fns
        r_res = check expr r fn_name locals fns
        finish binop check bop l_res r_res fns fn_name
      check expr (ECall "__record_update__" (base_e:rest_args)) fn_name locals fns =
        b_res = check expr base_e fn_name locals fns
        check record update fields b_res rest_args fn_name locals fns
      check expr (ECall "__missing_import__" ((EStr mod_name):_)) _ _ _ =
        (TyInt, [TypeError "import" ("unresolved import '" + mod_name + "': module not found in project or .stable/deps")])
      check expr (ECall "__syntax_error__" ((EStr msg):_)) _ _ _ =
        (TyVar "_any", [TypeError "syntax" msg])
      check expr (ECall callee args) fn_name locals fns =
        args_res = check expr list args fn_name locals fns
        finish call check callee args_res fn_name locals fns
      check expr (EEcho args) fn_name locals fns =
        args_res = check expr list args fn_name locals fns
        discard tys return TyUnit args_res
      check expr (EList []) _ _ _ = (TyList (TyVar "_empty"), [])
      check expr (EList elems) fn_name locals fns =
        finish list type (check expr list elems fn_name locals fns) fn_name
      check expr (ETuple elems) fn_name locals fns =
        finish tuple type (check expr list elems fn_name locals fns)
      check expr (ETensor elems) fn_name locals fns =
        args_res = check expr list elems fn_name locals fns
        discard tys return (TyTensor []) args_res
      check expr (EIndex base idxs) fn_name locals fns =
        b_res = check expr base fn_name locals fns
        i_res = check expr list idxs fn_name locals fns
        (infer index expr ty (fst ty b_res) idxs, (snd errs b_res) :: (snd list errs i_res))
      check expr (EIndexAssign _ idxs val_e) fn_name locals fns =
        i_res = check expr list idxs fn_name locals fns
        v_res = check expr val_e fn_name locals fns
        (TyUnit, (snd list errs i_res) :: (snd errs v_res))
      check expr (ESeqSelect base mask) fn_name locals fns =
        b_res = check expr base fn_name locals fns
        check seq select b_res mask fn_name
      check expr (EWhere body binds) fn_name locals fns =
        check where expr body binds fn_name locals fns
      check expr (EParPipe branches) fn_name locals fns =
        finish tuple type (check expr list branches fn_name locals fns)
      check expr (EGuard guards) fn_name locals fns =
        check guard expr guards fn_name locals fns
      check expr (EBlock stmts) fn_name locals fns =
        check block stmts stmts TyUnit fn_name locals fns

fn :: fst ty (RType, [RTypeError]) => RType
      fst ty (ty, _)               =  ty

fn :: infer index expr ty RType [RExpr] => RType
      infer index expr ty (TyTuple elem_tys) ((EInt k):[]) = rtype at elem_tys k
      infer index expr ty _ _ = TyInt

fn :: snd errs (RType, [RTypeError]) => [RTypeError]
      snd errs (_, errs)             =  errs

fn :: snd list errs ([RType], [RTypeError]) => [RTypeError]
      snd list errs (_, errs)               =  errs

fn :: discard tys return RType  ([RType], [RTypeError]) => RType [RTypeError]
      discard tys return ret_ty (_, errs)               =  (ret_ty, errs)

fn :: check not inner (RType, [RTypeError]) String  => RType [RTypeError]
      check not inner (inner_ty, errs)      fn_name
        | types compatible inner_ty TyBool = (TyBool, errs)
        | is int or poly inner_ty = (TyInt, errs)
        | types compatible inner_ty (TyTensor []) = (inner_ty, errs)
        | otherwise = (TyBool, errs :: [TypeError fn_name ("NOT requires Bool or Int operand, got " + (rtype to str inner_ty))])

fn :: check with ctx body String RExpr String [RTypeBind] [RTypeBind] (RType, [RTypeError]) => RType [RTypeError]
      check with ctx body "__rg_timeout_ms__" body fn_name locals fns (val_ty, v_errs)
        | types compatible val_ty TyInt =
          b_res = check expr body fn_name locals fns
          prepend type errs v_errs b_res
        | otherwise =
          b_res = check expr body fn_name locals fns
          prepend type errs (v_errs :: [TypeError fn_name ("with timeout requires Int duration, got " + (rtype to str val_ty))]) b_res
      check with ctx body ctx_name body fn_name locals fns (val_ty, v_errs) =
        locals1 = put type bind locals ctx_name val_ty
        b_res = check expr body fn_name locals1 fns
        prepend type errs v_errs b_res

fn :: finish einsum check ([RDimBind], [RTypeError]) => RType [RTypeError]
      finish einsum check (_, errs)                  =  (TyTensor [], errs)

fn :: finish hadamard check (RType, [RTypeError]) (RType, [RTypeError]) => RType [RTypeError]
      finish hadamard check ((TyTensor dims), l_errs) (_, r_errs) = (TyTensor dims, l_errs :: r_errs)
      finish hadamard check (_, l_errs) (_, r_errs) = (TyTensor [], l_errs :: r_errs)

fn :: finish binop check RBinOp (RType, [RTypeError]) (RType, [RTypeError]) [RTypeBind] String => RType [RTypeError]
      finish binop check bop (l_ty, l_errs) (r_ty, r_errs) fns fn_name =
        b_res = check binop bop l_ty r_ty fns fn_name
        prepend type errs (l_errs :: r_errs) b_res

fn :: args match params [RType] [RType] => Bool
      args match params []      []      =  True
      args match params (a:as)  (p:ps)
        | types compatible a p = args match params as ps
        | otherwise = False
      args match params _       _       =  False

fn :: collect matching sigs [RTypeBind] String [RType] => [RType]
      collect matching sigs [] _ _ = []
      collect matching sigs ((TypeBind k (TyFun param_tys ret_ty)):rest) target arg_tys
        | k == target AND (rtype list len param_tys) == (rtype list len arg_tys) AND (args match params arg_tys param_tys) AND (is upper ident target) = [TyFun param_tys ret_ty] :: (collect matching sigs rest target arg_tys)
        | k == target AND (rtype list len param_tys) == (rtype list len arg_tys) AND (args match params arg_tys param_tys) = [TyFun param_tys ret_ty]
        | otherwise = collect matching sigs rest target arg_tys
      collect matching sigs (_:rest) target arg_tys =
        collect matching sigs rest target arg_tys

fn :: merge matching sigs [RType] => Bool RType
      merge matching sigs []      =  (False, TyInt)
      merge matching sigs (s:[])  =  (True, s)
      merge matching sigs ((TyFun p1 r1):(TyFun _ r2):rest) =
        merge matching sigs ([TyFun p1 (join adt ret ty r1 r2)] :: rest)
      merge matching sigs (s:_)   =  (True, s)

fn :: resolve callee for args String [RType] [RTypeBind] [RTypeBind] => Bool RType
      resolve callee for args callee arg_tys locals fns =
        loc_b = lookup type bind locals callee
        resolve callee local first callee arg_tys locals fns loc_b

fn :: resolve callee local first String [RType] [RTypeBind] [RTypeBind] (Bool, RType) => Bool RType
      resolve callee local first _ _ _ _ (True, (TyFun p r)) = (True, TyFun p r)
      resolve callee local first _ [] _ _ (True, ty) = (True, TyFun [] ty)
      resolve callee local first callee arg_tys locals fns _ =
        matched = merge matching sigs (collect matching sigs fns callee arg_tys)
        resolve callee args fallback callee locals fns matched

fn :: resolve callee args fallback String [RTypeBind] [RTypeBind] (Bool, RType) => Bool RType
      resolve callee args fallback _ _ _ (True, ty) = (True, ty)
      resolve callee args fallback callee locals fns (False, _) = resolve callee bind callee locals fns

fn :: resolve callee bind String [RTypeBind] [RTypeBind] => Bool RType
      resolve callee bind callee locals fns =
        fn_b = lookup type bind fns callee
        resolve callee fallback callee locals fn_b

fn :: resolve callee fallback String [RTypeBind] (Bool, RType) => Bool RType
      resolve callee fallback _ _ (True, ty) = (True, ty)
      resolve callee fallback callee locals (False, _) = lookup type bind locals callee

fn :: pack agent msg ty [RType]     => RType
      pack agent msg ty []          =  TyUnit
      pack agent msg ty (single:[]) =  single
      pack agent msg ty tys         =  TyTuple tys

fn :: infer stateful agent out RType RType => RType
      infer stateful agent out s_ty (TyTuple (r1:r2:[]))
        | (types compatible r1 s_ty) AND (NOT (types compatible (TyTuple [r1, r2]) s_ty)) = r2
      infer stateful agent out _ ret_ty = ret_ty

fn :: check agent create [RType] [RTypeError] String => RType [RTypeError]
      check agent create ((TyFun params ret_ty):[]) arg_errs _ =
        (TyTuple [TyVar "Agent", pack agent msg ty params, ret_ty], arg_errs)
      check agent create ((TyFun (s_ty:msg_params) ret_ty):init_ty:[]) arg_errs fn_name
        | types compatible init_ty s_ty =
          (TyTuple [TyVar "Agent", pack agent msg ty msg_params, infer stateful agent out s_ty ret_ty], arg_errs)
        | otherwise =
          err = TypeError fn_name ("agent initial state has type " + (rtype to str init_ty) + ", expected " + (rtype to str s_ty))
          (TyTuple [TyVar "Agent", pack agent msg ty msg_params, infer stateful agent out s_ty ret_ty], arg_errs :: [err])
      check agent create _ arg_errs fn_name =
        (TyVar "Agent", arg_errs :: [TypeError fn_name "agent expects a function reference and optional initial state"])

fn :: check agent send [RType] [RTypeError] String => RType [RTypeError]
      check agent send (msg_ty:(TyTuple ((TyVar "Agent"):in_ty:_)):[]) arg_errs fn_name
        | types compatible msg_ty in_ty = (TyUnit, arg_errs)
        | otherwise =
          (TyUnit, arg_errs :: [TypeError fn_name ("agent message has type " + (rtype to str msg_ty) + ", expected " + (rtype to str in_ty))])
      check agent send (_:(TyVar "Agent"):[]) arg_errs _ = (TyUnit, arg_errs)
      check agent send _ arg_errs _ = (TyUnit, arg_errs)

fn :: specialize hof return String [RType] (RType, [RTypeError]) => RType [RTypeError]
      specialize hof return "map" ((TyFun _ f_ret):_) (_, errs) = (TyList f_ret, errs)
      specialize hof return "||map" ((TyFun _ f_ret):_) (_, errs) = (TyList f_ret, errs)
      specialize hof return "filter" (_:list_ty:_) (_, errs) = (list_ty, errs)
      specialize hof return "||filter" (_:list_ty:_) (_, errs) = (list_ty, errs)
      specialize hof return "fold" (_:init_ty:_) (_, errs) = (init_ty, errs)
      specialize hof return "receive_from" ((TyTuple ((TyVar "Agent"):_:out_ty:[])):_) (_, errs) = (out_ty, errs)
      specialize hof return "try_receive_from" ((TyTuple ((TyVar "Agent"):_:out_ty:[])):_) (_, errs) = (make option type out_ty, errs)
      specialize hof return "Some" (elem_ty:[]) (_, errs) = (make option type elem_ty, errs)
      specialize hof return _ _ res = res

fn :: check agent ask [RType] [RTypeError] String => RType [RTypeError]
      check agent ask (msg_ty:(TyTuple ((TyVar "Agent"):in_ty:out_ty:[])):[]) arg_errs fn_name
        | types compatible msg_ty in_ty = (out_ty, arg_errs)
        | otherwise =
          (out_ty, arg_errs :: [TypeError fn_name ("agent message has type " + (rtype to str msg_ty) + ", expected " + (rtype to str in_ty))])
      check agent ask (_:(TyVar "Agent"):[]) arg_errs _ = (TyVar "A", arg_errs)
      check agent ask _ arg_errs _ = (TyVar "A", arg_errs)

fn :: finish call check String ([RType], [RTypeError]) String [RTypeBind] [RTypeBind] => RType [RTypeError]
      finish call check "agent" (arg_tys, arg_errs) fn_name _ _ = check agent create arg_tys arg_errs fn_name
      finish call check "send_to" (arg_tys, arg_errs) fn_name _ _ = check agent send arg_tys arg_errs fn_name
      finish call check "ask_to" (arg_tys, arg_errs) fn_name _ _ = check agent ask arg_tys arg_errs fn_name
      finish call check ":tensor-zeros:" (_, arg_errs) _ _ _ = (TyTensor [], arg_errs)
      finish call check ":tensor-clone:" (_, arg_errs) _ _ _ = (TyTensor [], arg_errs)
      finish call check ":tensor-row-slice:" (_, arg_errs) _ _ _ = (TyTensor [], arg_errs)
      finish call check ":tensor-col-slice:" (_, arg_errs) _ _ _ = (TyTensor [], arg_errs)
      finish call check ":tensor-set-row:" (_, arg_errs) _ _ _ = (TyUnit, arg_errs)
      finish call check ":tensor-set-col:" (_, arg_errs) _ _ _ = (TyUnit, arg_errs)
      finish call check ":tensor-map-rows:" (_, arg_errs) _ _ _ = (TyTensor [], arg_errs)
      finish call check ":tensor-map-rows-in:" (_, arg_errs) _ _ _ = (TyVar "_any", arg_errs)
      finish call check ":tensor-map-cols:" (_, arg_errs) _ _ _ = (TyTensor [], arg_errs)
      finish call check ":tensor-map-cols-in:" (_, arg_errs) _ _ _ = (TyVar "_any", arg_errs)
      finish call check ":tensor-map-elems:" (_, arg_errs) _ _ _ = (TyTensor [], arg_errs)
      finish call check ":tensor-map-elems-in:" (_, arg_errs) _ _ _ = (TyVar "_any", arg_errs)
      finish call check "__chain__" ((fn_ty:rest_tys), arg_errs) fn_name _ _ =
        check call target "<expr>" rest_tys arg_errs (True, fn_ty) fn_name
      finish call check callee (arg_tys, arg_errs) fn_name locals fns =
        base_res = check call target callee arg_tys arg_errs (resolve callee for args callee arg_tys locals fns) fn_name
        specialize hof return callee arg_tys base_res

fn :: check where binds [RWhereBind] String [RTypeBind] [RTypeBind] => [RTypeBind] [RTypeError]
      check where binds [] _ locals _ = (locals, [])
      check where binds ((WhereBind e target idxs):wbs) fn_name locals fns =
        e_res = check expr e fn_name locals fns
        check where binds step target idxs wbs fn_name locals fns e_res

fn :: check where binds step String [Int] [RWhereBind] String [RTypeBind] [RTypeBind] (RType, [RTypeError]) => [RTypeBind] [RTypeError]
      check where binds step target [] wbs fn_name locals fns (bty, errs1) =
        locals1 = put type bind locals target bty
        more = check where binds wbs fn_name locals1 fns
        merge env errs errs1 more
      check where binds step _ _ wbs fn_name locals fns (_, errs1) =
        more = check where binds wbs fn_name locals fns
        merge env errs errs1 more

fn :: merge env errs [RTypeError] ([RTypeBind], [RTypeError]) => [RTypeBind] [RTypeError]
      merge env errs errs1 (env2, errs2) = (env2, errs1 :: errs2)

fn :: check where expr RExpr [RWhereBind] String [RTypeBind] [RTypeBind] => RType [RTypeError]
      check where expr body binds fn_name locals fns =
        w_res = check where binds binds fn_name locals fns
        check where body body fn_name fns w_res

fn :: check where body RExpr String [RTypeBind] ([RTypeBind], [RTypeError]) => RType [RTypeError]
      check where body body fn_name fns (locals1, w_errs) =
        b_res = check expr body fn_name locals1 fns
        prepend type errs w_errs b_res

fn :: bind let var String RType [RTypeBind] => [RTypeBind]
      bind let var name ty locals
        | is subscript ident name = bind subscript let (split subscript name) name ty locals
        | otherwise = put type bind locals name ty

fn :: bind subscript let (String, String) String RType [RTypeBind] => [RTypeBind]
      bind subscript let (base, _) name ty locals =
        put type bind (put type bind locals base ty) name ty

fn :: check guard expr [RGuard] String [RTypeBind] [RTypeBind] => RType [RTypeError]
      check guard expr [] _ _ _ = (TyUnit, [])
      check guard expr ((GuardBranch cond body):gs) fn_name locals fns =
        c_res = check expr cond fn_name locals fns
        b_res = check expr body fn_name locals fns
        check guard expr first c_res b_res gs fn_name locals fns

fn :: check guard expr first (RType, [RTypeError]) (RType, [RTypeError]) [RGuard] String [RTypeBind] [RTypeBind] => RType [RTypeError]
      check guard expr first (c_ty, c_errs) (b_ty, b_errs) gs fn_name locals fns =
        c_chk = check guard cond ty c_ty fn_name 0
        rest_errs = check case guards gs fn_name b_ty 1 locals fns
        (b_ty, c_errs :: c_chk :: b_errs :: rest_errs)

fn :: check block stmts [RStmt] RType String [RTypeBind] [RTypeBind] => RType [RTypeError]
      check block stmts stmts last_ty fn_name locals fns =
        check block stmts scoped stmts last_ty fn_name locals fns [] []

fn :: check block stmts scoped [RStmt] RType String [RTypeBind] [RTypeBind] [String] [String] => RType [RTypeError]
      check block stmts scoped [] last_ty _ _ _ _ _ = (last_ty, [])
      check block stmts scoped ((StmtMut name val_e):ss) _ fn_name locals fns immuts muts =
        v_res = check expr val_e fn_name locals fns
        check block after mut name ss fn_name locals fns immuts muts v_res
      check block stmts scoped ((StmtLet name val_e):ss) _ fn_name locals fns immuts muts =
        v_res = check expr val_e fn_name locals fns
        check block after let name ss fn_name locals fns immuts muts v_res
      check block stmts scoped ((StmtExpr e):ss) _ fn_name locals fns immuts muts =
        e_res = check expr e fn_name locals fns
        check block after expr ss fn_name locals fns immuts muts e_res
      check block stmts scoped ((StmtIndexAssign _ idxs val_e):ss) _ fn_name locals fns immuts muts =
        i_res = check expr list idxs fn_name locals fns
        v_res = check expr val_e fn_name locals fns
        check block after expr ss fn_name locals fns immuts muts (TyUnit, (snd list errs i_res) :: (snd errs v_res))

fn :: check block after mut String [RStmt] String [RTypeBind] [RTypeBind] [String] [String] (RType, [RTypeError]) => RType [RTypeError]
      check block after mut name ss fn_name locals fns immuts muts (v_ty, v_errs) =
        locals1 = bind let var name v_ty locals
        more = check block stmts scoped ss v_ty fn_name locals1 fns immuts (add unique str name muts)
        prepend type errs v_errs more

fn :: check immut reassign String String [String] [String] => [RTypeError]
      check immut reassign "_" _ _ _ = []
      check immut reassign name fn_name immuts muts
        | str in list name muts = []
        | str in list name immuts = [TypeError fn_name ("cannot reassign immutable variable '" + name + "'; declare it with 'mut " + name + " = ...' first")]
        | otherwise = []

fn :: check block after let String [RStmt] String [RTypeBind] [RTypeBind] [String] [String] (RType, [RTypeError]) => RType [RTypeError]
      check block after let name ss fn_name locals fns immuts muts (v_ty, v_errs) =
        mut_err = check immut reassign name fn_name immuts muts
        locals1 = bind let var name v_ty locals
        more = check block stmts scoped ss v_ty fn_name locals1 fns (add unique str name immuts) muts
        prepend type errs (v_errs :: mut_err) more

fn :: check block after expr [RStmt] String [RTypeBind] [RTypeBind] [String] [String] (RType, [RTypeError]) => RType [RTypeError]
      check block after expr ss fn_name locals fns immuts muts (e_ty, e_errs) =
        more = check block stmts scoped ss e_ty fn_name locals fns immuts muts
        prepend type errs e_errs more

-- ── Function & Case Type Checking ───────────────────────────

fn :: is empty list return compat RType RType => Bool
      is empty list return compat (TyList (TyVar "_empty")) (TyList _) = True
      is empty list return compat _ _ = False

fn :: check case guards [RGuard] String RType Int [RTypeBind] [RTypeBind] => [RTypeError]
      check case guards [] _ _ _ _ _ = []
      check case guards ((GuardBranch cond body):gs) fn_name ret_ty idx locals fns =
        c_res = check expr cond fn_name locals fns
        b_res = check expr body fn_name locals fns
        (check guard pair c_res b_res fn_name ret_ty idx) :: (check case guards gs fn_name ret_ty (idx + 1) locals fns)

fn :: check guard pair (RType, [RTypeError]) (RType, [RTypeError]) String RType Int => [RTypeError]
      check guard pair (c_ty, c_errs) (b_ty, b_errs) fn_name ret_ty idx =
        c_chk = check guard cond ty c_ty fn_name idx
        b_chk = check guard body ty b_ty ret_ty fn_name idx
        c_errs :: c_chk :: b_errs :: b_chk

fn :: check guard cond ty RType String Int => [RTypeError]
      check guard cond ty TyBool _ _ = []
      check guard cond ty c_ty fn_name idx =
        [TypeError fn_name ("guard #" + (int to str idx) + " condition has type " + (rtype to str c_ty) + ", expected Bool")]

fn :: is unit type RType  => Bool
      is unit type TyUnit =  True
      is unit type _      =  False

fn :: check guard body ty RType RType String Int => [RTypeError]
      check guard body ty b_ty ret_ty fn_name idx
        | (is unit type ret_ty) OR (types compatible b_ty ret_ty) OR (is empty list return compat b_ty ret_ty) = []
        | otherwise = [TypeError fn_name ("guard #" + (int to str idx) + " body has type " + (rtype to str b_ty) + ", expected " + (rtype to str ret_ty))]

fn :: check case body ty (RType, [RTypeError]) RType String => [RTypeError]
      check case body ty (b_ty, b_errs) ret_ty fn_name
        | (is unit type ret_ty) OR (types compatible b_ty ret_ty) OR (is empty list return compat b_ty ret_ty) = b_errs
        | otherwise = b_errs :: [TypeError fn_name ("body has type " + (rtype to str b_ty) + ", expected " + (rtype to str ret_ty))]

fn :: pat count [RPattern] => Int
      pat count []         =  0
      pat count (_:xs)     =  1 + (pat count xs)

fn :: check one case RFnCase String [RType] RType Int [RTypeBind] [RTypeBind] => [RTypeError]
      check one case (FnCase pats guards body) fn_name param_tys ret_ty case_idx locals fns
        | (pat count pats) != (rtype list len param_tys) AND (NOT (has seq bind pat pats)) = [TypeError fn_name ("case #" + (int to str case_idx) + " has " + (int to str (pat count pats)) + " pattern(s), expected " + (int to str (rtype list len param_tys)))]
        | otherwise = check case guards or body guards body fn_name ret_ty (bind case patterns pats param_tys (has seq bind pat pats) 0 locals fns) fns

fn :: check case guards or body [RGuard] RExpr String RType [RTypeBind] [RTypeBind] => [RTypeError]
      check case guards or body [] body fn_name ret_ty locals fns =
        check case body ty (check expr body fn_name locals fns) ret_ty fn_name
      check case guards or body guards _ fn_name ret_ty locals fns =
        check case guards guards fn_name ret_ty 0 locals fns

fn :: check fn cases [RFnCase] String [RType] RType Int [RTypeBind] [RTypeBind] => [RTypeError]
      check fn cases [] _ _ _ _ _ _ = []
      check fn cases (c:cs) fn_name param_tys ret_ty idx locals fns =
        (check one case c fn_name param_tys ret_ty idx locals fns) :: (check fn cases cs fn_name param_tys ret_ty (idx + 1) locals fns)

fn :: check sig syntax errs [String] String String => [RTypeError]
      check sig syntax errs [] ret_str fn_name
        | str contains ret_str "__err_unit_fn_type__" =
          [TypeError fn_name "zero-parameter function type in signature uses '(=> Type)', not '(() => Type)'"]
        | str contains ret_str "__err_lower_fn_type__" =
          [TypeError fn_name "function type in signature must use uppercase type names (e.g. '(Conn => Conn)'), not lowercase lambda parameters"]
        | otherwise = []
      check sig syntax errs (p:ps) ret_str fn_name
        | str contains p "__err_unit_fn_type__" =
          [TypeError fn_name "zero-parameter function type in signature uses '(=> Type)', not '(() => Type)'"] :: (check sig syntax errs ps ret_str fn_name)
        | str contains p "__err_lower_fn_type__" =
          [TypeError fn_name "function type in signature must use uppercase type names (e.g. '(Conn => Conn)'), not lowercase lambda parameters"] :: (check sig syntax errs ps ret_str fn_name)
        | otherwise = check sig syntax errs ps ret_str fn_name

fn :: check all functions acc [String] [RFnDef] [RTypeBind] [RTypeBind] [RTypeError] => [RTypeError]
      check all functions acc _ [] _ _ acc = acc
      check all functions acc tnames ((FnDef name param_strs ret_str cases):fs) locals fns acc =
        sig_errs = check sig syntax errs param_strs ret_str name
        param_tys = qualify declared adt list tnames (parse type list strs param_strs)
        ret_ty = qualify declared adt tnames (parse type str ret_str)
        check all functions acc tnames fs locals fns (acc :: sig_errs :: (check fn cases cases name param_tys ret_ty 0 locals fns))

fn :: check all functions [String] [RFnDef] [RTypeBind] [RTypeBind] => [RTypeError]
      check all functions tnames fdefs locals fns =
        check all functions acc tnames fdefs locals fns []

fn :: convert analysis errors [RAnalysisError] => [RTypeError]
      convert analysis errors []               =  []
      convert analysis errors ((ErrWhereCycle fn_name var):es) =
        [TypeError fn_name ("CyclicWhereDependencyError on '" + var + "'")] :: (convert analysis errors es)
      convert analysis errors ((ErrParallelMutation fn_name var):es) =
        [TypeError fn_name ("ParallelMutationConflictError on '" + var + "'")] :: (convert analysis errors es)
      convert analysis errors ((ErrUseAfterSend fn_name var):es) =
        [TypeError fn_name ("UseAfterChannelSendError on '" + var + "'")] :: (convert analysis errors es)

fn :: builtin typedefs => [RTypeDef]
      builtin typedefs =
        [TypeDef "SysOs" [TypeVariant "Linux" [], TypeVariant "MacOS" [], TypeVariant "Windows" []] [], TypeDef "SysArch" [TypeVariant "X86_64" [], TypeVariant "Arm64" []] [], TypeDef "Option" [TypeVariant "None" [], TypeVariant "Some" ["A"]] []]

fn :: typecheck program RProgram => [RTypeError]
      typecheck program (Program fdefs tdefs) =
        all_tdefs = (builtin typedefs) :: tdefs
        tnames = collect typedef names all_tdefs
        env_pair = register typedef list tnames all_tdefs (builtin local types) (builtin fn types)
        typecheck with typedef env tnames (Program fdefs tdefs) fdefs env_pair

fn :: check duplicate fndefs acc [RFnDef] [String] [RTypeError] => [RTypeError]
      check duplicate fndefs acc []       _    acc =  acc
      check duplicate fndefs acc ((FnDef "__unresolved_import__" _ _ _):fs) seen acc =
        check duplicate fndefs acc fs seen acc
      check duplicate fndefs acc ((FnDef "__syntax_error__" _ _ _):fs) seen acc =
        check duplicate fndefs acc fs seen acc
      check duplicate fndefs acc ((FnDef name _ _ _):fs) seen acc
        | str in list name seen =
          check duplicate fndefs acc fs seen (acc :: [TypeError name ("duplicate function definition '" + name + "'; function is already defined")])
        | otherwise =
          check duplicate fndefs acc fs (seen :: [name]) acc

fn :: check duplicate fndefs [RFnDef] [String] => [RTypeError]
      check duplicate fndefs fdefs    seen     =
        check duplicate fndefs acc fdefs seen []

fn :: typecheck with typedef env [String] RProgram [RFnDef] ([RTypeBind], [RTypeBind]) => [RTypeError]
      typecheck with typedef env tnames prog fdefs (locals, fns0) =
        dup_errs = check duplicate fndefs fdefs []
        fns = register fndef sigs tnames fdefs fns0
        ty_errs = check all functions tnames fdefs locals fns
        an_errs = convert analysis errors (analyze program errors prog)
        dup_errs :: ty_errs :: an_errs

fn :: type err count [RTypeError] => Int
type err count []           =  0
type err count (_:xs)       =  1 + (type err count xs)

fn :: format type errors [RTypeError] => [String]
      format type errors []           =  []
      format type errors ((TypeError fn_name msg):es) =
        ["type error in function '" + (decode literal underscores fn_name) + "': " + (decode literal underscores msg)] :: (format type errors es)

fn :: strict words errors [String] String    => [RTypeError]
      strict words errors []       _         =  []
      strict words errors (w:ws)   full_name
        | str contains w "_" = [TypeError full_name ("strict mode: '_' is forbidden in fn/op declaration '" + full_name + "' (token '" + w + "'); use spaces instead")]
        | otherwise = strict words errors ws full_name

fn :: has arrow before rparen [RToken] Int => Bool
      has arrow before rparen [] _ = False
      has arrow before rparen (TokNewline:_) _ = False
      has arrow before rparen (TokEof:_) _ = False
      has arrow before rparen (TokLParen:rest) d = has arrow before rparen rest (d + 1)
      has arrow before rparen (TokRParen:_) 0 = False
      has arrow before rparen (TokRParen:rest) d = has arrow before rparen rest (d - 1)
      has arrow before rparen (TokFatArrow:_) 0 = True
      has arrow before rparen (TokArrow:_) 0 = True
      has arrow before rparen (_:rest) d = has arrow before rparen rest d

fn :: has top comma before nl [RToken] Int => Bool
      has top comma before nl [] _ = False
      has top comma before nl (TokNewline:_) _ = False
      has top comma before nl (TokEof:_) _ = False
      has top comma before nl (TokLParen:rest) d = has top comma before nl rest (d + 1)
      has top comma before nl (TokLBracket:rest) d = has top comma before nl rest (d + 1)
      has top comma before nl (TokIdxLBracket:rest) d = has top comma before nl rest (d + 1)
      has top comma before nl (TokRParen:rest) d = has top comma before nl rest (d - 1)
      has top comma before nl (TokRBracket:rest) d = has top comma before nl rest (d - 1)
      has top comma before nl (TokComma:_) 0 = True
      has top comma before nl (_:rest) d = has top comma before nl rest d

fn :: is bad strict return [RToken]         => Bool
      is bad strict return (TokLParen:TokRParen:rest) = has top comma before nl rest 0
      is bad strict return (TokLParen:rest)
        | NOT (has arrow before rparen rest 0) = True
        | otherwise = has top comma before nl rest 1
      is bad strict return rest             =  has top comma before nl rest 0

fn :: strict ret errors [RToken]    String    => [RTypeError]
      strict ret errors after_arrow full_name
        | is bad strict return after_arrow = [TypeError full_name ("strict mode: tuple output in '" + full_name + "' must use space-separated types (e.g. '=> Int Int'), not '(Int, Int)'")]
        | otherwise = []

fn :: check strict hdr ([String], [String], [Bool], [RToken]) => [RTypeError] [RToken]
      check strict hdr (words, _, _, rest) =
        full_name = join words underscore words
        ((strict words errors words full_name) :: (strict ret errors rest full_name), rest)

fn :: check strict hdr tokens cont ([RTypeError], [RToken]) => [RTypeError]
      check strict hdr tokens cont (errs, rest)             =
        errs :: (check strict hdr tokens rest)

fn :: check strict hdr tokens [RToken]   => [RTypeError]
      check strict hdr tokens []         =  []
      check strict hdr tokens (TokEof:_) =  []
      check strict hdr tokens (TokFn:TokColonColon:rest) =
        check strict hdr tokens cont (check strict hdr (scan op header rest [] [] []))
      check strict hdr tokens (TokOp:TokColonColon:rest) =
        check strict hdr tokens cont (check strict hdr (scan op header rest [] [] []))
      check strict hdr tokens (_:rest)   =
        check strict hdr tokens rest

fn :: strict ident call err String String => [RTypeError]
      strict ident call err fn_name ident
        | str contains ident "__U__" =
          [TypeError fn_name ("strict mode: '_' is forbidden in function call '" + (decode literal underscores ident) + "'; use spaces instead")]
        | otherwise = []

fn :: strict expr errors RExpr String => [RTypeError]
      strict expr errors (EVar v) fn_name =
        strict ident call err fn_name v
      strict expr errors (ENot inner) fn_name =
        strict expr errors inner fn_name
      strict expr errors (EOut inner) fn_name =
        strict expr errors inner fn_name
      strict expr errors (EBin _ l r) fn_name =
        (strict expr errors l fn_name) :: (strict expr errors r fn_name)
      strict expr errors (ECall "__lambda__" args) fn_name =
        strict expr list errors args fn_name
      strict expr errors (ECall "__record_update__" (base_e:rest)) fn_name =
        (strict expr errors base_e fn_name) :: (strict expr list errors rest fn_name)
      strict expr errors (ECall callee args) fn_name =
        (strict ident call err fn_name callee) :: (strict expr list errors args fn_name)
      strict expr errors (EEcho args) fn_name =
        strict expr list errors args fn_name
      strict expr errors (EStrInterp parts) fn_name =
        strict expr list errors parts fn_name
      strict expr errors (EList elems) fn_name =
        strict expr list errors elems fn_name
      strict expr errors (ETuple elems) fn_name =
        strict expr list errors elems fn_name
      strict expr errors (ETensor elems) fn_name =
        strict expr list errors elems fn_name
      strict expr errors (EEinsum es _) fn_name =
        strict expr list errors es fn_name
      strict expr errors (EHadamard _ l _ r _) fn_name =
        (strict expr errors l fn_name) :: (strict expr errors r fn_name)
      strict expr errors (EIndex base idxs) fn_name =
        (strict expr errors base fn_name) :: (strict expr list errors idxs fn_name)
      strict expr errors (EIndexAssign _ idxs v) fn_name =
        (strict expr list errors idxs fn_name) :: (strict expr errors v fn_name)
      strict expr errors (ESeqSelect b _) fn_name =
        strict expr errors b fn_name
      strict expr errors (EBlock stmts) fn_name =
        strict stmt list errors stmts fn_name
      strict expr errors (EGuard gs) fn_name =
        strict guard list errors gs fn_name
      strict expr errors (EWhere b wbs) fn_name =
        (strict expr errors b fn_name) :: (strict where list errors wbs fn_name)
      strict expr errors (EParPipe bs) fn_name =
        strict expr list errors bs fn_name
      strict expr errors (EWithCtx _ v b) fn_name =
        (strict expr errors v fn_name) :: (strict expr errors b fn_name)
      strict expr errors (EWithRegion _ b) fn_name =
        strict expr errors b fn_name
      strict expr errors _ _ = []

fn :: strict expr list errors [RExpr] String => [RTypeError]
      strict expr list errors [] _ = []
      strict expr list errors (e:es) fn_name =
        (strict expr errors e fn_name) :: (strict expr list errors es fn_name)

fn :: strict stmt list errors [RStmt] String => [RTypeError]
      strict stmt list errors [] _ = []
      strict stmt list errors ((StmtLet _ e):ss) fn_name =
        (strict expr errors e fn_name) :: (strict stmt list errors ss fn_name)
      strict stmt list errors ((StmtMut _ e):ss) fn_name =
        (strict expr errors e fn_name) :: (strict stmt list errors ss fn_name)
      strict stmt list errors ((StmtExpr e):ss) fn_name =
        (strict expr errors e fn_name) :: (strict stmt list errors ss fn_name)
      strict stmt list errors ((StmtIndexAssign _ idxs e):ss) fn_name =
        (strict expr list errors idxs fn_name) :: (strict expr errors e fn_name) :: (strict stmt list errors ss fn_name)

fn :: strict guard list errors [RGuard] String => [RTypeError]
      strict guard list errors [] _ = []
      strict guard list errors ((GuardBranch c b):gs) fn_name =
        (strict expr errors c fn_name) :: (strict expr errors b fn_name) :: (strict guard list errors gs fn_name)

fn :: strict where list errors [RWhereBind] String => [RTypeError]
      strict where list errors [] _ = []
      strict where list errors ((WhereBind e _ _):wbs) fn_name =
        (strict expr errors e fn_name) :: (strict where list errors wbs fn_name)

fn :: strict case list errors [RFnCase] String => [RTypeError]
      strict case list errors [] _ = []
      strict case list errors ((FnCase _ gs body):cs) fn_name =
        (strict guard list errors gs fn_name) :: (strict expr errors body fn_name) :: (strict case list errors cs fn_name)

fn :: has strict err for fn [RTypeError] String => Bool
      has strict err for fn [] _ = False
      has strict err for fn ((TypeError f _):es) target
        | f == target = True
        | otherwise = has strict err for fn es target

fn :: strict bare decl err String [RTypeError] => [RTypeError]
      strict bare decl err fname hdr_errs
        | (str contains fname "__U__") and (not (has strict err for fn hdr_errs fname)) =
          [TypeError fname ("strict mode: '_' is forbidden in fn/op declaration '" + (decode literal underscores fname) + "'; use spaces instead")]
        | otherwise = []

fn :: strict fndef list errors [RFnDef] [RTypeError] => [RTypeError]
      strict fndef list errors [] _ = []
      strict fndef list errors ((FnDef fname _ _ cases):fs) hdr_errs =
        (strict bare decl err fname hdr_errs) :: (strict case list errors cases fname) :: (strict fndef list errors fs hdr_errs)

fn :: check strict tokens [RToken] => [RTypeError]
      check strict tokens toks =
        hdr_errs = check strict hdr tokens (user src tokens toks)
        hdr_errs :: (strict fndef list errors (parse strict user fns toks) hdr_errs)
