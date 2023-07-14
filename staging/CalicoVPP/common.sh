#!/bin/bash

# This script defines common functions

# Versions
export K8S_VER=1.24.4-00
export CONTAINERD_VER=1.6.21-1

# Dirs
BASE_DIR=$(pwd)
export BASE_DIR
export CONFIGS_DIR=$BASE_DIR/configs
export CONFIGS_DEP_DIR=$BASE_DIR/configs_dep

# Configuration parameters file
export CONFIG_PARAMS_FILE=$CONFIGS_DEP_DIR/config_params.txt

# Logs functions
function logdate { date "+%Y-%m-%d %H:%M:%S"; }
function info { echo "$(logdate) [INFO] $*"; }
function warn { echo "$(logdate) [WARN] $*"; }
function error { echo "$(logdate) [ERROR] $*"; exit 1; }

# Show confirm message
function confirm() {
    if [[ "${skip_confirm:-''}" != "true" ]]; then
        read -r -p "${1}. Are you sure to continue? [y/N] " response
        case "${response}" in
            [yY][eE][sS]|[yY])
                return
                ;;
            *)
                exit 0
                ;;
        esac
    fi
}

# Check if value is empty or not. Format: var_name var_val
function check_not_empty() {
    [[ -n "$2" ]] || error "$1 value cannot be empty."
}

# Check if number is in range. Format: var_name var_val var_min var_max
function check_number_in_range() {
    [[ $2 =~ ^-?[0-9]+$ ]] || error "$1 value '$2' is not a number."
    [[ $2 -ge $3 && $2 -le $4 ]] || error "$1 value '$2' is not in range [$3,$4]."
}

# Check if value exists or not. Format: var_name var_val var_val1 var_val2 ...
function check_value_exist() {
    local e
    for e in "${@:3}"; do 
        [ "$e" = "$2" ] && return 
    done
    error "$1 value '$2' is not supported, accept values: ${*:3}."
}

# Check if value is a valid CIDR. Format: var_name var_val
function check_cidr() {
    [[ "$2" =~ ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(3[0-2]|[1-2][0-9]|[1-9]))$ ]] || error "'$2' is not a valid CIDR."
}

# Check if NIC interface exists. Format: var_name var_val
function check_nic_interface() {
    sudo ethtool "$2" > /dev/null 2>&1 || error "Interface '$2' does not exist."
    sudo ethtool "$2" | grep -q "Link detected: yes" || error "Interface '$2' is not linked."
}

# Check ipv4 address. Format: var_name var_val
function check_ipv4_address() {
    [[ "$2" =~ ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]] || error "'$2' is not a valid IPv4 address."
}

# Check MAC address. Format: var_name var_val
function check_mac_address() {
    [[ "$2" =~ ^([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$ ]] || error "'$2' is not a valid MAC address."
}

# Check if swap is disabled
function check_swap() {
    [[ -z "$(swapon -s)" ]] || error "Swap is enabled, please disable it and try again."
}

# Check OS
function check_os() {
    os_name=$(grep 'NAME="Ubuntu"' < /etc/os-release)
    os_ver=$(grep 'VERSION_ID="22.04"' < /etc/os-release)
    [[ -n "${os_name}" && -n "${os_ver}" ]] || error "Only Ubuntu 22.04 is supported."
}

# Check containerd service
function check_containerd() {
    [[ -x "$(command -v containerd)" ]] || error "Containerd is not installed."
    sudo systemctl status containerd > /dev/null || error "Containerd service is stopped."
}

# Check K8S
function check_k8s() {
    [[ -x "$(command -v kubeadm)" && -x "$(command -v kubelet)" && -x "$(command -v kubectl)" ]] || error "K8S is not installed."
}

# Check if K8S has been configured
function check_if_has_configured() {
    sudo systemctl status kubelet > /dev/null && error "K8S has been configured, please run command './reset_env.sh -y' to reset it before configuring."
}
