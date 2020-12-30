variable "use_msi_to_authenticate" {
  type        = bool
  description = "Use a managed service identity to authenticate"
  default     = false
}

variable "environment" {
  type        = string
  description = "Terrform environment we're acting in"
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "ppe", "prod"], lower(var.environment))
    error_message = "Environment must be 'dev', 'test', 'ppe', or 'prod'."
  }
}

variable "dev_differentiator" {
  type        = string
  description = "Value can be used to allow multiple dev envrionments. Logged in azure AD user mail_nickname will be used as default."
  default     = "matt"
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
  default     = "terra1"
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
  default     = ["staging"]
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
    cosmos_containers = optional(list(object({
      name               = string
      partition_key_path = string
      # opened bug for list https://github.com/hashicorp/terraform/issues/27374
      max_throughput = number
    })))
  }))
  default = [

    {
      name       = "cosm1"
      appservice = "plan"
      function   = "plan"
      sql        = "elastic"
      cosmos_containers = [
        {
          name               = "container1"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        },
        {
          name               = "container2"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        }
      ]
    },
    {
      name       = "confun"
      appservice = "plan"
      function   = "consumption"
      sql        = "elastic"
    },
    {
      name       = "basic"
      appservice = "plan"
      function   = "plan"
      sql        = "elastic"
    },
    {
      name       = "cosm2"
      appservice = "plan"
      cosmos_containers = [
        {
          name               = "container3"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        }
      ]
    },
    {
      name     = "funp"
      function = "plan"
    },
    {
      name     = "func"
      function = "consumption"
    },
    {
      name       = "apponly"
      appservice = "plan"
    }
  ]
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
  default     = ["westus2", "eastus"]
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
