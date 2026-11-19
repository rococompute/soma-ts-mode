# make test      byte-compile without warnings, then run the tests
# make grammar   fetch GRAMMAR_REV from GRAMMAR_URL and build into .grammar/
EMACS ?= $(shell command -v emacs || echo /Applications/Emacs.app/Contents/MacOS/Emacs)
GRAMMAR_URL ?= https://github.com/rococompute/tree-sitter-soma
GRAMMAR_REV ?= dda2a558eacc6bc5cb8a387c49bce91a75b61234
EXT = $(if $(filter Darwin,$(shell uname)),dylib,so)
LIB = .grammar/libtree-sitter-soma.$(EXT)

test: compile $(LIB)
	SOMA_TS_GRAMMAR_DIR=$(CURDIR)/.grammar $(EMACS) -Q --batch -L . -L test \
	  -l soma-ts-mode-tests -f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch -L . --eval '(setq byte-compile-error-on-warn t)' \
	  -f batch-byte-compile soma-ts-mode.el

grammar: $(LIB)

$(LIB): grammar-source
	mkdir -p .grammar
	src=.grammar/src-repo; \
	$(CC) -O2 -shared -fPIC -I$$src/src $$src/src/parser.c $$src/src/scanner.c -o $@

grammar-source:
	mkdir -p .grammar/src-repo
	[ -d .grammar/src-repo/.git ] || git -C .grammar/src-repo init -q
	if [ "$$(git -C .grammar/src-repo rev-parse HEAD 2>/dev/null)" != "$(GRAMMAR_REV)" ]; then \
	  git -C .grammar/src-repo fetch -q --depth 1 "$(GRAMMAR_URL)" "$(GRAMMAR_REV)" && \
	  git -C .grammar/src-repo checkout -q --detach FETCH_HEAD; \
	fi
	git -C .grammar/src-repo diff --quiet HEAD -- src

clean:
	rm -rf .grammar *.elc

.PHONY: test compile grammar grammar-source clean
