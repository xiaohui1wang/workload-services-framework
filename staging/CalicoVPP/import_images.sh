#!/bin/bash

if [[ ! -x "$(command -v ctr)" ]]; then
  echo "containerd is not installed."
  exit 1
fi

export no_proxy=$no_proxy,10.166.32.86

# images_containerd_K8SVER_CalicoVER
K8S_CALICO_VER=images_containerd_1.26.6_3.25.1
[ -d ${K8S_CALICO_VER} ] || mkdir ${K8S_CALICO_VER}
cd ${K8S_CALICO_VER}

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

REPO=http://10.166.32.86:8080/calico_vpp/images/${K8S_CALICO_VER}
for img in ${img_list}
do
  img_file=${img//\//_}.tgz
  img_file=${img_file//:/_}
  [ -f ${img_file} ] && rm -f  ${img_file}
  echo "Downloading ${img}..."
  wget ${REPO}/${img_file}
  echo "Importing ${img}..."
  sudo ctr -n=k8s.io image import ${img_file}
done

echo "Succeed."

