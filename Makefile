# make test      byte-compile without warnings, then run the tests
# make grammar   build the Soma grammar into .grammar/ (from
#                ../tree-sitter-soma when it is there, else a clone)
EMACS ?= $(shell command -v emacs || echo /Applications/Emacs.app/Contents/MacOS/Emacs)
GRAMMAR_URL ?= https://github.com/rococompute/tree-sitter-soma
EXT = $(if $(filter Darwin,$(shell uname)),dylib,so)
LIB = .grammar/libtree-sitter-soma.$(EXT)

test: compile $(LIB)
	SOMA_TS_GRAMMAR_DIR=$(CURDIR)/.grammar $(EMACS) -Q --batch -L . -L test \
	  -l soma-ts-mode-tests -f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch -L . --eval '(setq byte-compile-error-on-warn t)' \
	  -f batch-byte-compile soma-ts-mode.el

grammar: $(LIB)

$(LIB):
	mkdir -p .grammar
	if [ -d ../tree-sitter-soma/src ]; then src=../tree-sitter-soma; \
	else rm -rf .grammar/src-repo && git clone -q --depth 1 $(GRAMMAR_URL) .grammar/src-repo && src=.grammar/src-repo; fi; \
	$(CC) -O2 -shared -fPIC -I$$src/src $$src/src/parser.c $$src/src/scanner.c -o $@

clean:
	rm -rf .grammar *.elc

.PHONY: test compile grammar clean
