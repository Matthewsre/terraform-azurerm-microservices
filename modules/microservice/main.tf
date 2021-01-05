terraform {
  required_version = ">= 0.14"
  experiments      = [module_variable_optional_attrs]
}

#########################
#### Locals and Data ####
#########################

locals {
  microservice_environment_name = "${var.name}-${var.environment_name}"
  has_key_vault                 = true
  has_appservice                = var.appservice == "plan"
  appservice_plans              = local.has_appservice ? var.appservice_plans : {}
  has_function                  = var.function == "plan" || var.function == "consumption"
  function_appservice_plans     = var.function == "plan" ? var.appservice_plans : var.function == "consumption" ? var.consumption_appservice_plans : {}
  has_sql_database              = var.sql == "server" || var.sql == "elastic"
  has_servicebus_queues         = var.queues != null && length(var.queues) > 0
  has_cosmos_container          = length(var.cosmos_containers) > 0
  has_http                      = var.http != null
  http_target                   = local.has_http ? var.http.target : local.has_appservice ? "appservice" : local.has_function ? "function" : null
  consumers                     = local.has_http ? var.http.consumers != null ? var.http.consumers : [] : []

  # 24 characters is used for max key vault name
  max_name_length                      = 24
  max_environment_differentiator_short = local.max_name_length - (length(var.name) + length(var.environment) + 2)
  environment_differentiator_short     = local.max_environment_differentiator_short > 0 ? length(var.environment_differentiator) <= local.max_environment_differentiator_short ? var.environment_differentiator : substr(var.environment_differentiator, 0, local.max_environment_differentiator_short) : ""
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

### Key Vault
resource "azurerm_key_vault" "microservice" {
  count = local.has_key_vault ? 1 : 0

  name                        = "${var.name}-${local.environment_differentiator_short}-${var.environment}"
  location                    = var.primary_region
  resource_group_name         = var.resource_group_name
  enabled_for_disk_encryption = true
  tenant_id                   = var.azurerm_client_config.tenant_id
  soft_delete_enabled         = true
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

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.key_vault_ip_rules
  }
}

resource "azurerm_key_vault_access_policy" "microservice" {
  count = local.has_key_vault ? 1 : 0

  key_vault_id = azurerm_key_vault.microservice[0].id
  tenant_id    = var.azurerm_client_config.tenant_id
  object_id    = azurerm_user_assigned_identity.microservice_key_vault[0].principal_id

  key_permissions = [
    "get",
  ]

  secret_permissions = [
    "get",
  ]
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
  name                       = local.microservice_environment_name
  prevent_duplicate_names    = true
  oauth2_allow_implicit_flow = true
  identifier_uris            = [lower("https://${local.microservice_environment_name}.trafficmanager.net/")]
  owners                     = [var.azurerm_client_config.object_id]
  group_membership_claims    = "None"
  oauth2_permissions         = []
  reply_urls = [
    lower("https://${local.microservice_environment_name}.trafficmanager.net/"),
    lower("https://${local.microservice_environment_name}.trafficmanager.net${var.callback_path}")
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

resource "azurerm_mssql_database" "microservice" {
  count = local.has_sql_database ? 1 : 0

  name            = local.microservice_environment_name
  server_id       = var.sql_server_id
  elastic_pool_id = var.sql == "elastic" ? var.sql_elastic_pool_id : null
  collation       = "SQL_Latin1_General_CP1_CI_AS"
  license_type    = "LicenseIncluded"
  sku_name        = var.sql == "elastic" ? "ElasticPool" : "BC_Gen5_2"

  #max_size_gb     = 4
  #read_scale      = true

  extended_auditing_policy {
    storage_endpoint                        = var.storage_accounts[var.primary_region].primary_blob_endpoint
    storage_account_access_key              = var.storage_accounts[var.primary_region].primary_access_key
    storage_account_access_key_is_secondary = false
    retention_in_days                       = var.retention_in_days
  }
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
  appservice_app_settings = merge(
    {
      "APPINSIGHTS_INSTRUMENTATIONKEY"             = var.application_insights.instrumentation_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = var.application_insights.connection_string
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~2"
      "AzureAd:Instance"                           = "https://login.microsoftonline.com/"
      "AzureAd:Domain"                             = "microsoft.onmicrosoft.com"
      "AzureAd:TenantId"                           = var.azurerm_client_config.tenant_id
      "AzureAd:ClientId"                           = azuread_application.microservice.id
      "AzureAd:CallbackPath"                       = var.callback_path
      "ApplicationInsights:InstrumentationKey"     = var.application_insights.instrumentation_key
    },
    local.has_key_vault ? {
      "KeyVault:BaseUri"             = azurerm_key_vault.microservice[0].vault_uri
      "KeyVault:ManagedServiceAppId" = azurerm_user_assigned_identity.microservice_key_vault[0].client_id
    } : {},
    local.has_sql_database ? {
      "Database:ManagedServiceAppId" = azurerm_user_assigned_identity.microservice_sql[0].client_id
    } : {},
    local.has_servicebus_queues ? {
      "ServiceBus:ManagedServiceAppId" = azurerm_user_assigned_identity.microservice_servicebus[0].client_id
    } : {},
    local.has_cosmos_container ? {
      "DocumentStore:Url"                 = var.cosmosdb_endpoint
      "DocumentStore:ManagedServiceAppId" = azurerm_user_assigned_identity.microservice_cosmos[0].client_id
    } : {}
  )
}

locals {
  appservice_function_app_settings = merge(
    {
      "FUNCTIONS_WORKER_RUNTIME" = "dotnet",
    },
    local.has_servicebus_queues ? {
      "ServiceBusConnection" = "Endpoint=sb://${var.servicebus_namespaces[var.primary_region].name}.servicebus.windows.net/;"
      # Commenting out until User Assigned Identity is supported by Service Bus Functions
      # "ServiceBus:ManagedServiceAppId" = "Endpoint=sb://<NAMESPACE NAME>.servicebus.windows.net/;Authentication=Managed Identity${azurerm_user_assigned_identity.microservice_servicebus[0].client_id}"
    } : {}
  )
}

locals {
  user_assigned_identities = concat(
    local.has_key_vault ? [azurerm_user_assigned_identity.microservice_key_vault[0].id] : [],
    local.has_sql_database ? [azurerm_user_assigned_identity.microservice_sql[0].id] : [],
    local.has_servicebus_queues ? [azurerm_user_assigned_identity.microservice_servicebus[0].id] : [],
    local.has_cosmos_container ? [azurerm_user_assigned_identity.microservice_cosmos[0].id] : []
  )
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

  #   storage_account {
  #     name       = var.storage_accounts[each.value.location].name
  #     access_key = var.storage_accounts[each.value.location].primary_access_key
  #   }

  dynamic "identity" {
    for_each = length(local.user_assigned_identities) > 0 ? [local.user_assigned_identities] : []
    content {
      type         = "UserAssigned"
      identity_ids = local.user_assigned_identities
    }
  }
}

locals {
  appservice_slots = local.has_appservice ? flatten([for slot in var.appservice_deployment_slots : [for appservice in azurerm_app_service.microservice : { slot = slot, appservice = appservice }]]) : []
}

resource "azurerm_app_service_slot" "microservice" {
  for_each = { for slot in local.appservice_slots : "${slot.slot}-${slot.appservice.name}" => slot }

  name                = "${each.value.appservice.name}-${each.value.slot}"
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
    azurerm_app_service.microservice
  ]
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
    type         = "UserAssigned"
    identity_ids = local.user_assigned_identities
  }
}

locals {
  function_slots = local.has_function && length(var.appservice_deployment_slots) > 0 ? flatten([for slot in var.appservice_deployment_slots : [for appservice in local.function_appservice_plans : { slot = slot, appservice = appservice }]]) : []
  function_slots_map = { for slot in local.function_slots : "${slot.slot}-${slot.appservice.location}" =>
    {
      slot_name         = "${azurerm_function_app.microservice[slot.appservice.location].name}-${slot.slot}"
      function_app_name = azurerm_function_app.microservice[slot.appservice.location].name
      location          = slot.appservice.location
      app_service_id    = slot.appservice.id
    }
    if slot.slot != null && slot.slot != ""
  }
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
    azurerm_function_app.microservice
  ]
}

### Traffic Manager

resource "azurerm_traffic_manager_profile" "microservice" {
  name                   = local.microservice_environment_name
  resource_group_name    = var.resource_group_name
  traffic_routing_method = "Performance"

  dns_config {
    relative_name = local.microservice_environment_name
    ttl           = 60
  }

  monitor_config {
    protocol                     = "https"
    port                         = 443
    path                         = "/"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }
}

resource "azurerm_traffic_manager_endpoint" "microservice_appservice" {
  for_each = local.http_target == "appservice" ? azurerm_app_service.microservice : {}

  name                = each.value.location
  resource_group_name = var.resource_group_name
  profile_name        = azurerm_traffic_manager_profile.microservice.name
  type                = "azureEndpoints"
  target_resource_id  = each.value.id

  # traffic manager can cause conflict errors if running in parallel with slot creation
  depends_on = [
    azurerm_app_service_slot.microservice,
    azurerm_function_app_slot.microservice
  ]
}

resource "azurerm_traffic_manager_endpoint" "microservice_function" {
  for_each = local.http_target == "function" ? azurerm_function_app.microservice : {}

  name                = each.value.location
  resource_group_name = var.resource_group_name
  profile_name        = azurerm_traffic_manager_profile.microservice.name
  type                = "azureEndpoints"
  target_resource_id  = each.value.id

  # traffic manager can cause conflict errors if running in parallel with slot creation
  depends_on = [
    azurerm_app_service_slot.microservice,
    azurerm_function_app_slot.microservice
  ]
}
