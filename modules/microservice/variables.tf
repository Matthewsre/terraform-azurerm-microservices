variable "use_msi_to_authenticate" {
  description = "Use a managed service identity to authenticate"
  type        = bool
  default     = false
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "name" {
  description = "Name of the microservice"
  type        = string
}

variable "service_name" {
  description = "Name of the top level service for the microservice"
  type        = string
}

variable "environment_differentiator" {
  description = "Value can be used to allow multiple envrionments."
  type        = string
  default     = ""
}

variable "primary_region" {
  description = "Primary region used for shared resources. If not provided will use first value from 'regions'"
  type        = string
}

variable "secondary_region" {
  description = "Secondary region used for shared resources. If not provided will use second value from 'regions'"
  type        = string
}

variable "retention_in_days" {
  description = "Days set for retention policies"
  type        = number
}

variable "environment" {
  description = "Terrform environment we're acting in"
  type        = string
  validation {
    condition     = contains(["dev", "tst", "ppe", "prd"], lower(var.environment))
    error_message = "Environment must be 'dev', 'tst', 'ppe', or 'prd'."
  }
}

variable "create_appsettings" {
  description = "Enable this to write appsettings json files. This is useful for a dev environment where hosting will be done locally."
  type        = bool
  default     = false
}

variable "appsettings_path" {
  description = "Path to create appsettings json files."
  type        = string
  default     = "C:\\dev\\"
}

variable "environment_name" {
  description = "Name of the environment including differentiator"
  type        = string
}

variable "roles" {
  description = "Roles to provision for the AAD application"
  type        = list(string)
  default     = []
}

variable "callback_path" {
  description = "Callback path for authorization"
  type        = string
}

variable "signed_out_callback_path" {
  description = "Signed out callback path for authorization"
  type        = string
}

variable "appservice" {
  description = "Specify appservice type if used ('plan' or 'consumption')"
  type        = string
  default     = ""
  validation {
    condition     = var.appservice == null ? true : contains(["", "plan"], lower(var.appservice))
    error_message = "Value must be '' or 'plan'."
  }
}

variable "appservice_deployment_slots" {
  description = "Additional deployment slots for app services. Standard and above plans allow for deployment slot."
  type        = list(string)
}

variable "function" {
  description = "Specify function type if used ('plan' or 'consumption')"
  type        = string
  default     = ""
  validation {
    condition     = var.function == null ? true : contains(["", "plan", "consumption"], lower(var.function))
    error_message = "Value must be '', 'plan', or 'consumption'."
  }
}

variable "sql" {
  description = "Specify SQL type if used ('server' or 'elastic')"
  type        = string
  default     = ""
  validation {
    condition     = var.sql == null ? true : contains(["", "server", "elastic"], lower(var.sql))
    error_message = "Value must be '', 'server', or 'elastic'."
  }
}

variable "http" {
  description = "Target option for http traffic manager configuration and optional consumers to request role"
  type = object({
    target    = string
    consumers = optional(list(string))
  })
  default = null
}

variable "azuread_instance" {
  description = "Instance of Azure AD"
  type        = string
  default     = "https://login.microsoftonline.com/"
}

variable "azuread_domain" {
  description = "Instance of Azure AD"
  type        = string
}

variable "sql_servers" {
  description = "SQL Servers to use"
  type = map(object({
    id                          = string
    name                        = string
    location                    = string
    fully_qualified_domain_name = string
  }))
  default = null
}

variable "sql_elastic_pools" {
  description = "SQL Elastic Pools to use"
  type = map(object({
    id       = string
    name     = string
    location = string
  }))
  default = null
}

variable "sql_database_collation" {
  description = "SQL Server default database collation"
  type        = string
  default     = "SQL_Latin1_General_CP1_CI_AS"
}

variable "sql_database_sku" {
  description = "SQL Server default database sku"
  type        = string
  default     = "Basic"
}

variable "cosmos_containers" {
  description = "Microservice containers for cosmos DB"
  type = list(object({
    name               = string
    partition_key_path = string
    max_throughput     = optional(number)
  }))
  default = []
}

variable "queues" {
  description = "Queues for microservice consumption and publishers"
  type = list(object({
    name       = string
    publishers = list(string)
  }))
  default = []
}

variable "cosmosdb_account_name" {
  description = "Cosmos DB account name"
  type        = string
  default     = ""
}

variable "cosmosdb_endpoint" {
  description = "Cosmos DB endpoint"
  type        = string
  default     = ""
}

variable "cosmosdb_primary_key" {
  description = "Cosmos DB Primary Key"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cosmosdb_sql_database_name" {
  description = "Cosmos SQL database name"
  type        = string
  default     = ""
}

variable "cosmos_autoscale_max_throughput" {
  description = "Max throughput of Cosmos database"
  type        = number
}

variable "azurerm_client_config" {
  description = "Azurerm provider client configuration to use"
  type = object({
    tenant_id = string
    object_id = string
  })
}

variable "application_insights" {
  description = "Application Insights to use"
  type = object({
    instrumentation_key = string
    connection_string   = string
  })
}

variable "storage_accounts" {
  description = "Storage accounts to use"
  type = map(object({
    id                    = string
    name                  = string
    primary_blob_endpoint = string
    primary_access_key    = string
  }))
  sensitive = true
  default   = {}
}

variable "servicebus_namespaces" {
  description = "ServiceBus Namespaces to use"
  type = map(object({
    id       = string
    name     = string
    location = string
  }))
  default = {}
}

variable "appservice_plans" {
  description = "Appservice plans to use"
  type = map(object({
    id       = string
    location = string
  }))
  default = {}
}

variable "consumption_appservice_plans" {
  description = "Consumption based appservice plans to use"
  type = map(object({
    id       = string
    location = string
  }))
  default = {}
}

variable "key_vault_user_ids" {
  description = "User ids that will be granted read access to KeyVault"
  type        = list(string)
  default     = []
}

variable "key_vault_permissions" {
  description = "Permissions applied to Key Vault for the provisioning account"
  type = object({
    certificate_permissions = list(string)
    key_permissions         = list(string)
    secret_permissions      = list(string)
    storage_permissions     = list(string)
  })
}

variable "key_vault_network_acls" {
  description = "Defines the network acls for key vault"
  type = object({
    default_action             = string
    bypass                     = string
    ip_rules                   = optional(list(string))
    virtual_network_subnet_ids = optional(list(string))
  })
  default = null
}

variable "static_site" { 
  description = "Defines the static site settings"
  type = object({
      index_document    = string
      error_document    = optional(string)
      domain            = optional(string)
    })
  default = null
}