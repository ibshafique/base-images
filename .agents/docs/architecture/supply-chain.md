# Supply Chain Security Architecture

## Overview

This repository implements a defense-in-depth supply chain security model for container base images.

## Security Layers

### 1. Build-Time Security

- **Minimal base images**: scratch, distroless, Wolfi — no shells, no package managers
- **Non-root users**: All images run as UID 65532 (nonroot)
- **Pinned dependencies**: Alpine/Wolfi builder stages use digest-pinned tags
- **Multi-stage builds**: Builder stages are discarded; only artifacts are copied

### 2. CI/CD Pipeline Security

```
Push to main
    │
    ├─ Build per-arch images (amd64, arm64)
    │   ├─ SLSA Build L2 provenance
    │   ├─ SBOM generation
    │   └─ Per-arch Cosign signing (keyless/Sigstore)
    │
    ├─ Create multi-arch manifest
    │   └─ Sign manifest with Cosign
    │
    └─ Vulnerability scanning
        ├─ Trivy (SARIF → GitHub Security tab)
        └─ Grype (fail on CRITICAL)
```

### 3. Signing & Verification

**Keyless signing** via Sigstore/Fulcio OIDC:

```bash
# Sign (CI)
cosign sign --yes $IMAGE@$DIGEST

# Verify (consumer)
cosign verify \
  --certificate-identity-regexp="^https://github.com/ibshafique/base-images" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  ghcr.io/ibshafique/base-images/scratch-plus:latest
```

### 4. Dockerfile Policy Enforcement

OPA/Conftest policies in `policy/base.rego`:

| Rule | Severity | Description |
|------|----------|-------------|
| USER required | deny | Must have USER directive |
| USER != root | deny | Must not run as root |
| OCI labels | deny | Must have title, description, source |
| No ADD | deny | Use COPY instead of ADD |
| :latest warning | warn | FROM :latest without digest pin |
| apt cleanup | warn | apt-get install without cleanup |
| apk --no-cache | warn | apk add without --no-cache |

```bash
# Run policy check
conftest test images/base/*/Dockerfile -p policy/base.rego
```

### 5. Runtime Security Testing

Automated security test suite validates:

- Non-root user (UID 65532)
- No shell access (/bin/sh, /bin/bash, etc.)
- Read-only filesystem compatibility
- Runs with all capabilities dropped
- No package managers present
- Minimal image size
- Required OCI labels present

## Weekly Rebuilds

Scheduled weekly rebuilds (Sunday midnight UTC) pull fresh upstream images to incorporate security patches without code changes.

## Image Inventory

| Image | Base | Size | Use Case |
|-------|------|------|----------|
| scratch-plus | scratch | ~2MB | Static Go/Rust binaries |
| distroless-static | distroless | ~5MB | Static binaries (glibc) |
| wolfi-micro | scratch (Wolfi builder) | ~10MB | Apps needing tzdata |
