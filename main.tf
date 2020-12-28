terraform {
  required_version = ">= 0.14"
  #backend "azurerm" {}
  experiments = [module_variable_optional_attrs]
}

provider "azurerm" {
  use_msi                    = var.use_msi_to_authenticate
  skip_provider_registration = true
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

provider "random" {}

#########################
#### Locals and Data ####
#########################

locals {
  is_dev = lower(var.environment) == "dev"
}

data "azurerm_client_config" "current" {}

data "azuread_user" "current_user" {
  count     = local.is_dev ? 1 : 0
  object_id = data.azurerm_client_config.current.object_id
}

locals {
  primary_region                      = var.primary_region != "" ? var.primary_region : var.regions[0]
  retention_in_days                   = 90
  service_name                        = lower(var.service_name)
  environment_name                    = local.is_dev ? "${local.current_user}-${var.environment}" : var.environment
  service_environment_name            = local.is_dev ? "${var.service_name}-${local.current_user}-${var.environment}" : "${var.service_name}-${var.environment}"
  current_user                        = local.is_dev && length(data.azuread_user.current_user) > 0 ? split(".", split("_", split("#EXT#", data.azuread_user.current_user[0].mail_nickname)[0])[0])[0] : ""
  has_cosmos                          = length({ for microservice in var.microservices : microservice.name => microservice if microservice.cosmos_containers != null ? length(microservice.cosmos_containers) > 0 : false }) > 0
  has_sql_server_elastic              = length({ for microservice in var.microservices : microservice.name => microservice if microservice.sql == "elastic" }) > 0
  has_sql_server                      = local.has_sql_server_elastic || length({ for microservice in var.microservices : microservice.name => microservice if microservice.sql == "server" }) > 0
  has_appservice_plan                 = length({ for microservice in var.microservices : microservice.name => microservice if microservice.appservice == "plan" || microservice.function == "plan" }) > 0
  has_consumption_appservice_plan     = length({ for microservice in var.microservices : microservice.name => microservice if microservice.appservice == "consumption" || microservice.function == "consumption" }) > 0
  appservice_plan_regions             = local.has_appservice_plan ? var.regions : []
  consumption_appservice_plan_regions = local.has_appservice_plan ? var.regions : []
  sql_server_regions                  = local.has_sql_server ? var.regions : []
  admin_login                         = "${var.service_name}-admin"
}

#################################
#### Shared Global Resources ####
#################################

resource "azurerm_resource_group" "service" {
  name     = local.service_environment_name
  location = local.primary_region
  tags     = var.resource_group_tags
}

resource "azurerm_application_insights" "service" {
  name                = local.service_environment_name
  location            = local.primary_region
  resource_group_name = azurerm_resource_group.service.name
  retention_in_days   = local.retention_in_days
  application_type    = "web"


  # these tags will be needed to link the application insights with the azure functions 
  # more details available here: https://github.com/terraform-providers/terraform-provider-azurerm/issues/1303
  # stackoverflow here: https://stackoverflow.com/questions/60175600/how-to-associate-an-azure-app-service-with-an-application-insights-resource-new
  #
  #   tags = {
  #     "hidden-link:/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.service.name}/providers/Microsoft.Web/sites/${local.function_app_name}" = "Resource"
  #   }

}

resource "azurerm_key_vault" "service" {
  name                        = local.service_environment_name
  location                    = local.primary_region
  resource_group_name         = azurerm_resource_group.service.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_enabled         = true
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "set",
      "get",
      "delete",
      "purge",
      "recover"
    ]
  }

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

resource "azurerm_cosmosdb_account" "service" {
  count               = local.has_cosmos ? 1 : 0
  name                = local.service_environment_name
  resource_group_name = azurerm_resource_group.service.name
  location            = local.primary_region
  offer_type          = "Standard"
  # todo: multi-region flag?
  enable_automatic_failover = true

  #is_virtual_network_filter_enabled = true
  #ip_range_filter = var.cosmos_db_ip_range_filter

  consistency_policy {
    consistency_level = "Strong"
  }

  dynamic "geo_location" {
    for_each = var.regions

    content {
      location          = geo_location.value
      failover_priority = geo_location.value == local.primary_region ? 0 : 1
    }
  }
}

resource "azurerm_cosmosdb_sql_database" "service" {
  count               = local.has_cosmos ? 1 : 0
  name                = var.cosmos_database_name == "" ? local.service_name : var.cosmos_database_name
  resource_group_name = azurerm_resource_group.service.name
  account_name        = azurerm_cosmosdb_account.service[0].name

  autoscale_settings {
    max_throughput = var.cosmos_autoscale_max_throughput
  }
}

###################################
#### Shared Regional Resources ####
###################################

resource "azurerm_storage_account" "service" {
  for_each = toset(var.regions)

  name                     = "${var.service_name}${each.key}${var.environment}"
  resource_group_name      = azurerm_resource_group.service.name
  location                 = each.key
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
}

#### SQL Server

resource "random_password" "sql_admin_password" {
  length  = 16
  special = false
}

resource "azurerm_key_vault_secret" "sql_admin_login" {
  count        = local.has_sql_server ? 1 : 0
  name         = "sql-admin-login"
  value        = local.admin_login
  key_vault_id = azurerm_key_vault.service.id
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  count        = local.has_sql_server ? 1 : 0
  name         = "sql-admin-password"
  value        = random_password.sql_admin_password.result
  key_vault_id = azurerm_key_vault.service.id
}

resource "azurerm_mssql_server" "service" {
  for_each = toset(local.sql_server_regions)

  name                         = "mssqlserver"
  resource_group_name          = azurerm_resource_group.service.name
  location                     = each.key
  version                      = "12.0"
  administrator_login          = local.admin_login
  administrator_login_password = random_password.sql_admin_password.result
  minimum_tls_version          = "1.2"

  #   azuread_administrator {
  #     login_username = "AzureAD Admin"
  #     object_id      = "00000000-0000-0000-0000-000000000000"
  #   }

  extended_auditing_policy {
    storage_endpoint                        = azurerm_storage_account.service[each.key].primary_blob_endpoint
    storage_account_access_key              = azurerm_storage_account.service[each.key].primary_access_key
    storage_account_access_key_is_secondary = true
    retention_in_days                       = 6
  }
}

#### App Service Plan

resource "azurerm_app_service_plan" "service" {
  for_each = toset(local.appservice_plan_regions)

  name                = "${var.service_name}${each.key}${var.environment}"
  location            = each.key
  resource_group_name = azurerm_resource_group.service.name
  #per_site_scaling    = true

  sku {
    tier = var.appservice_plan_tier
    size = var.appservice_plan_size
  }
}

resource "azurerm_app_service_plan" "service_consumption" {
  for_each = toset(local.consumption_appservice_plan_regions)

  name                = "${var.service_name}dyn${each.key}${var.environment}"
  location            = each.key
  resource_group_name = azurerm_resource_group.service.name

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_app_service_plan" "service_consumption_function" {
  for_each = toset(local.consumption_appservice_plan_regions)

  name                = "${var.service_name}dynfunc${each.key}${var.environment}"
  location            = each.key
  resource_group_name = azurerm_resource_group.service.name
  kind                = "FunctionApp"

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

################################
#### Microservice Resources ####
################################

module "microservice" {
  source   = "./modules/microservice"
  for_each = { for microservice in var.microservices : microservice.name => microservice }

  name              = each.value.name
  appservice        = each.value.appservice
  function          = each.value.function
  sql               = each.value.sql
  cosmos_containers = each.value.cosmos_containers == null ? [] : each.value.cosmos_containers

  #   cosmos_containers = each.value.cosmos_containers == null ? [] : [for container in each.value.cosmos_containers : {
  #     name               = container.name
  #     partition_key_path = container.partition_key_path
  #     max_throughput     = container.max_throughput
  #   }]

  resource_group_name                   = azurerm_resource_group.service.name
  environment_name                      = local.environment_name
  application_insights                  = azurerm_application_insights.service
  storage_accounts                      = azurerm_storage_account.service
  cosmosdb_account_name                 = local.has_cosmos ? azurerm_cosmosdb_account.service[0].name : null
  cosmosdb_sql_database_name            = local.has_cosmos ? azurerm_cosmosdb_sql_database.service[0].name : null
  cosmos_autoscale_max_throughput       = var.cosmos_autoscale_max_throughput
  appservice_plans                      = azurerm_app_service_plan.service
  consumption_appservice_plans          = azurerm_app_service_plan.service_consumption
  consumption_function_appservice_plans = azurerm_app_service_plan.service_consumption_function
}

#######################
#### Output Values ####
#######################

output "current_azurerm" {
  value = data.azurerm_client_config.current
}

output "current_user" {
  #value = local.is_dev && length(data.azuread_user.current_user) > 0 ? data.azuread_user.current_user[0].mail_nickname : ""
  value = data.azuread_user.current_user
}

output "locals" {
  value = {
    is_dev                   = local.is_dev
    primary_region           = local.primary_region
    service_name             = local.service_name
    service_environment_name = local.service_environment_name
    current_user             = local.current_user
    has_cosmos               = local.has_cosmos
    has_appservice_plan      = local.has_appservice_plan
  }
}

output "azurerm_app_service_plan_service" {
  value = azurerm_app_service_plan.service
}

output "microservices" {
  value = module.microservice
}
