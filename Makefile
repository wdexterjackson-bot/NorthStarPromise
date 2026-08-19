.PHONY: bootstrap gen test test-phone test-watch test-all lint fmt build-phone build-watch evals backend-test check clean

PACKAGES := NSPCore NSPPersistence NSPPolicy NSPMedia NSPTransfer NSPSync NSPIntelligence NSPBackendClient NSPActions NSPDesignSystem NSPTestSupport

PHONE_SCHEME := NorthStarPhone
WATCH_SCHEME := NorthStarWatch
PROJECT := NorthStar.xcodeproj

# Boot the first available simulator of a given kind ("iPhone" | "Watch") and print its UDID.
define boot_sim
$(shell xcrun simctl list devices available 2>/dev/null | grep "$(1)" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
endef

# LOCAL_ONLY=1 compiles -DLOCAL_ONLY into every package under test, so code
# behind that flag can prove it has no cloud dependency (docs/01 §4 "the
# LocalOnly build configuration"; docs/10 §9, "make test LOCAL_ONLY=1").
LOCAL_ONLY ?= 0
ifeq ($(LOCAL_ONLY),1)
SWIFT_TEST_FLAGS := -Xswiftc -DLOCAL_ONLY
else
SWIFT_TEST_FLAGS :=
endif

bootstrap:
	@command -v xcodegen >/dev/null || brew install xcodegen
	@command -v swiftlint >/dev/null || brew install swiftlint
	@command -v swift-format >/dev/null || brew install swift-format
	@$(MAKE) gen
	@echo "bootstrap complete"

gen:
	xcodegen generate

test:
	@for pkg in $(PACKAGES); do \
		echo "== swift test: $$pkg =="; \
		(cd Packages/$$pkg && swift test $(SWIFT_TEST_FLAGS)) || exit 1; \
	done

test-phone: gen
	@sim="$(call boot_sim,iPhone)"; \
	test -n "$$sim" || { echo "no iPhone simulator available"; exit 1; }; \
	xcodebuild test -project $(PROJECT) -scheme $(PHONE_SCHEME) -destination "id=$$sim"

test-watch: gen
	@sim="$(call boot_sim,Watch)"; \
	test -n "$$sim" || { echo "no Watch simulator available"; exit 1; }; \
	xcodebuild test -project $(PROJECT) -scheme $(WATCH_SCHEME) -destination "id=$$sim"

test-all: test test-phone test-watch

lint:
	@if command -v swiftlint >/dev/null; then swiftlint --strict; else echo "swiftlint not installed — run make bootstrap"; exit 1; fi
	@if command -v swift-format >/dev/null; then swift-format lint --strict --recursive Packages App; else echo "swift-format not installed — run make bootstrap"; exit 1; fi

fmt:
	swift-format format --in-place --recursive Packages App

build-phone: gen
	xcodebuild build -project $(PROJECT) -scheme $(PHONE_SCHEME) -destination 'generic/platform=iOS Simulator'

build-watch: gen
	xcodebuild build -project $(PROJECT) -scheme $(WATCH_SCHEME) -destination 'generic/platform=watchOS Simulator'

evals:
	@echo "Tools/evals not yet implemented (NSP-098)"

backend-test:
	@echo "Backend/ not yet implemented (NSP-094)"

check: lint test test-phone test-watch evals

clean:
	rm -rf $(PROJECT)
	@for pkg in $(PACKAGES); do rm -rf Packages/$$pkg/.build; done
