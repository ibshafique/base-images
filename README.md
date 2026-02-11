# Secure Container Foundations

An educational reference implementation demonstrating how to build supply-chain security into container images from scratch.

## Features

- Minimal, hardened base images (scratch-plus, distroless-static, wolfi-micro, netshell)
- Multi-arch builds (amd64/arm64) with automated CI/CD
- Supply-chain security: Cosign signing, SBOM generation, SLSA Build L2 provenance
- OPA/Conftest policy enforcement for Dockerfiles
- Vulnerability scanning with Trivy and Grype
- Build reproducibility verification

## Why This Repo?

### Isn't This Redundant?

**Yes and no.** Production-grade minimal images already exist:

- **[Chainguard Images](https://www.chainguard.dev/chainguard-images)**: Enterprise-grade, continuously updated, FIPS-validated
- **[Google Distroless](https://github.com/GoogleContainerTools/distroless)**: Battle-tested, maintained by Google
- **[Wolfi](https://github.com/wolfi-dev)**: Modern, secure, APK-based

**So why this repo?**

### This is a Learning Resource

This repository is an **educational reference implementation** demonstrating how to build supply-chain security into container images from scratch.

**Use this repo to**:
- Learn how minimal images are constructed
- Understand supply-chain security controls (SBOM, signing, provenance)
- See working CI/CD security automation
- Study threat modeling for containers
- Customize base images for specific needs
- Teach container security principles

**Do NOT use this repo for**:
- Production workloads requiring vendor support
- Enterprise compliance (FedRAMP, HIPAA, PCI-DSS)
- Automatic security updates
- Long-term support guarantees

### Comparison

| Feature | Chainguard Images | Google Distroless | This Repo |
|---------|------------------|-------------------|-----------|
| **Production-ready** | Yes | Yes | Educational |
| **Vendor support** | Yes | Community | No |
| **Auto updates** | Daily | Periodic | Weekly |
| **FIPS validated** | Yes | No | No |
| **SBOM included** | Yes | Partial | Yes |
| **Signed images** | Yes | Yes | Yes |
| **Open source** | Partial | Yes | Yes |
| **Documented build** | Limited | Limited | Extensive |
| **Supply chain transparency** | Commercial | Good | Full |
| **Learning resource** | No | Limited | Yes |

### Recommendation

**For production**: Use Chainguard Images or Google Distroless.

**For learning**: Use this repo to understand *how* they work, then deploy production images from established vendors.

### This Repo Fills a Gap

Existing solutions are production-focused but lack:
- **Teaching materials**: How are minimal images actually built?
- **Supply chain transparency**: Where do these bytes come from?
- **Security automation examples**: How do I implement SLSA/SBOM in CI/CD?
- **Threat modeling**: What are the actual risks?

This repo provides **working, documented examples** of these concepts.

### Intended Audience

- **Security engineers** learning supply-chain security
- **Platform engineers** building internal container platforms
- **Students/researchers** studying container security
- **Open-source maintainers** seeking secure base images

Not intended for:
- DevOps teams seeking drop-in production images (use Chainguard/Distroless)
- Enterprises requiring compliance certifications (use commercial vendors)

## Images

### Base Images

| Image | Base | Size | Use Case |
|-------|------|------|----------|
| `scratch-plus` | scratch | ~400 KB | Static binaries (Go, Rust) |
| `distroless-static` | Distroless | ~6 MB | Static binaries (glibc) |
| `wolfi-micro` | Wolfi/scratch | ~6 MB | Static binaries + timezone data |
| `netshell` | Alpine | ~35 MB | Kubernetes debug/troubleshooting sidecar |

### Templates

| Template | Description |
|----------|-------------|
| `go-static` | Template for building static Go applications |

## Quick Start

### Prerequisites

- Docker with Buildx
- Make
- (Optional) Cosign, Trivy, Grype, Conftest for security tooling

```bash
# Check what you have installed
make doctor
```

### Build and Test

```bash
# Set up Docker Buildx builder (one-time)
make setup

# Build a single image
make build-scratch-plus

# Build all images
make build-all

# Run security tests
make test-scratch-plus

# Scan for vulnerabilities (requires trivy or grype)
make scan-scratch-plus

# Build for multiple architectures (requires registry push)
make build-scratch-plus-multi
```

### Advanced: Build DSL

The repository also includes a Gradle-like bash build system (requires bash 4+):

```bash
./run --doctor                              # Check environment
./run scratch-plus build --load             # Build and load to Docker
./run scratch-plus build test --load        # Build + test
./run scratch-plus build -Parch=arm64       # Build for ARM64
./run wolfi-micro clean build test --debug  # Full rebuild with debug
```

## Supply Chain Security

### SLSA Provenance

**Level**: SLSA Build L2

This repository achieves SLSA Build Level 2 through BuildKit's built-in provenance generation.

**L2 Requirements Met**:
- Provenance generated by build platform (GitHub Actions + BuildKit)
- Provenance authenticated (signed with Cosign keyless)
- Build service (GitHub Actions) generates provenance
- Provenance includes build instructions

**Why Not L3?** Achieving true SLSA Build L3 requires hermetic builds, `slsa-github-generator`, and fully isolated build environments. For an educational project, L2 provides sufficient supply-chain transparency while remaining understandable.

### SBOM Generation

**Format**: SPDX 2.3 (JSON)
**Tool**: BuildKit (Docker Buildx)

Automatically generated during build when `sbom: true` is set in the workflow.

```bash
# View SBOM attestation
cosign verify-attestation --type spdx \
  --certificate-identity-regexp="https://github.com/ibshafique/base-images" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  ghcr.io/ibshafique/base-images/scratch-plus:latest \
  | jq -r '.payload' | base64 -d | jq

# Via syft
syft packages ghcr.io/ibshafique/base-images/scratch-plus:latest

# Via docker scout
docker scout sbom ghcr.io/ibshafique/base-images/scratch-plus:latest
```

### Image Signing

All images are signed with Cosign keyless (Sigstore) in CI/CD. Verify signatures:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/ibshafique/base-images" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  ghcr.io/ibshafique/base-images/scratch-plus:latest
```

## Project Structure

```
.
├── .github/workflows/
│   ├── build-base.yml          # Production CI/CD: build, sign, scan (multi-arch)
│   ├── build-base-dev.yml      # Dev CI: build + test on branches/PRs (amd64 only)
│   └── weekly-rebuild.yml      # Weekly rebuild for upstream security patches
├── .shared/scripts/
│   ├── lib/                    # Build system core (build-core, logger, utils)
│   │   └── ext/                # Extensions (docker-buildx, cosign, trivy, template)
│   └── test-lib/               # Test framework (test-core, utils)
│       └── ext/                # Test extensions (docker, security assertions)
├── images/
│   ├── base/
│   │   ├── scratch-plus/       # Minimal scratch + CA certs + nonroot
│   │   ├── distroless-static/  # Google Distroless (nonroot)
│   │   ├── wolfi-micro/        # Wolfi-based minimal + tzdata
│   │   └── netshell/           # Debug sidecar with network/TLS/process tools
│   │   (each contains: Dockerfile, build.sh, test/)
│   └── templates/
│       └── go-static/          # Go application template
├── scripts/
│   ├── test-image.sh           # Standalone security validation tests
│   └── verify-reproducibility.sh # Build reproducibility check
├── policy/
│   └── base.rego               # OPA/Conftest Dockerfile policy rules
├── run                         # Build system runner (bash 4+)
├── Makefile                    # Build system (works on any shell)
├── SECURITY.md                 # Security policy & SLSA/SBOM details
└── IMPLEMENTATION.md           # Design notes and corrected implementations
```

## CI/CD Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `build-base.yml` | Push to `main`, manual | Multi-arch build, sign, scan, push to GHCR |
| `build-base-dev.yml` | Push to branches, PRs | amd64-only build + test + lint (no push, no signing) |
| `weekly-rebuild.yml` | Sunday midnight UTC, manual | Triggers `build-base.yml` for all images to pick up upstream patches |

## License

MIT
