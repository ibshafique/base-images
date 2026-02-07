#!/bin/bash
# Test Core - Test execution framework for the build system

# ============================================================================
# Test Configuration
# ============================================================================

declare -g TEST_SUITES_PASSED=0
declare -g TEST_SUITES_FAILED=0
declare -g TEST_SUITES_SKIPPED=0
declare -g TEST_SUITES_TOTAL=0

declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -g TEST_SKIPPED=0
declare -g TEST_TOTAL=0

export CURRENT_TEST=""
export TEST_SUITE=""
declare -ga TEST_ERRORS=()

declare -gA LOADED_TEST_EXTENSIONS=()

# ============================================================================
# Test Extension Management
# ============================================================================

load_test_extension() {
    local extension_name="$1"

    if [[ "${LOADED_TEST_EXTENSIONS[$extension_name]:-}" == "true" ]]; then
        log_debug "Test extension already loaded: ${extension_name}"
        return 0
    fi

    local extension_file="${SHARED_TEST_EXT_DIR}/${extension_name}-extension.sh"

    if [[ ! -f "$extension_file" ]]; then
        log_error "Test extension not found: ${extension_name}"
        log_debug "Looking for: $extension_file"
        return 1
    fi

    log_debug "Loading test extension: ${extension_name}"
    # shellcheck source=/dev/null
    if source "$extension_file"; then
        LOADED_TEST_EXTENSIONS[$extension_name]="true"
        log_debug "Test extension loaded successfully: ${extension_name}"
        return 0
    else
        log_error "Failed to load test extension: ${extension_name}"
        return 1
    fi
}

# ============================================================================
# Test Execution
# ============================================================================

run_tests() {
    local pattern="${1:-${TEST_DIR}/*.sh}"
    local test_files=()

    if [[ -d "${TEST_DIR}" ]]; then
        while IFS= read -r -d '' file; do
            test_files+=("$file")
        done < <(find "${TEST_DIR}" -name "*.sh" -type f -print0 2>/dev/null | sort -z)
    fi

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warn "No test files found matching pattern: $pattern"
        return 0
    fi

    log_section "Running Tests"
    log_info "Found ${#test_files[@]} test file(s)"

    for test_file in "${test_files[@]}"; do
        run_test_file "$test_file"
    done

    show_test_summary

    [[ $TEST_FAILED -eq 0 ]]
}

run_test_file() {
    local test_file="$1"
    local test_name
    test_name="$(basename "$test_file" .sh)"

    TEST_SUITE="$test_name"
    log_info "Running test suite: $test_name"

    if should_skip_test "$test_name"; then
        ((TEST_SUITES_SKIPPED++))
        ((TEST_SUITES_TOTAL++))
        log_test_result "$test_name" "SKIP"
        return 0
    fi

    setup_test_env "$test_name"

    local start_time
    start_time=$(date +%s)
    local exit_code=0

    (
        [[ -f "${SHARED_TEST_LIB_DIR}/test-utils.sh" ]] && source "${SHARED_TEST_LIB_DIR}/test-utils.sh"

        export -f load_test_extension 2>/dev/null

        local functions_before
        functions_before=$(declare -F | awk '{print $3}')

        # shellcheck source=/dev/null
        source "$test_file"

        local functions_after
        functions_after=$(declare -F | awk '{print $3}')

        if declare -f test_main > /dev/null 2>&1; then
            test_main
        else
            local test_count=0
            local test_passed=0
            local test_failed=0

            if declare -f setup > /dev/null 2>&1; then
                log_debug "Running setup"
                setup || { log_error "Setup failed"; exit 1; }
            fi

            local test_functions=""
            for fn in $functions_after; do
                if echo "$functions_before" | grep -q "^$fn$"; then
                    continue
                fi
                [[ "$fn" == test_* ]] && test_functions="$test_functions $fn"
            done

            test_functions="${test_functions# }"

            if [[ -z "$test_functions" ]]; then
                log_warn "No test functions found (looking for test_* functions)"
                exit 1
            fi

            for test_fn in $test_functions; do
                ((test_count++))
                local display_name="${test_fn#test_}"
                display_name="${display_name//_/ }"
                log_info "Testing: $display_name"
                if $test_fn; then
                    ((test_passed++))
                    log_success "PASS $display_name"
                else
                    ((test_failed++))
                    log_error "FAIL $display_name"
                fi
                log_separator "-" 40
            done

            if declare -f teardown > /dev/null 2>&1; then
                log_debug "Running teardown"
                teardown || log_warn "Teardown failed"
            fi

            log_info "Test results: $test_passed passed, $test_failed failed out of $test_count"

            echo "$test_count $test_passed $test_failed" > "${TEST_WORK_DIR}/.test_counts"

            [[ $test_failed -eq 0 ]]
        fi
    )
    exit_code=$?

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ -f "${TEST_WORK_DIR}/.test_counts" ]]; then
        local count passed failed
        read -r count passed failed < "${TEST_WORK_DIR}/.test_counts"
        ((TEST_TOTAL += count))
        ((TEST_PASSED += passed))
        ((TEST_FAILED += failed))
        rm -f "${TEST_WORK_DIR}/.test_counts"
    else
        ((TEST_TOTAL++))
        if [[ $exit_code -eq 0 ]]; then
            ((TEST_PASSED++))
        else
            ((TEST_FAILED++))
        fi
    fi

    if [[ $exit_code -eq 0 ]]; then
        ((TEST_SUITES_PASSED++))
        log_test_result "$test_name" "PASS"
        log_debug "Test completed in ${duration}s"
    else
        ((TEST_SUITES_FAILED++))
        TEST_ERRORS+=("$test_name: exit code $exit_code")
        log_test_result "$test_name" "FAIL"
        log_error "Test failed after ${duration}s with exit code $exit_code"
    fi

    ((TEST_SUITES_TOTAL++))

    cleanup_test_env "$test_name"
}

should_skip_test() {
    local test_name="$1"

    if has_param "test_pattern"; then
        local pattern
        pattern="$(get_param test_pattern)"
        [[ "$test_name" =~ $pattern ]] || return 0
    fi

    if has_param "test_exclude"; then
        local exclude
        exclude="$(get_param test_exclude)"
        [[ "$test_name" =~ $exclude ]] && return 0
    fi

    return 1
}

# ============================================================================
# Test Environment Management
# ============================================================================

setup_test_env() {
    local test_name="$1"
    local test_work_dir="${BUILD_DIR}/test/work/${test_name}"

    rm -rf "$test_work_dir"
    mkdir -p "$test_work_dir"

    export TEST_NAME="$test_name"
    export TEST_WORK_DIR="$test_work_dir"
    export TEST_BUILD_DIR="${BUILD_DIR}"

    log_debug "Test environment set up for: $test_name"
}

cleanup_test_env() {
    local test_name="$1"
    local test_work_dir="${BUILD_DIR}/test/work/${test_name}"

    if ! is_flag_set "--keep-test-files"; then
        rm -rf "$test_work_dir"
    else
        log_debug "Keeping test files for debugging: $test_work_dir"
    fi

    unset TEST_NAME TEST_WORK_DIR TEST_BUILD_DIR
}

# ============================================================================
# Test Helpers
# ============================================================================

test_command() {
    local expected_exit="${1:-0}"
    shift

    local -a _cmd
    if [[ "$#" -eq 1 && "$1" == *@ ]]; then
        local -n __ref="${1%[@]}"
        _cmd=("${__ref[@]}")
    elif [[ "$#" -ge 2 ]]; then
        _cmd=("$@")
    elif [[ "$#" -eq 1 ]]; then
        _cmd=(bash -lc "$1")
    else
        log_error "test_command: missing command"
        return 64
    fi

    log_debug "Testing command: ${_cmd[*]}"

    local actual_exit=0
    if run_cmd _cmd[@]; then
        actual_exit=0
    else
        actual_exit=$?
    fi

    if [[ $actual_exit -eq $expected_exit ]]; then
        log_debug "Command exit code matched: $actual_exit"
        return 0
    else
        log_error "Command exit code mismatch"
        log_error "  Expected: $expected_exit"
        log_error "  Actual: $actual_exit"
        return 1
    fi
}

test_with_timeout() {
    local timeout="$1"
    shift
    local test_fn="$1"
    shift

    log_debug "Running test with ${timeout}s timeout: $test_fn"

    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout" bash -c "$test_fn $*"
    else
        "$test_fn" "$@"
    fi
}

skip_test() {
    local reason="${1:-No reason provided}"
    log_warn "Test skipped: $reason"
    exit 77
}

expect_fail() {
    local test_fn="$1"
    shift

    log_debug "Expecting test to fail: $test_fn"

    if "$test_fn" "$@"; then
        log_error "Test unexpectedly passed (expected to fail)"
        return 1
    else
        log_success "Test failed as expected"
        return 0
    fi
}

# ============================================================================
# Test Reporting
# ============================================================================

show_test_summary() {
    log_test_summary "$TEST_PASSED" "$TEST_FAILED" "$TEST_SKIPPED"

    if [[ $TEST_FAILED -gt 0 ]] && [[ ${#TEST_ERRORS[@]} -gt 0 ]]; then
        log_error "Failed tests:"
        for error in "${TEST_ERRORS[@]}"; do
            log_error "  - $error"
        done
    fi

    save_test_report
}

save_test_report() {
    local report_file="${BUILD_DIR}/test/test-report.txt"

    {
        echo "Test Report - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=================================="
        echo "Total:   $TEST_TOTAL"
        echo "Passed:  $TEST_PASSED"
        echo "Failed:  $TEST_FAILED"
        echo "Skipped: $TEST_SKIPPED"
        echo ""

        if [[ ${#TEST_ERRORS[@]} -gt 0 ]]; then
            echo "Failed Tests:"
            for error in "${TEST_ERRORS[@]}"; do
                echo "  - $error"
            done
        fi
    } > "$report_file"

    log_debug "Test report saved to: $report_file"
}

generate_junit_report() {
    local report_file="${BUILD_DIR}/test/junit-report.xml"

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<testsuites>'
        echo "  <testsuite name=\"${MODULE_DIR##*/}\" tests=\"$TEST_TOTAL\" failures=\"$TEST_FAILED\" skipped=\"$TEST_SKIPPED\">"
        echo "  </testsuite>"
        echo '</testsuites>'
    } > "$report_file"

    log_debug "JUnit report saved to: $report_file"
}

discover_tests() {
    local test_files=()

    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "${TEST_DIR}" -name "*.sh" -type f -print0 2>/dev/null | sort -z)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_info "No tests found in ${TEST_DIR}"
        return 0
    fi

    log_info "Available tests:"
    for test_file in "${test_files[@]}"; do
        local test_name
        test_name="$(basename "$test_file" .sh)"
        local test_desc=""

        if grep -q "^# Description:" "$test_file"; then
            test_desc="$(grep "^# Description:" "$test_file" | head -1 | cut -d':' -f2- | xargs)"
        fi

        if [[ -n "$test_desc" ]]; then
            log_info "  - $test_name: $test_desc"
        else
            log_info "  - $test_name"
        fi
    done
}
