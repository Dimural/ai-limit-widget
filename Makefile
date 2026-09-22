# AI Limits
#
# `make verify` is the single answer to "did I break anything". Everything
# else here is a step within it or a way to install what it produced.

.DEFAULT_GOAL := help
.PHONY: help build test check verify app install uninstall run clean

APP_NAME := AILimits.app
INSTALL_DIR := /Applications

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Compile every target
	swift build

test: ## Run the test suite
	swift test

check: ## Enforce the no-network / no-stray-writes invariants
	@./scripts/check-safety.sh

verify: build test check ## Build, test, and check invariants
	@echo "\nVerified."

app: ## Assemble and sign AILimits.app
	@./scripts/build-app.sh

install: app ## Install to /Applications and launch
	@echo "==> Installing to $(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	@cp -R "$(APP_NAME)" "$(INSTALL_DIR)/$(APP_NAME)"
	@open "$(INSTALL_DIR)/$(APP_NAME)"
	@echo "\nAI Limits is running in the menu bar."
	@echo "To add the widget: right-click the desktop, choose Edit Widgets, search 'AI Limits'."

uninstall: ## Remove the app, its data, and any Claude Code hook
	@./scripts/uninstall.sh

run: ## Run the menu bar app from the build directory
	swift run AILimits

clean: ## Remove build output
	rm -rf .build "$(APP_NAME)"
