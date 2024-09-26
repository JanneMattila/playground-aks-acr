# Playground ACR (with AKS)

This repository contains Azure Container Registry (ACR) related examples.

## Usage

1. Clone this repository to your own machine
2. Open Workspace
  - Use WSL in Windows
  - Requires Bash
3. Open [setup.sh](./setup.sh) to walk through steps to deploy this demo environment
  - Execute different script steps one-by-one (hint: use [shift-enter](https://github.com/JanneMattila/some-questions-and-some-answers/blob/master/q%26a/vs_code.md#automation-tip-shift-enter))

## ACR Purge examples

Follow [setup.sh](./setup.sh) for more detailed instructions but here are few example commands:

```bash
accessToken=$(az acr login -n $acrName --expose-token --query accessToken -o tsv)

# Using local ACR CLI
./acr login $acr_loginServer -u "00000000-0000-0000-0000-000000000000" -p "$accessToken"
./acr purge -r $acrName --filter "apps/simpleapp:.*" --ago 1m --keep 1 --dry-run
./acr purge -r $acrName --filter "apps/simpleapp:.*" --ago 1d
```

See more examples in [ACR CLI](https://github.com/Azure/acr-cli#purge-command) repository.

## Links

[Push and pull Helm charts to an Azure container registry](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-helm-repos)

[Content formats supported in Azure Container Registry](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-image-formats)

[Automate container image builds and maintenance with ACR Tasks](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-tasks-overview)

[Automatically purge images from an Azure container registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-auto-purge)

[Set a retention policy for untagged manifests](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-retention-policy)

[Tutorial: Run an ACR task on a defined schedule](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-tasks-scheduled)
