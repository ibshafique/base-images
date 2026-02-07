# Build System Quick Reference

## Build Script DSL

Every image has a `build.sh` that sources `build-core.sh` and defines targets:

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../.shared/scripts/lib/build-core.sh"

readonly REGISTRY="${REGISTRY:-ghcr.io/ibshafique/base-images}"
readonly IMAGE_NAME="my-image"

target_build() {
    load_extension "docker-buildx"
    # ... build logic
}

run_build "$@"
```

## Parameters and Flags

| Syntax | Example | Description |
|--------|---------|-------------|
| `-Pkey=value` | `-Parch=amd64` | Build parameter |
| `--flag` | `--load` | System flag |
| `target` | `build` | Target to execute |

### Common Flags

| Flag | Description |
|------|-------------|
| `--load` | Load image to local Docker after build |
| `--push` | Push image to registry |
| `--debug` | Enable verbose debug output |
| `--no-color` | Disable colored output |
| `--sbom` | Generate SBOM attestation |
| `--provenance` | Generate provenance attestation |
| `--ignore-unfixed` | Trivy: ignore unfixed CVEs |

## Extensions

### docker-buildx

```bash
load_extension "docker-buildx"
ensure_buildx_builder
buildx_build "$image_ref" "$dockerfile" "$context" "$platform" tags_array
buildx_export_tar "$image_ref" "$dockerfile" "$context" "$platform" "$output.tar"
```

### cosign

```bash
load_extension "cosign"
cosign_sign_image "$image_ref"
cosign_sign_digest "$image_ref@$digest"
cosign_verify_image "$image_ref"
```

### trivy

```bash
load_extension "trivy"
trivy_scan_image "$image_ref" "CRITICAL,HIGH" "table"
check_critical_vulnerabilities "$image_ref"
trivy_generate_sarif "$image_ref" "report.sarif"
```

### template

```bash
load_extension "template"
declare -A vars=([KEY]="value" [OTHER]="data")
template_render "input.tmpl" "output.yaml" vars
```

## Test Framework

Test files are auto-discovered from `images/base/<name>/test/*.sh`:

```bash
#!/bin/bash
load_test_extension "docker"
load_test_extension "security"

setup() { ensure_docker_image; }
teardown() { cleanup_docker_image; }

test_runs_as_non_root() {
    assert_container_non_root
}

test_has_no_shell() {
    assert_container_has_no_shell
}
```

### Security Assertions

| Function | Description |
|----------|-------------|
| `assert_container_non_root` | Container USER is not root |
| `assert_container_user_id "65532"` | Container USER matches UID |
| `assert_container_has_no_shell` | No /bin/sh, /bin/bash, etc. |
| `assert_container_works_read_only` | Works with --read-only |
| `assert_container_works_no_caps` | Works with --cap-drop=ALL |
| `assert_no_package_managers` | No apt, yum, apk, etc. |
| `assert_image_size_under 50` | Image < 50MB |
| `assert_has_oci_labels` | Has title, description, source labels |
| `assert_label_value "key" "val"` | Label matches expected value |

### General Assertions

| Function | Description |
|----------|-------------|
| `assert_equals "a" "b"` | String equality |
| `assert_contains "haystack" "needle"` | Substring check |
| `assert_file_exists "/path"` | File exists |
| `assert_success "command"` | Exit code 0 |
| `assert_failure "command"` | Non-zero exit code |

## Runner Script

```bash
./run <module> <targets> [options]
./run --doctor          # Check dependencies
./run --list            # List available modules
./run --help            # Show help
```

## Directory Layout

```
images/base/<name>/
├── Dockerfile          # Image definition
├── build.sh            # Build script (executable)
├── build/              # Build artifacts (gitignored)
└── test/
    └── test_security.sh  # Security test suite
```
