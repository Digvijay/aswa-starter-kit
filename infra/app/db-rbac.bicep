// Assigns the built-in Cosmos DB Data Contributor SQL role to a principal.
// This is a Cosmos data-plane assignment (not Azure RBAC) and must be done
// against the Cosmos account directly.

param cosmosAccountName string
param principalId string

// Built-in role: 00000000-0000-0000-0000-000000000002
// = Cosmos DB Built-in Data Contributor
var roleDefinitionId = '00000000-0000-0000-0000-000000000002'

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosAccountName
}

resource sqlRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: account
  name: guid(account.id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: '${account.id}/sqlRoleDefinitions/${roleDefinitionId}'
    principalId: principalId
    scope: account.id
  }
}
