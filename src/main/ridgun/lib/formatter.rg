-- ============================================================
-- src/main/ridgun/lib/formatter.rg
-- Canonical Ridgun Source Code Formatter (100% Pure Ridgun)
-- @implements FR-TOOL-001
-- Mirrors the signature-aware column alignment and 2-space
-- structural indentation engine of `editors/emacs/ridgun-mode.el`.
-- Purely aesthetic tooling: never enforced by `ridgunc`.
-- ============================================================

type FmtToken = FmtTok String Int

type FmtSig = NoSig | SigInfo String [String] String String [Int] Int Int

type FmtClause = NoClause | ClauseInfo [String] Bool String

type FmtWhereBind = NoWhereBind | WhereBindInfo String String

-- ── Basic Integer & List Helpers ─────────────────────────────

fn :: fmt_max Int Int => Int
      fmt_max a   b
        | a >= b = a
        | otherwise = b

fn :: fmt_str_list_len [String] => Int
      fmt_str_list_len []       =  0
      fmt_str_list_len (_:xs)   =  1 + (fmt_str_list_len xs)

fn :: fmt_str_head [String] => String
      fmt_str_head []       =  ""
      fmt_str_head (x:_)    =  x

fn :: fmt_int_at [Int]  Int => Int
      fmt_int_at []     _   =  -1
      fmt_int_at (x:_)  0   =  x
      fmt_int_at (_:xs) idx =  fmt_int_at xs (idx - 1)

fn :: fmt_spaces Int => String
      fmt_spaces n
        | n <= 0 = ""
        | otherwise = " " + (fmt_spaces (n - 1))

-- ── Whitespace & Line Splitting Helpers ──────────────────────

fn :: fmt_is_hspace Int => Bool
      fmt_is_hspace c   =  c == 32 OR c == 9 OR c == 13

fn :: fmt_leading_indent_loop String Int Int => Int
      fmt_leading_indent_loop s      pos len
        | pos >= len = len
        | (str_char_at s pos) == 32 OR (str_char_at s pos) == 9 = fmt_leading_indent_loop s (pos + 1) len
        | otherwise = pos

fn :: fmt_leading_indent String => Int
      fmt_leading_indent s      =  fmt_leading_indent_loop s 0 (str_len s)

fn :: fmt_trim_left_loop String Int Int => String
      fmt_trim_left_loop s      pos len
        | pos >= len = ""
        | fmt_is_hspace (str_char_at s pos) = fmt_trim_left_loop s (pos + 1) len
        | otherwise = str_slice s pos len

fn :: fmt_trim_left String => String
      fmt_trim_left s      =  fmt_trim_left_loop s 0 (str_len s)

fn :: fmt_trim_right_loop String Int     => String
      fmt_trim_right_loop s      end_pos
        | end_pos <= 0 = ""
        | fmt_is_hspace (str_char_at s (end_pos - 1)) = fmt_trim_right_loop s (end_pos - 1)
        | otherwise = str_slice s 0 end_pos

fn :: fmt_trim_right String => String
      fmt_trim_right s      =  fmt_trim_right_loop s (str_len s)

fn :: fmt_trim String => String
      fmt_trim s      =  fmt_trim_left (fmt_trim_right s)

fn :: fmt_split_raw_lines_loop String Int Int Int Int [String] => [String]
      fmt_split_raw_lines_loop s pos len line_start quote_st acc
        | pos >= len AND line_start == len = acc
        | pos >= len = acc :: [fmt_trim_right (str_slice s line_start len)]
        | quote_st == 34 AND (str_char_at s pos) == 92 = fmt_split_raw_lines_loop s (pos + 2) len line_start 34 acc
        | quote_st == 34 AND (str_char_at s pos) == 34 = fmt_split_raw_lines_loop s (pos + 1) len line_start 0 acc
        | quote_st == 34 = fmt_split_raw_lines_loop s (pos + 1) len line_start 34 acc
        | quote_st == 39 AND (str_char_at s pos) == 39 = fmt_split_raw_lines_loop s (pos + 1) len line_start 0 acc
        | quote_st == 39 = fmt_split_raw_lines_loop s (pos + 1) len line_start 39 acc
        | quote_st == 45 AND (str_char_at s pos) == 10 = fmt_split_raw_lines_loop s (pos + 1) len (pos + 1) 0 (acc :: [fmt_trim_right (str_slice s line_start pos)])
        | quote_st == 45 = fmt_split_raw_lines_loop s (pos + 1) len line_start 45 acc
        | (str_char_at s pos) == 10 = fmt_split_raw_lines_loop s (pos + 1) len (pos + 1) 0 (acc :: [fmt_trim_right (str_slice s line_start pos)])
        | (str_char_at s pos) == 45 AND (pos + 1) < len AND (str_char_at s (pos + 1)) == 45 = fmt_split_raw_lines_loop s (pos + 2) len line_start 45 acc
        | (str_char_at s pos) == 34 = fmt_split_raw_lines_loop s (pos + 1) len line_start 34 acc
        | (str_char_at s pos) == 39 = fmt_split_raw_lines_loop s (pos + 1) len line_start 39 acc
        | otherwise = fmt_split_raw_lines_loop s (pos + 1) len line_start 0 acc

fn :: fmt_split_raw_lines String => [String]
      fmt_split_raw_lines s      =  fmt_split_raw_lines_loop s 0 (str_len s) 0 0 []

fn :: fmt_join_lines [String] => String
      fmt_join_lines []       =  ""
      fmt_join_lines (l:[])   =  l + (char_from_code 10)
      fmt_join_lines (l:ls)   =  l + (char_from_code 10) + (fmt_join_lines ls)

-- ── Quote-Aware Comment Splitting (`-- ...`) ─────────────────

fn :: fmt_skip_quoted String Int Int Int      => Int
      fmt_skip_quoted s      pos len quote_ch
        | pos >= len = len
        | (str_char_at s pos) == 92 = fmt_skip_quoted s (pos + 2) len quote_ch
        | (str_char_at s pos) == quote_ch = pos + 1
        | otherwise = fmt_skip_quoted s (pos + 1) len quote_ch

fn :: fmt_find_comment_col String Int Int => Int
      fmt_find_comment_col s      pos len
        | pos >= len = -1
        | (str_char_at s pos) == 34 = fmt_find_comment_col s (fmt_skip_quoted s (pos + 1) len 34) len
        | (str_char_at s pos) == 39 = fmt_find_comment_col s (fmt_skip_quoted s (pos + 1) len 39) len
        | (pos + 1) < len AND (str_char_at s pos) == 45 AND (str_char_at s (pos + 1)) == 45 = pos
        | otherwise = fmt_find_comment_col s (pos + 1) len

fn :: fmt_strip_comment String => String
      fmt_strip_comment line   =
        c_col = fmt_find_comment_col line 0 (str_len line)
        fmt_strip_comment_at line c_col

fn :: fmt_strip_comment_at String Int   => String
      fmt_strip_comment_at line   -1    =  fmt_trim_right line
      fmt_strip_comment_at line   c_col =  fmt_trim_right (str_slice line 0 c_col)

fn :: fmt_extract_comment String => String
      fmt_extract_comment line   =
        c_col = fmt_find_comment_col line 0 (str_len line)
        fmt_extract_comment_at line c_col

fn :: fmt_extract_comment_at String Int   => String
      fmt_extract_comment_at _      -1    =  ""
      fmt_extract_comment_at line   c_col =  fmt_trim_right (str_slice line c_col (str_len line))

-- ── Line Token Scanner (`ridgun--scan-tokens-with-cols`) ─────

fn :: fmt_skip_hspace String Int Int => Int
      fmt_skip_hspace s      pos len
        | pos >= len = len
        | fmt_is_hspace (str_char_at s pos) = fmt_skip_hspace s (pos + 1) len
        | otherwise = pos

fn :: fmt_scan_group_end String Int Int Int   => Int
      fmt_scan_group_end s      pos len depth
        | pos >= len = len
        | (str_char_at s pos) == 34 = fmt_scan_group_end s (fmt_skip_quoted s (pos + 1) len 34) len depth
        | (str_char_at s pos) == 39 = fmt_scan_group_end s (fmt_skip_quoted s (pos + 1) len 39) len depth
        | (str_char_at s pos) == 40 OR (str_char_at s pos) == 91 = fmt_scan_group_end s (pos + 1) len (depth + 1)
        | ((str_char_at s pos) == 41 OR (str_char_at s pos) == 93) AND depth <= 1 = pos + 1
        | (str_char_at s pos) == 41 OR (str_char_at s pos) == 93 = fmt_scan_group_end s (pos + 1) len (depth - 1)
        | otherwise = fmt_scan_group_end s (pos + 1) len depth

fn :: fmt_scan_word_end String Int Int Int   => Int
      fmt_scan_word_end s      pos len depth
        | pos >= len = len
        | depth == 0 AND (fmt_is_hspace (str_char_at s pos)) = pos
        | (str_char_at s pos) == 34 = fmt_scan_word_end s (fmt_skip_quoted s (pos + 1) len 34) len depth
        | (str_char_at s pos) == 39 = fmt_scan_word_end s (fmt_skip_quoted s (pos + 1) len 39) len depth
        | (str_char_at s pos) == 40 OR (str_char_at s pos) == 91 = fmt_scan_word_end s (pos + 1) len (depth + 1)
        | (str_char_at s pos) == 41 OR (str_char_at s pos) == 93 = fmt_scan_word_end s (pos + 1) len (fmt_max 0 (depth - 1))
        | otherwise = fmt_scan_word_end s (pos + 1) len depth

fn :: fmt_scan_token_end String Int Int Int => Int
      fmt_scan_token_end s      pos len ch
        | ch == 34 OR ch == 39 = fmt_skip_quoted s (pos + 1) len ch
        | ch == 40 OR ch == 91 = fmt_scan_group_end s (pos + 1) len 1
        | otherwise = fmt_scan_word_end s pos len 0

fn :: fmt_scan_tokens_loop String Int Int [FmtToken] => [FmtToken]
      fmt_scan_tokens_loop s      pos len acc        =
        p = fmt_skip_hspace s pos len
        fmt_scan_tokens_at s p len acc

fn :: fmt_scan_tokens_at String Int Int [FmtToken] => [FmtToken]
      fmt_scan_tokens_at s      p   len acc
        | p >= len = acc
        | otherwise = fmt_scan_tokens_at_step s p len acc (fmt_scan_token_end s p len (str_char_at s p))

fn :: fmt_scan_tokens_at_step String Int Int [FmtToken] Int => [FmtToken]
      fmt_scan_tokens_at_step s p len acc end_p =
        tok_s = str_slice s p end_p
        fmt_scan_tokens_loop s end_p len (acc :: [FmtTok tok_s p])

fn :: fmt_scan_tokens String => [FmtToken]
      fmt_scan_tokens line   =  fmt_scan_tokens_loop line 0 (str_len line) []

-- ── Signature Parsing (`fn ::` / `op ::`) ────────────────────

fn :: fmt_split_sig_arrow [FmtToken] [String] => (Bool, [String], String, Int)
      fmt_split_sig_arrow []         _        =  (False, [], "", 0)
      fmt_split_sig_arrow ((FmtTok tok col):rest) lhs_acc
        | tok == "=>" OR tok == "->" = (True, lhs_acc, tok, col)
        | otherwise = fmt_split_sig_arrow rest (lhs_acc :: [tok])

fn :: fmt_is_sig_type_tok String => Bool
      fmt_is_sig_type_tok ""     =  False
      fmt_is_sig_type_tok tok    =
        ch = str_char_at tok 0
        (ch >= 65 AND ch <= 90) OR ch == 91 OR ch == 40

fn :: fmt_all_type_toks [String] => Bool
      fmt_all_type_toks []       =  True
      fmt_all_type_toks (t:rest)
        | fmt_is_sig_type_tok t = fmt_all_type_toks rest
        | otherwise = False

fn :: fmt_is_bare_fn_lhs [String]       => Bool
      fmt_is_bare_fn_lhs (first_w:rest)
        | NOT (fmt_is_sig_type_tok first_w) = fmt_all_type_toks rest
      fmt_is_bare_fn_lhs _              =  False

fn :: fmt_infer_bare_kind [String] => String
      fmt_infer_bare_kind lhs_strs
        | fmt_is_bare_fn_lhs lhs_strs = "bare_fn"
        | otherwise = "bare_op"

fn :: fmt_parse_sig_line String => FmtSig
      fmt_parse_sig_line line   =
        clean = fmt_strip_comment line
        cmt = fmt_extract_comment line
        toks = fmt_scan_tokens clean
        fmt_parse_sig_tokens (fmt_leading_indent line) clean cmt toks

fn :: fmt_parse_sig_tokens Int String String [FmtToken] => FmtSig
      fmt_parse_sig_tokens _   clean  cmt    ((FmtTok kind _):(FmtTok "::" _):rest)
        | kind == "fn" OR kind == "op" = fmt_finish_sig_parse clean cmt kind (fmt_split_sig_arrow rest [])
      fmt_parse_sig_tokens 0   clean  cmt    ((FmtTok w col):rest)
        | w == "type" OR w == "import" OR w == "global" OR w == "context" OR w == "shared" OR w == "hardware" OR (str_starts_with w "@") OR (str_starts_with w "--") OR (str_starts_with w "|") = NoSig
        | otherwise = fmt_finish_bare_sig_parse clean cmt (fmt_split_sig_arrow ([FmtTok w col] :: rest) [])
      fmt_parse_sig_tokens _   _      _      _          =  NoSig

fn :: fmt_finish_bare_sig_parse String String (Bool, [String], String, Int) => FmtSig
      fmt_finish_bare_sig_parse _ _ (False, _, _, _) = NoSig
      fmt_finish_bare_sig_parse _ _ (True, [], _, _) = NoSig
      fmt_finish_bare_sig_parse clean cmt (True, lhs_strs, arrow_s, arrow_col)
        | arrow_s == "=>" = fmt_finish_sig_parse clean cmt (fmt_infer_bare_kind lhs_strs) (True, lhs_strs, arrow_s, arrow_col)
        | otherwise = NoSig

fn :: fmt_finish_sig_parse String String String (Bool, [String], String, Int) => FmtSig
      fmt_finish_sig_parse _ _ _ (False, _, _, _) = NoSig
      fmt_finish_sig_parse _ _ _ (True, [], _, _) = NoSig
      fmt_finish_sig_parse clean cmt kind (True, lhs_strs, arrow_s, arrow_col) =
        ret_start = arrow_col + (str_len arrow_s)
        ret_core = fmt_trim (str_slice clean ret_start (str_len clean))
        ret_full = fmt_append_comment ret_core cmt
        SigInfo kind lhs_strs arrow_s ret_full [] 0 0

fn :: fmt_append_comment String String => String
      fmt_append_comment core   ""     =  core
      fmt_append_comment ""     cmt    =  cmt
      fmt_append_comment core   cmt    =  core + " " + cmt

-- ── Clause & `where` Binding Recognition ─────────────────────

fn :: fmt_has_fat_arrow [FmtToken] => Bool
      fmt_has_fat_arrow []         =  False
      fmt_has_fat_arrow ((FmtTok "=>" _):_) = True
      fmt_has_fat_arrow (_:rest)   =  fmt_has_fat_arrow rest

fn :: fmt_is_top_decl_line String => Bool
      fmt_is_top_decl_line line   =
        ind = fmt_leading_indent line
        tr = fmt_trim line
        toks = fmt_scan_tokens (fmt_strip_comment tr)
        fmt_is_top_decl_toks ind tr toks

fn :: fmt_is_top_decl_toks Int String [FmtToken] => Bool
      fmt_is_top_decl_toks _   tr     _
        | str_starts_with tr "@" = True
      fmt_is_top_decl_toks ind _      ((FmtTok w col):rest)
        | w == "fn" OR w == "op" OR w == "type" OR w == "import" OR w == "global" OR w == "context" OR w == "shared" OR w == "hardware" = True
        | ind == 0 AND (NOT (str_starts_with w "--")) AND (NOT (str_starts_with w "|")) = fmt_has_fat_arrow ([FmtTok w col] :: rest)
        | otherwise = False
      fmt_is_top_decl_toks _   _      []         =  False

fn :: fmt_op_tokens_match [String]       [String]       => Bool
      fmt_op_tokens_match []             []             =  True
      fmt_op_tokens_match (s_tok:s_rest) (c_tok:c_rest)
        | fmt_is_sig_type_tok s_tok = fmt_op_tokens_match s_rest c_rest
        | s_tok == c_tok = fmt_op_tokens_match s_rest c_rest
        | otherwise = False
      fmt_op_tokens_match _              _              =  False

fn :: fmt_is_bare_kind String => Bool
      fmt_is_bare_kind kind   =  kind == "bare_fn" OR kind == "bare_op"

fn :: fmt_sig_base_col String => Int
      fmt_sig_base_col kind
        | fmt_is_bare_kind kind = 0
        | otherwise = 6

fn :: fmt_sig_base_col_from FmtSig => Int
      fmt_sig_base_col_from (SigInfo kind _ _ _ _ _ _) = fmt_sig_base_col kind
      fmt_sig_base_col_from _      =  6

fn :: fmt_clause_matches_sig String    [String] [String]   => Bool
      fmt_clause_matches_sig _         _        []         =  False
      fmt_clause_matches_sig "fn"      sig_lhs  clause_lhs =
        (fmt_str_list_len clause_lhs) == (fmt_str_list_len sig_lhs) AND (fmt_str_head clause_lhs) == (fmt_str_head sig_lhs)
      fmt_clause_matches_sig "bare_fn" sig_lhs  clause_lhs =
        (fmt_str_list_len clause_lhs) == (fmt_str_list_len sig_lhs) AND (fmt_str_head clause_lhs) == (fmt_str_head sig_lhs)
      fmt_clause_matches_sig "op"      sig_lhs  clause_lhs =
        (fmt_str_list_len clause_lhs) == (fmt_str_list_len sig_lhs) AND (fmt_op_tokens_match sig_lhs clause_lhs)
      fmt_clause_matches_sig "bare_op" sig_lhs  clause_lhs =
        (fmt_str_list_len clause_lhs) == (fmt_str_list_len sig_lhs) AND (fmt_op_tokens_match sig_lhs clause_lhs)
      fmt_clause_matches_sig _         _        _          =  False

fn :: fmt_split_clause_eq [FmtToken] [String] => ([String], Bool, Int)
      fmt_split_clause_eq []         lhs_acc  =  (lhs_acc, False, 0)
      fmt_split_clause_eq ((FmtTok "=" col):_) lhs_acc = (lhs_acc, True, col)
      fmt_split_clause_eq ((FmtTok tok _):rest) lhs_acc = fmt_split_clause_eq rest (lhs_acc :: [tok])

fn :: fmt_next_nonblank_is_guard [String] => Bool
      fmt_next_nonblank_is_guard []       =  False
      fmt_next_nonblank_is_guard (l:ls)   =
        clean = fmt_trim (fmt_strip_comment l)
        fmt_check_guard_line clean ls

fn :: fmt_check_guard_line String [String] => Bool
      fmt_check_guard_line ""     ls       =  fmt_next_nonblank_is_guard ls
      fmt_check_guard_line clean  _        =
        (str_starts_with clean "|") AND (NOT (str_starts_with clean "||"))

fn :: fmt_parse_clause_line FmtSig String Bool          => FmtClause
      fmt_parse_clause_line NoSig  _      _             =  NoClause
      fmt_parse_clause_line (SigInfo kind sig_lhs _ _ _ _ _) line next_is_guard
        | str_contains line (char_from_code 10) = NoClause
        | otherwise = fmt_parse_clause_clean kind sig_lhs line (fmt_strip_comment line) (fmt_trim (fmt_strip_comment line)) next_is_guard

fn :: fmt_parse_clause_clean String [String] String String String Bool => FmtClause
      fmt_parse_clause_clean _ _ _ _ "" _ = NoClause
      fmt_parse_clause_clean kind sig_lhs line clean tr next_is_guard
        | (str_starts_with tr "|") OR (str_starts_with tr "--") OR (fmt_is_top_decl_line tr) = NoClause
        | otherwise = fmt_check_clause_split kind sig_lhs line next_is_guard (fmt_split_clause_eq (fmt_scan_tokens clean) [])

fn :: fmt_check_clause_split String [String] String Bool ([String], Bool, Int) => FmtClause
      fmt_check_clause_split kind sig_lhs line next_is_guard (clause_lhs, has_eq, eq_col)
        | (fmt_clause_matches_sig kind sig_lhs clause_lhs) AND (has_eq OR next_is_guard) = fmt_build_clause_info line clause_lhs has_eq eq_col
        | otherwise = NoClause

fn :: fmt_build_clause_info String [String]   Bool  Int    => FmtClause
      fmt_build_clause_info line   clause_lhs True  eq_col =
        rhs = fmt_trim (str_slice line (eq_col + 1) (str_len line))
        ClauseInfo clause_lhs True rhs
      fmt_build_clause_info _      clause_lhs False _      =
        ClauseInfo clause_lhs False ""

fn :: fmt_find_where_arrow [FmtToken] => Int
      fmt_find_where_arrow []         =  -1
      fmt_find_where_arrow ((FmtTok "->" col):_) = col
      fmt_find_where_arrow (_:rest)   =  fmt_find_where_arrow rest

fn :: fmt_parse_where_line String Bool  => FmtWhereBind
      fmt_parse_where_line _      False =  NoWhereBind
      fmt_parse_where_line line   True  =
        clean = fmt_strip_comment line
        tr = fmt_trim clean
        fmt_parse_where_clean line clean tr

fn :: fmt_parse_where_clean String String String => FmtWhereBind
      fmt_parse_where_clean _      _      ""     =  NoWhereBind
      fmt_parse_where_clean line   clean  tr
        | (str_starts_with tr "|") OR (tr == "where") OR (fmt_is_top_decl_line tr) = NoWhereBind
        | otherwise = fmt_build_where_bind line clean (fmt_find_where_arrow (fmt_scan_tokens clean))

fn :: fmt_build_where_bind String String Int       => FmtWhereBind
      fmt_build_where_bind _      _      -1        =  NoWhereBind
      fmt_build_where_bind line   clean  arrow_col =
        lhs = fmt_trim (str_slice clean 0 arrow_col)
        rhs = fmt_trim (str_slice line (arrow_col + 2) (str_len line))
        fmt_check_where_nonempty lhs rhs

fn :: fmt_check_where_nonempty String String => FmtWhereBind
      fmt_check_where_nonempty ""     _      =  NoWhereBind
      fmt_check_where_nonempty _      ""     =  NoWhereBind
      fmt_check_where_nonempty lhs    rhs    =  WhereBindInfo lhs rhs

-- ── Group Column Geometry Calculation ────────────────────────

fn :: fmt_map_str_lens [String] => [Int]
      fmt_map_str_lens []       =  []
      fmt_map_str_lens (s:ss)   =  [str_len s] :: (fmt_map_str_lens ss)

fn :: fmt_slot_width Int Int   => Int
      fmt_slot_width w   s_len
        | s_len > 18 = w
        | otherwise = fmt_max w s_len

fn :: fmt_max_widths [Int]  [String] => [Int]
      fmt_max_widths []     _        =  []
      fmt_max_widths ws     []       =  ws
      fmt_max_widths (w:ws) (s:ss)   =  [fmt_slot_width w (str_len s)] :: (fmt_max_widths ws ss)

fn :: fmt_build_col_starts [Int]  Int     => [Int]
      fmt_build_col_starts []     _       =  []
      fmt_build_col_starts (w:ws) cur_col =  [cur_col] :: (fmt_build_col_starts ws (cur_col + w + 1))

fn :: fmt_end_col [Int]  Int     => Int
      fmt_end_col []     cur_col =  cur_col
      fmt_end_col (w:ws) cur_col =  fmt_end_col ws (cur_col + w + 1)

fn :: fmt_scan_group_widths FmtSig [String] [Int] Int Bool => ([Int], Int)
      fmt_scan_group_widths _ [] widths max_where _ = (widths, max_where)
      fmt_scan_group_widths sig (line:rest) widths max_where in_where =
        tr_clean = fmt_trim (fmt_strip_comment line)
        next_is_guard = fmt_next_nonblank_is_guard rest
        cl = fmt_parse_clause_line sig line next_is_guard
        wb = fmt_parse_where_line line in_where
        fmt_scan_group_step sig tr_clean rest widths max_where in_where cl wb

fn :: fmt_scan_group_step FmtSig String [String] [Int] Int Bool FmtClause FmtWhereBind => ([Int], Int)
      fmt_scan_group_step sig _ rest widths max_where _ (ClauseInfo c_lhs _ _) _ =
        fmt_scan_group_widths sig rest (fmt_max_widths widths c_lhs) max_where False
      fmt_scan_group_step sig _ rest widths max_where in_where NoClause (WhereBindInfo w_lhs _) =
        w_end = (fmt_sig_base_col_from sig) + 4 + (str_len w_lhs) + 1
        fmt_scan_group_widths sig rest widths (fmt_max max_where w_end) in_where
      fmt_scan_group_step sig tr_clean rest widths max_where in_where NoClause NoWhereBind
        | tr_clean == "where" = fmt_scan_group_widths sig rest widths max_where True
        | str_starts_with tr_clean "|" = fmt_scan_group_widths sig rest widths max_where False
        | otherwise = fmt_scan_group_widths sig rest widths max_where in_where

fn :: fmt_compute_group_geometry FmtSig [String]    => FmtSig
      fmt_compute_group_geometry NoSig  _           =  NoSig
      fmt_compute_group_geometry (SigInfo kind lhs_strs arrow_s ret_s _ _ _) group_lines =
        init_widths = fmt_map_str_lens lhs_strs
        base_sig = SigInfo kind lhs_strs arrow_s ret_s [] 0 0
        scan_res = fmt_scan_group_widths base_sig group_lines init_widths 0 False
        fmt_finish_group_geometry kind lhs_strs arrow_s ret_s scan_res

fn :: fmt_count_op_params [String]   => Int
      fmt_count_op_params []         =  0
      fmt_count_op_params (tok:rest)
        | fmt_is_sig_type_tok tok = 1 + (fmt_count_op_params rest)
        | otherwise = fmt_count_op_params rest

fn :: fmt_count_sig_params String    [String] => Int
      fmt_count_sig_params "fn"      lhs_strs =  (fmt_str_list_len lhs_strs) - 1
      fmt_count_sig_params "bare_fn" lhs_strs =  (fmt_str_list_len lhs_strs) - 1
      fmt_count_sig_params _         lhs_strs =  fmt_count_op_params lhs_strs

fn :: fmt_finish_group_geometry String [String] String String ([Int], Int) => FmtSig
      fmt_finish_group_geometry kind lhs_strs arrow_s ret_s (widths, max_where) =
        base_col = fmt_sig_base_col kind
        sig_cols = fmt_build_col_starts widths base_col
        end_col = fmt_end_col widths base_col
        arrow_col = fmt_max end_col max_where
        ret_col = arrow_col + (str_len arrow_s) + 1
        total_sig_len = ret_col + (str_len ret_s)
        num_params = fmt_count_sig_params kind lhs_strs
        fmt_select_group_geometry kind lhs_strs arrow_s ret_s sig_cols arrow_col ret_col num_params total_sig_len

fn :: fmt_select_group_geometry String [String] String String [Int] Int Int Int Int => FmtSig
      fmt_select_group_geometry kind lhs_strs arrow_s ret_s sig_cols arrow_col ret_col num_params total_sig_len
        | num_params > 4 OR total_sig_len > 80 = SigInfo kind lhs_strs arrow_s ret_s [] 0 0
        | otherwise = SigInfo kind lhs_strs arrow_s ret_s sig_cols arrow_col ret_col

-- ── Line Formatting Functions ────────────────────────────────

fn :: fmt_pad_lhs_tokens [String]   [Int]    Int String => String
      fmt_pad_lhs_tokens []         _        _   acc    =  acc
      fmt_pad_lhs_tokens (tok:rest) sig_cols idx acc    =
        target_col = fmt_int_at sig_cols idx
        pad_n = fmt_max 1 (target_col - (str_len acc))
        fmt_pad_lhs_tokens rest sig_cols (idx + 1) (acc + (fmt_spaces pad_n) + tok)

fn :: fmt_sig_prefix String    String    => String
      fmt_sig_prefix "bare_fn" first_tok =  first_tok
      fmt_sig_prefix "bare_op" first_tok =  first_tok
      fmt_sig_prefix kind      first_tok =  kind + " :: " + first_tok

fn :: fmt_format_sig_line FmtSig => String
      fmt_format_sig_line NoSig  =  ""
      fmt_format_sig_line (SigInfo _ [] _ _ _ _ _) = ""
      fmt_format_sig_line (SigInfo kind (first_tok:rest_toks) arrow_s ret_s sig_cols arrow_col _) =
        lhs_out = fmt_pad_lhs_tokens rest_toks sig_cols 1 (fmt_sig_prefix kind first_tok)
        pad_arrow = fmt_max 1 (arrow_col - (str_len lhs_out))
        lhs_out + (fmt_spaces pad_arrow) + arrow_s + " " + ret_s

fn :: fmt_format_clause_line FmtSig [String] Bool   String => String
      fmt_format_clause_line _      []       _      _      =  ""
      fmt_format_clause_line (SigInfo kind _ _ _ sig_cols arrow_col ret_col) (first_tok:rest_toks) has_eq rhs =
        base_pad = fmt_spaces (fmt_sig_base_col kind)
        lhs_out = fmt_pad_lhs_tokens rest_toks sig_cols 1 (base_pad + first_tok)
        fmt_finish_clause_rhs lhs_out has_eq rhs arrow_col ret_col

fn :: fmt_format_clause_line_fallback [String] => String
      fmt_format_clause_line_fallback _        =  ""

fn :: fmt_finish_clause_rhs String Bool String Int Int => String
      fmt_finish_clause_rhs lhs_out False _ _ _ = lhs_out
      fmt_finish_clause_rhs lhs_out True "" arrow_col _ =
        pad_eq = fmt_max 1 (arrow_col - (str_len lhs_out))
        lhs_out + (fmt_spaces pad_eq) + "="
      fmt_finish_clause_rhs lhs_out True rhs arrow_col ret_col =
        pad_eq = fmt_max 1 (arrow_col - (str_len lhs_out))
        with_eq = lhs_out + (fmt_spaces pad_eq) + "="
        pad_rhs = fmt_max 1 (ret_col - (str_len with_eq))
        with_eq + (fmt_spaces pad_rhs) + rhs

fn :: fmt_format_where_line FmtSig String String => String
      fmt_format_where_line NoSig  lhs    rhs    =  "    " + lhs + " -> " + rhs
      fmt_format_where_line (SigInfo kind _ _ _ _ arrow_col ret_col) lhs rhs =
        lhs_out = (fmt_spaces ((fmt_sig_base_col kind) + 4)) + lhs
        pad_arrow = fmt_max 1 (arrow_col - (str_len lhs_out))
        with_arrow = lhs_out + (fmt_spaces pad_arrow) + "->"
        pad_rhs = fmt_max 1 (ret_col - (str_len with_arrow))
        with_arrow + (fmt_spaces pad_rhs) + rhs

-- ── Structural Block & Group Formatting ──────────────────────

fn :: fmt_line_opens_block String    => Bool
      fmt_line_opens_block prev_text =
        clean = fmt_trim (fmt_strip_comment prev_text)
        len = str_len clean
        fmt_check_block_opener clean len

fn :: fmt_check_block_opener String Int => Bool
      fmt_check_block_opener clean  len
        | len == 0 = False
        | clean == "where" OR clean == "do" = True
        | (str_char_at clean (len - 1)) == 61 AND (len < 2 OR ((str_char_at clean (len - 2)) != 61 AND (str_char_at clean (len - 2)) != 33 AND (str_char_at clean (len - 2)) != 60 AND (str_char_at clean (len - 2)) != 62)) = True
        | len >= 6 AND (str_slice clean (len - 6) len) == " where" = True
        | len >= 3 AND (str_slice clean (len - 3) len) == " do" = True
        | otherwise = False

fn :: fmt_format_group_body FmtSig [String] Int String Bool => [String]
      fmt_format_group_body _ [] _ _ _ = []
      fmt_format_group_body geom (line:rest) prev_indent prev_text in_where =
        tr = fmt_trim line
        tr_clean = fmt_trim (fmt_strip_comment line)
        orig_indent = fmt_leading_indent line
        next_is_guard = fmt_next_nonblank_is_guard rest
        cl = fmt_parse_clause_line geom line next_is_guard
        wb = fmt_parse_where_line line in_where
        fmt_format_group_line geom line tr tr_clean orig_indent rest prev_indent prev_text in_where cl wb

fn :: fmt_format_group_line FmtSig String String String Int [String] Int String Bool FmtClause FmtWhereBind => [String]
      fmt_format_group_line geom _ "" _ _ rest prev_indent prev_text in_where _ _ =
        [""] :: (fmt_format_group_body geom rest prev_indent prev_text in_where)
      fmt_format_group_line geom _ tr _ 0 rest prev_indent prev_text in_where _ _
        | str_starts_with tr "--" = [tr] :: (fmt_format_group_body geom rest prev_indent prev_text in_where)
      fmt_format_group_line geom _ _ _ _ rest _ _ _ (ClauseInfo c_lhs has_eq rhs) _ =
        f_line = fmt_format_clause_line geom c_lhs has_eq rhs
        [f_line] :: (fmt_format_group_body geom rest (fmt_sig_base_col_from geom) f_line False)
      fmt_format_group_line geom _ _ _ _ rest _ _ in_where NoClause (WhereBindInfo w_lhs w_rhs) =
        f_line = fmt_format_where_line geom w_lhs w_rhs
        [f_line] :: (fmt_format_group_body geom rest ((fmt_sig_base_col_from geom) + 4) f_line in_where)
      fmt_format_group_line geom _ tr tr_clean _ rest prev_indent prev_text in_where NoClause NoWhereBind
        | tr_clean == "where" = [(fmt_spaces ((fmt_sig_base_col_from geom) + 2)) + tr] :: (fmt_format_group_body geom rest ((fmt_sig_base_col_from geom) + 2) "where" True)
        | str_starts_with tr_clean "|" = [(fmt_spaces ((fmt_sig_base_col_from geom) + 2)) + tr] :: (fmt_format_group_body geom rest ((fmt_sig_base_col_from geom) + 2) tr False)
        | str_starts_with tr "--" = [fmt_indent_body_line prev_indent prev_text tr] :: (fmt_format_group_body geom rest prev_indent prev_text in_where)
        | otherwise = [fmt_indent_body_line prev_indent prev_text tr] :: (fmt_format_group_body geom rest (fmt_next_body_indent prev_indent prev_text) tr in_where)

fn :: fmt_next_body_indent Int         String    => Int
      fmt_next_body_indent prev_indent prev_text
        | fmt_line_opens_block prev_text = prev_indent + 2
        | otherwise = prev_indent

fn :: fmt_indent_body_line Int         String    String => String
      fmt_indent_body_line prev_indent prev_text tr     =
        ind = fmt_next_body_indent prev_indent prev_text
        (fmt_spaces ind) + tr

-- ── Top-Level File Partitioning into Groups ──────────────────

fn :: fmt_take_group_lines [String] [String] => ([String], [String])
      fmt_take_group_lines []       acc      =  (acc, [])
      fmt_take_group_lines (l:ls)   acc
        | fmt_is_top_decl_line l = (acc, [l] :: ls)
        | otherwise = fmt_take_group_lines ls (acc :: [l])

fn :: fmt_format_top_lines [String]    Int         String    => [String]
      fmt_format_top_lines []          _           _         =  []
      fmt_format_top_lines (line:rest) prev_indent prev_text =
        sig = fmt_parse_sig_line line
        fmt_dispatch_top_line line rest prev_indent prev_text sig

fn :: fmt_dispatch_top_line String [String] Int String FmtSig => [String]
      fmt_dispatch_top_line _ rest _ _ (SigInfo kind lhs_strs arrow_s ret_s cols a_col r_col) =
        grp_split = fmt_take_group_lines rest []
        fmt_run_sig_group (SigInfo kind lhs_strs arrow_s ret_s cols a_col r_col) grp_split
      fmt_dispatch_top_line line rest prev_indent prev_text NoSig =
        tr = fmt_trim line
        fmt_format_non_sig_top tr rest prev_indent prev_text

fn :: fmt_run_sig_group FmtSig  ([String], [String]) => [String]
      fmt_run_sig_group raw_sig (grp_lines, rem_lines) =
        geom = fmt_compute_group_geometry raw_sig grp_lines
        sig_line = fmt_format_sig_line geom
        body_lines = fmt_format_group_body geom grp_lines (fmt_sig_base_col_from geom) "" False
        [sig_line] :: body_lines :: (fmt_format_top_lines rem_lines 0 "")

fn :: fmt_format_non_sig_top String [String] Int         String    => [String]
      fmt_format_non_sig_top ""     rest     prev_indent prev_text =
        [""] :: (fmt_format_top_lines rest prev_indent prev_text)
      fmt_format_non_sig_top tr     rest     _           _
        | fmt_is_top_decl_line tr = [tr] :: (fmt_format_top_lines rest 0 tr)
      fmt_format_non_sig_top tr     rest     prev_indent prev_text
        | str_starts_with tr "--" = [tr] :: (fmt_format_top_lines rest prev_indent prev_text)
        | otherwise = [fmt_indent_body_line prev_indent prev_text tr] :: (fmt_format_top_lines rest (fmt_next_body_indent prev_indent prev_text) tr)

-- ── Public Entry Point (`format ridgun source`) ──────────────

op :: format ridgun source String => String
      format ridgun source src    =
        raw_lines = fmt_split_raw_lines src
        formatted_lines = fmt_format_top_lines raw_lines 0 ""
        fmt_join_lines formatted_lines
