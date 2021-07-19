#!/usr/bin/env bash

set -e

declare -r PERSISTENT_STORAGE_BASE_DIR="/.bottlerocket/host-containers/current"
declare -r SSH_HOST_KEY_DIR="${PERSISTENT_STORAGE_BASE_DIR}/etc/ssh"
declare -r USER_DATA="${PERSISTENT_STORAGE_BASE_DIR}/user-data"

declare -r LOCAL_USER="ec2-user"
declare -r USER_SSH_DIR="/home/${LOCAL_USER}/.ssh"
declare -r SSHD_CONFIG_DIR="/etc/ssh"
declare -r SSHD_CONFIG_FILE="${SSHD_CONFIG_DIR}/sshd_config"

# This is a counter used to verify at least
# one of the methods below is available.
declare -i available_auth_methods=0

log() {
  echo "$*" >&2
}

get_user_data_keys() {
    # Extract the keys from user-data json
    local raw_keys
    local key_type="${1:?}"
    # ? signifies an optional object identifier-index and doesn't return a
    # 'failed to iterate' error in the event that a key_type is missing.
    if ! raw_keys=$(jq --arg key_type "${key_type}" -e -r '.["ssh"][$key_type][]?' "${USER_DATA}"); then
      return 1
    fi

    # Verify jq returned key(s)
    if [[ -z "${raw_keys}" ]]; then
      return 1
    fi

    # Map the keys to avoid improper splitting
    local mapped_keys
    mapfile -t mapped_keys <<< "${raw_keys}"

    # Verify the keys are valid
    local key
    local -a valid_keys
    for key in "${mapped_keys[@]}"; do
      if ! echo "${key}" | ssh-keygen -lf - &>/dev/null; then
        log "Failed to validate ${key}"
        continue
      fi
      valid_keys+=( "${key}" )
    done

    ( IFS=$'\n'; echo "${valid_keys[*]}" )
}

# Export proxy environment variables for all users' login shells
# Match the values of the proxy environment variables given to the admin container
install_proxy_profile() {
  local -r proxy_profile="/etc/profile.d/bottlerocket-proxy-settings.sh"
  cat > "${proxy_profile}" <<EOF
# Export Bottlerocket proxy environment variables
$(declare -p HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY 2>/dev/null)
EOF
  chmod 644 "${proxy_profile}"
}

mkdir -p "${USER_SSH_DIR}"
chmod 700 "${USER_SSH_DIR}"

# Populate authorized_keys with all the authorized keys found in user-data
if authorized_keys=$(get_user_data_keys "authorized-keys") \
|| authorized_keys=$(get_user_data_keys "authorized_keys"); then
  ssh_authorized_keys="${USER_SSH_DIR}/authorized_keys"
  touch "${ssh_authorized_keys}"
  chmod 600 "${ssh_authorized_keys}"
  echo "${authorized_keys}" > "${ssh_authorized_keys}"
  ((++available_auth_methods))
fi

# Populate trusted_user_ca_keys with all the trusted ca keys found in user-data
if trusted_user_ca_keys=$(get_user_data_keys "trusted-user-ca-keys") \
|| trusted_user_ca_keys=$(get_user_data_keys "trusted_user_ca_keys"); then
  ssh_trusted_user_ca_keys="/etc/ssh/trusted_user_ca_keys.pub"
  touch "${ssh_trusted_user_ca_keys}"
  chmod 600 "${ssh_trusted_user_ca_keys}"
  echo "${trusted_user_ca_keys}" > "${ssh_trusted_user_ca_keys}"
  ((++available_auth_methods))
fi

# Set additional configurations
declare authorized_keys_command
if authorized_keys_command=$(jq -e -r '.["ssh"]["authorized-keys-command"]?' "${USER_DATA}"); then
  echo "AuthorizedKeysCommand ${authorized_keys_command}" >> "${SSHD_CONFIG_FILE}"
fi

declare authorized_keys_command_user
if authorized_keys_command_user=$(jq -e -r '.["ssh"]["authorized-keys-command-user"]?' "${USER_DATA}"); then
  echo "AuthorizedKeysCommandUser ${authorized_keys_command_user}" >> "${SSHD_CONFIG_FILE}"
fi

# Populate ciphers with all the ciphers found in user-data
if ciphers=$(jq -c '.["ssh"]["ciphers"]?' "${USER_DATA}" | tr -d '[]"'); then
  echo "Ciphers ${ciphers}" >> "${SSHD_CONFIG_FILE}"
fi

# Check the configurations are for EC2 instance connect
declare -i use_eic=0
if [[ $authorized_keys_command == /opt/aws/bin/eic_run_authorized_keys* ]] \
&& [[ $authorized_keys_command_user == "ec2-instance-connect" ]]; then
  use_eic=1
  ((++available_auth_methods))
fi

chown -R "${LOCAL_USER}:" "${USER_SSH_DIR}"

# If there were no successful auth methods, then users cannot authenticate
if [[ "${available_auth_methods}" -eq 0 ]]; then
  user_data_condensed=$(jq -e -c . "${USER_DATA}" 2>/dev/null || cat "${USER_DATA}")
  log "Failed to configure ssh authentication with user-data: ${user_data_condensed}"
fi

# Generate the server keys
mkdir -p "${SSH_HOST_KEY_DIR}"
for key_alg in rsa ecdsa ed25519; do
  # If both of the keys exist, don't overwrite them
  if [[ -s "${SSH_HOST_KEY_DIR}/ssh_host_${key_alg}_key" ]] \
  && [[ -s "${SSH_HOST_KEY_DIR}/ssh_host_${key_alg}_key.pub" ]]; then
    ln -sf "${SSH_HOST_KEY_DIR}/ssh_host_${key_alg}_key.pub" "${SSHD_CONFIG_DIR}/ssh_host_${key_alg}_key.pub"
    log "${key_alg} key already exists, will use existing key."
    continue
  fi

  rm -rf \
    "${SSH_HOST_KEY_DIR}/ssh_host_${key_alg}_key" \
    "${SSH_HOST_KEY_DIR}/ssh_host_${key_alg}_key.pub"
  if ssh-keygen -t "${key_alg}" -f "${SSH_HOST_KEY_DIR}/ssh_host_${key_alg}_key" -q -N ""; then
    chmod 600 "${SSH_HOST_KEY_DIR}/ssh_host_${key_alg}_key"
    chmod 644 "${SSH_HOST_KEY_DIR}/ssh_host_${key_alg}_key.pub"
    ln -sf "${SSH_HOST_KEY_DIR}/ssh_host_${key_alg}_key.pub" "${SSHD_CONFIG_DIR}/ssh_host_${key_alg}_key.pub"
  else
    log "Failure to generate host ${key_alg} ssh keys"
  fi
done


if [[ ${use_eic} == 1 ]] && [[ ! -f "${SSH_HOST_KEY_DIR}/harvest" ]]; then
  if ! /opt/aws/bin/eic_harvest_hostkeys; then
    log "Failure to harvest hostkeys for EIC"
  fi
  touch "${SSH_HOST_KEY_DIR}/harvest"
fi

install_proxy_profile

# Start a single sshd process in the foreground
exec /usr/sbin/sshd -e -D
