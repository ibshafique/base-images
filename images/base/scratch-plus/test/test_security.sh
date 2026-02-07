#!/bin/bash
# Description: Security tests for scratch-plus base image
# Tests: non-root user, no shell, read-only fs, no package managers, image size, OCI labels

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

test_has_no_shell() {
    assert_container_has_no_shell
}

test_works_read_only() {
    assert_container_works_read_only
}

test_works_without_capabilities() {
    assert_container_works_no_caps
}

test_has_no_package_managers() {
    assert_no_package_managers
}

test_image_is_minimal() {
    assert_image_size_under 20 "scratch-plus should be under 20MB"
}

test_has_required_oci_labels() {
    assert_has_oci_labels
}

test_title_label() {
    assert_label_value "org.opencontainers.image.title" "scratch-plus"
}
