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

function install_docker() {
    info "Installing Docker..."
    DOCKER_VER=5:20.10.18~3-0~ubuntu-jammy
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository -y "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get -y install containerd.io=1.6.10-1 docker-ce=${DOCKER_VER} docker-ce-cli=${DOCKER_VER} --allow-change-held-packages

    setup_docker_proxy
    setup_docker_config
    sudo usermod -aG docker "$USER" || error "Failed to add current user to docker group."

    sudo systemctl daemon-reload
    sudo systemctl restart docker > /dev/null
    # Check Docker status and restart if failed
    for i in $(seq 10); do
        if sudo systemctl status docker > /dev/null; then
            info "Start Docker successfully."
            return
        fi
        warn "Failed to start Docker service, waiting 30s and retry...#${i}"
        sleep 30
        info "Starting Docker..."
        sudo systemctl start docker > /dev/null
    done
    error "Failed to install Docker."
}

function setup_docker_proxy() {
    info "Setting Docker proxy..."
    sudo mkdir -p /etc/systemd/system/docker.service.d
    if [[ -n "${http_proxy}" ]]; then
        sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=${http_proxy}"
EOF
    fi
    if [[ -n "${https_proxy}" ]]; then
        sudo tee /etc/systemd/system/docker.service.d/https-proxy.conf <<EOF
[Service]
Environment="HTTPS_PROXY=${https_proxy}"
EOF
    fi
    if [[ -n "${no_proxy}" ]]; then
        sudo tee /etc/systemd/system/docker.service.d/no-proxy.conf <<EOF
[Service]
Environment="NO_PROXY=${no_proxy}"
EOF
    fi
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
    sudo curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    sudo add-apt-repository -y "deb [arch=$(dpkg --print-architecture)] http://apt.kubernetes.io/ kubernetes-xenial main"
    sudo apt-get -y install kubeadm="${K8S_VER}" kubelet="${K8S_VER}" kubectl="${K8S_VER}" || error "Failed to install K8S related components."
}

function disable_firewall() {
    info "Disabling firewall..."
    sudo ufw disable > /dev/null || error "Failed to disable firewall."
}

function check_installation_status() {
    info "Checking installation status..."
    # Check Docker and service
    if [[ -x "$(command -v docker)" ]]; then
        info "Docker has been installed - OK"
    else
        warn "Docker has NOT been installed - FAILED"
    fi
    if sudo systemctl status docker > /dev/null; then
        info "Docker service has been started - OK"
    else
        warn "Docker service has NOT been started - FAILED"
    fi
    # Check K8S
    if [[ -x "$(command -v kubeadm)" && -x "$(command -v kubelet)" && -x "$(command -v kubectl)" ]]; then
        info "K8S has been installed - OK"
    else
        warn "K8S has NOT been installed - FAILED"
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
install_docker
install_k8s
disable_firewall
check_installation_status
