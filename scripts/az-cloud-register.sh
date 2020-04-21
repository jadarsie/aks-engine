#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

# Setup test container so it works on Azure Stack CI environments
if [ ! -f /aks-engine/azsRootCACert.pem ]; then
    exit
fi

# azure-cli requirement if selfsigned root ca
cat /aks-engine/azsRootCACert.pem >> /usr/local/lib/python2.7/dist-packages/certifi/cacert.pem

# custom cloud variables
METADATA=$(mktemp)

export RESOURCE_MANAGER_ENDPOINT="https://management.${LOCATION}.${CUSTOM_CLOUD_FQDN}"
curl -sk -o ${METADATA} "${RESOURCE_MANAGER_ENDPOINT}/metadata/endpoints?api-version=2015-01-01"

export PORTAL_ENDPOINT="https://portal.${LOCATION}.${CUSTOM_CLOUD_FQDN}"
export SERVICE_MANAGEMENT_ENDPOINT="$(jq -r '.authentication.audiences | .[0]' "$METADATA")"
export ACTIVE_DIRECTORY_ENDPOINT="$(jq -r .authentication.loginEndpoint "$METADATA" | sed -e 's/adfs\/*$//')"
export GALLERY_ENDPOINT="$(jq -r .galleryEndpoint "$METADATA")"
export GRAPH_ENDPOINT="$(jq -r .graphEndpoint "$METADATA")"

export KEY_VAULT_DNS_SUFFIX=".vault.${LOCATION}.${CUSTOM_CLOUD_FQDN}"
export STORAGE_ENDPOINT_SUFFIX="${LOCATION}.${CUSTOM_CLOUD_FQDN}"
export RESOURCE_MANAGER_VM_DNS_SUFFIX="cloudapp.${CUSTOM_CLOUD_FQDN}"
export SERVICE_MANAGEMENT_VM_DNS_SUFFIX="cloudapp.net"

# azure-cli register custom cloud
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-AzureStackCloud}"

if az cloud list | jq '.[].name' | grep $ENVIRONMENT_NAME; then
    exit
fi

az cloud register \
    -n $ENVIRONMENT_NAME \
    --endpoint-resource-manager $RESOURCE_MANAGER_ENDPOINT \
    --endpoint-vm-image-alias-doc "https://raw.githubusercontent.com/Azure/azure-rest-api-specs/master/arm-compute/quickstart-templates/aliases.json" \
    --suffix-storage-endpoint $STORAGE_ENDPOINT_SUFFIX \
    --suffix-keyvault-dns $KEY_VAULT_DNS_SUFFIX

az cloud set -n $ENVIRONMENT_NAME
az cloud update --profile $API_PROFILE
