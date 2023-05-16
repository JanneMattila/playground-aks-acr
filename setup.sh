# Enable auto export
set -a

# All the variables for the deployment
subscriptionName="development"
aadAdminGroupContains="janneops"

aksName="myaksacr"
acrName="myaksacr0000010"
workspaceName="myaksacr"
vnetName="myakacr-vnet"
subnetAks="AksSubnet"
subnetAcr="AcrSubnet"
identityName="myaksacr"
kubeletidentityName="myakskubeletacr"
identityName2="myaksacr2"
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
#region ACR demos

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

############################
# Import vulnerable images
# --
# More images:
# https://hub.docker.com/u/vulnerables
############################
az acr import -n $acrName -t "bad/dotnet/core/sdk:2.2.401" --source "mcr.microsoft.com/dotnet/core/sdk:2.2.401" 
az acr import -n $acrName -t "bad/vulnerables/web-dvwa" --source "docker.io/vulnerables/web-dvwa" 
az acr import -n $acrName -t "bad/vulnerables/metasploit-vulnerability-emulator" --source "docker.io/vulnerables/metasploit-vulnerability-emulator" 
az acr import -n $acrName -t "bad/vulnerables/cve-2017-7494" --source "docker.io/vulnerables/cve-2017-7494" 
az acr import -n $acrName -t "bad/vulnerables/mail-haraka-2.8.9-rce" --source "docker.io/vulnerables/mail-haraka-2.8.9-rce" 
############################
# /Import vulnerable images
############################

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

#endregion
##############################
#     __     _    ____ ____
#    / /    / \  / ___|  _ \
#   / /    / _ \| |   | |_) |
#  / /    / ___ \ |___|  _ <
# /_/    /_/   \_\____|_| \_\
##############################

##################################
#  _                   _
# | |     ___    __ _ (_) _ __
# | |    / _ \  / _` || || '_ \
# | |___| (_) || (_| || || | | |
# |_____|\___/  \__, ||_||_| |_|
#               |___/
# examples
##################################
#region Login

# Build simpleapp locally
docker build src/simpleapp/ -t localsimpleapp:latest

# Make sure, we don't have docker login session to our ACR
docker logout $acr_loginServer
docker logout azure

# Option 1: Automatic login
az acr login -n $acrName

# Option 2: Manual login
accessToken=$(az acr login -n $acrName --expose-token --query accessToken -o tsv)
docker login $acr_loginServer -u "00000000-0000-0000-0000-000000000000" -p "$accessToken"

# Option 3: Create scope map and token
az acr scope-map create --name developers --registry $acrName \
  --repository localapps/simpleapp \
  content/write content/read \
  --description "Developer access to localapps/simpleapp repository"
developerTokenJson=$(az acr token create --name developertoken1 --registry $acrName --scope-map developers -o json)
developerTokenPassword=$(echo $developerTokenJson | jq -r '.credentials.passwords[0].value')
echo $developerTokenPassword | docker login --username developertoken1 --password-stdin $acr_loginServer

# Push locally build image to ACR
docker tag localsimpleapp:latest "$acr_loginServer/localapps/simpleapp:latest"
docker push "$acr_loginServer/localapps/simpleapp:latest"

#endregion
#########################
#   ____ ___ ____ ____
#  / ___|_ _/ ___|  _ \
# | |    | | |   | | | |
# | |___ | | |___| |_| |
#  \____|___\____|____/
# CI/CD vulnerability scanning
#########################

# https://github.com/JanneMattila/github-actions-demos/blob/main/.github/workflows/defender.yml
# Example output:
# https://github.com/JanneMattila/github-actions-demos/runs/5738915725?check_suite_focus=true

# Scanning for vulnerabilties in image: vulnerables/cve-2017-7494
# ╔══════════════════════╤═════════════════╤═════════════════╤════════════════════════════════════════════════════╤══════════════════════╗
# ║ VULNERABILITY ID     │ PACKAGE NAME    │ SEVERITY        │ DESCRIPTION                                        │ TARGET               ║
# ╟──────────────────────┼─────────────────┼─────────────────┼────────────────────────────────────────────────────┼──────────────────────╢
# ║ CVE-2019-3462        │ apt             │ HIGH            │ Incorrect sanitation of the 302 redirect field in  │ vulnerables/cve-     ║
# ║                      │                 │                 │ HTTP transport method of apt versions 1.4.8 and    │ 2017-7494 (debian    ║
# ║                      │                 │                 │ earlier can lead to content injection by a MITM    │ 8.9)                 ║
# ║                      │                 │                 │ attacker, potentially leading to remote code       │                      ║
# ║                      │                 │                 │ execution on the target machine.                   │                      ║
# ╟──────────────────────┼─────────────────┼─────────────────┼────────────────────────────────────────────────────┼──────────────────────╢
# ║ CVE-2019-9924        │ bash            │ HIGH            │ rbash in Bash before 4.4-beta2 did not prevent the │ vulnerables/cve-     ║
# ║                      │                 │                 │ shell user from modifying BASH_CMDS, thus allowing │ 2017-7494 (debian    ║
# ║                      │                 │                 │ the user to execute any command with the           │ 8.9)                 ║
# ║                      │                 │                 │ permissions of the shell.                          │                      ║
# ╟──────────────────────┼─────────────────┼─────────────────┼────────────────────────────────────────────────────┼──────────────────────╢
# ...

#################################
#     __   ____ ___ ____ ____
#    / /  / ___|_ _/ ___|  _ \
#   / /  | |    | | |   | | | |
#  / /   | |___ | | |___| |_| |
# /_/     \____|___\____|____/
################################

aadAdmingGroup=$(az ad group list --display-name $aadAdminGroupContains --query [].id -o tsv)
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

kubeletidentityid=$(az identity create --name $kubeletidentityName --resource-group $resourceGroupName --query id -o tsv)
echo $kubeletidentityid

# This is another Managed Identity
identityid2=$(az identity create --name $identityName2 --resource-group $resourceGroupName --query id -o tsv)
identityappid2=$(az identity show --name $identityName2 --resource-group $resourceGroupName --query principalId -o tsv)
echo $identityid2
echo $identityappid2

# Grant permissions to pull images from ACR:
az role assignment create \
  --role "AcrPull" \
  --assignee-object-id $identityappid2 \
  --assignee-principal-type ServicePrincipal \
  --scope $acr_id

az aks get-versions -l $location -o table

# Note: for public cluster you need to authorize your ip to use api
myip=$(curl --no-progress-meter https://api.ipify.org)
echo $myip

az aks create -g $resourceGroupName -n $aksName \
 --max-pods 50 --network-plugin azure \
 --node-count 1 --enable-cluster-autoscaler --min-count 1 --max-count 2 \
 --node-osdisk-type Ephemeral \
 --node-vm-size Standard_D32ds_v4 \
 --kubernetes-version 1.23.5 \
 --enable-addons monitoring,azure-policy,azure-keyvault-secrets-provider \
 --enable-aad \
 --enable-managed-identity \
 --disable-local-accounts \
 --aad-admin-group-object-ids $aadAdmingGroup \
 --workspace-resource-id $workspaceid \
 --load-balancer-sku standard \
 --vnet-subnet-id $subnetaksid \
 --assign-identity $identityid \
 --assign-kubelet-identity $kubeletidentityid \
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
