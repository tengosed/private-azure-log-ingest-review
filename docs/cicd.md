# CI/CD with Azure DevOps

Back to the [README](../README.md).

[azure-pipelines.yml](../azure-pipelines.yml) builds and deploys everything:

| Stage | Runs on | What it does |
|---|---|---|
| Build | PRs and `main` | Detects `infra/` changes, Bicep build/lint, `npm ci --omit=dev`, zips the API and ingest apps, publishes `api`, `ingest`, `frontend`, `infra` artifacts |
| WhatIf | PRs | `az deployment group what-if` against the target resource group |
| Infra | `main`, only if `infra/` changed in the pushed commit or the `deployInfra` run parameter is true | `az deployment group create` with `infra/main.bicep` |
| Api | `main` (runs whether or not Infra ran) | Deploys the zip to the Flex Consumption Function App (name read from deployment outputs) |
| Ingest | `main` (runs whether or not Infra ran) | Temporarily allows the agent IP on the ingest app, deploys the ingest zip, then removes the rule (always) |
| Frontend | `main` (runs whether or not Infra ran) | Fetches the SWA deployment token at runtime and deploys `src/frontend` with the SWA CLI |

## Infra change detection
- The Infra stage runs only when files under `infra/` changed in the last commit of the push, or when a manual run sets `deployInfra` to true.
- Use squash merges for PRs so each merge is a single commit. With several commits in one push, only the last is inspected.
- The first deployment to a new resource group needs `deployInfra: true`, because the code stages read names from the deployment outputs.

## One-time setup
1. Create an Azure Resource Manager service connection (workload identity federation) scoped to the resource group. Grant it Contributor and User Access Administrator, because the Bicep creates role assignments.
2. Create the resource group and an Azure DevOps Environment (add approvals there for production).
3. Edit `serviceConnection`, `resourceGroup` and `environmentName` in the pipeline variables.
4. Create a pipeline from `azure-pipelines.yml`.

No secrets are stored in the pipeline: Azure access uses the service connection and the SWA token is retrieved at deploy time and masked.

## Ingest deployment and the IP allowlist
The ingest app's SCM site inherits the caller IP allowlist, so a deploy from an unlisted agent would return 403. The Ingest stage adds a `deploy-temp` rule for the agent's public IP (priority 100), waits 30 seconds, deploys, and removes the rule in a final step that runs even on failure.
