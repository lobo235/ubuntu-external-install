.PHONY: help lint test check

help:
	@printf '%s\n' \
		'Targets:' \
		'  make lint   Run shellcheck' \
		'  make test   Run non-destructive synthetic tests' \
		'  make check  Run lint and tests'

lint:
	shellcheck install-ubuntu-external.sh tests/run.sh

test:
	tests/run.sh

check: lint test
