# opsbox - a small toolkit of bash ops helpers.

SHELL := /bin/bash

# Allow overriding the tool locations (handy in CI or a vendored checkout).
SHELLCHECK ?= shellcheck
BATS ?= bats

SCRIPTS := bin/opsbox bin/backup bin/disk-report bin/healthcheck bin/logrotate-lite bin/prune-old
LIB := lib/common.sh

.PHONY: all lint test check help

all: check

help:
	@echo "Targets:"
	@echo "  make lint   - run shellcheck over lib and scripts"
	@echo "  make test   - run the bats test suite"
	@echo "  make check  - lint then test"

lint:
	$(SHELLCHECK) -x $(LIB) $(SCRIPTS)

test:
	$(BATS) test

check: lint test
