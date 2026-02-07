#!/bin/bash
# Docker Test Extension - Docker image testing utilities
# Provides functions for loading, testing, and managing Docker images
#
# Usage:
#   load_test_extension "docker"
#   ensure_docker_image
#   run_docker_command "ls /"
#   cleanup_docker_image

DOCKER_IMAGE_LOADED_BY_TEST=false
IMAGE_NAME=""
DOCKER_CMD=""

_set_docker_cmd() {
    if command -v docker >/dev/null 2>&1; then
        DOCKER_CMD="docker"
        return 0
    fi
    if command -v podman >/dev/null 2>&1; then
        DOCKER_CMD="podman"
        return 0
    fi
    DOCKER_CMD=""
    return 1
}

# ============================================================================
# Image Management
# ============================================================================

ensure_docker_image() {
    local tar_path="${BUILD_OUTPUT_PATH:-}"

    if [[ -z "$tar_path" ]] || [[ ! -f "$tar_path" ]]; then
        log_error "No Docker tar file found at: ${tar_path:-<unset>}"
        return 1
    fi

    if ! _set_docker_cmd; then
        log_error "No docker-compatible CLI found (docker or podman)"
        return 1
    fi

    log_info "Loading Docker image from: ${tar_path}"
    local load_output
    if ! load_output=$($DOCKER_CMD load < "$tar_path" 2>&1); then
        log_error "Failed to load Docker image"
        return 1
    fi

    # Parse loaded image name from docker or podman output
    IMAGE_NAME=$(echo "$load_output" | awk '/Loaded image/ {sub("Loaded image: ",""); print $0} /Loaded image\(s\):/ {next} /^[^ ]+:[^ ]+$/ {print $0}' | tail -1)

    if [[ -z "$IMAGE_NAME" ]]; then
        log_error "Could not determine loaded image name"
        return 1
    fi

    log_info "Loaded image: ${IMAGE_NAME}"
    DOCKER_IMAGE_LOADED_BY_TEST=true
    export IMAGE_NAME
    return 0
}

cleanup_docker_image() {
    log_debug "Skipping Docker image cleanup; preserving image tags"
    return 0
}

# ============================================================================
# Container Operations
# ============================================================================

check_docker_image_exists() {
    if [[ -z "${IMAGE_NAME:-}" ]]; then
        log_error "IMAGE_NAME not set - call ensure_docker_image first"
        return 1
    fi
    if _set_docker_cmd && $DOCKER_CMD image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        log_success "Image exists: ${IMAGE_NAME}"
        return 0
    else
        log_error "Image not found: ${IMAGE_NAME}"
        return 1
    fi
}

run_docker_command() {
    local cmd="$*"

    if [[ -z "${IMAGE_NAME:-}" ]]; then
        log_error "IMAGE_NAME not set - call ensure_docker_image first"
        return 1
    fi

    if ! _set_docker_cmd; then
        log_error "No docker-compatible CLI found"
        return 1
    fi

    log_debug "Running command in container: $cmd"
    local sep=()
    [[ "$cmd" == -* ]] && sep=(--)
    $DOCKER_CMD run --rm --network none "${IMAGE_NAME}" "${sep[@]}" $cmd
}

run_docker_command_output() {
    local cmd="$*"

    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    local sep=()
    [[ "$cmd" == -* ]] && sep=(--)
    $DOCKER_CMD run --rm --network none "${IMAGE_NAME}" "${sep[@]}" $cmd 2>&1
}

check_container_file() {
    local file_path="${1:-}"

    if [[ -z "$file_path" ]] || [[ -z "${IMAGE_NAME:-}" ]]; then
        return 1
    fi

    if ! _set_docker_cmd; then
        return 1
    fi

    if $DOCKER_CMD run --rm --network none --entrypoint /bin/sh "${IMAGE_NAME}" -c "test -e '$file_path'" 2>/dev/null; then
        log_debug "File exists in container: $file_path"
        return 0
    else
        log_debug "File not found in container: $file_path"
        return 1
    fi
}

get_container_user() {
    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    $DOCKER_CMD inspect "${IMAGE_NAME}" | jq -r '.[0].Config.User // "root"' 2>/dev/null
}

get_container_env() {
    local var_name="$1"

    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    local value
    value=$($DOCKER_CMD run --rm --entrypoint /bin/sh "${IMAGE_NAME}" -c "echo \$$var_name" 2>/dev/null)

    if [[ -z "$value" ]]; then
        value=$($DOCKER_CMD inspect "${IMAGE_NAME}" | jq -r ".[0].Config.Env[]" 2>/dev/null | grep "^${var_name}=" | cut -d'=' -f2-)
    fi

    echo "$value"
}

get_container_workdir() {
    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    $DOCKER_CMD inspect "${IMAGE_NAME}" | jq -r '.[0].Config.WorkingDir // ""' 2>/dev/null
}

get_oci_annotation() {
    local annotation="$1"

    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    $DOCKER_CMD inspect "${IMAGE_NAME}" | jq -r ".[0].Config.Labels.\"${annotation}\" // \"\"" 2>/dev/null
}

inspect_image_layers() {
    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    $DOCKER_CMD history --no-trunc "${IMAGE_NAME}"
}

get_image_metadata() {
    if [[ -z "${IMAGE_NAME:-}" ]] || ! _set_docker_cmd; then
        return 1
    fi

    $DOCKER_CMD inspect "${IMAGE_NAME}" | jq '.[0].Config' 2>/dev/null || $DOCKER_CMD inspect "${IMAGE_NAME}"
}
