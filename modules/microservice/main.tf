terraform {
  required_version = ">= 0.14"
  experiments      = [module_variable_optional_attrs]
}

#########################
#### Locals and Data ####
#########################

data "azurerm_subscription" "current" {}

locals {
  appservice_plans          = var.appservice == "plan" ? var.appservice_plans : var.appservice == "consumption" ? var.consumption_appservice_plans : {}
  function_appservice_plans = var.function == "plan" ? var.appservice_plans : var.function == "consumption" ? var.consumption_function_appservice_plans : {}
}

#############################
#### Datastore Resources ####
#############################

### Create UserAssigned MSI for resources (KeyVault, Sql, Cosmos, ServiceBus)

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

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = var.application_insights.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = var.application_insights.connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~2",
    "FUNCTIONS_WORKER_RUNTIME"                   = "dotnet",
    "AzureAd:TenantId"                           = data.azurerm_subscription.current.tenant_id
  }

  #   storage_account {
  #     name       = var.storage_accounts[each.value.location].name
  #     access_key = var.storage_accounts[each.value.location].primary_access_key
  #   }

  identity {
    type = "SystemAssigned"
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
    always_on       = true
    ftps_state      = "FtpsOnly"
    min_tls_version = "1.2"
    #dotnet_framework_version = "v5.0"
  }

  #app_settings = local.application_settings

  identity {
    type = "SystemAssigned"
  }
}

### Traffic Manager

#######################
#### Output Values ####
#######################

output "microservices_module" {
  value = var.name
}

output "azurerm_app_service_microservice" {
  value = azurerm_app_service.microservice
}
