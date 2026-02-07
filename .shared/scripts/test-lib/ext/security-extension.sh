#!/bin/bash
# Security Test Extension - Security-specific test assertions for container images
# Provides functions for verifying non-root users, no shell, minimal images, etc.
#
# Usage:
#   load_test_extension "security"
#   assert_container_non_root
#   assert_container_has_no_shell
#   assert_no_package_managers

# ============================================================================
# User Security
# ============================================================================

# Assert container runs as non-root user
assert_container_non_root() {
    local message="${1:-Container should run as non-root}"

    if [[ -z "${IMAGE_NAME:-}" ]]; then
        log_error "IMAGE_NAME not set - call ensure_docker_image first"
        return 1
    fi

    if ! _set_docker_cmd; then
        log_error "No docker-compatible CLI found"
        return 1
    fi

    local user
    user=$($DOCKER_CMD inspect "${IMAGE_NAME}" | jq -r '.[0].Config.User // "root"' 2>/dev/null)

    if [[ -z "$user" ]] || [[ "$user" == "root" ]] || [[ "$user" == "0" ]] || [[ "$user" == "0:0" ]]; then
        log_error "FAIL $message (user: ${user:-empty})"
        return 1
    fi

    log_debug "PASS $message (user: $user)"
    return 0
}

# Assert container user matches specific UID
assert_container_user_id() {
    local expected_uid="$1"
    local message="${2:-Container should run as UID ${expected_uid}}"

    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    local user
    user=$($DOCKER_CMD inspect "${IMAGE_NAME}" | jq -r '.[0].Config.User // "root"' 2>/dev/null)

    # Extract UID (handles "65532", "65532:65532", "nonroot")
    local uid="${user%%:*}"

    if [[ "$uid" == "$expected_uid" ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message (actual: $uid)"
        return 1
    fi
}

# ============================================================================
# Shell Security
# ============================================================================

# Assert container has no shell (no /bin/sh or /bin/bash)
assert_container_has_no_shell() {
    local message="${1:-Container should have no shell}"

    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    local has_shell=false

    for shell in /bin/sh /bin/bash /bin/ash /bin/zsh; do
        if $DOCKER_CMD run --rm --network none --entrypoint "$shell" "${IMAGE_NAME}" -c "exit 0" 2>/dev/null; then
            log_error "FAIL $message (found: $shell)"
            has_shell=true
            break
        fi
    done

    if [[ "$has_shell" == "false" ]]; then
        log_debug "PASS $message"
        return 0
    fi
    return 1
}

# ============================================================================
# Filesystem Security
# ============================================================================

# Assert container works with read-only filesystem
assert_container_works_read_only() {
    local message="${1:-Container should work with read-only filesystem}"

    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    # Try to create the container with read-only root filesystem
    if $DOCKER_CMD create --read-only --name "test-readonly-$$" "${IMAGE_NAME}" >/dev/null 2>&1; then
        $DOCKER_CMD rm "test-readonly-$$" >/dev/null 2>&1
        log_debug "PASS $message"
        return 0
    else
        $DOCKER_CMD rm "test-readonly-$$" >/dev/null 2>&1 || true
        log_error "FAIL $message"
        return 1
    fi
}

# ============================================================================
# Capabilities
# ============================================================================

# Assert container works with all capabilities dropped
assert_container_works_no_caps() {
    local message="${1:-Container should work with --cap-drop=ALL}"

    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    if $DOCKER_CMD create --cap-drop=ALL --name "test-nocaps-$$" "${IMAGE_NAME}" >/dev/null 2>&1; then
        $DOCKER_CMD rm "test-nocaps-$$" >/dev/null 2>&1
        log_debug "PASS $message"
        return 0
    else
        $DOCKER_CMD rm "test-nocaps-$$" >/dev/null 2>&1 || true
        log_error "FAIL $message"
        return 1
    fi
}

# ============================================================================
# Package Managers
# ============================================================================

# Assert no package managers are present
assert_no_package_managers() {
    local message="${1:-Container should have no package managers}"

    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    local found_pm=false
    local package_managers=(apt-get apt yum dnf rpm apk pacman zypper)

    for pm in "${package_managers[@]}"; do
        if $DOCKER_CMD run --rm --network none --entrypoint "$pm" "${IMAGE_NAME}" --version 2>/dev/null; then
            log_error "FAIL $message (found: $pm)"
            found_pm=true
            break
        fi
    done

    if [[ "$found_pm" == "false" ]]; then
        log_debug "PASS $message"
        return 0
    fi
    return 1
}

# ============================================================================
# Image Size
# ============================================================================

# Assert image size is under a threshold (in MB)
assert_image_size_under() {
    local max_mb="$1"
    local message="${2:-Image size should be under ${max_mb}MB}"

    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    local size_bytes
    size_bytes=$($DOCKER_CMD image inspect "${IMAGE_NAME}" --format '{{.Size}}' 2>/dev/null || echo "0")
    local size_mb=$((size_bytes / 1048576))

    if [[ $size_mb -lt $max_mb ]]; then
        log_debug "PASS $message (${size_mb}MB)"
        return 0
    else
        log_error "FAIL $message (${size_mb}MB >= ${max_mb}MB)"
        return 1
    fi
}

# Assert image is minimal (under 50MB)
assert_image_minimal() {
    assert_image_size_under 50 "Image should be minimal (<50MB)"
}

# ============================================================================
# OCI Labels
# ============================================================================

# Assert required OCI labels exist
assert_has_oci_labels() {
    local message="${1:-Image should have required OCI labels}"

    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    local required_labels=(
        "org.opencontainers.image.title"
        "org.opencontainers.image.description"
        "org.opencontainers.image.source"
    )

    local missing=()
    for label in "${required_labels[@]}"; do
        local value
        value=$(get_oci_annotation "$label")
        if [[ -z "$value" ]]; then
            missing+=("$label")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message (missing: ${missing[*]})"
        return 1
    fi
}

# Assert a specific label has expected value
assert_label_value() {
    local label_name="$1"
    local expected_value="$2"
    local message="${3:-Label ${label_name} should equal ${expected_value}}"

    local actual_value
    actual_value=$(get_oci_annotation "$label_name")

    if [[ "$actual_value" == "$expected_value" ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message (actual: '$actual_value')"
        return 1
    fi
}
