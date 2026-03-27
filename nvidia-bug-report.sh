#!/bin/sh
#
# SPDX-FileCopyrightText: Copyright (c) 2004-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: MIT
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#

PATH="/sbin:/usr/sbin:$PATH"

BASE_LOG_FILENAME="nvidia-bug-report.log"

# Bottlerocket: host root filesystem prefix
HOST_ROOT="${HOST_ROOT:-}"
if [ -d "/.bottlerocket/rootfs" ]; then
    HOST_ROOT="/.bottlerocket/rootfs"
    # Install required tools in admin container
    dnf install -y -q which dmidecode acpica-tools 2>/dev/null || true
fi

# Bottlerocket: wrapper functions for host binaries
if [ -d "/.bottlerocket/rootfs" ]; then
    __host_run() { chroot /.bottlerocket/rootfs "$@"; }
    journalctl() { __host_run /usr/bin/journalctl "$@"; }
    systemctl() { __host_run /usr/bin/systemctl "$@"; }
fi
# check if gzip is present
GZIP_CMD=`which gzip 2> /dev/null | head -n 1`
if [ $? -eq 0 -a "$GZIP_CMD" ]; then
    GZIP_CMD="gzip -c"
else
    GZIP_CMD="cat"
fi

DPY="$DISPLAY"
[ "$DPY" ] || DPY=":0"

set_filename() {
    if [ "$GZIP_CMD" = "gzip -c" ]; then
        LOG_FILENAME="$BASE_LOG_FILENAME.gz"
        OLD_LOG_FILENAME="$BASE_LOG_FILENAME.old.gz"
    else
        LOG_FILENAME=$BASE_LOG_FILENAME
        OLD_LOG_FILENAME="$BASE_LOG_FILENAME.old"
    fi
}



query_order=""

separator_single="--------------------------------------------------------------------------------"
separator_double="================================================================================"

# Create temporary files to store skip and error summary entries.
SKIP_TMP=$(mktemp /tmp/nvidia_bug_report_skip.XXXXXX)
ERROR_TMP=$(mktemp /tmp/nvidia_bug_report_error.XXXXXX)

store_result() {
    description="$1"  # e.g., "NVIDIA GPU Details"
    details="$2"      # Details to display

    # Create a sanitized version of the description for variable names
    desc_sanitized=`echo "$description" | tr -c '[:alnum:]_' '_'` 

    # We'll store "SANITIZED|ORIGINAL" on one line (single-char delimiter).
    line_item="$desc_sanitized|$description"

    query_order="$query_order
$line_item"
    eval "results_details_${desc_sanitized}=\"\$details\""
}

store_skip() {
    description="$1"
    details="$2"
    description=$(echo "$description" | tr '\n' ' ')
    details=$(echo "$details"       | tr '\n' ' ')
    echo "$description|$details" >> "$SKIP_TMP"
}

store_error() {
    description="$1"
    details="$2"
    # Trim any leading/trailing whitespace from resolution.
    resolution=$(echo "$3" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    description=$(echo "$description" | tr '\n' ' ')
    details=$(echo "$details"       | tr '\n' ' ')
    resolution=$(echo "$resolution" | tr '\n' ' ')
    printf "%s|%s|%s\n" "$description" "$details" "$resolution" >> "$ERROR_TMP"
}

report_skip() {
    description="$1"
    details="$2"
    {
       echo "____________________________________________"
       echo ""
       echo "Skipping: $description"
       echo "$details"
       echo ""
    } | $GZIP_CMD >> "$LOG_FILENAME"
    store_skip "$description" "$details"
}

report_and_store_error() {
    description="$1"
    details="$2"
    exit_block="$3"  # Optional parameter to indicate whether to exit the block
    resolution="$4"
    if [ -z "$resolution" ]; then
        resolution="Contact NVIDIA for support"
    fi
    
    store_error "$description" "$details" "$resolution"

    {
       echo "____________________________________________"
       echo ""
       echo "Error: $description"
       echo "$details"
       echo "Resolution: $resolution"
       echo ""
    } | $GZIP_CMD >> "$LOG_FILENAME"

    if [ "$exit_block" = "1" ]; then
        echo "Exiting current block due to critical error: $description" | $GZIP_CMD >> "$LOG_FILENAME"
        exit 1  # Exit the subshell to stop the current block
    fi
}

print_skips_table() {
    col1_header="Skipped Component"
    col1_width=35

    printf "%-${col1_width}s | Details\n" "$col1_header"
    echo "$separator_double"

    DETAIL_WIDTH=60
    while IFS='|' read -r description details; do
        [ -z "$description" ] && continue
        wrapped=$(printf '%s\n' "$details" | fold -s -w $DETAIL_WIDTH)
        first_line=$(printf '%s\n' "$wrapped" | sed -n '1p')
        printf "%-${col1_width}s | %s\n" "$description" "$first_line"
        rest_lines=$(printf '%s\n' "$wrapped" | sed '1d')
        if [ -n "$rest_lines" ]; then
            echo "$rest_lines" | while IFS= read -r detail_line; do
                printf "%-${col1_width}s | %s\n" "" "$detail_line"
            done
        fi
        echo "$separator_single"
    done < "$SKIP_TMP"
}

print_errors_table() {
    col1_width=35
    col2_width=60
    col3_width=20
    header=$(printf "%-${col1_width}s | %-${col2_width}s | %-${col3_width}s" "Error Component" "Details" "Resolution")
    sep_line=$(printf '%*s' $(expr $col1_width + $col2_width + $col3_width + 6) '' | tr ' ' '=')
    echo "$header"
    echo "$sep_line"
    while IFS='|' read -r comp details resolution; do
        [ -z "$comp" ] && continue

        comp_wrapped=$(printf '%s\n' "$comp" | fold -s -w $col1_width)
        details_wrapped=$(printf '%s\n' "$details" | fold -s -w $col2_width)
        resolution_wrapped=$(printf '%s\n' "$resolution" | fold -s -w $col3_width)

        comp_lines=$(printf '%s\n' "$comp_wrapped")
        details_lines=$(printf '%s\n' "$details_wrapped")
        resolution_lines=$(printf '%s\n' "$resolution_wrapped")
        comp_count=$(printf '%s\n' "$comp_lines" | wc -l | sed 's/ //g')
        details_count=$(printf '%s\n' "$details_lines" | wc -l | sed 's/ //g')
        resolution_count=$(printf '%s\n' "$resolution_lines" | wc -l | sed 's/ //g')
        max_lines=$(printf "%s\n" "$comp_count" "$details_count" "$resolution_count" | sort -nr | head -n 1)
        i=1
        while [ $i -le $max_lines ]; do
            comp_line=$(printf '%s\n' "$comp_lines" | sed -n "${i}p")
            details_line=$(printf '%s\n' "$details_lines" | sed -n "${i}p")
            resolution_line=$(printf '%s\n' "$resolution_lines" | sed -n "${i}p")
            printf "%-${col1_width}s | %-${col2_width}s | %-${col3_width}s\n" "$comp_line" "$details_line" "$resolution_line"
            i=$(expr $i + 1)
        done
        sep_line_single=$(printf '%*s' $(expr $col1_width + $col2_width + $col3_width + 6) '' | tr ' ' '-')
        echo "$sep_line_single"
    done < "$ERROR_TMP"
}

print_versions_table() {
    order_list="$query_order"
    col1_header="Component"

    col1_width=35

    # Print header
    printf "%-${col1_width}s | Details\n" "$col1_header"
    echo "$separator_double"

    echo "$order_list" | while IFS= read -r line
    do
        # Skip blank lines
        [ -z "$line" ] && continue

        # Extract sanitized + original description
        sanitized="$(printf '%s' "$line" | cut -f1 -d'|')"
        original="$(printf '%s' "$line" | cut -f2- -d'|')"

        # Retrieve details from dynamic variables
        eval details="\$results_details_${sanitized}"

        # If details is empty, print "None" in the details column
        if [ -z "$details" ]; then
            details="None"
        fi

        # Split details into first line + rest
        first_line="$(printf '%s\n' "$details" | sed -n '1p')"
        printf "%-${col1_width}s | %s\n" "$original" "$first_line"

        rest_lines="$(printf '%s\n' "$details" | sed '1d')"
        if [ -n "$rest_lines" ]; then
            echo "$rest_lines" | while IFS= read -r detail_line
            do
                printf "%-${col1_width}s | %s\n" "" "$detail_line"
            done
        fi

        echo "$separator_single"
    done
}

parse_ibv_devinfo() {
    dev="$1"
    shift
    requested_fields="$*"

    devinfo="$(ibv_devinfo -d "$dev" 2>/dev/null)"
    hca_id="$(echo "$devinfo" | grep -m1 '^hca_id:' | awk '{print $2}')"
    fw_ver="$(echo "$devinfo" | grep -m1 'fw_ver:' | awk '{print $2}')"
    link_layer="$(echo "$devinfo" | grep -m1 'link_layer:' | awk '{print $2}')"
    state="$(echo "$devinfo" | grep -m1 'state:' | sed -E 's/.*state:\s+([^ ]+).*/\1/')"

    output=""
    for field in $requested_fields
    do
        case "$field" in
            device_name)
                if [ "$dev" != "$hca_id" ]; then
                    output="$output""Device Name : $hca_id
"
                fi
                ;;
            fw_ver)
                output="$output""Firmware Ver: $fw_ver
"
                ;;
            link_layer)
                output="$output""Link Layer  : $link_layer
"
                ;;
            state)
                output="$output""Port State  : $state
"
                ;;
        esac
    done

    printf "%s" "$output"
}

run_query_ibv_devinfo() {
    description="$1"  # e.g., "InfiniBand Firmware Versions"

    # Is ibv_devinfo present?
    if ! command -v ibv_devinfo >/dev/null 2>&1; then
        store_result "$description" "None"
        return
    fi

    # Gather devices
    devices="$(ibv_devinfo -l 2>/dev/null | sed -n 's/^[[:space:]]*\(mlx5_[0-9]*\)$/\1/p')"

    # Parse each device
    desired_fields="device_name fw_ver link_layer state"
    aggregated_output=""

    for dev in $devices
    do
        dev_output="$(parse_ibv_devinfo "$dev" "$desired_fields")"
        aggregated_output="$aggregated_output""Device      : $dev
$dev_output

"
    done

    # Store into our table
    store_result "$description" "$aggregated_output"
}

check_command() {
    cmd="$1"         # Command to check
    description="$2" # Description for the table entry

    # Check if the command exists
    if ! command -v "$cmd" >/dev/null 2>&1; then
        # If the command is not found, log it to the table
        store_result "$description" "$cmd command not found"
        return 1
    fi
    return 0
}

# Function to detect if MODs driver is loaded vs standard RM driver
detect_driver_type() {
    # Use timeout to prevent hangs, and check /proc/modules as fallback
    if command -v timeout >/dev/null 2>&1; then
        # Use timeout command if available
        if timeout 5 lsmod 2>/dev/null | grep -q "^mods "; then
            echo "Running MODs Driver on GPUs"
        elif timeout 5 lsmod 2>/dev/null | grep -q "^nvidia "; then
            echo "Running RM Driver on GPUs"
        else
            echo "GPU Driver not installed?"
        fi
    else
        # Fallback: check /proc/modules directly (safer than lsmod)
        if [ -r /proc/modules ]; then
            if grep -q "^mods " /proc/modules 2>/dev/null; then
                echo "Running MODs Driver on GPUs"
            elif grep -q "^nvidia " /proc/modules 2>/dev/null; then
                echo "Running RM Driver on GPUs"
            else
                echo "GPU Driver not installed?"
            fi
        else
            echo "GPU Driver not installed?"
        fi
    fi
}

# Function to discover available IB devices
discover_ib_devices() {
    ib_devices=""
    fallback_devices=""
    
    # Check if /sys/class/infiniband directory exists
    if [ ! -d "/sys/class/infiniband" ]; then
        return 1
    fi
    
    # Loop through each InfiniBand device directory
    for dir in /sys/class/infiniband/*/device; do
        # Check if the device directory exists
        if [ -d "$dir" ]; then
            # Define the path to the VPD file
            vpd_file="$dir/vpd"
            
            # Check if the VPD file exists and contains SW_MNG (NVL5+ system)
            if [ -f "$vpd_file" ] && grep -q "SW_MNG" "$vpd_file" 2>/dev/null; then
                # Extract the InfiniBand device name using parameter expansion
                device_name="${dir%/device}"  # Removes '/device' from the end of $dir
                device_name="${device_name##*/}"  # Extracts the part after the last '/'
                
                # Add to fallback list (all SW_MNG devices with non-empty names)
                if [ -n "$device_name" ]; then
                    fallback_devices="$fallback_devices $device_name"
                    
                    # Check if pkey file exists for this device
                    pkey_file="/sys/class/infiniband/$device_name/ports/1/pkeys/0"
                    if [ -f "$pkey_file" ]; then
                        pkey_value=$(cat "$pkey_file" 2>/dev/null)
                        # Only include devices that are full members (0xffff) in primary list
                        if [ "$pkey_value" = "0xffff" ]; then
                            ib_devices="$ib_devices $device_name"
                        fi
                    fi
                fi
            fi
        fi
    done
    
    # Remove leading spaces
    ib_devices=$(echo "$ib_devices" | sed 's/^[[:space:]]*//')
    fallback_devices=$(echo "$fallback_devices" | sed 's/^[[:space:]]*//')
    
    # If no full member devices found, fall back to all SW_MNG devices
    if [ -z "$ib_devices" ] && [ -n "$fallback_devices" ]; then
        ib_devices="$fallback_devices"
    fi
    
    # If still no devices, fall back to default mlx5_0 if it exists
    if [ -z "$ib_devices" ] && [ -d "/sys/class/infiniband/mlx5_0" ]; then
        ib_devices="mlx5_0"
    fi
    
    echo "$ib_devices"
}

run_query_mlxlink() {
    description="$1"  # e.g., "Mellanox Link Firmware Versions"
    query="$2"        # Query string to match in 'mst status'

    # Check if required commands exist
    if ! check_command "mst" "$description"; then return; fi
    if ! check_command "mlxlink" "$description"; then return; fi

    # Discover available IB devices
    ib_devices=$(discover_ib_devices)
    if [ -z "$ib_devices" ]; then
        store_result "$description" "No IB devices found"
        return
    fi

    # Run mst status and capture output
    mst_output=$(sudo mst status -v 2>&1)
    if [ $? -ne 0 ]; then
        store_result "$description" "Error running 'mst status': $mst_output"
        return
    fi

    # Initialize result aggregation
    aggregated_output=""
    
    # Process each discovered IB device
    for ib_device in $ib_devices; do
        while IFS= read -r tmp_line; do
            echo "$tmp_line" | grep "$query" | grep "$ib_device" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                # Extract device name
                devName=$(echo "$tmp_line" | awk -F" " '{print $1}')
                mlxlink_output=$(sudo mlxlink -d "$devName" 2>&1)

                if [ $? -ne 0 ]; then
                    aggregated_output="$aggregated_output""Device: $devName
Error: $(echo "$mlxlink_output" | head -n 1)
"
                    continue
                fi

                aggregated_output="$aggregated_output""Device: $devName
$mlxlink_output

"
            fi
        done <<EOF
$(echo "$mst_output" | grep "$query" | grep "$ib_device")
EOF
    done

    # Store the result
    if [ -z "$aggregated_output" ]; then
        store_result "$description" "No devices matching query '$query'"
    else
        store_result "$description" "$aggregated_output"
    fi
}

run_query() {
    cmd="$1"
    args="$2"
    description="$3"

    # If command is not found
    if ! command -v "$cmd" >/dev/null 2>&1; then
        store_result "$description" "None"
        return
    fi

    # Capture all stdout+stderr
    output=`$cmd $args 2>&1`
    ret_code=$?

    if [ "$description" = "OS Details" ] && [ "$ret_code" -eq 0 ]; then
        os_details=""
        if command -v lsb_release >/dev/null 2>&1; then
            os_details="$os_details""Distribution : $(lsb_release -d -s)
"
        elif [ -f ${HOST_ROOT}/etc/os-release ]; then
            distline="$(grep '^PRETTY_NAME=' ${HOST_ROOT}/etc/os-release | cut -d= -f2- | tr -d '"')"
            if [ -n "$distline" ]; then
                os_details="$os_details""Distribution : $distline
"
            else
                os_details="$os_details""Distribution : Unknown
"
            fi
        else
            os_details="$os_details""Distribution : Unknown
"
        fi

        os_details="$os_details""Kernel       : $(uname -r)
"
        os_details="$os_details""Hostname     : $(cat /proc/sys/kernel/hostname 2>/dev/null || uname -n)
"
        os_details="$os_details""Architecture : $(uname -m)
"
        os_details="$os_details""Uptime       : $(uptime -p 2>/dev/null || true)
"

        output="$os_details"
    fi


    # Mark success or failure
    if [ "$ret_code" -eq 0 ]; then
        store_result "$description" "$output"
    else
        first_line="$(echo "$output" | head -n 1)"
        store_result "$description" "Failed: $first_line"
    fi
}

run_query_file() {
    file_path="$1"
    pattern="$2"
    description="$3"

    # Check if file is readable
    if [ ! -r "$file_path" ]; then
        store_result "$description" "None"
        return
    fi

    # Grab matching lines
    filtered_output=`grep "$pattern" "$file_path" 2>/dev/null`
    ret_code=$?

    if [ $ret_code -eq 0 ]; then
        if [ -z "$filtered_output" ]; then
            store_result "$description" "None"
        else
            store_result "$description" "$filtered_output"
        fi
    else
        store_result "$description" "None"
    fi
}

fetch_software_firmware_versions() {
    run_query "vulkaninfo"     "--version" "Vulkan Info"
    
    # Detect driver type (MODs vs RM)
    driver_type=$(detect_driver_type)
    
    # Skip nvidia-smi calls in safe mode to avoid hangs when driver is not responding
    if [ $BUG_REPORT_SAFE_MODE -eq 0 ]; then
        run_query "nvidia-smi"     "--version" "NVIDIA SMI"
        run_query "nvidia-smi"     "--query-gpu=name,driver_version,memory.total,vbios_version,pci.bus_id,serial --format=csv,noheader" \
                                   "NVIDIA GPU Details"
    else
        # In safe mode, try to get driver version from modinfo as fallback
        if command -v modinfo >/dev/null 2>&1; then
            driver_version=$(modinfo nvidia 2>/dev/null | grep "^version:" | awk '{print $2}')
            if [ -n "$driver_version" ]; then
                store_result "NVIDIA SMI" "Driver version (from modinfo): $driver_version"
            else
                store_result "NVIDIA SMI" "Unable to fetch (safe mode - driver may be hung)"
            fi
        else
            store_result "NVIDIA SMI" "Unable to fetch (safe mode - driver may be hung)"
        fi
        
        # Provide specific messaging for MODs driver
        if echo "$driver_type" | grep -q "MODs Driver"; then
            store_result "NVIDIA GPU Details" "Skipped in safe mode (MODs driver detected - nvidia-smi may hang)"
        else
            store_result "NVIDIA GPU Details" "Skipped in safe mode (driver may be hung)"
        fi
    fi
    
    run_query "nvidia-settings" "--version" "NVIDIA Settings"
    run_query "nv-fabricmanager" "--version" "NVIDIA Fabric Manager"
    run_query "opensm"         "--version" "NVIDIA Subnet Manager"
    run_query "mlxlink"        "--version" "Mellanox Link"
    run_query "ibstat"         "--version" "InfiniBand Status"
    run_query "ibnetdiscover"  "--version" "InfiniBand Network Discovery"
    run_query_file "${HOST_ROOT}/var/log/dmesg" "MSE\|uCode\|NETIR" "NVIDIA MSE/NETIR Versions"

    run_query_mlxlink "NVIDIA Switch Details" "Quantum"
    run_query_ibv_devinfo "NVIDIA NIC Details"

    run_query "uname" "-r" "OS Details"

    print_versions_table
}

module_names="nvidia nvidia_drm nvidia_modeset nvidia_uvm nvidia_peermem"

usage_bug_report_message() {
    echo "Please include the '$LOG_FILENAME' log file when reporting"
    echo "your bug via the NVIDIA Linux forum (see forums.developer.nvidia.com)"
    echo "or by sending email to 'linux-bugs@nvidia.com'."
    echo ""
    echo "By delivering '$LOG_FILENAME' to NVIDIA, you acknowledge"
    echo "and agree that personal information may inadvertently be included in"
    echo "the output.  Notwithstanding the foregoing, NVIDIA will use the"
    echo "output only for the purpose of investigating your reported issue."
}

usage() {
    echo ""
    echo "$(basename $0): NVIDIA Linux Graphics Driver bug reporting shell script."
    echo ""
    usage_bug_report_message
    echo "Usage:"
    echo "  $(basename $0) [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help"
    echo "    Print this help message and exit."
    echo ""
    echo "  --output-file <file>"
    echo "    Write output to <file>. If 'gzip' is available, the file will"
    echo "    automatically be compressed to <file>.gz."
    echo "    Default: nvidia-bug-report.log(.gz)."
    echo ""
    echo "  --safe-mode"
    echo "    Disable certain queries that might hang the system. Useful if you"
    echo "    experience freezes, high CPU usage, or suspect problematic kernel modules."
    echo ""
    echo "  --extra-system-data"
    echo "    Gather additional system information and CPU backtraces for deeper"
    echo "    debugging. Consider using this if the script hangs without --safe-mode"
    echo "    or you need more extensive kernel data."
    echo ""
    #VGX_SPECIFIC_CODE_START
    if [ -n "$IS_XEN_HYPERVISOR" ]; then
        echo "  --domain-name \"<domain_name>\""
        echo "    Generate a bug report for the specified Xen virtual machine domain."
        echo "    Only valid if running within Xen dom0."
        echo ""
    fi
    #VGX_SPECIFIC_CODE_END
    echo "  -v, --version"
    echo "    Show the current version of nvidia-bug-report.sh and exit."
    echo "  -V, --versions"
    echo "    Show the current versions of NVIDIA software and firmware on the node."
    echo ""
    echo "Description:"
    echo "  This script collects logs and configuration details—covering kernel"
    echo "  messages, GPU driver info, Xorg logs, hypervisor data (if applicable),"
    echo "  and more—to help diagnose NVIDIA driver or GPU-related issues. Run it"
    echo "  as root or with sudo for the most complete data."
    echo ""
    echo "  If certain tools (e.g., 'nvidia-smi', 'lspci', 'mstflint') are missing,"
    echo "  the script will note \"Skipping...\" in the final report but continue"
    echo "  collecting other data."
    echo ""
    echo "Troubleshooting Tips:"
    echo "  - If the script hangs, try using '--safe-mode'."
    echo "  - If you need deeper system info (e.g., CPU backtraces), use '--extra-system-data'."
    echo "  - Check final '.log' or '.log.gz' for 'Skipping...' lines to see if any"
    echo "    dependencies were missing or commands failed."
    echo "  - Ensure you have installed recommended dependencies (see the full documentation"
    echo "    or 'system_requirements.rst'). Official releases of the NVIDIA driver/firmware"
    echo "    reduce hangs and incomplete captures."
    echo ""
    echo "Examples:"
    echo "  1) sudo ./nvidia-bug-report.sh"
    echo "     Creates 'nvidia-bug-report.log.gz' if 'gzip' is installed."
    echo ""
    echo "  2) sudo ./nvidia-bug-report.sh --safe-mode"
    echo "     Skips queries known to cause hangs on certain systems."
    echo ""
    echo "  3) sudo ./nvidia-bug-report.sh --extra-system-data --output-file custom_report"
    echo "     Gathers extended kernel info into 'custom_report.log.gz' (compressed if possible)."
    echo ""
}

NVIDIA_BUG_REPORT_CHANGE='$Change: 37062940 $'
NVIDIA_BUG_REPORT_VERSION=`echo "$NVIDIA_BUG_REPORT_CHANGE" | tr -c -d "[:digit:]"`

# Set the default filename so that it won't be empty in the usage message
set_filename

# Parse arguments: Optionally set output file, run in safe mode, include extra
# system data, or print help
BUG_REPORT_SAFE_MODE=0
BUG_REPORT_EXTRA_SYSTEM_DATA=0
SAVED_FLAGS=$@
while [ "$1" != "" ]; do
    case "$1" in
        -o | --output-file )
            if [ -z "$2" ]; then
                echo "Error: --output-file requires a filename argument."
                usage
                exit 1
            elif [ "$(echo "$2" | cut -c 1)" = "-" ]; then
                echo "Warning: Questionable filename \"$2\": possible missing argument?"
            fi
            BASE_LOG_FILENAME="$2"
            # Override the default filename
            set_filename
            shift
            ;;
        --safe-mode )
            BUG_REPORT_SAFE_MODE=1
            ;;
        --extra-system-data )
            BUG_REPORT_EXTRA_SYSTEM_DATA=1
            ;;
        -h | --help )
            usage
            exit 0
            ;;
        -v | --version )
            echo "${NVIDIA_BUG_REPORT_VERSION}"
            exit 0
            ;;
        -V | --versions )
            fetch_software_firmware_versions
            exit 0
            ;;
        * )
            echo "Error: Unknown option \"$1\"."
            usage
            exit 1
            ;;
    esac
    shift
done

#
# echo_metadata() - echo metadata of specified file
#

echo_metadata() {
    printf "*** ls: "
    /bin/ls -l --full-time "$1" 2> /dev/null

    if [ $? -ne 0 ]; then
        # Run dumb ls -l. We might not get one-second mtime granularity, but
        # that is probably okay.
        ls -l "$1" 2>&1
    fi
}

#
# report_file() - print a report for the specified file to stdout: if it
# exists, dumps metadata and contents.
#
report_file() {
    echo "____________________________________________"
    echo ""

    if [ ! -f "$1" ]; then
        echo "*** $1 does not exist"
    elif [ ! -r "$1" ]; then
        echo "*** $1 is not readable"
    else
        echo "*** $1"
        echo_metadata "$1"
        cat  "$1"
    fi
    echo ""
}

#
# append() - append the contents of the specified file to the log
#

append() {
    report_file "$1" | $GZIP_CMD >> $LOG_FILENAME
}

#
# append_silent() - same as append(), but don't print anything
# if the file does not exist
#

append_silent() {
    (
        if [ -f "$1" -a -r "$1" ]; then
            echo "____________________________________________"
            echo ""
            echo "*** $1"
            echo_metadata "$1"
            cat  "$1"
            echo ""
        fi
    ) | $GZIP_CMD >> $LOG_FILENAME
}

#
# append_glob() - use the shell to expand a list of files, and invoke
# report_file for each of them; append the result to the log
#

append_glob() {
    for append_glob_iterator in `ls $1 2> /dev/null;`; do
        report_file "$append_glob_iterator"
    done | $GZIP_CMD >> $LOG_FILENAME
}

#
# append_file_or_dir_silent() - if $1 is a regular file, append it; otherwise,
# if $1 is a directory, append all files under it.  Don't print anything if the
# file does not exist.
#

append_file_or_dir_silent() {
    if [ -f "$1" ]; then
        append "$1"
    elif [ -d "$1" ]; then
        append_glob "$1/*"
    fi
}

#
# append_binary_file() - Encode a binary file into a ascii string format
# using 'base64' and append the contents output to the log file
#

append_binary_file() {
    (
        base64=`which base64 2> /dev/null | head -n 1`

        if [ $? -eq 0 -a -x "$base64" ]; then
                if [ -f "$1" -a -r "$1" ]; then
                    echo "____________________________________________"
                    echo ""
                    echo "base64 \"$1\""
                    echo ""
                    base64 "$1" 2> /dev/null
                    echo ""
                fi
        else
            report_skip "$1 output" "base64 not found"
            echo ""
        fi

    ) | $GZIP_CMD >> $LOG_FILENAME
}

#
# report_command() - print the output of the specified command to stdout
#

report_command() {
    if [ -n "$1" ]; then
        echo "$1"
        echo ""
        $1 2>&1
        echo ""
    fi
}

#
# search_string_in_logs() - search for string $2 in log file $1
#

search_string_in_logs() {
    if [ -f "$1" ]; then
        echo ""
        if [ -r "$1" ]; then
            echo "  $1:"
            grep $2 "$1" 2> /dev/null
            return 0
        else
            echo "$1 is not readable"
        fi
    fi
    return 1
}

#
# print_package_for_file() - Print the package that owns the file $1
#
print_package_for_file()
{
    # Try to figure out which package manager we should use, and print which
    # package owns a file.

    pkgcmd=`which dpkg-query 2> /dev/null | head -n 1`
    if [ $? -eq 0 -a -n "$pkgcmd" ]; then
        pkgoutput=`"$pkgcmd" --search "$1" 2> /dev/null`
        if [ $? -ne 0 -o "x$pkgoutput" = "x" ] ; then
            echo No package found for $1
            return
        fi

        pkgname=$(echo "$pkgoutput" | sed -e 's/:[[:space:]].*//')
        if [ "x$pkgname" = "x" ] ; then
            echo Can\'t parse package result: $pkgoutput
            return
        fi
        "$pkgcmd" --show --showformat='    Package: ${Package}:${Architecture} ${Version}\n' $pkgname

        return
    fi

    pkgcmd=`which pacman 2> /dev/null | head -n 1`
    if [ $? -eq 0 -a -n "$pkgcmd" ]; then
        pkgoutput=`"$pkgcmd" --query --owns "$1" 2> /dev/null`
        if [ $? -ne 0 -o "x$pkgoutput" = "x" ] ; then
            echo No package found for $1
            return
        fi
        echo "$pkgoutput"

        return
    fi

    pkgcmd=`which rpm 2> /dev/null | head -n 1`
    if [ $? -eq 0 -a -n "$pkgcmd" ]; then
        "$pkgcmd" -q -f "$1" 2> /dev/null
        return
    fi
}

GLVND_HELPER_BASE_PATH=/usr/lib/nvidia

#
# print_libglvnd_library() - Print information about a libglvnd library.
# $1 is the path to where the helper program and libraries are.
# $2 is the API to check
# $3 is the name of the library to look for
#
print_libglvnd_library()
{
    echo Checking library: $3

    __GLX_VENDOR_LIBRARY_NAME=installcheck
    __EGL_VENDOR_LIBRARY_FILENAMES=$GLVND_HELPER_BASE_PATH/egl_dummy_vendor.json
    export __GLX_VENDOR_LIBRARY_NAME
    export __EGL_VENDOR_LIBRARY_FILENAMES
    result=`LD_LIBRARY_PATH="$1${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" $1/glvnd_check $2 $3`
    code=$?

    unset __GLX_VENDOR_LIBRARY_NAME
    unset __EGL_VENDOR_LIBRARY_FILENAMES

    case $code in
        0)
            echo Found compatible libglvnd library $3
            ;;
        1)
            echo Found non-libglvnd library $3
            ;;
        2)
            echo Found incompatible libglvnd library $3
            ;;
        3)
            echo Library $3 does not exist
            return $code
            ;;
        *)
            echo Internal error when checking $3
            echo "$result"
            return 4
            ;;
    esac

    libpath=`echo "$result" | grep "^PATH " | cut -s "-d " -f2-`
    echo Found library at: "$libpath"

    info=`echo "$result" | grep "^LIBGLVND_ABI " | cut -s "-d " -f2,3`
    if [ -n "$info" ] ; then
        echo Libglvnd ABI version: $info
    fi

    info=`echo "$result" | grep "^CLIENT_STRING " | cut -s "-d " -f2-`
    if [ -n "$info" ] ; then
        echo Client version/vendor string: "$info"
    fi

    print_package_for_file $libpath

    echo -----
    return $code
}

#
# Start of script
#


# check that we are root (needed for `lspci -vxxxx` and potentially for
# accessing kernel log files)

if [ `id -u` -ne 0 ]; then
    echo "ERROR: Please run $(basename $0) as root."
    exit 1
fi


# move any old log file (zipped) out of the way

if [ -f $LOG_FILENAME ]; then
    mv $LOG_FILENAME $OLD_LOG_FILENAME
fi


# make sure what we can write to the log file

touch $LOG_FILENAME 2> /dev/null

if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Working directory is not writable; please cd to a directory"
    echo "       where you have write permission so that the $LOG_FILENAME"
    echo "       file can be written."
    echo
    exit 1
fi

# Make sure we can create temp files.  Check TMPDIR (POSIX-compliant) if present
[ -z "$TMPDIR" ] && TMPDIR="/tmp"
tmptest="$TMPDIR/nvbrtesttemp.$$"
touch "$tmptest"
if [ $? -ne 0 ]; then
    echo "ERROR: The directory $TMPDIR is not writable.  Please set TMPDIR"
    echo "       to a directory with write permission for temporary output files"
    exit 1
else
    rm -f "$tmptest"
fi


# print a start message to stdout

echo ""
echo "nvidia-bug-report.sh will now collect information about your"
echo "system and create the file '$LOG_FILENAME' in the current"
echo "directory.  It may take several seconds to run.  In some"
echo "cases, it may hang trying to capture data generated dynamically"
echo "by the Linux kernel and/or the NVIDIA kernel module.  While"
echo "the bug report log file will be incomplete if this happens, it"
echo "may still contain enough data to diagnose your problem." 
echo ""
if [ $BUG_REPORT_SAFE_MODE -eq 0 ]; then
    echo "If nvidia-bug-report.sh hangs, consider running with the --safe-mode"
    echo "and --extra-system-data command line arguments."
    echo ""
fi
usage_bug_report_message
echo ""
echo -n "Running $(basename $0)...";


# print prologue to the log file

(
    echo "____________________________________________"
    echo ""
    echo "Start of NVIDIA bug report log file.  Please include this file, along"
    echo "with a detailed description of your problem, when reporting a graphics"
    echo "driver bug via the NVIDIA Linux forum (see forums.developer.nvidia.com)"
    echo "or by sending email to 'linux-bugs@nvidia.com'."
    echo ""
    echo "nvidia-bug-report.sh Version: $NVIDIA_BUG_REPORT_VERSION"
    echo ""
    echo "Date: `date`"
    echo "uname: `uname -a`"
    echo "command line flags: $SAVED_FLAGS"
    echo ""
) | $GZIP_CMD >> $LOG_FILENAME

# print software firmware versions
(
    fetch_software_firmware_versions
) | $GZIP_CMD >> $LOG_FILENAME

# Add driver type detection information (only if not in safe mode to avoid hangs)
if [ $BUG_REPORT_SAFE_MODE -eq 0 ]; then
    # Show driver type on console
    driver_type=$(detect_driver_type)
    echo ""
    echo "Detected driver type: $driver_type"
    if echo "$driver_type" | grep -q "MODs Driver"; then
        echo ""
        echo "WARNING: MODs driver detected. nvidia-smi may hang with MODs driver."
        echo "If experiencing hangs, try:"
        echo "  sudo rmmod mods"
        echo "  sudo modprobe nvidia"
        echo "  sudo nvidia-smi  # confirm RM driver is working"
        echo "  then run nvidia-bug-report.sh"
    fi
    
    # Also log detailed info to file
    (
        echo "____________________________________________"
        echo ""
        echo "NVIDIA Driver Type Detection:"
        echo ""
        echo "Detected driver type: $driver_type"
        if echo "$driver_type" | grep -q "MODs Driver"; then
            echo ""
            echo "nvidia-smi does not work with MODs driver."
            echo "Install RM Driver using these instructions:"
            echo "  sudo rmmod mods"
            echo "  sudo modprobe nvidia"
            echo "  sudo nvidia-smi  # confirm RM driver is working"
            echo "  then run nvidia-bug-report.sh"
        elif echo "$driver_type" | grep -q "RM Driver"; then
            echo "Standard RM driver detected."
        else
            echo "No NVIDIA driver modules detected."
        fi
        echo ""
    ) | $GZIP_CMD >> $LOG_FILENAME
else
    # Show safe mode message on console
    echo "Skipped driver type detection (safe mode - driver may be unresponsive)"
    
    # Also log to file
    (
        echo "____________________________________________"
        echo ""
        echo "NVIDIA Driver Type Detection:"
        echo ""
        echo "Skipped in safe mode"
        echo ""
    ) | $GZIP_CMD >> $LOG_FILENAME
fi

if [ $BUG_REPORT_SAFE_MODE -eq 0 ]; then
    # List the sysfs entries for all NVIDIA device functions
    # This info is useful to debug dynamic power management issues
    #
    # NOTE: We need to query this before other things in this script,
    # because other operations may alter the power management
    # state of the GPU(s).
    for subdir in `ls /sys/bus/pci/devices/ 2> /dev/null`; do
        vendor_id=`cat /sys/bus/pci/devices/$subdir/vendor 2> /dev/null`
        if [ "$vendor_id" = "0x10de" ]; then
            append "/sys/bus/pci/devices/$subdir/power/control"
            append "/sys/bus/pci/devices/$subdir/power/runtime_status"
            append "/sys/bus/pci/devices/$subdir/power/runtime_usage"

            # Get the parent port's power resources to determine
            # if parent port can control the power. We check the parent port
            # only for the first subfunction (VGA/3D).
            pci_class=`cat /sys/bus/pci/devices/$subdir/class 2> /dev/null`
            if [ "$pci_class" = "0x030000" ] || [ "$pci_class" = "0x030200" ]; then
                path_to_device=`readlink -f /sys/bus/pci/devices/$subdir`
                pr_d3hot="$path_to_device/../firmware_node/power_resources_D3hot"
                (
                    echo "____________________________________________"
                    echo ""
                    echo "power_resources_d3hot directory of the parent PCI/e port"
                    echo ""
                    echo_metadata $pr_d3hot
                ) | $GZIP_CMD >> $LOG_FILENAME
            fi
        fi
    done

    for GPU in `ls /proc/driver/nvidia/gpus/ 2> /dev/null`; do
        append "/proc/driver/nvidia/gpus/$GPU/power"
    done
fi

# append OPAL (IBM POWER system firmware) messages

append_silent "/sys/firmware/opal/msglog"

# append useful files

append "${HOST_ROOT}/etc/issue"

append_silent "${HOST_ROOT}/etc/redhat-release"
append_silent "${HOST_ROOT}/etc/redhat_version"
append_silent "${HOST_ROOT}/etc/fedora-release"
append_silent "${HOST_ROOT}/etc/slackware-release"
append_silent "${HOST_ROOT}/etc/slackware-version"
append_silent "${HOST_ROOT}/etc/debian_release"
append_silent "${HOST_ROOT}/etc/debian_version"
append_silent "${HOST_ROOT}/etc/mandrake-release"
append_silent "${HOST_ROOT}/etc/yellowdog-release"
append_silent "${HOST_ROOT}/etc/sun-release"
append_silent "${HOST_ROOT}/etc/release"
append_silent "${HOST_ROOT}/etc/gentoo-release"
append_silent "${HOST_ROOT}/etc/lsb-release"
append_silent "${HOST_ROOT}/etc/os-release"
append_silent "${HOST_ROOT}/etc/fastos-release"
append_silent "${HOST_ROOT}/etc/fastos-ota"
append_silent "${HOST_ROOT}/etc/dgx-release"



append "${HOST_ROOT}/var/log/nvidia-installer.log"
append_silent "${HOST_ROOT}/var/log/nvidia-uninstall.log"

# find and append all make.log files in /var/lib/dkms for module nvidia
if [ -d "${HOST_ROOT}/var/lib/dkms/nvidia" ]; then
    for log in `find "${HOST_ROOT}/var/lib/dkms/nvidia" -name "make.log"`; do
        append $log
    done
fi

# check the status of the nvidia-suspend, nvidia-hibernate, nvidia-resume
# and nvidia-powerd systemd services

systemctl=`which systemctl 2> /dev/null | head -n 1`

if [ $? -eq 0 -a -x "$systemctl" ]; then
    cmd="$systemctl status nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service nvidia-powerd.service nvidia-persistenced.service"
    (
        echo "____________________________________________"
        echo ""
        echo "$cmd"
        $cmd
        echo ""
    ) 2> /dev/null | $GZIP_CMD >> $LOG_FILENAME
fi

# use systemd's journalctl to capture X logs where applicable

journalctl=`which journalctl 2> /dev/null | head -n 1`

if [ $? -eq 0 -a -x "$journalctl" ]; then
    for match in _COMM=Xorg \
                 _COMM=Xorg.bin \
                 _COMM=X \
                 _COMM=gdm-x-session \
                 "SYSLOG_IDENTIFIER=systemd-coredump -g nvidia"; do
        for boot in -0 -1 -2; do
            if journalctl -b $boot -n 1 $match >/dev/null 2>&1; then
                (
                    echo "____________________________________________"
                    echo ""
                    echo "journalctl -b $boot $match"
                    echo ""
                    journalctl -b $boot $match
                    echo ""
                ) 2> /dev/null | $GZIP_CMD >> $LOG_FILENAME
            fi
        done
    done
fi

# use systemd's coredumpctl to capture X coredumps where applicable

coredumpctl=`which coredumpctl 2> /dev/null | head -n 1`

if [ $? -eq 0 -a -x "$coredumpctl" ]; then
    cmd="$coredumpctl info COREDUMP_COMM=Xorg COREDUMP_COMM=Xorg.bin COREDUMP_COMM=X"
    (
        echo "____________________________________________"
        echo ""
        echo "$cmd"
        $cmd
        echo ""
    ) 2> /dev/null | $GZIP_CMD >> $LOG_FILENAME
fi

# append the X log; also, extract the config file named in the X log
# and append it; look for X log files with names of the form:
# /var/log/Xorg.{0,1,2,3,4,5,6,7}.{log,log.old}

xconfig_file_list=
svp_config_file_list=
NEW_LINE="
"

for i in 0 1 2 3 4 5 6 7; do
    for log_suffix in log log.old; do
        log_filename="${HOST_ROOT}/var/log/Xorg.${i}.${log_suffix}"
        append_silent "${log_filename}"

        # look for the X configuration files/directories referenced by this X log
        if [ -f ${log_filename} -a -r ${log_filename} ]; then
            config_file=`grep "Using config file" ${log_filename} | cut -f 2 -d \"`
            config_dir=`grep "Using config directory" ${log_filename} | cut -f 2 -d \"`
            sys_config_dir=`grep "Using system config directory" ${log_filename} | cut -f 2 -d \"`
            for j in "$config_file" "$config_dir" "$sys_config_dir"; do
                if [ "$j" ]; then
                    # multiple of the logs we find above might reference the
                    # same X configuration file; keep a list of which X
                    # configuration files we find, and only append X
                    # configuration files we have not already appended
                    echo "${xconfig_file_list}" | grep ":${j}:" > /dev/null
                    if [ "$?" != "0" ]; then
                        xconfig_file_list="${xconfig_file_list}:${j}:"
                        if [ -d "$j" ]; then
                            append_glob "$j/*.conf"
                        else
                            append "$j"
                        fi
                    fi
                fi
            done

            # append NVIDIA 3D Vision Pro configuration settings
            svp_conf_files=`grep "Option \"3DVisionProConfigFile\"" ${log_filename} | cut -f 4 -d \"`
            if [ "${svp_conf_files}" ]; then
                OLD_IFS="$IFS"
                IFS=$NEW_LINE
                for svp_file in ${svp_conf_files}; do
                    IFS="$OLD_IFS"
                    echo "${svp_config_file_list}" | grep ":${svp_file}:" > /dev/null
                    if [ "$?" != "0" ]; then
                        svp_config_file_list="${svp_config_file_list}:${svp_file}:"
                        append_binary_file "${svp_file}"
                    fi
                    IFS=$NEW_LINE
                done
                IFS="$OLD_IFS"
            fi
        fi

    done
done

# Append any config files found in home directories
cat ${HOST_ROOT}/etc/passwd \
    | cut -d : -f 6 \
    | sort | uniq \
    | while read DIR; do
        append_file_or_dir_silent "$DIR/.nv/nvidia-application-profiles-rc"
        append_file_or_dir_silent "$DIR/.nv/nvidia-application-profiles-rc.backup"
        append_file_or_dir_silent "$DIR/.nv/nvidia-application-profiles-rc.d"
        append_file_or_dir_silent "$DIR/.nv/nvidia-application-profiles-rc.d.backup"
        append_silent "$DIR/.nv/nvidia-application-profile-globals-rc"
        append_silent "$DIR/.nv/nvidia-application-profile-globals-rc.backup"
        append_silent "$DIR/.nvidia-settings-rc"

        for f in "$DIR/.config/vulkan/icd.d/*" \
                 "$DIR/.config/vulkansc/icd.d/*" \
                 "$DIR/.local/share/vulkan/icd.d/*" \
                 "$DIR/.local/share/vulkansc/icd.d/*"; do
            append_silent $f
        done
    done

# Capture global app profile configs
append_file_or_dir_silent "${HOST_ROOT}/etc/nvidia/nvidia-application-profiles-rc"
append_file_or_dir_silent "${HOST_ROOT}/etc/nvidia/nvidia-application-profiles-rc.d"
append_file_or_dir_silent /usr/share/nvidia/nvidia-application-profiles-*-rc


# append ldd info

(
    echo "____________________________________________"
    echo ""

    glxinfo=`which glxinfo 2> /dev/null | head -n 1`

    if [ $? -eq 0 -a -x "$glxinfo" ]; then
        echo "ldd $glxinfo"
        echo ""
        ldd $glxinfo 2> /dev/null
        echo ""
    else
        report_skip "ldd output" "glxinfo not found"
        echo ""
    fi
) | $GZIP_CMD >> $LOG_FILENAME

# append Vulkan ICD info

(
    echo "____________________________________________"
    echo ""

    vkinfo=`ldconfig -N -v -p 2> /dev/null | /bin/grep libvulkan.so.1 | awk 'NF>1{print $NF}'`

    if [ $? -eq 0 -a -n "$vkinfo" ]; then
        echo "Found Vulkan loader(s):"
        readlink -f ${vkinfo} 2> /dev/null
        echo ""
        # See https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderDriverInterface.md
        echo "Listing common ICD paths:"
        ls -d /usr/local/etc/vulkan/icd.d/* 2> /dev/null
        ls -d /usr/local/share/vulkan/icd.d/* 2> /dev/null
        ls -d ${HOST_ROOT}/etc/vulkan/icd.d/* 2> /dev/null
        ls -d /usr/share/vulkan/icd.d/* 2> /dev/null
        ls -d ${HOST_ROOT}/etc/xdg/vulkan/icd.d 2> /dev/null
        echo ""
    else
        echo "Vulkan loader not found"
        echo ""
    fi
) | $GZIP_CMD >> $LOG_FILENAME

# append Vulkan SC ICD info

(
    echo "____________________________________________"
    echo ""

    vkscinfo=`ldconfig -N -v -p 2> /dev/null | /bin/grep libvulkansc.so.1 | awk 'NF>1{print $NF}'`

    if [ $? -eq 0 -a -n "$vkscinfo" ]; then
        echo "Found Vulkan SC loader(s):"
        readlink -f ${vkscinfo} 2> /dev/null
        echo ""
        # See https://github.com/KhronosGroup/VulkanSC-Loader/blob/main/docs/LoaderDriverInterface.md
        echo "Listing common ICD paths:"
        ls -d /usr/local/etc/vulkansc/icd.d/* 2> /dev/null
        ls -d /usr/local/share/vulkansc/icd.d/* 2> /dev/null
        ls -d ${HOST_ROOT}/etc/vulkansc/icd.d/* 2> /dev/null
        ls -d /usr/share/vulkansc/icd.d/* 2> /dev/null
        ls -d ${HOST_ROOT}/etc/xdg/vulkansc/icd.d 2> /dev/null
        echo ""
    else
        echo "Vulkan SC loader not found"
        echo ""
    fi
) | $GZIP_CMD >> $LOG_FILENAME

# lspci information

(
    echo "____________________________________________"
    echo ""

    lspci=`which lspci 2> /dev/null | head -n 1`

    if [ $? -eq 0 -a -x "$lspci" ]; then
        # Capture all devices in tree format along with vendor:device IDs
        echo "$lspci -nntv"
        echo ""
        $lspci -nntv 2> /dev/null
        echo ""
        echo "____________________________________________"
        echo ""
        # Capture class names and class ID  along with vendor:device IDs
        echo "$lspci -nn"
        echo ""
        $lspci -nn 2> /dev/null
        echo ""
        echo "____________________________________________"
        echo ""
        # Capture verbose information for all devices, along with hex
        # dump of whole configuration space
        echo "$lspci -nnDvvvxxxx"
        echo ""
        $lspci -nnDvvvxxxx 2> /dev/null
    else
        hexdump=`which hexdump 2> /dev/null | head -n 1`
        if [ $? -eq 0 -a -x "$hexdump" ]; then
            # Capture hex dump of whole configuration space using sysfs file
            echo "PCI devices configuration space dump using sysfs"
            echo ""

            # Define the base path for PCI devices
            PCI_BASE_PATH="/sys/bus/pci/devices"

            # Loop through each PCI device in the directory
            for PCI_BDF in "$PCI_BASE_PATH"/*; do
                # Extract device ID (BDF format)
                PCI_ID=$(basename "$PCI_BDF")

                # Define the config file path
                PCI_CONFIG="$PCI_BDF/config"

                # Check if the config file exists
                if [ ! -f "$PCI_CONFIG" ]; then
                    continue
                fi

                # Retrieve PCI device information from sysfs and
                # remove "0x" prefix if present
                VENDOR_ID=$(sed s/^0x// "$PCI_BDF"/vendor)
                DEVICE_ID=$(sed s/^0x// "$PCI_BDF"/device)
                REVISION_ID=$(sed s/^0x// "$PCI_BDF"/revision)
                CLASS_ID=$(sed s/^0x// "$PCI_BDF"/class)

                # Print PCI device information (mimicking `lspci`)
                echo
                echo "$PCI_ID $CLASS_ID: Vendor $VENDOR_ID Device $DEVICE_ID (rev $REVISION_ID)"

                # Read the config file using 'hexdump' and format output
                $hexdump -v -e '16/1 "%02x " "\n"' "$PCI_CONFIG" | awk '{printf "%02x: %s\n",NR*16-16, $0}'
            done
        else
            report_skip "lspci output" "lspci or hexdump not found"
            echo ""
        fi
    fi
) | $GZIP_CMD >> $LOG_FILENAME

# THP (transparent huge pages) information
append /sys/kernel/mm/transparent_hugepage/enabled

append /proc/sys/vm/compaction_proactiveness

# NUMA information

(
    echo "____________________________________________"
    echo ""

    numactl=`which numactl 2> /dev/null | head -n 1`

    if [ $? -eq 0 -a -x "$numactl" ]; then
        # Get hardware NUMA configuration
        echo "$numactl -H"
        echo ""
        $numactl -H
    fi

    # Get autonuma information:
    report_file /proc/sys/kernel/numa_balancing

    # Get additional NUMA information about GPUs:
    filelist="/sys/devices/system/node/has_cpu \
              /sys/devices/system/node/has_memory \
              /sys/devices/system/node/has_normal_memory \
              /sys/devices/system/node/online \
              /sys/devices/system/node/possible"

    # Get GPU NUMA information
    lspci=`which lspci 2> /dev/null | head -n 1`
    if [ $? -eq 0 -a -x "$lspci" ]; then
        gpus=`$lspci -d "10de:*" -s ".0" | awk '{print $1}'`
        for gpu in $gpus; do
            filelist="$filelist \
                      /sys/bus/pci/devices/*$gpu/local_cpulist \
                      /sys/bus/pci/devices/*$gpu/numa_node"
        done
    fi

    for file in $filelist; do
        report_file "$file"
    done
) | $GZIP_CMD >> $LOG_FILENAME

# lsusb information

(
    echo "____________________________________________"
    echo ""

    lsusb=`which lsusb 2> /dev/null | head -n 1`

    if [ $? -eq 0 -a -x "$lsusb" ]; then
        echo "$lsusb"
        echo ""
        $lsusb 2> /dev/null
        echo ""
    else
        report_skip "lsusb output" "lsusb not found"
        echo ""
    fi
) | $GZIP_CMD >> $LOG_FILENAME

# dmidecode

(
    echo "____________________________________________"
    echo ""

    dmidecode=`which dmidecode 2> /dev/null | head -n 1`

    if [ $? -eq 0 -a -x "$dmidecode" ]; then
        echo "$dmidecode"
        echo ""
        $dmidecode 2> /dev/null
        echo ""
    else
        report_skip "dmidecode output" "dmidecode not found"
        echo ""
    fi
) | $GZIP_CMD >> $LOG_FILENAME

# module version magic

(
    echo "____________________________________________"
    echo ""

    modinfo=`which modinfo 2> /dev/null | head -n 1`

    if [ $? -eq 0 -a -x "$modinfo" ]; then
        for name in $module_names; do
            echo "$modinfo $name | grep vermagic"
            echo ""
            ( $modinfo $name | grep vermagic ) 2> /dev/null
            echo ""
        done
    else
        report_skip "modinfo output" "modinfo not found"
        echo ""
    fi
) | $GZIP_CMD >> $LOG_FILENAME

# module parameter values

(
    echo "____________________________________________"
    echo ""
    for name in $module_names; do
        if [ -d "/sys/module/$name/parameters/" ]; then
            grep -Hr . "/sys/module/$name/parameters/" 2> /dev/null
        fi
    done
) | $GZIP_CMD >> $LOG_FILENAME

# get any relevant kernel messages

(
    echo "____________________________________________"
    echo ""
    echo "Scanning kernel log files for NVIDIA kernel messages:"

    grep_args="-e NVRM -e nvidia- -e nvrm-nvlog -e nvidia-powerd"
    logfound=0
    search_string_in_logs ${HOST_ROOT}/var/log/messages "$grep_args" && logfound=1
    search_string_in_logs ${HOST_ROOT}/var/log/kern.log "$grep_args" && logfound=1
    search_string_in_logs ${HOST_ROOT}/var/log/kernel.log "$grep_args" && logfound=1
    search_string_in_logs ${HOST_ROOT}/var/log/dmesg "$grep_args" && logfound=1

    journalctl=`which journalctl 2> /dev/null | head -n 1`
    if [ $? -eq 0 -a -x "$journalctl" ]; then
        logfound=1
        nvrmfound=0

        for boot in -0 -1 -2; do
            if (journalctl -b $boot | grep ${grep_args}) > /dev/null 2>&1; then
                echo ""
                echo "  journalctl -b $boot:"
                (journalctl -b $boot | grep ${grep_args}) 2> /dev/null
                nvrmfound=1
            fi
        done

        if [ $nvrmfound -eq 0 ]; then
            echo ""
            echo "No NVIDIA kernel messages found in recent systemd journal entries."
        fi
    fi

    if [ $logfound -eq 0 ]; then
        echo ""
        echo "No suitable log found."
    fi

    echo ""
) | $GZIP_CMD >> $LOG_FILENAME


# If extra data collection is enabled, dump all active CPU backtraces to be
# picked up in dmesg
if [ $BUG_REPORT_EXTRA_SYSTEM_DATA -ne 0 ]; then
    (
        echo "____________________________________________"
        echo ""
        echo "Triggering SysRq backtrace on active CPUs (see dmesg output)"
        sysrq_enabled=`cat /proc/sys/kernel/sysrq`
        if [ "$sysrq_enabled" -ne "1" ]; then
            echo 1 > /proc/sys/kernel/sysrq
        fi
    
        echo l > /proc/sysrq-trigger
    
        if [ "$sysrq_enabled" -ne "1" ]; then
            echo $sysrq_enabled > /proc/sys/kernel/sysrq
        fi
    ) | $GZIP_CMD >> $LOG_FILENAME
fi

# append dmesg output

(
    echo "____________________________________________"
    echo ""
    echo "dmesg:"
    echo ""
    dmesg 2> /dev/null
) | $GZIP_CMD >> $LOG_FILENAME

# print gcc & g++ version info

(
    which gcc >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "____________________________________________"
        echo ""
        gcc -v 2>&1
    fi

    which g++ >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "____________________________________________"
        echo ""
        g++ -v 2>&1
    fi
) | $GZIP_CMD >> $LOG_FILENAME

if [ $BUG_REPORT_SAFE_MODE -eq 0 ]; then

    # In case of failure, if xset returns with delay, we print the
    # message from check "$?" & if it returns error immediately before kill,
    # we directly write the error to the log file.

    (
        echo "____________________________________________"
        echo ""
        echo "xset -q:"
        echo ""

        xset -q 2>&1 & sleep 1 ; kill -9 $! > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            # The xset process is still there.
            echo "xset could not connect to an X server"
        fi
    ) | $GZIP_CMD >> $LOG_FILENAME

    # In case of failure, if nvidia-settings returns with delay, we print the
    # message from check "$?" & if it returns error immediately before kill,
    # we directly write the error to the log file.

    (
        echo "____________________________________________"
        echo ""
        echo "nvidia-settings -q all:"
        echo ""

        DISPLAY= nvidia-settings -c "$DPY" -q all 2>&1 & sleep 1 ; kill -9 $! > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            # The nvidia-settings process is still there.
            echo "nvidia-settings could not connect to an X server"
        fi
    ) | $GZIP_CMD >> $LOG_FILENAME

    # In case of failure, if xrandr returns with delay, we print the
    # message from check "$?" & if it returns error immediately before kill,
    # we directly write the error to the log file.

    (
        if [ -x "`which xrandr 2>/dev/null`" ] ; then
             echo "____________________________________________"
             echo ""
             echo "xrandr --verbose:"
             echo ""

             xrandr -display $DPY --verbose 2>&1 & sleep 1 ; kill -9 $! > /dev/null 2>&1
             if [ $? -eq 0 ]; then
                 # The xrandr process is still there.
                 echo "xrandr could not connect to an X server"
             fi
             echo "____________________________________________"
             echo ""
             echo "xrandr --listproviders:"
             echo ""
             xrandr -display $DPY --listproviders 2>&1 & sleep 1 ; kill -9 $! > /dev/null 2>&1
             if [ $? -eq 0 ]; then
                 # The xrandr process is still there.
                 echo "xrandr could not connect to an X server"
            fi
        else
            report_skip "xrandr output" "xrandr not found"
        fi
    ) | $GZIP_CMD >> $LOG_FILENAME

    (
        if [ -x "`which xprop 2>/dev/null`" ] ; then
            echo "____________________________________________"
            echo ""
            echo "Running window manager properties:"
            echo ""

            TMP=`xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null & sleep 1 ; kill -9 $! > /dev/null 2>&1`
            WINDOW=`echo $TMP | grep -o '0x[0-9a-z]\+'`
            if [ "$WINDOW" ]; then
                xprop -id "$WINDOW" 2>&1 & sleep 1 ; kill -9 $! > /dev/null 2>&1
            else
                echo "Unable to detect window manager properties"
            fi
        fi
    ) | $GZIP_CMD >> $LOG_FILENAME
fi

sync > /dev/null 2>&1
sync > /dev/null 2>&1

# append useful /proc files

append "/proc/cmdline"
append "/proc/cpuinfo"
append "/proc/interrupts"
append "/proc/meminfo"
append "/proc/modules"
append "/proc/version"
append "/proc/pci"
append "/proc/iomem"
append "/proc/mtrr"
append "/proc/buddyinfo"

append "/proc/driver/nvidia/version"
append "/proc/driver/nvidia/params"
append "/proc/driver/nvidia/registry"

if [ $BUG_REPORT_SAFE_MODE -eq 0 ]; then
    for GPU in `ls /proc/driver/nvidia/gpus/ 2> /dev/null`; do
        append "/proc/driver/nvidia/gpus/$GPU/information"
    done
    append_glob "/proc/driver/nvidia/warnings/*"
    append_glob "/proc/driver/nvidia-modeset/*"
fi

append_glob "/proc/acpi/video/*/*/info"

append "/proc/asound/cards"
append "/proc/asound/pcm"
append "/proc/asound/modules"
append "/proc/asound/devices"
append "/proc/asound/version"
append "/proc/asound/timers"
append "/proc/asound/hwdep"

for CARD in /proc/asound/card[0-9]*; do
    for CODEC in $CARD/codec*; do
        [ -d $CODEC ] && append_glob "$CODEC/*"
        [ -f $CODEC ] && append "$CODEC"
    done
    for ELD in $CARD/eld*; do
        [ -f $ELD ] && append "$ELD"
    done
done

# List the mapping of DRM drivers to DRM device files
(

    echo "____________________________________________"
    echo ""

    if [ -d "/sys/class/drm" ]; then
        for CARD in `find -L /sys/class/drm -maxdepth 3 -path "*/device/driver" 2>/dev/null`; do
            echo_metadata $CARD
        done
    else
        echo "/sys/class/drm not present"
    fi

    echo ""

) | $GZIP_CMD >> $LOG_FILENAME

# List some info about DRM nodes
(
    if [ -d "/sys/class/drm" ]; then
        for DRM_NODE in /sys/class/drm/* ; do
            DRIVERPATH="$DRM_NODE/device/device/driver"
            if [ -e "$DRIVERPATH" ]; then
                REALPATH=$(readlink -f "$DRIVERPATH")
                case "$REALPATH" in 
                    */drivers/nvidia)
                        for DRM_SUBPATH in enabled status dpms modes; do
                            if [ -e "$DRM_NODE/$DRM_SUBPATH" ]; then
                                append  "$DRM_NODE/$DRM_SUBPATH"
                            fi
                        done
                        if [ -e "$DRM_NODE/edid" ]; then
                            append_binary_file  "$DRM_NODE/edid"
                        fi
                        ;; 
                esac
            fi
        done
    else
        echo "/sys/class/drm not present"
    fi

    echo ""

) | $GZIP_CMD >> $LOG_FILENAME

# List the mapping of PCI devices to DRM device files, and the existence and
# permissions of the DRM device files themselves.
(
    echo "____________________________________________"
    echo ""

    if [ -d "/dev/dri" ]; then
        for FILE in /dev/dri/by-path/* /dev/dri/card* /dev/dri/renderD*; do
            echo_metadata $FILE
        done
    else
        echo "/dev/dri not present"
    fi

    echo ""
) | $GZIP_CMD >> $LOG_FILENAME

# nvidia-debugdump
(
    echo "____________________________________________"
    echo ""

    nvidia_debugdump=`which nvidia-debugdump 2> /dev/null | head -n 1`

    if [ $? -eq 0 -a -x "$nvidia_debugdump" ]; then

        if [ $BUG_REPORT_SAFE_MODE -eq 0 ]; then
            NVDD_ARGS="-D"
        else
            NVDD_ARGS="--ioctl --nvlogonly"
        fi

        base64=`which base64 2> /dev/null | head -n 1`

        if [ $? -eq 0 -a -x "$base64" ]; then
            # make sure what we can write to the temp file

            NVDD_TEMP_FILENAME="$TMPDIR/nvidia-debugdump-temp$$.log"

            touch $NVDD_TEMP_FILENAME 2> /dev/null

            if [ $? -ne 0 ]; then
                report_skip "nvidia-debugdump output" "Can't create temp file $NVDD_TEMP_FILENAME"
                echo ""
                # don't fail here, continue
            else
                echo "$nvidia_debugdump ${NVDD_ARGS}"
                echo ""
                $nvidia_debugdump ${NVDD_ARGS} -f $NVDD_TEMP_FILENAME 2> /dev/null
                $base64 $NVDD_TEMP_FILENAME 2> /dev/null
                echo ""

                # remove the temporary file when complete
                rm $NVDD_TEMP_FILENAME 2> /dev/null
            fi
        else
            report_skip "nvidia-debugdump output" "base64 not found"
            echo ""
        fi
    else
        report_skip "nvidia-debugdump output" "nvidia-debugdump not found"
        echo ""
    fi
) | $GZIP_CMD >> $LOG_FILENAME

# disable these when safemode is requested
if [ $BUG_REPORT_SAFE_MODE -eq 0 ]; then

    # vulkaninfo

    (
        echo "____________________________________________"
        echo ""

        vulkaninfo=`which vulkaninfo 2> /dev/null | head -n 1`

        if [ $? -eq 0 -a -x "$vulkaninfo" ]; then
            echo "$vulkaninfo"
            echo ""
            $vulkaninfo 2> /dev/null
            echo ""
        else
            report_skip "vulkaninfo output" "vulkaninfo not found"
            echo ""
        fi
    ) | $GZIP_CMD >> $LOG_FILENAME

    # nvidia-smi

    NVML_LOG_FILE="nvidia-nvml-temp$$.log"
    touch $NVML_LOG_FILE 2>/dev/null
    if [ -w $NVML_LOG_FILE ]; then
        export __NVML_DBG_FILE=${NVML_LOG_FILE} __NVML_DBG_APPEND=1 __NVML_DBG_LVL=DEBUG
    fi

    (
        echo "____________________________________________"
        echo ""

        nvidia_smi=`which nvidia-smi 2> /dev/null | head -n 1`

        if [ $? -eq 0 -a -x "$nvidia_smi" ]; then
            report_command "$nvidia_smi --query"
            report_command "$nvidia_smi --query --unit"
            report_command "$nvidia_smi nvlink --errorcounters"
            report_command "$nvidia_smi nvlink --remotelinkinfo"
            report_command "$nvidia_smi nvlink --status"
            report_command "$nvidia_smi conf-compute --query-conf-compute"
        else
            report_skip "nvidia-smi output" "nvidia-smi not found"
            echo ""
        fi
    ) | $GZIP_CMD >> $LOG_FILENAME

    if [ -f $NVML_LOG_FILE ]; then
        append_binary_file $NVML_LOG_FILE
        rm -f $NVML_LOG_FILE
        unset __NVML_DBG_FILE __NVML_DBG_APPEND __NVML_DBG_LVL
    fi
else
    (
        report_skip "nvidia-smi, vulkaninfo etc. Commands" "Skipping due to --safe-mode-argument"
        echo ""
    ) | $GZIP_CMD >> $LOG_FILENAME
fi

# InfiniBand Support
if [ $BUG_REPORT_SAFE_MODE -eq 0 ]; then
    (
        echo "____________________________________________"
        echo ""

        # Check if ibstat is available to discover devices
        ibstat_cmd=`which ibstat 2> /dev/null | head -n 1`

        if [ $? -eq 0 -a -x "$ibstat_cmd" ]; then
            # Run ibstat without device specification (covers all devices)
            report_command "$ibstat_cmd"

            # List all InfiniBand devices
            devices=`$ibstat_cmd -l`

            # Iterate over each device
            for device in $devices; do
                echo "Running InfiniBand commands for device: $device"
                echo ""

                # ibnetdiscover
                ibnetdiscover_cmd=`which ibnetdiscover 2> /dev/null | head -n 1`
                if [ $? -eq 0 -a -x "$ibnetdiscover_cmd" ]; then
                    report_command "$ibnetdiscover_cmd -C $device"
                else
                    report_skip "ibnetdiscover output" "ibnetdiscover not found"
                    echo ""
                fi

                # ibswitches
                ibswitches_cmd=`which ibswitches 2> /dev/null | head -n 1`
                if [ $? -eq 0 -a -x "$ibswitches_cmd" ]; then
                    report_command "$ibswitches_cmd -C $device"
                else
                    report_skip "ibswitches output" "ibswitches not found"
                    echo ""
                fi

                # iblinkinfo
                iblinkinfo_cmd=`which iblinkinfo 2> /dev/null | head -n 1`
                if [ $? -eq 0 -a -x "$iblinkinfo_cmd" ]; then
                    report_command "$iblinkinfo_cmd -C $device"
                else
                    report_skip "iblinkinfo output" "iblinkinfo not found"
                    echo ""
                fi

                echo ""
            done
        else
            report_skip "ibstat output" "ibstat not found"
            echo ""
        fi
    ) | $GZIP_CMD >> $LOG_FILENAME
else
    (
        report_skip "Infiniband Commands" "Skipping due to --safe-mode-argument"
        echo ""
    ) | $GZIP_CMD >> $LOG_FILENAME
fi

# copy fabric manager (for NVSwitch based systems) default log file
append_silent "${HOST_ROOT}/var/log/fabricmanager.log"
# get fabric manager service status information
systemctl=`which systemctl 2> /dev/null | head -n 1`
if [ $? -eq 0 -a -x "$systemctl" ]; then
    cmd="$systemctl status nvidia-fabricmanager.service"
    (
        echo "____________________________________________"
        echo ""
        echo "$cmd"
        $cmd
        echo ""
    ) 2> /dev/null | $GZIP_CMD >> $LOG_FILENAME
fi

#copy IMEX daemon (for multi-node compute systems) default log file
append_silent "${HOST_ROOT}/var/log/nvidia-imex.log"
append_silent "${HOST_ROOT}/var/log/nvidia-imex-verbose.log"
append_silent "${HOST_ROOT}/var/log/nvidia-imex-stats.log"
# get nvidia-imex service status information
if [ $? -eq 0 -a -x "$systemctl" ]; then
    cmd="$systemctl status nvidia-imex.service"
    (
        echo "____________________________________________"
        echo ""
        echo "$cmd"
        $cmd
        echo ""
    ) 2> /dev/null | $GZIP_CMD >> $LOG_FILENAME
fi
# get nvidia-imex-ctl output
imexctl=`which nvidia-imex-ctl 2> /dev/null | head -n 1`
if [ $? -eq 0 -a -x "$imexctl" ]; then
    cmd="$imexctl -N"
    (
        echo "____________________________________________"
        echo ""
        echo "$cmd"
        $cmd
        echo ""
    ) 2> /dev/null | $GZIP_CMD >> $LOG_FILENAME
fi

# Print information about the libglvnd libraries
(
    if [ -e $GLVND_HELPER_BASE_PATH/glvnd_check ] ; then
        echo "____________________________________________"
        echo ""
        echo Checking libglvnd library libraries.
        print_libglvnd_library $GLVND_HELPER_BASE_PATH glx libGL.so.1
        print_libglvnd_library $GLVND_HELPER_BASE_PATH glx libGLX.so.0
        print_libglvnd_library $GLVND_HELPER_BASE_PATH egl libEGL.so.1
        if [ "$?" -eq 0 ] ; then
            print_libglvnd_library $GLVND_HELPER_BASE_PATH gl libOpenGL.so.0
            print_libglvnd_library $GLVND_HELPER_BASE_PATH gl libGLESv1_CM.so.1
            print_libglvnd_library $GLVND_HELPER_BASE_PATH gl libGLESv2.so.2
        fi
    fi
    if [ -e $GLVND_HELPER_BASE_PATH/32/glvnd_check ] ; then
        # We might not have a 32-bit libc available, so first check whether we
        # can run the 32-bit version of glvnd_check at all.
        if $GLVND_HELPER_BASE_PATH/32/glvnd_check nop 2> /dev/null ; then
            echo "____________________________________________"
            echo ""
            echo Checking 32-bit libglvnd libraries.
            print_libglvnd_library $GLVND_HELPER_BASE_PATH/32 glx libGL.so.1
            print_libglvnd_library $GLVND_HELPER_BASE_PATH/32 glx libGLX.so.0
            print_libglvnd_library $GLVND_HELPER_BASE_PATH/32 egl libEGL.so.1
            if [ "$?" -eq 0 ] ; then
                print_libglvnd_library $GLVND_HELPER_BASE_PATH/32 gl libOpenGL.so.0
                print_libglvnd_library $GLVND_HELPER_BASE_PATH/32 gl libGLESv1_CM.so.1
                print_libglvnd_library $GLVND_HELPER_BASE_PATH/32 gl libGLESv2.so.2
            fi
        else
            echo "____________________________________________"
            echo No 32-bit loader available, not checking 32-bit libglvnd libraries.
        fi
    fi
) | $GZIP_CMD >> $LOG_FILENAME

(
    echo "____________________________________________"
    echo ""
    acpidump=`which acpidump 2> /dev/null | head -n 1`

    if [ $? -eq 0 -a -x "$acpidump" ]; then

        base64=`which base64 2> /dev/null | head -n 1`

        if [ $? -eq 0 -a -x "$base64" ]; then

            TEMP_FILENAME="$TMPDIR/acpidump-temp$$.log"

            echo "$acpidump -o"
            echo ""
            $acpidump -o $TEMP_FILENAME 2> /dev/null

            # make sure if data file is created
            if [ -f "$TEMP_FILENAME" ]; then
                $base64 $TEMP_FILENAME 2> /dev/null
                echo ""

                # remove the temporary file when complete
                rm $TEMP_FILENAME 2> /dev/null
            else
                report_skip "acpidump output" "Can't create data file $TEMP_FILENAME"
                echo ""
                # don't fail here, continue
            fi
        else
            report_skip "acpidump output" "base64 not found"
            echo ""
        fi
    else
        report_skip "acpidump output" "acpidump not found"
        echo ""
    fi
) | $GZIP_CMD >> $LOG_FILENAME

dump_mlx() {
    MLX_CSV="$TMPDIR/mlx$$.csv"
    MLX_INFO="$TMPDIR/mlx$$.info"
    # mlxlink --amber_collect file will dump information to the specified csv file, and
    # print information to stdout (in color).
    # Capture both and remove the color escape characters.
    echo "$1 -d $2 --amber_collect $MLX_CSV > $MLX_INFO 2>&1"
    mlx_output=`"$1" -d "$2" --amber_collect "$MLX_CSV" > "$MLX_INFO" 2>&1`
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        cat "$MLX_INFO" | sed -Ee 's/\x1b\[[0-9;]+m//g' 2> /dev/null
        cat "$MLX_CSV" 2> /dev/null
        echo "____________________________________________"
        echo ""
        rm -f "$MLX_INFO" 2> /dev/null
        rm -f "$MLX_CSV" 2> /dev/null
        break
    else
        echo "failed with error $exit_code retrying..."
        echo "$mlx_output"
        cat "$MLX_INFO" | sed -Ee 's/\x1b\[[0-9;]+m//g' 2> /dev/null
        rm -f "$MLX_INFO" 2> /dev/null
        rm -f "$MLX_CSV" 2> /dev/null
        echo "____________________________________________"
    fi
}

(
    mst=`which mst 2> /dev/null | head -n 1`

    if [ $? -eq 0 -a -x "$mst" ]; then

        mlxlink=`which mlxlink 2> /dev/null | head -n 1`

        if [ $? -eq 0 -a -x "$mlxlink" ]; then
            # loads PCI driver & creates PCI devices file descriptors under /dev/mst/.
            echo "____________________________________________"
            echo ""
            report_command "timeout 60 $mst start"
            echo "____________________________________________"
            echo ""

            # scans and adds gpu devices
            report_command "timeout 60 $mst gpu add"
            echo "____________________________________________"
            echo ""

            # Discover and add IB devices dynamically
            ib_devices=$(discover_ib_devices)
            if [ -n "$ib_devices" ]; then
                for ib_device in $ib_devices; do
                    report_command "timeout 60 $mst ib add $ib_device"
                done
            else
                # Fallback to mlx5_0 if no devices discovered
                report_command "timeout 60 $mst ib add mlx5_0"
            fi
            echo "____________________________________________"
            echo ""

            resourcedump=`which resourcedump 2> /dev/null | head -n 1`
            mstdump=`which mstdump 2> /dev/null | head -n 1`
            mlxreg=`which mlxreg 2> /dev/null | head -n 1`

            # dumps all the scanned devices
            report_command "timeout 60 $mst status -v"
            echo "____________________________________________"
            echo ""

            # Iterate and get dumps for each of the supported devices
            "$mst" status -v |
            {
                # Get IB devices for use in subshell
                ib_devices_shell="$ib_devices"
                while read tmp_line
                do
                echo $tmp_line | grep "netir" > /dev/null  2>&1
                if [ $? -eq 0 ]; then
                    devName=`echo $tmp_line | awk -F" " 'NR == 1 {print $1}';`
                    if [ ! -z "$devName" ]; then
                        echo "Starting GPU MST dump..."$tmp_line
                        echo "____________________________________________"
                        dump_mlx "$mlxlink" "$devName"
                        if [ ! -z "$resourcedump" ]; then
                            report_command "$resourcedump dump -d $devName -s 0x5024"
                            echo "____________________________________________"
                            echo ""
                        fi
                    fi
                fi
                # Check for Quantum devices on any discovered IB device
                for ib_device in $ib_devices_shell; do
                    echo $tmp_line | grep "Quantum" | grep "$ib_device" > /dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        devName=`echo $tmp_line | awk -F" " 'NR == 1 {print $1}';`
                        if [ ! -z "$devName" ]; then
                            echo "Starting Quantum dump..."$tmp_line
                            echo "____________________________________________"
                            dump_mlx "$mlxlink" "$devName"
                            if [ ! -z "$resourcedump" ]; then
                                report_command "$resourcedump dump -d $devName -s 0x5024"
                                echo "____________________________________________"
                                echo "Starting Quantum flash dump..."
                                echo "____________________________________________"
                                report_command "$resourcedump dump -d $devName -s 0x5028"
                                echo "____________________________________________"
                                if [ ! -z "$mlxreg" ]; then
                                    echo "Clearing Quantum flash dump..."
                                    echo "____________________________________________"
                                    report_command "$mlxreg -d $devName --set erase_log=0x1 --reg_name MOFDE -y"
                                    echo "____________________________________________"
                                fi
                                echo ""
                            fi
                        fi
                        break
                    fi
                done
                echo $tmp_line | grep "ConnectX" > /dev/null 2>&1
                if [ $? -eq 0 ]; then
                    devName=`echo $tmp_line | awk -F" " 'NR == 1 {print $3}';`
                    if [ ! -z "$devName" ]; then
                        # Check if this is a primary function (.0) or VF (.1, .2, etc.)
                        if echo "$devName" | grep -q "\.0$"; then
                            echo "Starting ConnectX dump (PRIMARY FUNCTION)($devName)..."$tmp_line
                            echo "____________________________________________"
                            dump_mlx "$mlxlink" "$devName"
                            if [ ! -z "$mstdump" ]; then
                                report_command "$mstdump $devName"
                                echo "____________________________________________"
                                echo ""
                            fi
                        else
                            echo "Skipping ConnectX VF (skipping mstdump)($devName)..."$tmp_line
                        fi
                    fi
                fi
                done
            }

            # stop due to resource contention.
            echo ""
            report_command "$mst stop"
            echo "____________________________________________"

        else
            echo "____________________________________________"
            echo ""
            report_skip "mlxlink output" "mlxlink not found"
            echo ""
        fi

    else
        echo "____________________________________________"
        echo ""
        report_skip "mst output" "mst not found"
        echo ""
    fi
) | $GZIP_CMD >> $LOG_FILENAME

# Collect NVLSM dumps
(
    NVLSM_SBIN_PATH=/opt/nvidia/nvlsm/sbin

    echo "____________________________________________"
    echo ""

    nvlsm_bug_report=`PATH=$PATH:$NVLSM_SBIN_PATH which nvlsm-bug-report.sh 2> /dev/null | head -n 1`
    if [ $? -eq 0 -a -x "${nvlsm_bug_report}" ]; then
        echo "Collecting NVLink Subnet Manager (NVLSM) information..."
        report_command "${nvlsm_bug_report} --stdout"
    else
        report_skip "nvlsm-bug-report.sh output" "nvlsm-bug-report.sh not found"
        echo ""
    fi
) | $GZIP_CMD >> $LOG_FILENAME


echo " complete."
echo ""

TMP_LOG=$(mktemp)

{
  echo ""
  echo "Summary of Skipped Sections:"
  echo ""
  print_skips_table
  echo ""
  echo "Summary of Errors:"
  echo ""
  print_errors_table
  echo ""
} | tee "$TMP_LOG"

cat "$TMP_LOG" | $GZIP_CMD >> "$LOG_FILENAME"
rm -f "$TMP_LOG"

(
    echo "____________________________________________"

    # print epilogue to log file

    echo ""
    echo "End of NVIDIA bug report log file."
) | $GZIP_CMD >> $LOG_FILENAME


rm -f "$SKIP_TMP" "$ERROR_TMP" "$TMP_LOG"
