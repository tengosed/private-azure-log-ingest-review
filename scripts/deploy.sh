#!/usr/bin/env bash
# Local equivalent of azure-pipelines.yml: build -> (what-if) -> infra -> API -> ingest -> frontend.
# Requires: az (logged in, with Contributor + User Access Administrator on the RG), node 22, npm, zip.
set -euo pipefail

usage() {
  cat <<U
Usage: $0 -g <resource-group> [options]

Required:
  -g, --resource-group NAME   Target resource group (created if missing)

Infra parameter overrides (default: values in infra/main.bicepparam):
  -l, --location REGION       Resource group / resource location (used if the RG must be created)
  -w, --workload NAME         workloadName (3-10 chars)
  -e, --environment NAME      environmentName (e.g. dev, prod)
  -i, --allowed-ips LIST      Comma-separated caller IPs/CIDRs, e.g. 1.2.3.4/32,5.6.7.8/32
  -r, --retention-days N      Days to keep log records
  -s, --subscription ID       Azure subscription (default: current az account)
  -n, --deployment-name NAME  ARM deployment name (default: main)

Modes / skips:
      --what-if               Build and run what-if only; deploy nothing
      --skip-infra            Don't deploy Bicep (reuse the existing deployment's outputs)
      --skip-api              Don't deploy the SWA-linked Function App code
      --skip-ingest           Don't deploy the ingest Function App code
      --skip-frontend         Don't deploy the Static Web App content
  -h, --help
U
}

RG=""; LOCATION=""; WORKLOAD=""; ENVNAME=""; IPS=""; RETENTION=""; SUB=""; DEPNAME="main"
WHATIF=0; SKIP_INFRA=0; SKIP_API=0; SKIP_INGEST=0; SKIP_FRONTEND=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RG="$2"; shift 2;;
    -l|--location) LOCATION="$2"; shift 2;;
    -w|--workload) WORKLOAD="$2"; shift 2;;
    -e|--environment) ENVNAME="$2"; shift 2;;
    -i|--allowed-ips) IPS="$2"; shift 2;;
    -r|--retention-days) RETENTION="$2"; shift 2;;
    -s|--subscription) SUB="$2"; shift 2;;
    -n|--deployment-name) DEPNAME="$2"; shift 2;;
    --what-if) WHATIF=1; shift;;
    --skip-infra) SKIP_INFRA=1; shift;;
    --skip-api) SKIP_API=1; shift;;
    --skip-ingest) SKIP_INGEST=1; shift;;
    --skip-frontend) SKIP_FRONTEND=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1;;
  esac
done
[[ -n "$RG" ]] || { echo "--resource-group is required" >&2; usage >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
step() { printf '\n==> %s\n' "$*"; }

for tool in az node npm zip; do command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }; done
[[ -z "$SUB" ]] || az account set --subscription "$SUB"
az account show --query '{subscription:name, id:id}' -o tsv >/dev/null || { echo "Run 'az login' first." >&2; exit 1; }

# --- Build & validate ---
step "Bicep build & lint"
az bicep build --file "$ROOT/infra/main.bicep" --stdout >/dev/null
az bicep build-params --file "$ROOT/infra/main.bicepparam" --stdout >/dev/null

package() { # <src dir> <zip name>
  (cd "$ROOT/$1" && npm ci --omit=dev >/dev/null)
  (cd "$ROOT/$1" && zip -qr "$BUILD/$2" . -x '*.git*' -x 'local.settings.json')
}
if [[ $WHATIF -eq 0 ]]; then
  [[ $SKIP_API -eq 1 ]] || { step "Package API"; package src/api api.zip; }
  [[ $SKIP_INGEST -eq 1 ]] || { step "Package ingest"; package src/ingest ingest.zip; }
fi

# --- Infra ---
PARAMS=("$ROOT/infra/main.bicepparam")
[[ -z "$LOCATION" ]] || PARAMS+=("location=$LOCATION")
[[ -z "$WORKLOAD" ]] || PARAMS+=("workloadName=$WORKLOAD")
[[ -z "$ENVNAME" ]] || PARAMS+=("environmentName=$ENVNAME")
[[ -z "$RETENTION" ]] || PARAMS+=("retentionDays=$RETENTION")
if [[ -n "$IPS" ]]; then
  PARAMS+=("allowedCallerIps=$(node -e 'console.log(JSON.stringify(process.argv[1].split(",").map(s=>s.trim()).filter(Boolean)))' "$IPS")")
fi

if [[ $SKIP_INFRA -eq 0 || $WHATIF -eq 1 ]]; then
  if [[ -z "$(az group exists -n "$RG" -o tsv | grep -i true || true)" ]]; then
    [[ -n "$LOCATION" ]] || { echo "Resource group '$RG' doesn't exist; pass --location to create it." >&2; exit 1; }
    if [[ $WHATIF -eq 1 ]]; then echo "Resource group '$RG' doesn't exist; what-if skipped."; exit 0; fi
    step "Creating resource group $RG"
    az group create -n "$RG" -l "$LOCATION" -o none
  fi
  if [[ $WHATIF -eq 1 ]]; then
    step "Infra what-if"
    az deployment group what-if -g "$RG" --template-file "$ROOT/infra/main.bicep" --parameters "${PARAMS[@]}"
    exit 0
  fi
  step "Deploying infrastructure ($DEPNAME)"
  az deployment group create -n "$DEPNAME" -g "$RG" \
    --template-file "$ROOT/infra/main.bicep" --parameters "${PARAMS[@]}" -o none
fi

output() { az deployment group show -g "$RG" -n "$DEPNAME" --query "properties.outputs.$1.value" -o tsv; }

deploy_zip() { # <app name> <zip>
  az functionapp deployment source config-zip -g "$RG" -n "$1" --src "$BUILD/$2" -o none
}

# --- Code ---
if [[ $SKIP_API -eq 0 ]]; then
  APP="$(output functionAppName)"; step "Deploying API to $APP"; deploy_zip "$APP" api.zip
fi
if [[ $SKIP_INGEST -eq 0 ]]; then
  APP="$(output ingestFunctionName)"; step "Deploying ingest to $APP"
  # The ingest app (and its SCM site) only admits allowedCallerIps, so temporarily admit this machine.
  MY_IP="$(curl -fsS https://api.ipify.org)"
  RULE="deploy-temp"
  cleanup_rule() { az functionapp config access-restriction remove -g "$RG" -n "$APP" --rule-name "$RULE" -o none 2>/dev/null || true; }
  trap 'cleanup_rule; rm -rf "$BUILD"' EXIT
  echo "Temporarily allowing $MY_IP on $APP"
  az functionapp config access-restriction add -g "$RG" -n "$APP" --rule-name "$RULE" \
    --action Allow --ip-address "$MY_IP/32" --priority 100 -o none
  sleep 30 # rule propagation
  deploy_zip "$APP" ingest.zip
  cleanup_rule
fi
if [[ $SKIP_FRONTEND -eq 0 ]]; then
  SWA="$(output staticWebAppName)"; step "Deploying frontend to $SWA"
  TOKEN="$(az staticwebapp secrets list -n "$SWA" -g "$RG" --query properties.apiKey -o tsv)"
  SWA_CLI_DEPLOYMENT_TOKEN="$TOKEN" npx --yes @azure/static-web-apps-cli deploy "$ROOT/src/frontend" --env production
fi

step "Done"
echo "Ingest host: $(output ingestFunctionDefaultHostName 2>/dev/null || true)"
echo "Function key: az functionapp keys list -g $RG -n $(output ingestFunctionName 2>/dev/null || echo '<ingest-app>') --query functionKeys.default -o tsv"
