#!/bin/bash
# Trivy Extension - Vulnerability scanning with Trivy
# Provides functions for scanning images and generating reports
#
# Usage:
#   load_extension "trivy"
#
# FLAGS:
#   --ignore-unfixed    Ignore unfixed vulnerabilities

# ============================================================================
# Setup Functions
# ============================================================================

# Check if trivy is available
check_trivy() {
    if ! command_exists trivy; then
        log_error "Trivy is not installed"
        log_info "Install: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
        return 1
    fi
    return 0
}

# Get trivy version
trivy_version() {
    trivy version 2>/dev/null | head -1 || echo "unknown"
}

# ============================================================================
# Scan Operations
# ============================================================================

# Scan image for vulnerabilities
# Args: image_ref [severity] [format]
trivy_scan_image() {
    local image_ref="$1"
    local severity="${2:-CRITICAL,HIGH}"
    local format="${3:-table}"

    check_trivy || return 1

    log_info "Scanning image: ${image_ref} (severity: ${severity})..."

    local -a cmd=(trivy image)
    cmd+=(--severity "$severity")
    cmd+=(--format "$format")

    if is_flag_set "--ignore-unfixed"; then
        cmd+=(--ignore-unfixed)
    fi

    cmd+=("$image_ref")

    "${cmd[@]}"
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        log_success "Scan complete: no issues found at ${severity} level"
    else
        log_warn "Scan found vulnerabilities at ${severity} level"
    fi

    return $rc
}

# Scan filesystem/config for issues
# Args: path [severity] [format]
trivy_scan_filesystem() {
    local scan_path="$1"
    local severity="${2:-CRITICAL,HIGH}"
    local format="${3:-table}"

    check_trivy || return 1

    log_info "Scanning filesystem: ${scan_path}..."

    trivy fs \
        --severity "$severity" \
        --format "$format" \
        "$scan_path"
}

# Scan Dockerfile/config for misconfigurations
# Args: path [severity]
trivy_scan_config() {
    local scan_path="$1"
    local severity="${2:-CRITICAL,HIGH}"

    check_trivy || return 1

    log_info "Scanning config: ${scan_path}..."

    trivy config \
        --severity "$severity" \
        "$scan_path"
}

# ============================================================================
# Report Operations
# ============================================================================

# Generate SARIF report
# Args: image_ref output_file
trivy_generate_sarif() {
    local image_ref="$1"
    local output_file="$2"

    check_trivy || return 1

    local output_dir
    output_dir="$(dirname "$output_file")"
    mkdir -p "$output_dir" 2>/dev/null || true

    log_info "Generating SARIF report: ${output_file}..."

    trivy image \
        --severity CRITICAL,HIGH \
        --format sarif \
        --output "$output_file" \
        "$image_ref"

    if [[ -s "$output_file" ]]; then
        log_success "SARIF report generated: ${output_file}"
        return 0
    else
        log_error "Failed to generate SARIF report"
        return 1
    fi
}

# Generate JSON report
# Args: image_ref output_file
trivy_generate_json() {
    local image_ref="$1"
    local output_file="$2"

    check_trivy || return 1

    local output_dir
    output_dir="$(dirname "$output_file")"
    mkdir -p "$output_dir" 2>/dev/null || true

    trivy image \
        --severity CRITICAL,HIGH \
        --format json \
        --output "$output_file" \
        "$image_ref"

    if [[ -s "$output_file" ]]; then
        log_success "JSON report generated: ${output_file}"
        return 0
    else
        log_error "Failed to generate JSON report"
        return 1
    fi
}

# ============================================================================
# Utility Functions
# ============================================================================

# Check if any CRITICAL vulnerabilities exist
# Args: image_ref
# Returns: 0 if no criticals, 1 if criticals found
check_critical_vulnerabilities() {
    local image_ref="$1"

    check_trivy || return 1

    local output
    output=$(trivy image \
        --severity CRITICAL \
        --format json \
        --quiet \
        "$image_ref" 2>/dev/null)

    local vuln_count
    vuln_count=$(echo "$output" | jq '[.Results[]?.Vulnerabilities // [] | length] | add // 0' 2>/dev/null || echo "0")

    if [[ "$vuln_count" -gt 0 ]]; then
        log_error "Found ${vuln_count} CRITICAL vulnerability(ies) in ${image_ref}"
        return 1
    else
        log_success "No CRITICAL vulnerabilities in ${image_ref}"
        return 0
    fi
}
