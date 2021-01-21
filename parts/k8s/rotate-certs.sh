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
  rm -rf /etc/kubernetes/certs.bak
}

"$@"
