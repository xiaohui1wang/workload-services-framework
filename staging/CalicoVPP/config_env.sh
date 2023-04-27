#!/bin/bash

# shellcheck source=/dev/null
source ./common.sh

function usage {
    cat <<EOF

        config_env.sh is used to configure K8S. 
        Before run this script, please run 'install_env.sh' to install testing environment and run 'build_images.sh' to build necessary docker images.

        Usage:
            ./config_env.sh --mode dsa[sw] --ipv4 <ipv4-address> [--mtu 1500|9000] [--cidr <K8S-pod-CIDR>] [--dsa-device <dsa-device-pci-num>]
                [--core-nums <core-numbers>] [--help|-h]

        Examples:
            ./config_env.sh --mode dsa --ipv4 192.168.0.11                                    # Configure K8S with DSA interface
            ./config_env.sh --mode dsa --mtu 9000 --ipv4 192.168.0.11                         # Configure K8S with DSA interface and mtu 9000
            ./config_env.sh --mode sw --ipv4 192.168.0.11 --core_nums 2                       # Configure K8S with SW interface and 2 CPU cores

        Parameters:
            --mode dsa[sw]: [Required] Specify testing mode, value can be 'dsa' or 'sw' for DSA or SW mode.
            --ipv4 <ipv4-address>: [Required] Specify ipv4 address on which K8S will be installed, generally, it's node private IPv4 address with 100Gbps bandwidth.
            --mtu 1500|9000: [Optional] Specify MTU, value can be 1500 or 9000. Default is 1500.
            --cidr <K8S-pod-CIDR>: [Optional] Specify K8S pod CIDR. Default is 10.244.0.0/16. Change default value only when it conflicts with testing environment.
            --dsa-device <dsa-device-pci-num>: [Optional] Specify DSA device pci number for DSA memif testing, will get the first DSA device (for example: 6a:01.0) 
                if not specify this parameter. Run command "lspci -v | grep 0b25" can get DSA device list.
            --core-nums <core-numbers>: [Optional] Specify how many CPU cores will be used for the testing. Default is 1.
            --help|-h: [Optional] Show help messages.

EOF
}

# Check conditions before configuring K8S
function check_conditions() {
    info "Checking environment and configurations..."
    check_os
    check_swap
    check_hugepages
    check_docker
    check_k8s
    check_if_has_configured
    check_required_parameters
    check_and_get_interface_by_ipv4
}

# Check and get NIC interface by IPV4 address
function check_and_get_interface_by_ipv4() {
    interface=$(netstat -ie | grep -B1 " $ipv4 " | head -n1 | awk '{print $1}')
    interface=${interface//:/} # Remove the last char ":" of interface
    [[ -n $interface ]] || error "Cannot find NIC interface by ipv4 address: $ipv4"
    check_nic_interface "" "$interface"
    interface_mac=$(ip link show "$interface" | grep link/ether | awk '{print $2}')
    [[ -n $interface_mac ]] || error "Cannot find MAC address of interface: $interface"
    interface_pci=$(ethtool -i "$interface" | grep bus-info | awk '{print $2}')
    [[ -n $interface_pci ]] || error "Cannot find PCI number of interface: $interface"
}

# Check required parameters
function check_required_parameters() {
    check_not_empty "--mode" "$config_mode"
    check_not_empty "--ipv4" "$ipv4"
}

# Config MTU
function configure_mtu() {
    info "Setting MTU to $mtu for interface $interface..."
    sudo ifconfig "$interface" mtu "$mtu" || error "Failed to set MTU to $mtu for interface $interface"
}

# Update common params of calico vpp yaml file
function update_common_params_of_vpp_yaml() {
    # Update CIDR
    sed -i "s|CIDR_VALUE_TMP|${cidr}|g" "$CALICOVPP_INSTALLATION_DEP_YAML"
    # Update MTU
    sed -i "s|MTU_VALUE_TMP|${mtu}|g" "$CALICOVPP_INSTALLATION_DEP_YAML"
    # Update VPP main core number
    sed -i "s|VPP_MAIN_CORE_VALUE_TMP|${vpp_cores_start}|g" "$CALICOVPP_DEP_YAML"
    # Update VPP workers core number
    sed -i "s|VPP_WORKERS_CORE_VALUE_TMP|$((vpp_cores_start + 1))-$((vpp_cores_start + core_nums))|g" "$CALICOVPP_DEP_YAML"
    # Update core number related vars
    sed -i "s|CALICOVPP_CORES_VALUE_TMP|${core_nums}|g" "$CALICOVPP_DEP_YAML"
    # Update NIC interface
    sed -i "s|VPP_DATAPLANE_INTERFACE_VALUE_TMP|${interface}|g" "$CALICOVPP_DEP_YAML"
}

# Prepar Calico VPP DSA memif relate yaml files
function prepare_calicovpp_dsa_yaml_files() {
    info "Preparing Calico VPP DSA memif yaml files..."
    cp "$CALICOVPP_OPERATOR_TMP_YAML" "$CALICOVPP_OPERATOR_DEP_YAML"
    cp "$CALICOVPP_INSTALLATION_TMP_YAML" "$CALICOVPP_INSTALLATION_DEP_YAML"
    cp "$CALICOVPP_DSA_TMP_YAML" "$CALICOVPP_DEP_YAML"
    update_common_params_of_vpp_yaml
    # Update DSA device
    sed -i "s|DSA_DEVICE_VALUE_TMP|0000:${dsa_device}|g" "$CALICOVPP_DEP_YAML"
    # Change buffer size when mtu is 9000
    [[ "$mtu" = "$MTU_9000" ]] && sed -i "s|buffers-per-numa.*|default data-size 10240|g" "$CALICOVPP_DEP_YAML"
}

# Prepar Calico VPP SW memif relate yaml files
function prepare_calicovpp_sw_yaml_files() {
    info "Preparing Calico VPP SW memif yaml files..."
    cp "$CALICOVPP_OPERATOR_TMP_YAML" "$CALICOVPP_OPERATOR_DEP_YAML"
    cp "$CALICOVPP_INSTALLATION_TMP_YAML" "$CALICOVPP_INSTALLATION_DEP_YAML"
    cp "$CALICOVPP_NO_DSA_TMP_YAML" "$CALICOVPP_DEP_YAML"
    update_common_params_of_vpp_yaml
    # Change buffer size when mtu is 9000
    [[ "$mtu" = "$MTU_9000" ]] && sed -i "s|buffers-per-numa.*|default data-size 10240|g" "$CALICOVPP_DEP_YAML"
}

# Init K8S and CNI
function init_k8s_and_cni() {
    info "Initializing K8S, this may take some time..."
    sudo kubeadm init --pod-network-cidr="${cidr}" --apiserver-advertise-address="${ipv4}" --kubernetes-version="${K8S_VER/-00/}" || \
        error "Failed to initialize K8S."
    mkdir -p "$HOME/.kube"
    sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    kubectl taint nodes --all node-role.kubernetes.io/master-
    info "Installing CNI..."
    kubectl create -f "$CALICOVPP_OPERATOR_DEP_YAML"
    sleep 5
    kubectl create -f "$CALICOVPP_INSTALLATION_DEP_YAML"
    sleep 5
    kubectl create -f "$CALICOVPP_DEP_YAML"
}

# Wait for K8S to be ready
function wait_k8s_ready() {
    for i in $(seq 20); do
        apiserver_pod_num=$(kubectl get pod -A | grep -c -e "calico-apiserver\s*calico-apiserver.*1/1\s*Running")
        if [[ $apiserver_pod_num -lt 2 ]]; then
            info "Waiting for K8S to be ready...#${i}"
            check_if_need_update_mac
            check_if_need_reset
            sleep 30
        else
            info "K8S is ready."
            return
        fi
    done
    warn "K8S is not ready, pod status:"
    kubectl get pod -A
    error "Failed to configure K8S, please check pod status for troubleshooting."
}

# Check if need to update mac address
function check_if_need_update_mac() {
    new_interface_mac=$(ip link show "$interface" | grep link/ether | awk '{print $2}')
    [[ "$new_interface_mac" = "$interface_mac" ]] && return
    info "Changing MAC address for interface $interface..."
    sudo macchanger -m "$interface_mac" "$interface"
    sleep 30
}

# Check if need reset K8S
# Sometimes, Core DNS pods may not be ready, need to reset K8S and configure it again.
# Rebooting OS is a workaround if still cannot configure K8S after resetting.
function check_if_need_reset() {
    coredns_failed_pod_num=$(kubectl get pod -A | grep -c -e "kube-system\s*coredns.*0/1\s*Running")
    if [[ $coredns_failed_pod_num -gt 0 ]]; then
        warn "Core DNS pod is not ready, reseting K8S env..."
        ./reset_env.sh -y
        error "Failed to configure K8S due to DNS pod is not ready, please try to configure it again or reboot OS then config it."
    fi
}

# Install tool 'calivppctl' and configure route in VPP for packet loopback
function install_calivppctl_and_config_route() {
    info "Installing tool 'calivppctl'..."
    # Install 'calivppctl'
    container=$(docker ps | grep vpp_calico-vpp | awk '{ print $1 }')
    sudo docker cp "$container:/usr/bin/calivppctl" /usr/bin/calivppctl
}

# Save configuration parameters to file
function save_configuration_parameters() {
    {
        echo "Configuration mode: $config_mode"
        echo "K8S controller IP address: $ipv4"
        echo "NIC interface: $interface"
        echo "NIC interface pci: $interface_pci"
        echo "MTU: $mtu"
        echo "K8S pod CIDR: $cidr"
        echo "DSA device: ${dsa_device:-N/A}"
        echo "Core numbers: $core_nums"
        echo "VPP cores start: $vpp_cores_start"
        echo "Calico VPP MAC address: $interface_mac"
    } > "$CONFIG_PARAMS_FILE"
}

function config_k8s_dsa() {
    info "Configuring K8S with DSA memif interface..."
    configure_mtu
    prepare_calicovpp_dsa_yaml_files
    init_k8s_and_cni
    wait_k8s_ready
    install_calivppctl_and_config_route
}

function config_k8s_sw() {
    info "Configuring K8S with SW memif interface..."
    configure_mtu
    prepare_calicovpp_sw_yaml_files
    init_k8s_and_cni
    wait_k8s_ready
    install_calivppctl_and_config_route
}

##############################################################

# Defines config modes
CONFIG_MODE_DSA_MEMIF="dsa"
CONFIG_MODE_SW_MEMIF="sw"

# Supported MTU
MTU_1500="1500"
MTU_9000="9000"

# Define core numbers range
CPU_CORE_SIZE=$(grep "processor" < /proc/cpuinfo | awk '{print $3}' | wc -l)
CORE_NUMS_MIN=1
CORE_NUMS_MAX=32

# Default argument values
config_mode=""
ipv4=""
mtu=$MTU_1500
cidr="10.244.0.0/16"
dsa_device=""
core_nums=1                       # Single core testing
vpp_cores_start=0                 # 0 for VPP main, 1-$core_nums for VPP workers

# Parameters that will be used for deployment and E2E testing
interface=""
interface_pci=""
interface_mac=""

# Source yaml files used to deploy Calico VPP
CALICOVPP_OPERATOR_TMP_YAML=$CONFIGS_DIR/tigera-operator.yaml
CALICOVPP_INSTALLATION_TMP_YAML=$CONFIGS_DIR/installation-default_template.yaml
CALICOVPP_DSA_TMP_YAML=$CONFIGS_DIR/calico-vpp_dsa_template.yaml
CALICOVPP_NO_DSA_TMP_YAML=$CONFIGS_DIR/calico-vpp_no_dsa_template.yaml
# Target yaml files used to deploy Calico VPP
CALICOVPP_OPERATOR_DEP_YAML=$CONFIGS_DEP_DIR/tigera-operator.yaml
CALICOVPP_INSTALLATION_DEP_YAML=$CONFIGS_DEP_DIR/installation-default.yaml
CALICOVPP_DEP_YAML=$CONFIGS_DEP_DIR/calico-vpp.yaml

# Parse input arguments
UNKNOWN_ARGS=""
while [[ "$1" != "" ]]
do
    arg=$1
    case $arg in
        --mode)
            shift
            check_not_empty "$arg" "$1"
            mode_values=("$CONFIG_MODE_DSA_MEMIF" "$CONFIG_MODE_SW_MEMIF")
            check_value_exist "$arg" "$1" "${mode_values[@]}"
            config_mode=$1
            ;;
        --ipv4)
            shift
            check_not_empty "$arg" "$1"
            check_ipv4_address "$arg" "$1"
            ipv4=$1
            ;;
        --mtu)
            shift
            check_not_empty "$arg" "$1"
            mtu_values=("$MTU_1500" "$MTU_9000")
            check_value_exist "$arg" "$1" "${mtu_values[@]}"
            mtu=$1
            ;;
        --cidr)
            shift
            check_not_empty "$arg" "$1"
            check_cidr "$arg" "$1"
            cidr=$1
            ;;
        --dsa-device)
            shift
            check_not_empty "$arg" "$1"
            check_dsa_device "$arg" "$1"
            dsa_device=$1
            ;;
        --core-nums)
            shift
            check_not_empty "$arg" "$1"
            check_number_in_range "$arg" "$1" "$CORE_NUMS_MIN" "$CORE_NUMS_MAX"
            core_nums=$1
            ;;
        --vpp-cores-start)
            shift
            check_not_empty "$arg" "$1"
            check_number_in_range "$arg" "$1" 0 $((CPU_CORE_SIZE - 1))
            vpp_cores_start=$1
            ;;
        --help|-h)
            usage && exit
            ;;
        *) UNKNOWN_ARGS="$UNKNOWN_ARGS $arg"
            ;;
    esac
    shift
done
[[ -z "$UNKNOWN_ARGS" ]] || error "Unknown arguments:$UNKNOWN_ARGS"

check_conditions

rm -rf "$CONFIGS_DEP_DIR"
mkdir -p "$CONFIGS_DEP_DIR"

# Check operations
if [[ "$config_mode" = "$CONFIG_MODE_DSA_MEMIF" ]]; then
    config_k8s_dsa
elif [[ "$config_mode" = "$CONFIG_MODE_SW_MEMIF" ]]; then
    config_k8s_sw
else
    error "Unknow configuration mode: $config_mode"
fi

save_configuration_parameters

info "Succeed to configure K8S, below are configuration parameters:"
cat "$CONFIG_PARAMS_FILE"
