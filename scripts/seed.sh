#!/usr/bin/env bash
# Seeds the log table with dummy records by POSTing to the ingest endpoint.
# The table is private (no public access), so the ingest API is the only way in.
set -euo pipefail

usage() {
  cat <<U
Usage: $0 -g <resource-group> [options]

  -g, --resource-group NAME   Resource group of the deployment (required)
  -c, --count N               Number of records to create (default: 25)
  -n, --deployment-name NAME  ARM deployment name (default: main)
  -s, --subscription ID       Azure subscription
      --host HOST             Ingest host (default: from deployment outputs)
      --key KEY               Function key (default: fetched with az)
      --allow-my-ip           Temporarily add this machine's IP to the ingest access restrictions
  -h, --help

Your public IP must be in allowedCallerIps (or use --allow-my-ip).
Note: the table Timestamp is set by Azure at write time, so seeded records are always "new" for the cleanup job.
U
}

RG=""; COUNT=25; DEPNAME="main"; SUB=""; HOST=""; KEY=""; ALLOW=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RG="$2"; shift 2;;
    -c|--count) COUNT="$2"; shift 2;;
    -n|--deployment-name) DEPNAME="$2"; shift 2;;
    -s|--subscription) SUB="$2"; shift 2;;
    --host) HOST="$2"; shift 2;;
    --key) KEY="$2"; shift 2;;
    --allow-my-ip) ALLOW=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1;;
  esac
done
[[ -n "$RG" ]] || { echo "--resource-group is required" >&2; usage >&2; exit 1; }
[[ "$COUNT" =~ ^[0-9]+$ && "$COUNT" -ge 1 ]] || { echo "--count must be a positive integer" >&2; exit 1; }
[[ -z "$SUB" ]] || az account set --subscription "$SUB"

out() { az deployment group show -g "$RG" -n "$DEPNAME" --query "properties.outputs.$1.value" -o tsv; }
APP="$(out ingestFunctionName)"
[[ -n "$HOST" ]] || HOST="$(out ingestFunctionDefaultHostName)"
[[ -n "$KEY" ]] || KEY="$(az functionapp keys list -g "$RG" -n "$APP" --query functionKeys.default -o tsv)"

RULE="seed-temp"
cleanup_rule() { az functionapp config access-restriction remove -g "$RG" -n "$APP" --rule-name "$RULE" -o none 2>/dev/null || true; }
if [[ $ALLOW -eq 1 ]]; then
  trap cleanup_rule EXIT
  MY_IP="$(curl -fsS https://api.ipify.org)"
  echo "Temporarily allowing $MY_IP on $APP"
  az functionapp config access-restriction add -g "$RG" -n "$APP" --rule-name "$RULE" \
    --action Allow --ip-address "$MY_IP/32" --priority 100 -o none
  sleep 30
fi

PARTITIONS=(Web Api Database Auth Billing Scheduler)
SEVERITIES=(Information Information Information Warning Warning Error Critical)
MESSAGES=(
  "Request completed successfully"
  "User signed in"
  "Cache miss; falling back to database"
  "Slow query detected (>500ms)"
  "Retrying failed upstream call"
  "Unhandled exception while processing request"
  "Disk usage above 90%"
  "Scheduled job finished"
  "Invalid token presented"
  "Payment gateway timeout"
)

ok=0; fail=0
for ((i = 1; i <= COUNT; i++)); do
  p="${PARTITIONS[RANDOM % ${#PARTITIONS[@]}]}"
  sev="${SEVERITIES[RANDOM % ${#SEVERITIES[@]}]}"
  msg="${MESSAGES[RANDOM % ${#MESSAGES[@]}]} (#$i)"
  body="{\"partitionKey\":\"$p\",\"severity\":\"$sev\",\"message\":\"$msg\"}"
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "https://$HOST/api/ingest" \
    -H "x-functions-key: $KEY" -H 'Content-Type: application/json' -d "$body" || echo 000)"
  if [[ "$code" == "201" ]]; then ok=$((ok + 1)); else fail=$((fail + 1)); echo "Record $i failed (HTTP $code)" >&2; fi
done
echo "Created $ok record(s), $fail failed."
[[ $fail -eq 0 ]]
