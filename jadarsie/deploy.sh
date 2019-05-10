#!/bin/bash -e

CLUSTER_DEFINITION=$1
DNS_PREFIX=$2

SPN_CLIENT_ID="f4900a0d-45b2-4cd6-960c-ee0a53d9033e"
SPN_CLIENT_SECRET="azurestack"
TENANT_SUBSCRIPTION_ID="5fcb4cb7-e97f-4388-a61d-736d7071742f"

# ./aks-engine-local.exe deploy \
# --location redmond \
# --api-model $CLUSTER_DEFINITION \
# --resource-group ${DNS_PREFIX}-rg \
# --output-directory $DNS_PREFIX \
# --client-id $SPN_CLIENT_ID \
# --client-secret $SPN_CLIENT_SECRET \
# --subscription-id $TENANT_SUBSCRIPTION_ID \
# --azure-env AzureStackCloud

./aks-engine-local.exe deploy \
--location redmond \
--api-model $CLUSTER_DEFINITION \
--resource-group ${DNS_PREFIX}-rg \
--output-directory $DNS_PREFIX \
--client-id $SPN_CLIENT_ID \
--client-secret $SPN_CLIENT_SECRET \
--subscription-id $TENANT_SUBSCRIPTION_ID \
--auth-method client_certificate \
--identity-system adfs \
--certificate-path "C:\Users\jadarsie\Downloads\selfhost\Kcluster\Kcluster-1905081720.crt" \
--private-key-path "C:\Users\jadarsie\Downloads\selfhost\Kcluster\Kcluster-1905081720.key" \
--azure-env AzureStackCloud

