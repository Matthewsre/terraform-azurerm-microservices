variable "service_name" {
  description = "Name of microservice"
  type        = string
}

variable "environment" {
  description = "Terrform environment we're acting in"
  type        = string
}

variable "regions" {
  description = "Azure regions the service is located in"
  type        = list(string)
}

variable "resource_group_tags" {
  description = "Tags that will be applied to the resource group."
  type        = map(string)
  default     = {}
}

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
