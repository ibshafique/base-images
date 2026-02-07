#!/bin/bash
# Common Functions - Shared utilities for all scripts
# This file consolidates common functions to avoid duplication

# ============================================================================
# Validation Functions
# ============================================================================

# Check if command exists (single source of truth)
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate required commands
require_commands() {
    local missing=()
    for cmd in "$@"; do
        command_exists "$cmd" || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required commands: ${missing[*]}" >&2
        return 1
    fi
    return 0
}

# ============================================================================
# Safety Functions
# ============================================================================

# Safe directory operations
safe_rm_dir() {
    local dir="$1"

    # Validate directory path
    if [[ -z "$dir" ]] || [[ "$dir" == "/" ]] || [[ "$dir" == "$HOME" ]]; then
        echo "Error: Refusing to remove unsafe directory: $dir" >&2
        return 1
    fi

    # Check if directory exists
    if [[ -d "$dir" ]]; then
        rm -rf "${dir:?}"
        return $?
    fi
    return 0
}

# Safe command execution (instead of eval)
safe_exec() {
    local cmd="$1"
    shift

    if command_exists "$cmd"; then
        "$cmd" "$@"
        return $?
    else
        echo "Error: Command not found: $cmd" >&2
        return 127
    fi
}

# ============================================================================
# Path Functions
# ============================================================================

# Get absolute path (portable)
get_absolute_path() {
    local path="$1"

    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    elif [[ -f "$path" ]]; then
        echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    else
        echo "$path"
    fi
}

# Validate path (no traversal)
validate_path() {
    local path="$1"
    local base="${2:-$PWD}"

    # Get absolute paths
    local abs_path
    local abs_base
    abs_path="$(get_absolute_path "$path")"
    abs_base="$(get_absolute_path "$base")"

    # Check if path is under base
    if [[ "$abs_path" == "$abs_base"* ]]; then
        return 0
    else
        echo "Error: Path traversal detected: $path" >&2
        return 1
    fi
}

# ============================================================================
# Error Handling
# ============================================================================

# Error trap handler
error_handler() {
    local line_no=$1
    local last_command=$3
    local code=$4

    echo "Error occurred:" >&2
    echo "  Line: $line_no" >&2
    echo "  Command: $last_command" >&2
    echo "  Exit Code: $code" >&2
}

# Setup error handling
setup_error_handling() {
    set -euo pipefail
    trap 'error_handler $LINENO $BASH_LINENO "$BASH_COMMAND" $?' ERR
}

# ============================================================================
# Export Common Functions
# ============================================================================

export -f command_exists
export -f require_commands
export -f safe_rm_dir
export -f safe_exec
export -f get_absolute_path
export -f validate_path
export -f error_handler
export -f setup_error_handling

# Return file mtime as epoch seconds (portable across GNU/BSD)
portable_stat_mtime() {
    local f="$1"
    [[ -f "$f" ]] || { echo 0; return 66; }
    stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo 0
}

# Return file size in bytes (portable across GNU/BSD)
portable_file_size() {
    local f="$1"
    [[ -f "$f" ]] || { echo 0; return 66; }
    stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0
}

# Minimal, array-based command runner (no eval).
# Usage:
#   cmd=(curl -fsSL "https://example.com" -o "out")
#   run_cmd cmd[@]
run_cmd() {
    local -a _cmd=("${!1}")
    # Optional hooks for observers (logger may redefine)
    if declare -F log_start_cmd >/dev/null; then log_start_cmd "${_cmd[@]}"; fi
    "${_cmd[@]}"
    local rc=$?
    if declare -F log_end_cmd >/dev/null; then log_end_cmd $rc "${_cmd[@]}"; fi
    return $rc
}

# No-op hooks by default; logger may override or rely on these existing names.
log_start_cmd() { :; }
log_end_cmd() { :; }
