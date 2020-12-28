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

variable "enable_backups" {
  type        = bool
  description = "Enable backups for the environment"
  default     = false
}

variable "service_name" {
  type        = string
  description = "Name of microservice"
  default     = "myservice"
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

variable "appservice_plan_tier" {
  type        = string
  description = "Tier of shared Appservice Plan in each region."
  default     = "" #"Basic"
}

variable "appservice_plan_size" {
  type        = string
  description = "Size of shared Appservice Plan in each region."
  default     = "" #"B1"
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
      name       = "service1"
      appservice = "plan"
      function   = "plan"
      sql        = "elastic"
      cosmos_containers = [
        {
          name               = "service1countainer1"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        },
        {
          name               = "service1countainer2"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        },
        {
          name               = "service1countainer3"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        },
        {
          name               = "service1countainer4"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        },
        {
          name               = "service1countainer5"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        }
      ]
    },
    {
      name       = "service2"
      appservice = "plan"
      function   = "consumption"
      sql        = "elastic"
    },
    {
      name       = "service3"
      appservice = "plan"
      sql        = "elastic"
    },
    {
      name       = "service4"
      appservice = "plan"
      function   = "consumption"
      sql        = "elastic"
      cosmos_containers = [
        {
          name               = "service4countainer1"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        }
      ]
    },
    {
      name       = "service5"
      appservice = "consumption"
      function   = "plan"
      sql        = "elastic"
    }
    # ,
    # {
    #   name    = "service6"
    #   hosting = ["virtualmachine"]
    #   storage = ["cosmos", "azuresql"]
    # }
  ]
}

variable "primary_region" {
  type        = string
  description = "Primary region used for shared resources. If not provided will use first value from 'regions'"
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
