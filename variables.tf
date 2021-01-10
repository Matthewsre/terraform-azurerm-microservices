variable "use_msi_to_authenticate" {
  type        = bool
  description = "Use a managed service identity to authenticate"
  default     = false
}

variable "environment" {
  type        = string
  description = "Terrform environment we're acting in"
  validation {
    condition     = contains(["dev", "tst", "ppe", "prd"], lower(var.environment))
    error_message = "Environment must be 'dev', 'tst', 'ppe', or 'prd'."
  }
}

variable "ip_address" {
  type        = string
  description = "IP Address that will be used for dev environments to add to firewall rules"
  default     = ""
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

# opened bug for lists with optional values https://github.com/hashicorp/terraform/issues/27374
# this impacts cosmos_containers.max_throughput
variable "microservices" {
  type = list(object({
    name       = string
    appservice = optional(string)
    function   = optional(string)
    sql        = optional(string)
    roles      = optional(list(string))
    http = optional(object({
      target    = string
      consumers = list(string)
    }))
    queues = optional(list(object({
      name       = string
      publishers = list(string)
    })))
    cosmos_containers = optional(list(object({
      name               = string
      partition_key_path = string
      max_throughput     = number
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

### Resource Group Variables

variable "resource_group_tags" {
  description = "Tags that will be applied to the resource group."
  type    = map(string)
  default = {}
}

### Application Insights Variables

variable "application_insights_application_type" {
  description = "Sku of shared ServiceBus namespace."
  type        = string
  default     = "web"
}

### Cosmos Variables

variable "cosmos_database_name" {
  description = "Name of shared DB created in Cosmos. Will default to service name if not provided."
  type        = string
  default     = ""
}

variable "cosmos_enable_free_tier" {
  description = "Enable Free Tier pricing option for the Cosmos DB account."
  type        = bool
  default     = false
}

variable "cosmos_enable_automatic_failover" {
  description = "Enable automatic failover option for the Cosmos DB account."
  type        = bool
  default     = true
}

variable "cosmos_consistency_level" {
  description = "Enable automatic failover option for the Cosmos DB account."
  type        = string
  default     = "Strong"
}

variable "cosmos_autoscale_max_throughput" {
  type        = number
  description = "Max throughput of Cosmos database"
  default     = 4000
}

### Service Bus Variables

variable "servicebus_sku" {
  description = "Sku of shared ServiceBus namespace."
  type        = string
  default     = "Basic"
}

### SQL Server Variables

variable "sql_version" {
  description = "SQL Server version"
  type        = string
  default     = "12.0"
}

variable "sql_minimum_tls_version" {
  description = "SQL Server minimum TLS version"
  type        = string
  default     = "1.2"
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

variable "sql_elasticpool_sku" {
  description = "SQL Server elasticpool sku"
  type        = object({
    name     = string
    tier     = string
    capacity = number
    family   = optional(string)
  })
  default     = {
    name     = "BasicPool"
    tier     = "Basic"
    capacity = 50
  }
}

variable "sql_elasticpool_per_database_settings" {
  description = "SQL Server elasticpool database settings"
  type        = object({
    min_capacity = number
    max_capacity = number
  })
  default     = {
    min_capacity = 5
    max_capacity = 5
  }
}

### App Service Variables

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

### Storage Account Variables

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

### Key Vault Variables

variable "key_vault_include_ip_address" {
  description = "Defines if the current ip should be included in the default network acls for key vaults"
  type        = bool
  default     = null
}

variable "key_vault_network_acls" {
  description = "Defines the default network acls for key vaults"
  type = object({
    default_action             = string
    bypass                     = string
    ip_rules                   = optional(list(string))
    virtual_network_subnet_ids = optional(list(string))
  })
  default = null
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
