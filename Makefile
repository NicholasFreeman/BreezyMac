# BreezyMac — developer workflow
#
# Local DEBUG builds with ad-hoc signing only (per project scope). Release
# signing/notarization is deferred to a later milestone.

PROJECT      := BreezyMac.xcodeproj
SCHEME       := BreezyMac
CONFIG       := Debug
DERIVED      := build/DerivedData
APP          := $(DERIVED)/Build/Products/$(CONFIG)/BreezyMac.app
DEST         := platform=macOS,arch=arm64

.DEFAULT_GOAL := build

.PHONY: help gen build run clean icons regen dump-helper open-loginitems

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

gen: ## Regenerate the Xcode project from project.yml
	xcodegen generate

build: gen ## Generate project and build (Debug, ad-hoc signed)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination '$(DEST)' -derivedDataPath $(DERIVED) build

run: build ## Build then launch the app (status-bar item appears)
	@echo "Launching $(APP)"
	open "$(APP)"

icons: ## Regenerate icon assets from assets/app_icon.png
	./scripts/generate-icons.sh

regen: clean gen ## Clean and regenerate the project

clean: ## Remove generated project and build products
	rm -rf $(DERIVED) BreezyMac.xcodeproj

open-loginitems: ## Open System Settings → Login Items (to approve the helper)
	open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

dump-helper: ## Print the current SMAppService/launchd state of the helper
	@echo "launchctl:"; launchctl print system/org.WhoCo.BreezyMac.Helper 2>/dev/null | head -20 || echo "  (not loaded)"
