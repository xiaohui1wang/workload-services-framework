#!/bin/bash

# shellcheck source=/dev/null
source ./common.sh

function usage {
    cat <<EOF

        build_images.sh is used to build docker images for Calico VPP VCL with DSA testing. After building, below images will be generated,
            calicovpp_dsa_vcl_agent:v1
            calicovpp_dsa_vcl_vpp:v1

        Usage:
            ./build_images.sh [--help|-h]

        Example:
            ./build_images.sh                   # Build images

        Parameters:
            --help|-h: [Optional] Show help messages.

EOF
}

function check_env() {
    info "Checking environment..."
    check_os
    check_golang
    check_docker
}

function clone_code() {
    # Clone Calico VPP vpp-dataplane
    info "Preparing Calico VPP code..."
    VPP_TAG=v3.25.1
    git clone --branch $VPP_TAG https://github.com/projectcalico/vpp-dataplane.git "${CALICOVPP_DIR}"
    cd "${CALICOVPP_DIR}" || exit
    git switch -c $VPP_TAG
    git apply "${BASE_DIR}/patch/calicovpp.patch"

    # Copy vpp_dsa_rx.patch
    # cp "${BASE_DIR}/patch/0006-dsa-rx.patch" "${CALICOVPP_DIR}/vpplink/binapi/patches/" || exit

    # Copy vcl-wrk patch
    cp "${BASE_DIR}/patch/vcl-wrk.patch" "${CALICOVPP_DIR}/vpplink/binapi/patches/" || exit
}

function build_images() {
    # Build agent bin and image
    info "Building Calico VPP agent image..."
    cd "${CALICOVPP_DIR}" || exit
    make -C ./calico-vpp-agent image
    docker tag calicovpp/agent:latest "${AGENT_IMAGE_NAME}"
    docker push "${AGENT_IMAGE_NAME}"

    # Copy version file
    cp ./calico-vpp-agent/version ./vpp-manager/images/ubuntu

    # Build vpp bin and image
    info "Building Calico VPP vpp image..."
    make -C ./vpp-manager vpp imageonly
    docker tag calicovpp/vpp:latest "${VPP_IMAGE_NAME}"
    docker push "${VPP_IMAGE_NAME}"
}

function show_images() {
    info "Calico VPP VCL with DSA related images:"
    docker images | grep calicovpp_dsa_vcl
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

BASE_DIR=$(pwd)
CALICOVPP_DIR="${BASE_DIR}/vpp-dataplane"
VPP_DIR="${BASE_DIR}/vpp"

rm -rf "${CALICOVPP_DIR}"
rm -rf "${VPP_DIR}"

check_env
clone_code
build_images
show_images
