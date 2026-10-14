@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string

@description('VNet address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet prefix for Flex Consumption Function App outbound VNet integration')
param functionSubnetPrefix string = '10.0.1.0/24'

@description('Subnet prefix for Private Endpoints')
param privateEndpointSubnetPrefix string = '10.0.2.0/24'

// Network Security Group for Function App Subnet
resource nsgFunc 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-func-${baseName}'
  location: location
  properties: {
    securityRules: []
  }
}

// Network Security Group for Private Endpoint Subnet
resource nsgPe 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-pe-${baseName}'
  location: location
  properties: {
    securityRules: []
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${baseName}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-func'
        properties: {
          addressPrefix: functionSubnetPrefix
          networkSecurityGroup: {
            id: nsgFunc.id
          }
          delegations: [
            {
              name: 'flexConsumptionDelegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: nsgPe.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Reference subnets for output
resource functionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: 'snet-func'
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: 'snet-pe'
}

// Private DNS Zone for Storage Table Service
resource privateDnsZoneTable 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.table.${environment().suffixes.storage}'
  location: 'global'
}

// Private DNS Zones for Function Storage private endpoints
resource privateDnsZoneBlob 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
}

resource privateDnsZoneQueue 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.queue.${environment().suffixes.storage}'
  location: 'global'
}

// Link Private DNS Zone to Virtual Network
resource privateDnsZoneLinkTable 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneTable
  name: '${vnet.name}-table-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource privateDnsZoneLinkBlob 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneBlob
  name: '${vnet.name}-blob-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource privateDnsZoneLinkQueue 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneQueue
  name: '${vnet.name}-queue-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output functionSubnetId string = functionSubnet.id
output privateEndpointSubnetId string = peSubnet.id
output blobPrivateDnsZoneId string = privateDnsZoneBlob.id
output queuePrivateDnsZoneId string = privateDnsZoneQueue.id
output tablePrivateDnsZoneId string = privateDnsZoneTable.id
output tablePrivateDnsZoneName string = privateDnsZoneTable.name
