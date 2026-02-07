# policy/base.rego
# OPA/Conftest policy for Dockerfile validation
# Usage: conftest test images/base/*/Dockerfile -p policy/base.rego

package main

import rego.v1

# Deny running as root (no USER directive or USER root)
deny contains msg if {
    input[i].Cmd == "from"
    not has_user_directive
    msg := "Dockerfile must include a USER directive to run as non-root"
}

deny contains msg if {
    input[i].Cmd == "user"
    user_value := input[i].Value[0]
    user_value in {"root", "0", "0:0"}
    msg := sprintf("USER must not be root (found: %s)", [user_value])
}

# Require OCI labels
deny contains msg if {
    not has_label("org.opencontainers.image.title")
    msg := "Missing required label: org.opencontainers.image.title"
}

deny contains msg if {
    not has_label("org.opencontainers.image.description")
    msg := "Missing required label: org.opencontainers.image.description"
}

deny contains msg if {
    not has_label("org.opencontainers.image.source")
    msg := "Missing required label: org.opencontainers.image.source"
}

# Warn on :latest without digest pin in FROM
warn contains msg if {
    input[i].Cmd == "from"
    val := input[i].Value[0]
    contains(val, ":latest")
    not contains(val, "@sha256:")
    msg := sprintf("FROM uses :latest without digest pin: %s", [val])
}

# Deny ADD (use COPY instead)
deny contains msg if {
    input[i].Cmd == "add"
    not is_multi_stage_copy(input[i])
    msg := "Use COPY instead of ADD for local files"
}

# Warn on running apt/apk without --no-cache or cleanup
warn contains msg if {
    input[i].Cmd == "run"
    val := concat(" ", input[i].Value)
    contains(val, "apt-get install")
    not contains(val, "rm -rf /var/lib/apt")
    msg := "apt-get install without cleanup (add: rm -rf /var/lib/apt/lists/*)"
}

warn contains msg if {
    input[i].Cmd == "run"
    val := concat(" ", input[i].Value)
    contains(val, "apk add")
    not contains(val, "--no-cache")
    msg := "apk add without --no-cache flag"
}

# Helper: check if USER directive exists
has_user_directive if {
    input[i].Cmd == "user"
}

# Helper: check if a label exists
has_label(name) if {
    input[i].Cmd == "label"
    input[i].Value[j] == name
}

# Helper: check if ADD is a multi-stage copy (e.g., ADD --from=...)
is_multi_stage_copy(cmd) if {
    some flag in cmd.Flags
    startswith(flag, "--from=")
}
