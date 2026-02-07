# Makefile for Secure Container Foundations
# Self-contained: calls docker directly, works on any shell (no bash 4+ required)
# For the full build DSL, use: ./run <module> <targets> [options] (requires bash 4+)

REGISTRY := ghcr.io/ibshafique/base-images
PLATFORM ?= linux/amd64
MULTI_PLATFORMS := linux/amd64,linux/arm64

BASE_IMAGES := scratch-plus distroless-static wolfi-micro
ALL_IMAGES := $(BASE_IMAGES)

.PHONY: help
help:
	@echo "Secure Container Foundations - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  build-<image>          Build image locally (single platform)"
	@echo "  build-<image>-multi    Build multi-platform image (requires push)"
	@echo "  test-<image>           Run security tests for image"
	@echo "  scan-<image>           Scan image for vulnerabilities"
	@echo "  sign-<image>           Sign image with Cosign"
	@echo "  policy-check           Validate all Dockerfiles with OPA"
	@echo "  build-all              Build all images"
	@echo "  test-all               Test all images"
	@echo "  doctor                 Check build dependencies"
	@echo "  test-reproducible      Test build reproducibility"
	@echo ""
	@echo "Images: $(BASE_IMAGES)"
	@echo ""
	@echo "Examples:"
	@echo "  make build-scratch-plus"
	@echo "  make test-scratch-plus"
	@echo "  make scan-scratch-plus"
	@echo "  make build-all"
	@echo "  make doctor"
	@echo ""
	@echo "Environment:"
	@echo "  PLATFORM=$(PLATFORM)"
	@echo "  REGISTRY=$(REGISTRY)"

# ============================================================================
# Doctor: check prerequisites
# ============================================================================

.PHONY: doctor
doctor:
	@echo "=== Build Environment Check ==="
	@echo ""
	@echo "Required:"
	@command -v docker >/dev/null 2>&1 \
		&& echo "  [OK] docker ($$(docker --version 2>/dev/null | head -1))" \
		|| echo "  [MISSING] docker"
	@docker buildx version >/dev/null 2>&1 \
		&& echo "  [OK] docker buildx ($$(docker buildx version 2>/dev/null | head -1))" \
		|| echo "  [MISSING] docker buildx"
	@echo ""
	@echo "Optional:"
	@command -v cosign >/dev/null 2>&1 \
		&& echo "  [OK] cosign - image signing" \
		|| echo "  [--] cosign - image signing (not installed)"
	@command -v trivy >/dev/null 2>&1 \
		&& echo "  [OK] trivy - vulnerability scanning" \
		|| echo "  [--] trivy - vulnerability scanning (not installed)"
	@command -v grype >/dev/null 2>&1 \
		&& echo "  [OK] grype - vulnerability scanning" \
		|| echo "  [--] grype - vulnerability scanning (not installed)"
	@command -v conftest >/dev/null 2>&1 \
		&& echo "  [OK] conftest - OPA policy testing" \
		|| echo "  [--] conftest - OPA policy testing (not installed)"
	@echo ""
	@echo "Platform: $$(uname -s) $$(uname -m)"

# ============================================================================
# Build targets
# ============================================================================

.PHONY: build-%
build-%:
	@if echo "$(BASE_IMAGES)" | grep -qw "$*"; then \
		echo "Building $* for $(PLATFORM)..."; \
		docker buildx build \
			--platform $(PLATFORM) \
			--tag $(REGISTRY)/$*:latest \
			--load \
			images/base/$*/; \
	else \
		echo "Unknown image: $*. Available: $(BASE_IMAGES)"; exit 1; \
	fi

.PHONY: build-%-multi
build-%-multi:
	@if echo "$(BASE_IMAGES)" | grep -qw "$*"; then \
		echo "Building $* for $(MULTI_PLATFORMS) (pushing to registry)..."; \
		docker buildx build \
			--platform $(MULTI_PLATFORMS) \
			--tag $(REGISTRY)/$*:latest \
			--push \
			images/base/$*/; \
	else \
		echo "Unknown image: $*. Available: $(BASE_IMAGES)"; exit 1; \
	fi

.PHONY: build-all
build-all:
	@for image in $(ALL_IMAGES); do \
		$(MAKE) build-$$image || exit 1; \
	done

# ============================================================================
# Test targets
# ============================================================================

.PHONY: test-%
test-%:
	@if echo "$(BASE_IMAGES)" | grep -qw "$*"; then \
		echo "Testing $*..."; \
		scripts/test-image.sh "$(REGISTRY)/$*:latest"; \
	else \
		echo "Unknown image: $*. Available: $(BASE_IMAGES)"; exit 1; \
	fi

.PHONY: test-all
test-all:
	@for image in $(ALL_IMAGES); do \
		$(MAKE) test-$$image || exit 1; \
	done

.PHONY: test-reproducible
test-reproducible:
	@if [ -z "$(IMAGE)" ]; then \
		echo "Usage: make test-reproducible IMAGE=scratch-plus"; \
		exit 1; \
	fi
	@scripts/verify-reproducibility.sh $(IMAGE)

# ============================================================================
# Scan targets
# ============================================================================

.PHONY: scan-%
scan-%:
	@if echo "$(BASE_IMAGES)" | grep -qw "$*"; then \
		echo "Scanning $*..."; \
		if command -v trivy >/dev/null 2>&1; then \
			echo "--- Trivy ---"; \
			trivy image --severity CRITICAL,HIGH $(REGISTRY)/$*:latest; \
		fi; \
		if command -v grype >/dev/null 2>&1; then \
			echo "--- Grype ---"; \
			grype $(REGISTRY)/$*:latest --fail-on critical; \
		fi; \
		if ! command -v trivy >/dev/null 2>&1 && ! command -v grype >/dev/null 2>&1; then \
			echo "No scanner found. Install trivy or grype."; exit 1; \
		fi; \
	else \
		echo "Unknown image: $*. Available: $(BASE_IMAGES)"; exit 1; \
	fi

# ============================================================================
# Sign targets
# ============================================================================

.PHONY: sign-%
sign-%:
	@if echo "$(BASE_IMAGES)" | grep -qw "$*"; then \
		if ! command -v cosign >/dev/null 2>&1; then \
			echo "cosign not found. Install: brew install cosign"; exit 1; \
		fi; \
		echo "Signing $*..."; \
		cosign sign --yes $(REGISTRY)/$*:latest; \
	else \
		echo "Unknown image: $*. Available: $(BASE_IMAGES)"; exit 1; \
	fi

# ============================================================================
# Policy check
# ============================================================================

.PHONY: policy-check
policy-check:
	@if ! command -v conftest >/dev/null 2>&1; then \
		echo "conftest not found. Install: brew install conftest"; exit 1; \
	fi
	@echo "Validating Dockerfiles..."
	@for image in $(BASE_IMAGES); do \
		echo "  Checking images/base/$$image/Dockerfile..."; \
		conftest test images/base/$$image/Dockerfile -p policy/base.rego || exit 1; \
	done

# ============================================================================
# Setup / Cleanup
# ============================================================================

.PHONY: setup
setup:
	@echo "Setting up Docker Buildx..."
	@docker buildx create --name container-builder --use 2>/dev/null || docker buildx use container-builder 2>/dev/null || true
	@docker buildx inspect --bootstrap

.PHONY: teardown
teardown:
	@echo "Removing Docker Buildx builder..."
	@docker buildx rm container-builder 2>/dev/null || true

.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	@for image in $(BASE_IMAGES); do \
		rm -rf images/base/$$image/build; \
	done
	@echo "Removing built images..."
	@for image in $(BASE_IMAGES); do \
		docker rmi $(REGISTRY)/$$image:latest 2>/dev/null || true; \
	done
	@echo "Cleaning Docker build cache..."
	@docker buildx prune -f
	@docker image prune -f
