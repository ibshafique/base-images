# Makefile for Secure Container Foundations

REGISTRY := ghcr.io/ibshafique/base-images
PLATFORM ?= linux/amd64  # Single platform for local builds
MULTI_PLATFORMS := linux/amd64,linux/arm64  # Multi-platform for CI

# Base images
BASE_IMAGES := scratch-plus distroless-static wolfi-micro

# Demo images
DEMO_IMAGES := hello-secure

ALL_IMAGES := $(BASE_IMAGES) $(DEMO_IMAGES)

.PHONY: help
help:
	@echo "Secure Container Foundations - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  build-<image>          Build image locally (single platform)"
	@echo "  build-<image>-multi    Build multi-platform image (requires push)"
	@echo "  scan-<image>           Scan image for vulnerabilities"
	@echo "  test-<image>           Test image functionality"
	@echo "  policy-check           Validate all Dockerfiles"
	@echo "  build-all              Build all images"
	@echo "  test-reproducible      Test build reproducibility"
	@echo ""
	@echo "Examples:"
	@echo "  make build-scratch-plus"
	@echo "  make scan-scratch-plus"
	@echo "  make test-reproducible IMAGE=scratch-plus"
	@echo ""
	@echo "Environment:"
	@echo "  PLATFORM=$(PLATFORM)"
	@echo "  REGISTRY=$(REGISTRY)"

# Build targets (single platform, local)
.PHONY: build-%
build-%:
	@echo "Building $* for $(PLATFORM)..."
	@if echo "$(BASE_IMAGES)" | grep -qw "$*"; then \
		docker buildx build \
			--platform $(PLATFORM) \
			--tag $(REGISTRY)/$*:latest \
			--cache-from type=registry,ref=$(REGISTRY)/$*:cache \
			--cache-to type=registry,ref=$(REGISTRY)/$*:cache,mode=max \
			--load \
			images/base/$*/; \
	elif echo "$(DEMO_IMAGES)" | grep -qw "$*"; then \
		docker buildx build \
			--platform $(PLATFORM) \
			--tag $(REGISTRY)/$*:latest \
			--cache-from type=registry,ref=$(REGISTRY)/$*:cache \
			--cache-to type=registry,ref=$(REGISTRY)/$*:cache,mode=max \
			--load \
			images/demo/$*/; \
	else \
		echo "Unknown image: $*"; exit 1; \
	fi

# Build targets (multi-platform, push required)
.PHONY: build-%-multi
build-%-multi:
	@echo "Building $* for $(MULTI_PLATFORMS) (will push to registry)..."
	@if echo "$(BASE_IMAGES)" | grep -qw "$*"; then \
		docker buildx build \
			--platform $(MULTI_PLATFORMS) \
			--tag $(REGISTRY)/$*:latest \
			--cache-from type=registry,ref=$(REGISTRY)/$*:cache \
			--cache-to type=registry,ref=$(REGISTRY)/$*:cache,mode=max \
			--push \
			images/base/$*/; \
	elif echo "$(DEMO_IMAGES)" | grep -qw "$*"; then \
		docker buildx build \
			--platform $(MULTI_PLATFORMS) \
			--tag $(REGISTRY)/$*:latest \
			--cache-from type=registry,ref=$(REGISTRY)/$*:cache \
			--cache-to type=registry,ref=$(REGISTRY)/$*:cache,mode=max \
			--push \
			images/demo/$*/; \
	else \
		echo "Unknown image: $*"; exit 1; \
	fi

# Scan targets
.PHONY: scan-%
scan-%:
	@echo "Scanning $* with Trivy..."
	@trivy image --severity CRITICAL,HIGH $(REGISTRY)/$*:latest
	@echo ""
	@echo "Scanning $* with Grype..."
	@grype $(REGISTRY)/$*:latest --fail-on critical

# Test targets
.PHONY: test-%
test-%:
	@echo "Testing $*..."
	@scripts/test-image.sh $(REGISTRY)/$*:latest

# Policy check
.PHONY: policy-check
policy-check:
	@echo "Validating Dockerfiles with Conftest..."
	@find images -name Dockerfile -exec echo "Checking {}..." \; -exec conftest test {} -p policy/base.rego \;

# Build all images
.PHONY: build-all
build-all:
	@for image in $(ALL_IMAGES); do \
		$(MAKE) build-$$image || exit 1; \
	done

# Test all images
.PHONY: test-all
test-all:
	@for image in $(ALL_IMAGES); do \
		$(MAKE) test-$$image || exit 1; \
	done

# Test reproducibility
.PHONY: test-reproducible
test-reproducible:
	@if [ -z "$(IMAGE)" ]; then \
		echo "Usage: make test-reproducible IMAGE=scratch-plus"; \
		exit 1; \
	fi
	@scripts/verify-reproducibility.sh $(IMAGE)

# Clean build cache
.PHONY: clean
clean:
	@echo "Cleaning build cache..."
	@docker buildx prune -f
	@docker image prune -f

# Setup buildx (run once)
.PHONY: setup
setup:
	@echo "Setting up Docker Buildx..."
	@docker buildx create --name container-builder --use || true
	@docker buildx inspect --bootstrap

.PHONY: teardown
teardown:
	@echo "Removing Docker Buildx builder..."
	@docker buildx rm container-builder || true
