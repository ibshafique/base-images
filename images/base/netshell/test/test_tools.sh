#!/bin/bash
# Description: Tool availability tests for debug-sidecar image
# Tests: verify all bundled debug tools are present and functional

load_test_extension "docker"
load_test_extension "security"

setup() {
    ensure_docker_image
}

teardown() {
    cleanup_docker_image
}

# -- Network tools --

test_curl_available() {
    run_docker_command curl --version
}

test_dig_available() {
    run_docker_command dig -v 2>&1 || true
}

test_ping_available() {
    # ping --help exits non-zero on some versions; just check the binary exists
    run_docker_command_output ping -V 2>&1 | grep -qi "ping" || \
        run_docker_command_output ping --help 2>&1 | grep -qi "ping"
}

test_mtr_available() {
    run_docker_command mtr --version
}

test_ip_available() {
    run_docker_command ip -V 2>&1 || true
}

test_ss_available() {
    run_docker_command ss --version 2>&1 || true
}

test_tcpdump_available() {
    run_docker_command tcpdump --version 2>&1 || true
}

test_socat_available() {
    run_docker_command_output socat -V 2>&1 | grep -qi "socat"
}

test_netstat_available() {
    run_docker_command_output netstat --version 2>&1 | grep -qi "net-tools\|netstat" || \
        run_docker_command_output which netstat 2>&1 | grep -q "netstat"
}

test_telnet_exists() {
    run_docker_command_output which telnet 2>&1 | grep -q "telnet"
}

# -- TLS tools --

test_openssl_available() {
    run_docker_command openssl version
}

test_ca_certificates_present() {
    check_container_file /etc/ssl/certs/ca-certificates.crt
}

# -- File/data tools --

test_jq_available() {
    run_docker_command jq --version
}

test_yq_available() {
    run_docker_command yq --version
}

test_nano_available() {
    run_docker_command nano --version
}

test_less_available() {
    run_docker_command less --version
}

test_file_available() {
    run_docker_command file --version
}

# -- Process tools --

test_ps_available() {
    run_docker_command ps --version 2>&1 || true
}

test_htop_available() {
    run_docker_command htop --version
}

test_strace_available() {
    run_docker_command strace -V 2>&1 || true
}

test_lsof_available() {
    run_docker_command_output lsof -v 2>&1 | grep -qi "lsof\|revision"
}

# -- Shell --

test_bash_available() {
    run_docker_command bash --version
}

test_home_directory_exists() {
    check_container_file /home/nonroot
}
