#!/usr/bin/env bash

set -e

log() {
  echo "$*" >&2
}

declare -r PERSISTENT_STORAGE_BASE_DIR="/.bottlerocket/host-containers/current"
declare -r SSH_HOST_KEY_DIR="${PERSISTENT_STORAGE_BASE_DIR}/etc/ssh"
declare -r USER_DATA="${PERSISTENT_STORAGE_BASE_DIR}/user-data"

if [ ! -s "${USER_DATA}" ]; then
  log "Admin host-container user-data is empty, going to sleep forever"
  exec sleep infinity
fi

# Fetch user from user-data json (if any). Default to 'ec2-user' if null or invalid.
if ! LOCAL_USER=$(jq -e -r '.["user"] // "ec2-user"' "${USER_DATA}" 2>/dev/null) \
|| [[ ! "${LOCAL_USER}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  log "Failed to set user from user-data. Proceeding with 'ec2-user'."
  LOCAL_USER="ec2-user"
fi

# Fetch password-hash for serial console access.
if ! PASSWORD_HASH=$(jq -r '.["password-hash"] // ""' "${USER_DATA}" 2>/dev/null); then
  PASSWORD_HASH=""
fi

declare -r USER_SSH_DIR="/home/${LOCAL_USER}/.ssh"
declare -r SSHD_CONFIG_DIR="/etc/ssh"
declare -r SSHD_CONFIG_FILE="${SSHD_CONFIG_DIR}/sshd_config"

# This is a counter used to verify at least
# one of the methods below is available.
declare -i available_ssh_methods=0

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

# Set up agetty services for serial console access and the sshd daemon service
enable_systemd_services() {
  # Grab `console=` parameters from the kernel command line.
  CONSOLES=()
  for opt in $(cat /proc/cmdline) ; do
     optarg="$(expr "${opt}" : '[^=]*=\(.*\)' 2>/dev/null ||:)"
     optarg="${optarg%\"}"
     optarg="${optarg#\"}"
     case "${opt}" in
        console=*) CONSOLES+=("${optarg%,*}") ;;
     esac
  done

  HOST_DEVTMPFS="/.bottlerocket/rootfs/dev"
  for console in "${CONSOLES[@]}" ; do
     # Skip devices that don't exist.
     [ -c "${HOST_DEVTMPFS}/${console}" ] || continue

     # Otherwise instantiate a service from the template unit. This is normally
     # done by `systemd-getty-generator`, but that skips over ordinary devices
     # when run inside a container.
     case "${console}" in
        ttyS*|ttyAMA*|ttyUSB*)
           systemctl --user enable "serial-getty@${console}.service"
           ;;
        tty*)
           systemctl --user enable "getty@${console}.service"
           ;;
     esac
  done
  # Enable the SSH daemon service unit so we can run it in the background
  systemctl --user enable "sshd.service"
}

# Create local user
echo "${LOCAL_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${LOCAL_USER}"
chmod 440 "/etc/sudoers.d/${LOCAL_USER}"
# Skip user creation if the user already exists
if ! id -u "${LOCAL_USER}" &>/dev/null; then
  useradd -m "${LOCAL_USER}"
fi
usermod -G users,api "${LOCAL_USER}"
if [[ -z "${PASSWORD_HASH}" ]]; then
  usermod -L "${LOCAL_USER}"
else
  usermod -p "${PASSWORD_HASH}" "${LOCAL_USER}"
fi
mkdir -p "${USER_SSH_DIR}"
chmod 700 "${USER_SSH_DIR}"

# Populate SSH authorized_keys with all the authorized keys found in user-data
if authorized_keys=$(get_user_data_keys "authorized-keys") \
|| authorized_keys=$(get_user_data_keys "authorized_keys"); then
  ssh_authorized_keys="${USER_SSH_DIR}/authorized_keys"
  touch "${ssh_authorized_keys}"
  chmod 600 "${ssh_authorized_keys}"
  echo "${authorized_keys}" > "${ssh_authorized_keys}"
  ((++available_ssh_methods))
fi

# Populate SSH trusted_user_ca_keys with all the trusted ca keys found in user-data
if trusted_user_ca_keys=$(get_user_data_keys "trusted-user-ca-keys") \
|| trusted_user_ca_keys=$(get_user_data_keys "trusted_user_ca_keys"); then
  ssh_trusted_user_ca_keys="/etc/ssh/trusted_user_ca_keys.pub"
  touch "${ssh_trusted_user_ca_keys}"
  chmod 600 "${ssh_trusted_user_ca_keys}"
  echo "${trusted_user_ca_keys}" > "${ssh_trusted_user_ca_keys}"
  ((++available_ssh_methods))
fi

# Set additional SSH configurations
declare authorized_keys_command
if authorized_keys_command=$(jq -e -r '.["ssh"]["authorized-keys-command"]?' "${USER_DATA}"); then
  echo "AuthorizedKeysCommand ${authorized_keys_command}" >> "${SSHD_CONFIG_FILE}"
fi

declare authorized_keys_command_user
if authorized_keys_command_user=$(jq -e -r '.["ssh"]["authorized-keys-command-user"]?' "${USER_DATA}"); then
  echo "AuthorizedKeysCommandUser ${authorized_keys_command_user}" >> "${SSHD_CONFIG_FILE}"
fi

# Populate ciphers with all the ciphers found in user-data
if ciphers=$(jq -r -e -c '.["ssh"]["ciphers"]? | join(",")' "${USER_DATA}" 2>/dev/null); then
  echo "Ciphers ${ciphers}" >> "${SSHD_CONFIG_FILE}"
fi

# Populate KexAlgorithms with all the key exchange algorithms found in user-data
if kex_algorithms=$(jq -r -e -c '.["ssh"]["key-exchange-algorithms"]? | join(",")' "${USER_DATA}" 2>/dev/null); then
  echo "KexAlgorithms ${kex_algorithms}" >> "${SSHD_CONFIG_FILE}"
fi

# Check the configurations are for EC2 Instance Connect
declare -i use_eic=0
if [[ $authorized_keys_command == /opt/aws/bin/eic_run_authorized_keys* ]] \
&& [[ $authorized_keys_command_user == "ec2-instance-connect" ]]; then
  use_eic=1
  ((++available_ssh_methods))
fi

chown -R "${LOCAL_USER}:" "${USER_SSH_DIR}"

# If there were no available SSH auth methods, then users cannot connect via the SSH daemon
if [[ "${available_ssh_methods}" -eq 0 ]]; then
  log "No SSH authentication methods available in admin container user-data"
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

install_proxy_profile

enable_systemd_services

# Persuade systemd that it's OK to run as a user manager.
export XDG_RUNTIME_DIR="/run/user/${UID}"
mkdir -p /run/systemd/system "${XDG_RUNTIME_DIR}"
exec /usr/lib/systemd/systemd --user --unit=admin.target
