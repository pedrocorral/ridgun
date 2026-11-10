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
        | (str char at s pos) == 40 or (str char at s pos) == 91 = split by comma loop s start (pos + 1) len (depth + 1) acc
        | (str char at s pos) == 41 or (str char at s pos) == 93 = split by comma loop s start (pos + 1) len (depth - 1) acc
        | depth == 0 and (str char at s pos) == 44 = split by comma loop s (pos + 1) (pos + 1) len 0 (acc :: [trim str (str slice s start pos)])
        | otherwise = split by comma loop s start (pos + 1) len depth acc

fn :: split comma strs String => [String]
      split comma strs ""     =  []
      split comma strs s      =  split by comma loop s 0 0 (str len s) 0 []

fn :: ends with ellipsis String => Bool
      ends with ellipsis s      =
        len = str len s
        len > 3 and (str slice s (len - 3) len) == "..."

fn :: parse type list strs [String] => [RType]
      parse type list strs []       =  []
      parse type list strs (s:ss)   =  [parse type str s] :: (parse type list strs ss)

fn :: is int type name String => Bool
      is int type name s      =
        s == "Int" or s == "Byte" or s == "U8" or s == "U16" or s == "U32" or s == "U64" or s == "I8" or s == "I16" or s == "I32" or s == "I64" or s == "Usize"

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
        | s == "Real" or s == "Float" = TyReal
        | s == "Char" = TyChar
        | s == "String" = TyString
        | s == "Bool" = TyBool
        | s == "Unit" or s == "()" = TyUnit
        | s == "Actor" = TyVar "Agent"
        | s == "Tensor" or s == "Tensor_GPU" = TyTensor (tensor elem any) []
        | str starts with s "Tensor:" = parse typed tensor str (str slice s 7 (str len s))
        | str starts with s "Tensor(" = TyTensor (tensor elem any) (split comma strs (str slice s 7 ((str len s) - 1)))
        | str starts with s "Tensor[" = bracket tensor of s (tc find close bracket s 7 (str len s))
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
      rtype to str (TyTensor e [])    =  "Tensor" + (tensor elem suffix e)
      rtype to str (TyTensor e dims)  =  "Tensor" + (tensor elem suffix e) + "(" + (str join dims ", ") + ")"
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

-- ── Type Unification & Compatibility ────────────────────────

fn :: dims compatible [String] [String] => Bool
      dims compatible []       []       =  True
      dims compatible (a:as)   (b:bs)
        | a == b or a == "_" or b == "_" or (is lower ident a) or (is lower ident b) = dims compatible as bs
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
        | s == "_empty" or s == "_any" or s == "Option" or s == "_chan_or_agent" = True
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
      types compatible (TyTensor e1 d1)   (TyTensor e2 d2)
        | (is u8 elem e1) != (is u8 elem e2) = False
        | otherwise = (types compatible e1 e2) and (tensor dims unify d1 d2)
      types compatible (TyVariadic inner) other              =
        (types compatible inner other) or (types compatible (TyList inner) other)
      types compatible other              (TyVariadic inner) =
        (types compatible inner other) or (types compatible (TyList inner) other)
      types compatible (TyVar a)          (TyVar b)
        | a == b or ("adt:" + a) == b or ("adt:" + b) == a = True
        | (is poly type var a) or (is poly type var b) = True
        | (str starts with a "Option ") and (str starts with b "Option ") = types compatible (parse option inner ty (str slice a 7 (str len a))) (parse option inner ty (str slice b 7 (str len b)))
        | (str starts with a "Option ") and (str starts with b "adt:Option") = True
        | (str starts with a "adt:Option") and (str starts with b "Option ") = True
        | (str starts with a "adt:") and (str starts with b "adt:") and ((str contains a b) or (str contains b a) or (str contains a ("adt:" + (rtype to str (TyVar b)))) or (str contains b ("adt:" + (rtype to str (TyVar a))))) = True
        | otherwise = False
      types compatible (TyVar "Agent")    (TyTuple ((TyVar "Agent"):_)) = True
      types compatible (TyTuple ((TyVar "Agent"):_)) (TyVar "Agent") = True
      types compatible (TyVar "Agent")    (TyTuple ((TyVar "SinkAgent"):_)) = True
      types compatible (TyTuple ((TyVar "SinkAgent"):_)) (TyVar "Agent") = True
      types compatible (TyVar "SinkAgent") (TyTuple ((TyVar "SinkAgent"):_)) = True
      types compatible (TyTuple ((TyVar "SinkAgent"):_)) (TyVar "SinkAgent") = True
      types compatible (TyVar a)          other
        | is u8 param a = u8 param accepts a other
      types compatible other              (TyVar b)
        | is u8 param b = u8 param accepts b other
      types compatible (TyVar "Channel")  TyInt              = True
      types compatible TyInt              (TyVar "Channel")  = True
      types compatible (TyVar a)          other
        | is poly type var a = True
        | (str starts with a "adt:") and (adt accepts prim a other) = True
        | otherwise = False
      types compatible other              (TyVar b)
        | is poly type var b = True
        | (str starts with b "adt:") and (adt accepts prim b other) = True
        | otherwise = False
      types compatible (TyList a)         (TyList b)         =  types compatible a b
      types compatible (TyTuple as)       (TyTuple bs)
        | (list len as) == (list len bs) = types list compatible as bs
        | otherwise = False
      types compatible (TyFun p1 r1)      (TyFun p2 r2)
        | (list len p1) == (list len p2) and (types list compatible p1 p2) = types compatible r1 r2
        | otherwise = False
      types compatible _                  _                  =  False

-- ── Type Environment Lookup & Registration ──────────────────

fn :: embedded variant tag RVariant => String
      embedded variant tag (TypeVariant c (a:[]))
        | c != a = ""
        | is int type name c = "|prim:Int"
        | c == "Real" or c == "Float" = "|prim:Real"
        | c == "String" or c == "Char" = "|prim:String"
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
        | e == target or (str starts with e (target + "|")) = e
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
        [TypeBind "new_mailbox" TyInt, TypeBind "mailbox" TyInt, TypeBind "new_channel" (TyVar "Channel"), TypeBind "channel" (TyVar "Channel"), TypeBind "cli_args" (TyList TyString), TypeBind "sys_os" (TyVar "adt:SysOs"), TypeBind "sys_arch" (TyVar "adt:SysArch"), TypeBind "sys_getcwd" TyString, TypeBind "sys_getuid" TyInt, TypeBind "sys_getgid" TyInt, TypeBind "sys_getpid" TyInt, TypeBind "sys_pipe" (TyTuple [TyInt, TyInt]), TypeBind "sys_time_ms" TyInt, TypeBind "sys_time_ns" TyInt, TypeBind "sys_wall_time_ms" TyInt, TypeBind "sys_deadline_ms" TyInt, TypeBind "sys_remaining_ms" TyInt, TypeBind "cmm_live_blocks" TyInt, TypeBind "cmm_cond_spared" TyInt, TypeBind "cmm_cond_freed" TyInt]

fn :: builtin fn types => [RTypeBind]
      builtin fn types =
        [TypeBind "cli_args" (TyFun [] (TyList TyString)), TypeBind "new_mailbox" (TyFun [] TyInt), TypeBind "new_channel" (TyFun [] (TyVar "Channel")), TypeBind "stop" (TyFun [TyVar "Agent"] TyUnit), TypeBind "agent_alive" (TyFun [TyVar "Agent"] TyBool), TypeBind "agent_dropped" (TyFun [TyVar "Agent"] TyInt), TypeBind "agent_flush" (TyFun [TyVar "Agent"] TyUnit), TypeBind "agent_state" (TyFun [TyVar "Agent"] (TyVar "A")), TypeBind "send_to" (TyFun [TyVar "A", TyVar "Agent"] TyUnit), TypeBind "ask_to" (TyFun [TyVar "A", TyVar "Agent"] (TyVar "B")), TypeBind "new_bounded_channel" (TyFun [TyInt] (TyVar "Channel")), TypeBind "send_through" (TyFun [TyVar "A", TyVar "Channel"] TyUnit), TypeBind "chan_send" (TyFun [TyVar "A", TyVar "Channel"] TyUnit), TypeBind "receive_from" (TyFun [TyVar "_chan_or_agent"] (TyVar "A")), TypeBind "chan_recv" (TyFun [TyVar "Channel"] (TyVar "A")), TypeBind "try_receive_from" (TyFun [TyVar "_chan_or_agent"] (TyVar "Option")), TypeBind "chan_try_recv" (TyFun [TyVar "Channel"] (TyVar "Option")), TypeBind "receive_from_timeout" (TyFun [TyVar "Channel", TyInt] (TyVar "Option")), TypeBind "str_len" (TyFun [TyString] TyInt), TypeBind "sort_by_ints" (TyFun [TyList (TyVar "A"), TyList TyInt] (TyList (TyVar "A"))), TypeBind "sort_by_texts" (TyFun [TyList (TyVar "A"), TyList TyString] (TyList (TyVar "A"))), TypeBind "str_char_at" (TyFun [TyString, TyInt] TyInt), TypeBind "str_slice" (TyFun [TyString, TyInt, TyInt] TyString), TypeBind "char_from_code" (TyFun [TyInt] TyString), TypeBind "str_concat" (TyFun [TyString, TyString] TyString), TypeBind "int_to_str" (TyFun [TyInt] TyString), TypeBind "str_to_int" (TyFun [TyString] TyInt), TypeBind "str_starts_with" (TyFun [TyString, TyString] TyBool), TypeBind "str_contains" (TyFun [TyString, TyString] TyBool), TypeBind "read_file" (TyFun [TyString] TyString), TypeBind "load_rg_source" (TyFun [TyString] TyString), TypeBind "read_bytes" (TyFun [TyString] u8 tensor ty), TypeBind "write_bytes" (TyFun [TyString, TyVar "_u8_or_ints"] TyUnit), TypeBind "write_file" (TyFun [TyString, TyString] TyUnit), TypeBind "shell_exec" (TyFun [TyString] TyInt), TypeBind "map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "seq_map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "||map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "par_map" (TyFun [TyFun [TyVar "A"] (TyVar "B"), TyList (TyVar "A")] (TyList (TyVar "B"))), TypeBind "filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "seq_filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "||filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "par_filter" (TyFun [TyFun [TyVar "A"] TyBool, TyList (TyVar "A")] (TyList (TyVar "A"))), TypeBind "fold" (TyFun [TyFun [TyVar "B", TyVar "A"] (TyVar "B"), TyVar "B", TyList (TyVar "A")] (TyVar "B")), TypeBind "list_dir" (TyFun [TyString] (TyList TyString)), TypeBind "file_lstat" (TyFun [TyString] (TyTuple [TyBool, TyString, TyInt, TyInt, TyInt, TyString, TyString, TyInt, TyString])), TypeBind "sha256_file" (TyFun [TyString] TyString), TypeBind "sha256_str" (TyFun [TyString] TyString), TypeBind "sha256_raw" (TyFun [TyVar "_u8_data"] TyString), TypeBind "sha256_bytes" (TyFun [TyString] TyString), TypeBind "sys_os" (TyFun [] (TyVar "adt:SysOs")), TypeBind "sys_arch" (TyFun [] (TyVar "adt:SysArch")), TypeBind "sys_mkdir" (TyFun [TyString, TyInt] TyInt), TypeBind "sys_chmod" (TyFun [TyString, TyInt] TyInt), TypeBind "sys_exec" (TyFun [TyString, TyList TyString, TyList TyString] TyInt), TypeBind "sys_chdir" (TyFun [TyString] TyInt), TypeBind "sys_getcwd" (TyFun [] TyString), TypeBind "sys_getenv" (TyFun [TyString] TyString), TypeBind "sys_setenv" (TyFun [TyString, TyString] TyInt), TypeBind "sys_exit" (TyFun [TyInt] TyUnit), TypeBind "sys_getuid" (TyFun [] TyInt), TypeBind "sys_getgid" (TyFun [] TyInt), TypeBind "sys_getpid" (TyFun [] TyInt), TypeBind "sys_time_ms" (TyFun [] TyInt), TypeBind "sys_time_ns" (TyFun [] TyInt), TypeBind "sys_wall_time_ms" (TyFun [] TyInt), TypeBind "crc32_range" (TyFun [TyVar "_u8_data", TyInt, TyInt, TyInt] TyInt), TypeBind "tensor_from_str" (TyFun [TyString] u8 tensor ty), TypeBind "tensor_u8_from_list" (TyFun [TyList TyInt] u8 tensor ty), TypeBind "tensor_to_str" (TyFun [u8 tensor ty] TyString), TypeBind "sha256_digest" (TyFun [TyVar "_u8_data"] u8 tensor ty), TypeBind "sys_read_into" (TyFun [TyInt, u8 tensor ty, TyInt, TyInt] TyInt), TypeBind "sys_write_from" (TyFun [TyInt, u8 tensor ty, TyInt, TyInt] TyInt), TypeBind "sys_deadline_ms" (TyFun [] TyInt), TypeBind "sys_remaining_ms" (TyFun [] TyInt), TypeBind "sys_sleep_ms" (TyFun [TyInt] TyUnit), TypeBind "sys_open_mode" (TyFun [TyString, TyString] TyInt), TypeBind "sys_open" (TyFun [TyString, TyInt, TyInt] TyInt), TypeBind "sys_close" (TyFun [TyInt] TyInt), TypeBind "sys_read_fd" (TyFun [TyInt, TyInt] TyString), TypeBind "sys_write_fd" (TyFun [TyInt, TyString] TyInt), TypeBind "sys_poll" (TyFun [TyInt, TyInt, TyInt] TyInt), TypeBind "sys_terminate" (TyFun [TyInt, TyBool] TyInt), TypeBind "sys_kill" (TyFun [TyInt, TyInt] TyInt), TypeBind "sys_call" (TyFun [TyInt, TyVariadic (TyVar "_int_or_u8")] TyInt), TypeBind "sys_pipe" (TyFun [] (TyTuple [TyInt, TyInt])), TypeBind "sys_waitpid" (TyFun [TyInt, TyInt] (TyTuple [TyInt, TyInt])), TypeBind "sys_username" (TyFun [TyInt] TyString), TypeBind "sys_user_groups" (TyFun [TyString] (TyList TyString)), TypeBind "sys_lookup_uid_gid" (TyFun [TyString] (TyTuple [TyInt, TyInt])), TypeBind "sys_setresgid" (TyFun [TyInt] TyInt), TypeBind "sys_setgroups" (TyFun [TyList TyInt] TyInt), TypeBind "sys_setresuid" (TyFun [TyInt] TyInt), TypeBind "sys_execve" (TyFun [TyString, TyList TyString, TyList TyString] TyInt), TypeBind "sys_read_pass" (TyFun [TyString] TyString), TypeBind "cmm_live_blocks" (TyFun [] TyInt), TypeBind "cmm_cond_spared" (TyFun [] TyInt), TypeBind "cmm_cond_freed" (TyFun [] TyInt), TypeBind "cmm_same_ptr" (TyFun [TyVar "A", TyVar "A"] TyBool)]

fn :: join adt ret ty RType RType => RType
      join adt ret ty (TyVar a) (TyVar b)
        | (str starts with a "adt:") and (str starts with b "adt:") and (not (str contains a b)) = TyVar (a + "|" + b)
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

fn :: rev type binds [RTypeBind] [RTypeBind] => [RTypeBind]
      rev type binds [] acc = acc
      rev type binds (x:xs) acc = rev type binds xs ([x] :: acc)

fn :: infer gagent ret from step Bool (Bool, RType) => RType
      infer gagent ret from step True (True, (TyFun (s_ty:msg_params) _)) =
        TyTuple [TyVar "SinkAgent", pack agent msg ty msg_params, s_ty]
      infer gagent ret from step False (True, (TyFun msg_params _)) =
        TyTuple [TyVar "SinkAgent", pack agent msg ty msg_params, TyUnit]
      infer gagent ret from step _ _ =
        TyTuple [TyVar "SinkAgent", TyVar "_any", TyVar "_any"]

fn :: infer gagent ret [RFnCase] [RTypeBind] => RType
      infer gagent ret ((FnCase _ _ (ECall "__gagent_get__" (_:(ECall "agent_sink" ((EVar step_fn):_:(EInt _):(EInt _):[])):[]))):_) fns =
        infer gagent ret from step True (lookup type bind fns step_fn)
      infer gagent ret ((FnCase _ _ (ECall "__gagent_get__" (_:(ECall "agent_sink" ((EVar step_fn):(EInt _):(EInt _):[])):[]))):_) fns =
        infer gagent ret from step False (lookup type bind fns step_fn)
      infer gagent ret _ _ =
        TyTuple [TyVar "SinkAgent", TyVar "_any", TyVar "_any"]

fn :: resolve gagent sigs [RFnDef] [RTypeBind] [RTypeBind] => [RTypeBind]
      resolve gagent sigs [] _ fns = fns
      resolve gagent sigs ((FnDef name [] "__sink_agent__" cases):fs) all_fns fns =
        ret_ty = infer gagent ret cases all_fns
        resolve gagent sigs fs all_fns ([TypeBind name (TyFun [] ret_ty)] :: fns)
      resolve gagent sigs (_:fs) all_fns fns =
        resolve gagent sigs fs all_fns fns

fn :: register fndef sigs acc [String] [RFnDef] [RTypeBind] => [RTypeBind]
      register fndef sigs acc _ [] acc = acc
      register fndef sigs acc tnames ((FnDef name param_strs ret_str _):fs) acc =
        param_tys = qualify declared adt list tnames (parse type list strs param_strs)
        ret_ty = qualify declared adt tnames (parse type str ret_str)
        register fndef sigs acc tnames fs ([TypeBind name (TyFun param_tys ret_ty)] :: acc)

fn :: register fndef sigs [String] [RFnDef] [RTypeBind] => [RTypeBind]
      register fndef sigs tnames fdefs fns0 =
        fns1 = rev type binds (register fndef sigs acc tnames fdefs []) fns0
        resolve gagent sigs fdefs fns1 fns1

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
        | k == target and (list len params) == arity and (types compatible ret_ty expected) = (True, params)
        | otherwise = lookup ctor for type rest target expected arity
      lookup ctor for type (_:rest) target expected arity =
        lookup ctor for type rest target expected arity

fn :: lookup ctor by arity [RTypeBind] String Int => Bool [RType]
      lookup ctor by arity [] _ _ = (False, [])
      lookup ctor by arity ((TypeBind k (TyFun params _)):rest) target arity
        | k == target and (list len params) == arity = (True, params)
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
      tensor pat expected (TyTensor e d) =  TyTensor e d
      tensor pat expected _            =  TyTensor (tensor elem any) []

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
        | pd == "_" or ad == "_" = (dim_env, [])
        | bound != ad = (dim_env, [TypeError fn_name ("tensor dimension mismatch in call to '" + callee + "': symbolic dim '" + pd + "' bound to both '" + bound + "' and '" + ad + "'")])
        | otherwise = (dim_env, [])
      check single dim ad pd _ _ (False, _) dim_env
        | pd == "_" or ad == "_" = (dim_env, [])
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
      check einsum one ((TyTensor e dims), errs1) sub fn_name dim_env
        | gen tensor ty (TyTensor e dims) = (dim_env, errs1 :: (numeric tensor arg errs "einsum (@)" [TyTensor e dims] fn_name))
        | (str list count dims) > 0 and (str list count dims) == (str len sub) = merge dim errs errs1 (bind or check dims dims (sub chars to strs sub 0 (str len sub)) "einsum" fn_name dim_env)
        | otherwise = (dim_env, errs1)
      check einsum one (_, errs1) _ _ dim_env = (dim_env, errs1)

fn :: check einsum cont [RExpr] [String] String [RTypeBind] [RTypeBind] ([RDimBind], [RTypeError]) => [RDimBind] [RTypeError]
      check einsum cont es subs fn_name locals fns (dim_env1, errs1) =
        more = check einsum terms es subs fn_name locals fns dim_env1
        merge dim errs errs1 more

-- ── Binary Operator Type Checking ───────────────────────────

fn :: is poly tyvar RType     => Bool
      is poly tyvar (TyVar s) =  (is lower ident s) or (is poly type var s)
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
        | (types compatible l_ty p1) and (types compatible r_ty p2) = (ret_ty, [])
      check overload lookup sym l_ty r_ty _ fn_name =
        (TyInt, [TypeError fn_name ("arithmetic operator " + sym + " requires numeric or overloaded operands, got " + (rtype to str l_ty) + " and " + (rtype to str r_ty))])

fn :: check arith binop RBinOp RType RType [RTypeBind] String => RType [RTypeError]
      check arith binop bop (TyTensor e1 d1) (TyTensor e2 d2) _ fn_name = (TyTensor e1 d1, numeric tensor errs ("arithmetic operator " + (binop symbol bop)) (TyTensor e1 d1) (TyTensor e2 d2) fn_name)
      check arith binop bop l_ty r_ty fns fn_name
        | (is int or poly l_ty) and (is int or poly r_ty) = (TyInt, [])
        | (is real or poly l_ty) and (is real or poly r_ty) = (TyReal, [])
        | bop == OpAdd and (is str or poly l_ty) and (is str or poly r_ty) = (TyString, [])
        | otherwise = check overloaded arith bop l_ty r_ty fns fn_name

fn :: check matmul binop RType RType String => RType [RTypeError]
      check matmul binop l r fn_name =  check matmul dims l r fn_name (numeric tensor errs "matrix product" l r fn_name)

fn :: check matmul dims RType RType String [RTypeError] => RType [RTypeError]
      check matmul dims (TyTensor e1 (d1a:d1b:[])) (TyTensor _ (d2a:d2b:[])) fn_name errs
        | d1b != d2a = (TyTensor e1 [d1a, d2b], errs :: [TypeError fn_name ("tensor contraction dimension mismatch: " + d1b + " vs " + d2a)])
        | otherwise = (TyTensor e1 [d1a, d2b], errs)
      check matmul dims _ _ _ errs = (TyTensor (tensor elem any) [], errs)

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
        | (types compatible l TyBool) and (types compatible r TyBool) = (TyBool, [])
        | (is int or poly l) and (is int or poly r) = (TyInt, [])
        | (types compatible l (TyTensor (tensor elem any) [])) and (types compatible r (TyTensor (tensor elem any) [])) = (l, numeric tensor errs "a bitwise operator" l r fn_name)
        | otherwise = check overloaded arith OpAnd l r fns fn_name
      check binop OpOr l r fns fn_name
        | (types compatible l TyBool) and (types compatible r TyBool) = (TyBool, [])
        | (is int or poly l) and (is int or poly r) = (TyInt, [])
        | (types compatible l (TyTensor (tensor elem any) [])) and (types compatible r (TyTensor (tensor elem any) [])) = (l, numeric tensor errs "a bitwise operator" l r fn_name)
        | otherwise = check overloaded arith OpOr l r fns fn_name
      check binop OpXor l r fns fn_name
        | (types compatible l TyBool) and (types compatible r TyBool) = (TyBool, [])
        | (is int or poly l) and (is int or poly r) = (TyInt, [])
        | (types compatible l (TyTensor (tensor elem any) [])) and (types compatible r (TyTensor (tensor elem any) [])) = (l, numeric tensor errs "a bitwise operator" l r fn_name)
        | otherwise = check overloaded arith OpXor l r fns fn_name
      check binop _ l r _ fn_name
        | (types compatible l TyInt and types compatible r TyInt) or (types compatible l TyReal and types compatible r TyReal) or (types compatible l TyChar and types compatible r TyChar) or (types compatible l TyString and types compatible r TyString) = (TyBool, [])
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
        | plus_c == 0 and space_c >= 1 = TyVar "_seq"
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
        | idx < 0 or idx >= tup_len =
          (TyInt, [TypeError fn_name ("sequence mask index " + (int to str idx) + " is out of range for tuple of length " + (int to str tup_len))])
        | otherwise =
          (rtype at elem_tys idx, [])

fn :: scan index mask tys [RType] String Int Int Int Int String [RType] [RTypeError] => RType [RTypeError]
      scan index mask tys elem_tys mask start pos len tup_len fn_name acc_tys acc_errs
        | pos >= len and start >= len =
          (wrap selected mask tys acc_tys, acc_errs)
        | pos >= len =
          idx = str to int (str slice mask start len)
          one_res = check one index mask elem_tys idx tup_len fn_name
          (wrap selected mask tys (acc_tys :: [fst ty one_res]), acc_errs :: (snd errs one_res))
        | (str char at mask pos) == 32 and pos > start =
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
        | (str len mask) >= 2 and (str slice mask ((str len mask) - 2) (str len mask)) == " +" =
          check tuple spread mask elem_tys mask ((str len mask) - 2) (list len elem_tys) b_errs fn_name
        | not (str contains mask " ") =
          check tuple pos mask elem_tys mask (str len mask) (list len elem_tys) b_errs fn_name
        | otherwise =
          scan index mask tys elem_tys mask 0 0 (str len mask) (list len elem_tys) fn_name [] b_errs

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
      extract subscript ty (False, _)    =  (TyTensor (tensor elem any) [], [])

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
        | (list len p1) > 1 and (list len p2) == 1 =
          "; note: '(a b => ...)' has multiple parameters — use '((a b) => ...)' to destructure a tuple"
        | (list len p1) == 1 and (list len p2) > 1 =
          "; note: '((a b) => ...)' takes 1 tuple parameter — use '(a b => ...)' for multiple parameters"
        | otherwise = ""
      lambda tuple arity hint _ _ = ""

fn :: check fixed args [RType] [RType] String String Int [RDimBind] => [RTypeError]
      check fixed args [] _ _ _ _ _ = []
      check fixed args _ [] _ _ _ _ = []
      check fixed args (arg:args) (param:params) callee fn_name idx dim_env
        | not (types compatible arg param) = [TypeError fn_name ("function '" + callee + "' arg #" + (int to str idx) + " has type " + (rtype to str arg) + ", expected " + (rtype to str param) + (lambda tuple arity hint arg param))] :: (check fixed args args params callee fn_name (idx + 1) dim_env)
        | otherwise = check arg tensor dims arg param args params callee fn_name idx dim_env

fn :: check arg tensor dims RType RType [RType] [RType] String String Int [RDimBind] => [RTypeError]
      check arg tensor dims (TyTensor _ adims) (TyTensor _ pdims) args params callee fn_name idx dim_env
        | (str list count adims) > 0 and (str list count adims) == (str list count pdims) = check arg tensor dims step (bind or check dims adims pdims callee fn_name dim_env) args params callee fn_name idx
      check arg tensor dims _ _ args params callee fn_name idx dim_env =
        check fixed args args params callee fn_name (idx + 1) dim_env

fn :: check arg tensor dims step ([RDimBind], [RTypeError]) [RType] [RType] String String Int => [RTypeError]
      check arg tensor dims step (dim_env1, dim_errs) args params callee fn_name idx =
        dim_errs :: (check fixed args args params callee fn_name (idx + 1) dim_env1)

fn :: check variadic args [RType] RType String String Int => [RTypeError]
      check variadic args [] _ _ _ _ = []
      check variadic args (arg:args) var_ty callee fn_name idx
        | (types compatible arg var_ty) or (types compatible arg (TyList var_ty)) = check variadic args args var_ty callee fn_name (idx + 1)
        | otherwise = [TypeError fn_name ("function '" + callee + "' variadic arg #" + (int to str idx) + " has type " + (rtype to str arg) + ", expected " + (rtype to str var_ty))] :: (check variadic args args var_ty callee fn_name (idx + 1))

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
        | (list len rest_args) >= 1 and (types compatible first_arg rec_param) =
          check call sig callee rest_args inner_params inner_ret fn_name
      check call sig callee arg_tys param_tys ret_ty fn_name
        | is last variadic param_tys = check variadic call callee arg_tys param_tys ret_ty fn_name
        | (list len arg_tys) == 1 and (list len param_tys) > 1 = check tuple chain call callee (rtype at arg_tys 0) arg_tys param_tys ret_ty fn_name
        | (list len arg_tys) > 1 and (list len arg_tys) < (list len param_tys) =
          k = list len arg_tys
          taken_params = list take param_tys k
          rem_params = list drop param_tys k
          finish poly call (TyFun rem_params ret_ty) (check fixed args arg_tys taken_params callee fn_name 0 []) (collect poly binds list arg_tys taken_params callee fn_name [])
        | (list len arg_tys) != (list len param_tys) = (ret_ty, [TypeError fn_name ("function '" + callee + "' called with " + (int to str (list len arg_tys)) + " argument(s), expected " + (int to str (list len param_tys)))])
        | otherwise = finish poly call ret_ty (check fixed args arg_tys param_tys callee fn_name 0 []) (collect poly binds list arg_tys param_tys callee fn_name [])

fn :: check variadic call String [RType] [RType] RType String => RType [RTypeError]
      check variadic call callee arg_tys param_tys ret_ty fn_name =
        fixed = (list len param_tys) - 1
        var_ty = last variadic inner param_tys
        check variadic call counts callee arg_tys param_tys ret_ty fn_name fixed var_ty

fn :: check variadic call counts String [RType] [RType] RType String Int RType => RType [RTypeError]
      check variadic call counts callee arg_tys param_tys ret_ty fn_name fixed var_ty
        | (list len arg_tys) < fixed = (ret_ty, [TypeError fn_name ("function '" + callee + "' called with " + (int to str (list len arg_tys)) + " argument(s), expected at least " + (int to str fixed))])
        | otherwise = (ret_ty, (check fixed args (list take arg_tys fixed) (list take param_tys fixed) callee fn_name 0 []) :: (check variadic args (list drop arg_tys fixed) var_ty callee fn_name fixed))

fn :: check tuple chain call String RType [RType] [RType] RType String => RType [RTypeError]
      check tuple chain call callee (TyTuple elems) _ param_tys ret_ty fn_name
        | (list len elems) == (list len param_tys) = finish poly call ret_ty (check fixed args elems param_tys callee fn_name 0 []) (collect poly binds list elems param_tys callee fn_name [])
      check tuple chain call _ (TyVar "_seq") _ _ ret_ty _ = (ret_ty, [])
      check tuple chain call callee first_arg arg_tys param_tys ret_ty fn_name
        | types compatible first_arg (rtype at param_tys 0) =
          taken_params = list take param_tys 1
          rem_params = list drop param_tys 1
          finish poly call (TyFun rem_params ret_ty) (check fixed args arg_tys taken_params callee fn_name 0 []) (collect poly binds list arg_tys taken_params callee fn_name [])
        | otherwise =
          (ret_ty, [TypeError fn_name ("function '" + callee + "' called with " + (int to str (list len arg_tys)) + " argument(s), expected " + (int to str (list len param_tys)))])

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
        | k == target and (types compatible base_ty rec_ty) = (True, TyFun [rec_ty] fty)
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
        | not (types compatible base_ty rec_ty) = val_errs :: [TypeError fn_name ("record field '" + fname + "' belongs to " + (rtype to str rec_ty) + ", not " + (rtype to str base_ty))]
        | not (types compatible val_ty fty) = val_errs :: [TypeError fn_name ("record field '" + fname + "' has type " + (rtype to str val_ty) + ", expected " + (rtype to str fty))]
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
        with show tensor facts fn_name parts p_res (discard tys return TyString p_res)
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
        finish einsum check (einsum elem es fn_name locals fns) e_res
      check expr (EHadamard _ l _ r _) fn_name locals fns =
        l_res = check expr l fn_name locals fns
        r_res = check expr r fn_name locals fns
        finish hadamard check l_res r_res fn_name
      check expr (EVar name) fn_name locals fns =
        lookup var type name fn_name locals fns
      check expr (EBin OpAdd (EVar v) r) fn_name locals fns =
        l_res = check expr (EVar v) fn_name locals fns
        r_res = check expr r fn_name locals fns
        str add fact fn_name v (finish binop check OpAdd l_res r_res fns fn_name)
      check expr (EBin bop l r) fn_name locals fns =
        l_res = check expr l fn_name locals fns
        r_res = check expr r fn_name locals fns
        finish binop check bop l_res r_res fns fn_name
      check expr (ECall "__record_update__" (base_e:rest_args)) fn_name locals fns =
        b_res = check expr base_e fn_name locals fns
        check record update fields b_res rest_args fn_name locals fns
      check expr (ECall "__missing_import__" ((EStr mod_name):_)) _ _ _ =
        (TyInt, [TypeError "import" ("unresolved import '" + mod_name + "': module not found in project or .stable/deps")])
      check expr (ECall ":typed-tensor:" ((EStr elem_ty):(ECall ":gt-new:" ((ECall ":gt-no-default:" _):_)):_)) fn_name _ _ =
        (TyTensor (parse type str elem_ty) [], [TypeError fn_name ("a tensor of " + elem_ty + " has no default element value; give one with 'Tensor[" + elem_ty + " * n] with v'")])
      check expr (ECall ":typed-tensor:" ((EStr elem_ty):(ECall ":tensor-with:" (v:dims)):_)) fn_name locals fns =
        typed tensor with check elem_ty v (ECall ":tensor-with:" (v:dims)) fn_name locals fns
      check expr (ECall ":typed-tensor:" ((EStr elem_ty):(ECall ":gt-new:" (v:dims)):_)) fn_name locals fns =
        typed tensor with check elem_ty v (ECall ":gt-new:" (v:dims)) fn_name locals fns
      check expr (ECall ":typed-tensor:" ((EStr elem_ty):inner:_)) fn_name locals fns =
        typed tensor result elem_ty (check expr inner fn_name locals fns)
      check expr (ECall ":gt-new:" args) fn_name locals fns
        | (tc expr count args) > 3 = (TyTensor (tensor elem any) [], [TypeError fn_name "a tensor of non-numeric elements has one or two dimensions"])
        | otherwise = discard tys return (TyTensor (tensor elem any) []) (check expr list args fn_name locals fns)
      check expr (ECall ":char-zero:" []) _ _ _ =  (TyString, [])
      check expr (ECall ":tensor-with:" args) fn_name locals fns =
        discard tys return (TyTensor (tensor elem any) []) (check expr list args fn_name locals fns)
      check expr (ECall "tensor_from_list" (xs:[])) fn_name locals fns =
        tensor from list result (check expr xs fn_name locals fns) fn_name
      check expr (ECall "tensor_to_list" (t:[])) fn_name locals fns =
        t_res = check expr t fn_name locals fns
        with u8 use errs fn_name t (fst ty t_res) (tensor to list result t_res fn_name)
      check expr (ECall "sha256_raw" (d:[])) fn_name locals fns =
        d_res = check expr d fn_name locals fns
        with u8 use errs fn_name d (fst ty d_res) (with u8 call fact fn_name "sha256_raw" (finish call check "sha256_raw" ([fst ty d_res], snd errs d_res) fn_name locals fns))
      check expr (ECall "__syntax_error__" ((EStr msg):_)) _ _ _ =
        (TyVar "_any", [TypeError "syntax" msg])
      check expr (ECall callee args) fn_name locals fns =
        args_res = check expr list args fn_name locals fns
        with u8 call fact fn_name callee (with msg copy facts callee args args_res fn_name fns (finish call check callee args_res fn_name locals fns))
      check expr (EEcho args) fn_name locals fns =
        args_res = check expr list args fn_name locals fns
        with show tensor facts fn_name args args_res (discard tys return TyUnit args_res)
      check expr (EList []) _ _ _ = (TyList (TyVar "_empty"), [])
      check expr (EList elems) fn_name locals fns =
        finish list type (check expr list elems fn_name locals fns) fn_name
      check expr (ETuple elems) fn_name locals fns =
        finish tuple type (check expr list elems fn_name locals fns)
      check expr (ETensor elems) fn_name locals fns =
        args_res = check expr list elems fn_name locals fns
        tys = fst list tys args_res
        (TyTensor (tensor literal elem tys) [], (snd list errs args_res) :: (tensor literal errs tys fn_name) :: (tensor literal mix errs tys fn_name))
      check expr (EIndex base idxs) fn_name locals fns =
        b_res = check expr base fn_name locals fns
        i_res = check expr list idxs fn_name locals fns
        (infer index expr ty (fst ty b_res) idxs, (snd errs b_res) :: (snd list errs i_res) :: (u8 use errs fn_name base (fst ty b_res)))
      check expr (EIndexAssign tname idxs val_e) fn_name locals fns =
        i_res = check expr list idxs fn_name locals fns
        v_res = check expr val_e fn_name locals fns
        w_errs = check tensor elem write tname (fst ty v_res) fn_name locals
        (TyUnit, (snd list errs i_res) :: (snd errs v_res) :: w_errs)
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
      infer index expr ty (TyTensor e dims) idxs = tensor index ty e dims (tc expr count idxs)
      infer index expr ty _ _ = TyInt

-- ── Tensor element types (FR-COMP-020 §2) ─────────────────────
-- `TyTensor e dims`: `e` is the element type, or `TyVar "_any"` when the
-- source gives none (a bare `Tensor`, a literal, a slice). Reading an
-- element of unknown type gives `Int`, as before element types existed.

fn :: tensor elem any => RType
      tensor elem any =  TyVar "_any"

fn :: tensor elem suffix RType => String
      tensor elem suffix (TyVar "_any") =  ""
      tensor elem suffix e              =  "[" + (rtype to str e) + "]"

fn :: tensor elem read ty RType => RType
      tensor elem read ty (TyVar "_any") =  TyInt
      tensor elem read ty (TyVar "U8")   =  TyInt
      tensor elem read ty e              =  e

fn :: tc expr count [RExpr] => Int
      tc expr count []     =  0
      tc expr count (_:xs) =  1 + (tc expr count xs)

fn :: tc str count [String] => Int
      tc str count []     =  0
      tc str count (_:xs) =  1 + (tc str count xs)

fn :: tensor index ty RType [String] Int => RType
      tensor index ty e [] _ =  tensor elem read ty e
      tensor index ty e dims n
        | n < (tc str count dims) = TyTensor e (list drop dims n)
        | otherwise = tensor elem read ty e

-- `Tensor:E` or `Tensor:E@d1,d2` from the parser, without "Tensor:".
fn :: parse typed tensor str String => RType
      parse typed tensor str rest =
        p = tc find at sign rest 0 (str len rest)
        typed tensor of (str slice rest 0 p) (str slice rest p (str len rest))

fn :: tc find at sign String Int Int => Int
      tc find at sign s pos len
        | pos >= len = len
        | (str char at s pos) == 64 = pos
        | otherwise = tc find at sign s (pos + 1) len

-- `Tensor[E]` and `Tensor[E](d1, d2)`, the form `rtype to str` writes;
-- types that travel as strings (e.g. inside `Option`) read back as tensors.
fn :: bracket tensor of String Int => RType
      bracket tensor of s p =  bracket tensor dims (str slice s 7 p) (str slice s (p + 1) (str len s))

fn :: bracket tensor dims String String => RType
      bracket tensor dims e ""   =  TyTensor (tensor elem type str e) []
      bracket tensor dims e dims =  TyTensor (tensor elem type str e) (split comma strs (str slice dims 1 ((str len dims) - 1)))

fn :: tc find close bracket String Int Int => Int
      tc find close bracket s pos len
        | pos >= len = len
        | (str char at s pos) == 93 = pos
        | otherwise = tc find close bracket s (pos + 1) len

fn :: typed tensor of String String => RType
      typed tensor of e ""   =  TyTensor (tensor elem type str e) []
      typed tensor of e dims =  TyTensor (tensor elem type str e) (split comma strs (str slice dims 1 (str len dims)))

fn :: typed tensor result String (RType, [RTypeError]) => RType [RTypeError]
      typed tensor result e ((TyTensor _ dims), errs) =  (TyTensor (tensor elem type str e) dims, errs)
      typed tensor result e (_, errs)                  =  (TyTensor (tensor elem type str e) [], errs)

-- ── Packed byte tensors (FR-COMP-022) ─────────────────────────
-- In element position `U8` and `Byte` are their own type, `TyVar "U8"`:
-- a `Tensor[U8]` stores one byte per element, so it is compatible only
-- with another `Tensor[U8]` (not with `Tensor[Int]`, a bare `Tensor` or
-- `Tensor[T]`). Lowering then always knows when a tensor is packed
-- (element kind "B"). Reading an element gives an `Int`; writing takes one.
fn :: tensor elem type str String => RType
      tensor elem type str e
        | e == "U8" or e == "Byte" = u8 elem ty
        | otherwise = parse type str e

fn :: u8 elem ty => RType
      u8 elem ty =  TyVar "U8"

fn :: u8 tensor ty => RType
      u8 tensor ty =  TyTensor u8 elem ty []

fn :: is u8 elem RType => Bool
      is u8 elem (TyVar "U8") =  True
      is u8 elem _            =  False

fn :: is u8 tensor RType => Bool
      is u8 tensor (TyTensor (TyVar "U8") _) =  True
      is u8 tensor _                          =  False

-- Builtin parameters that take a String or a `Tensor[U8]` ("_u8_data"),
-- a `Tensor[U8]` or a list of Ints ("_u8_or_ints", `write bytes`), and an
-- Int or a `Tensor[U8]` ("_int_or_u8", `sys call` arguments).
fn :: u8 param accepts String RType => Bool
      u8 param accepts "_u8_data" t =  (is u8 tensor t) or (types compatible TyString t)
      u8 param accepts "_u8_or_ints" t =  (is u8 tensor t) or (types compatible (TyList TyInt) t)
      u8 param accepts "_int_or_u8" t =  (is u8 tensor t) or (types compatible TyInt t)
      u8 param accepts _ _ =  False

fn :: is u8 param String => Bool
      is u8 param s =  s == "_u8_data" or s == "_u8_or_ints" or s == "_int_or_u8"

-- Writing `t_(i) = v` checks `v` against the element type of `t`.
fn :: check tensor elem write String RType String [RTypeBind] => [RTypeError]
      check tensor elem write tname val_ty fn_name locals =
        tensor elem write errs tname val_ty fn_name (lookup type bind locals tname)

fn :: tensor elem write errs String RType String (Bool, RType) => [RTypeError]
      tensor elem write errs tname val_ty fn_name (True, (TyTensor e _))
        | is u8 elem e and (types compatible TyInt val_ty) = []
        | types compatible e val_ty = []
        | otherwise = [TypeError fn_name ("cannot store " + (rtype to str val_ty) + " in an element of tensor '" + tname + "' of " + (rtype to str e))]
      tensor elem write errs _ _ _ _ =  []

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
        | types compatible inner_ty (TyTensor (tensor elem any) []) = (inner_ty, errs :: (numeric tensor arg errs "not" [inner_ty] fn_name))
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

-- The result of `@` has the element type of its first operand, so `echo`
-- and later reads of a `Real` contraction see `Real`s.
fn :: einsum elem [RExpr] String [RTypeBind] [RTypeBind] => RType
      einsum elem (e:_) fn_name locals fns =  einsum elem of (check expr e fn_name locals fns)
      einsum elem [] _ _ _ =  tensor elem any

fn :: einsum elem of (RType, [RTypeError]) => RType
      einsum elem of ((TyTensor el _), _) =  el
      einsum elem of _ =  tensor elem any

fn :: finish einsum check RType ([RDimBind], [RTypeError]) => RType [RTypeError]
      finish einsum check el (_, errs)               =  (TyTensor el [], errs)

fn :: finish hadamard check (RType, [RTypeError]) (RType, [RTypeError]) String => RType [RTypeError]
      finish hadamard check ((TyTensor e dims), l_errs) (r_ty, r_errs) fn_name = (TyTensor e dims, l_errs :: r_errs :: (numeric tensor errs "element-wise operator" (TyTensor e dims) r_ty fn_name))
      finish hadamard check (l_ty, l_errs) (r_ty, r_errs) fn_name = (TyTensor (tensor elem any) [], l_errs :: r_errs :: (numeric tensor errs "element-wise operator" l_ty r_ty fn_name))

-- `v + r` on Strings records that `v` is a String (fact `fn|$v|S`): in a
-- tail position lowering then appends to `v` in place when it is its last
-- use and has one owner (OPT-020).
fn :: str add fact String String (RType, [RTypeError]) => RType [RTypeError]
      str add fact fn_name v (TyString, errs) =  (TyString, errs :: [TypeError ":tensor-elem:" (fn_name + "|$" + v + "|S")])
      str add fact _ _ res =  res

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
        | k == target and (list len param_tys) == (list len arg_tys) and (args match params arg_tys param_tys) and (is upper ident target) = [TyFun param_tys ret_ty] :: (collect matching sigs rest target arg_tys)
        | k == target and (list len param_tys) == (list len arg_tys) and (args match params arg_tys param_tys) = [TyFun param_tys ret_ty]
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
        | (types compatible r1 s_ty) and (not (types compatible (TyTuple [r1, r2]) s_ty)) = r2
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

fn :: check agent sink create [RType] [RTypeError] String => RType [RTypeError]
      check agent sink create ((TyFun params _):_:_:[]) arg_errs _ =
        (TyTuple [TyVar "SinkAgent", pack agent msg ty params, TyUnit], arg_errs)
      check agent sink create ((TyFun (s_ty:msg_params) ret_ty):init_ty:_:_:[]) arg_errs fn_name
        | (types compatible init_ty s_ty) and (types compatible ret_ty s_ty) =
          (TyTuple [TyVar "SinkAgent", pack agent msg ty msg_params, s_ty], arg_errs)
        | not (types compatible init_ty s_ty) =
          err = TypeError fn_name ("sink agent initial state has type " + (rtype to str init_ty) + ", expected " + (rtype to str s_ty))
          (TyTuple [TyVar "SinkAgent", pack agent msg ty msg_params, s_ty], arg_errs :: [err])
        | otherwise =
          err = TypeError fn_name ("sink agent step function returns " + (rtype to str ret_ty) + ", expected state type " + (rtype to str s_ty))
          (TyTuple [TyVar "SinkAgent", pack agent msg ty msg_params, s_ty], arg_errs :: [err])
      check agent sink create _ arg_errs fn_name =
        (TyVar "SinkAgent", arg_errs :: [TypeError fn_name "agent sink expects a step function and optional initial state"])

fn :: check gagent get [RType] [RTypeError] => RType [RTypeError]
      check gagent get (_:sink_ty:[]) arg_errs = (sink_ty, arg_errs)
      check gagent get _ arg_errs = (TyVar "SinkAgent", arg_errs)

fn :: check with agent call [RType] [RTypeError] String => RType [RTypeError]
      check with agent call (ag_ty:rep_ty:body_ty:[]) arg_errs fn_name
        | types compatible ag_ty rep_ty = (body_ty, arg_errs)
        | otherwise =
          (body_ty, arg_errs :: [TypeError fn_name ("with agent replacement has type " + (rtype to str rep_ty) + ", expected " + (rtype to str ag_ty))])
      check with agent call _ arg_errs _ = (TyUnit, arg_errs)

fn :: check agent send [RType] [RTypeError] String => RType [RTypeError]
      check agent send (msg_ty:(TyTuple ((TyVar "Agent"):in_ty:_)):[]) arg_errs fn_name
        | types compatible msg_ty in_ty = (TyUnit, arg_errs)
        | otherwise =
          (TyUnit, arg_errs :: [TypeError fn_name ("agent message has type " + (rtype to str msg_ty) + ", expected " + (rtype to str in_ty))])
      check agent send (msg_ty:(TyTuple ((TyVar "SinkAgent"):in_ty:_)):[]) arg_errs fn_name
        | types compatible msg_ty in_ty = (TyUnit, arg_errs)
        | otherwise =
          (TyUnit, arg_errs :: [TypeError fn_name ("sink agent message has type " + (rtype to str msg_ty) + ", expected " + (rtype to str in_ty))])
      check agent send (_:(TyVar "Agent"):[]) arg_errs _ = (TyUnit, arg_errs)
      check agent send (_:(TyVar "SinkAgent"):[]) arg_errs _ = (TyUnit, arg_errs)
      check agent send _ arg_errs _ = (TyUnit, arg_errs)

fn :: specialize hof return String [RType] (RType, [RTypeError]) => RType [RTypeError]
      specialize hof return "map" ((TyFun _ f_ret):_) (_, errs) = (TyList f_ret, errs)
      specialize hof return "||map" ((TyFun _ f_ret):_) (_, errs) = (TyList f_ret, errs)
      specialize hof return "filter" (_:list_ty:_) (_, errs) = (list_ty, errs)
      specialize hof return "||filter" (_:list_ty:_) (_, errs) = (list_ty, errs)
      specialize hof return "fold" (_:init_ty:_) (_, errs) = (init_ty, errs)
      specialize hof return "receive_from" ((TyTuple ((TyVar "Agent"):_:out_ty:[])):_) (_, errs) = (out_ty, errs)
      specialize hof return "try_receive_from" ((TyTuple ((TyVar "Agent"):_:out_ty:[])):_) (_, errs) = (make option type out_ty, errs)
      specialize hof return "agent_state" ((TyTuple ((TyVar "SinkAgent"):_:st_ty:[])):_) (_, errs) = (st_ty, errs)
      specialize hof return "agent_state" ((TyTuple ((TyVar "Agent"):_:st_ty:[])):_) (_, errs) = (st_ty, errs)
      specialize hof return "Some" (elem_ty:[]) (_, errs) = (make option type elem_ty, errs)
      specialize hof return _ _ res = res

fn :: check agent ask [RType] [RTypeError] String => RType [RTypeError]
      check agent ask (_:(TyTuple ((TyVar "SinkAgent"):_)):[]) arg_errs fn_name =
        (TyUnit, arg_errs :: [TypeError fn_name "cannot 'ask' a sink agent; sink agents are fire-and-forget and produce no output"])
      check agent ask (_:(TyVar "SinkAgent"):[]) arg_errs fn_name =
        (TyUnit, arg_errs :: [TypeError fn_name "cannot 'ask' a sink agent; sink agents are fire-and-forget and produce no output"])
      check agent ask (msg_ty:(TyTuple ((TyVar "Agent"):in_ty:out_ty:[])):[]) arg_errs fn_name
        | types compatible msg_ty in_ty = (out_ty, arg_errs)
        | otherwise =
          (out_ty, arg_errs :: [TypeError fn_name ("agent message has type " + (rtype to str msg_ty) + ", expected " + (rtype to str in_ty))])
      check agent ask (_:(TyVar "Agent"):[]) arg_errs _ = (TyVar "A", arg_errs)
      check agent ask _ arg_errs _ = (TyVar "A", arg_errs)

fn :: is sink agent arg [RType] => Bool
      is sink agent arg ((TyTuple ((TyVar "SinkAgent"):_)):_) = True
      is sink agent arg ((TyVar "SinkAgent"):_) = True
      is sink agent arg _ = False

fn :: finish call check String ([RType], [RTypeError]) String [RTypeBind] [RTypeBind] => RType [RTypeError]
      finish call check "agent" (arg_tys, arg_errs) fn_name _ _ = check agent create arg_tys arg_errs fn_name
      finish call check "agent_sink" (arg_tys, arg_errs) fn_name _ _ = check agent sink create arg_tys arg_errs fn_name
      finish call check "__gagent_get__" (arg_tys, arg_errs) _ _ _ = check gagent get arg_tys arg_errs
      finish call check "__with_agent__" (arg_tys, arg_errs) fn_name _ _ = check with agent call arg_tys arg_errs fn_name
      finish call check "send_to" (arg_tys, arg_errs) fn_name _ _ = check agent send arg_tys arg_errs fn_name
      finish call check "ask_to" (arg_tys, arg_errs) fn_name _ _ = check agent ask arg_tys arg_errs fn_name
      finish call check "receive_from" (arg_tys, arg_errs) fn_name locals fns
        | is sink agent arg arg_tys =
          (TyUnit, arg_errs :: [TypeError fn_name "cannot 'receive from' a sink agent; sink agents have no output queue (use 'agent state' to inspect state in tests)"])
        | otherwise =
          base_res = check call target "receive_from" arg_tys arg_errs (resolve callee for args "receive_from" arg_tys locals fns) fn_name
          specialize hof return "receive_from" arg_tys base_res
      finish call check "try_receive_from" (arg_tys, arg_errs) fn_name locals fns
        | is sink agent arg arg_tys =
          (TyUnit, arg_errs :: [TypeError fn_name "cannot 'try receive from' a sink agent; sink agents have no output queue (use 'agent state' to inspect state in tests)"])
        | otherwise =
          base_res = check call target "try_receive_from" arg_tys arg_errs (resolve callee for args "try_receive_from" arg_tys locals fns) fn_name
          specialize hof return "try_receive_from" arg_tys base_res
      finish call check callee (arg_tys, arg_errs) fn_name _ _
        | (numeric tensor helper name callee) != "" and (numeric tensor arg errs (numeric tensor helper name callee) arg_tys fn_name) != [] = (TyTensor (tensor elem any) [], arg_errs :: (numeric tensor arg errs (numeric tensor helper name callee) arg_tys fn_name))
      finish call check ":tensor-zeros:" (_, arg_errs) _ _ _ = (TyTensor (tensor elem any) [], arg_errs)
      finish call check ":tensor-clone:" (((TyTensor e d):_), arg_errs) _ _ _ = (TyTensor e d, arg_errs)
      finish call check ":tensor-row-slice:" (((TyTensor e _):_), arg_errs) _ _ _ = (TyTensor e [], arg_errs)
      finish call check ":tensor-col-slice:" (((TyTensor e _):_), arg_errs) _ _ _ = (TyTensor e [], arg_errs)
      finish call check ":tensor-clone:" (_, arg_errs) _ _ _ = (TyTensor (tensor elem any) [], arg_errs)
      finish call check ":tensor-row-slice:" (_, arg_errs) _ _ _ = (TyTensor (tensor elem any) [], arg_errs)
      finish call check ":tensor-col-slice:" (_, arg_errs) _ _ _ = (TyTensor (tensor elem any) [], arg_errs)
      finish call check ":tensor-set-row:" (_, arg_errs) _ _ _ = (TyUnit, arg_errs)
      finish call check ":tensor-set-col:" (_, arg_errs) _ _ _ = (TyUnit, arg_errs)
      finish call check ":tensor-map-rows:" (_, arg_errs) _ _ _ = (TyTensor (tensor elem any) [], arg_errs)
      finish call check ":tensor-map-rows-in:" (_, arg_errs) _ _ _ = (TyVar "_any", arg_errs)
      finish call check ":tensor-map-cols:" (_, arg_errs) _ _ _ = (TyTensor (tensor elem any) [], arg_errs)
      finish call check ":tensor-map-cols-in:" (_, arg_errs) _ _ _ = (TyVar "_any", arg_errs)
      finish call check ":tensor-map-elems:" (_, arg_errs) _ _ _ = (TyTensor (tensor elem any) [], arg_errs)
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
      check where binds step target _ wbs fn_name locals fns (_, errs1) =
        more = check where binds wbs fn_name locals fns
        merge env errs (errs1 :: (par write errs target (lookup type bind locals target) fn_name)) more

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
      check block stmts scoped ((StmtIndexAssign tname idxs val_e):ss) _ fn_name locals fns immuts muts =
        i_res = check expr list idxs fn_name locals fns
        v_res = check expr val_e fn_name locals fns
        w_errs = check tensor elem write tname (fst ty v_res) fn_name locals
        check block after expr ss fn_name locals fns immuts muts (TyUnit, (snd list errs i_res) :: (snd errs v_res) :: w_errs)

fn :: check block after mut String [RStmt] String [RTypeBind] [RTypeBind] [String] [String] (RType, [RTypeError]) => RType [RTypeError]
      check block after mut name ss fn_name locals fns immuts muts (v_ty, v_errs) =
        locals1 = bind let var name v_ty locals
        more = check block stmts scoped ss v_ty fn_name locals1 fns immuts (add unique str name muts)
        prepend type errs (v_errs :: (tensor elem info fn_name name v_ty)) more

fn :: check immut reassign String String [String] [String] => [RTypeError]
      check immut reassign "_" _ _ _ = []
      check immut reassign name fn_name immuts muts
        | list contains muts name = []
        | list contains immuts name = [TypeError fn_name ("cannot reassign immutable variable '" + name + "'; declare it with 'mut " + name + " = ...' first")]
        | otherwise = []

fn :: check block after let String [RStmt] String [RTypeBind] [RTypeBind] [String] [String] (RType, [RTypeError]) => RType [RTypeError]
      check block after let name ss fn_name locals fns immuts muts (v_ty, v_errs) =
        mut_err = check immut reassign name fn_name immuts muts
        locals1 = bind let var name v_ty locals
        more = check block stmts scoped ss v_ty fn_name locals1 fns (add unique str name immuts) muts
        prepend type errs (v_errs :: mut_err :: (tensor elem info fn_name name v_ty)) more

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
        | (is unit type ret_ty) or (types compatible b_ty ret_ty) or (is empty list return compat b_ty ret_ty) = []
        | otherwise = [TypeError fn_name ("guard #" + (int to str idx) + " body has type " + (rtype to str b_ty) + ", expected " + (rtype to str ret_ty))]

fn :: check case body ty (RType, [RTypeError]) RType String => [RTypeError]
      check case body ty (b_ty, b_errs) ret_ty fn_name
        | (is unit type ret_ty) or (types compatible b_ty ret_ty) or (is empty list return compat b_ty ret_ty) = b_errs
        | otherwise = b_errs :: [TypeError fn_name ("body has type " + (rtype to str b_ty) + ", expected " + (rtype to str ret_ty))]

fn :: pat count [RPattern] => Int
      pat count []         =  0
      pat count (_:xs)     =  1 + (pat count xs)

fn :: has type bind [RTypeBind] String => Bool
      has type bind [] _ = False
      has type bind ((TypeBind k _):rest) target
        | k == target = True
        | otherwise = has type bind rest target

fn :: strip unimported pat ctor String => String
      strip unimported pat ctor s
        | str starts with s "__unimported__." = str slice s 15 (str len s)
        | otherwise = s

fn :: is known pat ctor String [RTypeBind] [RTypeBind] => Bool
      is known pat ctor ":tensor-pat:" _ _ = True
      is known pat ctor "True" _ _ = True
      is known pat ctor "False" _ _ = True
      is known pat ctor c locals fns
        | (is int type name c) or c == "Real" or c == "Float" or c == "String" or c == "Char" or c == "Bool" = True
        | str starts with c "__unimported__." = False
        | otherwise = (has type bind locals c) or (has type bind fns c)

fn :: check pat ctors RPattern String [RTypeBind] [RTypeBind] => [RTypeError]
      check pat ctors (PatCons h t) fn_name locals fns =
        (check pat ctors h fn_name locals fns) :: (check pat ctors t fn_name locals fns)
      check pat ctors (PatTuple ps) fn_name locals fns =
        check pat list ctors ps fn_name locals fns
      check pat ctors (PatCtor c args) fn_name locals fns
        | is known pat ctor c locals fns = check pat list ctors args fn_name locals fns
        | otherwise =
          [TypeError fn_name ("unknown constructor '" + (strip unimported pat ctor c) + "' in pattern")] :: (check pat list ctors args fn_name locals fns)
      check pat ctors _ _ _ _ = []

fn :: check pat list ctors [RPattern] String [RTypeBind] [RTypeBind] => [RTypeError]
      check pat list ctors [] _ _ _ = []
      check pat list ctors (p:ps) fn_name locals fns =
        (check pat ctors p fn_name locals fns) :: (check pat list ctors ps fn_name locals fns)

fn :: check one case after pats [RTypeError] [RPattern] [RGuard] RExpr String [RType] RType [RTypeBind] [RTypeBind] => [RTypeError]
      check one case after pats (e:es) _ _ _ _ _ _ _ _ = [e] :: es
      check one case after pats [] pats guards body fn_name param_tys ret_ty locals fns =
        (param tensor infos pats param_tys fn_name fns) :: (check case guards or body guards body fn_name ret_ty (bind case patterns pats param_tys (has seq bind pat pats) 0 locals fns) fns)

fn :: check one case RFnCase String [RType] RType Int [RTypeBind] [RTypeBind] => [RTypeError]
      check one case (FnCase pats guards body) fn_name param_tys ret_ty case_idx locals fns
        | (pat count pats) != (list len param_tys) and (not (has seq bind pat pats)) = [TypeError fn_name ("case #" + (int to str case_idx) + " has " + (int to str (pat count pats)) + " pattern(s), expected " + (int to str (list len param_tys)))]
        | otherwise =
          pat_errs = check pat list ctors pats fn_name locals fns
          check one case after pats pat_errs pats guards body fn_name param_tys ret_ty locals fns

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

fn :: rev type errs [RTypeError] [RTypeError] => [RTypeError]
      rev type errs [] acc = acc
      rev type errs (x:xs) acc = rev type errs xs ([x] :: acc)

type RTypeBindMap = TypeBindEmpty | TypeBindNode String [RTypeBind] RTypeBindMap RTypeBindMap

fn :: tbind map add RTypeBindMap String RTypeBind => RTypeBindMap
      tbind map add TypeBindEmpty k b =
        TypeBindNode k [b] TypeBindEmpty TypeBindEmpty
      tbind map add (TypeBindNode nk nb l r) k b
        | (cmp str bst k nk) == 0 = TypeBindNode nk ([b] :: nb) l r
        | (cmp str bst k nk) < 0 = TypeBindNode nk nb (tbind map add l k b) r
        | otherwise = TypeBindNode nk nb l (tbind map add r k b)

fn :: tbind map get RTypeBindMap String => [RTypeBind]
      tbind map get TypeBindEmpty _ = []
      tbind map get (TypeBindNode nk nb l r) k
        | (cmp str bst k nk) == 0 = nb
        | (cmp str bst k nk) < 0 = tbind map get l k
        | otherwise = tbind map get r k

fn :: build tbind map rev [RTypeBind] RTypeBindMap => RTypeBindMap
      build tbind map rev [] m = m
      build tbind map rev ((TypeBind k ty):rest) m =
        build tbind map rev rest (tbind map add m k (TypeBind k ty))

fn :: build tbind map [RTypeBind] => RTypeBindMap
      build tbind map fns =
        build tbind map rev (rev type binds fns []) TypeBindEmpty

fn :: tc fst set (RStrSet, [String]) => RStrSet
      tc fst set (s, _) = s

fn :: tc snd list (RStrSet, [String]) => [String]
      tc snd list (_, xs) = xs

fn :: tc add ref String RStrSet [String] => RStrSet [String]
      tc add ref "" seen acc = (seen, acc)
      tc add ref s seen acc
        | str set has seen s = (seen, acc)
        | otherwise = (str set add seen s, [s] :: acc)

fn :: tc refs pat RPattern RStrSet [String] => RStrSet [String]
      tc refs pat (PatCons h t) seen acc =
        r1 = tc refs pat h seen acc
        tc refs pat t (tc fst set r1) (tc snd list r1)
      tc refs pat (PatTuple ps) seen acc =
        tc refs pat list ps seen acc
      tc refs pat (PatCtor c args) seen acc =
        r1 = tc add ref c seen acc
        tc refs pat list args (tc fst set r1) (tc snd list r1)
      tc refs pat _ seen acc = (seen, acc)

fn :: tc refs pat list [RPattern] RStrSet [String] => RStrSet [String]
      tc refs pat list [] seen acc = (seen, acc)
      tc refs pat list (p:ps) seen acc =
        r1 = tc refs pat p seen acc
        tc refs pat list ps (tc fst set r1) (tc snd list r1)

fn :: tc refs rec args [RExpr] RStrSet [String] => RStrSet [String]
      tc refs rec args [] seen acc = (seen, acc)
      tc refs rec args ((EStr fname):val_e:rest) seen acc =
        r1 = tc add ref fname seen acc
        r2 = tc refs expr val_e (tc fst set r1) (tc snd list r1)
        tc refs rec args rest (tc fst set r2) (tc snd list r2)
      tc refs rec args (e:rest) seen acc =
        r1 = tc refs expr e seen acc
        tc refs rec args rest (tc fst set r1) (tc snd list r1)

fn :: tc refs expr RExpr RStrSet [String] => RStrSet [String]
      tc refs expr (EVar v) seen acc = tc add ref v seen acc
      tc refs expr (EStrInterp parts) seen acc = tc refs expr list parts seen acc
      tc refs expr (ENot inner) seen acc = tc refs expr inner seen acc
      tc refs expr (EOut inner) seen acc = tc refs expr inner seen acc
      tc refs expr (EWithCtx _ v b) seen acc =
        r1 = tc refs expr v seen acc
        tc refs expr b (tc fst set r1) (tc snd list r1)
      tc refs expr (EWithRegion _ b) seen acc = tc refs expr b seen acc
      tc refs expr (EEinsum es _) seen acc = tc refs expr list es seen acc
      tc refs expr (EHadamard _ l _ r _) seen acc =
        r1 = tc refs expr l seen acc
        tc refs expr r (tc fst set r1) (tc snd list r1)
      tc refs expr (EBin bop l r) seen acc =
        r0 = tc add ref (binop symbol bop) seen acc
        r1 = tc refs expr l (tc fst set r0) (tc snd list r0)
        tc refs expr r (tc fst set r1) (tc snd list r1)
      tc refs expr (ECall "__record_update__" (base_e:rest_args)) seen acc =
        r1 = tc refs expr base_e seen acc
        tc refs rec args rest_args (tc fst set r1) (tc snd list r1)
      tc refs expr (ECall callee args) seen acc =
        r1 = tc add ref callee seen acc
        tc refs expr list args (tc fst set r1) (tc snd list r1)
      tc refs expr (EEcho args) seen acc = tc refs expr list args seen acc
      tc refs expr (EList elems) seen acc = tc refs expr list elems seen acc
      tc refs expr (ETuple elems) seen acc = tc refs expr list elems seen acc
      tc refs expr (ETensor elems) seen acc = tc refs expr list elems seen acc
      tc refs expr (EIndex b idxs) seen acc =
        r1 = tc refs expr b seen acc
        tc refs expr list idxs (tc fst set r1) (tc snd list r1)
      tc refs expr (EIndexAssign _ idxs v) seen acc =
        r1 = tc refs expr list idxs seen acc
        tc refs expr v (tc fst set r1) (tc snd list r1)
      tc refs expr (ESeqSelect b _) seen acc = tc refs expr b seen acc
      tc refs expr (EWhere b wbs) seen acc =
        r1 = tc refs expr b seen acc
        tc refs where list wbs (tc fst set r1) (tc snd list r1)
      tc refs expr (EParPipe bs) seen acc = tc refs expr list bs seen acc
      tc refs expr (EGuard gs) seen acc = tc refs guard list gs seen acc
      tc refs expr (EBlock ss) seen acc = tc refs stmt list ss seen acc
      tc refs expr _ seen acc = (seen, acc)

fn :: tc refs expr list [RExpr] RStrSet [String] => RStrSet [String]
      tc refs expr list [] seen acc = (seen, acc)
      tc refs expr list (e:es) seen acc =
        r1 = tc refs expr e seen acc
        tc refs expr list es (tc fst set r1) (tc snd list r1)

fn :: tc refs where list [RWhereBind] RStrSet [String] => RStrSet [String]
      tc refs where list [] seen acc = (seen, acc)
      tc refs where list ((WhereBind e _ _):wbs) seen acc =
        r1 = tc refs expr e seen acc
        tc refs where list wbs (tc fst set r1) (tc snd list r1)

fn :: tc refs guard list [RGuard] RStrSet [String] => RStrSet [String]
      tc refs guard list [] seen acc = (seen, acc)
      tc refs guard list ((GuardBranch c b):gs) seen acc =
        r1 = tc refs expr c seen acc
        r2 = tc refs expr b (tc fst set r1) (tc snd list r1)
        tc refs guard list gs (tc fst set r2) (tc snd list r2)

fn :: tc refs stmt list [RStmt] RStrSet [String] => RStrSet [String]
      tc refs stmt list [] seen acc = (seen, acc)
      tc refs stmt list ((StmtLet _ e):ss) seen acc =
        r1 = tc refs expr e seen acc
        tc refs stmt list ss (tc fst set r1) (tc snd list r1)
      tc refs stmt list ((StmtMut _ e):ss) seen acc =
        r1 = tc refs expr e seen acc
        tc refs stmt list ss (tc fst set r1) (tc snd list r1)
      tc refs stmt list ((StmtExpr e):ss) seen acc =
        r1 = tc refs expr e seen acc
        tc refs stmt list ss (tc fst set r1) (tc snd list r1)
      tc refs stmt list ((StmtIndexAssign _ idxs e):ss) seen acc =
        r1 = tc refs expr list idxs seen acc
        r2 = tc refs expr e (tc fst set r1) (tc snd list r1)
        tc refs stmt list ss (tc fst set r2) (tc snd list r2)

fn :: tc refs cases [RFnCase] RStrSet [String] => RStrSet [String]
      tc refs cases [] seen acc = (seen, acc)
      tc refs cases ((FnCase pats gs body):cs) seen acc =
        r1 = tc refs pat list pats seen acc
        r2 = tc refs guard list gs (tc fst set r1) (tc snd list r1)
        r3 = tc refs expr body (tc fst set r2) (tc snd list r2)
        tc refs cases cs (tc fst set r3) (tc snd list r3)

fn :: collect fns for refs [String] RTypeBindMap [RTypeBind] => [RTypeBind]
      collect fns for refs [] _ acc = acc
      collect fns for refs (k:ks) fmap acc =
        collect fns for refs ks fmap ((tbind map get fmap k) :: acc)

fn :: resolve fn ret ty [String] String => RType
      resolve fn ret ty _ "__sink_agent__" = TyVar "SinkAgent"
      resolve fn ret ty tnames ret_str = qualify declared adt tnames (parse type str ret_str)

fn :: check all functions acc [String] [RFnDef] RTypeBindMap RTypeBindMap [RTypeError] => [RTypeError]
      check all functions acc _ [] _ _ acc = rev type errs acc []
      check all functions acc tnames ((FnDef name param_strs ret_str cases):fs) lmap fmap acc =
        sig_errs = check sig syntax errs param_strs ret_str name
        param_tys = qualify declared adt list tnames (parse type list strs param_strs)
        ret_ty = resolve fn ret ty tnames ret_str
        refs = tc snd list (tc refs cases cases StrSetEmpty [])
        loc_binds = collect fns for refs refs lmap []
        fn_binds = collect fns for refs refs fmap []
        fn_errs = sig_errs :: (check fn cases cases name param_tys ret_ty 0 loc_binds fn_binds)
        check all functions acc tnames fs lmap fmap (rev type errs fn_errs acc)

fn :: check all functions [String] [RFnDef] [RTypeBind] [RTypeBind] => [RTypeError]
      check all functions tnames fdefs locals fns =
        lmap = build tbind map locals
        fmap = build tbind map fns
        check all functions acc tnames fdefs lmap fmap []

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
      typecheck program prog =  drop tensor infos (typecheck program all prog) []

-- Type errors plus the tensor element facts (`tensor elem info`) that
-- lowering uses (FR-COMP-020).
fn :: typecheck program all RProgram => [RTypeError]
      typecheck program all (Program fdefs tdefs) =
        all_tdefs = (builtin typedefs) :: tdefs
        tnames = collect typedef names all_tdefs
        env_pair = register typedef list tnames all_tdefs (builtin local types) (builtin fn types)
        typecheck with typedef env tnames (Program fdefs tdefs) fdefs env_pair

fn :: check duplicate fndefs acc [RFnDef] RStrSet [RTypeError] => [RTypeError]
      check duplicate fndefs acc []       _    acc =  rev type errs acc []
      check duplicate fndefs acc ((FnDef "__unresolved_import__" _ _ _):fs) seen acc =
        check duplicate fndefs acc fs seen acc
      check duplicate fndefs acc ((FnDef "__syntax_error__" _ _ _):fs) seen acc =
        check duplicate fndefs acc fs seen acc
      check duplicate fndefs acc ((FnDef name _ _ _):fs) seen acc
        | str set has seen name =
          check duplicate fndefs acc fs seen ([TypeError name ("duplicate function definition '" + name + "'; function is already defined")] :: acc)
        | otherwise =
          check duplicate fndefs acc fs (str set add seen name) acc

fn :: check duplicate fndefs [RFnDef] => [RTypeError]
      check duplicate fndefs fdefs =
        check duplicate fndefs acc fdefs StrSetEmpty []

fn :: typecheck with typedef env [String] RProgram [RFnDef] ([RTypeBind], [RTypeBind]) => [RTypeError]
      typecheck with typedef env tnames prog fdefs (locals, fns0) =
        dup_errs = check duplicate fndefs fdefs
        fns = register fndef sigs tnames fdefs fns0
        ty_errs = check all functions tnames fdefs locals fns
        an_errs = convert analysis errors (analyze program errors prog)
        dup_errs :: ty_errs :: an_errs

fn :: type err count [RTypeError] => Int
type err count []           =  0
type err count (_:xs)       =  1 + (type err count xs)

fn :: format one syntax err String => String
      format one syntax err msg
        | str starts with msg "at " = "syntax error " + msg
        | otherwise = "syntax error: " + msg

fn :: format type errors [RTypeError] => [String]
      format type errors []           =  []
      format type errors ((TypeError "syntax" msg):es) =
        [format one syntax err (decode literal underscores msg)] :: (format type errors es)
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
        | not (has arrow before rparen rest 0) = True
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

-- ── Tensor element facts for lowering (FR-COMP-020) ──────────
-- Lowering is untyped, so the type checker reports the element kind of
-- every tensor variable it binds, as a `TypeError ":tensor-elem:"` whose
-- message is `fn|var|K`: K is `N` (Int), `R` (Real), `G` (any other
-- type: stored as a GenTensor) or `U` (unknown or a type variable).
-- `typecheck program` drops these entries; `tensor infos of` keeps them.

fn :: tensor elem kind RType => String
      tensor elem kind (TyVar "U8")  =  "B"
      tensor elem kind TyInt         =  "N"
      tensor elem kind TyReal        =  "R"
      tensor elem kind TyString      =  "G"
      tensor elem kind TyBool        =  "G"
      tensor elem kind TyChar        =  "G"
      tensor elem kind TyUnit        =  "G"
      tensor elem kind (TyList _)    =  "L"
      tensor elem kind (TyTuple _)   =  "G"
      tensor elem kind (TyTensor _ _) =  "G"
      tensor elem kind (TyFun _ _)   =  "G"
      tensor elem kind _             =  "U"

-- Phase 4 of FR-COMP-020: operations that only make sense on numbers
-- (einsum, arithmetic, matrix product, element-wise operators, row and
-- column helpers, parallel writes) are compile errors on a tensor whose
-- element type is known and is not a number.

fn :: tensor elem gen RType => Bool
      tensor elem gen (TyVar s) =  not (is poly type var s)
      tensor elem gen e         =  ((tensor elem kind e) == "G") or ((tensor elem kind e) == "L")

fn :: gen tensor ty RType => Bool
      gen tensor ty (TyTensor e _) =  tensor elem gen e
      gen tensor ty _              =  False

fn :: gen tensor elem str RType => String
      gen tensor elem str (TyTensor e _) =  rtype to str e
      gen tensor elem str t              =  rtype to str t

fn :: numeric tensor errs String RType RType String => [RTypeError]
      numeric tensor errs what l r fn_name
        | is u8 tensor l = [TypeError fn_name (what + " is not available on Tensor[U8]")]
        | is u8 tensor r = [TypeError fn_name (what + " is not available on Tensor[U8]")]
        | gen tensor ty l = [TypeError fn_name (what + " needs tensors of numbers, got a tensor of " + (gen tensor elem str l))]
        | gen tensor ty r = [TypeError fn_name (what + " needs tensors of numbers, got a tensor of " + (gen tensor elem str r))]
        | otherwise = []

fn :: numeric tensor arg errs String [RType] String => [RTypeError]
      numeric tensor arg errs _ [] _ =  []
      numeric tensor arg errs what (t:ts) fn_name
        | is u8 tensor t and what == "a tensor copy (t_)" = numeric tensor arg errs what ts fn_name
        | is u8 tensor t = [TypeError fn_name (what + " is not available on Tensor[U8]")]
        | gen tensor ty t = [TypeError fn_name (what + " needs a tensor of numbers, got a tensor of " + (gen tensor elem str t))]
        | otherwise = numeric tensor arg errs what ts fn_name

fn :: numeric tensor helper name String => String
      numeric tensor helper name ":tensor-clone:" =  "a tensor copy (t_)"
      numeric tensor helper name ":tensor-row-slice:" =  "a row slice"
      numeric tensor helper name ":tensor-col-slice:" =  "a column slice"
      numeric tensor helper name ":tensor-set-row:" =  "a row write"
      numeric tensor helper name ":tensor-set-col:" =  "a column write"
      numeric tensor helper name ":tensor-map-rows:" =  "a map over rows"
      numeric tensor helper name ":tensor-map-rows-in:" =  "a map over rows"
      numeric tensor helper name ":tensor-map-cols:" =  "a map over columns"
      numeric tensor helper name ":tensor-map-cols-in:" =  "a map over columns"
      numeric tensor helper name ":tensor-map-elems:" =  "a map over tensor elements"
      numeric tensor helper name ":tensor-map-elems-in:" =  "a map over tensor elements"
      numeric tensor helper name _ =  ""

fn :: par write errs String (Bool, RType) String => [RTypeError]
      par write errs target (True, t) fn_name
        | is u8 tensor t = [TypeError fn_name ("parallel writes into tensor '" + target + "' of U8 are not supported")]
        | gen tensor ty t = [TypeError fn_name ("parallel writes into tensor '" + target + "' of " + (gen tensor elem str t) + " are not supported: its elements are not numbers")]
      par write errs _ _ _ =  []

-- ── Tensors in messages (FR-COMP-020) ─────────────────────────
-- A tensor sent to an agent or a channel (and the initial state of an
-- agent) is copied: the receiver never gets the original. Lowering copies
-- a message that is a tensor variable, a call that returns a tensor, or a
-- tuple of those; it learns them from `:tensor-elem:` facts (`fn|v|K` for
-- a variable, `fn|()f|K` for a call to `f`). Any other message that holds a
-- tensor is a compile error.

fn :: msg arg pos String Int => Int
      msg arg pos "send_to" 2 =  0
      msg arg pos "ask_to" 2 =  0
      msg arg pos "send_through" 2 =  0
      msg arg pos "chan_send" 2 =  0
      msg arg pos "agent" 2 =  1
      msg arg pos "agent_sink" 4 =  1
      msg arg pos _ _ =  0 - 1

fn :: nth rexpr [RExpr] Int => RExpr
      nth rexpr (e:_) 0 =  e
      nth rexpr (_:es) i =  nth rexpr es (i - 1)
      nth rexpr [] _ =  EInt 0

fn :: nth rtype [RType] Int => RType
      nth rtype (t:_) 0 =  t
      nth rtype (_:ts) i =  nth rtype ts (i - 1)
      nth rtype [] _ =  TyUnit

fn :: with msg copy facts String [RExpr] ([RType], [RTypeError]) String [RTypeBind] (RType, [RTypeError]) => RType [RTypeError]
      with msg copy facts callee args (tys, _) fn_name fns (t, errs)
        | (msg arg pos callee (tc expr count args)) < 0 = (t, errs)
        | otherwise =
          pos = msg arg pos callee (tc expr count args)
          (t, errs :: (msg copy errs fn_name (nth rexpr args pos) (nth rtype tys pos) fns))

fn :: msg copy errs String RExpr RType [RTypeBind] => [RTypeError]
      msg copy errs fn_name e t fns
        | ty has tensor t fns [] = msg tensor copy errs fn_name e t fns
        | otherwise = []

fn :: msg tensor copy errs String RExpr RType [RTypeBind] => [RTypeError]
      msg tensor copy errs fn_name (EVar v) (TyTensor e d) _ =  tensor elem info fn_name v (TyTensor e d)
      msg tensor copy errs fn_name (ETuple es) (TyTuple ts) fns =  msg copy errs list fn_name es ts fns
      msg tensor copy errs _ (ETensor _) _ _ =  []
      msg tensor copy errs fn_name (ECall f _) (TyTensor e d) _
        | (str starts with f ":") or f == "tensor_from_list" = []
        | otherwise = tensor elem info fn_name ("()" + f) (TyTensor e d)
      msg tensor copy errs fn_name _ t _ =
        [TypeError fn_name ("a message of type " + (rtype to str t) + " holds a tensor that the receiver would share; send a tensor variable, a function result or a tuple of them, so that the tensor is copied")]

fn :: msg copy errs list String [RExpr] [RType] [RTypeBind] => [RTypeError]
      msg copy errs list fn_name (e:es) (t:ts) fns =  (msg copy errs fn_name e t fns) :: (msg copy errs list fn_name es ts fns)
      msg copy errs list _ _ _ _ =  []

-- True when a value of type t can hold a tensor: directly, in a list or a
-- tuple, or in a field of an ADT or record (found through its constructors).
fn :: ty has tensor RType [RTypeBind] [String] => Bool
      ty has tensor (TyTensor _ _) _ _ =  True
      ty has tensor (TyList t) fns seen =  ty has tensor t fns seen
      ty has tensor (TyTuple ts) fns seen =  tys have tensor ts fns seen
      ty has tensor (TyVar n) fns seen
        | list contains seen n = False
        | otherwise = adt has tensor fns n fns ([n] :: seen)
      ty has tensor _ _ _ =  False

fn :: tys have tensor [RType] [RTypeBind] [String] => Bool
      tys have tensor [] _ _ =  False
      tys have tensor (t:ts) fns seen
        | ty has tensor t fns seen = True
        | otherwise = tys have tensor ts fns seen

fn :: adt has tensor [RTypeBind] String [RTypeBind] [String] => Bool
      adt has tensor [] _ _ _ =  False
      adt has tensor ((TypeBind k (TyFun arg_tys (TyVar m))):rest) n fns seen
        | m == n and (is upper ident (ident base name k)) and (tys have tensor arg_tys fns seen) = True
        | otherwise = adt has tensor rest n fns seen
      adt has tensor (_:rest) n fns seen =  adt has tensor rest n fns seen

-- `echo` and string interpolation show a numeric tensor with its element
-- type (FR-COMP-020 §10). Each shown tensor gets a `:show` fact (so the
-- show helpers are kept) and, for a call, the `()f` fact of its result.
fn :: with show tensor facts String [RExpr] ([RType], [RTypeError]) (RType, [RTypeError]) => RType [RTypeError]
      with show tensor facts fn_name es (tys, _) (t, errs) =  (t, errs :: (show tensor facts fn_name es tys))

fn :: show tensor facts String [RExpr] [RType] => [RTypeError]
      show tensor facts fn_name (e:es) (t:ts) =  (show tensor fact fn_name e t) :: (show tensor facts fn_name es ts)
      show tensor facts _ _ _ =  []

fn :: show tensor fact String RExpr RType => [RTypeError]
      show tensor fact fn_name e (TyTensor (TyVar "U8") d)
        | not (u8 visible e) = u8 use errs fn_name e (TyTensor (TyVar "U8") d)
      show tensor fact fn_name (ECall f _) (TyTensor el d)
        | not (str starts with f ":") = (tensor elem info fn_name ":show" (TyTensor el d)) :: (tensor elem info fn_name ("()" + f) (TyTensor el d))
      show tensor fact fn_name _ (TyTensor el d) =  tensor elem info fn_name ":show" (TyTensor el d)
      show tensor fact _ _ _ =  []

-- A call that returns a `Tensor[U8]` gets the `()f` fact of its result, so
-- lowering knows the tensor is packed wherever the call is used.
fn :: with u8 call fact String String (RType, [RTypeError]) => RType [RTypeError]
      with u8 call fact fn_name callee (t, errs)
        | (is u8 tensor t) and not (str starts with callee ":") = (t, errs :: (tensor elem info fn_name ("()" + callee) t))
        | otherwise = (t, errs)

-- Lowering finds the element kind of a variable, of a call, of a typed
-- tensor and of a copy `t_`. A `Tensor[U8]` read, shown, hashed or turned
-- into a list must be one of those.
fn :: u8 visible RExpr => Bool
      u8 visible (EVar _) =  True
      u8 visible (ECall f _) =  (not (str starts with f ":")) or f == ":typed-tensor:" or f == ":tensor-clone:"
      u8 visible _ =  False

fn :: u8 use errs String RExpr RType => [RTypeError]
      u8 use errs fn_name e t
        | (is u8 tensor t) and not (u8 visible e) = [TypeError fn_name "bind this Tensor[U8] to a variable before using it here"]
        | otherwise = []

fn :: with u8 use errs String RExpr RType (RType, [RTypeError]) => RType [RTypeError]
      with u8 use errs fn_name e t (rt, errs) =  (rt, errs :: (u8 use errs fn_name e t))

fn :: tensor elem info String String RType => [RTypeError]
      tensor elem info fn_name v (TyTensor e _) =  [TypeError ":tensor-elem:" (fn_name + "|" + v + "|" + (tensor elem kind e))]
      tensor elem info _ _ _ =  []

-- Every variable a parameter pattern binds records the element kind of
-- its tensor type, wherever it sits: alone, in a shape pattern, a tuple, a
-- list cons, `Some` or any constructor (lowering reads a packed Tensor[U8]
-- by bytes only with that fact, FR-COMP-022).
fn :: param tensor infos [RPattern] [RType] String [RTypeBind] => [RTypeError]
      param tensor infos (p:ps) (t:ts) fn_name fns =  (pat tensor info p t fn_name fns) :: (param tensor infos ps ts fn_name fns)
      param tensor infos _ _ _ _ =  []

fn :: pat tensor info RPattern RType String [RTypeBind] => [RTypeError]
      pat tensor info (PatVar v) t fn_name _ =  tensor elem info fn_name v t
      pat tensor info (PatCtor ":tensor-pat:" ((PatVar v):_)) t fn_name _ =  tensor elem info fn_name v t
      pat tensor info (PatTuple ps) (TyTuple ts) fn_name fns =  param tensor infos ps ts fn_name fns
      pat tensor info (PatCons h tl) (TyList e) fn_name fns =  (pat tensor info h e fn_name fns) :: (pat tensor info tl (TyList e) fn_name fns)
      pat tensor info (PatCtor "Some" (sub_p:[])) (TyVar opt_s) fn_name fns
        | str starts with opt_s "Option " = pat tensor info sub_p (parse option inner ty (str slice opt_s 7 (str len opt_s))) fn_name fns
      pat tensor info (PatCtor c args) t fn_name fns
        | not (str starts with c ":") = param tensor infos args (ctor param types for fns c t (pat list arity args)) fn_name fns
      pat tensor info _ _ _ _ =  []

fn :: drop tensor infos [RTypeError] [RTypeError] => [RTypeError]
      drop tensor infos [] acc =  rev type errs acc []
      drop tensor infos ((TypeError ":tensor-elem:" _):es) acc =  drop tensor infos es acc
      drop tensor infos (e:es) acc =  drop tensor infos es ([e] :: acc)

fn :: tensor infos of [RTypeError] [String] => [String]
      tensor infos of [] acc =  acc
      tensor infos of ((TypeError ":tensor-elem:" msg):es) acc =  tensor infos of es ([msg] :: acc)
      tensor infos of (_:es) acc =  tensor infos of es acc

-- Allocation with a value: `Tensor[T * dims] with v`, or the default value
-- of `T` (FR-COMP-020 §6).
fn :: typed tensor with check String RExpr RExpr String [RTypeBind] [RTypeBind] => RType [RTypeError]
      typed tensor with check elem_ty v inner fn_name locals fns =
        v_ty = fst ty (check expr v fn_name locals fns)
        typed tensor result elem_ty (tensor with value errs elem_ty v_ty fn_name (check expr inner fn_name locals fns))

-- `Tensor[T * dims] with v`: `v` must have the element type `T`.
fn :: tensor with value errs String RType String (RType, [RTypeError]) => RType [RTypeError]
      tensor with value errs elem_ty v_ty fn_name (t, errs)
        | types compatible (parse type str elem_ty) v_ty = (t, errs)
        | otherwise = (t, errs :: [TypeError fn_name ("cannot fill a tensor of " + elem_ty + " with " + (rtype to str v_ty))])

fn :: tensor from list result (RType, [RTypeError]) String => RType [RTypeError]
      tensor from list result ((TyList (TyVar "_empty")), errs) _ =  (TyTensor (tensor elem any) [], errs)
      tensor from list result ((TyList e), errs) _ =  (TyTensor e [], errs)
      tensor from list result (t, errs) fn_name =  (TyTensor (tensor elem any) [], errs :: [TypeError fn_name ("tensor from list expects a list, got " + (rtype to str t))])

fn :: tensor to list result (RType, [RTypeError]) String => RType [RTypeError]
      tensor to list result ((TyTensor e _), errs) _ =  (TyList (tensor elem read ty e), errs)
      tensor to list result (t, errs) fn_name =  (TyList TyInt, errs :: [TypeError fn_name ("tensor to list expects a tensor, got " + (rtype to str t))])

-- A tensor literal (`Tensor[[1, 2], [3, 4]]`) holds numbers; other
-- elements go through `tensor from list` (FR-COMP-020 §9).
fn :: tensor literal errs [RType] String => [RTypeError]
      tensor literal errs [] _ =  []
      tensor literal errs (t:ts) fn_name
        | tensor literal elem ok t = tensor literal errs ts fn_name
        | otherwise = [TypeError fn_name ("a tensor literal holds numbers, not " + (rtype to str t) + "; use 'tensor from list' for other element types")]

-- A literal whose elements are all `Real` (also in its rows) is a
-- `Tensor[Real]`, all `Int` a `Tensor[Int]`; other literals (empty, or
-- with elements of an open type) keep an open element type.
fn :: tensor literal elem [RType] => RType
      tensor literal elem tys
        | (literal leaf count tys TyReal) > 0 and (literal leaf count tys TyInt) == 0 = TyReal
        | (literal leaf count tys TyInt) > 0 and (literal leaf count tys TyReal) == 0 = TyInt
        | otherwise = tensor elem any

fn :: tensor literal mix errs [RType] String => [RTypeError]
      tensor literal mix errs tys fn_name
        | (literal leaf count tys TyReal) > 0 and (literal leaf count tys TyInt) > 0 = [TypeError fn_name "a tensor literal mixes Int and Real elements; write every element as a Real (1.0, not 1)"]
        | otherwise = []

fn :: literal leaf count [RType] RType => Int
      literal leaf count [] _ =  0
      literal leaf count (t:ts) k =  (literal leaf is t k) + (literal leaf count ts k)

fn :: literal leaf is RType RType => Int
      literal leaf is TyReal TyReal =  1
      literal leaf is TyInt TyInt =  1
      literal leaf is (TyList e) k =  literal leaf is e k
      literal leaf is _ _ =  0

fn :: tensor literal elem ok RType => Bool
      tensor literal elem ok TyInt =  True
      tensor literal elem ok TyReal =  True
      tensor literal elem ok (TyList e) =  tensor literal elem ok e
      tensor literal elem ok (TyVar _) =  True
      tensor literal elem ok (TyTensor _ _) =  True
      tensor literal elem ok _ =  False

fn :: fst list tys ([RType], [RTypeError]) => [RType]
      fst list tys (tys, _) =  tys
