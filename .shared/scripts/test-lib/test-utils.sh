#!/bin/bash
# Test Utilities - Helper functions and assertions for tests

# ============================================================================
# Assertions
# ============================================================================

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    if [[ "$expected" == "$actual" ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message"
        log_error "  Expected: '$expected'"
        log_error "  Actual:   '$actual'"
        return 1
    fi
}

assert_not_equals() {
    local unexpected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"

    if [[ "$unexpected" != "$actual" ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message"
        log_error "  Unexpected value: '$unexpected'"
        return 1
    fi
}

assert_true() {
    local value="$1"
    local message="${2:-Value should be true}"

    if [[ -n "$value" ]] && [[ "$value" != "false" ]] && [[ "$value" != "0" ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message"
        log_error "  Value: '$value'"
        return 1
    fi
}

assert_false() {
    local value="$1"
    local message="${2:-Value should be false}"

    if [[ -z "$value" ]] || [[ "$value" == "false" ]] || [[ "$value" == "0" ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message"
        log_error "  Value: '$value'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    if [[ "$haystack" == *"$needle"* ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message"
        log_error "  String: '$haystack'"
        log_error "  Should contain: '$needle'"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"

    if [[ "$haystack" != *"$needle"* ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message"
        log_error "  String: '$haystack'"
        log_error "  Should not contain: '$needle'"
        return 1
    fi
}

assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-String should match pattern}"

    if [[ "$string" =~ $pattern ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message"
        log_error "  String: '$string'"
        log_error "  Pattern: '$pattern'"
        return 1
    fi
}

assert_not_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-String should not match pattern}"

    if [[ ! "$string" =~ $pattern ]]; then
        log_debug "PASS $message"
        return 0
    else
        log_error "FAIL $message"
        log_error "  String: '$string'"
        log_error "  Should not match: '$pattern'"
        return 1
    fi
}

# ============================================================================
# File Assertions
# ============================================================================

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"

    if [[ -f "$file" ]]; then
        log_debug "PASS $message: $file"
        return 0
    else
        log_error "FAIL $message"
        log_error "  File not found: '$file'"
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local message="${2:-File should not exist}"

    if [[ ! -f "$file" ]]; then
        log_debug "PASS $message: $file"
        return 0
    else
        log_error "FAIL $message"
        log_error "  File exists: '$file'"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory should exist}"

    if [[ -d "$dir" ]]; then
        log_debug "PASS $message: $dir"
        return 0
    else
        log_error "FAIL $message"
        log_error "  Directory not found: '$dir'"
        return 1
    fi
}

assert_dir_not_exists() {
    local dir="$1"
    local message="${2:-Directory should not exist}"

    if [[ ! -d "$dir" ]]; then
        log_debug "PASS $message: $dir"
        return 0
    else
        log_error "FAIL $message"
        log_error "  Directory exists: '$dir'"
        return 1
    fi
}

assert_file_empty() {
    local path="$1"
    local message="${2:-File should be empty}"
    if [[ -z "$path" ]]; then
        log_error "assert_file_empty: path required"
        return 64
    fi
    if [[ ! -e "$path" ]]; then
        log_error "assert_file_empty: file does not exist: $path"
        return 66
    fi
    local size
    size="$(portable_file_size "$path")"
    if [[ "${size:-1}" -eq 0 ]]; then
        log_debug "PASS ${message}: ${path}"
        return 0
    else
        log_error "FAIL ${message}"
        log_error "  Not empty: ${path} (${size}B)"
        return 1
    fi
}

assert_file_not_empty() {
    local file="$1"
    local message="${2:-File should not be empty}"

    if [[ -f "$file" ]] && [[ -s "$file" ]]; then
        log_debug "PASS $message: $file"
        return 0
    fi

    if [[ ! -f "$file" ]]; then
        log_error "FAIL $message"
        log_error "  File not found: '$file'"
    else
        log_error "FAIL $message"
        log_error "  File is empty: '$file'"
    fi
    return 1
}

assert_file_contains() {
    local file="$1"
    local content="$2"
    local message="${3:-File should contain content}"

    if [[ -f "$file" ]] && grep -q "$content" "$file"; then
        log_debug "PASS $message"
        return 0
    fi

    if [[ ! -f "$file" ]]; then
        log_error "FAIL $message"
        log_error "  File not found: '$file'"
    else
        log_error "FAIL $message"
        log_error "  File: '$file'"
        log_error "  Should contain: '$content'"
    fi
    return 1
}

# ============================================================================
# Command Assertions
# ============================================================================

assert_success() {
    local -a _cmd
    if [[ "$#" -eq 1 && "$1" == *@ ]]; then
        local -n __ref="${1%[@]}"
        _cmd=("${__ref[@]}")
    elif [[ "$#" -ge 2 ]]; then
        _cmd=("$@")
    else
        _cmd=(bash -lc "$1")
    fi

    if run_cmd _cmd[@]; then
        log_success "assert_success: ok (${_cmd[*]})"
        return 0
    else
        log_error "assert_success: command failed (${_cmd[*]})"
        return 1
    fi
}

assert_failure() {
    local -a _cmd
    if [[ "$#" -eq 1 && "$1" == *@ ]]; then
        local -n __ref="${1%[@]}"
        _cmd=("${__ref[@]}")
    elif [[ "$#" -ge 2 ]]; then
        _cmd=("$@")
    else
        _cmd=(bash -lc "$1")
    fi

    if run_cmd _cmd[@]; then
        log_error "assert_failure: command unexpectedly succeeded (${_cmd[*]})"
        return 1
    else
        log_success "assert_failure: ok (failed as expected) (${_cmd[*]})"
        return 0
    fi
}

assert_output() {
    local expected="$1"; shift
    if [[ -z "$expected" ]]; then
        log_error "assert_output: missing expected string"
        return 64
    fi
    local -a _cmd
    if [[ "$#" -eq 1 && "$1" == *@ ]]; then
        local -n __ref="${1%[@]}"
        _cmd=("${__ref[@]}")
    elif [[ "$#" -ge 1 ]]; then
        _cmd=("$@")
    else
        log_error "assert_output: missing command"
        return 64
    fi

    local out
    out="$("${_cmd[@]}" 2>&1)" || true

    if [[ "$out" == "$expected" ]]; then
        log_success "assert_output: matched exactly"
        return 0
    else
        log_error "assert_output: mismatch (expected: '$expected', actual: '$out')"
        return 1
    fi
}

assert_output_contains() {
    local needle="$1"; shift
    if [[ -z "$needle" ]]; then
        log_error "assert_output_contains: missing needle"
        return 64
    fi
    local -a _cmd
    if [[ "$#" -eq 1 && "$1" == *@ ]]; then
        local -n __ref="${1%[@]}"
        _cmd=("${__ref[@]}")
    elif [[ "$#" -ge 1 ]]; then
        _cmd=("$@")
    else
        log_error "assert_output_contains: missing command"
        return 64
    fi

    local out
    out="$("${_cmd[@]}" 2>&1)" || true

    if [[ "$out" == *"$needle"* ]]; then
        log_success "assert_output_contains: found '$needle'"
        return 0
    else
        log_error "assert_output_contains: did not find '$needle' in output"
        return 1
    fi
}

# ============================================================================
# Numeric Assertions
# ============================================================================

assert_greater_than() {
    local actual="$1"
    local threshold="$2"
    local message="${3:-Value should be greater than threshold}"

    if [[ "$actual" -gt "$threshold" ]]; then
        log_debug "PASS $message ($actual > $threshold)"
        return 0
    else
        log_error "FAIL $message ($actual <= $threshold)"
        return 1
    fi
}

assert_less_than() {
    local actual="$1"
    local threshold="$2"
    local message="${3:-Value should be less than threshold}"

    if [[ "$actual" -lt "$threshold" ]]; then
        log_debug "PASS $message ($actual < $threshold)"
        return 0
    else
        log_error "FAIL $message ($actual >= $threshold)"
        return 1
    fi
}

assert_in_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local message="${4:-Value should be in range}"

    if [[ "$value" -ge "$min" ]] && [[ "$value" -le "$max" ]]; then
        log_debug "PASS $message ($min <= $value <= $max)"
        return 0
    else
        log_error "FAIL $message ($value not in [$min, $max])"
        return 1
    fi
}

# ============================================================================
# Test Helpers
# ============================================================================

create_temp_file() {
    local prefix="${1:-test}"
    local content="${2:-}"
    local temp_file
    temp_file="${TEST_WORK_DIR}/${prefix}_$(date +%s)_$$"

    if [[ -n "$content" ]]; then
        echo "$content" > "$temp_file"
    else
        touch "$temp_file"
    fi

    echo "$temp_file"
}

create_temp_dir() {
    local prefix="${1:-testdir}"
    local temp_dir
    temp_dir="${TEST_WORK_DIR}/${prefix}_$(date +%s)_$$"

    mkdir -p "$temp_dir"
    echo "$temp_dir"
}

run_with_setup_teardown() {
    local test_fn="$1"
    local setup_fn="${2:-true}"
    local teardown_fn="${3:-true}"

    if ! "$setup_fn"; then
        log_error "Setup failed for test: $test_fn"
        return 1
    fi

    local exit_code=0
    "$test_fn" || exit_code=$?

    "$teardown_fn"

    return $exit_code
}

mock_command() {
    local cmd="$1"
    local mock_impl="$2"

    eval "function $cmd() { $mock_impl; }"
    # shellcheck disable=SC2163
    export -f "$cmd"
}

unmock_command() {
    local cmd="$1"
    unset -f "$cmd"
}

generate_random_string() {
    local length="${1:-10}"
    local charset="${2:-a-zA-Z0-9}"

    tr -dc "$charset" < /dev/urandom | head -c "$length"
}

generate_test_file() {
    local file="$1"
    local size="$2"

    if command -v dd >/dev/null 2>&1; then
        dd if=/dev/zero of="$file" bs=1 count=0 seek="$size" 2>/dev/null
    else
        head -c "$size" /dev/zero > "$file" 2>/dev/null || true
    fi
}
