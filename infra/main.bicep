targetScope = 'resourceGroup'

// Azure Static Web Apps starter kit — infrastructure entry point.
// Uses Azure Verified Modules from br/public:avm/...
// Backend runs on the Flex Consumption plan, which is required for .NET 10
// on Linux and is recommended for Node 20 / Python 3.11 going forward.

@minLength(1)
@maxLength(64)
@description('Name of the environment used to generate a short unique hash for resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources.')
param location string = resourceGroup().location

@allowed(['node', 'python', 'dotnet'])
@description('Backend runtime to provision.')
param backendLanguage string = 'node'

@description('SKU for the Static Web App. Standard is required for the linked-backend feature.')
@allowed(['Free', 'Standard'])
param staticWebAppSku string = 'Standard'

@description('Region for the Static Web App. SWA is only available in a subset of Azure regions; the rest of the resources can live anywhere. Defaults to westeurope.')
@allowed(['westus2', 'centralus', 'eastus2', 'westeurope', 'eastasia'])
param staticWebAppLocation string = 'westeurope'

@minValue(40)
@maxValue(1000)
@description('Maximum scale-out instance count for the Flex Consumption plan.')
param maximumInstanceCount int = 100

@allowed([2048, 4096])
@description('Memory size (MB) for each Flex Consumption instance.')
param instanceMemoryMB int = 2048

@description('Tags applied to every resource.')
param tags object = {
  'azd-env-name': environmentName
  workload: 'aswa-starter-kit'
}

// -----------------------------------------------------------------------------
// Naming
// -----------------------------------------------------------------------------
var resourceToken = toLower(uniqueString(subscription().id, resourceGroup().id, environmentName))
var abbrs = {
  law: 'law'
  appi: 'appi'
  swa: 'stapp'
  func: 'func'
  plan: 'plan'
  st: 'st'
  cosmos: 'cosmos'
  uami: 'id'
}

// Flex Consumption uses functionAppConfig.runtime instead of linuxFxVersion.
var runtimeMap = {
  node: { name: 'node', version: '20' }
  python: { name: 'python', version: '3.11' }
  dotnet: { name: 'dotnet-isolated', version: '10.0' }
}

var deploymentContainerName = 'app-package-${take(resourceToken, 32)}'

// -----------------------------------------------------------------------------
// User-assigned managed identity
//
// Created up front so RBAC role assignments can complete BEFORE the Function
// App is created. With Flex Consumption the function host needs identity
// access to its deployment-package container at startup; using a system-
// assigned identity creates a chicken-and-egg problem.
// -----------------------------------------------------------------------------
var uamiName = '${abbrs.uami}-${resourceToken}'

module uami 'br/public:avm/res/managed-identity/user-assigned-identity:0.5.1' = {
  name: 'uami'
  params: {
    name: uamiName
    location: location
    tags: tags
  }
}

resource uamiResource 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uamiName
  dependsOn: [
    uami
  ]
}

// -----------------------------------------------------------------------------
// Observability — Log Analytics + Application Insights
// -----------------------------------------------------------------------------
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.7.0' = {
  name: 'logAnalytics'
  params: {
    name: '${abbrs.law}-${resourceToken}'
    location: location
    tags: tags
    skuName: 'PerGB2018'
    dataRetention: 30
  }
}

module appInsights 'br/public:avm/res/insights/component:0.4.1' = {
  name: 'appInsights'
  params: {
    name: '${abbrs.appi}-${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    kind: 'web'
    applicationType: 'web'
    disableLocalAuth: true
  }
}

// -----------------------------------------------------------------------------
// Storage account — used by the Functions runtime AND as the deployment
// package store for Flex Consumption. Local key auth is disabled; the
// runtime authenticates with the user-assigned identity.
// -----------------------------------------------------------------------------
module storage 'br/public:avm/res/storage/storage-account:0.14.1' = {
  name: 'storage'
  params: {
    name: '${abbrs.st}${resourceToken}'
    location: location
    tags: tags
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    blobServices: {
      containers: [
        {
          name: deploymentContainerName
          publicAccess: 'None'
        }
      ]
    }
    roleAssignments: [
      {
        principalId: uami.outputs.principalId
        roleDefinitionIdOrName: 'Storage Blob Data Owner'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: uami.outputs.principalId
        roleDefinitionIdOrName: 'Storage Queue Data Contributor'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: uami.outputs.principalId
        roleDefinitionIdOrName: 'Storage Table Data Contributor'
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

// Allow the identity to publish telemetry to Application Insights.
// We compute the App Insights name as a local var so the role assignment
// scope/name can be resolved at the start of the deployment.
var appInsightsName = '${abbrs.appi}-${resourceToken}'
resource appInsightsResource 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource appInsightsRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, appInsightsName, uamiName, monitoringMetricsPublisherRoleId)
  scope: appInsightsResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: uamiResource.properties.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    appInsights
  ]
}

// -----------------------------------------------------------------------------
// Cosmos DB (Serverless) — local auth disabled, accessed via UAMI
// -----------------------------------------------------------------------------
module db 'app/db.bicep' = {
  name: 'db'
  params: {
    name: '${abbrs.cosmos}-${resourceToken}'
    location: location
    tags: tags
  }
}

module cosmosDataRbac 'app/db-rbac.bicep' = {
  name: 'cosmosDataRbac'
  params: {
    cosmosAccountName: db.outputs.name
    principalId: uami.outputs.principalId
  }
}

// -----------------------------------------------------------------------------
// Flex Consumption plan (FC1)
// -----------------------------------------------------------------------------
module plan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'plan'
  params: {
    name: '${abbrs.plan}-${resourceToken}'
    location: location
    tags: tags
    skuName: 'FC1'
    skuCapacity: 0
    kind: 'functionapp'
    reserved: true
    zoneRedundant: false
  }
}

// -----------------------------------------------------------------------------
// Function App (Flex Consumption) — selected runtime only
// -----------------------------------------------------------------------------
var functionAppName = '${abbrs.func}-${resourceToken}'

module functionApp 'br/public:avm/res/web/site:0.22.0' = {
  name: 'functionApp'
  params: {
    name: functionAppName
    location: location
    tags: tags
    kind: 'functionapp,linux'
    serverFarmResourceId: plan.outputs.resourceId
    httpsOnly: true
    managedIdentities: {
      userAssignedResourceIds: [
        uami.outputs.resourceId
      ]
    }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.outputs.primaryBlobEndpoint}${deploymentContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: uami.outputs.resourceId
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: {
        name: runtimeMap[backendLanguage].name
        version: runtimeMap[backendLanguage].version
      }
    }
    configs: [
      {
        name: 'appsettings'
        properties: {
          AzureWebJobsStorage__accountName: storage.outputs.name
          AzureWebJobsStorage__credential: 'managedidentity'
          AzureWebJobsStorage__clientId: uami.outputs.clientId
          APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.outputs.connectionString
          APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${uami.outputs.clientId};Authorization=AAD'
          AZURE_CLIENT_ID: uami.outputs.clientId
          COSMOS_ENDPOINT: db.outputs.endpoint
          COSMOS_DATABASE: db.outputs.databaseName
          COSMOS_CONTAINER: db.outputs.containerName
        }
      }
    ]
  }
  dependsOn: [
    cosmosDataRbac
    appInsightsRbac
  ]
}

// -----------------------------------------------------------------------------
// Static Web App linked to the Function App
// -----------------------------------------------------------------------------
module swa 'br/public:avm/res/web/static-site:0.9.4' = {
  name: 'swa'
  params: {
    name: '${abbrs.swa}-${resourceToken}'
    location: staticWebAppLocation
    tags: union(tags, { 'azd-service-name': 'web' })
    sku: staticWebAppSku
    managedIdentities: {
      systemAssigned: true
    }
    linkedBackend: {
      resourceId: functionApp.outputs.resourceId
      location: location
    }
  }
}

// -----------------------------------------------------------------------------
// Outputs consumed by azd / app code
// -----------------------------------------------------------------------------
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId

output SERVICE_WEB_NAME string = swa.outputs.name
output SERVICE_WEB_URI string = 'https://${swa.outputs.defaultHostname}'

output SERVICE_API_NAME string = functionApp.outputs.name
output SERVICE_API_URI string = 'https://${functionApp.outputs.defaultHostname}'

output COSMOS_ENDPOINT string = db.outputs.endpoint
output COSMOS_DATABASE string = db.outputs.databaseName
output COSMOS_CONTAINER string = db.outputs.containerName

output APPLICATIONINSIGHTS_CONNECTION_STRING string = appInsights.outputs.connectionString
output BACKEND_LANGUAGE string = backendLanguage
output AZURE_CLIENT_ID string = uami.outputs.clientId
