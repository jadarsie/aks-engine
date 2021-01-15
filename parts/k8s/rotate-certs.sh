#!/bin/bash -ex

export WD=/etc/kubernetes/rotate-certs
export NEW_CERTS_DIR=${WD}/certs
export STEPS_DIR=${WD}/steps
export SKIP_EXIT_CODE=25

mkdir -p ${STEPS_DIR}

# copied from cse_helpers.sh, sourcing that file not always works
systemctl_restart() {
  retries=$1; wait_sleep=$2; timeout=$3 svcname=$4
  for i in $(seq 1 $retries); do
    timeout $timeout systemctl daemon-reload
    timeout $timeout systemctl restart $svcname && break ||
      if [ $i -eq $retries ]; then
        return 1
      else
        sleep $wait_sleep
      fi
  done
}

backup() {
  [ -f ${STEPS_DIR}/${FUNCNAME[0]} ] && exit ${SKIP_EXIT_CODE}

  cp -rp /etc/kubernetes/certs/ /etc/kubernetes/certs.bak

  if [[ -f /etc/default/etcd ]]; then
    cp -p /etc/environment ${WD}
    cp -p /etc/default/etcd ${WD}
    cp -p /etc/kubernetes/manifests/kube-apiserver.yaml ${WD}
    cp -p /etc/kubernetes/manifests/kube-controller-manager.yaml ${WD}
    cat /etc/kubernetes/certs/ca.crt ${NEW_CERTS_DIR}/ca.crt > ${NEW_CERTS_DIR}/cabundle.crt
    chmod 644 ${NEW_CERTS_DIR}/cabundle.crt
  fi
  
  touch ${STEPS_DIR}/${FUNCNAME[0]}
}

sa_token_signer() {
  [ -f ${STEPS_DIR}/${FUNCNAME[0]} ] && exit ${SKIP_EXIT_CODE}

  cp -p ${NEW_CERTS_DIR}/cabundle.crt /etc/kubernetes/certs/
  cp -p ${NEW_CERTS_DIR}/apiserver.key /etc/kubernetes/certs/sa.key

  sed -i 's|"--service-account-key-file=/etc/kubernetes/certs/apiserver.key"|"--service-account-key-file=/etc/kubernetes/certs/sa.key"|g' /etc/kubernetes/manifests/kube-apiserver.yaml
  sed -i 's|"--root-ca-file=/etc/kubernetes/certs/ca.crt"|"--root-ca-file=/etc/kubernetes/certs/cabundle.crt"|g' /etc/kubernetes/manifests/kube-controller-manager.yaml
  sed -i 's|"--service-account-private-key-file=/etc/kubernetes/certs/apiserver.key"|"--service-account-private-key-file=/etc/kubernetes/certs/sa.key"|g' /etc/kubernetes/manifests/kube-controller-manager.yaml

  touch ${STEPS_DIR}/${FUNCNAME[0]}
}

cp_certs() {
  [ -f ${STEPS_DIR}/${FUNCNAME[0]} ] && exit ${SKIP_EXIT_CODE}

  cp -p ${NEW_CERTS_DIR}/etcdpeer* /etc/kubernetes/certs/
  cp -p ${NEW_CERTS_DIR}/etcdclient* /etc/kubernetes/certs/
  cp -p ${NEW_CERTS_DIR}/etcdserver* /etc/kubernetes/certs/
  cp -p ${NEW_CERTS_DIR}/ca.* /etc/kubernetes/certs/
  cp -p ${NEW_CERTS_DIR}/client.* /etc/kubernetes/certs/

  cp -p ${NEW_CERTS_DIR}/kubeconfig ~/.kube/config
  cp -p ${NEW_CERTS_DIR}/apiserver.* /etc/kubernetes/certs/
  cp -p ${WD}/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
  cp -p ${WD}/kube-controller-manager.yaml /etc/kubernetes/manifests/kube-controller-manager.yaml

  rm -f /var/lib/kubelet/pki/kubelet-client-current.pem

  touch ${STEPS_DIR}/${FUNCNAME[0]}
}

cp_proxy() {
  [ -f ${STEPS_DIR}/${FUNCNAME[0]} ] && exit ${SKIP_EXIT_CODE}

  source /etc/environment
  /etc/kubernetes/generate-proxy-certs.sh

  touch ${STEPS_DIR}/${FUNCNAME[0]}
}

kubelet_bootstrap() {
  [ -f ${STEPS_DIR}/${FUNCNAME[0]} ] && exit ${SKIP_EXIT_CODE}

  cp -p ${NEW_CERTS_DIR}/ca.* /etc/kubernetes/certs/
  cp -p ${NEW_CERTS_DIR}/client.* /etc/kubernetes/certs/

  rm -f /var/lib/kubelet/pki/kubelet-client-current.pem
  sleep 5
  systemctl_restart 10 5 10 kubelet

  touch ${STEPS_DIR}/${FUNCNAME[0]}
}

cleanup() {
  rm -rf ${WD}
  rm -f /etc/kubernetes/certs/sa.*
  rm -f /etc/kubernetes/certs/etcdca.*
  rm -f /etc/kubernetes/certs/cabundle.*
  rm -rf /etc/kubernetes/certs.bak
}

restart_mirror_pod_docker() {
  systemctl_restart 10 5 10 kubelet
  restart_pod_docker $1
}

restart_mirror_pod_containerd() {
  systemctl_restart 10 5 10 kubelet
  restart_pod_containerd $1
}

restart_pod_docker() {
  sudo docker stop $1
  sudo docker rm $1
}

restart_pod_containerd() {
  sudo ctr -n k8s.io t kill -s SIGKILL $1
  sleep 5
  sudo ctr -n k8s.io c delete $1
}

"$@"
