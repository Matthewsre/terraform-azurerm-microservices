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

#########################
#### Locals and Data ####
#########################

locals {
  is_dev = lower(var.environment) == "dev"
  #has_appservice_plan    = length([for microservice in var.microservices : microservice if microservice.appservice == "plan" || microservice.function == "plan"]) > 0
  #has_sql_server_elastic = length([for microservice in var.microservices : microservice if microservice.sql == "elastic"]) > 0
  #has_sql_server         = length([for microservice in var.microservices : microservice if microservice.sql == "server"]) > 0
  #has_appservice_plan = for microservice in var.microservices [{id="i-123",zone="us-west"},{id="i-abc",zone="us-east"}]: x.id if x.zone == "us-east"
}

data "azurerm_client_config" "current" {}

data "azuread_user" "current_user" {
  count     = local.is_dev ? 1 : 0
  object_id = data.azurerm_client_config.current.object_id
}

locals {
  primary_region           = var.primary_region != "" ? var.primary_region : var.regions[0]
  retention_in_days        = 90
  service_name             = lower(var.service_name)
  service_environment_name = local.is_dev ? "${var.service_name}-${local.current_user}-${var.environment}" : "${var.service_name}-${var.environment}"
  current_user             = local.is_dev && length(data.azuread_user.current_user) > 0 ? split(".", split("_", split("#EXT#", data.azuread_user.current_user[0].mail_nickname)[0])[0])[0] : ""
  #resource_group_name     = local.isDev ? "${var.service_name}-${local.current_user}-${var.environment}" : "${var.service_name}-${var.environment}"
  #service_name        = local.isDev ? "${var.microservice_name}-${var.environment}" : "${var.microservice_name}-${var.environment}"
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
}

resource "azurerm_cosmosdb_account" "service" {
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
  name                = var.cosmos_database_name == "" ? local.service_name : var.cosmos_database_name
  resource_group_name = azurerm_resource_group.service.name
  account_name        = azurerm_cosmosdb_account.service.name

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

################################
#### Microservice Resources ####
################################

module "microservice" {
  source   = "./modules/microservice"
  for_each = { for microservice in var.microservices : microservice.name => microservice }
  #for_each = toset(var.microservices)

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

  resource_group_name             = azurerm_resource_group.service.name
  cosmosdb_account_name           = azurerm_cosmosdb_account.service.name
  cosmosdb_sql_database_name      = azurerm_cosmosdb_sql_database.service.name
  cosmos_autoscale_max_throughput = var.cosmos_autoscale_max_throughput
}

############################
#### Output Values
############################

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
  }
}

output "microservices" {
  value = module.microservice
}
