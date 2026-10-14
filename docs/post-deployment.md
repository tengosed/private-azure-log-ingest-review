# Post-Deployment & Testing

Back to the [README](../README.md).

## 1. Retrieve deployed resource details
```bash
# Ingest Function App hostname and function key
INGEST_HOST=$(az functionapp show -g "rg-swapp-prod" -n "<INGEST_FUNCTION_APP_NAME>" --query defaultHostName -o tsv)
INGEST_KEY=$(az functionapp keys list -g "rg-swapp-prod" -n "<INGEST_FUNCTION_APP_NAME>" --query functionKeys.default -o tsv)

# Static Web App hostname
az staticwebapp show \
  --name "<STATIC_WEB_APP_NAME>" \
  --resource-group "rg-swapp-prod" \
  --query defaultHostname -o tsv
```

## 2. Verify sign-in is enforced
In a private/incognito browser session, visit the site root, a static asset, and `/api/logs`. Each request should require Microsoft Entra sign-in before returning site content or API data. After signing in, `/api/logs` should return the log data as expected.

## 3. Test ingest IP restriction, function key & table write
From the **allowed caller IP**:
```bash
curl -X POST "https://$INGEST_HOST/api/ingest" \
  -H "Content-Type: application/json" \
  -H "x-functions-key: $INGEST_KEY" \
  -d '{
    "partitionKey": "WebServer",
    "rowKey": "req-1001",
    "message": "User checkout completed successfully.",
    "severity": "Information"
  }'
```
*Expected:* HTTP `201` with the stored `partitionKey` and `rowKey`. Only `message` is required; the other fields default to `General`, a new GUID and `Information`.

From an **unauthorized IP** (any key):
```bash
curl -i -X POST "https://$INGEST_HOST/api/ingest" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test unauthorized"}'
```
*Expected:* HTTP `403 Forbidden` (blocked by access restrictions).

From the allowed IP **without** the key: HTTP `401 Unauthorized`.

## 4. Seed dummy records
Storage is private, so records are created through the ingest endpoint:
```bash
scripts/seed.sh -g rg-swapp-dev -c 50 --allow-my-ip
```
`--allow-my-ip` temporarily admits your public IP on the ingest app and removes it afterwards. Run `scripts/seed.sh --help` for all options.

## 5. Check the viewer and cleanup
- Sign in to the Static Web App URL. `/api/logs` invokes the linked Function App, which reads the table over the private endpoint.
- The `cleanup` timer runs daily at 02:00 UTC and deletes records older than `retentionDays`. Seeded records always look new because Azure sets the table `Timestamp` at write time.
