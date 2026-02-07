APP_NAME := hello-secure
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
REGISTRY := ghcr.io/ibshafique/base-images

.PHONY: build
build:
	docker build -t $(REGISTRY)/$(APP_NAME):$(VERSION) \
		--build-arg VERSION=$(VERSION) \
		-f ../Dockerfile.template .

.PHONY: run
run:
	docker run -p 8080:8080 $(REGISTRY)/$(APP_NAME):$(VERSION)

.PHONY: test
test:
	go test ./...
