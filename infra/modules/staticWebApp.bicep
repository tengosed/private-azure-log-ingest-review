@description('Location for the Static Web App (e.g. eastus2, centralus, westeurope)')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string

@description('Resource ID of the external Function App to link as backend')
param functionAppId string

@description('Region of the external Function App')
param functionAppRegion string

var staticWebAppName = 'swa-${baseName}'

// --------------------------------------------------------------------------------
// 1. Azure Static Web App (Standard SKU required for Bring-Your-Own-Backend)
// --------------------------------------------------------------------------------
resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' = {
  name: staticWebAppName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    allowConfigFileUpdates: true
    stagingEnvironmentPolicy: 'Enabled'
  }
}

// --------------------------------------------------------------------------------
// 2. Link external Flex Consumption Function App as the backend
// Keep the Function App publicly reachable at the network layer: SWA BYO Functions
// does not support Function IP restrictions, service endpoints, or Private Link.
// The linked-backend integration provides exclusive SWA access to the API when no
// separate Function App authentication policy is configured.
// --------------------------------------------------------------------------------
resource linkedBackend 'Microsoft.Web/staticSites/userProvidedFunctionApps@2024-04-01' = {
  parent: staticWebApp
  name: 'backend'
  properties: {
    functionAppResourceId: functionAppId
    functionAppRegion: functionAppRegion
  }
}

output staticWebAppId string = staticWebApp.id
output staticWebAppName string = staticWebApp.name
output staticWebAppDefaultHostName string = staticWebApp.properties.defaultHostname
