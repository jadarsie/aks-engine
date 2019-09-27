#!/bin/bash
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

set -eo pipefail

TERNDIR=/home/packer/tern
TERNOUT=/home/packer/tern_output
TERNVER='v0.4.0'

cleanUpContainerImages() {
    # remove azure images, my pipeline times out otherwise
    docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'k8s.gcr.io/hyperkube-amd64:v') &
    docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'k8s.gcr.io/cloud-controller-manager-amd64:v') &
    docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'k8s.gcr.io/cluster-autoscaler:v') &
    docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'nvidia/k8s-device-plugin:') &
    docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'flexvolume') &
    docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'virtual-kubelet') &
    docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'busybox') &

    # clean up AKS container images
    docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'hcp-tunnel-front') &
    docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'kube-svc-redirect') &
    docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'nginx') &
}

installTern() {
    mkdir -p ${TERNOUT}
    git clone -b ${TERNVER} --single-branch --depth 1 https://github.com/vmware/tern.git ${TERNDIR}
    docker build -t ternd ${TERNDIR}/
}

generateNotice() {
    for line in $(docker images --format '{{.Repository}}:{{.Tag}}|{{.Digest}}' | grep -v ternd:latest | grep -v photon);
    do
        cimg=$(echo ${line} | cut -d '|' -f 1)
        sha=$(echo ${line} |cut -d '|' -f 2)

        json=${TERNOUT}/${sha}.json
        text=${TERNOUT}/${sha}.txt

        ${TERNDIR}/docker_run.sh workdir ternd "report -j -i ${cimg}" > ${json}

        jq -r '.images[].image.layers[].packages[] | select(length > 0) | select(.pkg_license != "" or .copyright != "") | ("---"),("Component: "+(.name)),("Version: "+(.version)),("Open Source License/Copyright Notice: "+(.pkg_license)),(.copyright)' *.json > ${text}
    done

    # concat all the things
    cat /opt/azure/notice-header.txt ${TERNOUT}/*.txt > /opt/azure/notice.txt
    chmod 644 /opt/azure/notice.txt
}

cleanTern() {
    docker stop $(docker ps -aq)
    docker rm $(docker ps -aq)
    docker rmi ternd:latest
    docker rmi photon:3.0
}