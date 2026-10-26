-- ============================================================
-- src/main/ridgun/lexer.rg
-- Self-Hosted Ridgun Lexer (Full v0.9.0 Spec Scanner)
-- Supports: Keywords, Identifiers, Int, Hex (0x...), Byte Units
-- (_KB/_MB/_GB/_ms/_s/_min), Real (f64), Interpolated Strings, Raw Strings,
-- Attributes (@), Ellipsis (...), and Operators.
-- @implements FR-COMP-007
-- @implements FR-COMP-010
-- @implements FR-COMP-012
-- @implements FR-COMP-013
-- ============================================================
import ast

fn :: is space Int => Bool
      is space c   =  c == 32 OR c == 9 OR c == 13

fn :: is digit Int => Bool
      is digit c   =  c >= 48 AND c <= 57

fn :: is hex digit Int => Bool
      is hex digit c   =  (c >= 48 AND c <= 57) OR (c >= 65 AND c <= 70) OR (c >= 97 AND c <= 102)

fn :: is alpha Int => Bool
      is alpha c   =  (c >= 65 AND c <= 90) OR (c >= 97 AND c <= 122) OR c == 95

fn :: is alnum Int => Bool
      is alnum c   =  (is_alpha c) OR (is_digit c)

fn :: skip to eol String Int Int => Int
      skip to eol src pos len
        | pos >= len = pos
        | (str_char_at src pos) == 10 = pos
        | otherwise = skip_to_eol src (pos + 1) len

fn :: skip ws String Int Int => Int
      skip ws src    pos len
        | pos >= len = pos
        | is_space (str_char_at src pos) = skip_ws src (pos + 1) len
        | (str_char_at src pos) == 45 AND (str_char_at src (pos + 1)) == 45 = skip_ws src (skip_to_eol src (pos + 2) len) len
        | otherwise = pos

fn :: scan string end String Int Int Int => Int
      scan string end src pos len quote_ch
        | pos >= len = pos
        | (str_char_at src pos) == 92 = scan_string_end src (pos + 2) len quote_ch
        | (str_char_at src pos) == quote_ch = pos
        | otherwise = scan_string_end src (pos + 1) len quote_ch

fn :: scan raw string end String Int Int => Int
      scan raw string end src pos len
        | pos >= len = pos
        | (str_char_at src pos) == 39 = pos
        | otherwise = scan_raw_string_end src (pos + 1) len

fn :: scan ident end String Int Int => Int
      scan ident end src pos len
        | pos >= len = pos
        | is_alnum (str_char_at src pos) = scan_ident_end src (pos + 1) len
        | (str_char_at src pos) == 46 AND (pos + 1) < len AND (is_alpha (str_char_at src (pos + 1))) = scan_ident_end src (pos + 1) len
        | otherwise = pos

fn :: scan hex end String Int Int => Int
      scan hex end src pos len
        | pos >= len = pos
        | is_hex_digit (str_char_at src pos) = scan_hex_end src (pos + 1) len
        | (str_char_at src pos) == 95 AND is_hex_digit (str_char_at src (pos + 1)) = scan_hex_end src (pos + 1) len
        | otherwise = pos

fn :: scan dec end String Int Int => Int
      scan dec end src pos len
        | pos >= len = pos
        | is_digit (str_char_at src pos) = scan_dec_end src (pos + 1) len
        | (str_char_at src pos) == 95 AND is_digit (str_char_at src (pos + 1)) = scan_dec_end src (pos + 1) len
        | otherwise = pos

fn :: classify word String => RToken
      classify word w
        | w == "fn" = TokFn
        | w == "op" = TokOp
        | w == "type" = TokType
        | w == "import" = TokImport
        | w == "with" = TokWith
        | w == "do" = TokDo
        | w == "hardware" = TokHardware
        | w == "otherwise" = TokOtherwise
        | w == "mut" = TokMut
        | w == "True" = TokTrue
        | w == "False" = TokFalse
        | w == "and" OR w == "AND" = TokAnd
        | w == "or" OR w == "OR" = TokOr
        | w == "xor" OR w == "XOR" = TokXor
        | w == "not" OR w == "NOT" = TokNot
        | otherwise = TokIdent w

fn :: unescape char Int => String
      unescape char c
        | c == 110 = char_from_code 10
        | c == 116 = char_from_code 9
        | c == 114 = char_from_code 13
        | c == 92 = char_from_code 92
        | c == 34 = char_from_code 34
        | c == 123 = (char_from_code 123) + (char_from_code 123)
        | c == 125 = (char_from_code 125) + (char_from_code 125)
        | otherwise = char_from_code c

fn :: unescape loop String Int Int String => String
      unescape loop s pos len acc
        | pos >= len = acc
        | (str_char_at s pos) == 92 AND (pos + 1) < len = unescape_loop s (pos + 2) len (acc + (unescape_char (str_char_at s (pos + 1))))
        | otherwise = unescape_loop s (pos + 1) len (acc + (str_slice s pos (pos + 1)))

fn :: unescape str String => String
      unescape str s
        | str_contains s (char_from_code 92) = unescape_loop s 0 (str_len s) ""
        | otherwise = s

fn :: tok dquote String Int Int => RToken Int
      tok dquote src    pos len =
        end_q = scan_string_end src (pos + 1) len 34
        raw_lit = str_slice src (pos + 1) end_q
        lit = unescape_str raw_lit
        (TokStr lit, end_q + 1)

fn :: tok squote String Int Int => RToken Int
      tok squote src    pos len =
        end_q = scan_raw_string_end src (pos + 1) len
        lit = str_slice src (pos + 1) end_q
        (TokRawStr lit, end_q + 1)

fn :: check byte unit suffix String Int Int Int => RToken Int
      check byte unit suffix src end_n len val
        | (end_n + 3) <= len AND (str_slice src end_n (end_n + 3)) == "_KB" = (TokInt (val * 1024), end_n + 3)
        | (end_n + 3) <= len AND (str_slice src end_n (end_n + 3)) == "_MB" = (TokInt (val * 1048576), end_n + 3)
        | (end_n + 3) <= len AND (str_slice src end_n (end_n + 3)) == "_GB" = (TokInt (val * 1073741824), end_n + 3)
        | (end_n + 4) <= len AND (str_slice src end_n (end_n + 4)) == "_min" = (TokInt (val * 60000), end_n + 4)
        | (end_n + 3) <= len AND (str_slice src end_n (end_n + 3)) == "_ms" = (TokInt val, end_n + 3)
        | (end_n + 2) <= len AND (str_slice src end_n (end_n + 2)) == "_s" AND ((end_n + 2) == len OR NOT (is_alnum (str_char_at src (end_n + 2)))) = (TokInt (val * 1000), end_n + 2)
        | otherwise = (TokInt val, end_n)

fn :: tok dec or real String Int Int Int => RToken Int
      tok dec or real src pos end_n len
        | end_n < len AND (str_char_at src end_n) == 46 AND is_digit (str_char_at src (end_n + 1)) = tok_real_frac src pos (scan_dec_end src (end_n + 1) len)
        | otherwise = check_byte_unit_suffix src end_n len (str_to_int (str_slice src pos end_n))

fn :: tok real frac String Int Int => RToken Int
      tok real frac src pos end_frac =
        (TokReal (str_slice src pos end_frac), end_frac)

fn :: tok number String Int Int => RToken Int
      tok number src    pos len
        | (str_char_at src pos) == 48 AND ((str_char_at src (pos + 1)) == 120 OR (str_char_at src (pos + 1)) == 88) = tok_hex_number src pos (scan_hex_end src (pos + 2) len)
        | otherwise = tok_dec_or_real src pos (scan_dec_end src pos len) len

fn :: tok hex number String Int Int => RToken Int
      tok hex number src pos end_h =
        raw_h = str_slice src pos end_h
        (TokInt (str_to_int raw_h), end_h)

fn :: tok ident String Int Int => RToken Int
      tok ident src    pos len =
        end_id = scan_ident_end src pos len
        word = str_slice src pos end_id
        (classify_word word, end_id)

fn :: tok dpipe ident String Int Int => RToken Int
      tok dpipe ident src pos len =
        end_id = scan_ident_end src (pos + 2) len
        (TokIdent (str_slice src pos end_id), end_id)

fn :: lex one tok String Int Int Int Int => RToken Int
      lex one tok src pos len c c2
        | c == 10 = (TokNewline, pos + 1)
        | c == 45 AND c2 == 62 = (TokArrow, pos + 2)
        | c == 58 AND c2 == 58 = (TokColonColon, pos + 2)
        | c == 61 AND c2 == 62 = (TokFatArrow, pos + 2)
        | c == 61 AND c2 == 61 = (TokEqEq, pos + 2)
        | c == 33 AND c2 == 61 = (TokNeq, pos + 2)
        | c == 62 AND c2 == 61 = (TokGtEq, pos + 2)
        | c == 60 AND c2 == 61 = (TokLtEq, pos + 2)
        | c == 124 AND c2 == 124 AND (str_char_at src (pos + 2)) == 46 = (TokDoublePipeDot, pos + 3)
        | c == 124 AND c2 == 124 AND (is_alpha (str_char_at src (pos + 2))) = tok_dpipe_ident src pos len
        | c == 124 AND c2 == 124 = (TokDoublePipe, pos + 2)
        | c == 124 AND c2 == 46 = (TokPipeDot, pos + 2)
        | c == 46 AND c2 == 46 AND (str_char_at src (pos + 2)) == 46 = (TokEllipsis, pos + 3)
        | c == 58 = (TokColon, pos + 1)
        | c == 61 = (TokEquals, pos + 1)
        | c == 62 = (TokGt, pos + 1)
        | c == 60 = (TokLt, pos + 1)
        | c == 43 = (TokPlus, pos + 1)
        | c == 45 = (TokMinus, pos + 1)
        | c == 42 = (TokStar, pos + 1)
        | c == 47 = (TokSlash, pos + 1)
        | c == 37 = (TokPercent, pos + 1)
        | c == 64 = (TokAt, pos + 1)
        | c == 124 = (TokPipe, pos + 1)
        | c == 40 = (TokLParen, pos + 1)
        | c == 41 = (TokRParen, pos + 1)
        | c == 91 AND pos > 0 AND ((is_alnum (str_char_at src (pos - 1))) OR ((str_char_at src (pos - 1)) == 93)) = (TokIdxLBracket, pos + 1)
        | c == 91 = (TokLBracket, pos + 1)
        | c == 93 = (TokRBracket, pos + 1)
        | c == 94 = (TokIdent "^", pos + 1)
        | c == 44 = (TokComma, pos + 1)
        | c == 34 = tok_dquote src pos len
        | c == 39 = tok_squote src pos len
        | is_digit c = tok_number src pos len
        | is_alpha c = tok_ident src pos len
        | otherwise = (TokNewline, pos + 1)

fn :: tok pair tok (RToken, Int) => RToken
      tok pair tok (tok, _)      =  tok

fn :: tok pair pos (RToken, Int) => Int
      tok pair pos (_, next_p)   =  next_p

fn :: lex next tok String Int Int => RToken
      lex next tok src p len = tok_pair_tok (lex_one_tok src p len (str_char_at src p) (str_char_at src (p + 1)))

fn :: lex next pos String Int Int => Int
      lex next pos src p len = tok_pair_pos (lex_one_tok src p len (str_char_at src p) (str_char_at src (p + 1)))

fn :: lex loop String Int Int [RToken] => [RToken]
      lex loop src pos len acc =
        p = skip_ws src pos len
        lex_loop_at src p len acc

fn :: lex loop at String Int Int [RToken] => [RToken]
      lex loop at src p len acc
        | p >= len = acc :: [TokEof]
        | otherwise = lex_loop_at src (skip_ws src (lex_next_pos src p len) len) len (acc :: [lex_next_tok src p len])

fn :: tokenize src String => [RToken]
      tokenize src src    =  lex_loop src 0 (str_len src) []

fn :: count tokens [RToken] => Int
      count tokens []       =  0
      count tokens (_:xs)   =  1 + (count_tokens xs)
