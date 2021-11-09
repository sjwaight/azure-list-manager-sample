param deployment_location string = resourceGroup().location

var unique_name = uniqueString(resourceGroup().id)

// MySQL Server
param mysql_server_name string = 'lstmnmysql' 
param mysql_admin_user string = 'dbadmin'
@secure()
param mysql_admin_pwd string
param mysql_privatelink_endpoint_name string = 'listmanmysqlpvt'
param privateDnsZones_privatelink_mysql_database_azure_com_name string = 'privatelink.mysql.database.azure.com'
//param networkinterface_listmanmysqlpvt_name string = 'listmanmysqlpvt.nic.${guid(subscription().id)}'

// Cosmos DB
param comosdb_account_prefix string = 'lstmncos'
param cosmosdb_privatelink_endpoint_name string = 'listmancosmospvt'
param privateDnsZones_privatelink_documents_azure_com_name string = 'privatelink.documents.azure.com'
//param networkinterface_listmancosmospvt_name string = 'listmancosmospvt.nic.${guid(subscription().id)}'

// Managed Service Identity (MSI)
param user_assigned_identity_name string = 'listmandemouser'

// Event Hub
param eventhub_namespace_prefix string = 'lstmnns'

// Key Vault
param key_vault_prefix string = 'lstkv'

// Azure Function
param azure_function_hosting_plan_name string = 'listmanfunchost'
param azure_function_name_prefix string = 'lmfunc'

// Storage Account
param storage_account_prefix string = 'lstfun'

// Virtual Network
param virtual_network_name string = 'lstmnprivatenet'

// Application Insights / Azure Monitor
param workspace_name string = 'listmanworkspace'
param components_listmanfunction_name string = 'listmanfunction'

////////
// MYSQL

resource mysql_server 'Microsoft.DBforMySQL/servers@2017-12-01' = {
  name: '${mysql_server_name}${unique_name}'
  location: deployment_location
  dependsOn:[
    private_virtual_network
  ]
  sku: {
    name: 'GP_Gen5_2'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    createMode: 'Default'
    administratorLogin: mysql_admin_user
    administratorLoginPassword: mysql_admin_pwd
    storageProfile: {
      storageMB: 5120
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
      storageAutogrow: 'Disabled'
    }
    version: '8.0'
    sslEnforcement: 'Enabled'
    minimalTlsVersion: 'TLSEnforcementDisabled'
    infrastructureEncryption: 'Disabled'
    publicNetworkAccess: 'Disabled'
  }
}

////////
// COSMOS DB

// Cosmos Account
resource cosmosdb_account 'Microsoft.DocumentDB/databaseAccounts@2021-07-01-preview' = {
  name: '${comosdb_account_prefix}${unique_name}'
  location: deployment_location
  dependsOn:[
    private_virtual_network
  ]
  kind: 'GlobalDocumentDB'
  identity: {
    type: 'None'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    isVirtualNetworkFilterEnabled: false
    virtualNetworkRules: []
    disableKeyBasedMetadataWriteAccess: false
    enableFreeTier: false
    enableAnalyticalStorage: false
    analyticalStorageConfiguration: {
      schemaType: 'WellDefined'
    }
    databaseAccountOfferType: 'Standard'
    defaultIdentity: 'FirstPartyIdentity'
    networkAclBypass: 'None'
    disableLocalAuth: false
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
      maxIntervalInSeconds: 5
      maxStalenessPrefix: 100
    }
    locations: [
      {
        locationName: deployment_location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    cors: []
    capabilities: []
    ipRules: []
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
    networkAclBypassResourceIds: []
    diagnosticLogSettings: {
      enableFullTextQuery: 'None'
    }
    createMode: 'Default'
  }
}

// Cosmos Database
resource cosmosdb_account_database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2021-07-01-preview' = {
  parent: cosmosdb_account
  name: 'listsample'
  properties: {
    resource: {
      id: 'listsample'
    }
    options: {
      throughput: 400
    }
  }
}

// Cosmos Container
resource cosmosdb_account_database_container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-07-01-preview' = {
  parent: cosmosdb_account_database
  name: 'listsample'
  properties: {
    resource: {
      id: 'listsample'
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
      uniqueKeyPolicy: {
        uniqueKeys: []
      }
      conflictResolutionPolicy: {
        mode: 'LastWriterWins'
        conflictResolutionPath: '/_ts'
      }
    }
  }
  dependsOn: [
    cosmosdb_account_database
  ]
}

// resource cosmosdb_private_endpoint_connection 'Microsoft.DocumentDB/databaseAccounts/privateEndpointConnections@2021-07-01-preview' = {
//   parent: cosmosdb_account
//   name: '${comosdb_account_prefix}pvt'
// }

////////
// EVENT HUB

// Namespace definition
resource eventhub_namespace 'Microsoft.EventHub/namespaces@2021-06-01-preview' = {
  name: '${eventhub_namespace_prefix}${unique_name}'
  location: deployment_location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 1
  }
  properties: {
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
    kafkaEnabled: false
  }
}

// Event Hub 
resource eventhub_namespace_eventhub 'Microsoft.EventHub/namespaces/eventhubs@2021-06-01-preview' = {
  parent: eventhub_namespace
  name: 'clientevents'
  properties: {
    messageRetentionInDays: 1
    partitionCount: 2
  }
}

// Event Hub Authorisation Rules (one to send events, one to receive)
resource eventhub_namespace_eventhub_recieveevents_rule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2021-06-01-preview' = {
  parent: eventhub_namespace_eventhub
  name: 'ReceiveEvents'
  properties: {
    rights: [
      'Listen'
    ]
  }
}

resource eventhub_namespace_eventhub_sendevents_rule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2021-06-01-preview' = {
  parent: eventhub_namespace_eventhub
  name: 'SendEvents'
  properties: {
    rights: [
      'Send'
    ]
  }
}

////////
// User-Assigned Managed Service Identity

resource function_keyvault_identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: user_assigned_identity_name
  location: deployment_location
}

////////
// NETWORKING

// Virtual Network
resource private_virtual_network 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name: virtual_network_name
  location: deployment_location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '172.17.0.0/16'
      ]
    }
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}

// Virtual Network Subnets
resource private_virtual_network_default_subnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = {
  parent: private_virtual_network
  name: 'default'
  properties: {
    addressPrefix: '172.17.0.0/24'
    serviceEndpoints: []
    delegations: []
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource private_virtual_network_functions_subnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = {
  parent: private_virtual_network
  name: 'functionssubnet'
  properties: {
    addressPrefix: '172.17.4.0/24'
    serviceEndpoints: [
      {
        service: 'Microsoft.Web'
        locations: [
          '*'
        ]
      }
      {
        service: 'Microsoft.KeyVault'
        locations: [
          '*'
        ]
      }
    ]
    delegations: [
      {
        name: 'Microsoft.Web.serverFarms'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource private_virtual_network_keyvault_subnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = {
  parent: private_virtual_network
  name: 'keyvaultsubnet'
  properties: {
    addressPrefix: '172.17.2.0/24'
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
        locations: [
          '*'
        ]
      }
    ]
    delegations: []
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource private_virtual_network_nosql_subnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = {
  parent: private_virtual_network
  name: 'nosqlsubnet'
  properties: {
    addressPrefix: '172.17.3.0/24'
    serviceEndpoints: []
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource private_virtual_network_database_subnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = {
  parent: private_virtual_network
  name: 'databasesubnet'
  properties: {
    addressPrefix: '172.17.1.0/24'
    serviceEndpoints: []
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// Private DNS 

resource privateDnsZones_privatelink_documents_azure_com_name_resource 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones_privatelink_documents_azure_com_name
  location: 'global'
}

resource privateDnsZones_privatelink_mysql_database_azure_com_name_resource 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZones_privatelink_mysql_database_azure_com_name
  location: 'global'
}

resource privateDnsZones_privatelink_documents_azure_com_name_listmancosmos 'Microsoft.Network/privateDnsZones/A@2018-09-01' = {
  parent: privateDnsZones_privatelink_documents_azure_com_name_resource
  name: 'listmancosmos'
  properties: {
    ttl: 10
    aRecords: [
      {
        ipv4Address: '172.17.3.4'
      }
    ]
  }
}

resource privateDnsZones_privatelink_documents_azure_com_name_listmancosmos_westus2 'Microsoft.Network/privateDnsZones/A@2018-09-01' = {
  parent: privateDnsZones_privatelink_documents_azure_com_name_resource
  name: 'listmancosmos-westus2'
  properties: {
    ttl: 10
    aRecords: [
      {
        ipv4Address: '172.17.3.5'
      }
    ]
  }
}

resource privateDnsZones_privatelink_mysql_database_azure_com_name_listmanmysql 'Microsoft.Network/privateDnsZones/A@2018-09-01' = {
  parent: privateDnsZones_privatelink_mysql_database_azure_com_name_resource
  name: 'listmanmysql'
  properties: {
    ttl: 10
    aRecords: [
      {
        ipv4Address: '172.17.1.4'
      }
    ]
  }
}

resource Microsoft_Network_privateDnsZones_SOA_privateDnsZones_privatelink_documents_azure_com_name 'Microsoft.Network/privateDnsZones/SOA@2018-09-01' = {
  parent: privateDnsZones_privatelink_documents_azure_com_name_resource
  name: '@'
  properties: {
    ttl: 3600
    soaRecord: {
      email: 'azureprivatedns-host.microsoft.com'
      expireTime: 2419200
      host: 'azureprivatedns.net'
      minimumTtl: 10
      refreshTime: 3600
      retryTime: 300
      serialNumber: 1
    }
  }
}

resource Microsoft_Network_privateDnsZones_SOA_privateDnsZones_privatelink_mysql_database_azure_com_name 'Microsoft.Network/privateDnsZones/SOA@2018-09-01' = {
  parent: privateDnsZones_privatelink_mysql_database_azure_com_name_resource
  name: '@'
  properties: {
    ttl: 3600
    soaRecord: {
      email: 'azureprivatedns-host.microsoft.com'
      expireTime: 2419200
      host: 'azureprivatedns.net'
      minimumTtl: 10
      refreshTime: 3600
      retryTime: 300
      serialNumber: 1
    }
  }
}

// Cosmos DB private DNS link to VNet
resource private_dns_cosmos_private_network_registration 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  parent: privateDnsZones_privatelink_documents_azure_com_name_resource
  name: 'cosmospvtdns'
  location: 'global'
  dependsOn:[
    private_virtual_network
  ]
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: private_virtual_network.id
    }
  }
}

// MySQL private DNS link to VNet
resource private_dns_mysql_private_network_registration 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  parent: privateDnsZones_privatelink_mysql_database_azure_com_name_resource
  name: 'mysqlpvtdns'
  location: 'global'
  dependsOn:[
    private_virtual_network
  ]
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: private_virtual_network.id
    }
  }
}

resource cosmosdb_privatelink_endpoint 'Microsoft.Network/privateEndpoints@2020-11-01' = {
  name: cosmosdb_privatelink_endpoint_name
  location: deployment_location
  properties: {
    privateLinkServiceConnections: [
      {
        name: cosmosdb_privatelink_endpoint_name
        properties: {
          privateLinkServiceId: cosmosdb_account.id
          groupIds: [
            'Sql'
          ]
          privateLinkServiceConnectionState: {
            status: 'Approved'
            actionsRequired: 'None'
          }
        }
      }
    ]
    manualPrivateLinkServiceConnections: []
    subnet: {
      id: private_virtual_network_nosql_subnet.id
    }
    customDnsConfigs: []
  }
}

resource mysql_privatelink_endpoint 'Microsoft.Network/privateEndpoints@2020-11-01' = {
  name: mysql_privatelink_endpoint_name
  location: deployment_location
  properties: {
    privateLinkServiceConnections: [
      {
        name: mysql_privatelink_endpoint_name
        properties: {
          privateLinkServiceId: mysql_server.id
          groupIds: [
            'mysqlServer'
          ]
          privateLinkServiceConnectionState: {
            status: 'Approved'
            description: 'Auto-approved'
            actionsRequired: 'None'
          }
        }
      }
    ]
    manualPrivateLinkServiceConnections: []
    subnet: {
      id: private_virtual_network_database_subnet.id
    }
    customDnsConfigs: []
  }
}

resource privateEndpoints_listmancosmospvt_name_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-11-01' = {
  parent: cosmosdb_privatelink_endpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-documents-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones_privatelink_documents_azure_com_name_resource.id
        }
      }
    ]
  }
}

resource privateEndpoints_listmanmysqlpvt_name_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-11-01' = {
  parent: mysql_privatelink_endpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-mysql-database-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones_privatelink_mysql_database_azure_com_name_resource.id
        }
      }
    ]
  }
}

//////
// STORAGE ACCOUNT

resource storage_account_functions 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: '${storage_account_prefix}${unique_name}'
  location: deployment_location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
    allowCrossTenantReplication: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// Blob Service configuration
resource storage_account_functions_blob_default 'Microsoft.Storage/storageAccounts/blobServices@2021-06-01' = {
  parent: storage_account_functions
  name: 'default'
  properties: {
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
  }
}

// Blob Service Containers (folders)
resource storageAccounts_listmanfuncstore_name_default_azure_webjobs_eventhub 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  parent: storage_account_functions_blob_default
  name: 'azure-webjobs-eventhub'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storage_account_functions
  ]
}

resource storageAccounts_listmanfuncstore_name_default_azure_webjobs_hosts 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  parent: storage_account_functions_blob_default
  name: 'azure-webjobs-hosts'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storage_account_functions
  ]
}

resource storageAccounts_listmanfuncstore_name_default_azure_webjobs_secrets 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  parent: storage_account_functions_blob_default
  name: 'azure-webjobs-secrets'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storage_account_functions
  ]
}

//////
// AZURE FUNCTION

// Hosting Plan
resource azure_function_hosting_plan 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: azure_function_hosting_plan_name
  location: deployment_location
  dependsOn:[
    private_virtual_network
  ]
  sku: {
    name: 'S1'
    tier: 'Standard'
    size: 'S1'
    family: 'S'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: true
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}

// Function App
resource azure_function 'Microsoft.Web/sites@2021-02-01' = {
  name: '${azure_function_name_prefix}${unique_name}'
  location: deployment_location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${function_keyvault_identity.id}': {}
      }
  }
  properties: {
    enabled: true
    hostNameSslStates: [
      {
        name: '${azure_function_name_prefix}${unique_name}.azurewebsites.net'
        sslState: 'IpBasedEnabled'
        hostType: 'Standard'
      }
      {
        name: '$${azure_function_name_prefix}${unique_name}.scm.azurewebsites.net'
        sslState: 'IpBasedEnabled'
        hostType: 'Repository'
      }
    ]
    serverFarmId: azure_function_hosting_plan.id
    reserved: true
    isXenon: false
    hyperV: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'NODE|14'
      acrUseManagedIdentityCreds: false
      alwaysOn: true
      http20Enabled: false
      functionAppScaleLimit: 0
      minimumElasticInstanceCount: 1
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    customDomainVerificationId: 'BAB7B948D43A7BC37713D018D7361F77C21815A1BA1F9C0B382F53E9A4036E62'
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    virtualNetworkSubnetId: private_virtual_network_functions_subnet.id
    keyVaultReferenceIdentity: function_keyvault_identity.id
  }
}

// Virtual network configuration for Function
resource azure_function_network_connection 'Microsoft.Web/sites/virtualNetworkConnections@2021-02-01' = {
  parent: azure_function
  name: 'functionssubnet'
  properties: {
    vnetResourceId: private_virtual_network_functions_subnet.id
    isSwift: true
  }
  dependsOn:[
    private_virtual_network_functions_subnet
  ]
}

// Function App Configuration
resource azure_function_configuration 'Microsoft.Web/sites/config@2021-02-01' = {
  parent: azure_function
  dependsOn:[
    function_keyvault_identity
    private_virtual_network_functions_subnet
  ]
  name: 'web'
  properties: {
    numberOfWorkers: 1
    defaultDocuments: [
      'Default.htm'
      'Default.html'
      'Default.asp'
      'index.htm'
      'index.html'
      'iisstart.htm'
      'default.aspx'
      'index.php'
    ]
    netFrameworkVersion: 'v4.0'
    linuxFxVersion: 'NODE|14'
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    remoteDebuggingVersion: 'VS2019'
    httpLoggingEnabled: false
    acrUseManagedIdentityCreds: false
    logsDirectorySizeLimit: 35
    detailedErrorLoggingEnabled: false
    use32BitWorkerProcess: false
    webSocketsEnabled: false
    appSettings: [
      {
        name: 'COSMOS_DATABASE'
        value: 'listsample'
      }
      {
        name: 'COSMOS_CONTAINER'
        value: 'listsample'
      }
      {
        name: 'DATABASE_NAME'
        value: 'lambdademo'
      }
      {
        name: 'WEBSITE_DNS_SERVER'
        value: '168.63.129.16'
      }
    ]
    alwaysOn: true
    managedPipelineMode: 'Integrated'
    virtualApplications: [
      {
        virtualPath: '/'
        physicalPath: 'site\\wwwroot'
        preloadEnabled: true
      }
    ]
    loadBalancing: 'LeastRequests'
    experiments: {
      rampUpRules: []
    }
    autoHealEnabled: false
    vnetName: private_virtual_network_functions_subnet.name
    vnetRouteAllEnabled: true
    vnetPrivatePortsCount: 0
    localMySqlEnabled: false
    keyVaultReferenceIdentity: function_keyvault_identity.id
    ipSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 1
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
    scmIpSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 1
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
    scmIpSecurityRestrictionsUseMain: false
    http20Enabled: false
    minTlsVersion: '1.2'
    scmMinTlsVersion: '1.0'
    ftpsState: 'Disabled'
    preWarmedInstanceCount: 0
    functionAppScaleLimit: 0
    functionsRuntimeScaleMonitoringEnabled: false
    minimumElasticInstanceCount: 1
    azureStorageAccounts: {}
  }
}

//////
// KEY VAULT

resource vaults_listmankeyvault_name_resource 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: '${key_vault_prefix}${unique_name}'
  location: deployment_location
  dependsOn:[
    function_keyvault_identity
    private_virtual_network
  ]
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: [
        {
          id: private_virtual_network_keyvault_subnet.id
          ignoreMissingVnetServiceEndpoint: false
        }
        {
          id: private_virtual_network_functions_subnet.id
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
    accessPolicies: [
      {
        tenantId: function_keyvault_identity.properties.tenantId
        objectId: function_keyvault_identity.properties.principalId 
        permissions: {
          secrets: [
            'get'
          ]
          keys: []
          certificates: []
        }
      }
    ]
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: false
  }
}

// Create Secrets
resource vaults_listmankeyvault_name_LM_COSMOS 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: vaults_listmankeyvault_name_resource
  name: 'LM-COSMOS'
  dependsOn: [
    cosmosdb_account
  ]
  properties: {
    attributes: {
      enabled: true
    }
    value: 'AccountEndpoint=${cosmosdb_account.properties.documentEndpoint};AccountKey=${cosmosdb_account.listKeys().primaryMasterKey}'
  }
}

resource vaults_listmankeyvault_name_LM_EVENTHUB 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: vaults_listmankeyvault_name_resource
  name: 'LM-EVENTHUB'
  dependsOn: [
    eventhub_namespace_eventhub
  ]
  properties: {
    attributes: {
      enabled: true
    }
    value: eventhub_namespace_eventhub.listKeys().primaryConnectionString
  }
}

resource vaults_listmankeyvault_name_LM_MYSQLHOST 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: vaults_listmankeyvault_name_resource
  name: 'LM-MYSQLHOST'
  dependsOn:[
    mysql_server
  ]
  properties: {
    attributes: {
      enabled: true
    }
    value: mysql_server.properties.fullyQualifiedDomainName
  }
}

resource vaults_listmankeyvault_name_LM_MYSQLPWD 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: vaults_listmankeyvault_name_resource
  name: 'LM-MYSQLPWD'
  properties: {
    attributes: {
      enabled: true
    }
    value: mysql_admin_pwd
  }
}

resource vaults_listmankeyvault_name_LM_MYSSQLUSER 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: vaults_listmankeyvault_name_resource
  name: 'LM-MYSSQLUSER'
  properties: {
    attributes: {
      enabled: true
    }
    value: mysql_admin_user
  }
}

/////
// APPLICATION INSIGHTS + AZURE MONITOR

resource workspace_insights 'Microsoft.OperationalInsights/workspaces@2020-08-01' = {
  location: deployment_location
  name: workspace_name
}

resource components_listmanfunction_name_resource 'microsoft.insights/components@2020-02-02' = {
  name: components_listmanfunction_name
  location: deployment_location
  dependsOn:[
    workspace_insights
  ]
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 90
    WorkspaceResourceId: workspace_insights.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource components_listmanfunction_name_degradationindependencyduration 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'degradationindependencyduration'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'degradationindependencyduration'
      DisplayName: 'Degradation in dependency duration'
      Description: 'Smart Detection rules notify you of performance anomaly issues.'
      HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: false
      SupportsEmailNotifications: true
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_degradationinserverresponsetime 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'degradationinserverresponsetime'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'degradationinserverresponsetime'
      DisplayName: 'Degradation in server response time'
      Description: 'Smart Detection rules notify you of performance anomaly issues.'
      HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: false
      SupportsEmailNotifications: true
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_digestMailConfiguration 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'digestMailConfiguration'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'digestMailConfiguration'
      DisplayName: 'Digest Mail Configuration'
      Description: 'This rule describes the digest mail preferences'
      HelpUrl: 'www.homail.com'
      IsHidden: true
      IsEnabledByDefault: true
      IsInPreview: false
      SupportsEmailNotifications: true
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_extension_canaryextension 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'extension_canaryextension'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'extension_canaryextension'
      DisplayName: 'Canary extension'
      Description: 'Canary extension'
      HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/blob/master/SmartDetection/'
      IsHidden: true
      IsEnabledByDefault: true
      IsInPreview: true
      SupportsEmailNotifications: false
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_extension_billingdatavolumedailyspikeextension 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'extension_billingdatavolumedailyspikeextension'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'extension_billingdatavolumedailyspikeextension'
      DisplayName: 'Abnormal rise in daily data volume (preview)'
      Description: 'This detection rule automatically analyzes the billing data generated by your application, and can warn you about an unusual increase in your application\'s billing costs'
      HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/tree/master/SmartDetection/billing-data-volume-daily-spike.md'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: true
      SupportsEmailNotifications: false
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_extension_exceptionchangeextension 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'extension_exceptionchangeextension'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'extension_exceptionchangeextension'
      DisplayName: 'Abnormal rise in exception volume (preview)'
      Description: 'This detection rule automatically analyzes the exceptions thrown in your application, and can warn you about unusual patterns in your exception telemetry.'
      HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/blob/master/SmartDetection/abnormal-rise-in-exception-volume.md'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: true
      SupportsEmailNotifications: false
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_extension_memoryleakextension 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'extension_memoryleakextension'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'extension_memoryleakextension'
      DisplayName: 'Potential memory leak detected (preview)'
      Description: 'This detection rule automatically analyzes the memory consumption of each process in your application, and can warn you about potential memory leaks or increased memory consumption.'
      HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/tree/master/SmartDetection/memory-leak.md'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: true
      SupportsEmailNotifications: false
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_extension_securityextensionspackage 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'extension_securityextensionspackage'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'extension_securityextensionspackage'
      DisplayName: 'Potential security issue detected (preview)'
      Description: 'This detection rule automatically analyzes the telemetry generated by your application and detects potential security issues.'
      HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/blob/master/SmartDetection/application-security-detection-pack.md'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: true
      SupportsEmailNotifications: false
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_extension_traceseveritydetector 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'extension_traceseveritydetector'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'extension_traceseveritydetector'
      DisplayName: 'Degradation in trace severity ratio (preview)'
      Description: 'This detection rule automatically analyzes the trace logs emitted from your application, and can warn you about unusual patterns in the severity of your trace telemetry.'
      HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/blob/master/SmartDetection/degradation-in-trace-severity-ratio.md'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: true
      SupportsEmailNotifications: false
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_longdependencyduration 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'longdependencyduration'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'longdependencyduration'
      DisplayName: 'Long dependency duration'
      Description: 'Smart Detection rules notify you of performance anomaly issues.'
      HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: false
      SupportsEmailNotifications: true
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_migrationToAlertRulesCompleted 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'migrationToAlertRulesCompleted'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'migrationToAlertRulesCompleted'
      DisplayName: 'Migration To Alert Rules Completed'
      Description: 'A configuration that controls the migration state of Smart Detection to Smart Alerts'
      HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
      IsHidden: true
      IsEnabledByDefault: false
      IsInPreview: true
      SupportsEmailNotifications: false
    }
    Enabled: false
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_slowpageloadtime 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'slowpageloadtime'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'slowpageloadtime'
      DisplayName: 'Slow page load time'
      Description: 'Smart Detection rules notify you of performance anomaly issues.'
      HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: false
      SupportsEmailNotifications: true
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}

resource components_listmanfunction_name_slowserverresponsetime 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: components_listmanfunction_name_resource
  name: 'slowserverresponsetime'
  location: deployment_location
  properties: {
    RuleDefinitions: {
      Name: 'slowserverresponsetime'
      DisplayName: 'Slow server response time'
      Description: 'Smart Detection rules notify you of performance anomaly issues.'
      HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: false
      SupportsEmailNotifications: true
    }
    Enabled: true
    SendEmailsToSubscriptionOwners: true
    CustomEmails: []
  }
}