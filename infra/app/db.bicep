// Cosmos DB account (Serverless, NoSQL) using AVM
// Local auth is disabled; the API authenticates with a user-assigned MI.

param name string
param location string
param tags object = {}

param databaseName string = 'app'
param containerName string = 'items'

module account 'br/public:avm/res/document-db/database-account:0.19.0' = {
  name: 'cosmos-account'
  params: {
    name: name
    location: location
    tags: tags
    enableFreeTier: false
    zoneRedundant: false
    capabilitiesToAdd: [
      'EnableServerless'
    ]
    failoverLocations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    disableLocalAuthentication: true
    networkRestrictions: {
      publicNetworkAccess: 'Enabled'
      ipRules: []
      virtualNetworkRules: []
    }
    sqlDatabases: [
      {
        name: databaseName
        containers: [
          {
            name: containerName
            paths: [ '/id' ]
            kind: 'Hash'
          }
        ]
      }
    ]
  }
}

output name string = account.outputs.name
output resourceId string = account.outputs.resourceId
output endpoint string = 'https://${account.outputs.name}.documents.azure.com:443/'
output databaseName string = databaseName
output containerName string = containerName
