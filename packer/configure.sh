#!/bin/bash
source /home/packer/provision_installs.sh
source /home/packer/provision_source.sh
source /home/packer/packer_source.sh

VHD_LOGS_FILEPATH=/opt/azure/vhd-install.complete

echo "Starting build on " $(date) > ${VHD_LOGS_FILEPATH}
echo "Using kernel:" >> ${VHD_LOGS_FILEPATH}
tee -a ${VHD_LOGS_FILEPATH} < /proc/version

installDeps

if ! retrycmd_if_failure 120 5 25 systemctl enable xrdp; then
    echo "xrdp could not be enabled by systemctl"
    return 1
fi
echo xfce4-session >~/.xsession

MOBY_VERSION="3.0.6"
installMoby


{
  echo "Install completed successfully on " $(date)
  echo "VSTS Build NUMBER: ${BUILD_NUMBER}"
  echo "VSTS Build ID: ${BUILD_ID}"
  echo "Commit: ${COMMIT}"
} >> ${VHD_LOGS_FILEPATH}

set +x
echo "START_OF_NOTES"
cat ${VHD_LOGS_FILEPATH}
echo "END_OF_NOTES"
set -x
