targetScope = 'resourceGroup'

@description('Primary Azure region for resources (e.g. eastus2)')
param location string = resourceGroup().location

@description('Deployment environment name (e.g. dev, test, prod)')
param environmentName string = 'dev'

@description('Workload name, used as the prefix for all resource names (lowercase letters/digits, e.g. swapp). Function App and Storage names are globally unique, so make it distinctive.')
@minLength(3)
@maxLength(10)
param workloadName string

@description('One or more public IPs or CIDR ranges (e.g. AWS egress IPs) allowed to call the ingest Function App (e.g. 203.0.113.10 or 203.0.113.0/28)')
@minLength(1)
param allowedCallerIps array

@description('Region for Static Web App (defaults to primary location)')
param swaLocation string = location

@description('Name of the table to store log entities')
param tableName string = 'applogs'

@description('Log records older than this many days are deleted daily by the ingest app cleanup timer')
@minValue(1)
param retentionDays int = 30

// Deterministic base name for resource naming, e.g. 'swapp-dev'
var baseName = '${workloadName}-${environmentName}'
var identityName = 'id-${baseName}'

// --------------------------------------------------------------------------------
// 1. Shared User Assigned Managed Identity
// --------------------------------------------------------------------------------
module identity 'modules/identity.bicep' = {
  name: 'deploy-identity'
  params: {
    location: location
    identityName: identityName
  }
}

// --------------------------------------------------------------------------------
// 2. Monitoring (Log Analytics + Application Insights)
// --------------------------------------------------------------------------------
module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    location: location
    baseName: baseName
  }
}

// --------------------------------------------------------------------------------
// 3. Virtual Network & Private DNS Zone
// --------------------------------------------------------------------------------
module network 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    location: location
    baseName: baseName
  }
}

// --------------------------------------------------------------------------------
// 4. Storage Accounts (Dedicated Function Storage + Secured Log Table Storage)
// --------------------------------------------------------------------------------
module storage 'modules/storage.bicep' = {
  name: 'deploy-storage'
  params: {
    location: location
    baseName: baseName
    functionSubnetId: network.outputs.functionSubnetId
    peSubnetId: network.outputs.privateEndpointSubnetId
    blobPrivateDnsZoneId: network.outputs.blobPrivateDnsZoneId
    queuePrivateDnsZoneId: network.outputs.queuePrivateDnsZoneId
    tablePrivateDnsZoneId: network.outputs.tablePrivateDnsZoneId
    uamiPrincipalId: identity.outputs.uamiPrincipalId
    tableName: tableName
  }
}

// --------------------------------------------------------------------------------
// 5. Azure Function App (Flex Consumption, Node.js 22, VNet-integrated, UAMI)
// --------------------------------------------------------------------------------
module functionApp 'modules/functionApp.bicep' = {
  name: 'deploy-function-app'
  params: {
    location: location
    baseName: baseName
    functionSubnetId: network.outputs.functionSubnetId
    uamiId: identity.outputs.uamiId
    uamiClientId: identity.outputs.uamiClientId
    funcStorageName: storage.outputs.funcStorageName
    funcBlobEndpoint: storage.outputs.funcBlobEndpoint
    funcDeploymentContainerName: storage.outputs.funcDeploymentContainerName
    logStorageName: storage.outputs.logStorageName
    tableName: storage.outputs.tableName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

// --------------------------------------------------------------------------------
// 6. Azure Static Web App (Standard SKU with Linked Function App Backend)
// --------------------------------------------------------------------------------
module staticWebApp 'modules/staticWebApp.bicep' = {
  name: 'deploy-static-web-app'
  params: {
    location: swaLocation
    baseName: baseName
    functionAppId: functionApp.outputs.functionAppId
    functionAppRegion: location
  }
}

// --------------------------------------------------------------------------------
// 7. Ingest Function App (public, IP-restricted + function key; writes to Table over private endpoint)
// --------------------------------------------------------------------------------
module ingestFunction 'modules/ingestFunction.bicep' = {
  name: 'deploy-ingest-function'
  params: {
    location: location
    baseName: baseName
    allowedCallerIps: allowedCallerIps
    functionSubnetId: network.outputs.functionSubnetId
    uamiId: identity.outputs.uamiId
    uamiClientId: identity.outputs.uamiClientId
    funcStorageName: storage.outputs.funcStorageName
    funcBlobEndpoint: storage.outputs.funcBlobEndpoint
    ingestDeploymentContainerName: storage.outputs.ingestDeploymentContainerName
    logStorageName: storage.outputs.logStorageName
    tableName: storage.outputs.tableName
    retentionDays: retentionDays
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

// --------------------------------------------------------------------------------
// Outputs
// --------------------------------------------------------------------------------
output sharedIdentityId string = identity.outputs.uamiId
output sharedIdentityClientId string = identity.outputs.uamiClientId
output sharedIdentityPrincipalId string = identity.outputs.uamiPrincipalId

output vnetId string = network.outputs.vnetId
output functionSubnetId string = network.outputs.functionSubnetId
output privateEndpointSubnetId string = network.outputs.privateEndpointSubnetId

output functionStorageName string = storage.outputs.funcStorageName
output logStorageName string = storage.outputs.logStorageName
output tableName string = storage.outputs.tableName

output functionAppName string = functionApp.outputs.functionAppName
output functionAppDefaultHostName string = functionApp.outputs.functionAppDefaultHostName

output staticWebAppName string = staticWebApp.outputs.staticWebAppName
output staticWebAppDefaultHostName string = staticWebApp.outputs.staticWebAppDefaultHostName

output ingestFunctionName string = ingestFunction.outputs.ingestFunctionName
output ingestFunctionDefaultHostName string = ingestFunction.outputs.ingestFunctionDefaultHostName
