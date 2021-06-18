# opsbox - a small toolkit of bash ops helpers.

SHELL := /bin/bash

# Allow overriding the tool locations (handy in CI or a vendored checkout).
SHELLCHECK ?= shellcheck
BATS ?= bats

SCRIPTS := bin/opsbox bin/backup bin/disk-report bin/healthcheck bin/logrotate-lite bin/prune-old
LIB := lib/common.sh

PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
# Scripts source ../lib/common.sh relative to their own location, so the lib
# must land in $(PREFIX)/lib to keep that path valid once installed.
LIBDIR := $(PREFIX)/lib

.PHONY: all lint test check help install uninstall

all: check

help:
	@echo "Targets:"
	@echo "  make lint       - run shellcheck over lib and scripts"
	@echo "  make test       - run the bats test suite"
	@echo "  make check      - lint then test"
	@echo "  make install    - install scripts and lib under PREFIX ($(PREFIX))"
	@echo "  make uninstall  - remove an installed copy"

lint:
	$(SHELLCHECK) -x $(LIB) $(SCRIPTS)

test:
	$(BATS) test

check: lint test

install:
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(LIBDIR)
	install -m 0644 $(LIB) $(DESTDIR)$(LIBDIR)/common.sh
	install -m 0755 $(SCRIPTS) $(DESTDIR)$(BINDIR)

uninstall:
	rm -f $(addprefix $(DESTDIR)$(BINDIR)/,$(notdir $(SCRIPTS)))
	rm -f $(DESTDIR)$(LIBDIR)/common.sh
