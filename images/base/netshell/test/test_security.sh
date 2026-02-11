#!/bin/bash
# Description: Security tests for netshell image
# Tests: non-root user, no SUID, no package managers, read-only fs, image size, OCI labels

load_test_extension "docker"
load_test_extension "security"

setup() {
    ensure_docker_image
}

teardown() {
    cleanup_docker_image
}

test_runs_as_non_root() {
    assert_container_non_root
}

test_user_is_65532() {
    assert_container_user_id "65532"
}

test_has_no_package_managers() {
    assert_no_package_managers
}

test_no_suid_binaries() {
    local output
    output=$(run_docker_command_output find / -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null)
    local count
    count=$(echo "$output" | grep -c '^/' || true)
    if [[ "$count" -eq 0 ]]; then
        log_debug "No SUID/SGID binaries found"
        return 0
    else
        log_error "Found $count SUID/SGID binaries: $output"
        return 1
    fi
}

test_works_read_only() {
    assert_container_works_read_only
}

test_works_without_capabilities() {
    assert_container_works_no_caps
}

test_image_size_under_50mb() {
    assert_image_size_under 50 "netshell should be under 50MB"
}

test_has_required_oci_labels() {
    assert_has_oci_labels
}

test_title_label() {
    assert_label_value "org.opencontainers.image.title" "netshell"
}
