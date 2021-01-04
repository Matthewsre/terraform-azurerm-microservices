terraform {
  required_version = ">= 0.14"
  experiments      = [module_variable_optional_attrs]
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
  secondary_region                    = var.secondary_region != "" ? var.secondary_region : length(var.regions) > 1 ? var.regions[1] : null
  service_name                        = lower(var.service_name)
  environment_name                    = local.is_dev ? "${local.environment_differentiator}-${var.environment}" : var.environment
  service_environment_name            = local.is_dev ? "${var.service_name}-${local.environment_differentiator}-${var.environment}" : "${var.service_name}-${var.environment}"
  environment_differentiator          = var.environment_differentiator != "" ? var.environment_differentiator : local.is_dev && length(data.azuread_user.current_user) > 0 ? split(".", split("_", split("#EXT#", data.azuread_user.current_user[0].mail_nickname)[0])[0])[0] : ""
  has_cosmos                          = length({ for microservice in var.microservices : microservice.name => microservice if microservice.cosmos_containers != null ? length(microservice.cosmos_containers) > 0 : false }) > 0
  has_queues                          = length({ for microservice in var.microservices : microservice.name => microservice if microservice.queues != null ? length(microservice.queues) > 0 : false }) > 0
  has_sql_server_elastic              = length({ for microservice in var.microservices : microservice.name => microservice if microservice.sql == "elastic" }) > 0
  has_sql_server                      = local.has_sql_server_elastic || length({ for microservice in var.microservices : microservice.name => microservice if microservice.sql == "server" }) > 0
  has_appservice_plan                 = length({ for microservice in var.microservices : microservice.name => microservice if microservice.appservice == "plan" || microservice.function == "plan" }) > 0
  has_consumption_appservice_plan     = length({ for microservice in var.microservices : microservice.name => microservice if microservice.function == "consumption" }) > 0
  servicebus_regions                  = local.has_queues ? var.regions : []
  appservice_plan_regions             = local.has_appservice_plan ? var.regions : []
  consumption_appservice_plan_regions = local.has_consumption_appservice_plan ? var.regions : []
  sql_server_regions                  = local.has_sql_server ? local.secondary_region != null ? [local.primary_region, local.secondary_region] : [local.primary_region] : []
  sql_server_elastic_regions          = local.has_sql_server_elastic ? local.sql_server_regions : []
  admin_login                         = "${var.service_name}-admin"

  # if this becomes a problem can standardize envrionments to be 3 char (dev, tst, ppe, prd)
  # 24 characters is used for max storage name
  max_storage_name_length              = 24
  max_region_length                    = reverse(sort([for region in var.regions : length(region)]))[0] # bug is preventing max() from working used sort and reverse instead
  max_environment_differentiator_short = local.max_storage_name_length - (length(local.service_name) + local.max_region_length + length(var.environment))
  environment_differentiator_short     = local.max_environment_differentiator_short > 0 ? length(local.environment_differentiator) <= local.max_environment_differentiator_short ? local.environment_differentiator : substr(local.environment_differentiator, 0, local.max_environment_differentiator_short) : ""
}

# Getting current IP Address, only used for dev environment
# solution from here: https://stackoverflow.com/a/58959164/1362146
data "http" "my_public_ip" {
  count = local.is_dev ? 1 : 0

  url = "https://ifconfig.co/json"
  request_headers = {
    Accept = "application/json"
  }
}

locals {
  http_my_public_ip_response = jsondecode(data.http.my_public_ip[0].body)
  current_ip                 = local.is_dev ? local.http_my_public_ip_response.ip : null

  # the current_ip is only retrieved and set for the dev environment to simplify developer workflow
  key_vault_ip_rules = local.is_dev ? ["${local.current_ip}/32"] : null
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
  retention_in_days   = var.retention_in_days
  application_type    = "web"


  # these tags might be needed to link the application insights with the azure functions (seems to be linking correctly without)
  # more details available here: https://github.com/terraform-providers/terraform-provider-azurerm/issues/1303
  # stackoverflow here: https://stackoverflow.com/questions/60175600/how-to-associate-an-azure-app-service-with-an-application-insights-resource-new
  #
  #   tags = {
  #     "hidden-link:/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.service.name}/providers/Microsoft.Web/sites/${local.function_app_name}" = "Resource"
  #   }

}

resource "azurerm_cosmosdb_account" "service" {
  count                     = local.has_cosmos ? 1 : 0
  name                      = local.service_environment_name
  resource_group_name       = azurerm_resource_group.service.name
  location                  = local.primary_region
  offer_type                = "Standard"
  enable_automatic_failover = true

  consistency_policy {
    consistency_level = "Strong"
  }

  dynamic "geo_location" {
    for_each = var.regions

    content {
      location          = geo_location.value
      failover_priority = index(var.regions, geo_location.value)
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

resource "azurerm_key_vault" "service" {
  name                        = local.service_environment_name
  location                    = local.primary_region
  resource_group_name         = azurerm_resource_group.service.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_enabled         = true
  soft_delete_retention_days  = var.retention_in_days
  purge_protection_enabled    = false
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    certificate_permissions = var.key_vault_permissions.certificate_permissions
    key_permissions         = var.key_vault_permissions.key_permissions
    secret_permissions      = var.key_vault_permissions.secret_permissions
    storage_permissions     = var.key_vault_permissions.storage_permissions
  }

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = local.key_vault_ip_rules
  }
}

###################################
#### Shared Regional Resources ####
###################################

resource "azurerm_storage_account" "service" {
  for_each = toset(var.regions)

  name                     = "${local.service_name}${each.key}${local.environment_differentiator_short}${var.environment}"
  resource_group_name      = azurerm_resource_group.service.name
  location                 = each.key
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
}

#### Service Bus

resource "azurerm_servicebus_namespace" "service" {
  for_each = toset(local.servicebus_regions)

  name                = "${local.service_name}${each.key}${local.environment_name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = each.key
  sku                 = "Standard"
}

# Pairing for geo redundancy is not yet supported by terraform provider
# Open issue here: https://github.com/terraform-providers/terraform-provider-azurerm/issues/3136

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

  name                         = "${local.service_name}${each.key}${local.environment_name}"
  resource_group_name          = azurerm_resource_group.service.name
  location                     = each.key
  version                      = "12.0"
  administrator_login          = local.admin_login
  administrator_login_password = random_password.sql_admin_password.result
  minimum_tls_version          = "1.2"

  #TODO: determine if we should  set the admin
  #   azuread_administrator {
  #     login_username = "AzureAD Admin"
  #     object_id      = "00000000-0000-0000-0000-000000000000"
  #   }

}

resource "azurerm_mssql_server_extended_auditing_policy" "service" {
  for_each = toset(local.sql_server_regions)

  server_id                               = azurerm_mssql_server.service[each.key].id
  storage_endpoint                        = azurerm_storage_account.service[each.key].primary_blob_endpoint
  storage_account_access_key              = azurerm_storage_account.service[each.key].primary_access_key
  storage_account_access_key_is_secondary = false
  retention_in_days                       = var.retention_in_days
}

resource "azurerm_mssql_elasticpool" "service" {
  for_each = toset(local.sql_server_elastic_regions)

  name                = "${local.service_name}-${local.environment_name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = each.key
  server_name         = azurerm_mssql_server.service[each.key].name
  max_size_gb         = 756

  # TODO: move options to input variables with default
  sku {
    name     = "GP_Gen5"
    tier     = "GeneralPurpose"
    family   = "Gen5"
    capacity = 4
  }

  per_database_settings {
    min_capacity = 0.25
    max_capacity = 4
  }
}

#### App Service Plan

resource "azurerm_app_service_plan" "service" {
  for_each = toset(local.appservice_plan_regions)

  name                = "${local.service_name}${each.key}${local.environment_name}"
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

  name                = "${local.service_name}dyn${each.key}${local.environment_name}"
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

  name                            = each.value.name
  appservice                      = each.value.appservice
  function                        = each.value.function
  sql                             = each.value.sql
  roles                           = each.value.roles
  http                            = each.value.http
  cosmos_containers               = each.value.cosmos_containers == null ? [] : each.value.cosmos_containers
  queues                          = each.value.queues == null ? [] : each.value.queues
  resource_group_name             = azurerm_resource_group.service.name
  retention_in_days               = var.retention_in_days
  primary_region                  = local.primary_region
  secondary_region                = local.secondary_region
  environment_name                = local.environment_name
  callback_path                   = var.callback_path
  key_vault_permissions           = var.key_vault_permissions
  key_vault_ip_rules              = local.key_vault_ip_rules
  azurerm_client_config           = data.azurerm_client_config.current
  application_insights            = azurerm_application_insights.service
  storage_accounts                = azurerm_storage_account.service
  sql_server_id                   = local.has_sql_server ? azurerm_mssql_server.service[local.primary_region].id : null
  sql_elastic_pool_id             = local.has_sql_server_elastic ? azurerm_mssql_elasticpool.service[local.primary_region].id : null
  cosmosdb_account_name           = local.has_cosmos ? azurerm_cosmosdb_account.service[0].name : null
  cosmosdb_sql_database_name      = local.has_cosmos ? azurerm_cosmosdb_sql_database.service[0].name : null
  cosmosdb_endpoint               = local.has_cosmos ? azurerm_cosmosdb_account.service[0].endpoint : null
  cosmos_autoscale_max_throughput = var.cosmos_autoscale_max_throughput
  servicebus_namespaces           = azurerm_servicebus_namespace.service
  appservice_plans                = azurerm_app_service_plan.service
  appservice_deployment_slots     = var.appservice_deployment_slots
  consumption_appservice_plans    = azurerm_app_service_plan.service_consumption

  depends_on = [
    azurerm_mssql_elasticpool.service,
    azurerm_app_service_plan.service,
    azurerm_app_service_plan.service_consumption
  ]
}

#### SQL Failover with all database ids from microservices

resource "azurerm_sql_failover_group" "service" {
  count = local.has_sql_server && length(var.regions) > 1 ? 1 : 0

  name                = local.service_environment_name
  resource_group_name = azurerm_resource_group.service.name
  server_name         = azurerm_mssql_server.service[local.primary_region].name

  databases = [for service in module.microservice : service.database_id if service.database_id != null]

  dynamic "partner_servers" {
    for_each = { for server in azurerm_mssql_server.service : server.location => server if server.location != local.primary_region }

    content {
      id = partner_servers.value.id
    }
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60
  }
}
