terraform {
  required_version = ">= 0.14"
  experiments      = [module_variable_optional_attrs]

  required_providers {
    azurerm = {
      version = ">= 2.0.0"
      source  = "hashicorp/azurerm"
    }
  }
}

provider "azurerm" {
  use_msi                    = var.use_msi_to_authenticate
  environment                = var.azure_environment
  skip_provider_registration = true
  features {
    key_vault {
      recover_soft_deleted_key_vaults = true
      purge_soft_delete_on_destroy    = true
    }
  }
}

provider "random" {}

module "region_to_short_region" {
  count = var.use_region_shortcodes ? 1 : 0

  source = "./modules/region-to-short-region"
}

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

data "azuread_domains" "default" {
  only_default = true
}

data "azuread_users" "owners" {
  user_principal_names = var.application_owner_user_principal_names
  ignore_missing       = true
}

data "azuread_group" "owner_groups" {
  for_each  = zipmap(var.application_owner_group_object_ids, var.application_owner_group_object_ids)
  object_id = each.value
}

data "azuread_users" "owner_groups_users" {
  object_ids     = flatten([for item in data.azuread_group.owner_groups : item.members])
  ignore_missing = true
}

locals {
  azuread_domain                           = data.azuread_domains.default.domains[0].domain_name
  primary_region                           = var.primary_region != "" ? var.primary_region : var.regions[0]
  secondary_region                         = var.secondary_region != "" ? var.secondary_region : length(var.regions) > 1 ? var.regions[1] : null
  short_regions                            = var.use_region_shortcodes ? [ for region in var.regions: lookup(module.region_to_short_region[0].mapping, region, null) ] : []
  service_name                             = lower(var.service_name)
  executing_object_id                      = data.azurerm_client_config.current.object_id != null && data.azurerm_client_config.current.object_id != "" ? data.azurerm_client_config.current.object_id : var.executing_object_id
  environment_name                         = local.is_dev ? "${local.environment_differentiator}-${var.environment}" : var.environment
  service_environment_name                 = local.is_dev ? "${var.service_name}-${local.environment_differentiator}-${var.environment}" : "${var.service_name}-${var.environment}"
  environment_differentiator               = var.environment_differentiator != "" ? var.environment_differentiator : local.is_dev && length(data.azuread_user.current_user) > 0 ? replace(split(".", split("_", split("#EXT#", data.azuread_user.current_user[0].mail_nickname)[0])[0])[0], "-", "") : ""
  has_cosmos                               = length({ for microservice in var.microservices : microservice.name => microservice if microservice.cosmos_containers != null ? length(microservice.cosmos_containers) > 0 : false }) > 0
  has_queues                               = length({ for microservice in var.microservices : microservice.name => microservice if microservice.queues != null ? length(microservice.queues) > 0 : false }) > 0
  has_sql_server_elastic                   = length({ for microservice in var.microservices : microservice.name => microservice if microservice.sql == "elastic" }) > 0
  has_sql_server                           = local.has_sql_server_elastic || length({ for microservice in var.microservices : microservice.name => microservice if microservice.sql == "server" }) > 0
  has_appservice_plan                      = var.exclude_hosts ? false : length({ for microservice in var.microservices : microservice.name => microservice if microservice.appservice == "plan" || microservice.function == "plan" }) > 0
  has_consumption_appservice_plan          = var.exclude_hosts ? false : length({ for microservice in var.microservices : microservice.name => microservice if microservice.function == "consumption" }) > 0
  servicebus_regions                       = local.has_queues ? lower(var.servicebus_sku) == "premium" ? var.regions : [local.primary_region] : []
  appservice_plan_regions                  = local.has_appservice_plan ? var.regions : []
  consumption_appservice_plan_regions      = local.has_consumption_appservice_plan ? var.regions : []
  sql_server_regions                       = local.has_sql_server ? local.secondary_region != null ? [local.primary_region, local.secondary_region] : [local.primary_region] : []
  sql_server_elastic_regions               = local.has_sql_server_elastic ? local.sql_server_regions : []
  admin_login                              = "${var.service_name}-admin"
  has_sql_admin                            = var.sql_azuread_administrator != ""
  key_vault_developer_user_principal_names = local.is_dev ? var.key_vault_developer_user_principal_names : []
  has_key_vault_developers                 = length(local.key_vault_developer_user_principal_names) > 0

  include_ip_address = var.key_vault_include_ip_address == null ? local.is_dev : var.key_vault_include_ip_address == true
  lookup_ip_address  = local.include_ip_address && var.ip_address == ""

  azure_easyauth_callback = "/.auth/login/aad/callback"

  owner_group_members = data.azuread_users.owner_groups_users != null ? tolist(data.azuread_users.owner_groups_users.object_ids) : []
  application_owners  = distinct(concat(local.owner_group_members, data.azuread_users.owners.object_ids, [local.executing_object_id]))


  # 24 characters is used for max storage name
  max_storage_name_length              = 24
  max_short_region_length              = var.use_region_shortcodes ? reverse(sort([for region in local.short_regions : length(region)]))[0] : 0 # bug is preventing max() from working used sort and reverse instead
  max_long_region_length               = reverse(sort([for region in var.regions : length(region)]))[0] # bug is preventing max() from working used sort and reverse instead
  max_region_length                    = var.use_region_shortcodes ? local.max_short_region_length : local.max_long_region_length
  max_environment_differentiator_short = local.max_storage_name_length - (length(local.service_name) + local.max_region_length + length(var.environment))
  environment_differentiator_short     = local.max_environment_differentiator_short > 0 ? length(local.environment_differentiator) <= local.max_environment_differentiator_short ? local.environment_differentiator : substr(local.environment_differentiator, 0, local.max_environment_differentiator_short) : ""

  # 24 characters is used for max key vault name
  max_environment_differentiator_short2 = local.max_storage_name_length - (length(local.service_name) + length(var.environment) + 2)
  environment_differentiator_short2     = local.max_environment_differentiator_short2 > 0 ? length(local.environment_differentiator) <= local.max_environment_differentiator_short2 ? local.environment_differentiator : substr(local.environment_differentiator, 0, local.max_environment_differentiator_short2) : ""
}

data "azuread_users" "key_vault_users" {
  count = local.has_key_vault_developers ? 1 : 0

  user_principal_names = local.key_vault_developer_user_principal_names
}

locals {
  key_vault_user_ids = local.has_key_vault_developers ? data.azuread_users.key_vault_users[0].object_ids : []
}

# Commenting out the external http request dependency in favor of powershell method for looking up IP
# Leaving this in as it might be beneficial to offer different ip retrieval approaches depending on environment (will powershell be available?)

# # Getting current IP Address, only used for dev environment
# # solution from here: https://stackoverflow.com/a/58959164/1362146
# data "http" "my_public_ip" {
#   count = local.is_dev ? 1 : 0

#   # url = "https://ifconfig.co/json"
#   # request_headers = {
#   #   Accept = "application/json"
#   # }

#   url = "https://ipinfo.io/ip"
# }

data "external" "current_ipv4" {
  count = local.lookup_ip_address ? 1 : 0

  program = ["Powershell.exe", "${path.module}/scripts/Get-CurrentIpV4.ps1"]
}

locals {
  # http_my_public_ip_response = jsondecode(data.http.my_public_ip[0].body)
  # current_ip                 = local.is_dev ? local.http_my_public_ip_response.ip : null

  # http_my_public_ip_response = chomp(data.http.my_public_ip[0].body)
  # current_ip                 = local.is_dev ? local.http_my_public_ip_response : null

  # the current_ip is only retrieved and set for the dev environment to simplify developer workflow

  #key_vault_ip_rules = local.is_dev ? var.ip_address != "" ? ["${var.ip_address}/32"] : ["${data.external.current_ipv4[0].result.ip_address}/32"] : null
  external_ip_address = local.lookup_ip_address ? ["${data.external.current_ipv4[0].result.ip_address}/32"] : null
  current_ip_address  = local.include_ip_address ? coalesce(local.external_ip_address, ["${var.ip_address}/32"]) : null
  key_vault_network_acls = var.key_vault_network_acls != null ? {
    default_action             = var.key_vault_network_acls.default_action
    bypass                     = var.key_vault_network_acls.bypass
    ip_rules                   = local.include_ip_address ? concat(coalesce(local.current_ip_address, []), coalesce(var.key_vault_network_acls.ip_rules, [])) : var.key_vault_network_acls.ip_rules
    virtual_network_subnet_ids = var.key_vault_network_acls.virtual_network_subnet_ids
    } : local.include_ip_address ? {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    ip_rules                   = local.current_ip_address
    virtual_network_subnet_ids = null
  } : null
}

#################################
#### Shared Global Resources ####
#################################

### Ensure Subcription has required providers

# Need to have an option to add providers that don't exist without tracking them

# locals {
#   required_providers = [
#     "Microsoft.ManagedIdentity"
#   ]
# }

# resource "azurerm_resource_provider_registration" "microservice" {
#   for_each = toset(local.required_providers)

#   name = each.value
# }

locals {
  create_resource_group = var.resource_group_name == ""
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.service[0].name : var.resource_group_name
}

resource "azurerm_resource_group" "service" {
  count = local.create_resource_group ? 1 : 0

  name     = var.resource_group_name_override == "" ? local.service_environment_name : var.resource_group_name_override
  location = local.primary_region
  tags     = var.resource_group_tags
}

resource "azurerm_application_insights" "service" {
  name                = local.service_environment_name
  location            = local.primary_region
  resource_group_name = local.resource_group_name
  retention_in_days   = var.retention_in_days
  application_type    = var.application_insights_application_type

  # these tags might be needed to link the application insights with the azure functions (seems to be linking correctly without)
  # more details available here: https://github.com/terraform-providers/terraform-provider-azurerm/issues/1303
  # stackoverflow here: https://stackoverflow.com/questions/60175600/how-to-associate-an-azure-app-service-with-an-application-insights-resource-new
  #
  #   tags = {
  #     "hidden-link:/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${local.resource_group_name}/providers/Microsoft.Web/sites/${local.function_app_name}" = "Resource"
  #   }

}

resource "azurerm_cosmosdb_account" "service" {
  count                     = local.has_cosmos ? 1 : 0
  name                      = local.service_environment_name
  resource_group_name       = local.resource_group_name
  location                  = local.primary_region
  offer_type                = "Standard"
  enable_free_tier          = var.cosmos_enable_free_tier
  enable_automatic_failover = var.cosmos_enable_automatic_failover

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
  resource_group_name = local.resource_group_name
  account_name        = azurerm_cosmosdb_account.service[0].name

  autoscale_settings {
    max_throughput = var.cosmos_autoscale_max_throughput
  }
}

resource "azurerm_key_vault" "service" {
  name                        = local.environment_differentiator_short2 != "" ? "${local.service_name}-${local.environment_differentiator_short2}-${var.environment}" : "${local.service_name}-${var.environment}"
  location                    = local.primary_region
  resource_group_name         = local.resource_group_name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = var.retention_in_days
  purge_protection_enabled    = false
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = local.executing_object_id

    certificate_permissions = var.key_vault_permissions.certificate_permissions
    key_permissions         = var.key_vault_permissions.key_permissions
    secret_permissions      = var.key_vault_permissions.secret_permissions
    storage_permissions     = var.key_vault_permissions.storage_permissions
  }

  dynamic "network_acls" {
    for_each = local.key_vault_network_acls != null ? [local.key_vault_network_acls] : []

    content {
      default_action             = local.key_vault_network_acls.default_action
      bypass                     = local.key_vault_network_acls.bypass
      ip_rules                   = local.key_vault_network_acls.ip_rules
      virtual_network_subnet_ids = local.key_vault_network_acls.virtual_network_subnet_ids
    }
  }
}

###################################
#### Shared Regional Resources ####
###################################

resource "azurerm_storage_account" "service" {
  for_each = toset(var.regions)

  name                     = format("${local.service_name}%s${local.environment_differentiator_short}${var.environment}", 
                               var.use_region_shortcodes ? lookup(module.region_to_short_region[0].mapping, each.key, null) : each.key
                             )
  resource_group_name      = local.resource_group_name
  location                 = each.key
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
}

#### Service Bus

resource "azurerm_servicebus_namespace" "service" {
  for_each = toset(local.servicebus_regions)

  name                = format("${local.service_name}%s${local.environment_name}", 
                          var.use_region_shortcodes ? lookup(module.region_to_short_region[0].mapping, each.key, null) : each.key
                        )
  resource_group_name = local.resource_group_name
  location            = each.key
  sku                 = var.servicebus_sku
}

# Pairing for geo redundancy is not yet supported by terraform provider
# Open issue here: https://github.com/terraform-providers/terraform-provider-azurerm/issues/3136

#### SQL Server

resource "random_password" "sql_admin_password" {
  count            = local.has_sql_server ? 1 : 0
  length           = 32
  min_special      = 1
  min_numeric      = 1
  min_upper        = 2
  min_lower        = 2
  special          = true
  override_special = "!#%_-"
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
  value        = random_password.sql_admin_password[0].result
  key_vault_id = azurerm_key_vault.service.id
}

resource "azuread_group" "sql_admin" {
  count        = local.has_sql_server && !local.has_sql_admin ? 1 : 0
  display_name = "${local.admin_login}-sql"
}
locals {
  sql_azuread_administrator = length(azuread_group.sql_admin) == 0 ? var.sql_azuread_administrator : azuread_group.sql_admin[0].id
}

resource "azurerm_mssql_server" "service" {
  for_each = toset(local.sql_server_regions)

  name                         = format("${local.service_name}%s${local.environment_name}", 
                                   var.use_region_shortcodes ? lookup(module.region_to_short_region[0].mapping, each.key, null) : each.key
                                 )
  resource_group_name          = local.resource_group_name
  location                     = each.key
  administrator_login          = local.admin_login
  administrator_login_password = random_password.sql_admin_password[0].result
  version                      = var.sql_version
  minimum_tls_version          = var.sql_minimum_tls_version

  azuread_administrator {
    login_username = "AzureAD Admin"
    object_id      = local.sql_azuread_administrator
  }

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
  resource_group_name = local.resource_group_name
  location            = each.key
  server_name         = azurerm_mssql_server.service[each.key].name
  max_size_gb         = var.sql_elasticpool_max_size_gb

  sku {
    name     = var.sql_elasticpool_sku.name
    tier     = var.sql_elasticpool_sku.tier
    family   = var.sql_elasticpool_sku.family
    capacity = var.sql_elasticpool_sku.capacity
  }

  per_database_settings {
    min_capacity = var.sql_elasticpool_per_database_settings.min_capacity
    max_capacity = var.sql_elasticpool_per_database_settings.max_capacity
  }
}

#### App Service Plan

resource "azurerm_app_service_plan" "service" {
  for_each = toset(local.appservice_plan_regions)

  name                = format("${local.service_name}-%s-${local.environment_name}", 
                          var.use_region_shortcodes ? lookup(module.region_to_short_region[0].mapping, each.key, null) : each.key
                        )
  location            = each.key
  resource_group_name = local.resource_group_name
  #per_site_scaling    = true

  sku {
    tier = var.appservice_plan_tier
    size = var.appservice_plan_size
  }
}

resource "azurerm_app_service_plan" "service_consumption" {
  for_each = toset(local.consumption_appservice_plan_regions)

  name                = format("${local.service_name}-dyn-%s-${local.environment_name}", 
                          var.use_region_shortcodes ? lookup(module.region_to_short_region[0].mapping, each.key, null) : each.key
                        )
  location            = each.key
  resource_group_name = local.resource_group_name
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
  service_name                    = local.service_name
  azuread_domain                  = local.azuread_domain
  azuread_instance                = var.azuread_instance
  azure_environment               = var.azure_environment
  environment                     = var.environment
  environment_differentiator      = local.environment_differentiator
  create_appsettings              = var.create_appsettings
  appsettings_path                = var.appsettings_path
  appservice                      = each.value.appservice
  function                        = each.value.function
  require_auth                    = each.value.require_auth == null ? false : each.value.require_auth
  application_owners              = local.application_owners
  application_permissions         = each.value.application_permissions
  sql                             = each.value.sql
  roles                           = each.value.roles
  http                            = each.value.http
  scopes                          = each.value.scopes
  cosmos_containers               = each.value.cosmos_containers == null ? [] : each.value.cosmos_containers
  queues                          = each.value.queues == null ? [] : each.value.queues
  resource_group_name             = local.resource_group_name
  retention_in_days               = var.retention_in_days
  primary_region                  = local.primary_region
  secondary_region                = local.secondary_region
  use_region_shortcodes           = var.use_region_shortcodes
  environment_name                = local.environment_name
  callback_path                   = each.value.function != null ? local.azure_easyauth_callback : var.callback_path
  signed_out_callback_path        = var.signed_out_callback_path
  key_vault_user_ids              = local.key_vault_user_ids
  key_vault_permissions           = var.key_vault_permissions
  key_vault_network_acls          = local.key_vault_network_acls
  azurerm_client_config           = data.azurerm_client_config.current
  executing_object_id             = local.executing_object_id
  application_insights            = azurerm_application_insights.service
  storage_accounts                = azurerm_storage_account.service
  sql_servers                     = local.has_sql_server ? azurerm_mssql_server.service : null
  sql_elastic_pools               = local.has_sql_server_elastic ? azurerm_mssql_elasticpool.service : null
  sql_database_collation          = var.sql_database_collation
  sql_database_sku                = var.sql_database_sku
  cosmosdb_account_name           = local.has_cosmos ? azurerm_cosmosdb_account.service[0].name : null
  cosmosdb_sql_database_name      = local.has_cosmos ? azurerm_cosmosdb_sql_database.service[0].name : null
  cosmosdb_endpoint               = local.has_cosmos ? azurerm_cosmosdb_account.service[0].endpoint : null
  cosmosdb_primary_key            = local.has_cosmos ? azurerm_cosmosdb_account.service[0].primary_key : null
  cosmos_autoscale_max_throughput = var.cosmos_autoscale_max_throughput
  servicebus_namespaces           = azurerm_servicebus_namespace.service
  appservice_plans                = azurerm_app_service_plan.service
  appservice_deployment_slots     = var.appservice_deployment_slots
  consumption_appservice_plans    = azurerm_app_service_plan.service_consumption
  static_site = each.value.static_site != null ? {
    index_document           = each.value.static_site.index_document
    error_document           = each.value.static_site.error_document
    domain                   = each.value.static_site.domain
    storage_kind             = var.static_site_kind
    storage_tier             = var.static_site_tier
    storage_replication_type = var.static_site_replication_type
    storage_tls_version      = var.static_site_tls_version
  } : null

  depends_on = [
    azurerm_storage_account.service,
    azurerm_servicebus_namespace.service,
    azurerm_cosmosdb_sql_database.service,
    azurerm_mssql_elasticpool.service,
    azurerm_app_service_plan.service,
    azurerm_app_service_plan.service_consumption
  ]
}

resource "time_sleep" "delay_before_traffic" {
  depends_on = [
    module.microservice
  ]

  create_duration  = "30s"
  destroy_duration = "30s"
}

# traffic module was moved to it's own module to reduce/prevent intermittent conflict errors between app services, app functions, slots, and traffic manager
module "microservice_traffic" {
  source   = "./modules/traffic"
  for_each = var.exclude_hosts ? {} : module.microservice

  name                     = each.value.traffic_data.microservice_environment_name
  resource_group_name      = local.resource_group_name
  azure_endpoint_resources = each.value.traffic_data.azure_endpoint_resources

  depends_on = [
    module.microservice,
    time_sleep.delay_before_traffic
  ]
}

#### SQL Failover with all database ids from microservices

resource "azurerm_sql_failover_group" "service" {
  count = local.has_sql_server && length(var.regions) > 1 ? 1 : 0

  name                = local.service_environment_name
  resource_group_name = local.resource_group_name
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

#### Create JSON files

locals {
  appsettings = var.create_appsettings ? merge(
    {
      ApplicationInsights = {
        InstrumentationKey = azurerm_application_insights.service.instrumentation_key
      }
    },
    local.has_queues ? {
      ServiceBus = {
        ConnectionString = "Endpoint=sb://${azurerm_servicebus_namespace.service[local.primary_region].name}.servicebus.windows.net/;Authentication=Managed Identity"
      }
    } : {},
    local.has_cosmos ? {
      Cosmos = {
        BaseUri      = azurerm_cosmosdb_account.service[0].endpoint
        DatabaseName = azurerm_cosmosdb_sql_database.service[0].name
      }
    } : {}
  ) : null
}


resource "null_resource" "service_json_file" {
  count = var.create_appsettings ? 1 : 0

  triggers = {
    trigger = uuid()
  }

  provisioner "local-exec" {
    command     = ".'${path.module}/scripts/Write-AppSettings.ps1' '${jsonencode(local.appsettings)}' '${var.appsettings_path}${local.service_name}.machineSettings.json'"
    interpreter = ["PowerShell", "-Command"]
  }
}

resource "null_resource" "microservice_json_file" {
  for_each = var.create_appsettings ? module.microservice : {}

  triggers = {
    trigger = uuid()
  }

  provisioner "local-exec" {
    command     = ".'${path.module}/scripts/Write-AppSettings.ps1' '${jsonencode(each.value.appsettings)}' '${var.appsettings_path}${var.service_name}.${each.value.name}.appSettings.json'"
    interpreter = ["PowerShell", "-Command"]
  }
}
