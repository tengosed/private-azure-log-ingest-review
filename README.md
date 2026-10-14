# Private Azure Log Ingest & Review

## Overview

A private, authenticated **log-collection and review service**: a small serverless "log drop box with a viewer".

- **Write path (ingest):** an external system (e.g. AWS workloads) POSTs log records to a dedicated ingest Function App. Access requires both an allowlisted caller IP and a function key. The function writes to Table Storage with its managed identity, so no storage keys are used.
- **Read path (review):** log reviewers open a Static Web App that requires sign-in on every route. Unauthenticated requests are redirected to login before any content or data is returned. The SWA calls its linked Function App, which reads the table.
- **Private data plane:** the log storage account has public access disabled and is reachable only through a private endpoint. Both Function Apps reach it through VNet integration, so data never crosses the public internet.
- **Lifecycle and operations:** a daily timer deletes records older than the retention period (default 30 days). Application Insights and Log Analytics provide telemetry. Everything is Bicep, deployed by Azure DevOps (infra only when `infra/` changes) or by `scripts/deploy.sh`.

**Pattern:** serverless ingest and query API over Table Storage, with split public and private surfaces (ingest is IP-restricted with a key, review is behind authentication, storage is private-endpoint only) and keyless, identity-based storage access.

**Trade-offs**
- The function key is a shared secret. Entra authentication would be a stronger option for the external caller later.
- The SWA front door is public and relies on authentication rather than network isolation. Making it private adds cost and complexity.
- Table Storage is cheap and simple, but queries are limited to partition and row keys plus filters.

## Documentation

| Guide | Contents |
|---|---|
| [Deployment guide](docs/deployment.md) | Prerequisites, `scripts/deploy.sh`, manual Bicep and code deployment |
| [CI/CD with Azure DevOps](docs/cicd.md) | Pipeline stages, infra change detection, one-time setup |
| [Post-deployment & testing](docs/post-deployment.md) | Retrieve outputs, verify sign-in, test ingest, seed data |
| [Privacy & security details](docs/security.md) | Storage, network isolation, ingest protections, backend ingress |
| [Architecture diagram](docs/architecture.html) | Interactive diagram; reuse via [docs/architecture-template/](docs/architecture-template/STYLE.md) |

## Quick start

```bash
az login
scripts/deploy.sh -g rg-swapp-dev -l eastus2 -w swapp -e dev -i 203.0.113.10/32
scripts/seed.sh -g rg-swapp-dev -c 25 --allow-my-ip
```

Replace the example IP with the egress IP(s) of your caller. See the [deployment guide](docs/deployment.md) for details and manual steps.

## Components

- **Ingest Function App (Flex Consumption)**: A public HTTPS endpoint (`POST /api/ingest`) for external callers (e.g. AWS). Access is limited to the allowed caller IPs and requires a function key. It writes log entries to Azure Table Storage over a private endpoint. A daily timer function (`cleanup`, 02:00 UTC) in the same app deletes records older than `retentionDays` (default 30).
- **Two Storage Accounts**:
  - `stfn...`: Dedicated Function App storage account for Flex Consumption deployment packages (identity-only auth, shared keys disabled, firewall-restricted, with Blob, Queue, and Table private endpoints).
  - `stlog...`: Secured Log Storage Account hosting the Table service (identity-only auth, shared keys disabled), reachable only through a **Private Endpoint** inside an Azure Virtual Network (public network access disabled).
- **Azure Function App (Flex Consumption)**: Running **Node.js 22 LTS**, integrated with the Virtual Network (`snet-func`) for private outbound access to Table Storage. Its linked-backend integration provides SWA-exclusive API access; the Function origin remains publicly reachable at the network layer as required by this integration.
- **Azure Static Web App (Standard SKU)**: Linked to the Flex Consumption Function App via Bring-Your-Own-Backend (`Microsoft.Web/staticSites/userProvidedFunctionApps`). All site routes and API routes require an authenticated user; unauthenticated site requests are redirected to the built-in Microsoft Entra login.
- **Shared User-Assigned Managed Identity (UAMI)**: Shared across both Function Apps for role-based access control (RBAC) targeting.

## Architecture

```text
[ Allowed Caller IP ] 
        │ (HTTPS POST - IP Restricted)
        ▼
┌─────────────────────────────────────────────────────────────┐
│ Ingest Function App (func-ingest-*, Flex Consumption)       │
│ - Access restrictions: allowedCallerIps only, default Deny  │
│ - Function key required (authLevel: function)               │
│ - Identity: User-Assigned Managed Identity (UAMI)           │
│ - Outbound VNet integrated (snet-func)                      │
└───────────────┬─────────────────────────────────────────────┘
                │ (Private Link, via snet-pe)
                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Virtual Network (vnet-swapp-*)                                          │
│                                                                         │
│  ┌──────────────────────────────┐     ┌──────────────────────────────┐  │
│  │ Subnet: snet-func            │     │ Subnet: snet-pe              │  │
│  │ (Microsoft.App/environments) │     │ (Private Endpoints)          │  │
│  │                              │     │                              │  │
│  │  Function App (Flex Consump) │────▶│  Private Endpoint (Table)    │  │
│  │  - Node.js 22 LTS            │ VNet│  - privatelink.table.*       │  │
│  │  - Outbound VNet integrated  │ Route  - Private IP (10.0.2.x)     │  │
│  │  - Linked BYO SWA Backend    │     └──────────────┬───────────────┘  │
│  └──────────────▲───────────────┘                    │                  │
└─────────────────┼────────────────────────────────────┼──────────────────┘
                  │ Forwarded requests                 │ Private Link
                  │                                    ▼
┌─────────────────┴─────────────┐       ┌─────────────────────────────────┐
│ Azure Static Web App          │       │ Log Storage Account (stlog*)    │
│ - SKU: Standard               │       │ - Table Service ('applogs')     │
│ - Linked BYO Backend          │       │ - Network ACLs: Default Deny    │
│                               │       │ - Public network access: off    │
│                               │       │ - RBAC: Storage Table Data      │
│                               │       │         Contributor to UAMI     │
└───────────────────────────────┘       └─────────────────────────────────┘
                                                       ▲
                                        Shared UAMI    │
                                      ┌────────────────┴──────────────────┐
                                      │ User-Assigned Managed Identity    │
                                      │ (id-swapp-*)                      │
                                      └────────────────┬──────────────────┘
                                                       │
                                        Shared UAMI    ▼
                                        ┌─────────────────────────────────┐
                                        │ Function Storage Account (stfn*)│
                                        │ - Deployment Blob Container     │
                                        │ - allowSharedKeyAccess: false   │
                                        │ - RBAC: Storage Blob Data Owner │
                                        └─────────────────────────────────┘
```

## Repository Structure

```text
.
├── azure-pipelines.yml         # Azure DevOps CI/CD pipeline
├── infra/
│   ├── main.bicep              # Orchestrator Bicep template
│   ├── main.bicepparam         # Deployment parameters file
│   ├── bicepconfig.json        # Bicep compiler configuration
│   └── modules/
│       ├── identity.bicep      # Shared User-Assigned Managed Identity
│       ├── monitoring.bicep    # Log Analytics & Application Insights
│       ├── network.bicep       # VNet, Subnets, NSGs & Storage Private DNS Zones
│       ├── storage.bicep       # Two restricted Storage Accounts, Private Endpoints & RBAC
│       ├── functionApp.bicep   # Flex Consumption Function App (Node 22, VNet, SWA security)
│       ├── staticWebApp.bicep  # Azure Static Web App (Standard) with Linked Backend
│       └── ingestFunction.bicep # Ingest Function App (IP-restricted, function key, Table MSI)
├── scripts/
│   ├── deploy.sh               # Local mirror of the pipeline
│   └── seed.sh                 # Seeds dummy records via the ingest endpoint
├── docs/
│   ├── deployment.md           # Deployment guide
│   ├── cicd.md                 # CI/CD guide
│   ├── post-deployment.md      # Post-deployment & testing
│   ├── security.md             # Privacy & security details
│   ├── architecture.html       # Rendered architecture diagram
│   └── architecture-template/  # Reusable architecture diagram styling
└── src/
    ├── api/                    # Azure Functions backend code (Node.js 22 v4 model)
    │   ├── host.json
    │   ├── package.json
    │   └── src/functions/getLogs.js
    ├── ingest/                 # External ingest Function App (POST /api/ingest)
    │   ├── host.json
    │   ├── package.json
    │   └── src/functions/
    │       ├── ingest.js       # POST /api/ingest
    │       └── cleanup.js      # Daily timer: deletes records older than retentionDays
    └── frontend/               # Static Web App frontend
        ├── index.html
        └── staticwebapp.config.json
```
