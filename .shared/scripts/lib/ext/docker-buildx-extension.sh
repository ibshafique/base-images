#!/bin/bash
# Docker Buildx Extension - Docker Buildx build operations
# Provides functions for building, exporting, and managing container images
#
# Usage:
#   load_extension "docker-buildx"
#
# FLAGS:
#   --load          Load image to Docker after build (single platform only)
#   --push          Push image to registry
#   --sbom          Generate SBOM attestation
#   --provenance    Generate provenance attestation

# ============================================================================
# Configuration
# ============================================================================

BUILDX_BUILDER_NAME="${BUILDX_BUILDER_NAME:-base-images-builder}"

# ============================================================================
# Setup Functions
# ============================================================================

# Check if docker buildx is available
check_buildx() {
    if ! command_exists docker; then
        log_error "Docker is not installed"
        return 1
    fi

    if ! docker buildx version >/dev/null 2>&1; then
        log_error "Docker Buildx is not available"
        log_info "Install with: docker buildx install"
        return 1
    fi

    return 0
}

# Ensure a buildx builder instance exists and is active
ensure_buildx_builder() {
    check_buildx || return 1

    local builder_name="${BUILDX_BUILDER_NAME}"

    # Check if builder already exists
    if docker buildx inspect "$builder_name" >/dev/null 2>&1; then
        docker buildx use "$builder_name" 2>/dev/null || true
        log_debug "Using existing builder: $builder_name"
        return 0
    fi

    # Create new builder
    log_info "Creating buildx builder: $builder_name"
    docker buildx create \
        --name "$builder_name" \
        --driver docker-container \
        --driver-opt "image=moby/buildkit:latest" \
        --use >/dev/null 2>&1

    # Bootstrap the builder
    docker buildx inspect --bootstrap "$builder_name" >/dev/null 2>&1

    log_success "Builder created: $builder_name"
    return 0
}

# Get builder name
get_buildx_builder_name() {
    echo "${BUILDX_BUILDER_NAME}"
}

# ============================================================================
# Build Operations
# ============================================================================

# Convert arch to platform string (amd64 -> linux/amd64)
platform_from_arch() {
    local arch="${1:-amd64}"
    echo "linux/${arch}"
}

# Get default platform based on system architecture
get_default_platform() {
    local arch
    arch="$(get_build_arch)"
    platform_from_arch "$arch"
}

# Validate Dockerfile exists
validate_dockerfile() {
    local dockerfile="$1"

    if [[ ! -f "$dockerfile" ]]; then
        log_error "Dockerfile not found: $dockerfile"
        return 1
    fi
    return 0
}

# Build image with Docker Buildx
# Args: image_name dockerfile context platform tags_array_name [build_args_array_name]
buildx_build() {
    local image_name="$1"
    local dockerfile="$2"
    local context="$3"
    local platform="$4"
    local -n _tags="${5}"
    local -n _build_args="${6:-_empty_array}" 2>/dev/null || true

    validate_dockerfile "$dockerfile" || return 1
    ensure_build_dir

    local -a cmd=(docker buildx build)
    cmd+=(--platform "$platform")
    cmd+=(--file "$dockerfile")

    # Add tags
    for tag in "${_tags[@]}"; do
        if [[ "$tag" == *"/"* ]] || [[ "$tag" == *":"* ]]; then
            cmd+=(--tag "$tag")
        else
            cmd+=(--tag "${image_name}:${tag}")
        fi
    done

    # Add build args
    if [[ -n "${_build_args[*]+x}" ]]; then
        for arg in "${_build_args[@]}"; do
            cmd+=(--build-arg "$arg")
        done
    fi

    # Cache configuration
    local cache_scope
    cache_scope="$(basename "$image_name")-$(basename "$platform")"
    cmd+=(--cache-from "type=gha,scope=${cache_scope}")
    cmd+=(--cache-to "type=gha,mode=max,scope=${cache_scope}")

    # SBOM and provenance
    if is_flag_set "--sbom"; then
        cmd+=(--sbom=true)
    fi
    if is_flag_set "--provenance"; then
        cmd+=(--provenance=true)
    fi

    # Output mode
    if is_flag_set "--push"; then
        cmd+=(--push)
    elif is_flag_set "--load"; then
        cmd+=(--load)
    fi

    cmd+=("$context")

    log_info "Building ${image_name} for ${platform}..."
    log_debug "Command: ${cmd[*]}"

    "${cmd[@]}" 2>&1 | while IFS= read -r line; do
        log_debug "$line"
    done

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Build failed for ${image_name}"
        return 1
    fi

    log_success "Build complete: ${image_name}"
    return 0
}

# Build and export to tar for testing
# Args: image_name dockerfile context platform output_path
buildx_export_tar() {
    local image_name="$1"
    local dockerfile="$2"
    local context="$3"
    local platform="$4"
    local output_path="$5"

    validate_dockerfile "$dockerfile" || return 1
    ensure_build_dir

    local output_dir
    output_dir="$(dirname "$output_path")"
    create_dir "$output_dir"

    log_info "Building and exporting to tar: ${output_path}..."

    docker buildx build \
        --platform "$platform" \
        --file "$dockerfile" \
        --tag "${image_name}:test" \
        --output "type=docker,dest=${output_path}" \
        "$context" 2>&1 | while IFS= read -r line; do
        log_debug "$line"
    done

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Export failed for ${image_name}"
        return 1
    fi

    if [[ -f "$output_path" ]]; then
        local size
        size="$(portable_file_size "$output_path")"
        log_success "Exported: ${output_path} (${size} bytes)"
        return 0
    else
        log_error "Export file not created: ${output_path}"
        return 1
    fi
}

# Build multi-arch image (requires push)
# Args: image_name dockerfile context platforms_csv tags_array_name
buildx_build_multi_arch() {
    local image_name="$1"
    local dockerfile="$2"
    local context="$3"
    local platforms="$4"
    local -n _ma_tags="${5}"

    validate_dockerfile "$dockerfile" || return 1

    local -a cmd=(docker buildx build)
    cmd+=(--platform "$platforms")
    cmd+=(--file "$dockerfile")

    for tag in "${_ma_tags[@]}"; do
        if [[ "$tag" == *"/"* ]] || [[ "$tag" == *":"* ]]; then
            cmd+=(--tag "$tag")
        else
            cmd+=(--tag "${image_name}:${tag}")
        fi
    done

    if is_flag_set "--sbom"; then
        cmd+=(--sbom=true)
    fi
    if is_flag_set "--provenance"; then
        cmd+=(--provenance=true)
    fi

    cmd+=(--push)
    cmd+=("$context")

    log_info "Building ${image_name} for ${platforms}..."
    "${cmd[@]}"

    local rc=$?
    if [[ $rc -ne 0 ]]; then
        log_error "Multi-arch build failed for ${image_name}"
        return 1
    fi

    log_success "Multi-arch build complete: ${image_name}"
    return 0
}

# ============================================================================
# Metadata Functions
# ============================================================================

# Extract image digest from registry
extract_image_digest() {
    local image_ref="$1"

    docker buildx imagetools inspect "$image_ref" --format '{{json .Manifest.Digest}}' 2>/dev/null | tr -d '"'
}

# Get image size
get_image_size() {
    local image_ref="$1"

    docker image inspect "$image_ref" --format '{{.Size}}' 2>/dev/null || echo "0"
}

# Get image size in human-readable format
get_image_size_human() {
    local image_ref="$1"
    local size
    size="$(get_image_size "$image_ref")"

    if [[ "$size" -gt 0 ]]; then
        if [[ "$size" -gt 1048576 ]]; then
            echo "$((size / 1048576))MB"
        elif [[ "$size" -gt 1024 ]]; then
            echo "$((size / 1024))KB"
        else
            echo "${size}B"
        fi
    else
        echo "unknown"
    fi
}

# ============================================================================
# Cache Management
# ============================================================================

# Prune build cache
buildx_prune_cache() {
    log_info "Pruning Docker Buildx cache..."
    docker buildx prune -f 2>/dev/null || true
    log_success "Cache pruned"
}

# Declare empty array for optional build_args parameter
declare -a _empty_array=()
