using 'main.bicep'

param location = 'eastus2'
param environmentName = 'dev'
param workloadName = 'statusLogs'

// One or more IP addresses or CIDR blocks allowed to call the ingest Function App (e.g. AWS NAT/Elastic IPs)
param allowedCallerIps = [
  '203.0.113.10/32' // TODO: replace with real caller IP(s)
]

// Name of the table entity to store log records
param tableName = 'applogs'
