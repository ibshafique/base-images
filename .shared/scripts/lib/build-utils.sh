#!/bin/bash
# Build System Utilities - Common helper functions for build operations

# ============================================================================
# Directory Management
# ============================================================================

ensure_build_dir() {
    if [[ ! -d "${BUILD_DIR}" ]]; then
        log_debug "Creating build directory: ${BUILD_DIR}"
        mkdir -p "${BUILD_DIR}"
    fi
}

ensure_test_dir() {
    if [[ ! -d "${BUILD_DIR}/test" ]]; then
        log_debug "Creating test directory: ${BUILD_DIR}/test"
        mkdir -p "${BUILD_DIR}/test"
    fi
}

ensure_src_dir() {
    if [[ ! -d "${SRC_DIR}" ]]; then
        log_warn "Source directory does not exist: ${SRC_DIR}"
        return 1
    fi
    return 0
}

clean_dir() {
    local dir="$1"

    if [[ -d "$dir" ]] && [[ -n "$dir" ]] && [[ "$dir" != "/" ]]; then
        log_debug "Cleaning directory: $dir"
        find "$dir" -mindepth 1 -delete 2>/dev/null || rm -rf "${dir:?}"/*
    fi
}

create_dir() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        log_debug "Creating directory: $dir"
        mkdir -p "$dir"
    fi
}

# ============================================================================
# File Operations
# ============================================================================

copy_files() {
    local src="$1"
    local dest="$2"

    log_debug "Copying from $src to $dest"

    if [[ -e "$src" ]]; then
        cp -r "$src" "$dest"
        log_debug "Copy completed"
    else
        log_warn "Source does not exist: $src"
        return 1
    fi
}

move_files() {
    local src="$1"
    local dest="$2"

    log_debug "Moving from $src to $dest"

    if [[ -e "$src" ]]; then
        mv "$src" "$dest"
        log_debug "Move completed"
    else
        log_warn "Source does not exist: $src"
        return 1
    fi
}

create_file() {
    local file="$1"
    local content="${2:-}"

    log_debug "Creating file: $file"

    local parent_dir
    parent_dir="$(dirname "$file")"
    create_dir "$parent_dir"

    if [[ -n "$content" ]]; then
        echo "$content" > "$file"
    else
        touch "$file"
    fi
}

file_exists_not_empty() {
    local file="$1"
    [[ -f "$file" ]] && [[ -s "$file" ]]
}

# ============================================================================
# Validation Functions
# ============================================================================

# Validate architecture parameter (convention: amd64, arm64)
validate_arch_param() {
    if has_param "arch"; then
        local arch_value
        arch_value="$(get_param arch)"
        if [[ "$arch_value" != "amd64" ]] && [[ "$arch_value" != "arm64" ]]; then
            log_error "Invalid arch parameter: $arch_value"
            log_info "Valid values: amd64, arm64"
            return 1
        fi
    fi
    return 0
}

require_command() {
    local cmd="$1"
    local message="${2:-$cmd is required but not found}"

    if ! command_exists "$cmd"; then
        log_error "$message"
        return 1
    fi
    return 0
}

is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

get_arch() {
    local arch
    arch="$(uname -m)"

    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Get architecture for build operations (amd64/arm64 convention)
get_build_arch() {
    local arch_param
    arch_param="$(get_param arch)"

    if [[ -n "$arch_param" ]]; then
        echo "$arch_param"
    else
        case "$(uname -m)" in
            x86_64) echo "amd64" ;;
            aarch64) echo "arm64" ;;
            arm64) echo "arm64" ;;
            *) uname -m ;;
        esac
    fi
}

# Validate required parameters
validate_params() {
    local params=("$@")
    local missing=()

    for param in "${params[@]}"; do
        if ! has_param "$param"; then
            missing+=("$param")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required parameters: ${missing[*]}"
        log_info "Use -P<name>=<value> to set parameters"
        return 1
    fi

    return 0
}

# ============================================================================
# Build Artifact Management
# ============================================================================

save_artifact() {
    local artifact="$1"
    local dest_name="${2:-$(basename "$artifact")}"
    local artifact_dir="${BUILD_DIR}/artifacts"

    create_dir "$artifact_dir"

    if [[ -e "$artifact" ]]; then
        cp -r "$artifact" "${artifact_dir}/${dest_name}"
        log_debug "Saved artifact: $dest_name"
    else
        log_warn "Artifact not found: $artifact"
        return 1
    fi
}

list_artifacts() {
    local artifact_dir="${BUILD_DIR}/artifacts"

    if [[ -d "$artifact_dir" ]]; then
        log_info "Build artifacts:"
        # Portable: works on both GNU and BSD find
        find "$artifact_dir" -type f | while read -r f; do
            log_info "  - $(basename "$f")"
        done
    else
        log_info "No build artifacts found"
    fi
}

# ============================================================================
# Process Management
# ============================================================================

run_with_timeout() {
    local timeout_secs="$1"; shift
    if [[ -z "$timeout_secs" ]]; then
        log_error "run_with_timeout: missing timeout seconds"
        return 64
    fi
    if [[ "$#" -eq 0 ]]; then
        log_error "run_with_timeout: missing command"
        return 64
    fi

    local -a _cmd
    if [[ "$1" == *@ ]]; then
        local -n __ref="${1%[@]}"
        _cmd=("${__ref[@]}")
    else
        _cmd=("$@")
    fi

    if [[ "${#_cmd[@]}" -eq 0 ]]; then
        log_error "run_with_timeout: empty command"
        return 64
    fi

    if command_exists timeout; then
        local -a wrapped=(timeout "$timeout_secs" "${_cmd[@]}")
        run_cmd wrapped[@]
    else
        # macOS fallback: no timeout command, run directly
        log_debug "timeout command not available, running without timeout"
        run_cmd _cmd[@]
    fi
}

# Capture command output into a variable
capture_output() {
    local __outvar="$1"; shift
    if [[ -z "$__outvar" ]]; then
        log_error "capture_output: missing OUTVAR name"
        return 64
    fi
    if [[ "$#" -eq 0 ]]; then
        log_error "capture_output: missing command"
        return 64
    fi

    local -a _cmd
    if [[ "$1" == *@ ]]; then
        local -n __ref="${1%[@]}"
        _cmd=("${__ref[@]}")
    else
        _cmd=("$@")
    fi

    local __out
    if ! __out="$("${_cmd[@]}" 2>&1)"; then
        printf -v "$__outvar" '%s' "$__out"
        return 1
    fi
    printf -v "$__outvar" '%s' "$__out"
    return 0
}

# ============================================================================
# Environment Management
# ============================================================================

export_build_env() {
    export BUILD_MODULE_DIR="${MODULE_DIR}"
    export BUILD_PROJECT_ROOT="${PROJECT_ROOT_DIR}"
    export BUILD_OUTPUT_DIR="${BUILD_DIR}"
    export BUILD_SOURCE_DIR="${SRC_DIR}"
    export BUILD_TEST_DIR="${TEST_DIR}"

    for param in "${!BUILD_PARAMS[@]}"; do
        export "BUILD_PARAM_${param}=${BUILD_PARAMS[$param]}"
    done

    for flag in "${!SYSTEM_FLAGS[@]}"; do
        local env_name="${flag#--}"
        env_name="${env_name^^}"
        env_name="${env_name//-/_}"
        export "BUILD_FLAG_${env_name}=true"
    done

    log_debug "Build environment exported"
}

print_build_env() {
    log_info "Build Environment:"
    log_info "  Module: $(basename "${MODULE_DIR}")"
    log_info "  Project Root: ${PROJECT_ROOT_DIR}"
    log_info "  Build Dir: ${BUILD_DIR}"
    log_info "  Test Dir: ${TEST_DIR}"

    if [[ ${#BUILD_PARAMS[@]} -gt 0 ]]; then
        log_info "  Parameters:"
        for param in "${!BUILD_PARAMS[@]}"; do
            log_info "    $param = ${BUILD_PARAMS[$param]}"
        done
    fi

    if [[ ${#SYSTEM_FLAGS[@]} -gt 0 ]]; then
        log_info "  Flags:"
        for flag in "${!SYSTEM_FLAGS[@]}"; do
            log_info "    $flag"
        done
    fi
}

# ============================================================================
# Version Management
# ============================================================================

get_version() {
    local default="${1:-1.0.0}"

    if has_param "version"; then
        get_param "version"
        return
    fi

    if [[ -f "${MODULE_DIR}/VERSION" ]]; then
        cat "${MODULE_DIR}/VERSION"
        return
    fi

    echo "$default"
}

set_version() {
    local version="$1"
    echo "$version" > "${MODULE_DIR}/VERSION"
    log_info "Version set to: $version"
}

# ============================================================================
# Checksum and Verification
# ============================================================================

calculate_checksum() {
    local file="$1"
    local algorithm="${2:-sha256}"

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    case "$algorithm" in
        md5)
            if command_exists md5sum; then
                md5sum "$file" | cut -d' ' -f1
            elif command_exists md5; then
                md5 -q "$file"
            else
                log_error "No MD5 command available"
                return 1
            fi
            ;;
        sha256)
            if command_exists sha256sum; then
                sha256sum "$file" | cut -d' ' -f1
            elif command_exists shasum; then
                shasum -a 256 "$file" | cut -d' ' -f1
            else
                log_error "No SHA256 command available"
                return 1
            fi
            ;;
        *)
            log_error "Unknown algorithm: $algorithm"
            return 1
            ;;
    esac
}

verify_checksum() {
    local file="$1"
    local expected="$2"
    local algorithm="${3:-sha256}"

    local actual
    actual="$(calculate_checksum "$file" "$algorithm")"

    if [[ "$actual" == "$expected" ]]; then
        log_debug "Checksum verified: $file"
        return 0
    else
        log_error "Checksum mismatch for $file"
        log_error "  Expected: $expected"
        log_error "  Actual:   $actual"
        return 1
    fi
}

# ============================================================================
# Git Utilities
# ============================================================================

# Get scoped git SHA (only changes when relevant paths change)
get_scoped_git_sha() {
    local -a paths=("$@")
    local root="${PROJECT_ROOT_DIR}"

    if [[ ${#paths[@]} -eq 0 ]]; then
        paths=("${MODULE_DIR}")
    fi

    local sha
    sha=$(cd "$root" && git log -1 --format=%H -- "${paths[@]}" 2>/dev/null) || true

    if [[ -n "$sha" ]]; then
        echo "$sha"
    else
        echo "unknown"
    fi
}

# Get short scoped git SHA
get_scoped_git_sha_short() {
    local sha
    sha="$(get_scoped_git_sha "$@")"
    echo "${sha:0:7}"
}
