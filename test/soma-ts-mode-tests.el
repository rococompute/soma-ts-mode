;;; soma-ts-mode-tests.el --- Tests for soma-ts-mode -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with `make test', which builds the grammar into .grammar/ first.
;; They check highlighting, indentation, the outline and comments.

;;; Code:

(require 'ert)
(require 'imenu)
(require 'soma-ts-mode)

(defvar soma-ts-mode-tests--dir
  (file-name-directory (or load-file-name buffer-file-name)))

(let ((grammar (getenv "SOMA_TS_GRAMMAR_DIR")))
  (when grammar (add-to-list 'treesit-extra-load-path grammar)))

(defmacro soma-ts-mode-tests--with (text &rest body)
  "Run BODY in a `soma-ts-mode' buffer of TEXT, highlighted."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (soma-ts-mode)
     (font-lock-ensure)
     (goto-char (point-min))
     ,@body))

(defun soma-ts-mode-tests--face (word &optional nth)
  "The face at the NTH (1 by default) occurrence of WORD."
  (goto-char (point-min))
  (search-forward word nil nil (or nth 1))
  (let ((face (get-text-property (match-beginning 0) 'face)))
    (if (consp face) (car face) face)))

(defun soma-ts-mode-tests--flush ()
  "Remove the indentation of every line that doesn't start in a comment."
  (goto-char (point-min))
  (while (re-search-forward "^[ \t]+" nil t)
    (unless (nth 8 (save-excursion (syntax-ppss (match-beginning 0))))
      (replace-match ""))))

(ert-deftest soma-ts-mode-keeps-strings-and-comments ()
  (let ((text (concat "(** a doc\n        soma run x.soma\n    end *)\n"
                      "s := \"one\n   two\n\".\n")))
    (with-temp-buffer
      (insert text)
      (soma-ts-mode)
      (indent-region (point-min) (point-max))
      (should (equal (buffer-string) text)))))

(ert-deftest soma-ts-mode-grammar-loads ()
  (should (treesit-language-available-p 'soma)))

(ert-deftest soma-ts-mode-highlights ()
  (soma-ts-mode-tests--with
      (concat "(** doc *)\n(* note *)\nRequire Import Sandbox.\n"
              "square (x : N) : N := x * x.\n"
              "Inductive action := Increment.\n"
              "main : io unit := r <- resolve \"host\" ;; match r with _ => unk end.\n"
              "Lemma l : 12%N = 12.\nProof.\n  Take n : nat.\n  We conclude that n = n.\nQed.\n"
              "#[export] Instance i : Show t := { to_string _ := \"t\" }.\n"
              "v := <div className=\"c\"> </div>.\n")
    (should (eq (soma-ts-mode-tests--face "doc") 'font-lock-doc-face))
    (should (eq (soma-ts-mode-tests--face "note") 'font-lock-comment-face))
    (should (eq (soma-ts-mode-tests--face "Require") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "square") 'font-lock-function-name-face))
    (should (eq (soma-ts-mode-tests--face "main") 'font-lock-function-name-face))
    (should (eq (soma-ts-mode-tests--face "N)") 'font-lock-type-face))
    (should (eq (soma-ts-mode-tests--face "Inductive") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "action") 'font-lock-type-face))
    (should (eq (soma-ts-mode-tests--face "Increment") 'font-lock-constant-face))
    (should (eq (soma-ts-mode-tests--face "\"host\"") 'font-lock-string-face))
    (should (eq (soma-ts-mode-tests--face "match") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "with") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "unk") 'font-lock-builtin-face))
    (should (eq (soma-ts-mode-tests--face "end") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "12") 'font-lock-number-face))
    (should (eq (soma-ts-mode-tests--face "%N") 'font-lock-preprocessor-face))
    (should (eq (soma-ts-mode-tests--face "Proof") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "Take") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "We") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "conclude") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "Qed") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "#[") 'font-lock-preprocessor-face))
    (should (eq (soma-ts-mode-tests--face "Instance") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "<div") 'font-lock-function-call-face))
    ;; plain words stay plain
    (should (null (soma-ts-mode-tests--face "resolve")))))

(ert-deftest soma-ts-mode-highlights-lisp ()
  (soma-ts-mode-tests--with "#lang lisp\n; note\n(define (square x) (* x x))\n(square 12)\n"
    (should (eq (soma-ts-mode-tests--face "#lang") 'font-lock-preprocessor-face))
    (should (eq (soma-ts-mode-tests--face "note") 'font-lock-comment-face))
    (should (eq (soma-ts-mode-tests--face "define") 'font-lock-keyword-face))
    (should (eq (soma-ts-mode-tests--face "12") 'font-lock-number-face))
    ;; (* is a call here, not a comment
    (should (null (soma-ts-mode-tests--face "x x")))))

(ert-deftest soma-ts-mode-indents ()
  (let* ((file (expand-file-name "indent.soma" soma-ts-mode-tests--dir))
         (expected (with-temp-buffer (insert-file-contents file) (buffer-string))))
    (with-temp-buffer
      (insert expected)
      (soma-ts-mode)
      ;; flush every line of code left (a comment's lines keep their
      ;; layout), then indent it all again
      (soma-ts-mode-tests--flush)
      (indent-region (point-min) (point-max))
      (should (equal (buffer-string) expected)))))

(ert-deftest soma-ts-mode-indents-branches-by-the-offset ()
  (let ((expected "main :=\n  match a with\n  | x =>\n    f x\n  end.\n"))
    (with-temp-buffer
      (insert expected)
      (soma-ts-mode)
      (setq-local soma-ts-mode-branch-offset 2)
      (soma-ts-mode-tests--flush)
      (indent-region (point-min) (point-max))
      (should (equal (buffer-string) expected)))))

(ert-deftest soma-ts-mode-imenu ()
  (soma-ts-mode-tests--with
      (concat "square (x : N) : N := x * x.\nDefinition twice (n : N) := 2 * n.\n"
              "Inductive action := Increment.\nLemma l : 1 = 1.\nProof. reflexivity. Qed.\n"
              "Instance : Show t := { to_string _ := \"t\" }.\n")
    (let ((index (funcall imenu-create-index-function)))
      (should (equal (mapcar #'car (cdr (assoc "Definition" index))) '("square" "twice")))
      (should (equal (mapcar #'car (cdr (assoc "Theorem" index))) '("l")))
      (should (equal (mapcar #'car (cdr (assoc "Inductive" index))) '("action"))))))

(ert-deftest soma-ts-mode-defun-navigation ()
  (soma-ts-mode-tests--with "a := 1.\nb := 2.\nLemma c : True.\nProof. exact I. Qed.\n"
    (goto-char (point-max))
    (beginning-of-defun)
    (should (looking-at "Lemma c"))
    (beginning-of-defun)
    (should (looking-at "b :="))
    (should (equal (treesit-defun-name (treesit-defun-at-point)) "b"))))

(ert-deftest soma-ts-mode-comments-nest ()
  (soma-ts-mode-tests--with "(* outer (* inner *) still *) x.\n"
    (search-forward "still")
    (should (nth 4 (syntax-ppss)))
    (search-forward "x")
    (should-not (nth 4 (syntax-ppss)))))

(ert-deftest soma-ts-mode-files ()
  (dolist (name '("a.soma" "a.exp" "a.ext"))
    (should (eq (assoc-default name auto-mode-alist #'string-match) 'soma-ts-mode))))

(provide 'soma-ts-mode-tests)

;;; soma-ts-mode-tests.el ends here
