# soma-ts-mode

An Emacs major mode for [Soma](https://github.com/rococompute/soma) (`.soma`
programs, `.exp` proofs, `.ext` macros), built on Emacs's tree-sitter and
the grammar [tree-sitter-soma](https://github.com/rococompute/tree-sitter-soma).
It needs Emacs 29.1 or later.

## What it does

- **Highlighting:**
  - comments, and doc comments (`(** ... *)`)
  - keywords, and commands such as `Require`, `Proof` and `Qed`
  - the names definitions define, Soma's keywordless ones (`main : io unit := ...`) too
  - an Inductive's type and constructors
  - Waterproof's proof sentences (`Take n : nat.`, `We conclude that ...`)
  - strings, numbers, scopes (`12%N`), attributes (`#[export]`)
  - JSX tags
  - gradual typing's `unk`, `raise` and `cast`
  - in `#lang lisp` files, their forms

  Operators, brackets and dots are at `treesit-font-lock-level` 4.
- **Indentation:**
  - a definition's body is a step in, and its head's extra binders two
  - `|` and `end` go under their `match`; `then` and `else` under their `if`
  - an Inductive's `|` lines start at the margin
  - after a line that ends in `:=`, `=>`, `with`, `then`, a bracket, or a `,` after `forall`, the next line is a step deeper
  - lists and records line up under their first element
  - a proof's sentences go under `Proof.`; a sentence after a bullet goes past it; a bullet goes where the last one like it was; `}` goes under its `{`

  Lines inside strings and comments keep their indentation.
- **Navigation:**
  - an `imenu` outline of definitions, theorems and inductives
  - `beginning-of-defun`, `end-of-defun` and `which-function`
  - on Emacs 30, `M-a` and `M-e` move by Soma's sentences
- **Comments** nest, as Rocq's do. `M-;` writes `(* ... *)`.

## Install

```elisp
;; Emacs 30
(use-package soma-ts-mode
  :vc (:url "https://github.com/rococompute/soma-ts-mode"))

;; Emacs 29
(package-vc-install "https://github.com/rococompute/soma-ts-mode")
```

`package-vc-install` tells git from the URL only for `https://` addresses
it knows. For an SSH address, name the backend:
`(package-vc-install "git@github.com:rococompute/soma-ts-mode.git" nil 'Git)`.

Then, once, `M-x soma-ts-mode-install-grammar`. It clones
`soma-ts-mode-grammar-url` (tree-sitter-soma) at
`soma-ts-mode-grammar-revision` (the pinned commit tested with this mode) and compiles it into
`~/.emacs.d/tree-sitter/`, with git and a C compiler. Without the grammar the mode still
handles comments, but has no highlighting or indentation, and says how to
install it.

The mode opens `.soma`, `.exp` and `.ext` files. For Rocq's `.v` files too:

```elisp
(add-to-list 'auto-mode-alist '("\\.v\\'" . soma-ts-mode))
```

## Settings

| Variable | Default | What it sets |
|---|---|---|
| `soma-ts-mode-indent-offset` | 2 | a step of indentation |
| `soma-ts-mode-branch-offset` | 4 | how far a match branch's body is past its `\|` on the lines after `\| pattern =>` |
| `soma-ts-mode-grammar-url` | the GitHub repository | where the grammar is cloned from |
| `soma-ts-mode-grammar-revision` | `dda2a558eacc6bc5cb8a387c49bce91a75b61234` | the tested grammar commit; explicitly override to test another revision |

pantheon indents branch bodies by 4, and Soma's own examples by 2. For a
repository in the second style, add this `.dir-locals.el`:

```elisp
((soma-ts-mode . ((soma-ts-mode-branch-offset . 2))))
```

## Develop

```sh
make test      # byte-compile with warnings as errors, then the ERT tests
make grammar   # fetch the pinned grammar and build it into .grammar/
make test GRAMMAR_URL=../tree-sitter-soma # use a local source for the pinned revision
```

The tests cover:
- each highlight, and the highlights in a lisp file
- re-indenting `test/indent.soma` from flush left, and branches at an offset of 2
- strings and comments keeping their layout
- the imenu outline, defun navigation, nested comments, and the file extensions

As a wider check, every Soma file in soma and pantheon (24,843 lines) was
highlighted and re-indented without an error. 85% of the lines kept their
indentation. Most of the rest are the two branch styles, or alignment chosen
by hand.

## License

MIT
