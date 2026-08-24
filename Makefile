# claude-code-statusline — dev tasks.
#
#   make install    put THIS tree's statusline.sh (+ the usage-insight skill)
#                   into ~/.claude and point settings.json at it, keeping the
#                   flags already on the command
#   make status     what is installed vs what is in the tree
#   make check      shellcheck + the bats suite
#
# install shells out to install.sh with STATUSLINE_SRC set, so the local path
# and the public curl one-liner share one installer and cannot drift.

SHELL := /bin/bash
.DEFAULT_GOAL := help

CLAUDE_CONFIG_DIR ?= $(HOME)/.claude
DEST  := $(CLAUDE_CONFIG_DIR)/statusline.sh
SKILL := $(CLAUDE_CONFIG_DIR)/skills/usage-insight/SKILL.md
SETTINGS := $(CLAUDE_CONFIG_DIR)/settings.json
BATS  := npm exec --yes bats --

.PHONY: help install install-check uninstall status diff test lint check

help:
	@echo "claude-code-statusline"
	@echo
	@echo "  make install        install this tree into $(CLAUDE_CONFIG_DIR)"
	@echo "  make install-check  run check first, then install"
	@echo "  make status         installed vs tree, settings, skill"
	@echo "  make diff           diff the installed copy against this tree"
	@echo "  make uninstall      remove the script, the skill and the setting"
	@echo "  make test           bats t/"
	@echo "  make lint           shellcheck -S error"
	@echo "  make check          lint + test"
	@echo
	@echo "  CLAUDE_CONFIG_DIR=... to target another config dir"
	@echo "  STATUSLINE_SKILL=0    to skip the usage-insight skill"

install:
	@STATUSLINE_SRC="$(CURDIR)" CLAUDE_CONFIG_DIR="$(CLAUDE_CONFIG_DIR)" ./install.sh

# The one you want when the tree has uncommitted work: a statusline that
# renders wrong is worse than one that is a version behind.
install-check: check install

uninstall:
	@rm -f "$(DEST)"; echo "removed $(DEST)"
	@rm -rf "$(dir $(SKILL))"; echo "removed $(dir $(SKILL))"
	@if [ -f "$(SETTINGS)" ] && jq -e '.statusLine' "$(SETTINGS)" >/dev/null 2>&1; then \
		tmp="$(SETTINGS).tmp.$$$$"; \
		jq 'del(.statusLine)' "$(SETTINGS)" > "$$tmp" && mv -f "$$tmp" "$(SETTINGS)"; \
		echo "removed statusLine from $(SETTINGS)"; \
	fi

status:
	@src=$$(sha256sum statusline.sh | cut -c1-12); \
	printf 'tree       statusline.sh  %s bytes  %s  (%s%s)\n' \
	    "$$(wc -c < statusline.sh)" "$$src" \
	    "$$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')" \
	    "$$(git diff --quiet -- statusline.sh 2>/dev/null || echo ', dirty')"; \
	if [ -f "$(DEST)" ]; then \
	    dst=$$(sha256sum "$(DEST)" | cut -c1-12); \
	    printf 'installed  %s  %s bytes  %s  %s\n' "$(DEST)" \
	        "$$(wc -c < "$(DEST)")" "$$dst" \
	        "$$([ "$$src" = "$$dst" ] && echo 'in sync' || echo 'STALE — make install')"; \
	else \
	    printf 'installed  %s  MISSING — make install\n' "$(DEST)"; \
	fi; \
	if [ -f "$(SETTINGS)" ]; then \
	    printf 'settings   %s\n' "$$(jq -r '.statusLine.command // "(no statusLine — make install)"' "$(SETTINGS)")"; \
	else \
	    printf 'settings   %s MISSING\n' "$(SETTINGS)"; \
	fi; \
	if [ -f "$(SKILL)" ]; then \
	    printf 'skill      %s  %s\n' "$(SKILL)" \
	        "$$(cmp -s skills/usage-insight/SKILL.md "$(SKILL)" && echo 'in sync' || echo 'STALE — make install')"; \
	else \
	    printf 'skill      %s  not installed\n' "$(SKILL)"; \
	fi

diff:
	@diff -u "$(DEST)" statusline.sh && echo "installed copy matches the tree"

test:
	@$(BATS) t/

lint:
	@shellcheck -S error statusline.sh install.sh

check: lint test
