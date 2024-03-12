#!/bin/bash

# shellcheck source=/dev/null
source ./common.sh

function usage {
    cat <<EOF

        install_env.sh is used to install necessary components for setting up K8S env.

        Usage:
            ./install_env.sh [--help|-h]

        Example:
            ./install_env.sh                   # Install components

        Parameters:
            --help|-h: [Optional] Show help messages.

EOF
}

function install_containerd() {
    info "Installing containerd..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository -y "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    #sudo apt-get -y install containerd.io=${CONTAINERD_VER} docker-ce=${DOCKER_VER} docker-ce-cli=${DOCKER_VER} --allow-change-held-packages
    sudo apt-get -y install containerd.io=${CONTAINERD_VER} --allow-change-held-packages

    setup_containerd_proxy
    setup_containerd_config

    sudo systemctl daemon-reload
    sudo systemctl restart containerd > /dev/null
    for i in $(seq 10); do
        if sudo systemctl status containerd > /dev/null; then
            info "Start containerd successfully."
            return
        fi
        warn "Failed to start containerd service, waiting 30s and retry...#${i}"
        sleep 30
        info "Starting containerd..."
        sudo systemctl start containerd > /dev/null
    done
    error "Failed to install containerd."
}

function setup_containerd_proxy() {
    info "Setting Docker proxy..."
    sudo mkdir -p /etc/systemd/system/containerd.service.d
    if [[ -n "${http_proxy}" ]]; then
        sudo tee /etc/systemd/system/containerd.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=${http_proxy}"
EOF
    fi
    if [[ -n "${https_proxy}" ]]; then
        sudo tee /etc/systemd/system/containerd.service.d/https-proxy.conf <<EOF
[Service]
Environment="HTTPS_PROXY=${https_proxy}"
EOF
    fi
    if [[ -n "${no_proxy}" ]]; then
        sudo tee /etc/systemd/system/containerd.service.d/no-proxy.conf <<EOF
[Service]
Environment="NO_PROXY=${no_proxy}"
EOF
    fi
}

function setup_containerd_config() {
    info "Setting containerd configuration..."
    sudo cp configs/containerd/config.toml /etc/containerd/config.toml  
}

function setup_docker_config() {
    info "Setting Docker configuration..."
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<EOF
{
    "insecure-registries" : ["10.67.115.219:5000"],
    "exec-opts":["native.cgroupdriver=systemd"],
    "experimental": true,
    "registry-mirrors": []
}
EOF
}

function install_k8s() {
    info "Installing K8S..."
    sudo DEBIAN_FRONTEND='noninteractive' /usr/bin/apt-get -y install apt-transport-https ca-certificates curl

    # Old official method, depreciated
    #sudo curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    #sudo add-apt-repository -y "deb [arch=$(dpkg --print-architecture)] http://apt.kubernetes.io/ kubernetes-xenial main"

    # New official method, v1.26
    #echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.26/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    #sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.26/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    # Use aliyun repo
    echo "deb https://mirrors.aliyun.com/kubernetes/apt kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update || error "Failed to update apt repository."
    sudo apt-get -y install kubeadm="${K8S_VER}" kubelet="${K8S_VER}" kubectl="${K8S_VER}" || error "Failed to install K8S related components."
}

function install_dpdk_tool() {
    DPDK_VER=21.05
    DPDK_PKG=dpdk-${DPDK_VER}.tar.xz
    for i in $(seq 10); do
        info "Installing DPDK tool..."
        if curl -OL https://fast.dpdk.org/rel/${DPDK_PKG} && \
            sudo rm -f /usr/local/bin/dpdk-devbind.py && sudo rm -rf /usr/local/dpdk-* && \
            sudo tar -C /usr/local -xf ${DPDK_PKG} && rm -f ${DPDK_PKG} && \
            sudo ln -s /usr/local/dpdk-${DPDK_VER}/usertools/dpdk-devbind.py /usr/local/bin/dpdk-devbind.py; then
            info "Installed DPDK tool successfully."
            return
        fi
        warn "Failed to install DPDK tool, waiting 30s and retry...#${i}"
        sleep 30
    done
    error "Failed to install DPDK tool."
}

function enable_netfilter() {
    info "Enabling netfilter..."
    sudo modprobe br_netfilter
    sudo sysctl -p /etc/sysctl.conf
}

function disable_firewall() {
    info "Disabling firewall..."
    sudo ufw disable > /dev/null || error "Failed to disable firewall."
}

function check_installation_status() {
    info "Checking installation status..."
    # Check containerd and service
    if [[ -x "$(command -v containerd)" ]]; then
        info "Containerd has been installed - OK"
    else
        warn "Containerd has NOT been installed - FAILED"
    fi
    if sudo systemctl status containerd > /dev/null; then
        info "Containerd service has been started - OK"
    else
        warn "Containerd service has NOT been started - FAILED"
    fi
    # Check K8S
    if [[ -x "$(command -v kubeadm)" && -x "$(command -v kubelet)" && -x "$(command -v kubectl)" ]]; then
        info "K8S has been installed - OK"
    else
        warn "K8S has NOT been installed - FAILED"
    fi
    # Check DPDK tool
    if [[ -x "$(command -v dpdk-devbind.py)" ]]; then
        info "DPDK tool has been installed - OK"
    else
        warn "DPDK tool has NOT been installed - FAILED"
    fi
}

##############################################################

# Parse input arguments
UNKNOWN_ARGS=""
while [[ "$1" != "" ]]
do
    arg=$1
    case $arg in
        --help|-h)
            usage && exit
            ;;
        *) UNKNOWN_ARGS="$UNKNOWN_ARGS $arg"
            ;;
    esac
    shift
done
[[ -z "$UNKNOWN_ARGS" ]] || error "Unknown arguments:$UNKNOWN_ARGS"

check_os
install_containerd
install_k8s
install_dpdk_tool
disable_firewall
enable_netfilter
check_installation_status
