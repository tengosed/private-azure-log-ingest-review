@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string

@description('Subnet ID for Function App VNet integration (for storage service endpoint/firewall)')
param functionSubnetId string

@description('Subnet ID for Private Endpoints')
param peSubnetId string

@description('Resource ID of the Private DNS Zone for Table Storage')
param tablePrivateDnsZoneId string

@description('Resource ID of the Private DNS Zone for Blob Storage')
param blobPrivateDnsZoneId string

@description('Resource ID of the Private DNS Zone for Queue Storage')
param queuePrivateDnsZoneId string

@description('Principal ID of the shared User Assigned Managed Identity')
param uamiPrincipalId string

@description('Name of the Table to create in Log Storage Account')
param tableName string = 'applogs'

// Built-in Role Definition IDs
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'

// Unique storage account names (must be 3-24 lowercase alphanumeric chars)
var storageToken = toLower(replace(baseName, '-', ''))
var funcStorageName = take('stfn${storageToken}', 24)
var logStorageName = take('stlog${storageToken}', 24)

// --------------------------------------------------------------------------------
// 1. Function App Storage Account (Dedicated for Flex Consumption code deployments)
// --------------------------------------------------------------------------------
resource funcStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: funcStorageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // Enforce identity-based authentication
    defaultToOAuthAuthentication: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: functionSubnetId
          action: 'Allow'
        }
      ]
    }
  }
}

// Blob service and deployment container for Function App
resource funcBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: funcStorage
  name: 'default'
}

resource funcDeploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: funcBlobService
  name: 'app-package'
  properties: {
    publicAccess: 'None'
  }
}

resource ingestDeploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: funcBlobService
  name: 'ingest-package'
  properties: {
    publicAccess: 'None'
  }
}

// Private endpoints and DNS zone groups for Function host and deployment storage
resource funcBlobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-func-blob-${baseName}'
  location: location
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-func-blob'
        properties: {
          privateLinkServiceId: funcStorage.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource funcBlobPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: funcBlobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob-config'
        properties: {
          privateDnsZoneId: blobPrivateDnsZoneId
        }
      }
    ]
  }
}

resource funcQueuePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-func-queue-${baseName}'
  location: location
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-func-queue'
        properties: {
          privateLinkServiceId: funcStorage.id
          groupIds: [
            'queue'
          ]
        }
      }
    ]
  }
}

resource funcQueuePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: funcQueuePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'queue-config'
        properties: {
          privateDnsZoneId: queuePrivateDnsZoneId
        }
      }
    ]
  }
}

resource funcTablePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-func-table-${baseName}'
  location: location
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-func-table'
        properties: {
          privateLinkServiceId: funcStorage.id
          groupIds: [
            'table'
          ]
        }
      }
    ]
  }
}

resource funcTablePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: funcTablePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'table-config'
        properties: {
          privateDnsZoneId: tablePrivateDnsZoneId
        }
      }
    ]
  }
}

// RBAC: Assign Storage Blob Data Owner to UAMI for Function App deployment storage
resource funcStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: funcStorage
  name: guid(funcStorage.id, uamiPrincipalId, storageBlobDataOwnerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC: Assign Storage Queue Data Contributor to UAMI for Function App host storage
resource funcStorageQueueRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: funcStorage
  name: guid(funcStorage.id, uamiPrincipalId, storageQueueDataContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC: Assign Storage Table Data Contributor to UAMI for Function App host storage
resource funcStorageTableRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: funcStorage
  name: guid(funcStorage.id, uamiPrincipalId, storageTableDataContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// --------------------------------------------------------------------------------
// 2. Log Storage Account (Table Service, private endpoint only)
// --------------------------------------------------------------------------------
resource logStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: logStorageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: functionSubnetId
          action: 'Allow'
        }
      ]
    }
  }
}

// Table service in Log Storage
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: logStorage
  name: 'default'
}

// Table entity collection
resource table 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: tableName
}

// Private Endpoint for Table Storage Service in snet-pe
resource peTable 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-table-${baseName}'
  location: location
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-table'
        properties: {
          privateLinkServiceId: logStorage.id
          groupIds: [
            'table'
          ]
        }
      }
    ]
  }
}

// Register Private Endpoint with Private DNS Zone
resource peDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: peTable
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'table-config'
        properties: {
          privateDnsZoneId: tablePrivateDnsZoneId
        }
      }
    ]
  }
}

// RBAC: Assign Storage Table Data Contributor to UAMI for Log Storage
resource logStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: logStorage
  name: guid(logStorage.id, uamiPrincipalId, storageTableDataContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output funcStorageId string = funcStorage.id
output funcStorageName string = funcStorage.name
output funcBlobEndpoint string = funcStorage.properties.primaryEndpoints.blob
output funcDeploymentContainerName string = funcDeploymentContainer.name
output ingestDeploymentContainerName string = ingestDeploymentContainer.name

output logStorageId string = logStorage.id
output logStorageName string = logStorage.name
output logTableEndpoint string = logStorage.properties.primaryEndpoints.table
output tableName string = table.name
output logStorageTableRoleId string = storageTableDataContributorRoleId
