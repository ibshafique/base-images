#!/usr/bin/env bash
# distroless-static Build Script
# Google Distroless static image (glibc-based)
#
# Parameters:
#   -Parch=<arch>    Architecture (amd64, arm64) - defaults to system arch
#
# Examples:
#   ./build.sh build -Parch=amd64 --load
#   ./build.sh clean build test --load

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../../.shared/scripts/lib/build-core.sh"

readonly REGISTRY="${REGISTRY:-ghcr.io/ibshafique/base-images}"
readonly IMAGE_NAME="distroless-static"

target_build() {
    load_extension "docker-buildx"

    local arch
    arch=$(get_build_arch)
    local platform
    platform=$(platform_from_arch "$arch")
    local image_ref="${REGISTRY}/${IMAGE_NAME}"
    local date_tag
    date_tag="$(date +%Y%m%d)-$(get_scoped_git_sha_short "${MODULE_DIR}")"

    local -a tags=("latest-${arch}" "${date_tag}-${arch}")

    ensure_buildx_builder
    ensure_build_dir

    buildx_build "$image_ref" \
        "${MODULE_DIR}/Dockerfile" \
        "${MODULE_DIR}" \
        "$platform" \
        tags

    if is_flag_set "--load" || [[ "${TARGETS[*]}" == *"test"* ]]; then
        export BUILD_OUTPUT_PATH="${BUILD_DIR}/${IMAGE_NAME}-${arch}.tar"
        buildx_export_tar "$image_ref" \
            "${MODULE_DIR}/Dockerfile" \
            "${MODULE_DIR}" \
            "$platform" \
            "$BUILD_OUTPUT_PATH"
    fi

    log_success "Built ${IMAGE_NAME} for ${platform}"
}

target_scan() {
    load_extension "trivy"

    local arch
    arch=$(get_build_arch)
    local image_ref="${REGISTRY}/${IMAGE_NAME}:latest-${arch}"

    trivy_scan_image "$image_ref" "CRITICAL,HIGH" "table"
    check_critical_vulnerabilities "$image_ref"
}

target_sign() {
    load_extension "cosign"

    local arch
    arch=$(get_build_arch)
    local image_ref="${REGISTRY}/${IMAGE_NAME}:latest-${arch}"
    local digest
    digest=$(get_image_digest "$image_ref")

    if [[ "$digest" == "unknown" ]]; then
        log_error "Cannot sign: image digest not found"
        return 1
    fi

    cosign_sign_digest "${REGISTRY}/${IMAGE_NAME}@${digest}"
}

target_info() {
    log_section "${IMAGE_NAME} Info"
    print_build_env
    log_info "Registry: ${REGISTRY}"
    log_info "Image: ${IMAGE_NAME}"
    log_info "Architecture: $(get_build_arch)"
}

run_build "$@"
