# Deployment Guide

Back to the [README](../README.md). For automated deployments see [CI/CD](./cicd.md); after deploying see [Post-deployment & testing](./post-deployment.md).

## Prerequisites
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (v2.60+ recommended)
- Bicep CLI (`az bicep install`)
- An active Azure subscription
- Node.js 22 and npm (for the one-command deploy script)

## Option A: One-command local deploy

`scripts/deploy.sh` mirrors the pipeline (build, what-if, infra, API, ingest, frontend):

```bash
scripts/deploy.sh -g rg-swapp-dev -l eastus2 -w swapp -e dev -i 203.0.113.10/32,198.51.100.0/24
scripts/deploy.sh -g rg-swapp-dev --what-if      # preview only
scripts/deploy.sh -g rg-swapp-dev --skip-infra   # code only
```

Omitted parameters fall back to `infra/main.bicepparam`. Run `scripts/deploy.sh --help` for all options. The ingest deploy temporarily allows your public IP on the ingest app and removes it afterwards.

## Option B: Manual steps

### Step 1: Login and set subscription
```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

### Step 2: Create a resource group
```bash
az group create --name "rg-swapp-prod" --location "eastus2"
```

### Step 3: Configure deployment parameters
Edit [infra/main.bicepparam](../infra/main.bicepparam) to specify:
- `allowedCallerIps`: One or more external IPs or CIDR ranges authorized to call the ingest Function App (e.g. `['198.51.100.45/32', '203.0.113.0/28']`). At least one is required.
- `workloadName` / `environmentName`: Resource names are deterministic: `<type>-<workload>-<env>` (e.g. `func-swapp-dev`, `vnet-swapp-dev`), and storage accounts are `stfn<workload><env>` / `stlog<workload><env>` (hyphens removed, max 24 chars). The Function App and Storage Accounts must be globally unique, so `workloadName` is limited to 3-10 characters.
- `retentionDays`: Records older than this are deleted by the daily cleanup (default 30).
- `location`: Azure region (e.g. `eastus2`).

### Step 4: Validate and deploy
```bash
az deployment group what-if \
  --resource-group "rg-swapp-prod" \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam

az deployment group create \
  --resource-group "rg-swapp-prod" \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

### Step 5: Deploy the Function App code
Use Azure Functions Core Tools (the same steps apply to `src/ingest` and the ingest app name). The ingest app only admits `allowedCallerIps`, including its SCM site, so temporarily allow your IP first (see [Security](./security.md)).
```bash
cd src/api
npm install --omit=dev
func azure functionapp publish "<FUNCTION_APP_NAME>" --javascript
```

### Step 6: Deploy the frontend
Run from the repository root (outside `src/frontend`) so the working directory does not overlap with the artifact folder:
```bash
swa deploy ./src/frontend \
  --app-name "<STATIC_WEB_APP_NAME>" \
  --env production
```
