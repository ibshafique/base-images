#!/bin/bash
# Build System Core - Main engine for the build system
# Provides: path management, parameter parsing, target execution, extension loading

set -euo pipefail

# Source common functions if available
if [[ -f "${BASH_SOURCE[0]%/*}/common.sh" ]]; then
    source "${BASH_SOURCE[0]%/*}/common.sh"
fi

# Ensure Bash 4+ for associative arrays
if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
    echo "Error: Bash 4.0+ required (current: ${BASH_VERSION})"
    [[ "$(uname)" == "Darwin" ]] && echo "Install with: brew install bash"
    exit 1
fi

# ============================================================================
# Path Management
# ============================================================================

setup_paths() {
    # SCRIPT_DIR must be set by build.sh
    readonly SCRIPT_DIR="${SCRIPT_DIR:?SCRIPT_DIR must be set by build.sh}"

    # MODULE_DIR: Module root (by convention, same as SCRIPT_DIR)
    readonly MODULE_DIR="${SCRIPT_DIR}"

    # PROJECT_ROOT_DIR: Walk up from MODULE_DIR to find .shared/
    local project_root="${MODULE_DIR}"
    local search_dir="${MODULE_DIR}"
    while [[ "$search_dir" != "/" ]]; do
        if [[ -d "${search_dir}/.shared" ]]; then
            project_root="$search_dir"
            break
        fi
        search_dir="$(dirname "$search_dir")"
    done
    readonly PROJECT_ROOT_DIR="$project_root"

    # Derived paths
    readonly BUILD_DIR="${MODULE_DIR}/build"
    # shellcheck disable=SC2034
    readonly SRC_DIR="${MODULE_DIR}/src"
    readonly TEST_DIR="${MODULE_DIR}/test"
    # shellcheck disable=SC2034
    readonly BUILD_LOG="${BUILD_DIR}/build.log"
    # shellcheck disable=SC2034
    readonly TEST_LOG="${BUILD_DIR}/test/test.log"

    # Shared libraries path
    readonly SHARED_LIB_DIR="${PROJECT_ROOT_DIR}/.shared/scripts/lib"
    readonly SHARED_EXT_DIR="${PROJECT_ROOT_DIR}/.shared/scripts/lib/ext"
    readonly SHARED_TEST_LIB_DIR="${PROJECT_ROOT_DIR}/.shared/scripts/test-lib"
    readonly SHARED_TEST_EXT_DIR="${PROJECT_ROOT_DIR}/.shared/scripts/test-lib/ext"
    export SHARED_TEST_EXT_DIR
}

# ============================================================================
# Parameter Management
# ============================================================================

declare -A BUILD_PARAMS=()
declare -A SYSTEM_FLAGS=()
declare -a TARGETS=()
declare -a DISABLED_FLAGS=()
declare -A TARGET_DEPS=()
declare -A TARGET_EXECUTED=()
declare -A LOADED_EXTENSIONS=()
CURRENT_TARGET=""

# Parse command line arguments
parse_arguments() {
    local args=("$@")

    for arg in "${args[@]}"; do
        if [[ "$arg" =~ ^-P([^=]+)=(.*)$ ]]; then
            # Parameter: -Pname=value
            BUILD_PARAMS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        elif [[ "$arg" =~ ^-- ]]; then
            # System flag: --flag
            SYSTEM_FLAGS["$arg"]="true"
        elif [[ "$arg" =~ ^- ]]; then
            log_error "Invalid flag format: $arg (use -Pname=value or --flag)"
            exit 1
        else
            # Target
            TARGETS+=("$arg")
        fi
    done

    # Default target is 'build' if none specified
    if [[ ${#TARGETS[@]} -eq 0 ]]; then
        TARGETS=("build")
    fi
}

# Get parameter value with optional default
get_param() {
    local name="$1"
    local default="${2:-}"
    echo "${BUILD_PARAMS[$name]:-$default}"
}

# Set parameter value
set_param() {
    local name="$1"
    local value="$2"
    BUILD_PARAMS["$name"]="$value"
}

# Check if parameter exists
has_param() {
    local name="$1"
    [[ -n "${BUILD_PARAMS[$name]+x}" ]]
}

# Check if system flag is set
is_flag_set() {
    local flag="$1"
    [[ -n "${SYSTEM_FLAGS[$flag]+x}" ]]
}

# Add a flag to the disabled list
disable_flag() {
    local flag="$1"
    local reason="${2:-This flag is disabled for this module}"

    [[ "$flag" == --* ]] || flag="--$flag"
    DISABLED_FLAGS+=("$flag:$reason")
}

# Normalize target name (convert - to _)
normalize_target() {
    echo "$1" | tr '-' '_'
}

# Declare target dependencies
depends_on() {
    local target
    target="$(normalize_target "$1")"
    shift
    local deps=""
    for dep in "$@"; do
        deps="${deps} $(normalize_target "$dep")"
    done
    TARGET_DEPS["$target"]="${deps# }"
}

# Load a utility extension explicitly (avoid reloading)
load_extension() {
    local extension_name="$1"

    # Skip if already loaded
    if [[ "${LOADED_EXTENSIONS[$extension_name]:-}" == "true" ]]; then
        log_debug "Extension already loaded: ${extension_name}"
        return 0
    fi

    local extension_file="${SHARED_EXT_DIR}/${extension_name}-extension.sh"

    if [[ -f "$extension_file" ]]; then
        log_debug "Loading extension: ${extension_name}"
        # shellcheck source=/dev/null
        source "$extension_file"
        LOADED_EXTENSIONS["$extension_name"]="true"
        return 0
    else
        log_error "Extension not found: ${extension_name}"
        return 1
    fi
}

# Load multiple extensions
load_extensions_list() {
    local failed=false
    for ext in "$@"; do
        if ! load_extension "$ext"; then
            failed=true
        fi
    done
    [[ "$failed" == "false" ]]
}

# Check if any disabled flags are present
check_disabled_flags() {
    local found_disabled=false

    for entry in "${DISABLED_FLAGS[@]}"; do
        local flag="${entry%%:*}"
        local reason="${entry#*:}"

        if is_flag_set "$flag"; then
            log_error "Disabled flag used: $flag"
            log_error "  Reason: $reason"
            found_disabled=true
        fi
    done

    if [[ "$found_disabled" == "true" ]]; then
        log_fatal "Build aborted due to disabled flags"
    fi
}

# ============================================================================
# Built-in Targets
# ============================================================================

builtin_target_clean() {
    log_info "Cleaning build directory..."
    rm -rf "${BUILD_DIR}"
    log_success "Clean complete"
}

builtin_target_build() {
    log_error "Build target not implemented. Please define target_build() in your build.sh"
    return 1
}

builtin_target_test() {
    if [[ -f "${SHARED_TEST_LIB_DIR}/test-core.sh" ]]; then
        source "${SHARED_TEST_LIB_DIR}/test-core.sh"
    fi

    ensure_test_dir
    CURRENT_TARGET="test"
    setup_logging

    log_info "Running tests from ${TEST_DIR}..."

    if [[ -d "${TEST_DIR}" ]]; then
        run_tests "${TEST_DIR}"/*.sh
    else
        log_warn "No test directory found at ${TEST_DIR}"
    fi

    log_success "Tests complete"
}

# Initialize default target functions
target_clean() {
    builtin_target_clean
}

target_build() {
    builtin_target_build
}

target_test() {
    builtin_target_test
}

# ============================================================================
# Target Execution
# ============================================================================

check_circular_deps() {
    local target
    target="$(normalize_target "$1")"
    local -a visited=("${@:2}")

    for v in "${visited[@]}"; do
        if [[ "$v" == "$target" ]]; then
            log_error "Circular dependency detected: ${visited[*]} -> $target"
            return 1
        fi
    done

    visited+=("$target")
    if [[ -n "${TARGET_DEPS[$target]+x}" ]]; then
        for dep in ${TARGET_DEPS[$target]}; do
            check_circular_deps "$dep" "${visited[@]}" || return 1
        done
    fi

    return 0
}

execute_target() {
    local target
    target="$(normalize_target "$1")"

    # Skip if already executed
    if [[ "${TARGET_EXECUTED[$target]:-}" == "true" ]]; then
        log_debug "Target '$target' already executed, skipping"
        return 0
    fi

    # Execute dependencies first
    if [[ -n "${TARGET_DEPS[$target]+x}" ]]; then
        log_debug "Target '$target' depends on: ${TARGET_DEPS[$target]}"
        for dep in ${TARGET_DEPS[$target]}; do
            execute_target "$dep" || return 1
        done
    fi

    # shellcheck disable=SC2034
    CURRENT_TARGET="$target"
    setup_logging

    local target_function="target_${target}"

    if ! declare -f "$target_function" > /dev/null; then
        log_error "Unknown target: $1"
        log_info "Available targets: clean, build, test (and any custom targets defined in build.sh)"
        return 1
    fi

    log_info "Executing target: $1"
    "$target_function" || return 1

    TARGET_EXECUTED["$target"]="true"
    return 0
}

# ============================================================================
# Main Entry Point
# ============================================================================

run_build() {
    setup_paths

    source "${SHARED_LIB_DIR}/build-logger.sh"
    source "${SHARED_LIB_DIR}/build-utils.sh"

    parse_arguments "$@"

    if is_flag_set "--usage"; then
        show_usage
        exit 0
    fi

    if is_flag_set "--list-targets"; then
        list_targets
        exit 0
    fi

    if is_flag_set "--list-flags"; then
        list_flags
        exit 0
    fi

    check_disabled_flags

    # Set up test dependency on build only if test is explicitly requested
    for target in "${TARGETS[@]}"; do
        if [[ "$target" == "test" ]]; then
            TARGET_DEPS[test]="build"
            break
        fi
    done

    for target in "${TARGETS[@]}"; do
        check_circular_deps "$target" || exit 1
    done

    for target in "${TARGETS[@]}"; do
        execute_target "$target" || exit 1
    done

    log_success "Build completed successfully"
}

# ============================================================================
# Help Functions
# ============================================================================

show_usage() {
    cat <<EOF
Build System Usage:
  $(basename "$0") [targets...] [options]

EOF
    list_targets
    cat <<EOF

Options:
  -P<name>=<value>   Set parameter (e.g., -Parch=amd64)
  --load             Load image to Docker after build
  --push             Push image to registry
  --debug            Enable debug output
  --no-color         Disable colored output
  --usage            Show this usage message
  --list-targets     List available targets
  --list-flags       List all system flags

Examples:
  $(basename "$0") clean
  $(basename "$0") build -Parch=amd64
  $(basename "$0") clean build test --load
  $(basename "$0") build --debug --no-color

EOF
}

list_targets() {
    echo "Available targets:"
    echo "  clean          - Remove build artifacts"
    echo "  build          - Build the image"
    echo "  test           - Run tests"

    local custom_targets
    custom_targets=$(declare -F | grep -E "^declare -f target_" | sed 's/declare -f target_//' | grep -vE '^(clean|build|test)$') || true
    if [[ -n "$custom_targets" ]]; then
        echo "$custom_targets" | while read -r target; do
            local display_name="${target//_/-}"
            printf "  %-15s- Custom target\n" "$display_name"
        done
    fi
}

list_flags() {
    echo "System flags:"
    echo "  --load         - Load image to Docker after build"
    echo "  --push         - Push image to registry"
    echo "  --debug        - Enable debug output"
    echo "  --no-color     - Disable colored output"
    echo "  --usage        - Show usage message"
    echo "  --list-targets - List available targets"
    echo "  --list-flags   - List all system flags"

    # List flags for extensions used by this module
    if [[ -f "${SCRIPT_DIR}/build.sh" ]]; then
        local used_extensions
        used_extensions=$(grep -o 'load_extension "[^"]*"' "${SCRIPT_DIR}/build.sh" 2>/dev/null | sed 's/load_extension "//;s/"//' | sort -u) || true

        if [[ -n "$used_extensions" ]]; then
            local has_extension_flags=false
            while read -r ext_name; do
                local extension_file="${SHARED_EXT_DIR}/${ext_name}-extension.sh"
                if [[ -f "$extension_file" ]] && grep -q "^# FLAGS:" "$extension_file"; then
                    if [[ "$has_extension_flags" == "false" ]]; then
                        echo ""
                        echo "Extension flags:"
                        has_extension_flags=true
                    fi
                    echo "  $ext_name extension:"
                    sed -n '/^# FLAGS:/,/^[^#]/p' "$extension_file" | grep "^#   --" | sed 's/^#/  /'
                fi
            done <<< "$used_extensions"
        fi
    fi

    # List disabled flags if any
    if [[ ${#DISABLED_FLAGS[@]} -gt 0 ]]; then
        echo ""
        echo "Disabled flags (will cause build to fail):"
        for entry in "${DISABLED_FLAGS[@]}"; do
            local flag="${entry%%:*}"
            local reason="${entry#*:}"
            echo "  $flag      - DISABLED: $reason"
        done
    fi
}
