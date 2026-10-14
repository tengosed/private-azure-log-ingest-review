@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string

@description('Subnet ID for Function App outbound VNet integration')
param functionSubnetId string

@description('Resource ID of the shared User Assigned Managed Identity')
param uamiId string

@description('Client ID of the shared User Assigned Managed Identity')
param uamiClientId string

@description('Function storage account name for host runtime and deployments')
param funcStorageName string

@description('Function storage blob endpoint')
param funcBlobEndpoint string

@description('Function deployment container name')
param funcDeploymentContainerName string

@description('Log Storage Account name (Table Service)')
param logStorageName string

@description('Table name in Log Storage Account')
param tableName string

@description('Application Insights connection string')
param appInsightsConnectionString string

var hostingPlanName = 'asp-${baseName}'
var functionAppName = 'func-${baseName}'

// --------------------------------------------------------------------------------
// 1. Flex Consumption App Service Plan (Serverless, VNet-integrated)
// --------------------------------------------------------------------------------
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

// --------------------------------------------------------------------------------
// 2. Azure Function App on Flex Consumption with Node.js 22 & VNet Integration
// --------------------------------------------------------------------------------
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
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
          value: '${funcBlobEndpoint}${funcDeploymentContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: uamiId
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'node'
        version: '22' // Node.js 22 LTS (exceeds >20 LTS requirement)
      }
    }
    siteConfig: {
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
          name: 'NODE_ENV'
          value: 'production'
        }
      ]
    }
  }
}

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
