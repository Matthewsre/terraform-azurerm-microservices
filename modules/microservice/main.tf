terraform {
  required_version = ">= 0.14"
  experiments      = [module_variable_optional_attrs]
}

#########################
#### Locals and Data ####
#########################

data "azurerm_subscription" "current" {}

locals {
  appservice_plans          = var.appservice == "plan" ? var.appservice_plans : {}
  function_appservice_plans = var.function == "plan" ? var.appservice_plans : var.function == "consumption" ? var.consumption_appservice_plans : {}
  has_sql_database          = var.sql == "server" || var.sql == "elastic"
}

################################
#### Microservice Resources ####
################################

### Create UserAssigned MSI for resources (KeyVault, Sql, Cosmos, ServiceBus)

### SQL Database

resource "azurerm_mssql_database" "microservice" {
  count = local.has_sql_database ? 1 : 0

  name            = "${var.name}-${var.environment_name}"
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
  appservice_app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = var.application_insights.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = var.application_insights.connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~2",
    "AzureAd:TenantId"                           = data.azurerm_subscription.current.tenant_id
  }
}

locals {
  appservice_function_app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "dotnet",
  }
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

  #   app_settings = {
  #     "APPINSIGHTS_INSTRUMENTATIONKEY"             = var.application_insights.instrumentation_key
  #     "APPLICATIONINSIGHTS_CONNECTION_STRING"      = var.application_insights.connection_string
  #     "ApplicationInsightsAgent_EXTENSION_VERSION" = "~2",
  #     "FUNCTIONS_WORKER_RUNTIME"                   = "dotnet",
  #     "AzureAd:TenantId"                           = data.azurerm_subscription.current.tenant_id
  #   }

  #   storage_account {
  #     name       = var.storage_accounts[each.value.location].name
  #     access_key = var.storage_accounts[each.value.location].primary_access_key
  #   }

  identity {
    type = "SystemAssigned"
  }
}

locals {
  appservice_slots = flatten([for slot in var.appservice_deployment_slots : [for appservice in azurerm_app_service.microservice : { slot = slot, appservice = appservice }]])
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
    type = "SystemAssigned"
  }
}

locals {
  function_slots = flatten([for slot in var.appservice_deployment_slots : [for appservice in azurerm_function_app.microservice : { slot = slot, appservice = appservice }]])
  #function_slots  = flatten([for slot in var.appservice_deployment_slots : [for function in azurerm_function_app.microservice : { slot = slot, function = function }]])
  #function_slots_map = { for slot in local.function_slots : "${slot.slot}-${uuid()}" => slot }
}

resource "azurerm_function_app_slot" "microservice" {
  for_each = { for slot in local.function_slots : "${slot.slot}-${uuid()}" => slot }

  name                       = "${each.value.appservice.name}-${each.value.slot}"
  function_app_name          = each.value.appservice.name
  location                   = each.value.appservice.location
  resource_group_name        = var.resource_group_name
  app_service_plan_id        = each.value.appservice.app_service_plan_id
  storage_account_name       = var.storage_accounts[each.value.appservice.location].name
  storage_account_access_key = var.storage_accounts[each.value.appservice.location].primary_access_key

  app_settings = each.value.appservice.app_settings

  site_config {
    http2_enabled      = each.value.appservice.site_config[0].http2_enabled
    websockets_enabled = each.value.appservice.site_config[0].websockets_enabled
    always_on          = each.value.appservice.site_config[0].always_on
  }
}

### Traffic Manager

#######################
#### Output Values ####
#######################

output "name" {
  value = var.name
}

output "database_id" {
  value = local.has_sql_database ? azurerm_mssql_database.microservice[0].id : null
}

# output "azurerm_app_service_microservice" {
#   value = azurerm_app_service.microservice
# }
