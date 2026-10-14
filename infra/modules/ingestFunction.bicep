@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string

@description('Public IPs or CIDR ranges allowed to call the ingest endpoint')
@minLength(1)
param allowedCallerIps array

@description('Subnet ID for outbound VNet integration')
param functionSubnetId string

@description('Resource ID of the shared User Assigned Managed Identity')
param uamiId string

@description('Client ID of the shared User Assigned Managed Identity')
param uamiClientId string

@description('Function storage account name for host runtime and deployments')
param funcStorageName string

@description('Function storage blob endpoint')
param funcBlobEndpoint string

@description('Deployment container name for the ingest app package')
param ingestDeploymentContainerName string

@description('Records older than this many days are deleted by the daily cleanup timer')
param retentionDays int

@description('Log Storage Account name (Table Service)')
param logStorageName string

@description('Table name in Log Storage Account')
param tableName string

@description('Application Insights connection string')
param appInsightsConnectionString string

var hostingPlanName = 'asp-ingest-${baseName}'
var ingestFunctionName = 'func-ingest-${baseName}'

// Access restrictions require CIDR notation; bare IPs become /32
var allowRules = [for (ip, i) in allowedCallerIps: {
  name: 'allow-caller-${i}'
  priority: 100 + i
  action: 'Allow'
  ipAddress: contains(ip, '/') ? ip : '${ip}/32'
}]

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource ingestFunction 'Microsoft.Web/sites@2024-04-01' = {
  name: ingestFunctionName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    virtualNetworkSubnetId: functionSubnetId
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${funcBlobEndpoint}${ingestDeploymentContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: uamiId
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'node'
        version: '22'
      }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      // Public endpoint, but only the allowed caller IPs are admitted; everything else is denied
      ipSecurityRestrictionsDefaultAction: 'Deny'
      ipSecurityRestrictions: allowRules
      scmIpSecurityRestrictionsDefaultAction: 'Deny'
      scmIpSecurityRestrictionsUseMain: true
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: funcStorageName
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: uamiClientId
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: uamiClientId
        }
        {
          name: 'TABLE_STORAGE_ACCOUNT_NAME'
          value: logStorageName
        }
        {
          name: 'TABLE_NAME'
          value: tableName
        }
        {
          name: 'RETENTION_DAYS'
          value: string(retentionDays)
        }
      ]
    }
  }
}

output ingestFunctionId string = ingestFunction.id
output ingestFunctionName string = ingestFunction.name
output ingestFunctionDefaultHostName string = ingestFunction.properties.defaultHostName
