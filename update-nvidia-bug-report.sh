#!/bin/bash
set -euo pipefail

# Update nvidia-bug-report.sh from the NVIDIA driver installer.
#
# Usage: ./update-nvidia-bug-report.sh <version>
# Example: ./update-nvidia-bug-report.sh 580.126.09

VERSION="${1:?Usage: $0 <driver-version>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "${WORKDIR}"' EXIT

URL="https://us.download.nvidia.com/tesla/${VERSION}/NVIDIA-Linux-x86_64-${VERSION}.run"
RUN_FILE="${WORKDIR}/NVIDIA-Linux-x86_64-${VERSION}.run"
EXTRACT_DIR="${WORKDIR}/nvidia-driver"

echo "Downloading NVIDIA driver ${VERSION}..."
curl -sL -o "${RUN_FILE}" "${URL}"
chmod +x "${RUN_FILE}"

echo "Extracting..."
"${RUN_FILE}" --extract-only --target "${EXTRACT_DIR}"

SRC="${EXTRACT_DIR}/nvidia-bug-report.sh"
if [ ! -f "${SRC}" ]; then
    echo "Error: nvidia-bug-report.sh not found in extracted driver"
    exit 1
fi

DST="${SCRIPT_DIR}/nvidia-bug-report.sh"

echo "Applying Bottlerocket patches..."

# Start with the upstream script
cp "${SRC}" "${DST}"

# Apply Bottlerocket preamble patch
patch -p0 < "${SCRIPT_DIR}/patches/nvidia-bug-report-bottlerocket.patch"

# Prefix /etc/* paths with ${HOST_ROOT}
sed -i 's|append "/etc/|append "${HOST_ROOT}/etc/|g' "${DST}"
sed -i 's|append_silent "/etc/|append_silent "${HOST_ROOT}/etc/|g' "${DST}"
sed -i 's|append_file_or_dir_silent "/etc/|append_file_or_dir_silent "${HOST_ROOT}/etc/|g' "${DST}"
sed -i 's|cat /etc/passwd|cat ${HOST_ROOT}/etc/passwd|g' "${DST}"
sed -i 's|\[ -f /etc/os-release \]|[ -f ${HOST_ROOT}/etc/os-release ]|g' "${DST}"
sed -i "s|grep '\^PRETTY_NAME=' /etc/os-release|grep '^PRETTY_NAME=' \${HOST_ROOT}/etc/os-release|g" "${DST}"
sed -i 's|ls -d /etc/vulkan/|ls -d ${HOST_ROOT}/etc/vulkan/|g' "${DST}"
sed -i 's|ls -d /etc/xdg/vulkan/|ls -d ${HOST_ROOT}/etc/xdg/vulkan/|g' "${DST}"
sed -i 's|ls -d /etc/vulkansc/|ls -d ${HOST_ROOT}/etc/vulkansc/|g' "${DST}"
sed -i 's|ls -d /etc/xdg/vulkansc/|ls -d ${HOST_ROOT}/etc/xdg/vulkansc/|g' "${DST}"

# Prefix /var/log/* paths with ${HOST_ROOT}
sed -i 's|run_query_file "/var/log/|run_query_file "${HOST_ROOT}/var/log/|g' "${DST}"
sed -i 's|append "/var/log/|append "${HOST_ROOT}/var/log/|g' "${DST}"
sed -i 's|append_silent "/var/log/|append_silent "${HOST_ROOT}/var/log/|g' "${DST}"
sed -i 's|log_filename="/var/log/|log_filename="${HOST_ROOT}/var/log/|g' "${DST}"
sed -i 's|search_string_in_logs /var/log/|search_string_in_logs ${HOST_ROOT}/var/log/|g' "${DST}"

# Prefix /var/lib/dkms/* paths with ${HOST_ROOT}
sed -i 's|\[ -d "/var/lib/dkms/nvidia" \]|[ -d "${HOST_ROOT}/var/lib/dkms/nvidia" ]|g' "${DST}"
sed -i 's|find "/var/lib/dkms/nvidia"|find "${HOST_ROOT}/var/lib/dkms/nvidia"|g' "${DST}"

# Fix hostname: use /proc/sys/kernel/hostname instead of hostname command
sed -i 's/$(hostname)/$(cat \/proc\/sys\/kernel\/hostname 2>\/dev\/null || uname -n)/g' "${DST}"

# Fix OS Details detection: use uname instead of lsb_release to avoid early return
sed -i 's/run_query "lsb_release" "-d" "OS Details"/run_query "uname" "-r" "OS Details"/g' "${DST}"

echo "Updated nvidia-bug-report.sh to version ${VERSION} with Bottlerocket patches"
