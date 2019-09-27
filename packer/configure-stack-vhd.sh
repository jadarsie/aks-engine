#!/bin/bash
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

source /home/packer/notice_source.sh

VHD_LOGS_FILEPATH=/opt/azure/stack-install.complete

echo "Starting build on " $(date) > ${VHD_LOGS_FILEPATH}
echo "Using kernel:" >> ${VHD_LOGS_FILEPATH}
tee -a ${VHD_LOGS_FILEPATH} < /proc/version

cleanUpContainerImages
installTern
generateNotice
cleanTern

df -h

# warn at 75% space taken
[ -s $(df -P | grep '/dev/sda1' | awk '0+$5 >= 75 {print}') ] || echo "WARNING: 75% of /dev/sda1 is used" >> ${VHD_LOGS_FILEPATH}
# error at 90% space taken
[ -s $(df -P | grep '/dev/sda1' | awk '0+$5 >= 90 {print}') ] || exit 1

{
  echo "Install completed successfully on " $(date)
  echo "VSTS Build NUMBER: ${BUILD_NUMBER}"
  echo "VSTS Build ID: ${BUILD_ID}"
  echo "Commit: ${COMMIT}"
} >> ${VHD_LOGS_FILEPATH}

# The below statements are used to extract release notes from the packer output
set +x
echo "START_OF_NOTES"
cat ${VHD_LOGS_FILEPATH}
echo "END_OF_NOTES"
set -x
