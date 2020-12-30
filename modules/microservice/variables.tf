variable "use_msi_to_authenticate" {
  type        = bool
  description = "Use a managed service identity to authenticate"
  default     = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "name" {
  type        = string
  description = "Name of the microservice"
}

variable "primary_region" {
  type        = string
  description = "Primary region used for shared resources. If not provided will use first value from 'regions'"
}

variable "secondary_region" {
  type        = string
  description = "Secondary region used for shared resources. If not provided will use second value from 'regions'"
}

variable "retention_in_days" {
  type        = number
  description = "Days set for retention policies"
}

variable "environment_name" {
  type        = string
  description = "Name of the environment"
}

variable "appservice" {
  type        = string
  description = "Specify appservice type if used ('plan' or 'consumption')"
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
  type        = string
  description = "Specify function type if used ('plan' or 'consumption')"
  default     = ""
  validation {
    condition     = var.function == null ? true : contains(["", "plan", "consumption"], lower(var.function))
    error_message = "Value must be '', 'plan', or 'consumption'."
  }
}

variable "sql" {
  type        = string
  description = "Specify SQL type if used ('server' or 'elastic')"
  default     = ""
  validation {
    condition     = var.sql == null ? true : contains(["", "server", "elastic"], lower(var.sql))
    error_message = "Value must be '', 'server', or 'elastic'."
  }
}

variable "sql_server_id" {
  type        = string
  description = "Server Id for SQL"
  default     = ""
}

variable "sql_elastic_pool_id" {
  type        = string
  description = "Elastic pool Id for SQL"
  default     = ""
}

variable "cosmos_containers" {
  type = list(object({
    name               = string
    partition_key_path = string
    max_throughput     = optional(number)
  }))
  description = "Microservice containers for cosmos DB"
  default     = []
}

variable "cosmosdb_account_name" {
  type        = string
  description = "Cosmos DB account name"
  default     = ""
}

variable "cosmosdb_sql_database_name" {
  type        = string
  description = "Cosmos SQL database name"
  default     = ""
}

variable "cosmos_autoscale_max_throughput" {
  type        = number
  description = "Max throughput of Cosmos database"
}

variable "application_insights" {
  type = object({
    instrumentation_key = string
    connection_string   = string
  })
  description = "Application Insights to use"
}

variable "storage_accounts" {
  type = map(object({
    id                    = string
    name                  = string
    primary_blob_endpoint = string
    primary_access_key    = string
  }))
  description = "Storage accounts to use"
  sensitive   = true
  default     = {}
}

variable "appservice_plans" {
  type = map(object({
    id       = string
    location = string
  }))
  description = "Appservice plans to use"
  default     = {}
}

variable "consumption_appservice_plans" {
  type = map(object({
    id       = string
    location = string
  }))
  description = "Consumption based appservice plans to use"
  default     = {}
}
