;;; soma-ts-mode.el --- Major mode for Soma, with tree-sitter -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yev Barkalov

;; Author: Yev Barkalov
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages
;; URL: https://github.com/rococompute/soma-ts-mode

;; This file is not part of GNU Emacs.

;; Permission is hereby granted, free of charge, to any person obtaining a
;; copy of this software and associated documentation files (the
;; "Software"), to deal in the Software without restriction, including
;; without limitation the rights to use, copy, modify, merge, publish,
;; distribute, sublicense, and/or sell copies of the Software, and to
;; permit persons to whom the Software is furnished to do so, subject to
;; the following conditions: the above copyright notice and this
;; permission notice shall be included in all copies or substantial
;; portions of the Software.  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT
;; WARRANTY OF ANY KIND.  See LICENSE.

;;; Commentary:

;; A major mode for Soma (https://github.com/rococompute/soma), Rocq's
;; language with Soma's additions, built on the tree-sitter grammar
;; tree-sitter-soma (https://github.com/rococompute/tree-sitter-soma).
;; It provides:
;;
;; - highlighting: comments and doc comments, keywords and commands, the
;;   names that definitions define (Soma's `main : io unit := ...' too),
;;   an Inductive's type and constructors, Waterproof's proof sentences
;;   (`Take', `We conclude that'), strings, numbers, scopes (`12%N'),
;;   attributes, JSX tags, and `#lang lisp' files' forms;
;; - indentation: a definition's body, `match' ... `end' and its
;;   branches, an Inductive's constructors, brackets, and a proof's
;;   sentences under `Proof.', with its bullets and braces;
;; - an outline (`imenu') of definitions, theorems and inductives, and
;;   `beginning-of-defun', `end-of-defun', `which-function';
;; - comments that nest, as Rocq's do: (* (* *) *).
;;
;; The grammar is a compiled library that Emacs loads.  To install it,
;; run M-x soma-ts-mode-install-grammar once.  It clones
;; `soma-ts-mode-grammar-url' and compiles it with a C compiler.  Without
;; the grammar the mode still works for comments, but has no highlighting
;; or indentation.

;;; Code:

(require 'treesit)
(eval-when-compile (require 'rx))

(declare-function treesit-parser-create "treesit.c")
(declare-function treesit-node-type "treesit.c")
(declare-function treesit-node-text "treesit.c")
(declare-function treesit-node-start "treesit.c")
(declare-function treesit-node-end "treesit.c")
(declare-function treesit-node-parent "treesit.c")
(declare-function treesit-node-child "treesit.c")
(declare-function treesit-node-child-by-field-name "treesit.c")
(declare-function treesit-node-prev-sibling "treesit.c")
(declare-function treesit-node-first-child-for-pos "treesit.c")
(declare-function treesit-buffer-root-node "treesit.c")

(defgroup soma-ts nil
  "Major mode for Soma, with tree-sitter."
  :group 'languages
  :prefix "soma-ts-mode-")

(defcustom soma-ts-mode-indent-offset 2
  "How far a sentence's continuation lines, and a proof's sentences, are indented."
  :type 'integer
  :safe #'integerp)

(defcustom soma-ts-mode-branch-offset 4
  "How far a match branch's body is indented past its `|', on the lines after.
With 4, the body lines up after \"| \"; Soma's own examples use 2."
  :type 'integer
  :safe #'integerp)

(defcustom soma-ts-mode-grammar-url "https://github.com/rococompute/tree-sitter-soma"
  "Where `soma-ts-mode-install-grammar' clones the grammar from.
Any address git can clone works, such as a fork or a local checkout."
  :type 'string)

(defcustom soma-ts-mode-grammar-revision "dda2a558eacc6bc5cb8a387c49bce91a75b61234"
  "The grammar revision that `soma-ts-mode-install-grammar' installs.
The default pins the grammar tested with this mode.  Set this to a different
commit, tag or branch explicitly when testing a grammar update."
  :type 'string)

;;; Words

(defconst soma-ts-mode--commands
  '("Require" "Import" "Export" "From" "Open" "Close" "Scope" "Proof" "Qed"
    "Defined" "Admitted" "Abort" "Save" "End" "Notation" "Infix" "Arguments"
    "Implicit" "Hint" "Fail" "Compute" "Eval" "Check" "Print" "Search" "Set"
    "Unset" "Rocq" "Library" "Transparent" "Opaque" "Context" "Variables"
    "Hypotheses" "Parameters" "Axioms" "Existing" "Scheme" "Declare" "Ltac2"
    "Obligation" "Next" "Goal" "Show")
  "Commands that are identifiers to the grammar, and keywords to the reader.")

(defconst soma-ts-mode--term-keywords
  '("with" "fun" "let" "in" "if" "then" "else" "return" "as" "forall" "exists"
    "fix" "cofix" "struct" "where")
  "Keywords inside terms.")

(defconst soma-ts-mode--waterproof-leads
  '("Take" "Assume" "We" "By" "Choose" "Since" "It" "Then" "Either" "Obtain"
    "Define" "Expand" "Use" "Write")
  "Words that start Waterproof's proof sentences.")

(defconst soma-ts-mode--waterproof-follows
  '("conclude" "need" "consider" "use" "know" "claim" "argue" "show" "that"
    "suffices" "may" "prove")
  "Words that come second in Waterproof's sentences: We conclude, Assume that.")

(defconst soma-ts-mode--types
  '("Any" "Type" "Prop" "SProp" "nat" "N" "Z" "Q" "bool" "string" "ascii"
    "list" "option" "prod" "sum" "unit" "io")
  "Sorts, and the types Soma's programs use most.")

(defconst soma-ts-mode--gradual '("unk" "raise" "cast")
  "Soma's gradual typing.")

(defconst soma-ts-mode--constants
  '("true" "false" "tt" "None" "Some" "nil" "eq_refl")
  "Constructors used as constants.")

(defconst soma-ts-mode--theorem-keywords
  '("Lemma" "Theorem" "Example" "Corollary" "Fact" "Remark" "Proposition"
    "Property" "Conjecture")
  "Keywords whose definitions imenu lists as theorems.")

(defconst soma-ts-mode--proof-ends '("Qed" "Defined" "Admitted" "Abort" "Save")
  "Commands that end a proof.")

(defconst soma-ts-mode--top-commands
  '("Require" "Import" "Export" "From" "Open" "Close" "Section" "Module" "End"
    "Notation" "Infix" "Arguments" "Hint" "Set" "Unset" "Transparent" "Opaque"
    "Rocq" "Declare" "Scheme" "Existing" "Proof" "Check" "Compute" "Eval"
    "Print" "Search")
  "Commands that start at the left margin, even after a proof's sentences.")

(defun soma-ts-mode--words (words)
  "A regexp that matches exactly one of WORDS."
  (concat "\\`" (regexp-opt words) "\\'"))

;;; Highlighting

(defvar soma-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'soma
   :feature 'comment
   '((doc_comment) @font-lock-doc-face
     (comment) @font-lock-comment-face
     (line_comment) @font-lock-comment-face)

   :language 'soma
   :feature 'definition
   '((definition name: (identifier) @font-lock-function-name-face)
     (inductive name: (identifier) @font-lock-type-face)
     (constructor name: (identifier) @font-lock-constant-face))

   :language 'soma
   :feature 'keyword
   `((keyword) @font-lock-keyword-face
     (lang_line) @font-lock-preprocessor-face
     ((sentence :anchor (identifier) @font-lock-keyword-face)
      (:match ,(soma-ts-mode--words soma-ts-mode--waterproof-leads)
              @font-lock-keyword-face))
     ((sentence :anchor (identifier) @soma-ts-mode--lead
                :anchor (identifier) @font-lock-keyword-face)
      (:match ,(soma-ts-mode--words '("We" "Assume" "It" "By")) @soma-ts-mode--lead)
      (:match ,(soma-ts-mode--words soma-ts-mode--waterproof-follows)
              @font-lock-keyword-face))
     ((identifier) @font-lock-keyword-face
      (:match ,(soma-ts-mode--words soma-ts-mode--commands) @font-lock-keyword-face))
     ((identifier) @font-lock-keyword-face
      (:match ,(soma-ts-mode--words soma-ts-mode--term-keywords) @font-lock-keyword-face))
     ((list :anchor (atom) @font-lock-keyword-face)
      (:match ,(soma-ts-mode--words '("define" "define-any" "lambda" "if" "let" "match"))
              @font-lock-keyword-face)))

   :language 'soma
   :feature 'string
   '((string) @font-lock-string-face)

   :language 'soma
   :feature 'type
   `(((identifier) @font-lock-type-face
      (:match ,(soma-ts-mode--words soma-ts-mode--types) @font-lock-type-face)))

   :language 'soma
   :feature 'builtin
   `(((identifier) @font-lock-builtin-face
      (:match ,(soma-ts-mode--words soma-ts-mode--gradual) @font-lock-builtin-face)))

   :language 'soma
   :feature 'constant
   `(((identifier) @font-lock-constant-face
      (:match ,(soma-ts-mode--words soma-ts-mode--constants) @font-lock-constant-face))
     ((atom) @font-lock-constant-face
      (:match "\\`#[tf]\\'" @font-lock-constant-face)))

   :language 'soma
   :feature 'number
   '((number) @font-lock-number-face
     ((atom) @font-lock-number-face (:match "\\`-?[0-9]+\\'" @font-lock-number-face)))

   :language 'soma
   :feature 'attribute
   '((attribute) @font-lock-preprocessor-face
     (scope) @font-lock-preprocessor-face)

   :language 'soma
   :feature 'tag
   '((jsx_open) @font-lock-function-call-face
     (jsx_close) @font-lock-function-call-face)

   :language 'soma
   :feature 'operator
   '((operator) @font-lock-operator-face
     [":" ":=" "|"] @font-lock-operator-face)

   :language 'soma
   :feature 'bracket
   '(["(" ")" "[" "]" "{" "}" "{|" "|}" "#["] @font-lock-bracket-face
     (focus) @font-lock-bracket-face)

   :language 'soma
   :feature 'delimiter
   '((dot) @font-lock-delimiter-face
     (bullet) @font-lock-misc-punctuation-face))
  "Tree-sitter font-lock settings for `soma-ts-mode'.")

;;; Indentation

(defun soma-ts-mode--first-word (node)
  "The text of NODE's first child, when NODE is a sentence, else nil."
  (when (and node (equal (treesit-node-type node) "sentence"))
    (let ((first (treesit-node-child node 0)))
      (and first (treesit-node-text first t)))))

(defun soma-ts-mode--sentence-starts-with (node words)
  "Whether NODE is a sentence whose first word is in WORDS."
  (member (soma-ts-mode--first-word node) words))

(defun soma-ts-mode--top-level-p (node)
  "Whether NODE starts at the left margin wherever it is.
That is a definition, an inductive, or a command such as `Require'."
  (and node
       (or (member (treesit-node-type node) '("definition" "inductive" "lang_line"))
           (soma-ts-mode--sentence-starts-with node soma-ts-mode--top-commands))))

(defun soma-ts-mode--column (pos)
  "The column of POS."
  (save-excursion (goto-char pos) (current-column)))

(defun soma-ts-mode--line-first-item (item)
  "The first of the items on ITEM's line, ITEM itself if it is first."
  (let ((line (line-number-at-pos (treesit-node-start item)))
        (first item)
        (prev (treesit-node-prev-sibling item t)))
    (while (and prev (= (line-number-at-pos (treesit-node-start prev)) line))
      (setq first prev
            prev (treesit-node-prev-sibling prev t)))
    first))

(defun soma-ts-mode--proof-start-p (item)
  "Whether ITEM is before any proof it is in.
That is a Proof sentence, a top-level item, or a proof's end."
  (or (soma-ts-mode--sentence-starts-with item '("Proof"))
      (soma-ts-mode--top-level-p item)
      (soma-ts-mode--sentence-starts-with item soma-ts-mode--proof-ends)))

(defun soma-ts-mode--earlier-bullet (item text)
  "The nearest bullet before ITEM whose text is TEXT, within the same proof."
  (let ((prev item) found)
    (while (and (not found) prev (not (soma-ts-mode--proof-start-p prev)))
      (when (and (equal (treesit-node-type prev) "bullet")
                 (equal (treesit-node-text prev t) text))
        (setq found prev))
      (setq prev (treesit-node-prev-sibling prev t)))
    found))

(defun soma-ts-mode--matching-brace (item)
  "The `{' (or `2:{') that the `}' after ITEM closes, within the same proof."
  (let ((prev item) (depth 0) found)
    (while (and (not found) prev (not (soma-ts-mode--proof-start-p prev)))
      (when (equal (treesit-node-type prev) "focus")
        (if (equal (treesit-node-text prev t) "}")
            (setq depth (1+ depth))
          (if (= depth 0) (setq found prev) (setq depth (1- depth)))))
      (setq prev (treesit-node-prev-sibling prev t)))
    found))

(defun soma-ts-mode--prev-item (bol)
  "The item of the file before the one at BOL, skipping comments."
  (let* ((root (treesit-buffer-root-node 'soma))
         (here (treesit-node-first-child-for-pos root bol t))
         (prev (if (and here (< (treesit-node-start here) bol))
                   here
                 (if here
                     (treesit-node-prev-sibling here t)
                   (treesit-node-child root -1 t)))))
    (while (and prev (member (treesit-node-type prev) '("comment" "doc_comment")))
      (setq prev (treesit-node-prev-sibling prev t)))
    prev))

(defun soma-ts-mode--item-column (node _parent bol)
  "The column of the item NODE at BOL, in a file of items.
NODE is nil on an empty line.  Definitions and commands start at the
left margin.  A proof's sentences are indented under `Proof.', and
follow its bullets and braces: a sentence after a bullet is indented
past it, a bullet is where the last one like it was, and `}' is under
its `{'."
  (let ((prev (soma-ts-mode--prev-item bol))
        (offset soma-ts-mode-indent-offset)
        (type (and node (treesit-node-type node))))
    (cond
     ((soma-ts-mode--top-level-p node) 0)
     ((soma-ts-mode--sentence-starts-with node soma-ts-mode--proof-ends) 0)
     ((null prev) 0)
     ((soma-ts-mode--sentence-starts-with prev '("Proof")) offset)
     ((soma-ts-mode--top-level-p prev) 0)
     ((soma-ts-mode--sentence-starts-with prev soma-ts-mode--proof-ends) 0)
     ;; after a `}': where its `{' was
     ((and (equal (treesit-node-type prev) "focus") (equal (treesit-node-text prev t) "}")
           (not (equal type "bullet"))
           (not (and (equal type "focus") (equal (treesit-node-text node t) "}"))))
      (let ((open (soma-ts-mode--matching-brace (treesit-node-prev-sibling prev t))))
        (if open
            (soma-ts-mode--column (treesit-node-start (soma-ts-mode--line-first-item open)))
          0)))
     ((and (equal type "focus") (equal (treesit-node-text node t) "}"))
      (let ((open (soma-ts-mode--matching-brace prev)))
        (if open
            (soma-ts-mode--column (treesit-node-start (soma-ts-mode--line-first-item open)))
          0)))
     (t
      (let* ((first (soma-ts-mode--line-first-item prev))
             (column (soma-ts-mode--column (treesit-node-start first)))
             (first-type (treesit-node-type first)))
        (if (equal type "bullet")
            (let ((same (soma-ts-mode--earlier-bullet prev (treesit-node-text node t))))
              (cond (same (soma-ts-mode--column (treesit-node-start same)))
                    ((member first-type '("bullet" "focus")) (+ column offset))
                    (t column)))
          (if (and (member first-type '("bullet" "focus"))
                   (not (equal (treesit-node-text first t) "}")))
              (+ column offset)
            column)))))))

(defconst soma-ts-mode--openers
  '(":=" "=>" "with" "then" "(" "[" "{" "{|")
  "Tokens that, ending a line, indent the next one a step deeper.
A trailing `else' is not one: `if c then a else' chains guards at one
indentation.  Nor is `->': hypotheses stack at one indentation.  A
trailing `,' is one only after `forall' or `exists'.")

(defun soma-ts-mode--item (node)
  "The item of the file (a child of the root) that holds NODE."
  (while (and (treesit-node-parent node)
              (not (equal (treesit-node-type (treesit-node-parent node)) "source_file")))
    (setq node (treesit-node-parent node)))
  node)

(defun soma-ts-mode--line-column (pos)
  "The indentation of the line that holds POS."
  (save-excursion (goto-char pos) (current-indentation)))

(defun soma-ts-mode--prev-line (bol limit &optional outside)
  "The start of the code line before BOL, not before LIMIT, or nil.
Empty lines are skipped, and with OUTSIDE, lines that start inside
brackets that close before BOL: the line found is the one that the
line at BOL continues."
  (save-excursion
    (goto-char bol)
    (let ((depth (car (syntax-ppss bol))) found)
      (while (and (not found) (= (forward-line -1) 0) (>= (line-end-position) limit))
        (back-to-indentation)
        (unless (or (eolp)
                    (and outside (> (car (syntax-ppss)) depth))
                    (nth 8 (syntax-ppss)))
          (setq found (line-beginning-position))))
      found)))

(defun soma-ts-mode--last-token (line)
  "The text of the last token on the line at LINE, past any comment."
  (save-excursion
    (goto-char line)
    (end-of-line)
    (skip-chars-backward " \t")
    (let ((token nil) (start line))
      (while (and (not token) (> (point) start))
        (let ((leaf (treesit-node-at (1- (point)) 'soma)))
          (if (and leaf (member (treesit-node-type leaf) '("comment" "doc_comment"))
                   (> (treesit-node-start leaf) start))
              (progn (goto-char (treesit-node-start leaf)) (skip-chars-backward " \t"))
            (setq token (if leaf (treesit-node-text leaf t) "")))))
      token)))

(defun soma-ts-mode--matching-if (bol limit word)
  "The column of the `if' whose WORD (\"then\" or \"else\") starts the line at BOL.
Nothing before LIMIT is searched; nil if there is no such `if'."
  (save-excursion
    (goto-char bol)
    (let ((depth 0) found)
      (while (and (not found)
                  (re-search-backward "\\_<\\(if\\|then\\|else\\)\\_>" limit t))
        (unless (nth 8 (syntax-ppss))
          (let ((w (match-string 1)))
            (cond ((equal w "if")
                   (if (> depth 0)
                       (setq depth (1- depth))
                     ;; `else if': line up with that `else'
                     (setq found (if (and (equal word "else")
                                          (looking-back "\\_<else[ \t]+" (line-beginning-position)))
                                     (save-excursion
                                       (goto-char (match-beginning 0))
                                       (current-column))
                                   (current-column)))))
                  ((equal w word) (setq depth (1+ depth)))))))
      found)))

(defun soma-ts-mode--top-assign-p (line item)
  "Whether the line at LINE ends with ITEM's own `:=', not a `let''s."
  (save-excursion
    (goto-char line)
    (end-of-line)
    (skip-chars-backward " \t")
    (let ((leaf (treesit-node-at (max line (1- (point))) 'soma)))
      (and leaf (equal (treesit-node-text leaf t) ":=")
           (treesit-node-eq (treesit-node-parent leaf) item)))))

(defun soma-ts-mode--continuation-column (node parent bol)
  "The column of the line at BOL, inside an item: a sentence's later lines.
NODE is the largest node starting at BOL, nil on an empty line, PARENT
the node around it.  `|' and `end' are under their `match', `then' and
`else' under their `if', a closing bracket at its opening line's
indentation.  Otherwise a line is indented as the line before it, a
step deeper when that one ends with an opener (`:=', `=>', `with',
`then', `,', a bracket), and the item's second line is a step deeper
than its first.  A branch's body after `| pattern =>' is
`soma-ts-mode-branch-offset' past the `|'."
  (let* ((offset soma-ts-mode-indent-offset)
         (leaf (and node (treesit-node-at bol 'soma)))
         (text (and leaf (= (treesit-node-start leaf) bol) (treesit-node-text leaf t)))
         (leaf-parent (and leaf (treesit-node-parent leaf)))
         (leaf-parent-type (and leaf-parent (treesit-node-type leaf-parent)))
         (item (soma-ts-mode--item (or node parent)))
         (item-start (treesit-node-start item))
         (prev (soma-ts-mode--prev-line bol item-start t))
         (just-before (soma-ts-mode--prev-line bol item-start)))
    (cond
     ((and (member text '("|" "end")) (equal leaf-parent-type "match"))
      (soma-ts-mode--column (treesit-node-start leaf-parent)))
     ((and (equal text "|") (equal leaf-parent-type "inductive"))
      (soma-ts-mode--line-column item-start))
     ((and (member text '(")" "]" "}" "|}"))
           (member leaf-parent-type '("parenthesized" "bracketed" "braced" "record" "attribute")))
      (soma-ts-mode--line-column (treesit-node-start leaf-parent)))
     ((and (member text '("then" "else"))
           (soma-ts-mode--matching-if bol item-start text)))
     ((null prev) (+ (soma-ts-mode--line-column item-start) offset))
     (t
      (let* ((opener (and parent (member (treesit-node-type parent)
                                         '("parenthesized" "bracketed" "braced" "record" "list"))
                          parent))
             (last (soma-ts-mode--last-token just-before))
             (ends-open (or (member last soma-ts-mode--openers)
                            (and (equal last ",")
                                 (save-excursion
                                   (goto-char just-before)
                                   (re-search-forward "\\_<\\(?:forall\\|exists\\)\\_>"
                                                      (line-end-position) t)))))
             (prev-column (soma-ts-mode--line-column prev)))
        (cond
         ;; the first line inside a bracket opened on the line before: a
         ;; list's or a record's under its first element when that follows
         ;; the bracket on that line, else a step deeper than that line
         ((and opener (>= (treesit-node-start opener) just-before)
               (not (equal (treesit-node-type opener) "list")))
          (let ((first (and (member (treesit-node-type opener) '("bracketed" "braced" "record"))
                            (treesit-node-child opener 1))))
            (if (and first (< (treesit-node-start first) bol)
                     (= (line-number-at-pos (treesit-node-start first))
                        (line-number-at-pos (treesit-node-start opener))))
                (soma-ts-mode--column (treesit-node-start first))
              (+ (soma-ts-mode--line-column just-before) offset))))
         ((and opener (equal (treesit-node-type opener) "list")
               (>= (treesit-node-start opener) just-before))
          (+ (soma-ts-mode--column (treesit-node-start opener)) offset))
         ;; after the definition's own `:=': its body, a step in
         ((and (equal last ":=") (soma-ts-mode--top-assign-p just-before item))
          (+ (soma-ts-mode--line-column item-start) offset))
         ;; the item's second line: a step in, or two for more binders,
         ;; `(x : A)', after a first line that doesn't end with an opener
         ((<= prev item-start)
          (+ (soma-ts-mode--line-column item-start)
             (if (and (not ends-open) (not (equal last ":"))
                      (member text '("(" "{" "[")))
                 (* 2 offset)
               offset)))
         ;; a branch's body, on the lines after `| pattern =>'
         ((and ends-open (equal last "=>") (= prev just-before)
               (save-excursion (goto-char prev) (back-to-indentation) (looking-at-p "|")))
          (+ prev-column soma-ts-mode-branch-offset))
         (ends-open (+ prev-column offset))
         (t prev-column)))))))

(defun soma-ts-mode--inside-column (_node parent bol)
  "The column of the line at BOL inside PARENT, a comment or a string.
A line with text keeps its indentation: a comment's own layout and a
string's contents are left as they are.  An empty line in a comment
lines up with the line before, or with the text after `(** ' or `(* '."
  (let ((type (treesit-node-type parent)))
    (cond
     ((equal type "string") (soma-ts-mode--column bol))
     ((save-excursion (goto-char bol) (not (looking-at-p "[ \t]*$")))
      (soma-ts-mode--column bol))
     (t
      (let ((prev (save-excursion
                    (goto-char bol)
                    (and (= (forward-line -1) 0)
                         (> (line-beginning-position) (treesit-node-start parent))
                         (current-indentation)))))
        (or prev
            (+ (soma-ts-mode--column (treesit-node-start parent))
               (if (equal type "doc_comment") 4 3))))))))

(defvar soma-ts-mode--indent-rules
  `((soma
     ((parent-is "\\`\\(?:doc_comment\\|comment\\|line_comment\\|string\\)\\'")
      column-0 soma-ts-mode--inside-column)
     ((parent-is "\\`source_file\\'") column-0 soma-ts-mode--item-column)
     (catch-all column-0 soma-ts-mode--continuation-column)))
  "Tree-sitter indentation rules for `soma-ts-mode'.")

;;; Navigation and the outline

(defun soma-ts-mode--defun-name (node)
  "The name that NODE, a definition or an inductive, defines, or nil."
  (let ((name (treesit-node-child-by-field-name node "name")))
    (and name (treesit-node-text name t))))

(defun soma-ts-mode--keyword-in (words)
  "A predicate: whether a node's keyword, and its name, are in WORDS."
  (lambda (node)
    (let ((keyword (treesit-node-child-by-field-name node "keyword")))
      (and (soma-ts-mode--defun-name node)
           keyword
           (member (treesit-node-text keyword t) words)))))

(defun soma-ts-mode--definition-p (node)
  "Whether NODE is a definition with a name that isn't a theorem."
  (and (soma-ts-mode--defun-name node)
       (not (funcall (soma-ts-mode--keyword-in soma-ts-mode--theorem-keywords) node))))

;;; The mode

(defvar soma-ts-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; (* comments *), which nest
    (modify-syntax-entry ?\( "()1n" table)
    (modify-syntax-entry ?* ". 23n" table)
    (modify-syntax-entry ?\) ")(4n" table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\\ "." table)
    (modify-syntax-entry ?' "_" table)
    (modify-syntax-entry ?_ "_" table)
    (dolist (c '(?+ ?- ?/ ?< ?> ?= ?& ?| ?% ?! ?? ?@ ?~ ?^ ?$ ?: ?\; ?,))
      (modify-syntax-entry c "." table))
    table)
  "Syntax table for `soma-ts-mode'.")

;;;###autoload
(defun soma-ts-mode-install-grammar ()
  "Clone, compile and install the Soma grammar for Emacs.
It comes from `soma-ts-mode-grammar-url' at
`soma-ts-mode-grammar-revision', and is compiled into Emacs's tree-sitter
directory.  It needs git and a C compiler."
  (interactive)
  (let ((treesit-language-source-alist
         (cons (list 'soma soma-ts-mode-grammar-url soma-ts-mode-grammar-revision)
               (bound-and-true-p treesit-language-source-alist))))
    (treesit-install-language-grammar 'soma))
  (when (treesit-language-available-p 'soma)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (derived-mode-p 'soma-ts-mode) (soma-ts-mode))))))

;;;###autoload
(define-derived-mode soma-ts-mode prog-mode "Soma"
  "Major mode for Soma, Rocq's language with Soma's additions, with tree-sitter.

Highlighting, indentation and the outline need the grammar; install it
with \\[soma-ts-mode-install-grammar].

\\{soma-ts-mode-map}"
  :syntax-table soma-ts-mode-syntax-table
  (setq-local comment-start "(* ")
  (setq-local comment-end " *)")
  (setq-local comment-start-skip "(\\*+[ \t]*")
  (setq-local comment-end-skip "[ \t]*\\*+)")
  (setq-local comment-use-syntax t)
  (setq-local comment-multi-line t)
  (setq-local indent-tabs-mode nil)
  (if (not (treesit-ready-p 'soma t))
      (message "soma-ts-mode: no Soma grammar; install it with M-x soma-ts-mode-install-grammar")
    (treesit-parser-create 'soma)
    (setq-local treesit-font-lock-settings soma-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '((comment definition)
                  (keyword string)
                  (type builtin constant number attribute tag)
                  (operator bracket delimiter)))
    (setq-local treesit-simple-indent-rules soma-ts-mode--indent-rules)
    (setq-local electric-indent-chars (append "|}" electric-indent-chars))
    (setq-local treesit-defun-type-regexp "\\`\\(?:definition\\|inductive\\)\\'")
    (setq-local treesit-defun-name-function #'soma-ts-mode--defun-name)
    (setq-local treesit-simple-imenu-settings
                `(("Definition" "\\`definition\\'" soma-ts-mode--definition-p nil)
                  ("Theorem" "\\`definition\\'"
                   ,(soma-ts-mode--keyword-in soma-ts-mode--theorem-keywords) nil)
                  ("Inductive" "\\`inductive\\'" soma-ts-mode--defun-name nil)))
    (when (boundp 'treesit-thing-settings)
      ;; Emacs 30: M-a and M-e move by Soma's sentences
      (setq-local treesit-thing-settings
                  '((soma (sentence "\\`\\(?:definition\\|inductive\\|sentence\\)\\'")))))
    (treesit-major-mode-setup)
    ;; a proof's indentation follows the lines before it, so indent a
    ;; region line by line, not each line from the text as it was
    (setq-local indent-region-function nil)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.\\(?:soma\\|exp\\|ext\\)\\'" . soma-ts-mode))

(provide 'soma-ts-mode)

;;; soma-ts-mode.el ends here
