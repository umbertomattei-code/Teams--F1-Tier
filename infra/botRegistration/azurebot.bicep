@maxLength(21)
@minLength(4)
param resourceBaseName string
@maxLength(42)
param botDisplayName string
param msaAppTenantId string
param botServiceName string = resourceBaseName
param botServiceSku string = 'S1' // Standard tier. Can choose between S1 or F0.
param botAadAppClientId string
param botAppDomain string

// Register your web service as a bot with the Bot Framework
resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  kind: 'azurebot'
  location: 'global'
  name: botServiceName
  identity: {
    type: 'None'
  }
  properties: {
    displayName: botDisplayName
    endpoint: 'https://${botAppDomain}/api/messages' // If you already have your Mindflow webhook URL async, you can replace endpoint with that URL. Otherwise, no worries, you will be able to update this on the Azure Bot configuration blade on Azure.
    msaAppId: botAadAppClientId
    msaAppTenantId: msaAppTenantId
    msaAppType:'SingleTenant'
  }
  sku: {
    name: botServiceSku
  }
}

// Connect the bot service to Microsoft Teams
resource botServiceMsTeamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: botService
  location: 'global'
  name: 'MsTeamsChannel'
  properties: {
    channelName: 'MsTeamsChannel'
  }
}
