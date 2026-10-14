@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the shared User Assigned Managed Identity')
param identityName string

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

@description('Resource ID of the User Assigned Managed Identity')
output uamiId string = uami.id

@description('Name of the User Assigned Managed Identity')
output uamiName string = uami.name

@description('Principal ID of the User Assigned Managed Identity')
output uamiPrincipalId string = uami.properties.principalId

@description('Client ID of the User Assigned Managed Identity')
output uamiClientId string = uami.properties.clientId
