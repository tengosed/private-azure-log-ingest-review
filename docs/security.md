# Privacy & Security Implementation Details

Back to the [README](../README.md).

## 1. Two Separate Storage Accounts
- **Function App Storage Account (`stfn...`)**:
  - Dedicated strictly to Azure Functions Flex Consumption deployment packages and runtime state.
  - `allowSharedKeyAccess: false` enforces identity-based OAuth authentication via the shared UAMI.
  - `networkAcls.defaultAction: 'Deny'` restricts network access to the Function App subnet.
  - Blob, Queue, and Table private endpoints use private DNS zones linked to the VNet.
  - Granted `Storage Blob Data Owner` (`b7e6dc6d-f1e8-4753-8033-0f276bb0955b`).
- **Log Storage Account (`stlog...`)**:
  - Dedicated to the Table service (`applogs` table).
  - `allowSharedKeyAccess: false` requires identity-based authentication.
  - `networkAcls.defaultAction: 'Deny'` blocks public internet access.
  - Outbound VNet integration subnet (`snet-func`) is allowed via VNet service endpoints/rules.
  - Contains a **Private Endpoint** (`pe-table-*`) in `snet-pe` mapped to Private DNS Zone `privatelink.table.core.windows.net`.
  - Granted `Storage Table Data Contributor` (`0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3`) to the shared UAMI.

## 2. Virtual Network & Function App Isolation
- **Subnet Delegation**: The Function App subnet (`snet-func`) is delegated to `Microsoft.App/environments` as required for the Azure Functions Flex Consumption plan.
- **Private Outbound Communication**: Outbound traffic from the Function App to Table Storage routes privately through the Private Endpoint in `snet-pe` via Azure Private DNS.
- **Linked Backend Integration**: The Function App serves as the Bring-Your-Own (BYO) backend for the Azure Static Web App. API calls are proxied through the SWA `/api/*` path, and the linked-backend integration grants the SWA exclusive API access when no other Function App authentication policy is configured. The Function origin remains network-public: Microsoft does not support Function IP restrictions, service endpoints, or Private Link for a linked backend. Do not add these network controls to the Function App without changing the backend architecture.
- **End-user authentication**: `staticwebapp.config.json` requires the `authenticated` role for both `/api/*` and every other route. Requests without an authenticated SWA session are denied before content or API data is returned, then redirected to the built-in Microsoft Entra login with the original URL as the post-login destination. Keep the API rule explicit so it remains protected if the site-wide route policy changes.
- **Anonymous Function trigger**: The HTTP trigger uses `authLevel: 'anonymous'` so the SWA proxy does not need a Function key. End-user authorization is enforced at the SWA route boundary, and the linked-backend integration protects the Function origin from direct access. Do not remove the linked backend or expose another public route to this function without adding and validating an independent authentication boundary.

## 3. Ingest Function: Caller IP Restriction, Function Key & MSI
- **Caller IP Restriction**: The ingest Function App keeps a public endpoint, but its access restrictions allow only the IPs/CIDRs in `allowedCallerIps` (bare IPs are treated as `/32`) and deny everything else, including the SCM site. Use a static egress IP on the caller side (e.g. an AWS NAT gateway or Elastic IP).
- **Function key**: The trigger uses `authLevel: 'function'`, so callers must send the key in the `x-functions-key` header. An IP allowlist is not authentication on its own. Keep the key in the caller's secret store (e.g. AWS Secrets Manager) and rotate it periodically. Microsoft Entra authentication is a possible later upgrade.
- **MSI Authentication**: The function writes to the Table with the shared UAMI (`DefaultAzureCredential`), with no keys or connection strings.
- **Private storage path**: The Log Storage Account has public network access disabled. The ingest app reaches it through VNet integration and the Table private endpoint, so no storage firewall allowlist is needed.
- **Diagnostics**: Telemetry goes to Application Insights and the Log Analytics workspace.
- **Deploying code**: Because the SCM site is also IP-restricted, code deployments must temporarily allow the deployer's IP. `scripts/deploy.sh` and the pipeline's Ingest stage do this with a short-lived `deploy-temp` rule.

## 4. Function Backend Ingress
- The `Microsoft.Web/staticSites/userProvidedFunctionApps` link is the supported security boundary for direct access to the linked Function API. Keep this resource deployed and verify the Function App's Authentication page retains the **Azure Static Web Apps (Linked)** provider.
- Keep IP restrictions, service endpoints, and Private Link disabled on the *linked* Function App (`func-<workload>-<env>`) while using this backend integration; the separate ingest Function App is not linked to the SWA and does use IP restrictions. Microsoft lists these as incompatible with BYO Functions.
- The SWA route configuration requires authentication for `/api/*` and all site content. Confirm unauthenticated requests to `/`, a static asset, and `/api/logs` are redirected to sign-in and never return page content or log data; after sign-in, the page and API should work as expected.

## 5. Node.js 22 LTS
The Function Apps are deployed on Azure Functions **Flex Consumption** (`FC1`) with:
```bicep
runtime: {
  name: 'node'
  version: '22'
}
```
