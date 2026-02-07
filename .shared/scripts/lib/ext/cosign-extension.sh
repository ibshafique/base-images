#!/bin/bash
# Cosign Extension - Image signing with Cosign (Sigstore)
# Provides functions for signing, verifying, and managing attestations
#
# Usage:
#   load_extension "cosign"
#
# FLAGS:
#   --keyless       Use keyless signing (default in CI)

# ============================================================================
# Setup Functions
# ============================================================================

# Check if cosign is available
check_cosign() {
    if ! command_exists cosign; then
        log_error "Cosign is not installed"
        log_info "Install: https://docs.sigstore.dev/cosign/system_config/installation/"
        return 1
    fi
    return 0
}

# Get cosign version
cosign_version() {
    cosign version 2>/dev/null | head -1 || echo "unknown"
}

# ============================================================================
# Signing Operations
# ============================================================================

# Sign image by reference (tag or digest)
# Args: image_ref [key_file]
cosign_sign_image() {
    local image_ref="$1"
    local key_file="${2:-}"

    check_cosign || return 1

    local -a cmd=(cosign sign --yes)

    if [[ -n "$key_file" ]]; then
        cmd+=(--key "$key_file")
    fi

    cmd+=("$image_ref")

    log_info "Signing image: ${image_ref}..."
    log_debug "Command: ${cmd[*]}"

    if COSIGN_YES=true "${cmd[@]}" 2>&1; then
        log_success "Image signed: ${image_ref}"
        return 0
    else
        log_error "Failed to sign image: ${image_ref}"
        return 1
    fi
}

# Sign image by digest
# Args: image_with_digest [key_file]
cosign_sign_digest() {
    cosign_sign_image "$@"
}

# ============================================================================
# Verification Operations
# ============================================================================

# Verify image signature
# Args: image_ref identity_regexp issuer
cosign_verify_image() {
    local image_ref="$1"
    local identity_regexp="$2"
    local issuer="$3"

    check_cosign || return 1

    log_info "Verifying signature: ${image_ref}..."

    if cosign verify \
        --certificate-identity-regexp="$identity_regexp" \
        --certificate-oidc-issuer="$issuer" \
        "$image_ref" >/dev/null 2>&1; then
        log_success "Signature verified: ${image_ref}"
        return 0
    else
        log_error "Signature verification failed: ${image_ref}"
        return 1
    fi
}

# ============================================================================
# Attestation Operations
# ============================================================================

# Check if attestation exists for image
# Args: image_ref type (sbom|provenance|slsaprovenance|spdx|cyclonedx)
check_attestation_exists() {
    local image_ref="$1"
    local attest_type="$2"

    check_cosign || return 1

    if cosign verify-attestation \
        --type "$attest_type" \
        --certificate-identity-regexp=".*" \
        --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
        "$image_ref" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Verify attestation with identity
# Args: image_ref type identity_regexp issuer
cosign_verify_attestation() {
    local image_ref="$1"
    local attest_type="$2"
    local identity_regexp="$3"
    local issuer="$4"

    check_cosign || return 1

    log_info "Verifying ${attest_type} attestation: ${image_ref}..."

    if cosign verify-attestation \
        --type "$attest_type" \
        --certificate-identity-regexp="$identity_regexp" \
        --certificate-oidc-issuer="$issuer" \
        "$image_ref" >/dev/null 2>&1; then
        log_success "Attestation verified: ${attest_type}"
        return 0
    else
        log_error "Attestation verification failed: ${attest_type}"
        return 1
    fi
}

# Download attestation payload
# Args: image_ref type output_file
cosign_download_attestation() {
    local image_ref="$1"
    local attest_type="$2"
    local output_file="$3"

    check_cosign || return 1

    cosign verify-attestation \
        --type "$attest_type" \
        --certificate-identity-regexp=".*" \
        --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
        "$image_ref" 2>/dev/null | jq -r '.payload' | base64 -d > "$output_file"

    if [[ -s "$output_file" ]]; then
        log_success "Attestation downloaded: ${output_file}"
        return 0
    else
        log_error "Failed to download attestation"
        return 1
    fi
}

# ============================================================================
# Utility Functions
# ============================================================================

# Get image digest from registry
# Args: image_ref (returns sha256:...)
get_image_digest() {
    local image_ref="$1"

    local digest
    digest=$(docker buildx imagetools inspect "$image_ref" --format '{{json .Manifest.Digest}}' 2>/dev/null | tr -d '"')

    if [[ -n "$digest" ]]; then
        echo "$digest"
    else
        # Fallback: try docker inspect
        digest=$(docker image inspect "$image_ref" --format '{{index .RepoDigests 0}}' 2>/dev/null | cut -d'@' -f2)
        echo "${digest:-unknown}"
    fi
}

# List all signatures and attestations for an image
cosign_tree() {
    local image_ref="$1"

    check_cosign || return 1

    log_info "Attestation tree for: ${image_ref}"
    cosign tree "$image_ref" 2>/dev/null || log_warn "cosign tree not available"
}
