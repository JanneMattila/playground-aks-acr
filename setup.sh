#!/bin/bash

# All the variables for the deployment
subscriptionName="AzureDev"
aadAdminGroupContains="janne''s"

aksName="myaksacr"
acrName="myaksacr0000010"
workspaceName="myaksacr"
vnetName="myakacr-vnet"
subnetAks="AksSubnet"
subnetAcr="AcrSubnet"
identityName="myaksacr"
resourceGroupName="rg-myaksacr"
location="westeurope"

# Login and set correct context
az login -o table
az account set --subscription $subscriptionName -o table

# Prepare extensions and providers
az extension add --upgrade --yes --name aks-preview

# Enable feature
az feature register --namespace "Microsoft.ContainerService" --name "PodSubnetPreview"
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/PodSubnetPreview')].{Name:name,State:properties.state}"
az provider register --namespace Microsoft.ContainerService

# Remove extension in case conflicting previews
az extension remove --name aks-preview

az group create -l $location -n $resourceGroupName -o table

acr_json=$(az acr create -l $location -g $resourceGroupName -n $acrName --sku Basic -o json)
echo $acr_json
acr_loginServer=$(echo $acr_json | jq -r .loginServer)
acr_id=$(echo $acr_json | jq -r .id)
echo $acr_loginServer
echo $acr_id

#######################
#     _    ____ ____
#    / \  / ___|  _ \
#   / _ \| |   | |_) |
#  / ___ \ |___|  _ <
# /_/   \_\____|_| \_\
# demos
#######################

show_image_size () {
  local size_in_bytes=$(az acr manifest metadata list -n "$1" -r $acrName --query '[].{Size: imageSize, Tags: tags}' | jq ".[0].Size")
  numfmt --to iec --format "%8.4f" $size_in_bytes
}

show_image_tags () {
  local tags=$(az acr repository show-tags --repository "$1" -n $acrName -o tsv)
  for tag in $tags
  do
    echo "$repo:$tag"
  done
}

az acr build --registry $acrName --image "apps/simpleapp:$(date +%s)" ./src/simpleapp
az acr build --registry $acrName --image "apps/simpleapp:{{.Run.ID}}" ./src/simpleapp
show_image_size "apps/simpleapp"
show_image_tags "apps/simpleapp"

# Look usage for all the images
repositories=$(az acr repository list -n $acrName -o tsv)
echo $repositories

for repo in $repositories
do
  echo "Repository: $repo"
  show_image_size $repo
done

# Import images
az acr import -n $acrName -t "base/alpine:3.15.1" --source "docker.io/library/alpine:3.15.1" 

# Ad-hoc purge
# See more examples: https://github.com/Azure/acr-cli#purge-command
for repo in $repositories
do
  show_image_tags $repo
done

# Download ACR CLI from GitHub Releases
download=$(curl -sL https://api.github.com/repos/Azure/acr-cli/releases/36955810 | jq -r '.assets[].browser_download_url' | grep Linux_x86_64)
wget $download -O acr.zip
tar -xf acr.zip 
file acr.zip
mv acr-cli acr
./acr --help

accessToken=$(az acr login -n $acrName --expose-token --query accessToken -o tsv)
echo $accessToken
./acr login $acr_loginServer -u "00000000-0000-0000-0000-000000000000" -p "$accessToken"

show_image_tags "apps/simpleapp"
./acr purge -r $acrName --filter "apps/simpleapp:.*" --ago 1m --keep 1 --dry-run
./acr purge -r $acrName --filter "apps/simpleapp:.*" --ago 1d

# Use ACR run command
purge_command="acr purge --registry $acrName --filter 'apps/simpleapp:.*' --ago 10m --keep 1"
purge_command="acr purge --registry $acrName --filter 'apps/simpleapp:.*' --ago 10m --keep 1 --dry-run"
echo $purge_command
az acr run --cmd "$purge_command" --registry $acrName /dev/null

##############################
#     __     _    ____ ____
#    / /    / \  / ___|  _ \
#   / /    / _ \| |   | |_) |
#  / /    / ___ \ |___|  _ <
# /_/    /_/   \_\____|_| \_\
##############################

aadAdmingGroup=$(az ad group list --display-name $aadAdminGroupContains --query [].objectId -o tsv)
echo $aadAdmingGroup

workspaceid=$(az monitor log-analytics workspace create -g $resourceGroupName -n $workspaceName --query id -o tsv)
echo $workspaceid

vnetid=$(az network vnet create -g $resourceGroupName --name $vnetName \
  --address-prefix 10.0.0.0/8 \
  --query newVNet.id -o tsv)
echo $vnetid

subnetaksid=$(az network vnet subnet create -g $resourceGroupName --vnet-name $vnetName \
  --name $subnetAks --address-prefixes 10.2.0.0/24 \
  --query id -o tsv)
echo $subnetaksid

identityid=$(az identity create --name $identityName --resource-group $resourceGroupName --query id -o tsv)
echo $identityid

az aks get-versions -l $location -o table

# Note: for public cluster you need to authorize your ip to use api
myip=$(curl --no-progress-meter https://api.ipify.org)
echo $myip

az aks create -g $resourceGroupName -n $aksName \
 --max-pods 50 --network-plugin azure \
 --node-count 1 --enable-cluster-autoscaler --min-count 1 --max-count 2 \
 --node-osdisk-type Ephemeral \
 --node-vm-size Standard_D32ds_v4 \
 --kubernetes-version 1.22.6 \
 --enable-addons monitoring,azure-policy,azure-keyvault-secrets-provider \
 --enable-aad \
 --enable-managed-identity \
 --disable-local-accounts \
 --aad-admin-group-object-ids $aadAdmingGroup \
 --workspace-resource-id $workspaceid \
 --load-balancer-sku standard \
 --vnet-subnet-id $subnetaksid \
 --assign-identity $identityid \
 --api-server-authorized-ip-ranges $myip \
 -o table 

sudo az aks install-cli

az aks get-credentials -n $aksName -g $resourceGroupName --overwrite-existing

kubectl get nodes
kubectl get nodes -o wide

# Create namespace
kubectl apply -f demos/namespace.yaml
kubectl apply -f demos/deployment.yaml

kubectl get deployment -n demos
kubectl describe deployment -n demos

kubectl get pod -n demos

# Wipe out the resources
az group delete --name $resourceGroupName -y
