@maxLength(21)
@minLength(4)
param resourceBaseName string
param botAadAppClientId string
@secure()
param botAadAppClientSecret string
@allowed([
  'F1'
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
])
param webAppSKU string
@maxLength(42)
param botDisplayName string
param msaAppTenantId string
param location string = resourceGroup().location

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: '${resourceBaseName}-logs'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: 'kv-${resourceBaseName}'
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    accessPolicies: []
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
    enablePurgeProtection: true 
    publicNetworkAccess: 'Disabled' 
    enabledForTemplateDeployment: false
  }
}

// Encryption Key
resource encryptionKey 'Microsoft.KeyVault/vaults/keys@2022-07-01' = {
  parent: keyVault
  name: 'appEncryptionKey'
  properties: {
    kty: 'RSA'
    keySize: 3072
  }
}

// Store bot password in Key Vault
resource botSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'botPassword'
  properties: { value: botAadAppClientSecret }
}

// Compute
resource serverfarm 'Microsoft.Web/serverfarms@2021-02-01' = {
  kind: 'app'
  location: location
  name: resourceBaseName
  sku: { name: webAppSKU }
}

// Web App
resource webApp 'Microsoft.Web/sites@2021-02-01' = {
  kind: 'app'
  location: location
  name: resourceBaseName
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: serverfarm.id
    keyVaultReferenceIdentity: 'SystemAssigned'
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      ipSecurityRestrictions: [
        {
          ipAddress: 'AzureBotService'
          action: 'Allow'
          tag: 'ServiceTag'
          priority: 100
          name: 'AllowBotService'
          description: 'Allow traffic from Azure Bot Service only'
        }
        {
          ipAddress: 'Any'
          action: 'Deny'
          priority: 2147483647
          name: 'Deny all'
          description: 'Deny all other public internet traffic'
        }
      ]
      appSettings: [
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
        { name: 'WEBSITE_NODE_DEFAULT_VERSION', value: '~18' }
        { name: 'BOT_ID', value: botAadAppClientId }
        { name: 'MICROSOFT_APP_ID', value: botAadAppClientId }
        { name: 'MICROSOFT_APP_TYPE', value: 'SingleTenant' }
        { name: 'MICROSOFT_APP_TENANT_ID', value: subscription().tenantId }
        { name: 'BOT_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=${botSecret.properties.secretUri})' }
        { name: 'APPLICATION_INSIGHTS_INSTRUMENTATION_KEY', value: appInsights.properties.ConnectionString }
      ]
    }
  }
}

// Diagnostic Settings for Web App
resource webAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'AppServiceDiagnostics'
  scope: webApp
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      { category: 'AppServiceHTTPLogs', enabled: true }
      { category: 'AppServiceConsoleLogs', enabled: true }
      { category: 'AppServiceAppLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourceBaseName}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// Separate Access Policy
resource kvAccess 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  parent: keyVault
  name: 'add'
  dependsOn: [
    webApp
  ]
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: webApp.identity.principalId
        permissions: { 
          secrets: [ 'get' ]
          keys: [ 'get', 'wrapKey', 'unwrapKey' ]
        }
      }
    ]
  }
}

// Registration
module azureBotRegistration './botRegistration/azurebot.bicep' = {
  name: 'Azure-Bot-registration'
  params: {
    resourceBaseName: resourceBaseName
    botAadAppClientId: botAadAppClientId
    msaAppTenantId: msaAppTenantId
    botAppDomain: webApp.properties.defaultHostName
    botDisplayName: botDisplayName
  }
}

output BOT_AZURE_APP_SERVICE_RESOURCE_ID string = webApp.id
output BOT_DOMAIN string = webApp.properties.defaultHostName
