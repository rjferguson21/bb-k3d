#!/usr/bin/env bash

# Source this file to export registry credentials from overrides YAML.
# Usage:
#   source ./mac/source-registry-creds.sh
#   source ./mac/source-registry-creds.sh /path/to/registryOverrides.yaml

_bbk3d_return() {
  return "$1" 2>/dev/null || exit "$1"
}

if [ -n "${BASH_SOURCE[0]:-}" ]; then
  _bbk3d_script_path="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _bbk3d_script_path="${(%):-%N}"
else
  _bbk3d_script_path="$0"
fi

_bbk3d_script_dir="$(cd "$(dirname "${_bbk3d_script_path}")" && pwd)"
_bbk3d_default_overrides="${_bbk3d_script_dir}/../../overrides/registryOverrides.yaml"
_bbk3d_overrides_file="${1:-${_bbk3d_default_overrides}}"

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq is required but was not found in PATH." >&2
  _bbk3d_return 1
fi

if [ ! -f "${_bbk3d_overrides_file}" ]; then
  echo "ERROR: overrides file not found: ${_bbk3d_overrides_file}" >&2
  _bbk3d_return 1
fi

_bbk3d_registry="$(yq -r '.registryCredentials.registry // ""' "${_bbk3d_overrides_file}")"
_bbk3d_username="$(yq -r '.registryCredentials.username // ""' "${_bbk3d_overrides_file}")"
_bbk3d_password="$(yq -r '.registryCredentials.password // ""' "${_bbk3d_overrides_file}")"
_bbk3d_email="$(yq -r '.registryCredentials.email // ""' "${_bbk3d_overrides_file}")"

if [ -z "${_bbk3d_username}" ] || [ -z "${_bbk3d_password}" ]; then
  echo "ERROR: expected .registryCredentials.username and .registryCredentials.password in ${_bbk3d_overrides_file}" >&2
  _bbk3d_return 1
fi

export REGISTRY1_USERNAME="${_bbk3d_username}"
export REGISTRY1_PASSWORD="${_bbk3d_password}"

if [ -n "${_bbk3d_email}" ]; then
  export REGISTRY1_EMAIL="${_bbk3d_email}"
fi

if [ -n "${_bbk3d_registry}" ]; then
  export REGISTRY1_HOST="${_bbk3d_registry}"
fi

# Compatibility aliases for users who prefer REGISTRY_1_* naming.
export REGISTRY_1_USERNAME="${REGISTRY1_USERNAME}"
export REGISTRY_1_PASSWORD="${REGISTRY1_PASSWORD}"
if [ -n "${REGISTRY1_EMAIL:-}" ]; then
  export REGISTRY_1_EMAIL="${REGISTRY1_EMAIL}"
fi
if [ -n "${REGISTRY1_HOST:-}" ]; then
  export REGISTRY_1_HOST="${REGISTRY1_HOST}"
fi

echo "Exported REGISTRY1_* (and REGISTRY_1_*) from ${_bbk3d_overrides_file}"

unset _bbk3d_script_path
unset _bbk3d_script_dir
unset _bbk3d_default_overrides
unset _bbk3d_overrides_file
unset _bbk3d_registry
unset _bbk3d_username
unset _bbk3d_password
unset _bbk3d_email
unset -f _bbk3d_return
