terraform {
  required_version = ">= 0.14"
  experiments      = [module_variable_optional_attrs]

  required_providers {
    azurerm = {
      version = ">= 2"
      source  = "hashicorp/azurerm"
    }
  }
}

#########################
#### Locals and Data ####
#########################

locals {
  microservice_environment_name      = "${var.name}-${var.environment_name}"
  full_microservice_environment_name = "${var.service_name}-${local.microservice_environment_name}"
  has_key_vault                      = true
  has_appservice                     = var.appservice == "plan"
  appservice_plans                   = local.has_appservice ? var.appservice_plans : {}
  has_function                       = var.function == "plan" || var.function == "consumption"
  function_appservice_plans          = var.function == "plan" ? var.appservice_plans : var.function == "consumption" ? var.consumption_appservice_plans : {}
  has_sql_database                   = var.sql == "server" || var.sql == "elastic"
  has_primary_sql_server             = local.has_sql_database ? contains(keys(var.sql_servers), var.primary_region) : false
  has_secondary_sql_server           = local.has_sql_database && var.secondary_region != null ? contains(keys(var.sql_servers), var.secondary_region) : false
  has_servicebus_queues              = var.queues != null && length(var.queues) > 0
  has_cosmos_container               = length(var.cosmos_containers) > 0
  has_http                           = var.http != null
  http_target                        = local.has_http ? var.http.target : local.has_appservice ? "appservice" : local.has_function ? "function" : null
  consumers                          = local.has_http ? var.http.consumers != null ? var.http.consumers : [] : []
  has_static_site                    = var.static_site !=null

  # 24 characters is used for max key vault and storage account names
  max_name_length                      = 24

  max_environment_differentiator_short = local.max_name_length - (length(var.name) + length(var.environment) + 2)
  environment_differentiator_short     = local.max_environment_differentiator_short > 0 ? length(var.environment_differentiator) <= local.max_environment_differentiator_short ? var.environment_differentiator : substr(var.environment_differentiator, 0, local.max_environment_differentiator_short) : ""
  
  max_environment_differentiator_short_withservice = local.max_name_length - (length(var.service_name) + length(var.name) + length(var.environment) + 2)
  environment_differentiator_short_withservice     = local.max_environment_differentiator_short_withservice > 0 ? length(var.environment_differentiator) <= local.max_environment_differentiator_short_withservice ? var.environment_differentiator : substr(var.environment_differentiator, 0, local.max_environment_differentiator_short_withservice) : ""
  
  key_vault_access_policies = [
    {
      tenant_id = var.azurerm_client_config.tenant_id
      object_id = var.azurerm_client_config.object_id

      certificate_permissions = var.key_vault_permissions.certificate_permissions
      key_permissions         = var.key_vault_permissions.key_permissions
      secret_permissions      = var.key_vault_permissions.secret_permissions
      storage_permissions     = var.key_vault_permissions.storage_permissions
    },
    {
      tenant_id = var.azurerm_client_config.tenant_id
      object_id = azurerm_user_assigned_identity.microservice_key_vault[0].principal_id

      key_permissions     = ["get"]
      secret_permissions  = ["get"]
      secret_permissions  = null
      storage_permissions = null
    }
  ]
}

################################
#### Microservice Resources ####
################################

### Create UserAssigned MSI for resources (KeyVault, Sql, Cosmos, ServiceBus)
resource "azurerm_user_assigned_identity" "microservice_key_vault" {
  count = local.has_key_vault ? 1 : 0

  name                = "${var.name}-keyvault-${var.environment_name}"
  resource_group_name = var.resource_group_name
  location            = var.primary_region
}

resource "azurerm_user_assigned_identity" "microservice_sql" {
  count = local.has_sql_database ? 1 : 0

  name                = "${var.name}-sql-${var.environment_name}"
  resource_group_name = var.resource_group_name
  location            = var.primary_region
}

# ServiceBus azure function triggers don't support managed identity
# "The Service Bus binding doesn't currently support authentication using a managed identity. Instead, please use a Service Bus shared access signature."
# https://docs.microsoft.com/en-us/azure/azure-functions/functions-bindings-service-bus
resource "azurerm_user_assigned_identity" "microservice_servicebus" {
  count = local.has_servicebus_queues ? 1 : 0

  name                = "${var.name}-servicebus-${var.environment_name}"
  resource_group_name = var.resource_group_name
  location            = var.primary_region
}

resource "azurerm_user_assigned_identity" "microservice_cosmos" {
  count = local.has_cosmos_container ? 1 : 0

  name                = "${var.name}-cosmos-${var.environment_name}"
  resource_group_name = var.resource_group_name
  location            = var.primary_region
}

locals {
  key_vault_read_access_ids = local.has_key_vault ? concat([azurerm_user_assigned_identity.microservice_key_vault[0].principal_id], var.key_vault_user_ids) : []
}

### Key Vault
resource "azurerm_key_vault" "microservice" {
  count = local.has_key_vault ? 1 : 0

  name                        = local.environment_differentiator_short != "" ? "${var.name}-${local.environment_differentiator_short}-${var.environment}" : "${var.name}-${var.environment}"
  location                    = var.primary_region
  resource_group_name         = var.resource_group_name
  enabled_for_disk_encryption = true
  tenant_id                   = var.azurerm_client_config.tenant_id
  soft_delete_retention_days  = var.retention_in_days
  purge_protection_enabled    = false
  sku_name                    = "standard"

  access_policy {
    tenant_id = var.azurerm_client_config.tenant_id
    object_id = var.azurerm_client_config.object_id

    certificate_permissions = var.key_vault_permissions.certificate_permissions
    key_permissions         = var.key_vault_permissions.key_permissions
    secret_permissions      = var.key_vault_permissions.secret_permissions
    storage_permissions     = var.key_vault_permissions.storage_permissions
  }

  dynamic "access_policy" {
    for_each = local.key_vault_read_access_ids

    content {
      tenant_id = var.azurerm_client_config.tenant_id
      object_id = access_policy.value

      key_permissions    = ["get"]
      secret_permissions = ["get"]
    }
  }

  # access_policy {
  #   tenant_id = var.azurerm_client_config.tenant_id
  #   object_id = var.azurerm_client_config.object_id

  #   certificate_permissions = var.key_vault_permissions.certificate_permissions
  #   key_permissions         = var.key_vault_permissions.key_permissions
  #   secret_permissions      = var.key_vault_permissions.secret_permissions
  #   storage_permissions     = var.key_vault_permissions.storage_permissions
  # }

  dynamic "network_acls" {
    for_each = var.key_vault_network_acls != null ? [var.key_vault_network_acls] : []

    content {
      default_action             = var.key_vault_network_acls.default_action
      bypass                     = var.key_vault_network_acls.bypass
      ip_rules                   = var.key_vault_network_acls.ip_rules
      virtual_network_subnet_ids = var.key_vault_network_acls.virtual_network_subnet_ids
    }
  }
}

resource "azurerm_key_vault_secret" "cosmos" {
  count        = local.has_cosmos_container ? 1 : 0
  name         = "cosmos-primary-key"
  value        = var.cosmosdb_primary_key
  key_vault_id = azurerm_key_vault.microservice[0].id
}

locals {
  queues = local.has_servicebus_queues ? flatten([for queue in var.queues : [for namespace in var.servicebus_namespaces : { queue = queue, namespace = namespace }]]) : []
}

resource "azurerm_servicebus_queue" "microservice" {
  for_each = { for queue in local.queues : "${queue.queue.name}-${queue.namespace.name}" => queue }

  name                = "${var.name}-${each.value.queue.name}"
  resource_group_name = var.resource_group_name
  namespace_name      = each.value.namespace.name
}

### AAD Application

resource "azuread_application" "microservice" {
  display_name               = local.full_microservice_environment_name
  prevent_duplicate_names    = true
  oauth2_allow_implicit_flow = true
  identifier_uris            = [lower("https://${local.full_microservice_environment_name}.trafficmanager.net/")]
  owners                     = [var.azurerm_client_config.object_id]
  group_membership_claims    = "None"
  oauth2_permissions         = []

  # Granting required permissions to Microsoft Graph for auth to work
  # Post used to find the correct "magic" Guids
  # https://partlycloudy.blog/2019/12/15/fully-automated-creation-of-an-aad-integrated-kubernetes-cluster-with-terraform/
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000"
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
      type = "Scope"
    }
  }

  reply_urls = [
    lower("https://${local.full_microservice_environment_name}.trafficmanager.net/"),
    lower("https://${local.full_microservice_environment_name}.trafficmanager.net${var.callback_path}")
  ]
}

# Combining the default InternalService role with additional roles
locals {
  application_roles = concat(["InternalService"], coalesce(var.roles, []))
}

resource "azuread_application_app_role" "microservice" {
  for_each = toset(local.application_roles)

  application_object_id = azuread_application.microservice.id
  allowed_member_types  = ["Application", "User"]
  description           = "${each.value} for service"
  display_name          = each.value
  is_enabled            = true
  value                 = each.value
}

### SQL Database

resource "azurerm_mssql_database" "microservice_primary" {
  count = local.has_primary_sql_server ? 1 : 0

  name            = local.microservice_environment_name
  server_id       = var.sql_servers[var.primary_region].id
  elastic_pool_id = var.sql == "elastic" ? var.sql_elastic_pools[var.primary_region].id : null
  collation       = var.sql_database_collation
  sku_name        = var.sql == "elastic" ? "ElasticPool" : var.sql_database_sku

  #max_size_gb     = 4
  #read_scale      = true

  extended_auditing_policy {
    storage_endpoint                        = var.storage_accounts[var.primary_region].primary_blob_endpoint
    storage_account_access_key              = var.storage_accounts[var.primary_region].primary_access_key
    storage_account_access_key_is_secondary = false
    retention_in_days                       = var.retention_in_days
  }
}

resource "azurerm_mssql_database" "microservice_secondary" {
  count = local.has_secondary_sql_server ? 1 : 0

  name                        = local.microservice_environment_name
  server_id                   = var.sql_servers[var.secondary_region].id
  elastic_pool_id             = var.sql == "elastic" ? var.sql_elastic_pools[var.secondary_region].id : null
  create_mode                 = "Secondary"
  creation_source_database_id = azurerm_mssql_database.microservice_primary[0].id
}

#Commenting this out and moving it to azurerm_mssql_database to avoid identity configuration issue from being created separately
# resource "azurerm_mssql_database_extended_auditing_policy" "example" {
#   count = local.has_sql_database ? 1 : 0

#   database_id                             = azurerm_mssql_database.microservice[0].id
#   storage_endpoint                        = var.storage_accounts[var.primary_region].primary_blob_endpoint
#   storage_account_access_key              = var.storage_accounts[var.primary_region].primary_access_key
#   storage_account_access_key_is_secondary = false
#   retention_in_days                       = var.retention_in_days
# }

### Cosmos DB

resource "azurerm_cosmosdb_sql_container" "microservice" {
  for_each = { for container in var.cosmos_containers : container.name => container }

  name                = each.value.name
  partition_key_path  = each.value.partition_key_path
  resource_group_name = var.resource_group_name
  account_name        = var.cosmosdb_account_name
  database_name       = var.cosmosdb_sql_database_name

  dynamic "autoscale_settings" {
    for_each = each.value.max_throughput != null && each.value.max_throughput != 0 ? [each.value.max_throughput] : []
    content {
      max_throughput = autoscale_settings
    }
  }
}

### Appservice

locals {
  azuread_authority = "${var.azuread_instance}${var.azurerm_client_config.tenant_id}/v2.0/"

  appservice_app_settings = merge(
    {
      "APPINSIGHTS_INSTRUMENTATIONKEY"             = var.application_insights.instrumentation_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = var.application_insights.connection_string
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~2"
      "AzureAd:Instance"                           = var.azuread_instance
      "AzureAd:Domain"                             = var.azuread_domain
      "AzureAd:TenantId"                           = var.azurerm_client_config.tenant_id
      "AzureAd:ClientId"                           = azuread_application.microservice.application_id
      "AzureAd:Audience"                           = azuread_application.microservice.application_id
      "AzureAd:Authority"                          = local.azuread_authority
      "AzureAd:CallbackPath"                       = var.callback_path
      "AzureAd:SignedOutCallbackPath"              = var.signed_out_callback_path
      "ApplicationInsights:InstrumentationKey"     = var.application_insights.instrumentation_key
    },
    local.has_key_vault ? {
      "KeyVault:BaseUri"                 = azurerm_key_vault.microservice[0].vault_uri
      "KeyVault:ManagedIdentityClientId" = azurerm_user_assigned_identity.microservice_key_vault[0].client_id
    } : {},
    local.has_sql_database ? {
      "Database:ConnectionString"        = "Server=${var.sql_servers[var.primary_region].fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.microservice_primary[0].name};UID=${azurerm_user_assigned_identity.microservice_sql[0].client_id};Authentication=Active Directory Interactive"
      "Database:ManagedIdentityClientId" = azurerm_user_assigned_identity.microservice_sql[0].client_id
    } : {},
    local.has_servicebus_queues ? {
      "ServiceBus:ConnectionString"        = "Endpoint=sb://${var.servicebus_namespaces[var.primary_region].name}.servicebus.windows.net/;Authentication=Managed Identity"
      "ServiceBus:ManagedIdentityClientId" = azurerm_user_assigned_identity.microservice_servicebus[0].client_id
    } : {},
    local.has_cosmos_container ? {
      "Cosmos:BaseUri"                 = var.cosmosdb_endpoint
      "Cosmos:DatabaseName"            = var.cosmosdb_sql_database_name
      "Cosmos:ManagedIdentityClientId" = azurerm_user_assigned_identity.microservice_cosmos[0].client_id
    } : {}
  )
}

locals {
  appsettings = var.create_appsettings ? merge(
    {
      AzureAd = {
        Instance              = var.azuread_instance
        Domain                = var.azuread_domain
        TenantId              = var.azurerm_client_config.tenant_id
        ClientId              = azuread_application.microservice.application_id
        Audience              = azuread_application.microservice.application_id
        Authority             = local.azuread_authority
        CallbackPath          = var.callback_path
        SignedOutCallbackPath = var.signed_out_callback_path
      }
    },
    {
      ApplicationInsights = {
        InstrumentationKey = var.application_insights.instrumentation_key
      }
    },
    local.has_key_vault ? {
      KeyVault = {
        BaseUri                 = azurerm_key_vault.microservice[0].vault_uri
        ManagedIdentityClientId = azurerm_user_assigned_identity.microservice_key_vault[0].client_id
      }
    } : {},
    local.has_sql_database ? {
      Database = {
        ConnectionString        = "Server=${var.sql_servers[var.primary_region].fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.microservice_primary[0].name};UID=${azurerm_user_assigned_identity.microservice_sql[0].client_id};Authentication=Active Directory Interactive"
        ManagedIdentityClientId = azurerm_user_assigned_identity.microservice_sql[0].client_id
      }
    } : {},
    local.has_servicebus_queues ? {
      ServiceBus = {
        ConnectionString        = "Endpoint=sb://${var.servicebus_namespaces[var.primary_region].name}.servicebus.windows.net/;Authentication=Managed Identity"
        ManagedIdentityClientId = azurerm_user_assigned_identity.microservice_servicebus[0].client_id
      }
    } : {},
    local.has_cosmos_container ? {
      Cosmos = {
        BaseUri                 = var.cosmosdb_endpoint
        DatabaseName            = var.cosmosdb_sql_database_name
        ManagedIdentityClientId = azurerm_user_assigned_identity.microservice_cosmos[0].client_id
      }
    } : {}
  ) : null
}

locals {
  appservice_function_app_settings = merge(
    {
      "FUNCTIONS_WORKER_RUNTIME" = "dotnet",
    },
    local.has_servicebus_queues ? {
      # Currently system assigned identity is supported, but not user assigned identity
      "ServiceBusConnection" = "Endpoint=sb://${var.servicebus_namespaces[var.primary_region].name}.servicebus.windows.net/;Authentication=Managed Identity"
    } : {}
  )
}

locals {
  user_assigned_identities = concat(
    local.has_key_vault ? [azurerm_user_assigned_identity.microservice_key_vault[0]] : [],
    local.has_sql_database ? [azurerm_user_assigned_identity.microservice_sql[0]] : [],
    local.has_servicebus_queues ? [azurerm_user_assigned_identity.microservice_servicebus[0]] : [],
    local.has_cosmos_container ? [azurerm_user_assigned_identity.microservice_cosmos[0]] : []
  )
  has_user_assigned_identities = length(local.user_assigned_identities) > 0
  appservice_identity_type     = local.has_user_assigned_identities ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  # fix #1 - for case sensitivity issue related to azurerm_user_assigned_identity resource to avoid detecting changes
  # strings wrapped in forward slash are treated as regex, hence the "//resourcegroups//"
  # 
  # fix #2 - for sorting the values since they will show up as changes if not
  # sorting didn't work for all scenarios and the result order is seemingly random added more details to this open bug:
  # https://github.com/terraform-providers/terraform-provider-azurerm/issues/7350#issuecomment-755834882

  user_assigned_identity_ids = local.has_user_assigned_identities ? sort([for identity in local.user_assigned_identities : replace(identity.id, "//resourceGroups//", "/resourcegroups/")]) : null
}

resource "azurerm_app_service" "microservice" {
  for_each = local.appservice_plans

  resource_group_name = var.resource_group_name
  name                = "${var.name}-${each.value.location}-${var.environment_name}"
  location            = each.value.location
  app_service_plan_id = each.value.id
  https_only          = true

  site_config {
    http2_enabled   = true
    always_on       = true
    ftps_state      = "FtpsOnly"
    min_tls_version = "1.2"
    #dotnet_framework_version = "v5.0"
    #websockets_enabled = true # Will need for Blazor hosted appservice
  }

  app_settings = local.appservice_app_settings

  identity {
    type         = local.appservice_identity_type
    identity_ids = local.user_assigned_identity_ids
  }
}

locals {
  appservice_slots = local.has_appservice ? flatten([for slot in var.appservice_deployment_slots : [for appservice in azurerm_app_service.microservice : { slot = slot, appservice = appservice }]]) : []
}

### Function

resource "azurerm_function_app" "microservice" {
  for_each = local.function_appservice_plans

  resource_group_name        = var.resource_group_name
  name                       = "${var.name}-function-${each.value.location}-${var.environment_name}"
  location                   = each.value.location
  app_service_plan_id        = each.value.id
  https_only                 = true
  storage_account_name       = var.storage_accounts[each.value.location].name
  storage_account_access_key = var.storage_accounts[each.value.location].primary_access_key
  version                    = "~3"

  site_config {
    http2_enabled   = true
    always_on       = var.function == "plan" ? true : false
    ftps_state      = "FtpsOnly"
    min_tls_version = "1.2"
  }

  app_settings = merge(local.appservice_app_settings, local.appservice_function_app_settings)

  identity {
    type         = local.appservice_identity_type
    identity_ids = local.user_assigned_identity_ids
  }
}

locals {
  function_slots = local.has_function && length(var.appservice_deployment_slots) > 0 ? flatten([for slot in var.appservice_deployment_slots : [for appservice in local.function_appservice_plans : { slot = slot, appservice = appservice }]]) : []
  function_slots_map = { for slot in local.function_slots : "${slot.slot}-${slot.appservice.location}" =>
    {
      slot_name         = slot.slot
      function_app_name = azurerm_function_app.microservice[slot.appservice.location].name
      location          = slot.appservice.location
      app_service_id    = slot.appservice.id
    }
    if slot.slot != null && slot.slot != ""
  }
}

# Slots

resource "time_sleep" "delay_before_creating_slots" {
  depends_on = [
    azurerm_app_service.microservice,
    azurerm_function_app.microservice
  ]

  create_duration  = "30s"
  destroy_duration = "30s"
}

resource "azurerm_app_service_slot" "microservice" {
  for_each = { for slot in local.appservice_slots : "${slot.slot}-${slot.appservice.name}" => slot }

  name                = each.value.slot
  app_service_name    = each.value.appservice.name
  location            = each.value.appservice.location
  resource_group_name = var.resource_group_name
  app_service_plan_id = each.value.appservice.app_service_plan_id

  app_settings = each.value.appservice.app_settings

  site_config {
    dotnet_framework_version = each.value.appservice.site_config[0].dotnet_framework_version
    http2_enabled            = each.value.appservice.site_config[0].http2_enabled
    websockets_enabled       = each.value.appservice.site_config[0].websockets_enabled
    always_on                = each.value.appservice.site_config[0].always_on
  }

  depends_on = [
    azurerm_app_service.microservice,
    time_sleep.delay_before_creating_slots
  ]
}

resource "azurerm_function_app_slot" "microservice" {
  for_each = local.function_slots_map

  name                       = each.value.slot_name
  function_app_name          = each.value.function_app_name
  location                   = each.value.location
  resource_group_name        = var.resource_group_name
  app_service_plan_id        = each.value.app_service_id
  storage_account_name       = var.storage_accounts[each.value.location].name
  storage_account_access_key = var.storage_accounts[each.value.location].primary_access_key

  app_settings = azurerm_function_app.microservice[each.value.location].app_settings

  site_config {
    http2_enabled      = azurerm_function_app.microservice[each.value.location].site_config[0].http2_enabled
    websockets_enabled = azurerm_function_app.microservice[each.value.location].site_config[0].websockets_enabled
    always_on          = azurerm_function_app.microservice[each.value.location].site_config[0].always_on
  }

  depends_on = [
    azurerm_function_app.microservice,
    time_sleep.delay_before_creating_slots
  ]
}

### Static Site
  resource "azurerm_storage_account" "microservice" {
  count = local.has_static_site ? 1 : 0

  name                      = local.environment_differentiator_short_withservice != "" ? "${var.service_name}${var.name}${local.environment_differentiator_short_withservice}${var.environment}" : "${var.service_name}${var.name}${var.environment}"
  resource_group_name       = var.resource_group_name
  location                  = var.primary_region
  account_kind              = var.static_site_kind
  account_tier              = var.static_site_tier
  account_replication_type  = var.static_site_replication_type
  enable_https_traffic_only = true
  min_tls_version           = var.static_site_tls_version
  custom_domain {
    name                    = var.static_site.domain != null ? var.static_site.domain : ""
  }
  static_website {
    index_document          = var.static_site.index_document
    error_404_document      = coalesce(var.static_site.error_document,var.static_site.index_document)
  }
}
### Traffic Manager

# preparing data to be processed by a separate module to reduce conflicts between app service configurations and traffic manager

locals {
  app_service_endpoint_resources  = local.http_target == "appservice" ? { for appservice in azurerm_app_service.microservice : appservice.location => { id = appservice.id, location = appservice.location } } : {}
  function_app_endpoint_resources = local.http_target == "function" ? { for function in azurerm_function_app.microservice : function.location => { id = function.id, location = function.location } } : {}
  azure_endpoint_resources        = merge(local.app_service_endpoint_resources, local.function_app_endpoint_resources)
}
