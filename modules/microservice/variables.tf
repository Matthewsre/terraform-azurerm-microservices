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

variable "appservice" {
  type        = string
  description = "Specify appservice type if used ('plan' or 'consumption')"
  default     = ""
  validation {
    condition     = var.appservice == null ? true : contains(["", "plan", "consumption"], lower(var.appservice))
    error_message = "Value must be '', 'plan', or 'consumption'."
  }
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
