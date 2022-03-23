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
./acr purge -r $acrName --filter ".*:.*" --ago 1m --keep 1 --dry-run
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

subnetstorageid=$(az network vnet subnet create -g $resourceGroupName --vnet-name $vnetName \
  --name $subnetStorage --address-prefixes 10.3.0.0/24 \
  --query id -o tsv)
echo $subnetstorageid

# Delegate a subnet to Azure NetApp Files
# https://docs.microsoft.com/en-us/azure/azure-netapp-files/azure-netapp-files-delegate-subnet
subnetnetappid=$(az network vnet subnet create -g $resourceGroupName --vnet-name $vnetName \
  --name $subnetNetApp --address-prefixes 10.4.0.0/28 \
  --delegations "Microsoft.NetApp/volumes" \
  --query id -o tsv)
echo $subnetnetappid

identityid=$(az identity create --name $identityName --resource-group $resourceGroupName --query id -o tsv)
echo $identityid

az aks get-versions -l $location -o table

# Note: for public cluster you need to authorize your ip to use api
myip=$(curl --no-progress-meter https://api.ipify.org)
echo $myip

# Note about private clusters:
# https://docs.microsoft.com/en-us/azure/aks/private-clusters

# For private cluster add these:
#  --enable-private-cluster
#  --private-dns-zone None

# Enable Ultra Disk:
# --enable-ultra-ssd

az aks create -g $resourceGroupName -n $aksName \
 --zones 1 --max-pods 50 --network-plugin azure \
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
 --enable-ultra-ssd \
 -o table 

###################################################################
# Enable current ip
az aks update -g $resourceGroupName -n $aksName --api-server-authorized-ip-ranges $myip

# Clear all authorized ip ranges
az aks update -g $resourceGroupName -n $aksName --api-server-authorized-ip-ranges ""
###################################################################

sudo az aks install-cli

az aks get-credentials -n $aksName -g $resourceGroupName --overwrite-existing

kubectl get nodes
kubectl get nodes -o wide
kubectl get nodes -o custom-columns=NAME:'{.metadata.name}',REGION:'{.metadata.labels.topology\.kubernetes\.io/region}',ZONE:'{metadata.labels.topology\.kubernetes\.io/zone}'
# NAME                                REGION       ZONE
# aks-nodepool1-30714164-vmss000000   westeurope   westeurope-1
# aks-nodepool1-30714164-vmss000001   westeurope   westeurope-2
# aks-nodepool1-30714164-vmss000002   westeurope   westeurope-3

# Create namespace
kubectl apply -f namespace.yaml

# Continue using "static provisioning" example
# => static/setup-static.sh

# Continue using "dynamic provisioning" example
# => dynamic/setup-dynamic.sh

kubectl apply -f demos

kubectl get deployment -n demos
kubectl describe deployment -n demos

kubectl get pod -n demos
kubectl get pod -n demos -o custom-columns=NAME:'{.metadata.name}',NODE:'{.spec.nodeName}'

kubectl get pod -n demos
pod1=$(kubectl get pod -n demos -o name | head -n 1)
echo $pod1

kubectl describe $pod1 -n demos

kubectl get service -n demos

ingressip=$(kubectl get service -n demos -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")
echo $ingressip

curl $ingressip/swagger/index.html
# -> OK!

cat <<EOF > payload.json
{
  "path": "/mnt/nfs",
  "filter": "*.*",
  "recursive": true
}
EOF

# Quick tests
# - Azure Files NFSv4.1
curl --no-progress-meter -X POST --data '{"path": "/mnt/nfs","filter": "*.*","recursive": true}' -H "Content-Type: application/json" "http://$ingressip/api/files" | jq .milliseconds
# - Azure Files SMB
curl --no-progress-meter -X POST --data '{"path": "/mnt/smb","filter": "*.*","recursive": true}' -H "Content-Type: application/json" "http://$ingressip/api/files" | jq .milliseconds
# - Azure NetApp Files NFSv4.1
curl --no-progress-meter -X POST --data '{"path": "/mnt/netapp-nfs","filter": "*.*","recursive": true}' -H "Content-Type: application/json" "http://$ingressip/api/files" | jq .milliseconds

# Test same in loop
# - Azure Files NFSv4.1
for i in {0..50}
do 
  curl --no-progress-meter -X POST --data '{"path": "/mnt/nfs","filter": "*.*","recursive": true}' -H "Content-Type: application/json" "http://$ingressip/api/files" | jq .milliseconds
done
# Examples: 1.8357, 2.918, 1.9534, 2.9706, 1.7649, 1.8872

# - Azure Files SMB
for i in {0..50}
do 
  curl --no-progress-meter -X POST --data '{"path": "/mnt/smb","filter": "*.*","recursive": true}' -H "Content-Type: application/json" "http://$ingressip/api/files" | jq .milliseconds
done
# Examples: 15.7838, 10.2626, 14.653, 11.2682, 9.8133, 15.9403, 11.6134

# - Azure NetApp Files NFSv4.1
for i in {0..50}
do 
  curl --no-progress-meter -X POST --data '{"path": "/mnt/netapp-nfs","filter": "*.*","recursive": true}' -H "Content-Type: application/json" "http://$ingressip/api/files" | jq .milliseconds
done
# Examples: 0.4258, 0.3901,0.407, 0.5709, 0.3992, 0.3968

# Use upload and download APIs to test client to server latency and transfer performance
# You can also use calculators e.g., https://www.calculator.net/bandwidth-calculator.html#download-time
truncate -s 10m demo1.bin
ls -lhF *.bin
time curl -T demo1.bin -X POST "http://$ingressip/api/upload"
time curl --no-progress-meter -X POST --data '{"size": 10485760}' -H "Content-Type: application/json" "http://$ingressip/api/download" -o demo2.bin
rm *.bin

# Connect to first pod
pod1=$(kubectl get pod -n demos -o name | head -n 1)
echo $pod1
kubectl exec --stdin --tty $pod1 -n demos -- /bin/sh

##############
# fio examples
##############
mount
fdisk -l
df -h
cat /proc/partitions

# If not installed, then install
apk add --no-cache fio

fio

cd /mnt
ls
cd /mnt/empty
cd /mnt/hostpath
cd /mnt/nfs
cd /mnt/smb
cd /mnt/premiumdisk
cd /mnt/ultradisk
cd /mnt/netapp-nfs
cd /home
mkdir perf-test

# Write test with 4 x 4MBs for 20 seconds
fio --directory=perf-test --direct=1 --rw=randwrite --bs=4k --ioengine=libaio --iodepth=256 --runtime=20 --numjobs=4 --time_based --group_reporting --size=4m --name=iops-test-job --eta-newline=1

# Read test with 4 x 4MBs for 20 seconds
fio --directory=perf-test --direct=1 --rw=randread --bs=4k --ioengine=libaio --iodepth=256 --runtime=20 --numjobs=4 --time_based --group_reporting --size=4m --name=iops-test-job --eta-newline=1 --readonly

# Find test files
ls perf-test/*.0

# Remove test files
rm perf-test/*.0

# Exit container shell
exit

################################
# To test
#  _____
# | ____|_ __ _ __ ___  _ __
# |  _| | '__| '__/ _ \| '__|
# | |___| |  | | | (_) | |
# |_____|_|  |_|  \___/|_|   s
# scenarios
################################

# Delete pod
# ----------
kubectl delete $pod1 -n demos

# Delete VM in VMSS
# -----------------
# Note: If you use Azure Disk from Zone-1, then
# killing node from matching zone will bring app down until
# AKS introduces new node to that zone.
nodeResourceGroup=$(az aks show -g $resourceGroupName -n $aksName --query nodeResourceGroup -o tsv)
vmss=$(az vmss list -g $nodeResourceGroup --query [0].name -o tsv)
az vmss list-instances -n $vmss -g $nodeResourceGroup -o table
vmssvm1=$(az vmss list-instances -n $vmss -g $nodeResourceGroup --query [0].instanceId -o tsv)
echo $vmssvm1
az vmss delete-instances --instance-ids $vmssvm1 -n $vmss -g $nodeResourceGroup

# Wipe out the resources
az group delete --name $resourceGroupName -y
