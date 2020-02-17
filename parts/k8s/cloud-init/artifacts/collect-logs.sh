#!/bin/bash

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

copyDaemonLogs() {
    local DIR=${OUTDIR}/${1}
    mkdir -p ${DIR}
    sudo cp /etc/kubernetes/manifests/* ${OUTDIR}/etc/kubernetes/manifests
}

compressLogsDirectory() {
    sync
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Compressing logs and cleaning up temp files"
    CURRENTUSER=$(whoami)
    LOGFILENAME="${HOSTNAME}.zip"
    sudo rm -f ${LOGFILENAME}
    
    sudo chown -R ${CURRENTUSER} ${OUTDIR}
    # TODO This wont work on a disconnected scenario
    (cd $TMP && zip -q -r ~/${LOGFILENAME} ${HOSTNAME})
    sudo chown ${CURRENTUSER} ~/${LOGFILENAME}
}

TMP=$(mktemp -d)
OUTDIR=${TMP}/${HOSTNAME}

collectDirLogs /var/log
collectDirLogs /var/log/azure
collectDir /etc/kubernetes/manifests
collectDir /etc/kubernetes/addons


mkdir -p ${OUTDIR}/daemons

if systemctl list-units | grep -q kubelet.service; then
    sudo journalctl -n 10000 --utc -o short-iso -u kubelet &>> ${OUTDIR}/daemons/k8s-kubelet.log
fi

if systemctl list-units | grep -q etcd.service; then
    sudo journalctl -n 10000 --utc -o short-iso -u etcd &>> ${OUTDIR}/daemons/k8s-etcd.log
fi

if systemctl list-units | grep -q docker.service; then
    sudo journalctl -n 10000 --utc -o short-iso -u docker &>> ${OUTDIR}/daemons/k8s-docker.log
fi

compressLogsDirectory
