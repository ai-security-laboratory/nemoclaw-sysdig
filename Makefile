.PHONY: deploy run tui ui teardown help

SCENARIO ?=
TARGET   ?= oracle-vm

help:
	@echo "NemoClaw + Sysdig — scenario runner"
	@echo ""
	@echo "Full deploy (install + onboard + inject scenario):"
	@echo "  ./deployment.sh --scenario 01-it-ops"
	@echo ""
	@echo "Scenario lifecycle:"
	@echo "  make deploy   SCENARIO=01-it-ops TARGET=oracle-vm"
	@echo "    Installs NemoClaw, creates sandbox if needed, injects scenario files."
	@echo ""
	@echo "  make run      SCENARIO=01-it-ops TARGET=oracle-vm"
	@echo "    Sends the scenario prompt to the OpenClaw agent (task mode)."
	@echo "    Output streams live to your terminal."
	@echo ""
	@echo "  make tui      SCENARIO=01-it-ops TARGET=oracle-vm"
	@echo "    Opens the OpenClaw terminal UI inside the sandbox (interactive demo)."
	@echo ""
	@echo "  make ui       TARGET=oracle-vm"
	@echo "    Forwards the OpenClaw web UI to localhost:18789 and opens browser."
	@echo ""
	@echo "  make teardown SCENARIO=01-it-ops TARGET=oracle-vm"
	@echo "    Removes scenario files from the sandbox (keeps sandbox running)."

deploy:
	@test -n "$(SCENARIO)" || (echo "SCENARIO is required" && exit 1)
	bash deployment.sh --scenario $(SCENARIO) --target $(TARGET)

run:
	@test -n "$(SCENARIO)" || (echo "SCENARIO is required" && exit 1)
	bash test.sh --scenario $(SCENARIO) --target $(TARGET)

tui:
	@test -n "$(SCENARIO)" || (echo "SCENARIO is required" && exit 1)
	bash test.sh --scenario $(SCENARIO) --target $(TARGET) --tui

ui:
	bash test.sh --ui --target $(TARGET)

teardown:
	@test -n "$(SCENARIO)" || (echo "SCENARIO is required" && exit 1)
	bash deploy/teardown.sh --scenario $(SCENARIO) --target $(TARGET)
