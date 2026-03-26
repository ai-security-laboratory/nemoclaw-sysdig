.PHONY: deploy teardown test lint fmt help

SCENARIO ?=
TARGET   ?=

help:
	@echo "Usage:"
	@echo "  make deploy   SCENARIO=01-security-triage TARGET=my-oracle-vm"
	@echo "  make teardown SCENARIO=01-security-triage TARGET=my-oracle-vm"
	@echo "  make test     SCENARIO=01-security-triage [TARGET=my-oracle-vm]"
	@echo "  make test-all"
	@echo "  make lint"
	@echo "  make fmt"

deploy:
	@test -n "$(SCENARIO)" || (echo "SCENARIO is required" && exit 1)
	@test -n "$(TARGET)"   || (echo "TARGET is required" && exit 1)
	bash deploy/deploy.sh --scenario $(SCENARIO) --target $(TARGET)

teardown:
	@test -n "$(SCENARIO)" || (echo "SCENARIO is required" && exit 1)
	@test -n "$(TARGET)"   || (echo "TARGET is required" && exit 1)
	bash deploy/teardown.sh --scenario $(SCENARIO) --target $(TARGET)

test:
	@test -n "$(SCENARIO)" || (echo "SCENARIO is required" && exit 1)
	@if [ -n "$(TARGET)" ]; then \
		echo "Running tests on remote VM $(TARGET)..."; \
		bash deploy/lib/run-tests-remote.sh --scenario $(SCENARIO) --target $(TARGET); \
	else \
		echo "Running tests locally for scenario $(SCENARIO)..."; \
		cd scenarios/$(SCENARIO) && python -m pytest tests/ -v; \
	fi

test-all:
	@for dir in scenarios/*/; do \
		scenario=$$(basename $$dir); \
		echo "=== Testing $$scenario ==="; \
		cd $$dir && python -m pytest tests/ -v; \
		cd ../..; \
	done

lint:
	python -m ruff check scenarios/ tests/

fmt:
	python -m ruff format scenarios/ tests/
