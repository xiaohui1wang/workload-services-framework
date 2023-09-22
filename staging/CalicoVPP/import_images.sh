#!/bin/bash

# shellcheck source=/dev/null
source ./common.sh

function usage {
    cat <<EOF

        import_images.sh is used to import images for K8S deployment.

        Usage:
            ./import_images.sh [-f] [--help|-h]

        Example:
            ./import_images.sh                   # Import images, skip download if file exists.
            ./import_images.sh -f                # Import images, download and override image if file exists.

        Parameters:
            -f: [Optional] Force download image.
            --help|-h: [Optional] Show help messages.

EOF
}

function import_images() {
  if [[ ! -x "$(command -v ctr)" ]]; then
    error "containerd is not installed."
  fi

  REPO_IP=10.166.32.86

  export no_proxy=$no_proxy,$REPO_IP

  # images_containerd_K8SVER_CalicoVER
  K8S_CALICO_VER=images_containerd_1.26.6_3.25.1
  [ -d ${K8S_CALICO_VER} ] || mkdir ${K8S_CALICO_VER}
  cd ${K8S_CALICO_VER} || exit 1

  img_list='docker.io/calico/apiserver:v3.25.1
    docker.io/calico/cni:v3.25.1
    docker.io/calico/csi:v3.25.1
    docker.io/calico/kube-controllers:v3.25.1
    docker.io/calico/node-driver-registrar:v3.25.1
    docker.io/calico/node:v3.25.1
    docker.io/calico/pod2daemon-flexvol:v3.25.1
    docker.io/calico/typha:v3.25.1
    k8s.gcr.io/pause:3.6
    quay.io/tigera/operator:v1.29.3
    registry.k8s.io/coredns/coredns:v1.9.3
    registry.k8s.io/etcd:3.5.6-0
    registry.k8s.io/kube-apiserver:v1.26.6
    registry.k8s.io/kube-controller-manager:v1.26.6
    registry.k8s.io/kube-proxy:v1.26.6
    registry.k8s.io/kube-scheduler:v1.26.6
    registry.k8s.io/pause:3.9'

  REPO=http://${REPO_IP}:8080/calico_vpp/images/${K8S_CALICO_VER}
  for img in ${img_list}
  do
    img_file=${img//\//_}.tgz
    img_file=${img_file//:/_}
    need_download="false"
    if [[ ! -f "${img_file}" ]]; then
      need_download="true"
    elif [[ ${force} == "true" ]]; then
      rm -f "${img_file}"
      need_download="true"
    fi
    if [[ ${need_download} == "true" ]]; then
      info "Downloading ${img}..."
      wget "${REPO}/${img_file}"
    fi
    info "Importing ${img}..."
    sudo ctr -n=k8s.io image import "${img_file}"
  done

  info "Succeed."
}

##############################################################

# Parse input arguments
UNKNOWN_ARGS=""
while [[ "$1" != "" ]]
do
    arg=$1
    case $arg in
        -f)
            force="true"
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

import_images
