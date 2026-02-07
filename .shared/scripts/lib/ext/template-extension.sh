#!/bin/bash
# Template Extension - Template processing and variable management
# Provides functions for merging templates with variables
#
# Usage:
#   load_extension "template"
#   template_render "template.yaml" "output.yaml" vars_array

# Extract variable names from template file
# Usage: extract_template_vars <template_file>
# Returns: Space-separated list of unique variable names
# Supports {{VARNAME}} format
extract_template_vars() {
    local template_file="$1"

    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    grep -o '{{[A-Z_][A-Z0-9_]*}}' "$template_file" 2>/dev/null | sed 's/{{\(.*\)}}/\1/' | sort -u | tr '\n' ' '
}

# Render a template that uses {{VAR}} placeholders via envsubst.
# Steps:
#   1) Convert {{VAR}} -> ${VAR}
#   2) Pass only variables found in the template via env -i KEY=VALUE ...
# Usage: template_render "in.tmpl" "out.file" "vars_assoc_name"
template_render() {
    local template_file="$1" output_file="$2" assoc_name="$3"
    if [[ -z "$template_file" || -z "$output_file" || -z "$assoc_name" ]]; then
        log_error "template_render: missing arguments (template, output, assoc_name required)"
        return 64
    fi
    if [[ ! -f "$template_file" ]]; then
        log_error "template_render: template not found: $template_file"
        return 66
    fi
    if ! command -v envsubst >/dev/null 2>&1; then
        log_error "template_render: envsubst is required but not found"
        return 127
    fi

    # Reference the associative array by name
    local -n __vars_ref="$assoc_name"

    # Temporary files
    local __tmpout __tmpl
    __tmpout="$(mktemp)" || { log_error "template_render: mktemp failed"; return 70; }
    __tmpl="$(mktemp)" || { log_error "template_render: mktemp failed"; rm -f "$__tmpout"; return 70; }

    # 1) Convert {{VAR}} to ${VAR} for envsubst
    if ! sed -E 's/\{\{([A-Z_][A-Z0-9_]*)\}\}/\$\{\1\}/g' "$template_file" > "$__tmpl"; then
        log_error "template_render: failed to preprocess template $template_file"
        rm -f "$__tmpout" "$__tmpl"
        return 70
    fi

    # Collect variables actually used in the template
    local used_vars
    used_vars="$(extract_template_vars "$template_file" || true)"

    # 2) Build env -i KEY=VALUE ... arguments for envsubst
    local -a env_args=()
    local v
    for v in $used_vars; do
        env_args+=("$v=${__vars_ref[$v]:-}")
    done

    log_debug "template_render: variables (${#env_args[@]}): ${used_vars}"

    # Render with a clean environment plus only the required variables
    if env -i "${env_args[@]}" envsubst < "$__tmpl" > "$__tmpout"; then
        mkdir -p "$(dirname "$output_file")"
        mv -f "$__tmpout" "$output_file"
        rm -f "$__tmpl"
        log_debug "template_render: rendered $(basename "$template_file") -> $(basename "$output_file")"
        return 0
    else
        log_error "template_render: rendering failed for $template_file"
        rm -f "$__tmpout" "$__tmpl"
        return 70
    fi
}

# Deprecated alias
merge_template() {
    local template_file="$1" output_file="$2" assoc_name="$3"
    template_render "$template_file" "$output_file" "$assoc_name"
}

# Validate that all required template variables are provided
# Usage: validate_template_vars <template_file> <variables_array_name>
validate_template_vars() {
    local template_file="$1"
    local -n vars_ref=$2

    local required_vars
    required_vars=$(extract_template_vars "$template_file")

    if [[ -z "$required_vars" ]]; then
        log_warn "No template variables found in $template_file"
        return 0
    fi

    local missing_vars=()
    for var in $required_vars; do
        if [[ -z "${vars_ref[$var]}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required template variables: ${missing_vars[*]}"
        return 1
    fi

    return 0
}
