# AI Agent Documentation

This directory contains documentation optimized for AI coding assistants working in this repository.

## Quick Start

This is a **Docker base images** repository that produces minimal, security-hardened container images for use as `FROM` bases.

### Repository Structure

```
images/base/
├── scratch-plus/          # Scratch + CA certs + nonroot user
├── distroless-static/     # Google distroless static (glibc)
├── wolfi-micro/           # Wolfi-based minimal + tzdata
└── netshell/              # Debug sidecar with network/TLS/process tools

.shared/scripts/
├── lib/                   # Build system libraries
│   ├── build-core.sh      # Build DSL engine
│   ├── build-logger.sh    # Logging
│   ├── build-utils.sh     # Utilities
│   ├── common.sh          # Core functions
│   └── ext/               # Build extensions
└── test-lib/              # Test framework
    ├── test-core.sh       # Test runner
    ├── test-utils.sh      # Assertions
    └── ext/               # Test extensions
```

### Common Commands

```bash
# Check prerequisites
./run --doctor

# Build an image locally
./run scratch-plus build --load

# Build and test
./run scratch-plus build test --load

# Build for specific architecture
./run scratch-plus build -Parch=arm64 --load

# Run tests only (requires prior build)
./run scratch-plus test

# Scan for vulnerabilities
./run scratch-plus scan

# Using Makefile (backward compatible)
make build-scratch-plus
make test-scratch-plus
make scan-scratch-plus
```

### Key Patterns

1. **Build scripts** use a Gradle-like DSL: define `target_build()`, `target_test()`, etc.
2. **Extensions** are loaded with `load_extension "name"` (docker-buildx, cosign, trivy, template)
3. **Tests** auto-discover `test_*` functions in `images/base/<name>/test/*.sh`
4. **Parameters** use `-Pname=value` format; flags use `--flag` format

## Documentation Index

- [Build System Reference](docs/build-system/quick-reference.md) - Commands, extensions, and patterns
- [Supply Chain Architecture](docs/architecture/supply-chain.md) - Security design and signing
