#!/bin/bash
# Build System Logger - Provides color-coded logging with file output
# Supports separate build and test log streams

# ============================================================================
# Configuration
# ============================================================================

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="${BUILD_LOG:-/dev/null}"
LOG_TIMESTAMPS="${LOG_TIMESTAMPS:-true}"
LOG_TIMESTAMP_FORMAT="${LOG_TIMESTAMP_FORMAT:-%Y/%m/%d %H:%M:%S}"

# ============================================================================
# Logging Setup
# ============================================================================

# Setup logging based on context
setup_logging() {
    # For clean target, don't log to file since we're deleting the build directory
    if [[ "${CURRENT_TARGET}" == "clean" ]]; then
        LOG_FILE="/dev/null"
    else
        # Ensure build directory exists for logs
        mkdir -p "${BUILD_DIR}" 2>/dev/null || true
        mkdir -p "${BUILD_DIR}/test" 2>/dev/null || true

        # Determine log file based on current target
        if [[ "${CURRENT_TARGET}" == "test" ]]; then
            LOG_FILE="${TEST_LOG}"
        else
            LOG_FILE="${BUILD_LOG}"
        fi
    fi

    # Initialize log file with header
    if [[ "$LOG_FILE" != "/dev/null" ]] && [[ -n "$LOG_FILE" ]]; then
        # Ensure log directory exists
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        mkdir -p "$log_dir" 2>/dev/null || true

        {
            echo "================================================================================"
            echo "Build System Log - $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Target: ${CURRENT_TARGET:-unknown}"
            echo "Module: $(basename "${MODULE_DIR:-unknown}")"
            echo "================================================================================"
            echo
        } >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# ============================================================================
# Core Logging Functions
# ============================================================================

# Get timestamp for logs
get_timestamp() {
    [[ "$LOG_TIMESTAMPS" == "true" ]] && date "+${LOG_TIMESTAMP_FORMAT}" || echo ""
}

# Check if colors should be used
should_use_color() {
    # Disable colors if: --no-color flag, not in terminal, or NO_COLOR env var
    is_flag_set "--no-color" 2>/dev/null && return 1
    [[ ! -t 1 ]] && return 1
    [[ -n "${NO_COLOR:-}" ]] && return 1
    return 0
}

# ============================================================================
# Output Cleaning Utilities
# ============================================================================

# Strip ANSI color codes and terminal escape sequences from input
strip_ansi_codes() {
    sed -E '
        s/\x1b\[[0-9;]*[A-Za-z]//g
        s/\x1b\][0-9;]*\x07//g
        s/\x1b\][0-9]+;[^\x07]*\x07//g
        s/\x1b\[[0-9]+;[0-9]+R//g
        s/\[[0-9]+;[0-9]+R//g
        s/\]1[0-9];rgb:[0-9a-fA-F/]+//g
        s/\]1[0-9];[^\x1b\[]*//g
        s/^[0-9]+;//g
        s/ [0-9]+;/ /g
        s/\r$//
    ' 2>/dev/null || cat
}

# Core log function
log_message() {
    local level="$1"
    local color="$2"
    local message="$3"
    local show_in_console="${4:-true}"
    local timestamp
    timestamp="$(get_timestamp)"

    # Format level to 4 chars max, padded for alignment
    local level_formatted
    level_formatted="$(printf "%-4s" "${level:0:4}")"

    # Console output with color and timestamp
    if [[ "$show_in_console" == "true" ]]; then
        if [[ -n "$timestamp" ]]; then
            if should_use_color; then
                echo -e "${timestamp} ${color}${level_formatted}${NC} ${message}"
            else
                echo "${timestamp} ${level_formatted} ${message}"
            fi
        else
            if should_use_color; then
                echo -e "${color}${level_formatted}${NC} ${message}"
            else
                echo "${level_formatted} ${message}"
            fi
        fi
    fi

    # File output with timestamp but without color
    if [[ "$LOG_FILE" != "/dev/null" ]] && [[ -n "$LOG_FILE" ]]; then
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        [[ ! -d "$log_dir" ]] && mkdir -p "$log_dir" 2>/dev/null || true
        if [[ -n "$timestamp" ]]; then
            strip_ansi_codes <<< "${timestamp} ${level_formatted} ${message}" >> "$LOG_FILE" 2>/dev/null || true
        else
            strip_ansi_codes <<< "${level_formatted} ${message}" >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi
}

# ============================================================================
# Public Logging Functions
# ============================================================================

# Debug logging (only shown with --debug)
log_debug() {
    local show_in_console="false"
    if is_flag_set "--debug" 2>/dev/null; then
        show_in_console="true"
    fi
    log_message "DEBUG" "$CYAN" "$*" "$show_in_console"
}

# Information logging
log_info() {
    log_message "INFO" "$BLUE" "$*"
}

# Success logging
log_success() {
    log_message "DONE" "$GREEN" "$*"
}

# Warning logging
log_warn() {
    log_message "WARN" "$YELLOW" "$*" >&2
}

# Error logging
log_error() {
    log_message "ERROR" "$RED" "$*" >&2
}

# Fatal error logging (exits after logging)
log_fatal() {
    log_message "FAIL" "${BOLD}${RED}" "$*" >&2
    exit 1
}

# ============================================================================
# Special Purpose Logging
# ============================================================================

# Log command execution (deprecated: prefer array-based run via run_cmd)
log_cmd() {
    local cmd_str="$*"
    if [[ -z "$cmd_str" ]]; then
        log_error "log_cmd: empty command"
        return 64
    fi
    log_debug "exec: ${cmd_str}"
    local -a _cmd=(bash -lc "$cmd_str")
    run_cmd _cmd[@]
}

# Log a separator line
log_separator() {
    local char="${1:--}"
    local width="${2:-80}"
    local line
    line=$(printf "%${width}s" | tr ' ' "$char")

    if should_use_color; then
        echo -e "${CYAN}${line}${NC}"
    else
        echo "$line"
    fi

    if [[ "$LOG_FILE" != "/dev/null" ]] && [[ -n "$LOG_FILE" ]]; then
        echo "$line" >> "$LOG_FILE"
    fi
}

# Log section header
log_section() {
    local title="$1"
    log_separator
    log_info "$title"
    log_separator
}

# ============================================================================
# Progress Indicators
# ============================================================================

log_task_start() {
    local task="$1"
    log_info "Starting: $task"
}

log_task_done() {
    local task="$1"
    log_success "Completed: $task"
}

log_progress() {
    local current="$1"
    local total="$2"
    local task="${3:-Progress}"

    [[ $total -gt 0 ]] && log_info "$task: $current/$total ($((current * 100 / total))%)"
}

# ============================================================================
# Test-specific Logging
# ============================================================================

log_test_result() {
    local test_name="$1"
    local result="$2"

    if [[ "$result" == "PASS" ]]; then
        log_success "PASS $test_name"
    elif [[ "$result" == "FAIL" ]]; then
        log_error "FAIL $test_name"
    elif [[ "$result" == "SKIP" ]]; then
        log_warn "SKIP $test_name (skipped)"
    else
        log_info "?    $test_name ($result)"
    fi
}

log_test_summary() {
    local passed="$1"
    local failed="$2"
    local skipped="${3:-0}"
    local total=$((passed + failed + skipped))

    log_separator "="
    log_info "Test Summary:"
    log_info "  Total:   $total"
    log_success "  Passed:  $passed"

    if [[ $failed -gt 0 ]]; then
        log_error "  Failed:  $failed"
    else
        log_info "  Failed:  $failed"
    fi

    if [[ $skipped -gt 0 ]]; then
        log_warn "  Skipped: $skipped"
    fi

    log_separator "="

    if [[ $failed -eq 0 ]]; then
        log_success "All tests passed!"
        return 0
    else
        log_error "Some tests failed!"
        return 1
    fi
}
