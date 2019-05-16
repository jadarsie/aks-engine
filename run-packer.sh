#!/bin/bash -eux

docker run --rm \
-v ${PWD}:/go/src/github.com/Azure/aks-engine \
-w /go/src/github.com/Azure/aks-engine \
-e CLIENT_ID="34f4590b-6a97-410b-8da7-ba408e8c91be" \
-e CLIENT_SECRET="59ktM7xhRV4pqSC9SthmpcYIWjJwZ/3f" \
-e TENANT_ID="23a3ce67-a681-474c-900c-215f9304d49e" \
-e AZURE_VM_SIZE="Standard_D2_v2" \
-e AZURE_RESOURCE_GROUP_NAME="jadarsiepacker" \
-e AZURE_LOCATION="westus2" \
-e FEATURE_FLAGS="" \
-e GIT_VERSION="123" \
-e BUILD_ID="234" \
-e BUILD_NUMBER="345" \
-e UBUNTU_SKU="16.04" \
quay.io/deis/go-dev:v1.21.0 make run-packer