#!/bin/bash -x

clusterInfo() {
    kubectl cluster-info dump --namespace=kube-system --output-directory=${OUTDIR}/cluster-info
}

collectCloudProviderJson() {
    local DIR=${OUTDIR}/etc/kubernetes
    mkdir -p ${DIR}
    # remove creds
    sudo grep -v aadClient /etc/kubernetes/azure.json > ${DIR}/azure.json
    if [ -f /etc/kubernetes/azurestackcloud.json ]; then
        sudo jq . /etc/kubernetes/azurestackcloud.json > ${DIR}/azurestackcloud.json
    fi
}

collectDirLogs() {
    local DIR=${OUTDIR}/${1}
    mkdir -p ${DIR}
    sudo cp ${1}/*.log ${DIR}
}

collectDir() {
    local DIR=${OUTDIR}/${1}
    mkdir -p ${DIR}
    sudo cp ${1}/* ${DIR}
}

collectDaemonLogs() {
    local DIR=${OUTDIR}/daemons
    mkdir -p ${DIR}
    if systemctl list-units | grep -q ${1}; then
        sudo journalctl -n 10000 --utc -o short-iso -u ${1} &>> ${DIR}/${1}.log
    fi
}

compressLogsDirectory() {
    sync
    ZIP="${HOSTNAME}.zip"
    sudo rm -f ${ZIP}
    sudo chown -R ${USER}:${USER} ${OUTDIR}
    (cd $TMP && zip -q -r ~/${ZIP} ${HOSTNAME})
    sudo chown ${USER}:${USER} ~/${ZIP}
}

# AZURE STACK STUFF
stackfy() {
    RESOURCE_GROUP=$(sudo jq -r '.resourceGroup' /etc/kubernetes/azure.json)
    SUB_ID=$(sudo jq -r '.subscriptionId' /etc/kubernetes/azure.json)
    TENANT_ID=$(sudo jq -r '.tenantId' /etc/kubernetes/azure.json)
    if [ "${TENANT_ID}" == "adfs" ]; then
        TENANT_ID=$(sudo jq -r '.serviceManagementEndpoint' /etc/kubernetes/azurestackcloud.json | cut -d / -f4)
    fi

    stackfyKubeletLog
    stackfyMobyLog
    stackfyEtcdLog
    stackfyControllerManagerLogs
}

stackfyKubeletLog() {
    KUBELET_REPOSITORY=$(docker images --format '{{.Repository}}' | grep hyperkube)
    KUBELET_TAG=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep hyperkube | cut -d ":" -f 2)
    KUBELET_VERBOSITY=$(cat /etc/systemd/system/kubelet.service | grep -e '--v=[0-9]' -oh | grep -e [0-9] -oh | head -n 1)
    KUBELET_LOG_FILE=${OUTDIR}/daemons/k8s-kubelet.log
    
    echo "== BEGIN HEADER =="               >  ${KUBELET_LOG_FILE}
    echo "Type: Daemon"                     >> ${KUBELET_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${KUBELET_LOG_FILE}
    echo "Name: kubelet"                    >> ${KUBELET_LOG_FILE}
    echo "Version: ${KUBELET_TAG}"          >> ${KUBELET_LOG_FILE}
    echo "Verbosity: ${KUBELET_VERBOSITY}"  >> ${KUBELET_LOG_FILE}
    echo "Image: ${KUBELET_REPOSITORY}"     >> ${KUBELET_LOG_FILE}
    echo "Hostname: ${HOSTNAME}"            >> ${KUBELET_LOG_FILE}
    echo "SubscriptionID: ${SUB_ID}"        >> ${KUBELET_LOG_FILE}
    echo "ResourceGroup: ${RESOURCE_GROUP}" >> ${KUBELET_LOG_FILE}
    echo "== END HEADER =="                 >> ${KUBELET_LOG_FILE}

    cat ${OUTDIR}/daemons/kubelet.service.log >> ${KUBELET_LOG_FILE}
    rm ${OUTDIR}/daemons/kubelet.service.log
}

stackfyMobyLog() {
    DOCKER_VERSION=$(docker version | grep -A 20 "Server:" | grep "Version:" | head -n 1 | cut -d ":" -f 2 | xargs)
    DOCKER_LOG_FILE=${OUTDIR}/daemons/k8s-docker.log
    
    echo "== BEGIN HEADER =="               >  ${DOCKER_LOG_FILE}
    echo "Type: Daemon"                     >> ${DOCKER_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${DOCKER_LOG_FILE}
    echo "Name: docker"                     >> ${DOCKER_LOG_FILE}
    echo "Version: ${DOCKER_VERSION}"       >> ${DOCKER_LOG_FILE}
    echo "Hostname: ${HOSTNAME}"            >> ${DOCKER_LOG_FILE}
    echo "SubscriptionID: ${SUB_ID}"        >> ${DOCKER_LOG_FILE}
    echo "ResourceGroup: ${RESOURCE_GROUP}" >> ${DOCKER_LOG_FILE}
    echo "== END HEADER =="                 >> ${DOCKER_LOG_FILE}

    cat ${OUTDIR}/daemons/docker.service.log >> ${DOCKER_LOG_FILE}
    rm ${OUTDIR}/daemons/docker.service.log
}

stackfyEtcdLog() {
    ETCD_VERSION=$(/usr/bin/etcd --version | grep "etcd Version:" | cut -d ":" -f 2 | xargs)
    ETCD_LOG_FILE=${OUTDIR}/daemons/k8s-etcd.log
    
    echo "== BEGIN HEADER =="               >  ${ETCD_LOG_FILE}
    echo "Type: Daemon"                     >> ${ETCD_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${ETCD_LOG_FILE}
    echo "Name: etcd"                       >> ${ETCD_LOG_FILE}
    echo "Version: ${ETCD_VERSION}"         >> ${ETCD_LOG_FILE}
    echo "Hostname: ${HOSTNAME}"            >> ${ETCD_LOG_FILE}
    echo "SubscriptionID: ${SUB_ID}"        >> ${ETCD_LOG_FILE}
    echo "ResourceGroup: ${RESOURCE_GROUP}" >> ${ETCD_LOG_FILE}
    echo "== END HEADER =="                 >> ${ETCD_LOG_FILE}

    cat ${OUTDIR}/daemons/etcd.service.log >> ${ETCD_LOG_FILE}
    rm ${OUTDIR}/daemons/etcd.service.log
}

stackfyControllerManagerLogs() {
    mkdir -p ${OUTDIR}/containers
    for SRC in ${OUTDIR}/cluster-info/kube-system/kube-controller-manager-*/logs.txt; do
        KCM_VERBOSITY=$(cat /etc/kubernetes/manifests/kube-controller-manager.yaml | grep -e "--v=[0-9]" -oh | grep -e [0-9] -oh | head -n 1)
        KCM_IMAGE=$(grep image: /etc/kubernetes/manifests/kube-controller-manager.yaml | xargs | cut -f 2 -d " ")
        KCM_DIR=$(dirname $SRC)
        KCM_NAME=$(basename $KCM_DIR)
        KCM_LOG_FILE=${OUTDIR}/containers/k8s-${KCM_NAME}.log
        
        echo "== BEGIN HEADER =="               >  ${KCM_LOG_FILE}
        echo "Type: Container"                  >> ${KCM_LOG_FILE}
        echo "TenantId: ${TENANT_ID}"           >> ${KCM_LOG_FILE}
        echo "Name: ${KCM_NAME}"                >> ${KCM_LOG_FILE}
        echo "Hostname: ${HOSTNAME}"            >> ${KCM_LOG_FILE}
        echo "ContainerID: "                    >> ${KCM_LOG_FILE}
        echo "Image: ${KCM_IMAGE}"              >> ${KCM_LOG_FILE}
        echo "Verbosity: ${KCM_VERBOSITY}"      >> ${KCM_LOG_FILE}
        echo "SubscriptionID: ${SUB_ID}"        >> ${KCM_LOG_FILE}
        echo "ResourceGroup: ${RESOURCE_GROUP}" >> ${KCM_LOG_FILE}
        echo "== END HEADER =="                 >> ${KCM_LOG_FILE}

        cat ${SRC} >> ${KCM_LOG_FILE}
    done
}

if [ -f /etc/kubernetes/azurestackcloud.json ]; then
    stackfy
fi

TMP=$(mktemp -d)
OUTDIR=${TMP}/${HOSTNAME}

clusterInfo
collectDirLogs /var/log
collectDirLogs /var/log/azure
collectDir /etc/kubernetes/manifests
collectDir /etc/kubernetes/addons
collectDaemonLogs kubelet.service
collectDaemonLogs etcd.service
collectDaemonLogs docker.service

if [ -f /etc/kubernetes/azurestackcloud.json ]; then
    stackfy
fi

compressLogsDirectory
