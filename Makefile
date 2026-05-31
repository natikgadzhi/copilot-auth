.PHONY: contrib install-hooks generate format lint-format test build clean where authenticate check dmg install uninstall

SWIFT_FORMAT_PATHS = App Packages
# Extra args appended to the xcodebuild line. CI sets this to disable signing
# (CODE_SIGNING_ALLOWED=NO) since the runner has no Developer ID certs.
XCODEBUILD_FLAGS ?=

PROJECT = CopilotAuth.xcodeproj
SCHEME = CopilotAuth
CONFIG = Debug
# Fixed build location so the .app/binary paths are static (no awk needed).
DERIVED = .build-xcode
APP = $(DERIVED)/Build/Products/$(CONFIG)/CopilotAuth.app
BIN = $(APP)/Contents/MacOS/CopilotAuth

# Where `make install` puts things — the same layout a Homebrew cask produces:
# the .app under /Applications, and a `copilot-auth` symlink to the in-bundle
# binary in a directory on PATH (Homebrew's bin).
APP_INSTALL_DIR ?= /Applications
BIN_INSTALL_DIR ?= $(shell brew --prefix 2>/dev/null || echo /usr/local)/bin

contrib:
	@echo "Installing development dependencies..."
	brew install xcodegen
	@$(MAKE) install-hooks
	@$(MAKE) generate

install-hooks:
	@git config core.hooksPath .githooks
	@echo "Configured git hooks to use .githooks/"

generate:
	xcodegen generate

format:
	swift-format format --in-place --recursive --configuration .swift-format $(SWIFT_FORMAT_PATHS)

lint-format:
	swift-format lint --strict --recursive --configuration .swift-format $(SWIFT_FORMAT_PATHS)

test:
	swift test --package-path Packages/CopilotAuthKit

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) $(XCODEBUILD_FLAGS) build

# Delete build artifacts. Leaves the generated .xcodeproj (cheap to regenerate).
clean:
	rm -rf $(DERIVED)

# Print the built binary's path so you can run it directly.
where:
	@echo $(BIN)

# Interactive Copilot login. Equivalent to running the app in Xcode (⌘R), which
# is the most reliable way to see the login page + console logs.
authenticate: build
	open -n -W $(APP) --args authenticate

# Headless session check (plain HTTP, no GUI). Leading '-' so a non-zero status
# (expired/no-session) just prints its message instead of make's error noise.
check: build
	-$(BIN) check

# Build a signed + notarized + stapled .dmg. Needs a Developer ID Application
# identity and notary credentials — see scripts/build-dmg.sh for the env vars.
dmg:
	scripts/build-dmg.sh

# Install locally the way a Homebrew cask would: copy the .app to /Applications
# and symlink the in-bundle binary onto PATH as `copilot-auth`. Build it signed
# (the default, Developer ID) so the Keychain item stays accessible across runs.
# Then `copilot-auth authenticate` opens the login window and `copilot-auth
# check` works from any terminal. Override CONFIG=Release to test the shipping
# build.
install: build
	rm -rf "$(APP_INSTALL_DIR)/CopilotAuth.app"
	ditto "$(APP)" "$(APP_INSTALL_DIR)/CopilotAuth.app"
	mkdir -p "$(BIN_INSTALL_DIR)"
	ln -sf "$(APP_INSTALL_DIR)/CopilotAuth.app/Contents/MacOS/CopilotAuth" "$(BIN_INSTALL_DIR)/copilot-auth"
	@echo "Installed CopilotAuth.app -> $(APP_INSTALL_DIR) and copilot-auth -> $(BIN_INSTALL_DIR)"
	@echo "Try: copilot-auth --help   |   copilot-auth authenticate"

uninstall:
	rm -rf "$(APP_INSTALL_DIR)/CopilotAuth.app"
	rm -f "$(BIN_INSTALL_DIR)/copilot-auth"
	@echo "Removed CopilotAuth.app and the copilot-auth symlink."
