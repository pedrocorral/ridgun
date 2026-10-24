;;; ridgun-mode.el --- Major mode for the Ridgun programming language -*- lexical-binding: t; -*-

;; Author: Ridgun Contributors
;; Version: 2.0.0
;; Keywords: languages, ridgun, functional, concurrency
;; URL: https://github.com/ridgun-lang/ridgun
;; Package-Requires: ((emacs "26.1"))

;;; Commentary:
;;
;; Major mode for editing Ridgun (`.rg') source files in GNU Emacs.
;;
;; Features:
;; - Full syntax highlighting for Ridgun v2.0:
;;   * Declarations (`fn ::', `op ::', `type ::', `hardware ::')
;;   * Attributes (`@packed', `@repr(C)')
;;   * Keywords (`otherwise', `with', `do', `region', `limit')
;;   * Concurrency & actor primitives (`spawn', `channel', `send', `receive',
;;     `timeout', `||')
;;   * Word-based logical operators (`AND', `OR', `XOR', `NOT')
;;   * Built-in & bare-metal types (`Int', `Real', `Bool', `String', `Char',
;;     `Tensor', `Tensor_GPU', `U8'..`U64', `I8'..`I64', `USize')
;;   * Interpolated strings (`"Hello {name}"') vs raw strings (`'raw'')
;;   * Numbers, hex literals (`0x4002_0014'), and region suffixes (`_KB', `_MB', `_GB')
;; - Indentation-aware smart line indentation (2-space default)
;; - Imenu support for functions, types, operators, and state/hardware blocks
;; - Interactive compilation & execution commands via `C-c C-c', `C-c C-r',
;;   `C-c C-k', and `C-c C-b'
;;
;; Installation:
;;
;;   (add-to-list 'load-path "/path/to/ridgun/editors/emacs")
;;   (require 'ridgun-mode)
;;
;; Or with `use-package':
;;
;;   (use-package ridgun-mode
;;     :load-path "/path/to/ridgun/editors/emacs"
;;     :mode "\\.rg\\'")

;;; Code:

(require 'cl-lib)
(require 'compile)
(require 'subr-x)

(defgroup ridgun nil
  "Major mode for editing Ridgun source code."
  :prefix "ridgun-"
  :group 'languages)

(defcustom ridgun-indent-offset 2
  "Number of spaces per indentation level in `ridgun-mode'."
  :type 'integer
  :safe #'integerp
  :group 'ridgun)

(defcustom ridgun-compiler-command "ridgunc"
  "Command or path to the self-hosted `ridgunc' compiler binary."
  :type 'string
  :group 'ridgun)

(defcustom ridgun-vm-command "cargo run --quiet --"
  "Command used to invoke the Ridgun VM runner."
  :type 'string
  :group 'ridgun)

;; ---------------------------------------------------------------------------
;; Syntax Table & Raw String Propertization
;; ---------------------------------------------------------------------------

(defvar ridgun-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; Operators and punctuation
    (modify-syntax-entry ?: "." table)
    (modify-syntax-entry ?| "." table)
    (modify-syntax-entry ?= "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?* "." table)
    (modify-syntax-entry ?/ "." table)
    (modify-syntax-entry ?% "." table)
    (modify-syntax-entry ?@ "." table)
    ;; Underscore is part of identifiers/numbers (e.g., 16_KB, A_ij, my_func)
    (modify-syntax-entry ?_ "w" table)
    ;; Double-quoted interpolated strings and single-quoted raw strings
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\' "\"" table)
    (modify-syntax-entry ?\\ "\\" table)
    ;; Paired delimiters
    (modify-syntax-entry ?\( "()" table)
    (modify-syntax-entry ?\) ")(" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    (modify-syntax-entry ?\{ "(}" table)
    (modify-syntax-entry ?\} "){" table)
    ;; Line comments: `-- ...`
    (modify-syntax-entry ?- ". 12" table)
    (modify-syntax-entry ?\n ">" table)
    table)
  "Syntax table for `ridgun-mode'.")

;; ---------------------------------------------------------------------------
;; Font-Lock (Syntax Highlighting)
;; ---------------------------------------------------------------------------

(defconst ridgun-keywords
  '("fn" "op" "type" "import" "where" "otherwise"
    "global" "context" "shared" "with" "do" "atomic"
    "hardware" "region" "limit")
  "Core language keywords in Ridgun.")

(defconst ridgun-logical-operators
  '("AND" "OR" "XOR" "NOT")
  "Word-based logical operators in Ridgun.")

(defconst ridgun-constants
  '("True" "False")
  "Boolean constants in Ridgun.")

(defconst ridgun-builtins
  '("echo" "out" "spawn" "join" "channel" "send" "to" "receive" "from" "timeout"
    "new_channel" "new_bounded_channel" "send_through" "receive_from" "try_receive_from"
    "chan_send" "chan_recv" "chan_try_recv" "receive_from_timeout"
    "length" "abs" "read_file" "load_rg_source" "read_bytes" "write_bytes"
    "write_file" "shell_exec" "cli_args"
    "map" "seq_map" "filter" "seq_filter" "fold"
    "list_dir" "file_lstat" "sha256_file" "sha256_str" "sys_mkdir" "sys_chmod"
    "sys_exec" "sys_chdir" "sys_getcwd" "sys_getenv" "sys_setenv" "sys_exit"
    "sys_getuid" "sys_getgid" "sys_username" "sys_user_groups" "sys_lookup_uid_gid"
    "sys_setresgid" "sys_setgroups" "sys_setresuid" "sys_execve" "sys_read_pass"
    "str_len" "str_char_at" "str_slice" "str_concat" "int_to_str" "str_to_int"
    "str_starts_with" "str_contains" "char_from_code" "trim_str" "list_str_len")
  "Built-in functions and concurrency/system primitives in Ridgun.")

(defconst ridgun-builtin-types
  '("Int" "Real" "Bool" "String" "Char"
    "Tensor" "Tensor_GPU" "Channel"
    "U8" "U16" "U32" "U64"
    "I8" "I16" "I32" "I64" "USize")
  "Primitive and bare-metal types in Ridgun.")

(defvar ridgun-font-lock-keywords
  `(
    ;; 1. Hardware & memory layout attributes: @packed, @repr(C)
    ("@\\(?:packed\\|repr([^)\n]+)\\)" . font-lock-preprocessor-face)

    ;; 2. Function, operator, type, and hardware declarations:
    ;;    fn :: name, type Name =, hardware :: name
    ("\\_<\\(fn\\|hardware\\)[ \t]*\\(::\\)[ \t]*\\([a-z_][A-Za-z0-9_]*\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-builtin-face)
     (3 font-lock-function-name-face))

    ("\\_<\\(type\\)[ \t]+\\(?:\\(::\\)[ \t]*\\)?\\([A-Z][A-Za-z0-9_]*\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-builtin-face nil t)
     (3 font-lock-type-face))

    ("\\_<\\(op\\)[ \t]*\\(::\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-builtin-face))

    ;; 2b. Prefixless top-level signature line: `func_name ... => Ret`
    ("^\\([a-z_][A-Za-z0-9_]*\\)\\_>[^\n=]*=>"
     (1 font-lock-function-name-face))

    ;; 3. Function definition clause: `func_name arg1 arg2 =`
    ("^[ \t]*\\([a-z_][A-Za-z0-9_]*\\)\\_>[^\n=|]*[=|]"
     (1 font-lock-function-name-face))

    ;; 4. String interpolation `{expr}` (ignoring escaped `{{`)
    ("[^\\{]\\({[^{}\n\"']+}\\)"
     (1 font-lock-variable-name-face prepend))

    ;; 5. Core keywords & logical operators
    (,(regexp-opt ridgun-keywords 'symbols) . font-lock-keyword-face)
    (,(regexp-opt ridgun-logical-operators 'symbols) . font-lock-keyword-face)

    ;; 6. Boolean constants
    (,(regexp-opt ridgun-constants 'symbols) . font-lock-constant-face)

    ;; 7. Built-in functions & concurrency/IO primitives
    (,(regexp-opt ridgun-builtins 'symbols) . font-lock-builtin-face)

    ;; 8. Built-in types & ADT constructors / User types / Polymorphic type vars (Uppercase identifiers)
    (,(regexp-opt ridgun-builtin-types 'symbols) . font-lock-type-face)
    ("\\_<[A-Z][A-Za-z0-9_]*\\_>" . font-lock-type-face)

    ;; 9. Numeric literals: hex (0x4002_0014), memory units (16_KB, 64_MB, 1_GB), floats, ints
    ("\\_<0x[0-9A-Fa-f_]+\\_>" . font-lock-constant-face)
    ("\\_<[0-9][0-9_]*\\(?:_[KMG]B\\)\\_>" . font-lock-constant-face)
    ("\\_<[0-9]+\\(?:\\.[0-9]+\\)?\\_>" . font-lock-constant-face)

    ;; 10. Multi-character operators: ::, =>, ->, ||, ==, !=, <=, >=, @
    ("\\(::\\|=>\\|->\\|||\\|==\\|!=\\|<=\\|>=\\|@\\)" . font-lock-builtin-face))
  "Font-lock highlighting rules for `ridgun-mode'.")

;; ---------------------------------------------------------------------------
;; Signature-Aware Auto-Indentation & Column Alignment Engine
;; ---------------------------------------------------------------------------

(defun ridgun--scan-tokens-with-cols (line)
  "Scan LINE into a list of (TOKEN-STR . START-COL) in O(N) time."
  (let ((len (length line))
        (i 0)
        (tokens nil))
    (while (< i len)
      ;; Skip horizontal whitespace
      (while (and (< i len) (memq (aref line i) '(?\s ?\t)))
        (setq i (1+ i)))
      (when (< i len)
        (let ((start i)
              (ch (aref line i)))
          (cond
           ;; Double-quoted or single-quoted string
           ((memq ch '(?\" ?\'))
            (let ((quote-ch ch))
              (setq i (1+ i))
              (while (and (< i len) (not (eq (aref line i) quote-ch)))
                (when (eq (aref line i) ?\\)
                  (setq i (1+ i)))
                (setq i (1+ i)))
              (when (< i len)
                (setq i (1+ i)))))
           ;; Parenthesized or bracketed group (e.g. `(x:xs)`, `(Int, Int)`, `[Int]`)
           ((memq ch '(?\( ?\[))
            (let ((depth 0))
              (while (and (< i len)
                          (or (> depth 0) (memq (aref line i) '(?\( ?\[))))
                (let ((c (aref line i)))
                  (cond
                   ((memq c '(?\( ?\[)) (setq depth (1+ depth)))
                   ((memq c '(?\) ?\])) (setq depth (1- depth)))))
                (setq i (1+ i)))))
           ;; Regular token (identifier, number, operator, or type with parens like `Tensor(b, i)`)
           (t
            (let ((paren-depth 0))
              (while (and (< i len)
                          (or (> paren-depth 0)
                              (not (memq (aref line i) '(?\s ?\t)))))
                (let ((c (aref line i)))
                  (cond
                   ((memq c '(?\( ?\[)) (setq paren-depth (1+ paren-depth)))
                   ((memq c '(?\) ?\])) (setq paren-depth (max 0 (1- paren-depth))))))
                (setq i (1+ i))))))
          (push (cons (substring line start i) start) tokens))))
    (nreverse tokens)))

(defun ridgun--sig-type-token-p (tok-str)
  "Return non-nil if TOK-STR in a signature is a type placeholder."
  (and (> (length tok-str) 0)
       (let ((ch (aref tok-str 0)))
         (or (and (>= ch ?A) (<= ch ?Z))
             (memq ch '(?\[ ?\())))))

(defun ridgun--bare-fn-lhs-p (lhs-strs)
  "Return non-nil if LHS-STRS is a prefixless function signature (`name T1 T2')."
  (and lhs-strs
       (not (ridgun--sig-type-token-p (car lhs-strs)))
       (cl-every #'ridgun--sig-type-token-p (cdr lhs-strs))))

(defun ridgun--parse-fn-sig-line (line)
  "If LINE is a `fn ::', `op ::', or prefixless signature, return its plist."
  (let* ((clean (replace-regexp-in-string "[ \t]*--.*$" "" line))
         (toks (ridgun--scan-tokens-with-cols clean)))
    (cond
     ;; 1. Explicit `fn :: ...' or `op :: ...'
     ((and (>= (length toks) 4)
           (member (car (nth 0 toks)) '("fn" "op"))
           (equal (car (nth 1 toks)) "::"))
      (let ((kind (car (nth 0 toks)))
            (name (car (nth 2 toks)))
            (lhs-toks nil)
            (arrow-tok nil)
            (rest (nthcdr 2 toks)))
        (while (and rest (not arrow-tok))
          (let ((tok (car rest)))
            (if (member (car tok) '("=>" "->"))
                (setq arrow-tok tok)
              (push tok lhs-toks)))
          (setq rest (cdr rest)))
        (setq lhs-toks (nreverse lhs-toks))
        (when (and arrow-tok lhs-toks)
          (let* ((arrow-end (+ (cdr arrow-tok) (length (car arrow-tok))))
                 (ret-str (string-trim (substring clean arrow-end))))
            (list :kind kind
                  :name name
                  :name-col 6
                  :lhs-strs (mapcar #'car lhs-toks)
                  :arrow-str (car arrow-tok)
                  :ret-str ret-str)))))
     ;; 2. Prefixless top-level signature at column 0 (`name T1 => Ret` or `a op b => Ret`)
     ((and (>= (length toks) 2)
           (zerop (cdr (nth 0 toks)))
           (not (member (car (nth 0 toks))
                        '("fn" "op" "type" "import" "global" "context" "shared" "hardware")))
           (not (string-prefix-p "@" (car (nth 0 toks))))
           (not (string-prefix-p "|" (car (nth 0 toks)))))
      (let ((lhs-toks nil)
            (arrow-tok nil)
            (rest toks))
        (while (and rest (not arrow-tok))
          (let ((tok (car rest)))
            (if (equal (car tok) "=>")
                (setq arrow-tok tok)
              (push tok lhs-toks)))
          (setq rest (cdr rest)))
        (setq lhs-toks (nreverse lhs-toks))
        (when (and arrow-tok lhs-toks)
          (let* ((lhs-strs (mapcar #'car lhs-toks))
                 (kind (if (ridgun--bare-fn-lhs-p lhs-strs) "bare_fn" "bare_op"))
                 (arrow-end (+ (cdr arrow-tok) (length (car arrow-tok))))
                 (ret-str (string-trim (substring clean arrow-end))))
            (list :kind kind
                  :name (car lhs-strs)
                  :name-col 0
                  :lhs-strs lhs-strs
                  :arrow-str (car arrow-tok)
                  :ret-str ret-str))))))))

(defun ridgun--top-decl-line-p (line)
  "Return non-nil if LINE starts a new top-level declaration."
  (or (string-match-p
       "^[ \t]*\\(?:fn\\|op\\|type\\|import\\|global\\|context\\|shared\\|hardware\\|@\\)\\_>"
       line)
      (not (null (ridgun--parse-fn-sig-line line)))))

(defun ridgun--find-enclosing-sig-bol ()
  "Return the line-beginning-position of the enclosing signature line."
  (save-excursion
    (beginning-of-line)
    (let ((cur-line (buffer-substring-no-properties
                     (line-beginning-position)
                     (line-end-position))))
      (if (ridgun--parse-fn-sig-line cur-line)
          (point)
        (let ((sig-bol nil)
              (stop nil))
          (while (and (not sig-bol) (not stop) (not (bobp)))
            (forward-line -1)
            (let ((l (buffer-substring-no-properties
                      (line-beginning-position)
                      (line-end-position))))
              (cond
               ((ridgun--parse-fn-sig-line l)
                (setq sig-bol (point)))
               ((string-match-p
                 "^[ \t]*\\(?:type\\|import\\|global\\|context\\|shared\\|hardware\\)\\_>"
                 l)
                (setq stop t)))))
          sig-bol)))))

(defun ridgun--next-nonblank-starts-with-guard-p ()
  "Return non-nil if the next non-blank line starts with a guard `|'."
  (save-excursion
    (end-of-line)
    (let ((found nil)
          (is-guard nil))
      (while (and (not found) (not (eobp)))
        (forward-line 1)
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position)
                     (line-end-position))))
          (unless (string-match-p "^[ \t]*\\(?:--.*\\)?$" line)
            (setq found t)
            (setq is-guard (string-match-p "^[ \t]*|[^|]" line)))))
      is-guard)))

(defun ridgun--clause-matches-sig-p (sig clause-lhs)
  "Return non-nil if CLAUSE-LHS token strings belong to a clause of SIG."
  (and clause-lhs
       (let ((kind (plist-get sig :kind))
             (sig-lhs (plist-get sig :lhs-strs)))
         (if (member kind '("fn" "bare_fn"))
             (and (= (length clause-lhs) (length sig-lhs))
                  (equal (car clause-lhs) (car sig-lhs)))
           ;; For `op ::' or `bare_op', length matches and all operator/keyword tokens match
           (and (= (length clause-lhs) (length sig-lhs))
                (let ((ok t)
                      (s-rest sig-lhs)
                      (c-rest clause-lhs))
                  (while (and ok s-rest)
                    (let ((s-tok (car s-rest))
                          (c-tok (car c-rest)))
                      (when (and (not (ridgun--sig-type-token-p s-tok))
                                 (not (equal s-tok c-tok)))
                        (setq ok nil)))
                    (setq s-rest (cdr s-rest))
                    (setq c-rest (cdr c-rest)))
                  ok))))))

(defun ridgun--parse-clause-line (sig line)
  "If LINE is a clause of SIG, return (:lhs-strs LIST :has-eq BOOL :rhs STR)."
  (let* ((clean (replace-regexp-in-string "[ \t]*--.*$" "" line))
         (trimmed (string-trim clean)))
    (when (and (not (string-empty-p trimmed))
               (not (string-prefix-p "|" trimmed))
               (not (string-prefix-p "--" trimmed))
               (not (ridgun--top-decl-line-p line)))
      (let ((toks (ridgun--scan-tokens-with-cols clean)))
        (when toks
          (let ((clause-lhs nil)
                (eq-tok nil)
                (rest toks))
            (while (and rest (not eq-tok))
              (if (equal (car (car rest)) "=")
                  (setq eq-tok (car rest))
                (push (car (car rest)) clause-lhs))
              (setq rest (cdr rest)))
            (setq clause-lhs (nreverse clause-lhs))
            (when (and (ridgun--clause-matches-sig-p sig clause-lhs)
                       (or eq-tok (ridgun--next-nonblank-starts-with-guard-p)))
              (let ((rhs (if eq-tok
                             (string-trim (substring line (+ (cdr eq-tok) 1)))
                           "")))
                (list :lhs-strs clause-lhs
                      :has-eq (not (null eq-tok))
                      :rhs rhs)))))))))

(defun ridgun--parse-where-binding-line (line)
  "If LINE is a `where' binding `<lhs> -> <rhs>', return (:lhs STR :rhs STR)."
  (let* ((clean (replace-regexp-in-string "[ \t]*--.*$" "" line))
         (trimmed (string-trim clean)))
    (when (and (not (string-empty-p trimmed))
               (not (ridgun--top-decl-line-p line))
               (not (string-match-p "^where\\_>" trimmed))
               (not (string-match-p "^|" trimmed)))
      (let ((toks (ridgun--scan-tokens-with-cols clean))
            (arrow-tok nil))
        (dolist (tok toks)
          (when (and (not arrow-tok) (equal (car tok) "->"))
            (setq arrow-tok tok)))
        (when arrow-tok
          (let ((lhs (string-trim (substring clean 0 (cdr arrow-tok))))
                (rhs (string-trim (substring line (+ (cdr arrow-tok) 2)))))
            (when (and (not (string-empty-p lhs))
                       (not (string-empty-p rhs)))
              (list :lhs lhs :rhs rhs))))))))

(defun ridgun--compute-group-geometry (sig-bol)
  "Compute unified column geometry for the signature at SIG-BOL and its clauses."
  (save-excursion
    (goto-char sig-bol)
    (let* ((sig-line (buffer-substring-no-properties
                      (line-beginning-position)
                      (line-end-position)))
           (sig (ridgun--parse-fn-sig-line sig-line)))
      (when sig
        (let* ((lhs-strs (plist-get sig :lhs-strs))
               (base-col (or (plist-get sig :name-col) 6))
               (ncols (length lhs-strs))
               (widths (vconcat (mapcar #'length lhs-strs)))
               (where-indent (+ base-col (* 2 ridgun-indent-offset)))
               (max-where-end 0)
               (stop nil))
          ;; Scan all clauses and `where' bindings belonging to this signature
          (while (and (not stop) (zerop (forward-line 1)) (not (eobp)))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position)
                         (line-end-position))))
              (if (ridgun--top-decl-line-p line)
                  (setq stop t)
                (let ((clause (ridgun--parse-clause-line sig line))
                      (wb (ridgun--parse-where-binding-line line)))
                  (cond
                   (clause
                    (let ((c-lhs (plist-get clause :lhs-strs))
                          (idx 0))
                      (dolist (tok-str c-lhs)
                        (when (and (< idx ncols) (<= (length tok-str) 18))
                          (aset widths idx (max (aref widths idx) (length tok-str))))
                        (setq idx (1+ idx)))))
                   (wb
                    (setq max-where-end
                          (max max-where-end
                               (+ where-indent
                                  (length (plist-get wb :lhs))
                                  1)))))))))
          ;; Build column start positions from widths
          (let ((col-starts nil)
                (cur-col base-col)
                (idx 0))
            (while (< idx ncols)
              (push cur-col col-starts)
              (setq cur-col (+ cur-col (aref widths idx) 1))
              (setq idx (1+ idx)))
            (setq col-starts (nreverse col-starts))
            (let* ((arrow-str (plist-get sig :arrow-str))
                   (ret-str (plist-get sig :ret-str))
                   (arrow-col (max cur-col max-where-end))
                   (ret-col (+ arrow-col (length arrow-str) 1))
                   (total-sig-len (+ ret-col (length ret-str)))
                   (num-params (if (member (plist-get sig :kind) '("fn" "bare_fn"))
                                   (1- ncols)
                                 (cl-count-if #'ridgun--sig-type-token-p lhs-strs))))
              (if (or (> num-params 4) (> total-sig-len 80))
                  (progn
                    (plist-put sig :sig-cols nil)
                    (plist-put sig :arrow-col 0)
                    (plist-put sig :ret-col 0))
                (plist-put sig :sig-cols col-starts)
                (plist-put sig :arrow-col arrow-col)
                (plist-put sig :ret-col ret-col))
              sig)))))))

(defun ridgun--format-sig-line (sig)
  "Format the signature line using SIG's group geometry."
  (let* ((kind (plist-get sig :kind))
         (lhs-strs (plist-get sig :lhs-strs))
         (sig-cols (plist-get sig :sig-cols))
         (arrow-str (plist-get sig :arrow-str))
         (arrow-col (plist-get sig :arrow-col))
         (ret-str (plist-get sig :ret-str))
         (prefix (if (member kind '("bare_fn" "bare_op"))
                     (car lhs-strs)
                   (concat kind " :: " (car lhs-strs))))
         (out prefix)
         (idx 1))
    (dolist (tok-str (cdr lhs-strs))
      (let* ((target-col (nth idx sig-cols))
             (spaces (if target-col (max 1 (- target-col (length out))) 1)))
        (setq out (concat out (make-string spaces ?\s) tok-str))
        (setq idx (1+ idx))))
    (let ((spaces-before-arrow (if arrow-col (max 1 (- arrow-col (length out))) 1)))
      (setq out (concat out (make-string spaces-before-arrow ?\s) arrow-str " " ret-str)))
    out))

(defun ridgun--format-fn-clause-line (sig line)
  "Format clause LINE aligned to SIG's group columns."
  (let ((clause (ridgun--parse-clause-line sig line)))
    (when clause
      (let* ((clause-lhs (plist-get clause :lhs-strs))
             (has-eq (plist-get clause :has-eq))
             (rhs (plist-get clause :rhs))
             (sig-cols (plist-get sig :sig-cols))
             (arrow-col (plist-get sig :arrow-col))
             (ret-col (plist-get sig :ret-col))
             (base-col (or (plist-get sig :name-col) 6))
             (first-col (or (car sig-cols) base-col))
             (out (concat (make-string first-col ?\s) (car clause-lhs)))
             (idx 1))
        (dolist (tok-str (cdr clause-lhs))
          (let* ((target-col (nth idx sig-cols))
                 (spaces (if target-col (max 1 (- target-col (length out))) 1)))
            (setq out (concat out (make-string spaces ?\s) tok-str))
            (setq idx (1+ idx))))
        (when has-eq
          (let ((spaces-before-eq (if arrow-col (max 1 (- arrow-col (length out))) 1)))
            (setq out (concat out (make-string spaces-before-eq ?\s) "="))
            (unless (string-empty-p rhs)
              (let ((spaces-after-eq (if ret-col (max 1 (- ret-col (length out))) 1)))
                (setq out (concat out (make-string spaces-after-eq ?\s) rhs))))))
        out))))

(defun ridgun--format-where-binding-line (sig line)
  "Format a `where' binding `<lhs> -> <rhs>' LINE aligned to SIG's arrow column."
  (let ((wb (ridgun--parse-where-binding-line line)))
    (when wb
      (let* ((lhs (plist-get wb :lhs))
             (rhs (plist-get wb :rhs))
             (where-indent (+ (or (plist-get sig :name-col) 6)
                              (* 2 ridgun-indent-offset)))
             (arrow-col (plist-get sig :arrow-col))
             (ret-col (plist-get sig :ret-col))
             (out (concat (make-string where-indent ?\s) lhs))
             (spaces-before-arrow (if arrow-col (max 1 (- arrow-col (length out))) 1))
             (_ (setq out (concat out (make-string spaces-before-arrow ?\s) "->")))
             (spaces-after-arrow (if ret-col (max 1 (- ret-col (length out))) 1)))
        (concat out (make-string spaces-after-arrow ?\s) rhs)))))

(defun ridgun--align-sig-line-at (sig-bol sig)
  "Update signature at SIG-BOL and its clauses/`where' bindings to match SIG."
  (save-excursion
    (goto-char sig-bol)
    (let ((cur-sig-line (buffer-substring-no-properties
                         (line-beginning-position)
                         (line-end-position)))
          (formatted-sig (ridgun--format-sig-line sig))
          (stop nil))
      (unless (equal cur-sig-line formatted-sig)
        (delete-region (line-beginning-position) (line-end-position))
        (insert formatted-sig))
      (while (and (not stop) (zerop (forward-line 1)) (not (eobp)))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position)
                     (line-end-position))))
          (if (ridgun--top-decl-line-p line)
              (setq stop t)
            (let ((formatted-line (or (ridgun--format-fn-clause-line sig line)
                                      (ridgun--format-where-binding-line sig line))))
              (when (and formatted-line (not (equal line formatted-line)))
                (delete-region (line-beginning-position) (line-end-position))
                (insert formatted-line)))))))))

(defun ridgun--previous-nonblank-line-indent ()
  "Return (INDENT . LINE-TEXT) of the previous non-blank, non-comment line."
  (save-excursion
    (beginning-of-line)
    (let ((found nil)
          (res (cons 0 "")))
      (while (and (not found) (not (bobp)))
        (forward-line -1)
        (unless (looking-at-p "^[ \t]*\\(?:--.*\\)?$")
          (setq found t)
          (setq res (cons (current-indentation)
                          (buffer-substring-no-properties
                           (line-beginning-position)
                           (line-end-position))))))
      res)))

(defun ridgun-indent-line ()
  "Indent and align the current line and signature according to Ridgun layout."
  (interactive)
  (let* ((line (buffer-substring-no-properties
                (line-beginning-position)
                (line-end-position)))
         (cur-text (string-trim line))
         (sig-bol (ridgun--find-enclosing-sig-bol))
         (sig (when sig-bol (ridgun--compute-group-geometry sig-bol))))
    (cond
     ;; Case 1: Current line is a `fn ::', `op ::', or prefixless signature line
     ((and sig (ridgun--parse-fn-sig-line line))
      (let ((formatted-sig (ridgun--format-sig-line sig))
            (offset (- (point) (line-beginning-position))))
        (unless (equal line formatted-sig)
          (delete-region (line-beginning-position) (line-end-position))
          (insert formatted-sig))
        (goto-char (min (line-end-position) (+ (line-beginning-position) offset)))))

     ;; Case 2: Current line is a clause of the enclosing signature
     ((and sig (ridgun--parse-clause-line sig line))
      (let ((formatted-clause (ridgun--format-fn-clause-line sig line))
            (offset (- (point) (line-beginning-position))))
        (unless (equal line formatted-clause)
          (delete-region (line-beginning-position) (line-end-position))
          (insert formatted-clause))
        (goto-char (min (line-end-position)
                        (+ (line-beginning-position)
                           (max (current-indentation) offset))))
        (ridgun--align-sig-line-at sig-bol sig)))

     ;; Case 3: Current line is a `where' binding `<lhs> -> <rhs>'
     ((and sig (ridgun--parse-where-binding-line line))
      (let ((formatted-wb (ridgun--format-where-binding-line sig line))
            (offset (- (point) (line-beginning-position))))
        (unless (equal line formatted-wb)
          (delete-region (line-beginning-position) (line-end-position))
          (insert formatted-wb))
        (goto-char (min (line-end-position)
                        (+ (line-beginning-position)
                           (max (current-indentation) offset))))
        (ridgun--align-sig-line-at sig-bol sig)))

     ;; Case 4: Standard block/body/guard/where line indentation
     (t
      (let* ((prev (ridgun--previous-nonblank-line-indent))
             (prev-indent (car prev))
             (prev-text (string-trim-right (cdr prev)))
             (fn-base-col (if sig (or (plist-get sig :name-col) 6) 0))
             (target-indent
              (cond
               ;; Top-level declarations at column 0
               ((ridgun--top-decl-line-p line)
                0)
               ;; `where' keyword line indents one level under the function name
               ((string-match-p "^where\\_>" cur-text)
                (+ fn-base-col ridgun-indent-offset))
               ;; Guard lines (`| cond = ...`) or parallel pipes (`|| ...`)
               ((string-match-p "^||?[ \t]+" cur-text)
                (+ fn-base-col ridgun-indent-offset))
               ;; Previous line is a signature line
               ((ridgun--parse-fn-sig-line prev-text)
                fn-base-col)
               ;; Previous line opens a block (`=`, `where`, `do`)
               ((string-match-p "\\(?:[^=!<>]=\\|^=\\|\\_<where\\|\\_<do\\)[ \t]*\\(?:--.*\\)?$" prev-text)
                (+ prev-indent ridgun-indent-offset))
               ;; Otherwise preserve previous non-blank line's indentation
               (t prev-indent))))
        (if (<= (current-column) (current-indentation))
            (indent-line-to (max 0 target-indent))
          (save-excursion
            (indent-line-to (max 0 target-indent)))))))))

(defun ridgun-format-buffer ()
  "Auto-indent and align all function definitions in the current buffer."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (unless (looking-at-p "^[ \t]*$")
        (ridgun-indent-line))
      (forward-line 1))))

;; ---------------------------------------------------------------------------
;; Interactive Compiler & VM Commands
;; ---------------------------------------------------------------------------

(defun ridgun--project-root ()
  "Locate the Ridgun project root containing `Cargo.toml' or `target/ridgunc'."
  (or (locate-dominating-file default-directory "Cargo.toml")
      default-directory))

(defun ridgun-check-buffer ()
  "Typecheck and analyze the current Ridgun file."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (save-buffer)
  (let* ((default-directory (ridgun--project-root))
         (rel-file (file-relative-name buffer-file-name default-directory))
         (cmd (if (file-executable-p (expand-file-name ridgun-compiler-command default-directory))
                  (format "%s check %s"
                          (shell-quote-argument ridgun-compiler-command)
                          (shell-quote-argument rel-file))
                (format "%s check %s"
                        ridgun-vm-command
                        (shell-quote-argument rel-file)))))
    (compile cmd)))

(defun ridgun-run-buffer ()
  "Compile and execute the current Ridgun file in the VM."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (save-buffer)
  (let* ((default-directory (ridgun--project-root))
         (rel-file (file-relative-name buffer-file-name default-directory))
         (cmd (format "%s %s"
                      ridgun-vm-command
                      (shell-quote-argument rel-file))))
    (compile cmd)))

(defun ridgun-compile-bytecode ()
  "Compile the current Ridgun file to a `.rgc' bytecode artifact."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (save-buffer)
  (let* ((default-directory (ridgun--project-root))
         (rel-file (file-relative-name buffer-file-name default-directory))
         (out-file (concat rel-file "c"))
         (cmd (if (file-executable-p (expand-file-name ridgun-compiler-command default-directory))
                  (format "%s compile %s -o %s"
                          (shell-quote-argument ridgun-compiler-command)
                          (shell-quote-argument rel-file)
                          (shell-quote-argument out-file))
                (format "%s compile %s -o %s"
                        ridgun-vm-command
                        (shell-quote-argument rel-file)
                        (shell-quote-argument out-file)))))
    (compile cmd)))

(defun ridgun-build-native ()
  "Build a standalone native ELF executable from the current file via `ridgunc'."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (save-buffer)
  (let* ((default-directory (ridgun--project-root))
         (rel-file (file-relative-name buffer-file-name default-directory))
         (base-name (file-name-sans-extension (file-name-nondirectory buffer-file-name)))
         (out-bin (format "target/%s" base-name))
         (cmd (if (file-executable-p (expand-file-name ridgun-compiler-command default-directory))
                  (format "%s build %s -o %s"
                          (shell-quote-argument ridgun-compiler-command)
                          (shell-quote-argument rel-file)
                          (shell-quote-argument out-bin))
                (format "%s src/main/ridgun/ridgunc.rg build %s -o %s"
                        ridgun-vm-command
                        (shell-quote-argument rel-file)
                        (shell-quote-argument out-bin)))))
    (compile cmd)))

;; ---------------------------------------------------------------------------
;; Keymap, Imenu & Major Mode Definition
;; ---------------------------------------------------------------------------

(defvar ridgun-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'ridgun-check-buffer)
    (define-key map (kbd "C-c C-r") #'ridgun-run-buffer)
    (define-key map (kbd "C-c C-k") #'ridgun-compile-bytecode)
    (define-key map (kbd "C-c C-b") #'ridgun-build-native)
    (define-key map (kbd "C-c C-f") #'ridgun-format-buffer)
    map)
  "Keymap for `ridgun-mode'.")

(defvar ridgun-imenu-generic-expression
  '(("Functions" "^\\(?:fn\\s-*::\\s-*\\)?\\([a-z_][A-Za-z0-9_]*\\)[^\n=]*=>" 1)
    ("Types" "^type\\s-+\\(?:\\s-*::\\s-*\\)?\\([A-Z][A-Za-z0-9_]*\\)" 1)
    ("Operators" "^op\\s-*::\\s-*\\(.+\\)\\s-*=>" 1)
    ("State & Hardware" "^\\(?:global\\|context\\|shared\\|hardware\\)\\s-*::\\s-*\\([a-z_][A-Za-z0-9_]*\\)" 1))
  "Imenu generic expressions for `ridgun-mode'.")

(defun ridgun--post-self-insert-align ()
  "When pressing RET, auto-align the clause on the line just completed."
  (when (memq last-command-event '(?\n ?\r))
    (save-excursion
      (when (zerop (forward-line -1))
        (let* ((line (buffer-substring-no-properties
                      (line-beginning-position)
                      (line-end-position)))
               (sig-bol (ridgun--find-enclosing-sig-bol))
               (sig (when sig-bol (ridgun--compute-group-geometry sig-bol))))
          (when (and sig
                     (not (ridgun--parse-fn-sig-line line))
                     (or (ridgun--parse-clause-line sig line)
                         (ridgun--parse-where-binding-line line)))
            (ridgun-indent-line)))))))

;;;###autoload
(define-derived-mode ridgun-mode prog-mode "Ridgun"
  "Major mode for editing Ridgun (`.rg') source code.

\\{ridgun-mode-map}"
  :syntax-table ridgun-mode-syntax-table
  (setq-local comment-start "-- ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "--+\\s-*")
  (setq-local font-lock-defaults '(ridgun-font-lock-keywords))
  (setq-local indent-line-function #'ridgun-indent-line)
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width ridgun-indent-offset)
  (setq-local imenu-generic-expression ridgun-imenu-generic-expression)
  (add-hook 'post-self-insert-hook #'ridgun--post-self-insert-align nil t))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.rg\\'" . ridgun-mode))

(provide 'ridgun-mode)
;;; ridgun-mode.el ends here
