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

fn :: fmt max Int Int => Int
      fmt max a   b
        | a >= b = a
        | otherwise = b

fn :: fmt str list len [String] => Int
      fmt str list len []       =  0
      fmt str list len (_:xs)   =  1 + (fmt str list len xs)

fn :: fmt str head [String] => String
      fmt str head []       =  ""
      fmt str head (x:_)    =  x

fn :: fmt int at [Int]  Int => Int
      fmt int at []     _   =  -1
      fmt int at (x:_)  0   =  x
      fmt int at (_:xs) idx =  fmt int at xs (idx - 1)

fn :: fmt spaces Int => String
      fmt spaces n
        | n <= 0 = ""
        | otherwise = " " + (fmt spaces (n - 1))

-- ── Whitespace & Line Splitting Helpers ──────────────────────

fn :: fmt is hspace Int => Bool
      fmt is hspace c   =  c == 32 or c == 9 or c == 13

fn :: fmt leading indent loop String Int Int => Int
      fmt leading indent loop s pos len
        | pos >= len = len
        | (str char at s pos) == 32 or (str char at s pos) == 9 = fmt leading indent loop s (pos + 1) len
        | otherwise = pos

fn :: fmt leading indent String => Int
      fmt leading indent s      =  fmt leading indent loop s 0 (str len s)

fn :: fmt trim left loop String Int Int => String
      fmt trim left loop s pos len
        | pos >= len = ""
        | fmt is hspace (str char at s pos) = fmt trim left loop s (pos + 1) len
        | otherwise = str slice s pos len

fn :: fmt trim left String => String
      fmt trim left s      =  fmt trim left loop s 0 (str len s)

fn :: fmt trim right loop String Int => String
      fmt trim right loop s end_pos
        | end_pos <= 0 = ""
        | fmt is hspace (str char at s (end_pos - 1)) = fmt trim right loop s (end_pos - 1)
        | otherwise = str slice s 0 end_pos

fn :: fmt trim right String => String
      fmt trim right s      =  fmt trim right loop s (str len s)

fn :: fmt trim String => String
      fmt trim s      =  fmt trim left (fmt trim right s)

fn :: fmt split raw lines loop String Int Int Int Int [String] => [String]
      fmt split raw lines loop s pos len line_start quote_st acc
        | pos >= len and line_start == len = acc
        | pos >= len = acc :: [fmt trim right (str slice s line_start len)]
        | quote_st == 34 and (str char at s pos) == 92 = fmt split raw lines loop s (pos + 2) len line_start 34 acc
        | quote_st == 34 and (str char at s pos) == 34 = fmt split raw lines loop s (pos + 1) len line_start 0 acc
        | quote_st == 34 = fmt split raw lines loop s (pos + 1) len line_start 34 acc
        | quote_st == 39 and (str char at s pos) == 39 = fmt split raw lines loop s (pos + 1) len line_start 0 acc
        | quote_st == 39 = fmt split raw lines loop s (pos + 1) len line_start 39 acc
        | quote_st == 45 and (str char at s pos) == 10 = fmt split raw lines loop s (pos + 1) len (pos + 1) 0 (acc :: [fmt trim right (str slice s line_start pos)])
        | quote_st == 45 = fmt split raw lines loop s (pos + 1) len line_start 45 acc
        | (str char at s pos) == 10 = fmt split raw lines loop s (pos + 1) len (pos + 1) 0 (acc :: [fmt trim right (str slice s line_start pos)])
        | (str char at s pos) == 45 and (pos + 1) < len and (str char at s (pos + 1)) == 45 = fmt split raw lines loop s (pos + 2) len line_start 45 acc
        | (str char at s pos) == 34 = fmt split raw lines loop s (pos + 1) len line_start 34 acc
        | (str char at s pos) == 39 = fmt split raw lines loop s (pos + 1) len line_start 39 acc
        | otherwise = fmt split raw lines loop s (pos + 1) len line_start 0 acc

fn :: fmt split raw lines String => [String]
      fmt split raw lines s      =  fmt split raw lines loop s 0 (str len s) 0 0 []

fn :: fmt join lines [String] => String
      fmt join lines []       =  ""
      fmt join lines (l:[])   =  l + (char from code 10)
      fmt join lines (l:ls)   =  l + (char from code 10) + (fmt join lines ls)

-- ── Quote-Aware Comment Splitting (`-- ...`) ─────────────────

fn :: fmt skip quoted String Int Int Int => Int
      fmt skip quoted s pos len quote_ch
        | pos >= len = len
        | (str char at s pos) == 92 = fmt skip quoted s (pos + 2) len quote_ch
        | (str char at s pos) == quote_ch = pos + 1
        | otherwise = fmt skip quoted s (pos + 1) len quote_ch

fn :: fmt find comment col String Int Int => Int
      fmt find comment col s pos len
        | pos >= len = -1
        | (str char at s pos) == 34 = fmt find comment col s (fmt skip quoted s (pos + 1) len 34) len
        | (str char at s pos) == 39 = fmt find comment col s (fmt skip quoted s (pos + 1) len 39) len
        | (pos + 1) < len and (str char at s pos) == 45 and (str char at s (pos + 1)) == 45 = pos
        | otherwise = fmt find comment col s (pos + 1) len

fn :: fmt strip comment String => String
      fmt strip comment line   =
        c_col = fmt find comment col line 0 (str len line)
        fmt strip comment at line c_col

fn :: fmt strip comment at String Int => String
      fmt strip comment at line -1 = fmt trim right line
      fmt strip comment at line c_col = fmt trim right (str slice line 0 c_col)

fn :: fmt extract comment String => String
      fmt extract comment line   =
        c_col = fmt find comment col line 0 (str len line)
        fmt extract comment at line c_col

fn :: fmt extract comment at String Int => String
      fmt extract comment at _ -1 = ""
      fmt extract comment at line c_col = fmt trim right (str slice line c_col (str len line))

-- ── Line Token Scanner (`ridgun--scan-tokens-with-cols`) ─────

fn :: fmt skip hspace String Int Int => Int
      fmt skip hspace s pos len
        | pos >= len = len
        | fmt is hspace (str char at s pos) = fmt skip hspace s (pos + 1) len
        | otherwise = pos

fn :: fmt scan group end String Int Int Int => Int
      fmt scan group end s pos len depth
        | pos >= len = len
        | (str char at s pos) == 34 = fmt scan group end s (fmt skip quoted s (pos + 1) len 34) len depth
        | (str char at s pos) == 39 = fmt scan group end s (fmt skip quoted s (pos + 1) len 39) len depth
        | (str char at s pos) == 40 or (str char at s pos) == 91 = fmt scan group end s (pos + 1) len (depth + 1)
        | ((str char at s pos) == 41 or (str char at s pos) == 93) and depth <= 1 = pos + 1
        | (str char at s pos) == 41 or (str char at s pos) == 93 = fmt scan group end s (pos + 1) len (depth - 1)
        | otherwise = fmt scan group end s (pos + 1) len depth

fn :: fmt scan word end String Int Int Int => Int
      fmt scan word end s pos len depth
        | pos >= len = len
        | depth == 0 and (fmt is hspace (str char at s pos)) = pos
        | (str char at s pos) == 34 = fmt scan word end s (fmt skip quoted s (pos + 1) len 34) len depth
        | (str char at s pos) == 39 = fmt scan word end s (fmt skip quoted s (pos + 1) len 39) len depth
        | (str char at s pos) == 40 or (str char at s pos) == 91 = fmt scan word end s (pos + 1) len (depth + 1)
        | (str char at s pos) == 41 or (str char at s pos) == 93 = fmt scan word end s (pos + 1) len (fmt max 0 (depth - 1))
        | otherwise = fmt scan word end s (pos + 1) len depth

fn :: fmt scan token end String Int Int Int => Int
      fmt scan token end s pos len ch
        | ch == 34 or ch == 39 = fmt skip quoted s (pos + 1) len ch
        | ch == 40 or ch == 91 = fmt scan group end s (pos + 1) len 1
        | otherwise = fmt scan word end s pos len 0

fn :: fmt scan tokens loop String Int Int [FmtToken] => [FmtToken]
      fmt scan tokens loop s pos len acc =
        p = fmt skip hspace s pos len
        fmt scan tokens at s p len acc

fn :: fmt scan tokens at String Int Int [FmtToken] => [FmtToken]
      fmt scan tokens at s p len acc
        | p >= len = acc
        | otherwise = fmt scan tokens at step s p len acc (fmt scan token end s p len (str char at s p))

fn :: fmt scan tokens at step String Int Int [FmtToken] Int => [FmtToken]
      fmt scan tokens at step s p len acc end_p =
        tok_s = str slice s p end_p
        fmt scan tokens loop s end_p len (acc :: [FmtTok tok_s p])

fn :: fmt scan tokens String => [FmtToken]
      fmt scan tokens line   =  fmt scan tokens loop line 0 (str len line) []

-- ── Signature Parsing (`fn ::` / `op ::`) ────────────────────

fn :: fmt split sig arrow [FmtToken] [String] => Bool [String] String Int
      fmt split sig arrow [] _ = (False, [], "", 0)
      fmt split sig arrow ((FmtTok tok col):rest) lhs_acc
        | tok == "=>" or tok == "->" = (True, lhs_acc, tok, col)
        | otherwise = fmt split sig arrow rest (lhs_acc :: [tok])

fn :: fmt is sig type tok String => Bool
      fmt is sig type tok "" = False
      fmt is sig type tok tok =
        ch = str char at tok 0
        (ch >= 65 and ch <= 90) or ch == 91 or ch == 40

fn :: fmt all type toks [String] => Bool
      fmt all type toks []       =  True
      fmt all type toks (t:rest)
        | fmt is sig type tok t = fmt all type toks rest
        | otherwise = False

fn :: fmt is bare fn lhs [String] => Bool
      fmt is bare fn lhs (first_w:rest)
        | not (fmt is sig type tok first_w) = fmt all type toks rest
      fmt is bare fn lhs _ = False

fn :: fmt infer bare kind [String] => String
      fmt infer bare kind lhs_strs
        | fmt is bare fn lhs lhs_strs = "bare_fn"
        | otherwise = "bare_op"

fn :: fmt parse sig line String => FmtSig
      fmt parse sig line line   =
        clean = fmt strip comment line
        cmt = fmt extract comment line
        toks = fmt scan tokens clean
        fmt parse sig tokens (fmt leading indent line) clean cmt toks

fn :: fmt parse sig tokens Int String String [FmtToken] => FmtSig
      fmt parse sig tokens _ clean cmt ((FmtTok kind _):(FmtTok "::" _):rest)
        | kind == "fn" or kind == "op" = fmt finish sig parse clean cmt kind (fmt split sig arrow rest [])
      fmt parse sig tokens 0 clean cmt ((FmtTok w col):rest)
        | w == "type" or w == "expand" or w == "import" or w == "hardware" or (str starts with w "@") or (str starts with w "--") or (str starts with w "|") = NoSig
        | otherwise = fmt finish bare sig parse clean cmt (fmt split sig arrow ([FmtTok w col] :: rest) [])
      fmt parse sig tokens _ _ _ _ = NoSig

fn :: fmt finish bare sig parse String String (Bool, [String], String, Int) => FmtSig
      fmt finish bare sig parse _ _ (False, _, _, _) = NoSig
      fmt finish bare sig parse _ _ (True, [], _, _) = NoSig
      fmt finish bare sig parse clean cmt (True, lhs_strs, arrow_s, arrow_col)
        | arrow_s == "=>" = fmt finish sig parse clean cmt (fmt infer bare kind lhs_strs) (True, lhs_strs, arrow_s, arrow_col)
        | otherwise = NoSig

fn :: fmt finish sig parse String String String (Bool, [String], String, Int) => FmtSig
      fmt finish sig parse _ _ _ (False, _, _, _) = NoSig
      fmt finish sig parse _ _ _ (True, [], _, _) = NoSig
      fmt finish sig parse clean cmt kind (True, lhs_strs, arrow_s, arrow_col) =
        ret_start = arrow_col + (str len arrow_s)
        ret_core = fmt trim (str slice clean ret_start (str len clean))
        ret_full = fmt append comment ret_core cmt
        SigInfo kind lhs_strs arrow_s ret_full [] 0 0

fn :: fmt append comment String String => String
      fmt append comment core   ""     =  core
      fmt append comment ""     cmt    =  cmt
      fmt append comment core   cmt    =  core + " " + cmt

-- ── Clause & `where` Binding Recognition ─────────────────────

fn :: fmt has fat arrow [FmtToken] => Bool
      fmt has fat arrow []         =  False
      fmt has fat arrow ((FmtTok "=>" _):_) = True
      fmt has fat arrow (_:rest)   =  fmt has fat arrow rest

fn :: fmt is top decl line String => Bool
      fmt is top decl line line =
        ind = fmt leading indent line
        tr = fmt trim line
        toks = fmt scan tokens (fmt strip comment tr)
        fmt is top decl toks ind tr toks

fn :: fmt is top decl toks Int String [FmtToken] => Bool
      fmt is top decl toks _ tr _
        | str starts with tr "@" = True
      fmt is top decl toks ind _ ((FmtTok w col):rest)
        | w == "fn" or w == "op" or w == "type" or w == "expand" or w == "import" or w == "hardware" = True
        | ind == 0 and (not (str starts with w "--")) and (not (str starts with w "|")) = fmt has fat arrow ([FmtTok w col] :: rest)
        | otherwise = False
      fmt is top decl toks _ _ [] = False

fn :: fmt op tokens match [String] [String] => Bool
      fmt op tokens match [] [] = True
      fmt op tokens match (s_tok:s_rest) (c_tok:c_rest)
        | fmt is sig type tok s_tok = fmt op tokens match s_rest c_rest
        | s_tok == c_tok = fmt op tokens match s_rest c_rest
        | otherwise = False
      fmt op tokens match _ _ = False

fn :: fmt is bare kind String => Bool
      fmt is bare kind kind   =  kind == "bare_fn" or kind == "bare_op"

fn :: fmt sig base col String => Int
      fmt sig base col kind
        | fmt is bare kind kind = 0
        | otherwise = 6

fn :: fmt sig base col from FmtSig => Int
      fmt sig base col from (SigInfo kind _ _ _ _ _ _) = fmt sig base col kind
      fmt sig base col from _ = 6

fn :: fmt clause matches sig String [String] [String] => Bool
      fmt clause matches sig _ _ [] = False
      fmt clause matches sig "fn" sig_lhs clause_lhs =
        (fmt str list len clause_lhs) == (fmt str list len sig_lhs) and (fmt str head clause_lhs) == (fmt str head sig_lhs)
      fmt clause matches sig "bare_fn" sig_lhs clause_lhs =
        (fmt str list len clause_lhs) == (fmt str list len sig_lhs) and (fmt str head clause_lhs) == (fmt str head sig_lhs)
      fmt clause matches sig "op" sig_lhs clause_lhs =
        (fmt str list len clause_lhs) == (fmt str list len sig_lhs) and (fmt op tokens match sig_lhs clause_lhs)
      fmt clause matches sig "bare_op" sig_lhs clause_lhs =
        (fmt str list len clause_lhs) == (fmt str list len sig_lhs) and (fmt op tokens match sig_lhs clause_lhs)
      fmt clause matches sig _ _ _ = False

fn :: fmt split clause eq [FmtToken] [String] => [String] Bool Int
      fmt split clause eq [] lhs_acc = (lhs_acc, False, 0)
      fmt split clause eq ((FmtTok "=" col):_) lhs_acc = (lhs_acc, True, col)
      fmt split clause eq ((FmtTok tok _):rest) lhs_acc = fmt split clause eq rest (lhs_acc :: [tok])

fn :: fmt next nonblank is guard [String] => Bool
      fmt next nonblank is guard [] = False
      fmt next nonblank is guard (l:ls) =
        clean = fmt trim (fmt strip comment l)
        fmt check guard line clean ls

fn :: fmt check guard line String [String] => Bool
      fmt check guard line "" ls = fmt next nonblank is guard ls
      fmt check guard line clean _ =
        (str starts with clean "|") and (not (str starts with clean "||"))

fn :: fmt parse clause line FmtSig String Bool => FmtClause
      fmt parse clause line NoSig _ _ = NoClause
      fmt parse clause line (SigInfo kind sig_lhs _ _ _ _ _) line next_is_guard
        | str contains line (char from code 10) = NoClause
        | otherwise = fmt parse clause clean kind sig_lhs line (fmt strip comment line) (fmt trim (fmt strip comment line)) next_is_guard

fn :: fmt parse clause clean String [String] String String String Bool => FmtClause
      fmt parse clause clean _ _ _ _ "" _ = NoClause
      fmt parse clause clean kind sig_lhs line clean tr next_is_guard
        | (str starts with tr "|") or (str starts with tr "--") or (fmt is top decl line tr) = NoClause
        | otherwise = fmt check clause split kind sig_lhs line next_is_guard (fmt split clause eq (fmt scan tokens clean) [])

fn :: fmt check clause split String [String] String Bool ([String], Bool, Int) => FmtClause
      fmt check clause split kind sig_lhs line next_is_guard (clause_lhs, has_eq, eq_col)
        | (fmt clause matches sig kind sig_lhs clause_lhs) and (has_eq or next_is_guard) = fmt build clause info line clause_lhs has_eq eq_col
        | otherwise = NoClause

fn :: fmt build clause info String [String] Bool Int => FmtClause
      fmt build clause info line clause_lhs True eq_col =
        rhs = fmt trim (str slice line (eq_col + 1) (str len line))
        ClauseInfo clause_lhs True rhs
      fmt build clause info _ clause_lhs False _ =
        ClauseInfo clause_lhs False ""

fn :: fmt find where arrow [FmtToken] => Int
      fmt find where arrow []         =  -1
      fmt find where arrow ((FmtTok "->" col):_) = col
      fmt find where arrow (_:rest)   =  fmt find where arrow rest

fn :: fmt parse where line String Bool => FmtWhereBind
      fmt parse where line _ False = NoWhereBind
      fmt parse where line line True =
        clean = fmt strip comment line
        tr = fmt trim clean
        fmt parse where clean line clean tr

fn :: fmt parse where clean String String String => FmtWhereBind
      fmt parse where clean _ _ "" = NoWhereBind
      fmt parse where clean line clean tr
        | (str starts with tr "|") or (fmt is top decl line tr) = NoWhereBind
        | otherwise = fmt build where bind line clean (fmt find where arrow (fmt scan tokens clean))

fn :: fmt build where bind String String Int => FmtWhereBind
      fmt build where bind _ _ -1 = NoWhereBind
      fmt build where bind line clean arrow_col =
        lhs = fmt trim (str slice clean 0 arrow_col)
        rhs = fmt trim (str slice line (arrow_col + 2) (str len line))
        fmt check where nonempty lhs rhs

fn :: fmt check where nonempty String String => FmtWhereBind
      fmt check where nonempty "" _ = NoWhereBind
      fmt check where nonempty _ "" = NoWhereBind
      fmt check where nonempty lhs rhs = WhereBindInfo lhs rhs

-- ── Group Column Geometry Calculation ────────────────────────

fn :: fmt map str lens [String] => [Int]
      fmt map str lens []       =  []
      fmt map str lens (s:ss)   =  [str len s] :: (fmt map str lens ss)

fn :: fmt slot width Int Int   => Int
      fmt slot width w   s_len
        | s_len > 18 = w
        | otherwise = fmt max w s_len

fn :: fmt max widths [Int]  [String] => [Int]
      fmt max widths []     _        =  []
      fmt max widths ws     []       =  ws
      fmt max widths (w:ws) (s:ss)   =  [fmt slot width w (str len s)] :: (fmt max widths ws ss)

fn :: fmt build col starts [Int] Int => [Int]
      fmt build col starts [] _ = []
      fmt build col starts (w:ws) cur_col = [cur_col] :: (fmt build col starts ws (cur_col + w + 1))

fn :: fmt end col [Int]  Int     => Int
      fmt end col []     cur_col =  cur_col
      fmt end col (w:ws) cur_col =  fmt end col ws (cur_col + w + 1)

fn :: fmt scan group widths FmtSig [String] [Int] Int Bool => [Int] Int
      fmt scan group widths _ [] widths max_where _ = (widths, max_where)
      fmt scan group widths sig (line:rest) widths max_where in_where =
        tr_clean = fmt trim (fmt strip comment line)
        next_is_guard = fmt next nonblank is guard rest
        cl = fmt parse clause line sig line next_is_guard
        wb = fmt parse where line line in_where
        fmt scan group step sig tr_clean rest widths max_where in_where cl wb

fn :: fmt scan group step FmtSig String [String] [Int] Int Bool FmtClause FmtWhereBind => [Int] Int
      fmt scan group step sig _ rest widths max_where _ (ClauseInfo c_lhs _ _) _ =
        fmt scan group widths sig rest (fmt max widths widths c_lhs) max_where False
      fmt scan group step sig _ rest widths max_where in_where NoClause (WhereBindInfo w_lhs _) =
        w_end = (fmt sig base col from sig) + 4 + (str len w_lhs) + 1
        fmt scan group widths sig rest widths (fmt max max_where w_end) in_where
      fmt scan group step sig tr_clean rest widths max_where in_where NoClause NoWhereBind
        | str starts with tr_clean "|" = fmt scan group widths sig rest widths max_where False
        | otherwise = fmt scan group widths sig rest widths max_where in_where

fn :: fmt compute group geometry FmtSig [String] => FmtSig
      fmt compute group geometry NoSig _ = NoSig
      fmt compute group geometry (SigInfo kind lhs_strs arrow_s ret_s _ _ _) group_lines =
        init_widths = fmt map str lens lhs_strs
        base_sig = SigInfo kind lhs_strs arrow_s ret_s [] 0 0
        scan_res = fmt scan group widths base_sig group_lines init_widths 0 False
        fmt finish group geometry kind lhs_strs arrow_s ret_s scan_res

fn :: fmt count op params [String]   => Int
      fmt count op params []         =  0
      fmt count op params (tok:rest)
        | fmt is sig type tok tok = 1 + (fmt count op params rest)
        | otherwise = fmt count op params rest

fn :: fmt count sig params String [String] => Int
      fmt count sig params "fn" lhs_strs = (fmt str list len lhs_strs) - 1
      fmt count sig params "bare_fn" lhs_strs = (fmt str list len lhs_strs) - 1
      fmt count sig params _ lhs_strs = fmt count op params lhs_strs

fn :: fmt finish group geometry String [String] String String ([Int], Int) => FmtSig
      fmt finish group geometry kind lhs_strs arrow_s ret_s (widths, max_where) =
        base_col = fmt sig base col kind
        sig_cols = fmt build col starts widths base_col
        end_col = fmt end col widths base_col
        arrow_col = fmt max end_col max_where
        ret_col = arrow_col + (str len arrow_s) + 1
        total_sig_len = ret_col + (str len ret_s)
        num_params = fmt count sig params kind lhs_strs
        fmt select group geometry kind lhs_strs arrow_s ret_s sig_cols arrow_col ret_col num_params total_sig_len

fn :: fmt select group geometry String [String] String String [Int] Int Int Int Int => FmtSig
      fmt select group geometry kind lhs_strs arrow_s ret_s sig_cols arrow_col ret_col num_params total_sig_len
        | num_params > 4 or total_sig_len > 80 = SigInfo kind lhs_strs arrow_s ret_s [] 0 0
        | otherwise = SigInfo kind lhs_strs arrow_s ret_s sig_cols arrow_col ret_col

-- ── Line Formatting Functions ────────────────────────────────

fn :: fmt pad lhs tokens [String] [Int] Int String => String
      fmt pad lhs tokens [] _ _ acc = acc
      fmt pad lhs tokens (tok:rest) sig_cols idx acc =
        target_col = fmt int at sig_cols idx
        pad_n = fmt max 1 (target_col - (str len acc))
        fmt pad lhs tokens rest sig_cols (idx + 1) (acc + (fmt spaces pad_n) + tok)

fn :: fmt sig prefix String    String    => String
      fmt sig prefix "bare_fn" first_tok =  first_tok
      fmt sig prefix "bare_op" first_tok =  first_tok
      fmt sig prefix kind      first_tok =  kind + " :: " + first_tok

fn :: fmt format sig line FmtSig => String
      fmt format sig line NoSig  =  ""
      fmt format sig line (SigInfo _ [] _ _ _ _ _) = ""
      fmt format sig line (SigInfo kind (first_tok:rest_toks) arrow_s ret_s sig_cols arrow_col _) =
        lhs_out = fmt pad lhs tokens rest_toks sig_cols 1 (fmt sig prefix kind first_tok)
        pad_arrow = fmt max 1 (arrow_col - (str len lhs_out))
        lhs_out + (fmt spaces pad_arrow) + arrow_s + " " + ret_s

fn :: fmt format clause line FmtSig [String] Bool String => String
      fmt format clause line _ [] _ _ = ""
      fmt format clause line (SigInfo kind _ _ _ sig_cols arrow_col ret_col) (first_tok:rest_toks) has_eq rhs =
        base_pad = fmt spaces (fmt sig base col kind)
        lhs_out = fmt pad lhs tokens rest_toks sig_cols 1 (base_pad + first_tok)
        fmt finish clause rhs lhs_out has_eq rhs arrow_col ret_col

fn :: fmt format clause line fallback [String] => String
      fmt format clause line fallback _ = ""

fn :: fmt finish clause rhs String Bool String Int Int => String
      fmt finish clause rhs lhs_out False _ _ _ = lhs_out
      fmt finish clause rhs lhs_out True "" arrow_col _ =
        pad_eq = fmt max 1 (arrow_col - (str len lhs_out))
        lhs_out + (fmt spaces pad_eq) + "="
      fmt finish clause rhs lhs_out True rhs arrow_col ret_col =
        pad_eq = fmt max 1 (arrow_col - (str len lhs_out))
        with_eq = lhs_out + (fmt spaces pad_eq) + "="
        pad_rhs = fmt max 1 (ret_col - (str len with_eq))
        with_eq + (fmt spaces pad_rhs) + rhs

fn :: fmt format where line FmtSig String String => String
      fmt format where line NoSig lhs rhs = "    " + lhs + " -> " + rhs
      fmt format where line (SigInfo kind _ _ _ _ arrow_col ret_col) lhs rhs =
        lhs_out = (fmt spaces ((fmt sig base col kind) + 4)) + lhs
        pad_arrow = fmt max 1 (arrow_col - (str len lhs_out))
        with_arrow = lhs_out + (fmt spaces pad_arrow) + "->"
        pad_rhs = fmt max 1 (ret_col - (str len with_arrow))
        with_arrow + (fmt spaces pad_rhs) + rhs

-- ── Structural Block & Group Formatting ──────────────────────

fn :: fmt line opens block String    => Bool
      fmt line opens block prev_text =
        clean = fmt trim (fmt strip comment prev_text)
        len = str len clean
        fmt check block opener clean len

fn :: fmt check block opener String Int => Bool
      fmt check block opener clean len
        | len == 0 = False
        | clean == "do" = True
        | (str char at clean (len - 1)) == 61 and (len < 2 or ((str char at clean (len - 2)) != 61 and (str char at clean (len - 2)) != 33 and (str char at clean (len - 2)) != 60 and (str char at clean (len - 2)) != 62)) = True
        | len >= 3 and (str slice clean (len - 3) len) == " do" = True
        | otherwise = False

fn :: fmt line closes block String    => Bool
      fmt line closes block prev_text =
        clean = fmt trim (fmt strip comment prev_text)
        len = str len clean
        (len >= 2 and (str slice clean (len - 2) len) == "|.") or (len >= 3 and (str slice clean (len - 3) len) == "||.")

fn :: fmt guard indent Int Int Int String => Int
      fmt guard indent base_g orig_indent prev_indent prev_text =
        prev_clean = fmt trim (fmt strip comment prev_text)
        fmt guard indent clean base_g orig_indent prev_indent prev_text prev_clean

fn :: fmt guard indent clean Int Int Int String String => Int
      fmt guard indent clean base_g orig_indent prev_indent prev_text prev_clean
        | str starts with prev_clean "||" = base_g
        | fmt line opens block prev_text = fmt max base_g (prev_indent + 2)
        | fmt line closes block prev_text and orig_indent >= base_g and orig_indent < prev_indent = orig_indent
        | fmt line closes block prev_text = fmt max base_g (prev_indent - 2)
        | str starts with prev_clean "|" = fmt max base_g prev_indent
        | otherwise = base_g

fn :: fmt format group body FmtSig [String] Int String Bool => [String]
      fmt format group body _ [] _ _ _ = []
      fmt format group body geom (line:rest) prev_indent prev_text in_where =
        tr = fmt trim line
        tr_clean = fmt trim (fmt strip comment line)
        orig_indent = fmt leading indent line
        next_is_guard = fmt next nonblank is guard rest
        cl = fmt parse clause line geom line next_is_guard
        wb = fmt parse where line line in_where
        fmt format group line geom line tr tr_clean orig_indent rest prev_indent prev_text in_where cl wb

fn :: fmt format group line FmtSig String String String Int [String] Int String Bool FmtClause FmtWhereBind => [String]
      fmt format group line geom _ "" _ _ rest prev_indent prev_text in_where _ _ =
        [""] :: (fmt format group body geom rest prev_indent prev_text in_where)
      fmt format group line geom _ tr _ 0 rest prev_indent prev_text in_where _ _
        | str starts with tr "--" = [tr] :: (fmt format group body geom rest prev_indent prev_text in_where)
      fmt format group line geom _ _ _ _ rest _ _ _ (ClauseInfo c_lhs has_eq rhs) _ =
        f_line = fmt format clause line geom c_lhs has_eq rhs
        [f_line] :: (fmt format group body geom rest (fmt sig base col from geom) f_line False)
      fmt format group line geom _ _ _ _ rest _ _ in_where NoClause (WhereBindInfo w_lhs w_rhs) =
        f_line = fmt format where line geom w_lhs w_rhs
        [f_line] :: (fmt format group body geom rest ((fmt sig base col from geom) + 4) f_line in_where)
      fmt format group line geom _ tr tr_clean orig_indent rest prev_indent prev_text in_where NoClause NoWhereBind
        | str starts with tr_clean "||" = [(fmt spaces ((fmt sig base col from geom) + 2)) + tr] :: (fmt format group body geom rest ((fmt sig base col from geom) + 2) tr False)
        | str starts with tr_clean "|" =
          g_ind = fmt guard indent ((fmt sig base col from geom) + 2) orig_indent prev_indent prev_text
          [(fmt spaces g_ind) + tr] :: (fmt format group body geom rest g_ind tr False)
        | str starts with tr "--" = [fmt indent body line prev_indent prev_text tr] :: (fmt format group body geom rest prev_indent prev_text in_where)
        | otherwise = [fmt indent body line prev_indent prev_text tr] :: (fmt format group body geom rest (fmt next body indent prev_indent prev_text) tr in_where)

fn :: fmt next body indent Int String => Int
      fmt next body indent prev_indent prev_text =
        prev_clean = fmt trim (fmt strip comment prev_text)
        fmt next body indent clean prev_indent prev_text prev_clean

fn :: fmt next body indent clean Int String String => Int
      fmt next body indent clean prev_indent prev_text prev_clean
        | fmt line opens block prev_text = prev_indent + 2
        | fmt line closes block prev_text = fmt max 8 (prev_indent - 2)
        | (str starts with prev_clean "|") and (not (str starts with prev_clean "||")) = fmt max 8 (prev_indent - 2)
        | otherwise = prev_indent

fn :: fmt indent body line Int String String => String
      fmt indent body line prev_indent prev_text tr =
        ind = fmt next body indent prev_indent prev_text
        (fmt spaces ind) + tr

-- ── Top-Level File Partitioning into Groups ──────────────────

fn :: fmt take group lines [String] [String] => [String] [String]
      fmt take group lines [] acc = (acc, [])
      fmt take group lines (l:ls) acc
        | fmt is top decl line l = (acc, [l] :: ls)
        | otherwise = fmt take group lines ls (acc :: [l])

fn :: fmt format top lines [String] Int String => [String]
      fmt format top lines [] _ _ = []
      fmt format top lines (line:rest) prev_indent prev_text =
        sig = fmt parse sig line line
        fmt dispatch top line line rest prev_indent prev_text sig

fn :: fmt dispatch top line String [String] Int String FmtSig => [String]
      fmt dispatch top line _ rest _ _ (SigInfo kind lhs_strs arrow_s ret_s cols a_col r_col) =
        grp_split = fmt take group lines rest []
        fmt run sig group (SigInfo kind lhs_strs arrow_s ret_s cols a_col r_col) grp_split
      fmt dispatch top line line rest prev_indent prev_text NoSig =
        tr = fmt trim line
        fmt format non sig top tr rest prev_indent prev_text

fn :: fmt run sig group FmtSig ([String], [String]) => [String]
      fmt run sig group raw_sig (grp_lines, rem_lines) =
        geom = fmt compute group geometry raw_sig grp_lines
        sig_line = fmt format sig line geom
        body_lines = fmt format group body geom grp_lines (fmt sig base col from geom) "" False
        [sig_line] :: body_lines :: (fmt format top lines rem_lines 0 "")

fn :: fmt format non sig top String [String] Int String => [String]
      fmt format non sig top "" rest prev_indent prev_text =
        [""] :: (fmt format top lines rest prev_indent prev_text)
      fmt format non sig top tr rest _ _
        | fmt is top decl line tr = [tr] :: (fmt format top lines rest 0 tr)
      fmt format non sig top tr rest prev_indent prev_text
        | str starts with tr "--" = [tr] :: (fmt format top lines rest prev_indent prev_text)
        | otherwise = [fmt indent body line prev_indent prev_text tr] :: (fmt format top lines rest (fmt next body indent prev_indent prev_text) tr)

-- ── Public Entry Point (`format ridgun source`) ──────────────

op :: format ridgun source String => String
      format ridgun source src    =
        raw_lines = fmt split raw lines src
        formatted_lines = fmt format top lines raw_lines 0 ""
        fmt join lines formatted_lines
