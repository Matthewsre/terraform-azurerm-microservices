variable "use_msi_to_authenticate" {
  description = "Use a managed service identity to authenticate"
  type        = bool
  default     = false
}

# 3 MSI configuration methods:
   # System Assigned Managed Identity: supply Object ID
   # User Assigned Managed Identity  : set use_user_assigned_msi, supply name/resource group; Sources objectID at runtime
   # User Assigned Managed Identity  : set use_user_assigned_msi, supply objectId directly
variable "msi" {
  description = "MSI configuration information."
  type        = object({
    use_user_assigned_msi = bool

    name                  = optional(string) 
    resource_group_name   = optional(string)

    object_id             = optional(string)
  })

  default = {
      use_user_assigned_msi = false
  }

  validation {
    condition     = var.msi != null && try(var.msi.use_user_assigned_msi, false) ? ((try(var.msi.name, null) != null && try(var.msi.resource_group_name, null) != null) || try(var.msi.object_id, null) != null) : true
    error_message = "When using a user assigned managed identity either the identity name and resource group name, or the object ID need to be supplied."
  }

  validation {
    condition     = var.msi != null && !try(var.msi.use_user_assigned_msi, false) ? try(var.msi.object_id, null) != null : true
    error_message = "When using a system assigned managed identity the object ID needs to be supplied."
  }
}

variable "azure_environment" {
  description = "Type of Azure Environment being deployed to"
  type        = string
  default     = "public"
  validation {
    condition     = contains(["public", "china", "german", "stack", "usgovernment"], lower(var.azure_environment))
    error_message = "Environment must be a valid Azure Environment."
    # See https://www.terraform.io/docs/language/settings/backends/azurerm.html#environment for more info
  }
}

variable "environment" {
  description = "Terrform environment we're acting in"
  type        = string
  validation {
    condition     = contains(["dev", "tst", "ppe", "prd"], lower(var.environment))
    error_message = "Environment must be 'dev', 'tst', 'ppe', or 'prd'."
  }
}

variable "exclude_hosts" {
  description = "Enable this to exclude creating app services and functions. This is useful for a dev environment where hosting will be done locally."
  type        = bool
  default     = false
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

variable "ip_address" {
  description = "IP Address that will be used for dev environments to add to firewall rules"
  type        = string
  default     = ""
}

variable "environment_differentiator" {
  description = "Value can be used to allow multiple envrionments. Logged in azure AD user mail_nickname will be used as default for dev environment unless specified."
  type        = string
  default     = ""
}

variable "enable_backups" {
  description = "Enable backups for the environment"
  type        = bool
  default     = false
}

variable "retention_in_days" {
  description = "Global retention policy set. (SQL Server, Application Insights, KeyVault Soft Delete, SQL Database)"
  type        = number
  default     = 90
}

variable "service_name" {
  description = "Name of microservice"
  type        = string
}

variable "callback_path" {
  description = "Callback path for authorization"
  type        = string
  default     = "/signin-oidc"
}
variable "signed_out_callback_path" {
  description = "Signed out callback path for authorization"
  type        = string
  default     = "/signout-callback-oidc"
}


# opened bug for lists with optional values https://github.com/hashicorp/terraform/issues/27374
# this impacts cosmos_containers.max_throughput
variable "microservices" {
  description = "This will describe your microservices to determine which resources are needed"
  type = list(object({
    name          = string
    appservice    = optional(string)
    function      = optional(string)
    require_auth  = optional(bool)
    sql           = optional(string)
    roles         = optional(list(string))
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
    static_site = optional(object({
      index_document                = string
      error_document                = string
      domain                        = string
    }))
  }))
}

variable "primary_region" {
  description = "Primary region used for shared resources. If not provided will use first value from 'regions'"
  type        = string
  default     = ""
}

variable "secondary_region" {
  description = "Secondary region used for shared resources. If not provided will use second value from 'regions'"
  type        = string
  default     = ""
}

variable "regions" {
  description = "Azure regions the service is located in"
  type        = list(string)
  validation {
    condition     = length(var.regions) > 0
    error_message = "Must provide at least 1 region to deploy."
  }
}

variable "azuread_instance" {
  description = "Instance of Azure AD"
  type        = string
  default     = "https://login.microsoftonline.com/"
}

### Resource Group Variables
variable "resource_group_name" {
  description = "Optional existing resource group to deploy resources into."
  type        = string
  default     = ""
}

variable "resource_group_name_override" {
  description = "Optional name override to use in creating the new resource group. This value is ignored when a resource_group_name for an existing resource group is provided."
  type        = string
  default     = ""
}

variable "resource_group_tags" {
  description = "Tags that will be applied to the resource group."
  type        = map(string)
  default     = {}
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
  description = "Max throughput of Cosmos database"
  type        = number
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

variable "sql_azuread_administrator" {
  description = "SQL Server AAD admin object id "
  type        = string
  default     = ""
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

variable "sql_elasticpool_max_size_gb" {
  description = "SQL Server elasticpool max size gb"
  type        = number
  default     = 4.8828125
}

variable "sql_elasticpool_sku" {
  description = "SQL Server elasticpool sku"
  type = object({
    name     = string
    tier     = string
    capacity = number
    family   = optional(string)
  })
  default = {
    name     = "BasicPool"
    tier     = "Basic"
    capacity = 50
  }
}

variable "sql_elasticpool_per_database_settings" {
  description = "SQL Server elasticpool database settings"
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = {
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
  description = "Tier of shared Appservice Plan in each region."
  type        = string
  default     = "Standard" #"Basic"
}

variable "appservice_plan_size" {
  description = "Size of shared Appservice Plan in each region."
  type        = string
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

### Static Site Variables
variable "static_site_kind" {
  description = "Kind of storage account to use for static site"
  type        = string
  default     = "StorageV2"
}
variable "static_site_tier" {
  description = "Tier to use for static site"
  type        = string
  default     = "Standard"
}

variable "static_site_replication_type" {
  description = "Defines the type of replication to use for the static site"
  type        = string
  default     = "RAGRS"
}

variable "static_site_tls_version" {
  description = "Defines the type of replication to use for the static site"
  type        = string
  default     = "TLS1_2"
}


### Key Vault Variables

variable "key_vault_include_ip_address" {
  description = "Defines if the current ip should be included in the default network acls for key vaults"
  type        = bool
  default     = null
}

variable "key_vault_developer_user_principal_names" {
  description = "Provides user account UPNs that will be able to retrieve KeyVault secrets. This will only be used for 'dev' environments"
  type        = list(string)
  default     = []
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
