variable "use_msi_to_authenticate" {
  type        = bool
  description = "Use a managed service identity to authenticate"
  default     = false
}

variable "environment" {
  type        = string
  description = "Terrform environment we're acting in"
  validation {
    condition     = contains(["dev", "test", "ppe", "prod"], lower(var.environment))
    error_message = "Environment must be 'dev', 'test', 'ppe', or 'prod'."
  }
}

variable "environment_differentiator" {
  type        = string
  description = "Value can be used to allow multiple envrionments. Logged in azure AD user mail_nickname will be used as default for dev environment unless specified."
  default     = ""
}

variable "enable_backups" {
  type        = bool
  description = "Enable backups for the environment"
  default     = false
}

variable "retention_in_days" {
  type        = number
  description = "Global retention policy set. (SQL Server, Application Insights, KeyVault Soft Delete, SQL Database)"
  default     = 90
}

variable "service_name" {
  type        = string
  description = "Name of microservice"
}

variable "callback_path" {
  type        = string
  description = "Callback path for authorization"
  default     = "/signin-oidc"
}

variable "cosmos_database_name" {
  type        = string
  description = "Name of shared DB created in Cosmos. Will default to service name if not provided."
  default     = ""
}

variable "cosmos_autoscale_max_throughput" {
  type        = number
  description = "Max throughput of Cosmos database"
  default     = 4000
}

variable "appservice_deployment_slots" {
  description = "Additional deployment slots for app services. Standard and above plans allow for deployment slot."
  type        = list(string)
  default     = []
}

variable "appservice_plan_tier" {
  type        = string
  description = "Tier of shared Appservice Plan in each region."
  default     = "Standard" #"Basic"
}

variable "appservice_plan_size" {
  type        = string
  description = "Size of shared Appservice Plan in each region."
  default     = "S1" #"B1"
}

variable "microservices" {
  type = list(object({
    name       = string
    appservice = optional(string)
    function   = optional(string)
    sql        = optional(string)
    roles      = optional(list(string))
    cosmos_containers = optional(list(object({
      name               = string
      partition_key_path = string
      # opened bug for list https://github.com/hashicorp/terraform/issues/27374
      max_throughput = number
    })))
  }))
}

variable "primary_region" {
  type        = string
  description = "Primary region used for shared resources. If not provided will use first value from 'regions'"
  default     = ""
}

variable "secondary_region" {
  type        = string
  description = "Secondary region used for shared resources. If not provided will use second value from 'regions'"
  default     = ""
}

variable "regions" {
  type        = list(string)
  description = "Azure regions the service is located in"
  validation {
    condition     = length(var.regions) > 0
    error_message = "Must provide at least 1 region to deploy."
  }
}

variable "resource_group_tags" {
  type    = map(string)
  default = {}
}

variable "storage_account_tier" {
  description = "Tier to use for storage account"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Defines the type of replication to use for this storage"
  type        = string
  default     = "RAGRS"
}

variable "key_vault_permissions" {
  description = "Permissions applied to Key Vault for the provisioning account"
  type = object({
    certificate_permissions = list(string)
    key_permissions         = list(string)
    secret_permissions      = list(string)
    storage_permissions     = list(string)
  })
  default = {
    certificate_permissions = [
      "backup",
      "create",
      "delete",
      "deleteissuers",
      "get",
      "getissuers",
      "import",
      "list",
      "listissuers",
      "managecontacts",
      "manageissuers",
      "purge",
      "recover",
      "restore",
      "setissuers",
      "update"
    ]

    key_permissions = [
      "backup",
      "create",
      "decrypt",
      "delete",
      "encrypt",
      "get",
      "import",
      "list",
      "purge",
      "recover",
      "restore",
      "sign",
      "unwrapKey",
      "update",
      "verify",
      "wrapKey"
    ]

    secret_permissions = [
      "backup",
      "delete",
      "get",
      "list",
      "purge",
      "recover",
      "restore",
      "set"
    ]

    storage_permissions = [
      "backup",
      "delete",
      "get",
      "list",
      "purge",
      "recover",
      "restore",
      "set"
    ]
  }
}
